--!strict
-- 드론. 접속 여부와 무관하게 시간 경과로 블럭스를 낸다. 온라인과 오프라인이 같은
-- 계산이라 별도 OfflineService를 두지 않는다 — 지급 경로는 collect() 하나다.
-- 규칙은 DESIGN.md "5. 드론"이 원본이다. ⚠️ 근거를 여기로 복사하지 말 것.
-- 오프셋 확정 근거는 DroneConfig.lua 상단.
--
-- 두 호출 지점이 같은 collect()를 부른다 (아래 init() 참고):
--   1. 프로필 로드 직후 1회 (ProfileManager.onLoaded)
--   2. DroneConfig.INTERVAL_SEC 주기 루프 (RunService.Heartbeat 누산)
--
-- ===== collect()의 분기 (⚠️ 이 순서가 계약이다) ==========================================
--
--   elapsed = now - lastCollectAt
--   elapsed <= 0   → 지급 없음. 시계 되감김 방어. lastCollectAt = now로 보정, 저장, 종료
--   elapsed > CAP  → effectiveElapsed = CAP (사이클 계산에만 쓴다).
--                    이 경우 마지막에 lastCollectAt = now — 초과분은 버린다.
--                    남기면 다음 수령에서 그 초과분이 또 지급된다.
--   cycles = floor(effectiveElapsed / INTERVAL_SEC)
--   cycles == 0    → 지급 없음. lastCollectAt도 건드리지 않는다 — 다음 호출에서
--                    이번에 못 채운 나머지 시간과 합쳐 다시 잰다 (나머지 보존).
--   droneStage = maxStage - STAGE_OFFSET
--   droneStage < 1 → 지급 없음. lastCollectAt은 그래도 전진시킨다 — 드론 스테이지가
--                    없는 초반 구간의 시간을 "은행"처럼 쌓아두면, 나중에 스테이지가
--                    열리는 순간 그 긴 시간이 한꺼번에 터진다. 그 구간은 그냥 흘려보낸다.
--   지급액 = reward(droneStage) * cycles * count
--   CurrencyService.add로 지급 → lastCollectAt 갱신(상한에 안 걸렸으면 += cycles*INTERVAL_SEC,
--   걸렸으면 = now) → 저장
--
-- ===== 환생과 lastCollectAt (⚠️ 반드시 읽을 것) ==========================================
--
-- 환생 시 lastCollectAt을 건드리지 않는다. 환생해도 시간은 계속 흐르고, 드론 스테이지가
-- 없어지는 구간(환생 직후 maxStage가 초기화되어 STAGE_OFFSET+1 미만이 되는 동안)은
-- 위 "droneStage < 1" 분기를 타며 사이클만 소진되고 지나간다.
--
-- 멈추게 하면 "환생 직후 로그아웃해서 시간을 은행처럼 쌓아두는" 경로가 열린다 — 높은
-- 드론 스테이지로 오래 받다가 환생으로 낮아진 순간 시계를 멈추면, 그 뒤 쌓인 시간을
-- 나중에 (예: 다음 환생으로 다시 스테이지를 회복한 뒤) 옛 스테이지 기준으로 정산받으려는
-- 유인이 생긴다. RebirthService의 Deps에는 이 파일을 부르는 창구가 없다 — 그래서
-- 환생 흐름이 lastCollectAt을 건드릴 방법 자체가 없다.
--
-- ===== 왜 yield가 하나도 없어야 하는가 ==================================================
--
-- collect() 안의 모든 단계(프로필 조회, CurrencyService.add, lastCollectAt 대입,
-- profile:Save())는 yield하지 않는다. profile:Save()는 실제 DataStore 저장을
-- task.spawn으로 새 스레드에 넘기고 자신은 즉시 반환한다(ServerPackages의
-- ProfileStore.luau, Profile:Save 참고) — 그래서 이 파일 안에서 부르는 형태로는
-- yield가 없다. RebirthService.lua / WarpService.lua 상단과 같은 계약이다.
--
-- ⚠️ collect()와 REAL 안에 task.wait · task.delay · WaitForChild · 그 외 DataStore
--    호출을 절대 넣지 말 것.
--
-- 그런데도 in-flight 플래그(아래 guardedCollect)를 두는 이유: 위 무yield 계약은
-- "지금 코드가 지키고 있다"는 사실이지 "앞으로도 지켜진다"는 보장이 아니다. 호출
-- 지점이 둘(로드 훅 / 주기 루프)이라 언젠가 한쪽이 yield하는 코드로 바뀌면 조용히
-- 겹쳐 돌기 시작한다. 플래그는 지금 겹쳐서가 아니라 나중에 겹칠 수 있어서 두는
-- 방어선이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local DroneConfig = require(ReplicatedStorage.Shared.Config.DroneConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.CurrencyService)

type BigNumber = BigNum.BigNumber

local DroneService = {}

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

-- 호출 경로 식별용. RebirthService.normalizeSource와 같은 규칙이다.
local function normalizeSource(source: string?): string
	if type(source) == "string" and #source > 0 then
		return source
	end
	return "unknown"
end

-- 지급 -> lastCollectAt 갱신 -> 저장 순서에서 부분 실패가 났을 때 남기는 로그.
-- RebirthService.reportPartialFailure와 같은 형태다 — **사후에 이 줄이 유일한
-- 복구 근거다.** 어느 단계에서 멈췄는지에 따라 무엇이 위험한지가 갈리므로 단계
-- 이름을 반드시 싣는다.
--
-- ⚠️ 이 함수는 "지급이 이미 끝난 뒤" 실패에만 쓴다. 지급 자체가 실패한 경우
-- (CurrencyService.add가 false)는 아무 것도 안 바뀌었으므로 여기를 타지 않는다
-- (아래 runCollect의 "6. 지급" 참고) — 그건 정상적인 재시도 경로이지 부분 실패가 아니다.
local function reportPartialFailure(player: Player, step: string, granted: BigNumber, detail: string)
	warn(string.format(
		"[DroneService][ERROR] 부분 실패: UserId=%d step=%s granted=%s - %s. 프로필이 일관되지 않은 상태이며 이 줄이 유일한 복구 근거다.",
		player.UserId,
		step,
		BigNum.tostring(granted),
		detail
	))
end

-- collect() 시점의 드론 관련 프로필 스냅샷.
export type DroneState = {
	maxStage: number,
	count: number,
	lastCollectAt: number,
}

-- 한 번의 collect 결과.
--   granted: 이번 호출로 실제 지급된 액수(0이면 지급 없음)
--   cycles:  이번 호출로 소진된 사이클 수(지급 여부와 무관 — droneStage < 1이어도 는다)
export type CollectResult = {
	granted: BigNumber,
	cycles: number,
}

-- 이 흐름이 바깥 세계에 하는 일 전부. RebirthService.Deps / WarpService.Deps와 같은
-- 이음매다 — 기록용 테이블을 넣으면 Player·실제 프로필 없이 분기와 순서를 잴 수 있다.
export type Deps = {
	getState: (Player) -> DroneState?,
	grantBlox: (Player, BigNumber, string) -> boolean,
	setLastCollectAt: (Player, number) -> boolean,
	save: (Player) -> boolean,
}

local function zero(): BigNumber
	return BigNum.new(0, 0)
end

-- collect 한 번. 순서는 파일 상단 "collect()의 분기"가 계약이다.
--
-- ⚠️ 이 함수 안에서 yield하지 말 것 (파일 상단 참고). deps로 들어오는 함수들도 마찬가지다.
local function runCollect(deps: Deps, player: Player, now: number, source: string?): CollectResult
	local sourceTag = normalizeSource(source)
	local reason = "drone_collect_" .. sourceTag

	local noResult: CollectResult = { granted = zero(), cycles = 0 }

	-- 1. 프로필 확인.
	local state = deps.getState(player)
	if state == nil then
		return noResult
	end

	local elapsed = now - state.lastCollectAt

	-- 2. 시각 되감김 방어. 지급 없이 시계만 지금으로 보정한다.
	if elapsed <= 0 then
		if deps.setLastCollectAt(player, now) then
			deps.save(player)
		end
		return noResult
	end

	-- 3. 오프라인 상한. 초과분은 사이클 계산에서만 잘리고, lastCollectAt은 마지막에
	--    (상한에 걸렸으므로) now로 민다 — 초과분을 남기면 다음 수령에서 또 지급된다.
	local capped = elapsed > DroneConfig.OFFLINE_CAP_SEC
	local effectiveElapsed = if capped then DroneConfig.OFFLINE_CAP_SEC else elapsed

	-- 4. 사이클. 0이면 나머지 시간을 다음 호출로 넘긴다 — lastCollectAt을 건드리지 않는다.
	local cycles = math.floor(effectiveElapsed / DroneConfig.INTERVAL_SEC)
	if cycles == 0 then
		return noResult
	end

	-- 상한에 걸리지 않았으면 소진한 사이클만큼만 전진(나머지 보존). 걸렸으면 now로.
	local newLastCollectAt = if capped then now else state.lastCollectAt + cycles * DroneConfig.INTERVAL_SEC

	-- 5. 드론 스테이지. 없으면 지급 없이 시간만 흘려보낸다(파일 상단 "환생과 lastCollectAt" 참고).
	local droneStage = state.maxStage - DroneConfig.STAGE_OFFSET
	if droneStage < 1 then
		if not deps.setLastCollectAt(player, newLastCollectAt) then
			-- 지급할 것이 없었으므로 재화 위험은 없다. 다음 호출이 같은 구간을 다시
			-- 재보는 것으로 자연히 복구되므로 ERROR가 아니라 warn 한 줄로 충분하다.
			warn(string.format(
				"[DroneService] %s(%d) lastCollectAt 갱신 실패(droneStage<1) - 다음 호출에서 재시도됨",
				player.Name,
				player.UserId
			))
			return { granted = zero(), cycles = cycles }
		end
		deps.save(player)
		return { granted = zero(), cycles = cycles }
	end

	-- 6. 지급액. reward(droneStage) * cycles * count. 전부 BigNum 경로다.
	local reward = StageConfig.getBloxReward(droneStage)
	local amount = BigNum.mul(BigNum.mul(reward, BigNum.fromNumber(cycles)), BigNum.fromNumber(state.count))

	-- 7. 지급. 실패하면 CurrencyService.add가 이미 사유를 로깅했고, 여기서는 아무 것도
	--    바뀌지 않았으므로(부분 실패 아님) lastCollectAt을 그대로 두어 다음 호출이 이번
	--    구간을 통째로 재시도하게 한다.
	if not deps.grantBlox(player, amount, reason) then
		return noResult
	end

	-- 8. lastCollectAt 갱신. ⚠️ 여기서부터는 지급이 이미 끝났다 — 실패하면 이번 구간이
	--    다음 호출에서 다시 지급된다(중복 지급 위험). partial failure로 남긴다.
	if not deps.setLastCollectAt(player, newLastCollectAt) then
		reportPartialFailure(player, "setLastCollectAt", amount, "지급은 됐는데 lastCollectAt이 전진하지 않았다 - 다음 수령에서 이번 구간이 다시 지급된다")
		return { granted = amount, cycles = cycles }
	end

	-- 9. 저장. 실패해도 지급과 시계는 이미 메모리상 정상이다 — ProfileStore의 주기
	--    autosave/EndSession이 결국 저장한다. 그래도 창을 최소화하려고 즉시 시도한다
	--    (드론 수입은 크게 쌓였다가 한 번에 지급되는 성격이라, 저장 전에 서버가
	--    죽으면 이 구간이 통째로 다시 지급될 수 있다 — 위 setLastCollectAt 실패와
	--    같은 위험이다).
	if not deps.save(player) then
		reportPartialFailure(player, "save", amount, "지급과 lastCollectAt 갱신은 끝났으나 저장 시도 시점에 프로필이 이미 비활성 상태였다 - ProfileStore의 EndSession 저장에 맡긴다")
	end

	return { granted = amount, cycles = cycles }
end

-- ===== in-flight 방어 (Player 상태 보관) ===============================================

-- guardedCollect: runCollect를 in-flight 플래그로 감싼다. inFlight 테이블을 인자로
-- 받아서(모듈 전역을 직접 안 쓴다) 테스트가 자기만의 테이블로 겹침을 재현할 수 있다.
local function guardedCollect(deps: Deps, inFlight: { [Player]: boolean }, player: Player, now: number, source: string?): CollectResult
	if inFlight[player] then
		return { granted = zero(), cycles = 0 }
	end
	inFlight[player] = true

	-- ⚠️ pcall로 감싼다. runCollect가 에러를 던지면 finally 없는 Luau에서는 이 줄까지
	-- 못 와서 inFlight가 true로 눌어붙는다 — 그러면 이 플레이어는 서버가 안 죽는 한
	-- 다시는 드론 수입을 못 받는다. 원래 에러는 다시 던진다(삼키지 않는다).
	local ok, resultOrErr = pcall(runCollect, deps, player, now, source)
	inFlight[player] = nil

	if not ok then
		error(resultOrErr, 0)
	end
	return resultOrErr :: CollectResult
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
DroneService._pure = {
	normalizeSource = normalizeSource,
	runCollect = runCollect,
	guardedCollect = guardedCollect,
}

-- ===== 공개 API =======================================================================

-- 실제 서비스에 연결한 deps. 모듈 로드 시 한 번 만든다.
-- ⚠️ 여기 있는 함수 중 어느 것도 yield하지 않는다. 새 항목을 붙일 때 그것부터 확인할 것.
local REAL: Deps = {
	getState = function(player: Player): DroneState?
		local profile = ProfileManager.get(player)
		if profile == nil then
			return nil
		end
		return {
			maxStage = profile.Data.progress.maxStage,
			count = profile.Data.drones.count,
			lastCollectAt = profile.Data.drones.lastCollectAt,
		}
	end,
	grantBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.add(player, "blox", amount, reason))
	end,
	setLastCollectAt = function(player: Player, value: number)
		local profile = ProfileManager.get(player)
		if profile == nil then
			return false
		end
		profile.Data.drones.lastCollectAt = value
		return true
	end,
	save = function(player: Player)
		local profile = ProfileManager.get(player)
		if profile == nil or not profile:IsActive() then
			return false
		end
		profile:Save()
		return true
	end,
}

local inFlight: { [Player]: boolean } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	inFlight[player] = nil
end)

-- 드론 수입을 정산한다. 두 호출 지점(로드 직후 1회 / 주기 루프)이 이 함수 하나를 쓴다.
--
--   granted: 이번 호출로 실제 지급된 blox(BigNum). 0이면 지급 없음(정상 — 대부분의
--            주기 호출은 사이클을 다 못 채워 0이다).
--   cycles:  소진된 사이클 수. droneStage가 없어 지급이 없었던 경우에도 는다.
--
-- source는 호출 경로 태그다. nil이나 빈 문자열이면 "unknown"으로 접힌다
-- (RebirthService.rebirth / WarpService.warp과 같은 규칙).
function DroneService.collect(player: Player, source: string?): CollectResult
	return guardedCollect(REAL, inFlight, player, os.time(), source)
end

local initialized = false

-- 드론을 연다: 로드 훅 등록 + 주기 루프 시작.
--
-- ⚠️ 순서: ProfileManager.init() 뒤여야 한다 (PadService.init()과 같은 이유 —
-- ProfileManager.onLoaded는 등록 시점 이전에 이미 로드된 플레이어의 통지를 다시
-- 보내주지 않는다). CurrencyService는 상태가 없는 래퍼라 준비를 기다릴 필요가 없다.
--
-- ⚠️ 60초 주기 루프가 여기서 시작된다. init()을 안 부르면 신규 로드 1회 수령만 되고
-- 접속 중 정산이 멈춘다 — 증상은 "로그인할 때만 드론 수입이 들어온다" 하나뿐이라
-- 원인이 눈에 보이지 않는다.
function DroneService.init()
	if initialized then
		warn("[DroneService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	ProfileManager.onLoaded(function(player: Player)
		DroneService.collect(player, "load")
	end)

	-- RunService.Heartbeat 누산. ChallengeService의 만료 검사 루프와 같은 관용구이지만
	-- 그쪽과 달리 폴링 해상도를 INTERVAL_SEC보다 촘촘하게 둘 이유가 없다 — collect()는
	-- 실제 경과 시간(os.time() 차)으로 사이클을 계산하지 틱 횟수를 세지 않으므로,
	-- 루프가 정확히 60.0초마다 못 깨어나고 조금 밀려도(서버 렉 등) 다음 호출에서
	-- 나머지까지 정확히 잡힌다.
	local accumSec = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumSec += dt
		if accumSec < DroneConfig.INTERVAL_SEC then
			return
		end
		accumSec = 0

		for _, player in ipairs(Players:GetPlayers()) do
			DroneService.collect(player, "loop")
		end
	end)

	print(string.format("[DroneService] 드론 준비 완료 (오프셋=%d, 주기=%d초, 오프라인 상한=%d시간)", DroneConfig.STAGE_OFFSET, DroneConfig.INTERVAL_SEC, DroneConfig.OFFLINE_CAP_SEC / 3600))
end

return DroneService

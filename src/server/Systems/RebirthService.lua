--!strict
-- 환생(새 경제 — 지시서 #30 · #37에서 유일한 환생). 다음 비용(1000 × 4^n)을 내고 환생 수 +1 · 힘 배수의 환생 항은 1.25^n.
-- 규칙과 근거는 DESIGN.md 16장 "환생"이 원본이다 — 여기로 복사하지 말 것.
--
-- 이 프로젝트에서 **4개 서비스를 한 흐름 안에서 건드리는 첫 모듈**이다:
--   CurrencyService   blox / rebirths / strength
--   ChallengeService  진행 중 런 소멸(→ 스폰 복귀) + 진행도 되돌리기
--   SpeedService      최대 이동속도 재적용
--   Schema            초기값 출처
-- 그래서 이 파일에는 계산이 거의 없다. 하는 일은 **순서를 지키는 것**이다.
--
-- ===== 왜 yield가 하나도 없어야 하는가 (⚠️ 가장 중요) =================================
--
-- 환생은 "지금 보유한 블럭스"를 읽고 → 판정하고 → 비용을 뺀다.
-- Luau는 단일 스레드라 **yield하지 않는 한** 그 사이에 다른 핸들러가 끼어들 수 없고,
-- 그래서 "읽은 값"과 "실제로 사라진 값"이 같다는 보장이 성립한다.
--
-- 한 줄이라도 yield가 끼면 그 보장이 통째로 깨진다. 이 코드베이스에서 blox를 늘리는
-- 경로는 ChallengeService.cashout 하나뿐인데, 그게 그 틈에 들어오면 환생이 끝난 뒤에
-- 블럭스가 남는다 — 배수는 옛 잔액 기준으로 계산됐으므로 공짜 블럭스가 된다.
--
-- ⚠️ 아래 rebirth() 안에 task.wait · task.delay · profile:Save() · WaitForChild ·
--    DataStore 호출을 **절대 넣지 말 것.** 호출하는 함수들도 전부 yield하지 않는 것을
--    확인해 두었다(CurrencyService 전체 / ChallengeService.abandonRun·reset* /
--    SpeedService.onRebirth). 그 계약이 깨지면 여기가 먼저 조용히 틀린다.
--
-- ===== SpeedRequestService를 거치지 않는다 ============================================
--
-- 속도 재적용은 SpeedService.onRebirth를 **직접** 부른다. SpeedRequestService의 빈도
-- 상한(초당 5회)은 클라 입력 경로 전용이고, 서버 재적용이 그 상한에 걸리면 안 된다 —
-- 두 파일을 나눈 이유가 정확히 이것이다 (SpeedRequestService.lua 상단 참고).
--
-- ===== 재화는 전부 CurrencyService를 통과한다 =========================================
--
-- profile.Data.blox / strength / rebirths를 직접 대입하는 줄이 이 파일에 하나도 없다
-- (CLAUDE.md 절대 규칙 2). progress.* 도 마찬가지로 ChallengeService의 창구를 부른다 —
-- 그쪽이 그 필드의 유일한 소유자다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Schema = require(script.Parent.Parent.Data.Schema)
local CurrencyService = require(script.Parent.CurrencyService)
local ChallengeService = require(script.Parent.ChallengeService)
local SpeedService = require(script.Parent.SpeedService)
local PadService = require(script.Parent.PadService)
local Analytics = require(script.Parent.Analytics)

type BigNumber = BigNum.BigNumber

local RebirthService = {}

-- ===== 거부 사유 코드 =================================================================
--
-- ⚠️ 코드만 둔다. 표시 문구를 여기 넣지 말 것 — 매핑은 Phase 6 UI가 한다.
-- 이 규약은 4-2-e 워프의 블럭스 부족 거부에도 그대로 쓴다 (ROADMAP 4-2-d "[확정됨]").
--
-- ⚠️ 아래 둘과 REASON_PARTIAL_FAILURE는 **성격이 다르다.** 앞의 둘은 아무 일도 일어나지
-- 않은 정상 거부이고, 뒤의 하나는 이미 벌어진 뒤의 사고다. 호출자가 이 둘을 같은
-- "실패"로 뭉뚱그리면 블럭스가 사라진 유저에게 "환생하지 못했습니다"를 띄우게 된다.
RebirthService.REASON_NO_PROFILE = "no_profile"
RebirthService.REASON_NOT_ENOUGH_BLOX = "not_enough_blox"

-- 부작용이 이미 발생한 뒤의 실패. UI는 "실패"가 아니라
-- "문제 발생"으로 매핑할 것 — 유저의 블럭스가 사라졌을 수 있다.
--
-- ⚠️ 이 흐름에서 재화 조작이 실패하는 경우는 **전부** 이쪽이다. 되돌릴 수 없는 3단계
-- (런 소멸)가 모든 재화 조작보다 앞에 있기 때문이다 — "부작용 없이 재화만 실패했다"는
-- 경우가 구조적으로 존재할 수 없어서 그런 사유 코드를 따로 두지 않았다.
-- 3단계보다 앞에 실패할 수 있는 단계를 새로 넣는다면 그때 코드를 하나 더 만들 것.
RebirthService.REASON_PARTIAL_FAILURE = "partial_failure"

local REASON_NO_PROFILE = RebirthService.REASON_NO_PROFILE
local REASON_NOT_ENOUGH_BLOX = RebirthService.REASON_NOT_ENOUGH_BLOX
local REASON_PARTIAL_FAILURE = RebirthService.REASON_PARTIAL_FAILURE

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

-- 호출 경로 식별용. ChallengeService.advance/cashout의 normalizeSource와 같은 규칙이다.
-- 빈 문자열까지 접는 이유도 같다: CurrencyService의 reason은 비어 있으면 안 되는데
-- "rebirth_"로 끝나는 reason은 assert를 통과하면서 로그만 망가뜨린다.
local function normalizeSource(source: string?): string
	if type(source) == "string" and #source > 0 then
		return source
	end
	return "unknown"
end

-- 3단계(런 소멸) 이후의 실패를 기록하고 사유 코드를 돌려준다.
--
-- ⚠️ print가 아니라 warn이다. 이건 정상 거부가 아니라 프로필이 일관되지 않은 상태로
-- 남았다는 신호이고, **사후에 이 줄이 유일한 복구 근거가 된다.** 어느 단계에서
-- 멈췄는지에 따라 무엇이 사라졌는지가 달라지므로 단계 번호를 반드시 싣는다.
local function reportPartialFailure(
	player: Player,
	step: number,
	stepName: string,
	gained: BigNumber,
	sourceTag: string,
	lost: string
): (boolean, string)
	warn(string.format(
		"[RebirthService][ERROR] 부분 실패: UserId=%d step=%d(%s) gained=%s source=%s - %s. 프로필이 일관되지 않은 상태이며 이 줄이 유일한 복구 근거다.",
		player.UserId,
		step,
		stepName,
		BigNum.tostring(gained),
		sourceTag,
		lost
	))
	return false, REASON_PARTIAL_FAILURE
end

-- 환생 결과.
export type RebirthResult = {
	gained: BigNumber,
	total: BigNumber,
	cost: BigNumber, -- 낸 비용(지시서 #31 — 분석 이벤트 rebirth 값)
}

-- 이 흐름이 바깥 세계에 하는 일 전부. 실제 서비스 대신 기록용 테이블을 넣으면
-- **순서와 부작용을 Player 없이 잴 수 있다.**
--
-- 왜 이런 이음매가 필요한가: 환생 검증의 핵심은 "거부됐을 때 아무 일도 일어나지 않았는가"와
-- "strength를 되돌린 *뒤에* 속도를 재적용했는가"인데, 둘 다 계산 결과가 아니라 **호출 여부와
-- 순서**에 대한 질문이다. 가짜 Player 테이블로는 ProfileManager.get이 nil을 주기 때문에
-- 실제 서비스를 태우면 전부 "프로필 없음" 한 갈래로만 끝나서 이 둘을 볼 수 없다.
export type Deps = {
	getBlox: (Player) -> BigNumber?,
	abandonRun: (Player) -> boolean,
	setBlox: (Player, BigNumber, string) -> boolean,
	addRebirths: (Player, BigNumber, string) -> (boolean, BigNumber?),
	setStrength: (Player, BigNumber, string) -> boolean,
	resetMaxStage: (Player) -> boolean,
	resetCurrentWorld: (Player) -> boolean,
	onRebirth: (Player) -> number,
	resetLifeBlox: (Player, string) -> boolean,
	resetPad: (Player) -> boolean,
	getRebirths: (Player) -> BigNumber?,
	subtractBlox: (Player, BigNumber, string) -> boolean,
}

-- 환생 한 번. 순서는 아래 주석의 번호가 곧 계약이다.
--
-- ⚠️ 이 함수 안에서 yield하지 말 것 (파일 상단 참고). deps로 들어오는 함수들도 마찬가지다.
-- 환생(DESIGN 16장 "환생"):
--   조건  블럭스 ≥ 다음 비용(EconomyV2Logic.rebirthCost — 환생 수 n에 따라)
--   블럭스  비용만 뺀다(CurrencyService.subtract — REBIRTH_KEEP_REMAINDER) · 나머지가 0이면 set(0)
--   환생 수 +1 · 나머지 초기화(런 · 힘 · maxStage · 월드 · 속도 · lifeBlox · 패드)
--   곡괭이 · 광석 · 토큰 · 코인은 건드리지 않는다(EconomyV2Logic.REBIRTH_KEEPS — deps에 그 통로가 없다)
local function runRebirth(deps: Deps, player: Player, source: string?): (boolean, any)
	local sourceTag = normalizeSource(source)
	local reason = "rebirth_" .. sourceTag

	-- 1. 프로필 확인. getBlox가 nil이면 로드 전이거나 이미 나간 플레이어다.
	local blox = deps.getBlox(player)
	local rebirths = deps.getRebirths(player)
	if blox == nil or rebirths == nil then
		return false, REASON_NO_PROFILE
	end

	-- 2. 가능 판정. ⚠️ 여기까지는 **부작용이 0이어야 한다**(거부가 런을 없애면 안 된다).
	if not EconomyV2Logic.canRebirth(blox, rebirths) then
		return false, REASON_NOT_ENOUGH_BLOX
	end
	local gained = BigNum.new(1, 0)
	local cost = EconomyV2Logic.rebirthCost(rebirths)

	-- ===== 여기부터 되돌릴 수 없다 =====================================================

	-- 3. 진행 중인 런을 버린다(재화 조작보다 먼저 — 런이 살아 있으면 그 cashout이 방금 뺀 지갑에 다시 들어온다).
	deps.abandonRun(player)

	-- 4. 비용을 낸다. 나머지가 남으면 subtract, 아니면 set(0).
	local remainder = EconomyV2Logic.rebirthRemainder(blox, rebirths)
	local paid: boolean
	if BigNum.gt(remainder, BigNum.new(0, 0)) then
		paid = deps.subtractBlox(player, cost, reason)
	else
		paid = deps.setBlox(player, BigNum.new(0, 0), reason)
	end
	if not paid then
		return reportPartialFailure(player, 4, "payRebirthCost", gained, sourceTag, "런만 사라지고 블럭스는 남아 있다")
	end

	-- 5. 환생 수 가산(4번 뒤 — 실패하면 유저가 손해 보는 쪽이 무한 환생보다 낫다).
	local addOk, total = deps.addRebirths(player, gained, reason)
	if not addOk or total == nil then
		return reportPartialFailure(player, 5, "addRebirths", gained, sourceTag, "비용을 냈는데 환생 수가 오르지 않았다")
	end

	-- 6. 힘을 시작 상태로(Schema.new — 템플릿 참조를 공유하지 않게).
	if not deps.setStrength(player, Schema.new().strength, reason) then
		return reportPartialFailure(player, 6, "setStrength", gained, sourceTag, "비용과 환생 수는 끝났으나 힘이 초기화되지 않았다")
	end

	-- 7~8. 진행도 되돌리기(ChallengeService 소유). unlockedWorlds는 영구 — 되돌리지 않는다.
	deps.resetMaxStage(player)
	deps.resetCurrentWorld(player)

	-- 9. (없앴다) 환생은 런을 세우지 않는다 — 런은 입장 게이트가 세운다. 번호는 계약이라 비워 둔다.

	-- 10. 최대 이동속도 재적용 — ⚠️ 반드시 6번 뒤(초기화된 힘을 다시 읽는다).
	deps.onRebirth(player)

	-- 11. 패드 되돌리기(lifeBlox 0 · 선택 패드 1). 운동기구는 환생 수 기준이라 건드리지 않는다.
	if not deps.resetLifeBlox(player, reason) then
		return reportPartialFailure(player, 11, "resetLifeBlox", gained, sourceTag, "환생은 끝났으나 패드 해금 기준(lifeBlox)이 0이 되지 않았다")
	end
	deps.resetPad(player)

	local result: RebirthResult = { gained = gained, total = total, cost = cost }
	return true, result
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
RebirthService._pure = {
	normalizeSource = normalizeSource,
	runRebirth = runRebirth,
}

-- ===== 공개 API =======================================================================

-- 실제 서비스에 연결한 deps. 모듈 로드 시 한 번 만든다.
-- ⚠️ 여기 있는 함수 중 어느 것도 yield하지 않는다. 새 항목을 붙일 때 그것부터 확인할 것.
local REAL: Deps = {
	getBlox = function(player: Player)
		return CurrencyService.get(player, "blox")
	end,
	abandonRun = function(player: Player)
		return ChallengeService.abandonRun(player)
	end,
	setBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.set(player, "blox", amount, reason))
	end,
	addRebirths = function(player: Player, amount: BigNumber, reason: string)
		return CurrencyService.add(player, "rebirths", amount, reason)
	end,
	setStrength = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.set(player, "strength", amount, reason))
	end,
	resetMaxStage = function(player: Player)
		return ChallengeService.resetMaxStage(player)
	end,
	resetCurrentWorld = function(player: Player)
		return ChallengeService.resetCurrentWorld(player)
	end,
	onRebirth = function(player: Player)
		return SpeedService.onRebirth(player)
	end,
	resetLifeBlox = function(player: Player, reason: string)
		return CurrencyService.resetLifeBlox(player, reason)
	end,
	resetPad = function(player: Player)
		return PadService.resetForRebirth(player)
	end,
	getRebirths = function(player: Player)
		return CurrencyService.get(player, "rebirths")
	end,
	subtractBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.subtract(player, "blox", amount, reason))
	end,
}

-- 환생을 실행한다.
--
--   성공  true,  { gained = BigNum, total = BigNum }
--   거부  false, "사유코드"  (REASON_* 상수 중 하나)
--
-- ⚠️ false를 전부 같은 "실패"로 다루지 말 것. REASON_PARTIAL_FAILURE는 부작용이 이미
-- 발생한 뒤의 사고라 유저에게 "환생하지 못했습니다"를 띄우면 거짓 안내가 된다.
--
-- source는 호출 경로 태그다. nil이나 빈 문자열이면 "unknown"으로 접힌다
-- (ChallengeService.advance/cashout과 같은 규칙).
local rebirthedListeners: { (Player) -> () } = {}

-- 환생이 성공하면 부른다(지시서 #17 — Roblox Plus 프롬프트 기회 S16). 반응하는 쪽이 등록한다(순환 방지). 실패 · 거부에는 부르지 않는다.
function RebirthService.onRebirthed(callback: (Player) -> ())
	table.insert(rebirthedListeners, callback)
end

function RebirthService.rebirth(player: Player, source: string?): (boolean, any)
	local ok, value = runRebirth(REAL, player, source)
	if ok then
		Analytics.rebirth(player, value.total, value.cost) -- 분석 이벤트 rebirth(지시서 #31 — 값 환생 뒤 환생 수 · 필드 비용 자릿수 log10)
		for _, cb in ipairs(rebirthedListeners) do
			task.spawn(cb, player)
		end
	end
	return ok, value
end

local initialized = false

-- 환생을 연다.
--
-- ⚠️ 순서: CurrencyService · ChallengeService · SpeedService가 전부 준비된 뒤에 부른다
-- (Bootstrap의 호출 지점 주석 참고). 그 셋을 검사하지는 않는다 — 서로 init 상태를
-- 물어보는 API가 없고, 만들면 서비스끼리 준비 여부를 캐묻는 결합이 새로 생긴다.
--
-- 진입점은 환생 창이다(Phase 6 지시서 #5): 클라 RebirthRequest → RebirthRequestService가 빈도를
-- 자르고 rebirth(player, "ui")를 부른다. 이 함수는 로그 한 줄이 전부다.
function RebirthService.init()
	if initialized then
		warn("[RebirthService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	print("[RebirthService] 환생 준비 완료 (비용 1000 × 4^n · 진입점: 환생 창 → RebirthRequestService)")
end

-- 지금 환생하면 얻을 배수. 거부 여부만 보려면 canRebirth를 쓴다.
-- ⚠️ 읽기 전용이다. UI 표시용이며 이 값을 근거로 바깥에서 재화를 건드리지 말 것 —
-- 판정은 rebirth() 안에서 다시 한다.
function RebirthService.previewGain(player: Player): BigNumber?
	local blox = CurrencyService.get(player, "blox")
	if blox == nil then
		return nil
	end
	local rebirths = CurrencyService.get(player, "rebirths")
	return if rebirths ~= nil and EconomyV2Logic.canRebirth(blox, rebirths) then BigNum.new(1, 0) else BigNum.new(0, 0)
end

return RebirthService

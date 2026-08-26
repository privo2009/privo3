--!strict
-- 캐릭터 이동속도의 서버 권위 (CLAUDE.md 절대 규칙 3).
--
--   최대속도 = LevelConfig.getMaxSpeed(힘)
--   실제속도 = min(요청값, 최대속도)
--
-- 계산식과 상한의 근거는 Shared/Config/LevelConfig가 원본이다. 여기에 다시 쓰지 말 것 —
-- 이 파일은 그 값을 Humanoid에 얹고 유지하는 일만 한다.
--
-- ===== 왜 RemoteEvent 검증만으로 부족한가 =============================================
--
-- WalkSpeed는 클라가 바꿔도 서버로 복제된다. 그래서 "요청을 검증해서 세팅한다"까지만 하면
-- 세팅한 직후에 클라가 덮어써도 그대로 통한다. 서버가 최종값을 쓰고, 주기적으로 실측값을
-- 다시 읽어 되돌려야 한다.
--
-- ⚠️ 다만 주기 검사는 **지속적인 조작**을 걷어내는 장치이지 순간 조작을 막지 못한다.
-- 속도 500이면 깊이 8 studs를 16ms(60fps 기준 한 프레임)에 통과하므로, 어떤 주기를 골라도
-- 한 프레임짜리 관통은 잡히기 전에 끝난다. 이걸 주기를 줄여서 해결하려 하지 말 것 —
-- 부하만 늘고 막히지 않는다. 3D 이동으로 선택하는 구조에 남아 있는 잔여 리스크이고,
-- 실제 방어선은 "서버가 최종값을 쓴다 + 초과 상태가 유지되지 않는다"까지다.
--
-- ===== 저장하지 않는다 ================================================================
--
-- 커스텀 스피드는 프로필에 저장하지 않는다 (DESIGN.md "커스텀 스피드"). 세션 메모리뿐이다.
-- ⚠️ 그래서 schemaVersion을 올릴 일이 없다. 프로필 필드가 늘지 않는다.
--
-- ===== 재적용 계약 ====================================================================
--
-- min()은 **다시 호출될 때만** 클램프다. 세션 값만 메모리에 남고 재세팅이 없으면 이전 속도가
-- 그대로 유지된다. 그래서 아래 지점에서 반드시 재적용한다:
--
--   캐릭터 스폰   CharacterAdded — 접속·사망·리스폰이 전부 여기를 탄다
--   환생          onRebirth() — 최대치가 내려가는 유일한 지점
--   힘 변동       주기 검사가 매 틱 최대치를 다시 계산한다 (아래 참고)
--
-- 힘 변동마다 즉시 세팅하지 않는 이유: 클릭은 초당 최대 30회(OP 자동 클리커)라 클릭당
-- 세팅을 걸면 초당 30번 WalkSpeed를 쓴다. 레벨은 지수 기반이라 자릿수가 바뀔 때만 움직이므로
-- 그중 실제로 값이 달라지는 경우는 거의 없다. 그래서 주기 검사가 "지금 있어야 할 값"을
-- 계산해 다를 때만 쓴다 — 조작 되돌리기와 레벨업 반영이 같은 비교 한 줄로 처리된다.
-- 즉시 반영이 필요해지면 onStrengthChanged()를 호출자에서 부르면 된다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local CurrencyService = require(script.Parent.CurrencyService)

type BigNumber = BigNum.BigNumber

local SpeedService = {}

-- 실측값을 다시 읽어 검사하는 주기(초).
--
-- 값의 근거: 이 루프의 비용은 접속자당 Humanoid 읽기 1회 + 비교 1회다. 30명이면 틱당
-- 30회이고 1.5초 주기에서 초당 20회 — 무시할 수 있는 수준이다. 그런데도 1.0초로 더
-- 당기지 않는 이유는 얻는 것이 없기 때문이다: 위 주석대로 순간 관통은 어떤 주기로도
-- 못 막고, 이 루프가 실제로 잡는 것은 "속도를 올려놓고 계속 그 상태로 다니는" 경우다.
-- 그건 1.5초든 1.0초든 똑같이 잡힌다. 반대로 2초를 넘기면 되돌아오기까지의 체감 지연이
-- 눈에 띄기 시작한다(속도 80이면 2초에 160 studs). 1.5초는 그 사이다.
local CHECK_INTERVAL_SEC = 1.5

-- 같은 플레이어의 초과 로그를 다시 찍기까지의 최소 간격(초).
--
-- ⚠️ 되돌리기 자체는 매 틱 한다. 억제되는 것은 로그뿐이다.
-- PadService의 TOUCH_DEBOUNCE_SEC(처리 간격)과 NOTIFY_QUIET_SEC(로그 간격)이 별개였던 것과
-- 같은 구분이다 — 4-2-b에서 둘을 하나로 묶었다가 정상 동작인데 로그가 조용해서 오진했다.
-- 여기서는 반대 방향의 사고를 막는다: 조작을 계속 시도하는 클라는 매 틱 초과 상태로 잡히는데
-- 그때마다 찍으면 1.5초마다 한 줄씩 쌓여 다른 로그가 파묻힌다.
-- 10초인 이유: 이 로그의 용도는 "이 플레이어가 속도를 만지고 있다"는 사실 통지이지 횟수
-- 집계가 아니다. 억제된 동안의 횟수는 누적해서 다음 로그에 함께 싣는다.
local VIOLATION_LOG_QUIET_SEC = 10.0

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

-- requested가 nil이면 "최대치를 따라간다"는 뜻이다 (DESIGN.md: 기본값은 최대).
-- 유저가 한 번이라도 값을 정하면 그 값이 고정되고, 그 뒤로는 최대치가 올라도 따라 오르지 않는다.
export type SpeedState = {
	requested: number?,
	lastViolationLogAt: number,
	violationsSinceLog: number,
}

local function newSpeedState(): SpeedState
	return {
		requested = nil,
		lastViolationLogAt = 0,
		violationsSinceLog = 0,
	}
end

-- 클라가 보낸 값을 다시 잰다. 통과하면 그 수, 아니면 nil(거부)이다.
-- ⚠️ nil을 "기본값으로 되돌리기"로 해석하지 않는다 — 그러면 잘못된 payload가 조용히
-- 최대속도 요청이 되어버린다. 거부는 거부이고, 상태를 바꾸지 않는다.
local function sanitizeRequest(value: any): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value then -- nan
		return nil
	end
	if value == math.huge or value == -math.huge then
		return nil
	end
	if value <= 0 then
		return nil
	end
	return value
end

-- 지금 Humanoid에 있어야 할 속도.
local function resolveSpeed(requested: number?, maxSpeed: number): number
	if requested == nil then
		return maxSpeed
	end
	return math.min(requested, maxSpeed)
end

-- 최대치가 내려갔을 때 세션 값 자체를 끌어내린다 (환생이 이 경로다).
--
-- ⚠️ 내려가기만 하고 되돌아 오르지 않는다. 최대치가 다시 올라도 잘린 값은 그대로다 —
-- 유저가 느리게 설정한 데는 이유가 있다(발판을 정확히 밟으려는 것). 레벨이 올랐다는
-- 이유로 유저가 정한 속도를 임의로 올리면 그 의도를 서버가 뒤집는 셈이다.
-- 최대치 상승은 상한만 올린다.
local function clampState(state: SpeedState, maxSpeed: number): SpeedState
	if state.requested == nil or state.requested <= maxSpeed then
		return state
	end

	return {
		requested = maxSpeed,
		lastViolationLogAt = state.lastViolationLogAt,
		violationsSinceLog = state.violationsSinceLog,
	}
end

-- 요청 하나를 반영한다. (새 상태, 실제 적용될 속도, 받아들였는가)
local function applyRequest(state: SpeedState, value: any, maxSpeed: number): (SpeedState, number, boolean)
	local clean = sanitizeRequest(value)
	if clean == nil then
		return state, resolveSpeed(state.requested, maxSpeed), false
	end

	local moved: SpeedState = {
		requested = math.min(clean, maxSpeed),
		lastViolationLogAt = state.lastViolationLogAt,
		violationsSinceLog = state.violationsSinceLog,
	}
	return moved, resolveSpeed(moved.requested, maxSpeed), true
end

-- 테스트 전용 통로. 공개 API 계약이 아니다 (PadService._pure와 같은 패턴).
SpeedService._pure = {
	newSpeedState = newSpeedState,
	sanitizeRequest = sanitizeRequest,
	resolveSpeed = resolveSpeed,
	clampState = clampState,
	applyRequest = applyRequest,
	CHECK_INTERVAL_SEC = CHECK_INTERVAL_SEC,
	VIOLATION_LOG_QUIET_SEC = VIOLATION_LOG_QUIET_SEC,
}

-- ===== 공개 API (Player 상태 보관) =====================================================

local states: { [Player]: SpeedState } = {}
local initialized = false

local function getState(player: Player): SpeedState
	local state = states[player]
	if state == nil then
		state = newSpeedState()
		states[player] = state
	end
	return state
end

-- 힘을 읽는다. CurrencyService가 재화의 단일 통로다 (CLAUDE.md 절대 규칙 2) —
-- strength는 CURRENCIES에 있으므로 profile.Data.strength를 직접 읽지 않는다.
-- 프로필 로드 전이면 nil이 온다. 그때는 힘 0으로 보고 기본 속도를 준다.
local function readStrength(player: Player): BigNumber
	local strength = CurrencyService.get(player, "strength")
	if strength == nil then
		return BigNum.new(0, 0)
	end
	return strength
end

-- 이 플레이어의 현재 최대 이동속도.
function SpeedService.getMaxSpeed(player: Player): number
	return LevelConfig.getMaxSpeed(readStrength(player))
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- 세션 값을 현재 최대치로 클램프하고 Humanoid에 반영한다.
-- 캐릭터가 아직 없으면 상태만 정리한다 — 다음 CharacterAdded가 반영한다.
local function applyToHumanoid(player: Player): number
	local maxSpeed = SpeedService.getMaxSpeed(player)

	local state = clampState(getState(player), maxSpeed)
	states[player] = state

	local speed = resolveSpeed(state.requested, maxSpeed)

	local humanoid = getHumanoid(player)
	if humanoid ~= nil and humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end

	return speed
end

-- 요청값을 반영한다. 반환값은 실제로 적용된 속도다(요청값이 아니다).
--
-- ⚠️ 클라가 보낸 값은 전부 검증 대상이다 (CLAUDE.md 절대 규칙 3). 최대치는 여기서
-- 서버가 힘으로부터 다시 계산한다 — 호출자가 최대치를 넘겨주는 형태로 바꾸지 말 것.
function SpeedService.setCustomSpeed(player: Player, requested: any): number
	local maxSpeed = SpeedService.getMaxSpeed(player)

	local state, speed, accepted = applyRequest(getState(player), requested, maxSpeed)
	states[player] = state

	if not accepted then
		-- 거부는 조용히 넘긴다. Remote가 붙기 전이라 여기 오는 값은 서버 호출자뿐이고,
		-- 붙은 뒤에는 클라가 반복해서 보낼 수 있어 warn이 부하가 된다.
		--
		-- ⚠️ 거부여도 그냥 돌아가지 않는다. 최대치가 내려간 뒤 첫 요청이 거부된 경우
		-- 세션 값이 아직 새 최대치를 초과한 상태일 수 있고, 그러면 여기서 돌려주는 값과
		-- Humanoid의 실제 값이 어긋난다. 재적용을 태워 둘을 맞춘다.
		return applyToHumanoid(player)
	end

	local humanoid = getHumanoid(player)
	if humanoid ~= nil and humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end

	return speed
end

-- 현재 세션 값으로 다시 세팅한다. 최대치가 내려갔으면 세션 값도 함께 잘린다.
function SpeedService.reapply(player: Player): number
	return applyToHumanoid(player)
end

-- 환생 시 호출한다. 힘이 0이 되어 최대치가 기본값까지 내려가는 유일한 지점이다.
--
-- ⚠️ 호출자는 아직 없다. RebirthService는 4-2-d이고 SpeedService가 먼저 생겼다.
-- 4-2-d에서 환생 처리 마지막에 이 함수를 부르게 한다 — 부르지 않으면 세션 값이
-- 새 최대치를 초과한 채 남는다(그게 이 함수가 존재하는 이유다).
function SpeedService.onRebirth(player: Player): number
	return applyToHumanoid(player)
end

-- 힘이 바뀐 직후 즉시 반영이 필요할 때 부른다.
--
-- ⚠️ 클릭 경로에서 매번 부르지 말 것 — 초당 30회 호출이 된다. 평상시의 레벨업 반영은
-- 주기 검사가 맡는다(파일 상단 "재적용 계약" 참고). 이 함수는 "지금 당장 보여야 하는"
-- 경우(예: 대량 지급 직후 연출)를 위한 통로다.
function SpeedService.onStrengthChanged(player: Player): number
	return applyToHumanoid(player)
end

-- 주기 검사 한 틱. 초과 상태면 되돌리고, 로그는 억제 간격을 두고 찍는다.
local function checkOnce(player: Player, now: number)
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return
	end

	local maxSpeed = SpeedService.getMaxSpeed(player)

	local state = clampState(getState(player), maxSpeed)
	states[player] = state

	local expected = resolveSpeed(state.requested, maxSpeed)
	local actual = humanoid.WalkSpeed

	if actual == expected then
		return
	end

	-- 되돌리기는 매번 한다 (억제 대상이 아니다).
	humanoid.WalkSpeed = expected

	-- 최대치 이하에서의 불일치는 조작이 아니라 반영 지연이다(레벨업 직후 등). 조용히 맞춘다.
	if actual <= maxSpeed then
		return
	end

	state.violationsSinceLog += 1

	if (now - state.lastViolationLogAt) < VIOLATION_LOG_QUIET_SEC then
		return
	end

	warn(string.format(
		"[SpeedService] %s(%d) WalkSpeed 초과 감지 - %.1f -> %.1f로 되돌림 (최대 %.1f, 최근 %d회)",
		player.Name,
		player.UserId,
		actual,
		expected,
		maxSpeed,
		state.violationsSinceLog
	))

	state.lastViolationLogAt = now
	state.violationsSinceLog = 0
end

-- CharacterAdded / PlayerRemoving 배선 + 주기 검사 시작.
function SpeedService.init()
	if initialized then
		warn("[SpeedService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local function bindCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			-- 캐릭터 스폰은 접속·사망·리스폰이 전부 지나는 지점이다. Humanoid가 기본
			-- WalkSpeed(16)로 새로 만들어지므로 여기서 반드시 다시 얹어야 한다.
			SpeedService.reapply(player)
		end)

		-- init()보다 스폰이 먼저 끝난 경우(핫리로드·Play 재시작)를 위해 한 번 즉시 적용한다.
		if player.Character ~= nil then
			SpeedService.reapply(player)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindCharacter(player)
	end
	Players.PlayerAdded:Connect(bindCharacter)

	-- 나간 플레이어의 세션 값을 지운다. 안 지우면 Player 인스턴스가 이 테이블에 영구히
	-- 붙잡혀 있게 된다 (PadService.states와 같은 이유).
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	-- ⚠️ 주기 검사는 플레이어별 루프가 아니라 전역 루프 하나다.
	-- 플레이어마다 task.spawn을 걸면 나갈 때 그 루프를 각각 멈춰야 하고, 한 번 놓치면
	-- 죽은 Player를 붙잡은 루프가 서버 수명 내내 돈다. 전역 루프 하나면 정리할 것이
	-- states 한 곳뿐이라 누수 지점이 아예 생기지 않는다.
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL_SEC)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				checkOnce(player, now)
			end
		end
	end)

	print(string.format("[SpeedService] 초기화 완료 (검사 주기 %.1f초)", CHECK_INTERVAL_SEC))
end

return SpeedService

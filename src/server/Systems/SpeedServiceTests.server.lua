--!strict
-- SpeedService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-c 검증: 요청값 클램프 / 입력 위생 / 환생 시 세션 값 하향 / 최대치 상승 시 불변.
--
-- SpeedService._pure의 순수 함수만 호출한다 — Player/Humanoid 없이 검증한다
-- (PadServiceTests와 같은 방식). Humanoid에 실제로 얹히는지와 CharacterAdded 배선은
-- 여기서 다루지 않는다: 그쪽은 Instance가 필요해서 Studio Play 육안 확인 몫이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local SpeedService = require(script.Parent.SpeedService)

local pure = SpeedService._pure

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

-- 최대치 픽스처. 절대값을 박지 않고 LevelConfig에서 받아온다 — 발판 깊이가 바뀌면
-- 상한도 따라 바뀌는데, 여기에 80을 적어두면 그 시점에 테스트만 조용히 틀려진다.
local BASE = LevelConfig.BASE_WALK_SPEED
local CAP = LevelConfig.getMaxWalkSpeed()

-- 1. 요청값 클램프 ----------------------------------------------------------------------

do
	local state = pure.newSpeedState()
	local maxSpeed = 30

	local moved, applied, accepted = pure.applyRequest(state, 100, maxSpeed)
	check("요청값이 최대치보다 크면 최대치로 잘린다", applied == maxSpeed and accepted, string.format("applied=%s", tostring(applied)))
	check("잘린 값은 세션에도 잘린 채로 남는다", moved.requested == maxSpeed, tostring(moved.requested))
end

do
	local state = pure.newSpeedState()
	local maxSpeed = 30

	local moved, applied, accepted = pure.applyRequest(state, 22, maxSpeed)
	check("요청값이 최대치 이하면 그대로 통과", applied == 22 and moved.requested == 22 and accepted)
end

do
	local state = pure.newSpeedState()
	local maxSpeed = 30

	-- 경계값. 최대치와 정확히 같은 요청은 잘림이 아니라 통과다.
	local _, applied, accepted = pure.applyRequest(state, maxSpeed, maxSpeed)
	check("요청값이 최대치와 같으면 통과", applied == maxSpeed and accepted)
end

-- 2. 입력 위생 --------------------------------------------------------------------------

do
	-- ⚠️ nil을 이 배열에 넣지 말 것 — 배열 리터럴 중간의 nil은 ipairs를 거기서 끊는다.
	-- nil은 아래에서 따로 검사한다.
	local bad: { any } = { 0, -1, -0.5, 0 / 0, math.huge, -math.huge, "30", {}, true }
	local allRejected = pure.sanitizeRequest(nil) == nil
	for _, value in ipairs(bad) do
		if pure.sanitizeRequest(value) ~= nil then
			allRejected = false
		end
	end
	check("0 이하 / nan / inf / 숫자 아님 / nil은 전부 거부", allRejected)
end

do
	check("정상 양수는 통과", pure.sanitizeRequest(24.5) == 24.5)
end

do
	local state = pure.newSpeedState()
	local maxSpeed = 30

	-- 먼저 정상 요청으로 세션 값을 만든 뒤, 잘못된 요청이 그것을 건드리지 못하는지 본다.
	local settled = (pure.applyRequest(state, 20, maxSpeed))

	local after, applied, accepted = pure.applyRequest(settled, "빠르게", maxSpeed)
	check("거부된 요청은 세션 값을 바꾸지 않는다", after.requested == 20 and not accepted, tostring(after.requested))
	check("거부되어도 반환값은 현재 실제 속도", applied == 20, tostring(applied))
end

do
	-- ⚠️ nil을 "기본값으로 되돌리기"로 해석하면 잘못된 payload가 조용히 최대속도 요청이 된다.
	local state = pure.newSpeedState()
	local settled = (pure.applyRequest(state, 20, 30))

	local after, _, accepted = pure.applyRequest(settled, nil, 30)
	check("nil 요청은 최대속도 요청으로 해석되지 않는다", after.requested == 20 and not accepted, tostring(after.requested))
end

-- 3. 기본값은 최대치 추종 ---------------------------------------------------------------

do
	local state = pure.newSpeedState()
	check("한 번도 설정하지 않았으면 requested는 nil", state.requested == nil)
	check("설정 전에는 최대치를 그대로 따라간다", pure.resolveSpeed(state.requested, 47) == 47)
end

-- 4. 환생 시나리오 — 최대치가 내려가면 세션 값도 잘린다 -----------------------------------

do
	-- 힘이 커서 최대치가 상한(CAP)인 상태에서 값을 골라 두고, 환생으로 최대치가 BASE로 떨어진다.
	-- 고르는 값은 BASE와 CAP 사이에서 유도한다 — 50 같은 절대값을 박으면 발판 깊이를
	-- 줄여 CAP이 50 아래로 내려가는 순간 전제가 조용히 깨진다.
	local state = pure.newSpeedState()
	local chosen = (BASE + CAP) / 2

	local settled = (pure.applyRequest(state, chosen, CAP))
	check("환생 전: 고른 값이 그대로 남는다", settled.requested == chosen, tostring(settled.requested))

	-- 환생 후 최대치. 힘 0 -> 레벨 0 -> BASE.
	local rebirthMax = LevelConfig.getMaxSpeed(BigNum.new(0, 0))
	check("환생 후 최대치는 BASE_WALK_SPEED", rebirthMax == BASE, tostring(rebirthMax))

	local clamped = pure.clampState(settled, rebirthMax)
	check("환생으로 최대치가 내려가면 세션 값이 잘린다", clamped.requested == rebirthMax, tostring(clamped.requested))
	check("잘린 뒤 실제 속도도 새 최대치", pure.resolveSpeed(clamped.requested, rebirthMax) == rebirthMax)

	-- ⚠️ 재적용이 없으면 이 클램프가 일어나지 않는다는 것이 계약의 핵심이다.
	-- clampState를 부르지 않은 원래 상태는 새 최대치를 초과한 채로 남아 있다.
	check("재적용 전에는 세션 값이 새 최대치를 초과한 채 남는다", (settled.requested :: number) > rebirthMax)
end

-- 5. 최대치가 올라가도 세션 값은 그대로 --------------------------------------------------

do
	-- ⚠️ 이 케이스가 이 파일에서 제일 중요하다. 레벨이 올랐다고 유저가 설정한 속도를
	-- 임의로 올리면 안 된다 — 느리게 설정한 이유는 발판을 정확히 밟기 위해서다.
	local state = pure.newSpeedState()
	local settled = (pure.applyRequest(state, 20, 30))

	local raised = pure.clampState(settled, CAP)
	check("최대치가 올라가도 세션 값은 그대로", raised.requested == 20, tostring(raised.requested))
	check("최대치가 올라가도 실제 속도는 그대로", pure.resolveSpeed(raised.requested, CAP) == 20)
end

do
	-- 한 번 잘린 값은 최대치가 회복돼도 되돌아 오르지 않는다 (환생 후 다시 레벨업한 경우).
	local state = pure.newSpeedState()
	local settled = (pure.applyRequest(state, (BASE + CAP) / 2, CAP))
	local afterRebirth = pure.clampState(settled, BASE)
	local afterRegrow = pure.clampState(afterRebirth, CAP)

	check("환생으로 잘린 값은 레벨이 회복돼도 되돌아 오르지 않는다", afterRegrow.requested == BASE, tostring(afterRegrow.requested))
end

-- 6. 상수 계약 --------------------------------------------------------------------------

do
	-- 되돌리기(매 틱)와 로그(억제)는 별개 값이어야 한다. 같아지면 4-2-b에서 겪은
	-- "정상 동작인데 로그가 조용해서 오진" 또는 그 반대가 다시 난다.
	check(
		"검사 주기와 로그 억제 간격은 별개 값이다",
		pure.VIOLATION_LOG_QUIET_SEC > pure.CHECK_INTERVAL_SEC,
		string.format("check=%.1f, log=%.1f", pure.CHECK_INTERVAL_SEC, pure.VIOLATION_LOG_QUIET_SEC)
	)
	check(
		"검사 주기는 1~2초 범위",
		pure.CHECK_INTERVAL_SEC >= 1.0 and pure.CHECK_INTERVAL_SEC <= 2.0,
		string.format("%.2f", pure.CHECK_INTERVAL_SEC)
	)
end

print(string.format("[SpeedServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SpeedServiceTests] %d test(s) failed", failed))
end

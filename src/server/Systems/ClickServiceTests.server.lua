--!strict
-- ClickService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-b 검증: 입력 검증 / 슬라이딩 윈도우 상한 / 힘 증가량 / 상한 통지 억제.
--
-- ClickService._pure의 순수 함수만 호출한다 — Player/RemoteEvent 없이 검증한다
-- (PadServiceTests와 같은 방식). 실제 RemoteEvent 왕복과 CurrencyService 지급은
-- 여기서 다루지 않는다: 그쪽은 접속한 플레이어가 필요해서 Studio Play 육안 확인 몫이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local ClickService = require(script.Parent.ClickService)

local pure = ClickService._pure

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

local LIMIT = pure.MANUAL_CLICK_LIMIT
local WINDOW = pure.WINDOW_SEC
local WORLD_ID = 1

-- 배수가 없는 상태(환생 0회). compute가 돌려주는 값을 그대로 쓴다 —
-- BigNum.new(1, 0)을 직접 적으면 "배수 없음"의 정의가 두 곳이 된다.
local NO_MULTIPLIER = StrengthMultiplier.compute(nil)

-- 시각은 os.clock()을 쓰지 않는다. 순수 함수라 now를 인자로 받으므로 테스트가
-- 시간을 직접 정한다 — 실제 시계에 의존하면 윈도우 만료 검증에 sleep이 필요해진다.
local T0 = 1000.0

-- 1. sanitizeCount: 클라가 보낸 값 검증 ---------------------------------------------------

check("sanitizeCount: 정상 정수 3은 그대로", pure.sanitizeCount(3) == 3)
check("sanitizeCount: 1은 통과", pure.sanitizeCount(1) == 1)
check("sanitizeCount: 0은 0", pure.sanitizeCount(0) == 0)
check("sanitizeCount: 음수는 0", pure.sanitizeCount(-5) == 0)
check("sanitizeCount: 실수는 0", pure.sanitizeCount(2.5) == 0)
check("sanitizeCount: 문자열은 0", pure.sanitizeCount("10") == 0)
check("sanitizeCount: nil은 0", pure.sanitizeCount(nil) == 0)
check("sanitizeCount: 테이블은 0", pure.sanitizeCount({}) == 0)
check("sanitizeCount: nan은 0", pure.sanitizeCount(0 / 0) == 0)
check("sanitizeCount: inf는 0", pure.sanitizeCount(math.huge) == 0)
check(
	string.format("sanitizeCount: 배치 상한(%d) 초과는 상한으로 접힘", pure.MAX_BATCH_COUNT),
	pure.sanitizeCount(1e9) == pure.MAX_BATCH_COUNT
)

-- 2. 윈도우 안에서 상한까지 통과, 그 다음은 버려진다 ---------------------------------------

do
	-- 1회씩 LIMIT + 5번. 전부 같은 시각이므로 윈도우가 비지 않는다.
	local state = pure.newClickState()
	local totalAccepted = 0
	local totalRejected = 0
	local firstRejectAt = 0

	for i = 1, LIMIT + 5 do
		local nextState, accepted, rejected = pure.applyClicks(state, 1, T0)
		state = nextState
		totalAccepted += accepted
		totalRejected += rejected
		if rejected > 0 and firstRejectAt == 0 then
			firstRejectAt = i
		end
	end

	check(
		string.format("윈도우 안에서 %d회까지만 통과 (실제 %d)", LIMIT, totalAccepted),
		totalAccepted == LIMIT
	)
	check(
		string.format("나머지 5회는 버려짐 (실제 %d)", totalRejected),
		totalRejected == 5
	)
	check(
		string.format("%d회째부터 버려지기 시작 (실제 %d회째)", LIMIT + 1, firstRejectAt),
		firstRejectAt == LIMIT + 1
	)
end

do
	-- 한 배치에 상한을 넘겨 보낸 경우. 잘리는 지점은 같아야 한다.
	local state = pure.newClickState()
	local _, accepted, rejected = pure.applyClicks(state, LIMIT + 3, T0)
	check(string.format("한 배치 %d회 → %d회만 통과", LIMIT + 3, LIMIT), accepted == LIMIT)
	check("한 배치 초과분은 버려짐", rejected == 3)
end

-- 3. 윈도우가 지나면 다시 열린다 -----------------------------------------------------------

do
	local state = pure.newClickState()
	state = (pure.applyClicks(state, LIMIT, T0))

	-- 아직 창 안: 한 자리도 없다.
	local _, blockedAccepted, blockedRejected = pure.applyClicks(state, 1, T0 + WINDOW / 2)
	check("윈도우 안에서는 추가 통과 없음", blockedAccepted == 0 and blockedRejected == 1)

	-- 창을 정확히 넘긴 시점: 기록이 전부 만료되어 상한만큼 다시 열린다.
	local reopened, reopenedAccepted, reopenedRejected = pure.applyClicks(state, LIMIT, T0 + WINDOW)
	check(
		string.format("윈도우가 지나면 %d회가 다시 열림 (실제 %d)", LIMIT, reopenedAccepted),
		reopenedAccepted == LIMIT
	)
	check("윈도우 재개통 시 버려지는 분 없음", reopenedRejected == 0)
	check("재개통 후 기록은 새 것만 남음", #reopened.times == LIMIT)
end

-- 4. 힘 증가량 = 통과 횟수 × 현재 패드 파워 -------------------------------------------------
--
-- 전부 BigNum 경유다. raw number 산술로 기대값을 만들지 않는다.

do
	local pad5Power = ClickPadConfig.getPadPower(WORLD_ID, 5)
	local gain = pure.computeGain(pad5Power, 3, NO_MULTIPLIER)

	-- 패드5 파워는 basePower(1) × powerGrowth(2)^4 = 16. 3회면 48이다.
	-- 절대값 48을 그대로 쓰지 않고 파워 × 3으로도 함께 확인한다 — Config를 튜닝하면
	-- 이 주석의 숫자는 틀려지지만 아래 두 번째 검사는 스스로 따라간다.
	check(
		string.format("패드5 클릭 3회 → 힘 48 (실제 %s)", BigNum.tostring(gain)),
		BigNum.eq(gain, BigNum.new(4.8, 1))
	)
	check(
		"힘 증가량 == 패드 파워 × 통과 횟수",
		BigNum.eq(gain, BigNum.mul(pad5Power, BigNum.fromNumber(3)))
	)

	check(
		"패드1 클릭 1회 → 힘 1 (basePower 그대로)",
		BigNum.eq(pure.computeGain(ClickPadConfig.getPadPower(WORLD_ID, 1), 1, NO_MULTIPLIER), BigNum.new(1, 0))
	)
	check(
		"통과 0회면 증가량 0",
		BigNum.eq(pure.computeGain(ClickPadConfig.getPadPower(WORLD_ID, 5), 0, NO_MULTIPLIER), BigNum.new(0, 0))
	)

	-- 상한까지 눌러도 raw number로 새지 않는지. 패드24는 파워가 8.39e6이다.
	local pad24Gain = pure.computeGain(ClickPadConfig.getPadPower(WORLD_ID, 24), LIMIT, NO_MULTIPLIER)
	check(
		"패드24 상한만큼 클릭해도 BigNum 형태 유지",
		type(pad24Gain) == "table" and type(pad24Gain.m) == "number" and type(pad24Gain.e) == "number"
	)
end

-- 4b. 환생 배수가 획득량에 곱해진다 (4-2-d 잔여 배선) ---------------------------------------
--
-- ⚠️ 이 블록이 막는 사고: compute의 호출자가 0이라 환생을 몇 번 하든 클릭당 힘이
-- 그대로였다. 배수가 없어도 힘은 멀쩡히 오르므로 **플레이로는 발견되지 않는다** —
-- 그래서 테스트가 유일한 관측 지점이다. 이 케이스들을 지우지 말 것.
--
-- ⚠️ 기대 배수를 1 + rebirths로 직접 계산하지 않는다. compute를 태워서 만든다 —
-- 여기서 식을 다시 쓰면 그 순간 이 테스트는 "compute가 맞는가"가 아니라
-- "내가 적은 식이 맞는가"를 재게 되고, compute가 바뀌어도 안 깨진다.

do
	local padPower = ClickPadConfig.getPadPower(WORLD_ID, 5)
	local CLICKS = 3
	local base = pure.computeGain(padPower, CLICKS, NO_MULTIPLIER)

	-- (1) 회귀 방지: 환생 0회면 배선 전과 완전히 같은 값이어야 한다.
	local zeroMultiplier = StrengthMultiplier.compute({ rebirths = BigNum.new(0, 0) })
	check(
		"rebirths 0 — 획득량이 배선 전과 동일",
		BigNum.eq(pure.computeGain(padPower, CLICKS, zeroMultiplier), BigNum.mul(padPower, BigNum.fromNumber(CLICKS))),
		BigNum.tostring(pure.computeGain(padPower, CLICKS, zeroMultiplier))
	)
	check("rebirths 0의 배수는 1이다", BigNum.eq(zeroMultiplier, BigNum.new(1, 0)), BigNum.tostring(zeroMultiplier))

	-- (2) 양수 환생: 배수만큼 커진다. 배수 자체는 compute에서 받아온다.
	local rebirths = BigNum.fromNumber(4)
	local multiplier = StrengthMultiplier.compute({ rebirths = rebirths })
	local boosted = pure.computeGain(padPower, CLICKS, multiplier)

	check(
		"rebirths 4 — 획득량이 배수만큼 커진다",
		BigNum.eq(boosted, BigNum.mul(base, multiplier)),
		string.format("%s (배수 %s)", BigNum.tostring(boosted), BigNum.tostring(multiplier))
	)
	check("rebirths 4의 배수는 5다 (1 + rebirths)", BigNum.eq(multiplier, BigNum.new(5, 0)), BigNum.tostring(multiplier))
	check("배수가 붙으면 실제로 더 커진다", BigNum.gt(boosted, base))

	-- (3) 배수는 **획득량에만** 붙는다. 보유 힘에 붙지 않는다.
	-- computeGain의 인자에 보유 힘이 아예 없다는 것이 구조적 증거지만, 그것만으로는
	-- "인자가 늘어나도 안 깨지는" 테스트가 된다. 그래서 값으로도 확인한다:
	-- 획득량은 (패드파워 × 횟수)에만 비례하고, 보유 힘이 얼마든 결과가 같아야 한다.
	check(
		"배수는 획득량에만 적용된다 — 결과가 패드파워 × 횟수 × 배수와 정확히 일치",
		BigNum.eq(boosted, BigNum.mul(BigNum.mul(padPower, BigNum.fromNumber(CLICKS)), multiplier))
	)

	-- 보유 힘은 computeGain의 **인자가 아니다.** 누군가 보유 힘을 받아 곱하도록
	-- 바꾸면 인자가 4개로 늘고 여기서 잡힌다. 값 검사만으로는 그 변경을 못 본다 —
	-- 새 인자를 nil로 받으면 기존 등식이 그대로 성립하기 때문이다.
	check(
		"computeGain의 인자는 3개다 (보유 힘이 들어올 자리가 없다)",
		debug.info(pure.computeGain, "a") == 3,
		tostring(debug.info(pure.computeGain, "a"))
	)

	-- (4) 통과 0회면 배수가 아무리 커도 0이다. 배수가 0을 1로 만들면 안 된다.
	local bigMultiplier = StrengthMultiplier.compute({ rebirths = BigNum.new(1, 100) })
	check(
		"통과 0회면 배수가 커도 획득량 0",
		BigNum.eq(pure.computeGain(padPower, 0, bigMultiplier), BigNum.new(0, 0))
	)

	-- (5) 큰 배수에서도 BigNum 형태를 유지한다 (raw number로 새지 않는다).
	local huge = pure.computeGain(ClickPadConfig.getPadPower(WORLD_ID, 24), LIMIT, bigMultiplier)
	check(
		"큰 배수에서도 BigNum 형태 유지",
		type(huge) == "table" and type(huge.m) == "number" and type(huge.e) == "number" and huge.m == huge.m,
		BigNum.tostring(huge)
	)
end

-- 5. 버려진 클릭이 있을 때 rejected 신호가 선다 ---------------------------------------------

do
	local state = pure.newClickState()

	-- 아직 아무것도 안 버려졌으면 통지할 것이 없다.
	local _, quietNotify = pure.takeRejectNotice(state, T0)
	check("버린 것이 없으면 통지 안 함", quietNotify == false)

	-- 상한을 채우고 3회 더 → 3회가 버려진다.
	state = (pure.applyClicks(state, LIMIT, T0))
	local afterReject, _, rejected = pure.applyClicks(state, 3, T0)
	check("상한 초과분이 버려짐", rejected == 3)
	check("버린 수가 상태에 누적됨", afterReject.droppedSinceNotify == 3)

	local notified, shouldNotify, dropped = pure.takeRejectNotice(afterReject, T0)
	check("버린 것이 있으면 통지가 섬", shouldNotify == true)
	check(string.format("통지에 버린 수 3이 실림 (실제 %d)", dropped), dropped == 3)
	check("통지 후 누적이 비워짐", notified.droppedSinceNotify == 0)
end

-- 6. 통지 억제 ------------------------------------------------------------------------------

do
	local state = pure.newClickState()
	state = (pure.applyClicks(state, LIMIT, T0))

	-- 첫 통지.
	local afterFirst = (pure.applyClicks(state, 2, T0))
	local notified, firstNotify = pure.takeRejectNotice(afterFirst, T0)
	check("첫 통지는 나감", firstNotify == true)

	-- 억제 창 안에서 또 버려져도 통지하지 않는다.
	local afterSecond = (pure.applyClicks(notified, 2, T0 + pure.REJECT_NOTIFY_SEC / 2))
	local suppressed, secondNotify = pure.takeRejectNotice(afterSecond, T0 + pure.REJECT_NOTIFY_SEC / 2)
	check("억제 창 안의 두 번째 통지는 막힘", secondNotify == false)
	check("막힌 동안에도 버린 수는 계속 쌓임", suppressed.droppedSinceNotify == 2)

	-- 창이 지나면 다시 나가고, 그동안 쌓인 수가 한꺼번에 실린다.
	--
	-- ⚠️ later 시점에는 클릭 윈도우(WINDOW_SEC)도 같이 만료되어 자리가 다시 비어 있다.
	-- 그래서 한 번 더 버리려면 창을 다시 채우고 나서 초과분을 넣어야 한다. 두 창의
	-- 길이가 지금 우연히 같아서 겹치는 것이지, 억제 창과 클릭 창은 서로 다른 값이다.
	local later = T0 + pure.REJECT_NOTIFY_SEC
	local refilled = (pure.applyClicks(suppressed, LIMIT, later))
	local afterThird = (pure.applyClicks(refilled, 1, later))
	local _, thirdNotify, thirdDropped = pure.takeRejectNotice(afterThird, later)
	check("억제 창이 지나면 다시 통지", thirdNotify == true)
	check(
		string.format("억제 동안 쌓인 분이 합산되어 실림 (실제 %d)", thirdDropped),
		thirdDropped == 3
	)
end

-- 7. 자동 클리커 경로(Phase 8 자리)는 상한을 받지 않는다 -------------------------------------

do
	local state = pure.newClickState()
	state = (pure.applyClicks(state, LIMIT, T0)) -- 수동으로 창을 꽉 채워둔다

	local unchanged, accepted, rejected = pure.passAll(state, 30)
	check("자동 경로는 상한 없이 전부 통과", accepted == 30 and rejected == 0)
	check("자동 경로는 수동 윈도우를 소모하지 않음", #unchanged.times == LIMIT)
end

-- 결과 ------------------------------------------------------------------------------------

-- 출력 형식은 다른 테스트 파일과 동일하게 맞춘다 — 통과·실패 개수를 항상 함께 찍는다.
-- 전에는 통과 시 개수만 찍어서, 로그를 훑을 때 "실패 0"인지 "실패 항목이 안 찍힌 것"인지
-- 구분되지 않았다.
print(string.format("[ClickServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ClickServiceTests] %d test(s) failed", failed))
end

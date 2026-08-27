--!strict
-- WarpConfig 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-e Prompt 1 검증: 비용 곡선이 지수인가 / 순수한가 / 거부 사유가 갈리는가.
--
-- ⚠️ 마지막 층 번호를 이 파일에 적지 않는다. WorldConfig에서 찾아 쓴다 —
-- 여기에 25를 적으면 월드 2가 추가될 때 경계 테스트가 조용히 엉뚱한 층을 보게 된다.
-- 그게 바로 WarpConfig가 막으려는 하드코딩과 같은 실수다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = ReplicatedStorage.Shared.Config
local StageConfig = require(Config.StageConfig)
local WarpConfig = require(Config.WarpConfig)

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

local RATIO = WarpConfig._pure.TEMP_COST_RATIO
local BASE = WarpConfig._pure.TEMP_COST_BASE

-- 현재 WorldConfig가 덮는 마지막 층. 숫자를 적지 않고 찾는다.
local LAST_STAGE = 1
while StageConfig.hasStage(LAST_STAGE + 1) do
	LAST_STAGE = LAST_STAGE + 1
end

-- 상대 오차 비교. BigNum.pow는 log10 기반이고 유효자리 12에서 반올림되므로
-- 곡선 검사는 정확히 일치가 아니라 상대 오차로 본다.
local function closeEnough(actual: number, expected: number, tolerance: number): boolean
	if expected == 0 then
		return math.abs(actual) <= tolerance
	end
	return math.abs(actual - expected) / math.abs(expected) <= tolerance
end

-- 어떤 in-range 층의 비용보다도 큰 "충분한 블럭스".
-- ⚠️ 1e300 같은 고정값으로 두지 않는다. 월드가 늘어 비용이 그 값을 넘기면
-- 통과를 기대한 케이스들이 조용히 INSUFFICIENT_BLOX로 갈아타면서, 확인하려던
-- 것(범위 판정 · 사유 우선순위)과 다른 것을 확인하게 된다. 곡선에서 직접 뽑는다.
-- 비용은 단조 증가하므로 마지막 층보다 한 칸 위의 비용이면 전 구간을 덮는다.

local RICH = BigNum.mul(WarpConfig.cost(LAST_STAGE + 1), BigNum.fromNumber(10))

-- ===== 곡선 =========================================================================

do
	local ok = true
	local firstBad: string? = nil

	for stage = 1, LAST_STAGE - 1 do
		if not BigNum.gt(WarpConfig.cost(stage + 1), WarpConfig.cost(stage)) then
			ok = false
			firstBad = string.format(
				"%d(%s) -> %d(%s)",
				stage,
				BigNum.tostring(WarpConfig.cost(stage)),
				stage + 1,
				BigNum.tostring(WarpConfig.cost(stage + 1))
			)
			break
		end
	end

	check("비용이 stage에 대해 단조 증가한다", ok, firstBad)
end

do
	-- ⚠️ 이 파일에서 가장 중요한 케이스다. 선형이면 여기서 깨진다.
	-- 지수는 등간격 stage의 비용 **비율**이 어디서나 같다. 선형(a + b·s)이면
	-- 같은 간격이라도 s가 커질수록 비율이 1에 수렴하므로 아래가 통과할 수 없다.
	local STEP = 5
	local expected = RATIO ^ STEP
	local ok = true
	local firstBad: string? = nil

	for stage = 1, LAST_STAGE - STEP do
		local ratio = BigNum.toRatio(WarpConfig.cost(stage + STEP), WarpConfig.cost(stage))
		if not closeEnough(ratio, expected, 1e-9) then
			ok = false
			firstBad = string.format("stage %d: %.12g (기대 %.12g)", stage, ratio, expected)
			break
		end
	end

	check(string.format("지수다 — %d칸 간격 비용 비율이 어디서나 %.12g", STEP, expected), ok, firstBad)
end

do
	-- 1층이 기준점이므로 cost(1)은 BASE 그대로여야 한다. 지수가 stage(1이 되어버림)로
	-- 잘못 들어가면 여기가 RATIO배 어긋난 값으로 잡힌다.
	local cost1 = WarpConfig.cost(1)
	check(
		"1층 비용이 BASE와 같다 (지수는 stage-1)",
		BigNum.eq(cost1, BigNum.fromNumber(BASE)),
		string.format("%s (기대 %d)", BigNum.tostring(cost1), BASE)
	)
end

-- ===== 순수성 =======================================================================

do
	local a = WarpConfig.cost(10)
	local b = WarpConfig.cost(10)
	check(
		"같은 stage를 두 번 호출하면 같은 값이다",
		BigNum.eq(a, b),
		string.format("%s vs %s", BigNum.tostring(a), BigNum.tostring(b))
	)

	-- ⚠️ 값이 같은 것만으로는 부족하다. 상수 테이블을 재사용하고 있으면 호출자가
	-- 반환값을 고치는 순간 이후 모든 호출이 오염된다 (RebirthConfig의 zero() 주석 참고).
	-- 매번 새 테이블인지 확인한다.
	check("반환값이 매 호출 새 테이블이다", a ~= b)

	a.m = 999
	a.e = 999
	local c = WarpConfig.cost(10)
	check(
		"반환값을 고쳐도 다음 호출이 오염되지 않는다",
		BigNum.eq(c, b),
		string.format("%s vs %s", BigNum.tostring(c), BigNum.tostring(b))
	)
end

do
	-- 진행 상태를 참조하지 않는다는 계약. 인자가 목표층 하나뿐이므로 구조적으로
	-- 보장되지만, 시그니처가 늘어나면 여기서 잡힌다.
	check("cost의 인자는 목표층 하나다", debug.info(WarpConfig.cost, "a") == 1)
end

-- ===== 경계 =========================================================================

do
	local ok, result = WarpConfig.canWarp(RICH, 1)
	check("1층 — 충분한 블럭스로 통과", ok == true and BigNum.eq(result, WarpConfig.cost(1)))

	local lastOk, lastResult = WarpConfig.canWarp(RICH, LAST_STAGE)
	check(
		string.format("마지막 층(%d) — 충분한 블럭스로 통과", LAST_STAGE),
		lastOk == true and BigNum.eq(lastResult, WarpConfig.cost(LAST_STAGE))
	)
end

do
	-- ⚠️ 1층에서만 본다. 비용이 커지면 "1 적은 값"이 BigNum에 표현되지 않아
	-- 뺀 결과가 원래 값과 같아진다(유효자리 12 — CLAUDE.md 정밀도 계약).
	-- 그러면 통과가 정답이 되어 이 테스트가 의미를 잃는다.
	-- 여기서 확인하려는 건 부등호가 >= 인지 > 인지지, 큰 수의 정밀도가 아니다.
	local cost = WarpConfig.cost(1)
	local justBelow = BigNum.sub(cost, BigNum.fromNumber(1))

	local belowOk, belowReason = WarpConfig.canWarp(justBelow, 1)
	check(
		"비용보다 1 적은 블럭스 → INSUFFICIENT_BLOX",
		belowOk == false and belowReason == WarpConfig.REASON_INSUFFICIENT_BLOX,
		tostring(belowReason)
	)

	local exactOk, exactResult = WarpConfig.canWarp(cost, 1)
	check(
		"비용과 정확히 같은 블럭스 → 통과 (경계는 이상, 초과 아님)",
		exactOk == true and BigNum.eq(exactResult, cost),
		tostring(exactResult)
	)

	local zeroOk, zeroReason = WarpConfig.canWarp(BigNum.new(0, 0), 1)
	check(
		"블럭스 0 → INSUFFICIENT_BLOX",
		zeroOk == false and zeroReason == WarpConfig.REASON_INSUFFICIENT_BLOX,
		tostring(zeroReason)
	)
end

-- ===== 거부 사유 ====================================================================

do
	local cases: { { label: string, stage: any } } = {
		{ label = "0층", stage = 0 },
		{ label = "음수", stage = -5 },
		{ label = "소수", stage = 1.5 },
		{ label = "nil", stage = nil },
		{ label = "문자열", stage = "3" },
		{ label = "nan", stage = 0 / 0 },
	}

	for _, case in ipairs(cases) do
		local ok, reason = WarpConfig.canWarp(RICH, case.stage :: any)
		check(
			string.format("%s → INVALID_STAGE", case.label),
			ok == false and reason == WarpConfig.REASON_INVALID_STAGE,
			tostring(reason)
		)
	end
end

do
	-- ⚠️ 블럭스를 충분히 준 채로 본다. 부족한 채로 물으면 INSUFFICIENT_BLOX가 먼저
	-- 나올 수 있어 판정 순서가 검증되지 않는다. 유저가 블럭스를 모아도 영영 못 가는
	-- 층인데 "부족하다"고 안내하면 거짓 안내가 된다.

	local ok, reason = WarpConfig.canWarp(RICH, LAST_STAGE + 1)
	check(
		string.format("마지막 층 + 1(%d) → STAGE_OUT_OF_RANGE", LAST_STAGE + 1),
		ok == false and reason == WarpConfig.REASON_STAGE_OUT_OF_RANGE,
		tostring(reason)
	)

	-- 범위 밖은 정상 거부다. assert/error로 터지면 안 된다.
	local didNotThrow = pcall(function()
		WarpConfig.canWarp(RICH, LAST_STAGE + 1000)
	end)
	check("범위 밖 층은 터지지 않고 거부된다", didNotThrow)

	-- 판정 순서: 범위 밖이면 블럭스가 0이어도 STAGE_OUT_OF_RANGE가 나온다.
	local poorOk, poorReason = WarpConfig.canWarp(BigNum.new(0, 0), LAST_STAGE + 1)
	check(
		"범위 밖은 블럭스 0이어도 STAGE_OUT_OF_RANGE (사유 우선순위)",
		poorOk == false and poorReason == WarpConfig.REASON_STAGE_OUT_OF_RANGE,
		tostring(poorReason)
	)
end

do
	-- 상한이 WorldConfig에서 파생되는가. 마지막 층까지는 전부 통과하고
	-- 그 다음부터 거부되는지 — 숫자를 적지 않고 확인한다.
	local allInRangeOk = true

	for stage = 1, LAST_STAGE do
		local ok = WarpConfig.canWarp(RICH, stage)
		if not ok then
			allInRangeOk = false
			break
		end
	end

	check("WorldConfig가 덮는 층은 전부 워프 가능", allInRangeOk)
	check("상한이 하드코딩이 아니라 WorldConfig 파생", not StageConfig.hasStage(LAST_STAGE + 1))
end

-- ===== cost의 계약 (canWarp과 다르다) ================================================

do
	-- cost는 수식, canWarp은 정책이다. 범위 밖 층에도 수식상의 값은 존재한다 —
	-- 여기서 터지면 월드 추가 전에 비용을 미리 보는 것조차 못 하게 된다.
	local ok, result = pcall(function()
		return WarpConfig.cost(LAST_STAGE + 1)
	end)
	check(
		"cost는 범위 밖 층에도 값을 돌려준다 (범위는 canWarp의 몫)",
		ok and BigNum.gt(result :: any, WarpConfig.cost(LAST_STAGE))
	)

	-- 반대로 스테이지 번호가 아닌 값은 호출자 버그다. 조용히 접지 않는다.
	for _, bad in ipairs({ 0, -1, 2.5 }) do
		local threw = not pcall(function()
			WarpConfig.cost(bad)
		end)
		check(string.format("cost(%s)는 터진다 (사유 코드가 필요하면 canWarp)", tostring(bad)), threw)
	end
end

-- ===== 사유 코드 자체 ================================================================

do
	check(
		"사유 코드 3개가 서로 다르다",
		WarpConfig.REASON_INVALID_STAGE ~= WarpConfig.REASON_STAGE_OUT_OF_RANGE
			and WarpConfig.REASON_STAGE_OUT_OF_RANGE ~= WarpConfig.REASON_INSUFFICIENT_BLOX
			and WarpConfig.REASON_INVALID_STAGE ~= WarpConfig.REASON_INSUFFICIENT_BLOX
	)

	-- 거부 시 반환되는 두 번째 값은 항상 문자열이다. BigNum이 섞여 나오면
	-- 호출자가 사유와 비용을 구분하지 못한다.
	local _, reason = WarpConfig.canWarp(BigNum.new(0, 0), 1)
	check("거부의 두 번째 반환값은 문자열이다", type(reason) == "string", type(reason))

	-- 통과 시에는 BigNum이다.
	local _, result = WarpConfig.canWarp(RICH, 1)
	check(
		"통과의 두 번째 반환값은 BigNum이다",
		type(result) == "table" and type(result.m) == "number" and type(result.e) == "number"
	)
end

do
	check("WarpConfig.validate", (pcall(WarpConfig.validate)))
end

print(string.format("[WarpConfigTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[WarpConfigTests] %d test(s) failed", failed))
end

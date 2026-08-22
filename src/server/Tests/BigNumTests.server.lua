--!strict
-- BigNum 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 1-1 검증 항목: 10^2000 정밀도 / 정규화 / 0·음수 / 직렬화 왕복
--
-- ============================================================================
-- 정밀도 계약 (실측). add()로 base+inc를 만들고 sub()로 base를 다시 빼서 inc를 복원하는
-- 시나리오를, base/inc의 지수 차이(diff = |base.e - inc.e|)를 바꿔가며 무작위/조합 샘플
-- 400~2000회로 직접 측정한 결과다 (src/shared/BigNum.lua 상단에도 같은 내용 요약).
--
--   diff <= 3   : 정확히 일치 (실측 100%) — 9번 섹션에서 BigNum.eq로 엄격 비교
--   diff 4~10   : 근사치. 상대오차가 diff 1당 대략 10배씩 커진다
--                 (diff=4 최악 관측 ~4e-8, diff=10 최악 관측 ~4e-2)
--                 — 9번 섹션에서 상대오차 허용치 10^(diff-11)로 검증 (넉넉한 안전마진 포함)
--   diff 11~12  : 불안정 구간. 0으로 소실되거나 예측 불가능하게 큰 오차가 남는 경우가
--                 섞여 있다 — 9번 섹션에서 이 구간은 값 검증 없이 건너뛴다
--   diff >= 13  : 작은 쪽 값이 확정적으로 0으로 소실된다 (정상 동작) — 9번 섹션에서
--                 restored == {m=0,e=0}으로 검증
--
-- ⚠️ 위 수치는 피연산자 가수가 이미 유효자리 12자리를 다 쓰고 있지는 않다는 전제에서
-- 측정했다 (이 게임의 실사용 범위 — Config 원값에서 몇 단계 안 되는 연산만 거친 값).
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)

type BigNumber = BigNum.BigNumber

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function approxEqBig(a: BigNumber, b: BigNumber, tol: number?): boolean
	tol = tol or 1e-9
	if a.m == 0 and b.m == 0 then
		return true
	end
	if a.e ~= b.e then
		return false
	end
	return math.abs(a.m - b.m) < (tol :: number)
end

-- 17자리 = double이 항상 원래 비트로 되돌아오는(round-trip-safe) 최대 유효자리수.
-- 정밀도 진단용 출력이라 이만큼 필요하다 — Formatter.lua의 실제 표시 로직(소수점 2자리)과는
-- 무관하며, 그쪽은 건드리지 않는다.
local function describe(a: BigNumber): string
	return string.format("{m=%.17g, e=%d}", a.m, a.e)
end

-- 1. normalize --------------------------------------------------------

do
	local n = BigNum.new(12345, 0) -- 12345 = 1.2345e4
	check("normalize: 12345 -> m in [1,10)", n.m >= 1 and n.m < 10, describe(n))
	check("normalize: 12345 -> e=4", n.e == 4, describe(n))
	check("normalize: 12345 -> m approx 1.2345", math.abs(n.m - 1.2345) < 1e-9, describe(n))
end

do
	local n = BigNum.new(0.00042, 0) -- 4.2e-4
	check("normalize: 0.00042 -> e=-4", n.e == -4, describe(n))
	check("normalize: 0.00042 -> m approx 4.2", math.abs(n.m - 4.2) < 1e-9, describe(n))
end

do
	local zero = BigNum.new(0, 999)
	check("normalize: zero forces e=0", zero.m == 0 and zero.e == 0, describe(zero))
end

-- 2. fromNumber ---------------------------------------------------------

do
	local n = BigNum.fromNumber(123.456)
	local roundTripped = n.m * (10 ^ n.e)
	check("fromNumber: 123.456 round-trips", math.abs(roundTripped - 123.456) < 1e-6, describe(n))
end

do
	local n = BigNum.fromNumber(0)
	check("fromNumber: 0 -> {m=0,e=0}", n.m == 0 and n.e == 0, describe(n))
end

do
	local n = BigNum.fromNumber(-5000)
	check("fromNumber: -5000 -> m=-5, e=3", n.m == -5 and n.e == 3, describe(n))
end

-- 3. add / sub ------------------------------------------------------------

do
	local sum = BigNum.add(BigNum.fromNumber(150), BigNum.fromNumber(20))
	check("add: 150 + 20 = 170", approxEqBig(sum, BigNum.fromNumber(170)), describe(sum))
end

do
	-- 지수 차이가 커서(2000 vs 0) 작은 값이 결과에 반영되지 않아야 한다.
	local huge = BigNum.pow(BigNum.fromNumber(10), 2000)
	local sum = BigNum.add(huge, BigNum.fromNumber(5))
	check("add: 10^2000 + 5 == 10^2000 (정밀도 한계 밖)", BigNum.eq(sum, huge), describe(sum))
end

do
	local a = BigNum.fromNumber(100)
	local zero = BigNum.sub(a, a)
	check("sub: 100 - 100 = 0 exactly", zero.m == 0 and zero.e == 0, describe(zero))
end

do
	local diff = BigNum.sub(BigNum.fromNumber(1), BigNum.fromNumber(5))
	check("sub: 1 - 5 = -4", approxEqBig(diff, BigNum.fromNumber(-4)), describe(diff))
end

-- 4. mul / div --------------------------------------------------------------

do
	local a = BigNum.pow(BigNum.fromNumber(10), 1000) -- 10^1000
	local b = BigNum.mul(a, a) -- 10^2000, 정확히 표현되어야 함
	check("mul: 10^1000 * 10^1000 = 10^2000 (m=1)", b.m == 1, describe(b))
	check("mul: 10^1000 * 10^1000 = 10^2000 (e=2000)", b.e == 2000, describe(b))
end

do
	local q = BigNum.div(BigNum.fromNumber(100), BigNum.fromNumber(4))
	check("div: 100 / 4 = 25", approxEqBig(q, BigNum.fromNumber(25)), describe(q))
end

do
	local ok = pcall(function()
		BigNum.div(BigNum.fromNumber(1), BigNum.fromNumber(0))
	end)
	check("div: 0으로 나누면 error", not ok)
end

-- 5. pow (10^2000 정밀도 핵심 케이스) -----------------------------------------

do
	local big = BigNum.pow(BigNum.fromNumber(10), 2000)
	check("pow: 10^2000 -> m=1", big.m == 1, describe(big))
	check("pow: 10^2000 -> e=2000", big.e == 2000, describe(big))
end

do
	local zeroPow = BigNum.pow(BigNum.fromNumber(5), 0)
	check("pow: x^0 = 1", zeroPow.m == 1 and zeroPow.e == 0, describe(zeroPow))
end

do
	local evenPow = BigNum.pow(BigNum.fromNumber(-2), 2)
	local oddPow = BigNum.pow(BigNum.fromNumber(-2), 3)
	check("pow: (-2)^2 = 4", approxEqBig(evenPow, BigNum.fromNumber(4)), describe(evenPow))
	check("pow: (-2)^3 = -8", approxEqBig(oddPow, BigNum.fromNumber(-8)), describe(oddPow))
end

-- 6. compare (lt/lte/eq/gt/gte) -----------------------------------------------

do
	local negBig = BigNum.fromNumber(-5000)
	local negSmall = BigNum.fromNumber(-1)
	local pos = BigNum.fromNumber(1)
	local zero = BigNum.fromNumber(0)

	check("compare: -5000 < -1", BigNum.lt(negBig, negSmall))
	check("compare: -1 > -5000", BigNum.gt(negSmall, negBig))
	check("compare: -1 < 1", BigNum.lt(negSmall, pos))
	check("compare: 0 < 1", BigNum.lt(zero, pos))
	check("compare: -1 < 0", BigNum.lt(negSmall, zero))
	check("compare: 0 <= 0", BigNum.lte(zero, zero))
	check("compare: 100 == 60+40", BigNum.eq(BigNum.fromNumber(100), BigNum.add(BigNum.fromNumber(60), BigNum.fromNumber(40))))
	check("compare: 10^2000 >= 10^1999", BigNum.gte(BigNum.pow(BigNum.fromNumber(10), 2000), BigNum.pow(BigNum.fromNumber(10), 1999)))
end

-- 7. serialize / deserialize ---------------------------------------------------

local function checkRoundTrip(name: string, value: BigNumber)
	local saved = BigNum.serialize(value)
	local restored = BigNum.deserialize(saved)
	check("serialize round-trip: " .. name, BigNum.eq(value, restored), describe(restored))
end

checkRoundTrip("100", BigNum.fromNumber(100))
checkRoundTrip("-4200", BigNum.fromNumber(-4200))
checkRoundTrip("0", BigNum.fromNumber(0))
checkRoundTrip("10^2000", BigNum.pow(BigNum.fromNumber(10), 2000))

do
	local ok = pcall(function()
		BigNum.serialize({ m = math.huge, e = 5 })
	end)
	check("serialize: inf mantissa -> error", not ok)
end

do
	local ok = pcall(function()
		BigNum.serialize({ m = 0 / 0, e = 5 })
	end)
	check("serialize: NaN mantissa -> error", not ok)
end

-- 8. 회귀: 부동소수점 정밀도(자릿수 손실) --------------------------------------------
-- 비슷한 크기의 두 값을 빼면(자릿수 손실) 재확대 과정에서 부동소수점 노이즈가
-- 상대오차로 증폭되던 버그. normalize()의 유효자리 반올림(A)과 add()의 자릿수 손실
-- 가드(C)로 고쳤다. pow도 normalize를 거치도록(B) 바꿔서 같은 보호를 받는다.

do
	-- 실제 버그 리포트 재현: (5000+1)-5000이 1.000000000000334류로 어긋나던 케이스
	local sum = BigNum.add(BigNum.new(5, 3), BigNum.new(1, 0)) -- 5000 + 1 = 5001
	local diff = BigNum.sub(sum, BigNum.new(5, 3)) -- 5001 - 5000
	check("회귀: (5000+1)-5000 == 1 exactly (버그 리포트 재현)", diff.m == 1 and diff.e == 0, describe(diff))
end

do
	local diff = BigNum.sub(BigNum.new(5.001, 3), BigNum.new(5, 3)) -- 5001 - 5000
	check("회귀: sub(5.001e3, 5e3) == 1 exactly", diff.m == 1 and diff.e == 0, describe(diff))
end

do
	-- (a+b)-b == a를 자릿수 조합을 바꿔가며 검증
	local cases: { { BigNumber } } = {
		{ BigNum.new(5, 3), BigNum.new(1, 0) }, -- 큰 정수 + 작은 정수
		{ BigNum.new(1, 0), BigNum.new(1, -5) }, -- 1 + 0.00001
		{ BigNum.pow(BigNum.new(1, 1), 50), BigNum.new(7, 3) }, -- 10^50 + 7000
		{ BigNum.new(3, 2), BigNum.new(9, 1) }, -- 300 + 90
		{ BigNum.new(-2, 4), BigNum.new(1, 1) }, -- 음수 + 양수
	}

	for i, case in ipairs(cases) do
		local a, b = case[1], case[2]
		local restored = BigNum.sub(BigNum.add(a, b), b)
		check(
			string.format("회귀: (a+b)-b == a (케이스 %d: a=%s, b=%s)", i, describe(a), describe(b)),
			BigNum.eq(restored, a),
			describe(restored)
		)
	end
end

do
	-- HP 시나리오: hp에서 정확히 hp만큼 데미지를 빼면 lte(result, 0) == true여야 한다.
	local hp = BigNum.new(1, 2) -- 100
	local damage = BigNum.new(1, 2) -- 100
	local result = BigNum.sub(hp, damage)
	check("회귀: HP == 데미지면 lte(result, 0) == true", BigNum.lte(result, BigNum.new(0, 0)), describe(result))
end

do
	-- 연산을 거쳐 "지저분해질 수 있는" 경로로 만든 HP도 정확한 데미지에는 0 이하로 판정돼야 한다.
	local hp = BigNum.sub(BigNum.add(BigNum.new(1, 2), BigNum.new(1, -6)), BigNum.new(1, -6)) -- 100 (연산 경유)
	local damage = BigNum.new(1, 2) -- 100
	local result = BigNum.sub(hp, damage)
	check("회귀: 연산으로 만든 HP도 정확한 데미지에 lte(result, 0) == true", BigNum.lte(result, BigNum.new(0, 0)), describe(result))
end

do
	-- 큰 값에 작은 값을 여러 번 더했다 같은 횟수만큼 빼면 원래 값과 정확히 같아야 한다.
	local original = BigNum.new(1, 6) -- 1,000,000
	local small = BigNum.new(1, -2) -- 0.01
	local roundTrips = 20

	local accumulated = original
	for _ = 1, roundTrips do
		accumulated = BigNum.add(accumulated, small)
	end
	for _ = 1, roundTrips do
		accumulated = BigNum.sub(accumulated, small)
	end

	check(
		string.format("회귀: 큰 값에 작은 값을 %d번 더했다 빼면 원래 값", roundTrips),
		BigNum.eq(accumulated, original),
		describe(accumulated)
	)
end

do
	-- pow 결과가 normalize를 거치는지(B): m이 항상 [1,10) 범위여야 한다.
	local powResults = {
		BigNum.pow(BigNum.new(2, 0), 10), -- 2^10 = 1024
		BigNum.pow(BigNum.new(3, 0), 7), -- 3^7 = 2187
		BigNum.pow(BigNum.new(1, 1), 500), -- 10^500
		BigNum.pow(BigNum.new(-1, 0), 5), -- (-1)^5 = -1
	}

	for i, result in ipairs(powResults) do
		local absM = math.abs(result.m)
		check(
			string.format("회귀: pow 결과가 normalize를 거쳐 m이 [1,10) 범위 (케이스 %d)", i),
			absM >= 1 and absM < 10,
			describe(result)
		)
	end
end

-- 9. 회귀: 양쪽 다 지저분한 값 (10 경계 확정 캐리) ------------------------------------
-- 8번 섹션의 회귀 테스트는 한쪽이 항상 깨끗한 정수/원본값이라 자릿수 손실이 "1 근처"
-- 로만 몰렸다. 실전(blox가 add를 여러 번 거치며 양쪽 다 지저분해지는 경우)에서는 결과가
-- "10 근처"에 걸릴 수도 있는데, 그건 일반 반올림의 좁은 올림 문턱(9.999999999995)을
-- 못 넘어서 지수가 하나 어긋난 채 남았다 — normalize()에 10 경계 확정 캐리를 추가해서 고침.

do
	-- 사용자 리포트 그대로: 5000에 1을 두 번 더해 5002를 만들고, 한 번만 더한 5001을 뺀다.
	-- 양쪽 다 add를 거친("지저분한") 값끼리의 뺄셈.
	local base = BigNum.new(5, 3) -- 5000
	local plus1 = BigNum.add(base, BigNum.new(1, 0)) -- 5000+1 = 5001
	local plus2 = BigNum.add(plus1, BigNum.new(1, 0)) -- 5001+1 = 5002
	local diff = BigNum.sub(plus2, plus1)
	check("회귀: (5000+1+1)-(5000+1) == 1, 양쪽 다 add를 거친 값", diff.m == 1 and diff.e == 0, describe(diff))
end

do
	-- 소수점이 있는 값끼리 반복 연산 후 비교: 1에 0.1을 5번 더한 값 - 1에 0.1을 3번 더한 값 = 0.2
	local a = BigNum.new(1, 0)
	for _ = 1, 5 do
		a = BigNum.add(a, BigNum.new(1, -1))
	end

	local b = BigNum.new(1, 0)
	for _ = 1, 3 do
		b = BigNum.add(b, BigNum.new(1, -1))
	end

	local diff = BigNum.sub(a, b)
	check(
		"회귀: (1+0.1*5) - (1+0.1*3) == 0.2, 양쪽 다 반복 add를 거친 값",
		BigNum.eq(diff, BigNum.new(2, -1)),
		string.format("a=%s b=%s diff=%s", describe(a), describe(b), describe(diff))
	)
end

do
	-- 같은 값을 다른 연산 경로로 만들어도 eq가 true여야 한다.
	local viaTwoAdds = BigNum.add(BigNum.add(BigNum.new(1, 3), BigNum.new(1, 0)), BigNum.new(1, 0)) -- (1000+1)+1
	local viaOneAdd = BigNum.add(BigNum.new(1, 3), BigNum.new(2, 0)) -- 1000+2
	check(
		"회귀: 1000+1+1 과 1000+2가 다른 경로로 계산돼도 eq == true",
		BigNum.eq(viaTwoAdds, viaOneAdd),
		string.format("viaTwoAdds=%s viaOneAdd=%s", describe(viaTwoAdds), describe(viaOneAdd))
	)
end

-- 정밀도 계약 상수 (파일 상단 실측 표와 동일). 여기 있는 숫자를 바꿀 거면 먼저
-- 실측을 다시 돌려서 파일 상단 주석과 BigNum.lua 상단 주석도 같이 갱신할 것.
local EXACT_DIFF_LIMIT = 3 -- diff <= 3: 정확히 일치
local APPROX_DIFF_LIMIT = 10 -- diff 4~10: 근사치 (아래 relativeError로 검증)
local UNSTABLE_DIFF_LIMIT = 12 -- diff 11~12: 불안정 구간, 값 검증 안 함
-- diff > UNSTABLE_DIFF_LIMIT: 확정적으로 0

-- restored가 expected(둘 다 BigNumber) 대비 얼마나 벗어났는지 상대오차로 계산.
-- expected의 지수 기준으로 맞춰서 비교한다.
local function relativeError(restored: BigNumber, expected: BigNumber): number
	if restored.m == 0 and expected.m == 0 then
		return 0
	end
	if restored.m == 0 then
		return 1
	end
	local restoredScaled = restored.m * (10 ^ (restored.e - expected.e))
	return math.abs(restoredScaled - expected.m) / math.abs(expected.m)
end

do
	-- 10 경계 스트레스: 양쪽 다 add를 거쳐 "지저분한" 값으로 만든 base에 작은 값을 더했다가
	-- 다시 base를 빼면, diff(지수 차이)에 따라 파일 상단 계약표대로 나와야 한다.
	-- 이번 리포트의 핵심 조건(양쪽 다 지저분한 큰 값끼리의 뺄셈)을 다양한 자릿수·부호
	-- 조합으로 반복 재현한다.
	local baseSeeds: { BigNumber } = {
		BigNum.new(5, 3), -- 5000
		BigNum.new(1, 7), -- 10,000,000
		BigNum.new(9.876, -3), -- 0.009876
		BigNum.new(1.234, 5), -- 123400
		BigNum.new(7, 0), -- 7
		BigNum.new(-3, 4), -- -30000
		BigNum.new(2.5, 10), -- 25,000,000,000
	}
	local increments: { BigNumber } = {
		BigNum.new(1, 0), -- 1
		BigNum.new(1, -3), -- 0.001
		BigNum.new(5, -1), -- 0.5
		BigNum.new(1, 2), -- 100
		BigNum.new(3, -6), -- 0.000003
	}

	for bi, seed in ipairs(baseSeeds) do
		-- base 자체를 실제로 add 한 번 거쳐서 "지저분한" 값으로 만든다. seed에 diff=3만큼
		-- (계약상 "정확" 구간) 떨어진 오프셋을 더하고 그대로 둔다 — add한 값을 곧바로
		-- 같은 값으로 다시 sub하면 diff<=3에서는 정확히 원복돼버려서(계약표 참고) "안
		-- 더러워지는" 게 지난 버전의 실수였다. 실전에서 blox가 누적 add로 지저분해지는
		-- 것과 같은 모양으로, 진짜 add 결과를 그대로 base로 쓴다.
		local dirtyBase = BigNum.add(seed, BigNum.new(7, seed.e - 3))

		for ii, inc in ipairs(increments) do
			local sum = BigNum.add(dirtyBase, inc)
			local restored = BigNum.sub(sum, dirtyBase)
			local diff = math.abs(dirtyBase.e - inc.e)
			local detail = string.format(
				"diff=%d base=%s dirtyBase=%s sum=%s restored=%s",
				diff,
				describe(seed),
				describe(dirtyBase),
				describe(sum),
				describe(restored)
			)

			if diff <= EXACT_DIFF_LIMIT then
				check(string.format("10 경계 스트레스 (base #%d, inc #%d, diff=%d): 정확히 일치", bi, ii, diff), BigNum.eq(restored, inc), detail)
			elseif diff <= APPROX_DIFF_LIMIT then
				local tolerance = 10 ^ (diff - 11) -- 계약표 "diff 1당 약 10배" + 안전마진
				local err = relativeError(restored, inc)
				check(
					string.format("10 경계 스트레스 (base #%d, inc #%d, diff=%d): 상대오차 %.3e <= %.3e", bi, ii, diff, err, tolerance),
					err <= tolerance,
					detail
				)
			elseif diff <= UNSTABLE_DIFF_LIMIT then
				-- 불안정 구간: 값을 검증하지 않는다. m/e가 finite한지만 확인해서 크래시나
				-- NaN/inf 같은 진짜 이상 상태는 여전히 잡는다.
				check(
					string.format("10 경계 스트레스 (base #%d, inc #%d, diff=%d): 불안정 구간 - finite 값만 확인", bi, ii, diff),
					restored.m == restored.m and restored.m ~= math.huge and restored.m ~= -math.huge,
					detail
				)
			else
				check(string.format("10 경계 스트레스 (base #%d, inc #%d, diff=%d): 확정적으로 0 소실", bi, ii, diff), restored.m == 0 and restored.e == 0, detail)
			end
		end
	end
end

-- 11. toRatio: 큰 수의 비율을 number로 푸는 순서 --------------------------------------
--
-- 이 함수가 따로 있는 이유가 곧 테스트할 내용이다. m * 10^e를 먼저 계산하면 10^2000이
-- inf가 되고 inf/inf = nan이 된다. 나눗셈을 BigNum 안에서 끝낸 뒤에 풀어야 살아남는다.
-- 파편 연출이 이 비율 하나로 큐브 개수를 역산하므로(Client/Net/RemoteReceiver), 여기가
-- 깨지면 화면에서 블록이 통째로 사라지거나 아예 안 부서진다.

do
	check("같은 값의 비는 1", BigNum.toRatio(BigNum.new(5, 100), BigNum.new(5, 100)) == 1)
	check("0의 비는 0", BigNum.toRatio(BigNum.new(0, 0), BigNum.new(5, 100)) == 0)

	-- 핵심 케이스. 둘 다 number로 풀면 inf라서 inf/inf = nan이 되는 크기다.
	local huge = BigNum.toRatio(BigNum.new(1, 2000), BigNum.new(2, 2000))
	check("10^2000 규모의 절반 = 0.5 (nan 아님)", math.abs(huge - 0.5) < 1e-9, tostring(huge))

	local quarter = BigNum.toRatio(BigNum.new(2.5, 500), BigNum.new(1, 501))
	check("2.5e500 / 1e501 = 0.25", math.abs(quarter - 0.25) < 1e-9, tostring(quarter))

	-- 양 끝 포화. number로 표현할 수 없는 구간이라 inf / 0으로 접는다.
	check("분자가 10^308배 이상 크면 inf로 포화", BigNum.toRatio(BigNum.new(1, 2000), BigNum.new(1, 1)) == math.huge)
	check("분모가 10^308배 이상 크면 0으로 포화", BigNum.toRatio(BigNum.new(1, 1), BigNum.new(1, 2000)) == 0)

	-- HP가 조금 깎인 정상 범위. 파편 개수 역산이 이 구간에서 돈다.
	local partial = BigNum.toRatio(BigNum.new(7.5, 1200), BigNum.new(1, 1201))
	check("7.5e1200 / 1e1201 = 0.75", math.abs(partial - 0.75) < 1e-9, tostring(partial))

	local ok = pcall(function()
		BigNum.toRatio(BigNum.new(1, 0), BigNum.new(0, 0))
	end)
	check("분모가 0이면 assert로 막힌다", ok == false)
end

-- 결과 -------------------------------------------------------------------

print(string.format("[BigNumTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BigNumTests] %d test(s) failed", failed))
end

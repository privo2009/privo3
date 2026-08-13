--!strict
-- BigNum 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 1-1 검증 항목: 10^2000 정밀도 / 정규화 / 0·음수 / 직렬화 왕복

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

local function describe(a: BigNumber): string
	return string.format("{m=%.10g, e=%d}", a.m, a.e)
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

-- 결과 -------------------------------------------------------------------

print(string.format("[BigNumTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BigNumTests] %d test(s) failed", failed))
end

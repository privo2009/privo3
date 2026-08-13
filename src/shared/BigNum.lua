--!strict
-- 표현: value = m * 10^e, 1.0 <= |m| < 10 (m == 0인 경우는 e도 0으로 고정)

export type BigNumber = { m: number, e: number }

local BigNum = {}

-- 정규화 상한선. Luau double은 유효숫자가 약 15~17자리이므로
-- 두 수의 지수 차이가 이보다 크면 작은 쪽은 결과에 반영되지 않는다.
local INSIGNIFICANT_EXPONENT_GAP = 17

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- m, e를 받아 표준형(1.0 <= |m| < 10, 0은 {0,0})으로 맞춘다.
function BigNum.normalize(m: number, e: number): BigNumber
	if m == 0 then
		return { m = 0, e = 0 }
	end

	local sign = 1
	if m < 0 then
		sign = -1
		m = -m
	end

	-- log10으로 대략적인 자리수를 맞추고, 부동소수점 오차는 아래 while로 보정한다.
	local shift = math.floor(math.log(m, 10))
	m = m / (10 ^ shift)
	e = e + shift

	while m >= 10 do
		m = m / 10
		e = e + 1
	end
	while m < 1 do
		m = m * 10
		e = e - 1
	end

	return { m = sign * m, e = e }
end

function BigNum.new(m: number, e: number?): BigNumber
	return BigNum.normalize(m, e or 0)
end

-- 일반 Luau number(유한값)를 BigNum으로 변환한다.
function BigNum.fromNumber(n: number): BigNumber
	assert(isFinite(n), "BigNum.fromNumber: n must be finite")
	if n == 0 then
		return { m = 0, e = 0 }
	end
	return BigNum.normalize(n, 0)
end

function BigNum.add(a: BigNumber, b: BigNumber): BigNumber
	if a.m == 0 then
		return BigNum.new(b.m, b.e)
	end
	if b.m == 0 then
		return BigNum.new(a.m, a.e)
	end

	local hi, lo = a, b
	if b.e > a.e then
		hi, lo = b, a
	end

	local diff = hi.e - lo.e
	if diff > INSIGNIFICANT_EXPONENT_GAP then
		return BigNum.new(hi.m, hi.e)
	end

	local combinedM = hi.m + lo.m / (10 ^ diff)
	return BigNum.normalize(combinedM, hi.e)
end

function BigNum.sub(a: BigNumber, b: BigNumber): BigNumber
	return BigNum.add(a, { m = -b.m, e = b.e })
end

function BigNum.mul(a: BigNumber, b: BigNumber): BigNumber
	if a.m == 0 or b.m == 0 then
		return { m = 0, e = 0 }
	end
	return BigNum.normalize(a.m * b.m, a.e + b.e)
end

function BigNum.div(a: BigNumber, b: BigNumber): BigNumber
	assert(b.m ~= 0, "BigNum.div: division by zero")
	if a.m == 0 then
		return { m = 0, e = 0 }
	end
	return BigNum.normalize(a.m / b.m, a.e - b.e)
end

-- a ^ n. n은 일반 Luau number(정수/실수). 밑이 음수면 n은 정수여야 한다.
function BigNum.pow(a: BigNumber, n: number): BigNumber
	if n == 0 then
		return { m = 1, e = 0 }
	end
	if a.m == 0 then
		return { m = 0, e = 0 }
	end

	local sign = a.m < 0 and -1 or 1
	if sign < 0 then
		assert(n % 1 == 0, "BigNum.pow: negative base requires an integer exponent")
	end

	-- log10(a) = e + log10(|m|) 를 이용해 지수 폭발 없이 거듭제곱을 계산한다.
	local log10Result = n * (a.e + math.log(math.abs(a.m), 10))
	local e = math.floor(log10Result)
	local m = 10 ^ (log10Result - e)

	if m >= 10 then
		m = m / 10
		e = e + 1
	elseif m < 1 then
		m = m * 10
		e = e - 1
	end

	local resultSign = 1
	if sign < 0 and n % 2 ~= 0 then
		resultSign = -1
	end

	return { m = resultSign * m, e = e }
end

-- -1 / 0 / 1 : a < b / a == b / a > b
local function compare(a: BigNumber, b: BigNumber): number
	if a.m == 0 and b.m == 0 then
		return 0
	end
	if a.m == 0 then
		return b.m > 0 and -1 or 1
	end
	if b.m == 0 then
		return a.m > 0 and 1 or -1
	end

	local aSign = a.m < 0 and -1 or 1
	local bSign = b.m < 0 and -1 or 1
	if aSign ~= bSign then
		return aSign < bSign and -1 or 1
	end

	if a.e ~= b.e then
		local smallerExponentIsA = a.e < b.e
		if aSign > 0 then
			return smallerExponentIsA and -1 or 1
		else
			-- 음수는 지수가 클수록(절대값이 클수록) 더 작은 값이다.
			return smallerExponentIsA and 1 or -1
		end
	end

	if a.m == b.m then
		return 0
	end
	return a.m < b.m and -1 or 1
end

function BigNum.lt(a: BigNumber, b: BigNumber): boolean
	return compare(a, b) < 0
end

function BigNum.lte(a: BigNumber, b: BigNumber): boolean
	return compare(a, b) <= 0
end

function BigNum.eq(a: BigNumber, b: BigNumber): boolean
	return compare(a, b) == 0
end

function BigNum.gt(a: BigNumber, b: BigNumber): boolean
	return compare(a, b) > 0
end

function BigNum.gte(a: BigNumber, b: BigNumber): boolean
	return compare(a, b) >= 0
end

-- DataStore 저장용. inf/nan은 프로필을 영구 손상시키므로 여기서 차단한다.
function BigNum.serialize(a: BigNumber): { m: number, e: number }
	assert(isFinite(a.m), "BigNum.serialize: mantissa is not finite")
	assert(isFinite(a.e), "BigNum.serialize: exponent is not finite")
	return { m = a.m, e = a.e }
end

function BigNum.deserialize(data: { m: number, e: number }): BigNumber
	assert(type(data) == "table" and type(data.m) == "number" and type(data.e) == "number", "BigNum.deserialize: invalid data")
	return BigNum.normalize(data.m, data.e)
end

function BigNum.tostring(a: BigNumber): string
	if a.m == 0 then
		return "0"
	end
	return string.format("%.6fe%+d", a.m, a.e)
end

return BigNum

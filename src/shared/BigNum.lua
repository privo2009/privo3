--!strict
-- 표현: value = m * 10^e, 1.0 <= |m| < 10 (m == 0인 경우는 e도 0으로 고정)
--
-- ============================================================================
-- 정밀도 계약 (실측, src/server/Tests/BigNumTests.server.lua 9번 섹션과 동일 기준).
-- add()/sub()로 두 값을 합쳤다가 그중 큰 쪽을 다시 빼서 복원할 때, 작은 쪽 값의 지수가
-- 큰 쪽보다 얼마나 작은지(diff = 큰 쪽 지수 - 작은 쪽 지수)에 따라 보장되는 정밀도가 다르다:
--
--   diff <= 3   : 정확히 일치 (실측 100%)
--   diff 4~10   : 근사치. 상대오차가 diff 1당 대략 10배씩 커진다
--                 (diff=4 최악 관측 ~4e-8, diff=10 최악 관측 ~4e-2) — 정확한 값 비교 금지,
--                 상대오차 허용치(대략 10^(diff-11))로만 검증할 것
--   diff 11~12  : 불안정 구간. 0으로 소실되거나 예측 불가능하게 큰 오차가 남는 경우가
--                 섞여 있다 — 이 구간의 결과는 어떤 형태로도 신뢰하지 말 것
--   diff >= 13  : 작은 쪽 값이 확정적으로 0으로 소실된다 (정상 동작)
--
-- ⚠️ 위 수치는 피연산자 가수가 이미 유효자리 12자리를 다 쓰고 있지는 않다는 전제에서
-- 측정했다. Config 원값에서 몇 단계 안 되는 연산만 거친 값(이 게임의 실사용 범위)에서는
-- 이 전제가 거의 항상 성립한다.
-- ============================================================================

export type BigNumber = { m: number, e: number }

local BigNum = {}

-- 정규화 상한선. Luau double은 유효숫자가 약 15~17자리이므로
-- 두 수의 지수 차이가 이보다 크면 작은 쪽은 결과에 반영되지 않는다.
local INSIGNIFICANT_EXPONENT_GAP = 17

-- 가수는 이 유효자리 수까지만 신뢰한다. double 자체의 정밀도(15~17자리)보다 여유 있게
-- 낮게 잡아서, 연산 결과를 정규화할 때마다 하위 자리의 부동소수점 잡음을 이 자리에서
-- 정리한다 (예: add로 비슷한 크기의 두 수를 뺀 뒤 재확대하면 원래는 무시할 만했던
-- ~1e-16 수준의 표현 오차가 결과 자릿수 기준 상대오차로 증폭되는데, 그 노이즈가 이
-- SIGNIFICANT_DIGITS 자리 밖으로 밀려나 있으면 반올림으로 사라진다).
-- 화면 표시는 소수점 2자리뿐이라(Shared/Formatter.lua) 12자리는 압도적으로 여유 있다.
local SIGNIFICANT_DIGITS = 12

-- add()에서 자릿수 손실(비슷한 크기끼리 뺄셈)이 일어났을 때 쓰는 "이 정도면 사실상 0"
-- 판단 기준. SIGNIFICANT_DIGITS자리까지만 신뢰한다는 건 곧, 더 큰 피연산자(hi.m) 기준
-- 상대 크기가 10^-(SIGNIFICANT_DIGITS-1)보다 작은 결과는 hi.m 자체에 이미 있던 반올림
-- 잡음과 구분이 안 된다는 뜻이다. 그래서 두 상수를 따로 튜닝하지 않고 이 관계식으로
-- 하나에서 유도한다 — SIGNIFICANT_DIGITS를 바꾸면 이 임계값도 같이 움직인다.
local CANCELLATION_RATIO = 10 ^ -(SIGNIFICANT_DIGITS - 1)

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- m(이미 [1,10) 범위로 정규화된 양수)을 유효자리 digits자리로 반올림한다.
local function roundToSignificantDigits(m: number, digits: number): number
	local factor = 10 ^ (digits - 1)
	return math.floor(m * factor + 0.5) / factor
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

	-- (C') 10 경계 확정 캐리. m이 10에 CANCELLATION_RATIO(= add()의 자릿수 손실 가드와
	-- 같은 상수) 안쪽으로 가까우면, 반올림을 거치지 않고 바로 다음 자릿수로 캐리한다.
	-- 이게 필요한 이유: 일반 반올림의 올림 문턱은 9.999999999995(0.5 ULP 폭)로 좁아서,
	-- 그보다 문턱을 살짝 못 넘는 노이즈(예: 9.999999999991)는 반올림으로도 안 걸러지고
	-- 오히려 9.99999999999로 반올림되며 지수가 하나 어긋난 채 남는다 — add에서 비슷한
	-- 크기의 두 값을 뺐는데 그 결과가 "거의 정확히 10배" 지점에 걸리는 경우 흔히 생긴다.
	-- CANCELLATION_RATIO는 "이 폭 밖은 노이즈와 구분 안 됨"이라는 같은 전제이므로 재사용한다.
	if 10 - m < 10 * CANCELLATION_RATIO then
		m = 1
		e = e + 1
	else
		-- (A) 유효자리 반올림. 여기서 하위 자리 노이즈를 정리해야 add/sub의 자릿수 손실이
		-- compare()까지 전파되지 않는다 (compare는 가수를 그대로 ==/<로 비교하기 때문).
		m = roundToSignificantDigits(m, SIGNIFICANT_DIGITS)
		if m >= 10 then
			-- 반올림 자체가 자리올림을 만든 일반적인 경우 (예: 9.9999999999996 -> 10.0000000000)
			m = m / 10
			e = e + 1
		end
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

	-- (C) 자릿수 손실 가드. 비슷한 크기의 두 수를 빼서(예: sub) combinedM이 hi.m에 비해
	-- CANCELLATION_RATIO보다 작아지면, 그건 진짜 유효한 값이 아니라 hi.m 자체에 이미
	-- 있던 반올림 잡음일 뿐이다. 이대로 정규화하면 재확대 과정에서 그 잡음이 그럴듯한
	-- 크기의 가짜 값으로 부풀려지므로(정규화 후에는 Schema.isBigNum도 못 걸러냄),
	-- 여기서 먼저 정확히 0으로 처리한다.
	if combinedM ~= 0 and math.abs(combinedM) < math.abs(hi.m) * CANCELLATION_RATIO then
		return { m = 0, e = 0 }
	end

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

-- a / b를 평범한 Luau number로 돌려준다. 비율(0~1 근처)이 필요한 곳 전용이다.
--
-- 왜 따로 있나: BigNum 값을 number로 풀려고 m * 10^e를 직접 계산하면 e가 조금만 커도
-- inf가 된다(10^2000). 그 상태로 hp/maxHp를 하면 inf/inf = nan이 되어 비율이 통째로
-- 깨진다. 나눗셈을 BigNum 안에서 먼저 끝내면 결과의 지수가 작아지므로 그 뒤에야
-- 안전하게 number로 풀 수 있다. 순서가 전부다.
--
-- 그래도 넘칠 수 있는 양 끝(a가 b보다 10^308배 이상 크거나 작은 경우)은 inf/0으로
-- 포화시킨다. 비율 용도에서 그 너머의 값은 의미가 없다.
function BigNum.toRatio(a: BigNumber, b: BigNumber): number
	assert(b.m ~= 0, "BigNum.toRatio: b는 0일 수 없다")

	local r = BigNum.div(a, b)
	if r.m == 0 then
		return 0
	end
	if r.e > 308 then
		if r.m > 0 then
			return math.huge
		end
		return -math.huge
	end
	if r.e < -308 then
		return 0
	end

	return r.m * 10 ^ r.e
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

	local resultSign = 1
	if sign < 0 and n % 2 ~= 0 then
		resultSign = -1
	end

	-- (B) 범위 보정([1,10) 진입)과 유효자리 반올림을 normalize에 위임한다. pow는 원래
	-- normalize를 거치지 않고 여기서 직접 m/e를 만들었어서, add/sub에는 적용되는 (A)의
	-- 반올림이 pow 결과에는 빠지는 구멍이 있었다.
	return BigNum.normalize(resultSign * m, e)
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

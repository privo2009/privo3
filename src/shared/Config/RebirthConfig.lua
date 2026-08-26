--!strict
-- 환생 비용과 획득 배수 계산.
--
--   획득 배수 = floor(보유 블럭스 ÷ BLOX_PER_REBIRTH)
--
-- 환생은 **소모**다 — 보유 블럭스를 전액 지불하고 나머지는 함께 소멸한다.
-- 규칙과 근거(왜 누적 블럭스 파생값이면 안 되는지 등)는 DESIGN.md "3. 화폐와 배수 > 환생"이
-- 원본이다. ⚠️ 근거를 여기로 복사하지 말 것.
--
-- ===== floor의 BigNum 성질 (⚠️ 반드시 읽을 것) ========================================
--
-- BigNum 가수는 유효자리가 유한하다(BigNum.lua의 SIGNIFICANT_DIGITS = 12).
-- 즉 값 하나가 표현할 수 있는 최소 단위는 10^(e - 11)이다. 그래서 몫의 지수가
-- 11 이상이 되면 **소수부가 애초에 표현되지 않는다** — 그 값은 이미 정수이고,
-- floor를 태우든 안 태우든 결과가 같다.
--
-- 결론: "1000 미만 나머지는 버린다"는 DESIGN 규칙이 실제로 관측되는 것은
-- **초반 몇 번의 환생뿐**이다. 블럭스가 커지면 버림이 안 먹는 것처럼 보이는데,
-- 그건 버림이 고장난 게 아니라 버릴 나머지가 애초에 값 안에 없기 때문이다.
-- ⚠️ 후반에 버림이 안 먹는다고 floor 구현을 의심하지 말 것. BigNum의 성질이다.
--
-- ⚠️ 임계 지수 11은 상수가 아니라 **유도값**이다. BigNum의 SIGNIFICANT_DIGITS가 바뀌면
--    같이 움직인다. 그 모듈이 상수를 export하지 않아 여기 적어두지만, ConfigTests가
--    실측으로 대조하므로 어긋나면 테스트가 잡는다 (그 케이스를 지우지 말 것).

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

local RebirthConfig = {}

-- 배수 1당 소모 블럭스. ⚠️ 이 값이 원본이다. 다른 파일에 1000을 적지 말 것.
RebirthConfig.BLOX_PER_REBIRTH = 1000

-- 이 지수 이상이면 값에 소수부가 존재할 수 없다 (위 "floor의 BigNum 성질" 참고).
-- BigNum의 유효자리 12 = 정수 1자리 + 소수 11자리 → 최소 단위가 10^(e-11)이므로
-- e >= 11에서 최소 단위가 1 이상이 된다.
local INTEGER_EXPONENT = 11

-- ⚠️ 상수 테이블을 재사용하지 않는다. BigNum 값은 평범한 테이블이라 호출자가 반환값을
-- 고치면 그 상수가 오염되고, 이후 모든 호출이 틀린 값을 받는다.
local function zero(): BigNumber
	return BigNum.new(0, 0)
end

-- BigNum 버림. 이 파일 전용 지역 함수다.
--
-- ⚠️ BigNum.lua 본체에 넣지 않은 이유: 그 모듈은 96개 테스트가 걸린 기반 모듈이고,
-- 여기서 필요한 것은 "환생 몫"이라는 한 용도뿐이다. 범용 floor로 승격할 만큼
-- 쓰임이 모이면 그때 옮긴다.
--
-- ⚠️ 음수는 다루지 않는다. 입력은 블럭스의 몫이고 블럭스는 CurrencyService가 음수로
-- 내려가지 않게 막는다(절대 규칙 2). 음수가 오면 그 자체가 상위 경로의 버그이므로
-- 조용히 0으로 접지 않고 여기서 터뜨린다 — 접으면 "환생했는데 배수가 안 올랐다"로
-- 증상만 남고 원인이 사라진다.
--
-- e < 11 구간은 double로 펼쳐 math.floor를 태운다. 참값이 정수인데
-- 표현 오차로 1이 덜 나올 수 있다(e≈8~10, 상대오차 1e-8 수준).
-- 보정하지 않는다 — 상류의 BigNum.div 결과 자체가 정확한 정수를
-- 보장하지 않고, "1에 가까우면 올림" 방식은 잘못 올릴 수 있다.
-- 확정적 버그를 막으려다 비확정적 버그를 만드는 교환이 된다.
-- 이 현상을 정밀도 버그로 진단해 BigNum.lua를 뜯지 말 것.
local function floorBig(value: BigNumber): BigNumber
	assert(value.m >= 0, string.format("RebirthConfig.floorBig: 음수는 다루지 않는다 (m=%s)", tostring(value.m)))

	if value.m == 0 then
		return zero()
	end

	-- 1 미만이다. 버리면 0.
	if value.e < 0 then
		return zero()
	end

	-- 소수부가 표현될 수 없는 크기다. 이미 정수이므로 그대로 돌려준다.
	if value.e >= INTEGER_EXPONENT then
		return BigNum.new(value.m, value.e)
	end

	-- 0 <= e < 11. 펼쳐도 최대 10^12 수준이라 double 정수 정밀도(2^53 ≈ 9e15) 안이다.
	local expanded = value.m * (10 ^ value.e)
	return BigNum.fromNumber(math.floor(expanded))
end

-- 지금 보유한 블럭스로 얻을 배수. 1000 미만 나머지는 버린다.
function RebirthConfig.getGainedRebirths(blox: BigNumber): BigNumber
	local quotient = BigNum.div(blox, BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH))
	return floorBig(quotient)
end

-- 환생이 가능한가. 얻을 배수가 1 이상이어야 한다.
--
-- ⚠️ "blox >= BLOX_PER_REBIRTH"로 따로 쓰지 말 것. 판정 기준이 두 곳이 되면
-- 경계에서 갈라진다(999.9999가 어느 쪽으로 접히는지는 floor가 정한다).
-- 여기는 getGainedRebirths의 결과만 본다.
function RebirthConfig.canRebirth(blox: BigNumber): boolean
	return BigNum.gte(RebirthConfig.getGainedRebirths(blox), BigNum.fromNumber(1))
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- (ClickService._pure / SpeedService._pure와 같은 패턴)
RebirthConfig._pure = {
	floorBig = floorBig,
	INTEGER_EXPONENT = INTEGER_EXPONENT,
}

function RebirthConfig.validate(): boolean
	assert(
		type(RebirthConfig.BLOX_PER_REBIRTH) == "number"
			and RebirthConfig.BLOX_PER_REBIRTH > 0
			and RebirthConfig.BLOX_PER_REBIRTH % 1 == 0,
		string.format(
			"RebirthConfig: BLOX_PER_REBIRTH(%s)는 양의 정수여야 함",
			tostring(RebirthConfig.BLOX_PER_REBIRTH)
		)
	)

	-- 경계가 실제로 그 값에 서 있는지. 상수만 보고 지나가면 floor 구현이 한 칸
	-- 어긋나 있어도(예: >= 대신 >) 통과한다.
	local cost = BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH)
	local justBelow = BigNum.sub(cost, BigNum.fromNumber(1))

	assert(
		RebirthConfig.canRebirth(cost),
		"RebirthConfig: BLOX_PER_REBIRTH 정확히 보유했을 때 환생이 가능해야 함"
	)
	assert(
		not RebirthConfig.canRebirth(justBelow),
		"RebirthConfig: BLOX_PER_REBIRTH보다 1 적을 때 환생이 불가능해야 함"
	)

	-- 임계 지수가 BigNum의 유효자리와 어긋나면 e가 그 사이에 있는 구간에서 버림이
	-- 조용히 건너뛰어진다. 여기서는 값만 확인하고, 실측 대조는 ConfigTests가 한다.
	assert(
		INTEGER_EXPONENT > 0,
		string.format("RebirthConfig: INTEGER_EXPONENT(%d)는 양수여야 함", INTEGER_EXPONENT)
	)

	return true
end

return RebirthConfig

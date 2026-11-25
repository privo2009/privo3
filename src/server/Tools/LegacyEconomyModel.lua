--!strict
-- 옛 경제 결정 모델(기준선) — 시뮬레이터 전용(지시서 #37). ⚠️ 게임 코드가 아니다. 게임에서는 지웠다.
--
-- #37에서 새 경제가 유일한 경제가 되며 게임의 옛 규칙(Shared/Config/RebirthConfig — 블럭스 1000마다 환생 +1 · 전액 소모 ·
-- 힘 배수 1 + n · 운동기구 해금 1 · 3 · 5 · 10 · 50 · 500 · 1e4 · 1e6 · 상점 펀치 데미지 업그레이드)을 지웠다.
-- SuccessRateReport의 결정 모델(ECON 고리 없이 돌 때 — SuccessRateReportTests · EconomyReport.reproduceV1 기준선)은
-- 그 옛 규칙으로 숫자가 정해져 있어, 그대로 재현되게 이 파일 하나로 옮겨 둔다(식 그대로 — 값을 바꾸지 않는다).
-- 새 경제 측정(EconomyReport — ECON 고리)은 이 파일을 쓰지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)

type BigNumber = BigNum.BigNumber

local LegacyEconomyModel = {}

-- 배수 1당 소모 블럭스. ⚠️ 이 값이 원본이다. 다른 파일에 1000을 적지 말 것.
LegacyEconomyModel.BLOX_PER_REBIRTH = 1000

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
	assert(value.m >= 0, string.format("LegacyEconomyModel.floorBig: 음수는 다루지 않는다 (m=%s)", tostring(value.m)))

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
-- mult = 얻는 환생 수 배수(2배 환생 게임패스 — 지시서 #16 S6). 없거나 1 이하 · 깨진 값이면 1.
-- ⚠️ 환생할 수 있는가(canRebirth)와 버려지는 양(getLeftover)은 배수와 상관없다 — 둘은 mult 없이 부른다.
function LegacyEconomyModel.getGainedRebirths(blox: BigNumber, mult: number?): BigNumber
	local quotient = BigNum.div(blox, BigNum.fromNumber(LegacyEconomyModel.BLOX_PER_REBIRTH))
	local gained = floorBig(quotient)
	if type(mult) == "number" and mult == mult and mult > 1 and mult < math.huge then
		return BigNum.mul(gained, BigNum.fromNumber(mult))
	end
	return gained
end

-- 환생이 가능한가. 얻을 배수가 1 이상이어야 한다.
--
-- ⚠️ "blox >= BLOX_PER_REBIRTH"로 따로 쓰지 말 것. 판정 기준이 두 곳이 되면
-- 경계에서 갈라진다(999.9999가 어느 쪽으로 접히는지는 floor가 정한다).
-- 여기는 getGainedRebirths의 결과만 본다.
function LegacyEconomyModel.canRebirth(blox: BigNumber): boolean
	return BigNum.gte(LegacyEconomyModel.getGainedRebirths(blox), BigNum.fromNumber(1))
end

-- 환생하면 아무것도 되지 않고 버려지는 양 = 보유 − 얻는 배수 × 단가 (BLOX_PER_REBIRTH 미만 나머지).
-- 환생 창("버려지는 양")과 시뮬레이터의 업그레이드 예산(지시서 #7 S5)이 같이 읽는다.
-- 블럭스가 아주 크면(지수 11 이상 — floorBig이 내림을 안 한다) 나머지가 표현되지 않아 0이다. 음수 잡음도 0으로 접는다.
function LegacyEconomyModel.getLeftover(blox: BigNumber): BigNumber
	local gained = LegacyEconomyModel.getGainedRebirths(blox)
	local spent = BigNum.mul(gained, BigNum.fromNumber(LegacyEconomyModel.BLOX_PER_REBIRTH))
	local leftover = BigNum.sub(blox, spent)
	if leftover.m < 0 then
		return zero()
	end
	return leftover
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- (ClickService._pure / SpeedService._pure와 같은 패턴)
LegacyEconomyModel._pure = {
	floorBig = floorBig,
	INTEGER_EXPONENT = INTEGER_EXPONENT,
}

function LegacyEconomyModel.validate(): boolean
	assert(
		type(LegacyEconomyModel.BLOX_PER_REBIRTH) == "number"
			and LegacyEconomyModel.BLOX_PER_REBIRTH > 0
			and LegacyEconomyModel.BLOX_PER_REBIRTH % 1 == 0,
		string.format(
			"LegacyEconomyModel: BLOX_PER_REBIRTH(%s)는 양의 정수여야 함",
			tostring(LegacyEconomyModel.BLOX_PER_REBIRTH)
		)
	)

	-- 경계가 실제로 그 값에 서 있는지. 상수만 보고 지나가면 floor 구현이 한 칸
	-- 어긋나 있어도(예: >= 대신 >) 통과한다.
	local cost = BigNum.fromNumber(LegacyEconomyModel.BLOX_PER_REBIRTH)
	local justBelow = BigNum.sub(cost, BigNum.fromNumber(1))

	assert(
		LegacyEconomyModel.canRebirth(cost),
		"LegacyEconomyModel: BLOX_PER_REBIRTH 정확히 보유했을 때 환생이 가능해야 함"
	)
	assert(
		not LegacyEconomyModel.canRebirth(justBelow),
		"LegacyEconomyModel: BLOX_PER_REBIRTH보다 1 적을 때 환생이 불가능해야 함"
	)

	-- 임계 지수가 BigNum의 유효자리와 어긋나면 e가 그 사이에 있는 구간에서 버림이
	-- 조용히 건너뛰어진다. 여기서는 값만 확인하고, 실측 대조는 ConfigTests가 한다.
	assert(
		INTEGER_EXPONENT > 0,
		string.format("LegacyEconomyModel: INTEGER_EXPONENT(%d)는 양수여야 함", INTEGER_EXPONENT)
	)

	return true
end


-- ===== 옛 힘 배수 · 운동기구 · 펀치 데미지(시뮬레이터 기준선) ============================================

-- 옛 힘 배수의 환생 항 = 1 + n(새 경제는 1.25^n — StrengthMultiplier)
function LegacyEconomyModel.rebirthTerm(rebirths: BigNumber): BigNumber
	return BigNum.add(BigNum.new(1, 0), rebirths)
end

-- 옛 운동기구 해금 환생 수(GymConfig 기구 순서 — 로벅스 전용 기구는 세지 않는다)
LegacyEconomyModel.GYM_UNLOCK_REBIRTHS = { BigNum.new(1, 0), BigNum.new(3, 0), BigNum.new(5, 0), BigNum.new(1, 1), BigNum.new(5, 1), BigNum.new(5, 2), BigNum.new(1, 4), BigNum.new(1, 6) }
function LegacyEconomyModel.gymUnlockedCount(rebirths: BigNumber): number
	local n = 0
	for i, need in ipairs(LegacyEconomyModel.GYM_UNLOCK_REBIRTHS) do
		if not BigNum.gte(rebirths, need) then
			break
		end
		n = i
	end
	return n
end

-- 옛 상점 펀치 데미지 업그레이드(UpgradeConfig에서 지웠다 — 효과 = 1 + 0.05 × 레벨 · 비용 100 × 1.15^레벨 · 최대 없음).
-- 표는 SuccessRateReport.withUpgradeOverride가 잠깐 고칠 수 있게 열어 둔다(UpgradeConfig.Upgrades와 같은 꼴)
LegacyEconomyModel.UPGRADES = {
	punchDamage = { exposed = true, maxLevel = nil :: number?, baseCost = BigNum.new(1, 2), costGrowth = 1.15, effectBase = 1, effectPerLevel = 0.05 },
} :: { [string]: any }

function LegacyEconomyModel.upgradeEffect(name: string, level: number): number
	local def = LegacyEconomyModel.UPGRADES[name]
	return def.effectBase + def.effectPerLevel * math.max(0, math.floor(level))
end

function LegacyEconomyModel.upgradeCanBuy(name: string, level: number, blox: BigNumber): (boolean, string?, BigNumber?)
	local def = LegacyEconomyModel.UPGRADES[name]
	if def.maxLevel ~= nil and level >= def.maxLevel then
		return false, "max_level", nil
	end
	local cost = BigNum.mul(def.baseCost, BigNum.pow(BigNum.fromNumber(def.costGrowth), level))
	if BigNum.lt(blox, cost) then
		return false, "insufficient_blox", cost
	end
	return true, nil, cost
end

return LegacyEconomyModel

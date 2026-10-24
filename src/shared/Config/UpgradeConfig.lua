--!strict
-- 블럭스 상점 업그레이드. 비용 곡선 · 레벨 상한 · 효과 식을 정의한다 — 게임(UpgradeService · 효과 적용 지점)과
-- 시뮬레이터(SuccessRateReport · StandardPathReport)와 상점 창이 **전부 이 파일의 함수를 부른다.**
-- 효과를 다른 곳에서 다시 계산하지 않는다 — 식이 두 곳에 있으면 어긋난다.
-- 결정과 근거는 DESIGN.md "7. 업그레이드 상점"이 원본이다(S0~S8, 2026-10-22 사람 결정).
--
-- ===== 효과는 더하기다 (S1) ===========================================================
--
--   효과(레벨) = 기본값 + 레벨당 증가량 × 레벨          ← 레벨에 선형
--   비용(레벨) = 기준 비용 × 증가율^레벨                ← 지수 (다음 레벨 하나를 사는 값)
--
-- ⚠️ 효과를 곱하기(증가율^레벨)로 바꾸지 말 것. HP 곡선이 지수라 둘이 맞물리면 성공률이 무너진다.
--
-- ===== 1차 상점 3종 (S0 · L3) ==========================================================
--
--   punchDamage  펀치 데미지 배수  1 + a × L      힘 계통. AttackService.computePunchDamage 한 곳에서만 곱한다 (S4)
--   punchSpeed   펀치 속도(회/초) BASE + b × L    b = (MAX − BASE) ÷ 최대 레벨 — 유도값, 따로 적지 않는다 (S2)
--   bloxGain     블럭스 획득 배수  1 + d × L      블럭스 계통. ChallengeService 수령 지급 한 곳에서만 곱한다 (S4)
--
-- 이동 속도(moveSpeed)는 2026-10-24 사람 결정 L3으로 지웠다 — 이동 속도는 레벨로만 오른다(LevelConfig.getMaxSpeed).
-- 그 항목에만 쓰이던 거부 사유 max_speed_reached · "최대 속도 도달" 잠금도 함께 지웠다. 스키마 v6이 프로필 키를 지운다.
--
-- 아우라 행운 · 타이틀 행운 · 펫 행운 · 펫 장착 슬롯은 **Phase 7** 항목이다. 시스템이 붙는 지시서에서 상점에 연다(G13):
--   titleLuck #10 · auraLuck #11 · petSlots · petLuck #12(E7 — 상점 6 · 7번째 줄, L3 뒤). 이제 비노출 항목은 없다.
--   행운 효과 = 1 + 레벨당 증가량 × 레벨(더하기 — S1과 같다). 그 뽑기의 행운 체인에 곱한다(RollService.computeLuck).
--   펫 장착 슬롯 효과 = 레벨 × 보너스 — 슬롯 수 식은 PetConfig.getSlots가 원본이다.
--
-- ===== TEMP =========================================================================
--
-- 최대 레벨 · 기준 비용 · 비용 증가율 · 펀치 데미지/블럭스 획득 증가량은 TEMP다. 지시서 #7 4단계
-- 시뮬레이션으로 목표 성공률을 지키는지 잰 값이고, 조정 이력은 DESIGN.md "7. 업그레이드 상점".

local BigNum = require(script.Parent.Parent.BigNum)
local AttackConfig = require(script.Parent.AttackConfig)

type BigNumber = BigNum.BigNumber

export type UpgradeName = string

export type UpgradeDef = {
	exposed: boolean, -- 상점에 보이는가. false = Phase 7 — 상점 비노출
	maxLevel: number?, -- nil = 무한
	baseCost: BigNumber, -- 0레벨 → 1레벨 비용
	costGrowth: number, -- 레벨당 비용 배율. 노출 항목은 1보다 커야 한다(비용 단조 증가)
	effectBase: number?, -- 0레벨 효과. nil이면 getEffectBase가 유도한다(punchSpeed)
	effectPerLevel: number?, -- 레벨당 효과 증가량. nil이면 getEffectPerLevel이 유도한다(punchSpeed)
}

local UpgradeConfig = {}

local Upgrades: { [string]: UpgradeDef } = {
	-- ===== 1차 상점 (S0) =====
	-- TEMP — 지시서 #7 4단계 조정값(U10). 첫 TEMP(기준 비용 10 · 데미지/블럭스 0.1)는 S5 시뮬레이션에서 17~25층 68.7%로
	-- 목표(40~55%)를 넘었다 → 기준 비용 100 · 데미지/블럭스 0.05로 53.8%. 이력 표는 DESIGN.md "7. 업그레이드 상점".
	punchDamage = { exposed = true, maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.15, effectBase = 1, effectPerLevel = 0.05 }, -- TEMP
	punchSpeed = { exposed = true, maxLevel = 20, baseCost = BigNum.new(1, 2), costGrowth = 1.2 }, -- TEMP(레벨·비용). 효과는 S2 유도
	-- moveSpeed(이동 속도) 삭제됨: L3(2026-10-24 사람 결정) — 이동 속도는 레벨로만 오른다(DESIGN.md "레벨" · 7장 L3)
	bloxGain = { exposed = true, maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.15, effectBase = 1, effectPerLevel = 0.05 }, -- TEMP
	-- radius(파괴 반경) 삭제됨: 데미지 오버플로우 도입으로 반경 개념 자체가 없어짐
	-- (DESIGN.md 2장 "데미지 오버플로우" / 7장 업그레이드 상점). 펀치 데미지와 중복이었다.

	-- ===== Phase 7 — 행운 · 슬롯 (G13: 행운 = 1 + 증가량 × 레벨, 2026-10-24 사람 결정) =====
	-- effectBase 1 = "행운 업그레이드 0레벨은 ×1"(행운 체인의 곱셈 항이라 0이면 확률이 0이 된다).
	auraLuck = { exposed = true, maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.25, effectBase = 1, effectPerLevel = 0.01 }, -- 소폭씩만 (롤 상품 보호). #11에서 노출
	titleLuck = { exposed = true, maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.25, effectBase = 1, effectPerLevel = 0.01 }, -- 소폭씩만. #10에서 노출
	petLuck = { exposed = true, maxLevel = 20, baseCost = BigNum.new(1, 2), costGrowth = 1.2, effectBase = 1, effectPerLevel = 0.02 }, -- 상한 있음. #12에서 노출(E7)
	petSlots = { exposed = true, maxLevel = 1, baseCost = BigNum.new(1, 4), costGrowth = 1, effectBase = 0, effectPerLevel = 1 }, -- 최대 +1. #12에서 노출(E7)
}

UpgradeConfig.Upgrades = Upgrades

-- 상점 창의 줄 순서이자 노출 항목 목록(S0). validate가 Upgrades의 exposed와 같은지 본다.
-- titleLuck은 지시서 #10, auraLuck은 #11, petSlots · petLuck은 #12에서 열었다(G13 · A11 · E7). moveSpeed는 #13에서 지웠다(L3) — 7줄.
UpgradeConfig.SHOP_ORDER = { "punchDamage", "punchSpeed", "bloxGain", "titleLuck", "auraLuck", "petSlots", "petLuck" }

-- 구매 거부 사유 코드. 문구는 UI가 매핑한다(UpgradeShopLogic.reasonText).
UpgradeConfig.REASON_INVALID_UPGRADE = "invalid_upgrade" -- 없는 항목 · 비노출 항목
UpgradeConfig.REASON_MAX_LEVEL = "max_level"
UpgradeConfig.REASON_INSUFFICIENT_BLOX = "insufficient_blox"
-- (max_speed_reached는 이동 속도 업그레이드와 함께 지웠다 — L3)

local function getDef(name: string): UpgradeDef
	local def = Upgrades[name]
	assert(def ~= nil, "UpgradeConfig: 존재하지 않는 업그레이드 - " .. tostring(name))
	return def
end

function UpgradeConfig.isExposed(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	local def = Upgrades[name]
	return def ~= nil and def.exposed
end

-- 레벨을 0..maxLevel 정수로 접는다. 프로필 값이 상한보다 크면(상한을 내린 뒤 등) 효과는 상한에서 멈춘다.
local function clampLevel(def: UpgradeDef, level: number): number
	local l = math.max(0, math.floor(level))
	if def.maxLevel ~= nil then
		l = math.min(l, def.maxLevel :: number)
	end
	return l
end

function UpgradeConfig.getEffectBase(name: string): number
	local def = getDef(name)
	if name == "punchSpeed" then
		return AttackConfig.PUNCH_SPEED_BASE
	end
	return def.effectBase :: number
end

-- S2: 펀치 속도 증가량은 (상한 − 기본) ÷ 최대 레벨. 최대 레벨에서 정확히 상한에 닿는다.
-- ⚠️ 매번 계산한다 — AttackConfig 값이 바뀌면(테스트의 흔들기 포함) 따라와야 한다.
function UpgradeConfig.getEffectPerLevel(name: string): number
	local def = getDef(name)
	if name == "punchSpeed" then
		return (AttackConfig.PUNCH_SPEED_MAX - AttackConfig.PUNCH_SPEED_BASE) / (def.maxLevel :: number)
	end
	return def.effectPerLevel :: number
end

-- 효과 = 기본값 + 증가량 × 레벨 (S1). 레벨은 0..maxLevel로 접는다.
function UpgradeConfig.getEffect(name: string, level: number): number
	local def = getDef(name)
	return UpgradeConfig.getEffectBase(name) + UpgradeConfig.getEffectPerLevel(name) * clampLevel(def, level)
end

function UpgradeConfig.isMaxLevel(name: string, level: number): boolean
	local def = getDef(name)
	return def.maxLevel ~= nil and level >= (def.maxLevel :: number)
end

-- level → level+1 비용.
function UpgradeConfig.getCostAtLevel(name: string, level: number): BigNumber
	local def = getDef(name)
	assert(level >= 0, "UpgradeConfig: level은 0 이상이어야 함")
	if def.maxLevel then
		assert(level < (def.maxLevel :: number), string.format("UpgradeConfig: %s는 이미 최대 레벨(%d)", name, def.maxLevel :: number))
	end

	return BigNum.mul(def.baseCost, BigNum.pow(BigNum.fromNumber(def.costGrowth), level))
end

-- 지금 레벨에서 다음 레벨을 살 수 있는가. 서버(UpgradeService)가 매 요청마다 다시 부르고,
-- 상점 창은 잠김 표시에 같은 함수를 쓴다. 돌려주는 값: (가능, 거부 사유 코드?, 비용?)
-- 사유 판정 순서: 잘못된 항목 → 최대 레벨 → 블럭스 부족.
function UpgradeConfig.canBuy(name: any, level: number, blox: BigNumber): (boolean, string?, BigNumber?)
	if not UpgradeConfig.isExposed(name) then
		return false, UpgradeConfig.REASON_INVALID_UPGRADE, nil
	end
	if UpgradeConfig.isMaxLevel(name, level) then
		return false, UpgradeConfig.REASON_MAX_LEVEL, nil
	end
	local cost = UpgradeConfig.getCostAtLevel(name, level)
	if BigNum.lt(blox, cost) then
		return false, UpgradeConfig.REASON_INSUFFICIENT_BLOX, cost
	end
	return true, nil, cost
end

function UpgradeConfig.validate(): boolean
	for name, def in pairs(Upgrades) do
		assert(type(def.exposed) == "boolean", "UpgradeConfig: " .. name .. "의 exposed는 boolean이어야 함")
		assert(BigNum.gt(def.baseCost, BigNum.new(0, 0)), "UpgradeConfig: " .. name .. "의 baseCost는 0보다 커야 함")
		assert(def.costGrowth >= 1, "UpgradeConfig: " .. name .. "의 costGrowth는 1 이상이어야 함")
		if def.maxLevel then
			assert((def.maxLevel :: number) > 0 and (def.maxLevel :: number) % 1 == 0, "UpgradeConfig: " .. name .. "의 maxLevel은 양의 정수여야 함")
		end
		if def.exposed then
			-- 비용 단조 증가: 노출 항목은 증가율 > 1. 단 최대 1레벨 항목(petSlots)은 살 레벨이 하나라 비용 열이 한 칸이다 — 1이어도 된다
			assert(def.costGrowth > 1 or def.maxLevel == 1, "UpgradeConfig: " .. name .. "의 costGrowth는 1보다 커야 함(비용 단조 증가)")
			assert(UpgradeConfig.getEffectPerLevel(name) > 0, "UpgradeConfig: " .. name .. "의 레벨당 효과는 0보다 커야 함")
		end
	end

	-- 노출 항목 = SHOP_ORDER (S0 · 지시서 #10에서 titleLuck 추가)
	local listed: { [string]: boolean } = {}
	for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		assert(Upgrades[name] ~= nil and Upgrades[name].exposed, "UpgradeConfig: SHOP_ORDER의 " .. name .. "이 노출 항목이 아님")
		listed[name] = true
	end
	for name, def in pairs(Upgrades) do
		if def.exposed then
			assert(listed[name], "UpgradeConfig: 노출 항목 " .. name .. "이 SHOP_ORDER에 없음")
		end
	end

	-- S2: 최대 레벨에서 펀치 속도 == 상한
	local speedDef = getDef("punchSpeed")
	assert(speedDef.maxLevel ~= nil, "UpgradeConfig: punchSpeed는 최대 레벨이 있어야 함(S2)")
	local topSpeed = UpgradeConfig.getEffect("punchSpeed", speedDef.maxLevel :: number)
	assert(
		math.abs(topSpeed - AttackConfig.PUNCH_SPEED_MAX) < 1e-9,
		string.format("UpgradeConfig: 최대 레벨 펀치 속도(%s)가 PUNCH_SPEED_MAX(%s)와 다름", tostring(topSpeed), tostring(AttackConfig.PUNCH_SPEED_MAX))
	)

	-- L3: 이동 속도 업그레이드는 없다(이동 속도는 레벨로만 — LevelConfig.getMaxSpeed). 되살아나면 여기서 걸린다
	assert(Upgrades.moveSpeed == nil, "UpgradeConfig: moveSpeed는 L3(2026-10-24 사람 결정)으로 지웠다 — 되살리려면 사람 결정")

	return true
end

return UpgradeConfig

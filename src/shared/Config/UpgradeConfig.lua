--!strict
-- 블럭스 상점 업그레이드. 여기서는 비용 곡선과 레벨 상한만 정의한다.
-- 레벨이 실제 수치(데미지량 등)에 어떻게 반영되는지는 서비스 레이어의 몫.
-- DESIGN.md 7. 업그레이드 상점 참고. "맥스" 개념이 있는 항목은 maxLevel을 지정한다.

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type UpgradeDef = {
	maxLevel: number?, -- nil = 무한
	baseCost: BigNumber,
	costGrowth: number, -- 레벨당 비용 배율 (1 이상)
	effectPerLevel: number, -- 레벨당 효과 증가량 (해석은 서비스 레이어)
}

local UpgradeConfig = {}

local Upgrades: { [string]: UpgradeDef } = {
	punchDamage = { maxLevel = nil, baseCost = BigNum.new(1, 1), costGrowth = 1.15, effectPerLevel = 0.1 },
	punchSpeed = { maxLevel = 20, baseCost = BigNum.new(1, 1), costGrowth = 1.2, effectPerLevel = 0.05 }, -- 상한 있음
	-- radius(파괴 반경) 삭제됨: 데미지 오버플로우 도입으로 반경 개념 자체가 없어짐
	-- (DESIGN.md 2장 "데미지 오버플로우" / 7장 업그레이드 상점). 펀치 데미지와 중복이었다.
	moveSpeed = { maxLevel = 20, baseCost = BigNum.new(1, 1), costGrowth = 1.2, effectPerLevel = 0.05 }, -- 상한 있음
	bloxGain = { maxLevel = nil, baseCost = BigNum.new(1, 1), costGrowth = 1.15, effectPerLevel = 0.1 },
	auraLuck = { maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.25, effectPerLevel = 0.01 }, -- 소폭씩만 (롤 상품 보호)
	titleLuck = { maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.25, effectPerLevel = 0.01 }, -- 소폭씩만
	petLuck = { maxLevel = 20, baseCost = BigNum.new(1, 2), costGrowth = 1.2, effectPerLevel = 0.02 }, -- 상한 있음
	petSlots = { maxLevel = 1, baseCost = BigNum.new(1, 4), costGrowth = 1, effectPerLevel = 1 }, -- 최대 +1
}

UpgradeConfig.Upgrades = Upgrades

function UpgradeConfig.getCostAtLevel(name: string, level: number): BigNumber
	local def = Upgrades[name]
	assert(def ~= nil, "UpgradeConfig: 존재하지 않는 업그레이드 - " .. tostring(name))
	assert(level >= 0, "UpgradeConfig: level은 0 이상이어야 함")
	if def.maxLevel then
		assert(level < (def.maxLevel :: number), string.format("UpgradeConfig: %s는 이미 최대 레벨(%d)", name, def.maxLevel :: number))
	end

	return BigNum.mul(def.baseCost, BigNum.pow(BigNum.fromNumber(def.costGrowth), level))
end

function UpgradeConfig.validate(): boolean
	for name, def in pairs(Upgrades) do
		assert(BigNum.gt(def.baseCost, BigNum.new(0, 0)), "UpgradeConfig: " .. name .. "의 baseCost는 0보다 커야 함")
		assert(def.costGrowth >= 1, "UpgradeConfig: " .. name .. "의 costGrowth는 1 이상이어야 함")
		if def.maxLevel then
			assert((def.maxLevel :: number) > 0, "UpgradeConfig: " .. name .. "의 maxLevel은 0보다 커야 함")
		end
	end

	return true
end

return UpgradeConfig

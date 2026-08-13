--!strict
-- 펫 뽑기(알)와 크래프팅 규칙. 알은 WorldConfig.eggPacks 인덱스로 참조된다.
-- 펫은 힘 배수를 전담하며 장착 효과는 합산(뽑기 3종 중 유일). 뽑기 판정은 서비스 레이어(Phase 7 PetService)의 몫.
-- 배열은 희귀도 낮은 순으로 정렬한다 (판정 시 배열 뒤에서부터 확인). DESIGN.md 6. 뽑기 3종 참고.

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type PetTierDef = {
	tier: number, -- 클수록 희귀
	name: string,
}

export type PetDef = {
	id: string,
	name: string,
	baseChance: number, -- 0~1, 희귀할수록 낮음
	tier: number, -- PetTierDef.tier 참조
	strengthMult: number, -- 힘 배수 전담 (장착 시 합산)
}

export type EggDef = {
	eggId: number,
	name: string,
	unlockWorld: number, -- WorldConfig 월드 번호
	rollCost: BigNumber,
	pets: { PetDef },
}

local PetConfig = {}

-- 동일 펫 3마리 -> 상위 등급 1마리로 크래프팅
PetConfig.CraftRequirement = 3

local Tiers: { PetTierDef } = {
	{ tier = 1, name = "일반" },
	{ tier = 2, name = "희귀" },
	{ tier = 3, name = "영웅" },
	{ tier = 4, name = "전설" },
}
PetConfig.Tiers = Tiers

-- 장착 슬롯: 기본 2 + 업그레이드 최대 +1 + 게임패스 +3 = 최대 6
PetConfig.BaseSlots = 2
PetConfig.UpgradeSlotBonus = 1
PetConfig.GamepassSlotBonus = 3
PetConfig.MaxSlots = PetConfig.BaseSlots + PetConfig.UpgradeSlotBonus + PetConfig.GamepassSlotBonus

-- 저장 공간: 기본 50 + 게임패스 +100
PetConfig.BaseStorage = 50
PetConfig.GamepassStorageBonus = 100

local Eggs: { [number]: EggDef } = {
	[1] = {
		eggId = 1,
		name = "나무 알",
		unlockWorld = 1,
		rollCost = BigNum.new(1, 2), -- 100 (임시)
		pets = {
			{ id = "egg1_common", name = "도토리", baseChance = 0.6, tier = 1, strengthMult = 1.05 },
			{ id = "egg1_rare", name = "다람쥐", baseChance = 0.3, tier = 2, strengthMult = 1.15 },
			{ id = "egg1_epic", name = "올빼미", baseChance = 0.09, tier = 3, strengthMult = 1.35 },
			{ id = "egg1_legendary", name = "고대나무정령", baseChance = 0.01, tier = 4, strengthMult = 1.7 },
		},
	},
	[2] = {
		eggId = 2,
		name = "돌 알",
		unlockWorld = 1,
		rollCost = BigNum.new(1, 3), -- 1K (임시)
		pets = {
			{ id = "egg2_common", name = "자갈", baseChance = 0.6, tier = 1, strengthMult = 1.1 },
			{ id = "egg2_rare", name = "골렘새끼", baseChance = 0.3, tier = 2, strengthMult = 1.25 },
			{ id = "egg2_epic", name = "크리스탈웜", baseChance = 0.09, tier = 3, strengthMult = 1.5 },
			{ id = "egg2_legendary", name = "산의정령", baseChance = 0.01, tier = 4, strengthMult = 1.9 },
		},
	},
	[3] = {
		eggId = 3,
		name = "철 알",
		unlockWorld = 1,
		rollCost = BigNum.new(1, 4), -- 10K (임시)
		pets = {
			{ id = "egg3_common", name = "톱니쥐", baseChance = 0.6, tier = 1, strengthMult = 1.15 },
			{ id = "egg3_rare", name = "기계매", baseChance = 0.3, tier = 2, strengthMult = 1.35 },
			{ id = "egg3_epic", name = "강철드레이크", baseChance = 0.09, tier = 3, strengthMult = 1.65 },
			{ id = "egg3_legendary", name = "기계신", baseChance = 0.01, tier = 4, strengthMult = 2.1 },
		},
	},
}
PetConfig.Eggs = Eggs

function PetConfig.getNextTier(tier: number): number?
	for _, t in ipairs(Tiers) do
		if t.tier == tier + 1 then
			return t.tier
		end
	end
	return nil -- 최고 등급, 더 이상 승급 불가
end

function PetConfig.validate(): boolean
	assert(PetConfig.CraftRequirement >= 2, "PetConfig: CraftRequirement는 2 이상이어야 함")
	assert(
		PetConfig.MaxSlots == PetConfig.BaseSlots + PetConfig.UpgradeSlotBonus + PetConfig.GamepassSlotBonus,
		"PetConfig: MaxSlots 계산이 어긋남"
	)

	local tierNumbers: { [number]: boolean } = {}
	for _, t in ipairs(Tiers) do
		tierNumbers[t.tier] = true
	end

	local ids = {}
	for id in pairs(Eggs) do
		table.insert(ids, id)
	end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local egg = Eggs[id]
		assert(egg.eggId == id, string.format("PetConfig: 알 %d의 eggId 불일치", id))
		assert(BigNum.gt(egg.rollCost, BigNum.new(0, 0)), string.format("PetConfig: 알 %d의 rollCost는 0보다 커야 함", id))
		assert(#egg.pets > 0, string.format("PetConfig: 알 %d에 펫이 없음", id))

		local chanceSum = 0
		for _, pet in ipairs(egg.pets) do
			assert(pet.baseChance > 0 and pet.baseChance <= 1, "PetConfig: " .. pet.id .. "의 baseChance가 (0,1] 범위를 벗어남")
			assert(tierNumbers[pet.tier], "PetConfig: " .. pet.id .. "의 tier(" .. tostring(pet.tier) .. ")가 Tiers에 없음")
			assert(pet.strengthMult >= 1, "PetConfig: " .. pet.id .. "의 strengthMult는 1 이상이어야 함")
			chanceSum = chanceSum + pet.baseChance
		end
		assert(chanceSum <= 1.0001, string.format("PetConfig: 알 %d의 baseChance 합이 1을 초과함 (%.4f)", id, chanceSum))
	end

	return true
end

return PetConfig

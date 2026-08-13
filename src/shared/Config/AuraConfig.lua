--!strict
-- 아우라 뽑기. 팩 1~5, 각 팩이 독립 테이블(3~5종)이며 팩마다 롤 비용이 1000배씩 늘어난다.
-- 뽑기 판정(순차 확률, 희귀도 높은 순)은 서비스 레이어(Phase 7 AuraService)의 몫 — 여기서는 데이터만 정의한다.
-- 배열은 희귀도 낮은 순으로 정렬한다 (판정 시 배열 뒤에서부터 확인). DESIGN.md 6. 뽑기 3종 참고.

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type AuraDef = {
	id: string,
	name: string,
	baseChance: number, -- 0~1, 희귀할수록 낮음
	strengthMult: number,
	damageMult: number,
}

export type AuraPackDef = {
	packId: number,
	unlockLifetimeBlox: BigNumber, -- 누적 블럭스 기준 해금
	rollCost: BigNumber,
	auras: { AuraDef },
}

local AuraConfig = {}

local Packs: { [number]: AuraPackDef } = {
	[1] = {
		packId = 1,
		unlockLifetimeBlox = BigNum.new(0, 0),
		rollCost = BigNum.new(1, 3), -- 1K
		auras = {
			{ id = "pack1_common", name = "반짝임", baseChance = 0.6, strengthMult = 1.1, damageMult = 1.05 },
			{ id = "pack1_rare", name = "불꽃", baseChance = 0.3, strengthMult = 1.3, damageMult = 1.15 },
			{ id = "pack1_epic", name = "번개", baseChance = 0.09, strengthMult = 1.6, damageMult = 1.3 },
			{ id = "pack1_legendary", name = "오로라", baseChance = 0.01, strengthMult = 2.2, damageMult = 1.6 },
		},
	},
	[2] = {
		packId = 2,
		unlockLifetimeBlox = BigNum.new(1, 6),
		rollCost = BigNum.new(1, 6), -- 1M
		auras = {
			{ id = "pack2_common", name = "돌풍", baseChance = 0.6, strengthMult = 2.2, damageMult = 1.6 },
			{ id = "pack2_rare", name = "빙하", baseChance = 0.3, strengthMult = 2.6, damageMult = 1.8 },
			{ id = "pack2_epic", name = "용암", baseChance = 0.09, strengthMult = 3.2, damageMult = 2.1 },
			{ id = "pack2_legendary", name = "혜성", baseChance = 0.01, strengthMult = 4.4, damageMult = 2.6 },
		},
	},
	[3] = {
		packId = 3,
		unlockLifetimeBlox = BigNum.new(1, 9),
		rollCost = BigNum.new(1, 9), -- 1B
		auras = {
			{ id = "pack3_common", name = "성운", baseChance = 0.6, strengthMult = 4.4, damageMult = 2.6 },
			{ id = "pack3_rare", name = "일식", baseChance = 0.3, strengthMult = 5.2, damageMult = 3.0 },
			{ id = "pack3_epic", name = "초신성", baseChance = 0.09, strengthMult = 6.4, damageMult = 3.6 },
			{ id = "pack3_legendary", name = "블랙홀", baseChance = 0.01, strengthMult = 8.8, damageMult = 4.6 },
		},
	},
	[4] = {
		packId = 4,
		unlockLifetimeBlox = BigNum.new(1, 12),
		rollCost = BigNum.new(1, 12), -- 1T
		auras = {
			{ id = "pack4_common", name = "차원균열", baseChance = 0.6, strengthMult = 8.8, damageMult = 4.6 },
			{ id = "pack4_rare", name = "시공왜곡", baseChance = 0.3, strengthMult = 10.4, damageMult = 5.4 },
			{ id = "pack4_epic", name = "붕괴", baseChance = 0.09, strengthMult = 12.8, damageMult = 6.6 },
			{ id = "pack4_legendary", name = "특이점", baseChance = 0.01, strengthMult = 17.6, damageMult = 8.6 },
		},
	},
	[5] = {
		packId = 5,
		unlockLifetimeBlox = BigNum.new(1, 15),
		rollCost = BigNum.new(1, 15), -- 1Qa
		auras = {
			{ id = "pack5_common", name = "태초", baseChance = 0.6, strengthMult = 17.6, damageMult = 8.6 },
			{ id = "pack5_rare", name = "종말", baseChance = 0.3, strengthMult = 20.8, damageMult = 10.2 },
			{ id = "pack5_epic", name = "영원", baseChance = 0.09, strengthMult = 25.6, damageMult = 12.6 },
			{ id = "pack5_legendary", name = "절대자", baseChance = 0.01, strengthMult = 35.2, damageMult = 16.6 },
		},
	},
}

AuraConfig.Packs = Packs

function AuraConfig.validate(): boolean
	local ids = {}
	for id in pairs(Packs) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local prevRollCost: BigNumber? = nil
	for _, id in ipairs(ids) do
		local pack = Packs[id]
		assert(pack.packId == id, string.format("AuraConfig: 팩 %d의 packId 불일치", id))
		assert(#pack.auras >= 3 and #pack.auras <= 5, string.format("AuraConfig: 팩 %d의 아우라 개수는 3~5종이어야 함 (현재 %d)", id, #pack.auras))

		local chanceSum = 0
		for _, aura in ipairs(pack.auras) do
			assert(aura.baseChance > 0 and aura.baseChance <= 1, "AuraConfig: " .. aura.id .. "의 baseChance가 (0,1] 범위를 벗어남")
			assert(aura.strengthMult >= 1, "AuraConfig: " .. aura.id .. "의 strengthMult는 1 이상이어야 함")
			chanceSum = chanceSum + aura.baseChance
		end
		assert(chanceSum <= 1.0001, string.format("AuraConfig: 팩 %d의 baseChance 합이 1을 초과함 (%.4f)", id, chanceSum))

		if prevRollCost then
			assert(BigNum.gt(pack.rollCost, prevRollCost), string.format("AuraConfig: 팩 %d의 rollCost가 이전 팩보다 크지 않음", id))
		end
		prevRollCost = pack.rollCost
	end

	return true
end

return AuraConfig

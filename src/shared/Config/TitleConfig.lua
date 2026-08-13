--!strict
-- 타이틀 뽑기. 비용은 블럭스 10 고정(지수 아님). 자동 롤 무료 제공, 힘/블럭스 배수 동시 부여.
-- 뽑기 판정(순차 확률, 희귀도 높은 순)은 서비스 레이어(Phase 7 TitleService)의 몫.
-- 배열은 희귀도 낮은 순으로 정렬한다 (판정 시 배열 뒤에서부터 확인). DESIGN.md 6. 뽑기 3종 참고.

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type TitleDef = {
	id: string,
	name: string,
	baseChance: number, -- 0~1, 희귀할수록 낮음
	strengthMult: number,
	bloxMult: number,
}

local TitleConfig = {}

local RollCost: BigNumber = BigNum.new(1, 1) -- 10, 고정 (지수 아님)
TitleConfig.RollCost = RollCost

local Titles: { TitleDef } = {
	{ id = "novice", name = "초보자", baseChance = 0.5, strengthMult = 1.02, bloxMult = 1.02 },
	{ id = "apprentice", name = "견습생", baseChance = 0.25, strengthMult = 1.05, bloxMult = 1.05 },
	{ id = "breaker", name = "파괴자", baseChance = 0.15, strengthMult = 1.1, bloxMult = 1.1 },
	{ id = "champion", name = "챔피언", baseChance = 0.07, strengthMult = 1.2, bloxMult = 1.2 },
	{ id = "legend", name = "레전드", baseChance = 0.025, strengthMult = 1.35, bloxMult = 1.35 },
	{ id = "mythic", name = "신화", baseChance = 0.005, strengthMult = 1.5, bloxMult = 1.5 },
}

TitleConfig.Titles = Titles

function TitleConfig.validate(): boolean
	assert(BigNum.gt(RollCost, BigNum.new(0, 0)), "TitleConfig: RollCost는 0보다 커야 함")

	local chanceSum = 0
	for _, title in ipairs(Titles) do
		assert(title.baseChance > 0 and title.baseChance <= 1, "TitleConfig: " .. title.id .. "의 baseChance가 (0,1] 범위를 벗어남")
		assert(title.strengthMult >= 1 and title.bloxMult >= 1, "TitleConfig: " .. title.id .. "의 배수는 1 이상이어야 함")
		chanceSum = chanceSum + title.baseChance
	end
	assert(chanceSum <= 1.0001, string.format("TitleConfig: baseChance 합이 1을 초과함 (%.4f)", chanceSum))

	return true
end

return TitleConfig

--!strict
-- 게임패스 / 개발자 상품 정의. id = 0은 미발급 상태를 뜻하며,
-- 실제 배포 시 Roblox 대시보드에서 발급받은 ID로 교체한다 (Phase 8, 대시보드 작업은 수동).
-- DESIGN.md 9. 수익화 참고.

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type GamepassDef = {
	id: number, -- Roblox GamepassId
	name: string,
	priceRobux: number,
}

export type StrengthMultTier = {
	multiplier: number,
	priceRobux: number,
	gamepassId: number,
}

export type DroneTier = {
	count: number,
	priceRobux: number,
	gamepassId: number,
}

export type DeveloperProductDef = {
	id: number, -- Roblox ProductId
	name: string,
	priceRobux: number,
	effect: { [string]: any },
}

local ShopConfig = {}

-- 일반 게임패스 -------------------------------------------------------------

local Gamepasses: { [string]: GamepassDef } = {
	autoClicker = { id = 0, name = "OP 자동 클리커", priceRobux = 79 },
	rebirth2x = { id = 0, name = "2x 환생", priceRobux = 99 },
	hatch3x = { id = 0, name = "3x 부화 알", priceRobux = 99 },
	petLuck2x = { id = 0, name = "2x 펫 행운", priceRobux = 99 },
	petStorage100 = { id = 0, name = "+100 펫 저장 공간", priceRobux = 49 },
	damage2x = { id = 0, name = "2x 데미지", priceRobux = 149 },
	petSlots3 = { id = 0, name = "+3 펫 장착", priceRobux = 199 },
	blox2x = { id = 0, name = "2x 블럭스", priceRobux = 199 },
	autoCollect = { id = 0, name = "자동 수령", priceRobux = 199 },
	auraLuck10x = { id = 0, name = "10x 아우라 행운", priceRobux = 299 },
	titleLuck10x = { id = 0, name = "10x 타이틀 행운", priceRobux = 299 },
	offline24h = { id = 0, name = "오프라인 24h", priceRobux = 349 },
	voidTrainingZone = { id = 0, name = "공허 훈련 구역", priceRobux = 799 },
	bundle = { id = 0, name = "게임패스 번들 (25% 할인)", priceRobux = 1499 },
}
ShopConfig.Gamepasses = Gamepasses

-- 힘 배수 계단: 반드시 "최고 단계만 적용". 절대 누적 곱셈 금지 (CLAUDE.md 절대 규칙).
local StrengthMultTiers: { StrengthMultTier } = {
	{ multiplier = 2, priceRobux = 3, gamepassId = 0 },
	{ multiplier = 4, priceRobux = 9, gamepassId = 0 },
	{ multiplier = 8, priceRobux = 29, gamepassId = 0 },
	{ multiplier = 16, priceRobux = 79, gamepassId = 0 },
	{ multiplier = 32, priceRobux = 249, gamepassId = 0 },
	{ multiplier = 64, priceRobux = 799, gamepassId = 0 },
	{ multiplier = 128, priceRobux = 1499, gamepassId = 0 },
	{ multiplier = 256, priceRobux = 2499, gamepassId = 0 },
	{ multiplier = 512, priceRobux = 3999, gamepassId = 0 },
	{ multiplier = 1024, priceRobux = 5999, gamepassId = 0 },
}
ShopConfig.StrengthMultTiers = StrengthMultTiers

-- 여러 단계를 소유해도 곱하지 않고, 소유한 것 중 가장 높은 배수 하나만 반환한다.
function ShopConfig.getActiveStrengthMultiplier(isGamepassOwned: (number) -> boolean): number
	local best = 1
	for _, tier in ipairs(StrengthMultTiers) do
		if tier.multiplier > best and isGamepassOwned(tier.gamepassId) then
			best = tier.multiplier
		end
	end
	return best
end

-- 드론: 동일한 "최고 단계만 적용" 패턴. 기본 1대 + 구매한 단계 중 최고 대수.
local DroneTiers: { DroneTier } = {
	{ count = 2, priceRobux = 149, gamepassId = 0 },
	{ count = 3, priceRobux = 299, gamepassId = 0 },
	{ count = 4, priceRobux = 599, gamepassId = 0 },
	{ count = 5, priceRobux = 999, gamepassId = 0 },
}
ShopConfig.DroneTiers = DroneTiers
ShopConfig.BaseDroneCount = 1
ShopConfig.MaxDroneCount = 5

function ShopConfig.getActiveDroneCount(isGamepassOwned: (number) -> boolean): number
	local best = ShopConfig.BaseDroneCount
	for _, tier in ipairs(DroneTiers) do
		if tier.count > best and isGamepassOwned(tier.gamepassId) then
			best = tier.count
		end
	end
	return best
end

-- 개발자 상품 -----------------------------------------------------------------

local DeveloperProducts: { [string]: DeveloperProductDef } = {
	luckyRoll5x = { id = 0, name = "5x 럭키 롤", priceRobux = 49, effect = { type = "roll", luckMultiplier = 5, rolls = 5 } },
	luckyRoll15x = { id = 0, name = "15x 럭키 롤", priceRobux = 149, effect = { type = "roll", luckMultiplier = 5, rolls = 15 } },
	superRoll5x = { id = 0, name = "5x 슈퍼 롤", priceRobux = 99, effect = { type = "roll", luckMultiplier = 100, rolls = 5 } },
	superRoll15x = { id = 0, name = "15x 슈퍼 롤", priceRobux = 249, effect = { type = "roll", luckMultiplier = 100, rolls = 15 } },
	strengthPotion = { id = 0, name = "힘 포션", priceRobux = 19, effect = { type = "potion", potion = "strength", durationSec = 900, multiplier = 2 } },
	victoryPotion = { id = 0, name = "승리 포션", priceRobux = 29, effect = { type = "potion", potion = "victory", durationSec = 900, multiplier = 2 } },
	potionBundle = { id = 0, name = "포션 번들", priceRobux = 999, effect = { type = "potionBundle", potions = { "strength", "victory" } } },
	bloxPackSmall = { id = 0, name = "블럭스 팩 소량", priceRobux = 99, effect = { type = "blox", amount = BigNum.new(1, 3) } }, -- 1K (임시)
	bloxPackLarge = { id = 0, name = "블럭스 팩 대량", priceRobux = 499, effect = { type = "blox", amount = BigNum.new(1, 5) } }, -- 100K (임시)
	warpPack = { id = 0, name = "워프 팩", priceRobux = 199, effect = { type = "warp", stages = 10 } },
}
ShopConfig.DeveloperProducts = DeveloperProducts

function ShopConfig.validate(): boolean
	for name, def in pairs(Gamepasses) do
		assert(def.priceRobux > 0, "ShopConfig: 게임패스 " .. name .. "의 가격은 0보다 커야 함")
	end

	local prevMult = 0
	for i, tier in ipairs(StrengthMultTiers) do
		assert(tier.multiplier > prevMult, string.format("ShopConfig: 힘 배수 계단 %d번째 배수가 이전보다 크지 않음", i))
		assert(tier.priceRobux > 0, string.format("ShopConfig: 힘 배수 계단 %d번째 가격이 0 이하", i))
		prevMult = tier.multiplier
	end

	local prevCount = ShopConfig.BaseDroneCount
	for i, tier in ipairs(DroneTiers) do
		assert(tier.count > prevCount, string.format("ShopConfig: 드론 단계 %d번째 대수가 이전보다 크지 않음", i))
		assert(tier.priceRobux > 0, string.format("ShopConfig: 드론 단계 %d번째 가격이 0 이하", i))
		prevCount = tier.count
	end
	assert(prevCount <= ShopConfig.MaxDroneCount, "ShopConfig: 드론 최대 대수를 초과함")

	for name, def in pairs(DeveloperProducts) do
		assert(def.priceRobux > 0, "ShopConfig: 개발자 상품 " .. name .. "의 가격은 0보다 커야 함")
		assert(type(def.effect) == "table" and type(def.effect.type) == "string", "ShopConfig: 개발자 상품 " .. name .. "의 effect.type이 없음")
	end

	return true
end

return ShopConfig

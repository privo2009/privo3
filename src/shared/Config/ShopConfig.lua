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

-- 드론 단계(2~5대)와 "오프라인 24h" 게임패스는 드론 폐기(2026-10-21 사람 결정)로 지웠다.
-- 마지막 정의는 태그 drone-archive-2026-10-21.

-- 개발자 상품 -----------------------------------------------------------------

local DeveloperProducts: { [string]: DeveloperProductDef } = {
	luckyRoll5x = { id = 0, name = "5x 럭키 롤", priceRobux = 49, effect = { type = "roll", luckMultiplier = 5, rolls = 5 } },
	luckyRoll15x = { id = 0, name = "15x 럭키 롤", priceRobux = 149, effect = { type = "roll", luckMultiplier = 5, rolls = 15 } },
	superRoll5x = { id = 0, name = "5x 슈퍼 롤", priceRobux = 99, effect = { type = "roll", luckMultiplier = 100, rolls = 5 } },
	superRoll15x = { id = 0, name = "15x 슈퍼 롤", priceRobux = 249, effect = { type = "roll", luckMultiplier = 100, rolls = 15 } },
	strengthPotion = { id = 0, name = "힘 포션", priceRobux = 19, effect = { type = "potion", potion = "strength", durationSec = 900, multiplier = 2 } },
	victoryPotion = { id = 0, name = "승리 포션", priceRobux = 29, effect = { type = "potion", potion = "victory", durationSec = 900, multiplier = 2 } },
	potionBundle = { id = 0, name = "포션 번들", priceRobux = 999, effect = { type = "potionBundle", potions = { "strength", "victory" } } },
	-- 블럭스 팩(소량 · 대량)은 2026-10-24 삭제했다(사람 결정 P1). 블럭스를 로벅스로 팔면 칭호 · 아우라 · 펫 뽑기가
	-- 유료 랜덤 아이템이 된다(DESIGN.md "6. 뽑기 3종 > 유료 랜덤 아이템 정책"). validate가 다시 들어오는 것을 막는다.
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

	for name, def in pairs(DeveloperProducts) do
		assert(def.priceRobux > 0, "ShopConfig: 개발자 상품 " .. name .. "의 가격은 0보다 커야 함")
		assert(type(def.effect) == "table" and type(def.effect.type) == "string", "ShopConfig: 개발자 상품 " .. name .. "의 effect.type이 없음")
		-- P1: 블럭스를 로벅스로 파는 상품 금지(CLAUDE.md 금지 사항)
		assert(def.effect.type ~= "blox", "ShopConfig: 개발자 상품 " .. name .. "이 블럭스를 판다 — 금지(P1, 뽑기가 유료 랜덤 아이템이 된다)")
	end
	for name, def in pairs(Gamepasses) do
		assert((def :: any).effect == nil or (def :: any).effect.type ~= "blox", "ShopConfig: 게임패스 " .. name .. "이 블럭스를 준다 — 금지(P1)")
	end

	return true
end

return ShopConfig

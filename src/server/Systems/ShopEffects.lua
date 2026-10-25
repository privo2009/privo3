--!strict
-- 로벅스 상품 효과의 서버 창구 (Phase 8 지시서 #16 4단계 · DESIGN 9장 S4 · S5 · S6 · S8 · S13).
--
-- 결합 자리(StrengthMultiplier · 1펀치 데미지 · 수령 블럭스 · computeLuck · 환생 수 · 자동 클릭)는 이 파일에서 **배수 하나씩**만 받는다.
-- 소유(GamepassService 세션 값) · 제한(PolicyGate) · 부스트(BoostService)를 합치는 일은 여기 한 곳에서 한다 —
-- 특히 "로벅스 행운 상품은 제한 유저면 1"(S13)이 자리마다 따로 쓰이면 하나가 빠진다.
--
-- 각 효과는 자기 자리에서 **한 번만** 곱해진다(S5). 이 파일은 곱하지 않는다 — 값을 돌려줄 뿐이다.
-- 판정 식은 ShopConfig(최고 단계만 · 높은 자동 클리커만 · 뽑기별 행운 패스)가 원본이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local GamepassService = require(script.Parent.GamepassService)
local PolicyGate = require(script.Parent.PolicyGate)
local BoostService = require(script.Parent.BoostService)

local ShopEffects = {}

-- 한 플레이어의 효과를 정하는 재료. 테스트는 이것을 직접 만든다.
export type View = {
	owns: (string) -> boolean,
	restricted: boolean, -- 로벅스 행운 상품을 끄는가(S13)
	boostOf: (string) -> number, -- 부스트 종류 → 지금 배수(없으면 1)
}

-- 부스트 배수. 로벅스 행운 상품인 부스트(행운 포션)는 제한 유저면 1.
local function boostMult(view: View, boostType: string): number
	local def = ShopConfig.BOOSTS[boostType]
	if def == nil or (def.paidRandom and view.restricted) then
		return 1
	end
	return view.boostOf(boostType)
end

-- 힘 계통: 계단(최고 단계 하나) · 힘 포션. StrengthMultiplier의 tierMult · potionMult에 넣는다.
local function strength(view: View): (number, number)
	return ShopConfig.strengthTierMult(view.owns), boostMult(view, "strength")
end

-- 1펀치 데미지: 2배 데미지 게임패스 · 데미지 포션. combineDamageMultiplier의 passMult · potionMult에 넣는다.
local function damage(view: View): (number, number)
	return ShopConfig.passMult("damage2x", view.owns), boostMult(view, "damage")
end

-- 수령 블럭스: 2배 블럭스 게임패스(S14 위험 기록). combineBloxMultiplier의 passMult.
local function blox(view: View): number
	return ShopConfig.passMult("blox2x", view.owns)
end

-- 얻는 환생 수 배수(S6).
local function rebirth(view: View): number
	return ShopConfig.passMult("rebirth2x", view.owns)
end

-- computeLuck 옵션: 행운 패스(그 뽑기 것) · 행운 포션. 둘 다 로벅스 행운 상품이라 제한 유저면 1(S13).
local function luckOptions(view: View, roll: string): { luckPassMult: number, boostMult: number }
	return {
		luckPassMult = if view.restricted then 1 else ShopConfig.luckPassMult(roll, view.owns),
		boostMult = boostMult(view, "luck"),
	}
end

-- 자동 클리커 초당 횟수(없으면 0, 둘 다 있으면 높은 쪽).
local function autoClickRate(view: View): number
	return ShopConfig.autoClickRate(view.owns)
end

ShopEffects._pure = {
	boostMult = boostMult,
	strength = strength,
	damage = damage,
	blox = blox,
	rebirth = rebirth,
	luckOptions = luckOptions,
	autoClickRate = autoClickRate,
}

-- ===== 플레이어 창구 ================================================================================

local function viewOf(player: Player): View
	return {
		owns = GamepassService.ownsFn(player),
		restricted = PolicyGate.isPaidRandomRestricted(player),
		boostOf = function(boostType: string): number
			return BoostService.getMult(player, boostType)
		end,
	}
end
ShopEffects.viewOf = viewOf

function ShopEffects.strength(player: Player): (number, number)
	return strength(viewOf(player))
end

function ShopEffects.damage(player: Player): (number, number)
	return damage(viewOf(player))
end

function ShopEffects.blox(player: Player): number
	return blox(viewOf(player))
end

function ShopEffects.rebirth(player: Player): number
	return rebirth(viewOf(player))
end

function ShopEffects.luckOptions(player: Player, roll: string): { luckPassMult: number, boostMult: number }
	return luckOptions(viewOf(player), roll)
end

function ShopEffects.autoClickRate(player: Player): number
	return autoClickRate(viewOf(player))
end

return ShopEffects

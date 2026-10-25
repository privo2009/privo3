--!strict
-- 로벅스 상품 효과의 서버 창구 (Phase 8 지시서 #16 4단계 · DESIGN 9장 S4 · S5 · S6 · S8 · S13).
--
-- 결합 자리(StrengthMultiplier · 1펀치 데미지 · 수령 블럭스 · computeLuck · 환생 수 · 자동 클릭)는 이 파일에서 **배수 하나씩**만 받는다.
-- 소유(GamepassService 세션 값) · 제한(PolicyGate) · 부스트(BoostService)를 View 하나로 모으는 일은 여기 한 곳에서 한다 —
-- 특히 "로벅스 행운 상품은 제한 유저면 1"(S13)이 자리마다 따로 쓰이면 하나가 빠진다.
-- 식은 Shared/ShopEffectsLogic이 원본이다(클라 표시가 같은 식을 쓴다). 각 효과는 자기 자리에서 **한 번만** 곱해진다(S5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local GamepassService = require(script.Parent.GamepassService)
local PolicyGate = require(script.Parent.PolicyGate)
local BoostService = require(script.Parent.BoostService)

local ShopEffects = {}

export type View = ShopEffectsLogic.View

-- 테스트 통로: 식 원본을 그대로 가리킨다(ShopEffectsTests가 View를 직접 만들어 넣는다).
ShopEffects._pure = ShopEffectsLogic

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
	return ShopEffectsLogic.strength(viewOf(player))
end

function ShopEffects.damage(player: Player): (number, number)
	return ShopEffectsLogic.damage(viewOf(player))
end

function ShopEffects.blox(player: Player): number
	return ShopEffectsLogic.blox(viewOf(player))
end

function ShopEffects.rebirth(player: Player): number
	return ShopEffectsLogic.rebirth(viewOf(player))
end

function ShopEffects.luckOptions(player: Player, roll: string): { luckPassMult: number, boostMult: number }
	return ShopEffectsLogic.luckOptions(viewOf(player), roll)
end

function ShopEffects.autoClickRate(player: Player): number
	return ShopEffectsLogic.autoClickRate(viewOf(player))
end

return ShopEffects

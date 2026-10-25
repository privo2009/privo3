--!strict
-- 로벅스 상품 효과의 순수 식 (Phase 8 지시서 #16). 서버(Server/Systems/ShopEffects — 실제 배수)와 클라(창 · HUD 표시)가 같은 식을 쓴다.
--
-- 재료는 View 하나다: owns(키) · restricted(로벅스 행운 상품을 끄는가 — S13) · boostOf(부스트 종류 → 지금 배수).
--   서버는 GamepassService · PolicyGate · BoostService로 만들고, 클라는 PlayerState shop 요약으로 만든다(fromSummary).
-- 판정 식(최고 단계만 · 높은 자동 클리커만 · 뽑기별 행운 패스)은 ShopConfig가 원본이다. 이 파일은 고르고 합칠 뿐이다.
-- 각 효과는 자기 결합 자리에서 **한 번만** 곱해진다(S5) — 여기서 곱해 넘기지 않는다(행운의 패스 × 포션만 표시용 luckMult가 곱한다).

local ShopConfig = require(script.Parent.Config.ShopConfig)

local ShopEffectsLogic = {}

export type View = {
	owns: (string) -> boolean,
	restricted: boolean,
	boostOf: (string) -> number,
}

-- 부스트 배수. 로벅스 행운 상품인 부스트(행운 포션)는 제한 유저면 1.
function ShopEffectsLogic.boostMult(view: View, boostType: string): number
	local def = ShopConfig.BOOSTS[boostType]
	if def == nil or (def.paidRandom and view.restricted) then
		return 1
	end
	return view.boostOf(boostType)
end

-- 힘 계통: (계단 최고 단계 하나, 힘 포션). StrengthMultiplier의 tierMult · potionMult.
function ShopEffectsLogic.strength(view: View): (number, number)
	return ShopConfig.strengthTierMult(view.owns), ShopEffectsLogic.boostMult(view, "strength")
end

-- 1펀치 데미지: (2배 데미지 게임패스, 데미지 포션). combineDamageMultiplier의 passMult · potionMult.
function ShopEffectsLogic.damage(view: View): (number, number)
	return ShopConfig.passMult("damage2x", view.owns), ShopEffectsLogic.boostMult(view, "damage")
end

-- 수령 블럭스: 2배 블럭스 게임패스(S14 위험 기록). combineBloxMultiplier의 passMult.
function ShopEffectsLogic.blox(view: View): number
	return ShopConfig.passMult("blox2x", view.owns)
end

-- 얻는 환생 수 배수(S6).
function ShopEffectsLogic.rebirth(view: View): number
	return ShopConfig.passMult("rebirth2x", view.owns)
end

-- computeLuck 옵션: 행운 패스(그 뽑기 것) · 행운 포션. 둘 다 로벅스 행운 상품이라 제한 유저면 1(S13).
function ShopEffectsLogic.luckOptions(view: View, roll: string): { luckPassMult: number, boostMult: number }
	return {
		luckPassMult = if view.restricted then 1 else ShopConfig.luckPassMult(roll, view.owns),
		boostMult = ShopEffectsLogic.boostMult(view, "luck"),
	}
end

-- 표시용: 업그레이드 뒤에 곱해지는 행운(패스 × 포션). 창이 "지금 확률"을 그릴 때 쓴다(서버 computeLuck과 같은 항).
function ShopEffectsLogic.luckMult(view: View, roll: string): number
	local o = ShopEffectsLogic.luckOptions(view, roll)
	return o.luckPassMult * o.boostMult
end

-- 자동 클리커 초당 횟수(없으면 0, 둘 다 있으면 높은 쪽).
function ShopEffectsLogic.autoClickRate(view: View): number
	return ShopConfig.autoClickRate(view.owns)
end

-- PlayerState shop 요약 → View(클라). 요약이 없거나 깨졌으면 "보유 없음 · 제한 · 부스트 없음"(확인 전과 같다).
function ShopEffectsLogic.fromSummary(shop: any): View
	local set: { [string]: boolean } = {}
	local boosts: { [string]: number } = {}
	local restricted = true
	if type(shop) == "table" then
		if type(shop.gamepasses) == "table" then
			for _, key in ipairs(shop.gamepasses) do
				if type(key) == "string" then
					set[key] = true
				end
			end
		end
		if type(shop.boosts) == "table" then
			for _, b in ipairs(shop.boosts) do
				if type(b) == "table" and type(b.type) == "string" and type(b.mult) == "number" and b.mult > (boosts[b.type] or 1) then
					boosts[b.type] = b.mult
				end
			end
		end
		restricted = shop.paidRandomRestricted ~= false
	end
	return {
		owns = function(key: string): boolean
			return set[key] == true
		end,
		restricted = restricted,
		boostOf = function(boostType: string): number
			return boosts[boostType] or 1
		end,
	}
end

return ShopEffectsLogic

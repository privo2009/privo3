--!strict
-- 확률 보기 — 행운 패스를 더하면(지시서 #28 O1 · docs/POLICY_CHECK.md). 칭호 창 · 펫 창이 같이 쓴다. 순수 모듈.
--
-- 공식 paid-random-items "확률을 바꾸는 상품은 사기 전에 설명" — 상품 줄의 "배수 + 가장 귀한 것 하나"를 넘어
-- 결과 전부의 전후 확률을 창 표에서 바꿔 보인다. 판정 로직 · 확률 값은 그대로다(여기는 표시만).
--
--   passKey(roll)               그 뽑기의 행운 패스 키(ShopConfig luckPass — 칭호 titleLuck10x · 펫 petLuck2x)
--   canPreview(roll, shop)      토글을 보일까: 패스가 있고 · 제한 유저가 아니고(R4) · 아직 안 가졌다(가졌으면 "지금"에 이미 들어 있다)
--   luck(base, roll, shop, on)  on이고 보일 수 있으면 base × 패스 배수 — 서버 computeLuck의 luckPassMult 자리(패스는 뽑기마다 하나라
--                               안 가졌을 때 그 자리는 1이다). 그 밖에는 base 그대로
--   toggleText(roll, on, luck)  "확률: 지금 · 행운 ×N" ↔ "확률: ×M 패스 있으면 · 행운 ×N"
-- base = 그 창의 luckOf(업그레이드 × 가진 패스 × 켜진 포션 — 이미 가진 것 · 켜진 것은 "지금"에 들어 있다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local OddsPreviewLogic = {}

function OddsPreviewLogic.passKey(roll: string): string?
	for key, def in pairs(ShopConfig.Products) do
		if def.effect.type == "luckPass" and def.effect.roll == roll then
			return key
		end
	end
	return nil
end

function OddsPreviewLogic.passMult(roll: string): number
	local key = OddsPreviewLogic.passKey(roll)
	local def = if key ~= nil then ShopConfig.get(key) else nil
	return if def ~= nil then def.effect.mult or 1 else 1
end

function OddsPreviewLogic.canPreview(roll: string, shop: any): boolean
	local key = OddsPreviewLogic.passKey(roll)
	if key == nil then
		return false
	end
	local view = ShopEffectsLogic.fromSummary(shop)
	return not view.restricted and not view.owns(key)
end

function OddsPreviewLogic.luck(base: number, roll: string, shop: any, on: boolean?): number
	if on == true and OddsPreviewLogic.canPreview(roll, shop) then
		return base * OddsPreviewLogic.passMult(roll)
	end
	return base
end

function OddsPreviewLogic.toggleText(roll: string, on: boolean?, luck: number): string
	local l = string.format("%.2f", luck)
	if on == true then
		return Locale.t("odds.preview.pass", { mult = string.format("%g", OddsPreviewLogic.passMult(roll)), luck = l })
	end
	return Locale.t("odds.preview.now", { luck = l })
end

return OddsPreviewLogic

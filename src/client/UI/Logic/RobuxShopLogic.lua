--!strict
-- 상점 창 로벅스 탭의 줄 · 상태 · 문구 (Phase 8 지시서 #16 5단계 — docs/UI.md "지시서 #16"). 순수 모듈 —
-- 화면은 Screens/Window/UpgradeShopWindow(로벅스 탭).
--
-- 값은 원본에서 나온다: 가격 · ID는 ShopConfig, 이름 · 설명은 Strings(Names.product — 지시서 #L1 K6), 보유 · 제한 · 부스트는 서버 PlayerState shop 요약(Store "shop"),
-- 확률은 RollOdds(서버 RollLogic이 낳는 실제 등장 확률 — P3). 화면 값은 안내일 뿐이고 실제 구매 판정은 서버가 한다.
--
--   줄 순서   힘 배수 계단 한 줄 → ShopConfig.GAMEPASS_ORDER(게임패스 13)
--   상태      owned = "보유 중"(회색) · notRegistered = ID 0 "준비 중"(회색) · max = 계단 최고 단계 보유 · buy = 초록 버튼 + 가격
--   행운 줄   확률 변화를 숫자로: "<가장 귀한 것> 1.0% → 9.6%"(S13 — 구매 전에 숫자로 보인다)
--   제한 유저 로벅스 행운 상품(paidRandom) 줄을 숨긴다(S13)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

type BigNumber = BigNum.BigNumber

local RobuxShopLogic = {}

RobuxShopLogic.BUY_TEXT = Locale.t("common.buy")
RobuxShopLogic.OWNED_TEXT = Locale.t("shop.owned")
RobuxShopLogic.NOT_REGISTERED_TEXT = Locale.t("shop.comingSoon")
RobuxShopLogic.MAX_TEXT = Locale.t("shop.ladder.maxButton")
RobuxShopLogic.LADDER_KEY = "strengthLadder" -- 계단 줄의 화면 키(상품 키가 아니다 — 누르면 다음 단계 키로 요청한다)

export type State = "buy" | "owned" | "notRegistered" | "max"

export type Row = {
	key: string, -- 화면 키(게임패스 키 또는 LADDER_KEY)
	buyKey: string?, -- 누르면 요청할 상품 키(살 수 없으면 nil)
	title: string,
	detail: string, -- 설명 한 줄 또는 확률 변화
	state: State,
	buttonText: string,
	footText: string, -- 버튼 아래: 가격("49 R$") 또는 ""
	canBuy: boolean,
}

function RobuxShopLogic.priceText(priceRobux: number): string
	return string.format("%d R$", priceRobux)
end

-- 확률 변화의 기준 뽑기(그 뽑기에서 지금 굴리는 것): 칭호 = 전체 표, 아우라 = 고른 팩, 펫 = 열린 알 중 가장 높은 것.
export type Context = {
	upgrades: any?, -- Store "upgrades"
	auras: any?, -- Store "auras"(selectedPack)
	lifetimeBlox: BigNumber?,
	pets: any?, -- Store "pets"(world)
}

local function tiersFor(roll: string, ctx: Context): { any }?
	if roll == "title" then
		return TitleConfig.Titles
	elseif roll == "aura" then
		local packId = if type(ctx.auras) == "table" and type(ctx.auras.selectedPack) == "number" then ctx.auras.selectedPack else 1
		local pack = AuraConfig.Packs[packId] or AuraConfig.Packs[1]
		return if pack ~= nil then pack.auras else nil
	elseif roll == "pet" then
		local world = if type(ctx.pets) == "table" and type(ctx.pets.world) == "number" then ctx.pets.world else 1
		local unlocked = PetConfig.getUnlockedEggs(ctx.lifetimeBlox or BigNum.new(0, 0), world)
		local eggId = unlocked[#unlocked] or 1
		local egg = PetConfig.Eggs[eggId]
		return if egg ~= nil then egg.pets else nil
	end
	return nil
end

local UPGRADE_OF: { [string]: string } = { title = "titleLuck", aura = "auraLuck", pet = "petLuck" }

-- 그 뽑기의 지금 행운(업그레이드 × 이미 가진 패스 · 활성 행운 포션 — 서버 computeLuck과 같은 항).
function RobuxShopLogic.currentLuck(roll: string, ctx: Context, shop: any): number
	local name = UPGRADE_OF[roll]
	local levels = ctx.upgrades
	local raw = if type(levels) == "table" then levels[name] else nil
	local level = if type(raw) == "number" and raw == raw and raw >= 0 then math.floor(raw) else 0
	return UpgradeConfig.getEffect(name, level) * ShopEffectsLogic.luckMult(ShopEffectsLogic.fromSummary(shop), roll)
end

-- "<가장 귀한 것> a% → b%". 사면 행운이 mult배가 된다(같은 뽑기의 실제 등장 확률 — RollOdds).
function RobuxShopLogic.oddsText(roll: string, mult: number, ctx: Context, shop: any): string
	local tiers = tiersFor(roll, ctx)
	if tiers == nil or #tiers == 0 then
		return ""
	end
	local luck = RobuxShopLogic.currentLuck(roll, ctx, shop)
	local before = RollOdds.percentages(RollOdds.distribution(tiers, luck))
	local after = RollOdds.percentages(RollOdds.distribution(tiers, luck * mult))
	local top = tiers[#tiers]
	return string.format("%s %s → %s", Names.rollItem(roll, top.id), before[#tiers], after[#tiers]) -- percentages가 "%"를 붙인다
end

local function passRow(key: string, owns: (string) -> boolean, ctx: Context, shop: any): Row
	local def = ShopConfig.get(key) :: ShopConfig.ProductDef
	local detail = Names.productDesc(key)
	if def.effect.type == "luckPass" then
		detail = RobuxShopLogic.oddsText(def.effect.roll, def.effect.mult, ctx, shop)
	end
	local state: State = if owns(key) then "owned" elseif def.id == 0 then "notRegistered" else "buy"
	return {
		key = key,
		buyKey = if state == "buy" then key else nil,
		title = Names.product(key),
		detail = detail,
		state = state,
		buttonText = if state == "owned" then RobuxShopLogic.OWNED_TEXT elseif state == "notRegistered" then RobuxShopLogic.NOT_REGISTERED_TEXT
			else RobuxShopLogic.BUY_TEXT,
		footText = if state == "owned" then "" else RobuxShopLogic.priceText(def.priceRobux),
		canBuy = state == "buy",
	}
end

-- 계단 한 줄: "힘 배수 계단  지금 ×N" · 다음 단계 이름 · 가격. 최고 단계 보유면 "최고 단계".
local function ladderRow(owns: (string) -> boolean): Row
	local current, nextKey = ShopConfig.strengthTierState(owns)
	local nowMult = ShopConfig.strengthTierMult(owns)
	local title = Locale.t("shop.ladder.title", { mult = nowMult })
	if nextKey == nil then
		return {
			key = RobuxShopLogic.LADDER_KEY,
			buyKey = nil,
			title = title,
			detail = Locale.t("shop.ladder.top", { name = Names.product(current :: string) }),
			state = "max",
			buttonText = RobuxShopLogic.MAX_TEXT,
			footText = "",
			canBuy = false,
		}
	end
	local def = ShopConfig.get(nextKey) :: ShopConfig.ProductDef
	local state: State = if def.id == 0 then "notRegistered" else "buy"
	return {
		key = RobuxShopLogic.LADDER_KEY,
		buyKey = if state == "buy" then nextKey else nil,
		title = title,
		detail = Locale.t("shop.ladder.next", { name = Names.product(nextKey) }),
		state = state,
		buttonText = if state == "notRegistered" then RobuxShopLogic.NOT_REGISTERED_TEXT else RobuxShopLogic.BUY_TEXT,
		footText = RobuxShopLogic.priceText(def.priceRobux),
		canBuy = state == "buy",
	}
end

-- 로벅스 탭 줄 전부. shop = Store "shop". 제한 유저면 로벅스 행운 상품 줄이 빠진다.
function RobuxShopLogic.rows(shop: any, ctx: Context?): { Row }
	local view = ShopEffectsLogic.fromSummary(shop)
	local c: Context = ctx or {}
	local out: { Row } = { ladderRow(view.owns) }
	for _, key in ipairs(ShopConfig.GAMEPASS_ORDER) do
		local def = ShopConfig.get(key) :: ShopConfig.ProductDef
		if not (def.paidRandom and view.restricted) then
			table.insert(out, passRow(key, view.owns, c, shop))
		end
	end
	return out
end

-- PurchaseResult → 화면 문구(토스트 · 상태 줄). 이름은 ShopConfig. 보여 줄 것이 없으면 nil(프롬프트를 띄웠다).
function RobuxShopLogic.resultText(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	local def = ShopConfig.get(payload.key)
	local name = if def ~= nil then Names.product(payload.key) else Locale.t("shop.product")
	if payload.phase == "finished" then
		if payload.ok then
			return Locale.t("shop.purchased", { name = name })
		end
		return nil -- 프롬프트를 닫았다 — 알리지 않는다(유저가 직접 닫은 것)
	end
	if payload.ok then
		return nil
	end
	return RobuxShopLogic.reasonText(tostring(payload.reason))
end

-- 사유 코드 → 문구. 코드는 서버 PurchaseRequestService.REASON_* · MarketplaceGateway.
function RobuxShopLogic.reasonText(code: string): string
	if code == "not_registered" or code == "not_available" then
		return Locale.t("shop.reason.not_registered")
	elseif code == "already_owned" then
		return Locale.t("shop.reason.already_owned")
	elseif code == "restricted" then
		return Locale.t("shop.reason.restricted")
	elseif code == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif code == "invalid_key" then
		return Locale.t("shop.reason.invalid_key")
	elseif code == "prompt_failed" then
		return Locale.t("shop.reason.prompt_failed")
	end
	return Locale.t("shop.reason.failed")
end

return RobuxShopLogic

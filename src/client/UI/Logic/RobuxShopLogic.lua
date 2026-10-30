--!strict
-- 상점 창 로벅스 탭의 줄 · 상태 · 문구 (Phase 8 지시서 #16 5단계 — docs/UI.md "지시서 #16"). 순수 모듈 —
-- 화면은 Screens/Window/UpgradeShopWindow(로벅스 탭).
--
-- 값은 원본에서 나온다: 가격 · ID는 ShopConfig, 이름 · 설명은 Strings(Names.product — 지시서 #L1 K6), 보유 · 제한 · 부스트는 서버 PlayerState shop 요약(Store "shop"),
-- 확률은 RollOdds(서버 RollLogic이 낳는 실제 등장 확률 — P3). 화면 값은 안내일 뿐이고 실제 구매 판정은 서버가 한다.
--
--   줄 순서   힘 배수 계단 한 줄 → ShopConfig.GAMEPASS_ORDER(게임패스 13)
--   상태      owned = "보유 중"(회색) · notRegistered = ID 0 "준비 중"(회색) · max = 계단 최고 단계 보유 · buy = 초록 버튼 + 가격
--             ownedHigher = 더 높은 것을 가져 살 필요가 없다 "보유(상위)"(R2 — OP 자동 클리커 보유 중 기본 자동 클리커, 지시서 #17).
--             계단(R1)은 한 줄에 다음 단계만 보이므로 가진 단계 이하가 화면에 나오지 않는다
--   행운 줄   확률 변화를 숫자로: "<가장 귀한 것> 1.0% → 9.6%"(S13 — 구매 전에 숫자로 보인다)
--   제한 유저 로벅스 행운 상품(paidRandom) 줄을 숨긴다(S13)
--
-- 지시서 #17: 같은 줄 모양을 창별 상품 버튼(아우라 · 펫 · 칭호 창 — windowRows)과 상점 "포션" 묶음(potionRows)이 쓴다.
--   개발자 상품 줄  보유가 없다 — 등록됐으면 늘 "구매". 럭키 · 슈퍼 롤 줄의 설명은 그 롤의 행운으로 바뀌는 확률(아우라 고른 팩)
--   포션 줄        "<이름>  보유 N" · 설명 · 구매(초록) + 켜기(하늘 — 보유 0이면 잠김). 켜기는 Net/PotionClient(useKey = 포션 종류)
--   로벅스 탭 순서  계단 → 포션 묶음(포션 3 + 번들) → 게임패스(GAMEPASS_ORDER)

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
RobuxShopLogic.OWNED_HIGHER_TEXT = Locale.t("shop.ownedHigher")
RobuxShopLogic.NOT_REGISTERED_TEXT = Locale.t("shop.comingSoon")
RobuxShopLogic.MAX_TEXT = Locale.t("shop.ladder.maxButton")
RobuxShopLogic.LADDER_KEY = "strengthLadder" -- 계단 줄의 화면 키(상품 키가 아니다 — 누르면 다음 단계 키로 요청한다)

export type State = "buy" | "owned" | "ownedHigher" | "notRegistered" | "max"

export type Row = {
	key: string, -- 화면 키(게임패스 키 또는 LADDER_KEY)
	buyKey: string?, -- 누르면 요청할 상품 키(살 수 없으면 nil)
	title: string,
	detail: string, -- 설명 한 줄 또는 확률 변화
	state: State,
	buttonText: string,
	footText: string, -- 버튼 아래: 가격("49 R$") 또는 ""
	canBuy: boolean,
	-- 둘째 버튼(포션 줄의 "켜기" — 지시서 #17). 없는 줄은 useKey = nil · useText "" · canUse false
	useKey: string?,
	useText: string,
	canUse: boolean,
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
	local state: State = if owns(key) then "owned"
		elseif ShopConfig.ownedHigher(key, owns) ~= nil then "ownedHigher"
		elseif def.id == 0 then "notRegistered"
		else "buy"
	return {
		key = key,
		buyKey = if state == "buy" then key else nil,
		title = Names.product(key),
		detail = detail,
		state = state,
		buttonText = if state == "owned" then RobuxShopLogic.OWNED_TEXT
			elseif state == "ownedHigher" then RobuxShopLogic.OWNED_HIGHER_TEXT
			elseif state == "notRegistered" then RobuxShopLogic.NOT_REGISTERED_TEXT
			else RobuxShopLogic.BUY_TEXT,
		footText = if state == "owned" or state == "ownedHigher" then "" else RobuxShopLogic.priceText(def.priceRobux),
		canBuy = state == "buy",
		useKey = nil,
		useText = "",
		canUse = false,
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
			useKey = nil,
			useText = "",
			canUse = false,
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
		useKey = nil,
		useText = "",
		canUse = false,
	}
end

-- ===== 개발자 상품 · 포션 줄 (지시서 #17) =========================================================

RobuxShopLogic.USE_TEXT = Locale.t("shop.potion.use")
RobuxShopLogic.ROBUX_TAB_TEXT = Locale.t("shop.tab.robux") -- 아우라 · 펫 창의 로벅스 탭(상점 탭과 같은 낱말)

-- 개발자 상품 한 줄(보유 없음). 럭키 · 슈퍼 롤은 설명 대신 그 롤의 행운으로 바뀌는 아우라 확률.
local function productRow(key: string, ctx: Context, shop: any): Row
	local def = ShopConfig.get(key) :: ShopConfig.ProductDef
	local detail = Names.productDesc(key)
	if def.effect.type == "rollCredit" then
		detail = RobuxShopLogic.oddsText("aura", def.effect.luckMult, ctx, shop)
	end
	local state: State = if def.id == 0 then "notRegistered" else "buy"
	return {
		key = key,
		buyKey = if state == "buy" then key else nil,
		title = Names.product(key),
		detail = detail,
		state = state,
		buttonText = if state == "notRegistered" then RobuxShopLogic.NOT_REGISTERED_TEXT else RobuxShopLogic.BUY_TEXT,
		footText = RobuxShopLogic.priceText(def.priceRobux),
		canBuy = state == "buy",
		useKey = nil,
		useText = "",
		canUse = false,
	}
end

-- 게임패스 또는 개발자 상품 한 줄.
function RobuxShopLogic.row(key: string, shop: any, ctx: Context?): Row
	local def = ShopConfig.get(key) :: ShopConfig.ProductDef
	local c: Context = ctx or {}
	if def.kind == "product" then
		return productRow(key, c, shop)
	end
	return passRow(key, ShopEffectsLogic.fromSummary(shop).owns, c, shop)
end

-- 포션 상품 키(그 종류 1개짜리) — ShopConfig에서 찾는다.
function RobuxShopLogic.potionProductKey(boost: string): string?
	for key, def in pairs(ShopConfig.Products) do
		if def.effect.type == "potion" and def.effect.boost == boost then
			return key
		end
	end
	return nil
end

-- 보관 수(Store "shop".potions). 없으면 0.
function RobuxShopLogic.potionCount(shop: any, boost: string): number
	local p = if type(shop) == "table" then shop.potions else nil
	local n = if type(p) == "table" then p[boost] else nil
	return if type(n) == "number" then n else 0
end

-- "포션" 묶음: 종류마다 "<이름>  보유 N" · 구매 · 켜기, 그 뒤 번들(구매만). 제한 유저는 행운 포션 · 번들(행운 포함)을 숨긴다(S13).
function RobuxShopLogic.potionRows(shop: any): { Row }
	local restricted = ShopEffectsLogic.fromSummary(shop).restricted
	local out: { Row } = {}
	for _, boost in ipairs(ShopConfig.BOOST_ORDER) do
		local key = RobuxShopLogic.potionProductKey(boost)
		local def = if key ~= nil then ShopConfig.get(key) else nil
		if def ~= nil and not (def.paidRandom and restricted) then
			local r = productRow(key :: string, {}, shop)
			local n = RobuxShopLogic.potionCount(shop, boost)
			r.title = Locale.t("shop.potion.title", { name = Names.product(key :: string), n = n })
			r.useKey = boost
			r.useText = RobuxShopLogic.USE_TEXT
			r.canUse = n > 0
			table.insert(out, r)
		end
	end
	for key, def in pairs(ShopConfig.Products) do
		if def.effect.type == "potionBundle" and not (def.paidRandom and restricted) then
			table.insert(out, productRow(key, {}, shop))
		end
	end
	return out
end

-- 창별 상품 목록(DESIGN 9장 "창별 상품 버튼"). 제한 유저면 행운 상품을 뺀다.
RobuxShopLogic.WINDOW_PRODUCTS = {
	pet = { "hatch3x", "petLuck2x", "petStorage100", "petSlots3" },
	aura = { "luckyRoll5", "luckyRoll15", "superRoll5", "superRoll15", "auraLuck10x" },
	title = { "titleLuck10x" },
} :: { [string]: { string } }

function RobuxShopLogic.windowRows(window: string, shop: any, ctx: Context?): { Row }
	local restricted = ShopEffectsLogic.fromSummary(shop).restricted
	local out: { Row } = {}
	for _, key in ipairs(RobuxShopLogic.WINDOW_PRODUCTS[window] or {}) do
		local def = ShopConfig.get(key) :: ShopConfig.ProductDef
		if not (def.paidRandom and restricted) then
			table.insert(out, RobuxShopLogic.row(key, shop, ctx))
		end
	end
	return out
end

-- PotionResult → 문구. 켰으면 "<이름> 켰다(+N분)", 거부면 사유.
function RobuxShopLogic.potionResultText(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	local boost = tostring(payload.boost)
	local key = RobuxShopLogic.potionProductKey(boost)
	if payload.ok then
		local def = ShopConfig.BOOSTS[boost]
		return Locale.t("shop.potion.used", { name = if key ~= nil then Names.product(key) else boost,
			min = if def ~= nil then math.floor(def.durationSec / 60) else 0 })
	end
	return RobuxShopLogic.reasonText(tostring(payload.reason))
end

-- 로벅스 탭 줄 전부. shop = Store "shop". 제한 유저면 로벅스 행운 상품 줄이 빠진다.
function RobuxShopLogic.rows(shop: any, ctx: Context?): { Row }
	local view = ShopEffectsLogic.fromSummary(shop)
	local c: Context = ctx or {}
	local out: { Row } = { ladderRow(view.owns) }
	for _, r in ipairs(RobuxShopLogic.potionRows(shop)) do
		table.insert(out, r)
	end
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
	elseif code == ShopConfig.REASON_LADDER_OWNED_HIGHER then
		return Locale.t("shop.reason.ladder_owned_higher")
	elseif code == ShopConfig.REASON_AUTO_OWNED_HIGHER then
		return Locale.t("shop.reason.auto_owned_higher")
	elseif code == "restricted" then
		return Locale.t("shop.reason.restricted")
	elseif code == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif code == "invalid_key" then
		return Locale.t("shop.reason.invalid_key")
	elseif code == "prompt_failed" then
		return Locale.t("shop.reason.prompt_failed")
	elseif code == "already_unlocked" then
		return Locale.t("shop.reason.already_unlocked")
	elseif code == "none_owned" then
		return Locale.t("shop.reason.none_owned")
	end
	return Locale.t("shop.reason.failed")
end

return RobuxShopLogic

--!strict
-- 아우라 창의 표시 값 · 잠김 · 사유 문구 · 결과 연출 판정 (Phase 7 지시서 #11 A5 · A6). 순수 모듈 —
-- 화면은 Screens/Window/AuraWindow, 결과 모달은 Screens/Overlay/ResultModal(차단층 큐).
--
-- 값은 서버 · Config 원본에서 나온다: 보유 · 장착 · 고른 팩 · 월드는 서버 PlayerState(Store "auras"), 해금은 lifetimeBlox(Store),
-- m · 비용 · 확률은 AuraConfig, 행운은 UpgradeConfig.getEffect("auraLuck", 레벨)(서버 RollService.computeLuck에서 지금 1이 아닌 항).
-- 확률은 실제 등장 확률 %(RollOdds — 합 100, P3). ⚠️ 판정 · 해금 · 잔액은 서버가 다시 판정한다(절대 규칙 3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

type BigNumber = BigNum.BigNumber

local AuraWindowLogic = {}

AuraWindowLogic.TITLE = Locale.t("aura.title")
AuraWindowLogic.EQUIP_TEXT = Locale.t("common.equip")
AuraWindowLogic.EQUIPPED_TEXT = Locale.t("common.equipped")
AuraWindowLogic.LOCKED_TEXT = "-"
AuraWindowLogic.TITLE_BUTTON_TEXT = Locale.t("aura.titleButton")
AuraWindowLogic.ROLL_TEXT = Locale.t("aura.roll")
-- 럭키 · 슈퍼 롤 쓰기 버튼(지시서 #17). n = 남은 횟수
function AuraWindowLogic.useCreditText(credit: string, n: number): string
	return Locale.t(if credit == "super" then "aura.useSuper" else "aura.useLucky", { n = n })
end
AuraWindowLogic.ROBUX_TAB_TEXT = Locale.t("shop.tab.robux")

-- 아우라 등급(1 common ~ 4 legendary) → UiTheme.Rarity 단계(tier1~6). Claude가 정했다(docs/UI.md "지시서 #11").
-- 일반 = 가장 수수한 tier1, 희귀 = 하늘 tier3, 영웅 = 보라 tier4, 전설 = 금 tier5. tier6(진분홍)은 칭호 신화만 쓴다 —
-- 아우라 전설을 칭호 신화와 같은 색으로 두면 "가장 귀한 것"이 두 개가 된다.
AuraWindowLogic.RARITY_TIER = { 1, 3, 4, 5 }

AuraWindowLogic.REASONS = {
	insufficient_blox = Locale.t("common.reason.insufficient_blox"),
	rate_limited = Locale.t("common.reason.rate_limited"),
	no_profile = Locale.t("common.reason.no_profile"),
	not_owned = Locale.t("aura.reason.not_owned"),
	pack_locked = Locale.t("aura.reason.pack_locked"),
	none_owned = Locale.t("aura.reason.none_owned"), -- 롤 쓰기: 남은 횟수 0(지시서 #17)
	restricted = Locale.t("shop.reason.restricted"),
	invalid_request = Locale.t("common.reason.invalid_request"),
	partial_failure = Locale.t("common.reason.partial_failure"),
} :: { [string]: string }

function AuraWindowLogic.reasonText(code: string): string
	return AuraWindowLogic.REASONS[code] or Locale.t("common.reason.failed")
end

function AuraWindowLogic.rarityTier(tier: number): number
	return AuraWindowLogic.RARITY_TIER[math.clamp(math.floor(tier), 1, #AuraWindowLogic.RARITY_TIER)]
end

function AuraWindowLogic.multText(m: number): string
	return Locale.t("aura.mult", { mult = string.format("%.2f", m) })
end

-- shop = Store "shop"(지시서 #16). 주면 행운 패스 · 행운 포션을 곱한다(서버 computeLuck과 같은 항 — 제한 유저면 1, S13).
-- 사용 중인 행운 상품의 효과가 확률 표에 그대로 보인다(공식 paid-random-items: 활성 중에는 바뀐 확률을 보인다).
function AuraWindowLogic.luckOf(levels: any, shop: any?): number
	local v = if type(levels) == "table" then levels.auraLuck else nil
	local level = if type(v) == "number" and v == v and v >= 0 then math.floor(v) else 0
	local extra = if shop ~= nil then ShopEffectsLogic.luckMult(ShopEffectsLogic.fromSummary(shop), "aura") else 1
	return UpgradeConfig.getEffect("auraLuck", level) * extra
end

function AuraWindowLogic.luckText(levels: any, shop: any?): string
	return RollOdds.luckText(AuraWindowLogic.luckOf(levels, shop))
end

local function big(v: any): BigNumber
	if type(v) == "table" and type(v.m) == "number" and type(v.e) == "number" then
		return BigNum.new(v.m, v.e)
	end
	return BigNum.new(0, 0)
end

local function worldOf(summary: any): number
	return if type(summary) == "table" and type(summary.world) == "number" then summary.world else 1
end

export type PackTab = { packId: number, unlocked: boolean, label: string, infoText: string }

-- 그 월드에 있는 팩 탭(1~3). 잠긴 팩은 해금 조건(lifetimeBlox ≥ 롤 1회 비용 — G3)을 보인다.
function AuraWindowLogic.packs(summary: any, lifetimeBlox: any): { PackTab }
	local world = WorldConfig.get(worldOf(summary))
	local out: { PackTab } = {}
	if world == nil then
		return out
	end
	local lifetime = big(lifetimeBlox)
	for _, packId in ipairs(world.auraPacks) do
		local pack = AuraConfig.Packs[packId]
		if pack ~= nil then
			local unlocked = BigNum.gte(lifetime, pack.rollCost)
			table.insert(out, {
				packId = packId,
				unlocked = unlocked,
				label = Locale.t(if unlocked then "aura.pack.tab" else "aura.pack.tabLocked", { pack = packId }),
				infoText = Locale.t(if unlocked then "aura.pack.info" else "aura.pack.infoLocked", { pack = packId, cost = Formatter.format(pack.rollCost) }),
			})
		end
	end
	return out
end

-- 보여 줄 팩: 저장된 selectedPack이 그 월드에 있으면 그것, 아니면 월드 첫 팩.
function AuraWindowLogic.shownPack(summary: any): number
	local world = WorldConfig.get(worldOf(summary))
	local selected = if type(summary) == "table" then summary.selectedPack else nil
	if world ~= nil then
		for _, id in ipairs(world.auraPacks) do
			if id == selected then
				return id
			end
		end
		return world.auraPacks[1]
	end
	return 1
end

export type Card = {
	id: string,
	name: string,
	tier: number, -- 아우라 등급 1~4
	rarityTier: number, -- UiTheme.Rarity 단계
	tierName: string,
	multText: string,
	chanceText: string, -- 실제 등장 확률 %(카드 넷의 합 100)
	owned: boolean,
	equipped: boolean,
	statusText: string,
	buttonText: string,
	canEquip: boolean,
}

local function ownedSet(summary: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(summary) == "table" and type(summary.owned) == "table" then
		for _, id in ipairs(summary.owned) do
			if type(id) == "string" then
				set[id] = true
			end
		end
	end
	return set
end

-- 팩 하나의 카드 4장(희귀도 낮은 순 — 왼쪽 일반 → 오른쪽 전설).
function AuraWindowLogic.cards(summary: any, levels: any, packId: number, shop: any?): { Card }
	local pack = AuraConfig.Packs[packId]
	local out: { Card } = {}
	if pack == nil then
		return out
	end
	local owned = ownedSet(summary)
	local equippedId = if type(summary) == "table" and type(summary.equipped) == "string" then summary.equipped else ""
	local texts = RollOdds.percentages(RollOdds.distribution(pack.auras, AuraWindowLogic.luckOf(levels, shop)))
	for tier, def in ipairs(pack.auras) do
		local isOwned = owned[def.id] == true
		local isEquipped = isOwned and equippedId == def.id
		table.insert(out, {
			id = def.id,
			name = Names.aura(def.id),
			tier = tier,
			rarityTier = AuraWindowLogic.rarityTier(tier),
			tierName = Names.rarity(tier),
			multText = AuraWindowLogic.multText(def.mult),
			chanceText = texts[tier],
			owned = isOwned,
			equipped = isEquipped,
			statusText = if isEquipped then Locale.t("common.equipped") elseif isOwned then Locale.t("common.owned") else Locale.t("common.notOwned"),
			buttonText = if isEquipped then AuraWindowLogic.EQUIPPED_TEXT elseif isOwned then AuraWindowLogic.EQUIP_TEXT else AuraWindowLogic.LOCKED_TEXT,
			canEquip = isOwned and not isEquipped,
		})
	end
	return out
end

export type RollState = { canRoll: boolean, buttonText: string, footText: string }

-- 럭키 · 슈퍼 롤 사용 버튼(지시서 #17). 제한 유저면 안 보인다(S13 — 서버도 restricted로 막는다).
-- 쓸 수 있음 = 남은 횟수 > 0 · 고른 팩이 열림(블럭스는 상관없다 — 비용 없음).
export type CreditState = { visible: boolean, canUse: boolean, text: string, left: number }
function AuraWindowLogic.creditState(summary: any, lifetimeBlox: any, shop: any, packId: number, credit: string): CreditState
	local restricted = type(shop) ~= "table" or shop.paidRandomRestricted ~= false
	local credits = if type(shop) == "table" and type(shop.rollCredits) == "table" then shop.rollCredits[credit] else nil
	local left = if type(credits) == "number" then credits else 0
	local unlocked = AuraConfig.Packs[packId] ~= nil and AuraConfig.isUnlocked(packId, big(lifetimeBlox), worldOf(summary))
	return { visible = not restricted, canUse = not restricted and left > 0 and unlocked, text = AuraWindowLogic.useCreditText(credit, left), left = left }
end

-- 뽑기 버튼 상태(안내 — 서버가 다시 판정한다). 잠긴 팩 → 해금 조건, 블럭스 부족 → 사유.
function AuraWindowLogic.rollState(summary: any, lifetimeBlox: any, blox: any, packId: number): RollState
	local pack = AuraConfig.Packs[packId]
	if pack == nil then
		return { canRoll = false, buttonText = AuraWindowLogic.ROLL_TEXT, footText = AuraWindowLogic.reasonText("invalid_request") }
	end
	local buttonText = Locale.t("aura.rollCost", { cost = Formatter.format(pack.rollCost) })
	if not AuraConfig.isUnlocked(packId, big(lifetimeBlox), worldOf(summary)) then
		return { canRoll = false, buttonText = buttonText, footText = AuraWindowLogic.reasonText("pack_locked") }
	end
	if BigNum.lt(big(blox), pack.rollCost) then
		return { canRoll = false, buttonText = buttonText, footText = AuraWindowLogic.reasonText("insufficient_blox") }
	end
	return { canRoll = true, buttonText = buttonText, footText = "" }
end

local function nameOf(id: any): string
	local def = AuraConfig.get(id)
	return if def ~= nil then Names.aura(def.id) else tostring(id)
end

-- 요청 결과 → 창 상태 문구(nil이면 비운다).
function AuraWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if not payload.ok then
		return AuraWindowLogic.reasonText(tostring(payload.reason))
	end
	if payload.action == "roll" or payload.action == "rollCredit" then
		if payload.isNew then
			return Locale.t("aura.result.new", { name = nameOf(payload.auraId) })
		end
		return Locale.t("aura.result.dup", { name = nameOf(payload.auraId) })
	elseif payload.action == "equip" then
		return Locale.t("common.result.equip", { name = nameOf(payload.auraId) })
	end
	return nil
end

-- ===== 결과 연출 (A6) ======================================================================

-- 모달을 띄우는가: 롤 성공이고 새 아우라이거나 3등급(epic) 이상. 중복 하위 등급은 창 안 문구로만.
function AuraWindowLogic.shouldModal(payload: any): boolean
	return type(payload) == "table" and payload.ok == true and (payload.action == "roll" or payload.action == "rollCredit")
		and (payload.isNew == true or (type(payload.tier) == "number" and payload.tier >= AuraConfig.MODAL_MIN_TIER))
end

export type ResultView = { heading: string, name: string, rarityTier: number, detail: string }

function AuraWindowLogic.resultView(payload: any): ResultView?
	local def, _, tier = AuraConfig.get(type(payload) == "table" and payload.auraId or nil)
	if def == nil or tier == nil then
		return nil
	end
	return {
		heading = Locale.t(if payload.isNew then "aura.modal.new" else "aura.modal.heading"),
		name = Names.aura(def.id),
		rarityTier = AuraWindowLogic.rarityTier(tier),
		detail = Locale.t(if payload.equipped then "aura.modal.detailEquipped" else "aura.modal.detail", { rarity = Names.rarity(tier), mult = AuraWindowLogic.multText(def.mult) }),
	}
end

-- 런 중(클리어 대기 포함)에는 모달 대신 토스트(A6). 문구는 모달과 같은 내용 한 줄.
function AuraWindowLogic.toastFor(payload: any): { text: string, tier: number }?
	local v = AuraWindowLogic.resultView(payload)
	if v == nil then
		return nil
	end
	return { text = Locale.t("common.toast.result", { heading = v.heading, name = v.name, detail = AuraWindowLogic.multText((AuraConfig.get(payload.auraId) :: any).mult) }), tier = v.rarityTier }
end

function AuraWindowLogic.pendingKeyOf(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if payload.action == "roll" or payload.action == "equip" or payload.action == "selectPack" or payload.action == "rollCredit" then
		return payload.action
	end
	return nil
end

return AuraWindowLogic

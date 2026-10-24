--!strict
-- 펫 창의 표시 값 · 잠김 · 사유 문구 · 결과 연출 판정 (Phase 7 지시서 #12). 순수 모듈 — 화면은 Screens/Window/PetWindow,
-- 결과 모달은 Screens/Overlay/ResultModal(차단층 큐 — #11과 같은 큐).
--
-- 값은 서버 · Config 원본에서 나온다: 보유 · 장착 · 파생 슬롯 · 파생 저장 공간 · 월드는 서버 PlayerState(Store "pets"),
-- 해금은 lifetimeBlox(Store), m · 비용 · 확률 · 실효 증가분은 PetConfig, 행운은 UpgradeConfig.getEffect("petLuck", 레벨).
-- 확률은 실제 등장 확률 %(RollOdds — 합 100, P3). ⚠️ 판정 · 해금 · 잔액 · 슬롯 · 재료는 서버가 다시 판정한다(절대 규칙 3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)

type BigNumber = BigNum.BigNumber

local PetWindowLogic = {}

PetWindowLogic.TITLE = "펫"
PetWindowLogic.BEST_TEXT = "최고 장착"
PetWindowLogic.EQUIP_TEXT = "장착"
PetWindowLogic.UNEQUIP_TEXT = "해제"
PetWindowLogic.RELEASE_TEXT = "놓아주기"
PetWindowLogic.RELEASE_CONFIRM_TEXT = "한 번 더 누르면 놓아줘요"
PetWindowLogic.RELEASE_CONFIRM_SEC = 3 -- 놓아주기 확인 단계(되돌릴 수 없다 — E5). ConfirmFlow 창 시간
PetWindowLogic.EMPTY_SLOT_TEXT = "빈 슬롯"
PetWindowLogic.NO_SELECTION_TEXT = "펫을 골라 주세요"

-- 종 희귀도(1 일반 ~ 4 전설) → UiTheme.Rarity 단계. 아우라와 같은 매핑(docs/UI.md "지시서 #12") — tier6은 칭호 신화 전용.
PetWindowLogic.RARITY_TIER = { 1, 3, 4, 5 }

PetWindowLogic.REASONS = {
	insufficient_blox = "블럭스가 모자라요",
	rate_limited = "잠시 뒤에 다시 눌러 주세요",
	no_profile = "데이터를 불러오는 중이에요",
	egg_locked = "아직 열리지 않은 알이에요",
	storage_full = "보관함이 가득 찼어요 — 놓아주기로 자리를 비워 주세요",
	not_owned = "없는 펫이에요",
	slots_full = "장착 슬롯이 가득 찼어요",
	not_equipped = "장착하지 않은 펫이에요",
	pet_equipped = "장착 중인 펫은 놓아줄 수 없어요",
	max_level = "이미 최고 단계예요",
	not_enough = "같은 펫 3마리가 필요해요",
	invalid_request = "할 수 없는 요청이에요",
	partial_failure = "문제가 생겼어요. 관리자에게 알려 주세요",
} :: { [string]: string }

function PetWindowLogic.reasonText(code: string): string
	return PetWindowLogic.REASONS[code] or "하지 못했어요"
end

function PetWindowLogic.rarityTier(rarity: number): number
	return PetWindowLogic.RARITY_TIER[math.clamp(math.floor(rarity), 1, #PetWindowLogic.RARITY_TIER)]
end

-- 실효 증가분 문구: "힘 +0.47". 장착하면 펫 배수에 이만큼 더해진다(E3).
function PetWindowLogic.gainText(gain: number): string
	return string.format("힘 +%.2f", gain)
end

function PetWindowLogic.levelName(level: number): string
	return PetConfig.LEVEL_NAMES[math.clamp(math.floor(level), 1, PetConfig.MAX_LEVEL)]
end

function PetWindowLogic.luckOf(levels: any): number
	local v = if type(levels) == "table" then levels.petLuck else nil
	local level = if type(v) == "number" and v == v and v >= 0 then math.floor(v) else 0
	return UpgradeConfig.getEffect("petLuck", level)
end

function PetWindowLogic.luckText(levels: any): string
	return RollOdds.luckText(PetWindowLogic.luckOf(levels))
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

local function ownedList(summary: any): { any }
	return if type(summary) == "table" and type(summary.owned) == "table" then summary.owned else {}
end

local function equippedList(summary: any): { string }
	return if type(summary) == "table" and type(summary.equipped) == "table" then summary.equipped else {}
end

local function isEquipped(summary: any, uid: string): boolean
	return table.find(equippedList(summary), uid) ~= nil
end

export type EggTab = { eggId: number, unlocked: boolean, label: string, infoText: string }

-- 그 월드에 있는 알 탭. 잠긴 알은 해금 조건(lifetimeBlox ≥ 부화 1회 비용 — G8)을 보인다.
function PetWindowLogic.eggs(summary: any, lifetimeBlox: any): { EggTab }
	local world = WorldConfig.get(worldOf(summary))
	local out: { EggTab } = {}
	if world == nil then
		return out
	end
	local lifetime = big(lifetimeBlox)
	for _, eggId in ipairs(world.eggPacks) do
		local egg = PetConfig.Eggs[eggId]
		if egg ~= nil then
			local unlocked = BigNum.gte(lifetime, egg.rollCost)
			table.insert(out, {
				eggId = eggId,
				unlocked = unlocked,
				label = if unlocked then egg.name else egg.name .. " 잠김",
				infoText = if unlocked
					then string.format("%s · 1회 %s 블럭스", egg.name, Formatter.format(egg.rollCost))
					else string.format("%s — 누적 블럭스 %s 이상이면 열려요", egg.name, Formatter.format(egg.rollCost)),
			})
		end
	end
	return out
end

-- 처음 보여 줄 알: 열린 알 중 가장 높은 것. 하나도 안 열렸으면 월드 첫 알.
function PetWindowLogic.defaultEgg(summary: any, lifetimeBlox: any): number
	local tabs = PetWindowLogic.eggs(summary, lifetimeBlox)
	local best: number? = nil
	for _, t in ipairs(tabs) do
		if t.unlocked then
			best = t.eggId
		end
	end
	return best or (if tabs[1] ~= nil then tabs[1].eggId else 1)
end

export type Odd = { id: string, name: string, rarity: number, rarityTier: number, text: string }

-- 알 하나의 종 4개 실제 등장 확률(합 100) — "도토리 ×1.05 · 63.1%".
function PetWindowLogic.odds(eggId: number, levels: any): { Odd }
	local egg = PetConfig.Eggs[eggId]
	local out: { Odd } = {}
	if egg == nil then
		return out
	end
	local texts = RollOdds.percentages(RollOdds.distribution(egg.pets, PetWindowLogic.luckOf(levels)))
	for rarity, def in ipairs(egg.pets) do
		table.insert(out, {
			id = def.id,
			name = def.name,
			rarity = rarity,
			rarityTier = PetWindowLogic.rarityTier(rarity),
			text = string.format("%s ×%.2f · %s", def.name, def.mult, texts[rarity]),
		})
	end
	return out
end

export type HatchState = { canHatch: boolean, buttonText: string, footText: string }

-- 부화 버튼 상태(안내 — 서버가 다시 판정한다). 잠긴 알 → 사유, 보관함 가득 → 사유, 블럭스 부족 → 사유.
function PetWindowLogic.hatchState(summary: any, lifetimeBlox: any, blox: any, eggId: number): HatchState
	local egg = PetConfig.Eggs[eggId]
	if egg == nil then
		return { canHatch = false, buttonText = "부화", footText = PetWindowLogic.reasonText("invalid_request") }
	end
	local buttonText = string.format("부화 (%s 블럭스)", Formatter.format(egg.rollCost))
	if not PetConfig.isUnlocked(eggId, big(lifetimeBlox), worldOf(summary)) then
		return { canHatch = false, buttonText = buttonText, footText = PetWindowLogic.reasonText("egg_locked") }
	end
	local storage = if type(summary) == "table" and type(summary.storage) == "number" then summary.storage else 0
	if #ownedList(summary) >= storage then
		return { canHatch = false, buttonText = buttonText, footText = PetWindowLogic.reasonText("storage_full") }
	end
	if BigNum.lt(big(blox), egg.rollCost) then
		return { canHatch = false, buttonText = buttonText, footText = PetWindowLogic.reasonText("insufficient_blox") }
	end
	return { canHatch = true, buttonText = buttonText, footText = "" }
end

function PetWindowLogic.storageText(summary: any): string
	local storage = if type(summary) == "table" and type(summary.storage) == "number" then summary.storage else 0
	return string.format("보유 %d / %d", #ownedList(summary), storage)
end

function PetWindowLogic.slotsText(summary: any): string
	local slots = if type(summary) == "table" and type(summary.slots) == "number" then summary.slots else 0
	return string.format("장착 %d / %d", #equippedList(summary), slots)
end

export type Cell = {
	uid: string,
	petId: string,
	name: string,
	level: number,
	levelName: string,
	rarity: number,
	rarityTier: number,
	gain: number,
	equipped: boolean,
}

local function cellOf(summary: any, e: any): Cell?
	if type(e) ~= "table" then
		return nil
	end
	local def, _, rarity = PetConfig.get(e.petId)
	if def == nil or rarity == nil or not PetConfig.isLevel(e.level) then
		return nil
	end
	return {
		uid = e.uid,
		petId = e.petId,
		name = def.name,
		level = e.level,
		levelName = PetWindowLogic.levelName(e.level),
		rarity = rarity,
		rarityTier = PetWindowLogic.rarityTier(rarity),
		gain = PetConfig.effectiveGain(e.petId, e.level),
		equipped = isEquipped(summary, e.uid),
	}
end

-- 보유 격자: 장착한 것 먼저, 그다음 실효 증가분 큰 순, 같으면 uid 번호 순.
function PetWindowLogic.grid(summary: any): { Cell }
	local out: { Cell } = {}
	for _, e in ipairs(ownedList(summary)) do
		local c = cellOf(summary, e)
		if c ~= nil then
			table.insert(out, c)
		end
	end
	table.sort(out, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return (tonumber(a.uid) or 0) < (tonumber(b.uid) or 0)
	end)
	return out
end

export type Slot = { uid: string?, text: string, rarityTier: number? }

-- 장착 슬롯 줄(파생 슬롯 수만큼). 빈 슬롯은 "빈 슬롯".
function PetWindowLogic.slots(summary: any): { Slot }
	local n = if type(summary) == "table" and type(summary.slots) == "number" then math.max(0, math.floor(summary.slots)) else 0
	local byUid: { [string]: any } = {}
	for _, e in ipairs(ownedList(summary)) do
		if type(e) == "table" then
			byUid[e.uid] = e
		end
	end
	local out: { Slot } = {}
	local eq = equippedList(summary)
	for i = 1, math.max(n, #eq) do
		local uid = eq[i]
		local c = if uid ~= nil then cellOf(summary, byUid[uid]) else nil
		if c ~= nil then
			out[i] = { uid = c.uid, text = c.name, rarityTier = c.rarityTier }
		else
			out[i] = { uid = nil, text = PetWindowLogic.EMPTY_SLOT_TEXT, rarityTier = nil }
		end
	end
	return out
end

-- 같은 petId · 같은 단계 보유 수(크래프팅 재료).
function PetWindowLogic.sameCount(summary: any, petId: string, level: number): number
	local n = 0
	for _, e in ipairs(ownedList(summary)) do
		if type(e) == "table" and e.petId == petId and e.level == level then
			n += 1
		end
	end
	return n
end

export type Detail = {
	uid: string,
	name: string,
	rarityTier: number,
	infoText: string, -- "영웅 · 황금 · 힘 +0.47"
	equipped: boolean,
	equipText: string,
	canEquip: boolean, -- 장착 또는 해제 버튼을 누를 수 있는가
	craftText: string,
	canCraft: boolean,
	canRelease: boolean,
	releaseFoot: string, -- 놓아주기를 못 하는 이유(장착 중) — 비면 없음
}

-- 고른 펫의 상세. 없으면 nil(고른 펫이 놓아졌거나 크래프팅 재료로 쓰였다).
function PetWindowLogic.detail(summary: any, uid: string?): Detail?
	if uid == nil then
		return nil
	end
	local entry: any = nil
	for _, e in ipairs(ownedList(summary)) do
		if type(e) == "table" and e.uid == uid then
			entry = e
		end
	end
	local c = cellOf(summary, entry)
	if c == nil then
		return nil
	end
	local slots = if type(summary) == "table" and type(summary.slots) == "number" then summary.slots else 0
	local same = PetWindowLogic.sameCount(summary, c.petId, c.level)
	local need = PetConfig.CRAFT_REQUIREMENT
	local atMax = c.level >= PetConfig.MAX_LEVEL
	return {
		uid = c.uid,
		name = c.name,
		rarityTier = c.rarityTier,
		infoText = string.format("%s · %s · %s", PetConfig.TIER_NAMES[c.rarity], c.levelName, PetWindowLogic.gainText(c.gain)),
		equipped = c.equipped,
		equipText = if c.equipped then PetWindowLogic.UNEQUIP_TEXT else PetWindowLogic.EQUIP_TEXT,
		canEquip = c.equipped or #equippedList(summary) < slots,
		craftText = if atMax then "최고 단계" else string.format("크래프팅 → %s (%d/%d)", PetWindowLogic.levelName(c.level + 1), math.min(same, need), need),
		canCraft = not atMax and same >= need,
		canRelease = not c.equipped,
		releaseFoot = if c.equipped then PetWindowLogic.reasonText("pet_equipped") else "",
	}
end

local function nameOf(petId: any): string
	local def = PetConfig.get(petId)
	return if def ~= nil then def.name else tostring(petId)
end

-- 요청 결과 → 창 상태 문구(nil이면 비운다).
function PetWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if not payload.ok then
		return PetWindowLogic.reasonText(tostring(payload.reason))
	end
	local a = payload.action
	if a == "hatch" then
		return string.format("%s%s", if payload.isNew then "새 펫! " else "부화: ", nameOf(payload.petId))
	elseif a == "craft" then
		return string.format("크래프팅! %s %s", nameOf(payload.petId), PetWindowLogic.levelName(tonumber(payload.level) or 1))
	elseif a == "equip" then
		return "장착했어요"
	elseif a == "unequip" then
		return "해제했어요"
	elseif a == "equipBest" then
		return "가장 센 펫으로 장착했어요"
	elseif a == "release" then
		return "놓아줬어요"
	end
	return nil
end

-- ===== 결과 연출 (E8 — 아우라 A6과 같다) =======================================================

-- 모달을 띄우는가: 부화 성공이고 새 종이거나 3등급(영웅) 이상.
function PetWindowLogic.shouldModal(payload: any): boolean
	return type(payload) == "table" and payload.ok == true and payload.action == "hatch"
		and (payload.isNew == true or (type(payload.rarity) == "number" and payload.rarity >= PetConfig.MODAL_MIN_TIER))
end

export type ResultView = { heading: string, name: string, rarityTier: number, detail: string }

function PetWindowLogic.resultView(payload: any): ResultView?
	local def, _, rarity = PetConfig.get(type(payload) == "table" and payload.petId or nil)
	if def == nil or rarity == nil then
		return nil
	end
	local level = if type(payload.level) == "number" and PetConfig.isLevel(payload.level) then payload.level else 1
	return {
		heading = if payload.isNew then "새 펫!" else "펫",
		name = def.name,
		rarityTier = PetWindowLogic.rarityTier(rarity),
		detail = string.format("%s · %s%s", PetConfig.TIER_NAMES[rarity], PetWindowLogic.gainText(PetConfig.effectiveGain(def.id, level)),
			if payload.equipped then " · 장착" else ""),
	}
end

-- 런 중(클리어 대기 포함)에는 모달 대신 토스트(E8). 문구는 모달과 같은 내용 한 줄.
function PetWindowLogic.toastFor(payload: any): { text: string, tier: number }?
	local v = PetWindowLogic.resultView(payload)
	if v == nil then
		return nil
	end
	return { text = string.format("%s %s (%s)", v.heading, v.name, v.detail), tier = v.rarityTier }
end

local PENDING_KEYS: { [string]: boolean } = { hatch = true, equip = true, unequip = true, equipBest = true, craft = true, release = true }

function PetWindowLogic.pendingKeyOf(payload: any): string?
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return nil
	end
	return if PENDING_KEYS[payload.action] then payload.action else nil
end

return PetWindowLogic

--!strict
-- 장비 창 순수 로직(지시서 #34 — 인스턴스 없음 · EquipmentClientTests가 부른다). 판정은 서버다(EquipmentService) — 여기는 보여 줄 것만.
--   칸 15개(등급순 = rank 순) · 칸마다 보유 · 별 · 강화 · 배수 · 장착 · 없는 곡괭이는 실루엣 · 강화 미리보기(다음 비용 · 쓰일 광석 · 배수 바뀜) ·
--   별 미리보기(필요한 여벌 · 배수 바뀜) · 거부 사유 글자. 배수 식은 공유 EconomyV2Logic(게임 · 시뮬레이터와 같은 함수)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local EquipmentWindowLogic = {}

-- 장비 종류 탭(지금 곡괭이 하나 — 칼은 EQUIPMENT_KINDS에 하나 더)
EquipmentWindowLogic.KINDS = Config.EQUIPMENT_KINDS

export type Owned = { count: number, stars: number, enh: number }
export type Cell = {
	id: string,
	rarity: string,
	owned: boolean,
	count: number,
	stars: number,
	enh: number,
	mult: number,
	equipped: boolean,
}

local function multText(m: number): string
	return string.format("%.2f", m)
end
EquipmentWindowLogic.multText = multText

-- 15칸(등급순 — Config.PICKAXES는 rank 순이다)
function EquipmentWindowLogic.cells(equipment: { [string]: Owned }, equipped: string): { Cell }
	local out = {}
	for _, def in ipairs(Config.PICKAXES) do
		local o = equipment[def.id]
		table.insert(out, {
			id = def.id,
			rarity = def.rarity,
			owned = o ~= nil,
			count = if o ~= nil then o.count else 0,
			stars = if o ~= nil then o.stars else 0,
			enh = if o ~= nil then o.enh else 0,
			mult = if o ~= nil then EconomyV2Logic.pickaxeMult(def.id, o.enh, o.stars) else EconomyV2Logic.baseMult(def.id),
			equipped = def.id == equipped,
		})
	end
	return out
end

-- 이름 글자(없는 곡괭이는 ???)
function EquipmentWindowLogic.nameOf(cell: Cell): string
	if not cell.owned then
		return Locale.t("equip.unknown")
	end
	local def = EconomyV2Logic.pickaxe(cell.id) :: Config.PickaxeDef
	return Locale.t(def.nameKey)
end

local function oresText(take: { [number]: number }): string
	local parts = {}
	for k = 1, Config.ORE_COUNT do
		local n = take[k]
		if n ~= nil and n > 0 then
			table.insert(parts, string.format("%s ×%d", Locale.t(EconomyV2Logic.oreNameKey(k)), n))
		end
	end
	return table.concat(parts, " · ")
end

export type EnhancePreview = { canMax: boolean, cost: number?, take: { [number]: number }?, before: number, after: number, text: string, multText: string }

-- 강화 미리보기: 다음 단계 비용(광석 점수) · 실제로 쓰일 광석(가진 광석 전부에서 낮은 광석부터 — 서버와 같은 orePayment) · 배수 바뀜
function EquipmentWindowLogic.enhancePreview(cell: Cell, ores: { number }): EnhancePreview
	local before = cell.mult
	local cost = EconomyV2Logic.enhanceCost(cell.enh, cell.id)
	if cost == nil then
		return { canMax = true, cost = nil, take = nil, before = before, after = before, text = Locale.t("equip.enh.max"), multText = "" }
	end
	local after = EconomyV2Logic.pickaxeMult(cell.id, cell.enh + 1, cell.stars)
	local take = EconomyV2Logic.orePayment(ores, cost)
	local text = Locale.t("equip.enh.cost", { from = tostring(cell.enh), to = tostring(cell.enh + 1), points = tostring(cost),
		ores = if take ~= nil then oresText(take) else Locale.t("equip.reason.not_enough_ore") })
	return { canMax = false, cost = cost, take = take, before = before, after = after, text = text,
		multText = Locale.t("equip.multChange", { before = multText(before), after = multText(after) }) }
end

export type StarPreview = { isMax: boolean, need: number?, spare: number, can: boolean, after: number, text: string, multText: string }

-- 별 미리보기: 다음 별에 필요한 여벌(1 · 3 · 5 · 7 · 10) · 지금 여벌(보유 − 1 — 1개는 남긴다) · 배수 바뀜
function EquipmentWindowLogic.starPreview(cell: Cell): StarPreview
	local spare = EconomyV2Logic.spareOf(cell.count)
	local need = EconomyV2Logic.starCost(cell.stars)
	if need == nil then
		return { isMax = true, need = nil, spare = spare, can = false, after = cell.mult, text = Locale.t("equip.star.max"), multText = "" }
	end
	local after = EconomyV2Logic.pickaxeMult(cell.id, cell.enh, cell.stars + 1)
	return {
		isMax = false,
		need = need,
		spare = spare,
		can = spare >= need,
		after = after,
		text = Locale.t("equip.star.cost", { from = tostring(cell.stars), to = tostring(cell.stars + 1), need = tostring(need), spare = tostring(spare) }),
		multText = Locale.t("equip.multChange", { before = multText(cell.mult), after = multText(after) }),
	}
end

-- 서버 거부 사유 → 글자
function EquipmentWindowLogic.reasonText(reason: string?): string
	local known = { not_owned = true, already_equipped = true, max = true, not_enough_ore = true, not_enough_copies = true, forge_closed = true }
	if reason ~= nil and known[reason] then
		return Locale.t("equip.reason." .. reason)
	end
	return Locale.t("equip.reason.other")
end

return EquipmentWindowLogic

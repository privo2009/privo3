--!strict
-- 새 경제 인벤토리 단일 관문(지시서 #32 — DESIGN 16장 · CLAUDE.md 절대 규칙 2와 같은 원칙).
-- 광석(ores) · 토큰(tokens) · 장비(equipment · equipped) · 대장간 열림(forgeOpen)은 이 모듈만 바꾼다. profile.Data를 밖에서 직접 고치지 않는다.
-- 코인은 여기 없다 — 재화라 CurrencyService("coins")가 관문이다.
--
-- 구조는 CurrencyService와 같다:
--   순수 계산(apply*)은 profile · Player 없이 data 표만으로 돈다 → InventoryService._pure로 테스트가 직접 부른다
--   공개 API는 프로필을 찾고 · 검증하고 · 사본에 적용한 뒤 Schema.validateEconomy로 다시 보고 · 통과할 때만 바꾼다(실패면 그대로)
--   reason은 필수 문자열이다(로그 · 추적 — 어디서 바뀌었나)
-- ⚠️ yield하지 않는다(환생 · 수령 사이에 끼어들지 않게 — CurrencyService와 같은 이유).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Schema = require(script.Parent.Parent.Data.Schema)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)

local InventoryService = {}

export type Counts = { [number]: number } -- 광석 번호 → 개수
export type TokenCounts = { [string]: number } -- 토큰 종류 → 개수

local function isWhole(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v % 1 == 0 and v >= 0
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

local TOKEN_SET: { [string]: boolean } = {}
for _, key in ipairs(Schema.LIMITS.TOKEN_KEYS) do
	TOKEN_SET[key] = true
end

local function equipmentDef(kind: string, id: string): any
	local e = Config.EQUIPMENT[kind]
	if e == nil then
		return nil
	end
	for _, def in ipairs(e.list) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ===== 순수 계산 (data 표만 바꾼다 — 실패면 (false, 사유)이고 data는 그대로) =========================

local function validCounts(counts: any): (boolean, string?)
	if type(counts) ~= "table" then
		return false, "counts가 표가 아님"
	end
	for k, n in pairs(counts) do
		if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > Config.ORE_COUNT then
			return false, "광석 번호가 1 ~ ORE_COUNT 정수가 아님: " .. tostring(k)
		end
		if not isWhole(n) then
			return false, string.format("광석 %d 개수가 0 이상 정수가 아님", k)
		end
	end
	return true, nil
end

local function applyAddOres(data: any, counts: Counts): (boolean, string?)
	local ok, err = validCounts(counts)
	if not ok then
		return false, err
	end
	if type(data.ores) ~= "table" then
		return false, "ores 표가 없음"
	end
	for k, n in pairs(counts) do
		data.ores[k] = (data.ores[k] or 0) + n
	end
	return true, nil
end

local function applyTakeOres(data: any, counts: Counts): (boolean, string?)
	local ok, err = validCounts(counts)
	if not ok then
		return false, err
	end
	if type(data.ores) ~= "table" then
		return false, "ores 표가 없음"
	end
	for k, n in pairs(counts) do
		if (data.ores[k] or 0) < n then
			return false, string.format("광석 %d 부족", k)
		end
	end
	for k, n in pairs(counts) do
		data.ores[k] -= n
	end
	return true, nil
end

local function validTokens(counts: any): (boolean, string?)
	if type(counts) ~= "table" then
		return false, "counts가 표가 아님"
	end
	for key, n in pairs(counts) do
		if not TOKEN_SET[key] then
			return false, "모르는 토큰: " .. tostring(key)
		end
		if not isWhole(n) then
			return false, "토큰 " .. tostring(key) .. " 개수가 0 이상 정수가 아님"
		end
	end
	return true, nil
end

local function applyAddTokens(data: any, counts: TokenCounts): (boolean, string?)
	local ok, err = validTokens(counts)
	if not ok then
		return false, err
	end
	if type(data.tokens) ~= "table" then
		return false, "tokens 표가 없음"
	end
	for key, n in pairs(counts) do
		data.tokens[key] = (data.tokens[key] or 0) + n
	end
	return true, nil
end

local function applyTakeTokens(data: any, counts: TokenCounts): (boolean, string?)
	local ok, err = validTokens(counts)
	if not ok then
		return false, err
	end
	if type(data.tokens) ~= "table" then
		return false, "tokens 표가 없음"
	end
	for key, n in pairs(counts) do
		if (data.tokens[key] or 0) < n then
			return false, "토큰 " .. key .. " 부족"
		end
	end
	for key, n in pairs(counts) do
		data.tokens[key] -= n
	end
	return true, nil
end

-- 장비 하나를 얻는다(제작 · 교환 — #33). 이미 있으면 개수 +1(별 재료).
local function applyGrantEquipment(data: any, kind: string, id: string): (boolean, string?)
	if equipmentDef(kind, id) == nil then
		return false, string.format("모르는 장비 %s.%s", tostring(kind), tostring(id))
	end
	if type(data.equipment) ~= "table" or type(data.equipment[kind]) ~= "table" then
		return false, "equipment." .. kind .. " 표가 없음"
	end
	local o = data.equipment[kind][id]
	if o == nil then
		data.equipment[kind][id] = { count = 1, stars = 0, enh = 0 }
	else
		o.count += 1
	end
	return true, nil
end

-- 가진 장비를 장착한다(종류별 하나 — #34)
local function applyEquip(data: any, kind: string, id: string): (boolean, string?)
	if equipmentDef(kind, id) == nil then
		return false, string.format("모르는 장비 %s.%s", tostring(kind), tostring(id))
	end
	if type(data.equipment) ~= "table" or type(data.equipment[kind]) ~= "table" or data.equipment[kind][id] == nil then
		return false, "보유하지 않은 장비"
	end
	if type(data.equipped) ~= "table" then
		return false, "equipped 표가 없음"
	end
	data.equipped[kind] = id
	return true, nil
end

-- 대장간을 연다(영구 — 닫는 함수는 없다). 이미 열려 있으면 (true, "already")
local function applyOpenForge(data: any): (boolean, string?)
	if data.forgeOpen == true then
		return true, "already"
	end
	data.forgeOpen = true
	return true, nil
end

-- 제작 지급 한 번에(#33 — 대장간): 광석을 빼고 · 장비를 하나씩 얻고 · 토큰을 더한다. 하나라도 실패하면 전부 안 한다(applyChecked 사본)
local function applyCraft(data: any, take: Counts, kind: string, ids: { string }, tokens: TokenCounts): (boolean, string?)
	local ok, info = applyTakeOres(data, take)
	if not ok then
		return false, info
	end
	for _, id in ipairs(ids) do
		ok, info = applyGrantEquipment(data, kind, id)
		if not ok then
			return false, info
		end
	end
	if next(tokens) ~= nil then
		ok, info = applyAddTokens(data, tokens)
		if not ok then
			return false, info
		end
	end
	return true, nil
end

-- 교환 한 번에(#33 — 토큰 교환소): 토큰을 빼고 장비를 얻는다
local function applyExchange(data: any, kind: string, id: string, tokens: TokenCounts): (boolean, string?)
	local ok, info = applyTakeTokens(data, tokens)
	if not ok then
		return false, info
	end
	return applyGrantEquipment(data, kind, id)
end

-- 강화 +1(#34): 가진 장비 · +10 미만 · 비용(등급 × 단계 — EconomyV2Logic.enhanceCost)을 가진 광석 전부에서 낮은 광석부터 낸다.
-- 사유: "not_owned" · "max" · "not_enough_ore". 성공이면 (true, 낸 광석 {번호 = 개수})
local function applyEnhance(data: any, kind: string, id: string): (boolean, any)
	if equipmentDef(kind, id) == nil then
		return false, "unknown"
	end
	local o = if type(data.equipment) == "table" and type(data.equipment[kind]) == "table" then data.equipment[kind][id] else nil
	if o == nil then
		return false, "not_owned"
	end
	local cost = EconomyV2Logic.enhanceCost(o.enh, id)
	if cost == nil then
		return false, "max"
	end
	local take = EconomyV2Logic.orePayment(data.ores, cost)
	if take == nil then
		return false, "not_enough_ore"
	end
	local ok, info = applyTakeOres(data, take)
	if not ok then
		return false, info
	end
	o.enh += 1
	return true, take
end

-- 별 +1(#34): 여벌(보유 − 1)에서 STAR_CONSUME[지금 별 + 1]개를 쓴다 — 보유 1개는 언제나 남긴다. 사유: "not_owned" · "max" · "not_enough_copies"
local function applyStarUp(data: any, kind: string, id: string): (boolean, string?)
	if equipmentDef(kind, id) == nil then
		return false, "unknown"
	end
	local o = if type(data.equipment) == "table" and type(data.equipment[kind]) == "table" then data.equipment[kind][id] else nil
	if o == nil then
		return false, "not_owned"
	end
	local need = EconomyV2Logic.starCost(o.stars)
	if need == nil then
		return false, "max"
	end
	if EconomyV2Logic.spareOf(o.count) < need then
		return false, "not_enough_copies"
	end
	o.count -= need
	o.stars += 1
	return true, nil
end

-- 사본에 적용하고 Schema.validateEconomy로 다시 본 뒤에만 원본에 넣는다(CurrencyService.applyUpdatesWithRollback과 같은 뜻).
local ECON_FIELDS = { "ores", "equipment", "equipped", "tokens", "forgeOpen" }
local function applyChecked(data: any, fn: (any) -> (boolean, string?)): (boolean, string?)
	local copy = {}
	for _, field in ipairs(ECON_FIELDS) do
		copy[field] = deepCopy(data[field])
	end
	copy.coins = data.coins
	local ok, info = fn(copy)
	if not ok then
		return false, info
	end
	local errors = {}
	Schema.validateEconomy(copy, errors)
	if #errors > 0 then
		return false, "적용 뒤 검증 실패: " .. errors[1]
	end
	for _, field in ipairs(ECON_FIELDS) do
		data[field] = copy[field]
	end
	return true, info
end

-- 테스트 전용 통로. 공개 API 계약이 아니다.
InventoryService._pure = {
	applyAddOres = applyAddOres,
	applyTakeOres = applyTakeOres,
	applyAddTokens = applyAddTokens,
	applyTakeTokens = applyTakeTokens,
	applyGrantEquipment = applyGrantEquipment,
	applyEquip = applyEquip,
	applyOpenForge = applyOpenForge,
	applyCraft = applyCraft,
	applyExchange = applyExchange,
	applyEnhance = applyEnhance,
	applyStarUp = applyStarUp,
	applyChecked = applyChecked,
}

-- ===== 공개 API =======================================================================

-- 데이터 출처(기본 ProfileManager). 테스트가 가짜 프로필 표로 바꾼다 — 바꾼 뒤 반드시 되돌릴 것.
InventoryService._deps = {
	getData = function(player: Player): any
		local profile = ProfileManager.get(player)
		return if profile ~= nil then profile.Data else nil
	end,
	log = function(line: string)
		print(line)
	end,
}

local function run(op: string, player: Player, reason: string, fn: (any) -> (boolean, string?)): boolean
	assert(type(reason) == "string" and #reason > 0, "InventoryService." .. op .. ": reason은 필수 문자열이다")
	local data = InventoryService._deps.getData(player)
	if data == nil then
		warn(string.format("[InventoryService] %s 실패: %s 프로필 없음 (reason=%s)", op, tostring(player.Name), reason))
		return false
	end
	local ok, info = applyChecked(data, fn)
	if not ok then
		warn(string.format("[InventoryService] %s 거부: %s (reason=%s) - %s", op, tostring(player.Name), reason, tostring(info)))
		return false
	end
	if info ~= "already" then
		InventoryService._deps.log(string.format("[InventoryService] %s: %s (reason=%s)", op, tostring(player.Name), reason))
	end
	return true
end

function InventoryService.addOres(player: Player, counts: Counts, reason: string): boolean
	local any = false
	for _, n in pairs(counts) do
		any = any or (type(n) == "number" and n > 0)
	end
	if not any then
		return true -- 0개 — 바꿀 것이 없다(로그도 남기지 않는다)
	end
	return run("addOres", player, reason, function(d)
		return applyAddOres(d, counts)
	end)
end

function InventoryService.takeOres(player: Player, counts: Counts, reason: string): boolean
	return run("takeOres", player, reason, function(d)
		return applyTakeOres(d, counts)
	end)
end

function InventoryService.addTokens(player: Player, counts: TokenCounts, reason: string): boolean
	return run("addTokens", player, reason, function(d)
		return applyAddTokens(d, counts)
	end)
end

function InventoryService.takeTokens(player: Player, counts: TokenCounts, reason: string): boolean
	return run("takeTokens", player, reason, function(d)
		return applyTakeTokens(d, counts)
	end)
end

function InventoryService.grantEquipment(player: Player, kind: string, id: string, reason: string): boolean
	return run("grantEquipment", player, reason, function(d)
		return applyGrantEquipment(d, kind, id)
	end)
end

function InventoryService.equip(player: Player, kind: string, id: string, reason: string): boolean
	return run("equip", player, reason, function(d)
		return applyEquip(d, kind, id)
	end)
end

-- 제작 결과 지급(#33 — ForgeService만 부른다). 광석 take · 장비 ids · 토큰을 한 번에 — 하나라도 안 되면 아무것도 안 바뀐다
function InventoryService.craft(player: Player, take: Counts, kind: string, ids: { string }, tokens: TokenCounts, reason: string): boolean
	return run("craft", player, reason, function(d)
		return applyCraft(d, take, kind, ids, tokens)
	end)
end

-- 토큰 교환(#33 — ForgeService만 부른다). 토큰 차감 · 장비 지급을 한 번에
function InventoryService.exchange(player: Player, kind: string, id: string, tokens: TokenCounts, reason: string): boolean
	return run("exchange", player, reason, function(d)
		return applyExchange(d, kind, id, tokens)
	end)
end

-- 강화 +1(#34 — EquipmentService만 부른다). 성공이면 true
function InventoryService.enhance(player: Player, kind: string, id: string, reason: string): boolean
	return run("enhance", player, reason, function(d)
		local ok, info = applyEnhance(d, kind, id)
		return ok, if ok then nil else info
	end)
end

-- 별 +1(#34 — EquipmentService만 부른다)
function InventoryService.starUp(player: Player, kind: string, id: string, reason: string): boolean
	return run("starUp", player, reason, function(d)
		return applyStarUp(d, kind, id)
	end)
end

function InventoryService.openForge(player: Player, reason: string): boolean
	return run("openForge", player, reason, applyOpenForge)
end

-- ===== 읽기 (사본을 준다 — 받은 표를 고쳐도 프로필은 그대로) =========================================

function InventoryService.getOres(player: Player): { number }?
	local data = InventoryService._deps.getData(player)
	return if data ~= nil and type(data.ores) == "table" then table.clone(data.ores) else nil
end

function InventoryService.getTokens(player: Player): TokenCounts?
	local data = InventoryService._deps.getData(player)
	return if data ~= nil and type(data.tokens) == "table" then table.clone(data.tokens) else nil
end

function InventoryService.getEquipped(player: Player, kind: string): string?
	local data = InventoryService._deps.getData(player)
	if data == nil or type(data.equipped) ~= "table" then
		return nil
	end
	local id = data.equipped[kind]
	return if type(id) == "string" then id else nil
end

-- 종류별 가진 장비 전체(사본 — {id = {count, stars, enh}} · 장비 화면 · 데미지 배수 · #34)
function InventoryService.getEquipment(player: Player, kind: string): { [string]: any }?
	local data = InventoryService._deps.getData(player)
	if data == nil or type(data.equipment) ~= "table" or type(data.equipment[kind]) ~= "table" then
		return nil
	end
	return deepCopy(data.equipment[kind])
end

-- 종류별 가진 장비 id → 개수(사본 — 교환소 "보유" 표시 · #33)
function InventoryService.getOwned(player: Player, kind: string): { [string]: number }?
	local data = InventoryService._deps.getData(player)
	if data == nil or type(data.equipment) ~= "table" or type(data.equipment[kind]) ~= "table" then
		return nil
	end
	local out: { [string]: number } = {}
	for id, o in pairs(data.equipment[kind]) do
		out[id] = if type(o) == "table" and type(o.count) == "number" then o.count else 0
	end
	return out
end

function InventoryService.isForgeOpen(player: Player): boolean
	local data = InventoryService._deps.getData(player)
	return data ~= nil and data.forgeOpen == true
end

return InventoryService

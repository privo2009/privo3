--!strict
-- 대장간 창 순수 로직(지시서 #33 — 인스턴스 없음 · EconomyV2ClientTests가 부른다). 판정은 서버다 — 여기는 "무엇을 보여 줄까"만.
--   광석 칸 5개(넣고 빼기 · 가진 개수 넘지 않기) · 게이지(정수 점수 → 칸) · 받을 토큰 글자 · 자동 채우기(공유 bestCombo) ·
--   확률표 줄(공유 oddsFor + formatPctList — 보이는 합 정확히 100% · 0이 아닌 확률은 0%로 보이지 않는다 · #48) · 교환소 줄 · 거부 사유 글자

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local ForgeWindowLogic = {}

ForgeWindowLogic.TOKEN_ORDER = { "rare", "epic", "mythic", "legendary", "next" }
ForgeWindowLogic.EXCHANGE_TABS = { "rare", "epic", "mythic", "legendary", "next" } -- next = ??? (잠긴 칸)

export type Selection = { ores: { number } } -- 넣은 광석 번호(넣은 순서 · 최대 CRAFT_INPUT)

function ForgeWindowLogic.newSelection(): Selection
	return { ores = {} }
end

-- 칸에 이미 넣은 광석 k의 수
function ForgeWindowLogic.usedOf(sel: Selection, k: number): number
	local n = 0
	for _, x in ipairs(sel.ores) do
		if x == k then
			n += 1
		end
	end
	return n
end

-- 광석 k를 다음 빈 칸에 넣는다. 칸이 다 찼거나 가진 개수를 넘으면 false
function ForgeWindowLogic.add(sel: Selection, inv: { number }, k: number): boolean
	if #sel.ores >= Config.CRAFT_INPUT or ForgeWindowLogic.usedOf(sel, k) >= (inv[k] or 0) then
		return false
	end
	table.insert(sel.ores, k)
	return true
end

function ForgeWindowLogic.remove(sel: Selection, index: number): boolean
	if sel.ores[index] == nil then
		return false
	end
	table.remove(sel.ores, index)
	return true
end

-- 인벤토리가 줄어 넣은 광석이 가진 수를 넘으면 넘는 것을 뺀다(제작 · 자동 제작 뒤)
function ForgeWindowLogic.clamp(sel: Selection, inv: { number })
	local i = #sel.ores
	while i >= 1 do
		local k = sel.ores[i]
		if ForgeWindowLogic.usedOf(sel, k) > (inv[k] or 0) then
			table.remove(sel.ores, i)
		end
		i -= 1
	end
end

-- 점수 합 · 찬 칸(넣는 대로 정수 점수로 찬다 — 5개 미만이어도 보인다. 제작은 5개일 때만)
function ForgeWindowLogic.gauge(sel: Selection): (number, number)
	local points = 0
	for _, k in ipairs(sel.ores) do
		points += EconomyV2Logic.gaugePoints(k)
	end
	return points, math.min(points // Config.GAUGE_UNIT, Config.CRAFT_INPUT)
end

function ForgeWindowLogic.isFull(sel: Selection): boolean
	return #sel.ores == Config.CRAFT_INPUT
end

function ForgeWindowLogic.tokenName(key: string): string
	return Locale.t("token." .. key)
end

-- 칸 수 → "받을 토큰" 글자(got = 결과 연출의 "받은 토큰")
function ForgeWindowLogic.tokensText(slots: number, got: boolean?): string
	local tokens = EconomyV2Logic.tokensFor(slots)
	local parts = {}
	for _, key in ipairs(ForgeWindowLogic.TOKEN_ORDER) do
		local n = tokens[key]
		if n ~= nil and n > 0 then
			table.insert(parts, string.format("%s ×%d", ForgeWindowLogic.tokenName(key), n))
		end
	end
	if #parts == 0 then
		return if got then "" else Locale.t("forge.tokens.none")
	end
	return Locale.t(if got then "forge.result.tokens" else "forge.tokens.get", { tokens = table.concat(parts, " · ") })
end

-- 자동 채우기: 가진 광석으로 가장 높은 칸 조합(높은 광석은 아낀다 — 공유 bestCombo). 모자라면 빈 선택
function ForgeWindowLogic.fill(inv: { number }): Selection
	local combo = EconomyV2Logic.bestCombo(inv)
	return { ores = if combo ~= nil then table.clone(combo) else {} }
end

export type OddsLine = { id: string, rarity: string, pct: number, text: string }

-- 칸 수의 15종 확률 줄(rank 순서 · 글자는 0%로 보이지 않게)
function ForgeWindowLogic.oddsLines(slots: number): { OddsLine }
	-- 글자는 표 전체를 한 번에(보이는 합이 정확히 100% — 공식 정책 · #48 재점검. 줄마다 formatPct면 99.9 · 100.1%가 될 수 있었다)
	local rows = EconomyV2Logic.oddsFor(slots)
	local pcts = {}
	for i, row in ipairs(rows) do
		pcts[i] = row.pct
	end
	local texts = EconomyV2Logic.formatPctList(pcts)
	local out = {}
	for i, row in ipairs(rows) do
		table.insert(out, { id = row.id, rarity = row.rarity, pct = row.pct, text = texts[i] })
	end
	return out
end

export type ExchangeLine = { id: string, cost: number, owned: number, can: boolean }

-- 교환소 등급 탭의 줄(그 등급 곡괭이 · 비용 · 보유 수 · 지금 교환 가능). next(???)는 빈 목록 — 잠긴 칸으로 보인다
function ForgeWindowLogic.exchangeLines(rarity: string, tokens: { [string]: number }, owned: { [string]: number }): { ExchangeLine }
	local out = {}
	for _, def in ipairs(Config.PICKAXES) do
		if def.rarity == rarity and def.exchangeCost ~= nil then
			local cost = def.exchangeCost :: number
			table.insert(out, { id = def.id, cost = cost, owned = owned[def.id] or 0, can = (tokens[rarity] or 0) >= cost })
		end
	end
	return out
end

function ForgeWindowLogic.isLockedTab(rarity: string): boolean
	return rarity == Config.NEXT_RARITY
end

-- 서버 거부 사유 → 글자(모르는 사유는 한 문장으로)
function ForgeWindowLogic.reasonText(reason: string?): string
	local known = { not_enough_ore = true, too_soon = true, forge_closed = true, bad_combo = true, not_enough_tokens = true }
	if reason ~= nil and known[reason] then
		return Locale.t("forge.reason." .. reason)
	end
	return Locale.t("forge.reason.other")
end

-- 결과 연출 크기(등급이 좋을수록 조금 더 크게 — 임시). 1 = 일반
function ForgeWindowLogic.resultScale(rarity: string): number
	local order = { common = 1, rare = 1.1, epic = 1.2, mythic = 1.35, legendary = 1.5 }
	return order[rarity] or 1
end

-- 크게 알릴 등급인가(Config.CRAFT_BIG_NOTICE_RARITY 이상)
function ForgeWindowLogic.isBigNotice(rarity: string): boolean
	local idx: { [string]: number } = {}
	for i, r in ipairs(Config.RARITIES) do
		idx[r] = i
	end
	return (idx[rarity] or 0) >= (idx[Config.CRAFT_BIG_NOTICE_RARITY] or math.huge)
end

return ForgeWindowLogic

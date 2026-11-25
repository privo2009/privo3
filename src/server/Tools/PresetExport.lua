--!strict
-- 테스트 프리셋 뽑기(지시서 #38 6단계 — Studio 전용 · TestGate). EconomyReport V4(지금 TEMP — set = {}) 표준 플레이어를 PLAYERS명 돌려
-- 시점마다(TIMES) 그 시각에 처음 런을 시작한 순간의 상태를 모으고, 시점마다 **중앙값 플레이어**(환생 수 → 최고 층 순으로 줄 세운 가운데)
-- 한 사람을 Shared/Config/TestPresets 꼴 Lua 표로 찍는다("[PRESET] …"). 사람이(또는 Claude가) 그 줄을 TestPresets에 옮긴다.
-- 켜는 곳: Bootstrap PRESET_EXPORT_ENABLED(커밋 값 false). 프로필을 읽지도 쓰지도 않는다(시뮬레이터만).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)

local PresetExport = {}

PresetExport.PLAYERS = 40
-- 이름 → 시점(초). 30분은 8층 대장간 뒤 · 2시간은 25층 근처 · 3시간은 15종 무렵(V4 중앙값 — TUNING "새 경제 V4")
PresetExport.TIMES = {
	{ name = "fresh", sec = 0, label = "시작 직후" },
	{ name = "min10", sec = 600, label = "10분" },
	{ name = "min30", sec = 1800, label = "30분(8층 대장간 뒤)" },
	{ name = "hour1", sec = 3600, label = "1시간" },
	{ name = "hour2", sec = 7200, label = "2시간(25층 근처)" },
	{ name = "hour3", sec = 10800, label = "3시간(15종 무렵)" },
}
PresetExport.MAX_PETS = 20 -- 보유 펫은 실효 큰 순으로 이만큼(프로필 크기 · 읽기 쉬움)

local function big(v: any): string
	if type(v) ~= "table" or v.m == 0 then
		return "{ m = 0, e = 0 }"
	end
	return string.format("{ m = %.6f, e = %d }", v.m, v.e)
end

local function snap(p: any, s: any, forgeOpen: boolean): any
	local picks = {}
	for id, o in pairs(s.picks.owned) do
		picks[id] = { count = o.copies + 1, stars = o.stars, enh = o.enh }
	end
	local SRR = require(script.Parent.SuccessRateReport) :: any
	local list = SRR.petList(p)
	local pets = {}
	for i = 1, math.min(#list, PresetExport.MAX_PETS) do
		table.insert(pets, { petId = list[i].petId, tier = list[i].tier })
	end
	local slots = PetConfig.getSlots(p.upgrades.petSlots or 0, false)
	return {
		t = p.elapsedSec,
		strength = table.clone(p.strength),
		blox = table.clone(p.blox),
		lifeBlox = table.clone(p.lifeBlox),
		lifetimeBlox = table.clone(p.lifetimeBlox),
		rebirths = s.n,
		padIndex = p.padIndex,
		maxStage = math.max(1, p.bestThisLife or 1),
		maxEver = s.maxEver,
		upgrades = table.clone(p.upgrades),
		title = if p.titleIndex > 0 then TitleConfig.Titles[p.titleIndex].id else false,
		aura = p.auraId or false,
		pets = pets,
		equippedN = math.min(slots, #pets),
		coins = table.clone(s.coins),
		ores = table.clone(s.inv),
		tokens = table.clone(s.picks.tokens),
		pickaxes = picks,
		equippedPickaxe = s.picks.equipped,
		forgeOpen = forgeOpen,
	}
end

local function render(name: string, label: string, x: any, rank: number, total: number): string
	local lines = {}
	local function add(line: string)
		table.insert(lines, line)
	end
	add(string.format("\t%s = {", name))
	add(string.format("\t\tlabel = %q,", label))
	add(string.format("\t\tsource = %q,", string.format("EconomyReport V4 표준 플레이어 %d명 중 그 시각 중앙값(%d번째 · %.1f분 · 환생 %d회 · 최고 %d층)",
		total, rank, x.t / 60, x.rebirths, x.maxEver)))
	add(string.format("\t\tstrength = %s,", big(x.strength)))
	add(string.format("\t\tblox = %s,", big(x.blox)))
	add(string.format("\t\tlifeBlox = %s,", big(x.lifeBlox)))
	add(string.format("\t\tlifetimeBlox = %s,", big(x.lifetimeBlox)))
	add(string.format("\t\trebirths = %s,", big(BigNum.fromNumber(x.rebirths))))
	add(string.format("\t\tpadIndex = %d, maxStage = %d,", x.padIndex, x.maxStage))
	local ups = {}
	for _, k in ipairs({ "auraLuck", "bloxGain", "petLuck", "petSlots", "punchSpeed", "titleLuck" }) do
		table.insert(ups, string.format("%s = %d", k, x.upgrades[k] or 0))
	end
	add("\t\tupgrades = { " .. table.concat(ups, ", ") .. " },")
	add(string.format("\t\ttitle = %s, aura = %s,", if x.title then string.format("%q", x.title) else "false",
		if x.aura then string.format("%q", x.aura) else "false"))
	local pets = {}
	for _, pet in ipairs(x.pets) do
		table.insert(pets, string.format("{ petId = %q, tier = %d }", pet.petId, pet.tier))
	end
	add("\t\tpets = { " .. table.concat(pets, ", ") .. " },")
	local eq = {}
	for i = 1, x.equippedN do
		table.insert(eq, tostring(i))
	end
	add("\t\tequipped = { " .. table.concat(eq, ", ") .. " },")
	add(string.format("\t\tcoins = %s,", big(x.coins)))
	local ores = {}
	for k = 1, #x.ores do
		table.insert(ores, tostring(x.ores[k]))
	end
	add("\t\tores = { " .. table.concat(ores, ", ") .. " },")
	local toks = {}
	for _, r in ipairs({ "rare", "epic", "mythic", "legendary", "next" }) do
		table.insert(toks, string.format("%s = %d", r, x.tokens[r] or 0))
	end
	add("\t\ttokens = { " .. table.concat(toks, ", ") .. " },")
	local ids = {}
	for id in pairs(x.pickaxes) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local pk = {}
	for _, id in ipairs(ids) do
		local o = x.pickaxes[id]
		table.insert(pk, string.format("%s = { count = %d, stars = %d, enh = %d }", id, o.count, o.stars, o.enh))
	end
	add("\t\tpickaxes = { " .. table.concat(pk, ", ") .. " },")
	add(string.format("\t\tequippedPickaxe = %q, forgeOpen = %s,", x.equippedPickaxe, tostring(x.forgeOpen)))
	add("\t},")
	return table.concat(lines, "\n")
end

function PresetExport.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	local EconomyReport = require(script.Parent.EconomyReport) :: any
	print(string.format("[PRESET] ===== 뽑기 시작 (V4 · %d명)", PresetExport.PLAYERS))
	local byPlayer: { [any]: { [string]: any } } = {}
	local order: { any } = {}
	EconomyReport.snapshots(PresetExport.PLAYERS, function(p: any, s: any, forgeOpen: boolean)
		local got = byPlayer[p]
		if got == nil then
			got = {}
			byPlayer[p] = got
			table.insert(order, p)
		end
		for _, tp in ipairs(PresetExport.TIMES) do
			if got[tp.name] == nil and p.elapsedSec >= tp.sec then
				got[tp.name] = snap(p, s, forgeOpen)
			end
		end
	end)
	for _, tp in ipairs(PresetExport.TIMES) do
		local list = {}
		for _, p in ipairs(order) do
			local x = byPlayer[p][tp.name]
			if x ~= nil then
				table.insert(list, x)
			end
		end
		table.sort(list, function(a, b)
			if a.rebirths ~= b.rebirths then
				return a.rebirths < b.rebirths
			end
			if a.maxEver ~= b.maxEver then
				return a.maxEver < b.maxEver
			end
			return a.t < b.t
		end)
		local mid = math.max(1, math.ceil(#list / 2))
		if list[mid] ~= nil then
			print("[PRESET] " .. tp.name .. "\n" .. render(tp.name, tp.label, list[mid], mid, #list))
		else
			print("[PRESET] " .. tp.name .. " 그 시각에 닿은 플레이어 없음")
		end
		task.wait()
	end
	print("[PRESET] ===== 끝")
end

return PresetExport

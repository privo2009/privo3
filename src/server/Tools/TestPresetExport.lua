--!strict
-- 테스트 프리셋 값 뽑기 (지시서 #13 3단계). Shared/Config/TestPresets의 상수가 **어디서 왔는가**의 원본이다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다 — SuccessRateReport와 같은 시뮬레이터를
--    같은 결정 모델 · 같은 seed로 돌리고 print만 한다. 켜는 곳은 Bootstrap의 TEST_PRESET_EXPORT_ENABLED 하나다.
--    출력(Lua 표 글자)을 TestPresets.lua에 그대로 옮겨 적는다 — 값을 손으로 고치지 않는다.
--
-- ===== 값을 어떻게 고르는가 ===========================================================
--
-- 시점마다 200명 각자가 그 시점에 처음 닿은 순간의 상태를 모으고, **그 시각(분)의 중앙값 플레이어**를 고른다
-- (시각으로 줄 세워 가운데 — 짝수면 앞쪽 가운데. SuccessRateReport median과 같은 규칙). 상태는 한 사람의 것을 통째로 쓴다 —
-- 항목마다 따로 중앙값을 내면 서로 맞지 않는 조합(그 힘에 그 펫은 없는)이 생긴다.
--
--   fresh                  첫 런 직전(신규 프로필과 같다 — 시뮬레이터의 시작 상태가 Schema.new()다)
--   before_first_rebirth   첫 환생 직전(아우라 · 펫 · 업그레이드에 쓰기 전 — 사람이 그 순서를 직접 해 본다)
--   floorN                 N층에 처음 들어간 **그 런을 시작할 때**(스폰에 서 있는 상태 — 프리셋은 스폰에서 시작한다)
--                          N = HP 세그먼트 시작층(9 · 17)과 최고층(25) — WorldConfig에서 읽는다
--   floor25_cleared        최고층을 처음 깬 런이 끝난 뒤(수령까지 끝난 상태 — 최종층 벽 확인용)
--
-- 칭호 자동 롤은 꺼 둔다(autoRollTitle false — 켜 두면 Play 시작부터 블럭스가 빠져 상태가 흘러간다. 켜는 것은 사람이 한다).
-- 보유 칭호 · 아우라는 장착 중인 것 하나다(시뮬레이터는 가장 높은 것만 기억한다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)

local SuccessRateReport = require(script.Parent.SuccessRateReport)
local RollService = require(script.Parent.Parent.Systems.RollService)

type BigNumber = BigNum.BigNumber

local TestPresetExport = {}

export type Snapshot = {
	t: number, -- 경과 초
	strength: BigNumber,
	blox: BigNumber,
	lifeBlox: BigNumber,
	lifetimeBlox: BigNumber,
	rebirths: BigNumber,
	padIndex: number,
	maxStage: number,
	upgrades: { [string]: number },
	titleIndex: number,
	auraId: string?,
	pets: { [string]: number }, -- "petId:단계" → 마리 수
	rebirthCount: number,
}

local function copyBig(v: BigNumber): BigNumber
	return BigNum.new(v.m, v.e)
end

function TestPresetExport.snapshot(p: SuccessRateReport.Player, maxStage: number): Snapshot
	return {
		t = p.elapsedSec,
		strength = copyBig(p.strength),
		blox = copyBig(p.blox),
		lifeBlox = copyBig(p.lifeBlox),
		lifetimeBlox = copyBig(p.lifetimeBlox),
		rebirths = copyBig(p.rebirths),
		padIndex = p.padIndex,
		maxStage = math.max(1, maxStage),
		upgrades = table.clone(p.upgrades),
		titleIndex = p.titleIndex,
		auraId = p.auraId,
		pets = table.clone(p.pets),
		rebirthCount = p.rebirthCount,
	}
end

-- 시점 이름 목록(출력 순서). floorN은 WorldConfig 세그먼트에서 유도한다.
function TestPresetExport.milestoneStages(): { number }
	local world = WorldConfig.get(SuccessRateReport.SIM.WORLD_ID) :: WorldConfig.WorldDef
	local out: { number } = {}
	for i = 2, #world.hpGrowthSegments do
		table.insert(out, world.hpGrowthSegments[i].from)
	end
	local last = 1
	while StageConfig.hasStage(last + 1) do
		last += 1
	end
	table.insert(out, last)
	return out
end

-- 한 사람 몫의 관측기. 시점 이름 → 스냅샷.
function TestPresetExport.newObserver(stages: { number }, maxStage: number)
	local got: { [string]: Snapshot } = {}
	local runStart: Snapshot? = nil
	local hadBefore: { [number]: boolean } = {}
	local function observe(event: string, p: SuccessRateReport.Player, seen: { [number]: boolean }, reached: number?)
		if event == "run_start" then
			if got.fresh == nil then
				got.fresh = TestPresetExport.snapshot(p, p.bestThisLife)
			end
			runStart = TestPresetExport.snapshot(p, p.bestThisLife)
			for _, s in ipairs(stages) do
				hadBefore[s] = seen[s] == true
			end
		elseif event == "run_end" then
			for _, s in ipairs(stages) do
				local key = "floor" .. s
				if got[key] == nil and seen[s] and not hadBefore[s] and runStart ~= nil then
					got[key] = runStart
				end
			end
			if got.floor_cleared == nil and reached ~= nil and reached >= maxStage then
				got.floor_cleared = TestPresetExport.snapshot(p, maxStage)
			end
		elseif event == "rebirth_before" then
			if got.before_first_rebirth == nil and p.rebirthCount == 0 then
				got.before_first_rebirth = TestPresetExport.snapshot(p, p.bestThisLife)
			end
		end
	end
	return observe, got
end

export type Picked = { snap: Snapshot, player: number, count: number }

-- 시점마다 시각 중앙값 플레이어. 닿은 사람이 없으면 nil.
function TestPresetExport.pickMedian(all: { { [string]: Snapshot } }, key: string): Picked?
	local list: { { snap: Snapshot, player: number } } = {}
	for i, got in ipairs(all) do
		if got[key] ~= nil then
			table.insert(list, { snap = got[key], player = i })
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		if a.snap.t ~= b.snap.t then
			return a.snap.t < b.snap.t
		end
		return a.player < b.player
	end)
	local mid = list[math.floor((#list + 1) / 2)]
	return { snap = mid.snap, player = mid.player, count = #list }
end

-- 결정 모델 · 같은 seed로 돌린다(SuccessRateReport.runModel과 같은 난수열 — 플레이어 i는 리포트의 플레이어 i와 같은 사람이다).
function TestPresetExport.collect(players: number?, noYield: boolean?): ({ { [string]: Snapshot } }, number)
	local SIM = SuccessRateReport.SIM
	local stages = TestPresetExport.milestoneStages()
	local maxStage = stages[#stages]
	local rng = Random.new(SIM.SEED)
	local titleRandom = RollService.seededRandom(SIM.TITLE_SEED)
	local auraRandom = RollService.seededRandom(SIM.AURA_SEED)
	local petRandom = RollService.seededRandom(SIM.PET_SEED)
	local firstTry = {}
	local all: { { [string]: Snapshot } } = {}
	for _ = 1, players or SIM.PLAYERS do
		local observe, got = TestPresetExport.newObserver(stages, maxStage)
		SuccessRateReport.simulatePlayer(rng, maxStage, firstTry, titleRandom, auraRandom, petRandom, { observer = observe, untilFinalClear = true })
		table.insert(all, got)
		if not noYield then
			task.wait()
		end
	end
	return all, maxStage
end

-- ===== 출력 (TestPresets.lua에 옮길 Lua 표) ===================================================

local function bigText(v: BigNumber): string
	return string.format("{ m = %.12g, e = %d }", v.m, v.e)
end

-- 스냅샷 → 프리셋 표 값. 펫은 실효 증가분 큰 순(SuccessRateReport.petList — 게임 equipBest와 같은 순서)이고 장착은 앞에서 슬롯 수만큼.
function TestPresetExport.toPreset(snap: Snapshot): { [string]: any }
	local list = SuccessRateReport.petList({ pets = snap.pets } :: any)
	local pets = {}
	for _, pet in ipairs(list) do
		table.insert(pets, { petId = pet.petId, tier = pet.tier })
	end
	local slots = PetConfig.getSlots(snap.upgrades.petSlots or 0, false)
	local equipped = {}
	for i = 1, math.min(slots, #pets) do
		table.insert(equipped, i)
	end
	return {
		strength = snap.strength,
		blox = snap.blox,
		lifeBlox = snap.lifeBlox,
		lifetimeBlox = snap.lifetimeBlox,
		rebirths = snap.rebirths,
		padIndex = snap.padIndex,
		maxStage = snap.maxStage,
		upgrades = snap.upgrades,
		title = if snap.titleIndex > 0 then TitleConfig.Titles[snap.titleIndex].id else false,
		aura = snap.auraId or false,
		pets = pets,
		equipped = equipped,
	}
end

function TestPresetExport.toLuaLines(name: string, label: string, source: string, preset: { [string]: any }): { string }
	local lines = {}
	table.insert(lines, string.format("\t%s = {", name))
	table.insert(lines, string.format("\t\tlabel = %q,", label))
	table.insert(lines, string.format("\t\tsource = %q,", source))
	for _, k in ipairs({ "strength", "blox", "lifeBlox", "lifetimeBlox", "rebirths" }) do
		table.insert(lines, string.format("\t\t%s = %s,", k, bigText(preset[k])))
	end
	table.insert(lines, string.format("\t\tpadIndex = %d, maxStage = %d,", preset.padIndex, preset.maxStage))
	local names = {}
	for k in pairs(preset.upgrades) do
		table.insert(names, k)
	end
	table.sort(names)
	local ups = {}
	for _, k in ipairs(names) do
		table.insert(ups, string.format("%s = %d", k, preset.upgrades[k]))
	end
	table.insert(lines, "\t\tupgrades = { " .. table.concat(ups, ", ") .. " },")
	table.insert(lines, string.format("\t\ttitle = %s, aura = %s,",
		if preset.title then string.format("%q", preset.title) else "false",
		if preset.aura then string.format("%q", preset.aura) else "false"))
	table.insert(lines, "\t\tpets = {")
	local row = {}
	for i, pet in ipairs(preset.pets) do
		table.insert(row, string.format("{ petId = %q, tier = %d }", pet.petId, pet.tier))
		if #row == 3 or i == #preset.pets then
			table.insert(lines, "\t\t\t" .. table.concat(row, ", ") .. ",")
			row = {}
		end
	end
	table.insert(lines, "\t\t},")
	local eq = {}
	for _, i in ipairs(preset.equipped) do
		table.insert(eq, tostring(i))
	end
	table.insert(lines, "\t\tequipped = { " .. table.concat(eq, ", ") .. " },")
	table.insert(lines, "\t},")
	return lines
end

-- 이름 · 화면 이름 · 관측 키. 이름은 TestPresets.NAMES와 같은 순서다(테스트가 대조한다).
function TestPresetExport.entries(maxStage: number, stages: { number }): { { name: string, label: string, key: string } }
	local out = {
		{ name = "fresh", label = "시작 직후", key = "fresh" },
		{ name = "before_first_rebirth", label = "첫 환생 직전", key = "before_first_rebirth" },
	}
	for _, s in ipairs(stages) do
		table.insert(out, { name = "floor" .. s, label = string.format("%d층 첫 도달", s), key = "floor" .. s })
	end
	table.insert(out, { name = string.format("floor%d_cleared", maxStage), label = string.format("%d층 클리어 직후", maxStage), key = "floor_cleared" })
	return out
end

function TestPresetExport.run()
	local SIM = SuccessRateReport.SIM
	print("[PRESET] ===== 테스트 프리셋 값 (TestPresets.lua에 그대로 옮긴다) =====")
	local startedAt = os.clock()
	local all, maxStage = TestPresetExport.collect()
	local stages = TestPresetExport.milestoneStages()
	print(string.format("[PRESET] 결정 모델 · 플레이어 %d · seed %d/%d/%d/%d · 계산 %.1f초", SIM.PLAYERS, SIM.SEED, SIM.TITLE_SEED, SIM.AURA_SEED, SIM.PET_SEED, os.clock() - startedAt))
	for _, entry in ipairs(TestPresetExport.entries(maxStage, stages)) do
		local picked = TestPresetExport.pickMedian(all, entry.key)
		if picked == nil then
			print(string.format("[PRESET] -- %s: 닿은 사람이 없다", entry.name))
		else
			local source = string.format(
				"결정 모델 200명 중 그 시각 중앙값(플레이어 %d번 · %.1f분 · 닿은 %d명 · 환생 %d회)",
				picked.player, picked.snap.t / 60, picked.count, picked.snap.rebirthCount
			)
			for _, line in ipairs(TestPresetExport.toLuaLines(entry.name, entry.label, source, TestPresetExport.toPreset(picked.snap))) do
				print("[PRESET] " .. line)
			end
		end
	end
	print("[PRESET] 끝.")
end

return TestPresetExport

--!strict
-- 튜닝 요약 (지시서 #13 6단계). Play 한 번에 핵심 지표를 30줄 안팎으로 찍는다 — 사람이 값을 바꾼 뒤 이것만 켜고 읽는다.
-- 사용법은 docs/TUNING.md(사람용). 켜는 곳은 Bootstrap의 BALANCE_SUMMARY_ENABLED 하나다.
--
-- ⚠️ 개발 도구다. 프로필을 읽지도 쓰지도 않는다. 계산은 전부 다른 리포트의 같은 함수다 — 여기서 다시 세우지 않는다:
--   성공률 · 25층 중앙값 · 환생 · 뽑기 분포 · 레벨 상한   SuccessRateReport.measure(결정 모델 — 지금 Config 그대로)
--   절벽 판정(16→17 · 8→9, 임계 2.0)                      StandardPathReport.simulateAll · cliffRatio
--   목표 밖 층                                              SuccessRateReport.TARGETS ± TARGET_TOLERANCE
-- 출력은 [BALANCE] 줄. 줄 만들기(lines)와 찍기(run)를 나눠 둔다 — 테스트가 합성 값으로 줄을 잰다.
--
-- 자동 진행(안전층 반복) 줄 — 지시서 #18 AA14. 보고만 한다(게임 수치를 바꾸지 않는다).
--   대상: 테스트 프리셋 floor9 · floor17 · floor25(그 시각 중앙값 플레이어 — Shared/Config/TestPresets)
--   자동: D · 안전층 = AutoAdvanceLogic(서버 AutoAdvanceService와 같은 함수) · 1펀치 데미지 = 힘 × AttackService 결합 배수
--         런 길이 = 층마다 (필요 펀치 − 0.5) × 펀치 간격(첫 펀치 위상 평균) + 진행 지연 × (안전층 − 1) + 반복 대기(AutoAdvanceConfig)
--         수령 = 안전층 보상 × 블럭스 배수(ChallengeService.combineBloxMultiplier). 자동 중에는 클릭하지 않는다(힘이 그대로)
--   손 플레이 모델: 같은 프리셋 상태에서 SuccessRateReport.runOnce를 AUTO_MANUAL_RUNS번(매번 처음 상태 · 클릭률 · 진행 문턱은
--         결정 모델 범위에서 난수) — 걷기 · 런 중 클릭 · 진행 판단 · 실패 0이 들어 있다. 분당 = 수령 합 ÷ 런 시간 합

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)

local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local TestPresets = require(ReplicatedStorage.Shared.Config.TestPresets)
local AutoAdvanceConfig = require(ReplicatedStorage.Shared.Config.AutoAdvanceConfig)
local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)

local SuccessRateReport = require(script.Parent.SuccessRateReport)
local StandardPathReport = require(script.Parent.StandardPathReport)

type BigNumber = BigNum.BigNumber

local BalanceSummary = {}

BalanceSummary.PREFIX = "[BALANCE] "

local function median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	table.sort(xs)
	return xs[math.floor((#xs + 1) / 2)]
end

local function pct(x: number?): string
	return if x ~= nil then string.format("%.1f%%", x * 100) else "-"
end

local function num(x: number?, fmt: string): string
	return if x ~= nil then string.format(fmt, x) else "-"
end

-- 칭호 · 아우라 · 펫 분포 한 줄씩(최고층 첫 진입 시점 장착 기준 — SuccessRateReport 결과 필드).
function BalanceSummary.drawLines(results: { SuccessRateReport.PlayerResult }): { string }
	local titleCounts: { [number]: number } = {}
	local auraCounts: { [string]: number } = {}
	local petMults: { number } = {}
	local levelCounts: { [number]: number } = {}
	for _, r in ipairs(results) do
		titleCounts[r.finalTitleIndex] = (titleCounts[r.finalTitleIndex] or 0) + 1
		local _, packId, tier = AuraConfig.get(r.finalAuraId)
		local key = if packId ~= nil and tier ~= nil then tostring(r.finalAuraId) else "없음" -- id(지시서 #L1 K6 — 리포트는 이름 대신 id)
		auraCounts[key] = (auraCounts[key] or 0) + 1
		table.insert(petMults, PetConfig.totalMult(r.finalPets :: any))
		for _, pet in ipairs(r.finalPets) do
			levelCounts[pet.tier] = (levelCounts[pet.tier] or 0) + 1
		end
	end
	local titleParts = {}
	for i = #TitleConfig.Titles, 0, -1 do
		local n = titleCounts[i]
		if n ~= nil and n > 0 then
			table.insert(titleParts, string.format("%s %d", if i == 0 then "없음" else TitleConfig.Titles[i].id, n))
		end
	end
	local auraKeys = {}
	for k in pairs(auraCounts) do
		table.insert(auraKeys, k)
	end
	table.sort(auraKeys, function(a, b)
		return auraCounts[a] > auraCounts[b] or (auraCounts[a] == auraCounts[b] and a < b)
	end)
	local auraParts = {}
	for i = 1, math.min(4, #auraKeys) do
		table.insert(auraParts, string.format("%s %d", auraKeys[i], auraCounts[auraKeys[i]]))
	end
	local levelParts = {}
	for level = 1, PetConfig.MAX_LEVEL do
		table.insert(levelParts, string.format("L%d %d", level, levelCounts[level] or 0))
	end
	return {
		"칭호(25층 첫 진입 때 장착) " .. table.concat(titleParts, " · "),
		"아우라(많은 순 4) " .. table.concat(auraParts, " · ") .. string.format(" (종류 %d)", #auraKeys),
		string.format("펫 배수 중앙값 ×%s · 장착 펫 단계 %s", num(median(petMults), "%.2f"), table.concat(levelParts, " · ")),
	}
end

export type Cliff = { boundary: number, ratios: { { clickRate: number, ratio: number? } } }

-- 줄 만들기. m · results = SuccessRateReport.measure, cliffs = 경계마다 클릭률별 비율, pathFinal = 클릭률별 25층 도달 분.
function BalanceSummary.lines(m: SuccessRateReport.Metrics, results: { SuccessRateReport.PlayerResult }, cliffs: { Cliff },
	pathFinal: { { clickRate: number, minutes: number? } }): { string }
	local SIM = SuccessRateReport.SIM
	local MODEL = SuccessRateReport.MODEL
	local world = WorldConfig.get(SIM.WORLD_ID) :: WorldConfig.WorldDef
	local growths = {}
	for _, seg in ipairs(world.hpGrowthSegments) do
		table.insert(growths, string.format("%g", seg.growth))
	end
	local out: { string } = {}
	local function add(s: string)
		table.insert(out, s)
	end
	add("===== 튜닝 요약 (BALANCE_SUMMARY) =====")
	add(string.format("조건: 플레이어 %d명 · seed %d(칭호 %d · 아우라 %d · 펫 %d) · 월드 %d", m.players, SIM.SEED, SIM.TITLE_SEED, SIM.AURA_SEED, SIM.PET_SEED, SIM.WORLD_ID))
	add(string.format("모델: 클릭 %g~%g/초 · 진행 문턱 %g~%g%% · 업그레이드 %s · 칭호 %s · 아우라 %s(%g%%) · 펫 %s(%g%%) · 운동기구 %g초",
		MODEL.CLICK_RATE_MIN, MODEL.CLICK_RATE_MAX, MODEL.ADVANCE_THRESHOLD_MIN * 100, MODEL.ADVANCE_THRESHOLD_MAX * 100,
		MODEL.UPGRADE_POLICY, MODEL.TITLE_POLICY, MODEL.AURA_POLICY, MODEL.AURA_REBIRTH_SHARE * 100, MODEL.PET_POLICY,
		MODEL.PET_REBIRTH_SHARE * 100, MODEL.GYM_TRAIN_SEC))
	add("HP 성장률(WorldConfig): " .. table.concat(growths, " / ") .. string.format(" · CRAFT_FACTOR %g", PetConfig.CRAFT_FACTOR))
	add("--- 성공률 (첫 도달, 목표는 SuccessRateReport.TARGETS ±10%p) ---")
	for i, seg in ipairs(m.segments) do
		local t = SuccessRateReport.TARGETS[i]
		local ok = seg.rate ~= nil and t ~= nil and seg.rate >= t.min - SuccessRateReport.TARGET_TOLERANCE and seg.rate <= t.max + SuccessRateReport.TARGET_TOLERANCE
		add(string.format("%d~%d층  %s  (층별 %s~%s · 목표 %s~%s) %s", seg.from, seg.to, pct(seg.rate), pct(seg.lowest), pct(seg.highest),
			if t ~= nil then pct(t.min) else "-", if t ~= nil then pct(t.max) else "-", if ok then "안" else "⚠️ 밖"))
	end
	local oob = {}
	for stage = 1, m.maxStage do
		local r = m.floorRates[stage]
		local t = SuccessRateReport.targetFor(stage)
		if r ~= nil and t ~= nil and (r < t.min - SuccessRateReport.TARGET_TOLERANCE or r > t.max + SuccessRateReport.TARGET_TOLERANCE) then
			table.insert(oob, string.format("%d층 %d%%", stage, math.floor(r * 100 + 0.5)))
		end
	end
	add("목표 ±10%p 밖 층: " .. (if #oob > 0 then table.concat(oob, " · ") else "없음"))
	local cells = {}
	for stage = 1, m.maxStage do
		local r = m.floorRates[stage]
		table.insert(cells, if r ~= nil then string.format("%d", math.floor(r * 100 + 0.5)) else "-")
	end
	add("층별% 1→" .. m.maxStage .. ": " .. table.concat(cells, " "))
	add("--- 시간 · 환생 ---")
	add(string.format("%d층 첫 진입 중앙값 %s분 (%d/%d명) · 평균 런 %.0f · 평균 환생 %.1f회 · 그때 환생 수 중앙값 %s",
		m.maxStage, num(m.medianFinalMin, "%.1f"), m.reached, m.players, m.meanRuns, m.meanRebirths,
		if m.medianRebirthLog ~= nil then string.format("10^%.2f", m.medianRebirthLog) else "-"))
	add(string.format("레벨 상한(레벨 %d · 최대 속도 %g) 첫 도달 중앙값 %s분 · %s층 (%d명이 %d층 전에 닿음)",
		LevelConfig.getSpeedCapLevel(), LevelConfig.getMaxWalkSpeed(), num(m.medianLevelCapMin, "%.1f"),
		if m.medianLevelCapStage ~= nil then tostring(m.medianLevelCapStage) else "-", m.levelCapReached, m.maxStage))
	local pathParts = {}
	for _, p in ipairs(pathFinal) do
		table.insert(pathParts, string.format("클릭 %d → %s분", p.clickRate, num(p.minutes, "%.1f")))
	end
	add("표준 경로(시간 축, 이론 상한) 25층 도달: " .. table.concat(pathParts, " · "))
	add("--- 뽑기 분포 ---")
	for _, line in ipairs(BalanceSummary.drawLines(results)) do
		add(line)
	end
	add(string.format("--- 절벽 판정 (StandardPathReport, 임계 %.1f배 — 보기 전에 고정) ---", StandardPathReport.CLIFF_RATIO_THRESHOLD))
	for _, c in ipairs(cliffs) do
		local parts = {}
		local any = false
		for _, r in ipairs(c.ratios) do
			if r.ratio ~= nil and r.ratio >= StandardPathReport.CLIFF_RATIO_THRESHOLD then
				any = true
			end
			table.insert(parts, string.format("클릭 %d %s", r.clickRate, num(r.ratio, "%.2f")))
		end
		add(string.format("%d→%d층  %s  → %s", c.boundary, c.boundary + 1, table.concat(parts, " · "), if any then "절벽 실재(그 클릭률)" else "절벽 없음"))
	end
	add("끝. 자세히: SuccessRateReport · StandardPathReport · HpCandidateReport 플래그 (docs/TUNING.md)")
	return out
end

-- ===== 자동 진행(안전층 반복) — 지시서 #18 AA14 ==========================================

BalanceSummary.AUTO_PRESETS = { "floor9", "floor17", "floor25" }
BalanceSummary.AUTO_MANUAL_RUNS = 200 -- 손 플레이 모델 비교 런 수(관측 해상도 — 게임 수치 아님)
BalanceSummary.AUTO_MANUAL_SEED = 20261031

-- 프리셋 상태를 시뮬레이터 플레이어로 옮긴다(TestPresetExport의 반대 방향). 클릭률 · 진행 문턱은 rng로(결정 모델 범위).
function BalanceSummary.presetPlayer(name: string, rng: Random): SuccessRateReport.Player
	local preset = TestPresets.Presets[name]
	assert(preset ~= nil, "알 수 없는 프리셋: " .. tostring(name))
	local p = SuccessRateReport.newPlayer(rng)
	local function big(v: { m: number, e: number }): BigNumber
		return BigNum.new(v.m, v.e)
	end
	p.strength = big(preset.strength)
	p.blox = big(preset.blox)
	p.lifeBlox = big(preset.lifeBlox)
	p.lifetimeBlox = big(preset.lifetimeBlox)
	p.rebirths = big(preset.rebirths)
	p.padIndex = preset.padIndex
	p.bestThisLife = preset.maxStage
	for key, level in pairs(preset.upgrades) do
		p.upgrades[key] = level
	end
	p.titleIndex = 0
	if preset.title ~= false then
		for i, def in ipairs(TitleConfig.Titles) do
			if def.id == preset.title then
				p.titleIndex = i
			end
		end
	end
	p.auraId = if preset.aura ~= false then preset.aura else nil
	for _, pet in ipairs(preset.pets) do
		local key = pet.petId .. ":" .. tostring(pet.tier)
		p.pets[key] = (p.pets[key] or 0) + 1
	end
	return p
end

export type AutoRow = {
	preset: string,
	d: BigNumber,
	safeFloor: number,
	reward: BigNumber,
	runSec: number?,
	perMin: BigNumber?,
}

-- 자동 진행 한 런(목표 = 안전층). 순수 — 플레이어를 바꾸지 않는다.
function BalanceSummary.autoRow(preset: string, p: SuccessRateReport.Player): AutoRow
	local damage = BigNum.mul(p.strength, BigNum.fromNumber(SuccessRateReport.damageMultiplier(p)))
	local rate = SuccessRateReport.effect(p.upgrades, "punchSpeed")
	local d = AutoAdvanceLogic.dealTotal(damage, rate, StageConfig.CHALLENGE_TIMER_SEC)
	local safe = AutoAdvanceLogic.safeFloor(damage, rate)
	if safe <= 0 then
		return { preset = preset, d = d, safeFloor = 0, reward = BigNum.new(0, 0), runSec = nil, perMin = nil }
	end
	local interval = 1 / rate
	local sec = AutoAdvanceConfig.ADVANCE_DELAY_SEC * (safe - 1) + AutoAdvanceConfig.REPEAT_DELAY_SEC
	for stage = AutoAdvanceLogic.FIRST_STAGE, safe do
		local punches = math.max(1, math.ceil(BigNum.toRatio(StageConfig.getTotalHp(stage), damage) - 1e-9))
		sec += (punches - 0.5) * interval
	end
	local reward = BigNum.mul(StageConfig.getBloxReward(safe), BigNum.fromNumber(SuccessRateReport.bloxMultiplier(p)))
	return { preset = preset, d = d, safeFloor = safe, reward = reward, runSec = sec, perMin = BigNum.mul(reward, BigNum.fromNumber(60 / sec)) }
end

export type ManualRow = { meanReward: BigNumber, meanSec: number, perMin: BigNumber, medianBest: number, failShare: number }

-- 손 플레이 모델: 같은 프리셋 상태에서 runs번(매번 처음 상태로). 실패(보상 0)도 평균에 든다.
function BalanceSummary.manualRow(preset: string, runs: number, seed: number): ManualRow
	local rng = Random.new(seed)
	local total = BigNum.new(0, 0)
	local secSum = 0
	local bests: { number } = {}
	local fails = 0
	for _ = 1, runs do
		local p = BalanceSummary.presetPlayer(preset, rng)
		local best = SuccessRateReport.runOnce(p, rng, {}, {})
		local reward = p.lastRunReward or BigNum.new(0, 0)
		if reward.m <= 0 then
			fails += 1
		end
		total = BigNum.add(total, reward)
		secSum += p.lastRunSec or 0
		table.insert(bests, best)
	end
	return {
		meanReward = BigNum.mul(total, BigNum.fromNumber(1 / math.max(1, runs))),
		meanSec = secSum / math.max(1, runs),
		perMin = if secSum > 0 then BigNum.mul(total, BigNum.fromNumber(60 / secSum)) else BigNum.new(0, 0),
		medianBest = median(bests) or 0,
		failShare = fails / math.max(1, runs),
	}
end

export type AutoPair = { auto: AutoRow, manual: ManualRow? }

function BalanceSummary.autoLines(rows: { AutoPair }): { string }
	local out = { string.format("--- 자동 진행(안전층 반복 · 목표 = 안전층 · 진행 지연 %gs · 반복 대기 %gs) vs 손 플레이 모델 ---",
		AutoAdvanceConfig.ADVANCE_DELAY_SEC, AutoAdvanceConfig.REPEAT_DELAY_SEC) }
	for _, r in ipairs(rows) do
		local a = r.auto
		local autoPart = if a.runSec ~= nil and a.perMin ~= nil
			then string.format("D %s · 안전층 %d · 수령 %s · 런 %.1fs · 분당 %s", Formatter.format(a.d), a.safeFloor, Formatter.format(a.reward),
				a.runSec, Formatter.format(a.perMin))
			else string.format("D %s · 안전층 0(1층도 20초 안에 못 깬다) · 자동 반복 없음", Formatter.format(a.d))
		local manualPart = "-"
		local ratio = "-"
		local mrow = r.manual
		if mrow ~= nil then
			manualPart = string.format("수령 %s · 런 %.1fs · 분당 %s · 최고층 중앙 %d · 실패 %d%%", Formatter.format(mrow.meanReward), mrow.meanSec,
				Formatter.format(mrow.perMin), mrow.medianBest, math.floor(mrow.failShare * 100 + 0.5))
			if a.perMin ~= nil and mrow.perMin.m > 0 then
				ratio = string.format("×%.2f", BigNum.toRatio(a.perMin, mrow.perMin))
			end
		end
		table.insert(out, string.format("%s  자동 %s", a.preset, autoPart))
		table.insert(out, string.format("%s  손 %s  → 자동/손 분당 %s", a.preset, manualPart, ratio))
	end
	table.insert(out, "자동은 클릭하지 않는다(힘 그대로) · 손 모델은 걷기 · 런 중 클릭 · 진행 판단 · 실패 0 포함 (docs/TUNING.md)")
	return out
end

function BalanceSummary.autoRows(): { AutoPair }
	local rows: { AutoPair } = {}
	for i, name in ipairs(BalanceSummary.AUTO_PRESETS) do
		local p = BalanceSummary.presetPlayer(name, Random.new(BalanceSummary.AUTO_MANUAL_SEED))
		table.insert(rows, {
			auto = BalanceSummary.autoRow(name, p),
			manual = BalanceSummary.manualRow(name, BalanceSummary.AUTO_MANUAL_RUNS, BalanceSummary.AUTO_MANUAL_SEED + i),
		})
	end
	return rows
end

function BalanceSummary.run()
	task.wait(5) -- 시작 직후 테스트들이 MODEL · Config를 잠깐 흔드는 동안 기다린다
	local startedAt = os.clock()
	local m, results = SuccessRateReport.measure()
	local rates = StandardPathReport.simulateAll(m.maxStage)
	local cliffs: { Cliff } = {}
	local boundaries = StandardPathReport.boundaries()
	for i = #boundaries, 1, -1 do
		local b = boundaries[i]
		local ratios = {}
		for _, result in ipairs(rates) do
			local _, _, ratio = StandardPathReport.cliffRatio(result, b.stage)
			table.insert(ratios, { clickRate = result.clickRate, ratio = ratio })
		end
		table.insert(cliffs, { boundary = b.stage, ratios = ratios })
	end
	local pathFinal = {}
	for _, result in ipairs(rates) do
		local last = result.records[m.maxStage]
		table.insert(pathFinal, { clickRate = result.clickRate, minutes = if last ~= nil then last.elapsedSec / 60 else nil })
	end
	for _, line in ipairs(BalanceSummary.lines(m, results, cliffs, pathFinal)) do
		print(BalanceSummary.PREFIX .. line)
	end
	for _, line in ipairs(BalanceSummary.autoLines(BalanceSummary.autoRows())) do
		print(BalanceSummary.PREFIX .. line)
	end
	print(BalanceSummary.PREFIX .. string.format("(계산 %.1f초)", os.clock() - startedAt))
end

return BalanceSummary

--!strict
-- HP 곡선 후보 측정 (지시서 #13 5단계). ⚠️ 측정 도구다 — 채택하지 않는다(D2: 채택은 사람이 한다).
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다. WorldConfig를 고치지 않는다 —
--    후보마다 hpGrowthSegments의 **성장률 세 값만** 메모리에서 잠깐 갈아끼우고(구간 경계 · hpBase · 보상 곡선은 그대로)
--    끝나면 되돌린다(SuccessRateReport CURVE_VARIANTS와 같은 패턴). 켜는 곳은 Bootstrap의 HP_CANDIDATE_REPORT_ENABLED 하나다.
--
-- 후보 목록(자세히 볼 것)은 SuccessRateReport.CURVE_VARIANTS가 원본이고, 측정 기록은 그 표 위 주석에 남긴다.
-- 이 파일은 (1) 기준점 B4 (2) 넓게 훑기 격자 (3) 후보마다 자세한 지표를 찍는다.
--
-- 후보마다 찍는 것(지시서 #13 5단계):
--   구간 성공률 3개 · 목표 ±10%p 밖인 층 · 25층 첫 진입 중앙값 · 환생 횟수        (SuccessRateReport 결정 모델)
--   층별 체류(분, 클릭률 8) · 절벽 판정 16→17 · 8→9 (클릭률 6 · 8 · 10)           (StandardPathReport — 같은 함수)
--   기존 한도 여유: 아우라 = 펫 없음 중앙값 − 0.9 × 아우라 · 펫 없음 중앙값(#11 기준)
--                   펫 · CRAFT_FACTOR = 결정 중앙값 − 0.9 × 펫 없음 중앙값(#12 기준). 양수면 한도 안

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local SuccessRateReport = require(script.Parent.SuccessRateReport)
local StandardPathReport = require(script.Parent.StandardPathReport)

local HpCandidateReport = {}

-- 넓게 훑기 격자(관측 해상도 — 게임 수치가 아니다). 곡선 규약(각 값 > 보상 성장률 · 1 < 2 < 3)을 깨는 조합은 WorldConfig.validate가 거른다.
HpCandidateReport.GRID = {
	{ 2.75, 2.8, 2.9 },
	{ 3.6, 3.8, 4.0, 4.3 },
	{ 6.0, 6.5, 7.0, 7.5, 8.0, 9.0 },
}
HpCandidateReport.RUN_SWEEP = false -- true면 넓게 훑기(GRID 72개, 약 7분)도 돈다. 커밋 값 false(후보 자세히만 — 약 4분)

-- 성장률 세 값만 갈아끼운 채 fn을 돈다. 규약 위반이면 fn을 부르지 않고 (false, 에러)를 돌려준다. 언제나 되돌린다.
function HpCandidateReport.withGrowths(growths: { number }, fn: () -> ()): (boolean, any)
	local world = WorldConfig.get(SuccessRateReport.SIM.WORLD_ID) :: WorldConfig.WorldDef
	local original = world.hpGrowthSegments
	assert(#growths == #original, "HpCandidateReport: 세그먼트 수가 다르다")
	local swapped = {}
	for i, seg in ipairs(original) do
		swapped[i] = { from = seg.from, to = seg.to, growth = growths[i] }
	end
	world.hpGrowthSegments = swapped
	local ok, err = pcall(function()
		WorldConfig.validate()
		fn()
	end)
	world.hpGrowthSegments = original
	return ok, err
end

local function withModel(override: { [string]: any }, fn: () -> ())
	local MODEL = SuccessRateReport.MODEL :: any
	local saved = {}
	for k, v in pairs(override) do
		saved[k] = MODEL[k]
		MODEL[k] = v
	end
	local ok, err = pcall(fn)
	for k, v in pairs(saved) do
		MODEL[k] = v
	end
	if not ok then
		error(err)
	end
end

local function pct(x: number?): string
	return if x ~= nil then string.format("%.1f", x * 100) else "-"
end

-- 목표 ±10%p(측정 규약) 밖인 층 → "층 %" 목록.
function HpCandidateReport.outOfBand(m: SuccessRateReport.Metrics): { string }
	local out = {}
	for stage = 1, m.maxStage do
		local r = m.floorRates[stage]
		local target = SuccessRateReport.targetFor(stage)
		if r ~= nil and target ~= nil then
			local tol = SuccessRateReport.TARGET_TOLERANCE
			if r < target.min - tol or r > target.max + tol then
				table.insert(out, string.format("%d층 %d%%", stage, math.floor(r * 100 + 0.5)))
			end
		end
	end
	return out
end

local function growthText(growths: { number }): string
	local parts = {}
	for _, g in ipairs(growths) do
		table.insert(parts, string.format("%g", g))
	end
	return table.concat(parts, " / ")
end

local function compactLine(label: string, m: SuccessRateReport.Metrics): string
	local segs = {}
	for _, s in ipairs(m.segments) do
		table.insert(segs, pct(s.rate))
	end
	return string.format(
		"[HPCAND] %s | %s%% | 25층 %s분 (%d/%d명) | 환생 %.1f회 | 목표 밖 %d층",
		label, table.concat(segs, " / "),
		if m.medianFinalMin ~= nil then string.format("%.1f", m.medianFinalMin) else "-",
		m.reached, m.players, m.meanRebirths, #HpCandidateReport.outOfBand(m)
	)
end

-- 후보 하나 자세히. 지금 갈아끼워진 곡선 기준이다(withGrowths 안에서 부른다).
function HpCandidateReport.detail(label: string)
	local decision = SuccessRateReport.measure()
	local noPet, noAuraPet
	withModel({ PET_POLICY = "none" }, function()
		noPet = SuccessRateReport.measure()
	end)
	withModel({ PET_POLICY = "none", AURA_POLICY = "none" }, function()
		noAuraPet = SuccessRateReport.measure()
	end)
	print(compactLine(label, decision))
	local oob = HpCandidateReport.outOfBand(decision)
	print("[HPCAND]   목표 ±10%p 밖: " .. (if #oob > 0 then table.concat(oob, " · ") else "없음"))
	local cells = {}
	for stage = 1, decision.maxStage do
		local r = decision.floorRates[stage]
		table.insert(cells, if r ~= nil then string.format("%d", math.floor(r * 100 + 0.5)) else "-")
	end
	print("[HPCAND]   층별% 1→" .. decision.maxStage .. ": " .. table.concat(cells, " "))
	local function margin(a: SuccessRateReport.Metrics, b: SuccessRateReport.Metrics): string
		if a.medianFinalMin == nil or b.medianFinalMin == nil then
			return "-"
		end
		return string.format("%+.1f분(%.1f vs 한도 %.1f)", a.medianFinalMin - 0.9 * b.medianFinalMin, a.medianFinalMin, 0.9 * b.medianFinalMin)
	end
	print(string.format(
		"[HPCAND]   한도 여유: 아우라 %s · 펫 · CRAFT %s · 1~8층(한도 85%%) %s%% · 레벨 상한 %s분 · %s층(%d명)",
		margin(noPet, noAuraPet), margin(decision, noPet), pct(decision.segments[1] and decision.segments[1].rate),
		if decision.medianLevelCapMin ~= nil then string.format("%.1f", decision.medianLevelCapMin) else "-",
		if decision.medianLevelCapStage ~= nil then tostring(decision.medianLevelCapStage) else "-",
		decision.levelCapReached
	))

	-- 시간 축(StandardPathReport — 같은 함수). 층별 체류는 클릭률 8, 절벽 판정은 세 클릭률.
	local rates = StandardPathReport.simulateAll(decision.maxStage)
	local boundaries = StandardPathReport.boundaries()
	for _, result in ipairs(rates) do
		if result.clickRate == 8 then
			local stays = {}
			for stage = 1, decision.maxStage - 1 do
				local here, nextRec = result.records[stage], result.records[stage + 1]
				table.insert(stays, if here ~= nil and nextRec ~= nil then string.format("%.1f", (nextRec.elapsedSec - here.elapsedSec) / 60) else "-")
			end
			local last = result.records[decision.maxStage]
			print(string.format("[HPCAND]   체류(분, 클릭 8, 층→다음층) %s | 25층 %s분", table.concat(stays, " "),
				if last ~= nil then string.format("%.1f", last.elapsedSec / 60) else "-"))
		end
	end
	local verdicts = {}
	for i = #boundaries, 1, -1 do
		local b = boundaries[i]
		local parts = {}
		for _, result in ipairs(rates) do
			local _, _, ratio = StandardPathReport.cliffRatio(result, b.stage)
			table.insert(parts, if ratio ~= nil
				then string.format("%d:%.2f%s", result.clickRate, ratio, if ratio >= StandardPathReport.CLIFF_RATIO_THRESHOLD then "!" else "")
				else string.format("%d:-", result.clickRate))
		end
		table.insert(verdicts, string.format("%d→%d %s", b.stage, b.stage + 1, table.concat(parts, " ")))
	end
	print(string.format("[HPCAND]   절벽(임계 %.1f, !=실재) %s", StandardPathReport.CLIFF_RATIO_THRESHOLD, table.concat(verdicts, " · ")))
end

function HpCandidateReport.run()
	task.wait(5) -- 시작 직후 테스트들이 MODEL · Config를 잠깐 흔드는 동안 기다린다(테스트는 yield 없이 되돌린다)
	local SIM = SuccessRateReport.SIM
	local world = WorldConfig.get(SIM.WORLD_ID) :: WorldConfig.WorldDef
	local current = {}
	for _, seg in ipairs(world.hpGrowthSegments) do
		table.insert(current, seg.growth)
	end
	print(string.format("[HPCAND] ===== HP 곡선 후보 (결정 모델 S5' + S7 + A4 + E11 · L1 · L3, %d명 · seed %d) — 채택하지 않는다 =====", SIM.PLAYERS, SIM.SEED))
	print("[HPCAND] 목표 1~8 ≥ 95 / 9~16 65~85 / 17~25 40~55 (DESIGN \"목표 성공률\" · SuccessRateReport.TARGETS) · 측정 규약 ±10%p")
	HpCandidateReport.detail("B4 현재 " .. growthText(current))

	if HpCandidateReport.RUN_SWEEP then
		print("[HPCAND] ----- 넓게 훑기 (결정 모델만) -----")
		for _, g1 in ipairs(HpCandidateReport.GRID[1]) do
			for _, g2 in ipairs(HpCandidateReport.GRID[2]) do
				for _, g3 in ipairs(HpCandidateReport.GRID[3]) do
					local growths = { g1, g2, g3 }
					local ok, err = HpCandidateReport.withGrowths(growths, function()
						print(compactLine(growthText(growths), (SuccessRateReport.measure())))
					end)
					if not ok then
						print(string.format("[HPCAND] %s — 규약 위반으로 건너뜀: %s", growthText(growths), tostring(err)))
					end
				end
			end
		end
	end

	print("[HPCAND] ----- 후보 자세히 (SuccessRateReport.CURVE_VARIANTS) -----")
	for _, variant in ipairs(SuccessRateReport.CURVE_VARIANTS) do
		local growths = {}
		for _, seg in ipairs(variant.segments) do
			table.insert(growths, seg.growth)
		end
		local ok, err = HpCandidateReport.withGrowths(growths, function()
			HpCandidateReport.detail(variant.label)
		end)
		if not ok then
			print(string.format("[HPCAND] %s — 규약 위반으로 건너뜀: %s", variant.label, tostring(err)))
		end
	end
	print("[HPCAND] 끝.")
end

return HpCandidateReport

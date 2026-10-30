--!strict
-- BalanceSummary(튜닝 요약) 검증 (지시서 #13 6단계). 합성 지표로 줄을 만들어 잰다 — 시뮬레이터를 돌리지 않는다.
--   30줄 안팎 · 앞머리에 측정 조건(seed · 인원 · 모델) · 목표 밖 층 · 레벨 상한 · 절벽 판정(임계 이상이면 실재) · 뽑기 분포

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local SuccessRateReport = require(ServerScriptService.Server.Tools.SuccessRateReport)
local BalanceSummary = require(ServerScriptService.Server.Tools.BalanceSummary)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function has(lines: { string }, needle: string): boolean
	for _, line in ipairs(lines) do
		if string.find(line, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local fakeTry: any = {}
for stage = 1, 25 do
	fakeTry[stage] = { attempts = 10, successes = if stage <= 8 then 10 elseif stage <= 16 then 8 elseif stage == 20 then 9 else 5 }
end
local petId = PetConfig.Eggs[1].pets[1].id
local fakeResults: any = {
	{ reachedFinal = true, finalFirstSec = 600, rebirths = 2, runs = 10, finalRebirthsLog10 = 1, levelCapMin = 5, levelCapStage = 12,
		finalTitleIndex = 4, finalAuraId = "pack2_epic", finalPets = { { petId = petId, tier = 2, gain = 0 } } },
	{ reachedFinal = true, finalFirstSec = 1200, rebirths = 4, runs = 20, finalRebirthsLog10 = 2, levelCapMin = nil,
		finalTitleIndex = 0, finalAuraId = nil, finalPets = {} },
}
local m = SuccessRateReport.metrics(fakeTry, fakeResults)
local cliffs: any = {
	{ boundary = 16, ratios = { { clickRate = 6, ratio = 0.5 }, { clickRate = 8, ratio = 2.5 }, { clickRate = 10, ratio = nil } } },
	{ boundary = 8, ratios = { { clickRate = 6, ratio = 1.2 }, { clickRate = 8, ratio = 1.1 }, { clickRate = 10, ratio = 1.9 } } },
}
local path: any = { { clickRate = 6, minutes = 22.3 }, { clickRate = 8, minutes = 20.9 }, { clickRate = 10, minutes = nil } }
local lines = BalanceSummary.lines(m, fakeResults, cliffs, path)

check("줄 수 30 안팎(20~35)", #lines >= 20 and #lines <= 35, tostring(#lines))
check("앞머리: 측정 조건 — 인원 · seed · 모델", string.find(lines[2], "플레이어 2명", 1, true) ~= nil
	and string.find(lines[2], tostring(SuccessRateReport.SIM.SEED), 1, true) ~= nil and string.find(lines[3], "모델:", 1, true) ~= nil, lines[2])
check("구간 성공률 3줄 · 17~25층 54.4%는 목표 안(40~55)", has(lines, "1~8층  100.0%") and has(lines, "9~16층  80.0%") and has(lines, "17~25층  54.4%"))
check("목표 ±10%p 밖 층: 20층 90%만", has(lines, "목표 ±10%p 밖 층: 20층 90%"))
check("25층 중앙값 · 환생 · 레벨 상한 줄", has(lines, "25층 첫 진입 중앙값 10.0분 (2/2명)") and has(lines, "평균 환생 3.0회") and has(lines, "첫 도달 중앙값 5.0분 · 12층 (1명"))
check("표준 경로 25층 도달(클릭률별 · 못 닿으면 -)", has(lines, "클릭 6 → 22.3분") and has(lines, "클릭 10 → -분"))
check("절벽: 16→17 클릭 8 2.50 ≥ 임계 → 실재 · 8→9 전부 아래 → 없음", has(lines, "16→17층") and has(lines, "→ 절벽 실재(그 클릭률)") and has(lines, "8→9층")
	and has(lines, "클릭 10 1.90  → 절벽 없음"))
check("뽑기 분포: 칭호 이름 · 아우라 팩 · 펫 단계", has(lines, TitleConfig.Titles[4].id .. " 1") and has(lines, "pack2_epic 1") and has(lines, "L2 1"))
check("모든 줄이 문자열 · 비어 있지 않다", (function()
	for _, line in ipairs(lines) do
		if type(line) ~= "string" or #line == 0 then
			return false
		end
	end
	return true
end)())

print(string.format("[BalanceSummaryTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BalanceSummaryTests] %d test(s) failed", failed))
end

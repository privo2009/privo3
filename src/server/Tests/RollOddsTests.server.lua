--!strict
-- RollOdds 검증 (지시서 #11 3단계 — 확률 공개 P3): 실제 등장 확률 분포(합 1 · 손계산 · p ≥ 1 · 폴백 몫 · 순수성) ·
-- 표시 퍼센트(합이 표시 자릿수에서 정확히 100 · 작은 값이 0이 아님 · 반올림 경계 · 최대 나머지). 가짜 등급 표와 Config 표 둘 다 본다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

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

local function close(a: number, b: number): boolean
	return math.abs(a - b) < 1e-12
end

local function sum(xs: { number }): number
	local s = 0
	for _, x in ipairs(xs) do
		s += x
	end
	return s
end

-- 표시 문자열 합(자릿수 단위 정수로 더한다 — 부동소수 오차 없이 "정확히 100"을 잰다)
local function displaySumUnits(texts: { string }, d: number): number
	local total = 0
	for _, t in ipairs(texts) do
		local v = tonumber((string.gsub(t, "%%", ""))) :: number
		total += math.floor(v * 10 ^ d + 0.5)
	end
	return total
end

local TIERS = {
	{ id = "f" },
	{ id = "a", baseChance = 0.3 },
	{ id = "b", baseChance = 0.09 },
	{ id = "c", baseChance = 0.01 },
}

-- 1. 분포 ----------------------------------------------------------------------------------------
do
	local d = RollOdds.distribution(TIERS, 1)
	check("분포: 합 = 1", close(sum(d), 1))
	check("분포: 손계산 (행운 1) c = 0.01", close(d[4], 0.01))
	check("분포: 손계산 b = 0.99 × 0.09", close(d[3], 0.99 * 0.09))
	check("분포: 손계산 a = 0.99 × 0.91 × 0.3", close(d[2], 0.99 * 0.91 * 0.3))
	check("분포: 폴백 = 나머지 전부", close(d[1], 0.99 * 0.91 * 0.7))

	local lucky = RollOdds.distribution(TIERS, 2)
	check("분포: 행운 ×2 → 가장 높은 등급 2배", close(lucky[4], 0.02) and close(sum(lucky), 1))

	-- b가 확정(p ≥ 1): c는 먼저 판정돼 제 몫을 갖고, b가 남은 몫 전부, 그 뒤(a · 폴백)는 0
	local sure = RollOdds.distribution(TIERS, (1 / 0.09) * 1.001) -- 딱 1/0.09면 부동소수로 p가 1 바로 아래일 수 있다
	check("분포: p ≥ 1 등급이 나머지를 다 가져간다", close(sure[3], 1 - sure[4]) and sure[4] > 0)
	check("분포: 그보다 뒤에 판정되는 등급은 0", sure[2] == 0 and sure[1] == 0)
	check("분포: p ≥ 1이어도 합 1", close(sum(sure), 1))

	local before = TIERS[2].baseChance
	RollOdds.distribution(TIERS, 3)
	check("분포: 순수 — 입력 표를 바꾸지 않는다", TIERS[2].baseChance == before and TIERS[1].baseChance == nil)
	local zero = RollOdds.distribution(TIERS, 0 / 0)
	check("분포: 깨진 행운은 폴백 100%", zero[1] == 1 and zero[4] == 0)
	check("chance = 기본 × 행운", close(RollOdds.chance(TIERS[4], 3), 0.03) and RollOdds.chance(TIERS[1], 3) == 0)
end

-- 2. 표시 퍼센트 ---------------------------------------------------------------------------------
do
	local d = RollOdds.distribution(TIERS, 1)
	local texts, dec = RollOdds.percentages(d)
	check("표시: 합이 표시 자릿수에서 정확히 100", displaySumUnits(texts, dec) == 100 * 10 ^ dec, table.concat(texts, " "))
	check("표시: 자릿수 = 가장 작은 값이 유효숫자 2자리 (1.0% → 소수 1자리)", dec == 1 and texts[4] == "1.0%", texts[4])

	local tdist = RollOdds.distribution(TitleConfig.Titles, 1)
	local ttexts, tdec = RollOdds.percentages(tdist)
	check("표시(칭호): 합 100", displaySumUnits(ttexts, tdec) == 100 * 10 ^ tdec, table.concat(ttexts, " "))
	local smallest = ttexts[#ttexts]
	check("표시(칭호): 1/50000이 0으로 보이지 않는다 · 유효숫자 2자리", smallest == "0.0020%", smallest)
	local nonzero = true
	for i, p in ipairs(tdist) do
		if p > 0 and tonumber((string.gsub(ttexts[i], "%%", ""))) == 0 then
			nonzero = false
		end
	end
	check("표시(칭호): 0이 아닌 확률은 전부 0이 아니다", nonzero)

	-- 반올림 경계: 세 값이 전부 1/3이면 33.3 · 33.3 · 33.4 (나머지 한 단위가 한 칸에 간다)
	local third = { 1 / 3, 1 / 3, 1 / 3 }
	local th = RollOdds.percentages(third)
	table.sort(th)
	check("최대 나머지: 1/3 셋 → 33.3 · 33.3 · 33.4", th[1] == "33.3%" and th[2] == "33.3%" and th[3] == "33.4%", table.concat(th, " "))
	-- 0.25 · 0.25 · 0.5 → 그대로
	local even = RollOdds.percentages({ 0.25, 0.25, 0.5 })
	check("최대 나머지: 딱 떨어지면 그대로", even[1] == "25.0%" and even[3] == "50.0%")
	-- 0은 0으로
	local withZero = RollOdds.percentages({ 0, 1 })
	check("0인 확률은 0.0%, 나머지가 100.0%", withZero[1] == "0.0%" and withZero[2] == "100.0%")
	check("행운 문구", RollOdds.luckText(1.03) == Locale.t("roll.luckApplied", { luck = "1.03" }) and Locale.tFor("ko", "roll.luckApplied", { luck = "1.03" }) == "행운 ×1.03 적용")
end

print(string.format("[RollOddsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RollOddsTests] %d test(s) failed", failed))
end

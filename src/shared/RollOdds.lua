--!strict
-- 뽑기 확률 공개용 순수 함수 (Phase 7 지시서 #11 P3). 서버(RollLogic · 시뮬레이터)와 클라(뽑기 창)가 같은 식을 쓴다.
-- 판정 자체는 여기 없다 — 서버 RollLogic.roll이 한다(절대 규칙 3). 이 파일은 "판정이 낳는 결과 분포"와 그 표시만 계산한다.
-- 규칙 원본: DESIGN.md "6. 뽑기 3종 > 확률 공개".
--
--   distribution  순차 판정(희귀도 높은 순)의 실제 등장 확률. 높은 등급에서 빗나간 몫만 아래로 내려간다. 합 = 1
--   percentages   표시 문자열. 모든 결과의 합이 표시 자릿수에서 정확히 100(최대 나머지 방식).
--                 0이 아닌 확률은 유효숫자 2자리 이상으로 보인다(0으로 보이지 않는다)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local RollOdds = {}

export type Tier = { baseChance: number? }

-- 판정에 쓸 수 있는 행운(깨진 값은 0 — RollLogic과 같은 접기).
local function sanitizeLuck(luck: any): number
	if type(luck) ~= "number" or luck ~= luck or luck < 0 then
		return 0
	end
	return luck
end

-- 그 등급 하나의 판정 확률(기본 × 행운). 0~1로 자르지 않는다(1 이상이면 확정).
function RollOdds.chance(tier: Tier, luck: number): number
	local base = tier.baseChance
	if type(base) ~= "number" or base ~= base or base <= 0 then
		return 0
	end
	return base * sanitizeLuck(luck)
end

-- 실제 등장 확률. out[i] = P(tiers[i]가 뽑힌다). tiers[1]은 폴백(빗나간 나머지 전부). 입력을 바꾸지 않는다.
-- p ≥ 1인 등급이 있으면 그 등급이 남은 몫을 다 가져가고, 그보다 뒤에 판정되는(낮은) 등급은 0이다.
function RollOdds.distribution(tiers: { Tier }, luck: number): { number }
	local out: { number } = {}
	local remaining = 1
	for i = #tiers, 2, -1 do
		local p = math.min(1, RollOdds.chance(tiers[i], luck))
		out[i] = remaining * p
		remaining -= out[i]
	end
	out[1] = math.max(0, remaining)
	return out
end

RollOdds.MIN_DECIMALS = 1 -- 가장 큰 확률도 소수 한 자리는 보인다(20.0%)
RollOdds.MAX_DECIMALS = 6 -- 이보다 작은 확률은 표에 없다(가장 작은 기본 확률 1/50000 → 4자리)

-- 표시 자릿수: 0이 아닌 확률 중 가장 작은 것이 유효숫자 2자리가 되는 소수 자리. 표 전체가 같은 자릿수를 쓴다
-- (자릿수가 줄마다 다르면 "합 100"을 그 자릿수에서 맞출 수 없다).
function RollOdds.decimalsFor(dist: { number }): number
	local d = RollOdds.MIN_DECIMALS
	for _, p in ipairs(dist) do
		if p > 0 then
			local pct = p * 100
			local need = 1 - math.floor(math.log10(pct))
			d = math.max(d, need)
		end
	end
	return math.min(d, RollOdds.MAX_DECIMALS)
end

-- 표시 문자열 배열(dist와 같은 순서) + 쓴 자릿수. 최대 나머지 방식: 각 값을 자릿수 단위로 내리고, 모자란 단위를
-- 버린 나머지가 큰 순서로 하나씩 더한다(같으면 확률이 큰 쪽 — 큰 쪽의 끝자리가 조금 흔들리는 것이 덜 눈에 띈다).
function RollOdds.percentages(dist: { number }): ({ string }, number)
	local d = RollOdds.decimalsFor(dist)
	local unit = 10 ^ d
	local totalUnits = math.floor(100 * unit + 0.5)
	local units: { number } = {}
	local order: { number } = {}
	local used = 0
	for i, p in ipairs(dist) do
		local raw = math.max(0, p) * 100 * unit
		local fl = math.floor(raw + 1e-9)
		units[i] = fl
		used += fl
		order[i] = i
	end
	table.sort(order, function(a, b)
		local ra = math.max(0, dist[a]) * 100 * unit - units[a]
		local rb = math.max(0, dist[b]) * 100 * unit - units[b]
		if math.abs(ra - rb) > 1e-9 then
			return ra > rb
		end
		if dist[a] ~= dist[b] then
			return dist[a] > dist[b]
		end
		return a < b
	end)
	local short = totalUnits - used
	local k = 1
	while short > 0 and #order > 0 do
		local i = order[((k - 1) % #order) + 1]
		units[i] += 1
		short -= 1
		k += 1
	end
	local out: { string } = {}
	local fmt = "%." .. d .. "f%%"
	for i, u in ipairs(units) do
		out[i] = string.format(fmt, u / unit)
	end
	return out, d
end

-- "행운 ×N 적용" 문구(소수 두 자리 — Strings "roll.luckApplied").
function RollOdds.luckText(luck: number): string
	return Locale.t("roll.luckApplied", { luck = string.format("%.2f", sanitizeLuck(luck)) })
end

return RollOdds

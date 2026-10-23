--!strict
-- 뽑기 순수 판정 (Phase 7 지시서 #10 S2). 순차 확률 — 희귀도 높은 순으로 하나씩 판정한다.
-- 원본 규칙은 DESIGN.md "6. 뽑기 3종 > 공통: 행운 곱셈 체인 · 순차 판정".
--
--   tiers는 희귀도 **낮은 순** 배열이다. tiers[1]은 폴백이다(확률을 보지 않는다).
--   i = #tiers .. 2:  p = tiers[i].baseChance × luck,  randomFn() < p 이면 tiers[i]
--   전부 빗나가면 tiers[1]
--
-- 확률 합이 1을 넘어도 동작한다 — 높은 등급부터 보므로 합은 의미가 없다. p ≥ 1이면 그 등급이 확정이다
-- (randomFn은 [0, 1)을 돌려준다).
--
-- ⚠️ 서버 전용이다. 클라는 Config 확률을 **표시만** 한다(판정은 서버 — 절대 규칙 3). 그래서 Shared가 아니라 여기 있다.
--    시뮬레이터(SuccessRateReport)도 이 함수를 부른다 — 판정이 두 곳에 있으면 어긋난다.
-- 난수는 받는다(randomFn). RNG를 소유하는 것은 RollService다.

local RollLogic = {}

export type Tier = { baseChance: number? }

-- luck를 판정에 쓸 수 있는 수로 접는다. 깨진 값(nan · 음수 · 숫자 아님)은 0 — 폴백만 나온다.
-- inf는 그대로 둔다(모든 p가 inf → 가장 높은 등급 확정). 행운이 터무니없이 커지는 것은 RollService가 막을 일이다.
local function sanitizeLuck(luck: any): number
	if type(luck) ~= "number" or luck ~= luck or luck < 0 then
		return 0
	end
	return luck
end

-- 그 등급 하나의 판정 확률(행운 반영, 0~1로 자르지 않는다). 시뮬레이터 · 창 표시가 같은 식을 쓰도록 둔다.
function RollLogic.chance(tier: Tier, luck: number): number
	local base = tier.baseChance
	if type(base) ~= "number" or base ~= base or base <= 0 then
		return 0
	end
	return base * sanitizeLuck(luck)
end

-- 순차 판정. 반환: (뽑힌 등급, 그 인덱스). tiers가 비면 error — 호출자 버그다(Config validate가 막는다).
function RollLogic.roll<T>(tiers: { T }, luck: number, randomFn: () -> number): (T, number)
	assert(#tiers >= 1, "RollLogic.roll: tiers가 비어 있음")
	for i = #tiers, 2, -1 do
		local p = RollLogic.chance(tiers[i] :: any, luck)
		if p > 0 and randomFn() < p then
			return tiers[i], i
		end
	end
	return tiers[1], 1
end

-- 실제 등급별 확률(판정 순서까지 반영 — 높은 등급에서 빗나간 몫만 아래로 내려간다). 표시 · 시뮬레이터 대조용.
-- out[i] = P(tiers[i]가 뽑힌다). 합은 1이다.
function RollLogic.distribution(tiers: { Tier }, luck: number): { number }
	local out: { number } = {}
	local remaining = 1
	for i = #tiers, 2, -1 do
		local p = math.min(1, RollLogic.chance(tiers[i], luck))
		out[i] = remaining * p
		remaining -= out[i]
	end
	out[1] = remaining
	return out
end

return RollLogic

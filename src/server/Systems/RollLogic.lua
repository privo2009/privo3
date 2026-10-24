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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- 판정 확률 · 결과 분포 식은 Shared/RollOdds 하나다(클라 표시와 같은 식 — 지시서 #11 P3). 판정(roll)만 여기 있다.
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)

local RollLogic = {}

export type Tier = RollOdds.Tier

-- 그 등급 하나의 판정 확률(기본 × 행운, 0~1로 자르지 않는다). 깨진 행운(nan · 음수 · 숫자 아님)은 0 — 폴백만 나온다.
RollLogic.chance = RollOdds.chance

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

-- 실제 등장 확률(순차 판정 결과 분포, 합 1). 식은 RollOdds.distribution — 표시 · 시뮬레이터 대조용.
RollLogic.distribution = RollOdds.distribution

return RollLogic

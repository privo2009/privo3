--!strict
-- 새 경제(경제 재설계) 설정 — 플래그와 TEMP 숫자 (지시서 #30 — 원본 결정 DESIGN.md "16. 경제 재설계").
--
-- ⚠️ ECONOMY_V2는 **켜는 날까지 false로 커밋한다**(CLAUDE.md "작업 방식" · tools/check_test_gate.py가 커밋 값을 본다).
--    false면 게임은 지금과 똑같이 돈다 — 이 파일의 숫자를 읽는 게임 경로는 전부 이 플래그 뒤에 있다.
--    Play 확인은 로컬에서만 잠깐 true로 바꾸고 되돌린다.
--
-- ⚠️ 숫자는 전부 TEMP다(최종 결정은 사람 — D2). 지시서 #30 6번 측정(Tools/EconomyV2Report)의 추천 1순위 묶음으로 채웠다.
--    (묶음 C 균형: ORE_PER_BLOCK 1 · PICK_RATIO 1.255 · AUTO_CRAFT_INTERVAL_SEC 150 · 환생 1000 · ×4 · 1.25^n — docs/TUNING.md 7절.
--     나머지 TEMP(확률표 · 가방 · 강화 · 별 · 코인 · 알 가격)는 이 묶음들에서 고정한 출발값이다 — 측정 손잡이 아님)
--    결정 문장 그대로인 값(층 구간 · 토큰 규칙 · 교환 비용 · 별 소모 · 강화 +10 · 곡괭이 15종 등급 수)은 사람 결정이다 — 측정 손잡이가 아니다.
-- 식은 Shared/EconomyV2Logic이 한 곳에서 계산한다(게임 · 시뮬레이터가 같은 함수를 부른다). 여기는 값만 둔다.
-- 이름은 ID와 TEMP 문자열만 둔다 — 정식 이름(영어 · 한국어)은 사람이 정한다(docs/PENDING.md N1).

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

local EconomyV2Config = {}

-- 새 경제 플래그. ⚠️ 커밋 값 false.
EconomyV2Config.ECONOMY_V2 = false

-- ===== 광석 (DESIGN 16장 "광석과 드롭") ===================================================================

EconomyV2Config.ORE_COUNT = 10
-- 광석 k의 층 구간(사람 결정 TEMP). 빈틈 · 중복 없이 1 ~ 25층을 덮는다(validate).
EconomyV2Config.ORE_BANDS = {
	{ from = 1, to = 3 },
	{ from = 4, to = 5 },
	{ from = 6, to = 8 },
	{ from = 9, to = 10 },
	{ from = 11, to = 13 },
	{ from = 14, to = 16 },
	{ from = 17, to = 19 },
	{ from = 20, to = 22 },
	{ from = 23, to = 24 },
	{ from = 25, to = 25 },
} :: { { from: number, to: number } }
-- 게이지: 광석 k의 점수 = k(정수 — 0.1 × k칸을 10배로 저장). 칸 = 점수 합 ÷ GAUGE_UNIT 내림(실수로 더하지 않는다).
EconomyV2Config.GAUGE_UNIT = 10
EconomyV2Config.CRAFT_INPUT = 5 -- 제작 1회에 넣는 광석 수(= 게이지 칸 수 상한)
-- 블록 하나가 부서질 때 떨어지는 광석 수(TEMP — 측정 손잡이 "드롭 수")
EconomyV2Config.ORE_PER_BLOCK = 1
-- 자동으로 줍는 반경(스터드 — 사람 결정 "약 12")
EconomyV2Config.PICKUP_RADIUS = 12

-- ===== 곡괭이 (DESIGN 16장 "곡괭이") =======================================================================

-- 등급(낮은 것부터). "next"는 전설 다음 등급(??? 토큰 — 다음 월드 · 업데이트용, 교환소에 잠긴 칸)이다. 월드 1 곡괭이는 없다.
EconomyV2Config.RARITIES = { "common", "rare", "epic", "mythic", "legendary" }
EconomyV2Config.NEXT_RARITY = "next"

export type PickaxeDef = { id: string, rarity: string, rank: number, name: string, exchangeCost: number? }
-- 월드 1 곡괭이 15종(일반 3 · 희귀 4 · 에픽 4 · 신화 3 · 전설 1 — 사람 결정). rank = 강한 순서(1이 가장 약하다).
-- exchangeCost = 그 등급 토큰으로 확정 교환하는 비용(사람 결정: 희귀 3 · 4 · 5 · 7 / 에픽 2 · 3 · 5 · 9 / 신화 10 · 25 · 50 / 전설 50). 일반은 교환 없음.
-- name은 TEMP 문자열이다(Strings에 넣지 않는다 — 화면에 나가기 전에 사람이 이름을 정한다).
EconomyV2Config.PICKAXES = {
	{ id = "pick_c1", rarity = "common", rank = 1, name = "TEMP Common 1" },
	{ id = "pick_c2", rarity = "common", rank = 2, name = "TEMP Common 2" },
	{ id = "pick_c3", rarity = "common", rank = 3, name = "TEMP Common 3" },
	{ id = "pick_r1", rarity = "rare", rank = 4, name = "TEMP Rare 1", exchangeCost = 3 },
	{ id = "pick_r2", rarity = "rare", rank = 5, name = "TEMP Rare 2", exchangeCost = 4 },
	{ id = "pick_r3", rarity = "rare", rank = 6, name = "TEMP Rare 3", exchangeCost = 5 },
	{ id = "pick_r4", rarity = "rare", rank = 7, name = "TEMP Rare 4", exchangeCost = 7 },
	{ id = "pick_e1", rarity = "epic", rank = 8, name = "TEMP Epic 1", exchangeCost = 2 },
	{ id = "pick_e2", rarity = "epic", rank = 9, name = "TEMP Epic 2", exchangeCost = 3 },
	{ id = "pick_e3", rarity = "epic", rank = 10, name = "TEMP Epic 3", exchangeCost = 5 },
	{ id = "pick_e4", rarity = "epic", rank = 11, name = "TEMP Epic 4", exchangeCost = 9 },
	{ id = "pick_m1", rarity = "mythic", rank = 12, name = "TEMP Mythic 1", exchangeCost = 10 },
	{ id = "pick_m2", rarity = "mythic", rank = 13, name = "TEMP Mythic 2", exchangeCost = 25 },
	{ id = "pick_m3", rarity = "mythic", rank = 14, name = "TEMP Mythic 3", exchangeCost = 50 },
	{ id = "pick_l1", rarity = "legendary", rank = 15, name = "TEMP Legendary 1", exchangeCost = 50 },
} :: { PickaxeDef }
-- 처음부터 주는 곡괭이(TEMP — 일반 1번, 15종에 포함)
EconomyV2Config.START_PICKAXE = "pick_c1"

-- 곡괭이 배수 = PICK_RATIO^(rank − 1)(TEMP — 측정 손잡이). 펀치 데미지 업그레이드 자리에 들어간다.
EconomyV2Config.PICK_RATIO = 1.255
-- 가방 용량 = BAG_BASE + BAG_PER_RANK × (rank − 1) (장착 곡괭이 — TEMP 측정 손잡이)
EconomyV2Config.BAG_BASE = 20
EconomyV2Config.BAG_PER_RANK = 4

-- ===== 강화 · 별 (DESIGN 16장 "곡괭이") ===================================================================

EconomyV2Config.ENHANCE_MAX = 10 -- 사람 결정(+10 · 100% 성공)
-- 강화 효과 = 1 + ENHANCE_STEP × 강화 수준(TEMP). 비용 = 광석 점수 ENHANCE_COST_BASE × ENHANCE_COST_GROWTH^(지금 수준)(TEMP —
-- 광석 점수 = 게이지 점수와 같다 · 낮은 광석부터 낸다. Claude 해석: 결정은 "광석을 쓴다"뿐이다)
EconomyV2Config.ENHANCE_STEP = 0.06
EconomyV2Config.ENHANCE_COST_BASE = 10
EconomyV2Config.ENHANCE_COST_GROWTH = 1.35

-- 별 1 ~ 5성에 소모하는 같은 곡괭이 수(사람 결정 — 누적 26)
EconomyV2Config.STAR_CONSUME = { 1, 3, 5, 7, 10 }
-- 별 효과 = 1 + STAR_STEP × 별 수(TEMP)
EconomyV2Config.STAR_STEP = 0.1

-- ===== 제작 (DESIGN 16장 "제작") ==========================================================================

-- 칸 수(0 ~ 5)마다 등급 확률(%) — TEMP 측정 손잡이. 등급 안에서는 RARITY_SPLIT 비율로 나눈다(EconomyV2Logic.oddsFor가 15종 전체 표를 만든다).
-- 규칙(validate · EconomyV2Tests): 칸마다 합 100 · 칸이 늘수록 "그 등급 이상" 확률이 줄지 않는다 · 전설 ≤ LEGENDARY_ODDS_MAX_PCT.
EconomyV2Config.RARITY_ODDS = {
	[0] = { common = 94, rare = 5.5, epic = 0.5, mythic = 0, legendary = 0 },
	[1] = { common = 70, rare = 26, epic = 3.7, mythic = 0.3, legendary = 0 },
	[2] = { common = 45, rare = 40, epic = 13.5, mythic = 1.5, legendary = 0 },
	[3] = { common = 30, rare = 40, epic = 25, mythic = 5, legendary = 0 },
	[4] = { common = 20, rare = 37, epic = 33, mythic = 9.98, legendary = 0.02 },
	[5] = { common = 10, rare = 33, epic = 40, mythic = 16.95, legendary = 0.05 },
} :: { [number]: { [string]: number } }
-- 등급 안 나눔(rank 순서 — 강한 것일수록 드물다). 합은 아무 값이나 된다(비율).
EconomyV2Config.RARITY_SPLIT = {
	common = { 5, 3, 2 },
	rare = { 4, 3, 2, 1 },
	epic = { 4, 3, 2, 1 },
	mythic = { 6, 3, 1 },
	legendary = { 1 },
} :: { [string]: { number } }
-- 전설 확률 상한(%) — "극악"(사람 결정). 칸마다 전설 확률이 이 값 이하여야 한다.
EconomyV2Config.LEGENDARY_ODDS_MAX_PCT = 0.05

-- 토큰(제작 1회당 — 사람 결정): 0칸 없음 · 1칸 희귀 1 · 2칸 에픽 1 · 3칸 신화 1 · 4칸 전설 1 · 5칸 전설 1 + ??? 1
EconomyV2Config.TOKENS_BY_GAUGE = {
	[0] = {},
	[1] = { rare = 1 },
	[2] = { epic = 1 },
	[3] = { mythic = 1 },
	[4] = { legendary = 1 },
	[5] = { legendary = 1, next = 1 },
} :: { [number]: { [string]: number } }

-- 자동 제작 간격(초 — TEMP 측정 손잡이). 무료 토글. 빠른 제작(로벅스 · 가격 미정)은 FAST_CRAFT_FACTOR를 곱한다.
EconomyV2Config.AUTO_CRAFT_INTERVAL_SEC = 150
EconomyV2Config.FAST_CRAFT_FACTOR = 0.5 -- TEMP(상품 효과 — 참고 측정)
EconomyV2Config.TRIPLE_CRAFT_COUNT = 3 -- 트리플 제작(사람 결정 "한 번에 3개")

-- ===== 코인 · 펫 (DESIGN 16장 "재화") ======================================================================

-- 블록 하나 = COIN_BASE × COIN_GROWTH^(층 − 1) 코인(TEMP). 실패해도 잃지 않는다.
EconomyV2Config.COIN_BASE = 1
EconomyV2Config.COIN_GROWTH = 1.5
-- 알 부화 1회 코인 가격(TEMP — PetConfig.Eggs 번호). 알 해금은 지금 규칙(lifetimeBlox ≥ 알의 블럭스 부화 비용 — G8) 그대로.
EconomyV2Config.EGG_COIN_COST = {
	[1] = BigNum.new(5, 1), -- 50
	[2] = BigNum.new(5, 3), -- 5,000
	[3] = BigNum.new(2, 5), -- 200,000
} :: { [number]: BigNumber }

-- ===== 환생 v2 (DESIGN 16장 "환생 (새 경제)") ============================================================

-- 비용 = REBIRTH_COST_BASE × REBIRTH_COST_GROWTH^n(n = 지금 환생 수) · 힘 배수의 환생 항 = REBIRTH_MULT_BASE^n.
-- 출발점 = #29 R4(1000 · ×4 · 1.61^n). 지금 값 = 지시서 #30 추천 1순위 묶음 C(b 1.25 — R4의 1.61이면 25층 29분으로 너무 빠르다)(TEMP).
EconomyV2Config.REBIRTH_COST_BASE = BigNum.new(1, 3) -- 1000
EconomyV2Config.REBIRTH_COST_GROWTH = 4
EconomyV2Config.REBIRTH_MULT_BASE = 1.25
-- true = 비용만 빼고 나머지 블럭스를 남긴다(기본 — 지시서 #30). false = #29 R4 측정처럼 0(지금 환생과 같다).
EconomyV2Config.REBIRTH_KEEP_REMAINDER = true

-- 운동기구 해금 환생 수(새 경제 TEMP — GymConfig 기구 순서. 로벅스 전용 기구는 GymConfig 그대로).
-- 지금 값(1 · 3 · 5 · 10 · 50 · 500 · 1e4 · 1e6)은 환생이 1000 블럭스마다 +1일 때 값이라 새 경제(25층까지 10 ~ 20회)에서는 뒤 기구가 안 열린다.
-- 운동기구 개편 자체는 사람 결정이다(docs/PENDING.md N3) — 여기는 해금 수만 갈아 끼운다.
EconomyV2Config.GYM_UNLOCK_REBIRTHS = { 1, 2, 3, 5, 7, 9, 12, 15 }

-- ===== 검증 ==========================================================================================

function EconomyV2Config.validate(): boolean
	assert(type(EconomyV2Config.ECONOMY_V2) == "boolean", "EconomyV2Config: ECONOMY_V2는 boolean")
	-- 광석 구간: 1층부터 빈틈 · 중복 없이 이어진다
	local nextFrom = 1
	assert(#EconomyV2Config.ORE_BANDS == EconomyV2Config.ORE_COUNT, "EconomyV2Config: ORE_BANDS 수 ≠ ORE_COUNT")
	for k, band in ipairs(EconomyV2Config.ORE_BANDS) do
		assert(band.from == nextFrom and band.to >= band.from, string.format("EconomyV2Config: 광석 %d 구간이 이어지지 않는다", k))
		nextFrom = band.to + 1
	end
	-- 곡괭이: rank 1 ~ 15 연속 · 등급 순서가 rank와 같다 · 교환 비용은 일반 말고 전부
	local rarityIndex: { [string]: number } = {}
	for i, r in ipairs(EconomyV2Config.RARITIES) do
		rarityIndex[r] = i
	end
	local seen: { [string]: boolean } = {}
	local prevRarity = 1
	for i, def in ipairs(EconomyV2Config.PICKAXES) do
		assert(def.rank == i, string.format("EconomyV2Config: %s rank가 %d가 아니다", def.id, i))
		assert(not seen[def.id], "EconomyV2Config: 곡괭이 id 중복 " .. def.id)
		seen[def.id] = true
		local ri = rarityIndex[def.rarity]
		assert(ri ~= nil and ri >= prevRarity, string.format("EconomyV2Config: %s 등급 순서", def.id))
		prevRarity = ri
		assert((def.rarity == "common") == (def.exchangeCost == nil), string.format("EconomyV2Config: %s 교환 비용(일반만 없음)", def.id))
	end
	assert(seen[EconomyV2Config.START_PICKAXE], "EconomyV2Config: START_PICKAXE가 목록에 없다")
	for rarity, split in pairs(EconomyV2Config.RARITY_SPLIT) do
		local n = 0
		for _, def in ipairs(EconomyV2Config.PICKAXES) do
			if def.rarity == rarity then
				n += 1
			end
		end
		assert(n == #split, string.format("EconomyV2Config: RARITY_SPLIT.%s 칸 수 %d ≠ 곡괭이 %d", rarity, #split, n))
	end
	-- 확률표: 칸 0 ~ CRAFT_INPUT마다 합 100 · 전설 상한
	for s = 0, EconomyV2Config.CRAFT_INPUT do
		local row = EconomyV2Config.RARITY_ODDS[s]
		assert(row ~= nil, string.format("EconomyV2Config: RARITY_ODDS[%d] 없음", s))
		local sum = 0
		for _, r in ipairs(EconomyV2Config.RARITIES) do
			local v = row[r] or 0
			assert(v >= 0, "EconomyV2Config: 확률은 0 이상")
			sum += v
		end
		assert(math.abs(sum - 100) < 1e-9, string.format("EconomyV2Config: RARITY_ODDS[%d] 합 %.6f ≠ 100", s, sum))
		assert((row.legendary or 0) <= EconomyV2Config.LEGENDARY_ODDS_MAX_PCT, string.format("EconomyV2Config: RARITY_ODDS[%d] 전설 상한", s))
		assert(EconomyV2Config.TOKENS_BY_GAUGE[s] ~= nil, string.format("EconomyV2Config: TOKENS_BY_GAUGE[%d] 없음", s))
	end
	assert(#EconomyV2Config.STAR_CONSUME == 5, "EconomyV2Config: 별은 5성까지")
	assert(EconomyV2Config.REBIRTH_COST_GROWTH > 1 and EconomyV2Config.REBIRTH_MULT_BASE > 1, "EconomyV2Config: 환생 비용 · 배수 성장 > 1")
	local prevGym = 0
	for _, need in ipairs(EconomyV2Config.GYM_UNLOCK_REBIRTHS) do
		assert(need > prevGym and need % 1 == 0, "EconomyV2Config: 운동기구 해금 환생 수는 늘어나는 정수")
		prevGym = need
	end
	return true
end

return EconomyV2Config

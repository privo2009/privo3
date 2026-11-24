--!strict
-- 새 경제(경제 재설계) 설정 — 플래그와 TEMP 숫자 (지시서 #30 — 원본 결정 DESIGN.md "16. 경제 재설계").
--
-- ⚠️ ECONOMY_V2는 **켜는 날까지 false로 커밋한다**(CLAUDE.md "작업 방식" · tools/check_test_gate.py가 커밋 값을 본다).
--    false면 게임은 지금과 똑같이 돈다 — 이 파일의 숫자를 읽는 게임 경로는 전부 이 플래그 뒤에 있다.
--    Play 확인은 로컬에서만 잠깐 true로 바꾸고 되돌린다.
--
-- ⚠️ 숫자는 전부 TEMP다(최종 결정은 사람 — D2). 지금 값 = 지시서 #33 결정(광석 점수 표 · 모든 광석 드롭 0.5 이상 · 등급별 강화 비용) +
--    #33 5차 측정 추천 1순위 T1을 깔끔한 값으로 옮긴 V4(docs/TUNING.md 10절 — 확인 측정 25층 125 · 15종 162): 곡괭이 1.245 ·
--    광석 8 ~ 10 드롭 0.5(바닥) · 강화 비용 바탕 2.2 · 효과 0.02 · 1 ~ 3칸 신화 확률 낮춤.
--    환생 1000 · ×4 · 1.25^n · 연출 + 5초 스킵 · 대장간 8층은 그대로.
--    결정 문장 그대로인 값(층 구간 · 토큰 규칙 · 교환 비용 · 별 소모 · 강화 +10 · 곡괭이 15종 등급 수)은 사람 결정이다 — 측정 손잡이가 아니다.
-- 식은 Shared/EconomyV2Logic이 한 곳에서 계산한다(게임 · 시뮬레이터가 같은 함수를 부른다). 여기는 값만 둔다.
-- 이름은 Strings 키만 둔다(ORE_NAME_KEYS · PICKAXES.nameKey — 지시서 #31). ⚠️ 지금 이름은 전부 임시 이름이다 — 확정은 사람(docs/PENDING.md N1).

local BigNum = require(script.Parent.Parent.BigNum)
local ShopConfig = require(script.Parent.ShopConfig) -- 새 패스 ID 원본(#35 — ShopConfig.V2_GAMEPASS_IDS)

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
-- 광석 점수 표(#33 결정 — TEMP · 정수). 게이지 칸 = 점수 합 ÷ GAUGE_UNIT 내림(실수로 더하지 않는다) · 강화 비용도 이 점수로 낸다.
-- 규칙(validate): 정수 ≥ 1 · 광석 번호가 오를수록 줄지 않는다 · 마지막 광석 CRAFT_INPUT개만 꽉 찬 칸(25층 광석 5개로만 5칸 — 희준 결정)
EconomyV2Config.ORE_POINTS = { 1, 1, 2, 2, 3, 4, 5, 6, 8, 10 } :: { number }
EconomyV2Config.GAUGE_UNIT = 10
EconomyV2Config.CRAFT_INPUT = 5 -- 제작 1회에 넣는 광석 수(= 게이지 칸 수 상한)
-- 블록 하나가 부서질 때 떨어지는 광석 수(TEMP — 하위 광석 기본값)
EconomyV2Config.ORE_PER_BLOCK = 1
-- 상위 광석 공급(지시서 #31 — 15종 시간 손잡이). 광석 k(≥ UPPER_ORE_FROM)의 블록 하나 드롭 기대값 = ORE_PER_BLOCK × UPPER_ORE_DROP_MULT(TEMP).
-- 소수면 블록마다 확률로 하나 더(EconomyV2Logic.rollDrops — 기대값이 같다). 하위 광석은 ORE_PER_BLOCK 그대로(넉넉하게).
EconomyV2Config.UPPER_ORE_FROM = 8
EconomyV2Config.UPPER_ORE_DROP_MULT = 0.109
-- 광석 k별 블록당 드롭 기대값(#33 — TEMP · 5차 측정 손잡이. nil이면 위 ORE_PER_BLOCK · UPPER_ORE_DROP_MULT 규칙).
-- #33 결정 N13: 모든 광석을 넉넉하게 — 광석 1 ~ 10 모두 ORE_DROP_MIN 이상(validate). 시간 조절은 점수 표 · 가방 · 확률표 · 강화가 맡는다
EconomyV2Config.ORE_DROP_MIN = 0.5
EconomyV2Config.ORE_DROP_BY_ORE = { 1, 1, 1, 1, 1, 0.8, 0.8, 0.5, 0.5, 0.5 } :: { [number]: number }?
-- 자동으로 줍는 반경(스터드 — 사람 결정 "약 12" · TEMP)
EconomyV2Config.PICKUP_RADIUS = 12
-- 줍기 판정 주기(초 — 서버 단일 폴링 루프 · OreDropService). 시각 튜닝값
EconomyV2Config.PICKUP_POLL_SEC = 0.25
-- 블록 하나에서 떨어진 드롭이 흩어지는 반경(스터드 — 표시 · 줍기 위치. 시각 튜닝값)
EconomyV2Config.DROP_SCATTER = 2.5

-- 광석 표시(#32 — 임시 도형 + 에셋 자리). color = 광석 재질 색(등급 색은 미결 PENDING C1).
-- modelId · iconId · effectId가 nil이면 임시 도형(작은 Part · 색 칸)을 쓴다 — 방학 때 ID만 넣으면 모델로 바뀐다.
export type OreVisual = { color: Color3, modelId: number?, iconId: number?, effectId: number? }
EconomyV2Config.ORE_VISUALS = {
	{ color = Color3.fromRGB(184, 115, 51) }, -- 1 구리 — 주황갈색
	{ color = Color3.fromRGB(170, 176, 180) }, -- 2 주석 — 밝은 회색
	{ color = Color3.fromRGB(120, 124, 130) }, -- 3 철 — 짙은 회색
	{ color = Color3.fromRGB(214, 220, 228) }, -- 4 은 — 은백
	{ color = Color3.fromRGB(240, 196, 60) }, -- 5 금 — 노랑
	{ color = Color3.fromRGB(70, 170, 110) }, -- 6 비취 — 초록
	{ color = Color3.fromRGB(205, 40, 60) }, -- 7 루비 — 빨강
	{ color = Color3.fromRGB(40, 90, 210) }, -- 8 사파이어 — 파랑
	{ color = Color3.fromRGB(150, 90, 200) }, -- 9 자수정 — 연보라(재질 색 — 등급 색 아님)
	{ color = Color3.fromRGB(245, 245, 255) }, -- 10 별빛석 — 흰빛
} :: { OreVisual }
-- 코인 표시 자리(nil이면 임시 도형 — 노란 칸)
EconomyV2Config.COIN_VISUAL = { color = Color3.fromRGB(255, 205, 60), iconId = nil :: number?, effectId = nil :: number? }
-- 광석 이름 Strings 키(⚠️ 임시 이름 — 지시서 #31 · docs/LOCALIZATION.md 4절)
EconomyV2Config.ORE_NAME_KEYS = {
	"ore.name.1", "ore.name.2", "ore.name.3", "ore.name.4", "ore.name.5",
	"ore.name.6", "ore.name.7", "ore.name.8", "ore.name.9", "ore.name.10",
} :: { string }

-- ===== 장비 종류 (DESIGN 16장 "장비 종류" — #32) ===========================================================
-- 저장(equipment · equipped) · 설정 · 로직이 종류별로 갈라진다. 지금은 곡괭이 하나 · 4월 대형 업데이트에서 칼을 더한다.
-- Schema는 Config를 모르므로 종류 이름 목록을 따로 들고 있다(SchemaTests가 대조).
EconomyV2Config.EQUIPMENT_KINDS = { "pickaxe" } :: { string }

-- ===== 곡괭이 (DESIGN 16장 "곡괭이") =======================================================================

-- 등급(낮은 것부터). "next"는 전설 다음 등급(??? 토큰 — 다음 월드 · 업데이트용, 교환소에 잠긴 칸)이다. 월드 1 곡괭이는 없다.
EconomyV2Config.RARITIES = { "common", "rare", "epic", "mythic", "legendary" }
EconomyV2Config.NEXT_RARITY = "next"

export type PickaxeDef = { id: string, rarity: string, rank: number, nameKey: string, exchangeCost: number? }
-- 월드 1 곡괭이 15종(일반 3 · 희귀 4 · 에픽 4 · 신화 3 · 전설 1 — 사람 결정). rank = 강한 순서(1이 가장 약하다).
-- exchangeCost = 그 등급 토큰으로 확정 교환하는 비용(사람 결정: 희귀 3 · 4 · 5 · 7 / 에픽 2 · 3 · 5 · 9 / 신화 10 · 25 · 50 / 전설 50). 일반은 교환 없음.
-- nameKey = Strings 키("pickaxe.name." .. id — ⚠️ 임시 이름 · 지시서 #31).
EconomyV2Config.PICKAXES = {
	{ id = "pick_c1", rarity = "common", rank = 1, nameKey = "pickaxe.name.pick_c1" },
	{ id = "pick_c2", rarity = "common", rank = 2, nameKey = "pickaxe.name.pick_c2" },
	{ id = "pick_c3", rarity = "common", rank = 3, nameKey = "pickaxe.name.pick_c3" },
	{ id = "pick_r1", rarity = "rare", rank = 4, nameKey = "pickaxe.name.pick_r1", exchangeCost = 3 },
	{ id = "pick_r2", rarity = "rare", rank = 5, nameKey = "pickaxe.name.pick_r2", exchangeCost = 4 },
	{ id = "pick_r3", rarity = "rare", rank = 6, nameKey = "pickaxe.name.pick_r3", exchangeCost = 5 },
	{ id = "pick_r4", rarity = "rare", rank = 7, nameKey = "pickaxe.name.pick_r4", exchangeCost = 7 },
	{ id = "pick_e1", rarity = "epic", rank = 8, nameKey = "pickaxe.name.pick_e1", exchangeCost = 2 },
	{ id = "pick_e2", rarity = "epic", rank = 9, nameKey = "pickaxe.name.pick_e2", exchangeCost = 3 },
	{ id = "pick_e3", rarity = "epic", rank = 10, nameKey = "pickaxe.name.pick_e3", exchangeCost = 5 },
	{ id = "pick_e4", rarity = "epic", rank = 11, nameKey = "pickaxe.name.pick_e4", exchangeCost = 9 },
	{ id = "pick_m1", rarity = "mythic", rank = 12, nameKey = "pickaxe.name.pick_m1", exchangeCost = 10 },
	{ id = "pick_m2", rarity = "mythic", rank = 13, nameKey = "pickaxe.name.pick_m2", exchangeCost = 25 },
	{ id = "pick_m3", rarity = "mythic", rank = 14, nameKey = "pickaxe.name.pick_m3", exchangeCost = 50 },
	{ id = "pick_l1", rarity = "legendary", rank = 15, nameKey = "pickaxe.name.pick_l1", exchangeCost = 50 },
} :: { PickaxeDef }
-- 처음부터 주는 곡괭이(TEMP — 일반 1번, 15종에 포함)
EconomyV2Config.START_PICKAXE = "pick_c1"
-- 종류 → 목록 · 시작 장비(InventoryService · 저장 기본값이 이 표를 본다)
EconomyV2Config.EQUIPMENT = {
	pickaxe = { list = EconomyV2Config.PICKAXES, start = EconomyV2Config.START_PICKAXE },
} :: { [string]: { list: { PickaxeDef }, start: string } }

-- 큰 가방 게임패스(#32 자리 · #35 연결 — ID 원본 ShopConfig.V2_GAMEPASS_IDS.bigBag). ID가 nil이면 효과 없음(가방 배수 1)
EconomyV2Config.BIG_BAG_PASS_ID = ShopConfig.V2_GAMEPASS_IDS.bigBag :: number?
EconomyV2Config.BIG_BAG_MULT = 2

-- 곡괭이 배수 = PICK_RATIO^(rank − 1)(TEMP — 측정 손잡이). 펀치 데미지 업그레이드 자리에 들어간다.
EconomyV2Config.PICK_RATIO = 1.245
-- 가방 용량 = BAG_BASE + BAG_PER_RANK × (rank − 1) (장착 곡괭이 — TEMP 측정 손잡이)
EconomyV2Config.BAG_BASE = 20
EconomyV2Config.BAG_PER_RANK = 4

-- ===== 강화 · 별 (DESIGN 16장 "곡괭이") ===================================================================

EconomyV2Config.ENHANCE_MAX = 10 -- 사람 결정(+10 · 100% 성공)
-- 강화 효과 = 1 + ENHANCE_STEP × 강화 수준(TEMP). 비용 = 광석 점수 ENHANCE_COST_BASE × ENHANCE_COST_GROWTH^(지금 수준)(TEMP —
-- 광석 점수 = 게이지 점수와 같다 · 낮은 광석부터 낸다. Claude 해석: 결정은 "광석을 쓴다"뿐이다)
EconomyV2Config.ENHANCE_STEP = 0.02 -- #33: +10 = ×1.2 < 곡괭이 한 칸(PICK_RATIO) — 새 곡괭이 +0 ≥ 이전 +10
EconomyV2Config.ENHANCE_COST_BASE = 2.2
EconomyV2Config.ENHANCE_COST_GROWTH = 1.35
-- #33 결정 N14: 강화 비용은 장착 곡괭이의 등급과 단계(지금 강화 수준)에 따라 커진다 — 곡괭이마다 강화가 따로 · 새 곡괭이는 +0부터.
-- 비용(광석 점수) = ceil(ENHANCE_COST_BASE × ENHANCE_COST_BY_RARITY[등급] × ENHANCE_COST_GROWTH^수준) (TEMP — 5차 측정 손잡이)
-- 효과(등급별 — nil이면 ENHANCE_STEP) = 1 + ENHANCE_STEP_BY_RARITY[등급] × 수준
-- 목표(측정 기준): 새 곡괭이 +0 ≥ 이전 곡괭이 +10(바꾸는 것이 손해가 아니다) · 그 곡괭이 강화가 다음 곡괭이까지 공백을 채운다
EconomyV2Config.ENHANCE_COST_BY_RARITY = { common = 1, rare = 3, epic = 9, mythic = 27, legendary = 81 } :: { [string]: number }
EconomyV2Config.ENHANCE_STEP_BY_RARITY = nil :: { [string]: number }?
-- 강화 블럭스 비용(PENDING N5 — 사람 결정 전이라 nil = 블럭스 안 씀). 측정 변형만 넣어 본다(지시서 #31): 비용 = BASE × GROWTH^(지금 수준)
EconomyV2Config.ENHANCE_BLOX_COST_BASE = nil :: BigNumber?
EconomyV2Config.ENHANCE_BLOX_COST_GROWTH = 10

-- 별 1 ~ 5성에 소모하는 같은 곡괭이 수(사람 결정 — 누적 26)
EconomyV2Config.STAR_CONSUME = { 1, 3, 5, 7, 10 }
-- 별 효과 = 1 + STAR_STEP × 별 수(TEMP)
EconomyV2Config.STAR_STEP = 0.1

-- ===== 제작 (DESIGN 16장 "제작") ==========================================================================

-- 칸 수(0 ~ 5)마다 등급 확률(%) — TEMP 측정 손잡이. 등급 안에서는 RARITY_SPLIT 비율로 나눈다(EconomyV2Logic.oddsFor가 15종 전체 표를 만든다).
-- 규칙(validate · EconomyV2Tests): 칸마다 합 100 · 칸이 늘수록 "그 등급 이상" 확률이 줄지 않는다 · 전설 ≤ LEGENDARY_ODDS_MAX_PCT.
EconomyV2Config.RARITY_ODDS = {
	[0] = { common = 94, rare = 5.5, epic = 0.5, mythic = 0, legendary = 0 },
	[1] = { common = 70, rare = 26, epic = 3.9, mythic = 0.1, legendary = 0 }, -- #33: 1 ~ 3칸 신화 낮춤(2칸 제작이 수백 번 — 신화가 확률로 몰려 14종째가 빨랐다)
	[2] = { common = 45, rare = 40, epic = 14.7, mythic = 0.3, legendary = 0 },
	[3] = { common = 30, rare = 40, epic = 28.5, mythic = 1.5, legendary = 0 },
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

-- 제작 · 부화 시간 = 연출 + 스킵(지시서 #31 — DESIGN 16장 "제작"). 제작 간격은 시간 목표 손잡이가 아니다(15종은 상위 광석 공급으로 맞춘다).
--   무료        연출이 CRAFT_SKIP_SEC 지나면 스킵 → 자동 제작도 그 간격마다 1회(TEMP — 연출 길이는 나중)
--   연출 생략   로벅스 상품 "제작 연출 생략" 보유 → 서버 최소 간격 CRAFT_MIN_INTERVAL_SEC마다 1회(TEMP)
--   트리플      로벅스 상품 "트리플 제작" → 한 번에 TRIPLE_CRAFT_COUNT회(광석 5 × 3)
-- 부화도 같은 모델(HATCH_* · 트리플 부화 = 기존 Triple Hatch).
EconomyV2Config.CRAFT_SKIP_SEC = 5
EconomyV2Config.CRAFT_MIN_INTERVAL_SEC = 1
EconomyV2Config.TRIPLE_CRAFT_COUNT = 3 -- 트리플 제작(사람 결정 "한 번에 3개")
-- 대장간(제작 · 교환 · 강화)이 열리는 조건(#32 결정 N8 — 8층에 처음 도달하면 영구로 열린다 · 환생해도 안 닫힘). 둘 다 nil = 처음부터.
--   FORGE_UNLOCK_STAGE     그 층에 처음 도달하면(지금 8) — 열림은 저장 필드 forgeOpen(v10)에 남는다(InventoryService.openForge)
--   FORGE_UNLOCK_REBIRTHS  환생 수 조건(측정 비교용 — #31 R2. 지금 nil)
-- 이유: 첫 환생(약 4분)과 대장간을 다른 시점에 보여 준다 · 처음부터 열면 1 ~ 7층이 20 ~ 31% 빠르다(#31 3차 측정).
EconomyV2Config.FORGE_UNLOCK_REBIRTHS = nil :: number?
EconomyV2Config.FORGE_UNLOCK_STAGE = 8 :: number?
-- 대장간 화면 · 서버(#33). 결과 연출 길이(TEMP) — 스킵 버튼은 CRAFT_SKIP_SEC에 나타난다(무료 제작 간격과 같다)
EconomyV2Config.CRAFT_ANIM_SEC = 6
-- 로벅스 상품(#35 연결 — ID 원본 ShopConfig.V2_GAMEPASS_IDS. ID가 nil이면 보유 없음 = 무료와 같다)
EconomyV2Config.CRAFT_SKIP_PASS_ID = ShopConfig.V2_GAMEPASS_IDS.instantCraft :: number?
EconomyV2Config.TRIPLE_CRAFT_PASS_ID = ShopConfig.V2_GAMEPASS_IDS.tripleCraft :: number?
EconomyV2Config.HATCH_SKIP_PASS_ID = ShopConfig.V2_GAMEPASS_IDS.instantHatch :: number?
-- 부화 연출 길이(TEMP — 스킵 버튼은 HATCH_SKIP_SEC에 나타난다 · #35)
EconomyV2Config.HATCH_ANIM_SEC = 6
-- 자동 부화 서버 루프 주기(초 · #35)
EconomyV2Config.AUTO_HATCH_POLL_SEC = 0.25
-- 자동 부화 중 크게 알릴 펫 희귀도(1 ~ 4 — 이 값 이상 · #35)
EconomyV2Config.HATCH_BIG_NOTICE_RARITY = 3
-- 부화 연출 에셋 자리(#35 — nil이면 임시 도형: 흔들리는 알 칸)
EconomyV2Config.HATCH_FX_VISUAL = { eggModelId = nil :: number?, effectId = nil :: number? }
-- 새 경제 전용 상품(꺼져 있으면 안 보이고 효과 없음 — #35)
EconomyV2Config.V2_ONLY_PRODUCTS = { bigBag = true, instantCraft = true, tripleCraft = true, instantHatch = true } :: { [string]: boolean }
-- 제한 지역(ArePaidRandomItemsRestricted)에서 숨기는 새 경제 상품(DESIGN 16장 — 랜덤의 재료 · 횟수를 로벅스로 늘린다 · #35).
-- 행운 상품(paidRandom)은 기존 경로가 따로 숨긴다. 새 경제가 켜졌을 때만 적용한다(꺼지면 Triple Hatch는 지금처럼 보인다)
EconomyV2Config.RESTRICTED_RANDOM_PASSES = { bigBag = true, instantCraft = true, tripleCraft = true, instantHatch = true, hatch3x = true } :: { [string]: boolean }
-- 자동 제작 서버 루프 주기(초 — 제작 간격 판정은 CRAFT_SKIP_SEC · CRAFT_MIN_INTERVAL_SEC가 한다)
EconomyV2Config.AUTO_CRAFT_POLL_SEC = 0.25
-- 자동 제작 결과 목록에 남기는 줄 수(클라 표시)
EconomyV2Config.AUTO_CRAFT_LOG_MAX = 5
-- 이 등급 이상이면 자동 제작 중에도 크게 알린다(토스트)
EconomyV2Config.CRAFT_BIG_NOTICE_RARITY = "mythic"
-- 로비 임시 대장간(#33 — 에셋 자리). modelId가 nil이면 임시 도형(블록 + 지붕). 위치 = 스폰 바닥 빈 자리(바닥 위 Y 0)
EconomyV2Config.FORGE_SITE = {
	position = Vector3.new(-235, 0, -60),
	size = Vector3.new(10, 7, 8),
	color = Color3.fromRGB(110, 80, 60),
	modelId = nil :: number?,
	iconId = nil :: number?,
	effectId = nil :: number?,
}
EconomyV2Config.HATCH_SKIP_SEC = 5
EconomyV2Config.HATCH_MIN_INTERVAL_SEC = 1
EconomyV2Config.TRIPLE_HATCH_COUNT = 3

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

-- 새 경제에서 빠지는 로벅스 상품(ShopConfig 키 — 지시서 #31 G14). 플래그가 켜지면 상점에 안 보이고 효과도 없다 · 구매 요청은 not_available.
-- 플래그가 꺼진 경로는 그대로다. 코드에서 완전히 지우는 일은 플래그를 켜는 단계에서 한다(대시보드 판매 중지는 사람 — ROADMAP 출시 체크리스트 30).
EconomyV2Config.REMOVED_PRODUCTS = { rebirth2x = true } :: { [string]: boolean }
-- 새 경제에서 빠지는 상점 업그레이드(UpgradeConfig 키 — #34). 곡괭이가 그 역할을 맡는다(DESIGN 16장 "곡괭이"). 플래그가 켜지면 상점에 안 보이고
-- 효과도 없다(AttackService가 곡괭이 배수를 대신 곱한다) · 구매 요청은 invalid_upgrade. 꺼지면 그대로다
EconomyV2Config.REMOVED_UPGRADES = { punchDamage = true } :: { [string]: boolean }

-- 손에 든 곡괭이(#34 — 에셋 자리). 곡괭이 id → { modelId, swingAnimId } — 둘 다 nil이면 임시 도형(자루 + 머리 · 등급 색) · 휘두르기 없음.
-- 표에 없는 id도 임시 도형이다. 크기(스터드)는 임시 도형 값
EconomyV2Config.PICKAXE_VISUALS = {} :: { [string]: { modelId: number?, swingAnimId: number? } }
EconomyV2Config.HELD_PICKAXE_SIZE = { handle = Vector3.new(0.3, 3, 0.3), head = Vector3.new(2.2, 0.45, 0.45) }

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
	for _, def in ipairs(EconomyV2Config.PICKAXES) do
		assert(def.nameKey == "pickaxe.name." .. def.id, "EconomyV2Config: " .. def.id .. " nameKey 꼴")
	end
	assert(#EconomyV2Config.ORE_NAME_KEYS == EconomyV2Config.ORE_COUNT, "EconomyV2Config: ORE_NAME_KEYS 수 ≠ ORE_COUNT")
	assert(#EconomyV2Config.ORE_VISUALS == EconomyV2Config.ORE_COUNT, "EconomyV2Config: ORE_VISUALS 수 ≠ ORE_COUNT")
	for _, kind in ipairs(EconomyV2Config.EQUIPMENT_KINDS) do
		local e = EconomyV2Config.EQUIPMENT[kind]
		assert(e ~= nil and #e.list > 0, "EconomyV2Config: EQUIPMENT." .. kind .. " 목록 없음")
		local found = false
		for _, def in ipairs(e.list) do
			found = found or def.id == e.start
		end
		assert(found, "EconomyV2Config: EQUIPMENT." .. kind .. " 시작 장비가 목록에 없다")
	end
	if EconomyV2Config.ORE_DROP_BY_ORE ~= nil then
		for k = 1, EconomyV2Config.ORE_COUNT do
			local d = (EconomyV2Config.ORE_DROP_BY_ORE :: any)[k]
			assert(type(d) == "number" and d >= EconomyV2Config.ORE_DROP_MIN, string.format("EconomyV2Config: ORE_DROP_BY_ORE[%d] ≥ ORE_DROP_MIN", k))
		end
	end
	-- 점수 표: 정수 ≥ 1 · 줄지 않음 · 마지막 광석 CRAFT_INPUT개만 꽉 찬 칸
	assert(#EconomyV2Config.ORE_POINTS == EconomyV2Config.ORE_COUNT, "EconomyV2Config: ORE_POINTS 수 ≠ ORE_COUNT")
	local prevPt = 1
	for k, pt in ipairs(EconomyV2Config.ORE_POINTS) do
		assert(pt % 1 == 0 and pt >= prevPt, string.format("EconomyV2Config: ORE_POINTS[%d] 정수 · 줄지 않음", k))
		prevPt = pt
	end
	local top = EconomyV2Config.ORE_POINTS[EconomyV2Config.ORE_COUNT]
	local second = EconomyV2Config.ORE_POINTS[EconomyV2Config.ORE_COUNT - 1]
	assert(top * EconomyV2Config.CRAFT_INPUT >= EconomyV2Config.GAUGE_UNIT * EconomyV2Config.CRAFT_INPUT
		and top * (EconomyV2Config.CRAFT_INPUT - 1) + second < EconomyV2Config.GAUGE_UNIT * EconomyV2Config.CRAFT_INPUT,
		"EconomyV2Config: 마지막 광석 CRAFT_INPUT개만 꽉 찬 칸")
	for _, r in ipairs(EconomyV2Config.RARITIES) do
		local c = EconomyV2Config.ENHANCE_COST_BY_RARITY[r]
		assert(type(c) == "number" and c > 0, "EconomyV2Config: ENHANCE_COST_BY_RARITY." .. r .. " > 0")
	end
	assert(EconomyV2Config.CRAFT_ANIM_SEC >= EconomyV2Config.CRAFT_SKIP_SEC, "EconomyV2Config: 연출 길이 ≥ 스킵 시점")
	for k, key in ipairs(EconomyV2Config.ORE_NAME_KEYS) do
		assert(key == "ore.name." .. k, "EconomyV2Config: ORE_NAME_KEYS 꼴")
	end
	assert(EconomyV2Config.UPPER_ORE_DROP_MULT > 0 and EconomyV2Config.ORE_PER_BLOCK > 0, "EconomyV2Config: 드롭 기대값 > 0")
	assert(EconomyV2Config.CRAFT_SKIP_SEC >= EconomyV2Config.CRAFT_MIN_INTERVAL_SEC and EconomyV2Config.CRAFT_MIN_INTERVAL_SEC > 0,
		"EconomyV2Config: 제작 스킵 ≥ 최소 간격 > 0")
	assert(EconomyV2Config.HATCH_SKIP_SEC >= EconomyV2Config.HATCH_MIN_INTERVAL_SEC and EconomyV2Config.HATCH_MIN_INTERVAL_SEC > 0,
		"EconomyV2Config: 부화 스킵 ≥ 최소 간격 > 0")
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

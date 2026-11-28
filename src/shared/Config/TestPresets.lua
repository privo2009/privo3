--!strict
-- Studio 전용 테스트 프리셋 (지시서 #13 3단계 · #38 새 경제로 다시 뽑음). **데이터만** 있다 — 켜는 규칙 · 안전장치는 Server/Data/TestPresetGate,
-- 사람용 사용법 · 프리셋마다 무엇인지는 docs/TUNING.md "테스트 프리셋".
--
-- 사용: Bootstrap의 TEST_PRESET(기본 nil)에 아래 이름 하나를 적고 Play → 그 시점 상태의 **Mock 프로필**로 시작한다.
--       실제 개발 계정 데이터에는 읽기도 쓰기도 하지 않는다. Play를 멈추면 사라진다. 커밋할 때는 언제나 nil로 되돌린다.
--
-- ===== 값의 출처 ======================================================================
--
-- 손으로 정한 값이 아니다. EconomyReport 지금 TEMP(set = {}) 표준 플레이어 40명을 Server/Tools/PresetExport로 돌려
-- 시점마다 그 시각에 처음 런을 시작한 순간의 상태를 모으고, 환생 수 → 최고 층 순으로 줄 세운 **가운데 한 사람**을 통째로 옮겼다
-- (2026-11-25 지시서 #38 6단계 · #45 걷기 · 로비 모델 · 2026-11-27 #46 배율 0.5 · PICK_RATIO 1.40으로 다시 뽑음 —
-- 30분 최고 17층 · 1시간 21층 · 2시간 24층 · 3시간 25층(22명 — 나머지는 15종을 모아 먼저 끝났다)). TEMP 숫자 · 배율이 바뀌면
-- Bootstrap PRESET_EXPORT_ENABLED로 다시 뽑아 이 표를 바꾼다. pre_rebirth는 뽑지 않고 hour1에서 만든다(아래 source).
--
-- 칭호 자동 롤은 꺼서 시작한다. 보유 칭호 · 아우라는 장착 중인 것 하나다(시뮬레이터는 가장 높은 것만 기억한다).
-- 펫은 실효 증가분 큰 순으로 PresetExport.MAX_PETS(20)마리까지 · equipped는 그 배열의 번호(앞에서 슬롯 수만큼 — 게임의 "최고 장착"과 같다).
-- 곡괭이 count = 보유 수(별은 사본을 써서 올린 뒤의 값). 새 경제 안내(#36)는 TestPresetGate가 상태에서 다시 채운다.

type Big = { m: number, e: number }

export type PresetPet = { petId: string, tier: number }
export type PresetPick = { count: number, stars: number, enh: number }

export type Preset = {
	label: string,
	source: string,
	strength: Big,
	blox: Big,
	lifeBlox: Big,
	lifetimeBlox: Big,
	rebirths: Big,
	padIndex: number,
	maxStage: number,
	-- 계정 전체에서 깬 가장 깊은 층(stats.bestRunDepth — 시뮬 maxEver · #49 알 4 해금). 없으면 0
	bestDepth: number?,
	upgrades: { [string]: number },
	title: string | false,
	aura: string | false,
	pets: { PresetPet },
	equipped: { number },
	-- 새 경제(#38)
	coins: Big,
	ores: { number },
	tokens: { [string]: number },
	pickaxes: { [string]: PresetPick },
	equippedPickaxe: string,
	forgeOpen: boolean,
}

local TestPresets = {}

-- Bootstrap TEST_PRESET에 적는 이름(시점 순서).
TestPresets.NAMES = { "fresh", "min10", "min30", "hour1", "pre_rebirth", "hour2", "hour3" } -- pre_rebirth = hour1 + 블럭스만(#44 — 환생 길)

TestPresets.Presets = {
	fresh = {
		label = "시작 직후",
		source = "EconomyReport 표준 플레이어(#46 배율 0.5 · PICK_RATIO 1.40 · 걷기 · 로비 모델) 40명 중 그 시각 중앙값(20번째 · 0.0분 · 환생 0회 · 최고 0층)",
		strength = { m = 1.000000, e = 0 },
		blox = { m = 0, e = 0 },
		lifeBlox = { m = 0, e = 0 },
		lifetimeBlox = { m = 0, e = 0 },
		rebirths = { m = 0, e = 0 },
		padIndex = 1, maxStage = 1, bestDepth = 0,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchSpeed = 0, titleLuck = 0 },
		title = false, aura = false,
		pets = {  },
		equipped = {  },
		coins = { m = 0, e = 0 },
		ores = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		tokens = { rare = 0, epic = 0, mythic = 0, legendary = 0, next = 0 },
		pickaxes = { pick_c1 = { count = 1, stars = 0, enh = 0 } },
		equippedPickaxe = "pick_c1", forgeOpen = false,
	},
	min10 = {
		label = "10분",
		source = "EconomyReport 표준 플레이어(#46 배율 0.5 · PICK_RATIO 1.40 · 걷기 · 로비 모델) 40명 중 그 시각 중앙값(20번째 · 10.9분 · 환생 1회 · 최고 7층)",
		strength = { m = 1.110489, e = 4 },
		blox = { m = 6.121738, e = 2 },
		lifeBlox = { m = 6.110267, e = 2 },
		lifetimeBlox = { m = 1.612174, e = 3 },
		rebirths = { m = 1.000000, e = 0 },
		padIndex = 5, maxStage = 7, bestDepth = 7,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchSpeed = 0, titleLuck = 0 },
		title = false, aura = false,
		pets = {
			{ petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 },
			{ petId = "egg1_epic", tier = 1 }, { petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_common", tier = 1 },
			{ petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2 },
		coins = { m = 4.826562, e = 1 },
		ores = { 83, 71, 51, 0, 0, 0, 0, 0, 0, 0 },
		tokens = { rare = 0, epic = 0, mythic = 0, legendary = 0, next = 0 },
		pickaxes = { pick_c1 = { count = 1, stars = 0, enh = 0 } },
		equippedPickaxe = "pick_c1", forgeOpen = false,
	},
	min30 = {
		label = "30분",
		source = "EconomyReport 표준 플레이어(#46 배율 0.5 · PICK_RATIO 1.40 · 걷기 · 로비 모델) 40명 중 그 시각 중앙값(20번째 · 30.8분 · 환생 8회 · 최고 17층)",
		strength = { m = 6.793367, e = 6 },
		blox = { m = 2.990969, e = 7 },
		lifeBlox = { m = 6.280348, e = 6 },
		lifetimeBlox = { m = 5.682684, e = 7 },
		rebirths = { m = 8.000000, e = 0 },
		padIndex = 13, maxStage = 15, bestDepth = 17,
		upgrades = { auraLuck = 0, bloxGain = 75, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "champion", aura = "pack2_rare",
		pets = {
			{ petId = "egg2_common", tier = 2 }, { petId = "egg2_common", tier = 2 }, { petId = "egg1_epic", tier = 3 }, { petId = "egg2_rare", tier = 1 },
			{ petId = "egg2_rare", tier = 1 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 },
			{ petId = "egg1_rare", tier = 3 }, { petId = "egg2_common", tier = 1 }, { petId = "egg1_epic", tier = 2 }, { petId = "egg1_common", tier = 3 },
			{ petId = "egg1_rare", tier = 2 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_rare", tier = 1 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.301445, e = 3 },
		ores = { 0, 0, 0, 0, 0, 6, 1, 0, 0, 0 },
		tokens = { rare = 126, epic = 0, mythic = 0, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 31, stars = 5, enh = 0 }, pick_c2 = { count = 17, stars = 5, enh = 0 }, pick_c3 = { count = 2, stars = 5, enh = 0 },
			pick_e1 = { count = 1, stars = 0, enh = 0 }, pick_e2 = { count = 1, stars = 0, enh = 0 }, pick_e3 = { count = 1, stars = 0, enh = 0 },
			pick_e4 = { count = 1, stars = 1, enh = 7 }, pick_r1 = { count = 4, stars = 3, enh = 0 }, pick_r2 = { count = 1, stars = 4, enh = 0 },
			pick_r3 = { count = 5, stars = 3, enh = 0 }, pick_r4 = { count = 4, stars = 2, enh = 9 },
		},
		equippedPickaxe = "pick_e4", forgeOpen = true,
	},
	hour1 = {
		label = "1시간",
		source = "EconomyReport 표준 플레이어(#46 배율 0.5 · PICK_RATIO 1.40 · 걷기 · 로비 모델) 40명 중 그 시각 중앙값(20번째 · 60.6분 · 환생 12회 · 최고 21층)",
		strength = { m = 1.004768, e = 11 },
		blox = { m = 3.692764, e = 9 },
		lifeBlox = { m = 1.625231, e = 9 },
		lifetimeBlox = { m = 9.395359, e = 9 },
		rebirths = { m = 1.200000, e = 1 },
		padIndex = 18, maxStage = 20, bestDepth = 21,
		upgrades = { auraLuck = 0, bloxGain = 110, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack2_legendary",
		pets = {
			{ petId = "egg2_rare", tier = 2 }, { petId = "egg3_common", tier = 1 }, { petId = "egg3_common", tier = 1 }, { petId = "egg2_common", tier = 2 },
			{ petId = "egg2_common", tier = 2 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg1_common", tier = 4 },
			{ petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg1_epic", tier = 2 }, { petId = "egg1_legendary", tier = 1 },
			{ petId = "egg1_rare", tier = 2 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 }, { petId = "egg1_common", tier = 2 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.801821, e = 5 },
		ores = { 0, 0, 0, 0, 1, 0, 0, 0, 0, 0 },
		tokens = { rare = 176, epic = 93, mythic = 1, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 82, stars = 5, enh = 0 }, pick_c2 = { count = 32, stars = 5, enh = 0 }, pick_c3 = { count = 26, stars = 5, enh = 0 },
			pick_e1 = { count = 1, stars = 2, enh = 0 }, pick_e2 = { count = 3, stars = 2, enh = 4 }, pick_e3 = { count = 2, stars = 1, enh = 6 },
			pick_e4 = { count = 1, stars = 2, enh = 7 }, pick_r1 = { count = 6, stars = 5, enh = 0 }, pick_r2 = { count = 10, stars = 5, enh = 0 },
			pick_r3 = { count = 4, stars = 4, enh = 0 }, pick_r4 = { count = 4, stars = 2, enh = 0 },
		},
		equippedPickaxe = "pick_e4", forgeOpen = true,
	},
	pre_rebirth = {
		label = "환생 직전(1시간 + 블럭스만 다음 환생 비용 × 1.1)",
		source = "hour1에서 블럭스만 다음 환생 비용(1000 × 4^12 = 1.68e10)의 1.1배로 · lifeBlox · lifetimeBlox도 같은 만큼 더함(#44 — 봇 환생 구간 pre_rebirth · #46 다시 뽑은 hour1에서)",
		strength = { m = 1.004768, e = 11 },
		blox = { m = 1.845494, e = 10 },
		lifeBlox = { m = 1.638740, e = 10 },
		lifetimeBlox = { m = 2.415753, e = 10 },
		rebirths = { m = 1.200000, e = 1 },
		padIndex = 18, maxStage = 20, bestDepth = 21,
		upgrades = { auraLuck = 0, bloxGain = 110, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack2_legendary",
		pets = {
			{ petId = "egg2_rare", tier = 2 }, { petId = "egg3_common", tier = 1 }, { petId = "egg3_common", tier = 1 }, { petId = "egg2_common", tier = 2 },
			{ petId = "egg2_common", tier = 2 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg1_common", tier = 4 },
			{ petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg1_epic", tier = 2 }, { petId = "egg1_legendary", tier = 1 },
			{ petId = "egg1_rare", tier = 2 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 }, { petId = "egg1_common", tier = 2 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.801821, e = 5 },
		ores = { 0, 0, 0, 0, 1, 0, 0, 0, 0, 0 },
		tokens = { rare = 176, epic = 93, mythic = 1, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 82, stars = 5, enh = 0 }, pick_c2 = { count = 32, stars = 5, enh = 0 }, pick_c3 = { count = 26, stars = 5, enh = 0 },
			pick_e1 = { count = 1, stars = 2, enh = 0 }, pick_e2 = { count = 3, stars = 2, enh = 4 }, pick_e3 = { count = 2, stars = 1, enh = 6 },
			pick_e4 = { count = 1, stars = 2, enh = 7 }, pick_r1 = { count = 6, stars = 5, enh = 0 }, pick_r2 = { count = 10, stars = 5, enh = 0 },
			pick_r3 = { count = 4, stars = 4, enh = 0 }, pick_r4 = { count = 4, stars = 2, enh = 0 },
		},
		equippedPickaxe = "pick_e4", forgeOpen = true,
	},
	hour2 = {
		label = "2시간",
		source = "EconomyReport 표준 플레이어(#46 배율 0.5 · PICK_RATIO 1.40 · 걷기 · 로비 모델) 40명 중 그 시각 중앙값(20번째 · 121.0분 · 환생 15회 · 최고 24층)",
		strength = { m = 4.337541, e = 5 },
		blox = { m = 3.185836, e = 10 },
		lifeBlox = { m = 4.170079, e = 6 },
		lifetimeBlox = { m = 3.968394, e = 11 },
		rebirths = { m = 1.500000, e = 1 },
		padIndex = 13, maxStage = 14, bestDepth = 24,
		upgrades = { auraLuck = 0, bloxGain = 127, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack3_rare",
		pets = {
			{ petId = "egg3_common", tier = 3 }, { petId = "egg3_rare", tier = 2 }, { petId = "egg3_common", tier = 2 }, { petId = "egg3_epic", tier = 1 },
			{ petId = "egg3_epic", tier = 1 }, { petId = "egg3_common", tier = 1 }, { petId = "egg3_common", tier = 1 }, { petId = "egg2_common", tier = 2 },
			{ petId = "egg2_common", tier = 2 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg2_rare", tier = 1 }, { petId = "egg1_common", tier = 4 },
			{ petId = "egg1_rare", tier = 3 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg2_common", tier = 1 }, { petId = "egg2_common", tier = 1 },
			{ petId = "egg1_epic", tier = 2 }, { petId = "egg1_common", tier = 3 }, { petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 2.757227, e = 4 },
		ores = { 0, 4, 20, 14, 22, 0, 0, 3, 0, 0 },
		tokens = { rare = 214, epic = 219, mythic = 14, legendary = 6, next = 0 },
		pickaxes = {
			pick_c1 = { count = 122, stars = 5, enh = 0 }, pick_c2 = { count = 64, stars = 5, enh = 0 }, pick_c3 = { count = 39, stars = 5, enh = 0 },
			pick_e1 = { count = 3, stars = 4, enh = 0 }, pick_e2 = { count = 1, stars = 3, enh = 0 }, pick_e3 = { count = 1, stars = 3, enh = 6 },
			pick_e4 = { count = 5, stars = 2, enh = 8 }, pick_m1 = { count = 1, stars = 1, enh = 6 }, pick_r1 = { count = 30, stars = 5, enh = 0 },
			pick_r2 = { count = 26, stars = 5, enh = 4 }, pick_r3 = { count = 13, stars = 5, enh = 0 }, pick_r4 = { count = 10, stars = 4, enh = 5 },
		},
		equippedPickaxe = "pick_m1", forgeOpen = true,
	},
	hour3 = {
		label = "3시간",
		source = "EconomyReport 표준 플레이어(#49 배율 0.5 · PICK_RATIO 1.40 · 알 4 · 걷기 · 로비 모델) 22명 중 그 시각 중앙값(11번째 · 180.9분 · 환생 16회 · 최고 25층)",
		strength = { m = 8.329607, e = 14 },
		blox = { m = 4.046574, e = 12 },
		lifeBlox = { m = 3.893109, e = 12 },
		lifetimeBlox = { m = 5.528310, e = 12 },
		rebirths = { m = 1.600000, e = 1 },
		padIndex = 24, maxStage = 25, bestDepth = 25,
		upgrades = { auraLuck = 0, bloxGain = 139, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack3_legendary",
		pets = {
			{ petId = "egg3_common", tier = 3 }, { petId = "egg3_epic", tier = 2 }, { petId = "egg3_rare", tier = 2 }, { petId = "egg3_rare", tier = 2 },
			{ petId = "egg3_common", tier = 2 }, { petId = "egg3_common", tier = 2 }, { petId = "egg4_rare", tier = 1 }, { petId = "egg3_rare", tier = 1 },
			{ petId = "egg3_common", tier = 1 }, { petId = "egg2_common", tier = 2 }, { petId = "egg2_common", tier = 2 }, { petId = "egg1_epic", tier = 3 },
			{ petId = "egg1_legendary", tier = 2 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg2_rare", tier = 1 }, { petId = "egg2_rare", tier = 1 },
			{ petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg2_common", tier = 1 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 2.768781, e = 6 },
		ores = { 0, 0, 0, 0, 0, 0, 0, 1, 0, 0 },
		tokens = { rare = 249, epic = 354, mythic = 3, legendary = 49, next = 6 },
		pickaxes = {
			pick_c1 = { count = 186, stars = 5, enh = 0 }, pick_c2 = { count = 81, stars = 5, enh = 0 }, pick_c3 = { count = 60, stars = 5, enh = 0 },
			pick_e1 = { count = 16, stars = 5, enh = 0 }, pick_e2 = { count = 5, stars = 5, enh = 0 }, pick_e3 = { count = 8, stars = 4, enh = 0 },
			pick_e4 = { count = 4, stars = 3, enh = 8 }, pick_m1 = { count = 3, stars = 1, enh = 6 }, pick_m2 = { count = 1, stars = 0, enh = 6 },
			pick_m3 = { count = 1, stars = 0, enh = 5 },
			pick_r1 = { count = 84, stars = 5, enh = 4 }, pick_r2 = { count = 42, stars = 5, enh = 0 }, pick_r3 = { count = 26, stars = 5, enh = 0 },
			pick_r4 = { count = 15, stars = 5, enh = 5 },
		},
		equippedPickaxe = "pick_m3", forgeOpen = true,
	},
} :: { [string]: Preset }

return TestPresets

--!strict
-- Studio 전용 테스트 프리셋 (지시서 #13 3단계 · #38 새 경제로 다시 뽑음). **데이터만** 있다 — 켜는 규칙 · 안전장치는 Server/Data/TestPresetGate,
-- 사람용 사용법 · 프리셋마다 무엇인지는 docs/TUNING.md "테스트 프리셋".
--
-- 사용: Bootstrap의 TEST_PRESET(기본 nil)에 아래 이름 하나를 적고 Play → 그 시점 상태의 **Mock 프로필**로 시작한다.
--       실제 개발 계정 데이터에는 읽기도 쓰기도 하지 않는다. Play를 멈추면 사라진다. 커밋할 때는 언제나 nil로 되돌린다.
--
-- ===== 값의 출처 ======================================================================
--
-- 손으로 정한 값이 아니다. EconomyReport V4(지금 TEMP — set = {}) 표준 플레이어 40명을 Server/Tools/PresetExport로 돌려
-- 시점마다 그 시각에 처음 런을 시작한 순간의 상태를 모으고, 환생 수 → 최고 층 순으로 줄 세운 **가운데 한 사람**을 통째로 옮겼다
-- (2026-11-25 지시서 #38 6단계). TEMP 숫자가 바뀌면 Bootstrap PRESET_EXPORT_ENABLED로 다시 뽑아 이 표를 바꾼다.
-- 3시간은 그 시각까지 플레이한 19명 중 가운데다(나머지는 15종을 모아 먼저 끝났다).
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
		source = "EconomyReport V4 표준 플레이어 40명 중 그 시각 중앙값(20번째 · 0.0분 · 환생 0회 · 최고 0층)",
		strength = { m = 1, e = 0 },
		blox = { m = 0, e = 0 },
		lifeBlox = { m = 0, e = 0 },
		lifetimeBlox = { m = 0, e = 0 },
		rebirths = { m = 0, e = 0 },
		padIndex = 1, maxStage = 1,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchSpeed = 0, titleLuck = 0 },
		title = false, aura = false,
		pets = {},
		equipped = {},
		coins = { m = 0, e = 0 },
		ores = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		tokens = { rare = 0, epic = 0, mythic = 0, legendary = 0, next = 0 },
		pickaxes = { pick_c1 = { count = 1, stars = 0, enh = 0 } },
		equippedPickaxe = "pick_c1", forgeOpen = false,
	},
	min10 = {
		label = "10분",
		source = "EconomyReport V4 표준 플레이어 40명 중 그 시각 중앙값(20번째 · 10.2분 · 환생 2회 · 최고 9층)",
		strength = { m = 1.455197, e = 4 },
		blox = { m = 1.959075, e = 3 },
		lifeBlox = { m = 1.635260, e = 3 },
		lifetimeBlox = { m = 6.959075, e = 3 },
		rebirths = { m = 2, e = 0 },
		padIndex = 6, maxStage = 8,
		upgrades = { auraLuck = 0, bloxGain = 2, petLuck = 0, petSlots = 0, punchSpeed = 1, titleLuck = 0 },
		title = false, aura = false,
		pets = {
			{ petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_common", tier = 2 },
			{ petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2 },
		coins = { m = 6.105078, e = 1 },
		ores = { 0, 9, 20, 0, 0, 0, 0, 0, 0, 0 },
		tokens = { rare = 15, epic = 0, mythic = 0, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 1, stars = 3, enh = 0 }, pick_c2 = { count = 1, stars = 3, enh = 0 }, pick_c3 = { count = 1, stars = 1, enh = 0 },
			pick_e2 = { count = 1, stars = 0, enh = 2 }, pick_r1 = { count = 2, stars = 1, enh = 0 }, pick_r2 = { count = 1, stars = 0, enh = 7 },
			pick_r3 = { count = 1, stars = 1, enh = 0 }, pick_r4 = { count = 1, stars = 1, enh = 2 },
		},
		equippedPickaxe = "pick_e2", forgeOpen = true,
	},
	min30 = {
		label = "30분(8층 대장간 뒤)",
		source = "EconomyReport V4 표준 플레이어 40명 중 그 시각 중앙값(20번째 · 30.1분 · 환생 9회 · 최고 17층)",
		strength = { m = 6.548024, e = 7 },
		blox = { m = 2.618219, e = 7 },
		lifeBlox = { m = 1.876215, e = 7 },
		lifetimeBlox = { m = 1.166521, e = 8 },
		rebirths = { m = 9, e = 0 },
		padIndex = 14, maxStage = 16,
		upgrades = { auraLuck = 0, bloxGain = 73, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "champion", aura = "pack2_rare",
		pets = {
			{ petId = "egg2_common", tier = 3 }, { petId = "egg2_rare", tier = 2 }, { petId = "egg2_rare", tier = 2 }, { petId = "egg1_common", tier = 4 },
			{ petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg2_common", tier = 1 },
			{ petId = "egg2_common", tier = 1 }, { petId = "egg1_epic", tier = 2 }, { petId = "egg1_epic", tier = 2 }, { petId = "egg1_legendary", tier = 1 },
			{ petId = "egg1_legendary", tier = 1 }, { petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 },
			{ petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.365104, e = 4 },
		ores = { 9, 10, 8, 14, 71, 18, 0, 0, 0, 0 },
		tokens = { rare = 221, epic = 24, mythic = 0, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 87, stars = 5, enh = 0 }, pick_c2 = { count = 23, stars = 5, enh = 0 }, pick_c3 = { count = 10, stars = 5, enh = 0 },
			pick_e1 = { count = 2, stars = 2, enh = 3 }, pick_e2 = { count = 1, stars = 1, enh = 0 }, pick_e3 = { count = 1, stars = 0, enh = 0 },
			pick_e4 = { count = 1, stars = 0, enh = 9 }, pick_r1 = { count = 9, stars = 4, enh = 8 }, pick_r2 = { count = 4, stars = 4, enh = 0 },
			pick_r3 = { count = 3, stars = 3, enh = 2 }, pick_r4 = { count = 4, stars = 2, enh = 5 },
		},
		equippedPickaxe = "pick_e4", forgeOpen = true,
	},
	hour1 = {
		label = "1시간",
		source = "EconomyReport V4 표준 플레이어 40명 중 그 시각 중앙값(20번째 · 60.2분 · 환생 12회 · 최고 21층)",
		strength = { m = 4.937557, e = 9 },
		blox = { m = 3.065184, e = 9 },
		lifeBlox = { m = 5.973071, e = 8 },
		lifetimeBlox = { m = 8.730668, e = 9 },
		rebirths = { m = 1.2, e = 1 },
		padIndex = 17, maxStage = 19,
		upgrades = { auraLuck = 0, bloxGain = 109, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack2_legendary",
		pets = {
			{ petId = "egg2_common", tier = 3 }, { petId = "egg2_common", tier = 3 }, { petId = "egg2_epic", tier = 2 }, { petId = "egg3_epic", tier = 1 },
			{ petId = "egg2_rare", tier = 2 }, { petId = "egg1_rare", tier = 4 }, { petId = "egg3_common", tier = 1 }, { petId = "egg1_epic", tier = 3 },
			{ petId = "egg2_rare", tier = 1 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_legendary", tier = 1 },
			{ petId = "egg1_legendary", tier = 1 }, { petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 },
			{ petId = "egg1_epic", tier = 1 }, { petId = "egg1_common", tier = 2 }, { petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.681940, e = 5 },
		ores = { 0, 0, 0, 9, 21, 18, 17, 0, 0, 0 },
		tokens = { rare = 224, epic = 64, mythic = 2, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 106, stars = 5, enh = 0 }, pick_c2 = { count = 31, stars = 5, enh = 0 }, pick_c3 = { count = 13, stars = 5, enh = 0 },
			pick_e1 = { count = 4, stars = 2, enh = 1 }, pick_e2 = { count = 1, stars = 2, enh = 4 }, pick_e3 = { count = 3, stars = 1, enh = 0 },
			pick_e4 = { count = 1, stars = 1, enh = 0 }, pick_m1 = { count = 1, stars = 0, enh = 5 }, pick_r1 = { count = 27, stars = 5, enh = 0 },
			pick_r2 = { count = 4, stars = 4, enh = 0 }, pick_r3 = { count = 1, stars = 4, enh = 5 }, pick_r4 = { count = 3, stars = 3, enh = 4 },
		},
		equippedPickaxe = "pick_m1", forgeOpen = true,
	},
	pre_rebirth = {
		label = "환생 직전(1시간 + 블럭스만 다음 환생 비용 × 1.1)",
		source = "hour1에서 블럭스만 다음 환생 비용(1000 × 4^12 = 1.68e10)의 1.1배로 · lifeBlox · lifetimeBlox도 같은 만큼 더함(#44 — 봇 환생 구간 pre_rebirth)",
		strength = { m = 4.937557, e = 9 },
		blox = { m = 1.845494, e = 10 },
		lifeBlox = { m = 1.598706, e = 10 },
		lifetimeBlox = { m = 2.412042, e = 10 },
		rebirths = { m = 1.2, e = 1 },
		padIndex = 17, maxStage = 19,
		upgrades = { auraLuck = 0, bloxGain = 109, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack2_legendary",
		pets = {
			{ petId = "egg2_common", tier = 3 }, { petId = "egg2_common", tier = 3 }, { petId = "egg2_epic", tier = 2 }, { petId = "egg3_epic", tier = 1 },
			{ petId = "egg2_rare", tier = 2 }, { petId = "egg1_rare", tier = 4 }, { petId = "egg3_common", tier = 1 }, { petId = "egg1_epic", tier = 3 },
			{ petId = "egg2_rare", tier = 1 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_legendary", tier = 1 },
			{ petId = "egg1_legendary", tier = 1 }, { petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 },
			{ petId = "egg1_epic", tier = 1 }, { petId = "egg1_common", tier = 2 }, { petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.681940, e = 5 },
		ores = { 0, 0, 0, 9, 21, 18, 17, 0, 0, 0 },
		tokens = { rare = 224, epic = 64, mythic = 2, legendary = 0, next = 0 },
		pickaxes = {
			pick_c1 = { count = 106, stars = 5, enh = 0 }, pick_c2 = { count = 31, stars = 5, enh = 0 }, pick_c3 = { count = 13, stars = 5, enh = 0 },
			pick_e1 = { count = 4, stars = 2, enh = 1 }, pick_e2 = { count = 1, stars = 2, enh = 4 }, pick_e3 = { count = 3, stars = 1, enh = 0 },
			pick_e4 = { count = 1, stars = 1, enh = 0 }, pick_m1 = { count = 1, stars = 0, enh = 5 }, pick_r1 = { count = 27, stars = 5, enh = 0 },
			pick_r2 = { count = 4, stars = 4, enh = 0 }, pick_r3 = { count = 1, stars = 4, enh = 5 }, pick_r4 = { count = 3, stars = 3, enh = 4 },
		},
		equippedPickaxe = "pick_m1", forgeOpen = true,
	},
	hour2 = {
		label = "2시간(25층 근처)",
		source = "EconomyReport V4 표준 플레이어 40명 중 그 시각 중앙값(20번째 · 120.5분 · 환생 15회 · 최고 24층)",
		strength = { m = 3.120832, e = 12 },
		blox = { m = 6.952618, e = 10 },
		lifeBlox = { m = 2.625754, e = 10 },
		lifetimeBlox = { m = 4.435113, e = 11 },
		rebirths = { m = 1.5, e = 1 },
		padIndex = 20, maxStage = 22,
		upgrades = { auraLuck = 0, bloxGain = 132, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "legend", aura = "pack3_epic",
		pets = {
			{ petId = "egg3_common", tier = 3 }, { petId = "egg2_rare", tier = 3 }, { petId = "egg3_rare", tier = 2 }, { petId = "egg3_rare", tier = 2 },
			{ petId = "egg3_common", tier = 2 }, { petId = "egg2_common", tier = 3 }, { petId = "egg2_common", tier = 3 }, { petId = "egg3_epic", tier = 1 },
			{ petId = "egg3_rare", tier = 1 }, { petId = "egg1_rare", tier = 4 }, { petId = "egg3_common", tier = 1 }, { petId = "egg3_common", tier = 1 },
			{ petId = "egg1_epic", tier = 3 }, { petId = "egg2_legendary", tier = 1 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg1_common", tier = 4 },
			{ petId = "egg1_common", tier = 4 }, { petId = "egg2_common", tier = 1 }, { petId = "egg1_legendary", tier = 1 }, { petId = "egg1_epic", tier = 1 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 1.287349, e = 5 },
		ores = { 0, 0, 0, 0, 0, 0, 0, 2, 0, 0 },
		tokens = { rare = 310, epic = 304, mythic = 4, legendary = 3, next = 0 },
		pickaxes = {
			pick_c1 = { count = 176, stars = 5, enh = 0 }, pick_c2 = { count = 91, stars = 5, enh = 0 }, pick_c3 = { count = 62, stars = 5, enh = 0 },
			pick_e1 = { count = 9, stars = 4, enh = 0 }, pick_e2 = { count = 8, stars = 4, enh = 0 }, pick_e3 = { count = 2, stars = 4, enh = 1 },
			pick_e4 = { count = 2, stars = 2, enh = 9 }, pick_m1 = { count = 2, stars = 1, enh = 6 }, pick_m2 = { count = 1, stars = 0, enh = 4 },
			pick_r1 = { count = 62, stars = 5, enh = 0 }, pick_r2 = { count = 36, stars = 5, enh = 0 }, pick_r3 = { count = 17, stars = 5, enh = 5 },
			pick_r4 = { count = 1, stars = 5, enh = 5 },
		},
		equippedPickaxe = "pick_m2", forgeOpen = true,
	},
	hour3 = {
		label = "3시간(15종 무렵)",
		source = "EconomyReport V4 표준 플레이어 19명 중 그 시각 중앙값(10번째 · 180.1분 · 환생 17회 · 최고 25층)",
		strength = { m = 8.365430, e = 14 },
		blox = { m = 1.796050, e = 12 },
		lifeBlox = { m = 1.634027, e = 12 },
		lifetimeBlox = { m = 7.585748, e = 12 },
		rebirths = { m = 1.7, e = 1 },
		padIndex = 24, maxStage = 25,
		upgrades = { auraLuck = 0, bloxGain = 141, petLuck = 0, petSlots = 1, punchSpeed = 20, titleLuck = 0 },
		title = "champion", aura = "pack3_epic",
		pets = {
			{ petId = "egg3_rare", tier = 4 }, { petId = "egg3_common", tier = 4 }, { petId = "egg3_common", tier = 4 }, { petId = "egg3_common", tier = 3 },
			{ petId = "egg3_epic", tier = 2 }, { petId = "egg3_rare", tier = 2 }, { petId = "egg2_common", tier = 3 }, { petId = "egg3_legendary", tier = 1 },
			{ petId = "egg3_epic", tier = 1 }, { petId = "egg3_epic", tier = 1 }, { petId = "egg2_rare", tier = 2 }, { petId = "egg2_legendary", tier = 1 },
			{ petId = "egg2_epic", tier = 1 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 },
			{ petId = "egg1_rare", tier = 3 }, { petId = "egg2_common", tier = 1 }, { petId = "egg2_common", tier = 1 }, { petId = "egg1_epic", tier = 2 },
		},
		equipped = { 1, 2, 3 },
		coins = { m = 8.171524, e = 4 },
		ores = { 0, 0, 0, 0, 18, 4, 17, 4, 0, 0 },
		tokens = { rare = 574, epic = 1133, mythic = 137, legendary = 26, next = 10 },
		pickaxes = {
			pick_c1 = { count = 501, stars = 5, enh = 0 }, pick_c2 = { count = 255, stars = 5, enh = 0 }, pick_c3 = { count = 155, stars = 5, enh = 0 },
			pick_e1 = { count = 93, stars = 5, enh = 0 }, pick_e2 = { count = 53, stars = 5, enh = 0 }, pick_e3 = { count = 23, stars = 5, enh = 0 },
			pick_e4 = { count = 8, stars = 4, enh = 10 }, pick_l1 = { count = 1, stars = 0, enh = 0 }, pick_m1 = { count = 2, stars = 3, enh = 0 },
			pick_m2 = { count = 1, stars = 2, enh = 0 }, pick_m3 = { count = 2, stars = 1, enh = 9 }, pick_r1 = { count = 292, stars = 5, enh = 0 },
			pick_r2 = { count = 171, stars = 5, enh = 0 }, pick_r3 = { count = 121, stars = 5, enh = 9 }, pick_r4 = { count = 43, stars = 5, enh = 7 },
		},
		equippedPickaxe = "pick_m3", forgeOpen = true,
	},
} :: { [string]: Preset }

return TestPresets

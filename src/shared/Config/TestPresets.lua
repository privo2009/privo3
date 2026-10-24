--!strict
-- Studio 전용 테스트 프리셋 (지시서 #13 3단계). **데이터만** 있다 — 켜는 규칙 · 안전장치는 Server/Data/TestPresetGate,
-- 사람용 사용법은 docs/TUNING.md "테스트 프리셋".
--
-- 사용: Bootstrap의 TEST_PRESET(기본 nil)에 아래 이름 하나를 적고 Play → 그 시점 상태의 **Mock 프로필**로 시작한다.
--       실제 개발 계정 데이터에는 읽기도 쓰기도 하지 않는다. Play를 멈추면 사라진다. 커밋할 때는 언제나 nil로 되돌린다.
--
-- ===== 값의 출처 ======================================================================
--
-- 손으로 정한 값이 아니다. SuccessRateReport 결정 모델(S5' + S7 + A4 + E11 · L1 · L3, 200명 · seed 20261021 /
-- 칭호 20261024 / 아우라 20261025 / 펫 20261026)을 돌려, 시점마다 **그 시각의 중앙값 플레이어** 한 사람의 상태를 통째로 옮겼다
-- (Server/Tools/TestPresetExport — 시점 정의 · 고르는 규칙은 그 파일 상단). 2026-10-25 지시서 #13 3단계 출력.
-- 다시 뽑기: Bootstrap의 TEST_PRESET_EXPORT_ENABLED = true로 Play → [PRESET] 줄을 이 표에 그대로 옮긴다 → 플래그를 끈다.
-- ⚠️ 게임 수치(HP · 뽑기 · 업그레이드)를 바꾸면 이 값은 옛 모델의 것이 된다. 바꾼 뒤에는 다시 뽑는다.
--
-- 칭호 자동 롤은 꺼서 시작한다. 보유 칭호 · 아우라는 장착 중인 것 하나다(시뮬레이터는 가장 높은 것만 기억한다).
-- 펫은 실효 증가분 큰 순이고 equipped는 그 배열의 번호(앞에서 슬롯 수만큼 — 게임의 "최고 장착"과 같다).

type Big = { m: number, e: number }

export type PresetPet = { petId: string, tier: number }

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
}

local TestPresets = {}

-- Bootstrap TEST_PRESET에 적는 이름(시점 순서). TestPresetExport.entries와 같은 순서다(테스트가 대조한다).
TestPresets.NAMES = { "fresh", "before_first_rebirth", "floor9", "floor17", "floor25", "floor25_cleared" }

TestPresets.Presets = {
	fresh = {
		label = "시작 직후",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 100번 · 0.0분 · 닿은 200명 · 환생 0회)",
		strength = { m = 1, e = 0 },
		blox = { m = 0, e = 0 },
		lifeBlox = { m = 0, e = 0 },
		lifetimeBlox = { m = 0, e = 0 },
		rebirths = { m = 0, e = 0 },
		padIndex = 1, maxStage = 1,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchDamage = 0, punchSpeed = 0, titleLuck = 0 },
		title = false, aura = false,
		pets = {},
		equipped = {},
	},
	before_first_rebirth = {
		label = "첫 환생 직전",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 170번 · 5.0분 · 닿은 200명 · 환생 0회)",
		strength = { m = 2.4743, e = 4 },
		blox = { m = 2.135793366, e = 3 },
		lifeBlox = { m = 2.135793366, e = 3 },
		lifetimeBlox = { m = 2.135793366, e = 3 },
		rebirths = { m = 0, e = 0 },
		padIndex = 6, maxStage = 7,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchDamage = 0, punchSpeed = 0, titleLuck = 0 },
		title = false, aura = false,
		pets = {},
		equipped = {},
	},
	floor9 = {
		label = "9층 첫 도달",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 168번 · 8.4분 · 닿은 200명 · 환생 1회)",
		strength = { m = 3.992011, e = 4 },
		blox = { m = 1.6300889793, e = 3 },
		lifeBlox = { m = 1.6300889793, e = 3 },
		lifetimeBlox = { m = 7.5599031375, e = 3 },
		rebirths = { m = 4, e = 0 },
		padIndex = 6, maxStage = 8,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchDamage = 1, punchSpeed = 1, titleLuck = 0 },
		title = false, aura = "pack1_common",
		pets = {
			{ petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_rare", tier = 1 },
			{ petId = "egg1_common", tier = 1 }, { petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2 },
	},
	floor17 = {
		label = "17층 첫 도달",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 142번 · 23.2분 · 닿은 200명 · 환생 2회)",
		strength = { m = 1.874983677, e = 9 },
		blox = { m = 2.0539956061, e = 6 },
		lifeBlox = { m = 2.0563756061, e = 6 },
		lifetimeBlox = { m = 2.35180598039, e = 6 },
		rebirths = { m = 2.22, e = 2 },
		padIndex = 12, maxStage = 15,
		upgrades = { auraLuck = 0, bloxGain = 2, petLuck = 0, petSlots = 1, punchDamage = 2, punchSpeed = 2, titleLuck = 0 },
		title = "champion", aura = "pack1_epic",
		pets = {
			{ petId = "egg1_common", tier = 2 }, { petId = "egg1_rare", tier = 1 }, { petId = "egg1_common", tier = 1 },
			{ petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2, 3 },
	},
	floor25 = {
		label = "25층 첫 도달",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 41번 · 38.7분 · 닿은 200명 · 환생 3회)",
		strength = { m = 2.36396428874, e = 15 },
		blox = { m = 2.59061179127, e = 10 },
		lifeBlox = { m = 2.59061228927, e = 10 },
		lifetimeBlox = { m = 2.62120486949, e = 10 },
		rebirths = { m = 2.45801, e = 5 },
		padIndex = 20, maxStage = 24,
		upgrades = { auraLuck = 0, bloxGain = 4, petLuck = 0, petSlots = 1, punchDamage = 5, punchSpeed = 4, titleLuck = 0 },
		title = "champion", aura = "pack2_epic",
		pets = {
			{ petId = "egg2_common", tier = 1 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_common", tier = 2 },
		},
		equipped = { 1, 2, 3 },
	},
	floor25_cleared = {
		label = "25층 클리어 직후",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 79번 · 40.2분 · 닿은 200명 · 환생 4회)",
		strength = { m = 2.02650402985, e = 16 },
		blox = { m = 3.96994563609, e = 10 },
		lifeBlox = { m = 3.96994567109, e = 10 },
		lifetimeBlox = { m = 9.14458375803, e = 10 },
		rebirths = { m = 3.5531428, e = 7 },
		padIndex = 21, maxStage = 25,
		upgrades = { auraLuck = 0, bloxGain = 5, petLuck = 0, petSlots = 1, punchDamage = 5, punchSpeed = 4, titleLuck = 0 },
		title = "legend", aura = "pack3_epic",
		pets = {
			{ petId = "egg3_common", tier = 4 }, { petId = "egg3_rare", tier = 3 }, { petId = "egg3_common", tier = 3 },
			{ petId = "egg2_common", tier = 4 }, { petId = "egg3_epic", tier = 2 }, { petId = "egg3_epic", tier = 2 },
			{ petId = "egg2_rare", tier = 3 }, { petId = "egg3_rare", tier = 2 }, { petId = "egg3_rare", tier = 2 },
			{ petId = "egg2_common", tier = 3 }, { petId = "egg2_epic", tier = 2 }, { petId = "egg3_epic", tier = 1 },
			{ petId = "egg3_epic", tier = 1 }, { petId = "egg2_rare", tier = 2 }, { petId = "egg3_rare", tier = 1 },
			{ petId = "egg3_rare", tier = 1 }, { petId = "egg3_common", tier = 1 }, { petId = "egg2_common", tier = 2 },
			{ petId = "egg2_epic", tier = 1 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg2_rare", tier = 1 },
			{ petId = "egg2_rare", tier = 1 }, { petId = "egg2_common", tier = 1 }, { petId = "egg1_rare", tier = 1 },
			{ petId = "egg1_common", tier = 1 }, { petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2, 3 },
	},
} :: { [string]: Preset }

return TestPresets

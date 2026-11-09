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
-- (Server/Tools/TestPresetExport — 시점 정의 · 고르는 규칙은 그 파일 상단). 2026-10-25 지시서 #13 3단계 출력 →
-- 2026-11-09 지시서 #24 다시 뽑음(1번 패드 클릭 파워 1 — P1).
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
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 10번 · 5.2분 · 닿은 200명 · 환생 0회)",
		strength = { m = 3.1117, e = 4 },
		blox = { m = 2.342416536, e = 3 },
		lifeBlox = { m = 2.342416536, e = 3 },
		lifetimeBlox = { m = 2.342416536, e = 3 },
		rebirths = { m = 0, e = 0 },
		padIndex = 6, maxStage = 7,
		upgrades = { auraLuck = 0, bloxGain = 0, petLuck = 0, petSlots = 0, punchDamage = 0, punchSpeed = 0, titleLuck = 0 },
		title = false, aura = false,
		pets = {},
		equipped = {},
	},
	floor9 = {
		label = "9층 첫 도달",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 90번 · 8.9분 · 닿은 200명 · 환생 1회)",
		strength = { m = 8.376376, e = 4 },
		blox = { m = 2.87402756256, e = 3 },
		lifeBlox = { m = 2.87402756256, e = 3 },
		lifetimeBlox = { m = 5.05057202856, e = 3 },
		rebirths = { m = 1, e = 0 },
		padIndex = 6, maxStage = 8,
		upgrades = { auraLuck = 0, bloxGain = 2, petLuck = 0, petSlots = 0, punchDamage = 3, punchSpeed = 2, titleLuck = 0 },
		title = false, aura = false,
		pets = {
			{ petId = "egg1_rare", tier = 2 },
		},
		equipped = { 1 },
	},
	floor17 = {
		label = "17층 첫 도달",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 103번 · 23.6분 · 닿은 200명 · 환생 3회)",
		strength = { m = 6.74025367216, e = 8 },
		blox = { m = 1.60504176652, e = 6 },
		lifeBlox = { m = 1.60528176652, e = 6 },
		lifetimeBlox = { m = 7.39029084398, e = 6 },
		rebirths = { m = 4.153, e = 3 },
		padIndex = 12, maxStage = 15,
		upgrades = { auraLuck = 0, bloxGain = 4, petLuck = 0, petSlots = 1, punchDamage = 4, punchSpeed = 3, titleLuck = 0 },
		title = "champion", aura = "pack2_rare",
		pets = {
			{ petId = "egg2_common", tier = 2 }, { petId = "egg2_epic", tier = 1 }, { petId = "egg2_rare", tier = 1 },
			{ petId = "egg1_common", tier = 4 }, { petId = "egg1_rare", tier = 3 }, { petId = "egg1_rare", tier = 3 },
			{ petId = "egg2_common", tier = 1 }, { petId = "egg1_epic", tier = 2 }, { petId = "egg1_epic", tier = 1 },
			{ petId = "egg1_epic", tier = 1 }, { petId = "egg1_common", tier = 2 }, { petId = "egg1_common", tier = 2 },
		},
		equipped = { 1, 2, 3 },
	},
	floor25 = {
		label = "25층 첫 도달",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 164번 · 38.5분 · 닿은 200명 · 환생 6회)",
		strength = { m = 2.85726490821, e = 15 },
		blox = { m = 1.35519292392, e = 10 },
		lifeBlox = { m = 1.35519295692, e = 10 },
		lifetimeBlox = { m = 3.81743422408, e = 10 },
		rebirths = { m = 1.7589282, e = 7 },
		padIndex = 20, maxStage = 24,
		upgrades = { auraLuck = 0, bloxGain = 7, petLuck = 0, petSlots = 1, punchDamage = 7, punchSpeed = 6, titleLuck = 0 },
		title = "champion", aura = "pack3_rare",
		pets = {
			{ petId = "egg3_common", tier = 3 }, { petId = "egg3_common", tier = 3 }, { petId = "egg3_rare", tier = 2 },
			{ petId = "egg3_common", tier = 2 }, { petId = "egg3_common", tier = 2 }, { petId = "egg3_epic", tier = 1 },
			{ petId = "egg3_epic", tier = 1 }, { petId = "egg3_rare", tier = 1 }, { petId = "egg2_common", tier = 1 },
			{ petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 }, { petId = "egg1_epic", tier = 1 },
			{ petId = "egg1_rare", tier = 1 }, { petId = "egg1_common", tier = 1 }, { petId = "egg1_common", tier = 1 },
		},
		equipped = { 1, 2, 3 },
	},
	floor25_cleared = {
		label = "25층 클리어 직후",
		source = "결정 모델 200명 중 그 시각 중앙값(플레이어 150번 · 40.3분 · 닿은 200명 · 환생 4회)",
		strength = { m = 7.08553059812, e = 15 },
		blox = { m = 6.66889471662, e = 10 },
		lifeBlox = { m = 6.66889515362, e = 10 },
		lifetimeBlox = { m = 6.70972717805, e = 10 },
		rebirths = { m = 3.27117, e = 5 },
		padIndex = 21, maxStage = 25,
		upgrades = { auraLuck = 0, bloxGain = 3, petLuck = 0, petSlots = 1, punchDamage = 4, punchSpeed = 3, titleLuck = 0 },
		title = "champion", aura = "pack2_epic",
		pets = {
			{ petId = "egg1_epic", tier = 2 }, { petId = "egg1_common", tier = 3 }, { petId = "egg1_rare", tier = 2 },
			{ petId = "egg1_rare", tier = 2 }, { petId = "egg1_rare", tier = 1 },
		},
		equipped = { 1, 2, 3 },
	},
} :: { [string]: Preset }

return TestPresets

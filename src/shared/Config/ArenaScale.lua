--!strict
-- 아레나 · 로비 크기 배율 하나(지시서 #46 — 2026-11-27 희준 결정 "블록과 맵 크기를 모두 줄인다").
--
-- 왜: 걷기 · 로비를 세는 정직한 시뮬(#45)에서 2시간 시점의 걷기(진행 벽 · 수령 발판까지 3222초)가 공격(2208초)보다 길었다.
-- 걷는 거리는 블록 · 스테이지 · 로비 크기에서 나온다 — 그 크기를 숫자 하나로 줄인다. 이동 속도(LevelConfig)는 그대로다.
--
-- 이 파일은 배율과 배율 계산 도우미만 가진다(다른 모듈을 require하지 않는다 — 모두가 이것을 읽는다).
-- 배율로 무엇이 얼마가 되는지는 ArenaConfig.layoutAt(배율)이 한 곳에서 계산한다(블록 크기는 BlockLayoutConfig가 이 값을 곱한다).
--
-- ===== 배율을 따르는 것 / 따르지 않는 것 =========================================================================
--
--   따른다(× 배율)   큐브 · 블록 크기 → 블록 배치 반지름 · 판정 반경(AttackConfig — 블록에서 파생) · 스테이지 폭의 블록 몫 ·
--                    챌린지 통로 폭 · 스폰 → 게이트 거리 · 로비 줄 · 간격 · 여백 · 대장간 자리 · 드롭 흩어짐 · 줍기 반경
--   안 따른다        캐릭터에 묶인 것 — 수령 발판(12 × 12)과 옆으로 비킨 거리(20 — 캐릭터 폭) · 클릭 패드(8) · 운동기구 발판(16) ·
--                    대장간 건물 · 스폰 발판 · 3D 안내판 높이 · 경계 높이(점프)
--                    Touched 관통 하한에 묶인 것 — 진행 벽 · 게이트 깊이(8) · 발판 깊이 → 띠 폭(24)과 이동 속도 상한(LevelConfig 80)
--                    엔진 상한(MAX_PART_SIZE) · 바닥 두께
--   그래서 스테이지 폭은 배율에 정비례하지 않는다(블록 몫만 줄고 벽 깊이 몫은 그대로) — 식은 ArenaConfig.layoutAt.
--   로비 물체는 크기를 그대로 두고 간격만 줄인다 — 간격은 (기준 × 배율)과 (크기 + 틈) 중 큰 쪽(pitch).
--
-- ⚠️ 배율을 바꾸면 다시 할 것(docs/TUNING.md "배율 바꾸는 법"): 시뮬 측정(EconomyReport — 걷는 거리가 바뀐다) · 목표 시간 손잡이 ·
--    테스트 프리셋 다시 뽑기(PresetExport) · 자동 플레이 봇 4구간 · 스크린샷(블록이 캐릭터보다 충분히 큰가)

local ArenaScale = {}

-- 배율(1.0 = #45까지의 배치). TEMP — 지시서 #46 2부 후보 측정(docs/TUNING.md 16절)으로 0.5:
--   후보 0.4 · 0.5 · 0.6 · 0.7의 2시간 시점 걷기 ÷ 공격 = 0.70 · 0.77 · 1.01 · 1.12(옛 1.0 = 1.47) — "절반 이하"는 어느 후보도 못 닿는다
--   (띠 24는 Touched 깊이에 묶여 안 줄고 · 스테이지 폭은 블록 16개 이중 원 기준). 블록이 캐릭터의 1.5배 이상(0.4는 6.4 studs라 밖)이면서
--   걷기가 가장 짧은 것이 0.5(블록 8 studs). 발판 · 벽은 판정 반경 밖(0.53까지 띠 24 그대로)
ArenaScale.ARENA_SCALE = 0.5

-- 로비 물체 사이 최소 틈(studs — 배율을 안 따른다). 패드 · 기구는 높이 1인 발판이라 밟고 지나갈 수 있다 — 틈은 "서로 다른 칸"으로
-- 보이게 하는 몫이다. 패드는 좁게(2 — 24개가 두 줄), 기구는 캐릭터 폭(4) 만큼
ArenaScale.PAD_MIN_GAP = 2
ArenaScale.GYM_MIN_GAP = 4

-- 길이를 이 격자로 맞춘다(studs). 배율을 곱한 소수(0.7 × 3.8 × 16 …)가 쌓여 1.0에서 147.99999…가 되지 않게 —
-- 같은 식이 언제나 같은 수를 내야 서버 판정 · 클라 표시 · 테스트가 한 값을 나눠 쓴다
ArenaScale.SNAP = 1e-3

-- 캐릭터(로블록스 기본 아바타) 키(studs — 배율을 안 따른다). 블록이 캐릭터보다 충분히 커 보이는지 재는 기준(ArenaScaleTests)
ArenaScale.CHARACTER_HEIGHT = 5
-- 블록 한 변 ≥ 캐릭터 키 × 이 값(지시서 #46 2부 고르는 기준 "블록이 캐릭터보다 충분히 커 보임" — Claude 판단 1.5배)
ArenaScale.MIN_BLOCK_TO_CHARACTER = 1.5

-- 2부 후보(지시서 #46)
ArenaScale.CANDIDATES = { 0.4, 0.5, 0.6, 0.7 }

function ArenaScale.snap(x: number): number
	return math.round(x / ArenaScale.SNAP) * ArenaScale.SNAP
end

-- 기준 길이 × 배율(격자에 맞춤)
function ArenaScale.scaled(base: number, scale: number): number
	return ArenaScale.snap(base * scale)
end

-- 로비 간격: 기준 간격 × 배율, 다만 물체 크기 + 틈보다 작아지지 않는다(물체는 캐릭터 크기라 안 줄어든다)
function ArenaScale.pitch(base: number, size: number, gap: number, scale: number): number
	return ArenaScale.snap(math.max(base * scale, size + gap))
end

function ArenaScale.validate(): boolean
	local s = ArenaScale.ARENA_SCALE
	assert(type(s) == "number" and s == s and s > 0 and s <= 1,
		string.format("ArenaScale: ARENA_SCALE(%s)는 0 초과 1 이하(줄이기만 한다 — 키우려면 띠 · 발판 규칙을 다시 본다)", tostring(s)))
	assert(ArenaScale.PAD_MIN_GAP > 0 and ArenaScale.GYM_MIN_GAP > 0, "ArenaScale: 로비 최소 틈은 0보다 커야 함")
	return true
end

return ArenaScale

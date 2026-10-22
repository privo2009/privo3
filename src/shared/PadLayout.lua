--!strict
-- 클릭 파워 패드 배치 좌표 계산 (순수). BlockLayout과 같은 성격이다 — 좌표만 만들고
-- Instance는 만들지 않는다. 파트 생성은 Server/Systems/PadService가 한다.
--
-- ===== 어디에 서는가 (지시서 #8 M1 — 2026-10-23 사람 결정) ================================
--
--   -Z 옆   패드 24개, 2줄 × 12열          ← 여기
--   Z = 0   스폰 ──── 가운데 통로 ──── 입장 게이트     (통로에는 아무것도 없다)
--   +Z 옆   운동기구 9개 (GymLayout)
--
-- 패드는 통로 한쪽 옆에 2줄로 선다. 예전에는 스폰과 게이트 사이 통로 위에 한 줄로 있어서 지나가다 낮은 패드를
-- 밟으면 클릭 파워가 그 패드로 내려갔다(세팅이지 누적이 아니다 — PadService). 통로에서 빼면 그 사고가 없어진다.
--
-- ===== 순서 = 강함 =====================================================================
--
-- 패드 인덱스가 곧 강함이다(ClickPadConfig.getPadPower). 공간 순서가 인덱스 순서와 일치해야
-- "게이트 쪽으로 갈수록 강해진다"가 설명 없이 읽힌다.
--
--   열 c(= ceil(i / 2))가 게이트 쪽으로 갈수록 커진다. 한 열 안에서는 통로 쪽(안쪽 줄)이 앞 번호다.
--   즉 1 · 2가 스폰 쪽 첫 열, 23 · 24가 게이트 쪽 마지막 열.
--
-- ⚠️ 배치 순서를 섞지 말 것. 좌표 i번은 반드시 패드 i번이다.
--
-- ===== 배치 상수는 초안값이다 ==========================================================
--
-- 지환 · 희준 파트가 들어오면 PAD_SIZE · 간격은 조정 대상이다. 축 · 스폰은 ArenaConfig가 원본이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)

local PadLayout = {}

-- 패드 한 장의 크기 (studs). 캐릭터가 밟고 지나갈 수 있는 폭 기준 초안.
PadLayout.PAD_SIZE = Vector3.new(8, 1, 8)

-- 진행 축. 정본은 `ArenaConfig.AXIS`다 — 재공개일 뿐 두 번째 원본이 아니다
-- (호출부 LevelConfig.depthAlong · PadServiceTests가 PadLayout.AXIS를 읽는다).
PadLayout.AXIS = ArenaConfig.AXIS

-- 열 간격 (진행축, studs). PAD_SIZE.X(8)의 1.5배 — 패드 사이로 걸어 다닐 틈.
PadLayout.PITCH = 12

-- 줄 수와 줄 간격 (Z, studs). 줄 간격 = PAD_SIZE.Z + 4 — 두 줄이 붙지 않게.
PadLayout.ROWS = 2
PadLayout.ROW_PITCH = 12

-- 안쪽 줄(통로에 가까운 줄)의 Z. 통로(Z = 0)에서 패드 가장자리까지 32 studs — 통로 한가운데로 걸으면
-- 캐릭터 폭(약 4)과 고속 이동 보정을 넉넉히 넘는다(CASHOUT_LATERAL_OFFSET의 여유 근거와 같은 종류).
-- 바깥쪽 줄은 -Z로 ROW_PITCH만큼 더 간다.
PadLayout.LANE_Z = -36

-- 첫 열이 스폰 지점보다 뒤(-X)로 들어간 거리. 스폰 바로 옆에서 시작해 게이트 쪽으로 뻗는다.
-- 12열이면 마지막 열이 -220 + 11 × 12 = -88 — 입장 게이트(-74) 앞에서 끝난다(테스트가 잰다).
PadLayout.START_BEHIND_SPAWN = 20

-- 패드 아랫면이 지면(Y=0)에 닿도록 중심을 반 칸 띄운다.
-- BlockLayout.GROUND_Y_OFFSET과 같은 계산이고 같은 이유다 (그대로 두면 절반이 바닥에 묻힌다).
PadLayout.GROUND_Y_OFFSET = PadLayout.PAD_SIZE.Y / 2

-- 패드 1의 중심 좌표(첫 열 · 안쪽 줄).
PadLayout.ORIGIN = Vector3.new(ArenaConfig.SPAWN_X - PadLayout.START_BEHIND_SPAWN, PadLayout.GROUND_Y_OFFSET, PadLayout.LANE_Z)

-- 패드 i번의 열(1부터)과 줄(0 = 안쪽, 1 = 바깥쪽).
function PadLayout.cellOf(index: number): (number, number)
	local column = math.ceil(index / PadLayout.ROWS)
	local row = (index - 1) % PadLayout.ROWS
	return column, row
end

-- 패드 1..count의 중심 좌표를 순서대로 반환한다.
-- 블록 좌표와 마찬가지로 플레이어와 무관한 절대 좌표다 — player 인자를 붙이지 말 것.
-- (패드는 파트가 Workspace에 하나만 서고 전원이 같은 것을 밟는다)
function PadLayout.computeLayout(count: number): { Vector3 }
	assert(
		type(count) == "number" and count >= 1 and count % 1 == 0,
		"PadLayout.computeLayout: count는 1 이상의 정수여야 함"
	)

	local positions = {}
	for i = 1, count do
		local column, row = PadLayout.cellOf(i)
		positions[i] = PadLayout.ORIGIN
			+ PadLayout.AXIS * (PadLayout.PITCH * (column - 1))
			+ Vector3.new(0, 0, -PadLayout.ROW_PITCH * row)
	end
	return positions
end

return PadLayout

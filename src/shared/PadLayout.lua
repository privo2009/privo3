--!strict
-- 클릭 파워 패드 배치 좌표 계산 (순수). BlockLayout과 같은 성격이다 — 좌표만 만들고
-- Instance는 만들지 않는다. 파트 생성은 Server/Systems/PadService가 한다.
--
-- ===== 왜 일렬인가 =====================================================================
--
-- 패드 인덱스가 곧 강함이다(ClickPadConfig.getPadPower). 그러므로 공간 순서가 인덱스 순서와
-- 일치해야 "앞으로 갈수록 강해진다"가 설명 없이 읽힌다. 원형으로 두면 강함이 방향으로
-- 드러나지 않아서, 어디까지 해금했는지도 어느 쪽이 다음 목표인지도 눈으로 알 수 없다.
--
-- ⚠️ 그래서 배치 순서를 섞지 말 것. 좌표 i번은 반드시 패드 i번이다.
--
-- ===== 배치 상수는 초안값이다 ==========================================================
--
-- 아직 맵이 없다. 아래 값들은 "블록 아레나와 안 겹치는 빈 축 하나"를 잡은 것일 뿐,
-- 지형을 보고 정한 값이 아니다. 맵과 지환 파트가 들어오면 ORIGIN/AXIS/PITCH/PAD_SIZE는
-- 전부 조정 대상이다. 특히:
--   - AXIS: 스폰 지점에서 아레나로 걸어가는 동선 위에 놓여야 의미가 있다
--   - PITCH: 실제 파트 크기가 정해지면 그 크기 기준으로 다시 잡아야 한다
--   - PAD_SIZE: 지환 파트의 실제 바운딩 박스로 교체한다

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)

local PadLayout = {}

-- 패드 한 장의 크기 (studs). 캐릭터가 밟고 지나갈 수 있는 폭 기준 초안.
PadLayout.PAD_SIZE = Vector3.new(8, 1, 8)

-- 패드가 뻗어나가는 방향. 원점에서 멀어질수록 강한 패드다.
-- ⚠️ 반드시 단위 벡터여야 한다 — PITCH를 그대로 곱하므로 길이가 1이 아니면 간격이 틀어진다.
PadLayout.AXIS = Vector3.new(0, 0, -1)

-- 패드 중심 간 거리 (studs). PAD_SIZE에서 축 방향 성분보다 커야 패드끼리 안 붙는다.
-- 현재 축이 Z이므로 기준은 PAD_SIZE.Z(=8)이고, 12는 그 1.5배다.
PadLayout.PITCH = 12

-- 패드 윗면이 지면(Y=0)에 오도록 중심을 반 칸 띄운다.
-- BlockLayout.GROUND_Y_OFFSET과 같은 계산이고 같은 이유다 (그대로 두면 절반이 바닥에 묻힌다).
PadLayout.GROUND_Y_OFFSET = PadLayout.PAD_SIZE.Y / 2

-- 블록 아레나가 차지하는 반지름 = 가장 바깥 링 + 블록 반 칸.
-- BlockLayoutConfig에서 유도한다 — 여기에 studs 절대값을 직접 쓰면 아레나 반지름을 튜닝했을 때
-- 패드가 블록 안으로 파고들어도 아무도 모른다 (CLAUDE.md: 수치는 Config 한 곳에서).
local ARENA_RADIUS = BlockLayoutConfig.BLOCK_SPAN * BlockLayoutConfig.OUTER_RING_MULT
	+ BlockLayoutConfig.BLOCK_SPAN / 2

-- 아레나 가장자리와 패드 1 사이 여유. 블록 한 변만큼 띄운다.
local START_GAP = BlockLayoutConfig.BLOCK_SPAN

-- 패드 1의 중심 좌표. 아레나 밖에서 시작해 AXIS 방향으로 나아간다.
PadLayout.ORIGIN = PadLayout.AXIS * (ARENA_RADIUS + START_GAP + PadLayout.PAD_SIZE.Z / 2)
	+ Vector3.new(0, PadLayout.GROUND_Y_OFFSET, 0)

-- 패드 1..count의 중심 좌표를 순서대로 반환한다.
-- 블록 좌표와 마찬가지로 플레이어와 무관한 절대 좌표다 — player 인자를 붙이지 말 것.
-- (패드는 파트가 Workspace에 하나만 서고 전원이 같은 것을 밟는다. 블록과 달리 클라마다
--  따로 만드는 물건이 아니므로 개인 오프셋 자체가 성립하지 않는다)
function PadLayout.computeLayout(count: number): { Vector3 }
	assert(
		type(count) == "number" and count >= 1 and count % 1 == 0,
		"PadLayout.computeLayout: count는 1 이상의 정수여야 함"
	)

	local positions = {}
	for i = 1, count do
		positions[i] = PadLayout.ORIGIN + PadLayout.AXIS * (PadLayout.PITCH * (i - 1))
	end
	return positions
end

return PadLayout

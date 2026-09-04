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
-- ===== 4-2-a: 패드는 스폰 구역에 있다 (원점 이동) ======================================
--
-- ⚠️ 예전 구조와 다르다. 패드는 블록 클러스터 주위를 도는 물건이 아니라 **스폰 구역**에
-- 있고, 챌린지 구간에는 패드가 하나도 없다. 아레나 공간 구조는
-- docs/UI_HANDOFF.md "3D 파트 배치 — 아레나 좌표"가 원본이다.
--
--   스폰 구역                          챌린지 구간 →
--   [ 패드 24개 · 펫뽑기 ]  →  [ St.1 블록 ] [ 띠 ] [ St.2 블록 ] [ 띠 ] ...
--   X -400 ~ -104              X -80 부터
--
-- 그래서 좌표의 기준점이 블록 클러스터 중심에서 **스폰 지점**으로 옮겨졌다. 아래
-- SPAWN_X가 그 기준점이고, 패드는 거기서 진행 방향으로 나아간다.
--
-- ⚠️ 이 이동으로 "패드를 밟으러 갈 것인가, 블록 곁을 지킬 것인가"라는 선택 자체가
-- 사라졌다. 챌린지 중에는 패드에 갈 수 없다. 그 서술에 기대던 문서·주석은 전부
-- 틀린 것이 됐다 (AttackConfig 상단 실측표 포함 — 4-2-a 커밋 4에서 정리한다).
--
-- ===== 배치 상수는 초안값이다 ==========================================================
--
-- 아직 맵이 없다. 맵과 지환 파트가 들어오면 PITCH/PAD_SIZE는 조정 대상이다:
--   - PITCH: 실제 파트 크기가 정해지면 그 크기 기준으로 다시 잡아야 한다
--   - PAD_SIZE: 지환 파트의 실제 바운딩 박스로 교체한다
-- AXIS와 SPAWN_X는 이제 초안이 아니다 — 아레나 구조가 확정한 값이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)

local PadLayout = {}

-- 패드 한 장의 크기 (studs). 캐릭터가 밟고 지나갈 수 있는 폭 기준 초안.
PadLayout.PAD_SIZE = Vector3.new(8, 1, 8)

-- 패드가 뻗어나가는 방향. 스폰 지점에서 멀어질수록 강한 패드이고, 같은 방향으로 더
-- 가면 챌린지 입구가 나온다 — 즉 "패드를 다 밟고 나온 자리가 곧 챌린지 앞"이다.
--
-- ⚠️ 진행 축은 +X다(아레나 전체가 그렇다). 예전에는 -Z였다 — 블록 클러스터를 피해
-- 빈 축 하나를 잡은 것뿐이었고 동선과 무관했다.
--
-- ⚠️ 정본은 `ArenaConfig.AXIS`다. 여기서 다시 적지 않는다 — 패드와 스테이지가 같은
-- 축을 써야 "패드를 다 밟고 나온 자리가 곧 챌린지 앞"이 성립하는데, 양쪽에 따로
-- 적으면 축을 틀었을 때 한쪽만 따라온다. 단위 벡터 보장도 ArenaConfig.validate가 한다.
-- 이 필드를 남겨두는 이유는 호출부(LevelConfig.depthAlong, PadServiceTests)가
-- 이미 PadLayout.AXIS를 읽고 있어서다 — 재공개일 뿐 두 번째 원본이 아니다.
PadLayout.AXIS = ArenaConfig.AXIS

-- 패드 중심 간 거리 (studs). PAD_SIZE에서 축 방향 성분보다 커야 패드끼리 안 붙는다.
-- 현재 축이 X이므로 기준은 PAD_SIZE.X(=8)이고, 12는 그 1.5배다.
PadLayout.PITCH = 12

-- 패드 아랫면이 지면(Y=0)에 닿도록 중심을 반 칸 띄운다 — 중심 y=0.5, 윗면 y=1이 되어
-- 패드가 지면 위에 얹힌다(밟고 지나가는 물건이므로 이게 맞는 동작이다).
-- BlockLayout.GROUND_Y_OFFSET과 같은 계산이고 같은 이유다 (그대로 두면 절반이 바닥에 묻힌다).
PadLayout.GROUND_Y_OFFSET = PadLayout.PAD_SIZE.Y / 2

-- ===== 패드 1의 기준점 ================================================================
--
-- ⚠️ 여기가 원점 이동의 핵심이다. 예전에는 이 자리에 블록 아레나 반지름
-- (`BlockLayout.OUTER_RADIUS + BLOCK_SPAN/2` = 68.8)이 있었고, "블록 바깥면에서
-- 얼마나 떨어져 시작하는가"가 패드 1의 위치를 정했다. 패드가 블록 클러스터를
-- 둘러싸고 있었으니 그게 맞는 기준이었다.
--
-- 이제 패드는 블록 근처에 없다. 스폰 구역에 있고, 챌린지 구간과는 320 studs
-- 떨어져 있다 — 블록 아레나 반지름은 패드 위치와 **아무 관계가 없다.** 그래서
-- 그 항을 스폰 지점으로 갈아끼웠다. 남겨두면 블록 크기를 튜닝했을 때 스폰 구역의
-- 패드가 따라 움직이는, 근거 없는 연동이 생긴다.
--
-- ⚠️ `BlockLayout` require도 함께 걷어냈다. 이 파일이 블록 기하를 읽을 이유가
-- 이제 없다. 되살리기 전에 "패드가 블록과 무슨 상관인가"를 먼저 답할 것.
--
-- 스폰 지점의 정본은 `ArenaConfig.SPAWN_X`다. 스폰은 패드만 쓰는 값이 아니라
-- 경계·복귀 경로도 쓰는 값이라 이 파일이 가질 자리가 아니다.
local SPAWN_X = ArenaConfig.SPAWN_X

-- 스폰 지점과 패드 1 사이 여유. 블록 한 변만큼 띄운다 — 스폰하자마자 발밑이
-- 패드이면 첫 접촉이 사고가 된다.
local START_GAP = BlockLayoutConfig.BLOCK_SPAN

-- PAD_SIZE에서 축 방향 변의 절반. `.Z/2`로 박아두면 축을 X로 튼 지금 엉뚱한 변을
-- 쓴다 (LevelConfig.depthAlong이 같은 이유로 축 투영을 쓴다 — 그쪽을 require하면
-- 순환이라 식만 같게 둔다).
local function halfSpanAlongAxis(): number
	local axis = PadLayout.AXIS
	local size = PadLayout.PAD_SIZE
	return (math.abs(axis.X) * size.X + math.abs(axis.Y) * size.Y + math.abs(axis.Z) * size.Z) / 2
end

-- 패드 1의 중심 좌표. 스폰 지점에서 시작해 AXIS 방향(챌린지 쪽)으로 나아간다.
-- 확정 구조 기준: X = -400 + 16 + 4 = -380, 패드 24는 -380 + 12×23 = -104.
PadLayout.ORIGIN = PadLayout.AXIS * (SPAWN_X + START_GAP + halfSpanAlongAxis())
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

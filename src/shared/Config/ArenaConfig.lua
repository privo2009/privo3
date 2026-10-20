--!strict
-- 아레나 월드 좌표. 스폰 구역 · 스테이지 구간 · 그 사이 띠가 어디에 놓이는가.
--
-- 공간 구조의 원본은 docs/UI_HANDOFF.md "3D 파트 배치 — 아레나 좌표"다.
-- ⚠️ 근거를 여기로 복사하지 말 것. 이 파일은 "얼마인가"만 답한다.
--
--   스폰 구역                          챌린지 구간 →
--   [ 패드 24개 · 펫뽑기 ]  →  [ St.1 블록 ] [ 띠 ] [ St.2 블록 ] [ 띠 ] ...
--   X -400 ~ -104              X -80 부터
--
-- 이 모듈은 순수하다. Player·프로필·Instance를 보지 않고 Service를 require하지 않는다.
-- 좌표만 만들고 파트는 만들지 않는다 — BlockLayout/PadLayout과 같은 성격이다.
--
-- ===== 주기 200을 여러 곳에 박지 말 것 (이 파일이 있는 이유) ===========================
--
-- 스테이지 25개면 마지막 블록 중심이 X = 4800이고, 발판·벽까지 세면 좌표를 가진
-- 파트가 75개다. 주기를 파트 배치 코드에 적으면 나중에 폭을 조정할 때 그 75개가
-- 전부 어긋나고, 어긋난 것이 "걸어가다 벽에 막힌다" 같은 증상으로만 나타난다.
--
-- ⚠️ 그래서 파트를 놓는 쪽은 200·100·120을 절대 쓰지 않는다. getStageCenterX /
-- getCashoutX / getAdvanceX를 부른다. 아래 파생 함수들이 유일한 계산처다.
--
-- ⚠️ 파생은 함수다. 상수로 미리 계산해두면 STAGE_WIDTH를 흔들었을 때(테스트가 실제로
-- 그렇게 한다) 따라오지 않아서, 유도가 끊겨도 통과한다.
-- (AttackConfig.getRadius가 상수 대신 함수인 것과 같은 이유)

local ArenaConfig = {}

-- ===== 진행 축 =======================================================================
--
-- 아레나 전체가 +X로 진행한다. 스폰에서 패드를 지나 챌린지 입구까지, 그리고 스테이지
-- 1 → 25까지 전부 같은 방향이다 — 유저가 한 번도 돌아설 필요가 없다는 뜻이다.
--
-- ⚠️ 여기가 축의 정본이다. PadLayout.AXIS가 이 값을 읽는다. 양쪽에 따로 적으면
-- 축을 틀었을 때 패드만 남거나 스테이지만 남는다.
-- ⚠️ 반드시 단위 축 벡터여야 한다 (LevelConfig.depthAlong이 축 투영을 전제한다).
ArenaConfig.AXIS = Vector3.new(1, 0, 0)

-- ===== 1차 상수 (여기 적힌 둘만 원본이다) ==============================================

-- 스테이지 한 칸의 폭. 블록 중심에서 양옆으로 절반씩이다.
-- ⚠️ 근접 판정 반경(AttackConfig.getRadius, 92.8)이 이 폭의 절반(80)보다 크다.
-- 스테이지 안에 서 있는 한 공격이 끊기지 않는다는 뜻이고, 그게 의도다.
-- 그쪽은 이 값을 참조하지 않는다 — 근거가 다르고 서로 끌려다니면 안 된다.
ArenaConfig.STAGE_WIDTH = 160

-- 스테이지와 스테이지 사이 띠. 수령 발판과 진행 벽이 이 띠 안에 있다.
ArenaConfig.GAP_WIDTH = 40

-- 스폰 지점의 X. 패드도 아레나 경계도 복귀 경로도 이 값에서 시작한다.
--
-- ⚠️ 4-2-a 이전에는 PadLayout이 이 역할을 겸했다(블록 아레나 반지름에서 패드
-- 시작점을 유도). 패드가 스폰 구역으로 오면서 스폰 지점이 패드만의 값이 아니게
-- 됐고, 그래서 여기가 정본이 됐다.
ArenaConfig.SPAWN_X = -400

-- 수령 발판이 진행축에서 옆으로 비키는 거리.
--
-- ⚠️ **유도값이 아니다.** STAGE_WIDTH나 GAP_WIDTH에서 파생시키지 말 것 — 근거가
-- 다른 축에 있다. 아레나 폭을 조정해도 이 값은 따라 움직이면 안 된다.
--
-- 근거는 캐릭터 폭이다:
--   로블록스 기본 캐릭터 폭 약 4 (HumanoidRootPart 2, 팔 포함 4).
--   축 중앙 통로 ±14, 캐릭터 반폭 2, 여유 12.
--   (발판 크기 12×1×12이므로 안쪽 모서리가 축에서 20 - 6 = 14)
--
-- 여유 12는 고속 이동 보정이다. 후반 이동속도가 수천까지 올라가 프레임당 수십
-- studs를 움직이고, 직선으로 걸어도 물리 보정으로 옆으로 밀린다. 여유가 좁으면
-- 지나가다 발판에 스쳐 런이 끝난다 — 수령은 런당 1회고 되돌릴 수 없다.
-- 반대로 멀면 클리어 후 가는 것이 부담이 된다.
ArenaConfig.CASHOUT_LATERAL_OFFSET = 20

-- 수령 발판 크기.
--
-- ⚠️ **여기 있는 이유가 있다.** 파트 크기는 원래 파트를 세우는 Service의 몫인데,
-- 이 값만은 shared여야 한다 — LevelConfig가 진행 방향 깊이를 읽어 이동속도 상한을
-- 유도하기 때문이다(docs/UI_ASSET_SPEC.md "5-1"). Service(서버 전용)에 두면 Config가
-- 서버 모듈을 require해야 하고 그건 계층이 뒤집힌다. LevelConfig 상단이 예고한
-- "파트 깊이만 별도 모듈로 빼서 양쪽이 읽게 한다"의 그 자리가 여기다.
--
-- ⚠️ 진행 방향 깊이(X, 12)를 8 아래로 내리지 말 것. 그 하한이 이동속도 상한을 직접
-- 정한다 — 깊이 8이면 상한 80, 4면 40이다.
ArenaConfig.CASHOUT_PAD_SIZE = Vector3.new(12, 1, 12)

-- ===== 아레나 경계 ===================================================================
--
-- 물리적으로 못 나가게 막는 벽이다. 서버 판정과는 별개의 물건이다 —
-- ChallengeService가 진행을 거부해도 파트가 없으면 캐릭터는 그냥 걸어나간다.
--
-- ⚠️ PadLayout이 예전에 쓰던 `ARENA_RADIUS`(68.8)와 아무 관계가 없다. 그쪽은
-- 패드 시작점 계산값이었고 물리 경계가 아니었다(4-2-a에서 그 항 자체가 사라졌다).

-- 스폰 구역의 X 범위. 패드(-380~-104)를 품고 챌린지 입구(-80)를 20 지나서 끝난다 —
-- 이 20의 겹침이 스폰 구역과 챌린지 구간을 잇는 출입구다.
ArenaConfig.SPAWN_ZONE_X_MIN = -420
ArenaConfig.SPAWN_ZONE_X_MAX = -60

-- Z 반폭. 스폰 구역이 더 넓다 — 패드 24장을 훑으며 좌우로 움직이는 구역이기 때문이다.
ArenaConfig.SPAWN_ZONE_Z_HALF = 120
ArenaConfig.CHALLENGE_ZONE_Z_HALF = 100

-- 경계 높이. 기본 점프가 약 7 studs이므로 넘어갈 수 없다.
-- ⚠️ 이동속도가 올라가도 점프 높이는 안 변한다(JumpPower는 힘에서 파생되지 않는다).
-- 이 값이 속도 상한을 따라갈 이유가 없는 이유다.
ArenaConfig.BOUNDARY_HEIGHT = 50

-- 경계 벽 두께.
--
-- ⚠️ 게임 수치가 아니라 기술 상수다. 진행 벽의 깊이(8)와 같은 값을 쓰되 근거는
-- 다르다 — 그쪽은 Touched 관통을 막는 하한이고(docs/UI_ASSET_SPEC.md "5-1"),
-- 이쪽은 CanCollide 관통을 막는 두께다. Touched를 쓰지 않으므로
-- LevelConfig.MIN_PART_DEPTH_SOURCES에 넣지 말 것 — 넣으면 경계 두께를 줄였을 때
-- 이동속도 상한이 근거 없이 따라 내려간다.
ArenaConfig.BOUNDARY_THICKNESS = 8

-- ===== 아레나 바닥 ===================================================================
--
-- 범위는 새 숫자를 만들지 않는다 — 스폰 구역·챌린지 구간 상수와 getChallengeEndX에서
-- 나온다(getFloorSpecs). 여기 1차 상수는 두께 하나뿐이다.
--
-- ⚠️ 윗면이 지면 Y=0이다. groundedY·발판·블록·진행 벽(getAdvanceWallCenter)이 전부
-- 이 지면을 전제하므로, 두께를 바꿔도 윗면은 움직이지 않고 아래로만 자란다.
-- ⚠️ 이 바닥이 생기기 전에는 플레이스 파일의 Baseplate(X·Z ±1024)뿐이었고,
-- 6층(X 1024 근처)에서 캐릭터가 떨어졌다.
ArenaConfig.FLOOR_THICKNESS = 4

-- 로블록스 파트 한 축의 최대 크기.
--
-- ⚠️ 게임 수치가 아니라 엔진 상한이다. 이보다 큰 Size를 넣으면 오류 없이 이 값으로
-- 잘려 세워진다 — 챌린지 바닥(X 5060)이 2048로 잘려 X 1446~3494만 덮었다(2026-10-19 실측).
-- 숫자 스펙만 보는 테스트는 이것을 못 잡으므로 validate가 모든 파트 스펙을 이 값과 비교하고,
-- 긴 바닥은 이 값 이하로 나눈다(getFloorSpecs).
ArenaConfig.MAX_PART_SIZE = 2048

-- ===== 진행 벽 =======================================================================
--
-- 위치는 getAdvanceX(아래 파생)이고, 여기는 크기와 열린 모습만 답한다.
-- "런 상태 → 벽 모습" 판정은 Shared/AdvanceWallView다 — 이 파일에 쓰지 말 것.

-- 진행 방향 깊이. 발판·벽 최소 깊이 규약값이다(docs/UI_ASSET_SPEC.md "5-1").
--
-- ⚠️ LevelConfig.DEPTH_SOURCES가 이 값을 읽어 이동속도 상한을 유도한다. 8 아래로
-- 내리면 상한이 따라 내려간다 (CASHOUT_PAD_SIZE 주석과 같은 이유).
ArenaConfig.ADVANCE_WALL_DEPTH = 8

-- 열린 벽의 투명도. 닫힌 벽은 불투명(0)이다.
ArenaConfig.ADVANCE_WALL_OPEN_TRANSPARENCY = 0.5

-- 같은 플레이어의 진행 벽 접촉을 다시 처리하기까지의 최소 간격(초).
-- 창의 의미는 CashoutPadService.TOUCH_DEBOUNCE_SEC과 같다(창 안의 재접촉은 무시,
-- 창 밖 접촉은 런이 없어도 시각을 갱신). 그쪽 상수를 읽지 않는 이유도 같다 —
-- 발판 디바운스를 튜닝했다고 벽이 따라 변하면 안 된다.
ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC = 0.5

-- ===== 파생 =========================================================================

-- 스테이지 한 주기 = 스테이지 폭 + 띠 폭. 스테이지 N과 N+1의 블록 중심 간 거리다.
function ArenaConfig.getStagePitch(): number
	return ArenaConfig.STAGE_WIDTH + ArenaConfig.GAP_WIDTH
end

-- 스테이지 N의 블록 클러스터 중심 X. 스테이지 1이 원점(X=0)이다.
--
-- ⚠️ 블록 좌표 자체(BlockLayout.computeLayout)는 여전히 원점 고정이고 player 인자를
-- 받지 않는다. 그쪽은 "클러스터 안에서 블록 16개가 어디에 서는가"이고, 이 함수는
-- "그 클러스터가 통째로 어디에 놓이는가"다. 두 값을 더해서 쓴다.
function ArenaConfig.getStageCenterX(stage: number): number
	assert(
		type(stage) == "number" and stage == stage and stage % 1 == 0 and stage >= 1,
		string.format("ArenaConfig.getStageCenterX: stage(%s)는 1 이상의 정수여야 함", tostring(stage))
	)
	return ArenaConfig.getStagePitch() * (stage - 1)
end

-- 수령 발판의 블록중심 기준 오프셋. 띠의 한가운데다 (스테이지 끝 + 띠 절반).
--
-- ⚠️ 발판은 이 X에 놓이되 **진행 축에서 옆으로 비켜서** 놓인다. 축 위에 두면 다음
-- 스테이지로 걸어가다 밟아서 런이 끝난다 — 수령은 선택이어야지 사고여서는 안 된다
-- (DESIGN.md "1. 챌린지"). 옆으로 얼마나 비키는지는 이 파일이 정하지 않는다.
function ArenaConfig.getCashoutOffset(): number
	return ArenaConfig.STAGE_WIDTH / 2 + ArenaConfig.GAP_WIDTH / 2
end

-- 진행 벽의 블록중심 기준 오프셋. 띠의 끝, 곧 다음 스테이지가 시작하는 자리다.
-- 벽은 축 정면에 있어서 통과하면 곧바로 다음 블록이 보인다.
function ArenaConfig.getAdvanceOffset(): number
	return ArenaConfig.STAGE_WIDTH / 2 + ArenaConfig.GAP_WIDTH
end

-- 스테이지 N의 수령 발판 X.
function ArenaConfig.getCashoutX(stage: number): number
	return ArenaConfig.getStageCenterX(stage) + ArenaConfig.getCashoutOffset()
end

-- 스테이지 N의 진행 벽 X.
--
-- ⚠️ 최종 스테이지 뒤에도 벽은 선다. 서버는 이미 진행을 거부하지만
-- (ChallengeService.advance — 담당 월드가 없는 층), **파트가 물리적으로 막지 않으면
-- 캐릭터는 그냥 걸어나간다.** 거부와 차단은 다른 일이다.
function ArenaConfig.getAdvanceX(stage: number): number
	return ArenaConfig.getStageCenterX(stage) + ArenaConfig.getAdvanceOffset()
end

-- 진행 벽 크기. 깊이(진행축 X)만 1차 상수이고, 폭과 높이는 새 숫자를 만들지 않는다:
--   폭(Z)   챌린지 통로 폭 전체 = CHALLENGE_ZONE_Z_HALF × 2 — 통로 어디로 걸어도 막힌다
--   높이(Y) 아레나 경계 높이 BOUNDARY_HEIGHT — 경계와 같은 이유로 점프로 못 넘는다
-- ⚠️ 축이 X라는 전제다(AXIS). 축을 틀면 이 함수의 성분 배치도 함께 바꿀 것.
function ArenaConfig.getAdvanceWallSize(): Vector3
	return Vector3.new(
		ArenaConfig.ADVANCE_WALL_DEPTH,
		ArenaConfig.BOUNDARY_HEIGHT,
		ArenaConfig.CHALLENGE_ZONE_Z_HALF * 2
	)
end

-- 스테이지 N 진행 벽의 중심 좌표 (x, y, z 숫자 셋).
--   x  getAdvanceX(stage)
--   y  지면(Y=0) + 벽 높이 절반. CashoutPadService.getPadPosition이 발판 Y를
--      PAD_SIZE.Y / 2로 두는 것과 같은 기준이다 (ArenaService.groundedY도 같다)
--   z  챌린지 구간 Z 중심(0). 경계 옆벽이 ±CHALLENGE_ZONE_Z_HALF에 대칭으로 선다
--
-- ⚠️ 서버 트리거(AdvanceWallService)와 클라 벽(AdvanceWallView → 렌더러)이 **둘 다** 이
-- 함수로 위치를 얻는다. 어느 쪽에서도 Y·Z를 따로 계산하지 말 것 — 두 벌이 되면
-- 보이는 벽과 판정하는 벽이 갈라진다.
-- ⚠️ Vector3가 아니라 숫자로 돌려준다. Vector3에 넣으면 float32 격자로 X가 어긋나서
-- 양쪽을 비교할 때 원본이 흐려진다 (TestHelpers.float32GapAt).
function ArenaConfig.getAdvanceWallCenter(stage: number): (number, number, number)
	local x = ArenaConfig.getAdvanceX(stage)
	local y = ArenaConfig.getAdvanceWallSize().Y / 2
	local z = 0
	return x, y, z
end

-- 스테이지 N의 시작 면 X. 걸어 들어온 유저가 그 층에서 처음 서게 되는 자리다.
--
-- ⚠️ 중심이 아니라 시작 면인 것이 요점이다. 중심은 블록 클러스터 한가운데라 캐릭터를
-- 그리로 옮기면 블록 사이에 낀다. 시작 면은 클러스터 바깥면(68.8)보다는 멀고
-- 근접 판정 반경(92.8)보다는 가까운 유일한 유도 지점이다 — 임의로 고른 좌표가
-- 아니라 폭을 조정하면 따라 움직인다.
function ArenaConfig.getStageEntranceX(stage: number): number
	return ArenaConfig.getStageCenterX(stage) - ArenaConfig.STAGE_WIDTH / 2
end

-- 챌린지 입구 X = 스테이지 1의 시작 면. 스폰 구역과 챌린지 구간의 경계다.
-- ⚠️ -80을 적지 않는다. 스테이지 폭을 바꾸면 입구가 따라 움직여야 한다.
--
-- ⚠️ 위 getStageEntranceX(1)의 별칭이다. 식을 여기 다시 쓰지 말 것 — 두 벌이 되면
-- 폭을 바꿨을 때 스폰 경계와 스테이지 시작 면이 갈라진다.
function ArenaConfig.getEntranceX(): number
	return ArenaConfig.getStageEntranceX(1)
end

-- ===== 챌린지 입장 게이트 ===========================================================
--
-- 런은 이 게이트를 지나는 순간 선다(EntranceGateService → ChallengeService.startRun).
-- 보이지 않는 서버 트리거 하나다 — 시각 표시는 U4(3D 안내) 몫이다.
--
-- ⚠️ 새 숫자를 만들지 않는다. 진행 벽 트리거와 같은 모양이다:
--   중심 X  getEntranceX() — 스폰 구역과 챌린지 구간의 경계 = 스테이지 1 시작 면
--   깊이 X  ADVANCE_WALL_DEPTH — Touched 최소 깊이 규약(이동속도 상한과 묶인 값)
--   높이 Y  BOUNDARY_HEIGHT — 점프로 넘어가 런 없이 들어가지 못한다
--   폭   Z  CHALLENGE_ZONE_Z_HALF × 2 — 통로 어디로 걸어도 닿는다
--   바닥    지면 Y=0에 아랫면이 닿는다(중심 Y = 높이 / 2)
-- ⚠️ 진행 벽 크기(getAdvanceWallSize)를 부르지 않고 같은 상수로 따로 조립한다. 벽 크기가
-- 바뀐다고 게이트가 따라 변할 이유는 없다 — 지금 같은 값인 것은 근거가 같아서다.

-- 입장 게이트 크기.
function ArenaConfig.getEntranceGateSize(): Vector3
	return Vector3.new(
		ArenaConfig.ADVANCE_WALL_DEPTH,
		ArenaConfig.BOUNDARY_HEIGHT,
		ArenaConfig.CHALLENGE_ZONE_Z_HALF * 2
	)
end

-- 입장 게이트 중심 (x, y, z 숫자 셋). Vector3로 주지 않는 이유는 getAdvanceWallCenter와 같다.
function ArenaConfig.getEntranceGateCenter(): (number, number, number)
	return ArenaConfig.getEntranceX(), ArenaConfig.BOUNDARY_HEIGHT / 2, 0
end

-- 스폰 지점에서 챌린지 입구까지의 거리. 패드 24장이 이 사이에 들어간다.
-- "체감상 적절한가"는 Play에서 볼 값이고, 여기서는 얼마인지만 답한다.
function ArenaConfig.getSpawnToEntrance(): number
	return ArenaConfig.getEntranceX() - ArenaConfig.SPAWN_X
end

-- 챌린지 구간의 끝 X. 주기 × 스테이지 수다 — 마지막 스테이지 중심(주기 × (N-1))보다
-- 한 주기 더 가서, 최종 진행 벽 뒤에 설 자리가 남는다.
--
-- ⚠️ 스테이지 수를 인자로 받는다. 여기서 WorldConfig를 조회하지 않는 이유는 이 파일이
-- 순수해야 하기 때문이고(다른 Config를 require하지 않는 것이 이 코드베이스의 관례),
-- 덕분에 테스트가 스테이지 수를 흔들어 경계가 따라 늘어나는지 볼 수 있다.
function ArenaConfig.getChallengeEndX(stageCount: number): number
	assert(
		type(stageCount) == "number" and stageCount == stageCount and stageCount % 1 == 0 and stageCount >= 1,
		string.format("ArenaConfig.getChallengeEndX: stageCount(%s)는 1 이상의 정수여야 함", tostring(stageCount))
	)
	return ArenaConfig.getStagePitch() * stageCount
end

-- 바닥 한 장의 명세. 위치·크기를 숫자로 준다 — 파트를 세우는 쪽(ArenaService)은
-- 이것을 소비만 한다. Vector3로 주지 않는 이유는 getAdvanceWallCenter와 같다.
export type FloorSpec = {
	name: string,
	xMin: number,
	xMax: number,
	zMin: number,
	zMax: number,
	topY: number,
	centerX: number,
	centerY: number,
	centerZ: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
}

local function floorSpec(name: string, xMin: number, xMax: number, zHalf: number): FloorSpec
	local thickness = ArenaConfig.FLOOR_THICKNESS
	local topY = 0 -- 지면. 위 "아레나 바닥" 절의 ⚠️
	return {
		name = name,
		xMin = xMin,
		xMax = xMax,
		zMin = -zHalf,
		zMax = zHalf,
		topY = topY,
		centerX = (xMin + xMax) / 2,
		centerY = topY - thickness / 2,
		centerZ = 0,
		sizeX = xMax - xMin,
		sizeY = thickness,
		sizeZ = zHalf * 2,
	}
end

-- 챌린지 바닥의 장 수. 길이를 파트 크기 상한으로 나눠 올림한다.
function ArenaConfig.getChallengeFloorCount(stageCount: number): number
	local length = ArenaConfig.getChallengeEndX(stageCount) - ArenaConfig.SPAWN_ZONE_X_MAX
	return math.ceil(length / ArenaConfig.MAX_PART_SIZE)
end

-- 아레나 바닥.
--   스폰 바닥     X SPAWN_ZONE_X_MIN ~ SPAWN_ZONE_X_MAX,         Z ±SPAWN_ZONE_Z_HALF   (한 장)
--   챌린지 바닥   X SPAWN_ZONE_X_MAX ~ getChallengeEndX(층 수),  Z ±CHALLENGE_ZONE_Z_HALF
--                 → getChallengeFloorCount장으로 같은 길이로 나눈다 (MAX_PART_SIZE)
--
-- ⚠️ 이웃 장은 맞닿고 겹치지 않는다. 같은 높이의 면이 겹치면 화면이 깜빡인다.
-- 챌린지 바닥이 입구(getEntranceX)가 아니라 스폰 구역 끝에서 시작하는 이유도 그것이다 —
-- 두 구역이 X로 겹치는 출입구 띠는 스폰 바닥이 덮는다.
-- ⚠️ i번째 경계는 시작 + 길이 × i / 장 수로 **직접** 계산한다. 앞 장의 xMax에 길이를
-- 더해 가면 오차가 쌓여 마지막 xMax가 끝 X에서 어긋난다. 이웃 장은 같은 경계 값을
-- 나눠 쓰므로 맞닿음은 정확히 성립한다.
-- ⚠️ 층 수는 인자다. ArenaService가 경계 벽에 쓰는 findLastStage() 값을 그대로 넘긴다
-- (getChallengeEndX가 인자를 받는 것과 같은 이유).
function ArenaConfig.getFloorSpecs(stageCount: number): { FloorSpec }
	local specs: { FloorSpec } = {
		floorSpec("ArenaFloorSpawn", ArenaConfig.SPAWN_ZONE_X_MIN, ArenaConfig.SPAWN_ZONE_X_MAX, ArenaConfig.SPAWN_ZONE_Z_HALF),
	}

	local startX = ArenaConfig.SPAWN_ZONE_X_MAX
	local endX = ArenaConfig.getChallengeEndX(stageCount)
	local length = endX - startX
	local count = ArenaConfig.getChallengeFloorCount(stageCount)
	local function boundary(i: number): number
		if i == count then
			return endX -- 끝 X는 원본 함수 값 그대로 (나눗셈을 거치지 않는다)
		end
		return startX + length * i / count
	end

	for i = 1, count do
		table.insert(
			specs,
			floorSpec(
				string.format("ArenaFloorChallenge_%02d", i),
				boundary(i - 1),
				boundary(i),
				ArenaConfig.CHALLENGE_ZONE_Z_HALF
			)
		)
	end
	return specs
end

-- 파트 스펙의 한 축이 엔진이 그대로 세울 수 있는 크기인지 (0 초과 MAX_PART_SIZE 이하).
local function isPartAxisOk(size: number): boolean
	return type(size) == "number" and size == size and size > 0 and size <= ArenaConfig.MAX_PART_SIZE
end

-- stageCount는 선택이다. 주면 그 층 수의 바닥 스펙도 함께 본다(ArenaServiceTests가 실제
-- 마지막 층을 넘긴다). 이 파일은 StageConfig를 require하지 않으므로 스스로는 층 수를 모른다.
function ArenaConfig.validate(stageCount: number?): boolean
	assert(
		type(ArenaConfig.STAGE_WIDTH) == "number" and ArenaConfig.STAGE_WIDTH > 0,
		string.format("ArenaConfig: STAGE_WIDTH(%s)는 0보다 커야 함", tostring(ArenaConfig.STAGE_WIDTH))
	)

	-- 0이면 스테이지끼리 맞붙는다 — 발판도 벽도 놓을 자리가 없어진다.
	assert(
		type(ArenaConfig.GAP_WIDTH) == "number" and ArenaConfig.GAP_WIDTH > 0,
		string.format("ArenaConfig: GAP_WIDTH(%s)는 0보다 커야 함", tostring(ArenaConfig.GAP_WIDTH))
	)

	-- 스폰이 입구보다 뒤에 있어야 한다. 넘어가면 스폰하자마자 챌린지 안이다.
	assert(
		ArenaConfig.SPAWN_X < ArenaConfig.getEntranceX(),
		string.format(
			"ArenaConfig: SPAWN_X(%.1f)가 챌린지 입구(%.1f)보다 앞에 있음 — 스폰이 챌린지 안이다",
			ArenaConfig.SPAWN_X,
			ArenaConfig.getEntranceX()
		)
	)

	-- AXIS가 단위 벡터가 아니면 이 축을 쓰는 쪽(PadLayout.PITCH 곱셈,
	-- LevelConfig.depthAlong 투영)이 통째로 틀어진다.
	assert(
		math.abs(ArenaConfig.AXIS.Magnitude - 1) < 1e-6,
		string.format("ArenaConfig: AXIS가 단위 벡터가 아님 (크기 %.6f)", ArenaConfig.AXIS.Magnitude)
	)

	-- 파생이 실제로 성립하는지. 상수만 보고 지나가면 getStageCenterX가 주기를
	-- 빼먹어도 통과한다 (AttackConfig.validate / WarpConfig.validate와 같은 이유).
	local pitch = ArenaConfig.getStagePitch()
	assert(
		pitch == ArenaConfig.STAGE_WIDTH + ArenaConfig.GAP_WIDTH,
		string.format("ArenaConfig: 주기(%.1f)가 폭+띠와 다름", pitch)
	)
	assert(
		ArenaConfig.getStageCenterX(1) == 0,
		string.format("ArenaConfig: 스테이지 1의 중심(%.1f)이 원점이 아님", ArenaConfig.getStageCenterX(1))
	)
	assert(
		ArenaConfig.getStageCenterX(2) - ArenaConfig.getStageCenterX(1) == pitch,
		"ArenaConfig: 이웃 스테이지 간격이 주기와 다름 — getStageCenterX가 주기를 안 쓴다"
	)

	-- 발판과 벽이 둘 다 띠 **안**에 있어야 한다. 발판이 띠를 벗어나면 스테이지 위에
	-- 겹쳐 놓이고, 벽이 띠보다 멀면 다음 스테이지 블록을 지나서야 막힌다.
	local stageEdge = ArenaConfig.STAGE_WIDTH / 2
	local bandEnd = stageEdge + ArenaConfig.GAP_WIDTH
	local cashout = ArenaConfig.getCashoutOffset()
	local advance = ArenaConfig.getAdvanceOffset()

	assert(
		cashout > stageEdge and cashout < bandEnd,
		string.format("ArenaConfig: 수령 발판 오프셋(%.1f)이 띠(%.1f~%.1f) 밖", cashout, stageEdge, bandEnd)
	)
	assert(
		advance == bandEnd,
		string.format("ArenaConfig: 진행 벽 오프셋(%.1f)이 띠 끝(%.1f)이 아님", advance, bandEnd)
	)

	-- 발판이 벽보다 앞에 있어야 한다. 뒤에 있으면 벽을 통과한 뒤에야 발판이 나와서
	-- "수령이냐 진행이냐"의 선택 순서가 뒤집힌다.
	assert(
		cashout < advance,
		string.format("ArenaConfig: 수령 발판(%.1f)이 진행 벽(%.1f)보다 뒤에 있음", cashout, advance)
	)

	-- 스테이지가 올라가도 발판이 다음 스테이지를 침범하지 않는지. 주기와 오프셋이
	-- 따로 놀면 여기서 걸린다.
	assert(
		ArenaConfig.getCashoutX(1) < ArenaConfig.getStageCenterX(2) - stageEdge,
		"ArenaConfig: 스테이지 1의 수령 발판이 스테이지 2 영역 안에 있음"
	)
	-- ⚠️ 우변을 getStageEntranceX로 쓴다. "다음 스테이지 시작 면"이라는 말이 곧 그 함수이고,
	-- 식을 손으로 다시 쓰면 그쪽이 틀어져도 여기는 통과한다.
	assert(
		ArenaConfig.getAdvanceX(1) == ArenaConfig.getStageEntranceX(2),
		"ArenaConfig: 진행 벽이 다음 스테이지 시작 면에 있지 않음"
	)

	-- 시작 면은 층이 올라가도 항상 중심에서 폭의 절반만큼 뒤다. 이 관계가 깨지면
	-- 검증 스크립트가 캐릭터를 세우는 자리가 층마다 달라진다.
	assert(
		ArenaConfig.getStageCenterX(3) - ArenaConfig.getStageEntranceX(3) == stageEdge,
		"ArenaConfig: 스테이지 시작 면이 중심에서 폭의 절반만큼 떨어져 있지 않음"
	)

	-- ===== 측면 오프셋 ================================================================

	-- 0이면 발판이 진행축 위에 놓인다 — 다음 스테이지로 걸어가다 밟아서 런이 끝난다.
	assert(
		type(ArenaConfig.CASHOUT_LATERAL_OFFSET) == "number" and ArenaConfig.CASHOUT_LATERAL_OFFSET > 0,
		string.format(
			"ArenaConfig: CASHOUT_LATERAL_OFFSET(%s)는 0보다 커야 함 — 0이면 발판이 축 위에 있다",
			tostring(ArenaConfig.CASHOUT_LATERAL_OFFSET)
		)
	)

	-- ===== 경계 ======================================================================

	assert(
		ArenaConfig.SPAWN_ZONE_X_MIN < ArenaConfig.SPAWN_X,
		string.format(
			"ArenaConfig: 스폰 지점(%.1f)이 스폰 구역 뒷벽(%.1f) 밖에 있음",
			ArenaConfig.SPAWN_X,
			ArenaConfig.SPAWN_ZONE_X_MIN
		)
	)

	-- 스폰 구역이 챌린지 입구를 지나서 끝나야 출입구가 생긴다. 입구보다 앞에서 끝나면
	-- 두 구역 사이에 벽도 바닥도 없는 틈이 남는다.
	assert(
		ArenaConfig.SPAWN_ZONE_X_MAX > ArenaConfig.getEntranceX(),
		string.format(
			"ArenaConfig: 스폰 구역 끝(%.1f)이 챌린지 입구(%.1f)를 지나지 않음 — 출입구가 없다",
			ArenaConfig.SPAWN_ZONE_X_MAX,
			ArenaConfig.getEntranceX()
		)
	)

	-- 스폰 구역이 더 좁으면 두 구역 경계에서 챌린지 쪽 벽이 스폰 구역 안으로 파고든다.
	assert(
		ArenaConfig.SPAWN_ZONE_Z_HALF >= ArenaConfig.CHALLENGE_ZONE_Z_HALF,
		string.format(
			"ArenaConfig: 스폰 구역 반폭(%.1f)이 챌린지 구간 반폭(%.1f)보다 좁음",
			ArenaConfig.SPAWN_ZONE_Z_HALF,
			ArenaConfig.CHALLENGE_ZONE_Z_HALF
		)
	)

	-- 발판이 챌린지 구간 폭 안에 들어와야 한다. 벗어나면 경계 벽 바깥에 놓인다.
	local cashoutFarEdge = ArenaConfig.CASHOUT_LATERAL_OFFSET
	assert(
		cashoutFarEdge < ArenaConfig.CHALLENGE_ZONE_Z_HALF,
		string.format(
			"ArenaConfig: 수령 발판 측면 오프셋(%.1f)이 챌린지 구간 반폭(%.1f) 밖",
			cashoutFarEdge,
			ArenaConfig.CHALLENGE_ZONE_Z_HALF
		)
	)

	-- 기본 점프(약 7)로 넘어갈 수 없어야 경계가 경계다.
	assert(
		type(ArenaConfig.BOUNDARY_HEIGHT) == "number" and ArenaConfig.BOUNDARY_HEIGHT > 7,
		string.format("ArenaConfig: BOUNDARY_HEIGHT(%s)가 기본 점프 높이 이하", tostring(ArenaConfig.BOUNDARY_HEIGHT))
	)
	assert(
		type(ArenaConfig.BOUNDARY_THICKNESS) == "number" and ArenaConfig.BOUNDARY_THICKNESS > 0,
		string.format("ArenaConfig: BOUNDARY_THICKNESS(%s)는 0보다 커야 함", tostring(ArenaConfig.BOUNDARY_THICKNESS))
	)

	-- 진행 벽 크기 세 축이 양수인지.
	local wallSize = ArenaConfig.getAdvanceWallSize()
	assert(
		wallSize.X > 0 and wallSize.Y > 0 and wallSize.Z > 0,
		string.format("ArenaConfig: 진행 벽 크기(%s)의 축 중 양수가 아닌 것이 있음", tostring(wallSize))
	)

	-- ===== 파트 크기 상한 ============================================================
	--
	-- 상한을 넘는 Size는 오류 없이 잘려 세워진다(MAX_PART_SIZE 주석). 스펙 숫자로는
	-- 멀쩡해 보이므로 여기서 막는다.

	assert(
		isPartAxisOk(wallSize.X) and isPartAxisOk(wallSize.Y) and isPartAxisOk(wallSize.Z),
		string.format(
			"ArenaConfig: 진행 벽 크기(%s)의 축이 0 초과 MAX_PART_SIZE(%s) 이하가 아님",
			tostring(wallSize),
			tostring(ArenaConfig.MAX_PART_SIZE)
		)
	)

	local gateSize = ArenaConfig.getEntranceGateSize()
	assert(
		isPartAxisOk(gateSize.X) and isPartAxisOk(gateSize.Y) and isPartAxisOk(gateSize.Z),
		string.format(
			"ArenaConfig: 입장 게이트 크기(%s)의 축이 0 초과 MAX_PART_SIZE(%s) 이하가 아님",
			tostring(gateSize),
			tostring(ArenaConfig.MAX_PART_SIZE)
		)
	)

	assert(
		type(ArenaConfig.FLOOR_THICKNESS) == "number" and ArenaConfig.FLOOR_THICKNESS > 0,
		string.format("ArenaConfig: FLOOR_THICKNESS(%s)는 0보다 커야 함", tostring(ArenaConfig.FLOOR_THICKNESS))
	)

	-- 바닥을 볼 층 수. 1층, 위 경계 검사의 임의 층(3), 챌린지 바닥이 최소 세 장으로
	-- 나뉘는 층 수(분할 경로를 반드시 지나게), 그리고 호출자가 준 층 수.
	local splitStageCount = math.ceil(
		(ArenaConfig.MAX_PART_SIZE * 2 + ArenaConfig.SPAWN_ZONE_X_MAX) / pitch
	) + 1
	local floorStageCounts = { 1, 3, splitStageCount }
	if stageCount ~= nil then
		table.insert(floorStageCounts, stageCount)
	end
	for _, count in ipairs(floorStageCounts) do
		for _, spec in ipairs(ArenaConfig.getFloorSpecs(count)) do
			assert(
				isPartAxisOk(spec.sizeX) and isPartAxisOk(spec.sizeY) and isPartAxisOk(spec.sizeZ),
				string.format(
					"ArenaConfig: 바닥 %s(층 수 %d) 크기 (%s, %s, %s)의 축이 0 초과 MAX_PART_SIZE(%s) 이하가 아님",
					spec.name,
					count,
					tostring(spec.sizeX),
					tostring(spec.sizeY),
					tostring(spec.sizeZ),
					tostring(ArenaConfig.MAX_PART_SIZE)
				)
			)
		end
	end

	-- 경계 끝이 최종 진행 벽보다 뒤에 있어야 한다. 앞에 있으면 마지막 벽이 경계 밖에 선다.
	local lastStage = 3 -- 임의의 층. 스테이지 수와 무관하게 성립해야 하는 관계다.
	assert(
		ArenaConfig.getChallengeEndX(lastStage) > ArenaConfig.getAdvanceX(lastStage),
		string.format(
			"ArenaConfig: 챌린지 경계 끝(%.1f)이 최종 진행 벽(%.1f)보다 앞",
			ArenaConfig.getChallengeEndX(lastStage),
			ArenaConfig.getAdvanceX(lastStage)
		)
	)

	return true
end

return ArenaConfig

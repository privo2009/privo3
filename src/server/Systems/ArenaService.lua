--!strict
-- 아레나의 월드 파트를 세운다. 스폰 지점과 물리 경계.
--
-- 값의 원본은 Shared/Config/ArenaConfig(좌표)다. 이 파일은 그것을 Workspace에 얹는
-- 일만 한다 — 좌표식을 여기에 다시 쓰지 말 것. PadService가 PadLayout을 대하는 방식과
-- 같다.
--
-- ===== 서버 거부와 물리 차단은 별개다 =================================================
--
-- ChallengeService는 이미 최종 층에서 advance를 거부하고 있다. 그런데 거부는 "다음
-- 층으로 안 넘어간다"일 뿐이고, **캐릭터가 그 자리에서 더 걸어나가는 것을 막지는
-- 않는다.** 판정과 기하는 서로를 대신하지 못한다 — 그래서 경계 파트가 따로 있다.
--
-- ===== 순수 로직을 분리한 이유 ========================================================
--
-- 경계 벽 배치는 Instance 없이 검증할 수 있다. 스테이지 수를 흔들어 경계가 따라
-- 늘어나는지 같은 것은 파트를 세우지 않고도 재야 한다 — Studio Play가 없는 세션에서도
-- 좌표가 맞는지는 확인할 수 있어야 하기 때문이다.
-- (PadService._pure / BlockService._pure와 같은 패턴)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)

local ArenaService = {}

local ARENA_CONTAINER_NAME = "ArenaBounds"
local SPAWN_CONTAINER_NAME = "ArenaSpawn"

-- ===== 순수 로직 =====================================================================

-- 벽 하나의 명세. Instance가 아니라 값이다 — 테스트가 이것만 보고 배치를 검증한다.
export type WallSpec = {
	name: string,
	size: Vector3,
	position: Vector3,
}

-- 벽은 지면(Y=0) 위에 선다. 중심을 높이 절반만큼 띄운다
-- (PadLayout.GROUND_Y_OFFSET / BlockLayout.GROUND_Y_OFFSET과 같은 계산이다).
local function groundedY(height: number): number
	return height / 2
end

-- 정의된 마지막 스테이지 번호. WorldConfig에 월드가 추가되면 저절로 올라간다.
--
-- ⚠️ 25를 적지 말 것. 상한은 숫자가 아니라 WorldConfig에서 파생된다
-- (WarpConfig.validate가 "없는 층"을 찾는 방식과 같은 관용구).
local function findLastStage(): number
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		stage += 1
	end
	return stage
end

-- 스폰 지점의 좌표. 진행축 위, 지면 위에 선다.
--
-- ⚠️ Z=0이다. 스폰이 축 위에 있어야 걸어나가는 방향이 곧 진행 방향이 된다 —
-- 수령 발판이 축에서 비켜 있는 것과 정반대 이유다(그쪽은 사고로 밟히면 안 되고,
-- 이쪽은 사고로도 정면을 보게 해야 한다).
local function getSpawnPosition(spawnSize: Vector3): Vector3
	return Vector3.new(ArenaConfig.SPAWN_X, groundedY(spawnSize.Y), 0)
end

-- 경계 벽 명세 전체. 두 구역이 X 방향으로 20 겹치고, 그 겹침이 출입구다.
--
--        Z
--    +120├──────────────────┐
--        │   스폰 구역        │  ← +X 면은 벽이 없다 (출입구)
--    +100│                  └──────────────────┐
--        │                  │  챌린지 구간       │
--        0   ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·│→ X
--    -100│                  ┌──────────────────┘
--        │                  │
--    -120└──────────────────┘
--       -420              -60          주기 × 스테이지수
--
-- ⚠️ **어깨 벽(shoulder)이 필요하다.** 스폰 구역 반폭(120)이 챌린지 구간 반폭(100)보다
-- 넓어서, 스폰 옆벽이 끝나는 X=-60 지점에 |Z| 100~120 구간의 틈이 남는다. 그 틈으로
-- 걸어나가면 어느 구역의 벽에도 안 걸린다. 이 벽 둘은 임의로 추가한 것이 아니라
-- 주어진 좌표(120 vs 100)가 강제하는 것이다 — 두 반폭을 같게 만들면 없어진다.
local function buildWallSpecs(stageCount: number): { WallSpec }
	local height = ArenaConfig.BOUNDARY_HEIGHT
	local thickness = ArenaConfig.BOUNDARY_THICKNESS
	local y = groundedY(height)

	local spawnMinX = ArenaConfig.SPAWN_ZONE_X_MIN
	local spawnMaxX = ArenaConfig.SPAWN_ZONE_X_MAX
	local spawnHalfZ = ArenaConfig.SPAWN_ZONE_Z_HALF
	local challengeMinX = ArenaConfig.getEntranceX()
	local challengeMaxX = ArenaConfig.getChallengeEndX(stageCount)
	local challengeHalfZ = ArenaConfig.CHALLENGE_ZONE_Z_HALF

	local spawnSpanX = spawnMaxX - spawnMinX
	local challengeSpanX = challengeMaxX - challengeMinX
	local shoulderSpanZ = spawnHalfZ - challengeHalfZ

	local specs: { WallSpec } = {
		-- 스폰 구역 뒷벽. 진행 반대쪽 끝을 막는다.
		{
			name = "SpawnBack",
			size = Vector3.new(thickness, height, spawnHalfZ * 2 + thickness * 2),
			position = Vector3.new(spawnMinX, y, 0),
		},
		-- 스폰 구역 옆벽 둘. +X 면에는 벽이 없다 — 있으면 챌린지로 못 간다.
		{
			name = "SpawnSidePosZ",
			size = Vector3.new(spawnSpanX, height, thickness),
			position = Vector3.new((spawnMinX + spawnMaxX) / 2, y, spawnHalfZ),
		},
		{
			name = "SpawnSideNegZ",
			size = Vector3.new(spawnSpanX, height, thickness),
			position = Vector3.new((spawnMinX + spawnMaxX) / 2, y, -spawnHalfZ),
		},
		-- 챌린지 구간 옆벽 둘. -X 면에는 벽이 없다 — 있으면 스폰에서 못 들어온다.
		{
			name = "ChallengeSidePosZ",
			size = Vector3.new(challengeSpanX, height, thickness),
			position = Vector3.new((challengeMinX + challengeMaxX) / 2, y, challengeHalfZ),
		},
		{
			name = "ChallengeSideNegZ",
			size = Vector3.new(challengeSpanX, height, thickness),
			position = Vector3.new((challengeMinX + challengeMaxX) / 2, y, -challengeHalfZ),
		},
		-- 챌린지 구간 끝벽. 최종 진행 벽 뒤를 한 번 더 막는다
		-- (최종 벽 자체는 3c에서 따로 선다 — 이쪽은 아레나 전체의 끝이다).
		{
			name = "ChallengeEnd",
			size = Vector3.new(thickness, height, challengeHalfZ * 2 + thickness * 2),
			position = Vector3.new(challengeMaxX, y, 0),
		},
	}

	-- 어깨 벽. 두 구역의 반폭이 같으면 폭이 0이므로 아예 만들지 않는다.
	if shoulderSpanZ > 0 then
		local shoulderCenterZ = (spawnHalfZ + challengeHalfZ) / 2
		table.insert(specs, {
			name = "ShoulderPosZ",
			size = Vector3.new(thickness, height, shoulderSpanZ),
			position = Vector3.new(spawnMaxX, y, shoulderCenterZ),
		})
		table.insert(specs, {
			name = "ShoulderNegZ",
			size = Vector3.new(thickness, height, shoulderSpanZ),
			position = Vector3.new(spawnMaxX, y, -shoulderCenterZ),
		})
	end

	return specs
end

-- 캐릭터를 스폰 위에 세울 때의 목표 좌표.
--
-- Y를 올리는 이유: PivotTo는 모델의 **중심**을 맞춘다. 스폰 파트 윗면 좌표를 그대로
-- 주면 캐릭터 절반이 파트 안으로 들어가고, 로블록스가 밀어내면서 튄다.
--
-- ⚠️ 캐릭터 높이를 상수로 적지 말 것. R6과 R15가 다르고 유저 아바타마다 또 다르다 —
-- 실제 모델의 바운딩 박스에서 받는다(호출자가 GetExtentsSize로 잰다). 숫자를 박으면
-- 어떤 아바타에서는 묻히고 어떤 아바타에서는 뜬다.
local function computeReturnTarget(spawnPosition: Vector3, spawnSize: Vector3, characterHeight: number): Vector3
	return Vector3.new(
		spawnPosition.X,
		spawnPosition.Y + spawnSize.Y / 2 + characterHeight / 2,
		spawnPosition.Z
	)
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
ArenaService._pure = {
	groundedY = groundedY,
	findLastStage = findLastStage,
	getSpawnPosition = getSpawnPosition,
	buildWallSpecs = buildWallSpecs,
	computeReturnTarget = computeReturnTarget,
}

-- ===== 파트 생성 =====================================================================

-- 스폰 파트의 크기.
--
-- ⚠️ 게임 수치가 아니다. 이 값에 걸린 판정이 하나도 없다 — Touched를 쓰지 않고,
-- 통과 여부를 정하지도 않는다. 패드와 같은 발자국(8×1×8)으로 둔 것은 같은 통로에
-- 서 있는 물건이라 눈에 어긋나지 않게 하려는 것뿐이다. 지환 파트가 오면 교체 대상이다.
local SPAWN_SIZE = Vector3.new(8, 1, 8)

-- ⚠️ 지환 파트 교체 지점. 지금은 임시 기본 파트다. 교체할 때 바뀌지 않아야 하는
-- 계약은 PadService.createPadPart와 같은 성격의 셋이다:
--   - Anchored = true       (물리 시뮬레이션 금지 — CLAUDE.md 절대 규칙 4)
--   - CanCollide = true     (경계는 막는 물건이다. 이것이 경계의 전부다)
--   - Touched 연결 없음     (경계는 신호를 보내지 않는다. 판정에 관여하지 않는다)
local function createWallPart(spec: WallSpec, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Size = spec.size
	part.Position = spec.position
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- init()이 세운 SpawnLocation. 복귀가 이 파트의 실제 좌표를 쓴다 — ArenaConfig.SPAWN_X를
-- 다시 계산하지 않는 이유는 파트가 옮겨졌을 때(지환이 Studio에서 만지는 경우) 복귀도
-- 따라가야 하기 때문이다. 파트가 없으면 Config에서 만들어 쓴다(아래 fallback).
local spawnPart: BasePart? = nil

-- 런이 끝난 캐릭터를 스폰 지점으로 되돌린다.
--
--   true   옮겼다
--   false  옮기지 못했다 (캐릭터 없음 / 스폰 없음)
--
-- ⚠️ **실패해도 호출자를 실패시키지 않는다.** 이 함수는 런 종료 처리의 맨 끝에서
-- 불리고, 그 시점엔 보상이 이미 지급돼 있다. 여기서 error를 던지면 지급은 됐는데
-- 런 종료가 반쯤 끝난 상태가 된다 — 그래서 전부 조용히 false로 접는다.
-- 대신 로그는 남긴다. 무슨 일이 있었는지 알 근거가 그것뿐이다.
--
-- ⚠️ WalkSpeed를 건드리지 말 것. 서버 상한 관리는 SpeedService의 몫이고
-- 여기서 만지면 두 곳이 같은 값을 쓰게 된다 (CLAUDE.md 절대 규칙 3).
--
-- ⚠️ **yield하지 않는다.** 이 함수는 ChallengeService.endRun의 맨 끝에서 불리고,
-- 그 경로 중 하나(abandonRun)는 환생이 재화를 읽고 차감하는 사이에 지난다 —
-- RebirthService가 그 구간의 무-yield를 계약으로 걸어두었다. 여기서 한 번이라도
-- yield하면 그 사이 cashout이 끼어들어 차감액이 어긋난다.
-- task.wait·WaitForChild·트윈을 넣지 말 것. PivotTo는 즉시 반환한다.
function ArenaService.returnToSpawn(player: Player): boolean
	-- 가짜 Player 테이블(테스트)과 퇴장 중인 플레이어를 함께 걸러낸다.
	if typeof(player) ~= "Instance" then
		return false
	end

	local character = (player :: any).Character
	if character == nil then
		-- 정상 상황이다. 죽은 직후이거나 아직 스폰 전일 수 있다.
		print(string.format("[ArenaService] %s 스폰 복귀 건너뜀 - 캐릭터 없음", player.Name))
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		-- 캐릭터는 있는데 루트가 없다 = 조립 중이거나 해체 중이다. 옮길 대상이 없다.
		warn(string.format("[ArenaService] %s 스폰 복귀 실패 - HumanoidRootPart 없음", player.Name))
		return false
	end

	local part = spawnPart
	if part == nil or part.Parent == nil then
		-- init()이 안 돌았거나 파트가 지워졌다. 좌표는 Config가 여전히 알고 있으므로
		-- 복귀 자체를 포기하지는 않는다 — 아레나 밖에 남는 것보다는 낫다.
		warn("[ArenaService] 스폰 파트가 없다 - ArenaConfig 좌표로 대체한다")
	end

	local spawnPosition = if part ~= nil and part.Parent ~= nil
		then part.Position
		else getSpawnPosition(SPAWN_SIZE)
	local spawnSize = if part ~= nil and part.Parent ~= nil then part.Size else SPAWN_SIZE

	local ok, err = pcall(function()
		local extents = character:GetExtentsSize()
		character:PivotTo(CFrame.new(computeReturnTarget(spawnPosition, spawnSize, extents.Y)))
	end)

	if not ok then
		warn(string.format("[ArenaService] %s 스폰 복귀 실패 - %s", player.Name, tostring(err)))
		return false
	end

	return true
end

local initialized = false

-- 스폰 지점과 경계를 Workspace에 세운다.
function ArenaService.init()
	if initialized then
		warn("[ArenaService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- Play를 반복하거나 핫리로드된 경우 이전 파트가 남아 있을 수 있다. 겹쳐 세우면
	-- 같은 자리에 벽이 둘이 된다 (PadService.init과 같은 이유·같은 처리).
	for _, name in ipairs({ ARENA_CONTAINER_NAME, SPAWN_CONTAINER_NAME }) do
		local existing = Workspace:FindFirstChild(name)
		if existing ~= nil then
			existing:Destroy()
		end
	end

	-- ===== 스폰 =====================================================================

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = SPAWN_CONTAINER_NAME
	spawnFolder.Parent = Workspace

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawnLocation"
	spawn.Size = SPAWN_SIZE
	spawn.Position = getSpawnPosition(SPAWN_SIZE)
	spawn.Anchored = true
	spawn.CanCollide = true
	-- 팀 없는 게임이므로 중립. Neutral=false로 두면 팀이 없는 플레이어가 여기서
	-- 스폰하지 못해 로블록스가 원점(0,0,0)에 떨어뜨린다 — 스테이지 1 블록 한가운데다.
	spawn.Neutral = true
	spawn.Duration = 0 -- 스폰 보호 없음. 이 게임에는 PvP도 데미지도 없다.
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = spawnFolder

	-- returnToSpawn이 이 파트의 실제 좌표를 쓴다. 여기서 잡아두지 않으면 복귀가
	-- Config 좌표로만 돌아서, 파트를 Studio에서 옮겼을 때 둘이 갈라진다.
	spawnPart = spawn

	-- ===== 경계 =====================================================================

	local boundsFolder = Instance.new("Folder")
	boundsFolder.Name = ARENA_CONTAINER_NAME
	boundsFolder.Parent = Workspace

	local lastStage = findLastStage()
	for _, spec in ipairs(buildWallSpecs(lastStage)) do
		createWallPart(spec, boundsFolder)
	end

	print(string.format(
		"[ArenaService] 스폰 X=%.1f, 경계 %d개 (스테이지 %d층까지, 끝 X=%.1f)",
		ArenaConfig.SPAWN_X,
		#buildWallSpecs(lastStage),
		lastStage,
		ArenaConfig.getChallengeEndX(lastStage)
	))
end

return ArenaService

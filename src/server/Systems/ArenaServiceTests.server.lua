--!strict
-- ArenaService / ArenaConfig 경계·스폰 검증. Studio에서 Rojo 연결 후 Play 하면
-- 서버 시작 시 자동 실행된다. Phase 4-2-a 커밋 3a 검증.
--
-- ArenaService._pure의 순수 함수만 호출한다 — Instance 없이 검증한다
-- (PadServiceTests / BlockServiceTests와 같은 방식). 실제로 벽에 막히는지는
-- Studio Play 육안 확인 몫이다.
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
local ArenaService = require(script.Parent.ArenaService)

local pure = ArenaService._pure

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

-- ⚠️ 사본을 만들지 말 것. 2026-09-07 이전에는 이 자리에 손으로 베낀 사본이 있었고,
-- 원본이 실패 메시지에 함께 싣는 **상대오차 항을 떨어뜨리고 있었다**
-- (→ Shared/TestHelpers.lua 상단).
local checkClose = TestHelpers.checkClose

local function findSpec(specs: { any }, name: string): any
	for _, spec in ipairs(specs) do
		if spec.name == name then
			return spec
		end
	end
	return nil
end

-- 1. 스폰 좌표 --------------------------------------------------------------------------

do
	local size = Vector3.new(8, 1, 8)
	local pos = pure.getSpawnPosition(size)

	-- ⚠️ -400을 여기 적지 않는다. Config에서 읽어야 스폰을 옮겼을 때 이 검사가 따라온다.
	check("스폰 X가 ArenaConfig.SPAWN_X와 일치", checkClose(pos.X, ArenaConfig.SPAWN_X))

	-- Z=0이어야 걸어나가는 방향이 곧 진행 방향이 된다.
	check("스폰이 진행축 위에 있다 (Z=0)", checkClose(pos.Z, 0))

	-- 지면 위에 얹힌다. 그대로 두면 절반이 바닥에 묻힌다.
	check("스폰이 지면 위에 얹힌다 (중심 Y = 높이/2)", checkClose(pos.Y, size.Y / 2))

	-- 스폰이 스폰 구역 경계 안에 있는가. 밖에 있으면 벽 너머에서 시작한다.
	check(
		"스폰이 스폰 구역 안에 있다",
		pos.X > ArenaConfig.SPAWN_ZONE_X_MIN and pos.X < ArenaConfig.SPAWN_ZONE_X_MAX,
		string.format("x=%.1f 구역=[%.1f, %.1f]", pos.X, ArenaConfig.SPAWN_ZONE_X_MIN, ArenaConfig.SPAWN_ZONE_X_MAX)
	)
end

-- 2. 경계 높이 --------------------------------------------------------------------------

do
	local specs = pure.buildWallSpecs(5)
	check("경계 벽이 하나 이상 생긴다", #specs > 0, tostring(#specs))

	local allHeight = true
	local allGrounded = true
	for _, spec in ipairs(specs) do
		if spec.size.Y ~= ArenaConfig.BOUNDARY_HEIGHT then
			allHeight = false
		end
		if math.abs(spec.position.Y - ArenaConfig.BOUNDARY_HEIGHT / 2) > 1e-6 then
			allGrounded = false
		end
	end

	check("모든 경계 벽 높이가 BOUNDARY_HEIGHT", allHeight)
	check("모든 경계 벽이 지면 위에 얹힌다 (중심 Y = 높이/2)", allGrounded)

	-- 기본 점프(약 7)로 넘어갈 수 없어야 한다. 값 자체는 Config가 정하고
	-- 여기서는 그 값이 점프를 넘는지만 본다.
	check(
		"경계 높이가 기본 점프(약 7)로 넘을 수 없다",
		ArenaConfig.BOUNDARY_HEIGHT > 7,
		tostring(ArenaConfig.BOUNDARY_HEIGHT)
	)
end

-- 3. 경계가 스테이지 수에 따라 늘어난다 --------------------------------------------------
--
-- 스테이지 수를 흔들어 확인한다. 상수를 박았으면 두 결과가 같게 나온다.

do
	local few = pure.buildWallSpecs(5)
	local many = pure.buildWallSpecs(10)

	local fewEnd = findSpec(few, "ChallengeEnd")
	local manyEnd = findSpec(many, "ChallengeEnd")

	check("ChallengeEnd 벽이 존재한다", fewEnd ~= nil and manyEnd ~= nil)

	if fewEnd and manyEnd then
		check("끝벽 X가 ArenaConfig.getChallengeEndX(5)와 일치", checkClose(fewEnd.position.X, ArenaConfig.getChallengeEndX(5)))
		check("끝벽 X가 ArenaConfig.getChallengeEndX(10)와 일치", checkClose(manyEnd.position.X, ArenaConfig.getChallengeEndX(10)))
		check(
			"스테이지가 늘면 끝벽이 더 멀어진다",
			manyEnd.position.X > fewEnd.position.X,
			string.format("5층=%.1f 10층=%.1f", fewEnd.position.X, manyEnd.position.X)
		)
	end

	local fewSide = findSpec(few, "ChallengeSidePosZ")
	local manySide = findSpec(many, "ChallengeSidePosZ")
	if fewSide and manySide then
		check(
			"스테이지가 늘면 옆벽도 길어진다",
			manySide.size.X > fewSide.size.X,
			string.format("5층=%.1f 10층=%.1f", fewSide.size.X, manySide.size.X)
		)
		-- 옆벽이 입구부터 끝까지를 정확히 덮어야 중간에 틈이 없다.
		check(
			"옆벽 길이가 입구~끝 전체를 덮는다",
			checkClose(manySide.size.X, ArenaConfig.getChallengeEndX(10) - ArenaConfig.getEntranceX())
		)
	end
end

-- 4. 출입구 — 막으면 안 되는 면 -----------------------------------------------------------
--
-- 두 구역 사이는 뚫려 있어야 한다. 사방을 막으면 스폰 구역에 갇힌다.

do
	local specs = pure.buildWallSpecs(5)

	-- 스폰 구역의 +X 면과 챌린지 구간의 -X 면에는 벽이 없어야 한다. 이름으로 찾지 않고
	-- 좌표로 찾는다 — 이름을 바꿔도 "여기 벽이 서면 갇힌다"는 사실은 그대로다.
	local blocksDoorway = false
	for _, spec in ipairs(specs) do
		-- 진행축(Z=0)을 가로막는 얇은 X벽인가. 끝벽(ChallengeEnd)은 제외한다 —
		-- 그건 아레나 끝이지 출입구가 아니다.
		local isThinXWall = spec.size.X <= ArenaConfig.BOUNDARY_THICKNESS
		local coversAxis = math.abs(spec.position.Z) < spec.size.Z / 2
		local isBetweenZones = spec.position.X > ArenaConfig.SPAWN_X
			and spec.position.X < ArenaConfig.getChallengeEndX(5)
		if isThinXWall and coversAxis and isBetweenZones and spec.name ~= "ChallengeEnd" then
			blocksDoorway = true
		end
	end

	check("스폰 구역과 챌린지 구간 사이가 뚫려 있다 (갇히지 않는다)", not blocksDoorway)
	check("스폰 구역 +X 면에 벽이 없다", findSpec(specs, "SpawnFront") == nil)
	check("챌린지 구간 -X 면에 벽이 없다", findSpec(specs, "ChallengeStart") == nil)
end

-- 5. 어깨 벽 — 반폭 차이가 만드는 틈 -------------------------------------------------------
--
-- 스폰 구역(±120)이 챌린지 구간(±100)보다 넓어서, 스폰 옆벽이 끝나는 X에
-- |Z| 100~120 구간의 틈이 남는다. 임의로 추가한 벽이 아니라 좌표가 강제하는 것이다.

do
	local specs = pure.buildWallSpecs(5)
	local shoulder = findSpec(specs, "ShoulderPosZ")

	local needsShoulder = ArenaConfig.SPAWN_ZONE_Z_HALF > ArenaConfig.CHALLENGE_ZONE_Z_HALF
	check("반폭이 다르면 어깨 벽이 있다", needsShoulder == (shoulder ~= nil))

	if shoulder then
		local gap = ArenaConfig.SPAWN_ZONE_Z_HALF - ArenaConfig.CHALLENGE_ZONE_Z_HALF
		check("어깨 벽이 반폭 차이만큼을 덮는다", checkClose(shoulder.size.Z, gap))
		check("어깨 벽이 스폰 구역 끝에 선다", checkClose(shoulder.position.X, ArenaConfig.SPAWN_ZONE_X_MAX))

		-- 두 반폭 사이를 정확히 메우는가. 안쪽 모서리가 챌린지 반폭, 바깥이 스폰 반폭.
		local inner = shoulder.position.Z - shoulder.size.Z / 2
		local outer = shoulder.position.Z + shoulder.size.Z / 2
		check("어깨 벽 안쪽이 챌린지 반폭에 닿는다", checkClose(inner, ArenaConfig.CHALLENGE_ZONE_Z_HALF))
		check("어깨 벽 바깥이 스폰 반폭에 닿는다", checkClose(outer, ArenaConfig.SPAWN_ZONE_Z_HALF))

		check("어깨 벽이 양쪽에 있다", findSpec(specs, "ShoulderNegZ") ~= nil)
	end
end

-- 6. 스폰 구역이 패드를 품는다 -------------------------------------------------------------

do
	local specs = pure.buildWallSpecs(5)
	local back = findSpec(specs, "SpawnBack")
	local side = findSpec(specs, "SpawnSidePosZ")

	check("SpawnBack 벽이 존재한다", back ~= nil)
	check("SpawnSidePosZ 벽이 존재한다", side ~= nil)

	if back then
		check("뒷벽이 SPAWN_ZONE_X_MIN에 선다", checkClose(back.position.X, ArenaConfig.SPAWN_ZONE_X_MIN))
	end
	if side then
		check("옆벽이 SPAWN_ZONE_Z_HALF에 선다", checkClose(side.position.Z, ArenaConfig.SPAWN_ZONE_Z_HALF))
		check(
			"옆벽 길이가 스폰 구역 전체를 덮는다",
			checkClose(side.size.X, ArenaConfig.SPAWN_ZONE_X_MAX - ArenaConfig.SPAWN_ZONE_X_MIN)
		)
	end
end

-- 7. findLastStage가 WorldConfig에서 나온다 -----------------------------------------------

do
	local last = pure.findLastStage()
	-- ⚠️ 25를 적지 않는다. 월드가 추가되면 저절로 올라가야 하는 값이다.
	check("마지막 스테이지가 1 이상", last >= 1, tostring(last))

	local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
	check("마지막 스테이지가 실재한다", StageConfig.hasStage(last))
	check("그 다음 스테이지는 없다 (그래서 마지막이다)", not StageConfig.hasStage(last + 1))
end

-- 8. 바닥 스펙 — 범위가 원천 상수·함수에서 나온다 (4-2-a 3a 보강) ------------------------
--
-- ⚠️ 숫자를 적지 않는다. 기대값은 전부 ArenaConfig 상수·함수다.

local StageConfigForFloor = require(ReplicatedStorage.Shared.Config.StageConfig)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local CashoutPadSize = ArenaConfig.CASHOUT_PAD_SIZE

local LAST_STAGE = pure.findLastStage()
local floorSpecs = ArenaConfig.getFloorSpecs(LAST_STAGE)

local spawnFloor = findSpec(floorSpecs, "ArenaFloorSpawn")

-- 챌린지 바닥 장들. 이름 순서(_01, _02, ...)로 모은다 — 목록 순서에 기대지 않는다.
local function collectChallengeFloors(specs: { any }): { any }
	local out = {}
	local i = 1
	while true do
		local spec = findSpec(specs, string.format("ArenaFloorChallenge_%02d", i))
		if spec == nil then
			break
		end
		table.insert(out, spec)
		i += 1
	end
	return out
end

local challengeFloors = collectChallengeFloors(floorSpecs)

-- 챌린지 바닥 장 목록의 분할 규칙 검사. 층 수를 흔들어 여러 번 부른다.
local function checkChallengeSplit(label: string, stageCount: number, specs: { any })
	local chunks = collectChallengeFloors(specs)
	local startX = ArenaConfig.SPAWN_ZONE_X_MAX
	local endX = ArenaConfig.getChallengeEndX(stageCount)
	local expectedCount = math.ceil((endX - startX) / ArenaConfig.MAX_PART_SIZE)

	check(
		label .. ": 장 수 == ceil(길이 / MAX_PART_SIZE)",
		#chunks == expectedCount and ArenaConfig.getChallengeFloorCount(stageCount) == expectedCount,
		string.format("장=%d 함수=%d 기대=%d (층 수 %d, X %s~%s)", #chunks, ArenaConfig.getChallengeFloorCount(stageCount), expectedCount, stageCount, tostring(startX), tostring(endX))
	)
	check(
		label .. ": 바닥 목록 == 스폰 1장 + 챌린지 장들",
		#specs == 1 + #chunks and findSpec(specs, "ArenaFloorSpawn") ~= nil,
		string.format("목록=%d 챌린지=%d", #specs, #chunks)
	)
	if #chunks == 0 then
		return
	end

	check(
		label .. ": 첫 장 xMin == SPAWN_ZONE_X_MAX",
		chunks[1].xMin == startX,
		string.format("xMin=%s 기대=%s", tostring(chunks[1].xMin), tostring(startX))
	)
	check(
		label .. ": 마지막 장 xMax == getChallengeEndX(층 수)",
		chunks[#chunks].xMax == endX,
		string.format("xMax=%s 기대=%s (층 수 %d)", tostring(chunks[#chunks].xMax), tostring(endX), stageCount)
	)

	local problems: { string } = {}
	local covered = 0
	local expectedLength = (endX - startX) / #chunks
	for i, chunk in ipairs(chunks) do
		covered += chunk.xMax - chunk.xMin
		if not (chunk.sizeX > 0 and chunk.sizeX <= ArenaConfig.MAX_PART_SIZE) then
			table.insert(problems, string.format("%s 길이=%s > MAX_PART_SIZE", chunk.name, tostring(chunk.sizeX)))
		end
		if not checkClose(chunk.sizeX, expectedLength) then
			table.insert(problems, string.format("%s 길이=%s 같은 길이 기대=%s", chunk.name, tostring(chunk.sizeX), tostring(expectedLength)))
		end
		if chunk.zMin ~= -ArenaConfig.CHALLENGE_ZONE_Z_HALF or chunk.zMax ~= ArenaConfig.CHALLENGE_ZONE_Z_HALF then
			table.insert(problems, string.format("%s Z=%s~%s", chunk.name, tostring(chunk.zMin), tostring(chunk.zMax)))
		end
		if i > 1 and chunks[i - 1].xMax ~= chunk.xMin then
			-- 같지 않으면 빈틈(<) 또는 겹침(>)이다.
			table.insert(problems, string.format("%s xMax=%s ≠ %s xMin=%s", chunks[i - 1].name, tostring(chunks[i - 1].xMax), chunk.name, tostring(chunk.xMin)))
		end
	end
	check(label .. ": 각 장 길이 ≤ MAX_PART_SIZE · 같은 길이 · 이웃 맞닿음", #problems == 0, #problems > 0 and table.concat(problems, " / ") or nil)
	check(
		label .. ": 장 길이의 합 == 전 구간 길이",
		checkClose(covered, endX - startX),
		string.format("합=%s 구간=%s", tostring(covered), tostring(endX - startX))
	)
end

do
	check("스폰 바닥이 있다", spawnFloor ~= nil)
	check("챌린지 바닥이 한 장 이상", #challengeFloors >= 1, tostring(#challengeFloors))

	if spawnFloor then
		check("스폰 바닥 xMin == SPAWN_ZONE_X_MIN", spawnFloor.xMin == ArenaConfig.SPAWN_ZONE_X_MIN, tostring(spawnFloor.xMin))
		check("스폰 바닥 xMax == SPAWN_ZONE_X_MAX", spawnFloor.xMax == ArenaConfig.SPAWN_ZONE_X_MAX, tostring(spawnFloor.xMax))
		check("스폰 바닥 zMin == -SPAWN_ZONE_Z_HALF", spawnFloor.zMin == -ArenaConfig.SPAWN_ZONE_Z_HALF, tostring(spawnFloor.zMin))
		check("스폰 바닥 zMax == SPAWN_ZONE_Z_HALF", spawnFloor.zMax == ArenaConfig.SPAWN_ZONE_Z_HALF, tostring(spawnFloor.zMax))
	end
	if spawnFloor and #challengeFloors >= 1 then
		check(
			"스폰 바닥과 챌린지 첫 장이 맞닿는다 (스폰 xMax == 챌린지 xMin, 겹침 없음)",
			spawnFloor.xMax == challengeFloors[1].xMin,
			string.format("스폰 xMax=%s 챌린지 xMin=%s", tostring(spawnFloor.xMax), tostring(challengeFloors[1].xMin))
		)
	end

	-- 실제 마지막 층과, 층 수를 흔든 경우(한 장 / 상한 딱 근처 / 여러 장).
	checkChallengeSplit("마지막 층", LAST_STAGE, floorSpecs)
	for _, count in ipairs({ 1, 3, 10, 11, 20, 50 }) do
		checkChallengeSplit(string.format("층 수 %d", count), count, ArenaConfig.getFloorSpecs(count))
	end

	-- validate가 실제 마지막 층의 바닥에서 통과한다 (파트 크기 상한 포함).
	local ok, err = pcall(ArenaConfig.validate, LAST_STAGE)
	check("ArenaConfig.validate(마지막 층) 통과", ok, tostring(err))

	for _, spec in ipairs(floorSpecs) do
		-- 윗면 = 중심 + 두께/2. 숫자 필드끼리 다시 계산해 topY와 0을 함께 본다.
		local top = spec.centerY + spec.sizeY / 2
		check(spec.name .. ": 윗면 Y == 0 (topY)", spec.topY == 0, tostring(spec.topY))
		check(spec.name .. ": 중심 + 두께/2 == 0", top == 0, tostring(top))
		check(spec.name .. ": 두께 == FLOOR_THICKNESS", spec.sizeY == ArenaConfig.FLOOR_THICKNESS, tostring(spec.sizeY))
		check(
			spec.name .. ": 세 축 모두 0 초과 MAX_PART_SIZE 이하",
			spec.sizeX > 0 and spec.sizeX <= ArenaConfig.MAX_PART_SIZE
				and spec.sizeY > 0 and spec.sizeY <= ArenaConfig.MAX_PART_SIZE
				and spec.sizeZ > 0 and spec.sizeZ <= ArenaConfig.MAX_PART_SIZE,
			string.format("(%s, %s, %s)", tostring(spec.sizeX), tostring(spec.sizeY), tostring(spec.sizeZ))
		)
		check(spec.name .. ": 크기 X == xMax - xMin", spec.sizeX == spec.xMax - spec.xMin)
		check(spec.name .. ": 크기 Z == zMax - zMin", spec.sizeZ == spec.zMax - spec.zMin)
		check(spec.name .. ": 중심 X == 범위 중앙", spec.centerX == (spec.xMin + spec.xMax) / 2)
		check(spec.name .. ": 중심 Z == 범위 중앙", spec.centerZ == (spec.zMin + spec.zMax) / 2)
	end
end

-- 9. 회귀 — 모든 층의 서 있을 자리가 바닥 위에 있다 -----------------------------------------
--
-- ⚠️ 이번 사고를 잡는 검사다. 바닥이 Baseplate(±1024)뿐이었을 때 6층에서 떨어졌다.
-- 1층만 보면 멀쩡해 보인다 — 층 범위는 리터럴이 아니라 StageConfig에서 구한다.

-- 점 (x, z)가 바닥 장 중 하나 안에 있는가 (경계 포함). 모든 장의 합 기준이다.
local function onFloor(x: number, z: number): boolean
	for _, spec in ipairs(floorSpecs) do
		if x >= spec.xMin and x <= spec.xMax and z >= spec.zMin and z <= spec.zMax then
			return true
		end
	end
	return false
end

do
	local stageCount = 0
	local missing: { string } = {}
	local stage = 1
	while StageConfigForFloor.hasStage(stage) do
		stageCount += 1

		local centerX = ArenaConfig.getStageCenterX(stage)
		if not onFloor(centerX, 0) then
			table.insert(missing, string.format("%d층 블록 중심 x=%.1f z=0", stage, centerX))
		end

		local padX = ArenaConfig.getCashoutX(stage)
		local padZMin = ArenaConfig.CASHOUT_LATERAL_OFFSET - CashoutPadSize.Z / 2
		local padZMax = ArenaConfig.CASHOUT_LATERAL_OFFSET + CashoutPadSize.Z / 2
		for _, z in ipairs({ padZMin, ArenaConfig.CASHOUT_LATERAL_OFFSET, padZMax }) do
			if not onFloor(padX, z) then
				table.insert(missing, string.format("%d층 수령 발판 x=%.1f z=%.1f", stage, padX, z))
			end
		end

		local wallX, _, wallZ = ArenaConfig.getAdvanceWallCenter(stage)
		if not onFloor(wallX, wallZ) then
			table.insert(missing, string.format("%d층 진행 벽 x=%.1f z=%.1f", stage, wallX, wallZ))
		end

		stage += 1
	end

	check("회귀: 검사한 층 수 == 마지막 층", stageCount == LAST_STAGE and stageCount >= 1, string.format("검사=%d 마지막=%d", stageCount, LAST_STAGE))
	check(
		"회귀: 전 층의 블록 중심·수령 발판·진행 벽이 바닥 위",
		#missing == 0,
		#missing > 0 and table.concat(missing, " / ") or nil
	)
end

do
	check("회귀: SPAWN_X가 바닥 위", onFloor(ArenaConfig.SPAWN_X, 0), string.format("x=%.1f z=0", ArenaConfig.SPAWN_X))
	check("회귀: 챌린지 입구 X가 바닥 위", onFloor(ArenaConfig.getEntranceX(), 0), string.format("x=%.1f z=0", ArenaConfig.getEntranceX()))

	-- 클릭 파워 패드 전부. 정의된 월드마다 패드 세트를 펼쳐 축 방향 양 끝을 본다.
	local missing: { string } = {}
	local padCount = 0
	local halfX = PadLayout.PAD_SIZE.X / 2
	local worldId = 1
	while WorldConfig.get(worldId) ~= nil do
		local world = WorldConfig.get(worldId) :: any
		local positions = PadLayout.computeLayout(world.clickPadSet.count)
		for i, pos in ipairs(positions) do
			padCount += 1
			for _, x in ipairs({ pos.X - halfX, pos.X + halfX }) do
				if not onFloor(x, pos.Z) then
					table.insert(missing, string.format("월드 %d 패드 %d x=%.1f z=%.1f", worldId, i, x, pos.Z))
				end
			end
		end
		worldId += 1
	end
	check("회귀: 클릭 파워 패드가 하나 이상 검사됐다", padCount > 0, tostring(padCount))
	check("회귀: 클릭 파워 패드 전부의 X 범위가 바닥 위", #missing == 0, #missing > 0 and table.concat(missing, " / ") or nil)
end

-- ===== 지시서 #8 M3 조건 + M2 목표 이동 시간 =================================================
-- ArenaConfig는 다른 Config를 require하지 않으므로 모듈을 건너는 조건은 여기서 잰다.
do
	local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
	local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
	local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
	local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
	local stageHalf = ArenaConfig.STAGE_WIDTH / 2
	local clusterFace = BlockLayout.OUTER_RADIUS + BlockLayoutConfig.BLOCK_SPAN / 2

	check("M3: 블록 클러스터 바깥면이 스테이지 안", clusterFace < stageHalf, string.format("면 %.1f / 반폭 %.1f", clusterFace, stageHalf))
	check("M3: 판정 반경 > 스테이지 반폭", AttackConfig.getRadius() > stageHalf, string.format("반경 %.1f / 반폭 %.1f", AttackConfig.getRadius(), stageHalf))
	check("M3: 입구(시작 면)에 서도 판정 반경 안", ArenaConfig.getStageCenterX(1) - ArenaConfig.getStageEntranceX(1) <= AttackConfig.getRadius())

	local padHalf = ArenaConfig.CASHOUT_PAD_SIZE.X / 2
	local wallHalf = ArenaConfig.ADVANCE_WALL_DEPTH / 2
	local padNear = ArenaConfig.getCashoutOffset() - padHalf
	local padFar = ArenaConfig.getCashoutOffset() + padHalf
	local wallNear = ArenaConfig.getAdvanceOffset() - wallHalf
	local bandEnd = stageHalf + ArenaConfig.GAP_WIDTH
	check("M3: 수령 발판이 띠 안 (스테이지 끝 뒤)", padNear > stageHalf, string.format("발판 앞 %.1f / 끝 %.1f", padNear, stageHalf))
	check("M3: 수령 발판과 진행 벽이 안 겹침", padFar < wallNear, string.format("발판 뒤 %.1f / 벽 앞 %.1f", padFar, wallNear))
	check("M3: 진행 벽이 띠 끝 (다음 스테이지 시작 면)", ArenaConfig.getAdvanceOffset() == bandEnd)
	check("M3: 발판 · 벽 깊이 ≥ 8", ArenaConfig.CASHOUT_PAD_SIZE.X >= 8 and ArenaConfig.ADVANCE_WALL_DEPTH >= 8)
	local okValidate, err = pcall(ArenaConfig.validate, LAST_STAGE)
	check("M3: 모든 파트 각 축 ≤ MAX_PART_SIZE (ArenaConfig.validate, 마지막 층까지)", okValidate, tostring(err))

	-- M2: 기본 이동 속도 · 업그레이드 0 · 레벨 0 기준 목표 시간. ≈ 는 ±1초로 본다.
	local base = LevelConfig.getMaxSpeed(BigNum.new(0, 0))
	local lobbySec = ArenaConfig.getSpawnToEntrance() / base
	local stageSec = ArenaConfig.getStagePitch() / base -- 클리어 지점(그 층 시작 면) → 그 층 진행 벽 = 한 주기
	check("M2: 스폰 → 입장 게이트 ≈ 4초", math.abs(lobbySec - 4) <= 1, string.format("%.2f초 (%.0f studs ÷ %.0f)", lobbySec, ArenaConfig.getSpawnToEntrance(), base))
	check("M2: 층 시작 면 → 진행 벽 ≈ 5초", math.abs(stageSec - 5) <= 1, string.format("%.2f초 (%.0f studs ÷ %.0f)", stageSec, ArenaConfig.getStagePitch(), base))
	check("M3: 기본 속도가 MAX_WALK_SPEED 아래 (상한은 안 바꾼다)", base < LevelConfig.getMaxWalkSpeed(), string.format("%.0f / %.0f", base, LevelConfig.getMaxWalkSpeed()))
end

print(string.format("[ArenaServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ArenaServiceTests] %d test(s) failed", failed))
end

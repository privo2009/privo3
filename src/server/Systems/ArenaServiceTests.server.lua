--!strict
-- ArenaService / ArenaConfig 경계·스폰 검증. Studio에서 Rojo 연결 후 Play 하면
-- 서버 시작 시 자동 실행된다. Phase 4-2-a 커밋 3a 검증.
--
-- ArenaService._pure의 순수 함수만 호출한다 — Instance 없이 검증한다
-- (PadServiceTests / BlockServiceTests와 같은 방식). 실제로 벽에 막히는지는
-- Studio Play 육안 확인 몫이다.
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

print(string.format("[ArenaServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ArenaServiceTests] %d test(s) failed", failed))
end

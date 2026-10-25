--!strict
-- AdvanceWallView(진행 벽 모습 계산) + ArenaConfig 벽 크기 + LevelConfig 깊이 소스 검증.
-- Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다. 3c 커밋 1.
--
-- ⚠️ 설정 숫자(8·50·100·120 등)를 여기 리터럴로 적지 않는다. 기대값은 전부 원천 상수와
-- 다른 함수에서 다시 유도한다 — 리터럴을 쓰면 설정을 바꾼 순간 테스트가 이유 없이 깨지거나,
-- 같은 오타를 양쪽에 적어 조용히 통과한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local AdvanceWallView = require(Shared.AdvanceWallView)
local ArenaConfig = require(Shared.Config.ArenaConfig)
local LevelConfig = require(Shared.Config.LevelConfig)
local StageConfig = require(Shared.Config.StageConfig)
local TestHelpers = require(Shared.TestHelpers)

local checkClose = TestHelpers.checkClose

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function findLastStage(): number
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		stage += 1
	end
	return stage
end

local LAST_STAGE = findLastStage()

-- 1. 크기 — 각 축이 원천 상수에서 나온다 -------------------------------------------------
-- Vector3 성분은 float32로 읽히므로 checkClose를 쓴다.
do
	local size = ArenaConfig.getAdvanceWallSize()
	check("크기: 깊이(X) = ADVANCE_WALL_DEPTH", checkClose(size.X, ArenaConfig.ADVANCE_WALL_DEPTH))
	check("크기: 높이(Y) = BOUNDARY_HEIGHT", checkClose(size.Y, ArenaConfig.BOUNDARY_HEIGHT))
	check("크기: 폭(Z) = CHALLENGE_ZONE_Z_HALF × 2", checkClose(size.Z, ArenaConfig.CHALLENGE_ZONE_Z_HALF * 2))
end

-- 2. 상태 → 모습 ---------------------------------------------------------------------
local function expectHidden(label: string, view: AdvanceWallView.View)
	check(label .. ": visible=false", view.visible == false)
	check(label .. ": open=false", view.open == false)
	check(label .. ": canCollide=false", view.canCollide == false)
	check(label .. ": colorRole=neutral", view.colorRole == "neutral", tostring(view.colorRole))
	check(label .. ": transparency=1", view.transparency == 1, tostring(view.transparency))
end

local function expectClosed(label: string, view: AdvanceWallView.View)
	check(label .. ": visible=true", view.visible == true)
	check(label .. ": open=false", view.open == false)
	check(label .. ": canCollide=true", view.canCollide == true)
	check(label .. ": colorRole=neutral", view.colorRole == "neutral", tostring(view.colorRole))
	check(label .. ": transparency=0", view.transparency == 0, tostring(view.transparency))
	check(label .. ": invalid 없음", view.invalid == nil, tostring(view.invalid))
end

do
	local v = AdvanceWallView.compute({ active = false, stage = 1, cleared = true, canAdvance = true })
	expectHidden("active=false", v)
	check("active=false: invalid 없음", v.invalid == nil, tostring(v.invalid))
end

expectClosed("미클리어", AdvanceWallView.compute({ active = true, stage = 1, cleared = false, canAdvance = false }))

do
	local v = AdvanceWallView.compute({ active = true, stage = 1, cleared = true, canAdvance = true })
	check("열림: visible=true", v.visible == true)
	check("열림: open=true", v.open == true)
	check("열림: canCollide=false", v.canCollide == false)
	check("열림: colorRole=advance", v.colorRole == "advance", tostring(v.colorRole))
	check(
		"열림: transparency = ADVANCE_WALL_OPEN_TRANSPARENCY",
		v.transparency == ArenaConfig.ADVANCE_WALL_OPEN_TRANSPARENCY,
		tostring(v.transparency)
	)
	check("열림: invalid 없음", v.invalid == nil, tostring(v.invalid))
end

expectClosed(
	"최종층(cleared, canAdvance=false)",
	AdvanceWallView.compute({ active = true, stage = LAST_STAGE, cleared = true, canAdvance = false })
)

-- nil 입력 · stage 없음 — 오류 없이 보이지 않음, invalid 없음
do
	local ok, v = pcall(AdvanceWallView.compute, nil)
	check("nil 입력: 오류 없음", ok, tostring(v))
	if ok then
		expectHidden("nil 입력", v)
		check("nil 입력: invalid 없음", v.invalid == nil, tostring(v.invalid))
		check("nil 입력: x 없음", v.x == nil)
	end
end

do
	local ok, v = pcall(AdvanceWallView.compute, { active = true, cleared = true, canAdvance = true })
	check("stage 없음: 오류 없음", ok, tostring(v))
	if ok then
		expectHidden("stage 없음", v)
		check("stage 없음: invalid 없음", v.invalid == nil, tostring(v.invalid))
		check("stage 없음: x 없음", v.x == nil)
	end
end

-- 잘못된 stage — 오류 없이 보이지 않음, invalid="invalid_stage"
for _, case in ipairs({
	{ label = "0", value = 0 },
	{ label = "음수", value = -1 },
	{ label = "소수", value = 1.5 },
	{ label = "NaN", value = 0 / 0 },
}) do
	local label = "잘못된 stage(" .. case.label .. ")"
	local ok, v = pcall(AdvanceWallView.compute, { active = true, stage = case.value, cleared = true, canAdvance = true })
	check(label .. ": 오류 없음", ok, tostring(v))
	if ok then
		expectHidden(label, v)
		check(label .. ": invalid=invalid_stage", v.invalid == "invalid_stage", tostring(v.invalid))
		check(label .. ": x 없음", v.x == nil)
	end
end

-- 3. 위치 — 배치가 실제로 getAdvanceX를 쓰는가 --------------------------------------
-- x는 숫자로 비교한다(Vector3에 넣으면 float32 격자로 X만 어긋난다 — TestHelpers.float32GapAt).
local function xAt(stage: number): number?
	return AdvanceWallView.compute({ active = true, stage = stage, cleared = false, canAdvance = false }).x
end

for _, stage in ipairs({ 1, 3, LAST_STAGE }) do
	check(
		string.format("위치: %d층 x == getAdvanceX(%d)", stage, stage),
		xAt(stage) == ArenaConfig.getAdvanceX(stage),
		string.format("x=%s 기대=%s", tostring(xAt(stage)), tostring(ArenaConfig.getAdvanceX(stage)))
	)
end

-- 다른 함수로 같은 자리를 확인한다: 진행 벽 = 다음 층의 시작 면.
for _, stage in ipairs({ 1, 3 }) do
	if stage < LAST_STAGE then
		check(
			string.format("위치: %d층 x == getStageEntranceX(%d)", stage, stage + 1),
			xAt(stage) == ArenaConfig.getStageEntranceX(stage + 1),
			string.format("x=%s 기대=%s", tostring(xAt(stage)), tostring(ArenaConfig.getStageEntranceX(stage + 1)))
		)
	end
end

-- 1층만 보면 층 오프셋을 빠뜨려도 멀쩡해 보인다 (docs/PENDING.md 함정 절).
check("위치: 3층 x ≠ 1층 x (층 오프셋이 실린다)", xAt(3) ~= xAt(1), string.format("1층=%s 3층=%s", tostring(xAt(1)), tostring(xAt(3))))

-- y·z — 서버 트리거와 같은 함수(getAdvanceWallCenter)에서 나오는가 (3c 커밋 2).
local function viewAt(stage: number): AdvanceWallView.View
	return AdvanceWallView.compute({ active = true, stage = stage, cleared = false, canAdvance = false })
end

for _, stage in ipairs({ 1, 3, LAST_STAGE }) do
	local v = viewAt(stage)
	local cx, cy, cz = ArenaConfig.getAdvanceWallCenter(stage)
	check(string.format("위치: %d층 x == getAdvanceWallCenter x", stage), v.x == cx, string.format("x=%s 기대=%s", tostring(v.x), tostring(cx)))
	check(string.format("위치: %d층 y == getAdvanceWallCenter y", stage), v.y == cy, string.format("y=%s 기대=%s", tostring(v.y), tostring(cy)))
	check(string.format("위치: %d층 z == getAdvanceWallCenter z", stage), v.z == cz, string.format("z=%s 기대=%s", tostring(v.z), tostring(cz)))
end

do
	local v1, v3 = viewAt(1), viewAt(3)
	check("위치: 3층 y == 1층 y (층이 바뀌어도 높이는 같다)", v1.y ~= nil and v1.y == v3.y, string.format("1층=%s 3층=%s", tostring(v1.y), tostring(v3.y)))
	check("위치: 3층 z == 1층 z (층이 바뀌어도 통로 중심은 같다)", v1.z ~= nil and v1.z == v3.z, string.format("1층=%s 3층=%s", tostring(v1.z), tostring(v3.z)))
end

-- stage가 없거나 잘못됐으면 y·z도 x와 같이 비어 있다.
do
	local vNil = AdvanceWallView.compute(nil)
	check("nil 입력: y·z 없음", vNil.y == nil and vNil.z == nil)
	local vBad = AdvanceWallView.compute({ active = true, stage = 0, cleared = false, canAdvance = false })
	check("잘못된 stage(0): y·z 없음", vBad.y == nil and vBad.z == nil)
end

-- 4. LevelConfig 깊이 소스 ------------------------------------------------------------
do
	local found = false
	for _, source in ipairs(LevelConfig.DEPTH_SOURCES) do
		if source.name == "advanceWall" then
			found = true
			check("LevelConfig: 진행 벽 소스 깊이 = ADVANCE_WALL_DEPTH", checkClose(source.get(), ArenaConfig.ADVANCE_WALL_DEPTH))
		end
	end
	check("LevelConfig: 진행 벽이 깊이 소스에 등록돼 있다", found)

	-- 진행 벽을 뺀 나머지 소스로 유도한 상한과 같아야 한다 — 벽 추가가 상한을 바꾸지 않았다.
	local shallowestWithoutWall: number? = nil
	for _, source in ipairs(LevelConfig.DEPTH_SOURCES) do
		if source.name ~= "advanceWall" then
			local depth = source.get()
			if shallowestWithoutWall == nil or depth < shallowestWithoutWall then
				shallowestWithoutWall = depth
			end
		end
	end
	local before = if shallowestWithoutWall ~= nil then LevelConfig.deriveMaxWalkSpeed(shallowestWithoutWall) else nil
	local after = LevelConfig.getMaxWalkSpeed()
	check(
		"LevelConfig: 이동속도 상한이 진행 벽 추가 전과 같다",
		before ~= nil and checkClose(after, before),
		string.format("전=%s 후=%s", tostring(before), tostring(after))
	)
end

print(string.format("[AdvanceWallViewTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AdvanceWallViewTests] %d test(s) failed", failed))
end

--!strict
-- 진행 벽 렌더 적용(AdvanceWallPart.applyView) 검증. Studio에서 Rojo 연결 후 Play 하면
-- 클라 시작 시 자동 실행된다. 3c 커밋 2.
--
-- ⚠️ 실물 LocalWalls 파트는 건드리지 않는다. 케이스마다 **테스트 전용 새 Part**를 만들어
-- 거기에 적용한다 — 이름 접두어로 격리를 흉내 내지 않고 자기 인스턴스를 쓴다
-- (docs/PENDING.md 함정 절). 만든 파트는 부모를 붙이지 않고 끝에 지운다.
-- ⚠️ 설정 숫자를 리터럴로 적지 않는다. 기대값은 AdvanceWallView·ArenaConfig·UiTheme에서 다시 유도한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdvanceWallView = require(ReplicatedStorage.Shared.AdvanceWallView)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
local AdvanceWallPart = require(script.Parent.Parent.World.AdvanceWallPart)

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

local created: { BasePart } = {}
local function newTestPart(): Part
	local part = Instance.new("Part")
	table.insert(created, part)
	return part
end

-- Part.Color는 8비트로 저장된다. 0~255 정수로 비교한다.
local function rgb255(c: Color3): (number, number, number)
	return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end

local function sameColor(a: Color3, b: Color3): boolean
	local ar, ag, ab = rgb255(a)
	local br, bg, bb = rgb255(b)
	return ar == br and ag == bg and ab == bb
end

-- 파트가 view를 그대로 받았는지. 위치·크기는 엔진에서 float32로 읽히므로 checkClose,
-- 숫자 성분끼리 비교한다(Vector3로 만들어 비교하지 않는다).
local function expectApplied(label: string, part: BasePart, view: AdvanceWallView.View, stage: number)
	check(label .. ": Transparency", checkClose(part.Transparency, view.transparency), string.format("%s vs %s", tostring(part.Transparency), tostring(view.transparency)))
	check(label .. ": CanCollide", part.CanCollide == view.canCollide, tostring(part.CanCollide))
	check(label .. ": Color = UiTheme." .. view.colorRole .. ".base", sameColor(part.Color, UiTheme.Colors[view.colorRole].base), tostring(part.Color))

	local size = ArenaConfig.getAdvanceWallSize()
	check(label .. ": Size.X", checkClose(part.Size.X, size.X), tostring(part.Size.X))
	check(label .. ": Size.Y", checkClose(part.Size.Y, size.Y), tostring(part.Size.Y))
	check(label .. ": Size.Z", checkClose(part.Size.Z, size.Z), tostring(part.Size.Z))

	local cx, cy, cz = ArenaConfig.getAdvanceWallCenter(stage)
	check(label .. ": Position.X", checkClose(part.Position.X, cx), string.format("%s vs %s", tostring(part.Position.X), tostring(cx)))
	check(label .. ": Position.Y", checkClose(part.Position.Y, cy), string.format("%s vs %s", tostring(part.Position.Y), tostring(cy)))
	check(label .. ": Position.Z", checkClose(part.Position.Z, cz), string.format("%s vs %s", tostring(part.Position.Z), tostring(cz)))
end

-- 1. 닫힘 (미클리어) --------------------------------------------------------------------
do
	local stage = 3
	local part = newTestPart()
	local view = AdvanceWallView.compute({ active = true, stage = stage, cleared = false, canAdvance = false })
	AdvanceWallPart.applyView(part, view)
	expectApplied("닫힘", part, view, stage)
	check("닫힘: 막는다", part.CanCollide == true)
	check("닫힘: 불투명", checkClose(part.Transparency, 0) or part.Transparency == 0, tostring(part.Transparency))
	check("닫힘: 중립 색", sameColor(part.Color, UiTheme.Colors.neutral.base))
end

-- 2. 열림 -----------------------------------------------------------------------------
do
	local stage = 1
	local part = newTestPart()
	local view = AdvanceWallView.compute({ active = true, stage = stage, cleared = true, canAdvance = true })
	AdvanceWallPart.applyView(part, view)
	expectApplied("열림", part, view, stage)
	check("열림: 막지 않는다", part.CanCollide == false)
	check("열림: 투명도 = ADVANCE_WALL_OPEN_TRANSPARENCY", checkClose(part.Transparency, ArenaConfig.ADVANCE_WALL_OPEN_TRANSPARENCY), tostring(part.Transparency))
	check("열림: 진행 색", sameColor(part.Color, UiTheme.Colors.advance.base))
end

-- 3. 최종층 (cleared, canAdvance=false) — 닫힘과 같은 모습 -------------------------------
do
	local part = newTestPart()
	local view = AdvanceWallView.compute({ active = true, stage = LAST_STAGE, cleared = true, canAdvance = false })
	AdvanceWallPart.applyView(part, view)
	expectApplied("최종층", part, view, LAST_STAGE)
	check("최종층: 막는다", part.CanCollide == true)
	check("최종층: 중립 색", sameColor(part.Color, UiTheme.Colors.neutral.base))
end

-- 4. 보이지 않음 (active=false, stage 유효) — 값은 그 층 자리로 옮겨진다 ------------------
do
	local stage = 3
	local part = newTestPart()
	local view = AdvanceWallView.compute({ active = false, stage = stage, cleared = true, canAdvance = true })
	AdvanceWallPart.applyView(part, view)
	expectApplied("보이지 않음", part, view, stage)
	check("보이지 않음: 투명 1", checkClose(part.Transparency, 1), tostring(part.Transparency))
	check("보이지 않음: 막지 않는다", part.CanCollide == false)
end

-- 5. x nil이면 위치 유지 — 앞서 놓인 자리에서 안 움직이고 나머지 값만 바뀐다 ---------------
for _, case in ipairs({
	{ label = "nil 입력", input = nil :: AdvanceWallView.Input? },
	{ label = "잘못된 stage", input = { active = true, stage = 0, cleared = true, canAdvance = true } :: AdvanceWallView.Input? },
}) do
	local stage = 3
	local part = newTestPart()
	AdvanceWallPart.applyView(part, AdvanceWallView.compute({ active = true, stage = stage, cleared = false, canAdvance = false }))
	local px, py, pz = part.Position.X, part.Position.Y, part.Position.Z
	local sx, sy, sz = part.Size.X, part.Size.Y, part.Size.Z

	local view = AdvanceWallView.compute(case.input)
	check(case.label .. ": 전제 — view.x가 nil", view.x == nil)
	AdvanceWallPart.applyView(part, view)

	check(case.label .. ": Position 유지", part.Position.X == px and part.Position.Y == py and part.Position.Z == pz)
	check(case.label .. ": Size 유지", part.Size.X == sx and part.Size.Y == sy and part.Size.Z == sz)
	check(case.label .. ": Transparency 적용", checkClose(part.Transparency, view.transparency), tostring(part.Transparency))
	check(case.label .. ": CanCollide 적용", part.CanCollide == view.canCollide)
	check(case.label .. ": Color 적용", sameColor(part.Color, UiTheme.Colors[view.colorRole].base))
end

-- 6. create — 고정 속성 ------------------------------------------------------------------
do
	local part = AdvanceWallPart.create()
	table.insert(created, part)
	check("create: Anchored", part.Anchored == true)
	check("create: CanTouch=false (클라 Touched를 쓰지 않는다)", part.CanTouch == false)
	check("create: 부모 없음 (붙이는 것은 렌더러 몫)", part.Parent == nil)
	local hidden = AdvanceWallView.compute(nil)
	check("create: 처음엔 보이지 않음 값", checkClose(part.Transparency, hidden.transparency) and part.CanCollide == hidden.canCollide)
end

for _, part in ipairs(created) do
	part:Destroy()
end

print(string.format("[AdvanceWallRendererTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AdvanceWallRendererTests] %d test(s) failed", failed))
end

--!strict
-- ChallengeInfo 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동
-- 실행된다. U3-2 착수 준비.
--
-- 실제 RunStateChanged 없이 handle._debug.apply()로 표시 로직을 직접 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.UI.Layout)
local ChallengeInfo = require(script.Parent.Parent.UI.Screens.Hud.ChallengeInfo)

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

local handle = ChallengeInfo.create()

-- ⚠️ **create() 바로 다음 줄이어야 한다. 사이에 yield를 넣지 말 것.**
-- 근거는 BloxDisplayTests의 같은 이름 상수 주석에 있다 — create()가 Offset에 박는
-- 인셋과 검사 시점의 인셋이 다를 수 있고(뷰포트가 바뀌면 GetGuiInset()이 달라진다),
-- 그러면 프로덕션이 멀쩡한데 검사만 깨진다.
--
-- ⚠️ 이 파일은 2026-09-04 Play에서 **우연히 통과했다.** create()와 검사 사이에
-- yield가 적어서 뷰포트가 바뀔 틈이 없었을 뿐이고, BloxDisplayTests가 깨진 것과
-- 완전히 같은 지뢰였다. 로딩이 느린 날 이쪽이 터진다.
local CREATED_TOP_INSET = Layout.getTopInset()

-- 1. 중앙 금지 구역을 침범하지 않고 상단 정보 15% 안에 있다 -----------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	check(
		"ChallengeInfo가 중앙 금지 구역을 침범하지 않는다",
		not Layout.overlapsCenterForbidden(x0, y0, x1, y1),
		string.format("x0=%.4f y0=%.4f x1=%.4f y1=%.4f", x0, y0, x1, y1)
	)
	check("ChallengeInfo가 상단 정보 높이(15%) 안에 있다", y1 <= Layout.TOP_HEIGHT, tostring(y1))
end

-- 2. 타이머가 특대(huge, 7%) 단계다 --------------------------------------------------

do
	local timerLabel = handle.root:FindFirstChild("Timer") :: TextLabel
	check("Timer 라벨이 있다", timerLabel ~= nil)

	local sizeConstraint = timerLabel:FindFirstChildOfClass("UITextSizeConstraint")
	check("Timer에 UITextSizeConstraint가 있다", sizeConstraint ~= nil)
	if sizeConstraint then
		check(
			"Timer의 MaxTextSize가 huge(76)와 같다",
			(sizeConstraint :: UITextSizeConstraint).MaxTextSize == TextScale.Levels.huge.maxTextSize
		)
	end

	-- Timer.Size.Y.Scale은 root 기준이다 (ChallengeInfo.lua 안의 환산 주석 참고) —
	-- 화면 기준으로 되돌려서 huge(7%)와 비교해야 한다.
	local timerScreenHeight = timerLabel.Size.Y.Scale * handle.root.Size.Y.Scale
	check(
		"Timer 높이가 화면 기준으로 huge(7%)와 같다",
		math.abs(timerScreenHeight - TextScale.Levels.huge.heightFraction) < 1e-9,
		tostring(timerScreenHeight)
	)
end

-- 3. active=false에서 레이아웃이 튀지 않는다 --------------------------------------------

do
	local stageLabel = handle.root:FindFirstChild("Stage") :: TextLabel
	local timerLabel = handle.root:FindFirstChild("Timer") :: TextLabel

	local rootSizeBefore = handle.root.Size
	local stageSizeBefore = stageLabel.Size
	local timerSizeBefore = timerLabel.Size

	handle._debug.apply({
		active = true,
		reason = "start",
		state = { stage = 3, reward = { m = 0, e = 0 }, timeLeft = 19.8, cleared = false, canAdvance = true },
		seeds = {},
	})

	check("활성 상태: 스테이지 문구가 채워진다", stageLabel.Text == "스테이지 3", stageLabel.Text)
	check("활성 상태: 타이머가 소수 1자리로 채워진다", timerLabel.Text == "19.8", timerLabel.Text)

	handle._debug.apply({
		active = false,
		reason = "cashout",
		state = { stage = 3, reward = { m = 0, e = 0 }, timeLeft = 0, cleared = true, canAdvance = false },
		seeds = {},
	})

	check("비활성 상태에서도 root Size가 그대로다(레이아웃 안 튐)", handle.root.Size == rootSizeBefore)
	check("비활성 상태에서도 Stage Size가 그대로다", stageLabel.Size == stageSizeBefore)
	check("비활성 상태에서도 Timer Size가 그대로다", timerLabel.Size == timerSizeBefore)
	check("비활성 상태: 대기 문구로 바뀐다(Stage)", stageLabel.Text == "대기 중", stageLabel.Text)
	check("비활성 상태: 대기 문구로 바뀐다(Timer)", timerLabel.Text == "--", timerLabel.Text)
end

-- 4. Offset을 쓰지 않는다 (허용 예외: Position.Y.Offset의 기본 UI 인셋만) -----------------

do
	check("root Size.X.Offset == 0", handle.root.Size.X.Offset == 0)
	check("root Size.Y.Offset == 0", handle.root.Size.Y.Offset == 0)
	check("root Position.X.Offset == 0", handle.root.Position.X.Offset == 0)
	-- ⚠️ getTopInset()을 여기서 다시 부르지 말 것. create() 시점에 잡아둔 값과 비교한다
	--    (이유는 CREATED_TOP_INSET 선언부). 정확 비교는 그대로다.
	check(
		"root Position.Y.Offset == Layout.getTopInset() (허용된 픽셀 예외)",
		handle.root.Position.Y.Offset == CREATED_TOP_INSET,
		string.format("Offset=%d 캡처=%d 현재=%d", handle.root.Position.Y.Offset, CREATED_TOP_INSET, Layout.getTopInset())
	)
end

print(string.format("[ChallengeInfoTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ChallengeInfoTests] %d test(s) failed", failed))
end

--!strict
-- AutoTools(자동 클리커 토글 / 자동 진행 버튼) 검증. Studio에서 Rojo 연결 후
-- Play 하면 클라 시작 시 자동 실행된다. U3-6 착수 준비.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Layout = require(script.Parent.Parent.UI.Layout)
local AutoTools = require(script.Parent.Parent.UI.Screens.Hud.AutoTools)
local TestHelpers = require(script.Parent.TestHelpers)
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

local handle = AutoTools.create()

-- 1. 하단 띠 경계(Y 0.75) 위에 있다 — 이번 결정의 핵심 --------------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	local boundary = 1 - Layout.BOTTOM_HEIGHT

	check(
		"AutoTools 하단이 하단 띠 경계(Y=0.75)와 정확히 같다(그 아래로 내려가지 않는다)",
		checkClose(y1, boundary)
	)
	check(
		"AutoTools 전체가 경계 위쪽에 있다(하단 띠를 침범하지 않는다)",
		y0 < boundary and y1 <= boundary,
		string.format("y0=%.6f y1=%.6f 경계=%.6f", y0, y1, boundary)
	)
end

-- 2. 우측 레일(20%) 폭 안에 있다 --------------------------------------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	check(
		"AutoTools가 우측 레일(20%) 안에 있다",
		x0 >= 1 - Layout.RAIL_WIDTH and x1 <= 1,
		string.format("x0=%.4f x1=%.4f 레일시작=%.4f", x0, x1, 1 - Layout.RAIL_WIDTH)
	)
	check(
		"AutoTools가 중앙 금지 구역을 침범하지 않는다",
		not Layout.overlapsCenterForbidden(x0, y0, x1, y1),
		string.format("x0=%.4f y0=%.4f x1=%.4f y1=%.4f", x0, y0, x1, y1)
	)
end

-- 3. 두 항목이 전부 있다 (2열: 자동클릭 왼쪽, 자동진행 오른쪽) --------------------------

do
	local autoClickerItem = handle.root:FindFirstChild("AutoClicker") :: Frame?
	local autoAdvanceItem = handle.root:FindFirstChild("AutoAdvance") :: Frame?
	check("AutoClicker 항목이 있다", autoClickerItem ~= nil)
	check("AutoAdvance 항목이 있다", autoAdvanceItem ~= nil)

	if autoClickerItem and autoAdvanceItem then
		local leftX0 = Layout.getBounds(autoClickerItem)
		local rightX0 = Layout.getBounds(autoAdvanceItem)
		check(
			"자동클릭이 자동진행보다 왼쪽에 있다",
			leftX0 < rightX0,
			string.format("autoClicker.x0=%.4f autoAdvance.x0=%.4f", leftX0, rightX0)
		)
	end
end

-- 4. 자동 진행 버튼은 잠김(중립 회색) 상태로 고정된다 -----------------------------------

do
	local autoAdvanceItem = handle.root:FindFirstChild("AutoAdvance") :: Frame
	local icon = autoAdvanceItem:FindFirstChild("Icon") :: Frame?
	check("AutoAdvance Icon이 있다", icon ~= nil)

	if icon then
		-- icon_autoadvance는 AssetRegistry에 미도착 상태다(placeholderRole="neutral") —
		-- 이 전제가 깨지면(에셋이 도착하면) 아래 색 검사도 같이 의미를 잃는다.
		local resolved = AssetRegistry.resolve("icon_autoadvance")
		check("icon_autoadvance가 미도착 상태다(전제 확인)", resolved.arrived == false)

		check(
			"자동 진행 아이콘이 중립(회색) 배경이다(잠김 표시)",
			icon.BackgroundColor3 == UiTheme.Colors.neutral.base,
			tostring(icon.BackgroundColor3)
		)
	end

	local hitArea = autoAdvanceItem:FindFirstChild("HitArea")
	check("자동 진행 항목에는 HitArea가 없다(눌러도 아무 일도 안 일어난다 — 창이 안 열린다)", hitArea == nil)
end

-- 5. 자동 클리커 토글이 두 상태를 전환한다 ------------------------------------------------

do
	check("기본값은 꺼짐이다", handle._debug.isAutoClickerEnabled() == false)

	local autoClickerItem = handle.root:FindFirstChild("AutoClicker") :: Frame
	local icon = autoClickerItem:FindFirstChild("Icon") :: GuiObject
	local stroke = icon:FindFirstChildOfClass("UIStroke") :: UIStroke

	local offColor = stroke.Color

	handle._debug.setAutoClickerEnabled(true)
	check("켜짐으로 바뀐다", handle._debug.isAutoClickerEnabled() == true)
	check(
		"켜지면 테두리 색이 바뀐다(꺼짐 색과 달라진다)",
		stroke.Color ~= offColor,
		tostring(stroke.Color)
	)
	local onColor = stroke.Color

	handle._debug.setAutoClickerEnabled(false)
	check("다시 꺼짐으로 바뀐다", handle._debug.isAutoClickerEnabled() == false)
	check(
		"꺼지면 테두리 색이 원래대로 돌아간다",
		stroke.Color == offColor and stroke.Color ~= onColor,
		tostring(stroke.Color)
	)

	local hitArea = autoClickerItem:FindFirstChild("HitArea")
	check("자동 클리커 항목에는 HitArea가 있다(탭으로 토글)", hitArea ~= nil)
end

-- 6. Offset을 쓰지 않는다 (허용 예외 없음) ----------------------------------------------

do
	check("root Size.X.Offset == 0", handle.root.Size.X.Offset == 0)
	check("root Size.Y.Offset == 0", handle.root.Size.Y.Offset == 0)
	check("root Position.X.Offset == 0", handle.root.Position.X.Offset == 0)
	check("root Position.Y.Offset == 0", handle.root.Position.Y.Offset == 0)
end

print(string.format("[AutoToolsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AutoToolsTests] %d test(s) failed", failed))
end

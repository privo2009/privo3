--!strict
-- AutoTools(자동 클리커 토글 / 자동 진행 버튼) 검증. Studio에서 Rojo 연결 후
-- Play 하면 클라 시작 시 자동 실행된다. U3-6 착수 준비, U3-7에서 밝기 채널
-- 검사를 추가했다(새 파일을 만들지 않았다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Layout = require(script.Parent.Parent.UI.Layout)
local AutoTools = require(script.Parent.Parent.UI.Screens.Hud.AutoTools)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
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

-- "더 흐리다"를 세 채널 합으로 잰다 — UiTheme의 light/base/dark 셰이드가 R=G=B인
-- 무채색(회색조)이라 이 합이 곧 밝기 순서와 정확히 일치한다(light > base > dark).
local function brightness(color: Color3): number
	return color.R + color.G + color.B
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

-- 4. 자동 진행 버튼은 잠김(중립 회색, 가장 어두움) 상태로 고정된다 ----------------------

do
	local autoAdvanceItem = handle.root:FindFirstChild("AutoAdvance") :: Frame
	local icon = autoAdvanceItem:FindFirstChild("Icon") :: Frame?
	check("AutoAdvance Icon이 있다", icon ~= nil)

	if icon then
		-- icon_autoadvance는 AssetRegistry에 미도착 상태다(placeholderRole="neutral") —
		-- 이 전제가 깨지면(에셋이 도착하면) 아래 색 검사도 같이 의미를 잃는다.
		local resolved = AssetRegistry.resolve("icon_autoadvance")
		check("icon_autoadvance가 미도착 상태다(전제 확인)", resolved.arrived == false)

		-- U3-7: 잠김은 neutral.dark로 고정한다(예전엔 placeholderRole이 우연히 낸
		-- neutral.base였다 — "에셋 미도착"과 "기능 잠김"이 같은 회색이라 구분이
		-- 안 됐다. 이제는 잠김 쪽이 더 어둡다).
		check(
			"자동 진행 아이콘이 neutral.dark 배경이다(잠김 = 가장 어두움)",
			icon.BackgroundColor3 == UiTheme.Colors.neutral.dark,
			tostring(icon.BackgroundColor3)
		)

		-- 잠김(dark)이 자동클릭의 기본 꺼짐 상태(base, 이 시점엔 아직 안 건드렸다 —
		-- 섹션 5에서 토글하기 전)보다 더 어두운지 — "잠김 > 꺼짐 > 켜짐" 순서의
		-- 절반(잠김 vs 꺼짐)을 여기서 먼저 고정한다.
		local autoClickerIcon = handle.root:FindFirstChild("AutoClicker") :: Frame
		local autoClickerIconVisual = autoClickerIcon:FindFirstChild("Icon") :: Frame
		check(
			"잠김이 자동클릭 기본(꺼짐) 상태보다 더 흐리다",
			brightness(icon.BackgroundColor3) < brightness(autoClickerIconVisual.BackgroundColor3),
			string.format(
				"잠김밝기=%.3f 꺼짐밝기=%.3f",
				brightness(icon.BackgroundColor3),
				brightness(autoClickerIconVisual.BackgroundColor3)
			)
		)
	end

	local hitArea = autoAdvanceItem:FindFirstChild("HitArea")
	check("자동 진행 항목에는 HitArea가 없다(눌러도 아무 일도 안 일어난다 — 창이 안 열린다)", hitArea == nil)
end

-- 5. 자동 클리커 토글이 두 상태를 전환한다 (색 + 밝기 두 채널) --------------------------

do
	check("기본값은 꺼짐이다", handle._debug.isAutoClickerEnabled() == false)

	local autoClickerItem = handle.root:FindFirstChild("AutoClicker") :: Frame
	local icon = autoClickerItem:FindFirstChild("Icon") :: Frame
	local stroke = icon:FindFirstChildOfClass("UIStroke") :: UIStroke

	local offStrokeColor = stroke.Color
	local offTint = icon.BackgroundColor3

	check(
		"꺼짐 상태 아이콘 밝기가 neutral.base다(기존 기본값과 동일)",
		offTint == UiTheme.Colors.neutral.base,
		tostring(offTint)
	)

	handle._debug.setAutoClickerEnabled(true)
	check("켜짐으로 바뀐다", handle._debug.isAutoClickerEnabled() == true)
	check(
		"켜지면 테두리 색이 바뀐다(꺼짐 색과 달라진다) — 색 채널",
		stroke.Color ~= offStrokeColor,
		tostring(stroke.Color)
	)
	check(
		"켜지면 아이콘 밝기도 바뀐다(꺼짐 밝기와 달라진다) — 밝기 채널",
		icon.BackgroundColor3 ~= offTint,
		tostring(icon.BackgroundColor3)
	)
	check(
		"켜짐이 꺼짐보다 밝다(neutral.light > neutral.base)",
		brightness(icon.BackgroundColor3) > brightness(offTint),
		string.format("켜짐밝기=%.3f 꺼짐밝기=%.3f", brightness(icon.BackgroundColor3), brightness(offTint))
	)
	local onStrokeColor = stroke.Color
	local onTint = icon.BackgroundColor3

	handle._debug.setAutoClickerEnabled(false)
	check("다시 꺼짐으로 바뀐다", handle._debug.isAutoClickerEnabled() == false)
	check(
		"꺼지면 테두리 색이 원래대로 돌아간다",
		stroke.Color == offStrokeColor and stroke.Color ~= onStrokeColor,
		tostring(stroke.Color)
	)
	check(
		"꺼지면 아이콘 밝기도 원래대로 돌아간다",
		icon.BackgroundColor3 == offTint and icon.BackgroundColor3 ~= onTint,
		tostring(icon.BackgroundColor3)
	)

	local hitArea = autoClickerItem:FindFirstChild("HitArea")
	check("자동 클리커 항목에는 HitArea가 있다(탭으로 토글)", hitArea ~= nil)
end

-- 6. setIconTint가 도착/미도착 두 경로 모두에서 밝기를 세팅한다(U3-7) -------------------
--
-- 지금 이 프로젝트의 아이콘은 전부 미도착이라 실제 데이터로는 도착(ImageLabel)
-- 경로를 밟을 수 없다 — AutoTools._pure로 노출된 순수 함수를 합성 인스턴스에
-- 직접 불러 두 경로 다 검증한다.

do
	local setIconTint = AutoTools._pure.setIconTint

	local frame = Instance.new("Frame")
	setIconTint(frame, false, UiTheme.Colors.neutral.dark)
	check(
		"미도착(Frame) 경로: BackgroundColor3가 바뀐다",
		frame.BackgroundColor3 == UiTheme.Colors.neutral.dark,
		tostring(frame.BackgroundColor3)
	)

	local image = Instance.new("ImageLabel")
	setIconTint(image, true, UiTheme.Colors.neutral.light)
	check(
		"도착(ImageLabel) 경로: ImageColor3가 바뀐다",
		image.ImageColor3 == UiTheme.Colors.neutral.light,
		tostring(image.ImageColor3)
	)
end

-- 7. Offset을 쓰지 않는다 (허용 예외 없음) ----------------------------------------------

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

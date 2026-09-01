--!strict
-- Panel 컴포넌트 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동
-- 실행된다. U3-1 착수 준비.
--
-- "제목·X 버튼 위치가 두 크기에서 동일하다"는 root 기준 Scale이 아니라 **화면
-- 기준** 값이 같은지로 검증한다 — Panel.lua가 하는 일이 정확히 그 환산이므로,
-- root 기준 숫자만 비교하면 그 환산 로직 자체가 빠져도 테스트가 통과해버린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Button = require(script.Parent.Parent.UI.Components.Button)
local Panel = require(script.Parent.Parent.UI.Components.Panel)
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

-- docs/UI.md "2. 세이프존" 기준 해상도. Panel.lua 안의 값과 같아야 폭 기준 여백을
-- 세로로 환산한 값을 이 테스트가 독립적으로 재현할 수 있다.
local REFERENCE_ASPECT = 1920 / 1080
local MARGIN_OF_SCREEN_WIDTH = 0.02

local small = Panel.create("Small", "작은 창")
local large = Panel.create("Large", "큰 창")

-- 1. 작은 창 / 큰 창 크기가 규격과 같다 (docs/UI.md "6. 패널 > 크기 2종") -----------------

check("작은 창 크기 == 0.60 x 0.70", small.root.Size == UDim2.fromScale(0.60, 0.70))
check("큰 창 크기 == 0.85 x 0.85", large.root.Size == UDim2.fromScale(0.85, 0.85))

-- 2. 제목·X 버튼의 화면 기준 크기·위치가 두 크기에서 동일하다 --------------------------

local function screenHeightFraction(panel: Panel.PanelHandle, localScaleY: number): number
	return localScaleY * panel.root.Size.Y.Scale
end

local function screenWidthFraction(panel: Panel.PanelHandle, localScaleX: number): number
	return localScaleX * panel.root.Size.X.Scale
end

-- 제목 높이 == 화면 높이의 5% ("대") 여야 하고, 두 크기에서 같아야 한다.
local smallTitleScreenHeight = screenHeightFraction(small, small.titleLabel.Size.Y.Scale)
local largeTitleScreenHeight = screenHeightFraction(large, large.titleLabel.Size.Y.Scale)

check("작은 창 제목 높이가 화면 기준 5%다", checkClose(smallTitleScreenHeight, TextScale.Levels.large.heightFraction))
check("큰 창 제목 높이가 화면 기준 5%다", checkClose(largeTitleScreenHeight, TextScale.Levels.large.heightFraction))
check("두 크기의 제목 높이가 화면 기준으로 같다", checkClose(smallTitleScreenHeight, largeTitleScreenHeight))

-- X 버튼 높이 == 화면 높이의 6% ("작은 버튼") 여야 하고, 두 크기에서 같아야 한다.
local smallCloseScreenHeight = screenHeightFraction(small, small.closeButton.root.Size.Y.Scale)
local largeCloseScreenHeight = screenHeightFraction(large, large.closeButton.root.Size.Y.Scale)

check("작은 창 X 버튼 높이가 화면 기준 6%다", checkClose(smallCloseScreenHeight, Button.HEIGHT_SMALL))
check("큰 창 X 버튼 높이가 화면 기준 6%다", checkClose(largeCloseScreenHeight, Button.HEIGHT_SMALL))
check("두 크기의 X 버튼 높이가 화면 기준으로 같다", checkClose(smallCloseScreenHeight, largeCloseScreenHeight))

-- 여백(위쪽) == 화면 폭 2%를 세로로 환산한 값이어야 하고, 두 크기에서 같아야 한다.
local EXPECTED_MARGIN_Y = MARGIN_OF_SCREEN_WIDTH * REFERENCE_ASPECT

local smallMarginYScreen = screenHeightFraction(small, small.titleLabel.Position.Y.Scale)
local largeMarginYScreen = screenHeightFraction(large, large.titleLabel.Position.Y.Scale)

check("작은 창 위쪽 여백이 화면 기준으로 규격과 같다", checkClose(smallMarginYScreen, EXPECTED_MARGIN_Y))
check("큰 창 위쪽 여백이 화면 기준으로 규격과 같다", checkClose(largeMarginYScreen, EXPECTED_MARGIN_Y))
check("두 크기의 위쪽 여백이 화면 기준으로 같다", checkClose(smallMarginYScreen, largeMarginYScreen))

-- X 버튼 오른쪽 여백(가로) == 화면 폭 2%여야 하고, 두 크기에서 같아야 한다.
local smallMarginXScreen = screenWidthFraction(small, 1 - small.closeButton.root.Position.X.Scale)
local largeMarginXScreen = screenWidthFraction(large, 1 - large.closeButton.root.Position.X.Scale)

check("작은 창 오른쪽 여백이 화면 기준으로 규격과 같다", checkClose(smallMarginXScreen, MARGIN_OF_SCREEN_WIDTH))
check("큰 창 오른쪽 여백이 화면 기준으로 규격과 같다", checkClose(largeMarginXScreen, MARGIN_OF_SCREEN_WIDTH))
check("두 크기의 오른쪽 여백이 화면 기준으로 같다", checkClose(smallMarginXScreen, largeMarginXScreen))

-- 3. X 버튼은 정사각형(AspectRatioConstraint)이고 제목/본문이 항상 존재한다 -------------

do
	local aspect = small.closeButton.root:FindFirstChildOfClass("UIAspectRatioConstraint")
	check("X 버튼에 UIAspectRatioConstraint가 있다", aspect ~= nil)
	if aspect then
		check("X 버튼 AspectRatio == 1 (정사각형)", (aspect :: UIAspectRatioConstraint).AspectRatio == 1)
		check(
			"X 버튼 DominantAxis == Height",
			(aspect :: UIAspectRatioConstraint).DominantAxis == Enum.DominantAxis.Height
		)
	end
end

check("body가 존재한다", small.body ~= nil and large.body ~= nil)
check("titleLabel.Text가 세팅된다", small.titleLabel.Text == "작은 창" and large.titleLabel.Text == "큰 창")

print(string.format("[PanelTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PanelTests] %d test(s) failed", failed))
end

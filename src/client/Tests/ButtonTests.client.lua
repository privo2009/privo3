--!strict
-- Button 컴포넌트 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동
-- 실행된다. U3-1 착수 준비. 생성한 Instance는 Parent를 세팅하지 않으므로 화면에는
-- 나타나지 않는다.

local Button = require(script.Parent.Parent.UI.Components.Button)
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

-- 1. 6색 전부 생성된다 --------------------------------------------------------------

local COLORS: { Button.ColorName } = { "yellow", "purple", "blue", "green", "red", "gray" }

for _, color in ipairs(COLORS) do
	local ok, handle = pcall(Button.create, {
		size = "Big",
		color = color,
		widthScale = 0.3,
	})
	check(string.format("Button.create('%s')가 에러 없이 만들어진다", color), ok)

	if ok then
		local colorVisual = handle.root:FindFirstChild("Color")
		local grayVisual = handle.root:FindFirstChild("Gray")
		check(string.format("'%s': Color visual이 있다", color), colorVisual ~= nil)
		check(string.format("'%s': Gray visual이 있다", color), grayVisual ~= nil)
	end
end

-- 2. 큰/작은 크기가 규격과 같다 (docs/UI.md "5. 버튼 > 크기 2종") -----------------------

do
	-- Size.Y.Scale은 Instance에서 읽은 float32 값이라 checkClose를 쓴다(TestHelpers.lua 참고).
	local big = Button.create({ size = "Big", color = "blue", widthScale = 0.3 })
	check("Big 버튼 높이 == 0.09", checkClose(big.root.Size.Y.Scale, Button.HEIGHT_BIG))

	local small = Button.create({ size = "Small", color = "blue", widthScale = 0.2 })
	check("Small 버튼 높이 == 0.06", checkClose(small.root.Size.Y.Scale, Button.HEIGHT_SMALL))

	-- heightScale을 명시하면 size 기본값 대신 그 값을 쓴다 (Panel.lua가 중첩 환산에 쓰는 경로).
	local custom = Button.create({ size = "Small", color = "blue", widthScale = 0.2, heightScale = 0.123 })
	check("heightScale을 넘기면 그 값을 그대로 쓴다", checkClose(custom.root.Size.Y.Scale, 0.123))
end

-- 3. 비활성 상태에서 gray로 바뀐다 ----------------------------------------------------

do
	local handle = Button.create({ size = "Big", color = "purple", widthScale = 0.3 })
	local colorVisual = handle.root:FindFirstChild("Color") :: GuiObject
	local grayVisual = handle.root:FindFirstChild("Gray") :: GuiObject

	check("기본 상태: Color가 보이고 Gray는 숨어 있다", colorVisual.Visible == true and grayVisual.Visible == false)

	handle.setDisabled(true)
	check("setDisabled(true) -> isDisabled()가 true", handle.isDisabled() == true)
	check("비활성: Gray가 보이고 Color는 숨는다", grayVisual.Visible == true and colorVisual.Visible == false)

	handle.setDisabled(false)
	check("setDisabled(false) -> 다시 Color가 보인다", colorVisual.Visible == true and grayVisual.Visible == false)
end

-- 4. 미도착 에셋(Frame)과 도착 에셋(ImageLabel) 양쪽에서 눌림 처리가 동작한다 -----------

do
	-- purple은 AssetConfig에 아직 실물이 없다 (미도착, Frame).
	local handle = Button.create({ size = "Big", color = "purple", widthScale = 0.3 })
	local colorVisual = handle.root:FindFirstChild("Color") :: Frame
	check("미도착 색 버튼의 Color visual은 Frame이다", colorVisual:IsA("Frame"))

	local baseColor = colorVisual.BackgroundColor3
	local basePosition = colorVisual.Position

	handle.setPressed(true)
	check("미도착: 눌리면 BackgroundColor3가 어두워진다", colorVisual.BackgroundColor3 ~= baseColor)
	check("미도착: 눌리면 Position이 아래로(Offset) 이동한다", colorVisual.Position ~= basePosition)
	check("미도착: 눌리면 Position.Y.Scale은 그대로 0이다 (Offset 예외 — Scale은 안 건드림)", colorVisual.Position.Y.Scale == 0)
	check("미도착: 눌리면 Position.Y.Offset이 0보다 크다", colorVisual.Position.Y.Offset > 0)

	handle.setPressed(false)
	check("미도착: 뗴면 원래 색으로 돌아온다", colorVisual.BackgroundColor3 == baseColor)
	check("미도착: 떼면 원래 위치로 돌아온다", colorVisual.Position == basePosition)
end

do
	-- yellow는 AssetConfig에 실물이 있다 (도착, ImageLabel).
	local handle = Button.create({ size = "Big", color = "yellow", widthScale = 0.3 })
	local colorVisual = handle.root:FindFirstChild("Color") :: ImageLabel
	check("도착 색 버튼의 Color visual은 ImageLabel이다", colorVisual:IsA("ImageLabel"))

	local baseTint = colorVisual.ImageColor3
	local basePosition = colorVisual.Position

	handle.setPressed(true)
	check("도착: 눌리면 ImageColor3가 어두워진다", colorVisual.ImageColor3 ~= baseTint)
	check("도착: 눌리면 Position이 아래로(Offset) 이동한다", colorVisual.Position ~= basePosition)

	handle.setPressed(false)
	check("도착: 떼면 원래 색으로 돌아온다", colorVisual.ImageColor3 == baseTint)
	check("도착: 떼면 원래 위치로 돌아온다", colorVisual.Position == basePosition)
end

print(string.format("[ButtonTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ButtonTests] %d test(s) failed", failed))
end

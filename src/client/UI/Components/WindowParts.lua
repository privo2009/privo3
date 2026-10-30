--!strict
-- 창 본문 조각 (환생 창 · 월드·워프 창 공용, Phase 6). 글자 줄 · 버튼 글자/탭 영역 · 버튼 그림 층 올리기.
--
-- 글자: 흰색 + 검은 외곽선, TextScaled + UITextSizeConstraint(5단계 maxTextSize) — docs/UI.md "4. 글자".
-- 버튼(Components/Button)에는 탭 감지가 없어 투명 HitArea(TextButton)를 덮는다(MenuRail과 같은 방식).
-- 위치 · 크기는 부모 기준 Scale이다. Offset을 쓰지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Button = require(script.Parent.Button)

local WindowParts = {}

WindowParts.Z_TEXT = 4
WindowParts.Z_BUTTON = 5
WindowParts.Z_BUTTON_LABEL = 6
WindowParts.Z_HIT = 7

function WindowParts.makeText(
	name: string,
	parent: Instance,
	level: TextScale.Level,
	x: number,
	y: number,
	w: number,
	h: number,
	align: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Position = UDim2.fromScale(x, y)
	label.Size = UDim2.fromScale(w, h)
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = UiTheme.FONT
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.ZIndex = WindowParts.Z_TEXT
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels[level].maxTextSize
	size.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	label.Parent = parent
	return label
end

function WindowParts.hitArea(parent: Instance): TextButton
	local hit = Instance.new("TextButton")
	hit.Name = "HitArea"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = WindowParts.Z_HIT
	hit.Parent = parent
	return hit
end

-- 버튼 위에 글자와 투명 HitArea를 얹는다.
function WindowParts.decorateButton(button: Button.ButtonHandle, text: string): (TextLabel, TextButton)
	local label = WindowParts.makeText("Label", button.root, "medium", 0, 0, 1, 1, Enum.TextXAlignment.Center)
	label.ZIndex = WindowParts.Z_BUTTON_LABEL
	label.Text = text
	return label, WindowParts.hitArea(button.root)
end

-- 버튼 안쪽 그림(Button의 Color/Gray)은 ZIndex 1이라 패널 배경층(Panel 2층 구조) 밑에 깔린다
-- (2026-10-22 Play: 환생 창 X 버튼과 버튼 바탕이 안 보였다). 버튼 안쪽 전부를 본문 글자보다 위로 올린다.
function WindowParts.raiseButtons(roots: { Instance })
	for _, buttonRoot in ipairs(roots) do
		for _, obj in ipairs(buttonRoot:GetDescendants()) do
			if obj:IsA("GuiObject") and obj.ZIndex < WindowParts.Z_BUTTON then
				obj.ZIndex = WindowParts.Z_BUTTON
			end
		end
	end
end

return WindowParts

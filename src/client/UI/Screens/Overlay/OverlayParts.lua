--!strict
-- Overlay 화면들이 같이 쓰는 조각 (U4, 지시서 #5).
--
-- OverlayGui 안쪽 3층(docs/UI.md "6. 패널 > 레이어 우선순위")을 ZIndex로 나눈다:
--   알림층(토스트 · 오류) 30 > 차단층(로딩 등 모달) 20 > 런 표시층(클리어 안내 · 실패) 10
-- ScreenGui의 ZIndexBehavior가 기본(Sibling)이라 형제 root끼리의 ZIndex가 곧 층 순서다.
--
-- 글자는 흰색 + 검은 외곽선, TextScaled + UITextSizeConstraint(5단계 maxTextSize) — docs/UI.md "4. 글자".
-- 색은 UiTheme 역할 키만 쓴다. Offset을 쓰지 않는다(Scale만).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)

local OverlayParts = {}

OverlayParts.Z = {
	runDisplay = 10,
	blocking = 20,
	notice = 30,
}

-- 오른쪽 레일 위쪽 칸(x 0.80 ~ 0.97). 중앙 금지 구역(x 0.2 ~ 0.8)과 겹치지 않는다.
-- 레일 폭 20%에서 가장자리 여백 3%를 뺀 17%. 위치는 Claude가 정한 배치값(세션 로그).
OverlayParts.RIGHT_RAIL_LEFT = 0.80
OverlayParts.RIGHT_RAIL_WIDTH = 0.17

-- 텍스트 한 줄. 배경은 역할 색(base), 글자는 흰색 + 검은 외곽선.
function OverlayParts.textRow(name: string, text: string, level: TextScale.Level, role: UiTheme.ColorRole?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.SourceSansBold
	label.BorderSizePixel = 0
	if role ~= nil then
		label.BackgroundColor3 = UiTheme.Colors[role].base
		label.BackgroundTransparency = 0
	else
		label.BackgroundTransparency = 1
	end

	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels[level].maxTextSize
	size.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	return label
end

-- 역할 색 배경칸(UIStroke 테두리 포함). 글자 칸과 별도로 테두리를 그리고 싶을 때.
function OverlayParts.setRole(label: TextLabel, role: UiTheme.ColorRole)
	label.BackgroundColor3 = UiTheme.Colors[role].base
	label.BackgroundTransparency = 0
end

return OverlayParts

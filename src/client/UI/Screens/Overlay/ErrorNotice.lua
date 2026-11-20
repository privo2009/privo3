--!strict
-- 오류 (OverlayGui 알림층 — 최상단). U4, 지시서 #5. 지금 쓰는 곳은 로딩 시간 초과 하나다.
-- 오른쪽 레일 위쪽(중앙 금지 구역 밖). 경고 · 실패 역할(danger, 빨강).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local OverlayParts = require(script.Parent.OverlayParts)

local ErrorNotice = {}

local LEVEL: TextScale.Level = "small"
local ROWS = 3 -- 문구가 세 줄까지 들어가는 높이

-- 자리(화면 Scale). 토스트가 안내 띠 동안 같은 칸을 쓴다(지시서 #26 ToastStack.BelowBounds — 테스트가 둘이 같은지 본다)
ErrorNotice.Bounds = {
	x0 = OverlayParts.RIGHT_RAIL_LEFT,
	y0 = Layout.TOP_HEIGHT,
	x1 = OverlayParts.RIGHT_RAIL_LEFT + OverlayParts.RIGHT_RAIL_WIDTH,
	y1 = Layout.TOP_HEIGHT + TextScale.Levels[LEVEL].heightFraction * ROWS,
}

export type Handle = {
	root: Frame,
	setText: (string) -> (),
}

function ErrorNotice.create(): Handle
	local height = TextScale.Levels[LEVEL].heightFraction * ROWS
	local root = Instance.new("Frame")
	root.Name = "ErrorNotice"
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromScale(OverlayParts.RIGHT_RAIL_LEFT, Layout.TOP_HEIGHT)
	root.Size = UDim2.fromScale(OverlayParts.RIGHT_RAIL_WIDTH, height)
	root.BackgroundTransparency = 1
	root.ZIndex = OverlayParts.Z.notice

	local label = OverlayParts.textRow("Text", "", LEVEL, "danger")
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = true
	label.ZIndex = OverlayParts.Z.notice
	label.Parent = root

	return {
		root = root,
		setText = function(text: string)
			label.Text = text
		end,
	}
end

ErrorNotice.LOADING_TIMEOUT_TEXT = Locale.t("overlay.error.loadingTimeout")

return ErrorNotice

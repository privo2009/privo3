--!strict
-- HUD: 일일 보상 아이콘 (좌측 레일 — 블럭스 표시 바로 아래, 지시서 #20 D5). 누르면 일일 보상 창(차단층 큐 — OverlayBoot가 Navigation으로 받는다).
-- 받을 게 있으면 배지 — 수령 노랑 바탕 + "!" 글자(색 + 모양 두 채널). 값은 서버 PlayerState daily(DailyRewardWindowLogic.badge).
--
-- 칸 = 타일(icon_attend — 미도착이면 역할색 대체물) + 라벨("출석"). 타일 · 라벨은 Content 안 UIListLayout, HitArea는 Content 밖
-- (UIListLayout이 HitArea를 줄에 끼워 밀던 U3-10b 사고를 피한다). 배지는 타일의 자식(타일 오른쪽 위 안쪽).
-- 위치는 HudBoot가 정한다(블럭스 표시의 실제 아랫변 + 간격). 배치값은 Claude가 정했다(docs/UI.md "지시서 #20").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Store = require(script.Parent.Parent.Parent.Store)
local DailyRewardWindowLogic = require(script.Parent.Parent.Parent.Logic.DailyRewardWindowLogic)
local ButtonFx = require(script.Parent.Parent.Parent.Components.ButtonFx)

local DailyIcon = {}

DailyIcon.HEIGHT = 0.07 -- 칸 높이(화면 높이 기준). 폰 338px에서 타일 23.7px · 배지 13px(11px 하한 위)
DailyIcon.BADGE_SCALE = 0.55 -- 타일 대비 배지 크기
DailyIcon.LABEL_WIDTH = 0.6 -- 칸 폭 대비 라벨 폭

export type Deps = {
	store: any?,
	top: number?, -- 칸 윗변(화면 높이 기준). HudBoot가 블럭스 표시 아랫변에서 정한다
	onPress: (() -> ())?,
}

export type Handle = {
	root: Frame,
	_debug: { badge: Frame, badgeLabel: TextLabel, tile: GuiObject, label: TextLabel, hit: TextButton, press: () -> () },
}

local function textLabel(name: string, parent: Instance, level: TextScale.Level): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = UiTheme.FONT
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels[level].maxTextSize
	size.Parent = l
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = l
	l.Parent = parent
	return l
end

function DailyIcon.create(deps: Deps?): Handle
	local d: Deps = deps or {} :: Deps
	local source: any = d.store or Store

	local root = Instance.new("Frame")
	root.Name = "DailyIcon"
	root.Position = UDim2.fromScale(Layout.EDGE_MARGIN, d.top or 0.12)
	root.Size = UDim2.fromScale(Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2, DailyIcon.HEIGHT)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = root
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.05, 0)
	list.Parent = content

	local tile = AssetImage.create(AssetRegistry.resolve("icon_attend"))
	tile.Name = "Tile"
	tile.LayoutOrder = 1
	tile.Size = UDim2.fromScale(1, 1) -- 상자. 실제 폭은 아래 비율 제약이 높이 기준으로 깎는다(BloxDisplay 아이콘과 같은 관례)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = tile
	tile.Parent = content

	local label = textLabel("Label", content, "small")
	label.LayoutOrder = 2
	label.Size = UDim2.fromScale(DailyIcon.LABEL_WIDTH, 0.6)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = Locale.t("hud.daily")

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.fromScale(1, 0)
	badge.Size = UDim2.fromScale(DailyIcon.BADGE_SCALE, DailyIcon.BADGE_SCALE)
	badge.BackgroundColor3 = UiTheme.Colors.cashout.base
	badge.BorderSizePixel = 0
	badge.ZIndex = 3
	badge.Parent = tile
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = badge
	local badgeLabel = textLabel("Mark", badge, "small")
	badgeLabel.Size = UDim2.fromScale(1, 1)
	badgeLabel.TextXAlignment = Enum.TextXAlignment.Center
	badgeLabel.Text = Locale.t("hud.daily.badge")
	badgeLabel.ZIndex = 4

	local hit = Instance.new("TextButton")
	hit.Name = "HitArea"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = root
	ButtonFx.attach(hit) -- 지시서 #21 A

	local function render()
		badge.Visible = DailyRewardWindowLogic.badge(source.get("daily"))
	end
	local function press()
		if d.onPress ~= nil then
			d.onPress()
		end
	end
	hit.Activated:Connect(press)
	source.subscribe("daily", render)
	render()

	return { root = root, _debug = { badge = badge, badgeLabel = badgeLabel, tile = tile, label = label, hit = hit, press = press } }
end

return DailyIcon

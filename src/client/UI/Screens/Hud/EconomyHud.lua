--!strict
-- HUD: 코인 칸 · 가방 칸(지금 / 최대) (지시서 #32 — 플래그 ECONOMY_V2가 켜졌을 때만 만든다 · 꺼져 있으면 아무도 부르지 않는다).
-- 자리: 좌측 레일 바로 오른쪽 상단 띠(Layout.RAIL_WIDTH ~ ChallengeInfo 왼쪽 끝 0.35 사이) — 상단 띠는 중앙 금지 구역이 아니다.
-- 기존 컴포넌트(ValuePanel — Formatter · UiTheme.FONT · 외곽선)를 쓴다. 문장은 Strings 키(econ.*) · Locale.t · AutoLocalize = false.
-- 아이콘 자리: EconomyV2Config.COIN_VISUAL.iconId — nil이면 임시 도형(코인 색 정사각형).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local ValuePanel = require(script.Parent.Parent.Parent.Components.ValuePanel)

local EconomyHud = {}

EconomyHud.X0 = Layout.RAIL_WIDTH + 0.01
EconomyHud.WIDTH = 0.13 -- ChallengeInfo(0.35 ~ 0.65) 왼쪽에서 끝난다
local LEVEL: TextScale.Level = "small"

export type Handle = {
	root: Frame,
	coinIcon: Frame,
	coinValue: TextLabel,
	bagName: TextLabel,
	bagValue: TextLabel,
	coinTarget: () -> Vector2, -- 코인 이펙트가 날아갈 화면 픽셀 위치(아이콘 가운데)
	refreshInset: () -> (), -- 기본 UI 인셋을 다시 읽어 자리를 맞춘다(접속 직후에는 0으로 읽힐 수 있다 — Play 실측 #32)
	set: (values: any) -> (),
}

local function row(name: string, order: number, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 0.5)
	f.LayoutOrder = order
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.04, 0)
	list.Parent = f
	f.Parent = parent
	return f
end

local function textLabel(name: string, text: string, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AutoLocalize = false
	label.BackgroundTransparency = 1
	label.Font = UiTheme.FONT
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Size = UDim2.fromScale(0.45, 1)
	label.LayoutOrder = order
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = TextScale.Levels[LEVEL].maxTextSize
	c.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = parent
	return label
end

function EconomyHud.create(parent: Instance?): Handle
	local height = TextScale.Levels[LEVEL].heightFraction * 2.4
	local root = Instance.new("Frame")
	root.Name = "EconomyHud"
	root.BackgroundTransparency = 1
	root.Position = UDim2.new(EconomyHud.X0, 0, 0, Layout.getTopInset())
	root.Size = UDim2.fromScale(EconomyHud.WIDTH, height)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = root

	local coinRow = row("Coins", 1, root)
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.BackgroundColor3 = Config.COIN_VISUAL.color -- 임시 도형(iconId nil)
	icon.Size = UDim2.fromScale(1, 0.8)
	icon.LayoutOrder = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = icon
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = icon
	icon.Parent = coinRow
	local coinPanel = ValuePanel.create(LEVEL, ValuePanel.MAX_CHARS_DEFAULT)
	coinPanel.label.Name = "Value"
	coinPanel.label.AutoLocalize = false
	coinPanel.label.Size = UDim2.fromScale(1, 1)
	coinPanel.label.LayoutOrder = 2
	coinPanel.label.Parent = coinRow

	local bagRow = row("Bag", 2, root)
	local bagName = textLabel("Name", Locale.t("econ.bag.label"), 1, bagRow)
	local bagValue = textLabel("Value", Locale.t("econ.bag.value", { used = "0", cap = "0" }), 2, bagRow)

	root.Parent = parent

	local self = {} :: Handle
	self.root = root
	self.coinIcon = icon
	self.coinValue = coinPanel.label
	self.bagName = bagName
	self.bagValue = bagValue

	function self.coinTarget(): Vector2
		return icon.AbsolutePosition + icon.AbsoluteSize / 2
	end

	function self.refreshInset()
		root.Position = UDim2.new(EconomyHud.X0, 0, 0, Layout.getTopInset())
	end

	function self.set(values: any)
		self.refreshInset()
		coinPanel.setValue(values.coins)
		bagValue.Text = Locale.t("econ.bag.value", { used = tostring(values.bagUsed), cap = tostring(values.bagCap) })
		-- 가득 차면 숫자를 경고색으로(색 역할: 위험 = danger)
		bagValue.TextColor3 = if values.bagCap > 0 and values.bagUsed >= values.bagCap then UiTheme.Colors.danger.light else Color3.new(1, 1, 1)
	end

	return self
end

return EconomyHud

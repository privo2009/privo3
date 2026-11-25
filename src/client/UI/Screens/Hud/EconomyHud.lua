--!strict
-- HUD: 코인 칸 · 가방 칸(지금 / 최대) (지시서 #32 — 플래그 ECONOMY_V2가 켜졌을 때만 만든다 · 꺼져 있으면 아무도 부르지 않는다).
-- 자리: 좌측 레일 바로 오른쪽 상단 띠(Layout.RAIL_WIDTH ~ ChallengeInfo 왼쪽 끝 0.35 사이) — 상단 띠는 중앙 금지 구역이 아니다.
-- 기존 컴포넌트(ValuePanel — Formatter · UiTheme.FONT · 외곽선)를 쓴다. 문장은 Strings 키(econ.*) · Locale.t · AutoLocalize = false.
-- 아이콘 자리: EconomyV2Config.COIN_VISUAL.iconId — nil이면 임시 도형(코인 색 정사각형).
-- #33: 셋째 줄 = 대장간 버튼(대장간이 열렸을 때만 보인다 — 어디서든 연다) + 자동 제작 상태(진행 중 · 횟수).
-- #36: 코인 칸 · 가방 칸은 그 안내를 지났을 때 나타난다(values.tipsSeen — OnboardingTipsLogic.hudShown · 한 번 보이면 계속).
-- 자리 맞춤: 기본 UI 인셋이 바뀌면(GuiService.TopbarInset 변경 신호 — 공식 문서 GuiService) 다시 맞춘다. #32의 "처음 5초 다시 맞춤"을 대신한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local ValuePanel = require(script.Parent.Parent.Parent.Components.ValuePanel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local OnboardingTipsLogic = require(ReplicatedStorage.Shared.OnboardingTipsLogic)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots) -- 에셋 자리(#36 — 값이 있으면 그 그림 · 없으면 임시 도형)

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
	coinRow: Frame,
	bagRow: Frame,
	forgeRow: Frame,
	forgeButton: Frame,
	equipButton: Frame,
	forgeHit: TextButton,
	equipHit: TextButton,
	autoStatus: TextLabel,
	coinTarget: () -> Vector2, -- 코인 이펙트가 날아갈 화면 픽셀 위치(아이콘 가운데)
	refreshInset: () -> (), -- 기본 UI 인셋을 다시 읽어 자리를 맞춘다(접속 직후에는 0으로 읽힐 수 있다 — Play 실측 #32)
	set: (values: any) -> (),
}

local function row(name: string, order: number, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1 / 3)
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
	local height = TextScale.Levels[LEVEL].heightFraction * 3.6 -- 세 줄(코인 · 가방 · 대장간)
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
	if AssetSlots.applyImage(icon, Config.COIN_VISUAL.iconId) ~= nil then
		icon.BackgroundTransparency = 1 -- 아이콘이 오면 임시 원 대신(#36)
	end
	local coinPanel = ValuePanel.create(LEVEL, ValuePanel.MAX_CHARS_DEFAULT)
	coinPanel.label.Name = "Value"
	coinPanel.label.AutoLocalize = false
	coinPanel.label.Size = UDim2.fromScale(1, 1)
	coinPanel.label.LayoutOrder = 2
	coinPanel.label.Parent = coinRow

	local bagRow = row("Bag", 2, root)
	local bagName = textLabel("Name", Locale.t("econ.bag.label"), 1, bagRow)
	local bagValue = textLabel("Value", Locale.t("econ.bag.value", { used = "0", cap = "0" }), 2, bagRow)

	local forgeRow = row("Forge", 3, root)
	forgeRow.Visible = false
	local forgeButton = Button.create({ size = "Small", color = "gray", widthScale = 0.3, heightScale = 0.8 })
	forgeButton.root.Name = "ForgeButton"
	forgeButton.root.LayoutOrder = 1
	forgeButton.root.Parent = forgeRow
	local forgeLabel, forgeHit = WindowParts.decorateButton(forgeButton, Locale.t("forge.title"))
	forgeLabel.AutoLocalize = false
	AssetSlots.applyImage(forgeButton.root, Config.FORGE_SITE.iconId, { position = UDim2.fromScale(0.15, 0.5), size = UDim2.fromScale(0.25, 0.9) })
	-- 장비 버튼(#34 — 대장간이 열린 뒤에만 · 같은 줄)
	local equipButton = Button.create({ size = "Small", color = "gray", widthScale = 0.3, heightScale = 0.8 })
	equipButton.root.Name = "EquipButton"
	equipButton.root.LayoutOrder = 2
	equipButton.root.Parent = forgeRow
	local equipLabel, equipHit = WindowParts.decorateButton(equipButton, Locale.t("equip.open"))
	equipLabel.AutoLocalize = false
	local autoStatus = textLabel("AutoStatus", "", 3, forgeRow)
	autoStatus.Size = UDim2.fromScale(0.34, 1)

	root.Parent = parent

	local self = {} :: Handle
	self.root = root
	self.coinIcon = icon
	self.coinValue = coinPanel.label
	self.bagName = bagName
	self.bagValue = bagValue
	self.coinRow = coinRow
	self.bagRow = bagRow
	self.forgeRow = forgeRow
	self.forgeButton = forgeButton.root
	self.equipButton = equipButton.root
	self.forgeHit = forgeHit
	self.equipHit = equipHit
	self.autoStatus = autoStatus

	function self.coinTarget(): Vector2
		return icon.AbsolutePosition + icon.AbsoluteSize / 2
	end

	function self.refreshInset()
		root.Position = UDim2.new(EconomyHud.X0, 0, 0, Layout.getTopInset())
	end
	-- 인셋 변경 신호(공식 문서 GuiService.TopbarInset · GetPropertyChangedSignal). 읽기는 다음 프레임에(같은 프레임에 아직 안 바뀌었을 수 있다)
	local insetConn = GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		task.defer(self.refreshInset)
	end)
	root.Destroying:Connect(function()
		insetConn:Disconnect()
	end)

	function self.set(values: any)
		self.refreshInset()
		coinPanel.setValue(values.coins)
		bagValue.Text = Locale.t("econ.bag.value", { used = tostring(values.bagUsed), cap = tostring(values.bagCap) })
		-- 가득 차면 숫자를 경고색으로(색 역할: 위험 = danger)
		bagValue.TextColor3 = if values.bagCap > 0 and values.bagUsed >= values.bagCap then UiTheme.Colors.danger.light else Color3.new(1, 1, 1)
		-- 대장간: 열렸을 때만 버튼 · 자동 제작 중이면 횟수
		forgeRow.Visible = values.forgeOpen == true
		local seen = if type(values.tipsSeen) == "table" then values.tipsSeen else nil
		coinRow.Visible = seen == nil or OnboardingTipsLogic.hudShown(seen, "coins")
		bagRow.Visible = seen == nil or OnboardingTipsLogic.hudShown(seen, "bag")
		autoStatus.Text = if values.autoOn == true then Locale.t("forge.auto.status", { count = tostring(values.autoCount or 0) }) else ""
	end

	return self
end

return EconomyHud

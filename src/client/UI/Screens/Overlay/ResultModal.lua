--!strict
-- 뽑기 결과 모달 (OverlayGui 차단층 — 한 번에 하나, 닫으면 다음). Phase 7 지시서 #11 A6.
-- 큐 규칙은 UI/Logic/BlockingQueueLogic(범용 — 펫 · 일일 보상이 다시 쓴다), 문구는 AuraWindowLogic.resultView.
--
-- 화면 전체를 덮는 반투명 막(입력을 막는다 — 차단층) + 가운데 판: 머리말(대) · 이름(특대, 희귀도 색) · 등급 · 배수(소) · "확인"(회색).
-- 런 중(클리어 대기 포함)에는 띄우지 않는다 — OverlayBoot가 토스트로 보낸다(폰에서 썸스틱 · 이동을 막는다, A6).
-- 배치값은 Claude가 정했다(docs/UI.md "지시서 #11" 절).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local OverlayParts = require(script.Parent.OverlayParts)

local ResultModal = {}

local PANEL_W, PANEL_H = 0.4, 0.42

export type View = { heading: string, name: string, rarityTier: number, detail: string }

export type Handle = {
	root: Frame,
	show: (View) -> (),
	hide: () -> (),
	onConfirm: (() -> ()) -> (),
	_debug: { heading: TextLabel, name: TextLabel, detail: TextLabel, confirmHit: TextButton, panel: Frame },
}

function ResultModal.create(): Handle
	local root = Instance.new("Frame")
	root.Name = "ResultModal"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = OverlayParts.Z.blocking
	-- root는 늘 보이는 투명 틀이다(ScreenController.open이 root를 보이게 한다 — RebirthNotice와 같은 이유). 막과 판을 Visible로.
	local dim = Instance.new("TextButton") -- 입력을 막는 막(누르면 아무 일도 없다 — "확인"으로만 닫는다)
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.ZIndex = OverlayParts.Z.blocking
	dim.Visible = false
	dim.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = UiTheme.Colors.neutral.dark
	panel.BorderSizePixel = 0
	panel.ZIndex = OverlayParts.Z.blocking + 1
	panel.Visible = false
	panel.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Parent = panel

	local function text(name: string, level: any, y: number, h: number): TextLabel
		local l = WindowParts.makeText(name, panel, level, 0.05, y, 0.9, h, Enum.TextXAlignment.Center)
		l.ZIndex = OverlayParts.Z.blocking + 2
		return l
	end
	local heading = text("Heading", "large", 0.06, 0.18)
	local name = text("Name", "huge", 0.26, 0.24)
	local detail = text("Detail", "small", 0.52, 0.12)

	local confirm = Button.create({ size = "Small", color = "gray", widthScale = 0.5, heightScale = 0.2 })
	confirm.root.Name = "Confirm"
	confirm.root.Position = UDim2.fromScale(0.25, 0.72)
	confirm.root.Parent = panel
	local confirmLabel, confirmHit = WindowParts.decorateButton(confirm, Locale.t("common.ok"))
	for _, obj in ipairs(confirm.root:GetDescendants()) do
		if obj:IsA("GuiObject") then
			obj.ZIndex = OverlayParts.Z.blocking + 3
		end
	end
	confirm.root.ZIndex = OverlayParts.Z.blocking + 3
	confirmLabel.ZIndex = OverlayParts.Z.blocking + 4
	confirmHit.ZIndex = OverlayParts.Z.blocking + 5

	local listeners: { () -> () } = {}
	confirmHit.Activated:Connect(function()
		for _, f in ipairs(listeners) do
			f()
		end
	end)

	local function show(v: View)
		heading.Text = v.heading
		name.Text = v.name
		name.TextColor3 = UiTheme.rarityColor(v.rarityTier)
		stroke.Color = UiTheme.rarityColor(v.rarityTier)
		detail.Text = v.detail
		dim.Visible = true
		panel.Visible = true
	end

	local function hide()
		dim.Visible = false
		panel.Visible = false
	end

	return {
		root = root,
		show = show,
		hide = hide,
		onConfirm = function(f: () -> ())
			table.insert(listeners, f)
		end,
		_debug = { heading = heading, name = name, detail = detail, confirmHit = confirmHit, panel = panel },
	}
end

return ResultModal

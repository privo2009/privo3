--!strict
-- UI 키트 — 창 · HUD · 오버레이가 그림을 만드는 단 하나의 입구(2026-11-26 지시서 #39 · docs/UI.md "UI 키트").
-- 1월 템플릿 작업은 이 파일 안쪽 · UiTheme.Skin(Config/UiSkin) · 그림 ID만 바꾼다 — 화면 코드는 손대지 않는다.
-- 지금 모양(임시)은 #39 이전과 같다. 있던 부품(Panel · Button · WindowParts · Shine · ButtonFx)의 이름 · 인자는 그대로 두고 여기서 다시 내보낸다.
--
-- 부품(인자는 전부 부모 기준 Scale — Offset 금지):
--   틀 · 껍데기   panel(size, title) · panelLayout(size, inset?) · titlePlate(parent, text, pos, size) · closeButton(parent, pos, h)
--   버튼         button(props) · labeledButton(name, parent, color, x, y, w, h, caption) · decorateButton(btn, text) · hitArea(parent) · raiseButtons(list)
--   글자         text(name, parent, level, x, y, w, h, align?) · styleText(label, level)
--   칸           box(name, parent, x, y, w, h, z?) · card(name, parent, x, y, w, h, style, z?) · cardStyle(frame, style) · gradeColor(grade)
--   탭           tab(name, parent, x, y, w, h, caption, opts?) → { button, selected, label, hit, setSelected }
--   빛 띠        shine(target, options?) · unshine(target)
--   게이지       gauge(name, parent, x, y, w, h, opts?) → { root, fill, set(ratio) }
--   토스트       toastRow(name, level) — 토스트 한 줄(어두운 바탕 · 오른쪽 정렬)
--   확률 표 줄    oddsRow(parent, i, rowH, nameW) → (이름, 확률)
--   재화 칸       currencyChip(parent, opts) → { icon, value(ValuePanel) }
--   모달          dim(name, parent, alpha?) · modalPanel(name, parent, w, h, z, opts?)
--   바닥          stroke(parent, color?, px?, mode?) · corner(parent, kind) · skinImage(frame, slot)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local KitBase = require(script.Parent.KitBase)
local Button = require(script.Parent.Button)
local Panel = require(script.Parent.Panel)
local WindowParts = require(script.Parent.WindowParts)
local ValuePanel = require(script.Parent.ValuePanel)
local Shine = require(script.Parent.Shine)

local Kit = {}

Kit.Z_TEXT = WindowParts.Z_TEXT
Kit.Z_BUTTON = WindowParts.Z_BUTTON
Kit.Z_BUTTON_LABEL = WindowParts.Z_BUTTON_LABEL
Kit.Z_HIT = WindowParts.Z_HIT
Kit.IMAGE_SLOTS = KitBase.IMAGE_SLOTS

-- 틀 · 껍데기 ------------------------------------------------------------------------------------------
Kit.panel = Panel.create
Kit.panelLayout = Panel.layout
Kit.titlePlate = Panel.makeTitle
Kit.closeButton = Panel.makeClose

-- 버튼 ---------------------------------------------------------------------------------------------
Kit.button = Button.create
Kit.decorateButton = WindowParts.decorateButton
Kit.hitArea = WindowParts.hitArea
Kit.raiseButtons = WindowParts.raiseButtons

-- 글자 붙은 입체 버튼 하나(창마다 있던 makeButton · button 도우미와 같다): 작은 버튼 · Z_BUTTON · 글자 + HitArea
function Kit.labeledButton(name: string, parent: Instance, color: Button.ColorName, x: number, y: number, w: number, h: number, caption: string)
	local b = Button.create({ size = "Small", color = color, widthScale = w, heightScale = h })
	b.root.Name = name
	b.root.Position = UDim2.fromScale(x, y)
	b.root.ZIndex = WindowParts.Z_BUTTON
	b.root.Parent = parent
	local label, hit = WindowParts.decorateButton(b, caption)
	return b, label, hit
end

-- 글자 ---------------------------------------------------------------------------------------------
Kit.text = WindowParts.makeText
Kit.styleText = KitBase.styleText

-- 칸 -----------------------------------------------------------------------------------------------
Kit.box = KitBase.box
Kit.cardStyle = KitBase.cardStyle
Kit.stroke = KitBase.stroke
Kit.corner = KitBase.corner
Kit.skinImage = KitBase.skinImage
Kit.dim = KitBase.dim

function Kit.card(name: string, parent: Instance?, x: number, y: number, w: number, h: number, style: KitBase.CardStyle, z: number?): (Frame, UIStroke?)
	local f = KitBase.box(name, parent, x, y, w, h, z)
	f.BorderSizePixel = 0
	return f, KitBase.cardStyle(f, style)
end

-- 등급 색(장비 C1 · 아이템 테두리와 이름 글자만) — UiTheme.color("grade.<등급>")과 같다. 모르는 등급은 common
Kit.gradeColor = UiTheme.equipGradeColor
Kit.rarityColor = UiTheme.rarityColor

-- 탭 ----------------------------------------------------------------------------------------------
-- 회색 버튼 위에 고른 색(기본 하늘) 한 벌을 겹쳐 두고 고른 탭만 켠다(상점 · 펫 · 아우라 창이 쓰던 방식 그대로)
export type TabHandle = {
	button: Button.ButtonHandle,
	selected: Button.ButtonHandle,
	label: TextLabel,
	hit: TextButton,
	setSelected: (boolean) -> (),
}

function Kit.tab(name: string, parent: Instance, x: number, y: number, w: number, h: number, caption: string, opts: { color: Button.ColorName?, selectedColor: Button.ColorName? }?): TabHandle
	local o = opts or {}
	local base, label, hit = Kit.labeledButton(name, parent, o.color or "gray", x, y, w, h, caption)
	local sel = Button.create({ size = "Small", color = o.selectedColor or "blue", widthScale = 1, heightScale = 1 })
	sel.root.Name = "Selected"
	sel.root.Position = UDim2.fromScale(0, 0)
	sel.root.ZIndex = WindowParts.Z_BUTTON
	sel.root.Visible = false
	sel.root.Parent = base.root
	KitBase.skinImage(base.root, "tab")
	KitBase.skinImage(sel.root, "tabSelected")
	return {
		button = base,
		selected = sel,
		label = label,
		hit = hit,
		setSelected = function(on: boolean)
			sel.root.Visible = on
		end,
	}
end

-- 빛 띠 -------------------------------------------------------------------------------------------
function Kit.shine(target: GuiObject, options: Shine.Options?): boolean
	return Shine.attach(target, options)
end
function Kit.unshine(target: GuiObject)
	Shine.detach(target)
end

-- 게이지 ------------------------------------------------------------------------------------------
-- 배경 + 채움 두 층(PowerBlock 레벨 바와 같다). opts.back · fill = 색(기본 neutral.dark · power.base) · anchor = 배경 AnchorPoint
export type GaugeHandle = { root: Frame, fill: Frame, set: (ratio: number) -> () }

function Kit.gauge(name: string, parent: Instance?, x: number, y: number, w: number, h: number, opts: { back: Color3?, fill: Color3?, anchor: Vector2? }?): GaugeHandle
	local o = opts or {}
	local bg = Instance.new("Frame")
	bg.Name = name
	bg.AnchorPoint = o.anchor or Vector2.new(0, 0)
	bg.Position = UDim2.fromScale(x, y)
	bg.Size = UDim2.fromScale(w, h)
	bg.BackgroundColor3 = o.back or UiTheme.Colors.neutral.dark
	bg.BorderSizePixel = 0
	bg.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0)
	fill.Position = UDim2.fromScale(0, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = o.fill or UiTheme.Colors.power.base
	fill.BorderSizePixel = 0
	fill.Parent = bg
	KitBase.skinImage(bg, "gaugeBack")
	KitBase.skinImage(fill, "gaugeFill")

	return {
		root = bg,
		fill = fill,
		set = function(ratio: number)
			fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		end,
	}
end

-- 토스트 한 줄 ---------------------------------------------------------------------------------------
-- 어두운 바탕(neutral.dark · Skin.alpha.toast) · 흰 글자 외곽선 · 오른쪽 정렬. 글자색(희귀도)은 띄울 때 정한다
function Kit.toastRow(name: string, level: TextScale.Level): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = ""
	label.BorderSizePixel = 0
	KitBase.styleText(label, level)
	label.BackgroundColor3 = UiTheme.Colors.neutral.dark
	label.BackgroundTransparency = UiTheme.Skin.alpha.toast
	label.TextXAlignment = Enum.TextXAlignment.Right
	KitBase.skinImage(label, "toast")
	return label
end

-- 확률 표 한 줄 -------------------------------------------------------------------------------------
-- 왼쪽 이름(nameW) · 오른쪽 확률(오른쪽 정렬). i번째 줄 = 위에서 (i-1)·rowH, 줄 높이는 rowH의 95%(대장간 확률표와 같다)
function Kit.oddsRow(parent: Instance, i: number, rowH: number, nameW: number): (TextLabel, TextLabel)
	local y = (i - 1) * rowH
	local nameL = WindowParts.makeText("Name" .. i, parent, "small", 0, y, nameW, rowH * 0.95)
	local pctL = WindowParts.makeText("Pct" .. i, parent, "small", nameW, y, 1 - nameW, rowH * 0.95, Enum.TextXAlignment.Right)
	return nameL, pctL
end

-- 재화 칸 -----------------------------------------------------------------------------------------
-- 둥근 아이콘(그림 ID가 있으면 그 그림 · 없으면 색 원) + 숫자(ValuePanel). 부모는 가로 목록(UIListLayout)이라고 본다(HUD 코인 칸)
export type ChipHandle = { icon: Frame, value: ValuePanel.ValuePanelHandle }

function Kit.currencyChip(parent: Instance, opts: { color: Color3, iconId: any, level: TextScale.Level, maxChars: number? }): ChipHandle
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.BackgroundColor3 = opts.color
	icon.Size = UDim2.fromScale(1, 0.8)
	icon.LayoutOrder = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = icon
	KitBase.corner(icon, "round")
	icon.Parent = parent
	if AssetSlots.applyImage(icon, opts.iconId) ~= nil then
		icon.BackgroundTransparency = 1 -- 아이콘이 오면 임시 원 대신(#36)
	end
	local value = ValuePanel.create(opts.level, opts.maxChars or ValuePanel.MAX_CHARS_DEFAULT)
	value.label.Name = "Value"
	value.label.AutoLocalize = false
	value.label.Size = UDim2.fromScale(1, 1)
	value.label.LayoutOrder = 2
	value.label.Parent = parent
	return { icon = icon, value = value }
end

-- 모달 판 ----------------------------------------------------------------------------------------
-- 화면 가운데 판(결과 모달 · 일일 보상). 바탕 neutral.dark · 테두리 Skin.line.modal(색 기본 검정). 처음엔 숨김(Visible = false)
function Kit.modalPanel(name: string, parent: Instance?, w: number, h: number, z: number, opts: { lineColor: Color3? }?): (Frame, UIStroke)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(w, h)
	panel.BackgroundColor3 = UiTheme.Colors.neutral.dark
	panel.BorderSizePixel = 0
	panel.ZIndex = z
	panel.Visible = false
	panel.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiTheme.Skin.line.modal
	if opts ~= nil and opts.lineColor ~= nil then
		stroke.Color = opts.lineColor
	end
	stroke.Parent = panel
	KitBase.skinImage(panel, "modal")
	return panel, stroke
end

return Kit

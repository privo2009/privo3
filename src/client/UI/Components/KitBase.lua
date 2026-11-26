--!strict
-- UI 키트 바닥 부품(2026-11-26 지시서 #39). 다른 컴포넌트를 require하지 않는다 — WindowParts · OverlayParts · ValuePanel이 이걸 쓰고,
-- 공개 입구 Components/Kit가 다시 내보낸다(화면 코드는 Kit를 쓴다). 숫자 · 색은 전부 UiTheme.Skin에서 읽는다.
--
--   styleText(label, level)          흰 글자 + 검은 외곽선 + 글꼴 + 글자 크기 상한(docs/UI.md "4. 글자")
--   stroke(parent, color?, px?, mode?)  테두리(UIStroke). px · mode를 안 주면 엔진 기본(1 · Contextual)
--   corner(parent, kind)             둥글기 — kind = Skin.corner 이름("round" · "cell") 또는 UDim
--   box(name, parent, x, y, w, h, z?)  투명 틀(부모 기준 Scale)
--   cardStyle(frame, style)          칸 꾸미기: 바탕색 · 투명도 · 테두리 · 둥글기 · 스킨 그림
--   dim(name, parent, alpha?)        입력을 막는 검은 막(TextButton — 눌러도 아무 일 없음)
--   skinImage(frame, slot)           Skin.images[slot]이 있으면 그 그림(9-slice)을 칸 뒤에 깐다 · 없으면 아무것도 안 한다(지금 모양)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)

local KitBase = {}

function KitBase.styleText(label: TextLabel | TextButton | TextBox, level: TextScale.Level): (UIStroke, UITextSizeConstraint)
	local spec = TextScale.Levels[level]
	assert(spec ~= nil, "Kit.styleText: 알 수 없는 글자 크기 단계: " .. tostring(level))
	label.TextScaled = true
	label.TextColor3 = UiTheme.Skin.text.main
	label.Font = UiTheme.FONT
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = spec.maxTextSize
	size.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiTheme.Skin.text.stroke
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return stroke, size
end

function KitBase.stroke(parent: Instance, color: Color3?, thickness: number?, mode: Enum.ApplyStrokeMode?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or UiTheme.Skin.text.stroke
	if thickness ~= nil then
		s.Thickness = thickness
	end
	if mode ~= nil then
		s.ApplyStrokeMode = mode
	end
	s.Parent = parent
	return s
end

function KitBase.corner(parent: Instance, kind: string | UDim): UICorner
	local radius: UDim
	if typeof(kind) == "UDim" then
		radius = kind :: UDim
	else
		local r = UiTheme.Skin.corner[kind :: string]
		assert(r ~= nil, "Kit.corner: 알 수 없는 둥글기: " .. tostring(kind))
		radius = r
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

function KitBase.box(name: string, parent: Instance?, x: number, y: number, w: number, h: number, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	if z ~= nil then
		f.ZIndex = z
	end
	f.Parent = parent
	return f
end

-- 스킨 그림 칸 이름(Skin.images 키) — 원본은 AssetSlots.KIT_IMAGE_SLOTS(uiList · docs/UI_ASSET_SPEC.md "9"가 같은 목록)
KitBase.IMAGE_SLOTS = require(ReplicatedStorage.Shared.AssetSlots).KIT_IMAGE_SLOTS

function KitBase.skinImage(frame: GuiObject, slot: string): ImageLabel?
	local spec = UiTheme.Skin.images[slot]
	if type(spec) ~= "table" or type(spec.id) ~= "number" then
		return nil
	end
	local img = frame:FindFirstChild("SkinImage") :: ImageLabel?
	if img == nil then
		local l = Instance.new("ImageLabel")
		l.Name = "SkinImage"
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.Size = UDim2.fromScale(1, 1)
		l.ZIndex = frame.ZIndex
		l.Parent = frame
		img = l
	end
	local i = img :: ImageLabel
	i.Image = "rbxassetid://" .. string.format("%d", spec.id)
	if typeof(spec.slice) == "Rect" then
		i.ScaleType = Enum.ScaleType.Slice
		i.SliceCenter = spec.slice
	else
		i.ScaleType = Enum.ScaleType.Stretch
	end
	frame.BackgroundTransparency = 1 -- 그림이 바탕을 대신한다
	return i
end

export type CardStyle = {
	fill: Color3?, -- 바탕색(없으면 바탕을 건드리지 않는다)
	alpha: number?, -- 바탕 투명도(fill과 함께)
	line: number?, -- 테두리 두께(px) — 없으면 테두리 없음
	lineColor: Color3?, -- 테두리 색(기본 검정)
	lineMode: Enum.ApplyStrokeMode?,
	corner: (string | UDim)?,
	image: string?, -- 스킨 그림 칸(Skin.images 키)
}

function KitBase.cardStyle(frame: GuiObject, style: CardStyle): UIStroke?
	if style.fill ~= nil then
		frame.BackgroundColor3 = style.fill
	end
	if style.alpha ~= nil then
		frame.BackgroundTransparency = style.alpha
	end
	if style.corner ~= nil then
		KitBase.corner(frame, style.corner :: any)
	end
	local s: UIStroke? = nil
	if style.line ~= nil then
		s = KitBase.stroke(frame, style.lineColor, style.line, style.lineMode)
	end
	if style.image ~= nil then
		KitBase.skinImage(frame, style.image :: string)
	end
	return s
end

function KitBase.dim(name: string, parent: Instance?, alpha: number?): TextButton
	local dim = Instance.new("TextButton")
	dim.Name = name
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = UiTheme.Skin.fill.shade
	dim.BackgroundTransparency = alpha or UiTheme.Skin.alpha.dim
	dim.BorderSizePixel = 0
	KitBase.skinImage(dim, "dim")
	dim.Parent = parent
	return dim
end

return KitBase

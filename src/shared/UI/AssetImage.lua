--!strict
-- AssetRegistry.resolve() 결과를 실제 Instance로 바꾸는 헬퍼.
-- 클라(화면 UI)와 서버(3D 파트 위 BillboardGui) 양쪽에서 쓰이므로 shared에 둔다.
--
-- 미도착 에셋은 역할 기본색의 Frame으로, 도착한 에셋은 ImageLabel로 나온다.
-- 크기와 위치는 이 헬퍼가 정하지 않는다 — 호출자가 세팅한다.

local AssetRegistry = require(script.Parent.Parent.Config.AssetRegistry)
local UiTheme = require(script.Parent.Parent.Config.UiTheme)

local AssetImage = {}

-- docs/UI.md "8. 비주얼 스타일" — 모든 UI 요소에 검은 테두리 3~4px. 3으로 고정.
local STROKE_THICKNESS = 3

local function addStroke(instance: GuiObject)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = STROKE_THICKNESS
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = instance
end

local function createPlaceholder(placeholderRole: UiTheme.ColorRole): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = UiTheme.Colors[placeholderRole].base
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	addStroke(frame)
	return frame
end

local function createImage(id: string, scaleType: AssetRegistry.ScaleType, slice: Rect?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Image = id
	image.ScaleType = Enum.ScaleType[scaleType]
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0

	if scaleType == "Slice" then
		assert(slice ~= nil, "AssetImage: Slice 에셋인데 AssetConfig에 slice가 없음")
		image.SliceCenter = slice :: Rect
	end

	addStroke(image)
	return image
end

-- resolved: AssetRegistry.resolve()의 반환값. 키를 직접 받지 않는다 —
-- 호출자가 resolve 시점과 Instance 생성 시점을 분리할 수 있게 하기 위해서다.
function AssetImage.create(resolved: AssetRegistry.Resolved): GuiObject
	if resolved.arrived then
		return createImage(resolved.id, resolved.scaleType, resolved.slice)
	end
	return createPlaceholder(resolved.placeholderRole)
end

return AssetImage

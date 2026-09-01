--!strict
-- docs/UI.md "5. 버튼"의 공용 버튼. 9-slice는 AssetImage가 처리하고, 이 파일은
-- 색 6종 · 크기 2종 · 상태 3종(기본/눌림/비활성)만 다룬다.
--
-- ⚠️ 폭은 이 컴포넌트가 정하지 않는다(AssetImage와 같은 원칙) — 버튼마다 라벨
-- 길이가 달라 표준 폭이 없다. 높이만 docs 값(9%/6%, 화면 높이 대비)을 그대로
-- 쓴다. 단 Panel처럼 화면 전체가 아닌 곳에 중첩해서 쓸 때는 호출자가 이미
-- 환산한 값을 heightScale로 직접 넘길 수 있다 (Panel.lua의 X 버튼이 이 경로다).
--
-- ⚠️ 눌림 상태의 "1~2px 아래로"는 docs/UI.md 원문이 이미 px다. CLAUDE.md의 Offset
-- 금지 규칙은 해상도마다 크기가 달라지는 요소(버튼 자체 크기·위치)에 대한 것인데,
-- 이 오프셋은 "눌렸다"는 착시를 주는 고정 폭 그림자 이동이라 화면 크기에 비례할
-- 이유가 없다 — 오히려 Scale로 늘리면 큰 화면에서 과장되고 작은 화면에서 안 보인다.
-- Rect.new SliceCenter · UIStroke.Thickness와 같은 성격의 픽셀 예외로 취급해
-- Position의 Offset 성분에만 쓴다. Size는 여전히 Scale만 쓴다.
--
-- 미도착 에셋(지금 5종)일 때는 AssetImage가 Frame을 반환하므로 눌림·비활성
-- 처리를 BackgroundColor3로, 도착한 에셋(ImageLabel)일 때는 ImageColor3로 한다.
-- 색 자체를 gray로 통째로 바꿔야 하는 비활성 상태는, 인스턴스 타입이 도중에
-- Frame ↔ ImageLabel로 바뀔 수 없다는 제약 때문에 색상용/gray용 두 Visual을
-- 처음부터 같이 만들어 겹쳐 두고 Visible만 토글하는 방식으로 푼다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)

local Button = {}

export type Size = "Big" | "Small"
export type ColorName = "yellow" | "purple" | "blue" | "green" | "red" | "gray"

-- 화면 높이 대비 (docs/UI.md "5. 버튼 > 크기 2종")
Button.HEIGHT_BIG = 0.09
Button.HEIGHT_SMALL = 0.06

-- 눌림 시 아래로 이동하는 픽셀 오프셋 (docs/UI.md "5. 버튼 > 상태 3종은 PNG를 그리지 않는다"
-- 원문 "1~2px"의 중간값).
local PRESS_OFFSET_PIXELS = 2

-- ImageColor3/BackgroundColor3를 어둡게 하는 비율. docs는 "어둡게"라고만 하고 수치를
-- 주지 않아 임의로 정했다 — UiTheme의 밝은→기본→어두운 3단계가 대략 20~30% 폭으로
-- 감쇠하므로(실측), 눌림도 그와 비슷한 "한 단계 어두워진 것"처럼 보이도록 20% 감쇠를
-- 골랐다. 실물 확인 후 조정 가능 (게임 수치가 아니라 시각 튜닝값).
local PRESS_DARKEN_FACTOR = 0.8

local COLOR_TO_ASSET_KEY: { [ColorName]: string } = {
	yellow = "btn_yellow",
	purple = "btn_purple",
	blue = "btn_blue",
	green = "btn_green",
	red = "btn_red",
	gray = "btn_gray",
}

-- 미도착 상태(Frame)일 때 배경색으로 쓸 역할. AssetRegistry의 placeholderRole과
-- 동일해야 이 버튼의 "제 색"과 AssetImage 플레이스홀더 색이 일치한다.
local COLOR_TO_ROLE: { [ColorName]: UiTheme.ColorRole } = {
	yellow = "cashout",
	purple = "advance",
	blue = "blox",
	green = "robux",
	red = "danger",
	gray = "neutral",
}

export type ButtonHandle = {
	root: Frame, -- 호출자가 Position/Parent를 세팅하는 대상
	setPressed: (boolean) -> (),
	setDisabled: (boolean) -> (),
	isPressed: () -> boolean,
	isDisabled: () -> boolean,
}

local function darken(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

-- 미도착(Frame)이면 역할 기본색, 도착(ImageLabel)이면 흰색(원본 그대로 보이는 색)이
-- "눌리지 않은 기본 틴트"다.
local function baseTint(resolved: AssetRegistry.Resolved): Color3
	if resolved.arrived then
		return Color3.new(1, 1, 1)
	end
	return UiTheme.Colors[resolved.placeholderRole].base
end

local function setTint(visual: GuiObject, arrived: boolean, tint: Color3)
	if arrived then
		(visual :: ImageLabel).ImageColor3 = tint
	else
		(visual :: Frame).BackgroundColor3 = tint
	end
end

function Button.create(props: {
	size: Size,
	color: ColorName,
	widthScale: number,
	heightScale: number?,
}): ButtonHandle
	local assetKey = COLOR_TO_ASSET_KEY[props.color]
	assert(assetKey ~= nil, "Button.create: 알 수 없는 색: " .. tostring(props.color))

	local colorResolved = AssetRegistry.resolve(assetKey)
	local grayResolved = AssetRegistry.resolve("btn_gray")

	local height = props.heightScale or (if props.size == "Big" then Button.HEIGHT_BIG else Button.HEIGHT_SMALL)

	local root = Instance.new("Frame")
	root.Name = "Button"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(props.widthScale, height)

	local colorVisual = AssetImage.create(colorResolved)
	colorVisual.Name = "Color"
	colorVisual.Size = UDim2.fromScale(1, 1)
	colorVisual.Parent = root

	local grayVisual = AssetImage.create(grayResolved)
	grayVisual.Name = "Gray"
	grayVisual.Size = UDim2.fromScale(1, 1)
	grayVisual.Visible = false
	grayVisual.Parent = root

	local colorBaseTint = baseTint(colorResolved)
	local grayBaseTint = baseTint(grayResolved)

	local pressed = false
	local disabled = false

	local function refresh()
		colorVisual.Visible = not disabled
		grayVisual.Visible = disabled

		local activeVisual = if disabled then grayVisual else colorVisual
		local activeResolved = if disabled then grayResolved else colorResolved
		local activeBaseTint = if disabled then grayBaseTint else colorBaseTint

		local tint = if pressed then darken(activeBaseTint, PRESS_DARKEN_FACTOR) else activeBaseTint
		setTint(activeVisual, activeResolved.arrived, tint)

		local offset = if pressed then PRESS_OFFSET_PIXELS else 0
		colorVisual.Position = UDim2.new(0, 0, 0, offset)
		grayVisual.Position = UDim2.new(0, 0, 0, offset)
	end

	refresh()

	local function setPressed(value: boolean)
		pressed = value
		refresh()
	end

	local function setDisabled(value: boolean)
		disabled = value
		refresh()
	end

	return {
		root = root,
		setPressed = setPressed,
		setDisabled = setDisabled,
		isPressed = function()
			return pressed
		end,
		isDisabled = function()
			return disabled
		end,
	}
end

return Button

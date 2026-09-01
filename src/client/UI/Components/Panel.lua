--!strict
-- docs/UI.md "6. 패널"의 공용 껍데기. 창을 몇 개 열어도 제목·X 버튼이 항상 같은
-- 자리·크기여야 한다는 것이 이 파일의 존재 이유다 — 개별 화면은 제목·X를 직접
-- 만들 수 없고, 반드시 이 컴포넌트를 통해서만 만든다.
--
-- ⚠️ docs/UI.md의 글자 5단계·버튼 크기 2종은 전부 "화면 높이 대비"다. 그런데 이
-- 패널의 root는 화면 전체가 아니라 60~85%만 차지한다. 화면 기준 비율을 그대로
-- root의 Size.*.Scale로 쓰면 실제로는 그보다 작게(작은 창) 또는 크게(큰 창) 나와서,
-- 크기가 다른 두 창의 제목·X 버튼이 서로 다른 절대 크기로 보인다. 아래
-- heightFractionToRootScale/widthFractionToRootScaleX·Y가 그 보정이다 — "화면
-- 기준 N%"를 "이 root 기준 M%"로 환산해서, 어떤 크기의 창이든 실제 화면 픽셀
-- 기준으로는 항상 같은 크기·같은 위치가 되게 한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Button = require(script.Parent.Button)

local Panel = {}

export type Size = "Small" | "Large"

-- 크기 2종 (docs/UI.md "6. 패널 > 크기 2종")
local SIZES: { [Size]: Vector2 } = {
	Small = Vector2.new(0.60, 0.70),
	Large = Vector2.new(0.85, 0.85),
}

-- 여백 = 화면 폭의 2% (docs/UI.md "6. 패널 > 여백")
local MARGIN_OF_SCREEN_WIDTH = 0.02

-- docs/UI.md "2. 세이프존" 기준 해상도. 폭 기준 값(여백)을 세로 위치로 환산할 때만
-- 쓴다 — 크기 쪽(제목 높이, X 버튼)은 UIAspectRatioConstraint가 실제 픽셀에서
-- 맞추므로 이 상수가 필요 없고, Position에는 그런 장치가 없어 직접 환산한다.
local REFERENCE_ASPECT = 1920 / 1080

export type PanelHandle = {
	root: Frame,
	body: Frame,
	titleLabel: TextLabel,
	closeButton: Button.ButtonHandle,
}

local function heightFractionToRootScale(fraction: number, rootHeight: number): number
	return fraction / rootHeight
end

local function widthFractionToRootScaleX(fraction: number, rootWidth: number): number
	return fraction / rootWidth
end

local function widthFractionToRootScaleY(fraction: number, rootHeight: number): number
	return (fraction * REFERENCE_ASPECT) / rootHeight
end

function Panel.create(size: Size, title: string): PanelHandle
	local dims = SIZES[size]
	assert(dims ~= nil, "Panel.create: 알 수 없는 크기: " .. tostring(size))

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(dims.X, dims.Y)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- 2층 구조: 아래 texture_lego(Tile) 위에 panel_frame(Slice)이 겹친다
	-- (docs/UI.md "6. 패널 > 2층 구조"). 둘 다 미도착이라 지금은 역할색 Frame 두 장이
	-- 겹쳐 보인다.
	local texture = AssetImage.create(AssetRegistry.resolve("texture_lego"))
	texture.Name = "Texture"
	texture.Size = UDim2.fromScale(1, 1)
	texture.ZIndex = 1
	texture.Parent = root

	local frame = AssetImage.create(AssetRegistry.resolve("panel_frame"))
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 2
	frame.Parent = root

	local marginX = widthFractionToRootScaleX(MARGIN_OF_SCREEN_WIDTH, dims.X)
	local marginY = widthFractionToRootScaleY(MARGIN_OF_SCREEN_WIDTH, dims.Y)
	local titleHeight = heightFractionToRootScale(TextScale.Levels.large.heightFraction, dims.Y)
	local closeHeight = heightFractionToRootScale(Button.HEIGHT_SMALL, dims.Y)

	-- 제목: 위쪽 가운데, 대(5%) (docs/UI.md "6. 패널 > 껍데기는 완전히 동일")
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.fromScale(0.5, marginY)
	titleLabel.Size = UDim2.fromScale(1 - marginX * 2, titleHeight)
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.ZIndex = 3

	local titleSizeConstraint = Instance.new("UITextSizeConstraint")
	titleSizeConstraint.MaxTextSize = TextScale.Levels.large.maxTextSize
	titleSizeConstraint.Parent = titleLabel

	-- 외곽선: 흰 글자 + 검은 스트로크 (docs/UI.md "4. 글자 > 외곽선")
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.new(0, 0, 0)
	titleStroke.Parent = titleLabel

	titleLabel.Parent = root

	-- X 버튼: 오른쪽 위 구석, 작은 버튼(6%) (docs/UI.md "6. 패널 > 껍데기는 완전히 동일")
	local closeButton = Button.create({
		size = "Small",
		color = "red",
		widthScale = closeHeight, -- 아래 AspectRatioConstraint가 실제 폭을 덮어쓴다
		heightScale = closeHeight,
	})
	closeButton.root.Name = "Close"
	closeButton.root.AnchorPoint = Vector2.new(1, 0)
	closeButton.root.Position = UDim2.fromScale(1 - marginX, marginY)
	closeButton.root.ZIndex = 3

	-- X 버튼은 정사각형이어야 한다. root의 Y Scale은 화면 기준으로 이미 환산돼
	-- 있으므로, 이 제약은 실제 렌더 픽셀 기준으로 폭을 높이에 맞춰 정사각형을
	-- 만든다 — 패널 크기(Small/Large)에 따라 다시 계산할 필요가 없다.
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.DominantAxis = Enum.DominantAxis.Height
	closeAspect.Parent = closeButton.root

	closeButton.root.Parent = root

	-- 본문: 나머지 전부, 호출자가 채운다 (docs/UI.md "6. 패널 > 껍데기는 완전히 동일")
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromScale(marginX, titleHeight + marginY * 2)
	body.Size = UDim2.fromScale(1 - marginX * 2, 1 - titleHeight - marginY * 3)
	body.ZIndex = 3
	body.Parent = root

	return {
		root = root,
		body = body,
		titleLabel = titleLabel,
		closeButton = closeButton,
	}
end

return Panel

--!strict
-- HUD: 로벅스 상품 구좌 4개 (우측 · 하단). docs/UI.md "1. 화면 목록", "2. 세이프존",
-- "7. 아이콘 > 타일 규격". 어떤 상품 4개인지는 `Shared/Config/ShopSlotConfig`가 정한다.
--
-- ⚠️ 이번 범위는 자리와 표시뿐이다. `MarketplaceService` 호출을 넣지 않는다 — 눌러도
-- 아무 일도 일어나지 않는다(그래서 탭 감지용 버튼도 두지 않는다. MenuRail의
-- HitArea와 달리 지금은 누를 대상이 없다). 소유 상태도 표시하지 않는다 — CLAUDE.md
-- 절대 규칙 5(게임패스 소유 상태 저장 금지)가 매 세션 MarketplaceService로 확인하게
-- 하고, 그 배선은 Phase 8이다. 가격은 ShopSlotConfig(→ ShopConfig) 값을 그대로
-- 보여줄 뿐 실제 결제 가격이 아니다.
--
-- ⚠️ 아이콘. AssetRegistry 17종 중 이 4개 상품에 대응하는 엔트리가 없다(icon_drone은
-- 있지만 "드론 창을 연다"는 메뉴 아이콘이라 "드론 2대 구매"와 의미가 다르다 —
-- 재사용하면 같은 그림이 다른 뜻으로 두 번 쓰여 혼란을 만든다). 그래서 네 구좌
-- 전부 UiTheme "로벅스(초록)" 역할색 Frame으로 그린다. AssetRegistry에 새 엔트리를
-- 추가하지 않는다 — 그건 디자인 담당의 제작 목록을 늘리는 별개의 결정이다.
--
-- ⚠️ UIListLayout/UIGridLayout을 쓰지 않는다. 2행 2열 네 칸을 각각 명시적
-- Position/Size로 배치한다 — 레이아웃 오브젝트는 자식의 Position을 수정하지 않아
-- Position 기반 검증이 전부 (0,0)으로 걸린다(docs/PENDING.md "함정").
--
-- 세로 예산(하단 여백)은 PowerBlock과 같은 원본(Layout.BOTTOM_MARGIN_HEIGHT)을
-- 쓴다 — 두 곳에 따로 계산하면 한쪽만 고쳤을 때 어긋난다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local ShopSlotConfig = require(ReplicatedStorage.Shared.Config.ShopSlotConfig)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)

local ShopSlots = {}

-- 타일 8% 정사각 (docs/UI.md "7. 아이콘 > 타일 규격" — MenuRail.lua의 TILE_HEIGHT와
-- 같은 값이다. 같은 상수를 내보내는 공용 자리가 없어 각자 정의한다. MenuRail도
-- 이 값을 export하지 않으므로 여기서 새로 만드는 것이 기존 관례다).
local TILE_HEIGHT = 0.08

-- 행간 1.5% (U3-6 확정값). 열 간격은 문서에 별도 값이 없어 같은 값을 재사용한다 —
-- 정사각 타일 사이 간격을 가로세로로 다르게 둘 근거가 없다.
local GAP = 0.015

local COLUMNS = 2
local ROWS = 2

-- 세로 합 = 2 * 8% + 1 * 1.5% = 17.5% (docs U3-6 확정값과 일치. 파생값이라 직접 박지 않는다).
local TOTAL_HEIGHT = ROWS * TILE_HEIGHT + (ROWS - 1) * GAP

local PRICE_LEVEL: TextScale.Level = "small" -- 소(2.5%)
-- 가격 라벨은 별도 행이 아니라 타일 하단에 얹힌다 — 세로 예산(17.5%)이 타일+행간
-- 뿐이라 라벨 몫이 없다. 화면 기준(소, 2.5%)을 타일 기준(8%)으로 환산한다
-- (ChallengeInfo/PowerBlock과 같은 환산 패턴).
local PRICE_LABEL_HEIGHT_TILE_REL = TextScale.Levels[PRICE_LEVEL].heightFraction / TILE_HEIGHT

-- docs/UI.md "8. 비주얼 스타일" — 모든 UI 요소에 검은 테두리 3~4px. AssetImage.lua의
-- STROKE_THICKNESS(3)과 같은 값 — 그 헬퍼는 local이라 가져다 쓸 수 없어 재현한다.
local STROKE_THICKNESS = 3

local function createSlot(slot: ShopSlotConfig.Slot, x: number, y: number, cellWidth: number, cellHeight: number): Frame
	local tile = Instance.new("Frame")
	tile.Name = slot.key
	tile.AnchorPoint = Vector2.new(0, 0)
	tile.Position = UDim2.fromScale(x, y)
	tile.Size = UDim2.fromScale(cellWidth, cellHeight)
	tile.BackgroundColor3 = UiTheme.Colors.robux.base
	tile.BorderSizePixel = 0

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = tile

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = STROKE_THICKNESS
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = tile

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.AnchorPoint = Vector2.new(0.5, 1)
	priceLabel.Position = UDim2.fromScale(0.5, 1)
	priceLabel.Size = UDim2.fromScale(1, PRICE_LABEL_HEIGHT_TILE_REL)
	priceLabel.BackgroundTransparency = 1
	priceLabel.BorderSizePixel = 0
	-- 실제 가격은 Phase 8에서 MarketplaceService가 준다. 지금은 Config 값을 그대로 보여준다.
	priceLabel.Text = string.format("%d R$", slot.priceRobux)
	priceLabel.TextScaled = true
	priceLabel.TextColor3 = Color3.new(1, 1, 1)
	priceLabel.Font = Enum.Font.SourceSansBold
	priceLabel.ZIndex = 2
	priceLabel.Parent = tile

	local priceSizeConstraint = Instance.new("UITextSizeConstraint")
	priceSizeConstraint.MaxTextSize = TextScale.Levels[PRICE_LEVEL].maxTextSize
	priceSizeConstraint.Parent = priceLabel

	local priceStroke = Instance.new("UIStroke")
	priceStroke.Color = Color3.new(0, 0, 0)
	priceStroke.Parent = priceLabel

	return tile
end

export type ShopSlotsHandle = {
	root: Frame,
}

function ShopSlots.create(): ShopSlotsHandle
	local rootWidth = Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2 -- 우측 레일, BloxDisplay 좌측 레일과 같은 여백 관례를 미러링

	local root = Instance.new("Frame")
	root.Name = "ShopSlots"
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.fromScale(1 - Layout.EDGE_MARGIN, 1 - Layout.BOTTOM_MARGIN_HEIGHT)
	root.Size = UDim2.fromScale(rootWidth, TOTAL_HEIGHT)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- 2x2 그리드를 UIGridLayout 없이 손으로 계산한다(MenuRail.create의 CellSize/
	-- CellPadding 계산과 같은 산수를 명시적 Position/Size로 옮긴 것 — 파일 상단
	-- "UIListLayout/UIGridLayout을 쓰지 않는다" 참고).
	local gapXScale = GAP / rootWidth
	local gapYScale = GAP / TOTAL_HEIGHT
	local cellWidthScale = (1 - gapXScale) / COLUMNS
	local cellHeightScale = TILE_HEIGHT / TOTAL_HEIGHT

	local slots = ShopSlotConfig.TEMP_SLOTS
	for index, slot in ipairs(slots) do
		local row = math.ceil(index / COLUMNS)
		local col = ((index - 1) % COLUMNS) + 1

		local x = (col - 1) * (cellWidthScale + gapXScale)
		local y = (row - 1) * (cellHeightScale + gapYScale)

		local tile = createSlot(slot, x, y, cellWidthScale, cellHeightScale)
		tile.Parent = root
	end

	return {
		root = root,
	}
end

return ShopSlots

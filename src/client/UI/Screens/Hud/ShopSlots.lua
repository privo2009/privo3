--!strict
-- HUD: 로벅스 상품 구좌 4개 (우측 · 하단). docs/UI.md "1. 화면 목록", "2. 세이프존",
-- "7. 아이콘 > 타일 규격". 어떤 상품 4개인지는 `Shared/Config/ShopSlotConfig`가 정한다.
--
-- 누르면 구매 요청(지시서 #16 — Net/PurchaseClient: 같은 키는 결과까지 한 번만). 프롬프트는 서버가 띄운다 —
-- ID 0이면 서버가 not_registered로 답하고 토스트가 "준비 중"을 띄운다(OverlayBoot). 판정을 클라에 두지 않는다.
-- 보유는 서버 세션 값(Store "shop".gamepasses — 절대 규칙 5)이다. 보유한 구좌는 가격 대신 "보유"를 적는다.
-- 가격은 ShopSlotConfig(→ ShopConfig) 값이다.
--
-- ⚠️ 아이콘. AssetRegistry 아이콘 16종 중 이 4개 상품에 대응하는 엔트리가 없다
-- (메뉴 아이콘을 상품 그림으로 재사용하면 같은 그림이 다른 뜻으로 두 번 쓰여 혼란을
-- 만든다 — 넷째 구좌가 "드론 2대"였을 때 icon_drone을 쓰지 않은 이유). 그래서 네 구좌
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
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local TextService = game:GetService("TextService")
local Layout = require(script.Parent.Parent.Parent.Layout)
local Store = require(script.Parent.Parent.Parent.Store)

local ShopSlots = {}

ShopSlots.OWNED_TEXT = Locale.t("hud.slot.owned")

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

-- 테스트 전용 참조 (PowerBlock.BlockHeight와 같은 성격) — HudLayoutTests가 렌더
-- 결과(AbsoluteSize)를 예산과 대조할 때 매직넘버를 다시 옮겨적지 않기 위해 노출한다.
ShopSlots.TotalHeight = TOTAL_HEIGHT

local PRICE_LEVEL: TextScale.Level = "small" -- 소(2.5%)
-- 가격 라벨은 별도 행이 아니라 타일 하단에 얹힌다 — 세로 예산(17.5%)이 타일+행간
-- 뿐이라 라벨 몫이 없다. 화면 기준(소, 2.5%)을 타일 기준(8%)으로 환산한다
-- (ChallengeInfo/PowerBlock과 같은 환산 패턴).
local PRICE_LABEL_HEIGHT_TILE_REL = TextScale.Levels[PRICE_LEVEL].heightFraction / TILE_HEIGHT

-- docs/UI.md "8. 비주얼 스타일" — 모든 UI 요소에 검은 테두리 3~4px. AssetImage.lua의
-- STROKE_THICKNESS(3)과 같은 값 — 그 헬퍼는 local이라 가져다 쓸 수 없어 재현한다.
local STROKE_THICKNESS = 3

local PRICE_FONT = UiTheme.FONT

-- 가격 표기. 칸에 "199 R$"가 다 들어가면 그대로, 안 들어가면 숫자만(지시서 #7 1단계).
-- 폰에서는 타일이 22px 안팎이라 글자 하한(TextScale.MIN_TEXT_PX)으로 "199 R$"를 찍으면 칸보다 넓다.
-- 하한은 지키고 표기를 줄인다 — 타일 자체가 로벅스(초록) 역할색이라 "R$"가 빠져도 무엇의 값인지 남는다
-- (Claude 판단, 세션 로그).
function ShopSlots.priceText(priceRobux: number, short: boolean): string
	if short then
		return tostring(priceRobux)
	end
	return string.format("%d R$", priceRobux)
end

-- 칸 안 좌우 여유(px). 글자 테두리(UIStroke 1px) 양쪽 몫.
local PRICE_SIDE_PADDING_PX = 2

-- 타일 실제 크기를 보고 가격 줄 높이와 표기를 맞춘다. 줄 높이는 기본 2.5%(타일 기준 환산값)를 쓰되,
-- 그 높이가 글자 하한보다 작으면 하한만큼 키운다(Scale로 다시 쓴다 — Offset 금지).
-- 표기는 네 구좌가 같이 정한다 — 하나라도 긴 꼴이 안 들어가면 전부 짧은 꼴. "3 R$" 옆에 "79"가 서면
-- 서로 다른 단위처럼 읽힌다(2026-10-22 폰 실측에서 섞여 나왔다).
type PriceEntry = { tile: Frame, label: TextLabel, priceRobux: number, owned: boolean }

local function fitPrices(entries: { PriceEntry })
	local first = entries[1]
	if first == nil then
		return
	end
	local tileSize = first.tile.AbsoluteSize -- 네 타일은 같은 크기다(같은 8% 정사각)
	if tileSize.X <= 0 or tileSize.Y <= 0 then
		-- 아직 화면에 안 붙었다 — 문구만 긴 꼴로 맞춘다(크기는 붙은 뒤 AbsoluteSize 신호에서 다시 맞춘다)
		for _, entry in ipairs(entries) do
			entry.label.Text = if entry.owned then ShopSlots.OWNED_TEXT else ShopSlots.priceText(entry.priceRobux, false)
		end
		return
	end
	local heightRel = math.min(1, math.max(PRICE_LABEL_HEIGHT_TILE_REL, TextScale.MIN_TEXT_PX / tileSize.Y))

	-- TextScaled는 폭에 맞춰 줄이다가 하한에서 멈춘다. 그러니 하한 크기로 폭이 들어가면 넘치지 않는다.
	local short = false
	for _, entry in ipairs(entries) do
		local fullWidth = TextService:GetTextSize(
			if entry.owned then ShopSlots.OWNED_TEXT else ShopSlots.priceText(entry.priceRobux, false),
			TextScale.MIN_TEXT_PX,
			PRICE_FONT,
			Vector2.new(math.huge, math.huge)
		).X
		if fullWidth > tileSize.X - PRICE_SIDE_PADDING_PX * 2 then
			short = true
		end
	end
	for _, entry in ipairs(entries) do
		entry.label.Size = UDim2.fromScale(1, heightRel)
		entry.label.Text = if entry.owned then ShopSlots.OWNED_TEXT else ShopSlots.priceText(entry.priceRobux, short)
	end
end

local function createSlot(slot: ShopSlotConfig.Slot, x: number, y: number, cellWidth: number, cellHeight: number): (Frame, TextLabel)
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
	priceLabel.Text = ShopSlots.priceText(slot.priceRobux, false)
	priceLabel.TextScaled = true
	priceLabel.TextColor3 = Color3.new(1, 1, 1)
	priceLabel.Font = PRICE_FONT
	priceLabel.ZIndex = 2
	priceLabel.Parent = tile

	local priceSizeConstraint = Instance.new("UITextSizeConstraint")
	priceSizeConstraint.MaxTextSize = TextScale.Levels[PRICE_LEVEL].maxTextSize
	priceSizeConstraint.Parent = priceLabel

	local priceStroke = Instance.new("UIStroke")
	priceStroke.Color = Color3.new(0, 0, 0)
	priceStroke.Parent = priceLabel

	return tile, priceLabel
end

export type ShopSlotsHandle = {
	root: Frame,
	_debug: {
		press: (key: string) -> (),
	},
}

export type Deps = {
	store: any?, -- Store 인스턴스. 생략하면 싱글톤
	requestPurchase: ((key: string) -> ())?, -- PurchaseClient.request. 생략하면 눌러도 보내지 않는다(표시만 보는 테스트)
}

function ShopSlots.create(deps: Deps?): ShopSlotsHandle
	local d: Deps = deps or {}
	local source: any = d.store or Store
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
	local priceEntries: { PriceEntry } = {}
	for index, slot in ipairs(slots) do
		local row = math.ceil(index / COLUMNS)
		local col = ((index - 1) % COLUMNS) + 1

		local x = (col - 1) * (cellWidthScale + gapXScale)
		local y = (row - 1) * (cellHeightScale + gapYScale)

		local tile, priceLabel = createSlot(slot, x, y, cellWidthScale, cellHeightScale)
		tile.Parent = root
		table.insert(priceEntries, { tile = tile, label = priceLabel, priceRobux = slot.priceRobux, owned = false })

		-- 탭 감지(타일 전체). 판정은 서버 — 여기서는 요청만 보낸다
		local hit = Instance.new("TextButton")
		hit.Name = "HitArea"
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.BorderSizePixel = 0
		hit.Text = ""
		hit.ZIndex = 10
		hit.Parent = tile
		hit.Activated:Connect(function()
			if d.requestPurchase ~= nil then
				d.requestPurchase(slot.key)
			end
		end)
	end

	-- 보유 표시: 서버 세션 값(Store "shop".gamepasses)
	local function readOwned()
		local shop = source.get("shop")
		local owned: { [string]: boolean } = {}
		if type(shop) == "table" and type(shop.gamepasses) == "table" then
			for _, key in ipairs(shop.gamepasses) do
				owned[key] = true
			end
		end
		for i, entry in ipairs(priceEntries) do
			entry.owned = owned[slots[i].key] == true
		end
		fitPrices(priceEntries)
	end
	readOwned()
	source.subscribe("shop", readOwned)

	-- 타일 크기를 본다(root가 아니라) — 정사각 제약이 걸린 타일 쪽이 실제 칸 크기다.
	if priceEntries[1] ~= nil then
		priceEntries[1].tile:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitPrices(priceEntries)
		end)
	end
	fitPrices(priceEntries)

	return {
		root = root,
		_debug = {
			press = function(key: string)
				if d.requestPurchase ~= nil then
					d.requestPurchase(key)
				end
			end,
		},
	}
end

return ShopSlots

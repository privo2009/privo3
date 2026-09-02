--!strict
-- HUD: 메뉴 진입 아이콘 (좌측). docs/UI.md "1. 화면 목록 > 메뉴 진입은 6개다" · "7. 아이콘".
--
-- ⚠️ 처음엔 화면 목록의 9개(상점·환생·드론·설정·아우라·타이틀·펫·워프·월드)를
-- 전부 얹으려 했으나 항목당 타일 8% + 라벨 2.5% = 10.5%, 9개면 94.5%로 좌측
-- 레일에 물리적으로 안 들어갔다(간격 0·BloxDisplay 미고려·기본 UI 인셋 미고려의
-- 최선값). 규격(8%/2.5%)이 아니라 메뉴 구조를 고쳤다 — docs/UI.md "메뉴 진입은
-- 6개다"에서 레일 6개로 확정했고, 타이틀은 아우라 창 안에서, 워프는 월드 창과
-- 합쳐 그 창 안에서 진입한다. 근거를 이 파일에 다시 옮기지 않는다.
--
-- 타일은 전부 미도착 에셋이라 AssetImage가 역할색(중립 회색) Frame을 낸다. 6개가
-- 전부 같은 회색이라 라벨이 유일한 구분 수단이다 — 라벨을 생략하지 않는다
-- (docs "왜 9개가 아닌가"의 "라벨 제거" 대안이 기각된 이유와 같다).
--
-- 타일의 검은 3px 테두리는 AssetImage.create()가 이미 붙여준다(모든 에셋 공통).
-- 안쪽 그림이 타일의 70%를 차지하는 것은 PNG 자체에 15% 여백을 그려 넣는
-- 제작 규격이라(docs "7. 아이콘 > 타일 규격") 코드가 처리할 몫이 없다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local ScreenController = require(script.Parent.Parent.Parent.ScreenController)

local MenuRail = {}

-- 타일 8%, 라벨 소(2.5%) — docs/UI.md "7. 아이콘 > 타일 규격".
local TILE_HEIGHT = 0.08
local LABEL_LEVEL: TextScale.Level = "small"
local LABEL_HEIGHT = TextScale.Levels[LABEL_LEVEL].heightFraction

-- 항목 간 간격(세로·가로 공용). docs에 수치가 없어 임의로 정했다 — 6개로 줄면서 생긴
-- 여유를 가시적인 간격으로 쓴다는 것이 목적이라, 라벨(2.5%)보다 작지만 0은 아닌 값으로
-- 골랐다. 게임 수치가 아니라 시각 튜닝값이다.
local ITEM_GAP = 0.015

-- 열 수 (U3-4C). 1열일 때 타일이 레일 폭의 23%만 쓰고(62px 정사각 타일이 267px
-- 상자 안에 있다), 레일 전체가 화면을 위아래로 가로지르는 얇은 기둥이 됐다
-- (세로 점유 약 75%, docs/UI.md "2. 세이프존 > 하단 띠가 가장 붐빈다"가 지목한
-- 구역과 충돌 여지가 있었다). 메뉴 6개 자체는 그대로다 — docs/UI.md "메뉴 진입은
-- 6개다"가 접근 빈도 근거로 이미 확정한 값이라 자리가 남는다고 되돌리지 않는다.
local COLUMNS = 2

-- 화면 목록의 "메뉴 진입은 6개다" 그대로. 순서는 그 절의 나열 순서를 따른다.
-- screenName은 아직 등록된 창이 하나도 없는 상태의 자리표시자다(아래 tap 처리 참고).
local ITEMS = {
	{ assetKey = "icon_shop", label = "상점", screenName = "Shop" },
	{ assetKey = "icon_rebirth", label = "환생", screenName = "Rebirth" },
	{ assetKey = "icon_drone", label = "드론", screenName = "Drone" },
	{ assetKey = "icon_aura", label = "아우라", screenName = "Aura" },
	{ assetKey = "icon_pet", label = "펫 목록", screenName = "Pet" },
	{ assetKey = "icon_settings", label = "설정", screenName = "Settings" },
}

-- 테스트 전용 참조. 개수·라벨을 테스트에 하드코딩하지 않고 이 목록과 대조하기
-- 위해 노출한다 (AssetRegistry.Entries와 같은 성격).
MenuRail.Items = ITEMS

-- 테스트 전용 참조. 열 수를 테스트에 매직넘버 2로 다시 적지 않기 위해 노출한다
-- (MenuRail.Items와 같은 이유).
MenuRail.Columns = COLUMNS

export type MenuRailHandle = {
	root: Frame,
}

-- 등록되지 않은 이름으로 open()하면 U3-1 설계상 error가 난다(오타/미구현 창을
-- 구분하려는 의도적인 설계 — AssetRegistry.resolve가 등록되지 않은 키에 error를
-- 던지는 것과 같은 판단). 여기서는 그 error를 pcall로 잡아 warn으로 그대로
-- 보여준다 — 삼키지도 않고(메시지가 그대로 출력에 남는다), 클릭 한 번이 클라
-- 전체를 죽이지도 않는다. 창이 아직 하나도 없는 지금 단계에서는 탭할 때마다
-- 이 warn이 뜨는 것이 정상이다.
local function openScreen(screenName: string, label: string)
	local ok, err = pcall(ScreenController.open, screenName)
	if not ok then
		warn(string.format("[MenuRail] '%s'(%s) 창이 아직 없다: %s", label, screenName, tostring(err)))
	end
end

local function createTile(item: { assetKey: string, label: string, screenName: string }, layoutOrder: number): Frame
	local itemHeight = TILE_HEIGHT + LABEL_HEIGHT

	local itemRow = Instance.new("Frame")
	itemRow.Name = item.screenName
	itemRow.LayoutOrder = layoutOrder
	itemRow.BackgroundTransparency = 1
	itemRow.BorderSizePixel = 0
	-- itemRow 자신의 Size/Position은 여기서 정하지 않는다 — MenuRail.create의
	-- UIGridLayout이 CellSize로 직접 관리한다(U3-4C, 2열x3행 전환).

	local itemLayout = Instance.new("UIListLayout")
	itemLayout.FillDirection = Enum.FillDirection.Vertical
	itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemLayout.Parent = itemRow

	local tile = AssetImage.create(AssetRegistry.resolve(item.assetKey))
	tile.Name = "Tile"
	tile.LayoutOrder = 1
	-- X=1 (0이 아니다): 아래 AspectRatioConstraint는 AspectType 기본값 FitWithinMaxSize라
	-- Size가 상자다 — X=0이면 상자 폭 0으로 결과가 0x0이 된다 (BloxDisplay/Icon·Value·
	-- ChallengeInfo/Timer에도 같은 관례가 손으로 반복돼 있다, U3-2 관측).
	tile.Size = UDim2.fromScale(1, TILE_HEIGHT / itemHeight) -- itemRow 기준
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = tile
	tile.Parent = itemRow

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.LayoutOrder = 2
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, LABEL_HEIGHT / itemHeight) -- itemRow 기준
	label.Text = item.label
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.SourceSansBold
	label.Parent = itemRow

	local labelSizeConstraint = Instance.new("UITextSizeConstraint")
	labelSizeConstraint.MaxTextSize = TextScale.Levels[LABEL_LEVEL].maxTextSize
	labelSizeConstraint.Parent = label

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.new(0, 0, 0)
	labelStroke.Parent = label

	-- 탭 감지용 투명 버튼. AssetImage가 내는 Frame/ImageLabel은 버튼 클래스가
	-- 아니라 Activated를 못 받으므로, 타일+라벨 전체를 덮는 투명 TextButton을
	-- 맨 위에 얹는다.
	local hitArea = Instance.new("TextButton")
	hitArea.Name = "HitArea"
	hitArea.Size = UDim2.fromScale(1, 1)
	hitArea.BackgroundTransparency = 1
	hitArea.BorderSizePixel = 0
	hitArea.Text = ""
	hitArea.ZIndex = 10
	hitArea.Parent = itemRow
	hitArea.Activated:Connect(function()
		openScreen(item.screenName, item.label)
	end)

	return itemRow
end

function MenuRail.create(startY: number): MenuRailHandle
	local rows = math.ceil(#ITEMS / COLUMNS)
	local itemHeight = TILE_HEIGHT + LABEL_HEIGHT
	local totalHeight = rows * itemHeight + (rows - 1) * ITEM_GAP
	local rootWidth = Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2

	local root = Instance.new("Frame")
	root.Name = "MenuRail"
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromScale(Layout.EDGE_MARGIN, startY)
	root.Size = UDim2.fromScale(rootWidth, totalHeight)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- UIGridLayout 하나로 2열x3행을 만든다. 행마다 별도 Frame + 가로
	-- UIListLayout을 중첩하는 대안은 기각했다 — 그러면 그 행 Frame들의 Size도
	-- root 기준으로 각각 환산해야 해서(1열일 때 itemRow.Size가 그랬듯) 변환
	-- 단계가 한 겹 늘고, "같은 행은 같은 Y" 보장이 그 Frame들의 높이가 우연히
	-- 같다는 사실에 기댄다. UIGridLayout은 CellSize 하나로 폭·높이를 동시에
	-- 맞춰줘서 그 보장이 구조로 따라온다 — "같은 행의 두 항목이 같은 Y" ·
	-- "1열과 2열의 X가 다르다"가 별도 계산 없이 성립한다.
	--
	-- CellSize/CellPadding은 root 기준 Scale이다(UIGridLayout이 부모 기준으로
	-- 해석한다). 기존 ITEM_GAP(화면 기준 값)을 새 상수 없이 그대로 재사용한다 —
	-- 세로는 기존 1열 배치와 같은 환산(화면 기준 gap ÷ root 기준 totalHeight),
	-- 가로도 같은 방식(화면 기준 gap ÷ root 기준 rootWidth)이다.
	local gapXScale = ITEM_GAP / rootWidth
	local gapYScale = ITEM_GAP / totalHeight
	local cellWidthScale = (1 - gapXScale) / COLUMNS
	local cellHeightScale = itemHeight / totalHeight

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal -- 행 우선: 좌->우, 위->아래
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	gridLayout.CellSize = UDim2.fromScale(cellWidthScale, cellHeightScale)
	gridLayout.CellPadding = UDim2.fromScale(gapXScale, gapYScale)
	gridLayout.Parent = root

	for index, item in ipairs(ITEMS) do
		local itemRow = createTile(item, index)
		-- Size를 여기서 다시 세팅하지 않는다 — UIGridLayout은 UIListLayout과
		-- 달리 자식의 Position뿐 아니라 Size도 CellSize로 직접 관리한다.
		-- 손으로 root-상대 Size를 또 세팅해도 GridLayout이 바로 덮어써서
		-- 죽은 코드가 된다.
		itemRow.Parent = root
	end

	return {
		root = root,
	}
end

return MenuRail

--!strict
-- HUD: 자동 클리커 토글 / 자동 진행 버튼 (우측 레일, 하단 띠 경계 바로 위).
-- docs/UI.md "1. 화면 목록", "7. 아이콘 > 타일 규격".
--
-- ⚠️ **하단 띠에 두지 않는다.** 우측 레일의 Y 0.75(하단 띠 경계) 바로 위에 둔다.
-- 이유 둘:
--   1. 자동 클리커 토글은 계속 누르는 조작이고 바로 아래(하단 띠)는 로벅스 구좌
--      (`ShopSlots`)다. 나란히 두면 손가락 하나 차이로 결제창이 뜬다
--   2. 하단 띠 사용 가능 19.67% 중 `ShopSlots`가 이미 17.5%를 먹어 물리적으로
--      안 들어간다(U3-6 확정값)
--
-- ⚠️ 타일은 `MenuRail.createTile`과 같은 모양(아이콘 + 라벨, 8% 정사각)이라 그
-- 패턴을 그대로 따른다 — `Button.lua`(둥근 버튼 배경 6색)는 쓰지 않는다. 이
-- 자리에 필요한 것은 "타일 아이콘"(docs "7. 아이콘 > 필요 목록"의 icon_autoclick·
-- icon_autoadvance가 정확히 이 용도로 이미 등록돼 있다)이지 버튼 배경이 아니다.
--
-- 토글/잠김 상태 표시는 두 채널을 겹친다(U3-7 정정 — 처음엔 색 하나뿐이었다):
--   1. `UIStroke`(테두리) 색 — 도착 여부와 무관하게 `AssetImage.create`가 항상
--      붙여주므로 안전하다
--   2. 아이콘 자체의 밝기(`ImageColor3`/`BackgroundColor3`) — UiTheme "중립"
--      역할의 3단계 셰이드(light>base>dark)를 그대로 쓴다(새 상수 없음)
-- 색만으로는 색각 이상 사용자(남성 약 8%)에게 안 읽히고, 모바일에서 UIStroke
-- 몇 픽셀의 색 변화도 잘 안 보인다 — 밝기는 그 둘을 보완하는 두 번째 채널이지
-- 색 채널을 대체하지 않는다.
--
-- 아이콘은 도착 여부에 따라 인스턴스 타입이 Frame ↔ ImageLabel로 바뀌므로,
-- 밝기도 색과 같은 이유로 두 프로퍼티(`BackgroundColor3`/`ImageColor3`)를
-- 분기해서 세팅해야 한다 — `Button.lua`의 `setTint`와 같은 분기다(그 함수는
-- local이라 가져다 쓸 수 없어 재현한다).
--
-- ⚠️ UIListLayout은 각 타일 "내부"(아이콘 위 라벨 아래)에만 쓴다 — MenuRail.createTile과
-- 같은 관례이고, 이 안쪽 배치는 테스트가 Position으로 재지 않는다. 두 타일을
-- 나란히 놓는 "바깥" 배치는 명시적 Position/Size다(문서 "함정" 절 — 격자/리스트
-- 레이아웃은 자식 Position을 검증 불가능하게 만든다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)

local AutoTools = {}

-- MenuRail.lua의 TILE_HEIGHT/LABEL_LEVEL/ITEM_GAP과 값이 같다(같은 문서 규격,
-- "7. 아이콘 > 타일 규격") — 그 상수들이 export되지 않아 각자 정의한다(ShopSlots.lua와
-- 같은 사정).
local TILE_HEIGHT = 0.08
local LABEL_LEVEL: TextScale.Level = "small"
local LABEL_HEIGHT = TextScale.Levels[LABEL_LEVEL].heightFraction
local ITEM_HEIGHT = TILE_HEIGHT + LABEL_HEIGHT
local ITEM_GAP = 0.015

local COLUMNS = 2

-- 테스트 전용 참조 (PowerBlock.BlockHeight/ShopSlots.TotalHeight와 같은 성격) —
-- HudLayoutTests가 렌더 결과(AbsoluteSize)를 예산과 대조할 때 매직넘버를 다시
-- 옮겨적지 않기 위해 노출한다.
AutoTools.ItemHeight = ITEM_HEIGHT

-- 토글 ON일 때 아이콘 테두리 색. docs가 토글 상태 색을 정하지 않아 기존 역할 중
-- 하나를 고른 것이다 — "수령·안전(노랑)"은 이미 "확정된·활성화된 선택"이라는
-- 뜻으로 쓰이고 있어(발판) 가장 가까운 기존 의미였다. 새 역할을 만들지 않았다.
local TOGGLE_ON_COLOR = UiTheme.Colors.cashout.base
local TOGGLE_OFF_COLOR = Color3.new(0, 0, 0) -- AssetImage 기본 테두리 색과 동일(무표시 = 꺼짐)

-- 밝기 채널(U3-7). UiTheme "중립" 역할의 기존 3단계 셰이드를 그대로 쓴다 — 새
-- 상수를 만들지 않는다. 순서: 켜짐(light, 가장 밝음) > 꺼짐(base, 기존 기본값과
-- 동일해 시각적으로 안 바뀐다) > 잠김(dark, 가장 어두움). 잠김이 꺼짐보다 더
-- 흐려야 "잠김 > 꺼짐 > 켜짐" 순서가 밝기만으로도 읽힌다.
local ICON_ON_TINT = UiTheme.Colors.neutral.light
local ICON_OFF_TINT = UiTheme.Colors.neutral.base
local ICON_LOCKED_TINT = UiTheme.Colors.neutral.dark

-- 아이콘의 밝기(색조 자체)를 세팅한다. arrived=false(지금 icon_autoclick/
-- icon_autoadvance 둘 다 이 경로다)면 AssetImage가 낸 placeholder Frame의
-- BackgroundColor3를, arrived=true(에셋 도착 후)면 ImageLabel의 ImageColor3를
-- 바꾼다 — 어느 경로든 밝기가 똑같이 먹어야 한다(파일 상단 참고).
local function setIconTint(icon: GuiObject, arrived: boolean, tint: Color3)
	if arrived then
		(icon :: ImageLabel).ImageColor3 = tint
	else
		(icon :: Frame).BackgroundColor3 = tint
	end
end

-- 테스트 전용 통로 — setIconTint의 arrived/미도착 분기를 실제 AssetConfig 등록
-- 여부와 무관하게 직접 검증할 수 있게 한다 (WarpConfig._pure/RebirthConfig._pure와
-- 같은 패턴 — 상태 없는 순수 함수라 인스턴스별 _debug가 아니라 모듈에 바로 둔다).
AutoTools._pure = {
	setIconTint = setIconTint,
}

export type AutoToolsHandle = {
	root: Frame,
	-- 테스트 전용: 실제 탭(HitArea Activated) 없이도 토글 로직을 검증할 수 있게 한다.
	_debug: {
		setAutoClickerEnabled: (boolean) -> (),
		isAutoClickerEnabled: () -> boolean,
	},
}

local function createItem(name: string, assetKey: string, label: string, layoutOrder: number): Frame
	local itemRow = Instance.new("Frame")
	itemRow.Name = name
	itemRow.LayoutOrder = layoutOrder
	itemRow.BackgroundTransparency = 1
	itemRow.BorderSizePixel = 0
	-- Size/Position은 여기서 정하지 않는다 — AutoTools.create가 바깥 2열 배치를 잡는다.

	local itemLayout = Instance.new("UIListLayout")
	itemLayout.FillDirection = Enum.FillDirection.Vertical
	itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemLayout.Parent = itemRow

	local icon = AssetImage.create(AssetRegistry.resolve(assetKey))
	icon.Name = "Icon"
	icon.LayoutOrder = 1
	-- X=1 (0이 아니다): AspectType 기본값 FitWithinMaxSize에서 Size가 상자다 —
	-- X=0이면 상자 폭 0으로 결과가 0x0이 된다(MenuRail/Tile 등과 같은 관례).
	icon.Size = UDim2.fromScale(1, TILE_HEIGHT / ITEM_HEIGHT)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = icon
	icon.Parent = itemRow

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.LayoutOrder = 2
	textLabel.BackgroundTransparency = 1
	textLabel.BorderSizePixel = 0
	textLabel.Size = UDim2.fromScale(1, LABEL_HEIGHT / ITEM_HEIGHT)
	textLabel.Text = label
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.Parent = itemRow

	local labelSizeConstraint = Instance.new("UITextSizeConstraint")
	labelSizeConstraint.MaxTextSize = TextScale.Levels[LABEL_LEVEL].maxTextSize
	labelSizeConstraint.Parent = textLabel

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.new(0, 0, 0)
	labelStroke.Parent = textLabel

	return itemRow
end

function AutoTools.create(): AutoToolsHandle
	local rootWidth = Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2 -- ShopSlots/BloxDisplay와 같은 레일 여백 관례

	local root = Instance.new("Frame")
	root.Name = "AutoTools"
	root.AnchorPoint = Vector2.new(1, 1)
	-- 하단 띠 경계(Y = 1 - Layout.BOTTOM_HEIGHT) 바로 위에 바닥을 고정한다 — 이번
	-- 결정의 핵심(하단 띠에 두지 않는다)이라 HudLayoutTests 검사 6이 이 Y를 고정 검증한다.
	root.Position = UDim2.fromScale(1 - Layout.EDGE_MARGIN, 1 - Layout.BOTTOM_HEIGHT)
	root.Size = UDim2.fromScale(rootWidth, ITEM_HEIGHT)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- 2열을 UIGridLayout/UIListLayout 없이 손으로 배치한다(ShopSlots.create와 같은 이유).
	local gapXScale = ITEM_GAP / rootWidth
	local cellWidthScale = (1 - gapXScale) / COLUMNS

	local autoClickerItem = createItem("AutoClicker", "icon_autoclick", "자동클릭", 1)
	autoClickerItem.AnchorPoint = Vector2.new(0, 0)
	autoClickerItem.Position = UDim2.fromScale(0, 0)
	autoClickerItem.Size = UDim2.fromScale(cellWidthScale, 1)
	autoClickerItem.Parent = root

	local autoAdvanceItem = createItem("AutoAdvance", "icon_autoadvance", "자동진행", 2)
	autoAdvanceItem.AnchorPoint = Vector2.new(0, 0)
	autoAdvanceItem.Position = UDim2.fromScale(cellWidthScale + gapXScale, 0)
	autoAdvanceItem.Size = UDim2.fromScale(cellWidthScale, 1)
	autoAdvanceItem.Parent = root

	-- ===== 자동 클리커 토글 =========================================================
	--
	-- 켜짐/꺼짐 두 상태. 상태는 클라 로컬로만 둔다 — 서버 배선(ClickService 자동
	-- 경로)은 이번에 넣지 않는다.
	local autoClickerIcon = autoClickerItem:FindFirstChild("Icon") :: GuiObject
	local autoClickerStroke = autoClickerIcon:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- AssetImage.create 시점의 도착 여부를 다시 조회한다(같은 키, 순수 함수라
	-- 두 번 불러도 안전하다) — setIconTint가 그 값으로 BackgroundColor3/
	-- ImageColor3 중 어느 프로퍼티를 쓸지 가른다.
	local autoClickerArrived = AssetRegistry.resolve("icon_autoclick").arrived

	local autoClickerEnabled = false

	local function refreshAutoClickerVisual()
		autoClickerStroke.Color = if autoClickerEnabled then TOGGLE_ON_COLOR else TOGGLE_OFF_COLOR
		setIconTint(autoClickerIcon, autoClickerArrived, if autoClickerEnabled then ICON_ON_TINT else ICON_OFF_TINT)
	end
	refreshAutoClickerVisual()

	local function setAutoClickerEnabled(value: boolean)
		autoClickerEnabled = value
		refreshAutoClickerVisual()
	end

	local autoClickerHitArea = Instance.new("TextButton")
	autoClickerHitArea.Name = "HitArea"
	autoClickerHitArea.Size = UDim2.fromScale(1, 1)
	autoClickerHitArea.BackgroundTransparency = 1
	autoClickerHitArea.BorderSizePixel = 0
	autoClickerHitArea.Text = ""
	autoClickerHitArea.ZIndex = 10
	autoClickerHitArea.Parent = autoClickerItem
	autoClickerHitArea.Activated:Connect(function()
		setAutoClickerEnabled(not autoClickerEnabled)
	end)

	-- ===== 자동 진행 버튼 ===========================================================
	--
	-- 미보유 잠김 상태(중립 회색)로 고정 — docs/UI.md "자동 진행 설정 창"이 이미
	-- 정한 동작이다. 창은 열리지 않는다: 이 자리에 HitArea/Activated 배선을
	-- 아예 두지 않는다(눌러도 아무 일도 안 일어나는 것이 곧 "창이 안 열린다"다).
	-- 자동 진행 설정 창 자체는 U7 — 여기서 만들지 않는다.
	--
	-- U3-7: 잠김 밝기를 명시적으로 세팅한다. icon_autoadvance의 placeholderRole이
	-- "neutral"이라 예전엔 아무것도 안 해도 우연히 회색(neutral.base)이 나왔지만,
	-- 그건 "에셋이 아직 없어서"이지 "기능이 잠겨서"가 아니었다 — 에셋이 도착하면
	-- (자동 진행 기능 자체는 U7까지 미구현이므로) 조용히 사라질 신호였다. 이제는
	-- ICON_LOCKED_TINT(neutral.dark)를 도착 여부와 무관하게 항상 세팅해서, 잠김이
	-- 자동클릭 꺼짐(neutral.base)보다 항상 더 어둡다는 것을 보장한다.
	local autoAdvanceIcon = autoAdvanceItem:FindFirstChild("Icon") :: GuiObject
	local autoAdvanceArrived = AssetRegistry.resolve("icon_autoadvance").arrived
	setIconTint(autoAdvanceIcon, autoAdvanceArrived, ICON_LOCKED_TINT)

	return {
		root = root,
		_debug = {
			setAutoClickerEnabled = setAutoClickerEnabled,
			isAutoClickerEnabled = function()
				return autoClickerEnabled
			end,
		},
	}
end

return AutoTools

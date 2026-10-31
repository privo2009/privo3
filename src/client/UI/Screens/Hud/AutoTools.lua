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
-- ⚠️ 타일 "내부"(아이콘 위 라벨 아래)도 명시적 Position이다 — MenuRail.createTile과
-- 같다. 예전에는 내부만 UIListLayout이었는데 자동 클리커의 HitArea(항목 전체 크기)가
-- 그 리스트에 끼어 아이콘·라벨을 항목 높이만큼 아래로 밀었고, 그 아이콘이 ShopSlots와
-- 겹쳤다(2026-10-21 Play 관측, docs/PENDING.md U3-10b). 두 타일을 나란히 놓는 "바깥"
-- 배치도 명시적 Position/Size다(문서 "함정" 절 — 격자/리스트 레이아웃은 자식
-- Position을 검증 불가능하게 만든다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Store = require(script.Parent.Parent.Parent.Store)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local AutoAdvanceWindowLogic = require(script.Parent.Parent.Parent.Logic.AutoAdvanceWindowLogic)

local AutoTools = {}

-- 미보유면 누를 때 요청할 상품 키(지시서 #16 S8 — 자동 클리커 게임패스. OP는 상점 창에서 산다)
AutoTools.PURCHASE_KEY = "autoClicker"
AutoTools.PENDING_TIMEOUT_SEC = 2 -- 토글 결과를 기다리는 최대 시간(업그레이드 상점과 같은 값)

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

-- 자동 진행 상태 줄(지시서 #18 AA13): 자동 도구 바로 위 · 소(2.5%) · 오른쪽 정렬. 켜져 있을 때만 보인다.
-- 폭은 자동 도구 폭 그대로(우측 레일 안 — 중앙 금지 구역 밖). 폰에서 줄 높이가 하한보다 낮으면 하한 + 1px(BoostTimers와 같은 방식)
local STATUS_LEVEL: TextScale.Level = "small"
local STATUS_H = TextScale.Levels[STATUS_LEVEL].heightFraction
local STATUS_GAP = 0.005
AutoTools.StatusHeight = STATUS_H

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
	-- 서버 AutoClickResult 1건(실물은 HudBoot가 채널에서 넘긴다)
	onAutoClickResult: (any) -> (),
	-- 테스트 전용: 실제 탭(HitArea Activated) 없이도 토글 로직을 검증할 수 있게 한다.
	_debug: {
		setAutoClickerEnabled: (boolean) -> (),
		isAutoClickerEnabled: () -> boolean,
		isLocked: () -> boolean,
		press: () -> (),
		-- 자동 진행(지시서 #18)
		pressAdvance: () -> (),
		advanceState: () -> string,
		status: TextLabel,
		advanceStroke: UIStroke,
	},
}

-- 실물 배선(테스트는 가짜를 넘긴다). 생략하면 아무 데도 보내지 않는다(HudLayoutTests 등 표시만 보는 쪽).
export type Deps = {
	store: any?, -- Store 인스턴스. 생략하면 싱글톤
	requestPurchase: ((key: string) -> ())?, -- 미보유일 때 누르면(PurchaseClient.request)
	sendAutoClick: ((on: boolean) -> ())?, -- 보유일 때 누르면(AutoClickRequest)
	-- 자동 진행(지시서 #18): 꺼짐에서 누르면 설정 창 · 켜짐에서 누르면 중지(AutoAdvanceClient.stop)
	openAutoAdvance: (() -> ())?,
	stopAutoAdvance: (() -> ())?,
	now: (() -> number)?,
}

local function createItem(name: string, assetKey: string, label: string, layoutOrder: number): Frame
	local itemRow = Instance.new("Frame")
	itemRow.Name = name
	itemRow.LayoutOrder = layoutOrder
	itemRow.BackgroundTransparency = 1
	itemRow.BorderSizePixel = 0
	-- Size/Position은 여기서 정하지 않는다 — AutoTools.create가 바깥 2열 배치를 잡는다.

	-- 안쪽 배치는 명시적 Position이다 (파일 상단 ⚠️, MenuRail.createTile과 같은 이유).
	local icon = AssetImage.create(AssetRegistry.resolve(assetKey))
	icon.Name = "Icon"
	icon.LayoutOrder = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
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
	textLabel.Position = UDim2.fromScale(0, TILE_HEIGHT / ITEM_HEIGHT) -- 아이콘 바로 아래
	textLabel.Text = label
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.Font = UiTheme.FONT
	textLabel.Parent = itemRow

	local labelSizeConstraint = Instance.new("UITextSizeConstraint")
	labelSizeConstraint.MaxTextSize = TextScale.Levels[LABEL_LEVEL].maxTextSize
	labelSizeConstraint.Parent = textLabel

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.new(0, 0, 0)
	labelStroke.Parent = textLabel

	return itemRow
end

function AutoTools.create(deps: Deps?): AutoToolsHandle
	local d: Deps = deps or {}
	local source: any = d.store or Store
	local now = d.now or os.clock
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

	local autoClickerItem = createItem("AutoClicker", "icon_autoclick", Locale.t("hud.auto.clicker"), 1)
	autoClickerItem.AnchorPoint = Vector2.new(0, 0)
	autoClickerItem.Position = UDim2.fromScale(0, 0)
	autoClickerItem.Size = UDim2.fromScale(cellWidthScale, 1)
	autoClickerItem.Parent = root

	local autoAdvanceItem = createItem("AutoAdvance", "icon_autoadvance", Locale.t("hud.auto.advance"), 2)
	autoAdvanceItem.AnchorPoint = Vector2.new(0, 0)
	autoAdvanceItem.Position = UDim2.fromScale(cellWidthScale + gapXScale, 0)
	autoAdvanceItem.Size = UDim2.fromScale(cellWidthScale, 1)
	autoAdvanceItem.Parent = root

	-- ===== 자동 클리커 토글 (지시서 #16 S8) ================================================
	--
	-- 세 상태: 잠김(미보유 — 중립 어두운 밝기, 자동 진행 버튼과 같은 모습) · 꺼짐 · 켜짐.
	-- 보유 · 켜짐은 서버 값이다(Store "shop" — gamepasses · autoClick, AutoClickResult). 클라는 요청만 보낸다(두 채널 — 요청 · 결과).
	--   잠김에서 누르면 구매 요청(AutoTools.PURCHASE_KEY — ID 0이면 서버가 not_registered → "준비 중" 토스트)
	--   보유에서 누르면 AutoClickRequest{on = 반대}. 결과가 올 때까지(또는 PENDING_TIMEOUT_SEC) 다시 보내지 않는다
	local autoClickerIcon = autoClickerItem:FindFirstChild("Icon") :: GuiObject
	local autoClickerStroke = autoClickerIcon:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- AssetImage.create 시점의 도착 여부를 다시 조회한다(같은 키, 순수 함수라
	-- 두 번 불러도 안전하다) — setIconTint가 그 값으로 BackgroundColor3/
	-- ImageColor3 중 어느 프로퍼티를 쓸지 가른다.
	local autoClickerArrived = AssetRegistry.resolve("icon_autoclick").arrived

	local autoClickerEnabled = false
	local locked = true
	local pendingAt: number? = nil

	local function refreshAutoClickerVisual()
		if locked then
			autoClickerStroke.Color = TOGGLE_OFF_COLOR
			setIconTint(autoClickerIcon, autoClickerArrived, ICON_LOCKED_TINT)
			return
		end
		autoClickerStroke.Color = if autoClickerEnabled then TOGGLE_ON_COLOR else TOGGLE_OFF_COLOR
		setIconTint(autoClickerIcon, autoClickerArrived, if autoClickerEnabled then ICON_ON_TINT else ICON_OFF_TINT)
	end

	-- Store "shop"에서 보유 · 켜짐을 읽는다(서버 값)
	local function readShop()
		local shop = source.get("shop")
		locked = ShopEffectsLogic.autoClickRate(ShopEffectsLogic.fromSummary(shop)) <= 0
		autoClickerEnabled = not locked and type(shop) == "table" and shop.autoClick == true
		refreshAutoClickerVisual()
	end
	readShop()
	source.subscribe("shop", function()
		pendingAt = nil
		readShop()
	end)

	local function setAutoClickerEnabled(value: boolean)
		autoClickerEnabled = value
		refreshAutoClickerVisual()
	end

	local function press()
		if locked then
			if d.requestPurchase ~= nil then
				d.requestPurchase(AutoTools.PURCHASE_KEY)
			end
			return
		end
		local t = now()
		if pendingAt ~= nil and t - (pendingAt :: number) < AutoTools.PENDING_TIMEOUT_SEC then
			return
		end
		pendingAt = t
		if d.sendAutoClick ~= nil then
			d.sendAutoClick(not autoClickerEnabled)
		end
	end

	local function onAutoClickResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		pendingAt = nil
		if type(payload.on) == "boolean" then
			setAutoClickerEnabled(payload.on and not locked)
		end
	end

	local autoClickerHitArea = Instance.new("TextButton")
	autoClickerHitArea.Name = "HitArea"
	autoClickerHitArea.Size = UDim2.fromScale(1, 1)
	autoClickerHitArea.BackgroundTransparency = 1
	autoClickerHitArea.BorderSizePixel = 0
	autoClickerHitArea.Text = ""
	autoClickerHitArea.ZIndex = 10
	autoClickerHitArea.Parent = autoClickerItem
	autoClickerHitArea.Activated:Connect(press)

	-- ===== 자동 진행 버튼 (지시서 #18 AA8 · AA11 · AA13) ===================================
	--
	-- 세 상태 — 자동 클리커와 같은 두 채널(테두리 색 + 아이콘 밝기):
	--   locked(미보유) neutral.dark + 검은 테두리 → 누르면 구매 요청(autoAdvance — 프롬프트는 서버)
	--   off(보유)      neutral.base + 검은 테두리 → 누르면 설정 창
	--   on(켜짐)       neutral.light + 노랑 테두리 → 누르면 중지(자동만 꺼진다 — 런은 남는다)
	-- 상태는 서버 값(Store "shop" 보유 · "autoAdvance" 켜짐). 판정은 AutoAdvanceWindowLogic.hudState.
	local autoAdvanceIcon = autoAdvanceItem:FindFirstChild("Icon") :: GuiObject
	local autoAdvanceStroke = autoAdvanceIcon:FindFirstChildOfClass("UIStroke") :: UIStroke
	local autoAdvanceArrived = AssetRegistry.resolve("icon_autoadvance").arrived
	local advanceState = "locked"

	-- 상태 줄(켜져 있을 때만). 자동 도구 root 위로 붙는다 — TouchSafeLayout이 root를 올리면 같이 올라간다
	local status = Instance.new("TextLabel")
	status.Name = "AutoAdvanceStatus"
	status.AnchorPoint = Vector2.new(1, 1)
	status.Position = UDim2.fromScale(1, -STATUS_GAP / ITEM_HEIGHT)
	status.Size = UDim2.fromScale(1, STATUS_H / ITEM_HEIGHT)
	status.BackgroundTransparency = 1
	status.BorderSizePixel = 0
	status.Text = ""
	status.TextScaled = true
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.TextColor3 = Color3.new(1, 1, 1)
	status.Font = UiTheme.FONT
	status.Visible = false
	status.Parent = root
	local statusSize = Instance.new("UITextSizeConstraint")
	statusSize.MaxTextSize = TextScale.Levels[STATUS_LEVEL].maxTextSize
	statusSize.Parent = status
	local statusStroke = Instance.new("UIStroke")
	statusStroke.Color = Color3.new(0, 0, 0)
	statusStroke.Parent = status

	-- 폰 맞춤(K12 — 레이아웃 먼저): 줄 높이가 하한보다 낮으면 하한 + 1px(화면 높이 기준 — Scale로 다시 쓴다, BoostTimers와 같은 방식).
	-- 그 글자 크기로 한 줄 폭이 칸(자동 도구 폭)보다 길면 두 줄로 감싼다 — 폰 705×338 영어 "Auto · Floor 25 · 999 runs"가 99px 칸을
	-- 넘쳤다(2026-10-31). 글은 그대로 두고 줄을 늘린다(위쪽으로 — 바닥은 자동 도구 윗변에 붙어 있다)
	local function fitStatus()
		local parent = root.Parent
		local screenH = if parent ~= nil and parent:IsA("GuiBase2d") then (parent :: GuiBase2d).AbsoluteSize.Y else 0
		if screenH <= 0 then
			return
		end
		local h = math.max(STATUS_H, (TextScale.MIN_TEXT_PX + 1) / screenH)
		local px = math.min(h * screenH, statusSize.MaxTextSize)
		local need = TextService:GetTextSize(status.Text, px, status.Font, Vector2.new(10000, 10000)).X
		local lines = if status.Text ~= "" and need > status.AbsoluteSize.X - 2 and status.AbsoluteSize.X > 0 then 2 else 1
		status.TextWrapped = lines > 1
		status.Size = UDim2.fromScale(1, h * lines / ITEM_HEIGHT)
	end
	local statusParentConn: RBXScriptConnection? = nil
	root.AncestryChanged:Connect(function()
		if statusParentConn ~= nil then
			statusParentConn:Disconnect()
			statusParentConn = nil
		end
		local parent = root.Parent
		if parent ~= nil and parent:IsA("GuiBase2d") then
			statusParentConn = (parent :: GuiBase2d):GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStatus)
		end
		fitStatus()
	end)

	local function readAdvance()
		local summary = source.get("autoAdvance")
		advanceState = AutoAdvanceWindowLogic.hudState(summary, source.get("shop"))
		if advanceState == "locked" then
			autoAdvanceStroke.Color = TOGGLE_OFF_COLOR
			setIconTint(autoAdvanceIcon, autoAdvanceArrived, ICON_LOCKED_TINT)
		else
			local on = advanceState == "on"
			autoAdvanceStroke.Color = if on then TOGGLE_ON_COLOR else TOGGLE_OFF_COLOR
			setIconTint(autoAdvanceIcon, autoAdvanceArrived, if on then ICON_ON_TINT else ICON_OFF_TINT)
		end
		local text = AutoAdvanceWindowLogic.statusText(summary)
		status.Text = text
		status.Visible = text ~= ""
		fitStatus() -- 글이 바뀌면 한 줄 · 두 줄을 다시 정한다
	end
	readAdvance()
	source.subscribe("shop", readAdvance)
	source.subscribe("autoAdvance", readAdvance)

	local function pressAdvance()
		if advanceState == "locked" then
			if d.requestPurchase ~= nil then
				d.requestPurchase(AutoAdvanceWindowLogic.PURCHASE_KEY)
			end
		elseif advanceState == "off" then
			if d.openAutoAdvance ~= nil then
				d.openAutoAdvance()
			end
		elseif d.stopAutoAdvance ~= nil then
			d.stopAutoAdvance()
		end
	end

	local autoAdvanceHitArea = Instance.new("TextButton")
	autoAdvanceHitArea.Name = "HitArea"
	autoAdvanceHitArea.Size = UDim2.fromScale(1, 1)
	autoAdvanceHitArea.BackgroundTransparency = 1
	autoAdvanceHitArea.BorderSizePixel = 0
	autoAdvanceHitArea.Text = ""
	autoAdvanceHitArea.ZIndex = 10
	autoAdvanceHitArea.Parent = autoAdvanceItem
	autoAdvanceHitArea.Activated:Connect(pressAdvance)

	return {
		root = root,
		onAutoClickResult = onAutoClickResult,
		_debug = {
			setAutoClickerEnabled = setAutoClickerEnabled,
			isAutoClickerEnabled = function()
				return autoClickerEnabled
			end,
			isLocked = function()
				return locked
			end,
			press = press,
			pressAdvance = pressAdvance,
			advanceState = function()
				return advanceState
			end,
			status = status,
			advanceStroke = autoAdvanceStroke,
		},
	}
end

return AutoTools

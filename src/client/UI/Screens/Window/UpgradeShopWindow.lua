--!strict
-- 상점 창 — 업그레이드 / 로벅스 두 탭 (작은 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 6 지시서 #7 U5 · Phase 8 지시서 #16.
-- 메뉴 레일 첫 칸 "상점"(screenName "Shop")이 연다.
--
-- 본문 맨 위 탭 줄: "업그레이드" | "로벅스"(고른 탭 하늘, 나머지 회색 — 아우라 창 팩 탭과 같은 두 벌 방식). 단일 창 안에서 바꾼다.
--   업그레이드 탭  항목 줄(UpgradeConfig.SHOP_ORDER — 7줄, 스크롤 목록). 한 줄 = 이름 · 지금 레벨/최대 · 지금 효과 → 다음 효과 ·
--                 구매 버튼 · 버튼 아래 비용(또는 잠긴 이유). 값 · 문구 · 중복 요청 막기는 UI/Logic/UpgradeShopLogic.
--                 구매 버튼은 블럭스(하늘) — btn_blue. 확인 단계 없음(S8), 결과가 올 때까지 그 줄 버튼을 잠근다.
--                 RobuxSlot(숨김 자리)은 지웠다 — 업그레이드는 로벅스로 팔지 않는다(DESIGN 7장 · 지시서 #16).
--   로벅스 탭     힘 배수 계단 한 줄 + 게임패스(ShopConfig.GAMEPASS_ORDER). 줄 = 이름 · 설명(행운 상품은 확률 변화 숫자) · 버튼 · 가격.
--                 보유 = "보유 중"(회색) · ID 0 = "준비 중"(회색) · 그 밖 = 초록 btn_green + 가격. 제한 유저는 행운 상품 줄을 숨긴다(S13).
--                 값 · 상태 · 문구는 UI/Logic/RobuxShopLogic. 구매 요청은 Net/PurchaseClient(같은 키는 결과까지 한 번만).
-- 이 파일은 그리기와 배선뿐이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local UpgradeShopLogic = require(script.Parent.Parent.Parent.Logic.UpgradeShopLogic)
local RobuxShopLogic = require(script.Parent.Parent.Parent.Logic.RobuxShopLogic)
local PurchaseClient = require(script.Parent.Parent.Parent.Parent.Net.PurchaseClient)

type BigNumber = BigNum.BigNumber

local UpgradeShopWindow = {}

UpgradeShopWindow.TITLE = "상점"
UpgradeShopWindow.SUCCESS_TEXT = "%s Lv %d (-%s)"
UpgradeShopWindow.TAB_UPGRADE = "upgrade"
UpgradeShopWindow.TAB_ROBUX = "robux"
UpgradeShopWindow.TAB_TEXT = { upgrade = "업그레이드", robux = "로벅스" }

-- 본문 안 배치(본문 기준 비율). Claude가 정한 배치값(세션 로그 · docs/UI.md "지시서 #16" 실측).
-- 지시서 #12까지의 기록: 줄 높이 0.15 · 간격 0.004는 폰 줄 안 두 칸이 각각 11px(글자 하한)이 되게 고른 값이다 — 그대로 둔다.
-- 지시서 #16: 맨 위 탭 줄 TAB_H(본문 0.1 — 폰 약 15px, 작은 글자 11px가 들어간다). 목록은 그 아래 LIST_Y부터 LIST_H만큼 보이고
-- 스크롤한다(보이는 줄 수가 5쯤으로 준다 — 줄 높이를 줄이면 11px 하한이 깨진다). 그 아래가 상태 문구.
local TAB_H = 0.1
local TAB_W = 0.49
local TAB_GAP = 0.02
local LIST_Y = TAB_H + 0.01
local ROW_H = 0.15
local ROW_GAP = 0.004
local LIST_H = 0.79 -- 보이는 목록 높이(본문 기준)
local STATUS_Y = LIST_Y + LIST_H + 0.01
local STATUS_H = 1 - STATUS_Y
local SCROLLBAR_PX = 6 -- ScrollBarThickness는 픽셀 정수 속성이라 Scale로 줄 수 없다(docs/UI.md "지시서 #12")
local UPGRADE_ROWS = #UpgradeConfig.SHOP_ORDER
local ROBUX_MAX_ROWS = 1 + #ShopConfig.GAMEPASS_ORDER -- 계단 한 줄 + 게임패스(제한 유저는 이보다 적다 — 남는 줄은 숨긴다)
local function canvasK(rows: number): number
	return math.max(1, (ROW_H + ROW_GAP) * rows / LIST_H)
end
local CANVAS_K = canvasK(UPGRADE_ROWS) -- 업그레이드 목록 캔버스 = 보이는 목록 × 이 값
UpgradeShopWindow.Layout = { ROW_H = ROW_H, LIST_H = LIST_H, LIST_Y = LIST_Y, TAB_H = TAB_H, CANVAS_K = CANVAS_K, canvasK = canvasK }
-- 줄 안(줄 기준 비율)
local LEFT_W = 0.64
local BUTTON_X = 0.68
local BUTTON_W = 0.32
local BUTTON_H = 0.5
local FOOT_Y = 0.5
local FOOT_H = 0.5

export type Deps = {
	store: any?, -- Store 인스턴스. 생략하면 싱글톤
	sendRequest: (name: string) -> (), -- 업그레이드 구매(블럭스)
	purchase: PurchaseClient.Client?, -- 로벅스 구매 요청. 생략하면 실물(PurchaseClient.get)
	onClose: () -> (),
	now: (() -> number)?, -- 테스트용 시계
}

type RowParts = {
	frame: Frame,
	title: TextLabel,
	effect: TextLabel,
	foot: TextLabel,
	button: Button.ButtonHandle,
	buttonLabel: TextLabel,
	hit: TextButton,
}

type TabParts = { button: Button.ButtonHandle, selected: Button.ButtonHandle, label: TextLabel, hit: TextButton }

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	_debug: {
		press: (name: string) -> (),
		pressRobux: (index: number) -> (),
		selectTab: (tab: string) -> (),
		tab: () -> string,
		close: () -> (),
		list: ScrollingFrame,
		robuxList: ScrollingFrame,
		rows: { [string]: RowParts },
		robuxRows: { RowParts },
		tabs: { [string]: TabParts },
		status: TextLabel,
		view: () -> { UpgradeShopLogic.Row },
		robuxView: () -> { RobuxShopLogic.Row },
	},
}

local function makeList(name: string, body: Instance, rows: number): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.Position = UDim2.fromScale(0, LIST_Y)
	list.Size = UDim2.fromScale(1, LIST_H)
	list.CanvasSize = UDim2.fromScale(0, canvasK(rows))
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR_PX
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ZIndex = 3
	list.Parent = body
	return list
end

-- 본문 기준 높이 h → 캔버스 기준 Scale
local function onCanvas(h: number, k: number): number
	return h / LIST_H / k
end

local function makeRow(name: string, list: ScrollingFrame, index: number, k: number, color: Button.ColorName, buttonText: string,
	raise: { Instance }): RowParts
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromScale(0, onCanvas((index - 1) * (ROW_H + ROW_GAP), k))
	-- 오른쪽 끝을 스크롤바 폭만큼 비우지 않는다 — 비우려면 Offset이 필요하다. 스크롤바는 줄 위에 얇게 겹친다
	frame.Size = UDim2.fromScale(1, onCanvas(ROW_H, k))
	-- 줄 바탕: 중립 어두운 단계 — 패널 자리표시(중립 기본)와 구분된다(워프 창 행 경계 결함과 같은 이유)
	frame.BackgroundColor3 = UiTheme.Colors.neutral.dark
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	frame.Parent = list

	local title = WindowParts.makeText("Title", frame, "medium", 0.02, 0, LEFT_W, 0.5)
	local effect = WindowParts.makeText("Effect", frame, "small", 0.02, 0.5, LEFT_W, 0.5)

	local button = Button.create({ size = "Small", color = color, widthScale = BUTTON_W, heightScale = BUTTON_H })
	button.root.Name = "BuyButton"
	button.root.Position = UDim2.fromScale(BUTTON_X, 0)
	button.root.ZIndex = WindowParts.Z_BUTTON
	button.root.Parent = frame
	local buttonLabel, hit = WindowParts.decorateButton(button, buttonText)
	table.insert(raise, button.root)

	local foot = WindowParts.makeText("Foot", frame, "small", BUTTON_X, FOOT_Y, BUTTON_W, FOOT_H, Enum.TextXAlignment.Center)
	return { frame = frame, title = title, effect = effect, foot = foot, button = button, buttonLabel = buttonLabel, hit = hit }
end

function UpgradeShopWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local purchase: PurchaseClient.Client = deps.purchase or PurchaseClient.get()
	local panel = Panel.create("Small", UpgradeShopWindow.TITLE)
	panel.root.Name = "UpgradeShopWindow"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }

	-- 탭 줄(선택 표시는 색 — 고른 탭 하늘 / 나머지 회색. 탭마다 두 벌을 둔다 — 아우라 창 팩 탭과 같은 이유)
	local tabs: { [string]: TabParts } = {}
	for i, tabKey in ipairs({ UpgradeShopWindow.TAB_UPGRADE, UpgradeShopWindow.TAB_ROBUX }) do
		local gray = Button.create({ size = "Small", color = "gray", widthScale = TAB_W, heightScale = TAB_H })
		gray.root.Name = "Tab_" .. tabKey
		gray.root.Position = UDim2.fromScale((i - 1) * (TAB_W + TAB_GAP), 0)
		gray.root.ZIndex = WindowParts.Z_BUTTON
		gray.root.Parent = body
		local selected = Button.create({ size = "Small", color = "blue", widthScale = 1, heightScale = 1 })
		selected.root.Name = "Selected"
		selected.root.Position = UDim2.fromScale(0, 0)
		selected.root.ZIndex = WindowParts.Z_BUTTON
		selected.root.Visible = false
		selected.root.Parent = gray.root
		local label, hit = WindowParts.decorateButton(gray, UpgradeShopWindow.TAB_TEXT[tabKey])
		table.insert(raise, gray.root)
		tabs[tabKey] = { button = gray, selected = selected, label = label, hit = hit }
	end

	-- 업그레이드 탭 목록
	local list = makeList("List", body, UPGRADE_ROWS)
	local rows: { [string]: RowParts } = {}
	for i, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		rows[name] = makeRow("Row_" .. name, list, i, CANVAS_K, "blue", UpgradeShopLogic.BUY_TEXT, raise)
	end

	-- 로벅스 탭 목록(줄은 최대 수만큼 만들고, 그리는 순간의 줄 수만큼 보인다)
	local robuxList = makeList("RobuxList", body, ROBUX_MAX_ROWS)
	robuxList.Visible = false
	local robuxK = canvasK(ROBUX_MAX_ROWS)
	local robuxRows: { RowParts } = {}
	for i = 1, ROBUX_MAX_ROWS do
		robuxRows[i] = makeRow("RobuxRow_" .. i, robuxList, i, robuxK, "green", RobuxShopLogic.BUY_TEXT, raise)
	end

	local status = WindowParts.makeText("Status", body, "small", 0, STATUS_Y, 1, STATUS_H, Enum.TextXAlignment.Center)
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local pending = UpgradeShopLogic.newPending()
	local resultText: string? = nil
	local view: { UpgradeShopLogic.Row } = {}
	local robuxView: { RobuxShopLogic.Row } = {}
	local tab = UpgradeShopWindow.TAB_UPGRADE

	local function render()
		for key, parts in pairs(tabs) do
			parts.selected.root.Visible = key == tab
		end
		list.Visible = tab == UpgradeShopWindow.TAB_UPGRADE
		robuxList.Visible = tab == UpgradeShopWindow.TAB_ROBUX

		view = UpgradeShopLogic.rows(source.get("upgrades"), source.get("blox"))
		local t = now()
		for _, r in ipairs(view) do
			local parts = rows[r.name]
			parts.title.Text = r.title
			parts.effect.Text = r.effectText
			parts.foot.Text = r.footText
			parts.buttonLabel.Text = r.buttonText
			parts.button.setDisabled(not r.canBuy or pending.isPending(r.name, t))
		end

		robuxView = RobuxShopLogic.rows(source.get("shop"), {
			upgrades = source.get("upgrades"),
			auras = source.get("auras"),
			lifetimeBlox = source.get("lifetimeBlox"),
			pets = source.get("pets"),
		})
		for i, parts in ipairs(robuxRows) do
			local r = robuxView[i]
			parts.frame.Visible = r ~= nil
			if r ~= nil then
				parts.title.Text = r.title
				parts.effect.Text = r.detail
				parts.foot.Text = r.footText
				parts.buttonLabel.Text = r.buttonText
				parts.button.setDisabled(not r.canBuy or (r.buyKey ~= nil and purchase.isPending(r.buyKey :: string)))
			end
		end
		-- 캔버스는 지금 줄 수에서 유도한다(제한 유저는 줄이 적다). 줄 위치 · 높이도 그 캔버스 기준으로 다시 잡는다
		local k = canvasK(#robuxView)
		robuxList.CanvasSize = UDim2.fromScale(0, k)
		for i, parts in ipairs(robuxRows) do
			parts.frame.Position = UDim2.fromScale(0, onCanvas((i - 1) * (ROW_H + ROW_GAP), k))
			parts.frame.Size = UDim2.fromScale(1, onCanvas(ROW_H, k))
		end
		status.Text = resultText or ""
	end

	local function rowOf(name: string): UpgradeShopLogic.Row?
		for _, r in ipairs(view) do
			if r.name == name then
				return r
			end
		end
		return nil
	end

	local function press(name: string)
		render() -- 최신 Store 값으로 다시 판정한다
		local r = rowOf(name)
		if r == nil or not r.canBuy then
			return
		end
		if not pending.tryBegin(name, now()) then
			return
		end
		resultText = nil
		deps.sendRequest(name)
		render()
		-- 결과가 안 오면 PENDING_TIMEOUT_SEC 뒤에 버튼을 다시 연다.
		task.delay(UpgradeShopLogic.PENDING_TIMEOUT_SEC + 0.05, render)
	end

	local function pressRobux(index: number)
		render()
		local r = robuxView[index]
		if r == nil or not r.canBuy or r.buyKey == nil then
			return
		end
		if purchase.request(r.buyKey :: string) then
			resultText = nil
			render()
			task.delay(PurchaseClient.PENDING_TIMEOUT_SEC + 0.05, render)
		end
	end

	local function selectTab(key: string)
		if tabs[key] == nil or key == tab then
			return
		end
		tab = key
		resultText = nil
		render()
	end

	local function close()
		resultText = nil
		render()
		deps.onClose()
	end

	local function onResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local name = tostring(payload.name)
		pending.finish(name)
		if payload.ok then
			local cost = if type(payload.cost) == "table" then payload.cost else BigNum.new(0, 0)
			resultText = string.format(UpgradeShopWindow.SUCCESS_TEXT, UpgradeShopLogic.NAMES[name] or name, tonumber(payload.level) or 0, Formatter.format(cost))
		else
			resultText = UpgradeShopLogic.reasonText(tostring(payload.reason))
		end
		render()
	end

	-- 로벅스 구매 결과(프롬프트를 띄웠으면 문구 없음 · 거부 사유 · 구매 완료)
	purchase.onResult(function(payload)
		if tab == UpgradeShopWindow.TAB_ROBUX then
			resultText = RobuxShopLogic.resultText(payload)
		end
		render()
	end)

	for name, parts in pairs(rows) do
		parts.hit.Activated:Connect(function()
			press(name)
		end)
	end
	for i, parts in ipairs(robuxRows) do
		parts.hit.Activated:Connect(function()
			pressRobux(i)
		end)
	end
	for key, parts in pairs(tabs) do
		parts.hit.Activated:Connect(function()
			selectTab(key)
		end)
	end
	closeHit.Activated:Connect(close)
	for _, key in ipairs({ "blox", "upgrades", "shop", "auras", "lifetimeBlox", "pets" }) do
		source.subscribe(key, render)
	end

	render()

	return {
		root = panel.root,
		refresh = render,
		onResult = onResult,
		_debug = {
			press = press,
			pressRobux = pressRobux,
			selectTab = selectTab,
			tab = function()
				return tab
			end,
			close = close,
			list = list,
			robuxList = robuxList,
			rows = rows,
			robuxRows = robuxRows,
			tabs = tabs,
			status = status,
			view = function()
				return view
			end,
			robuxView = function()
				return robuxView
			end,
		},
	}
end

return UpgradeShopWindow

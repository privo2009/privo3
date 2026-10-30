--!strict
-- 환생 창 (작은 창 60% × 70%, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController가 한다).
-- docs/UI.md "1. 화면 목록 > 환생 창 — 반드시 보여야 하는 것". Phase 6 지시서 #5.
--
-- 본문: 보유 블럭스 / 얻는 배수(지금 → 환생 후) / 버려지는 양(빨강 강조) + 상점 안내 · 상점 버튼 / 초기화되는 것 목록 / 남는 것.
-- 상점 버튼은 회색(중립 — 블럭스를 쓰지 않는 이동 버튼이다). 누르면 상점 창이 열리고 이 창은 닫힌다(Window 층 단일 오픈 —
-- ScreenController.open이 열린 창을 닫는다).
-- 값 · 문구 · 확인 단계는 UI/Logic/RebirthWindowLogic(순수)에서 나온다. 이 파일은 그리기와 배선뿐이다.
--
-- 환생 버튼은 블럭스(하늘) 역할 — 블럭스를 쓰는 행동이라서. 1000 미만이면 회색 잠김 + 이유 문구.
-- 확인 단계: 첫 누름은 "한 번 더 누르면 환생"으로 바꿀 뿐이고, 두 번째 누름에만 요청이 나간다.
--
-- ⚠️ 버튼(Components/Button)에는 탭 감지가 없다 — MenuRail처럼 투명 HitArea(TextButton)를 덮는다.
-- 줄 높이 · 자리는 본문(Panel.body) 기준 비율이다. Offset을 쓰지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local RebirthWindowLogic = require(script.Parent.Parent.Parent.Logic.RebirthWindowLogic)

type BigNumber = BigNum.BigNumber

local RebirthWindow = {}

RebirthWindow.TITLE = Locale.t("rebirth.title")
RebirthWindow.BUTTON_TEXT = Locale.t("rebirth.button")
RebirthWindow.CONFIRM_TEXT = Locale.t("rebirth.confirm")
RebirthWindow.CANCEL_TEXT = Locale.t("common.cancel")
function RebirthWindow.successText(gained: BigNumber): string
	return Locale.t("rebirth.success", { gained = Formatter.format(gained) })
end

-- 본문 안 세로 배치(본문 높이 대비). Claude가 정한 배치값(세션 로그).
local ROW_H = 0.09
-- 목록 줄(머리 · 초기화 3줄 · 남는 것) 한 칸. 지시서 #8: 6줄 × 0.045 → 3줄(두 개씩) × 이 값. 폰(Galaxy A06)에서 본문 높이가
-- 152px이라 이 값이 11px — 글자 하한(11px)이 줄 간격을 넘지 않는 가장 작은 값이다(넘으면 윗줄 글자가 아랫줄에 겹친다 — 2026-10-23 실측).
local LIST_STEP = 0.0725
local RESETS_HEADER_Y = 0.385
local ROWS = {
	blox = 0.0,
	gain = 0.10,
	wasted = 0.20,
	shop = 0.30, -- 상점 안내 + 상점 버튼 (지시서 #7)
	resetsHeader = RESETS_HEADER_Y,
	resetsTop = RESETS_HEADER_Y + LIST_STEP,
	resetLine = LIST_STEP,
	keeps = RESETS_HEADER_Y + LIST_STEP * 4,
	status = 0.785,
	button = 0.86,
}
local KEEPS_H = LIST_STEP
local SHOP_H = 0.075
local SHOP_BUTTON_W = 0.3
local BUTTON_H = 0.14
local BUTTON_W = 0.46

local makeText = WindowParts.makeText
local decorateButton = WindowParts.decorateButton

export type Deps = {
	store: any?, -- Store 인스턴스. 생략하면 싱글톤(BloxDisplay.create와 같은 이유)
	sendRequest: () -> (), -- 서버에 환생 요청을 보낸다
	onClose: () -> (),
	openShop: (() -> ())?, -- 상점 창을 연다(지시서 #7). 실물은 ScreenController.open("Shop")
	now: (() -> number)?, -- 테스트용 시계
}

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	_debug: {
		press: () -> (),
		cancel: () -> (),
		close: () -> (),
		openShop: () -> (),
		labels: { [string]: TextLabel },
		button: Button.ButtonHandle,
		cancelButton: Button.ButtonHandle,
		shopButton: Button.ButtonHandle,
	},
}

function RebirthWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local panel = Panel.create("Small", RebirthWindow.TITLE)
	panel.root.Name = "RebirthWindow"
	local body = panel.body

	local labels: { [string]: TextLabel } = {}
	labels.bloxName = makeText("BloxName", body, "medium", 0, ROWS.blox, 0.45, ROW_H)
	labels.bloxName.Text = Locale.t("rebirth.blox")
	labels.bloxValue = makeText("BloxValue", body, "medium", 0.5, ROWS.blox, 0.5, ROW_H, Enum.TextXAlignment.Right)

	labels.gainName = makeText("GainName", body, "medium", 0, ROWS.gain, 0.45, ROW_H)
	labels.gainName.Text = Locale.t("rebirth.gain")
	labels.gainValue = makeText("GainValue", body, "medium", 0.45, ROWS.gain, 0.55, ROW_H, Enum.TextXAlignment.Right)

	-- 버려지는 양: 강조(경고 빨강 배경). 1000 미만 나머지는 환생해도 아무것도 안 된다.
	labels.wastedName = makeText("WastedName", body, "medium", 0, ROWS.wasted, 0.45, ROW_H)
	labels.wastedName.Text = Locale.t("rebirth.wasted")
	labels.wastedValue = makeText("WastedValue", body, "medium", 0.5, ROWS.wasted, 0.5, ROW_H, Enum.TextXAlignment.Right)
	labels.wastedValue.BackgroundColor3 = UiTheme.Colors.danger.base
	labels.wastedValue.BackgroundTransparency = 0

	-- 상점 안내 + 상점으로 가는 버튼 (지시서 #7). 버려지는 양 바로 아래.
	labels.shopHint = makeText("ShopHint", body, "small", 0, ROWS.shop, 1 - SHOP_BUTTON_W - 0.02, SHOP_H)
	labels.shopHint.Text = RebirthWindowLogic.SHOP_HINT
	local shopButton = Button.create({ size = "Small", color = "gray", widthScale = SHOP_BUTTON_W, heightScale = SHOP_H })
	shopButton.root.Name = "ShopButton"
	shopButton.root.AnchorPoint = Vector2.new(1, 0)
	shopButton.root.Position = UDim2.fromScale(1, ROWS.shop)
	shopButton.root.ZIndex = 5
	shopButton.root.Parent = body
	local shopLabel, shopHit = decorateButton(shopButton, RebirthWindowLogic.SHOP_BUTTON_TEXT)
	labels.shopButton = shopLabel

	labels.resetsHeader = makeText("ResetsHeader", body, "small", 0, ROWS.resetsHeader, 1, LIST_STEP)
	labels.resetsHeader.Text = Locale.t("rebirth.resetsHeader")
	for i, text in ipairs(RebirthWindowLogic.resetLines()) do
		local line = makeText("Reset" .. i, body, "small", 0.03, ROWS.resetsTop + (i - 1) * ROWS.resetLine, 0.97, ROWS.resetLine)
		line.Text = text
		labels["reset" .. i] = line
	end
	labels.keeps = makeText("Keeps", body, "small", 0, ROWS.keeps, 1, KEEPS_H)
	labels.keeps.Text = RebirthWindowLogic.KEEPS

	labels.status = makeText("Status", body, "small", 0, ROWS.status, 1, 0.07, Enum.TextXAlignment.Center)

	local button = Button.create({ size = "Big", color = "blue", widthScale = BUTTON_W, heightScale = BUTTON_H })
	button.root.Name = "RebirthButton"
	button.root.Position = UDim2.fromScale(0, ROWS.button)
	button.root.ZIndex = 5
	button.root.Parent = body
	local buttonLabel, buttonHit = decorateButton(button, RebirthWindow.BUTTON_TEXT)
	labels.button = buttonLabel

	local cancelButton = Button.create({ size = "Big", color = "gray", widthScale = BUTTON_W, heightScale = BUTTON_H })
	cancelButton.root.Name = "CancelButton"
	cancelButton.root.AnchorPoint = Vector2.new(1, 0)
	cancelButton.root.Position = UDim2.fromScale(1, ROWS.button)
	cancelButton.root.ZIndex = 5
	cancelButton.root.Visible = false
	cancelButton.root.Parent = body
	local _cancelLabel, cancelHit = decorateButton(cancelButton, RebirthWindow.CANCEL_TEXT)

	local closeHit = WindowParts.hitArea(panel.closeButton.root)

	WindowParts.raiseButtons({ button.root, cancelButton.root, shopButton.root, panel.closeButton.root })

	local confirm = RebirthWindowLogic.newConfirm()
	local view: RebirthWindowLogic.View = RebirthWindowLogic.compute(source.get("blox"), source.get("rebirths"), source.get("shop"))
	local resultText: string? = nil

	local function render()
		labels.bloxValue.Text = Formatter.format(view.blox)
		labels.gainValue.Text = Locale.t("rebirth.gainValue", { gained = Formatter.format(view.gained),
			before = Formatter.format(view.multiplierNow), after = Formatter.format(view.multiplierAfter) })
		labels.wastedValue.Text = Formatter.format(view.wasted)
		labels.wastedValue.BackgroundTransparency = if RebirthWindowLogic.shouldWarnWasted(view.wasted) then 0 else 1

		local armed = confirm.isArmed(now())
		button.setDisabled(not view.canRebirth)
		cancelButton.root.Visible = armed and view.canRebirth
		buttonLabel.Text = if armed and view.canRebirth then RebirthWindow.CONFIRM_TEXT else RebirthWindow.BUTTON_TEXT

		if resultText ~= nil then
			labels.status.Text = resultText
		elseif not view.canRebirth and view.lockReason ~= nil then
			labels.status.Text = RebirthWindowLogic.reasonText(view.lockReason)
		elseif armed then
			labels.status.Text = Locale.t("rebirth.confirmHint")
		else
			labels.status.Text = ""
		end
	end

	local function refresh()
		view = RebirthWindowLogic.compute(source.get("blox"), source.get("rebirths"), source.get("shop"))
		render()
	end

	local function press()
		resultText = nil
		local action = confirm.press(now(), view.canRebirth)
		if action == "send" then
			deps.sendRequest()
			render()
			labels.status.Text = Locale.t("rebirth.sending") -- 서버 RebirthResult가 오면 onResult가 바꾼다
			return
		end
		render()
		if action == "askConfirm" then
			-- 확인 시간이 지나면 처음 모습으로 돌아간다.
			task.delay(RebirthWindowLogic.CONFIRM_WINDOW_SEC + 0.05, function()
				if not confirm.isArmed(now()) then
					render()
				end
			end)
		end
	end

	local function cancel()
		confirm.cancel()
		resultText = nil
		render()
	end

	local function close()
		confirm.cancel()
		resultText = nil
		render()
		deps.onClose()
	end

	-- 상점으로: 확인 중이던 환생은 취소한다(창이 닫히므로 — 돌아오면 처음부터 다시 확인).
	local function openShop()
		confirm.cancel()
		resultText = nil
		render()
		if deps.openShop ~= nil then
			deps.openShop()
		end
	end

	local function onResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		confirm.cancel()
		if payload.ok then
			resultText = RebirthWindow.successText(payload.gained)
		else
			resultText = RebirthWindowLogic.reasonText(tostring(payload.reason))
		end
		refresh()
	end

	buttonHit.Activated:Connect(press)
	cancelHit.Activated:Connect(cancel)
	closeHit.Activated:Connect(close)
	shopHit.Activated:Connect(openShop)
	source.subscribe("blox", refresh)
	source.subscribe("rebirths", refresh)
	source.subscribe("shop", refresh) -- 2배 환생 게임패스(지시서 #16 S6)

	render()

	return {
		root = panel.root,
		refresh = refresh,
		onResult = onResult,
		_debug = {
			press = press,
			cancel = cancel,
			close = close,
			openShop = openShop,
			labels = labels,
			button = button,
			cancelButton = cancelButton,
			shopButton = shopButton,
		},
	}
end

return RebirthWindow

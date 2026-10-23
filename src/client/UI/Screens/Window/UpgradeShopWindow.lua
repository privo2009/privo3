--!strict
-- 상점 창 — 업그레이드 1차 4종 (작은 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 6 지시서 #7 U5.
-- 메뉴 레일 첫 칸 "상점"(screenName "Shop")이 연다.
--
-- 본문: 항목 4줄(UpgradeConfig.SHOP_ORDER). 한 줄 = 이름 · 지금 레벨/최대 · 지금 효과 → 다음 효과 · 구매 버튼 · 버튼 아래 비용(또는 잠긴 이유).
-- 값 · 문구 · 중복 요청 막기는 UI/Logic/UpgradeShopLogic(순수)에서 나온다. 이 파일은 그리기와 배선뿐이다.
--
-- 구매 버튼은 블럭스(하늘) 역할 — btn_blue, 블럭스를 쓰는 행동이라서(UI.md "5. 버튼 > 색 6종").
-- 확인 단계가 없다(S8 — 자주 · 소액으로 반복하는 행동). 대신 요청을 보낸 항목은 결과가 올 때까지 버튼을 잠근다.
-- 최대 레벨이면 회색 "MAX", 블럭스가 모자라면 회색 잠김 + 버튼 아래 사유 문구.
--
-- 로벅스 버튼 자리(S6 — 로벅스 구매는 Phase 8): 줄마다 "RobuxSlot"을 만들어 두고 숨긴다. 붙일 때 Visible만 켜고
-- 구매 버튼 폭을 나눈다(지금은 자리만 — 누를 대상이 없어 HitArea도 없다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local UpgradeShopLogic = require(script.Parent.Parent.Parent.Logic.UpgradeShopLogic)

type BigNumber = BigNum.BigNumber

local UpgradeShopWindow = {}

UpgradeShopWindow.TITLE = "상점"
UpgradeShopWindow.SUCCESS_TEXT = "%s Lv %d (-%s)"

-- 본문 안 배치(본문 기준 비율). Claude가 정한 배치값(세션 로그).
-- 지시서 #10: 칭호 행운이 5번째 줄로 들어와 0.2 → 0.17, 간격 0.02 → 0.01(5줄 0.9 + 상태 문구). 폰 줄 높이에서도 글자 하한 11px.
local ROW_H = 0.17
local ROW_GAP = 0.01
local STATUS_Y = (ROW_H + ROW_GAP) * #UpgradeConfig.SHOP_ORDER + 0.01
local STATUS_H = 1 - STATUS_Y
-- 줄 안(줄 기준 비율)
local LEFT_W = 0.64
local BUTTON_X = 0.68
local BUTTON_W = 0.32
local BUTTON_H = 0.58
local FOOT_Y = 0.6
local FOOT_H = 0.4

export type Deps = {
	store: any?, -- Store 인스턴스. 생략하면 싱글톤
	sendRequest: (name: string) -> (),
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
	robuxSlot: Frame,
}

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	_debug: {
		press: (name: string) -> (),
		close: () -> (),
		rows: { [string]: RowParts },
		status: TextLabel,
		view: () -> { UpgradeShopLogic.Row },
	},
}

function UpgradeShopWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local panel = Panel.create("Small", UpgradeShopWindow.TITLE)
	panel.root.Name = "UpgradeShopWindow"
	local body = panel.body

	local rows: { [string]: RowParts } = {}
	local raise: { Instance } = { panel.closeButton.root }
	for i, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		local frame = Instance.new("Frame")
		frame.Name = "Row_" .. name
		frame.Position = UDim2.fromScale(0, (i - 1) * (ROW_H + ROW_GAP))
		frame.Size = UDim2.fromScale(1, ROW_H)
		-- 줄 바탕: 중립 어두운 단계 — 패널 자리표시(중립 기본)와 구분된다(워프 창 행 경계 결함과 같은 이유)
		frame.BackgroundColor3 = UiTheme.Colors.neutral.dark
		frame.BackgroundTransparency = 0
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = body

		local title = WindowParts.makeText("Title", frame, "medium", 0.02, 0.03, LEFT_W, 0.5)
		local effect = WindowParts.makeText("Effect", frame, "small", 0.02, 0.54, LEFT_W, 0.44)

		local button = Button.create({ size = "Small", color = "blue", widthScale = BUTTON_W, heightScale = BUTTON_H })
		button.root.Name = "BuyButton"
		button.root.Position = UDim2.fromScale(BUTTON_X, 0.02)
		button.root.ZIndex = WindowParts.Z_BUTTON
		button.root.Parent = frame
		local buttonLabel, hit = WindowParts.decorateButton(button, UpgradeShopLogic.BUY_TEXT)
		table.insert(raise, button.root)

		local foot = WindowParts.makeText("Foot", frame, "small", BUTTON_X, FOOT_Y, BUTTON_W, FOOT_H, Enum.TextXAlignment.Center)

		-- S6: 로벅스 버튼 자리(숨김). Phase 8에서 Visible을 켜고 구매 버튼 폭을 나눈다.
		local robuxSlot = Instance.new("Frame")
		robuxSlot.Name = "RobuxSlot"
		robuxSlot.Position = UDim2.fromScale(BUTTON_X, 0.02)
		robuxSlot.Size = UDim2.fromScale(BUTTON_W / 2, BUTTON_H)
		robuxSlot.BackgroundColor3 = UiTheme.Colors.robux.base
		robuxSlot.BorderSizePixel = 0
		robuxSlot.Visible = false
		robuxSlot.Parent = frame

		rows[name] = {
			frame = frame,
			title = title,
			effect = effect,
			foot = foot,
			button = button,
			buttonLabel = buttonLabel,
			hit = hit,
			robuxSlot = robuxSlot,
		}
	end

	local status = WindowParts.makeText("Status", body, "small", 0, STATUS_Y, 1, STATUS_H, Enum.TextXAlignment.Center)
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local pending = UpgradeShopLogic.newPending()
	local resultText: string? = nil
	local view: { UpgradeShopLogic.Row } = {}

	local function render()
		view = UpgradeShopLogic.rows(source.get("upgrades"), source.get("blox"), source.get("strength"))
		local t = now()
		for _, r in ipairs(view) do
			local parts = rows[r.name]
			parts.title.Text = r.title
			parts.effect.Text = r.effectText
			parts.foot.Text = r.footText
			parts.buttonLabel.Text = r.buttonText
			parts.button.setDisabled(not r.canBuy or pending.isPending(r.name, t))
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

	for name, parts in pairs(rows) do
		parts.hit.Activated:Connect(function()
			press(name)
		end)
	end
	closeHit.Activated:Connect(close)
	source.subscribe("blox", render)
	source.subscribe("upgrades", render)
	source.subscribe("strength", render) -- 이동 속도 "최대 속도 도달"이 힘에 따라 바뀐다(지시서 #8)

	render()

	return {
		root = panel.root,
		refresh = render,
		onResult = onResult,
		_debug = {
			press = press,
			close = close,
			rows = rows,
			status = status,
			view = function()
				return view
			end,
		},
	}
end

return UpgradeShopWindow

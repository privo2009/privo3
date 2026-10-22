--!strict
-- 월드·워프 창 (작은 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 6 지시서 #6.
-- 메뉴 레일 셋째 칸 "워프"(screenName "Warp")가 연다.
--
-- 위: 현재 월드(지금은 월드 1뿐 — 월드 전환은 만들지 않는다). 본문: 층 목록 한 쪽(WarpWindowLogic.PAGE_SIZE개)
-- — 층 번호 · 워프 비용(WarpConfig.cost) · 갈 수 있는지. 목록을 눌러 층을 고르고, 아래 워프 버튼으로 간다.
-- 목록이 길어(25층) 쪽을 나눈다 — ScrollingFrame · UIListLayout을 쓰지 않는다(Position 기반 검증 함정,
-- docs/PENDING.md "함정").
--
-- 워프 버튼은 진행(보라) 역할 — UI.md "5. 버튼 > 색 6종"의 "진행 선택, 워프 구매". 블럭스를 쓰는 동작이라
-- 확인 단계(ConfirmFlow — 환생 창과 같은 방식)를 둔다. 못 가면(블럭스 부족 · 런 중 W1) 회색 잠김 + 이유 문구.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local WarpWindowLogic = require(script.Parent.Parent.Parent.Logic.WarpWindowLogic)

type BigNumber = BigNum.BigNumber

local WarpWindow = {}

WarpWindow.TITLE = "월드 · 워프"
WarpWindow.WORLD_TEXT = "월드 1" -- 월드가 하나뿐이다(월드 전환 기능 없음 — 지시서 #6)
WarpWindow.BUTTON_TEXT = "워프"
WarpWindow.CONFIRM_TEXT = "한 번 더 누르면 워프"
WarpWindow.CANCEL_TEXT = "취소"
WarpWindow.SUCCESS_TEXT = "%d층으로 워프했어요 (-%s)"

-- 본문 안 세로 배치(본문 높이 대비). Claude가 정한 배치값(세션 로그).
local WORLD_Y, WORLD_H = 0.0, 0.08
local LIST_TOP = 0.10
local ROW_H = 0.095
local ROW_GAP = 0.01
local PAGER_Y = LIST_TOP + (ROW_H + ROW_GAP) * WarpWindowLogic.PAGE_SIZE + 0.005
local PAGER_H = 0.08
local STATUS_Y = PAGER_Y + PAGER_H + 0.01
local STATUS_H = 0.07
local BUTTON_Y = STATUS_Y + STATUS_H + 0.01
local BUTTON_H = 1 - BUTTON_Y
local BUTTON_W = 0.46

export type Deps = {
	store: any?,
	sendRequest: (stage: number) -> (),
	onClose: () -> (),
	now: (() -> number)?,
}

export type Handle = {
	root: Frame,
	refresh: () -> (),
	setRunActive: (boolean) -> (),
	onResult: (any) -> (),
	onOpen: () -> (),
	_debug: {
		press: () -> (),
		cancel: () -> (),
		close: () -> (),
		select: (number) -> (),
		nextPage: () -> (),
		prevPage: () -> (),
		state: () -> { page: number, selected: number, runActive: boolean },
		rowLabels: { TextLabel },
		labels: { [string]: TextLabel },
		button: Button.ButtonHandle,
		cancelButton: Button.ButtonHandle,
	},
}

function WarpWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local panel = Panel.create("Small", WarpWindow.TITLE)
	panel.root.Name = "WarpWindow"
	local body = panel.body

	local labels: { [string]: TextLabel } = {}
	labels.world = WindowParts.makeText("World", body, "medium", 0, WORLD_Y, 1, WORLD_H, Enum.TextXAlignment.Center)
	labels.world.Text = WarpWindow.WORLD_TEXT

	-- 층 행: 배경으로 선택 · 가능 여부를 보인다(선택 = 진행 보라, 갈 수 있음 = 중립 밝음, 못 감 = 중립 어두움).
	local rowLabels: { TextLabel } = {}
	local rowHits: { TextButton } = {}
	for i = 1, WarpWindowLogic.PAGE_SIZE do
		local y = LIST_TOP + (i - 1) * (ROW_H + ROW_GAP)
		local row = WindowParts.makeText("Row" .. i, body, "small", 0, y, 1, ROW_H)
		row.BackgroundTransparency = 0
		table.insert(rowLabels, row)
		table.insert(rowHits, WindowParts.hitArea(row))
	end

	local prevButton = Button.create({ size = "Small", color = "gray", widthScale = 0.18, heightScale = PAGER_H })
	prevButton.root.Name = "PrevPage"
	prevButton.root.Position = UDim2.fromScale(0, PAGER_Y)
	prevButton.root.ZIndex = WindowParts.Z_BUTTON
	prevButton.root.Parent = body
	local _prevLabel, prevHit = WindowParts.decorateButton(prevButton, "◀")

	local nextButton = Button.create({ size = "Small", color = "gray", widthScale = 0.18, heightScale = PAGER_H })
	nextButton.root.Name = "NextPage"
	nextButton.root.AnchorPoint = Vector2.new(1, 0)
	nextButton.root.Position = UDim2.fromScale(1, PAGER_Y)
	nextButton.root.ZIndex = WindowParts.Z_BUTTON
	nextButton.root.Parent = body
	local _nextLabel, nextHit = WindowParts.decorateButton(nextButton, "▶")

	labels.page = WindowParts.makeText("Page", body, "small", 0.2, PAGER_Y, 0.6, PAGER_H, Enum.TextXAlignment.Center)
	labels.status = WindowParts.makeText("Status", body, "small", 0, STATUS_Y, 1, STATUS_H, Enum.TextXAlignment.Center)

	local button = Button.create({ size = "Big", color = "purple", widthScale = BUTTON_W, heightScale = BUTTON_H })
	button.root.Name = "WarpButton"
	button.root.Position = UDim2.fromScale(0, BUTTON_Y)
	button.root.ZIndex = WindowParts.Z_BUTTON
	button.root.Parent = body
	local buttonLabel, buttonHit = WindowParts.decorateButton(button, WarpWindow.BUTTON_TEXT)
	labels.button = buttonLabel

	local cancelButton = Button.create({ size = "Big", color = "gray", widthScale = BUTTON_W, heightScale = BUTTON_H })
	cancelButton.root.Name = "CancelButton"
	cancelButton.root.AnchorPoint = Vector2.new(1, 0)
	cancelButton.root.Position = UDim2.fromScale(1, BUTTON_Y)
	cancelButton.root.ZIndex = WindowParts.Z_BUTTON
	cancelButton.root.Visible = false
	cancelButton.root.Parent = body
	local _cancelLabel, cancelHit = WindowParts.decorateButton(cancelButton, WarpWindow.CANCEL_TEXT)

	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons({ button.root, cancelButton.root, prevButton.root, nextButton.root, panel.closeButton.root })

	local confirm = WarpWindowLogic.newConfirm()
	local runActive = false
	local selected = WarpWindowLogic.defaultStage(source.get("blox"))
	local page = WarpWindowLogic.pageOf(selected)
	local resultText: string? = nil

	local function selectedRow(): WarpWindowLogic.Row
		return WarpWindowLogic.row(selected, source.get("blox"), runActive)
	end

	local function render()
		local blox = source.get("blox")
		local rows = WarpWindowLogic.rows(page, blox, runActive)
		for i, label in ipairs(rowLabels) do
			local r = rows[i]
			if r == nil then
				label.Visible = false
			else
				label.Visible = true
				label.Text = string.format("  %d층   %s 블럭스   %s", r.stage, Formatter.format(r.cost), if r.canWarp then "갈 수 있음" else "—")
				if r.stage == selected then
					label.BackgroundColor3 = UiTheme.Colors.advance.base
				elseif r.canWarp then
					label.BackgroundColor3 = UiTheme.Colors.neutral.base
				else
					label.BackgroundColor3 = UiTheme.Colors.neutral.dark
				end
			end
		end
		labels.page.Text = string.format("%d / %d", page, WarpWindowLogic.pageCount())

		local sel = selectedRow()
		local armed = confirm.isArmed(now()) and sel.canWarp
		button.setDisabled(not sel.canWarp)
		cancelButton.root.Visible = armed
		buttonLabel.Text = if armed then WarpWindow.CONFIRM_TEXT else string.format("%s (%d층)", WarpWindow.BUTTON_TEXT, selected)

		if resultText ~= nil then
			labels.status.Text = resultText
		elseif not sel.canWarp and sel.reason ~= nil then
			labels.status.Text = WarpWindowLogic.reasonText(sel.reason)
		elseif armed then
			labels.status.Text = string.format("%s 블럭스를 써요. 확인하면 한 번 더 누르세요", Formatter.format(sel.cost))
		else
			labels.status.Text = ""
		end
	end

	local function select(stage: number)
		if stage ~= selected then
			confirm.cancel()
		end
		selected = stage
		resultText = nil
		render()
	end

	local function setPage(p: number)
		page = math.clamp(p, 1, WarpWindowLogic.pageCount())
		render()
	end

	local function press()
		resultText = nil
		local action = confirm.press(now(), selectedRow().canWarp)
		if action == "send" then
			deps.sendRequest(selected)
			render()
			labels.status.Text = "워프하는 중..." -- 서버 WarpResult가 오면 onResult가 바꾼다
			return
		end
		render()
		if action == "askConfirm" then
			task.delay(WarpWindowLogic.CONFIRM_WINDOW_SEC + 0.05, function()
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

	local function onResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		confirm.cancel()
		if payload.ok then
			resultText = string.format(WarpWindow.SUCCESS_TEXT, payload.stage, Formatter.format(payload.cost))
		else
			resultText = WarpWindowLogic.reasonText(tostring(payload.reason))
		end
		render()
	end

	-- 창을 열 때: 지금 갈 수 있는 가장 높은 층을 고르고 그 쪽을 보인다.
	local function onOpen()
		confirm.cancel()
		resultText = nil
		selected = WarpWindowLogic.defaultStage(source.get("blox"))
		page = WarpWindowLogic.pageOf(selected)
		render()
	end

	for i, hit in ipairs(rowHits) do
		hit.Activated:Connect(function()
			local stage = (page - 1) * WarpWindowLogic.PAGE_SIZE + i
			if stage <= WarpWindowLogic.lastStage() then
				select(stage)
			end
		end)
	end
	prevHit.Activated:Connect(function()
		setPage(page - 1)
	end)
	nextHit.Activated:Connect(function()
		setPage(page + 1)
	end)
	buttonHit.Activated:Connect(press)
	cancelHit.Activated:Connect(cancel)
	closeHit.Activated:Connect(close)
	source.subscribe("blox", render)

	render()

	return {
		root = panel.root,
		refresh = render,
		setRunActive = function(value: boolean)
			if runActive ~= value then
				runActive = value
				if value then
					confirm.cancel()
				end
				render()
			end
		end,
		onResult = onResult,
		onOpen = onOpen,
		_debug = {
			press = press,
			cancel = cancel,
			close = close,
			select = select,
			nextPage = function()
				setPage(page + 1)
			end,
			prevPage = function()
				setPage(page - 1)
			end,
			state = function()
				return { page = page, selected = selected, runActive = runActive }
			end,
			rowLabels = rowLabels,
			labels = labels,
			button = button,
			cancelButton = cancelButton,
		},
	}
end

return WarpWindow

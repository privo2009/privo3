--!strict
-- 자동 진행 설정 창 (작은 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 8 지시서 #18.
-- HUD 자동 진행 버튼(보유 · 꺼짐)이 연다(screenName "AutoAdvance"). docs/UI.md "지시서 #18".
--
-- 위에서부터: 안전층(서버 값 그대로 — AA5) · 안내 두 줄(목표층 자동 수령 · 반복 / 부스트가 끝나면 달라질 수 있음) ·
-- "목표층" · [−] N층 [+](1 ~ 그 월드 층 수, 기본 = 안전층 — AA6) · 시작 버튼(AA7 — 안전 노랑 / 도박 보라, 글자도 다르다) · 상태 문구.
-- 시작 버튼은 색마다 한 벌씩 두고 하나만 보인다(버튼 색을 바꾸려면 그림을 다시 만들어야 해서 — 아우라 창 팩 탭과 같은 방식).
-- 값 · 문구는 UI/Logic/AutoAdvanceWindowLogic(순수). 요청은 Net/AutoAdvanceClient(결과까지 한 번만). 시작이 받아들여지면 창을 닫는다.

local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local AutoAdvanceWindowLogic = require(script.Parent.Parent.Parent.Logic.AutoAdvanceWindowLogic)
local AutoAdvanceClient = require(script.Parent.Parent.Parent.Parent.Net.AutoAdvanceClient)

local AutoAdvanceWindow = {}

-- 본문 기준 배치(Claude가 정한 값 — docs/UI.md "지시서 #18" 실측)
local SAFE_Y, SAFE_H = 0, 0.14
local NOTE1_Y, NOTE2_Y, NOTE_H = 0.16, 0.25, 0.08
local LABEL_Y, LABEL_H = 0.35, 0.08
local ROW_Y, ROW_H = 0.45, 0.15
local STEP_W = 0.15
local MINUS_X, VALUE_X, VALUE_W, PLUS_X = 0.18, 0.35, 0.3, 0.67
local START_X, START_Y, START_W, START_H = 0.15, 0.65, 0.7, 0.17
local STATUS_Y, STATUS_H = 0.85, 0.13
AutoAdvanceWindow.Layout = { ROW_Y = ROW_Y, START_Y = START_Y, STATUS_Y = STATUS_Y }

export type Deps = {
	store: any?,
	client: AutoAdvanceClient.Client?, -- 생략하면 실물(AutoAdvanceClient.get)
	onClose: () -> (),
}

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onOpen: () -> (),
	_debug: {
		pressMinus: () -> (),
		pressPlus: () -> (),
		pressStart: () -> (),
		view: () -> AutoAdvanceWindowLogic.View,
		safe: TextLabel,
		value: TextLabel,
		status: TextLabel,
		startSafe: Button.ButtonHandle,
		startRisky: Button.ButtonHandle,
		startSafeLabel: TextLabel,
		startRiskyLabel: TextLabel,
		minus: Button.ButtonHandle,
		plus: Button.ButtonHandle,
	},
}

function AutoAdvanceWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local client: AutoAdvanceClient.Client = deps.client or AutoAdvanceClient.get()
	local panel = Panel.create("Small", AutoAdvanceWindowLogic.TITLE)
	panel.root.Name = "AutoAdvanceWindow"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }

	local function makeButton(name: string, color: Button.ColorName, x: number, y: number, w: number, h: number, text: string)
		local b = Button.create({ size = "Small", color = color, widthScale = w, heightScale = h })
		b.root.Name = name
		b.root.Position = UDim2.fromScale(x, y)
		b.root.ZIndex = WindowParts.Z_BUTTON
		b.root.Parent = body
		local label, hit = WindowParts.decorateButton(b, text)
		table.insert(raise, b.root)
		return b, label, hit
	end

	local safe = WindowParts.makeText("Safe", body, "medium", 0, SAFE_Y, 1, SAFE_H, Enum.TextXAlignment.Center)
	local note1 = WindowParts.makeText("NoteRepeat", body, "small", 0, NOTE1_Y, 1, NOTE_H, Enum.TextXAlignment.Center)
	note1.Text = AutoAdvanceWindowLogic.NOTE_REPEAT
	local note2 = WindowParts.makeText("NoteBoost", body, "small", 0, NOTE2_Y, 1, NOTE_H, Enum.TextXAlignment.Center)
	note2.Text = AutoAdvanceWindowLogic.NOTE_BOOST
	local label = WindowParts.makeText("TargetLabel", body, "small", 0, LABEL_Y, 1, LABEL_H, Enum.TextXAlignment.Center)
	label.Text = AutoAdvanceWindowLogic.TARGET_LABEL
	local minus, _minusLabel, minusHit = makeButton("Minus", "gray", MINUS_X, ROW_Y, STEP_W, ROW_H, "-")
	local value = WindowParts.makeText("Value", body, "medium", VALUE_X, ROW_Y, VALUE_W, ROW_H, Enum.TextXAlignment.Center)
	local plus, _plusLabel, plusHit = makeButton("Plus", "gray", PLUS_X, ROW_Y, STEP_W, ROW_H, "+")
	local startSafe, startSafeLabel, startSafeHit = makeButton("StartSafe", "yellow", START_X, START_Y, START_W, START_H, "")
	local startRisky, startRiskyLabel, startRiskyHit = makeButton("StartRisky", "purple", START_X, START_Y, START_W, START_H, "")
	local status = WindowParts.makeText("Status", body, "small", 0, STATUS_Y, 1, STATUS_H, Enum.TextXAlignment.Center)
	status.TextWrapped = true

	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local chosen: number? = nil -- 사람이 고른 목표층(창을 열 때마다 기본값 = 안전층으로 돌아간다)
	local resultText: string? = nil
	local current: AutoAdvanceWindowLogic.View = AutoAdvanceWindowLogic.view(source.get("autoAdvance"), nil)

	local function render()
		current = AutoAdvanceWindowLogic.view(source.get("autoAdvance"), chosen)
		safe.Text = current.safeText
		value.Text = current.targetText
		minus.setDisabled(not current.canMinus)
		plus.setDisabled(not current.canPlus)
		local isSafe = current.kind == "safe"
		startSafe.root.Visible = isSafe
		startRisky.root.Visible = not isSafe
		startSafeLabel.Text = current.startText
		startRiskyLabel.Text = current.startText
		startSafe.setDisabled(client.isPending())
		startRisky.setDisabled(client.isPending())
		status.Text = resultText or ""
	end

	local function step(delta: number)
		render()
		chosen = current.target + delta
		resultText = nil
		render()
	end

	local function pressStart()
		render()
		if client.start(current.target) then
			resultText = nil
			render()
			task.delay(AutoAdvanceClient.PENDING_TIMEOUT_SEC + 0.05, render)
		end
	end

	client.onResult(function(payload)
		if type(payload) == "table" and payload.action == "start" then
			if payload.ok then
				resultText = nil
				render()
				deps.onClose() -- 켜졌다 — 창을 닫는다(HUD 상태 줄이 보인다)
				return
			end
			resultText = AutoAdvanceWindowLogic.resultText(payload)
		end
		render()
	end)

	minusHit.Activated:Connect(function()
		step(-1)
	end)
	plusHit.Activated:Connect(function()
		step(1)
	end)
	startSafeHit.Activated:Connect(pressStart)
	startRiskyHit.Activated:Connect(pressStart)
	closeHit.Activated:Connect(function()
		deps.onClose()
	end)
	source.subscribe("autoAdvance", render)

	local function onOpen()
		chosen = nil
		resultText = nil
		render()
	end

	render()

	return {
		root = panel.root,
		refresh = render,
		onOpen = onOpen,
		_debug = {
			pressMinus = function()
				step(-1)
			end,
			pressPlus = function()
				step(1)
			end,
			pressStart = pressStart,
			view = function()
				return current
			end,
			safe = safe,
			value = value,
			status = status,
			startSafe = startSafe,
			startRisky = startRisky,
			startSafeLabel = startSafeLabel,
			startRiskyLabel = startRiskyLabel,
			minus = minus,
			plus = plus,
		},
	}
end

return AutoAdvanceWindow

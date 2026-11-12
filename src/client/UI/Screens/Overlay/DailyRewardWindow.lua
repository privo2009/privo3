--!strict
-- 일일 보상 창 (OverlayGui 차단층 — 큐 3번, 지시서 #20 D1 ~ D5). 자동 등장 · HUD 아이콘 둘 다 이 창 하나를 차단층 큐로 연다(OverlayBoot).
-- 값 · 문구는 UI/Logic/DailyRewardWindowLogic(서버 PlayerState daily · DailyRewardConfig), 받기는 DailyRequest("claim")를 한 번만 보낸다.
--
-- 화면 전체를 덮는 반투명 막(차단층 — 결과 모달과 같은 예외로 가운데 판) + 판: 제목(대) · 7칸(4 + 3줄) · 다음 보상까지 · 상태 문구 ·
-- 받기(수령 · 안전 노랑) · 닫기(회색). 칸: "n일" · 보상 이름 · 양(받은 칸은 "받음"). 오늘 칸은 노랑 테두리, 받은 칸은 어두운 바탕 · 회색 글자,
-- 펫 칸은 이름이 희귀도 색(리미티드 tier6). 배치값은 Claude가 정했다(docs/UI.md "지시서 #20").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local DailyRewardWindowLogic = require(script.Parent.Parent.Parent.Logic.DailyRewardWindowLogic)
local OverlayParts = require(script.Parent.OverlayParts)
local Fx = require(script.Parent.Parent.Parent.Components.Fx)

local DailyRewardWindow = {}

DailyRewardWindow.PANEL_W = 0.62
DailyRewardWindow.PANEL_H = 0.74
local CELL_W, CELL_H, CELL_GAP = 0.22, 0.25, 0.02
local ROW_Y = { 0.15, 0.42 }
local TIMER_Y, STATUS_Y, TEXT_H = 0.69, 0.765, 0.07
local BUTTON_Y, BUTTON_H = 0.85, 0.12

local Z = OverlayParts.Z.blocking

export type Deps = {
	store: any?,
	sendClaim: () -> (),
	now: (() -> number)?,
}

type CellParts = { frame: Frame, stroke: UIStroke, day: TextLabel, name: TextLabel, amount: TextLabel }

export type Handle = {
	root: Frame,
	show: () -> (),
	hide: () -> (),
	isShown: () -> boolean,
	onClose: (() -> ()) -> (),
	onResult: (any) -> (),
	refresh: () -> (),
	_debug: { cells: { CellParts }, claimHit: TextButton, closeHit: TextButton, claimLabel: TextLabel, timer: TextLabel, status: TextLabel,
		panel: Frame, press: () -> (), sent: () -> number },
}

local function setZ(root: Instance, z: number)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("GuiObject") then
			obj.ZIndex = z
		end
	end
	if root:IsA("GuiObject") then
		root.ZIndex = z
	end
end

function DailyRewardWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock

	local root = Instance.new("Frame")
	root.Name = "DailyRewardWindow"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = Z
	-- root는 늘 보이는 투명 틀이다(결과 모달과 같은 이유). 막과 판을 Visible로.
	local dim = Instance.new("TextButton") -- 입력을 막는 막(누르면 아무 일도 없다 — "닫기"로만 닫는다)
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.ZIndex = Z
	dim.Visible = false
	dim.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(DailyRewardWindow.PANEL_W, DailyRewardWindow.PANEL_H)
	panel.BackgroundColor3 = UiTheme.Colors.neutral.dark
	panel.BorderSizePixel = 0
	panel.ZIndex = Z + 1
	panel.Visible = false
	panel.Parent = root
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 4
	panelStroke.Color = UiTheme.Colors.cashout.base
	panelStroke.Parent = panel

	local function text(name: string, parent: Instance, level: any, x: number, y: number, w: number, h: number): TextLabel
		local l = WindowParts.makeText(name, parent, level, x, y, w, h, Enum.TextXAlignment.Center)
		l.ZIndex = Z + 3
		return l
	end
	text("Title", panel, "large", 0.05, 0.03, 0.9, 0.1).Text = Locale.t("daily.title")

	local cells: { CellParts } = {}
	for day = 1, 7 do
		local row = if day <= 4 then 1 else 2
		local col = if row == 1 then day - 1 else day - 5
		local rowCount = if row == 1 then 4 else 3
		local rowWidth = rowCount * CELL_W + (rowCount - 1) * CELL_GAP
		local x = (1 - rowWidth) / 2 + col * (CELL_W + CELL_GAP)
		local frame = Instance.new("Frame")
		frame.Name = "Day" .. day
		frame.Position = UDim2.fromScale(x, ROW_Y[row])
		frame.Size = UDim2.fromScale(CELL_W, CELL_H)
		frame.BackgroundColor3 = UiTheme.Colors.neutral.base
		frame.BorderSizePixel = 0
		frame.ZIndex = Z + 2
		frame.Parent = panel
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = frame
		cells[day] = {
			frame = frame,
			stroke = stroke,
			day = text("DayLabel", frame, "small", 0.04, 0.04, 0.92, 0.28),
			name = text("Name", frame, "small", 0.04, 0.36, 0.92, 0.3),
			amount = text("Amount", frame, "small", 0.04, 0.68, 0.92, 0.28),
		}
	end

	local timer = text("Timer", panel, "small", 0.05, TIMER_Y, 0.9, TEXT_H)
	local status = text("Status", panel, "small", 0.05, STATUS_Y, 0.9, TEXT_H)

	local claim = Button.create({ size = "Small", color = "yellow", widthScale = 0.45, heightScale = BUTTON_H })
	claim.root.Name = "Claim"
	claim.root.Position = UDim2.fromScale(0.08, BUTTON_Y)
	claim.root.Parent = panel
	local claimLabel, claimHit = WindowParts.decorateButton(claim, Locale.t("daily.claim"))
	setZ(claim.root, Z + 3)
	claimLabel.ZIndex = Z + 4
	claimHit.ZIndex = Z + 5

	local close = Button.create({ size = "Small", color = "gray", widthScale = 0.3, heightScale = BUTTON_H })
	close.root.Name = "Close"
	close.root.Position = UDim2.fromScale(0.62, BUTTON_Y)
	close.root.Parent = panel
	local closeLabel, closeHit = WindowParts.decorateButton(close, Locale.t("daily.close"))
	setZ(close.root, Z + 3)
	closeLabel.ZIndex = Z + 4
	closeHit.ZIndex = Z + 5

	local shown = false
	local pendingUntil = 0
	local resultText: string? = nil
	local sentCount = 0
	local closeListeners: { () -> () } = {}

	local function render()
		local daily = source.get("daily")
		for i, c in ipairs(DailyRewardWindowLogic.cells(daily, source.get("maxStage"))) do
			local parts = cells[i]
			parts.day.Text = c.dayText
			parts.name.Text = c.name
			parts.amount.Text = c.amount
			local claimed = c.state == "claimed"
			parts.frame.BackgroundColor3 = if claimed then UiTheme.Colors.neutral.dark else UiTheme.Colors.neutral.base
			parts.stroke.Color = if c.state == "today" then UiTheme.Colors.cashout.base else Color3.new(0, 0, 0)
			parts.stroke.Thickness = if c.state == "today" then 4 else 2
			local textColor = if claimed then UiTheme.Colors.neutral.light else Color3.new(1, 1, 1)
			parts.day.TextColor3 = textColor
			parts.amount.TextColor3 = if c.isPet and not claimed then UiTheme.rarityColor(c.rarityTier) else textColor
			parts.name.TextColor3 = if c.isPet then UiTheme.rarityColor(c.rarityTier) else textColor
		end
		local b = DailyRewardWindowLogic.button(daily, now() < pendingUntil)
		claimLabel.Text = b.text
		claim.setDisabled(not b.enabled)
		timer.Text = DailyRewardWindowLogic.timerText(daily, now())
		status.Text = resultText or ""
	end

	local function press()
		local b = DailyRewardWindowLogic.button(source.get("daily"), now() < pendingUntil)
		if not b.enabled then
			return
		end
		pendingUntil = now() + DailyRewardWindowLogic.PENDING_TIMEOUT_SEC
		resultText = nil
		sentCount += 1
		deps.sendClaim()
		render()
		task.delay(DailyRewardWindowLogic.PENDING_TIMEOUT_SEC + 0.05, function()
			if shown then
				render()
			end
		end)
	end

	claimHit.Activated:Connect(press)
	closeHit.Activated:Connect(function()
		for _, f in ipairs(closeListeners) do
			f()
		end
	end)
	source.subscribe("daily", function()
		if shown then
			render()
		end
	end)
	source.subscribe("maxStage", function()
		if shown then
			render()
		end
	end)
	-- 남은 시간 글자는 1초에 한 번만 다시 쓴다(보일 때만)
	local lastTick = 0
	RunService.Heartbeat:Connect(function()
		if shown and now() - lastTick >= 1 then
			lastTick = now()
			timer.Text = DailyRewardWindowLogic.timerText(source.get("daily"), now())
		end
	end)

	local function show()
		if not shown then
			Fx.modalIn(panel, nil) -- 등장 연출(지시서 #25 U2 — 희귀도 없음: 보통 튀기)
		end
		shown = true
		resultText = nil
		dim.Visible = true
		panel.Visible = true
		render()
	end
	local function hide()
		Fx.modalOut(panel)
		shown = false
		dim.Visible = false
		panel.Visible = false
	end

	return {
		root = root,
		show = show,
		hide = hide,
		isShown = function()
			return shown
		end,
		onClose = function(f: () -> ())
			table.insert(closeListeners, f)
		end,
		onResult = function(payload: any)
			pendingUntil = 0
			resultText = DailyRewardWindowLogic.resultText(payload)
			if shown then
				render()
			end
		end,
		refresh = render,
		_debug = { cells = cells, claimHit = claimHit, closeHit = closeHit, claimLabel = claimLabel, timer = timer, status = status, panel = panel,
			press = press, sent = function()
				return sentCount
			end },
	}
end

return DailyRewardWindow

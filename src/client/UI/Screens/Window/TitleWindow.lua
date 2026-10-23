--!strict
-- 타이틀(칭호) 창 (작은 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 7 지시서 #10.
-- 메뉴 레일 넷째 칸이 연다 — 아우라 창이 생길 때(#11)까지 임시로 "칭호"(screenName "Title"). docs/UI.md "메뉴 진입은 6개다".
--
-- 본문: 칭호 6줄(희귀도 높은 순) — 이름(희귀도 색) · "힘·블럭스 ×N" · 현재 확률(행운 반영) · 보유/미보유 · 장착 버튼.
-- 아래: "1회 뽑기 (10 블럭스)"(하늘 btn_blue — 블럭스를 쓰는 행동) · 자동 뽑기 토글 · 자동 뽑기 비용 안내 · 상태 문구.
-- 값 · 문구 · 중복 요청 막기는 UI/Logic/TitleWindowLogic(순수)에서 나온다. 이 파일은 그리기와 배선뿐이다.
--
-- 확인 단계는 없다(소액 반복 — 상점 S8과 같다). 요청을 보낸 버튼은 결과가 올 때까지 잠근다.
-- 자동 뽑기 토글은 자동 도구(AutoTools)와 같은 두 채널로 켜짐을 보인다: 테두리 색(켜짐 = 수령 · 안전 노랑 / 꺼짐 = 검정) +
-- 글자 밝기(켜짐 = 중립 밝음 / 꺼짐 = 중립 기본). 색만으로는 색각 이상 사용자에게 안 읽힌다(AutoTools 상단).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local TitleWindowLogic = require(script.Parent.Parent.Parent.Logic.TitleWindowLogic)

local TitleWindow = {}

-- 본문 안 배치(본문 기준 비율). Claude가 정한 배치값(docs/UI.md "지시서 #10" 절).
local ROW_H = 0.095
local ROW_GAP = 0.008
local ROWS_H = 6 * ROW_H + 5 * ROW_GAP -- 0.61
local CONTROL_Y = ROWS_H + 0.02
local CONTROL_H = 0.15
local NOTE_Y = CONTROL_Y + CONTROL_H + 0.01
local NOTE_H = 0.07
local STATUS_Y = NOTE_Y + NOTE_H + 0.005
local STATUS_H = 1 - STATUS_Y
-- 줄 안 칸(줄 기준 비율)
local COL = {
	name = { x = 0.02, w = 0.21 },
	mult = { x = 0.24, w = 0.28 },
	chance = { x = 0.53, w = 0.16 },
	status = { x = 0.70, w = 0.11 },
	button = { x = 0.82, w = 0.17 },
}
-- 아래 조작부(본문 기준)
local ROLL_X, ROLL_W = 0, 0.49
local AUTO_X, AUTO_W = 0.51, 0.49
TitleWindow.Layout = { ROW_H = ROW_H, ROWS_H = ROWS_H, CONTROL_Y = CONTROL_Y, STATUS_Y = STATUS_Y }

local TOGGLE_ON_STROKE = UiTheme.Colors.cashout.base
local TOGGLE_OFF_STROKE = Color3.new(0, 0, 0)
local TOGGLE_ON_TEXT = UiTheme.Colors.neutral.light
local TOGGLE_OFF_TEXT = UiTheme.Colors.neutral.base

export type Deps = {
	store: any?, -- Store 인스턴스. 생략하면 싱글톤
	sendRequest: (payload: { action: string, titleId: string?, on: boolean? }) -> (),
	onClose: () -> (),
	now: (() -> number)?, -- 테스트용 시계
}

type RowParts = {
	frame: Frame,
	name: TextLabel,
	mult: TextLabel,
	chance: TextLabel,
	status: TextLabel,
	button: Button.ButtonHandle,
	buttonLabel: TextLabel,
	hit: TextButton,
}

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	_debug: {
		pressRoll: () -> (),
		pressAuto: () -> (),
		pressEquip: (id: string) -> (),
		rows: { RowParts }, -- 화면 위에서부터
		view: () -> { TitleWindowLogic.Row },
		rollButton: Button.ButtonHandle,
		rollFoot: TextLabel,
		autoButton: Button.ButtonHandle,
		autoLabel: TextLabel,
		autoStroke: UIStroke,
		note: TextLabel,
		status: TextLabel,
	},
}

function TitleWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local panel = Panel.create("Small", TitleWindowLogic.TITLE)
	panel.root.Name = "TitleWindow"
	local body = panel.body

	local raise: { Instance } = { panel.closeButton.root }
	local rows: { RowParts } = {}
	for i = 1, 6 do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. i
		frame.Position = UDim2.fromScale(0, (i - 1) * (ROW_H + ROW_GAP))
		frame.Size = UDim2.fromScale(1, ROW_H)
		frame.BackgroundColor3 = UiTheme.Colors.neutral.dark -- 상점 줄과 같은 이유(패널 자리표시와 경계)
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = body

		local name = WindowParts.makeText("Name", frame, "medium", COL.name.x, 0.05, COL.name.w, 0.9)
		local mult = WindowParts.makeText("Mult", frame, "small", COL.mult.x, 0.1, COL.mult.w, 0.8)
		local chance = WindowParts.makeText("Chance", frame, "small", COL.chance.x, 0.1, COL.chance.w, 0.8, Enum.TextXAlignment.Right)
		local status = WindowParts.makeText("Status", frame, "small", COL.status.x, 0.1, COL.status.w, 0.8, Enum.TextXAlignment.Center)

		local button = Button.create({ size = "Small", color = "blue", widthScale = COL.button.w, heightScale = 0.86 })
		button.root.Name = "EquipButton"
		button.root.Position = UDim2.fromScale(COL.button.x, 0.07)
		button.root.ZIndex = WindowParts.Z_BUTTON
		button.root.Parent = frame
		local buttonLabel, hit = WindowParts.decorateButton(button, TitleWindowLogic.EQUIP_TEXT)
		table.insert(raise, button.root)

		rows[i] = { frame = frame, name = name, mult = mult, chance = chance, status = status, button = button, buttonLabel = buttonLabel, hit = hit }
	end

	-- 1회 뽑기
	local rollButton = Button.create({ size = "Small", color = "blue", widthScale = ROLL_W, heightScale = CONTROL_H })
	rollButton.root.Name = "RollButton"
	rollButton.root.Position = UDim2.fromScale(ROLL_X, CONTROL_Y)
	rollButton.root.ZIndex = WindowParts.Z_BUTTON
	rollButton.root.Parent = body
	local _rollLabel, rollHit = WindowParts.decorateButton(rollButton, TitleWindowLogic.rollButtonText())
	table.insert(raise, rollButton.root)

	-- 자동 뽑기 토글 (회색 바탕 + 두 채널)
	local autoButton = Button.create({ size = "Small", color = "gray", widthScale = AUTO_W, heightScale = CONTROL_H })
	autoButton.root.Name = "AutoButton"
	autoButton.root.Position = UDim2.fromScale(AUTO_X, CONTROL_Y)
	autoButton.root.ZIndex = WindowParts.Z_BUTTON
	autoButton.root.Parent = body
	local autoLabel, autoHit = WindowParts.decorateButton(autoButton, TitleWindowLogic.autoText(false))
	-- 테두리 채널은 버튼 그림(AssetImage)이 이미 가진 UIStroke의 색을 바꾼다 — 따로 얹으면 그림 테두리에 가려진다
	-- (2026-10-24 Play 캡처: 켜도 검정으로 보였다). 자동 도구(AutoTools)도 같은 방식이다.
	local autoStrokes: { UIStroke } = {}
	for _, obj in ipairs(autoButton.root:GetDescendants()) do
		if obj:IsA("UIStroke") and obj.Parent ~= autoLabel then
			table.insert(autoStrokes, obj)
		end
	end
	local autoStroke = autoStrokes[1]
	table.insert(raise, autoButton.root)

	local rollFoot = WindowParts.makeText("RollFoot", body, "small", ROLL_X, NOTE_Y, ROLL_W, NOTE_H, Enum.TextXAlignment.Center)
	local note = WindowParts.makeText("AutoNote", body, "small", AUTO_X, NOTE_Y, AUTO_W, NOTE_H, Enum.TextXAlignment.Center)
	note.Text = TitleWindowLogic.autoNoteText()
	local status = WindowParts.makeText("Status", body, "small", 0, STATUS_Y, 1, STATUS_H, Enum.TextXAlignment.Center)

	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local pending = TitleWindowLogic.newPending()
	-- 롤 결과가 오면 서버 롤 시계(TitleConfig.ROLL_INTERVAL_SEC)가 지날 때까지 버튼을 더 잠가 둔다 —
	-- 바로 다시 누르면 서버가 rate_limited로 거부하고 "새 칭호" 문구를 덮는다(2026-10-24 Play 실측).
	local rollCooldownUntil = -math.huge
	local resultText: string? = nil
	local view: { TitleWindowLogic.Row } = {}

	local function autoOn(): boolean
		local t = source.get("titles")
		return type(t) == "table" and t.autoRoll == true
	end

	local function render()
		local t = now()
		view = TitleWindowLogic.rows(source.get("titles"), source.get("upgrades"))
		for i, r in ipairs(view) do
			local parts = rows[i]
			parts.name.Text = r.name
			parts.name.TextColor3 = UiTheme.rarityColor(r.tier)
			parts.mult.Text = r.multText
			parts.chance.Text = r.chanceText
			parts.status.Text = r.statusText
			parts.buttonLabel.Text = r.buttonText
			parts.button.setDisabled(not r.canEquip or pending.isPending("equip", t))
		end
		local roll = TitleWindowLogic.rollState(source.get("blox"))
		rollButton.setDisabled(not roll.canRoll or pending.isPending("roll", t) or t < rollCooldownUntil)
		rollFoot.Text = roll.footText
		local on = autoOn()
		autoLabel.Text = TitleWindowLogic.autoText(on)
		autoLabel.TextColor3 = if on then TOGGLE_ON_TEXT else TOGGLE_OFF_TEXT
		for _, stroke in ipairs(autoStrokes) do
			stroke.Color = if on then TOGGLE_ON_STROKE else TOGGLE_OFF_STROKE
		end
		autoButton.setDisabled(pending.isPending("auto", t))
		status.Text = resultText or ""
	end

	local function send(key: string, payload: { action: string, titleId: string?, on: boolean? })
		if not pending.tryBegin(key, now()) then
			return
		end
		resultText = nil
		deps.sendRequest(payload)
		render()
		task.delay(TitleWindowLogic.PENDING_TIMEOUT_SEC + 0.05, render)
	end

	local function pressRoll()
		render() -- 최신 Store 값으로 다시 판정한다
		if not TitleWindowLogic.rollState(source.get("blox")).canRoll or now() < rollCooldownUntil then
			return
		end
		send("roll", { action = "roll" })
	end

	local function pressAuto()
		send("auto", { action = "setAuto", on = not autoOn() })
	end

	local function pressEquip(id: string)
		render()
		for _, r in ipairs(view) do
			if r.id == id then
				if r.canEquip then
					send("equip", { action = "equip", titleId = id })
				end
				return
			end
		end
	end

	local function onResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local key = TitleWindowLogic.pendingKeyOf(payload)
		if key == nil then
			return -- 자동 롤 알림은 토스트가 맡는다(창 상태 문구를 덮지 않는다)
		end
		pending.finish(key)
		if key == "roll" then
			rollCooldownUntil = now() + TitleConfig.ROLL_INTERVAL_SEC
			task.delay(TitleConfig.ROLL_INTERVAL_SEC + 0.05, render)
		end
		resultText = TitleWindowLogic.resultText(payload)
		render()
	end

	for i, parts in ipairs(rows) do
		parts.hit.Activated:Connect(function()
			local r = view[i]
			if r ~= nil then
				pressEquip(r.id)
			end
		end)
	end
	rollHit.Activated:Connect(pressRoll)
	autoHit.Activated:Connect(pressAuto)
	closeHit.Activated:Connect(function()
		resultText = nil
		render()
		deps.onClose()
	end)
	source.subscribe("titles", render)
	source.subscribe("upgrades", render) -- 칭호 행운 레벨 → 현재 확률
	source.subscribe("blox", render)

	render()

	return {
		root = panel.root,
		refresh = render,
		onResult = onResult,
		_debug = {
			pressRoll = pressRoll,
			pressAuto = pressAuto,
			pressEquip = pressEquip,
			rows = rows,
			view = function()
				return view
			end,
			rollButton = rollButton,
			rollFoot = rollFoot,
			autoButton = autoButton,
			autoLabel = autoLabel,
			autoStroke = autoStroke,
			note = note,
			status = status,
		},
	}
end

return TitleWindow

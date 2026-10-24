--!strict
-- 설정 창 (작은 창, Window 층). Phase 7 지시서 #11 A8. 메뉴 레일 "설정" 칸(screenName "Settings")이 연다.
--
-- 항목 둘: "다른 사람 아우라 숨기기"(#11 A8) · "다른 사람 펫 숨기기"(#12 E10). 줄은 ROWS 표에서 나온다.
-- 토글은 자동 도구 · 칭호 창과 같은 두 채널: 테두리 색(켜짐 = 수령 · 안전 노랑 / 꺼짐 = 검정 — 버튼 그림의 UIStroke) + 글자 밝기.
-- 요청은 SettingsRequest{key, value}(서버 화이트리스트가 다시 판정), 결과는 SettingsResult. 저장된 값은 PlayerState(Store "auras" · "pets")가 돌려준다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local TitleWindowLogic = require(script.Parent.Parent.Parent.Logic.TitleWindowLogic)

local SettingsWindow = {}

SettingsWindow.TITLE = "설정"
SettingsWindow.ON_TEXT = "켜짐"
SettingsWindow.OFF_TEXT = "꺼짐"

-- 항목 표. read(Store) → 지금 값, key = 서버 화이트리스트 키.
local ROWS = {
	{
		key = "hideOtherAuras",
		label = "다른 사람 아우라 숨기기",
		read = function(source: any): boolean
			local a = source.get("auras")
			return type(a) == "table" and a.hideOtherAuras == true
		end,
	},
	{
		key = "hideOtherPets",
		label = "다른 사람 펫 숨기기",
		read = function(source: any): boolean
			local p = source.get("pets")
			return type(p) == "table" and p.hideOtherPets == true
		end,
	},
}
SettingsWindow.ROWS = ROWS

local ROW_H = 0.16
local ROW_GAP = 0.02
local LABEL_W = 0.62
local TOGGLE_X, TOGGLE_W = 0.66, 0.34

local ON_STROKE = UiTheme.Colors.cashout.base
local OFF_STROKE = Color3.new(0, 0, 0)
local ON_TEXT = UiTheme.Colors.neutral.light
local OFF_TEXT = UiTheme.Colors.neutral.base

local REASONS = {
	rate_limited = "잠시 뒤에 다시 눌러 주세요",
	not_allowed = "바꿀 수 없는 설정이에요",
	bad_value = "잘못된 값이에요",
	no_profile = "데이터를 불러오는 중이에요",
} :: { [string]: string }

export type Deps = {
	store: any?,
	sendRequest: (payload: { key: string, value: any }) -> (),
	onClose: () -> (),
	now: (() -> number)?,
}

type RowParts = { label: TextLabel, button: Button.ButtonHandle, buttonLabel: TextLabel, hit: TextButton, strokes: { UIStroke } }

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	_debug: { press: (index: number) -> (), rows: { RowParts }, status: TextLabel },
}

function SettingsWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local panel = Panel.create("Small", SettingsWindow.TITLE)
	panel.root.Name = "SettingsWindow"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }

	local rows: { RowParts } = {}
	for i, row in ipairs(ROWS) do
		local y = (i - 1) * (ROW_H + ROW_GAP)
		local label = WindowParts.makeText("Label" .. i, body, "medium", 0, y, LABEL_W, ROW_H)
		label.Text = row.label
		local button = Button.create({ size = "Small", color = "gray", widthScale = TOGGLE_W, heightScale = ROW_H })
		button.root.Name = "Toggle" .. i
		button.root.Position = UDim2.fromScale(TOGGLE_X, y)
		button.root.ZIndex = WindowParts.Z_BUTTON
		button.root.Parent = body
		local buttonLabel, hit = WindowParts.decorateButton(button, SettingsWindow.OFF_TEXT)
		local strokes: { UIStroke } = {}
		for _, obj in ipairs(button.root:GetDescendants()) do
			if obj:IsA("UIStroke") and obj.Parent ~= buttonLabel then
				table.insert(strokes, obj)
			end
		end
		table.insert(raise, button.root)
		rows[i] = { label = label, button = button, buttonLabel = buttonLabel, hit = hit, strokes = strokes }
	end
	local status = WindowParts.makeText("Status", body, "small", 0, 0.85, 1, 0.15, Enum.TextXAlignment.Center)
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local pending = TitleWindowLogic.newPending()
	local resultText: string? = nil

	local function render()
		local t = now()
		for i, row in ipairs(ROWS) do
			local on = row.read(source)
			local parts = rows[i]
			parts.buttonLabel.Text = if on then SettingsWindow.ON_TEXT else SettingsWindow.OFF_TEXT
			parts.buttonLabel.TextColor3 = if on then ON_TEXT else OFF_TEXT
			for _, s in ipairs(parts.strokes) do
				s.Color = if on then ON_STROKE else OFF_STROKE
			end
			parts.button.setDisabled(pending.isPending(row.key, t))
		end
		status.Text = resultText or ""
	end

	local function press(index: number)
		local row = ROWS[index]
		if row == nil or not pending.tryBegin(row.key, now()) then
			return
		end
		resultText = nil
		deps.sendRequest({ key = row.key, value = not row.read(source) })
		render()
		task.delay(TitleWindowLogic.PENDING_TIMEOUT_SEC + 0.05, render)
	end

	local function onResult(payload: any)
		if type(payload) ~= "table" or type(payload.key) ~= "string" then
			return
		end
		pending.finish(payload.key)
		resultText = if payload.ok then nil else (REASONS[tostring(payload.reason)] or "바꾸지 못했어요")
		render()
	end

	for i, parts in ipairs(rows) do
		parts.hit.Activated:Connect(function()
			press(i)
		end)
	end
	closeHit.Activated:Connect(function()
		resultText = nil
		render()
		deps.onClose()
	end)
	source.subscribe("auras", render)
	source.subscribe("pets", render)
	render()

	return { root = panel.root, refresh = render, onResult = onResult, _debug = { press = press, rows = rows, status = status } }
end

return SettingsWindow

--!strict
-- 코드 입력 창 (작은 창, Window 층 — 지시서 #20 C4 · C6). 설정 창 "코드 입력" 버튼이 연다(screenName "Code").
--
-- 입력칸(TextBox) 하나 · 확인 · 결과 문구. 요청은 CodeRequest{code}(서버가 정리 · 판정한다), 결과는 CodeResult.
-- ⚠️ 입력 글자를 화면에 되보이지 않는다(C4): 확인을 누르면 입력칸을 바로 비우고, 결과 문구는 CodeWindowLogic.resultText(서버 결과 · Strings)뿐이다.
-- 폰 키보드: 창을 화면 위쪽에 붙이고(위 4%부터) 입력칸과 확인 버튼을 본문 첫 줄 한 줄에 둔다 — 키보드가 올라와도 가리지 않게.
-- Enter(FocusLost enterPressed)로도 보낸다. 배치값은 Claude가 정했다(docs/UI.md "지시서 #20").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local CodeWindowLogic = require(script.Parent.Parent.Parent.Logic.CodeWindowLogic)

local CodeWindow = {}

CodeWindow.TOP = 0.04 -- 창 윗변(화면 높이 기준)
local ROW_H = 0.2
local INPUT_W = 0.62
local SUBMIT_X, SUBMIT_W = 0.66, 0.34
local RESULT_Y, RESULT_H = 0.26, 0.16

export type Deps = {
	send: (code: string) -> (),
	onClose: () -> (),
	now: (() -> number)?,
}

export type Handle = {
	root: Frame,
	onResult: (any) -> (),
	reset: () -> (),
	_debug: { box: TextBox, result: TextLabel, submitHit: TextButton, submit: () -> (), sent: { string } },
}

function CodeWindow.create(deps: Deps): Handle
	local now = deps.now or os.clock
	local panel = Panel.create("Small", Locale.t("code.title"))
	panel.root.Name = "CodeWindow"
	panel.root.AnchorPoint = Vector2.new(0.5, 0)
	panel.root.Position = UDim2.fromScale(0.5, CodeWindow.TOP)
	local body = panel.body

	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.Position = UDim2.fromScale(0, 0)
	box.Size = UDim2.fromScale(INPUT_W, ROW_H)
	box.BackgroundColor3 = UiTheme.Colors.neutral.light
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = Locale.t("code.placeholder")
	box.PlaceholderColor3 = UiTheme.Colors.neutral.base
	box.TextColor3 = Color3.new(0, 0, 0)
	box.TextScaled = true
	box.Font = UiTheme.FONT
	box.ZIndex = WindowParts.Z_TEXT
	local boxSize = Instance.new("UITextSizeConstraint")
	boxSize.MaxTextSize = TextScale.Levels.medium.maxTextSize
	boxSize.Parent = box
	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Color3.new(0, 0, 0)
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Thickness = 2
	boxStroke.Parent = box
	box.Parent = body

	local submit = Button.create({ size = "Small", color = "blue", widthScale = SUBMIT_W, heightScale = ROW_H })
	submit.root.Name = "Submit"
	submit.root.Position = UDim2.fromScale(SUBMIT_X, 0)
	submit.root.ZIndex = WindowParts.Z_BUTTON
	submit.root.Parent = body
	local _, submitHit = WindowParts.decorateButton(submit, Locale.t("code.submit"))
	local result = WindowParts.makeText("Result", body, "small", 0, RESULT_Y, 1, RESULT_H, Enum.TextXAlignment.Center)
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons({ panel.closeButton.root, submit.root })

	local pendingUntil = 0
	local sent: { string } = {}

	local function render()
		submit.setDisabled(now() < pendingUntil)
	end

	local function doSubmit()
		if now() < pendingUntil then
			return
		end
		local code = box.Text
		box.Text = "" -- C4: 보낸 글자는 바로 지운다(결과에도 쓰지 않는다)
		pendingUntil = now() + CodeWindowLogic.PENDING_TIMEOUT_SEC
		result.Text = ""
		table.insert(sent, code)
		deps.send(code)
		render()
		task.delay(CodeWindowLogic.PENDING_TIMEOUT_SEC + 0.05, render)
	end

	local function reset()
		box.Text = ""
		result.Text = ""
		pendingUntil = 0
		render()
	end

	submitHit.Activated:Connect(doSubmit)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			doSubmit()
		end
	end)
	closeHit.Activated:Connect(function()
		reset()
		deps.onClose()
	end)
	render()

	return {
		root = panel.root,
		onResult = function(payload: any)
			pendingUntil = 0
			result.Text = CodeWindowLogic.resultText(payload) or ""
			render()
		end,
		reset = reset,
		_debug = { box = box, result = result, submitHit = submitHit, submit = doSubmit, sent = sent },
	}
end

return CodeWindow

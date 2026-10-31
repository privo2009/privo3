--!strict
-- 첫 접속 안내 띠 (OverlayGui 런 표시층 — 비차단, 지시서 #20 O1 ~ O3). 단계 · 끝남은 서버 PlayerState onboarding, 문구는 UI/Logic/OnboardingLogic.
--
-- 자리: 상단 정보 띠(위 15%)의 오른쪽 — x 0.73 ~ 0.97(토스트와 같은 칸), y 0.005 ~ 0.145. 중앙 금지 구역 밖이고, 챌린지 정보(0.35 ~ 0.65) ·
-- 런 안내(오른쪽 레일 y 0.235 ~) · 환생 안내(0.28 ~ 0.72)와 겹치지 않는다. 토스트(알림층)가 뜨면 그 위에 그려진다 — 안내 중 토스트는 드물고
-- 잠깐이다(Claude 판단 — docs/UI.md "지시서 #20").
-- 첫 줄: "n/5단계"(왼쪽) + 버튼(오른쪽 — 1 ~ 4단계 건너뛰기(두 번 누름) / 5단계 확인). 아래 두 줄: 단계 문장(글자 감싸기).
-- 요청은 OnboardingRequest(finish · skip) 한 번만(대기 중이면 버튼 잠김 — 결과 또는 시간 초과로 풀린다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local OnboardingLogic = require(script.Parent.Parent.Parent.Logic.OnboardingLogic)
local OverlayParts = require(script.Parent.OverlayParts)

local OnboardingBand = {}

OnboardingBand.X0 = 0.73
OnboardingBand.WIDTH = 0.24
OnboardingBand.TOP = 0.005
OnboardingBand.HEIGHT = 0.14
local HEAD_H = 0.34 -- 띠 높이 대비 첫 줄
local Z = OverlayParts.Z.runDisplay

export type Deps = {
	store: any?,
	send: (action: string) -> (),
	now: (() -> number)?,
}

export type Handle = {
	root: Frame,
	onResult: (any) -> (),
	refresh: () -> (),
	_debug: { panel: Frame, progress: TextLabel, text: TextLabel, buttonLabel: TextLabel, hit: TextButton, press: () -> (), sent: { string } },
}

function OnboardingBand.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock

	local root = Instance.new("Frame")
	root.Name = "OnboardingBand"
	root.Position = UDim2.fromScale(OnboardingBand.X0, OnboardingBand.TOP)
	root.Size = UDim2.fromScale(OnboardingBand.WIDTH, OnboardingBand.HEIGHT)
	root.BackgroundTransparency = 1
	root.ZIndex = Z

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = UiTheme.Colors.neutral.dark
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.ZIndex = Z
	panel.Visible = false
	panel.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UiTheme.Colors.cashout.base
	stroke.Parent = panel

	local progress = WindowParts.makeText("Progress", panel, "small", 0.04, 0.04, 0.5, HEAD_H - 0.06)
	progress.ZIndex = Z + 1
	progress.TextColor3 = UiTheme.Colors.cashout.light
	local text = WindowParts.makeText("Text", panel, "small", 0.04, HEAD_H + 0.02, 0.92, 1 - HEAD_H - 0.06)
	text.ZIndex = Z + 1
	text.TextWrapped = true
	text.TextYAlignment = Enum.TextYAlignment.Top

	local button = Button.create({ size = "Small", color = "gray", widthScale = 0.42, heightScale = HEAD_H - 0.06 })
	button.root.Name = "Action"
	button.root.Position = UDim2.fromScale(0.56, 0.04)
	button.root.Parent = panel
	local buttonLabel, hit = WindowParts.decorateButton(button, "")
	for _, obj in ipairs(button.root:GetDescendants()) do
		if obj:IsA("GuiObject") then
			obj.ZIndex = Z + 2
		end
	end
	button.root.ZIndex = Z + 2
	buttonLabel.ZIndex = Z + 3
	hit.ZIndex = Z + 4

	local skipConfirm = OnboardingLogic.newSkipConfirm()
	local pendingUntil = 0
	local sent: { string } = {}

	local function render()
		local v = OnboardingLogic.view(source.get("onboarding"), skipConfirm.isArmed(now()))
		panel.Visible = v.visible
		progress.Text = v.progress
		text.Text = v.text
		buttonLabel.Text = if v.showFinish then v.finishText else v.skipText
		button.setDisabled(now() < pendingUntil)
	end

	local function press()
		local v = OnboardingLogic.view(source.get("onboarding"), false)
		if not v.visible or now() < pendingUntil then
			return
		end
		local action: string? = nil
		if v.showFinish then
			action = "finish"
		elseif skipConfirm.press(now(), true) == "send" then
			action = "skip"
		end
		if action ~= nil then
			pendingUntil = now() + OnboardingLogic.PENDING_TIMEOUT_SEC
			table.insert(sent, action)
			deps.send(action)
			task.delay(OnboardingLogic.PENDING_TIMEOUT_SEC + 0.05, render)
		else
			task.delay(OnboardingLogic.SKIP_CONFIRM_SEC + 0.05, render) -- 확인 시간이 지나면 글자를 되돌린다
		end
		render()
	end
	hit.Activated:Connect(press)
	source.subscribe("onboarding", function()
		skipConfirm.cancel()
		render()
	end)
	render()

	return {
		root = root,
		onResult = function(_payload: any)
			pendingUntil = 0
			render()
		end,
		refresh = render,
		_debug = { panel = panel, progress = progress, text = text, buttonLabel = buttonLabel, hit = hit, press = press, sent = sent },
	}
end

return OnboardingBand

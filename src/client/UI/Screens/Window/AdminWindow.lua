--!strict
-- 관리 창(지시서 #48 4부 — 개발자 전용). 서버가 AdminResult{ action = "hello" }를 보낸 관리자에게만 AdminBoot가 만든다.
-- 키트 창(Panel Large) 하나: 줄 1 대상 UserId · 종류(누르면 다음) · id / 줄 2 개수 · 지급 · 회수 · 상태 / 줄 3 공지 글 · 공지 / 아래 결과 글.
-- 글 · 판정: AdminWindowLogic(편의 검사) → AdminRequest. 서버가 관리자 · 값 · 관문을 다시 본다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Kit = require(script.Parent.Parent.Parent.Components.Kit)
local AdminWindowLogic = require(script.Parent.Parent.Parent.Logic.AdminWindowLogic)

local AdminWindow = {}

local ROW_H = 0.12
local GAP = 0.03

export type Deps = { send: (payload: any) -> (), onClose: () -> () }
export type Handle = {
	root: Frame,
	onResult: (payload: any) -> (),
	_debug: { boxes: { [string]: TextBox }, kind: () -> string, press: (action: string) -> (), result: TextLabel, sent: { any } },
}

-- 입력칸(코드 입력 창과 같은 모양 — 키트 바깥선)
local function makeBox(name: string, parent: Instance, x: number, y: number, w: number, placeholder: string): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.Position = UDim2.fromScale(x, y)
	box.Size = UDim2.fromScale(w, ROW_H)
	box.BackgroundColor3 = UiTheme.Colors.neutral.light
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = UiTheme.Colors.neutral.base
	box.TextColor3 = UiTheme.Skin.text.stroke
	box.TextScaled = true
	box.Font = UiTheme.FONT
	box.ZIndex = WindowParts.Z_TEXT
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels.small.maxTextSize
	size.Parent = box
	Kit.stroke(box, UiTheme.Skin.text.stroke, UiTheme.Skin.line.cell, Enum.ApplyStrokeMode.Border)
	box.Parent = parent
	return box
end

function AdminWindow.create(deps: Deps): Handle
	local panel = Panel.create("Large", Locale.t("admin.title"))
	panel.root.Name = "AdminWindow"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }
	local sent: { any } = {}

	local y1, y2, y3 = 0, ROW_H + GAP, 2 * (ROW_H + GAP)
	local boxes = {
		target = makeBox("Target", body, 0, y1, 0.3, Locale.t("admin.target")),
		id = makeBox("Id", body, 0.64, y1, 0.36, Locale.t("admin.id")),
		amount = makeBox("Amount", body, 0, y2, 0.3, Locale.t("admin.amount")),
		text = makeBox("Text", body, 0, y3, 0.74, Locale.t("admin.text")),
	}
	local kind = AdminConfig.KINDS[1]

	local function button(name: string, x: number, y: number, w: number, color: Button.ColorName, caption: string): (TextLabel, TextButton)
		local b = Button.create({ size = "Small", color = color, widthScale = w, heightScale = ROW_H })
		b.root.Name = name
		b.root.Position = UDim2.fromScale(x, y)
		b.root.ZIndex = WindowParts.Z_BUTTON
		b.root.Parent = body
		table.insert(raise, b.root)
		return WindowParts.decorateButton(b, caption)
	end
	local kindLabel, kindHit = button("Kind", 0.32, y1, 0.3, "gray", Locale.t("admin.kind", { kind = kind }))
	local _, grantHit = button("Grant", 0.32, y2, 0.21, "green", Locale.t("admin.grant"))
	local _, revokeHit = button("Revoke", 0.55, y2, 0.21, "red", Locale.t("admin.revoke"))
	local _, inspectHit = button("Inspect", 0.78, y2, 0.22, "blue", Locale.t("admin.inspect"))
	local _, announceHit = button("Announce", 0.76, y3, 0.24, "blue", Locale.t("admin.announce"))
	local result = WindowParts.makeText("Result", body, "small", 0, 3 * (ROW_H + GAP), 1, 1 - 3 * (ROW_H + GAP), Enum.TextXAlignment.Left)
	result.TextWrapped = true
	result.TextYAlignment = Enum.TextYAlignment.Top
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local function press(action: string)
		local payload, reason = AdminWindowLogic.build(action, {
			target = boxes.target.Text,
			kind = kind,
			id = boxes.id.Text,
			amount = boxes.amount.Text,
			text = boxes.text.Text,
		})
		if payload == nil then
			result.Text = Locale.t("admin.fail", { reason = tostring(reason) })
			return
		end
		table.insert(sent, payload)
		deps.send(payload)
	end

	kindHit.Activated:Connect(function()
		kind = AdminWindowLogic.nextKind(kind)
		kindLabel.Text = Locale.t("admin.kind", { kind = kind })
	end)
	grantHit.Activated:Connect(function()
		press("grant")
	end)
	revokeHit.Activated:Connect(function()
		press("revoke")
	end)
	inspectHit.Activated:Connect(function()
		press("inspect")
	end)
	announceHit.Activated:Connect(function()
		press("announce")
	end)
	closeHit.Activated:Connect(deps.onClose)

	return {
		root = panel.root,
		onResult = function(payload: any)
			local text = AdminWindowLogic.resultText(payload)
			if text ~= nil then
				result.Text = text
			end
		end,
		_debug = {
			boxes = boxes,
			kind = function()
				return kind
			end,
			press = press,
			result = result,
			sent = sent,
		},
	}
end

return AdminWindow

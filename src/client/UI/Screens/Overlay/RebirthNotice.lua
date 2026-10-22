--!strict
-- 환생 안내 (Phase 6 지시서 #8 2c). 환생하는 순간 크게 뜬다 — "힘 배수 ×이전 → ×이후"와 초기화 사실.
-- 첫 직접 플레이에서 환생 직후 무엇이 달라졌는지 느끼기 어려웠다. 문구는 UI/Logic/FeedbackLogic.rebirthNotice.
--
-- 알림층(OverlayParts.Z.notice) — 차단하지 않는다(모달 아님). REBIRTH_HOLD_SEC 뒤에 스스로 사라진다.
-- 자리: 상단 정보 띠(화면 위 15%) 가운데. 중앙 금지 구역(위 15% ~ 아래 25%) 밖이다. 같은 띠의 챌린지 정보(스테이지 · 타이머)를
-- 잠깐 가리지만 환생 직후에는 런이 없어 "대기 중"이다(환생이 런을 버린다 — RebirthService 3번).
-- 오른쪽 레일(오류 · 런 안내)을 쓰지 않은 이유: 폰에서는 그 아래로 자동 도구 · 구좌가 올라와 있어(TouchSafeLayout) 겹친다.
-- 배치값은 Claude가 정했다(세션 로그).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local OverlayParts = require(script.Parent.OverlayParts)
local FeedbackLogic = require(script.Parent.Parent.Parent.Logic.FeedbackLogic)

local RebirthNotice = {}

local WIDTH = 0.5
local TOP = 0.01
local GAP = 0.005
local TITLE_H = TextScale.Levels.large.heightFraction
local CHANGE_H = TextScale.Levels.medium.heightFraction
local RESET_H = TextScale.Levels.small.heightFraction
local HEIGHT = TITLE_H + CHANGE_H + RESET_H + GAP * 4
RebirthNotice.Bounds = { x0 = 0.5 - WIDTH / 2, y0 = TOP, x1 = 0.5 + WIDTH / 2, y1 = TOP + HEIGHT }

export type Handle = {
	root: Frame,
	panel: Frame, -- 보이는 것은 이것이다(root는 늘 보이는 투명 틀)
	show: (FeedbackLogic.RebirthNotice) -> (),
	_rows: { title: TextLabel, change: TextLabel, reset: TextLabel },
}

function RebirthNotice.create(): Handle
	assert(TOP + HEIGHT <= Layout.TOP_HEIGHT, "RebirthNotice: 상단 정보 띠(15%)를 넘는다")
	local root = Instance.new("Frame")
	root.Name = "RebirthNotice"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.fromScale(0.5, TOP)
	root.Size = UDim2.fromScale(WIDTH, HEIGHT)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = OverlayParts.Z.notice
	-- ⚠️ root는 늘 보이는 투명 틀이다. ScreenController.open이 root를 보이게 하므로(2026-10-23 Play: 빈 파란 띠가 떴다)
	-- 보일지 말지는 안쪽 Panel의 Visible로 정한다.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = UiTheme.Colors.blox.dark
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.ZIndex = OverlayParts.Z.notice
	panel.Visible = false
	panel.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = panel

	local function row(name: string, level: TextScale.Level, y: number, h: number): TextLabel
		local label = OverlayParts.textRow(name, "", level, nil)
		label.Position = UDim2.fromScale(0.03, y / HEIGHT)
		label.Size = UDim2.fromScale(0.94, h / HEIGHT)
		label.ZIndex = OverlayParts.Z.notice
		label.Parent = panel
		return label
	end
	local title = row("Title", "large", GAP, TITLE_H)
	local change = row("Change", "medium", GAP * 2 + TITLE_H, CHANGE_H)
	change.TextColor3 = UiTheme.Colors.power.light
	local reset = row("Reset", "small", GAP * 3 + TITLE_H + CHANGE_H, RESET_H)

	local token = 0
	local function show(notice: FeedbackLogic.RebirthNotice)
		token += 1
		local mine = token
		title.Text = notice.title
		change.Text = notice.change
		reset.Text = notice.reset
		panel.Visible = true
		task.delay(FeedbackLogic.REBIRTH_HOLD_SEC, function()
			if token == mine then
				panel.Visible = false
			end
		end)
	end

	return {
		root = root,
		panel = panel,
		show = show,
		_rows = { title = title, change = change, reset = reset },
	}
end

return RebirthNotice

--!strict
-- 런 표시층 안내 — 클리어 선택 · 실패 (U4, 지시서 #5). 비차단이다(모달 금지): 클리어 뒤 유저는
-- 발판이나 벽까지 직접 걸어가야 하므로 화면을 덮으면 안 된다(docs/UI.md "레이어 우선순위").
-- 무엇을 띄울지는 UI/Logic/RunNoticeLogic이 정한다. 이 파일은 그리기만 한다.
--
-- 자리: 오른쪽 레일 위쪽(OverlayParts.RIGHT_RAIL_*). 중앙 금지 구역 · 하단 띠와 겹치지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local OverlayParts = require(script.Parent.OverlayParts)
local RunNoticeLogic = require(script.Parent.Parent.Parent.Logic.RunNoticeLogic)

local RunNotice = {}

local LEVEL: TextScale.Level = "medium"
local ROW_HEIGHT = TextScale.Levels[LEVEL].heightFraction
local ROW_GAP = 0.01 -- 줄 사이. 시각 튜닝값
-- 오류(알림층) 칸 바로 아래. 둘이 동시에 떠도 겹치지 않게 오류 칸 높이(small 3줄)만큼 내린다.
local TOP = Layout.TOP_HEIGHT + TextScale.Levels.small.heightFraction * 3 + ROW_GAP

RunNotice.TEXT = {
	cashout = Locale.t("overlay.run.cashout"),
	advance = Locale.t("overlay.run.advance"),
	final = Locale.t("overlay.run.final"),
	fail = Locale.t("overlay.run.fail"),
}

export type Handle = {
	root: Frame,
	show: (RunNoticeLogic.Kind) -> (),
	_rows: { first: TextLabel, second: TextLabel },
}

function RunNotice.create(): Handle
	local root = Instance.new("Frame")
	root.Name = "RunNotice"
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromScale(OverlayParts.RIGHT_RAIL_LEFT, TOP)
	root.Size = UDim2.fromScale(OverlayParts.RIGHT_RAIL_WIDTH, ROW_HEIGHT * 2 + ROW_GAP)
	root.BackgroundTransparency = 1
	root.ZIndex = OverlayParts.Z.runDisplay
	root.Visible = false

	local rootHeight = ROW_HEIGHT * 2 + ROW_GAP
	local first = OverlayParts.textRow("First", "", LEVEL, "cashout")
	first.Size = UDim2.fromScale(1, ROW_HEIGHT / rootHeight)
	first.Position = UDim2.fromScale(0, 0)
	first.ZIndex = OverlayParts.Z.runDisplay
	first.Parent = root

	local second = OverlayParts.textRow("Second", "", LEVEL, "advance")
	second.Size = UDim2.fromScale(1, ROW_HEIGHT / rootHeight)
	second.Position = UDim2.fromScale(0, (ROW_HEIGHT + ROW_GAP) / rootHeight)
	second.ZIndex = OverlayParts.Z.runDisplay
	second.Parent = root

	local token = 0

	local function show(kind: RunNoticeLogic.Kind)
		token += 1
		if kind == "hide" then
			root.Visible = false
			return
		end
		if kind == "clear" then
			first.Text = RunNotice.TEXT.cashout
			OverlayParts.setRole(first, "cashout")
			second.Text = RunNotice.TEXT.advance
			OverlayParts.setRole(second, "advance")
			second.Visible = true
		elseif kind == "clearFinal" then
			first.Text = RunNotice.TEXT.final
			OverlayParts.setRole(first, "cashout")
			second.Visible = false
		elseif kind == "fail" then
			first.Text = RunNotice.TEXT.fail
			OverlayParts.setRole(first, "danger")
			second.Visible = false
		end
		root.Visible = true
		local mine = token
		task.delay(RunNoticeLogic.DURATION_SEC[kind], function()
			if token == mine then
				root.Visible = false
			end
		end)
	end

	return { root = root, show = show, _rows = { first = first, second = second } }
end

return RunNotice

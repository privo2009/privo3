--!strict
-- HUD: 챌린지 정보 — 스테이지 · 타이머 (상단 중앙). docs/UI.md "1. 화면 목록" · "2. 세이프존".
--
-- ⚠️ 소스는 Store가 아니라 RunStateChanged다 (stage/timeLeft/cleared/canAdvance가
-- 그 채널로 온다). RemoteReceiver.client.lua는 LocalScript라 require할 수 없고
-- (require 대상이 못 됨), 이미 그 채널에 연결돼 있다. RemoteEvent는 리스너를
-- 여러 개 붙일 수 있으므로 이 파일이 같은 채널에 독립적으로 한 번 더 연결한다 —
-- RunStateChanged 채널 정의(Remotes.lua)도 RemoteReceiver도 건드리지 않는다
-- (SpeedInput이 SpeedApplied에, RemoteReceiver가 RunStateChanged/BlockDamaged에
-- 각자 따로 연결하는 것과 같은 패턴 — 이 프로젝트에 이미 있는 방식이다).
--
-- ⚠️ 타이머는 ValuePanel을 그대로 쓰지 않는다. ValuePanel.setValue는 BigNum
-- 전용이고 setNumber는 정수(%d)라 소수 1자리(19.8)가 잘린다. ValuePanel.create가
-- 만들어주는 라벨(TextScaled + UITextSizeConstraint + AspectRatioConstraint +
-- UIStroke)의 골격만 재사용하고, Text는 이 파일이 직접 "%.1f"로 채운다 —
-- ValuePanel.lua는 U3-1 산출물이라 고치지 않는다.
--
-- 런이 없을 때(active=false)는 자리를 유지한 채 대기 문구로 바꾼다. 라벨의
-- Size는 AspectRatioConstraint가 자릿수 기준으로 이미 고정하므로, 무슨 문구를
-- 넣어도 크기가 안 바뀐다 — "타이머 칸이 사라졌다 나타나면 레이아웃이 튄다"를
-- 자연스럽게 피한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local ValuePanel = require(script.Parent.Parent.Parent.Components.ValuePanel)

local ChallengeInfo = {}

local STAGE_LEVEL: TextScale.Level = "medium"
local TIMER_LEVEL: TextScale.Level = "huge" -- 특대(7%) — docs/UI.md 힘 수치와 같은 단계
local TIMER_CHARS = 4 -- 런 제한 20초 안쪽이라 "19.8"류 4자로 충분하다

local INACTIVE_STAGE_TEXT = "대기 중"
local INACTIVE_TIMER_TEXT = "--"

export type ChallengeInfoHandle = {
	root: Frame,
	-- 테스트 전용: 실제 RunStateChanged 없이도 표시 로직을 검증할 수 있게 노출한다
	-- (ScreenController._debug와 같은 성격).
	_debug: {
		apply: (Remotes.RunStateChangedPayload) -> (),
	},
}

function ChallengeInfo.create(): ChallengeInfoHandle
	local stageHeight = TextScale.Levels[STAGE_LEVEL].heightFraction
	local timerHeight = TextScale.Levels[TIMER_LEVEL].heightFraction
	local rootHeight = stageHeight + timerHeight

	local root = Instance.new("Frame")
	root.Name = "ChallengeInfo"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, Layout.getTopInset())
	root.Size = UDim2.fromScale(0.3, rootHeight)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = root

	-- ⚠️ 자식의 Size.Y.Scale은 root 기준이다. root 자체가 이미 화면 기준으로 줄어든
	-- 크기(rootHeight)라서, stageHeight/timerHeight(화면 기준 값)를 그대로 쓰면 실제로는
	-- "화면의 stageHeight%"가 아니라 "root의 stageHeight%"가 되어 훨씬 작게 나온다
	-- (Panel.lua가 X 버튼·제목에 쓴 것과 같은 환산이 여기도 필요하다).
	local stageLabel = Instance.new("TextLabel")
	stageLabel.Name = "Stage"
	stageLabel.LayoutOrder = 1
	stageLabel.BackgroundTransparency = 1
	stageLabel.BorderSizePixel = 0
	stageLabel.Size = UDim2.fromScale(1, stageHeight / rootHeight)
	stageLabel.Text = INACTIVE_STAGE_TEXT
	stageLabel.TextScaled = true
	stageLabel.TextColor3 = Color3.new(1, 1, 1)
	stageLabel.Font = Enum.Font.SourceSansBold
	stageLabel.Parent = root

	local stageSizeConstraint = Instance.new("UITextSizeConstraint")
	stageSizeConstraint.MaxTextSize = TextScale.Levels[STAGE_LEVEL].maxTextSize
	stageSizeConstraint.Parent = stageLabel

	local stageStroke = Instance.new("UIStroke")
	stageStroke.Color = Color3.new(0, 0, 0)
	stageStroke.Parent = stageLabel

	local timer = ValuePanel.create(TIMER_LEVEL, TIMER_CHARS)
	timer.label.Name = "Timer"
	timer.label.LayoutOrder = 2
	timer.label.Size = UDim2.fromScale(0, timerHeight / rootHeight)
	timer.label.Text = INACTIVE_TIMER_TEXT
	timer.label.Parent = root

	local function apply(payload: Remotes.RunStateChangedPayload)
		if payload.active then
			stageLabel.Text = string.format("스테이지 %d", payload.state.stage)
			timer.label.Text = string.format("%.1f", payload.state.timeLeft)
		else
			stageLabel.Text = INACTIVE_STAGE_TEXT
			timer.label.Text = INACTIVE_TIMER_TEXT
		end
	end

	local channels = Remotes.getClient()
	channels.runStateChanged.OnClientEvent:Connect(apply)

	return {
		root = root,
		_debug = { apply = apply },
	}
end

return ChallengeInfo

--!strict
-- 3D 안내 BillboardGui (U4, 지시서 #5). 클라 전용이고 각자 자기 값을 본다.
--
--   현재 층 수령 발판 위   지금 수령하면 받는 양 (cashout 노랑). 켜진 발판에만
--   진행 벽 위             클리어 후 다음 층 보상 (advance 보라). 최종층: "다음 월드 준비 중" (neutral)
--   클릭 파워 패드 위       클릭 파워 + 해금 조건 (해금 power 주황 / 미해금 neutral 회색)
--   입장 게이트            위치 안내 (neutral). 런 중에는 숨김
--
-- 내용은 WorldLabelLogic(순수)이 정한다. 이 파일은 빌보드를 만들고(한 번만) 내용을 바꿀 뿐이다 —
-- 이벤트마다 Instance.new 하지 않는다(CLAUDE.md 금지 사항).
--
-- 크기는 studs다(BillboardGui.Size의 Scale = studs). 화면 UI가 아니라 금지 구역 규칙의 예외다
-- (docs/UI.md "2. 세이프존 > 규칙"). 숫자는 Claude가 정한 배치값(세션 로그).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local WorldLabelLogic = require(script.Parent.WorldLabelLogic)
local Store = require(script.Parent.Parent.UI.Store)
local StateSync = require(script.Parent.Parent.Net.StateSync)

type BigNumber = BigNum.BigNumber

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- 빌보드 크기(studs)와 지면에서의 높이(studs).
-- 2026-10-22 Play: 발판·벽 표시가 60 studs 밖에서 작아 1.4배쯤 키웠다. 패드는 한 줄로 붙어 있어
-- 키우면 서로 가린다 — 그대로 둔다.
local SIZE = {
	pad = Vector2.new(8, 3),
	cashout = Vector2.new(14, 5),
	wall = Vector2.new(20, 6.5),
	gate = Vector2.new(16, 5),
}
local HEIGHT_ABOVE_GROUND = {
	pad = 4,
	cashout = 7,
	wall = 14,
	gate = 13,
}
local MAX_DISTANCE = 160 -- studs. 더 멀면 안 그린다(패드 24장이 한꺼번에 떠서 화면을 덮지 않게)

type Billboard = {
	gui: BillboardGui,
	title: TextLabel,
	detail: TextLabel,
	kind: string,
}

local function makeText(name: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.SourceSansBold
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels.large.maxTextSize
	size.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function makeBillboard(name: string, kind: string): Billboard
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(SIZE[kind].X, SIZE[kind].Y)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 0.1
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = frame

	local title = makeText("Title", frame)
	local detail = makeText("Detail", frame)

	gui.Parent = playerGui
	return { gui = gui, title = title, detail = detail, kind = kind }
end

-- 지면 기준 높이로 띄운다. 파트 중심이 아니라 바닥에서 재야 파트 크기가 달라도 같은 높이에 뜬다.
local function place(board: Billboard, part: BasePart)
	board.gui.Adornee = part
	local groundOffset = -part.Size.Y / 2 + HEIGHT_ABOVE_GROUND[board.kind] + SIZE[board.kind].Y / 2
	board.gui.StudsOffsetWorldSpace = Vector3.new(0, groundOffset, 0)
end

local function apply(board: Billboard, label: WorldLabelLogic.Label)
	board.gui.Enabled = label.visible and board.gui.Adornee ~= nil
	if not label.visible then
		return
	end
	local panel = board.gui:FindFirstChild("Panel") :: Frame
	panel.BackgroundColor3 = UiTheme.Colors[label.role].base
	board.title.Text = label.title
	board.detail.Text = label.detail
	if label.detail == "" then
		board.title.Size = UDim2.fromScale(1, 1)
		board.title.Position = UDim2.fromScale(0, 0)
		board.detail.Visible = false
	else
		board.title.Size = UDim2.fromScale(1, 0.55)
		board.title.Position = UDim2.fromScale(0, 0)
		board.detail.Size = UDim2.fromScale(1, 0.45)
		board.detail.Position = UDim2.fromScale(0, 0.55)
		board.detail.Visible = true
	end
end

-- ===== 런 상태 =================================================================================

local run: WorldLabelLogic.RunInput? = nil

local cashoutBoard = makeBillboard("CashoutLabel", "cashout")
local wallBoard = makeBillboard("WallLabel", "wall")
local gateBoard = makeBillboard("GateLabel", "gate")

local function findCashoutPad(stage: number): BasePart?
	local folder = Workspace:FindFirstChild("CashoutPads")
	if folder == nil then
		return nil
	end
	for _, pad in ipairs(folder:GetChildren()) do
		if pad:IsA("BasePart") and pad:GetAttribute("CashoutStage") == stage then
			return pad
		end
	end
	return nil
end

local function findWall(): BasePart?
	local folder = Workspace:FindFirstChild("LocalWalls")
	if folder == nil then
		return nil
	end
	return folder:FindFirstChildWhichIsA("BasePart")
end

local function findGate(): BasePart?
	local folder = Workspace:FindFirstChild("EntranceGate")
	if folder == nil then
		return nil
	end
	return folder:FindFirstChildWhichIsA("BasePart")
end

local function refreshRun()
	local current = run
	if current ~= nil then
		local pad = findCashoutPad(current.stage)
		if pad ~= nil then
			place(cashoutBoard, pad)
		end
	end
	apply(cashoutBoard, WorldLabelLogic.cashout(current, if current ~= nil then current.stage else -1))

	-- 진행 벽 크기 · 위치는 AdvanceWallRenderer가 같은 이벤트에서 바꾼다. 순서를 모르므로 한 프레임 뒤에 잰다.
	task.defer(function()
		local wall = findWall()
		if wall ~= nil then
			place(wallBoard, wall)
		end
		apply(wallBoard, WorldLabelLogic.wall(run))
	end)

	local gate = findGate()
	if gate ~= nil then
		place(gateBoard, gate)
	end
	apply(gateBoard, WorldLabelLogic.gate(current ~= nil and current.active))
end

local channels = Remotes.getClient()
channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	local state = payload.state
	run = {
		active = payload.active,
		stage = state.stage,
		cleared = state.cleared,
		canAdvance = state.canAdvance,
		reward = state.reward,
	}
	refreshRun()
end)

-- ===== 클릭 파워 패드 ===========================================================================

local padBoards: { [number]: Billboard } = {}

local function refreshPad(index: number)
	local board = padBoards[index]
	if board ~= nil then
		apply(board, WorldLabelLogic.pad(index, Store.get("lifeBlox")))
	end
end

local function attachPad(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	local index = pad:GetAttribute("PadIndex")
	if type(index) ~= "number" or padBoards[index] ~= nil then
		return
	end
	local board = makeBillboard(string.format("PadLabel_%02d", index), "pad")
	place(board, pad)
	padBoards[index] = board
	refreshPad(index)
end

Store.subscribe("lifeBlox", function()
	for index in pairs(padBoards) do
		refreshPad(index)
	end
end)

task.spawn(function()
	local folder = Workspace:WaitForChild("ClickPads")
	folder.ChildAdded:Connect(attachPad)
	for _, pad in ipairs(folder:GetChildren()) do
		attachPad(pad)
	end
end)

-- 서버가 게이트 폴더를 늦게 세울 수 있다. 나타나면 런 없음 모습으로 한 번 맞춘다.
task.spawn(function()
	Workspace:WaitForChild("EntranceGate")
	refreshRun()
end)

-- 리스너를 붙였으니 지금 런 상태를 받는다(Net/StateSync.lua).
StateSync.request()

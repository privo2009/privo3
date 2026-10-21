--!strict
-- 수령 발판 렌더러. 내 런 상태(RunStateChanged)를 받아 서버 발판 파트의 색을 내 화면에서만
-- 바꾼다. 진행 벽 렌더러(AdvanceWallRenderer)와 짝이다 — DESIGN.md "클리어 → 진행 벽 개방 +
-- 수령 발판 활성화"의 "활성화"를 보이게 한다.
--
-- 벽과 달리 파트를 새로 만들지 않는다. 발판은 서버가 층마다 세운 실물이고(밟아야 Touched가
-- 서버로 간다), 클라가 Color를 바꿔도 서버·다른 플레이어에게 복제되지 않는다.
-- 서버는 발판 색을 처음 한 번만 정하고 다시 바꾸지 않으므로 여기서 칠한 값이 덮이지 않는다.
--
-- 발판의 층은 서버가 붙인 "CashoutStage" 속성에서 읽는다. 이름을 파싱하지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CashoutPadView = require(ReplicatedStorage.Shared.CashoutPadView)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)

local CONTAINER_NAME = "CashoutPads"
local STAGE_ATTRIBUTE = "CashoutStage"

local current: CashoutPadView.Input? = nil

local function paint(pad: Instance)
	if not pad:IsA("BasePart") then
		return
	end
	local stage = pad:GetAttribute(STAGE_ATTRIBUTE)
	if type(stage) ~= "number" then
		return
	end
	local view = CashoutPadView.compute(current, stage)
	pad.Color = UiTheme.Colors[view.colorRole].base
end

local container: Instance? = nil

local function paintAll()
	if container == nil then
		return
	end
	for _, pad in ipairs(container:GetChildren()) do
		paint(pad)
	end
end

local channels = Remotes.getClient()

channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	local state = payload.state
	current = {
		active = payload.active,
		stage = if state ~= nil then state.stage else nil,
		cleared = if state ~= nil then state.cleared else nil,
	}
	paintAll()
end)

-- 서버가 발판 폴더를 세우기 전에 이 스크립트가 돌 수 있다. 폴더가 나타나면 붙고,
-- 그 뒤에 들어오는 발판(스트리밍 등)도 들어오는 순간 칠한다.
task.spawn(function()
	container = Workspace:WaitForChild(CONTAINER_NAME)
	local folder = container :: Instance
	folder.ChildAdded:Connect(paint)
	paintAll()
end)

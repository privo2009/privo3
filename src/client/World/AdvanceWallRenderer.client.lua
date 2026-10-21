--!strict
-- 진행 벽 렌더러. 내 런 상태(RunStateChanged)를 받아 클라 전용 벽 하나를 옮기고 칠한다. 3c 커밋 2.
--
-- 벽은 플레이어마다 다르다(내 런이 열렸는지는 나만의 상태다). 그래서 서버 파트가 아니라
-- 클라가 만든 Workspace.LocalWalls 안의 파트다 — 서버에도 다른 플레이어에게도 안 보인다.
-- 진행 판정은 서버의 보이지 않는 트리거(AdvanceWallService)가 같은 자리에서 한다.
--
-- RunStateChanged를 RemoteReceiver와 별도로 구독한다. 블록 모델과 벽은 서로 읽는 값이
-- 없어서 한 핸들러에 묶을 이유가 없다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AdvanceWallView = require(ReplicatedStorage.Shared.AdvanceWallView)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AdvanceWallPart = require(script.Parent.AdvanceWallPart)

local CONTAINER_NAME = "LocalWalls"

local function getContainer(): Folder
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = Workspace
	return folder
end

-- 벽은 하나뿐이고 끝까지 재사용한다. 이벤트마다 Instance.new 하지 않는다.
local wall = AdvanceWallPart.create()
wall.Parent = getContainer()

-- 같은 잘못된 stage 값으로는 경고를 한 번만 찍는다. 키는 tostring이다 —
-- NaN은 테이블 키가 될 수 없다.
local warnedInvalid: { [string]: boolean } = {}

local channels = Remotes.getClient()
local StateSync = require(script.Parent.Parent.Net.StateSync)

channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	local state = payload.state
	local input: AdvanceWallView.Input = {
		active = payload.active,
		stage = if state ~= nil then state.stage else nil,
		cleared = if state ~= nil then state.cleared else nil,
		canAdvance = if state ~= nil then state.canAdvance else nil,
	}

	local view = AdvanceWallView.compute(input)

	if view.invalid ~= nil then
		local key = view.invalid .. ":" .. tostring(input.stage)
		if not warnedInvalid[key] then
			warnedInvalid[key] = true
			warn(string.format("[AdvanceWallRenderer] %s: stage=%s - 벽을 숨긴다", view.invalid, tostring(input.stage)))
		end
	end

	AdvanceWallPart.applyView(wall, view)
end)
-- 리스너를 붙였으니 지금 런 상태를 받는다(접속 직후 벽 모습 맞춤 — Net/StateSync.lua).
StateSync.request()

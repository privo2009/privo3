--!strict
-- Window 층 화면(환생 창 · 월드·워프 창)을 ScreenController에 등록하고 서버 채널에 배선한다
-- (Phase 6 지시서 #5 · #6). MenuRail의 "환생" 칸이 "Rebirth", "워프" 칸이 "Warp"로 open한다.
--
-- 요청은 RebirthRequest로 보내고(payload 비어 있음 — 결과값을 싣지 않는다), 결과는 RebirthResult로 받는다.
-- 바뀐 값(블럭스 · 배수)은 PlayerState → Store로 들어와 창이 스스로 다시 그린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScreenController = require(script.Parent.ScreenController)
local RebirthWindow = require(script.Parent.Screens.Window.RebirthWindow)

local channels = Remotes.getClient()

local rebirthWindow = RebirthWindow.create({
	sendRequest = function()
		local payload: Remotes.RebirthRequestPayload = {}
		channels.rebirthRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Rebirth")
	end,
})

ScreenController.register("Rebirth", "Window", function()
	return rebirthWindow.root
end)

channels.rebirthResult.OnClientEvent:Connect(function(payload: Remotes.RebirthResultPayload)
	rebirthWindow.onResult(payload)
end)

-- ===== 월드·워프 창 (지시서 #6) =================================================================

local WarpWindow = require(script.Parent.Screens.Window.WarpWindow)
local StateSync = require(script.Parent.Parent.Net.StateSync)

local warpWindow = WarpWindow.create({
	sendRequest = function(stage: number)
		local payload: Remotes.WarpRequestPayload = { stage = stage }
		channels.warpRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Warp")
	end,
})

ScreenController.register("Warp", "Window", function()
	return warpWindow.root
end)

-- 열릴 때마다 지금 갈 수 있는 가장 높은 층을 다시 고른다.
-- ⚠️ 숨긴 채로 시작해야 한다. Visible=true로 만들어 두면 첫 open에서 값이 안 바뀌어 신호가 안 나고,
--    만들 때(Store가 아직 더미값일 때) 고른 층이 남는다(2026-10-22 Play: 블럭스 32인데 25층이 골라져 있었다).
warpWindow.root.Visible = false
warpWindow.root:GetPropertyChangedSignal("Visible"):Connect(function()
	if warpWindow.root.Visible then
		warpWindow.onOpen()
	end
end)

channels.warpResult.OnClientEvent:Connect(function(payload: Remotes.WarpResultPayload)
	warpWindow.onResult(payload)
end)

-- W1: 활성 런이 있으면 워프 버튼을 잠근다. 런 상태는 서버 RunStateChanged가 원본이다.
channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	warpWindow.setRunActive(payload.active)
end)
StateSync.request()

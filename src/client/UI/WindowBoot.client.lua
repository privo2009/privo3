--!strict
-- Window 층 화면(지금은 환생 창 하나)을 ScreenController에 등록하고 서버 채널에 배선한다
-- (Phase 6 지시서 #5). MenuRail의 "환생" 칸이 screenName "Rebirth"로 open한다.
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

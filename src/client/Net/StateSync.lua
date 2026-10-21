--!strict
-- "지금 상태를 다시 보내 달라" 요청 (SyncRequest, Phase 6 지시서 #5).
--
-- RunStateChanged · PlayerState를 듣는 수신부는 **리스너를 붙인 직후** 이것을 부른다.
-- 리스너가 붙기 전에 온 이벤트는 처음 붙은 리스너 하나에만 전달되므로(Shared/Remotes.lua
-- SyncRequestPayload 주석), 접속 직후 상태는 이 요청으로 받는다. 여러 수신부가 거의 동시에
-- 불러도 서버가 짧은 창 안의 요청을 하나로 모아 한 번만 답한다(PlayerStateService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local StateSync = {}

function StateSync.request()
	local channels = Remotes.getClient()
	local payload: Remotes.SyncRequestPayload = {}
	channels.syncRequest:FireServer(payload)
end

return StateSync

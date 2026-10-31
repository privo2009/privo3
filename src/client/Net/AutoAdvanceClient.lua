--!strict
-- 자동 진행 요청의 클라 쪽 한 곳 (Phase 8 지시서 #18). 설정 창(시작) · HUD 버튼(중지)이 같이 쓴다.
--
--   start(target)  AutoAdvanceRequest{action = "start", target}. 안전층 · 보상을 싣지 않는다(규약 2 — 서버가 정한다)
--   stop()         AutoAdvanceRequest{action = "stop"}
--   요청은 결과가 올 때까지(또는 PENDING_TIMEOUT_SEC) 한 번만 나간다(시작 · 중지 공용 — 둘이 엇갈리지 않게)
--   onResult(cb)   AutoAdvanceResult(요청 결과 · 서버가 끈 알림 stopped)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AutoAdvanceClient = {}

AutoAdvanceClient.PENDING_TIMEOUT_SEC = 2

export type Deps = {
	send: (payload: Remotes.AutoAdvanceRequestPayload) -> (),
	now: (() -> number)?,
}

export type Client = {
	start: (target: number) -> boolean,
	stop: () -> boolean,
	isPending: () -> boolean,
	handleResult: (payload: any) -> (),
	onResult: (callback: (Remotes.AutoAdvanceResultPayload) -> ()) -> (),
}

function AutoAdvanceClient.new(deps: Deps): Client
	local now = deps.now or os.clock
	local startedAt: number? = nil
	local listeners: { (Remotes.AutoAdvanceResultPayload) -> () } = {}
	local client = {}

	function client.isPending(): boolean
		return startedAt ~= nil and now() - (startedAt :: number) < AutoAdvanceClient.PENDING_TIMEOUT_SEC
	end

	local function send(payload: Remotes.AutoAdvanceRequestPayload): boolean
		if client.isPending() then
			return false
		end
		startedAt = now()
		deps.send(payload)
		return true
	end

	function client.start(target: number): boolean
		return send({ action = "start", target = target })
	end

	function client.stop(): boolean
		return send({ action = "stop" })
	end

	function client.handleResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.action ~= "stopped" then
			startedAt = nil -- 요청의 응답(서버가 끈 알림은 요청과 무관)
		end
		for _, cb in ipairs(listeners) do
			task.spawn(cb, payload)
		end
	end

	function client.onResult(callback: (Remotes.AutoAdvanceResultPayload) -> ())
		table.insert(listeners, callback)
	end

	return client :: Client
end

local shared: Client? = nil

function AutoAdvanceClient.get(): Client
	if shared == nil then
		local channels = Remotes.getClient()
		local client = AutoAdvanceClient.new({
			send = function(payload: Remotes.AutoAdvanceRequestPayload)
				channels.autoAdvanceRequest:FireServer(payload)
			end,
		})
		channels.autoAdvanceResult.OnClientEvent:Connect(function(payload: Remotes.AutoAdvanceResultPayload)
			client.handleResult(payload)
		end)
		shared = client
	end
	return shared :: Client
end

return AutoAdvanceClient

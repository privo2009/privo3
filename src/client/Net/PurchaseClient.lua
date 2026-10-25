--!strict
-- 로벅스 구매 요청의 클라 쪽 한 곳 (Phase 8 지시서 #16 5단계). 상점 창 로벅스 탭 · HUD 구좌 4개 · 자동 클리커 잠김이 같이 쓴다.
--
--   request(key)  PurchaseRequest{key}를 보낸다. 가격 · ID를 싣지 않는다(규약 2) — 서버가 다시 판정한다(PurchaseRequestService).
--                 같은 키는 결과가 올 때까지(또는 PENDING_TIMEOUT_SEC) 한 번만 나간다 — 연타로 프롬프트가 겹치지 않게.
--                 서버도 빈도를 자른다 — 두 겹이다(업그레이드 상점과 같은 구조).
--   onResult(cb)  PurchaseResult를 받으면 부른다(토스트 · 창 문구). 결과가 오면 그 키의 대기를 푼다.
--
-- ID 0 상품도 요청을 보낸다 — 서버가 not_registered로 답하고 토스트가 "준비 중"을 띄운다(판정을 클라에 두지 않는다).
-- ⚠️ 실제 로벅스 프롬프트는 서버가 띄운다. 테스트는 new(deps)로 보내기를 가짜로 바꾼다 — MCP로 프롬프트를 누르지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PurchaseClient = {}

PurchaseClient.PENDING_TIMEOUT_SEC = 2 -- 업그레이드 상점과 같은 값(UpgradeShopLogic) — 응답은 보통 0.1초 안에 온다

export type Deps = {
	send: (key: string) -> (),
	now: (() -> number)?,
}

export type Client = {
	request: (key: string) -> boolean, -- 보냈는가(대기 중이면 false)
	isPending: (key: string) -> boolean,
	handleResult: (payload: any) -> (), -- 결과 1건(실물은 채널이 부른다)
	onResult: (callback: (Remotes.PurchaseResultPayload) -> ()) -> (),
}

function PurchaseClient.new(deps: Deps): Client
	local now = deps.now or os.clock
	local startedAt: { [string]: number } = {}
	local listeners: { (Remotes.PurchaseResultPayload) -> () } = {}
	local client = {}

	function client.isPending(key: string): boolean
		local t = startedAt[key]
		return t ~= nil and now() - t < PurchaseClient.PENDING_TIMEOUT_SEC
	end

	function client.request(key: string): boolean
		if type(key) ~= "string" or client.isPending(key) then
			return false
		end
		startedAt[key] = now()
		deps.send(key)
		return true
	end

	function client.handleResult(payload: any)
		if type(payload) ~= "table" or type(payload.key) ~= "string" then
			return
		end
		startedAt[payload.key] = nil
		for _, cb in ipairs(listeners) do
			task.spawn(cb, payload)
		end
	end

	function client.onResult(callback: (Remotes.PurchaseResultPayload) -> ())
		table.insert(listeners, callback)
	end

	return client :: Client
end

local shared: Client? = nil

-- 실물 인스턴스(하나). 처음 부를 때 채널에 붙는다. 화면 모듈은 이것을 deps로 받는다(테스트는 new로 만든 것을 넘긴다).
function PurchaseClient.get(): Client
	if shared == nil then
		local channels = Remotes.getClient()
		local client = PurchaseClient.new({
			send = function(key: string)
				local payload: Remotes.PurchaseRequestPayload = { key = key }
				channels.purchaseRequest:FireServer(payload)
			end,
		})
		channels.purchaseResult.OnClientEvent:Connect(function(payload: Remotes.PurchaseResultPayload)
			client.handleResult(payload)
		end)
		shared = client
	end
	return shared :: Client
end

return PurchaseClient

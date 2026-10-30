--!strict
-- 포션 켜기 요청의 클라 쪽 한 곳 (Phase 8 지시서 #17 5단계). 상점 로벅스 탭 "포션" 묶음이 쓴다.
--
--   request(boost)  PotionRequest{boost}를 보낸다(종류만 — 시간 · 배수는 서버가 ShopConfig에서 찾는다, 규약 2).
--                   같은 종류는 결과가 올 때까지(또는 PENDING_TIMEOUT_SEC) 한 번만 — PurchaseClient와 같은 대기 규칙을 그대로 쓴다.
--   onResult(cb)    PotionResult를 받으면 부른다(창 문구). 보관 수 · 남은 시간은 PlayerState가 따로 보낸다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PurchaseClient = require(script.Parent.PurchaseClient)

local PotionClient = {}

PotionClient.PENDING_TIMEOUT_SEC = PurchaseClient.PENDING_TIMEOUT_SEC

-- 대기 · 결과 배선은 PurchaseClient.new와 같다 — 결과 payload의 boost를 key로 옮겨 넘긴다.
function PotionClient.new(deps: PurchaseClient.Deps): PurchaseClient.Client
	local inner = PurchaseClient.new(deps)
	local client = table.clone(inner :: any)
	client.handleResult = function(payload: any)
		if type(payload) ~= "table" or type(payload.boost) ~= "string" then
			return
		end
		local copy = table.clone(payload)
		copy.key = payload.boost
		inner.handleResult(copy)
	end
	return client :: PurchaseClient.Client
end

local shared: PurchaseClient.Client? = nil

function PotionClient.get(): PurchaseClient.Client
	if shared == nil then
		local channels = Remotes.getClient()
		local client = PotionClient.new({
			send = function(boost: string)
				local payload: Remotes.PotionRequestPayload = { boost = boost }
				channels.potionRequest:FireServer(payload)
			end,
		})
		channels.potionResult.OnClientEvent:Connect(function(payload: Remotes.PotionResultPayload)
			client.handleResult(payload)
		end)
		shared = client
	end
	return shared :: PurchaseClient.Client
end

return PotionClient

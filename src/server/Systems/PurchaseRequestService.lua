--!strict
-- 로벅스 구매 요청 채널 (PurchaseRequest → PurchaseResult, Phase 8 지시서 #16 3단계).
--
-- 클라가 보낸 것은 "이 상품을 사고 싶다"는 요청(상품 키 하나)이다. 가격 · ID를 싣지 않는다(규약 2) — 서버가 ShopConfig에서 찾는다.
-- 서버가 검증한 뒤에만 MarketplaceGateway로 프롬프트를 띄운다. 거부면 사유 코드를 그대로 돌려준다(클라가 토스트로 보인다).
--
-- 판정 순서(앞에서 걸리면 거기서 끝 — 프롬프트를 띄우지 않는다):
--   1. 빈도 — 플레이어당 MIN_INTERVAL_SEC에 1회. 넘으면 rate_limited(WarpRequestService와 같은 구조)
--   2. 키 — ShopConfig에 없는 키면 invalid_key
--   3. 이미 보유 — 그 게임패스를 가졌으면 already_owned(소유는 GamepassService 세션 값)
--   4. 제한 — 로벅스 행운 상품(paidRandom)이고 제한 유저면 restricted(S13 — 판정 실패 · 확인 전도 제한)
--   5. 미등록 — ID 0이면 not_registered(클라는 "준비 중")
--   6. 지급 불가 — 개발자 상품인데 지급 함수가 없으면 not_available(결제는 되고 지급은 안 되는 상태를 만들지 않는다 — #17이 채운다)
--   7. 프롬프트 — 게이트웨이가 실패하면 prompt_failed
--
-- 결과는 두 번 갈 수 있다: phase "prompt"(요청 판정 · 프롬프트를 띄웠는가) → 게임패스면 phase "finished"
-- (PromptGamePassPurchaseFinished — 샀으면 ok, 닫았으면 reason "cancelled"). 소유 자체는 GamepassService가 바꾸고 PlayerState가 보낸다.
-- 개발자 상품의 지급 결과는 영수증(ProductService)이 처리한다 — 이 채널로 보내지 않는다(#17).
--
-- ⚠️ 실제 로벅스 프롬프트를 테스트나 MCP로 누르지 않는다. 테스트는 MarketplaceGateway.fake()로 잰다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MarketplaceGateway = require(script.Parent.MarketplaceGateway)
local GamepassService = require(script.Parent.GamepassService)
local PolicyGate = require(script.Parent.PolicyGate)
local ProductService = require(script.Parent.ProductService)

local PurchaseRequestService = {}

local MIN_INTERVAL_SEC = 1.0
PurchaseRequestService.REASON_RATE_LIMITED = "rate_limited"
PurchaseRequestService.REASON_INVALID_KEY = "invalid_key"
PurchaseRequestService.REASON_ALREADY_OWNED = "already_owned"
PurchaseRequestService.REASON_RESTRICTED = "restricted"
PurchaseRequestService.REASON_NOT_REGISTERED = MarketplaceGateway.REASON_NOT_REGISTERED
PurchaseRequestService.REASON_NOT_AVAILABLE = "not_available"
PurchaseRequestService.REASON_CANCELLED = "cancelled"
PurchaseRequestService.PHASE_PROMPT = "prompt"
PurchaseRequestService.PHASE_FINISHED = "finished"

-- payload에서 상품 키를 꺼낸다. 형태가 틀리면 nil.
local function readKey(payload: any): string?
	if type(payload) ~= "table" or type(payload.key) ~= "string" or #payload.key == 0 or #payload.key > 64 then
		return nil
	end
	return payload.key
end

export type Deps = {
	gateway: MarketplaceGateway.Gateway,
	owns: (Player, string) -> boolean,
	isRestricted: (Player) -> boolean,
	hasGrant: (string) -> boolean,
	send: (Player, Remotes.PurchaseResultPayload) -> (),
	-- 상품표(기본 ShopConfig). 테스트가 ID를 채운 표로 바꿔 끼운다
	catalog: any?,
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local catalog = deps.catalog or ShopConfig
	local handler = {}

	local function result(key: string, kind: string, phase: string, ok: boolean, reason: string): Remotes.PurchaseResultPayload
		return { key = key, kind = kind, phase = phase, ok = ok, reason = reason }
	end

	-- 판정만(프롬프트 전). 통과면 (nil, def), 거부면 (사유, def 또는 nil)
	local function judge(player: Player, key: string?): (string?, ShopConfig.ProductDef?)
		local def = if key ~= nil then catalog.get(key) else nil
		if def == nil then
			return PurchaseRequestService.REASON_INVALID_KEY, nil
		end
		if def.kind == "gamepass" and deps.owns(player, def.key) then
			return PurchaseRequestService.REASON_ALREADY_OWNED, def
		end
		if def.paidRandom and deps.isRestricted(player) then
			return PurchaseRequestService.REASON_RESTRICTED, def
		end
		if def.id == 0 then
			return PurchaseRequestService.REASON_NOT_REGISTERED, def
		end
		if def.kind == "product" and not deps.hasGrant(def.key) then
			return PurchaseRequestService.REASON_NOT_AVAILABLE, def
		end
		return nil, def
	end

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.PurchaseResultPayload
		local key = readKey(payload)
		local shownKey = if key ~= nil then key else ""
		local out: Remotes.PurchaseResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			out = result(shownKey, "", PurchaseRequestService.PHASE_PROMPT, false, PurchaseRequestService.REASON_RATE_LIMITED)
		else
			lastAt[player] = now
			local reason, def = judge(player, key)
			local kind = if def ~= nil then def.kind else ""
			if reason ~= nil then
				out = result(shownKey, kind, PurchaseRequestService.PHASE_PROMPT, false, reason)
			else
				local d = def :: ShopConfig.ProductDef
				local ok, why
				if d.kind == "gamepass" then
					ok, why = deps.gateway.promptGamePass(player, d.id)
				else
					ok, why = deps.gateway.promptProduct(player, d.id)
				end
				out = result(shownKey, kind, PurchaseRequestService.PHASE_PROMPT, ok, if ok then "" else why)
			end
		end
		deps.send(player, out)
		return out
	end

	-- 게임패스 프롬프트가 닫혔다(샀든 안 샀든). 등록된 패스가 아니면 아무것도 보내지 않는다.
	function handler.onGamePassFinished(player: Player, passId: number, wasPurchased: boolean): Remotes.PurchaseResultPayload?
		local key = catalog.findById("gamepass", passId)
		if key == nil then
			return nil
		end
		local out = result(key, "gamepass", PurchaseRequestService.PHASE_FINISHED, wasPurchased,
			if wasPurchased then "" else PurchaseRequestService.REASON_CANCELLED)
		deps.send(player, out)
		return out
	end

	function handler.onRemoving(player: Player)
		lastAt[player] = nil
	end

	return handler
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
PurchaseRequestService._pure = {
	createHandler = createHandler,
	readKey = readKey,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function PurchaseRequestService.init()
	if initialized then
		warn("[PurchaseRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local channels = Remotes.getServer()
	local gateway = MarketplaceGateway.get()
	local handler = createHandler({
		gateway = gateway,
		owns = GamepassService.owns,
		isRestricted = PolicyGate.isPaidRandomRestricted,
		hasGrant = ProductService.hasGrant,
		send = function(player: Player, payload: Remotes.PurchaseResultPayload)
			channels.purchaseResult:FireClient(player, payload)
		end,
	})

	channels.purchaseRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = handler.onRequest(player, payload, os.clock())
		print(string.format("[PurchaseRequestService] %s(%d) 구매 요청 key=%s → ok=%s reason=%s", player.Name, player.UserId,
			out.key, tostring(out.ok), out.reason))
	end)
	gateway.onGamePassPurchaseFinished(function(player: Player, passId: number, wasPurchased: boolean)
		handler.onGamePassFinished(player, passId, wasPurchased)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)

	print(string.format("[PurchaseRequestService] 구매 요청 채널 준비 완료 (플레이어당 %.1f초에 1회)", MIN_INTERVAL_SEC))
end

return PurchaseRequestService

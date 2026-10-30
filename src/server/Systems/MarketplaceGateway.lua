--!strict
-- 로블록스 결제 API의 얇은 덮개 (Phase 8 지시서 #16 3단계). MarketplaceService · PolicyService를 **이 파일에서만** 부른다.
-- 서비스(GamepassService · ProductService · PolicyGate · PurchaseRequestService)는 이 덮개만 보고, 테스트는 fake()로 바꿔 끼운다 —
-- 실제 로벅스 구매 프롬프트를 테스트나 MCP로 누르지 않기 위해서다(지시서 #16 공통 규칙).
--
-- API 이름 · 반환은 create.roblox.com 공식 문서(2026-10-25 확인, 지시서 #15 보고)를 따른다:
--   UserOwnsGamePassAsync(userId, gamePassId) · PromptGamePassPurchase(player, gamePassId) →
--   PromptGamePassPurchaseFinished(player, gamePassId, wasPurchased) · PromptProductPurchase(player, productId) ·
--   ProcessReceipt(receiptInfo) → Enum.ProductPurchaseDecision.PurchaseGranted / NotProcessedYet ·
--   PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted
--   GetProductInfoAsync(id, Enum.InfoType.GamePass | Product) → { PriceInRobux, UserBasePriceInRobux, IsForSale, ... } — 없는 ID면 오류.
--     동시에 부르면 엔진이 요청을 묶는다(Transparent Batching). 옛 GetProductInfo는 deprecated (2026-10-30 확인, 지시서 #17)
--
-- ⚠️ ID 0(대시보드 미등록)은 여기서 막는다 — 프롬프트를 띄우지 않고 "not_registered"를 돌려준다.

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

local MarketplaceGateway = {}

MarketplaceGateway.REASON_NOT_REGISTERED = "not_registered"
MarketplaceGateway.DECISION_GRANTED = "PurchaseGranted"
MarketplaceGateway.DECISION_NOT_YET = "NotProcessedYet"

export type ReceiptInfo = { PlayerId: number, PurchaseId: string, ProductId: number, CurrencySpent: number? }

export type Gateway = {
	-- (조회 성공, 소유) — 실패면 (false, false)
	ownsGamePass: (userId: number, passId: number) -> (boolean, boolean),
	-- 프롬프트를 띄웠는가 · 사유("" 또는 not_registered · prompt_failed)
	promptGamePass: (player: Player, passId: number) -> (boolean, string),
	promptProduct: (player: Player, productId: number) -> (boolean, string),
	onGamePassPurchaseFinished: (callback: (Player, number, boolean) -> ()) -> (),
	-- 콜백은 DECISION_GRANTED / DECISION_NOT_YET 문자열을 돌려준다(실물은 Enum으로 바꿔 넘긴다)
	setProcessReceipt: (callback: (ReceiptInfo) -> string) -> (),
	-- (조회 성공, 정책 표) — 실패면 (false, nil)
	getPolicy: (player: Player) -> (boolean, any),
	-- (조회 성공, 상품 정보 표) — 실패면 (false, 오류 문구). kind = "gamepass" | "product". 양보(yield)한다
	getProductInfo: (id: number, kind: string) -> (boolean, any),
	-- Roblox Plus(S16 — 지시서 #17). Player.HasRobloxSubscription(읽기 None) · PromptRobloxSubscriptionPurchase(보안 None, 공식 예제는 서버 Script)
	hasRobloxSubscription: (player: Player) -> boolean,
	promptRobloxSubscription: (player: Player) -> (boolean, string),
}

-- ===== 실물 ======================================================================================

function MarketplaceGateway.real(): Gateway
	local gateway = {} :: Gateway
	gateway.ownsGamePass = function(userId: number, passId: number): (boolean, boolean)
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end)
		if not ok then
			return false, false
		end
		return true, owns == true
	end
	gateway.promptGamePass = function(player: Player, passId: number): (boolean, string)
		if passId == 0 then
			return false, MarketplaceGateway.REASON_NOT_REGISTERED
		end
		local ok = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
		return ok, if ok then "" else "prompt_failed"
	end
	gateway.promptProduct = function(player: Player, productId: number): (boolean, string)
		if productId == 0 then
			return false, MarketplaceGateway.REASON_NOT_REGISTERED
		end
		local ok = pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
		return ok, if ok then "" else "prompt_failed"
	end
	gateway.onGamePassPurchaseFinished = function(callback: (Player, number, boolean) -> ())
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
			callback(player, passId, wasPurchased)
		end)
	end
	-- ⚠️ ProcessReceipt는 서버 스크립트 한 곳에서만 설정한다(공식 문서). 이 함수를 부르는 곳은 ProductService.init 하나다.
	gateway.setProcessReceipt = function(callback: (ReceiptInfo) -> string)
		MarketplaceService.ProcessReceipt = function(receiptInfo: any)
			local ok, decision = pcall(callback, receiptInfo)
			if ok and decision == MarketplaceGateway.DECISION_GRANTED then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			if not ok then
				warn("[MarketplaceGateway] ERROR ProcessReceipt 처리 중 예외 — NotProcessedYet: " .. tostring(decision))
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	gateway.getPolicy = function(player: Player): (boolean, any)
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if not ok or type(info) ~= "table" then
			return false, nil
		end
		return true, info
	end
	gateway.hasRobloxSubscription = function(player: Player): boolean
		local ok, v = pcall(function()
			return (player :: any).HasRobloxSubscription
		end)
		return ok and v == true
	end
	gateway.promptRobloxSubscription = function(player: Player): (boolean, string)
		local ok = pcall(function()
			MarketplaceService:PromptRobloxSubscriptionPurchase(player)
		end)
		return ok, if ok then "" else "prompt_failed"
	end
	gateway.getProductInfo = function(id: number, kind: string): (boolean, any)
		local infoType = if kind == "gamepass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		if not ok or type(info) ~= "table" then
			return false, tostring(info)
		end
		return true, info
	end
	return gateway
end

-- ===== 가짜 (테스트 전용) =========================================================================
--
-- 표를 직접 고쳐 결과를 정한다: owned[userId][passId] = true · failOwns[passId] = true(조회 실패) · policy[userId] = 정보 표 / false(조회 실패) ·
-- productInfo[id] = 정보 표(없으면 조회 실패)
-- prompts에 띄운 프롬프트가 쌓인다. finish(player, passId, wasPurchased)로 구매 완료 이벤트를, receipt(info)로 영수증을 흉내 낸다.
export type Fake = Gateway & {
	owned: { [number]: { [number]: boolean } },
	failOwns: { [number]: boolean },
	policy: { [number]: any },
	productInfo: { [number]: any },
	subscribed: { [number]: boolean },
	prompts: { { kind: string, player: Player, id: number } },
	ownsCalls: number,
	finish: (Player, number, boolean) -> (),
	receipt: (ReceiptInfo) -> string?,
}

function MarketplaceGateway.fake(): Fake
	local fake: any = { owned = {}, failOwns = {}, policy = {}, productInfo = {}, subscribed = {}, prompts = {}, ownsCalls = 0 }
	local finishedCallbacks: { (Player, number, boolean) -> () } = {}
	local receiptCallback: ((ReceiptInfo) -> string)? = nil
	fake.ownsGamePass = function(userId: number, passId: number): (boolean, boolean)
		fake.ownsCalls += 1
		if fake.failOwns[passId] then
			return false, false
		end
		local set = fake.owned[userId]
		return true, set ~= nil and set[passId] == true
	end
	local function prompt(kind: string)
		return function(player: Player, id: number): (boolean, string)
			if id == 0 then
				return false, MarketplaceGateway.REASON_NOT_REGISTERED
			end
			table.insert(fake.prompts, { kind = kind, player = player, id = id })
			return true, ""
		end
	end
	fake.promptGamePass = prompt("gamepass")
	fake.promptProduct = prompt("product")
	fake.onGamePassPurchaseFinished = function(callback: (Player, number, boolean) -> ())
		table.insert(finishedCallbacks, callback)
	end
	fake.setProcessReceipt = function(callback: (ReceiptInfo) -> string)
		receiptCallback = callback
	end
	fake.getPolicy = function(player: Player): (boolean, any)
		local info = fake.policy[player.UserId]
		if info == false or info == nil then
			return false, nil
		end
		return true, info
	end
	fake.hasRobloxSubscription = function(player: Player): boolean
		return fake.subscribed[player.UserId] == true
	end
	fake.promptRobloxSubscription = function(player: Player): (boolean, string)
		table.insert(fake.prompts, { kind = "plus", player = player, id = 0 })
		return true, ""
	end
	fake.getProductInfo = function(id: number, _kind: string): (boolean, any)
		local info = fake.productInfo[id]
		if info == nil then
			return false, "fake: no info"
		end
		return true, info
	end
	fake.finish = function(player: Player, passId: number, wasPurchased: boolean)
		for _, cb in ipairs(finishedCallbacks) do
			cb(player, passId, wasPurchased)
		end
	end
	fake.receipt = function(info: ReceiptInfo): string?
		if receiptCallback == nil then
			return nil
		end
		return (receiptCallback :: (ReceiptInfo) -> string)(info)
	end
	return fake :: Fake
end

-- 테스트용 상품표: ShopConfig의 정의를 복사해 ID만 바꾼다(공유 Config를 고치지 않는다 — Play 중 다른 서비스가 같은 표를 본다).
-- 서비스의 deps.catalog에 넘긴다. ids에 없는 키는 ID 0(미등록)으로 친다 — 테스트가 실제 대시보드 ID와 상관없이
-- "이 상품들만 등록됐다"를 정한다(지시서 #17에서 ShopConfig에 실제 ID가 들어간 뒤로).
function MarketplaceGateway.fakeCatalog(ids: { [string]: number }): any
	local defs: { [string]: any } = {}
	for key, def in pairs(ShopConfig.Products) do
		local copy = table.clone(def :: any)
		copy.id = ids[key] or 0
		defs[key] = copy
	end
	for key in pairs(ids) do
		assert(defs[key] ~= nil, "MarketplaceGateway.fakeCatalog: 없는 키 - " .. key)
	end
	local catalog = {}
	catalog.get = function(key: any): any
		if type(key) ~= "string" then
			return nil
		end
		return defs[key]
	end
	catalog.isRegistered = function(key: any): boolean
		local def = catalog.get(key)
		return def ~= nil and def.id ~= 0
	end
	catalog.gamepassKeys = ShopConfig.gamepassKeys
	catalog.findById = function(kind: string, id: any): string?
		if type(id) ~= "number" or id == 0 then
			return nil
		end
		for key, def in pairs(defs) do
			if def.kind == kind and def.id == id then
				return key
			end
		end
		return nil
	end
	return catalog
end

-- ===== 지금 쓰는 덮개 ==============================================================================

local current: Gateway? = nil

function MarketplaceGateway.get(): Gateway
	if current == nil then
		current = MarketplaceGateway.real()
	end
	return current :: Gateway
end

return MarketplaceGateway

--!strict
-- 개발자 상품 영수증 처리 — ProcessReceipt 멱등 (Phase 8 지시서 #16 · DESIGN 9장 S2 · S3 · CLAUDE.md 절대 규칙 6).
--
-- 순서(공식 player-data-purchasing 권장 — 2026-10-25 확인):
--   1. 프로필이 아직 없으면 PROFILE_WAIT_SEC까지 기다린다. 그래도 없으면 NotProcessedYet(다음 접속 · 다른 서버로 다시 온다)
--   2. 이미 기록된 PurchaseId면 PurchaseGranted — 단, 기록이 아직 저장되지 않았으면 저장을 기다린다(못 하면 NotProcessedYet)
--   3. 메모리에 지급(상품 키 → 지급 함수). 지급 함수가 없으면 ERROR 로그 + NotProcessedYet(#17이 채운다 — 영수증은 다시 온다)
--   4. PurchaseId 기록(profile.Data.purchases — 오래된 것이 앞, 최근 Schema.LIMITS.MAX_PURCHASES개만)
--   5. 저장 확인 — Profile:Save() 뒤 OnAfterSave(last_saved_data)에 그 PurchaseId가 들어 있을 때까지(SAVE_WAIT_SEC)
--      ProfileStore 1.0.3: Profile.LastSavedData("Useful for proper developer product purchase receipt handling") · OnAfterSave
--   6. PurchaseGranted. 저장이 확인되지 않으면 NotProcessedYet — 다시 와도 2번에서 걸러져 두 번 지급하지 않는다
--
-- 콜백 설정은 이 파일의 init 하나뿐이다(MarketplaceGateway.setProcessReceipt — ProcessReceipt는 서버 한 곳만).
--
-- ===== 가짜 영수증 (Studio · Mock 프리셋 전용 — Bootstrap TEST_RECEIPTS, 지시서 #17 6단계) ==========================
--   개발자 상품 키 목록을 적고 TEST_PRESET과 함께 Play하면, 프로필이 로드될 때 그 상품의 영수증을 같은 처리 순서(process)로 흘린다
--   — 실제 결제 없이 지급 경로를 실물로 잰다. 첫 영수증은 같은 PurchaseId로 한 번 더 보내 멱등(지급 1회)도 본다.
--   Studio가 아니거나 Mock 세션이 아니면(ProfileManager.mockPreset() == nil) 무시하고 ERROR — 실제 프로필에는 절대 흘리지 않는다.
--   커밋 값 nil은 ProductGrantsTests가 잰다(켠 Play에서는 그 줄이 실패한다 — 그 Play로 테스트 개수를 세지 않는다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Schema = require(script.Parent.Parent.Data.Schema)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local MarketplaceGateway = require(script.Parent.MarketplaceGateway)

local ProductService = {}

ProductService.PROFILE_WAIT_SEC = 5
ProductService.SAVE_WAIT_SEC = 15

local GRANTED = MarketplaceGateway.DECISION_GRANTED
local NOT_YET = MarketplaceGateway.DECISION_NOT_YET

-- 지급 함수: (player, profile.Data, 상품 정의) → 지급했는가. yield하지 말 것(메모리만 바꾼다 — 저장은 이 파일이 한다).
export type Grant = (Player?, any, ShopConfig.ProductDef) -> boolean

export type Deps = {
	-- userId의 프로필(로드 중이면 기다린다). 없으면 nil
	getProfile: (userId: number, timeoutSec: number) -> any?,
	getPlayer: (userId: number) -> Player?,
	-- 저장해서 last_saved_data.purchases에 purchaseId가 들어갔는가(timeoutSec 안)
	waitSaved: (profile: any, purchaseId: string, timeoutSec: number) -> boolean,
	log: (string) -> (),
	-- 상품표(기본 ShopConfig). 테스트가 ID를 채운 표로 바꿔 끼운다
	catalog: any?,
}

local function contains(list: any, id: string): boolean
	if type(list) ~= "table" then
		return false
	end
	for _, v in ipairs(list) do
		if v == id then
			return true
		end
	end
	return false
end
ProductService.contains = contains

-- 기록하고 상한을 지킨다(오래된 것부터 버린다).
local function record(data: any, id: string)
	if type(data.purchases) ~= "table" then
		data.purchases = {}
	end
	table.insert(data.purchases, id)
	while #data.purchases > Schema.LIMITS.MAX_PURCHASES do
		table.remove(data.purchases, 1)
	end
end

local function createRuntime(deps: Deps)
	local grants: { [string]: Grant } = {}
	local catalog = deps.catalog or ShopConfig
	local runtime = {}

	function runtime.register(key: string, grant: Grant)
		local def = catalog.get(key)
		assert(def ~= nil and def.kind == "product", "ProductService.register: 개발자 상품이 아님 - " .. tostring(key))
		grants[key] = grant
	end

	function runtime.hasGrant(key: string): boolean
		return grants[key] ~= nil
	end

	function runtime.process(info: any): string
		local userId = if type(info) == "table" then info.PlayerId else nil
		local purchaseId = if type(info) == "table" then info.PurchaseId else nil
		local productId = if type(info) == "table" then info.ProductId else nil
		if type(userId) ~= "number" or type(purchaseId) ~= "string" or #purchaseId == 0 then
			deps.log("[ProductService] ERROR 영수증 형태가 이상하다 — NotProcessedYet")
			return NOT_YET
		end
		-- 1. 프로필
		local profile = deps.getProfile(userId, ProductService.PROFILE_WAIT_SEC)
		if profile == nil or type(profile.Data) ~= "table" then
			deps.log(string.format("[ProductService] 영수증 %s: 프로필 없음(UserId=%d) — NotProcessedYet", purchaseId, userId))
			return NOT_YET
		end
		local data = profile.Data
		-- 2. 이미 처리했나
		if contains(data.purchases, purchaseId) then
			if contains(profile.LastSavedData and profile.LastSavedData.purchases, purchaseId)
				or deps.waitSaved(profile, purchaseId, ProductService.SAVE_WAIT_SEC) then
				return GRANTED
			end
			deps.log(string.format("[ProductService] 영수증 %s: 처리 기록은 있으나 저장 확인 안 됨 — NotProcessedYet", purchaseId))
			return NOT_YET
		end
		-- 3. 지급
		local key = catalog.findById("product", productId)
		local def = if key ~= nil then catalog.get(key) else nil
		local grant = if key ~= nil then grants[key :: string] else nil
		if def == nil or grant == nil then
			deps.log(string.format("[ProductService] ERROR 영수증 %s: 상품 %s(key=%s)의 지급 함수가 없다 — NotProcessedYet(#17)", purchaseId, tostring(productId), tostring(key)))
			return NOT_YET
		end
		local okGrant, granted = pcall(grant, deps.getPlayer(userId), data, def :: ShopConfig.ProductDef)
		if not okGrant or granted ~= true then
			deps.log(string.format("[ProductService] ERROR 영수증 %s: 지급 실패(%s) — NotProcessedYet", purchaseId, tostring(granted)))
			return NOT_YET
		end
		-- 4. 기록
		record(data, purchaseId)
		-- 5. 저장 확인
		if not deps.waitSaved(profile, purchaseId, ProductService.SAVE_WAIT_SEC) then
			deps.log(string.format("[ProductService] 영수증 %s: 지급 · 기록했으나 저장 확인 안 됨 — NotProcessedYet(다시 오면 2번에서 걸러진다)", purchaseId))
			return NOT_YET
		end
		-- 6.
		return GRANTED
	end

	return runtime
end

ProductService._pure = { createRuntime = createRuntime, record = record }

-- ===== 런타임 ======================================================================================

local runtime: any = nil
local requestedTestReceipts: { string }? = nil
local testReceiptsRegistered = false

-- Bootstrap의 TEST_RECEIPTS 값(테스트가 커밋 값 nil을 확인하는 통로).
function ProductService.getRequestedTestReceipts(): ({ string }?, boolean)
	return requestedTestReceipts, testReceiptsRegistered
end

-- 가짜 영수증을 켤 수 있는가(순수). (켤 키 목록 또는 nil, 로그 한 줄 또는 nil)
function ProductService.resolveTestReceipts(list: any, isStudio: boolean, mockPreset: string?): ({ string }?, string?)
	if list == nil then
		return nil, nil
	end
	if not isStudio or mockPreset == nil then
		return nil, "[ProductService] ERROR TEST_RECEIPTS는 Studio + TEST_PRESET(Mock)에서만 — 무시한다. Bootstrap의 TEST_RECEIPTS를 nil로 되돌릴 것"
	end
	if type(list) ~= "table" then
		return nil, "[ProductService] ERROR TEST_RECEIPTS는 상품 키 목록이어야 한다 — 무시한다"
	end
	local keys: { string } = {}
	for _, key in ipairs(list) do
		local def = ShopConfig.get(key)
		if def ~= nil and def.kind == "product" and def.id > 0 then
			table.insert(keys, key)
		end
	end
	return keys, string.format("[ProductService] ⚠️ 가짜 영수증(Studio · Mock %s — 실제 결제 · 실제 프로필 없음): %s", mockPreset, table.concat(keys, ", "))
end

function ProductService.register(key: string, grant: Grant)
	assert(runtime ~= nil, "ProductService.register: init 전")
	runtime.register(key, grant)
end

-- 그 상품을 지금 팔아도 되는가(지급 함수가 있다). 구매 요청 채널이 본다 — 지급 못 할 상품을 결제시키지 않는다.
function ProductService.hasGrant(key: string): boolean
	return runtime ~= nil and runtime.hasGrant(key)
end

-- 실물 저장 확인: 이미 저장돼 있으면 바로 true. 아니면 Save() 뒤 OnAfterSave를 기다린다.
local function waitSaved(profile: any, purchaseId: string, timeoutSec: number): boolean
	if contains(profile.LastSavedData and profile.LastSavedData.purchases, purchaseId) then
		return true
	end
	local done = false
	local conn = profile.OnAfterSave:Connect(function(lastSaved: any)
		if contains(lastSaved and lastSaved.purchases, purchaseId) then
			done = true
		end
	end)
	profile:Save()
	local deadline = os.clock() + timeoutSec
	while not done and os.clock() < deadline and profile:IsActive() do
		task.wait(0.1)
	end
	conn:Disconnect()
	return done or contains(profile.LastSavedData and profile.LastSavedData.purchases, purchaseId)
end
ProductService._pure.waitSaved = waitSaved

local initialized = false

function ProductService.init()
	if initialized then
		return
	end
	initialized = true
	runtime = createRuntime({
		getProfile = function(userId: number, timeoutSec: number)
			local deadline = os.clock() + timeoutSec
			while true do
				local player = Players:GetPlayerByUserId(userId)
				local profile = if player ~= nil then ProfileManager.get(player) else nil
				if profile ~= nil then
					return profile
				end
				if player == nil or os.clock() >= deadline then
					return nil
				end
				task.wait(0.2)
			end
		end,
		getPlayer = function(userId: number)
			return Players:GetPlayerByUserId(userId)
		end,
		waitSaved = waitSaved,
		log = function(line: string)
			warn(line)
		end,
	})
	MarketplaceGateway.get().setProcessReceipt(function(info: any): string
		local decision = runtime.process(info)
		print(string.format("[ProductService] 영수증 %s 상품 %s → %s", tostring(info and info.PurchaseId), tostring(info and info.ProductId), decision))
		return decision
	end)
	print("[ProductService] 영수증 처리 준비 완료 (멱등 — 최근 " .. Schema.LIMITS.MAX_PURCHASES .. "개 기록 · 저장 확인 뒤 PurchaseGranted)")
end

-- 가짜 영수증 시작(위 "가짜 영수증"). init 뒤 · 지급 함수 등록 뒤에 부른다.
function ProductService.startTestReceipts(list: { string }?, isStudio: boolean)
	requestedTestReceipts = list
	testReceiptsRegistered = true
	local keys, line = ProductService.resolveTestReceipts(list, isStudio, ProfileManager.mockPreset())
	if line ~= nil then
		warn(line)
	end
	if keys == nil or runtime == nil then
		return
	end
	local function run(player: Player)
		task.spawn(function()
			for i, key in ipairs(keys :: { string }) do
				local def = ShopConfig.get(key) :: ShopConfig.ProductDef
				local info = { PlayerId = player.UserId, PurchaseId = string.format("TEST-%s-%d", key, i), ProductId = def.id, CurrencySpent = 0 }
				local decision = runtime.process(info)
				print(string.format("[ProductService] ⚠️ 가짜 영수증 %s(%s) → %s", info.PurchaseId, key, decision))
				if i == 1 then
					local again = runtime.process(info) -- 같은 영수증 다시(멱등 — 지급 1회)
					print(string.format("[ProductService] ⚠️ 가짜 영수증 %s 다시 → %s", info.PurchaseId, again))
				end
			end
		end)
	end
	ProfileManager.onLoaded(function(player: Player)
		run(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if ProfileManager.get(player) ~= nil then
			run(player)
		end
	end
end

return ProductService

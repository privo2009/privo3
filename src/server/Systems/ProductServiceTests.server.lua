--!strict
-- ProductService 검증 (지시서 #16 3단계 · DESIGN 9장 S2 · S3 · CLAUDE.md 절대 규칙 6). 가짜 프로필 · 가짜 저장 · 가짜 상품표로 굴린다 —
-- 실제 영수증 · 실제 프로필을 건드리지 않는다. 마지막 절만 ProfileStore 1.0.3 Mock 실물로 저장 확인을 잰다(서버 메모리에만 남는다).
--   같은 PurchaseId 두 번 → 지급 1회 / 프로필 미로드 · 저장 실패 → NotProcessedYet / 지급 함수 없음 → NotProcessedYet + ERROR /
--   기록 상한 100

local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Schema = require(ServerScriptService.Server.Data.Schema)
local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local ProductService = require(ServerScriptService.Server.Systems.ProductService)

local pure = ProductService._pure
local GRANTED = MarketplaceGateway.DECISION_GRANTED
local NOT_YET = MarketplaceGateway.DECISION_NOT_YET

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local IDS = { strengthPotion = 8201, damagePotion = 8202, luckyRoll5 = 8203 }
local catalog = MarketplaceGateway.fakeCatalog(IDS)
local USER = 601

-- 가짜 세계: 프로필 하나(있거나 없거나) · 저장은 saveOk일 때만 LastSavedData를 지금 Data로 바꾼다.
local function newWorld(opts: { loaded: boolean?, saveOk: boolean? }?)
	local o = opts or {}
	local w: any = { logs = {}, saveCalls = 0, saveOk = o.saveOk ~= false, grants = 0 }
	w.profile = { Data = Schema.new(), LastSavedData = { purchases = {} } }
	local loaded = o.loaded ~= false
	w.runtime = pure.createRuntime({
		getProfile = function(userId: number)
			if loaded and userId == USER then
				return w.profile
			end
			return nil
		end,
		getPlayer = function()
			return nil
		end,
		waitSaved = function(profile: any, _id: string)
			w.saveCalls += 1
			if w.saveOk then
				profile.LastSavedData = { purchases = table.clone(profile.Data.purchases) }
				return true
			end
			return false
		end,
		log = function(line: string)
			table.insert(w.logs, line)
		end,
		catalog = catalog,
	})
	w.runtime.register("strengthPotion", function(_player, data, def)
		w.grants += 1
		data.potions.strength += def.effect.count
		return true
	end)
	return w
end

local function receipt(purchaseId: string, productId: number?): any
	return { PlayerId = USER, PurchaseId = purchaseId, ProductId = productId or IDS.strengthPotion, CurrencySpent = 29 }
end

local function hasLog(w: any, needle: string): boolean
	for _, line in ipairs(w.logs) do
		if string.find(line, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- 1. 정상 · 같은 PurchaseId 두 번 → 지급 1회 ---------------------------------------------------------
do
	local w = newWorld()
	local d1 = w.runtime.process(receipt("P-1"))
	check("정상: PurchaseGranted · 지급 1 · 기록 · 저장 확인", d1 == GRANTED and w.grants == 1 and w.profile.Data.potions.strength == 1
		and w.profile.Data.purchases[1] == "P-1" and w.saveCalls == 1)
	local d2 = w.runtime.process(receipt("P-1"))
	check("같은 PurchaseId 두 번 → 지급 1회(두 번째도 PurchaseGranted)", d2 == GRANTED and w.grants == 1 and w.profile.Data.potions.strength == 1
		and #w.profile.Data.purchases == 1)
	check("이미 저장된 기록이면 저장을 다시 기다리지 않는다", w.saveCalls == 1)
	local d3 = w.runtime.process(receipt("P-2"))
	check("다른 PurchaseId는 따로 지급", d3 == GRANTED and w.grants == 2 and #w.profile.Data.purchases == 2)
end

-- 2. 프로필 미로드 → NotProcessedYet ----------------------------------------------------------------
do
	local w = newWorld({ loaded = false })
	local d = w.runtime.process(receipt("P-3"))
	check("프로필 미로드 → NotProcessedYet · 지급 0 · 저장 시도 0", d == NOT_YET and w.grants == 0 and w.saveCalls == 0 and hasLog(w, "프로필 없음"))
end

-- 3. 저장 실패 → NotProcessedYet. 다시 오면 지급 없이 저장만 확인 ----------------------------------------------
do
	local w = newWorld({ saveOk = false })
	local d = w.runtime.process(receipt("P-4"))
	check("저장 실패 → NotProcessedYet(지급 · 기록은 메모리에 남는다)", d == NOT_YET and w.grants == 1 and w.profile.Data.purchases[1] == "P-4"
		and hasLog(w, "저장 확인 안 됨"))
	local again = w.runtime.process(receipt("P-4"))
	check("저장 실패 뒤 재전달(여전히 저장 실패) → NotProcessedYet · 두 번 지급 안 함", again == NOT_YET and w.grants == 1)
	w.saveOk = true
	local later = w.runtime.process(receipt("P-4"))
	check("저장되면 재전달 → PurchaseGranted · 여전히 지급 1회", later == GRANTED and w.grants == 1 and w.profile.Data.potions.strength == 1)
end

-- 4. 지급 함수 없음 → NotProcessedYet + ERROR ------------------------------------------------------------
do
	local w = newWorld()
	local d = w.runtime.process(receipt("P-5", IDS.damagePotion))
	check("지급 함수 없음 → NotProcessedYet + ERROR · 기록 안 함", d == NOT_YET and hasLog(w, "ERROR") and #w.profile.Data.purchases == 0
		and w.saveCalls == 0)
	local unknown = w.runtime.process(receipt("P-6", 424242))
	check("모르는 상품 ID → NotProcessedYet + ERROR", unknown == NOT_YET and #w.profile.Data.purchases == 0)
	check("hasGrant: 등록한 것만 true", w.runtime.hasGrant("strengthPotion") and not w.runtime.hasGrant("damagePotion"))
	check("register: 게임패스 키는 거부(assert)", not pcall(w.runtime.register, "damage2x", function()
		return true
	end))
end

-- 5. 지급 실패 · 이상한 영수증 → NotProcessedYet ---------------------------------------------------------
do
	local w = newWorld()
	w.runtime.register("luckyRoll5", function()
		error("boom")
	end)
	local d = w.runtime.process(receipt("P-7", IDS.luckyRoll5))
	check("지급 함수가 예외 → NotProcessedYet · 기록 안 함", d == NOT_YET and #w.profile.Data.purchases == 0 and hasLog(w, "지급 실패"))
	w.runtime.register("damagePotion", function()
		return false
	end)
	check("지급 함수가 false → NotProcessedYet · 기록 안 함", w.runtime.process(receipt("P-8", IDS.damagePotion)) == NOT_YET
		and #w.profile.Data.purchases == 0)
	check("영수증 형태가 이상하면 NotProcessedYet", w.runtime.process({ PlayerId = "x" }) == NOT_YET and w.runtime.process(nil) == NOT_YET
		and w.runtime.process({ PlayerId = USER, PurchaseId = "" }) == NOT_YET)
end

-- 6. 기록 상한 ------------------------------------------------------------------------------------------
do
	local data: any = { purchases = {} }
	for i = 1, Schema.LIMITS.MAX_PURCHASES + 5 do
		pure.record(data, "R" .. i)
	end
	check("기록 상한: 최근 MAX_PURCHASES개만 · 오래된 것부터 버림", #data.purchases == Schema.LIMITS.MAX_PURCHASES and data.purchases[1] == "R6"
		and data.purchases[#data.purchases] == "R" .. (Schema.LIMITS.MAX_PURCHASES + 5))
	local fresh: any = {}
	pure.record(fresh, "X")
	check("기록: purchases가 없으면 만든다", type(fresh.purchases) == "table" and fresh.purchases[1] == "X")
	check("기록 상한 100이 Schema 검증과 같다", Schema.LIMITS.MAX_PURCHASES == 100)
end

-- 7. ProfileStore 1.0.3 Mock 실물: 저장 확인(Save → OnAfterSave → LastSavedData) ---------------------------------
do
	local store = ProfileStore.New("ProductServiceTests_Mock", Schema.getTemplate())
	local key = "t" .. tostring(math.floor(os.clock() * 1000))
	local profile = store.Mock:StartSessionAsync(key)
	check("Mock 세션 열림", profile ~= nil)
	if profile ~= nil then
		pure.record(profile.Data, "MOCK-1")
		local before = pure.waitSaved ~= nil and ProductService.contains(profile.LastSavedData and profile.LastSavedData.purchases, "MOCK-1")
		local ok = pure.waitSaved(profile, "MOCK-1", 10)
		check("Mock 실물: 저장 전 LastSavedData에 없다 → 저장 확인 뒤 들어 있다", not before and ok
			and ProductService.contains(profile.LastSavedData.purchases, "MOCK-1"))
		check("Mock 실물: 이미 저장된 기록이면 바로 true", pure.waitSaved(profile, "MOCK-1", 0))
		profile:EndSession()
	end
end

print(string.format("[ProductServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ProductServiceTests] %d test(s) failed", failed))
end

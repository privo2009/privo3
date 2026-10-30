--!strict
-- ProductGrants 검증 (지시서 #17 4단계 — DESIGN 9장 "구매 규칙 · 지급 · 사용"). 가짜 프로필(Schema.new) · 가짜 상품표로 굴린다 —
-- 실제 영수증 · 실제 프로필을 건드리지 않는다. 지급 수치는 ShopConfig에서 읽는다(Config 원본).
--   16개 등록 · 종류별 지급(포션 · 번들 · 롤 · 선해금) · 표가 없으면 실패(반쪽 지급 없음) · 영수증 순서와 함께: 같은 영수증 두 번 = 지급 1회 ·
--   선해금 중복(이미 열림) · 지급하면 알림(플레이어가 있을 때만)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Schema = require(ServerScriptService.Server.Data.Schema)
local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local ProductService = require(ServerScriptService.Server.Systems.ProductService)
local ProductGrants = require(ServerScriptService.Server.Systems.ProductGrants)

local GRANTED = MarketplaceGateway.DECISION_GRANTED

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

local function def(key: string): ShopConfig.ProductDef
	return ShopConfig.get(key) :: ShopConfig.ProductDef
end

-- 1. 종류별 지급(순수) ---------------------------------------------------------------------------------
do
	local data = Schema.new()
	check("힘 포션: potions.strength += count(1)", ProductGrants.apply(data, def("strengthPotion")) and data.potions.strength == def("strengthPotion").effect.count
		and data.potions.damage == 0 and data.potions.luck == 0)
	check("데미지 · 행운 포션: 그 종류만", ProductGrants.apply(data, def("damagePotion")) and ProductGrants.apply(data, def("luckPotion"))
		and data.potions.damage == 1 and data.potions.luck == 1 and data.potions.strength == 1)
	check("사면 바로 켜지지 않는다(부스트 없음)", #data.boosts == 0)
	local bundle = def("potionBundle").effect.counts
	check("포션 번들: 세 종류 각 counts(99)만큼", ProductGrants.apply(data, def("potionBundle")) and data.potions.strength == 1 + bundle.strength
		and data.potions.damage == 1 + bundle.damage and data.potions.luck == 1 + bundle.luck and bundle.strength == 99)
	check("럭키 롤 5 · 15: rollCredits.lucky += rolls", ProductGrants.apply(data, def("luckyRoll5")) and ProductGrants.apply(data, def("luckyRoll15"))
		and data.rollCredits.lucky == def("luckyRoll5").effect.rolls + def("luckyRoll15").effect.rolls and data.rollCredits.super == 0)
	check("슈퍼 롤 5 · 15: rollCredits.super", ProductGrants.apply(data, def("superRoll5")) and ProductGrants.apply(data, def("superRoll15"))
		and data.rollCredits.super == 20)
	local allGyms = true
	for i, key in ipairs(ShopConfig.GYM_UNLOCKS) do
		if not ProductGrants.apply(data, def(key)) or data.gymUnlocks[tostring(i)] ~= true then
			allGyms = false
		end
	end
	check("운동기구 선해금 8종: gymUnlocks[\"번호\"] = true", allGyms)
	check("이미 열린 기구를 다시 지급해도 true(결제는 됐다) · 기록 그대로", ProductGrants.apply(data, def("gymUnlock3")) and data.gymUnlocks["3"] == true)
	local ok, errs = Schema.validate(data)
	check("지급 뒤 프로필이 스키마를 통과한다", ok, table.concat(errs or {}, "; "))
end

-- 2. 표가 없거나 이상하면 실패 — 반쪽 지급 없음 -------------------------------------------------------------
do
	check("프로필 아님 → false", not ProductGrants.apply(nil, def("strengthPotion")))
	local noPotions = Schema.new()
	noPotions.potions = nil
	check("potions 없음 → 포션 · 번들 false", not ProductGrants.apply(noPotions, def("strengthPotion")) and not ProductGrants.apply(noPotions, def("potionBundle")))
	local bad = Schema.new()
	bad.potions.luck = -1
	check("번들: 한 종류가 이상하면 전부 안 더한다", not ProductGrants.apply(bad, def("potionBundle")) and bad.potions.strength == 0 and bad.potions.damage == 0)
	local noCredits = Schema.new()
	noCredits.rollCredits = nil
	check("rollCredits 없음 → 롤 false", not ProductGrants.apply(noCredits, def("superRoll5")))
	local noGyms = Schema.new()
	noGyms.gymUnlocks = nil
	check("gymUnlocks 없음 → 선해금 false", not ProductGrants.apply(noGyms, def("gymUnlock1")))
	check("게임패스 정의는 지급하지 않는다", not ProductGrants.apply(Schema.new(), def("damage2x")))
end

-- 3. 등록 · 영수증 순서와 함께 -----------------------------------------------------------------------
do
	local ids: { [string]: number } = {}
	local n = 0
	for key, d in pairs(ShopConfig.Products) do
		if d.kind == "product" then
			n += 1
			ids[key] = 9700 + n
		end
	end
	local catalog = MarketplaceGateway.fakeCatalog(ids)
	local USER = 611
	local fakePlayer: any = { Name = "GrantTest", UserId = USER }
	local profile: any = { Data = Schema.new(), LastSavedData = { purchases = {} } }
	local playerPresent = true
	local runtime = ProductService._pure.createRuntime({
		getProfile = function(userId: number)
			return if userId == USER then profile else nil
		end,
		getPlayer = function()
			return if playerPresent then fakePlayer else nil
		end,
		waitSaved = function(p: any)
			p.LastSavedData = { purchases = table.clone(p.Data.purchases) }
			return true
		end,
		log = function() end,
		catalog = catalog,
	})
	local notified = 0
	local keys = ProductGrants.registerAll({
		register = runtime.register,
		notify = function(p: any)
			if p == fakePlayer then
				notified += 1
			end
		end,
	})
	local allHave = true
	for _, key in ipairs(keys) do
		if not runtime.hasGrant(key) then
			allHave = false
		end
	end
	check("개발자 상품 16개 전부 지급 함수 등록", #keys == 16 and allHave, tostring(#keys))
	local function receipt(id: string, key: string): any
		return { PlayerId = USER, PurchaseId = id, ProductId = ids[key], CurrencySpent = 0 }
	end
	local d1 = runtime.process(receipt("G-1", "strengthPotion"))
	check("영수증 → 지급 · PurchaseGranted · 알림 1", d1 == GRANTED and profile.Data.potions.strength == 1 and notified == 1)
	local d2 = runtime.process(receipt("G-1", "strengthPotion"))
	check("같은 영수증 다시 → PurchaseGranted · 두 번 주지 않는다 · 알림 없음", d2 == GRANTED and profile.Data.potions.strength == 1 and notified == 1)
	runtime.process(receipt("G-2", "gymUnlock2"))
	local d3 = runtime.process(receipt("G-3", "gymUnlock2"))
	check("선해금 같은 기구 새 영수증 → PurchaseGranted(이미 열림 — 기록 그대로)", d3 == GRANTED and profile.Data.gymUnlocks["2"] == true)
	playerPresent = false
	local d4 = runtime.process(receipt("G-4", "superRoll15"))
	check("플레이어가 없어도(나간 뒤) 지급 · 알림은 안 한다", d4 == GRANTED and profile.Data.rollCredits.super == def("superRoll15").effect.rolls
		and notified == 3, tostring(notified))
end

-- 4. 가짜 영수증(TEST_RECEIPTS — 지시서 #17 6단계): Studio + Mock에서만 · 커밋 값 nil -------------------------------------
do
	local r = ProductService.resolveTestReceipts
	local k1, l1 = r(nil, true, "floor9")
	check("가짜 영수증: nil이면 꺼짐 · 로그 없음", k1 == nil and l1 == nil)
	local k2, l2 = r({ "strengthPotion" }, true, nil)
	check("가짜 영수증: Mock 프리셋이 없으면 무시 + ERROR(실제 프로필에 흘리지 않는다)", k2 == nil and string.find(l2 :: string, "ERROR", 1, true) ~= nil)
	local k3, l3 = r({ "strengthPotion" }, false, "floor9")
	check("가짜 영수증: Studio 밖이면 무시 + ERROR", k3 == nil and string.find(l3 :: string, "ERROR", 1, true) ~= nil)
	local k4 = r({ "strengthPotion", "damage2x", "nope", "gymUnlock5" }, true, "floor9")
	check("가짜 영수증: Studio + Mock이면 개발자 상품 키만(게임패스 · 없는 키 버림)", k4 ~= nil and #k4 == 2 and k4[1] == "strengthPotion" and k4[2] == "gymUnlock5")
	local deadline = os.clock() + 10
	local _, registered = ProductService.getRequestedTestReceipts()
	while not registered and os.clock() < deadline do
		task.wait(0.1)
		_, registered = ProductService.getRequestedTestReceipts()
	end
	local requested = ProductService.getRequestedTestReceipts()
	check("Bootstrap TEST_RECEIPTS 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)", registered and requested == nil)
end

print(string.format("[ProductGrantsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ProductGrantsTests] %d test(s) failed", failed))
end

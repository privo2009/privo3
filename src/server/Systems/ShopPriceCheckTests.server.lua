--!strict
-- ShopPriceCheck 검증 (지시서 #17 3단계 — DESIGN 9장 "가격 확인"). 가짜 게이트웨이의 productInfo로 응답을 정한다 — 실제 조회를 하지 않는다.
--   판정(같음 · 할인 전 값으로 같음 · 다름 · 판매 안 함 · 조회 실패) / 등록된 상품만 조회 · 동시 / 다름만 WARN · 요약 한 줄 · 고치지 않는다

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local ShopPriceCheck = require(ServerScriptService.Server.Systems.ShopPriceCheck)

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

-- 1. 판정 --------------------------------------------------------------------------------------------
do
	local def = ShopConfig.get("damage2x") :: ShopConfig.ProductDef
	local p = def.priceRobux
	check("같음: PriceInRobux = ShopConfig 가격 → match", ShopPriceCheck.judge(def, true, { PriceInRobux = p, IsForSale = true }).status == "match")
	check("할인: PriceInRobux가 낮아도 UserBasePriceInRobux가 같으면 match(Plus 할인)",
		ShopPriceCheck.judge(def, true, { PriceInRobux = p - 10, UserBasePriceInRobux = p }).status == "match")
	local m = ShopPriceCheck.judge(def, true, { PriceInRobux = p + 1, UserBasePriceInRobux = p + 1 })
	check("다름 → mismatch · 값 둘 다 기록", m.status == "mismatch" and m.price == p + 1 and m.basePrice == p + 1 and m.expected == p)
	check("IsForSale false → notForSale(가격이 같아도)", ShopPriceCheck.judge(def, true, { PriceInRobux = p, IsForSale = false }).status == "notForSale")
	check("조회 실패 · 표 아님 → failed", ShopPriceCheck.judge(def, false, "err").status == "failed"
		and ShopPriceCheck.judge(def, true, 5).status == "failed")
	check("줄: match는 nil · 그 밖은 WARN 한 줄(키 · ID · 두 가격)", ShopPriceCheck.lineFor(ShopPriceCheck.judge(def, true, { PriceInRobux = p })) == nil
		and string.find(ShopPriceCheck.lineFor(m) :: string, "damage2x", 1, true) ~= nil
		and string.find(ShopPriceCheck.lineFor(m) :: string, tostring(def.id), 1, true) ~= nil)
end

-- 2. 실행: 등록된 것만 · 결과 · 로그 ------------------------------------------------------------------
do
	local IDS = { damage2x = 9501, blox2x = 9502, strengthPotion = 9503, luckyRoll5 = 9504 }
	local catalog = MarketplaceGateway.fakeCatalog(IDS)
	local gateway = MarketplaceGateway.fake()
	local calls = 0
	local inner = gateway.getProductInfo
	gateway.getProductInfo = function(id: number, kind: string)
		calls += 1
		return inner(id, kind)
	end
	local function priceOf(key: string): number
		return (ShopConfig.get(key) :: ShopConfig.ProductDef).priceRobux
	end
	gateway.productInfo[IDS.damage2x] = { PriceInRobux = priceOf("damage2x"), IsForSale = true }
	gateway.productInfo[IDS.blox2x] = { PriceInRobux = priceOf("blox2x") + 50 }
	gateway.productInfo[IDS.strengthPotion] = { PriceInRobux = priceOf("strengthPotion"), IsForSale = false }
	-- luckyRoll5는 응답 없음 → 조회 실패
	local warns, prints = {}, {}
	local before = priceOf("blox2x")
	local results, summary = ShopPriceCheck.run({
		gateway = gateway,
		catalog = catalog,
		warn = function(s: string)
			table.insert(warns, s)
		end,
		print = function(s: string)
			table.insert(prints, s)
		end,
	})
	local by: { [string]: string } = {}
	for _, r in ipairs(results) do
		by[r.key] = r.status
	end
	check("실행: 등록된(ID > 0) 상품만 조회 — 4개", #results == 4 and calls == 4, tostring(#results) .. "/" .. tostring(calls))
	check("실행: 상품마다 판정", by.damage2x == "match" and by.blox2x == "mismatch" and by.strengthPotion == "notForSale" and by.luckyRoll5 == "failed")
	check("실행: WARN은 일치가 아닌 것만(3줄)", #warns == 3)
	check("실행: 요약 한 줄", #prints == 1 and prints[1] == summary and string.find(summary, "일치 1", 1, true) ~= nil
		and string.find(summary, "다름 1", 1, true) ~= nil)
	check("실행: 자동으로 고치지 않는다(ShopConfig 가격 그대로)", priceOf("blox2x") == before)
end

-- 3. 실제 표: 등록된 상품 = 39개 전부(지시서 #17 — ID 0 없음) ------------------------------------------
do
	local n = 0
	for _, def in pairs(ShopConfig.Products) do
		if def.id > 0 then
			n += 1
		end
	end
	check("실제 ShopConfig: 39개 전부 ID가 있다(서버 시작 대조 대상)", n == 39, tostring(n))
end

print(string.format("[ShopPriceCheckTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ShopPriceCheckTests] %d test(s) failed", failed))
end

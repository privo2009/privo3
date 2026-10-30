--!strict
-- 대시보드 가격 대조 (Phase 8 지시서 #17 3단계 — DESIGN.md 9장 "구매 규칙 · 지급 · 사용 > 가격 확인").
--
-- 화면 가격은 ShopConfig priceRobux다. 대시보드 가격이 바뀌었는데 ShopConfig를 안 고치면 화면과 실제 결제 금액이 갈린다.
-- 서버가 시작할 때 등록된 상품(ID > 0)마다 GetProductInfoAsync를 **한 번** 읽어 다르면 WARN 한 줄을 남긴다.
-- **자동으로 고치지 않는다**(2026-10-30 사람 결정) — 사람이 로그를 보고 ShopConfig와 대시보드 중 맞는 쪽으로 고친다.
--
-- 같다의 뜻: PriceInRobux(할인 뒤) 또는 UserBasePriceInRobux(할인 전) 중 하나가 ShopConfig 가격과 같다.
--   Roblox Plus 구독 할인(PriceDiscountDetails)이 PriceInRobux를 낮출 수 있어 할인 전 값도 본다(공식 MarketplaceService
--   GetProductInfoAsync 반환 표, 2026-10-30 확인). IsForSale이 false로 오면 판매 중이 아니다 — 그것도 WARN.
--
-- 조회는 동시에 띄운다(task.spawn) — 엔진이 요청을 묶는다(Transparent Batching, 같은 문서). 상품마다 따로 기다리면 39번 왕복이다.
-- 게이트웨이를 받는다 — 테스트는 MarketplaceGateway.fake()의 productInfo로 응답을 정한다(실제 조회를 하지 않는다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

local ShopPriceCheck = {}

ShopPriceCheck.WAIT_SEC = 30 -- 모든 조회를 기다리는 상한. 넘으면 남은 것은 failed로 센다

export type Status = "match" | "mismatch" | "notForSale" | "failed"
export type Result = {
	key: string,
	kind: string,
	id: number,
	expected: number,
	price: number?, -- PriceInRobux
	basePrice: number?, -- UserBasePriceInRobux
	status: Status,
}

local function num(v: any): number?
	return if type(v) == "number" and v == v then v else nil
end

-- 응답 하나 판정(순수).
function ShopPriceCheck.judge(def: ShopConfig.ProductDef, ok: boolean, info: any): Result
	local r: Result = { key = def.key, kind = def.kind, id = def.id, expected = def.priceRobux, status = "failed" }
	if not ok or type(info) ~= "table" then
		return r
	end
	r.price = num(info.PriceInRobux)
	r.basePrice = num(info.UserBasePriceInRobux)
	if info.IsForSale == false then
		r.status = "notForSale"
	elseif r.price == def.priceRobux or r.basePrice == def.priceRobux then
		r.status = "match"
	else
		r.status = "mismatch"
	end
	return r
end

-- 결과 한 줄(로그). match는 nil.
function ShopPriceCheck.lineFor(r: Result): string?
	if r.status == "match" then
		return nil
	end
	return string.format("[ShopPriceCheck] WARN %s %s(%s %d) ShopConfig %d R$ · 대시보드 %s(할인 전 %s) — 자동으로 고치지 않는다",
		r.status, r.key, r.kind, r.id, r.expected, tostring(r.price), tostring(r.basePrice))
end

export type Deps = {
	gateway: any, -- getProductInfo(id, kind) -> (ok, info)
	catalog: any?, -- 기본 ShopConfig
	warn: ((string) -> ())?,
	print: ((string) -> ())?,
	now: (() -> number)?,
	wait: ((number) -> ())?,
}

-- 등록된 상품 전부를 동시에 조회하고 다 올 때까지(또는 WAIT_SEC) 기다린다. 결과 목록(키 이름순)과 요약 줄을 돌려준다.
function ShopPriceCheck.run(deps: Deps): ({ Result }, string)
	local catalog = deps.catalog or ShopConfig
	local warnFn = deps.warn or warn
	local printFn = deps.print or print
	local now = deps.now or os.clock
	local waitFn = deps.wait or task.wait

	local keys: { string } = {}
	for key in pairs(ShopConfig.Products) do
		local def = catalog.get(key)
		if def ~= nil and def.id > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys)

	local results: { [string]: Result } = {}
	local pending = #keys
	for _, key in ipairs(keys) do
		local def = catalog.get(key) :: ShopConfig.ProductDef
		task.spawn(function()
			local ok, info = deps.gateway.getProductInfo(def.id, def.kind)
			results[key] = ShopPriceCheck.judge(def, ok, info)
			pending -= 1
		end)
	end
	local deadline = now() + ShopPriceCheck.WAIT_SEC
	while pending > 0 and now() < deadline do
		waitFn(0.1)
	end

	local out: { Result } = {}
	local counts = { match = 0, mismatch = 0, notForSale = 0, failed = 0 }
	for _, key in ipairs(keys) do
		local def = catalog.get(key) :: ShopConfig.ProductDef
		local r = results[key] or ShopPriceCheck.judge(def, false, nil) -- 시간 안에 안 온 것
		table.insert(out, r)
		counts[r.status] += 1
		local line = ShopPriceCheck.lineFor(r)
		if line ~= nil then
			warnFn(line)
		end
	end
	local summary = string.format("[ShopPriceCheck] %d개 — 일치 %d · 다름 %d · 판매 안 함 %d · 조회 실패 %d", #keys, counts.match, counts.mismatch,
		counts.notForSale, counts.failed)
	printFn(summary)
	return out, summary
end

return ShopPriceCheck

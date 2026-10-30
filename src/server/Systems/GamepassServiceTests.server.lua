--!strict
-- GamepassService 검증 (지시서 #16 3단계 · DESIGN 9장 S1). 가짜 게이트웨이 · 가짜 상품표(ID를 채운 복사본)로 굴린다 —
-- 실제 MarketplaceService를 부르지 않고 공유 ShopConfig도 고치지 않는다.
--   소유 조회 성공 · 실패 · 재시도 / 구매 완료 → 즉시 소유 / ID 0은 조회하지 않음 / 가짜 소유가 Studio 밖에서 무시됨 /
--   커밋된 TEST_GAMEPASSES = nil
-- ⚠️ 마지막 검사는 TEST_GAMEPASSES를 켠 Play에서 실패한다(TestPresetGateTests와 같은 방식). 그 Play로 테스트 개수를 세지 않는다.

local ServerScriptService = game:GetService("ServerScriptService")

local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local GamepassService = require(ServerScriptService.Server.Systems.GamepassService)

local pure = GamepassService._pure

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

local IDS = { damage2x = 9101, blox2x = 9102, strength8x = 9103, autoClicker = 9104 }
local catalog = MarketplaceGateway.fakeCatalog(IDS)

local function newWorld(opts: { testPasses: { string }?, isStudio: boolean? }?)
	local o = opts or {}
	local w = { gateway = MarketplaceGateway.fake(), notified = 0, logs = {} :: { string } }
	w.runtime = pure.createRuntime({
		gateway = w.gateway,
		-- 기본은 실서버 분기(실제 조회). Studio 분기(G-OWN — 실제 소유 무시)는 isStudio = true로 따로 잰다
		isStudio = o.isStudio == true,
		testPasses = o.testPasses,
		notify = function()
			w.notified += 1
		end,
		log = function(line: string)
			table.insert(w.logs, line)
		end,
		catalog = catalog,
	})
	return w
end

local playerA: any = { Name = "GamepassTestA", UserId = 501 }

-- 1. 가짜 소유 목록 판정 ----------------------------------------------------------------------
do
	local set, line = pure.resolveTestPasses(nil, true)
	check("가짜 소유: nil이면 꺼짐 · 로그 없음", set == nil and line == nil)
	local set2, line2 = pure.resolveTestPasses({ "damage2x" }, false)
	check("가짜 소유: Studio 밖이면 무시 + ERROR 로그", set2 == nil and line2 ~= nil and string.find(line2 :: string, "ERROR", 1, true) ~= nil)
	local set3, line3 = pure.resolveTestPasses({ "damage2x", "luckyRoll5", "nope" }, true)
	check("가짜 소유: Studio면 게임패스 키만 켠다(개발자 상품 · 없는 키는 버림)",
		set3 ~= nil and (set3 :: any).damage2x == true and (set3 :: any).luckyRoll5 == nil and (set3 :: any).nope == nil
			and line3 ~= nil and string.find(line3 :: string, "damage2x", 1, true) ~= nil)
	local set4, line4 = pure.resolveTestPasses("damage2x", true)
	check("가짜 소유: 목록이 아니면 무시 + ERROR 로그", set4 == nil and line4 ~= nil and string.find(line4 :: string, "ERROR", 1, true) ~= nil)
end

-- 2. 접속 조회: 성공 · ID 0은 조회 안 함 -----------------------------------------------------------
do
	local w = newWorld()
	w.gateway.owned[playerA.UserId] = { [IDS.damage2x] = true }
	w.runtime.onJoin(playerA, 0)
	check("조회 성공: 가진 패스는 소유 · 확정", w.runtime.owns(playerA, "damage2x") and w.runtime.isResolved(playerA, "damage2x"))
	check("조회 성공: 안 가진 패스는 미보유 · 확정", not w.runtime.owns(playerA, "blox2x") and w.runtime.isResolved(playerA, "blox2x"))
	check("ID 0(미등록) 패스는 조회하지 않고 미보유 · 확정(등록 4개만 조회)", w.gateway.ownsCalls == 4 and not w.runtime.owns(playerA, "rebirth2x")
		and w.runtime.isResolved(playerA, "rebirth2x"), tostring(w.gateway.ownsCalls))
	check("조회 끝에 한 번 통지", w.notified == 1)
	local keys = w.runtime.ownedKeys(playerA)
	check("ownedKeys: 보유만 · 이름순", #keys == 1 and keys[1] == "damage2x")
	w.runtime.onRemoving(playerA)
	check("나가면 지운다(소유 · 확정 모두 false)", not w.runtime.owns(playerA, "damage2x") and not w.runtime.isResolved(playerA, "damage2x"))
end

-- 3. 조회 실패 → 미보유 · 미확정 → RETRY_SEC 뒤 재조회 -------------------------------------------------
do
	local w = newWorld()
	w.gateway.owned[playerA.UserId] = { [IDS.blox2x] = true }
	w.gateway.failOwns[IDS.blox2x] = true
	w.runtime.onJoin(playerA, 100)
	check("조회 실패: 미보유 · 미확정", not w.runtime.owns(playerA, "blox2x") and not w.runtime.isResolved(playerA, "blox2x"))
	local before = w.gateway.ownsCalls
	w.runtime.tick(100 + GamepassService.RETRY_SEC - 1)
	check("재시도: RETRY_SEC 전에는 다시 조회하지 않는다", w.gateway.ownsCalls == before)
	w.runtime.tick(100 + GamepassService.RETRY_SEC)
	check("재시도: 여전히 실패면 미확정 그대로 · 실패한 것만 다시 조회", w.gateway.ownsCalls == before + 1 and not w.runtime.isResolved(playerA, "blox2x"))
	w.gateway.failOwns[IDS.blox2x] = nil
	local notifiedBefore = w.notified
	w.runtime.tick(100 + GamepassService.RETRY_SEC * 2)
	check("재시도 성공: 소유 · 확정 · 통지", w.runtime.owns(playerA, "blox2x") and w.runtime.isResolved(playerA, "blox2x") and w.notified == notifiedBefore + 1)
	local settled = w.gateway.ownsCalls
	w.runtime.tick(100 + GamepassService.RETRY_SEC * 3)
	check("재시도: 다 확정되면 더 조회하지 않는다", w.gateway.ownsCalls == settled)
end

-- 4. 게임 중 구매 완료 → 즉시 소유 -------------------------------------------------------------------
do
	local w = newWorld()
	w.runtime.onJoin(playerA, 0)
	local n = w.notified
	local key = w.runtime.onPurchaseFinished(playerA, IDS.strength8x, true)
	check("구매 완료(wasPurchased): 그 자리에서 소유 · 확정 · 통지", key == "strength8x" and w.runtime.owns(playerA, "strength8x")
		and w.runtime.isResolved(playerA, "strength8x") and w.notified == n + 1)
	local key2 = w.runtime.onPurchaseFinished(playerA, IDS.autoClicker, false)
	check("구매 취소: 소유 그대로 · 통지 없음", key2 == "autoClicker" and not w.runtime.owns(playerA, "autoClicker") and w.notified == n + 1)
	check("모르는 패스 ID: nil · 아무것도 안 바꾼다", w.runtime.onPurchaseFinished(playerA, 777, true) == nil and w.notified == n + 1)
end

-- 5. 가짜 소유: Studio에서만 ------------------------------------------------------------------------
do
	local w = newWorld({ testPasses = { "rebirth2x", "damage2x" }, isStudio = true })
	w.runtime.onJoin(playerA, 0)
	check("가짜 소유(Studio): 미등록(ID 0) 패스도 소유 · 확정", w.runtime.owns(playerA, "rebirth2x") and w.runtime.isResolved(playerA, "rebirth2x"))
	check("가짜 소유(Studio): 켠 패스는 소유 · Studio라 실제 조회 0번(G-OWN)", w.runtime.owns(playerA, "damage2x") and w.gateway.ownsCalls == 0,
		tostring(w.gateway.ownsCalls))
	check("가짜 소유(Studio): 로그 두 줄(실제 소유 무시 · 가짜 소유 안내)", #w.logs == 2)
	local outside = newWorld({ testPasses = { "rebirth2x", "damage2x" }, isStudio = false })
	outside.runtime.onJoin(playerA, 0)
	check("가짜 소유가 Studio 밖에서 무시됨: 소유 없음 · ERROR 로그", not outside.runtime.owns(playerA, "rebirth2x")
		and not outside.runtime.owns(playerA, "damage2x") and #outside.logs == 1 and string.find(outside.logs[1], "ERROR", 1, true) ~= nil)
end

-- 5b. G-OWN (2026-10-31 사람 결정): Studio는 실제 소유를 무시한다 -----------------------------------------
do
	local w = newWorld({ isStudio = true })
	w.gateway.owned[playerA.UserId] = { [IDS.damage2x] = true, [IDS.blox2x] = true, [IDS.strength8x] = true, [IDS.autoClicker] = true }
	w.runtime.onJoin(playerA, 0)
	check("G-OWN Studio: 실제로 가진 패스도 미보유 · 확정 · 조회 0번", not w.runtime.owns(playerA, "damage2x") and w.runtime.isResolved(playerA, "damage2x")
		and #w.runtime.ownedKeys(playerA) == 0 and w.gateway.ownsCalls == 0, tostring(w.gateway.ownsCalls))
	check("G-OWN Studio: 시작 로그 한 줄", table.find(w.logs, "[Gamepass] Studio — 실제 소유 무시") ~= nil)
	w.runtime.tick(1e6)
	check("G-OWN Studio: 재조회도 하지 않는다", w.gateway.ownsCalls == 0)
	w.runtime.onPurchaseFinished(playerA, IDS.blox2x, true)
	check("G-OWN Studio: 구매 완료 이벤트는 그 세션에 반영", w.runtime.owns(playerA, "blox2x") and not w.runtime.owns(playerA, "damage2x"))
	local real = newWorld({ isStudio = false })
	real.gateway.owned[playerA.UserId] = { [IDS.damage2x] = true }
	real.runtime.onJoin(playerA, 0)
	check("G-OWN 실서버: 실제 조회 그대로(가진 패스 보유) · 시작 로그 없음", real.runtime.owns(playerA, "damage2x") and real.gateway.ownsCalls == 4
		and table.find(real.logs, "[Gamepass] Studio — 실제 소유 무시") == nil)
	local fake = newWorld({ testPasses = { "rebirth2x" }, isStudio = true })
	fake.gateway.owned[playerA.UserId] = { [IDS.damage2x] = true }
	fake.runtime.onJoin(playerA, 0)
	check("G-OWN + TEST_GAMEPASSES: 가짜로 켠 패스만 보유(실제 소유는 무시) · 조회 0번", fake.runtime.owns(playerA, "rebirth2x")
		and not fake.runtime.owns(playerA, "damage2x") and fake.gateway.ownsCalls == 0)
end

-- 6. 커밋된 TEST_GAMEPASSES = nil (Bootstrap이 GamepassService.init으로 넘긴 값) -----------------------------
do
	local deadline = os.clock() + 15
	local requested, registered = GamepassService.getRequestedTestPasses()
	while not registered and os.clock() < deadline do
		task.wait(0.1)
		requested, registered = GamepassService.getRequestedTestPasses()
	end
	check("Bootstrap TEST_GAMEPASSES 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)", registered and requested == nil,
		if requested ~= nil then table.concat(requested, ",") else "nil")
end

print(string.format("[GamepassServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[GamepassServiceTests] %d test(s) failed", failed))
end

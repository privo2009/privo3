--!strict
-- PurchaseRequestService 검증 (지시서 #16 3단계). 가짜 게이트웨이 · 가짜 상품표로 굴린다 — 실제 로벅스 프롬프트를 띄우지 않는다.
--   payload 거르기 · 빈도 상한 · 판정 순서(invalid_key · already_owned · restricted · not_registered · not_available) ·
--   통과면 프롬프트 · 게임패스 프롬프트가 닫힌 결과(산 것 · 취소) · 상위 보유 거부(지시서 #17 R1 계단 · R2 자동 클리커) ·
--   운동기구 선해금 이미 열림 already_unlocked(#17)

local ServerScriptService = game:GetService("ServerScriptService")

local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local PurchaseRequestService = require(ServerScriptService.Server.Systems.PurchaseRequestService)

local pure = PurchaseRequestService._pure
local R = PurchaseRequestService

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

-- 이 표의 상품만 등록된 것으로 친다(fakeCatalog — 나머지는 ID 0). blox2x · damagePotion은 미등록.
local IDS = { damage2x = 9301, petLuck2x = 9302, strengthPotion = 9303, luckyRoll5 = 9304, strength2x = 9311, strength4x = 9312,
	strength8x = 9313, strength16x = 9314, autoClicker = 9321, autoClickerOP = 9322, gymUnlock2 = 9332, gymUnlock5 = 9335 }
local catalog = MarketplaceGateway.fakeCatalog(IDS)

local function newWorld(opts: { owned: { [string]: boolean }?, restricted: boolean?, grants: { [string]: boolean }? }?)
	local o = opts or {}
	local w: any = { gateway = MarketplaceGateway.fake(), sent = {} }
	w.handler = pure.createHandler({
		gateway = w.gateway,
		owns = function(_player, key: string)
			return o.owned ~= nil and o.owned[key] == true
		end,
		isRestricted = function()
			return o.restricted == true
		end,
		hasGrant = function(key: string)
			return o.grants ~= nil and o.grants[key] == true
		end,
		send = function(_player, payload)
			table.insert(w.sent, payload)
		end,
		catalog = catalog,
	})
	return w
end

local player: any = { Name = "PurchaseTest", UserId = 801 }
local STEP = pure.MIN_INTERVAL_SEC

-- 1. payload ---------------------------------------------------------------------------------------
check("payload: 문자열 키는 통과", pure.readKey({ key = "damage2x" }) == "damage2x")
check("payload: 숫자 · 빈 문자열 · 테이블 아님 · 너무 긴 키는 nil", pure.readKey({ key = 3 }) == nil and pure.readKey({ key = "" }) == nil
	and pure.readKey("damage2x") == nil and pure.readKey({ key = string.rep("a", 65) }) == nil)

-- 2. 판정 순서 ----------------------------------------------------------------------------------------
do
	local w = newWorld({ owned = { damage2x = true }, restricted = true, grants = { strengthPotion = true } })
	local t = 0
	local function ask(key: any)
		t += STEP
		return w.handler.onRequest(player, { key = key }, t)
	end
	local r1 = ask("nope")
	check("없는 키 → invalid_key · kind \"\"", not r1.ok and r1.reason == R.REASON_INVALID_KEY and r1.kind == "" and r1.phase == R.PHASE_PROMPT)
	local r2 = ask("damage2x")
	check("이미 가진 게임패스 → already_owned", not r2.ok and r2.reason == R.REASON_ALREADY_OWNED and r2.kind == "gamepass")
	local r3 = ask("petLuck2x")
	check("행운 상품 + 제한 유저 → restricted(ID가 있어도)", not r3.ok and r3.reason == R.REASON_RESTRICTED)
	local r4 = ask("luckyRoll5")
	check("행운 개발자 상품 + 제한 유저 → restricted", not r4.ok and r4.reason == R.REASON_RESTRICTED and r4.kind == "product")
	local r5 = ask("blox2x")
	check("ID 0 → not_registered(제한 유저라도 행운 상품이 아니면 제한과 무관)", not r5.ok and r5.reason == R.REASON_NOT_REGISTERED)
	check("거부 경로는 프롬프트를 하나도 띄우지 않는다", #w.gateway.prompts == 0)
	check("요청마다 결과 1건", #w.sent == 5)
end

do
	local w = newWorld({ grants = { strengthPotion = true } })
	local r1 = w.handler.onRequest(player, { key = "damagePotion" }, 0)
	check("ID 0인 개발자 상품 → not_registered(지급 함수 검사보다 먼저)", r1.reason == R.REASON_NOT_REGISTERED)
	local wNo = newWorld({ grants = {} })
	local r2 = wNo.handler.onRequest(player, { key = "strengthPotion" }, 0)
	check("등록됐지만 지급 함수가 없는 개발자 상품 → not_available · 프롬프트 없음", not r2.ok and r2.reason == R.REASON_NOT_AVAILABLE
		and #wNo.gateway.prompts == 0)
end

-- 3. 통과 → 프롬프트 ----------------------------------------------------------------------------------
do
	local w = newWorld({ grants = { strengthPotion = true } })
	local r1 = w.handler.onRequest(player, { key = "damage2x" }, 0)
	check("게임패스 통과 → 게임패스 프롬프트(그 ID) · ok · reason \"\"", r1.ok and r1.reason == "" and r1.kind == "gamepass"
		and #w.gateway.prompts == 1 and w.gateway.prompts[1].kind == "gamepass" and w.gateway.prompts[1].id == IDS.damage2x)
	local r2 = w.handler.onRequest(player, { key = "strengthPotion" }, STEP)
	check("개발자 상품 통과 → 상품 프롬프트(그 ID)", r2.ok and r2.kind == "product" and #w.gateway.prompts == 2
		and w.gateway.prompts[2].kind == "product" and w.gateway.prompts[2].id == IDS.strengthPotion)
	local r3 = w.handler.onRequest(player, { key = "petLuck2x" }, STEP * 2)
	check("행운 상품 + 제한 아님 → 프롬프트", r3.ok and #w.gateway.prompts == 3)
end

-- 3b. 상위 보유 거부 (지시서 #17 — 2026-10-30 사람 결정 R1 · R2) -------------------------------------------
do
	local w = newWorld({ owned = { strength8x = true, autoClickerOP = true } })
	local t = 0
	local function ask(key: string)
		t += STEP
		return w.handler.onRequest(player, { key = key }, t)
	end
	local lower = ask("strength4x")
	check("R1: 8배 보유 중 4배 → ladder_owned_higher", not lower.ok and lower.reason == R.REASON_LADDER_OWNED_HIGHER and lower.kind == "gamepass")
	local same = ask("strength8x")
	check("R1: 같은 단계는 already_owned(먼저 걸린다)", not same.ok and same.reason == R.REASON_ALREADY_OWNED)
	local auto = ask("autoClicker")
	check("R2: OP 보유 중 기본 자동 클리커 → auto_owned_higher", not auto.ok and auto.reason == R.REASON_AUTO_OWNED_HIGHER)
	check("상위 보유 거부는 프롬프트를 띄우지 않는다", #w.gateway.prompts == 0)
	local higher = ask("strength16x")
	check("R1: 더 높은 단계는 프롬프트", higher.ok and #w.gateway.prompts == 1 and w.gateway.prompts[1].id == IDS.strength16x)
	local w2 = newWorld({ owned = { autoClicker = true } })
	check("R2: 기본만 보유면 OP는 프롬프트", w2.handler.onRequest(player, { key = "autoClickerOP" }, 0).ok and #w2.gateway.prompts == 1)
end

-- 3c. 운동기구 선해금 이미 열림 (지시서 #17) ---------------------------------------------------------------
do
	local w: any = { gateway = MarketplaceGateway.fake(), sent = {} }
	local asked: { number } = {}
	w.handler = pure.createHandler({
		gateway = w.gateway,
		owns = function()
			return false
		end,
		isRestricted = function()
			return false
		end,
		hasGrant = function()
			return true
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
		gymUnlocked = function(_p, index: number)
			table.insert(asked, index)
			return index == 2 -- 기구 2는 이미 열림(환생 수 또는 선해금)
		end,
		catalog = catalog,
	})
	local r1 = w.handler.onRequest(player, { key = "gymUnlock2" }, 0)
	check("선해금: 이미 열린 기구 → already_unlocked · 프롬프트 없음", not r1.ok and r1.reason == R.REASON_ALREADY_UNLOCKED and r1.kind == "product"
		and #w.gateway.prompts == 0 and asked[1] == 2)
	local r2 = w.handler.onRequest(player, { key = "gymUnlock5" }, STEP)
	check("선해금: 안 열린 기구 → 프롬프트(그 ID)", r2.ok and #w.gateway.prompts == 1 and w.gateway.prompts[1].id == IDS.gymUnlock5)
	local r3 = w.handler.onRequest(player, { key = "damage2x" }, STEP * 2)
	check("선해금 검사는 운동기구 상품에만(다른 상품은 묻지 않는다)", r3.ok and #asked == 2)
end

-- 4. 빈도 상한 -----------------------------------------------------------------------------------------
do
	local w = newWorld()
	w.handler.onRequest(player, { key = "damage2x" }, 10)
	local r = w.handler.onRequest(player, { key = "damage2x" }, 10 + STEP * 0.5)
	check("빈도: MIN_INTERVAL_SEC 안의 두 번째 요청 → rate_limited · 프롬프트 1번만", not r.ok and r.reason == R.REASON_RATE_LIMITED
		and #w.gateway.prompts == 1 and r.key == "damage2x")
	local r2 = w.handler.onRequest(player, { key = "damage2x" }, 10 + STEP)
	check("빈도: 간격이 지나면 다시 받는다", r2.ok and #w.gateway.prompts == 2)
	local other: any = { Name = "PurchaseOther", UserId = 802 }
	check("빈도: 플레이어마다 따로", w.handler.onRequest(other, { key = "damage2x" }, 10 + STEP).ok)
	w.handler.onRemoving(player)
	check("빈도: 나가면 지운다", w.handler.onRequest(player, { key = "damage2x" }, 10 + STEP * 1.1).ok)
end

-- 5. 게임패스 프롬프트가 닫힘 ---------------------------------------------------------------------------
do
	local w = newWorld()
	local bought = w.handler.onGamePassFinished(player, IDS.damage2x, true)
	check("닫힘(샀다) → phase finished · ok · reason \"\"", bought ~= nil and bought.phase == R.PHASE_FINISHED and bought.ok and bought.reason == ""
		and bought.key == "damage2x")
	local cancelled = w.handler.onGamePassFinished(player, IDS.damage2x, false)
	check("닫힘(취소) → ok false · cancelled", cancelled ~= nil and not cancelled.ok and cancelled.reason == R.REASON_CANCELLED)
	check("모르는 패스 ID → 보내지 않는다", w.handler.onGamePassFinished(player, 555, true) == nil and #w.sent == 2)
end

-- 6. 실물 게이트웨이는 ID 0에서 프롬프트를 띄우지 않는다(MarketplaceService를 부르기 전에 막는다) ----------------------------------
do
	local real = MarketplaceGateway.real()
	local ok1, why1 = real.promptGamePass(player, 0)
	local ok2, why2 = real.promptProduct(player, 0)
	check("실물 게이트웨이: ID 0 → not_registered(프롬프트 없음)", not ok1 and why1 == MarketplaceGateway.REASON_NOT_REGISTERED
		and not ok2 and why2 == MarketplaceGateway.REASON_NOT_REGISTERED)
end

print(string.format("[PurchaseRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PurchaseRequestServiceTests] %d test(s) failed", failed))
end

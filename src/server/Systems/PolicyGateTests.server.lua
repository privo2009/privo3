--!strict
-- PolicyGate 검증 (지시서 #16 3단계 · DESIGN 9장 S13). 가짜 게이트웨이로 정책 응답을 정한다 — 실제 PolicyService를 부르지 않는다.
--   제한 판정 실패 → 제한 / 확인 전 → 제한 / 응답 false만 허용 / 나가면 지운다

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ServerScriptService = game:GetService("ServerScriptService")

local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local PolicyGate = require(ServerScriptService.Server.Systems.PolicyGate)

local pure = PolicyGate._pure

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

local function newWorld()
	local w: any = { gateway = MarketplaceGateway.fake(), notified = 0 }
	w.runtime = pure.createRuntime({
		gateway = w.gateway,
		notify = function()
			w.notified += 1
		end,
	})
	return w
end

local pOpen: any = { Name = "PolicyOpen", UserId = 701 }
local pClosed: any = { Name = "PolicyClosed", UserId = 702 }
local pFail: any = { Name = "PolicyFail", UserId = 703 }
local pOdd: any = { Name = "PolicyOdd", UserId = 704 }

do
	local w = newWorld()
	check("확인 전: 제한(행운 상품을 막는다)", w.runtime.isPaidRandomRestricted(pOpen) and not w.runtime.wasChecked(pOpen))
	w.gateway.policy[pOpen.UserId] = { ArePaidRandomItemsRestricted = false }
	w.gateway.policy[pClosed.UserId] = { ArePaidRandomItemsRestricted = true }
	w.gateway.policy[pFail.UserId] = false
	w.gateway.policy[pOdd.UserId] = {}
	w.runtime.onJoin(pOpen)
	w.runtime.onJoin(pClosed)
	w.runtime.onJoin(pFail)
	w.runtime.onJoin(pOdd)
	check("응답 false → 제한 아님 · 확인됨", not w.runtime.isPaidRandomRestricted(pOpen) and w.runtime.wasChecked(pOpen))
	check("응답 true → 제한 · 확인됨", w.runtime.isPaidRandomRestricted(pClosed) and w.runtime.wasChecked(pClosed))
	check("제한 판정 실패 → 제한 · 확인 안 됨", w.runtime.isPaidRandomRestricted(pFail) and not w.runtime.wasChecked(pFail))
	check("응답에 필드가 없으면 → 제한(false일 때만 연다)", w.runtime.isPaidRandomRestricted(pOdd))
	check("판정마다 한 번 통지(PlayerState가 다시 보낸다)", w.notified == 4)
	w.runtime.onRemoving(pOpen)
	check("나가면 지운다 → 다시 확인 전(제한)", w.runtime.isPaidRandomRestricted(pOpen) and not w.runtime.wasChecked(pOpen))
end

-- 가짜 제한 판정(지시서 #27 — TEST_PAID_RANDOM_RESTRICTED, Studio 전용)
do
	local resolve = pure.resolveTestRestricted
	local v0, l0 = resolve(nil, true)
	local vT, lT = resolve(true, true)
	local vF = resolve(false, true)
	local vX, lX = resolve(true, false)
	local vS, lS = resolve("yes", true)
	check("가짜 제한: nil이면 없음(줄 없음) · Studio true · false는 그 값 + 경고 줄", v0 == nil and l0 == nil and vT == true and lT ~= nil and vF == false)
	check("가짜 제한: Studio 밖 · boolean 아님은 무시 + ERROR", vX == nil and string.find(lX :: string, "ERROR", 1, true) ~= nil and vS == nil
		and string.find(lS :: string, "ERROR", 1, true) ~= nil)
	local wT: any = { gateway = MarketplaceGateway.fake(), notified = 0 }
	wT.runtime = pure.createRuntime({ gateway = wT.gateway, forced = true, notify = function()
		wT.notified += 1
	end })
	wT.gateway.policy[pOpen.UserId] = { ArePaidRandomItemsRestricted = false }
	wT.runtime.onJoin(pOpen)
	local wF: any = { gateway = MarketplaceGateway.fake(), notified = 0 }
	wF.runtime = pure.createRuntime({ gateway = wF.gateway, forced = false, notify = function()
		wF.notified += 1
	end })
	wF.gateway.policy[pFail.UserId] = false -- 조회 실패(정상이면 제한)
	wF.runtime.onJoin(pFail)
	check("가짜 제한 true: 응답이 false여도 제한 · 실제 확인 아님 · 통지 1", wT.runtime.isPaidRandomRestricted(pOpen) and not wT.runtime.wasChecked(pOpen)
		and wT.notified == 1)
	check("가짜 제한 false: 응답을 묻지 않고 제한 아님", not wF.runtime.isPaidRandomRestricted(pFail) and wF.notified == 1)
	local deadline = os.clock() + 15
	local req, registered = PolicyGate.getRequestedTestRestricted()
	while not registered and os.clock() < deadline do
		task.wait(0.1)
		req, registered = PolicyGate.getRequestedTestRestricted()
	end
	check("Bootstrap TEST_PAID_RANDOM_RESTRICTED 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)", registered and req == nil, tostring(req))
end

print(string.format("[PolicyGateTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PolicyGateTests] %d test(s) failed", failed))
end

--!strict
-- PolicyGate 검증 (지시서 #16 3단계 · DESIGN 9장 S13). 가짜 게이트웨이로 정책 응답을 정한다 — 실제 PolicyService를 부르지 않는다.
--   제한 판정 실패 → 제한 / 확인 전 → 제한 / 응답 false만 허용 / 나가면 지운다

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

print(string.format("[PolicyGateTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PolicyGateTests] %d test(s) failed", failed))
end

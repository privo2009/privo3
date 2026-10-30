--!strict
-- PlusPromptService 검증 (S16 — 지시서 #17). 가짜 게이트웨이로 굴린다 — 실제 구독 프롬프트를 띄우지 않는다.
--   꺼짐이면 아무것도 안 띄움 · 커밋된 플래그 = false / 켜짐: 세션 한 번 · 구독자 제외 · 모르는 이유 거부 · 나가면 지움 · 환생 알림 배선

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local PlusPromptService = require(ServerScriptService.Server.Systems.PlusPromptService)
local RebirthService = require(ServerScriptService.Server.Systems.RebirthService)

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

local function newWorld(enabled: boolean)
	local w: any = { gateway = MarketplaceGateway.fake(), logs = {} }
	w.runtime = PlusPromptService._pure.createRuntime({
		enabled = enabled,
		gateway = w.gateway,
		log = function(s: string)
			table.insert(w.logs, s)
		end,
	})
	return w
end

local pA: any = { Name = "PlusA", UserId = 901 }
local pB: any = { Name = "PlusB", UserId = 902 }

check("커밋된 ShopConfig.PLUS_PROMPT_ENABLED = false(켜는 시점은 사람 — Studio 동작 문서 없음)", ShopConfig.PLUS_PROMPT_ENABLED == false)

do
	local w = newWorld(false)
	check("꺼짐: 환생 · 상점 둘 다 disabled · 프롬프트 0", w.runtime.request(pA, "rebirth") == "disabled" and w.runtime.request(pA, "shop") == "disabled"
		and #w.gateway.prompts == 0)
end

do
	local w = newWorld(true)
	check("켜짐: 첫 기회(환생) → 띄움", w.runtime.request(pA, "rebirth") == "prompted" and #w.gateway.prompts == 1
		and w.gateway.prompts[1].kind == "plus")
	check("켜짐: 같은 세션 두 번째(상점) → already · 안 띄움", w.runtime.request(pA, "shop") == "already" and #w.gateway.prompts == 1)
	w.gateway.subscribed[pB.UserId] = true
	check("켜짐: 이미 구독자 → subscribed · 안 띄움", w.runtime.request(pB, "shop") == "subscribed" and #w.gateway.prompts == 1)
	check("켜짐: 모르는 이유 → invalid", w.runtime.request(pA, "spam") == "invalid")
	w.runtime.onRemoving(pA)
	check("켜짐: 나갔다 다시 오면(새 세션) 다시 한 번", w.runtime.request(pA, "shop") == "prompted" and #w.gateway.prompts == 2)
end

-- 환생 알림 배선: 등록만 확인(실제 환생은 부르지 않는다 — 프로필을 바꾸지 않는다)
check("RebirthService.onRebirthed가 있다(Plus 기회 — 성공에만 부른다)", type(RebirthService.onRebirthed) == "function")

print(string.format("[PlusPromptServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PlusPromptServiceTests] %d test(s) failed", failed))
end

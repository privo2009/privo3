--!strict
-- Roblox Plus 구독 프롬프트 (S16 — Phase 8 지시서 #17 · DESIGN.md 9장 "Roblox Plus 유치").
--
-- 세션에 한 번, 기회가 오면 띄운다: 환생 직후(RebirthService.onRebirthed) 또는 상점을 열 때(클라 PlusPromptRequest{reason="shop"}).
-- 이미 구독자(Player.HasRobloxSubscription)면 띄우지 않는다. 띄웠으면 그 세션에서는 다시 띄우지 않는다(닫았든 샀든).
--
-- ⚠️ ShopConfig.PLUS_PROMPT_ENABLED = false(커밋 값). 꺼져 있으면 아무것도 띄우지 않고 판정만 "disabled"로 돌려준다.
--    Studio 동작이 공식 문서에 없고 실제 구독(결제) 프롬프트라 MCP로 잴 수 없어서다(DESIGN 9장 · docs/PENDING.md).
-- 판정 순서: disabled → invalid(모르는 이유) → already(이 세션에 이미 띄움) → subscribed → prompted(또는 prompt_failed)
-- 실제 API는 MarketplaceGateway(hasRobloxSubscription · promptRobloxSubscription) — 테스트는 fake()로 바꿔 끼운다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MarketplaceGateway = require(script.Parent.MarketplaceGateway)

local PlusPromptService = {}

PlusPromptService.REASONS = { rebirth = true, shop = true } :: { [string]: boolean }

export type Deps = {
	enabled: boolean,
	gateway: any, -- hasRobloxSubscription · promptRobloxSubscription
	log: (string) -> (),
}

local function createRuntime(deps: Deps)
	local prompted: { [Player]: boolean } = {}
	local runtime = {}

	-- 기회 한 번. 결과 코드를 돌려준다.
	function runtime.request(player: Player, reason: any): string
		if not deps.enabled then
			return "disabled"
		end
		if type(reason) ~= "string" or not PlusPromptService.REASONS[reason] then
			return "invalid"
		end
		if prompted[player] then
			return "already"
		end
		if deps.gateway.hasRobloxSubscription(player) then
			prompted[player] = true -- 구독자에게는 이 세션에 다시 묻지 않는다
			return "subscribed"
		end
		prompted[player] = true
		local ok = deps.gateway.promptRobloxSubscription(player)
		deps.log(string.format("[PlusPrompt] %s(%d) 프롬프트 %s (%s)", player.Name, player.UserId, if ok then "띄움" else "실패", reason))
		return if ok then "prompted" else "prompt_failed"
	end

	function runtime.onRemoving(player: Player)
		prompted[player] = nil
	end

	return runtime
end

PlusPromptService._pure = { createRuntime = createRuntime }

local initialized = false

-- onRebirthed: RebirthService.onRebirthed(Bootstrap이 넘긴다 — 순환 require를 피한다)
function PlusPromptService.init(onRebirthed: ((Player) -> ()) -> ())
	if initialized then
		warn("[PlusPromptService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local runtime = createRuntime({
		enabled = ShopConfig.PLUS_PROMPT_ENABLED == true,
		gateway = MarketplaceGateway.get(),
		log = print,
	})
	local channels = Remotes.getServer()
	channels.plusPromptRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		runtime.request(player, if type(payload) == "table" then payload.reason else nil)
	end)
	onRebirthed(function(player: Player)
		runtime.request(player, "rebirth")
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)
	if ShopConfig.PLUS_PROMPT_ENABLED then
		print("[PlusPrompt] 켜짐 — 세션에 한 번(환생 직후 · 상점 열기) · 구독자 제외")
	else
		print("[PlusPrompt] 꺼짐 — ShopConfig.PLUS_PROMPT_ENABLED = false(Studio 동작 문서 없음 · 실제 구독 프롬프트 — 켜는 시점은 사람)")
	end
end

return PlusPromptService

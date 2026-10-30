--!strict
-- 포션 켜기 요청 채널 (PotionRequest → PotionResult, Phase 8 지시서 #17 4단계 — DESIGN.md 9장 "구매 규칙 · 지급 · 사용").
--
-- 포션은 사면 보관함(profile.Data.potions)에 들어가고, 이 채널로 하나씩 켠다: 보관함 −1 → BoostService에 15분 더하기
-- (같은 종류가 켜져 있으면 시간만 더한다 — S7). 클라가 보낸 것은 종류 하나뿐이다(규약 2 — 시간 · 배수는 ShopConfig.BOOSTS).
--
-- 판정 순서(앞에서 걸리면 거기서 끝 — 보관함을 건드리지 않는다):
--   1. 빈도 — 플레이어당 MIN_INTERVAL_SEC에 1회 → rate_limited
--   2. 형태 · 종류 — ShopConfig.BOOSTS에 없는 종류 → invalid
--   3. 제한 — 로벅스 행운 상품인 포션(행운)이고 제한 유저면 restricted(S13 — 보관함 그대로)
--   4. 보관 — 0개면 none_owned
--   5. 켜기 — 보관함 −1 → 부스트 더하기. 더하기가 실패하면(프로필 없음 등) 보관함을 되돌리고 invalid
-- 켜면 PlayerState에 알린다(보관 수 · 남은 시간이 다음 틱에 간다). 저장은 하지 않는다 — 포션 1개는 자동 저장 주기에 맡긴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PotionRequestService = {}

local MIN_INTERVAL_SEC = 0.5
PotionRequestService.REASON_RATE_LIMITED = "rate_limited"
PotionRequestService.REASON_INVALID = "invalid"
PotionRequestService.REASON_RESTRICTED = "restricted"
PotionRequestService.REASON_NONE_OWNED = "none_owned"

local function readBoost(payload: any): string?
	if type(payload) ~= "table" or type(payload.boost) ~= "string" or #payload.boost > 32 then
		return nil
	end
	return if ShopConfig.BOOSTS[payload.boost] ~= nil then payload.boost else nil
end

export type Deps = {
	getData: (Player) -> any?,
	isRestricted: (Player) -> boolean,
	addBoost: (Player, string) -> boolean,
	notify: (Player) -> (),
	send: (Player, Remotes.PotionResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	local function judgeAndUse(player: Player, boost: string?): string?
		if boost == nil then
			return PotionRequestService.REASON_INVALID
		end
		local def = ShopConfig.BOOSTS[boost]
		if def.paidRandom and deps.isRestricted(player) then
			return PotionRequestService.REASON_RESTRICTED
		end
		local data = deps.getData(player)
		local potions = if type(data) == "table" then data.potions else nil
		local have = if type(potions) == "table" then potions[boost] else nil
		if type(have) ~= "number" or have < 1 then
			return PotionRequestService.REASON_NONE_OWNED
		end
		potions[boost] = have - 1
		if not deps.addBoost(player, boost) then
			potions[boost] = have -- 되돌린다 — 켜지 못한 포션을 잃지 않는다
			return PotionRequestService.REASON_INVALID
		end
		return nil
	end

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.PotionResultPayload
		local boost = readBoost(payload)
		local shown = if boost ~= nil then boost else ""
		local out: Remotes.PotionResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			out = { boost = shown, ok = false, reason = PotionRequestService.REASON_RATE_LIMITED }
		else
			lastAt[player] = now
			local reason = judgeAndUse(player, boost)
			out = { boost = shown, ok = reason == nil, reason = reason or "" }
			if reason == nil then
				deps.notify(player)
			end
		end
		deps.send(player, out)
		return out
	end

	function handler.onRemoving(player: Player)
		lastAt[player] = nil
	end

	return handler
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
PotionRequestService._pure = {
	createHandler = createHandler,
	readBoost = readBoost,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

export type InitDeps = {
	getData: (Player) -> any?,
	isRestricted: (Player) -> boolean,
	addBoost: (Player, string) -> boolean,
	notify: (Player) -> (),
}

-- 서비스를 Bootstrap이 넘긴다(PlayerStateService가 이 파일보다 많은 것을 require해서 순환을 피한다).
function PotionRequestService.init(services: InitDeps)
	if initialized then
		warn("[PotionRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local channels = Remotes.getServer()
	local handler = createHandler({
		getData = services.getData,
		isRestricted = services.isRestricted,
		addBoost = services.addBoost,
		notify = services.notify,
		send = function(player: Player, payload: Remotes.PotionResultPayload)
			channels.potionResult:FireClient(player, payload)
		end,
	})
	channels.potionRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = handler.onRequest(player, payload, os.clock())
		print(string.format("[PotionRequestService] %s(%d) 포션 켜기 %s → ok=%s reason=%s", player.Name, player.UserId, out.boost,
			tostring(out.ok), out.reason))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)
	print(string.format("[PotionRequestService] 포션 켜기 채널 준비 완료 (플레이어당 %.1f초에 1회)", MIN_INTERVAL_SEC))
end

return PotionRequestService

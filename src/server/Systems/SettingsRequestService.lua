--!strict
-- 설정 창의 요청 채널 (SettingsRequest → SettingsResult, Phase 7 지시서 #11 A8).
--
-- 범용 채널이다 — 키 하나 · 값 하나. **허용 키 화이트리스트(ALLOWED)**에 있는 키만, 그 키의 타입인 값만 받는다.
-- 지금 허용 키는 hideOtherAuras(#11) · hideOtherPets(#12 E10) 둘이다. 둘 다 boolean.
-- 저장 자리는 profile.Data.cosmetics[key]. 설정은 표시 취향이라 게임 판정에 쓰지 않는다(절대 규칙 3과 충돌 없음).
-- 이 파일이 cosmetics.hideOther* 를 쓰는 유일한 곳이다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)

local SettingsRequestService = {}

local MIN_INTERVAL_SEC = 0.25
SettingsRequestService.REASON_RATE_LIMITED = "rate_limited"
SettingsRequestService.REASON_NOT_ALLOWED = "not_allowed"
SettingsRequestService.REASON_BAD_VALUE = "bad_value"
SettingsRequestService.REASON_NO_PROFILE = "no_profile"

-- 허용 키 → 값 타입.
local ALLOWED: { [string]: string } = {
	hideOtherAuras = "boolean",
	hideOtherPets = "boolean",
}
SettingsRequestService.ALLOWED = ALLOWED

export type Deps = {
	getCosmetics: (Player) -> any?,
	send: (Player, Remotes.SettingsResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.SettingsResultPayload
		local key = if type(payload) == "table" and type(payload.key) == "string" and #payload.key <= 64 then payload.key else ""
		local function out(ok: boolean, reason: string, value: boolean): Remotes.SettingsResultPayload
			local r: Remotes.SettingsResultPayload = { ok = ok, reason = reason, key = key, value = value }
			deps.send(player, r)
			return r
		end
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			return out(false, SettingsRequestService.REASON_RATE_LIMITED, false)
		end
		lastAt[player] = now
		local kind = ALLOWED[key]
		if kind == nil then
			return out(false, SettingsRequestService.REASON_NOT_ALLOWED, false)
		end
		local value = payload.value
		if type(value) ~= kind then
			return out(false, SettingsRequestService.REASON_BAD_VALUE, false)
		end
		local cosmetics = deps.getCosmetics(player)
		if type(cosmetics) ~= "table" then
			return out(false, SettingsRequestService.REASON_NO_PROFILE, false)
		end
		cosmetics[key] = value
		return out(true, "", value)
	end

	function handler.onRemoving(player: Player)
		lastAt[player] = nil
	end

	return handler
end

SettingsRequestService._pure = {
	createHandler = createHandler,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function SettingsRequestService.init()
	if initialized then
		warn("[SettingsRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local channels = Remotes.getServer()
	local handler = createHandler({
		getCosmetics = function(player: Player)
			local profile = ProfileManager.get(player)
			return if profile ~= nil then profile.Data.cosmetics else nil
		end,
		send = function(player: Player, payload: Remotes.SettingsResultPayload)
			channels.settingsResult:FireClient(player, payload)
		end,
	})
	channels.settingsRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local r = handler.onRequest(player, payload, os.clock())
		print(string.format("[SettingsRequestService] %s(%d) %s = %s → %s", player.Name, player.UserId, r.key, tostring(r.value), if r.ok then "저장" else ("거부 " .. r.reason)))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)
	print("[SettingsRequestService] 설정 채널 준비 완료 (허용 키: hideOtherAuras · hideOtherPets)")
end

return SettingsRequestService

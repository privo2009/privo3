--!strict
-- 아우라 창의 요청 채널 (AuraRequest → AuraResult, Phase 7 지시서 #11).
--
-- 이 파일은 payload 형태와 빈도만 거르고, 가능 여부(팩 해금 · 잔액 · 롤 시계 · 보유)는 AuraService가 **다시 판정한다**
-- (CLAUDE.md 절대 규칙 3). 사유 코드는 그대로 돌려준다. 결과는 요청한 플레이어에게 1건만(결과 연출용) — 브로드캐스트하지 않는다.
--
-- 빈도 두 겹: 채널(플레이어당 MIN_INTERVAL_SEC에 요청 1회) + 롤 시계(AuraConfig.ROLL_INTERVAL_SEC). 클라도 결과 대기 중 잠근다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RollService = require(script.Parent.RollService)
local AuraService = require(script.Parent.AuraService)

local AuraRequestService = {}

local MIN_INTERVAL_SEC = 0.2 -- 롤 시계(0.25초)보다 짧게 — 정상 반복 롤을 채널이 먼저 막지 않게(Claude 판단)
AuraRequestService.REASON_RATE_LIMITED = "rate_limited"

local MAX_ID_LEN = 64
local MAX_PACK = 99
local ACTIONS: { [string]: boolean } = { roll = true, equip = true, selectPack = true }

export type Request = { action: string, pack: number?, auraId: string? }

local function readPack(v: any): number?
	if type(v) ~= "number" or v ~= v or v % 1 ~= 0 or v < 1 or v > MAX_PACK then
		return nil
	end
	return v
end

local function readRequest(payload: any): Request?
	if type(payload) ~= "table" then
		return nil
	end
	local action = payload.action
	if type(action) ~= "string" or not ACTIONS[action] then
		return nil
	end
	if action == "equip" then
		local id = payload.auraId
		if type(id) ~= "string" or #id == 0 or #id > MAX_ID_LEN then
			return nil
		end
		return { action = action, auraId = id }
	end
	local pack = readPack(payload.pack)
	if pack == nil then
		return nil
	end
	return { action = action, pack = pack }
end

local function result(action: string, ok: boolean, reason: string?, r: any?): Remotes.AuraResultPayload
	return {
		action = action,
		ok = ok,
		reason = reason or "",
		auraId = if r ~= nil and type(r.auraId) == "string" then r.auraId else "",
		packId = if r ~= nil and type(r.packId) == "number" then r.packId else 0,
		tier = if r ~= nil and type(r.tier) == "number" then r.tier else 0,
		isNew = r ~= nil and r.isNew == true,
		equipped = r ~= nil and r.equipped == true,
	}
end

export type Deps = {
	roll: (Player, number) -> (boolean, any),
	equip: (Player, string) -> (boolean, string?),
	selectPack: (Player, number) -> (boolean, string?),
	send: (Player, Remotes.AuraResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.AuraResultPayload
		local req = readRequest(payload)
		local shownAction = if req ~= nil then req.action
			elseif type(payload) == "table" and type(payload.action) == "string" and ACTIONS[payload.action] then payload.action
			else ""
		local out: Remotes.AuraResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			out = result(shownAction, false, AuraRequestService.REASON_RATE_LIMITED)
		elseif req == nil then
			lastAt[player] = now
			out = result(shownAction, false, RollService.REASON_INVALID)
		else
			lastAt[player] = now
			if req.action == "roll" then
				local ok, value = deps.roll(player, req.pack :: number)
				if ok and type(value) == "table" then
					out = result("roll", true, nil, value)
				else
					out = result("roll", false, if type(value) == "string" then value else "unknown")
				end
			elseif req.action == "equip" then
				local ok, reason = deps.equip(player, req.auraId :: string)
				out = result("equip", ok, if ok then nil else (reason or "unknown"), if ok then { auraId = req.auraId, equipped = true } else nil)
			else
				local ok, reason = deps.selectPack(player, req.pack :: number)
				out = result("selectPack", ok, if ok then nil else (reason or "unknown"), if ok then { packId = req.pack } else nil)
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

AuraRequestService._pure = {
	createHandler = createHandler,
	readRequest = readRequest,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function AuraRequestService.init()
	if initialized then
		warn("[AuraRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local channels = Remotes.getServer()
	local handler = createHandler({
		roll = function(player: Player, pack: number)
			return AuraService.roll(player, pack, "manual")
		end,
		equip = AuraService.equip,
		selectPack = AuraService.selectPack,
		send = function(player: Player, payload: Remotes.AuraResultPayload)
			channels.auraResult:FireClient(player, payload)
		end,
	})
	channels.auraRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = handler.onRequest(player, payload, os.clock())
		if not out.ok then
			print(string.format("[AuraRequestService] %s(%d) 요청 action=%s → 거부 reason=%s", player.Name, player.UserId, out.action, out.reason))
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)
	print(string.format("[AuraRequestService] 아우라 요청 채널 준비 완료 (플레이어당 %.2f초에 1회)", MIN_INTERVAL_SEC))
end

return AuraRequestService

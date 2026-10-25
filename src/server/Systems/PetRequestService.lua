--!strict
-- 펫 창의 요청 채널 (PetRequest → PetResult, Phase 7 지시서 #12).
--
-- 이 파일은 payload 형태와 빈도만 거르고, 가능 여부(해금 · 저장 공간 · 잔액 · 롤 시계 · 보유 · 슬롯 · 재료)는 PetService가
-- **다시 판정한다**(CLAUDE.md 절대 규칙 3). 사유 코드는 그대로 돌려준다. 결과는 요청한 플레이어에게 1건만 — 브로드캐스트하지 않는다.
--
-- 빈도 두 겹: 채널(플레이어당 MIN_INTERVAL_SEC에 요청 1회) + 롤 시계(PetConfig.HATCH_INTERVAL_SEC — 부화만). 클라도 결과 대기 중 잠근다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RollService = require(script.Parent.RollService)
local PetService = require(script.Parent.PetService)

local PetRequestService = {}

local MIN_INTERVAL_SEC = 0.2 -- 롤 시계(0.25초)보다 짧게 — 정상 반복 부화를 채널이 먼저 막지 않게(AuraRequest와 같다)
PetRequestService.REASON_RATE_LIMITED = "rate_limited"

local MAX_UID_LEN = 12 -- tostring(nextUid). 10^12마리는 오지 않는다
local MAX_EGG = 99
-- action → 필요한 필드
local ACTIONS: { [string]: string } = {
	hatch = "egg",
	hatch3 = "egg", -- 3배 부화(S18 — 게임패스는 PetService가 다시 판정한다). 창 버튼은 #17
	equip = "uid",
	unequip = "uid",
	equipBest = "none",
	craft = "uid",
	release = "uid",
}
PetRequestService.ACTIONS = ACTIONS

export type Request = { action: string, egg: number?, uid: string? }

local function readRequest(payload: any): Request?
	if type(payload) ~= "table" then
		return nil
	end
	local action = payload.action
	if type(action) ~= "string" then
		return nil
	end
	local need = ACTIONS[action]
	if need == nil then
		return nil
	end
	if need == "egg" then
		local egg = payload.egg
		if type(egg) ~= "number" or egg ~= egg or egg % 1 ~= 0 or egg < 1 or egg > MAX_EGG then
			return nil
		end
		return { action = action, egg = egg }
	elseif need == "uid" then
		local uid = payload.uid
		if type(uid) ~= "string" or #uid == 0 or #uid > MAX_UID_LEN or string.find(uid, "^%d+$") == nil then
			return nil
		end
		return { action = action, uid = uid }
	end
	return { action = action }
end

local function entryOf(r: any): Remotes.PetResultEntry
	return {
		uid = if type(r.uid) == "string" then r.uid else "",
		petId = if type(r.petId) == "string" then r.petId else "",
		rarity = if type(r.rarity) == "number" then r.rarity else 0,
		level = if type(r.level) == "number" then r.level else 0,
		isNew = r.isNew == true,
		equipped = r.equipped == true,
	}
end

-- r = 결과 펫 하나(앞의 필드들), list = 부화한 펫 전부(3배 부화 — 결과 1건에 3마리. 보통 부화는 1마리, 그 밖은 빈 목록)
local function result(action: string, ok: boolean, reason: string?, r: any?, list: { any }?): Remotes.PetResultPayload
	local pets: { Remotes.PetResultEntry } = {}
	for _, e in ipairs(list or {}) do
		table.insert(pets, entryOf(e))
	end
	return {
		action = action,
		ok = ok,
		reason = reason or "",
		uid = if r ~= nil and type(r.uid) == "string" then r.uid else "",
		petId = if r ~= nil and type(r.petId) == "string" then r.petId else "",
		eggId = if r ~= nil and type(r.eggId) == "number" then r.eggId else 0,
		rarity = if r ~= nil and type(r.rarity) == "number" then r.rarity else 0,
		level = if r ~= nil and type(r.level) == "number" then r.level else 0,
		isNew = r ~= nil and r.isNew == true,
		equipped = r ~= nil and r.equipped == true,
		pets = pets,
	}
end

export type Deps = {
	hatch: (Player, number) -> (boolean, any),
	hatchMulti: ((Player, number) -> (boolean, any))?,
	equip: (Player, string) -> (boolean, string?),
	unequip: (Player, string) -> (boolean, string?),
	equipBest: (Player) -> (boolean, string?),
	craft: (Player, string) -> (boolean, any),
	release: (Player, string) -> (boolean, string?),
	send: (Player, Remotes.PetResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.PetResultPayload
		local req = readRequest(payload)
		local shownAction = if req ~= nil then req.action
			elseif type(payload) == "table" and type(payload.action) == "string" and ACTIONS[payload.action] ~= nil then payload.action
			else ""
		local out: Remotes.PetResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			out = result(shownAction, false, PetRequestService.REASON_RATE_LIMITED)
		elseif req == nil then
			lastAt[player] = now
			out = result(shownAction, false, RollService.REASON_INVALID)
		else
			lastAt[player] = now
			local a = req.action
			if a == "hatch3" then
				local ok, value
				if deps.hatchMulti ~= nil then
					ok, value = deps.hatchMulti(player, req.egg :: number)
				else
					ok, value = false, "unknown"
				end
				if ok and type(value) == "table" and type(value[1]) == "table" then
					out = result(a, true, nil, value[1], value)
				else
					out = result(a, false, if type(value) == "string" then value else "unknown")
				end
			elseif a == "hatch" or a == "craft" then
				local ok, value
				if a == "hatch" then
					ok, value = deps.hatch(player, req.egg :: number)
				else
					ok, value = deps.craft(player, req.uid :: string)
				end
				if ok and type(value) == "table" then
					out = result(a, true, nil, value, if a == "hatch" then { value } else nil)
				else
					out = result(a, false, if type(value) == "string" then value else "unknown")
				end
			else
				local ok, reason
				if a == "equip" then
					ok, reason = deps.equip(player, req.uid :: string)
				elseif a == "unequip" then
					ok, reason = deps.unequip(player, req.uid :: string)
				elseif a == "release" then
					ok, reason = deps.release(player, req.uid :: string)
				else
					ok, reason = deps.equipBest(player)
				end
				out = result(a, ok, if ok then nil else (reason or "unknown"), if ok then { uid = req.uid } else nil)
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

PetRequestService._pure = {
	createHandler = createHandler,
	readRequest = readRequest,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function PetRequestService.init()
	if initialized then
		warn("[PetRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local channels = Remotes.getServer()
	local handler = createHandler({
		hatch = function(player: Player, egg: number)
			return PetService.hatch(player, egg, "manual")
		end,
		hatchMulti = function(player: Player, egg: number)
			return PetService.hatchMulti(player, egg, "manual")
		end,
		equip = PetService.equip,
		unequip = PetService.unequip,
		equipBest = PetService.equipBest,
		craft = PetService.craft,
		release = PetService.release,
		send = function(player: Player, payload: Remotes.PetResultPayload)
			channels.petResult:FireClient(player, payload)
		end,
	})
	channels.petRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = handler.onRequest(player, payload, os.clock())
		if not out.ok then
			print(string.format("[PetRequestService] %s(%d) 요청 action=%s → 거부 reason=%s", player.Name, player.UserId, out.action, out.reason))
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)
	print(string.format("[PetRequestService] 펫 요청 채널 준비 완료 (플레이어당 %.2f초에 1회)", MIN_INTERVAL_SEC))
end

return PetRequestService

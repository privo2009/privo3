--!strict
-- 타이틀 창의 요청 채널 (TitleRequest → TitleResult, Phase 7 지시서 #10).
--
-- 클라가 보낸 것은 "굴려 달라 / 이것을 장착해 달라 / 자동 롤을 켜 달라"는 요청이다. 이 파일은 payload 형태와 빈도만 거르고,
-- 가능 여부(잔액 · 롤 시계 · 보유)는 TitleService가 **다시 판정한다**(CLAUDE.md 절대 규칙 3). 사유 코드는 그대로 돌려준다.
--
-- 빈도 두 겹:
--   채널   플레이어당 MIN_INTERVAL_SEC에 요청 1회(모든 action 공용) — 연타 · 중복 발화 방어선(UpgradeRequestService와 같은 값)
--   롤     TitleService의 롤 시계 — 수동 · 자동 합쳐 TitleConfig.ROLL_INTERVAL_SEC에 1회(G6)
-- 클라도 결과가 올 때까지 버튼을 잠근다(TitleWindow).
--
-- 자동 롤로 새 칭호를 얻으면 TitleService.onAutoNew가 부르고, 이 파일이 action = "autoRoll"로 알린다(중복은 알리지 않는다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RollService = require(script.Parent.RollService)
local TitleService = require(script.Parent.TitleService)

local TitleRequestService = {}

local MIN_INTERVAL_SEC = 0.25
TitleRequestService.REASON_RATE_LIMITED = "rate_limited"
TitleRequestService.ACTION_ROLL = "roll"
TitleRequestService.ACTION_EQUIP = "equip"
TitleRequestService.ACTION_SET_AUTO = "setAuto"
TitleRequestService.ACTION_AUTO_ROLL = "autoRoll" -- 서버 → 클라 알림 전용

local MAX_ID_LEN = 64
local ACTIONS: { [string]: boolean } = { roll = true, equip = true, setAuto = true }

export type Request = { action: string, titleId: string?, on: boolean? }

-- payload를 요청으로 접는다. 모양이 틀리면 nil(그 경우 서비스까지 가지 않고 invalid_request).
local function readRequest(payload: any): Request?
	if type(payload) ~= "table" then
		return nil
	end
	local action = payload.action
	if type(action) ~= "string" or not ACTIONS[action] then
		return nil
	end
	if action == "equip" then
		local id = payload.titleId
		if type(id) ~= "string" or #id == 0 or #id > MAX_ID_LEN then
			return nil
		end
		return { action = action, titleId = id }
	elseif action == "setAuto" then
		if type(payload.on) ~= "boolean" then
			return nil
		end
		return { action = action, on = payload.on }
	end
	return { action = action }
end

local function result(action: string, ok: boolean, reason: string?, titleId: string?, isNew: boolean?, equipped: boolean?): Remotes.TitleResultPayload
	return {
		action = action,
		ok = ok,
		reason = reason or "",
		titleId = titleId or "",
		isNew = isNew == true,
		equipped = equipped == true,
	}
end

export type Deps = {
	roll: (Player) -> (boolean, any),
	equip: (Player, string) -> (boolean, string?),
	setAutoRoll: (Player, boolean) -> (boolean, string?),
	send: (Player, Remotes.TitleResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.TitleResultPayload
		local req = readRequest(payload)
		local shownAction = if req ~= nil then req.action elseif type(payload) == "table" and type(payload.action) == "string" and ACTIONS[payload.action] then payload.action else ""
		local out: Remotes.TitleResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			out = result(shownAction, false, TitleRequestService.REASON_RATE_LIMITED)
		elseif req == nil then
			lastAt[player] = now
			out = result(shownAction, false, RollService.REASON_INVALID)
		else
			lastAt[player] = now
			if req.action == "roll" then
				local ok, value = deps.roll(player)
				if ok and type(value) == "table" then
					out = result("roll", true, nil, value.titleId, value.isNew, value.equipped)
				else
					out = result("roll", false, if type(value) == "string" then value else "unknown")
				end
			elseif req.action == "equip" then
				local ok, reason = deps.equip(player, req.titleId :: string)
				out = result("equip", ok, if ok then nil else (reason or "unknown"), req.titleId, false, ok)
			else
				local ok, reason = deps.setAutoRoll(player, req.on :: boolean)
				out = result("setAuto", ok, if ok then nil else (reason or "unknown"))
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

-- 자동 롤 신규 획득 알림 payload(서비스 결과 → 채널 모양). 테스트가 같은 함수를 쓴다.
local function autoNewPayload(r: TitleService.RollResult): Remotes.TitleResultPayload
	return result(TitleRequestService.ACTION_AUTO_ROLL, true, nil, r.titleId, r.isNew, r.equipped)
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
TitleRequestService._pure = {
	createHandler = createHandler,
	readRequest = readRequest,
	autoNewPayload = autoNewPayload,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function TitleRequestService.init()
	if initialized then
		warn("[TitleRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local channels = Remotes.getServer()
	local function send(player: Player, payload: Remotes.TitleResultPayload)
		channels.titleResult:FireClient(player, payload)
	end
	local handler = createHandler({
		roll = function(player: Player)
			return TitleService.roll(player, TitleService.SOURCE_MANUAL)
		end,
		equip = TitleService.equip,
		setAutoRoll = TitleService.setAutoRoll,
		send = send,
	})

	channels.titleRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = handler.onRequest(player, payload, os.clock())
		if not out.ok then
			print(string.format(
				"[TitleRequestService] %s(%d) 요청 action=%s → 거부 reason=%s",
				player.Name, player.UserId, out.action, out.reason
			))
		end
	end)
	TitleService.onAutoNew(function(player: Player, r: TitleService.RollResult)
		send(player, autoNewPayload(r))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)

	print(string.format("[TitleRequestService] 타이틀 요청 채널 준비 완료 (플레이어당 %.2f초에 1회)", MIN_INTERVAL_SEC))
end

return TitleRequestService

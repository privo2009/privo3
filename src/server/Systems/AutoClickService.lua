--!strict
-- 자동 클리커 (Phase 8 지시서 #16 4단계 · DESIGN 9장 S8).
--
--   서버가 초당 ShopEffects.autoClickRate(15 또는 30 — 높은 쪽만)회 클릭을 만들어 ClickService.processClicks(…, "auto")에 넣는다.
--   서버 단일 루프(BATCH_SEC마다 — 플레이어마다 task.spawn 금지). 소수 클릭은 다음 배치로 넘긴다(초당 횟수가 정확히 맞는다).
--   켜져 있는 동안 **수동 클릭은 힘에 들어가지 않는다**(ClickService.setManualBlocked). 수동 상한(초당 10회)은 그대로다 —
--   자동 경로는 상한 윈도우를 쓰지 않는다(ClickService.passAll).
--   런 중 · 기구 위에서도 같다 — 배수(힘 · 기구)는 processClicks가 정하므로 기구 위면 기구 배수가 붙는다.
--   토글은 **세션에만**(저장하지 않는다 — 접속하면 꺼짐). 미보유면 켜기를 거부한다(not_owned — 클라는 잠김 · 누르면 구매 요청).
--   보유가 사라지면(확정 전 · 조회 실패) 루프가 끈다.
--
-- 채널 두 개(요청 · 결과 — 다른 토글과 같은 규칙): AutoClickRequest { on } → AutoClickResult { ok, reason, on, rate }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClickService = require(script.Parent.ClickService)
local ShopEffects = require(script.Parent.ShopEffects)

local AutoClickService = {}

AutoClickService.BATCH_SEC = 0.2 -- ClickService 클라 배치 주기와 같다
AutoClickService.MAX_BATCH_DT = 1.0 -- 서버가 멈췄다 풀려도 한 배치에 이보다 많이 몰아 넣지 않는다
local MIN_INTERVAL_SEC = 0.25
AutoClickService.REASON_RATE_LIMITED = "rate_limited"
AutoClickService.REASON_INVALID = "invalid_request"
AutoClickService.REASON_NOT_OWNED = "not_owned"
AutoClickService.SOURCE = "auto"

local function readOn(payload: any): boolean?
	if type(payload) ~= "table" or type(payload.on) ~= "boolean" then
		return nil
	end
	return payload.on
end

export type Deps = {
	rateOf: (Player) -> number, -- 지금 초당 횟수(미보유 0)
	click: (Player, number) -> (), -- 자동 클릭 n회
	send: (Player, Remotes.AutoClickResultPayload) -> (),
}

local function createRuntime(deps: Deps)
	local enabled: { [Player]: boolean } = {}
	local carry: { [Player]: number } = {}
	local lastAt: { [Player]: number } = {}
	local runtime = {}

	local function result(ok: boolean, reason: string, on: boolean, rate: number): Remotes.AutoClickResultPayload
		return { ok = ok, reason = reason, on = on, rate = rate }
	end

	function runtime.onRequest(player: Player, payload: any, now: number): Remotes.AutoClickResultPayload
		local on = readOn(payload)
		local out: Remotes.AutoClickResultPayload
		local last = lastAt[player]
		local current = enabled[player] == true
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			out = result(false, AutoClickService.REASON_RATE_LIMITED, current, deps.rateOf(player))
		elseif on == nil then
			lastAt[player] = now
			out = result(false, AutoClickService.REASON_INVALID, current, deps.rateOf(player))
		else
			lastAt[player] = now
			local rate = deps.rateOf(player)
			if on and rate <= 0 then
				enabled[player] = nil
				out = result(false, AutoClickService.REASON_NOT_OWNED, false, 0)
			else
				enabled[player] = if on then true else nil
				if not on then
					carry[player] = nil
				end
				out = result(true, "", on, rate)
			end
		end
		deps.send(player, out)
		return out
	end

	-- 수동 클릭을 버려야 하는가(켜져 있고 보유 중).
	function runtime.isActive(player: Player): boolean
		return enabled[player] == true and deps.rateOf(player) > 0
	end

	-- 한 배치. dt초 동안의 클릭을 만든다. 보유가 사라진 플레이어는 끄고 알린다.
	function runtime.tick(dt: number)
		for player in pairs(enabled) do
			local rate = deps.rateOf(player)
			if rate <= 0 then
				enabled[player] = nil
				carry[player] = nil
				deps.send(player, result(false, AutoClickService.REASON_NOT_OWNED, false, 0))
			else
				local total = (carry[player] or 0) + rate * dt
				local n = math.floor(total + 1e-9)
				carry[player] = total - n
				if n > 0 then
					deps.click(player, n)
				end
			end
		end
	end

	function runtime.isOn(player: Player): boolean
		return enabled[player] == true
	end

	function runtime.onRemoving(player: Player)
		enabled[player] = nil
		carry[player] = nil
		lastAt[player] = nil
	end

	return runtime
end

AutoClickService._pure = {
	createRuntime = createRuntime,
	readOn = readOn,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local runtime: any = nil

-- 켜져 있는가(세션 값). PlayerState가 보낸다.
function AutoClickService.isOn(player: Player): boolean
	return runtime ~= nil and runtime.isOn(player)
end

local initialized = false

function AutoClickService.init()
	if initialized then
		warn("[AutoClickService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local channels = Remotes.getServer()
	-- 켜진 동안 만든 클릭 수(관측용 — 끌 때 한 줄 찍는다). 세션 메모리.
	local made: { [Player]: number } = {}
	runtime = createRuntime({
		rateOf = ShopEffects.autoClickRate,
		click = function(player: Player, n: number)
			local accepted = ClickService.processClicks(player, n, AutoClickService.SOURCE)
			made[player] = (made[player] or 0) + accepted
		end,
		send = function(player: Player, payload: Remotes.AutoClickResultPayload)
			channels.autoClickResult:FireClient(player, payload)
		end,
	})
	ClickService.setManualBlocked(function(player: Player): boolean
		return runtime.isActive(player)
	end)
	channels.autoClickRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = runtime.onRequest(player, payload, os.clock())
		print(string.format("[AutoClickService] %s(%d) 토글 요청 → ok=%s reason=%s on=%s 초당=%d", player.Name, player.UserId,
			tostring(out.ok), out.reason, tostring(out.on), out.rate))
		if out.ok and not out.on then
			print(string.format("[AutoClickService] %s(%d) 끔 — 켜진 동안 자동 클릭 %d회", player.Name, player.UserId, made[player] or 0))
			made[player] = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
		made[player] = nil
	end)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum < AutoClickService.BATCH_SEC then
			return
		end
		local step = math.min(accum, AutoClickService.MAX_BATCH_DT)
		accum = 0
		runtime.tick(step)
	end)
	print(string.format("[AutoClickService] 자동 클리커 준비 완료 (%.1f초 배치 단일 루프 · 세션 토글 · 켜면 수동 클릭 무시)", AutoClickService.BATCH_SEC))
end

return AutoClickService

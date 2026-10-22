--!strict
-- 월드·워프 창의 워프 요청 채널 (WarpRequest → WarpResult, Phase 6 지시서 #6).
--
-- 클라가 보낸 것은 "이 층으로 가고 싶다"는 요청이다. 이 파일은 payload 형태와 빈도만 거르고, 가능 여부
-- (활성 런 없음 W1 · 잔액 · 범위)는 WarpService.warp가 **다시 판정한다**(CLAUDE.md 절대 규칙 3).
--
-- 빈도: 플레이어당 MIN_INTERVAL_SEC에 1회. 넘으면 "rate_limited"(워프는 일어나지 않는다). 창에 확인 단계가
-- 있어 정상 유저는 닿지 않는다 — 연타 · 중복 발화 방어선이다(RebirthRequestService와 같은 구조).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WarpService = require(script.Parent.WarpService)

local WarpRequestService = {}

local MIN_INTERVAL_SEC = 1.0
WarpRequestService.REASON_RATE_LIMITED = "rate_limited"

-- payload에서 목표 층을 꺼낸다. 형태가 틀리면 nil — 그 경우 WarpService까지 가지 않고 invalid_stage로 답한다.
-- 정수 · 범위 판정은 WarpConfig.canWarp가 한다(여기서 범위를 다시 쓰지 않는다). 여기서는 "숫자인가"만.
local function readStage(payload: any): number?
	if type(payload) ~= "table" then
		return nil
	end
	local stage = payload.stage
	if type(stage) ~= "number" or stage ~= stage or stage == math.huge or stage == -math.huge then
		return nil
	end
	return stage
end

export type Deps = {
	warp: (Player, number) -> (boolean, any),
	send: (Player, Remotes.WarpResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.WarpResultPayload
		local stage = readStage(payload)
		local shownStage = if stage ~= nil then stage else 0
		local result: Remotes.WarpResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			result = { ok = false, reason = WarpRequestService.REASON_RATE_LIMITED, stage = shownStage, cost = BigNum.new(0, 0) }
		elseif stage == nil then
			lastAt[player] = now
			result = { ok = false, reason = WarpService.REASON_INVALID_STAGE, stage = 0, cost = BigNum.new(0, 0) }
		else
			lastAt[player] = now
			local ok, value = deps.warp(player, stage)
			if ok and type(value) == "table" then
				result = { ok = true, reason = "", stage = stage, cost = BigNum.new(value.m, value.e) }
			else
				result = { ok = false, reason = if type(value) == "string" then value else "unknown", stage = stage, cost = BigNum.new(0, 0) }
			end
		end
		deps.send(player, result)
		return result
	end

	function handler.onRemoving(player: Player)
		lastAt[player] = nil
	end

	return handler
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
WarpRequestService._pure = {
	createHandler = createHandler,
	readStage = readStage,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function WarpRequestService.init()
	if initialized then
		warn("[WarpRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local channels = Remotes.getServer()
	local handler = createHandler({
		warp = function(player: Player, stage: number)
			return WarpService.warp(player, stage, "ui")
		end,
		send = function(player: Player, payload: Remotes.WarpResultPayload)
			channels.warpResult:FireClient(player, payload)
		end,
	})

	channels.warpRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local result = handler.onRequest(player, payload, os.clock())
		print(string.format(
			"[WarpRequestService] %s(%d) 워프 요청 stage=%s → ok=%s reason=%s cost=%s",
			player.Name, player.UserId, tostring(result.stage), tostring(result.ok), result.reason, BigNum.tostring(result.cost)
		))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)

	print(string.format("[WarpRequestService] 워프 요청 채널 준비 완료 (플레이어당 %.1f초에 1회)", MIN_INTERVAL_SEC))
end

return WarpRequestService

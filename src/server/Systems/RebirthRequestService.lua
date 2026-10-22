--!strict
-- 환생 창의 환생 요청 채널 (RebirthRequest → RebirthResult, Phase 6 지시서 #5).
--
-- 클라가 보낸 것은 "환생해 달라"는 요청뿐이다. 가능한지는 RebirthService.rebirth가 canRebirth로
-- **다시 판정한다**(클라 값 신뢰 금지 — CLAUDE.md 절대 규칙 3). 이 파일은 빈도만 자른다.
--
-- 빈도: 플레이어당 MIN_INTERVAL_SEC에 1회. 넘으면 "rate_limited"로 거부한다(환생은 일어나지 않는다).
-- 확인 단계(두 번 누름)가 클라에 있어 정상 유저는 이 상한에 닿지 않는다 — 연타 · 중복 발화 방어선이다.
-- 환생 자체는 yield 없이 끝나므로(RebirthService 상단) 같은 플레이어의 두 요청이 겹칠 수 없다.
--
-- 결과의 바뀐 값(블럭스 0 · 배수 · 힘)은 PlayerState 채널이 다음 틱에 보낸다. 여기서는 성공 · 사유만 보낸다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RebirthService = require(script.Parent.RebirthService)

type BigNumber = BigNum.BigNumber

local RebirthRequestService = {}

local MIN_INTERVAL_SEC = 1.0
RebirthRequestService.REASON_RATE_LIMITED = "rate_limited"

export type Deps = {
	rebirth: (Player) -> (boolean, any),
	send: (Player, Remotes.RebirthResultPayload) -> (),
}

-- 요청 처리 상태 기계. 실물은 init()이, 테스트는 가짜 deps로 굴린다.
local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, now: number): Remotes.RebirthResultPayload
		local last = lastAt[player]
		local result: Remotes.RebirthResultPayload
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			result = { ok = false, reason = RebirthRequestService.REASON_RATE_LIMITED, gained = BigNum.new(0, 0), total = BigNum.new(0, 0) }
		else
			lastAt[player] = now
			local ok, value = deps.rebirth(player)
			if ok then
				local gained = if type(value) == "table" and type(value.gained) == "table" then value.gained else BigNum.new(0, 0)
				local total = if type(value) == "table" and type(value.total) == "table" then value.total else BigNum.new(0, 0)
				result = { ok = true, reason = "", gained = BigNum.new(gained.m, gained.e), total = BigNum.new(total.m, total.e) }
			else
				result = { ok = false, reason = if type(value) == "string" then value else "unknown", gained = BigNum.new(0, 0), total = BigNum.new(0, 0) }
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
RebirthRequestService._pure = {
	createHandler = createHandler,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function RebirthRequestService.init()
	if initialized then
		warn("[RebirthRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local channels = Remotes.getServer()
	local handler = createHandler({
		rebirth = function(player: Player)
			return RebirthService.rebirth(player, "ui")
		end,
		send = function(player: Player, payload: Remotes.RebirthResultPayload)
			channels.rebirthResult:FireClient(player, payload)
		end,
	})

	-- payload는 비어 있다(규약 2). 보지 않는다 — 요청 자체가 신호다.
	channels.rebirthRequest.OnServerEvent:Connect(function(player: Player)
		local result = handler.onRequest(player, os.clock())
		print(string.format(
			"[RebirthRequestService] %s(%d) 환생 요청 → ok=%s reason=%s gained=%s",
			player.Name, player.UserId, tostring(result.ok), result.reason, BigNum.tostring(result.gained)
		))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)

	print(string.format("[RebirthRequestService] 환생 요청 채널 준비 완료 (플레이어당 %.1f초에 1회)", MIN_INTERVAL_SEC))
end

return RebirthRequestService

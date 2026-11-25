--!strict
-- 상점 창의 업그레이드 구매 요청 채널 (UpgradeRequest → UpgradeResult, Phase 6 지시서 #7).
--
-- 클라가 보낸 것은 "이 항목을 한 레벨 사고 싶다"는 요청이다. 이 파일은 payload 형태와 빈도만 거르고, 가능 여부
-- (노출 항목 · 최대 레벨 · 잔액)는 UpgradeService.buy가 **다시 판정한다**(CLAUDE.md 절대 규칙 3).
--
-- 빈도: 플레이어당 MIN_INTERVAL_SEC에 1회. 넘으면 "rate_limited"(구매는 일어나지 않는다).
-- 상점 구매는 확인 단계가 없다(S8 — 자주 · 소액으로 반복하는 행동). 그래서 중복 입력은 두 겹으로 막는다:
--   클라  요청을 보내면 결과가 올 때까지 그 버튼을 잠근다(UpgradeShopWindow)
--   서버  여기 — 연타 · 중복 발화 방어선. 정상 유저의 빠른 반복 구매는 막지 않을 만큼 짧게 잡았다(Claude 판단)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UpgradeService = require(script.Parent.UpgradeService)

local UpgradeRequestService = {}

local MIN_INTERVAL_SEC = 0.25
UpgradeRequestService.REASON_RATE_LIMITED = "rate_limited"

-- payload에서 항목 이름을 꺼낸다. 문자열이 아니면 nil — 그 경우 UpgradeService까지 가지 않고 invalid_upgrade로 답한다.
-- 노출 항목인지는 UpgradeService(→ UpgradeConfig.isExposed)가 본다. 여기서는 "문자열인가"와 길이만.
local MAX_NAME_LEN = 64
local function readName(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	local name = payload.name
	if type(name) ~= "string" or #name == 0 or #name > MAX_NAME_LEN then
		return nil
	end
	return name
end

export type Deps = {
	buy: (Player, string) -> (boolean, any),
	send: (Player, Remotes.UpgradeResultPayload) -> (),
}

local function createHandler(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local handler = {}

	function handler.onRequest(player: Player, payload: any, now: number): Remotes.UpgradeResultPayload
		local name = readName(payload)
		local shownName = name or ""
		local result: Remotes.UpgradeResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < MIN_INTERVAL_SEC then
			result = { ok = false, reason = UpgradeRequestService.REASON_RATE_LIMITED, name = shownName, level = 0, cost = BigNum.new(0, 0) }
		elseif name == nil then
			lastAt[player] = now
			result = { ok = false, reason = UpgradeConfig.REASON_INVALID_UPGRADE, name = "", level = 0, cost = BigNum.new(0, 0) }
		else
			lastAt[player] = now
			local ok, value = deps.buy(player, name)
			if ok and type(value) == "table" then
				result = { ok = true, reason = "", name = name, level = value.level, cost = BigNum.new(value.cost.m, value.cost.e) }
			else
				result = { ok = false, reason = if type(value) == "string" then value else "unknown", name = name, level = 0, cost = BigNum.new(0, 0) }
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
UpgradeRequestService._pure = {
	createHandler = createHandler,
	readName = readName,
	MIN_INTERVAL_SEC = MIN_INTERVAL_SEC,
}

local initialized = false

function UpgradeRequestService.init()
	if initialized then
		warn("[UpgradeRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local channels = Remotes.getServer()
	local handler = createHandler({
		buy = function(player: Player, name: string)
			return UpgradeService.buy(player, name)
		end,
		send = function(player: Player, payload: Remotes.UpgradeResultPayload)
			channels.upgradeResult:FireClient(player, payload)
		end,
	})

	channels.upgradeRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local result = handler.onRequest(player, payload, os.clock())
		if not result.ok then
			print(string.format(
				"[UpgradeRequestService] %s(%d) 구매 요청 name=%s → 거부 reason=%s",
				player.Name, player.UserId, result.name, result.reason
			))
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		handler.onRemoving(player)
	end)

	print(string.format("[UpgradeRequestService] 업그레이드 구매 채널 준비 완료 (플레이어당 %.2f초에 1회)", MIN_INTERVAL_SEC))
end

return UpgradeRequestService

--!strict
-- 자동 부화(지시서 #35 — DESIGN 16장 "펫").
--
-- 무료 토글. 고른 알을 서버 단일 루프가 부화 간격마다 되풀이한다(간격 판정은 PetService — 무료 HATCH_SKIP_SEC · 즉시 부화 최소 간격).
-- 트리플 부화(Triple Hatch)를 가졌으면(제한 지역이면 끔) 한 번에 3마리 · 코인 3배(PetService.hatchMulti).
-- **접속 중에만** 돈다 — 저장하지 않는다(나가면 끝). 코인 · 저장 공간이 모자라거나 알이 잠기면 멈추고 알린다(auto_hatch_state reason).
-- 결과는 EconomyEvent(auto_hatch_result — 작은 목록 · 좋은 등급만 크게 알림)로 보낸다. PetResult(모달)로 보내지 않는다.
-- 요청 채널 PetAutoRequest { on, egg } — 연타 상한 0.15초(대장간과 같다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteGuard = require(script.Parent.RemoteGuard) -- 입구 공통 문(모양 · 연타 · 오류 격리 — #38)

local PetAutoHatchService = {}

PetAutoHatchService.REQUEST_MIN_GAP_SEC = 0.15
-- 이 사유면 기다리면 된다(멈추지 않는다)
local WAIT_REASONS = { too_soon = true, rate_limited = true }

export type Deps = {
	hatch: (Player, number) -> (boolean, any), -- 1마리(PetService.hatch)
	hatchMulti: (Player, number) -> (boolean, any), -- 트리플(PetService.hatchMulti)
	ownsTriple: (Player) -> boolean,
	send: (Player, any) -> (),
	notify: (Player) -> (), -- 상태 다시 보내기(펫 목록)
	now: () -> number,
}

export type AutoState = { on: boolean, egg: number, count: number, lastRequestAt: number }

local function liveDeps(): Deps
	local PetService = require(script.Parent.PetService)
	local ShopEffects = require(script.Parent.ShopEffects)
	local channels = Remotes.getServer()
	return {
		hatch = function(player, egg)
			return PetService.hatch(player, egg, "auto")
		end,
		hatchMulti = function(player, egg)
			return PetService.hatchMulti(player, egg, "auto")
		end,
		ownsTriple = function(player)
			return ShopEffects.v2PassActive(player, "hatch3x")
		end,
		send = function(player, payload)
			if typeof(player) == "Instance" and player:IsA("Player") then
				channels.economyEvent:FireClient(player, payload)
			end
		end,
		notify = function(player)
			if typeof(player) == "Instance" then
				require(script.Parent.PlayerStateService).notify(player)
			end
		end,
		now = os.clock,
	}
end

PetAutoHatchService._deps = nil :: Deps?

local function deps(): Deps
	if PetAutoHatchService._deps == nil then
		PetAutoHatchService._deps = liveDeps()
	end
	return PetAutoHatchService._deps :: Deps
end

local states: { [Player]: AutoState } = {}

local function stateOf(player: Player): AutoState
	local s = states[player]
	if s == nil then
		s = { on = false, egg = 1, count = 0, lastRequestAt = -math.huge }
		states[player] = s
	end
	return s
end

function PetAutoHatchService.setAuto(player: Player, on: boolean, egg: any)
	local s = stateOf(player)
	if on then
		if type(egg) ~= "number" or egg % 1 ~= 0 or egg < 1 or egg > #PetConfig.Eggs then -- 있는 알 번호만(#38)
			s.on = false
			deps().send(player, { kind = "auto_hatch_state", on = false, count = s.count, reason = "invalid_request" })
			return
		end
		s.on, s.egg, s.count = true, egg, 0
	else
		s.on = false
	end
	deps().send(player, { kind = "auto_hatch_state", on = s.on, count = s.count, egg = s.egg })
end

-- 자동 부화 1틱(루프 · 테스트). 간격 전이면 조용히 넘어간다. 그 밖의 거부면 멈추고 알린다.
function PetAutoHatchService.tick(player: Player)
	local s = states[player]
	if s == nil or not s.on then
		return
	end
	local d = deps()
	local triple = d.ownsTriple(player)
	local ok, value
	if triple then
		ok, value = d.hatchMulti(player, s.egg)
	else
		ok, value = d.hatch(player, s.egg)
	end
	if not ok then
		local reason = if type(value) == "string" then value else "failed"
		if WAIT_REASONS[reason] then
			return
		end
		s.on = false
		d.send(player, { kind = "auto_hatch_state", on = false, count = s.count, reason = reason, egg = s.egg })
		return
	end
	local list = if triple then value else { value }
	s.count += #list
	local results = {}
	local big = {}
	for _, r in ipairs(list) do
		table.insert(results, { petId = r.petId, rarity = r.rarity, isNew = r.isNew })
		if r.rarity >= Config.HATCH_BIG_NOTICE_RARITY then
			table.insert(big, r.petId)
		end
	end
	d.send(player, { kind = "auto_hatch_result", results = results, count = s.count, big = big })
	d.notify(player)
end

function PetAutoHatchService.handleRequest(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local s = stateOf(player)
	local now = deps().now()
	if now - s.lastRequestAt < PetAutoHatchService.REQUEST_MIN_GAP_SEC then
		return
	end
	s.lastRequestAt = now
	PetAutoHatchService.setAuto(player, payload.on == true, payload.egg)
end

function PetAutoHatchService._state(player: Player): AutoState?
	return states[player]
end
function PetAutoHatchService._reset(player: Player)
	states[player] = nil
end

local initialized = false

function PetAutoHatchService._initialized(): boolean
	return initialized
end

function PetAutoHatchService.init()
	if initialized then
		return
	end
	initialized = true
	RemoteGuard.connect(Remotes.getServer().petAutoRequest, function(player: Player, payload: any)
		local ok, err = pcall(PetAutoHatchService.handleRequest, player, payload)
		if not ok then
			warn("[PetAutoHatchService] 요청 오류: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AUTO_HATCH_POLL_SEC)
			for player, s in pairs(states) do
				if s.on then
					local ok, err = pcall(PetAutoHatchService.tick, player)
					if not ok then
						warn("[PetAutoHatchService] 자동 부화 오류: " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil -- 접속 중에만(저장하지 않는다)
	end)
	print(string.format("[PetAutoHatchService] 자동 부화 시작 (무료 간격 %.1f초 · 연출 %.1f초)", Config.HATCH_SKIP_SEC, Config.HATCH_ANIM_SEC))
end

return PetAutoHatchService

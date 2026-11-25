--!strict
-- 새 경제 안내(지시서 #36 — DESIGN 16장 "해금 순서 · 첫 접속 안내").
--
-- 서버가 프로필 · 가방 상태를 TIP_POLL_SEC마다 읽어(OnboardingTipsLogic.facts) 처음 참이 되는 안내 하나를 적고(onboarding.tips[키] = true) 보낸다.
--   한 틱에 하나 — 안내가 한 번에 하나씩 나온다. 보낼 때 적는다(한 번만). 지난 것 · 안내를 끈 유저(tipsOff)는 글 없이 적는다(칸만 나타난다)
--   프로필을 불러올 때 이미 참인 것은 전부 글 없이 적는다(이미 지난 유저에게 지난 안내를 띄우지 않는다 — backfill)
-- 보내는 꼴(EconomyEvent): { kind = "tip", key, silent } · { kind = "tips", seen = {키 목록}, off } (접속 · 동기화 요청 때 전체)
-- 요청 채널 OnboardingTipRequest { action = "sync" } — 연타 상한 TIP_REQUEST_MIN_INTERVAL_SEC
-- 저장 필드는 기존 onboarding 안(tips · tipsOff) — 새 최상위 필드 · 스키마 버전 변경 없음. 상태를 바꾸는 것은 안내 표시뿐(재화 · 진행 없음)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local OnboardingTipsLogic = require(ReplicatedStorage.Shared.OnboardingTipsLogic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteGuard = require(script.Parent.RemoteGuard) -- 입구 공통 문(모양 · 연타 · 오류 격리 — #38)

local OnboardingTipsService = {}

export type Deps = {
	getData: (Player) -> any?,
	bagUsed: (Player) -> number,
	send: (Player, any) -> (),
	log: (string) -> (),
}

local function liveDeps(): Deps
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	local OreDropService = require(script.Parent.OreDropService)
	local channels = Remotes.getServer()
	return {
		getData = function(player)
			local profile = ProfileManager.get(player)
			return if profile ~= nil then profile.Data else nil
		end,
		bagUsed = function(player)
			return OreDropService.bagUsed(player)
		end,
		send = function(player, payload)
			if typeof(player) == "Instance" and player:IsA("Player") then
				channels.economyEvent:FireClient(player, payload)
			end
		end,
		log = print,
	}
end

OnboardingTipsService._deps = nil :: Deps?

local function deps(): Deps
	if OnboardingTipsService._deps == nil then
		OnboardingTipsService._deps = liveDeps()
	end
	return OnboardingTipsService._deps :: Deps
end

local function onboardingOf(data: any): any?
	if type(data) == "table" and type(data.onboarding) == "table" then
		return data.onboarding
	end
	return nil
end

local function stateMessage(o: any): any
	local seen = {}
	for _, tip in ipairs(OnboardingConfig.V2_TIPS) do
		if OnboardingTipsLogic.seenSet(o)[tip.key] then
			table.insert(seen, tip.key)
		end
	end
	return { kind = "tips", seen = seen, off = OnboardingTipsLogic.isOff(o) }
end

-- 프로필을 불러온 뒤 한 번: 이미 참인 것을 글 없이 적고 전체 상태를 보낸다. 적은 키 목록을 돌려준다
function OnboardingTipsService.onLoaded(player: Player): { string }
	local d = deps()
	local data = d.getData(player)
	local o = onboardingOf(data)
	if o == nil then
		return {}
	end
	local keys = OnboardingTipsLogic.backfill(o, OnboardingTipsLogic.facts(data, d.bagUsed(player)))
	for _, key in ipairs(keys) do
		OnboardingTipsLogic.mark(o, key)
	end
	if #keys > 0 then
		d.log(string.format("[OnboardingTips] %s 이미 지난 안내 %d개(글 없이): %s", player.Name, #keys, table.concat(keys, ", ")))
	end
	d.send(player, stateMessage(o))
	return keys
end

-- 한 틱: 처음 참이 된 안내 하나를 적고 보낸다. 적은 키(없으면 nil)와 silent
function OnboardingTipsService.tick(player: Player): (string?, boolean)
	local d = deps()
	local data = d.getData(player)
	local o = onboardingOf(data)
	if o == nil then
		return nil, false
	end
	local key, silent = OnboardingTipsLogic.pick(o, OnboardingTipsLogic.facts(data, d.bagUsed(player)))
	if key == nil then
		return nil, false
	end
	OnboardingTipsLogic.mark(o, key)
	d.send(player, { kind = "tip", key = key, silent = silent })
	d.log(string.format("[OnboardingTips] %s 안내 %s%s", player.Name, key, if silent then "(글 없이)" else ""))
	return key, silent
end

local lastRequestAt: { [Player]: number } = {}

function OnboardingTipsService.handleRequest(player: Player, payload: any, clock: number)
	if type(payload) ~= "table" or payload.action ~= "sync" then
		return
	end
	local last = lastRequestAt[player]
	if last ~= nil and clock - last < OnboardingConfig.TIP_REQUEST_MIN_INTERVAL_SEC then
		return
	end
	lastRequestAt[player] = clock
	local o = onboardingOf(deps().getData(player))
	if o ~= nil then
		deps().send(player, stateMessage(o))
	end
end

local initialized = false
function OnboardingTipsService._initialized(): boolean
	return initialized
end

function OnboardingTipsService.init()
	if initialized then
		return
	end
	initialized = true
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	local loaded: { [Player]: boolean } = {}
	ProfileManager.onLoaded(function(player: Player)
		local ok, err = pcall(OnboardingTipsService.onLoaded, player)
		if not ok then
			warn("[OnboardingTipsService] 접속 처리 오류: " .. tostring(err))
		end
		loaded[player] = true
	end)
	RemoteGuard.connect(Remotes.getServer().onboardingTipRequest, function(player: Player, payload: any)
		OnboardingTipsService.handleRequest(player, payload, os.clock())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		loaded[player] = nil
		lastRequestAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(OnboardingConfig.TIP_POLL_SEC)
			for player in pairs(loaded) do
				local ok, err = pcall(OnboardingTipsService.tick, player)
				if not ok then
					warn("[OnboardingTipsService] 안내 오류: " .. tostring(err))
				end
			end
		end
	end)
	print(string.format("[OnboardingTipsService] 새 경제 안내 준비 완료 (%d개 · 주기 %.1f초)", #OnboardingConfig.V2_TIPS, OnboardingConfig.TIP_POLL_SEC))
end

return OnboardingTipsService

--!strict
-- 소프트 셧다운(지시서 #48 1부) — 새 버전을 게시하고 옛 서버를 닫을 때 플레이어를 잃지 않고 새 서버로 보낸다.
-- 값 · 공식 문서 근거 → Shared/Config/SoftShutdownConfig. 규칙 원본 → DESIGN.md "15. 운영 > 소프트 셧다운".
--
-- 옛 서버(닫히는 쪽) — BindToClose · ServerRestartScheduled 둘 다 같은 evacuate:
--   1. 모두에게 "업데이트 중" 화면(ServerNotice kind = "updating")
--   2. 런 중이면 포기(ChallengeService.abandonRun — "수령 없이 나가기"와 같다: 가방 광석 · 수령 전 블럭스를 잃는다. 코인은 이미 들어왔다)
--   3. 저장이 먼저: ProfileManager.closeAll(상한) — 세션을 끝내고 저장이 끝날 때까지 기다린다(#38 서버 종료 저장과 한 흐름)
--   4. 예약 서버(대기실)로 순간이동(ShouldReserveServer) · 순간이동 데이터에 표시 · 실패하면 다시 시도
-- 대기실(예약 서버 — SoftShutdownConfig.isHoldingServer): 프로필을 열지 않는다(ProfileManager가 건너뛴다). 들어오면 "업데이트 중" 화면 →
--   HOLD_SEC 뒤 같은 플레이스의 공개 서버(새 버전)로 다시 보낸다.
-- Studio: 순간이동은 하지 않는다(저장 · 화면까지만 — 줄 하나). 실제 게시 · 순간이동은 2월 비공개 서버에서 사람이 확인(PENDING)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoftShutdownConfig = require(ReplicatedStorage.Shared.Config.SoftShutdownConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local LocaleGate = require(script.Parent.LocaleGate)

local SoftShutdown = {}

export type Deps = {
	players: () -> { any },
	isStudio: boolean,
	placeId: number,
	notify: (player: any) -> (),
	abandonRun: (player: any) -> (),
	saveAll: (timeoutSec: number) -> number, -- 저장 못 끝낸 수
	teleport: (placeId: number, players: { any }, reserve: boolean) -> (boolean, string?), -- (성공, 오류 문구)
	wait: (sec: number) -> (),
	log: (line: string) -> (),
	kick: (player: any) -> (), -- 옮기지 못한 사람: 세션이 이미 끝났으니 남겨 두지 않는다(저장 없이 노는 것을 막는다 — 다시 접속 안내)
}

export type Result = {
	status: string, -- "empty" | "studio" | "teleported" | "teleport_failed" | "busy"
	players: number,
	unsaved: number,
	attempts: number,
}

-- 순간이동 한 번을 다시 시도와 함께(공식 문서 예시: 5번 · 1초 · Flooded면 15초). 돌려주는 값: 성공 · 시도 수
function SoftShutdown.teleportWithRetry(deps: Deps, placeId: number, list: { any }, reserve: boolean): (boolean, number)
	local attempt = 0
	while attempt < SoftShutdownConfig.TELEPORT_ATTEMPTS do
		attempt += 1
		local ok, err = deps.teleport(placeId, list, reserve)
		if ok then
			return true, attempt
		end
		deps.log(string.format("[SoftShutdown] 순간이동 실패 %d/%d: %s", attempt, SoftShutdownConfig.TELEPORT_ATTEMPTS, tostring(err)))
		if attempt < SoftShutdownConfig.TELEPORT_ATTEMPTS then
			local flooded = type(err) == "string" and string.find(err, "Flooded", 1, true) ~= nil
			deps.wait(if flooded then SoftShutdownConfig.FLOODED_DELAY_SEC else SoftShutdownConfig.RETRY_DELAY_SEC)
		end
	end
	return false, attempt
end

local running = false

-- 옛 서버: 화면 → 런 포기 → 저장(끝날 때까지) → 대기실로. 순서가 규칙이다(저장 전에 옮기지 않는다)
function SoftShutdown.evacuate(deps: Deps, reason: string): Result
	if running then
		return { status = "busy", players = 0, unsaved = 0, attempts = 0 }
	end
	running = true
	local list = deps.players()
	if #list == 0 then
		running = false
		return { status = "empty", players = 0, unsaved = 0, attempts = 0 }
	end
	for _, player in ipairs(list) do
		deps.notify(player)
	end
	for _, player in ipairs(list) do
		deps.abandonRun(player)
	end
	local unsaved = deps.saveAll(SoftShutdownConfig.SAVE_TIMEOUT_SEC)
	if unsaved > 0 then
		-- 그래도 옮긴다: 남으면 서버가 꺼지며 어차피 나간다. 저장은 ProfileStore가 다음 세션에서 이어받는다(세션 잠금)
		deps.log(string.format("[SoftShutdown] 저장 상한(%d초) 안에 못 끝낸 프로필 %d개 — 그래도 옮긴다", SoftShutdownConfig.SAVE_TIMEOUT_SEC, unsaved))
	end
	if deps.isStudio then
		deps.log(string.format("[SoftShutdown] Studio — 저장까지 하고 순간이동은 건너뜀(%s · %d명)", reason, #list))
		running = false
		return { status = "studio", players = #list, unsaved = unsaved, attempts = 0 }
	end
	local ok, attempts = SoftShutdown.teleportWithRetry(deps, deps.placeId, list, true)
	deps.log(string.format("[SoftShutdown] %s · %d명 → 대기실 %s(시도 %d)", reason, #list, if ok then "보냄" else "실패", attempts))
	if not ok then
		for _, player in ipairs(list) do
			deps.kick(player)
		end
	end
	running = false
	return { status = if ok then "teleported" else "teleport_failed", players = #list, unsaved = unsaved, attempts = attempts }
end

-- 대기실: 지금 있는 사람을 공개 서버(새 버전)로. 새로 들어오면 다시 부른다
function SoftShutdown.release(deps: Deps): Result
	local list = deps.players()
	if #list == 0 then
		return { status = "empty", players = 0, unsaved = 0, attempts = 0 }
	end
	local ok, attempts = SoftShutdown.teleportWithRetry(deps, deps.placeId, list, false)
	deps.log(string.format("[SoftShutdown] 대기실 → 새 서버 %d명 %s(시도 %d)", #list, if ok then "보냄" else "실패", attempts))
	return { status = if ok then "teleported" else "teleport_failed", players = #list, unsaved = 0, attempts = attempts }
end

function SoftShutdown._resetForTest()
	running = false
end

-- ===== 실물 배선 =================================================================================

local function realTeleport(placeId: number, list: { any }, reserve: boolean): (boolean, string?)
	local options = Instance.new("TeleportOptions")
	if reserve then
		-- 대기실로 갈 때만 표시를 싣는다(새 서버로 돌아갈 때는 안 싣는다 — 그 서버에서 "업데이트 중" 화면이 뜨지 않게)
		options.ShouldReserveServer = true
		options:SetTeleportData({ [SoftShutdownConfig.TELEPORT_DATA_KEY] = true })
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, list, options)
	end)
	return ok, if ok then nil else tostring(err)
end

local function notify(player: any)
	if typeof(player) == "Instance" and player.Parent == Players then
		Remotes.getServer().serverNotice:FireClient(player, { kind = "updating", text = "", sec = 0 })
	end
end

local initialized = false

-- deps: Bootstrap이 넘긴다(abandonRun · saveAll — 순환 require를 피한다)
function SoftShutdown.init(opts: { abandonRun: (Player) -> (), saveAll: (number) -> number })
	if initialized then
		return
	end
	initialized = true
	local deps: Deps = {
		players = function()
			return Players:GetPlayers()
		end,
		isStudio = RunService:IsStudio(),
		placeId = game.PlaceId,
		notify = notify,
		abandonRun = opts.abandonRun,
		saveAll = opts.saveAll,
		teleport = realTeleport,
		wait = function(sec: number)
			task.wait(sec)
		end,
		log = function(line: string)
			print(line)
		end,
		kick = function(player: any)
			if typeof(player) == "Instance" and player.Parent == Players then
				player:Kick(LocaleGate.kickText(player, "kick.updating"))
			end
		end,
	}

	-- 순간이동이 마지막에 실패하면(공식 문서 — 오류 없이 실패할 수 있다) 그 사람만 다시 보낸다
	local retried: { [Player]: number } = {}
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string, placeId: number)
		local n = (retried[player] or 0) + 1
		retried[player] = n
		if n >= SoftShutdownConfig.TELEPORT_ATTEMPTS or player.Parent ~= Players then
			warn(string.format("[SoftShutdown] %s 순간이동 실패(%s · %s) — 그만", player.Name, tostring(result), tostring(message)))
			return
		end
		task.wait(if result == Enum.TeleportResult.Flooded then SoftShutdownConfig.FLOODED_DELAY_SEC else SoftShutdownConfig.RETRY_DELAY_SEC)
		if player.Parent == Players then
			local holding = SoftShutdownConfig.isHoldingServer(deps.isStudio, game.PrivateServerId, game.PrivateServerOwnerId)
			realTeleport(placeId, { player }, not holding)
		end
	end)

	if SoftShutdownConfig.isHoldingServer(deps.isStudio, game.PrivateServerId, game.PrivateServerOwnerId) then
		-- 대기실: 들어오면 화면 → 잠깐 기다렸다가 새 서버로(한 번에 모아서)
		print("[SoftShutdown] 이 서버는 대기실(예약 서버) — 프로필을 열지 않고 새 서버로 다시 보낸다")
		local pending = false
		local function schedule()
			if pending then
				return
			end
			pending = true
			task.delay(SoftShutdownConfig.HOLD_SEC, function()
				pending = false
				SoftShutdown.release(deps)
			end)
		end
		Players.PlayerAdded:Connect(function(player: Player)
			notify(player)
			schedule()
		end)
		for _, player in ipairs(Players:GetPlayers()) do
			notify(player)
		end
		schedule()
		return
	end

	-- 옛 서버: 재시작 예정(대시보드 Restart Servers) → 앞당겨 시작 · 서버 닫힘(BindToClose) → 바로
	pcall(function()
		(game :: any).ServerRestartScheduled:Connect(function(restartTime: number?, source: any)
			local delaySec = SoftShutdownConfig.delayBeforeEvacuate(restartTime, os.time())
			print(string.format("[SoftShutdown] 재시작 예정(%s) — %d초 뒤 저장 · 옮기기", tostring(source), delaySec))
			for _, player in ipairs(Players:GetPlayers()) do
				Remotes.getServer().serverNotice:FireClient(player, { kind = "restart", text = "", sec = math.floor(delaySec) })
			end
			task.delay(delaySec, function()
				SoftShutdown.evacuate(deps, "restart")
			end)
		end)
	end)
	game:BindToClose(function()
		local startedAt = os.clock()
		local result = SoftShutdown.evacuate(deps, "close")
		if result.status ~= "teleported" then
			return
		end
		-- 순간이동이 끝날 때까지 서버를 붙잡는다(먼저 꺼지면 이동이 끊긴다)
		while #Players:GetPlayers() > 0 and os.clock() - startedAt < SoftShutdownConfig.CLOSE_HOLD_SEC do
			task.wait(0.5)
		end
	end)
end

return SoftShutdown

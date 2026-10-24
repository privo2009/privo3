--!strict
-- 서버 → 클라 플레이어 상태 채널 (Phase 6 지시서 #5). HUD가 더미가 아니라 서버 값을 보이게 한다.
--
-- 값은 서버가 만든다(CLAUDE.md 절대 규칙 3). 클라는 받은 스냅샷을 Store에 넣고 화면은 Store만 본다.
-- payload 형태는 Shared/GameTypes.PlayerStateView, 채널 이름은 Shared/Remotes.
--
-- ===== 보내는 시점 =====================================================================
--
--   1. 프로필 로드 직후 1회 — 전체 스냅샷 (ProfileManager.onLoaded)
--   2. 그 뒤로는 바뀔 때만 — SEND_PERIOD마다 스냅샷을 만들어 마지막으로 보낸 것과 다를 때 보낸다
--   3. 클라가 SyncRequest를 보내면 — SYNC_COALESCE_SEC 안의 요청을 하나로 모아 한 번만 답한다
--      (PlayerState 전체 + ChallengeService.syncRunState). 이유는 Remotes.lua SyncRequestPayload
--   4. 리스폰 직후 — 런 상태 sync만 (CharacterAdded)
--
-- ===== 빈도 상한 =======================================================================
--
-- 클릭으로 힘이 초당 여러 번 바뀐다. 클릭 1회마다 보내지 않는다 — 플레이어당 SEND_PERIOD에 최대 1회다.
-- 값은 ClickService 배치 주기(0.2초)와 같게 잡았다: 힘은 어차피 그 주기로만 바뀌므로 더 자주 봐도
-- 보낼 것이 없고, 더 드물게 보면 클릭한 만큼 화면이 늦게 따라온다.
--
-- ⚠️ 이 루프는 화면 동기화용이다. 게임 판정에 쓰지 않는다 — 판정용 폴링 루프 금지(CLAUDE.md 3)와
--    다른 일이다. 이 파일은 아무 상태도 바꾸지 않는다(읽기 + 통지).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local Schema = require(script.Parent.Parent.Data.Schema)
local PadService = require(script.Parent.PadService)
local SpeedService = require(script.Parent.SpeedService)
local ChallengeService = require(script.Parent.ChallengeService)
-- 업그레이드 레벨(지시서 #7). 저장값 읽기 규칙은 UpgradeService.readLevels가 원본이다.
local UpgradeService = require(script.Parent.UpgradeService)
-- 칭호 요약(지시서 #10). 읽기 규칙은 TitleService.summarize가 원본이다.
local TitleService = require(script.Parent.TitleService)
-- 아우라 요약(지시서 #11). 읽기 규칙은 AuraService.summarize가 원본이다.
local AuraService = require(script.Parent.AuraService)
-- 펫 요약(지시서 #12). 읽기 규칙은 PetService.summarize가 원본이다. 보유 150마리(최대 저장 공간)도 한 번에 보낸다 —
-- 크기는 PlayerStateServiceTests가 잰다. 바뀔 때만 보내므로(아래 "보내는 시점") 차분 방식은 두지 않는다.
local PetService = require(script.Parent.PetService)

type BigNumber = BigNum.BigNumber
type PlayerStateView = Remotes.PlayerStateView

local PlayerStateService = {}

local SEND_PERIOD = 0.2 -- 초. 플레이어당 최대 전송 빈도 (위 "빈도 상한")
local LOOP_PERIOD = 0.1 -- 초. 루프 한 틱. SEND_PERIOD보다 짧아야 주기를 놓치지 않는다
local SYNC_COALESCE_SEC = 0.5 -- 초. 이 창 안의 SyncRequest를 하나로 모은다 (수신부 넷이 다 붙을 시간)
local SYNC_WINDOW_SEC = 10 -- 초. 요청 횟수를 세는 창
local SYNC_MAX_PER_WINDOW = 10 -- 그 창 안에서 받아 줄 최대 요청 수. 넘으면 버린다

local BIG_FIELDS = { "blox", "strength", "lifetimeBlox", "lifeBlox", "rebirths" }
local NUMBER_FIELDS = { "walkSpeed", "maxWalkSpeed", "maxStage", "padIndex" }

-- ===== 순수 로직 ==========================================================================

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function copyBig(v: any): BigNumber
	if Schema.isBigNum(v) then
		return BigNum.new(v.m, v.e)
	end
	return BigNum.new(0, 0)
end

local function finiteOr(n: any, fallback: number): number
	return if isFinite(n) then n else fallback
end

-- 프로필 Data와 서비스 값으로 스냅샷을 만든다. 항상 모든 필드를 채운다(선택 필드 금지 —
-- nil인 키는 직렬화에서 사라진다). BigNum은 복사본이고 숫자는 유한하다(inf·nan이면 0).
local function buildSnapshot(data: any, walkSpeed: number?, maxWalkSpeed: number?, padIndex: number?, pets: any?): PlayerStateView
	local progress = if type(data.progress) == "table" then data.progress else {}
	return {
		blox = copyBig(data.blox),
		strength = copyBig(data.strength),
		lifetimeBlox = copyBig(data.lifetimeBlox),
		lifeBlox = copyBig(data.lifeBlox),
		rebirths = copyBig(data.rebirths),
		walkSpeed = finiteOr(walkSpeed, 0),
		maxWalkSpeed = finiteOr(maxWalkSpeed, 0),
		maxStage = finiteOr(progress.maxStage, 1),
		padIndex = finiteOr(padIndex, 1),
		upgrades = UpgradeService.readLevels(data),
		titles = TitleService.summarize(data),
		auras = AuraService.summarize(data),
		-- pets는 호출자가 게임패스(세션 값)를 넣어 만든 요약을 넘긴다(readSnapshot). 없으면 게임패스 없음으로 만든다
		pets = pets or PetService.summarize(data),
	}
end

-- 펫 요약이 같은가. owned는 uid 번호 순, equipped는 장착 순서라 순서까지 같으면 같다.
local function petsEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.slots ~= b.slots or a.storage ~= b.storage or a.hideOtherPets ~= b.hideOtherPets or a.world ~= b.world then
		return false
	end
	if type(a.owned) ~= "table" or type(b.owned) ~= "table" or #a.owned ~= #b.owned then
		return false
	end
	if type(a.equipped) ~= "table" or type(b.equipped) ~= "table" or #a.equipped ~= #b.equipped then
		return false
	end
	for i, e in ipairs(a.owned) do
		local f = b.owned[i]
		if type(f) ~= "table" or f.uid ~= e.uid or f.petId ~= e.petId or f.level ~= e.level then
			return false
		end
	end
	for i, uid in ipairs(a.equipped) do
		if b.equipped[i] ~= uid then
			return false
		end
	end
	return true
end

-- 아우라 요약이 같은가.
local function aurasEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.equipped ~= b.equipped or a.selectedPack ~= b.selectedPack or a.hideOtherAuras ~= b.hideOtherAuras or a.world ~= b.world then
		return false
	end
	if type(a.owned) ~= "table" or type(b.owned) ~= "table" or #a.owned ~= #b.owned then
		return false
	end
	for i, id in ipairs(a.owned) do
		if b.owned[i] ~= id then
			return false
		end
	end
	return true
end

-- 칭호 요약이 같은가. owned는 희귀도 순으로 만들어지므로 순서까지 같으면 같다.
local function titlesEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.equipped ~= b.equipped or a.autoRoll ~= b.autoRoll then
		return false
	end
	if type(a.owned) ~= "table" or type(b.owned) ~= "table" or #a.owned ~= #b.owned then
		return false
	end
	for i, id in ipairs(a.owned) do
		if b.owned[i] ~= id then
			return false
		end
	end
	return true
end

-- 업그레이드 레벨 표가 같은가. 키 집합은 양쪽 다 UpgradeConfig 키다(readLevels — #13 L3 뒤 7키). JSON 왕복 뒤에도 키는 문자열 그대로다.
local function upgradesEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function snapshotsEqual(a: PlayerStateView?, b: PlayerStateView?): boolean
	if a == nil or b == nil then
		return a == b
	end
	for _, key in ipairs(BIG_FIELDS) do
		if not BigNum.eq((a :: any)[key], (b :: any)[key]) then
			return false
		end
	end
	for _, key in ipairs(NUMBER_FIELDS) do
		if (a :: any)[key] ~= (b :: any)[key] then
			return false
		end
	end
	return upgradesEqual((a :: any).upgrades, (b :: any).upgrades) and titlesEqual((a :: any).titles, (b :: any).titles)
		and aurasEqual((a :: any).auras, (b :: any).auras) and petsEqual((a :: any).pets, (b :: any).pets)
end

export type Deps = {
	-- 지금 상태 스냅샷. 프로필이 없으면 nil
	readSnapshot: (Player) -> PlayerStateView?,
	sendState: (Player, PlayerStateView) -> (),
	syncRun: (Player) -> (),
}

type PlayerEntry = {
	lastSent: PlayerStateView?,
	lastSentAt: number,
	syncDueAt: number?,
	syncWindowStart: number,
	syncCount: number,
}

-- 시각을 인자로 받는 상태 기계. 실물은 init()이, 테스트는 가짜 deps로 굴린다.
local function createRuntime(deps: Deps)
	local entries: { [Player]: PlayerEntry } = {}
	-- 로드 전에 온 SyncRequest. 클라 수신부는 접속 직후(프로필 로드보다 먼저) 요청하므로 버리면 안 된다.
	-- 2026-10-22 Play 실측: 버렸더니 접속 직후 런 상태 sync가 한 번도 안 나갔다.
	local requestedBeforeLoad: { [Player]: boolean } = {}

	local function send(player: Player, entry: PlayerEntry, snapshot: PlayerStateView, now: number)
		deps.sendState(player, snapshot)
		entry.lastSent = snapshot
		entry.lastSentAt = now
	end

	local runtime = {}

	-- 프로필 로드 직후. 전체 스냅샷을 바로 1회 보낸다(빈도 상한과 무관).
	function runtime.onLoaded(player: Player, now: number)
		local entry: PlayerEntry = { lastSent = nil, lastSentAt = -math.huge, syncDueAt = nil, syncWindowStart = now, syncCount = 0 }
		entries[player] = entry
		local snapshot = deps.readSnapshot(player)
		if snapshot ~= nil then
			send(player, entry, snapshot, now)
		end
		if requestedBeforeLoad[player] then
			requestedBeforeLoad[player] = nil
			entry.syncCount = 1
			entry.syncDueAt = now + SYNC_COALESCE_SEC
		end
	end

	-- 클라 SyncRequest. 바로 답하지 않고 모은다. 로드 전이면 기억해 두었다가 로드 직후 답한다.
	-- 반환값: 받아 줬는가(테스트용)
	function runtime.onSyncRequest(player: Player, now: number): boolean
		local entry = entries[player]
		if entry == nil then
			requestedBeforeLoad[player] = true
			return true
		end
		if now - entry.syncWindowStart >= SYNC_WINDOW_SEC then
			entry.syncWindowStart = now
			entry.syncCount = 0
		end
		if entry.syncCount >= SYNC_MAX_PER_WINDOW then
			return false
		end
		entry.syncCount += 1
		if entry.syncDueAt == nil then
			entry.syncDueAt = now + SYNC_COALESCE_SEC
		end
		return true
	end

	-- 리스폰 직후. 런 상태만 다시 보낸다(죽으면 런은 포기로 끝나 있다 — 진행 벽·발판을 맞춘다).
	function runtime.onCharacterAdded(player: Player)
		if entries[player] ~= nil then
			deps.syncRun(player)
		end
	end

	function runtime.onRemoving(player: Player)
		entries[player] = nil
		requestedBeforeLoad[player] = nil
	end

	-- 루프 한 틱. 모아 둔 sync가 만기면 전체를 강제로 보내고 런 상태도 보낸다.
	-- 아니면 SEND_PERIOD가 지났고 값이 바뀐 플레이어에게만 보낸다.
	function runtime.tick(now: number)
		for player, entry in pairs(entries) do
			local due = entry.syncDueAt
			if due ~= nil and now >= due then
				entry.syncDueAt = nil
				local snapshot = deps.readSnapshot(player)
				if snapshot ~= nil then
					send(player, entry, snapshot, now)
				end
				deps.syncRun(player)
			elseif now - entry.lastSentAt >= SEND_PERIOD then
				local snapshot = deps.readSnapshot(player)
				if snapshot ~= nil and not snapshotsEqual(snapshot, entry.lastSent) then
					send(player, entry, snapshot, now)
				end
			end
		end
	end

	return runtime
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
PlayerStateService._pure = {
	buildSnapshot = buildSnapshot,
	snapshotsEqual = snapshotsEqual,
	createRuntime = createRuntime,
	SEND_PERIOD = SEND_PERIOD,
	SYNC_COALESCE_SEC = SYNC_COALESCE_SEC,
	SYNC_MAX_PER_WINDOW = SYNC_MAX_PER_WINDOW,
	BIG_FIELDS = BIG_FIELDS,
	NUMBER_FIELDS = NUMBER_FIELDS,
}

-- ===== 런타임 =============================================================================

local initialized = false

local function readSnapshot(player: Player): PlayerStateView?
	local profile = ProfileManager.get(player)
	if profile == nil then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walkSpeed = if humanoid ~= nil then humanoid.WalkSpeed else 0
	return buildSnapshot(profile.Data, walkSpeed, SpeedService.getMaxSpeed(player), PadService.getSelectedIndex(player),
		PetService.summarizeFor(player, profile.Data))
end

function PlayerStateService.init()
	if initialized then
		warn("[PlayerStateService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local channels = Remotes.getServer()
	local runtime = createRuntime({
		readSnapshot = readSnapshot,
		sendState = function(player: Player, snapshot: PlayerStateView)
			channels.playerState:FireClient(player, snapshot)
		end,
		syncRun = function(player: Player)
			ChallengeService.syncRunState(player)
		end,
	})

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			runtime.onCharacterAdded(player)
		end)
	end

	ProfileManager.onLoaded(function(player: Player)
		runtime.onLoaded(player, os.clock())
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		hookCharacter(player)
		if ProfileManager.get(player) ~= nil then
			runtime.onLoaded(player, os.clock())
		end
	end
	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)

	-- payload는 비어 있다(규약 2). 타입도 보지 않는다 — 요청 자체가 신호다. 빈도는 runtime이 자른다.
	channels.syncRequest.OnServerEvent:Connect(function(player: Player)
		runtime.onSyncRequest(player, os.clock())
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum < LOOP_PERIOD then
			return
		end
		accum = 0
		runtime.tick(os.clock())
	end)

	print(string.format(
		"[PlayerStateService] 상태 채널 준비 완료 (플레이어당 최대 %.1f초에 1회, sync 모음 %.1f초)",
		SEND_PERIOD,
		SYNC_COALESCE_SEC
	))
end

return PlayerStateService

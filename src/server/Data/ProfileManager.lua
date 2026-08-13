--!strict
-- 플레이어 프로필 로드/저장 오케스트레이션. ProfileStore(lm-loleris/profilestore@1.0.3) 기반.
-- ⚠️ ProfileService가 아니다 — API가 다르다 (Reconcile은 인자 없이 호출, StartSessionAsync가
-- nil을 반환할 수 있음 등). 이 파일은 ServerPackages/ProfileStore.luau 소스를 직접 읽고 작성했다.
--
-- 로드 순서 (반드시 이 순서): StartSessionAsync -> Migrations.run -> profile:Reconcile()
-- -> Schema.validate -> 신규 프로필 초기화(firstJoin/lastCollectAt)
--
-- 이 모듈이 하지 않는 것:
--   - profile.Data의 재화 필드 직접 수정 (CurrencyService의 몫, Phase 2-2)
--   - run 상태(stage, currentReward, timeLeft) 저장
--   - 게임패스 소유 여부 저장

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Schema = require(script.Parent.Schema)
local Migrations = require(script.Parent.Migrations)

-- ProfileStore.Profile<T>은 제네릭이고 T(profile.Data의 실제 형태)는 Schema.validate가
-- 런타임에 검증하는 대상이라 여기서는 굳이 정적으로 좁히지 않는다.
type Profile = any

-- 스토어 이름 뒤의 "v1"은 schemaVersion과 무관하다. 스키마 변경은 Migrations.lua로 처리하고,
-- 이 이름은 데이터를 통째로 리셋해야 하는 비상 상황(예비)에만 올린다.
local STORE_NAME = "PlayerData_v1"

-- Roblox는 game:BindToClose 콜백에 대략 30초의 예산만 준다. 20초로 끊어서 여유를 두지 않으면
-- 콜백이 강제 종료되면서 진행 중이던 UpdateAsync 호출이 오히려 더 지저분하게 끊길 수 있다.
local BIND_TO_CLOSE_TIMEOUT_SEC = 20

local ProfileManager = {}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, Profile) -> () } = {}
local initialized = false

-- handlePlayerAdded 중복 진입 방지용. Players.PlayerAdded 연결과 GetPlayers() 순회가
-- 같은 플레이어를 동시에 잡을 수 있어서(둘 다 "이 플레이어를 로드해야 함" 신호), 실제로
-- StartSessionAsync를 두 번 호출하지 않도록 여기서 먼저 선점한다.
local loadClaimed: { [Player]: boolean } = {}

-- 실제 DataStore 접근이 불가능한 환경(예: API 서비스 비활성화된 Studio)에서는
-- ProfileStore가 내부적으로 자동 목업 저장소로 전환한다 - 여기서 별도 분기 불필요.
local playerStore = ProfileStore.New(STORE_NAME, Schema.getTemplate())

function ProfileManager.onLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
end

local function fireLoaded(player: Player, profile: Profile)
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, profile)
	end
end

function ProfileManager.get(player: Player): Profile?
	return profiles[player]
end

function ProfileManager.waitFor(player: Player, timeoutSec: number?): Profile?
	local deadline = os.clock() + (timeoutSec or 30)

	while profiles[player] == nil do
		if player.Parent ~= Players then
			return nil -- 로드를 기다리는 동안 플레이어가 나감
		end
		if os.clock() >= deadline then
			return nil -- 타임아웃
		end
		task.wait()
	end

	return profiles[player]
end

local function handlePlayerAdded(player: Player)
	if loadClaimed[player] then
		return -- 이미 다른 경로(PlayerAdded 이벤트 vs GetPlayers() 순회)로 로딩이 시작됨
	end
	loadClaimed[player] = true

	local profile = playerStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- 세션 시작 실패. 데이터 없이 플레이시킬 수 없으므로 무조건 킥한다.
		warn(string.format("[ProfileManager] %s(%d) 세션 시작 실패 - 킥", player.Name, player.UserId))
		if player.Parent == Players then
			player:Kick("데이터 로드에 실패했습니다. 다시 접속해 주세요.")
		end
		return
	end

	if player.Parent ~= Players then
		-- Cancel 콜백이 걸리기 전에 세션이 이미 열린 경우: 로딩 중 나간 유저 처리.
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId) -- GDPR 삭제 요청 대응

	local migrateOk, migrateErr = Migrations.run(profile.Data)
	if not migrateOk then
		warn(string.format("[ProfileManager] %s(%d) 마이그레이션 실패: %s - 킥", player.Name, player.UserId, tostring(migrateErr)))
		profile:EndSession()
		player:Kick("데이터 버전 오류입니다. 다시 접속해 주세요.")
		return
	end

	profile:Reconcile() -- ProfileStore.New()에 넘긴 템플릿 기준으로 누락된 필드 채움

	local valid, errors = Schema.validate(profile.Data)
	if not valid then
		warn(string.format("[ProfileManager] %s(%d) 데이터 검증 실패 - 킥 (손상된 데이터 위에 덮어쓰지 않음)", player.Name, player.UserId))
		for _, err in ipairs(errors) do
			warn("  - " .. err)
		end
		profile:EndSession()
		player:Kick("데이터가 손상되어 로드할 수 없습니다. 관리자에게 문의해 주세요.")
		return
	end

	-- 신규 프로필 초기화. firstJoin이 0이면 이번이 첫 세션이라는 뜻.
	-- ⚠️ 이걸 안 하면 lastCollectAt=0 상태로 오프라인 계산이 돌아서 첫 접속에
	-- 8시간치 드론 보상이 즉시 지급된다 (DESIGN.md 5. 드론).
	local isNewProfile = profile.Data.stats.firstJoin == 0
	if isNewProfile then
		profile.Data.stats.firstJoin = os.time()
		profile.Data.drones.lastCollectAt = os.time()
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		warn(string.format("[ProfileManager] %s(%d) 세션 종료 - 킥 (다른 서버가 세션을 가져갔을 가능성)", player.Name, player.UserId))
		if player.Parent == Players then
			player:Kick("다른 서버에서 데이터를 불러왔습니다. 다시 접속해 주세요.")
		end
	end)

	profiles[player] = profile
	print(string.format("[ProfileManager] %s(%d) 프로필 로드 완료 (신규=%s)", player.Name, player.UserId, tostring(isNewProfile)))
	fireLoaded(player, profile)
end

function ProfileManager.init()
	if initialized then
		warn("[ProfileManager] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- ⚠️ 경쟁 조건: 반드시 Connect가 먼저, GetPlayers() 순회는 그 다음이어야 한다.
	-- 순서가 바뀌면 "GetPlayers() 스냅샷을 찍은 시점"과 "Connect가 걸리는 시점" 사이에
	-- 들어온 플레이어가 스냅샷에도 없고 이벤트도 못 받아서 통째로 누락된다.
	-- Play Solo에서 흔히 재현되지만, 스크립트 초기화가 플레이어 접속보다 늦게 끝나는
	-- 경우라면 라이브 서버에서도 첫 입장자에게 실제로 발생할 수 있는 버그다.
	Players.PlayerAdded:Connect(handlePlayerAdded)

	-- Connect 이후 지금까지 들어와 있는 플레이어(= init() 호출 전에 이미 접속해 있던
	-- 플레이어 포함)를 마저 처리한다. PlayerAdded 이벤트와 이 순회가 같은 플레이어를
	-- 동시에 잡더라도 handlePlayerAdded의 loadClaimed 가드가 중복 로드를 막아준다.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(handlePlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		if profile ~= nil then
			profile:EndSession()
		end
		loadClaimed[player] = nil
	end)

	game:BindToClose(function()
		for _, profile in pairs(profiles) do
			profile:EndSession()
		end

		-- EndSession()은 저장을 새 스레드에서 돌리므로, BindToClose가 끝나기 전에
		-- 실제로 저장이 끝나길(= OnSessionEnd가 profiles에서 지울 때까지) 기다린다.
		-- 단, 무한 대기하지 않는다 - Roblox가 강제로 프로세스를 죽이면 진행 중이던
		-- 저장이 오히려 더 지저분하게 끊길 수 있으므로 타임아웃 후에는 포기하고 빠져나간다.
		local deadline = os.clock() + BIND_TO_CLOSE_TIMEOUT_SEC

		while next(profiles) ~= nil do
			if os.clock() >= deadline then
				local remaining = 0
				for _ in pairs(profiles) do
					remaining = remaining + 1
				end
				warn(string.format("[ProfileManager] BindToClose 타임아웃(%ds) - 저장 미완료 프로필 %d개 남음", BIND_TO_CLOSE_TIMEOUT_SEC, remaining))
				break
			end
			task.wait()
		end
	end)
end

return ProfileManager

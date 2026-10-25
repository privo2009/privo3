--!strict
-- 게임패스 소유 — 세션 메모리 전용 (Phase 8 지시서 #16 · DESIGN 9장 S1).
--
--   접속할 때 등록된(ID ≠ 0) 게임패스를 전부 조회해 **세션 메모리에만** 둔다 — 프로필에 저장하지 않는다(절대 규칙 5, 환불 시 영구 지급 방지).
--   게임 중 구매는 PromptGamePassPurchaseFinished(wasPurchased = true)에서 바로 소유로 바꾼다.
--   조회에 실패한 패스는 미보유로 두고 RETRY_SEC마다 다시 조회한다(서버 단일 루프 — 플레이어마다 루프를 띄우지 않는다).
--   ID 0(미등록) 패스는 조회하지 않는다 — 아무도 갖지 않은 것으로 "확인 끝"이다.
--
--   isResolved(player, key) — 그 패스의 소유가 확정됐는가(조회 성공 · 구매 완료 · 미등록). 펫 장착 잘라내기(E6)처럼
--   "확인이 끝난 뒤에만" 해야 하는 일이 이것을 본다(DESIGN 9장 S17).
--
-- ===== 가짜 소유 (Studio 전용 — Bootstrap TEST_GAMEPASSES) ========================================
--
--   키 목록을 넘기면 Studio에서만 그 패스를 가진 것으로 친다(확정). 저장하지 않는다. Studio가 아니면 무시하고 ERROR 로그.
--   커밋 값 nil은 GamepassServiceTests가 잰다(register로 받은 값 — TestPresetGate와 같은 방식).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local MarketplaceGateway = require(script.Parent.MarketplaceGateway)

local GamepassService = {}

GamepassService.RETRY_SEC = 60 -- 조회 실패한 패스를 다시 조회하는 간격(S1)

export type Deps = {
	gateway: MarketplaceGateway.Gateway,
	isStudio: boolean,
	testPasses: { string }?, -- 가짜 소유(Studio 전용)
	notify: (Player) -> (), -- 소유가 바뀌었다(PlayerState · 효과 반응)
	log: (string) -> (),
	-- 상품표(기본 ShopConfig). 테스트가 ID를 채운 표로 바꿔 끼운다 — 공유 Config를 고치지 않기 위해서다
	catalog: any?,
}

type Entry = {
	owned: { [string]: boolean },
	resolved: { [string]: boolean },
	nextRetryAt: number,
}

-- 가짜 소유 목록을 판정한다. (켤 키 집합 또는 nil, 로그 한 줄 또는 nil)
local function resolveTestPasses(list: any, isStudio: boolean, catalog: any?): ({ [string]: boolean }?, string?)
	local cat = catalog or ShopConfig
	if list == nil then
		return nil, nil
	end
	if not isStudio then
		return nil, "[GamepassService] ERROR Studio가 아닌데 TEST_GAMEPASSES가 켜져 있다 — 무시한다. Bootstrap의 TEST_GAMEPASSES를 nil로 되돌릴 것"
	end
	if type(list) ~= "table" then
		return nil, "[GamepassService] ERROR TEST_GAMEPASSES는 키 목록이어야 한다 — 무시한다"
	end
	local set: { [string]: boolean } = {}
	local names = {}
	for _, key in ipairs(list) do
		local def = cat.get(key)
		if def ~= nil and def.kind == "gamepass" then
			set[key] = true
			table.insert(names, key)
		end
	end
	return set, "[GamepassService] ⚠️ 가짜 소유(Studio 전용 · 저장 안 함): " .. table.concat(names, ", ")
end

local function createRuntime(deps: Deps)
	local entries: { [Player]: Entry } = {}
	local catalog = deps.catalog or ShopConfig
	local fakeSet, fakeLine = resolveTestPasses(deps.testPasses, deps.isStudio, catalog)
	if fakeLine ~= nil then
		deps.log(fakeLine)
	end
	local runtime = {}

	local function query(player: Player, entry: Entry, key: string): boolean
		local def = catalog.get(key) :: ShopConfig.ProductDef
		local ok, owns = deps.gateway.ownsGamePass(player.UserId, def.id)
		if ok then
			entry.owned[key] = owns
			entry.resolved[key] = true
		else
			entry.owned[key] = false
			entry.resolved[key] = false
		end
		return ok
	end

	-- 접속: 등록된 패스를 전부 조회한다(yield할 수 있다 — 호출자가 task.spawn으로 한 번 부른다).
	function runtime.onJoin(player: Player, now: number)
		local entry: Entry = { owned = {}, resolved = {}, nextRetryAt = now + GamepassService.RETRY_SEC }
		entries[player] = entry
		for _, key in ipairs(catalog.gamepassKeys()) do
			if fakeSet ~= nil and fakeSet[key] then
				entry.owned[key] = true
				entry.resolved[key] = true
			elseif not catalog.isRegistered(key) then
				entry.owned[key] = false
				entry.resolved[key] = true -- 미등록 = 아무도 없다(확정)
			else
				query(player, entry, key)
			end
			if entries[player] ~= entry then
				return -- 조회 도중 나갔다
			end
		end
		deps.notify(player)
	end

	-- 루프 한 틱: 실패한 패스만 RETRY_SEC마다 다시 조회한다.
	function runtime.tick(now: number)
		for player, entry in pairs(entries) do
			if now >= entry.nextRetryAt then
				entry.nextRetryAt = now + GamepassService.RETRY_SEC
				local changed = false
				for _, key in ipairs(catalog.gamepassKeys()) do
					if not entry.resolved[key] and query(player, entry, key) then
						changed = true
					end
				end
				if changed then
					deps.notify(player)
				end
			end
		end
	end

	-- 게임 중 구매 완료 이벤트. 산 것만 바로 소유로 바꾼다(취소는 그대로).
	function runtime.onPurchaseFinished(player: Player, passId: number, wasPurchased: boolean): string?
		local key = catalog.findById("gamepass", passId)
		local entry = entries[player]
		if key == nil or entry == nil or not wasPurchased then
			return key
		end
		entry.owned[key] = true
		entry.resolved[key] = true
		deps.notify(player)
		return key
	end

	function runtime.owns(player: Player, key: string): boolean
		local entry = entries[player]
		return entry ~= nil and entry.owned[key] == true
	end

	function runtime.isResolved(player: Player, key: string): boolean
		local entry = entries[player]
		return entry ~= nil and entry.resolved[key] == true
	end

	-- 보유한 키(이름순). PlayerState가 클라에 보낸다.
	function runtime.ownedKeys(player: Player): { string }
		local out = {}
		local entry = entries[player]
		if entry ~= nil then
			for key, v in pairs(entry.owned) do
				if v then
					table.insert(out, key)
				end
			end
		end
		table.sort(out)
		return out
	end

	function runtime.onRemoving(player: Player)
		entries[player] = nil
	end

	return runtime
end

GamepassService._pure = {
	createRuntime = createRuntime,
	resolveTestPasses = resolveTestPasses,
}

-- ===== 런타임 ======================================================================================

local runtime: any = nil
local changeListeners: { (Player) -> () } = {}
local requested: { string }? = nil
local registered = false

-- Bootstrap의 TEST_GAMEPASSES 값을 기록한다(init이 부른다). 테스트가 커밋 값(nil)을 확인하는 통로다.
function GamepassService.getRequestedTestPasses(): ({ string }?, boolean)
	return requested, registered
end

-- 소유가 바뀌면 부른다(접속 조회 끝 · 재조회 성공 · 게임 중 구매). 반응하는 쪽이 등록한다(순환 방지).
function GamepassService.onChanged(callback: (Player) -> ())
	table.insert(changeListeners, callback)
end

function GamepassService.owns(player: Player, key: string): boolean
	return runtime ~= nil and runtime.owns(player, key)
end

function GamepassService.isResolved(player: Player, key: string): boolean
	return runtime ~= nil and runtime.isResolved(player, key)
end

function GamepassService.ownedKeys(player: Player): { string }
	return if runtime ~= nil then runtime.ownedKeys(player) else {}
end

-- owns를 키 하나만 받는 함수로(ShopConfig의 owns 인자에 그대로 넘긴다).
function GamepassService.ownsFn(player: Player): (string) -> boolean
	return function(key: string): boolean
		return GamepassService.owns(player, key)
	end
end

local initialized = false

function GamepassService.init(testPasses: { string }?)
	if initialized then
		warn("[GamepassService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	requested = testPasses
	registered = true
	local gateway = MarketplaceGateway.get()
	runtime = createRuntime({
		gateway = gateway,
		isStudio = RunService:IsStudio(),
		testPasses = testPasses,
		notify = function(player: Player)
			for _, cb in ipairs(changeListeners) do
				local ok, err = pcall(cb, player)
				if not ok then
					warn("[GamepassService] 소유 변경 반응 실패: " .. tostring(err))
				end
			end
		end,
		log = function(line: string)
			warn(line)
		end,
	})
	gateway.onGamePassPurchaseFinished(function(player: Player, passId: number, wasPurchased: boolean)
		local key = runtime.onPurchaseFinished(player, passId, wasPurchased)
		print(string.format("[GamepassService] %s(%d) 구매 완료 이벤트 pass=%d key=%s 구매=%s", player.Name, player.UserId, passId, tostring(key), tostring(wasPurchased)))
	end)
	local function join(player: Player)
		task.spawn(function()
			runtime.onJoin(player, os.clock())
			print(string.format("[GamepassService] %s(%d) 소유 확인 끝 — 보유 %s", player.Name, player.UserId, table.concat(runtime.ownedKeys(player), ", ")))
		end)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in ipairs(Players:GetPlayers()) do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			runtime.tick(os.clock())
		end
	end)
	print("[GamepassService] 게임패스 소유 확인 준비 완료 (세션 메모리 전용 · 실패 재조회 " .. GamepassService.RETRY_SEC .. "초)")
end

return GamepassService

--!strict
-- 새 경제 광석 드롭 · 줍기 · 런 가방 · 코인 획득 · 대장간 열림(지시서 #32 — DESIGN 16장 "광석과 드롭"). ⚠️ 플래그 ECONOMY_V2 뒤.
--
-- 플래그가 꺼져 있으면 Bootstrap이 이 서비스를 init하지 않고 ChallengeService에 고리를 걸지 않는다 — 게임은 지금과 똑같다.
--
-- 서버 권위(CLAUDE.md 절대 규칙 3):
--   드롭      블록이 깨지면 서버가 그 층 드롭을 굴린다(EconomyV2Logic.rollDrops). 드롭은 이 서비스의 런 상태(메모리)에 있다 —
--             클라에는 "어디에 무엇이 떨어졌다"만 알려 그리게 한다(물리 없음 · 표시는 클라 전용 — 절대 규칙 4)
--   줍기      서버 단일 폴링 루프(PICKUP_POLL_SEC)가 거리로 판정한다 — 드롭이 있는가 · 반경(PICKUP_RADIUS) 안인가 · 가방에 자리가 있는가.
--             클라 요청은 받지 않는다(줍기 채널이 없다). 거리는 수평(XZ) — 드롭은 바닥(Y 0)에 있고 루트는 그 위에 있다
--             ⚠️ AttackService의 "별도 폴링 루프 금지"는 펀치 거리 판정 이야기다 — 줍기는 펀치와 무관한 판정이라 자기 루프 하나를 둔다
--   가방      용량 = 장착 곡괭이 등급(EconomyV2Logic.bagCapacity) × 큰 가방 패스(ID nil이면 1). 가득 차면 새 광석이 가방 안 가장 낮은 것보다
--             좋을 때만 바꿔 줍고(낮은 것은 사라진다) 아니면 바닥에 남는다(EconomyV2Logic.addToBag)
--   층 이동   다음 층으로 가면 남은 드롭은 사라진다(가방은 그대로)
--   자동 진행 보유자(게임패스 autoAdvance)는 거리와 상관없이 전부 줍는다. 가방 상한은 그대로
--   런 끝     수령 → 가방을 인벤토리로(InventoryService.addOres) · 실패 · 사망 · 이탈 · 나가기 → 가방을 비운다(G11)
--   코인      블록이 깨지면 그 층 코인이 바로 들어온다(CurrencyService "coins" — 실패해도 잃지 않는다) · 클라에 코인 이펙트 신호
--   대장간    FORGE_UNLOCK_STAGE에 처음 도달하면 열림을 저장(InventoryService.openForge — 영구)하고 알린다. 열리기 전에 첫 광석을 주우면
--             안내를 한 번(세션당 · 인벤토리 광석이 0일 때만 — 새 저장 필드 없이 "처음"을 고른다)
-- ⚠️ 고리 함수(onStageEnter · onBlocksDestroyed · onRunEnded)는 yield하지 않는다(ChallengeService가 판정 중에 부른다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type BigNumber = BigNum.BigNumber

local OreDropService = {}

export type Drop = { id: number, ore: number, position: Vector3 }
export type RunEcon = {
	stage: number,
	drops: { [number]: Drop },
	nextId: number,
	bag: { number },
}

-- ===== 순수 로직 (Player · 프로필 없음 — OreDropServiceTests가 _pure로 부른다) ===========================

local function newRunEcon(stage: number): RunEcon
	return { stage = stage, drops = {}, nextId = 1, bag = EconomyV2Logic.newInv() }
end

local function bagUsed(bag: { number }): number
	local n = 0
	for k = 1, Config.ORE_COUNT do
		n += bag[k] or 0
	end
	return n
end

-- 깨진 블록 자리들에 그 층 드롭을 굴려 만든다. 새로 생긴 드롭 목록을 돌려준다. rand: [0, 1)
local function spawnDrops(state: RunEcon, stage: number, positions: { Vector3 }, rand: () -> number): { Drop }
	local ore = EconomyV2Logic.oreOf(stage)
	local made: { Drop } = {}
	for _, pos in ipairs(positions) do
		local n = EconomyV2Logic.rollDrops(stage, 1, rand)
		for _ = 1, n do
			local angle = rand() * math.pi * 2
			local r = rand() * Config.DROP_SCATTER
			local d: Drop = { id = state.nextId, ore = ore, position = Vector3.new(pos.X + math.cos(angle) * r, 0, pos.Z + math.sin(angle) * r) }
			state.nextId += 1
			state.drops[d.id] = d
			table.insert(made, d)
		end
	end
	return made
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 한 번의 줍기 판정. rootPosition 근처(반경 radius — 수평) 또는 all이면 전부를 후보로, 높은 광석부터 가방에 넣는다.
-- 들어간 드롭은 바닥에서 지운다 · 못 들어간 것(가득 + 더 좋지 않음)은 남는다. 주운 id 목록을 돌려준다.
local function pickupPass(state: RunEcon, cap: number, rootPosition: Vector3?, radius: number, all: boolean): { number }
	local candidates: { Drop } = {}
	for _, d in pairs(state.drops) do
		if all or (rootPosition ~= nil and horizontalDistance(rootPosition, d.position) <= radius) then
			table.insert(candidates, d)
		end
	end
	table.sort(candidates, function(a, b)
		if a.ore ~= b.ore then
			return a.ore > b.ore
		end
		return a.id < b.id
	end)
	local picked: { number } = {}
	for _, d in ipairs(candidates) do
		if EconomyV2Logic.addToBag(state.bag, cap, d.ore, 1) == 1 then
			state.drops[d.id] = nil
			table.insert(picked, d.id)
		end
	end
	return picked
end

-- 층이 바뀌면 바닥 드롭만 사라진다(가방은 그대로)
local function enterStage(state: RunEcon, stage: number)
	state.stage = stage
	table.clear(state.drops)
end

-- 수령: 가방 → {광석 번호 = 개수}(0은 빼고) · 가방을 비운다
local function takeBag(state: RunEcon): { [number]: number }
	local counts: { [number]: number } = {}
	for k = 1, Config.ORE_COUNT do
		if (state.bag[k] or 0) > 0 then
			counts[k] = state.bag[k]
		end
		state.bag[k] = 0
	end
	return counts
end

-- 실패 · 이탈: 가방과 바닥을 비운다. 잃은 개수를 돌려준다
local function discard(state: RunEcon): number
	local lost = bagUsed(state.bag)
	for k = 1, Config.ORE_COUNT do
		state.bag[k] = 0
	end
	table.clear(state.drops)
	return lost
end

-- 깨진 블록 수만큼 그 층 코인
local function coinsFor(stage: number, blocks: number): BigNumber
	return BigNum.mul(EconomyV2Logic.coinPerBlock(stage), BigNum.fromNumber(blocks))
end

-- 이 층 도달로 대장간이 새로 열리는가(이미 열렸으면 false)
local function opensForge(alreadyOpen: boolean, stage: number): boolean
	return not alreadyOpen and Config.FORGE_UNLOCK_STAGE ~= nil and EconomyV2Logic.forgeOpen(stage, nil)
end

OreDropService._pure = {
	newRunEcon = newRunEcon,
	bagUsed = bagUsed,
	spawnDrops = spawnDrops,
	pickupPass = pickupPass,
	enterStage = enterStage,
	takeBag = takeBag,
	discard = discard,
	coinsFor = coinsFor,
	opensForge = opensForge,
	horizontalDistance = horizontalDistance,
}

-- ===== 바깥 세계 이음매 (테스트가 기록용으로 바꿔 끼운다 — 바꾼 뒤 반드시 되돌릴 것) ======================

export type Deps = {
	addCoins: (Player, BigNumber, string) -> (boolean, BigNumber?),
	getCoins: (Player) -> BigNumber?,
	addOres: (Player, { [number]: number }, string) -> boolean,
	getOres: (Player) -> { number }?,
	isForgeOpen: (Player) -> boolean,
	openForge: (Player, string) -> boolean,
	getEquipped: (Player) -> string?,
	ownsAutoAdvance: (Player) -> boolean,
	ownsBigBag: (Player) -> boolean,
	rootPosition: (Player) -> Vector3?,
	send: (Player, any) -> (),
	rand: () -> number,
}

local function liveDeps(): Deps
	local CurrencyService = require(script.Parent.CurrencyService)
	local InventoryService = require(script.Parent.InventoryService)
	local GamepassService = require(script.Parent.GamepassService)
	local Proximity = require(script.Parent.Proximity)
	local channels = Remotes.getServer()
	local rng = Random.new()
	return {
		addCoins = function(player, amount, reason)
			return CurrencyService.add(player, "coins", amount, reason)
		end,
		getCoins = function(player)
			return CurrencyService.get(player, "coins")
		end,
		addOres = InventoryService.addOres,
		getOres = InventoryService.getOres,
		isForgeOpen = InventoryService.isForgeOpen,
		openForge = InventoryService.openForge,
		getEquipped = function(player)
			return InventoryService.getEquipped(player, "pickaxe")
		end,
		ownsAutoAdvance = function(player)
			return GamepassService.owns(player, "autoAdvance")
		end,
		ownsBigBag = function(_player)
			-- 큰 가방 패스 자리(#32). ID가 nil이면 효과 없음. ID가 생기면 #35 상품 코드에서 ShopConfig 키로 잇는다
			return false
		end,
		rootPosition = function(player)
			return (Proximity.rootPosition(player))
		end,
		send = function(player, payload)
			if typeof(player) == "Instance" and player:IsA("Player") then
				channels.economyEvent:FireClient(player, payload)
			end
		end,
		rand = function()
			return rng:NextNumber()
		end,
	}
end

OreDropService._deps = nil :: Deps?

local function deps(): Deps
	if OreDropService._deps == nil then
		OreDropService._deps = liveDeps()
	end
	return OreDropService._deps :: Deps
end

local states: { [Player]: RunEcon } = {}
local hinted: { [Player]: boolean } = {} -- 대장간 안내를 이번 세션에 띄웠나(저장하지 않는다)

local function capOf(player: Player): number
	local d = deps()
	local id = d.getEquipped(player) or Config.START_PICKAXE
	if EconomyV2Logic.pickaxe(id) == nil then
		id = Config.START_PICKAXE
	end
	local pass = if Config.BIG_BAG_PASS_ID ~= nil and d.ownsBigBag(player) then Config.BIG_BAG_MULT else nil
	return EconomyV2Logic.bagCapacity(id, pass)
end

local function bagPayload(player: Player, state: RunEcon?, kind: string): any
	local bag = if state ~= nil then table.clone(state.bag) else EconomyV2Logic.newInv()
	return { kind = kind, bag = bag, used = bagUsed(bag), cap = capOf(player) }
end

-- 장착을 바꿔 가방 용량이 바뀌었다(#34 — EquipmentService가 부른다). 바뀐 용량을 바로 보낸다. 줄어 넘치면 든 광석은 그대로 두고
-- 새로 줍기만 막힌다(EconomyV2Logic.addToBag — 넘친 동안 0개)
function OreDropService.refreshBag(player: Player)
	deps().send(player, bagPayload(player, states[player], "bag"))
end

-- 지금 상태 한 번에(접속 · 동기화). 클라 HUD가 이것으로 시작한다
function OreDropService.sendSnapshot(player: Player)
	local d = deps()
	local state = states[player]
	local payload = bagPayload(player, state, "snapshot")
	payload.coins = d.getCoins(player) or BigNum.new(0, 0)
	payload.ores = d.getOres(player) or EconomyV2Logic.newInv()
	payload.forgeOpen = d.isForgeOpen(player)
	local drops = {}
	if state ~= nil then
		for _, dr in pairs(state.drops) do
			table.insert(drops, { id = dr.id, ore = dr.ore, position = dr.position })
		end
	end
	payload.drops = drops
	d.send(player, payload)
end

-- ===== 고리 (ChallengeService가 부른다 — Bootstrap이 플래그가 켜졌을 때만 건다) =================================

-- 런 시작(start) · 다음 층(advance). start면 새 가방, advance면 바닥 드롭만 사라진다. 대장간 첫 도달 검사.
function OreDropService.onStageEnter(player: Player, stage: number, reason: string)
	local d = deps()
	local state = states[player]
	if reason == "start" or state == nil then
		if state ~= nil then
			discard(state)
		end
		state = newRunEcon(stage)
		states[player] = state
	else
		enterStage(state, stage)
	end
	d.send(player, { kind = "clear", stage = stage })
	if opensForge(d.isForgeOpen(player), stage) then
		if d.openForge(player, "forge_reach_stage_" .. tostring(stage)) then
			d.send(player, { kind = "forge_open", stage = stage })
		end
	end
end

-- 블록이 깨졌다(positions = 깨진 블록 자리). 드롭을 굴리고 코인을 넣는다.
function OreDropService.onBlocksDestroyed(player: Player, stage: number, positions: { Vector3 })
	if #positions == 0 then
		return
	end
	local d = deps()
	local state = states[player]
	if state == nil then
		state = newRunEcon(stage)
		states[player] = state
	end
	local made = spawnDrops(state, stage, positions, d.rand)
	if #made > 0 then
		local list = {}
		for _, dr in ipairs(made) do
			table.insert(list, { id = dr.id, ore = dr.ore, position = dr.position })
		end
		d.send(player, { kind = "drops", stage = stage, drops = list })
	end
	local amount = coinsFor(stage, #positions)
	local ok, total = d.addCoins(player, amount, "block_break")
	if ok and total ~= nil then
		d.send(player, { kind = "coins", amount = amount, total = total, positions = positions })
	end
end

-- 런 끝(ChallengeService.endRun — cashout · timeout · abandon). 수령이면 가방 → 인벤토리, 아니면 가방을 잃는다.
function OreDropService.onRunEnded(player: Player, reason: string)
	local d = deps()
	local state = states[player]
	states[player] = nil
	if state == nil then
		return
	end
	if reason == "cashout" then
		local counts = takeBag(state)
		if next(counts) ~= nil then
			if not d.addOres(player, counts, "cashout_bag") then
				warn(string.format("[OreDropService] %s 가방 → 인벤토리 실패 — 가방 광석을 잃었다", player.Name))
			end
		end
	else
		discard(state)
	end
	table.clear(state.drops)
	d.send(player, bagPayload(player, nil, "bag"))
	d.send(player, { kind = "clear", stage = state.stage })
	local ores = d.getOres(player)
	if ores ~= nil then
		d.send(player, { kind = "ores", ores = ores })
	end
end

-- 줍기 한 번(루프 · 테스트). 주운 게 있으면 가방 신호 · 처음 주운 광석이면 대장간 안내.
function OreDropService.pickupTick(player: Player)
	local state = states[player]
	if state == nil or next(state.drops) == nil then
		return
	end
	local d = deps()
	local all = d.ownsAutoAdvance(player)
	local root = if all then nil else d.rootPosition(player)
	if not all and root == nil then
		return
	end
	local wasEmpty = bagUsed(state.bag) == 0
	local picked = pickupPass(state, capOf(player), root, Config.PICKUP_RADIUS, all)
	if #picked == 0 then
		return
	end
	local payload = bagPayload(player, state, "picked")
	payload.ids = picked
	d.send(player, payload)
	if wasEmpty and not hinted[player] and not d.isForgeOpen(player) then
		local ores = d.getOres(player)
		local total = 0
		for _, n in ipairs(ores or {}) do
			total += n
		end
		if total == 0 then
			hinted[player] = true
			d.send(player, { kind = "forge_hint", stage = Config.FORGE_UNLOCK_STAGE or 0 })
		end
	end
end

-- 테스트 전용: 상태 들여다보기 · 지우기
function OreDropService._state(player: Player): RunEcon?
	return states[player]
end
function OreDropService._reset(player: Player)
	states[player] = nil
	hinted[player] = nil
end

local initialized = false

function OreDropService.init()
	if initialized then
		return
	end
	initialized = true
	-- 서버 단일 줍기 루프(플레이어별 task.spawn 아님 — AttackService · SpeedService와 같은 관례)
	task.spawn(function()
		while true do
			task.wait(Config.PICKUP_POLL_SEC)
			for player in pairs(states) do
				local ok, err = pcall(OreDropService.pickupTick, player)
				if not ok then
					warn("[OreDropService] 줍기 오류: " .. tostring(err))
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil -- 나가기 = 가방을 잃는다(G11 — 저장하지 않았으니 지우면 끝)
		hinted[player] = nil
	end)
	-- HUD 시작값: 프로필이 로드되면 · 클라가 SyncRequest를 보내면(PlayerStateService와 같은 신호 — 로드 전이면 로드 때 보낸다)
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	ProfileManager.onLoaded(function(player: Player)
		OreDropService.sendSnapshot(player)
	end)
	Remotes.getServer().syncRequest.OnServerEvent:Connect(function(player: Player)
		task.delay(0.6, function()
			if player.Parent ~= nil and ProfileManager.get(player) ~= nil then
				OreDropService.sendSnapshot(player)
			end
		end)
	end)
	print(string.format("[OreDropService] 새 경제 드롭 · 줍기 시작 (반경 %.1f · 주기 %.2f초 · 대장간 %s층)", Config.PICKUP_RADIUS,
		Config.PICKUP_POLL_SEC, tostring(Config.FORGE_UNLOCK_STAGE)))
end

return OreDropService

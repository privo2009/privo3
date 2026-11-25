--!strict
-- 복제(dupe) 경로 점검(지시서 #38 — 리모트 보안). 재화 · 아이템이 한 번 몫보다 늘지 않는다.
-- 가짜 플레이어 표 + 가짜 프로필(ProfileManager._attachTestProfile — Studio 전용 · 실제 저장소에 닿지 않는다)에
-- 실물 서비스(ChallengeService · CurrencyService · InventoryService · ForgeService · EquipmentService · OreDropService)를 그대로 돌린다.
--   1. 수령 두 번 · 수령 뒤 포기(나가기와 같은 길)   2. 실패(포기) 뒤 수령   3. 환생 중 수령
--   4. 제작 · 교환 · 강화 · 별 연달아(재료는 한 번 몫)   5. 대장간 · 장비 입구로 같은 시각 연타
-- 개발자 상품 지급 중 나가기 · 같은 영수증 두 번은 ProductServiceTests(프로필 미로드 → NotProcessedYet · 지급 1회)가 본다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local Schema = require(script.Parent.Parent.Data.Schema)
local ChallengeService = require(script.Parent.ChallengeService)
local CurrencyService = require(script.Parent.CurrencyService)
local InventoryService = require(script.Parent.InventoryService)
local ForgeService = require(script.Parent.ForgeService)
local EquipmentService = require(script.Parent.EquipmentService)
local OreDropService = require(script.Parent.OreDropService)
local RebirthService = require(script.Parent.RebirthService)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function noop() end
local P = ({ Name = "DupeTestPlayer", UserId = -3800 } :: any) :: Player

-- 경제 고리(가방)는 Bootstrap이 테스트와 같은 때 걸고, OreDropServiceTests는 잠깐 가짜 고리로 바꿔 끼운다 —
-- **실물 고리**(OreDropService 함수)가 걸려 있을 때까지 기다린다(상한 20초 · 넘으면 아래 가방 줄이 실패한다).
-- 그 뒤로 이 파일은 끝까지 yield하지 않는다 — 다른 테스트가 고리 · _deps를 바꿔 끼우는 틈이 없다
do
	local deadline = os.clock() + 20
	local function realHooks(): boolean
		local h = (ChallengeService :: any).economyHooks
		return type(h) == "table" and h.onRunEnded == OreDropService.onRunEnded and h.onStageEnter == OreDropService.onStageEnter
	end
	while not realHooks() and os.clock() < deadline do
		task.wait(0.2)
	end
end

local data = Schema.new()
local attached = ProfileManager._attachTestProfile(P, data)
check("준비: 가짜 프로필이 붙었다(Studio · 가짜 플레이어 표)", attached)

-- 경제 고리(가방 → 인벤토리)는 실물 함수 그대로 — 바깥(신호 · 게임패스 · 위치)만 조용히
local savedOre = OreDropService._deps
OreDropService._deps = {
	addCoins = function(p, amount, reason)
		return CurrencyService.add(p, "coins", amount, reason)
	end,
	getCoins = function(p)
		return CurrencyService.get(p, "coins")
	end,
	addOres = InventoryService.addOres,
	getOres = InventoryService.getOres,
	isForgeOpen = InventoryService.isForgeOpen,
	openForge = InventoryService.openForge,
	getEquipped = function(p)
		return InventoryService.getEquipped(p, "pickaxe")
	end,
	ownsAutoAdvance = function()
		return false
	end,
	ownsBigBag = function()
		return false
	end,
	rootPosition = function()
		return nil
	end,
	send = noop,
	rand = function()
		return 0.5
	end,
} :: any

local function clearedRun(stage: number): boolean
	ChallengeService.startRun(P, stage)
	ChallengeService.applyDamage(P, Vector3.new(0, 0, 0), BigNum.new(1, 300))
	local view = ChallengeService.getRunState(P)
	return view ~= nil and (view :: any).cleared == true
end

local function putInBag(ore: number, n: number)
	local s = OreDropService._state(P)
	if s ~= nil then
		s.bag[ore] += n
	end
end

-- 1. 수령 두 번 · 수령 뒤 포기 -------------------------------------------------------------------------
do
	local cleared = clearedRun(1)
	check("수령: 1층 런을 클리어했다(준비)", cleared)
	putInBag(1, 4)
	local before = data.blox
	local ores0 = data.ores[1]
	local ok1, reward = ChallengeService.cashout(P, "dupe_test")
	local afterFirst = data.blox
	local ok2 = ChallengeService.cashout(P, "dupe_test")
	local ok3 = ChallengeService.abandonRun(P)
	check("수령 두 번: 처음만 성공 · 뒤 수령과 포기(나가기와 같은 끝)는 런 없음", ok1 and not ok2 and not ok3)
	check("수령 두 번: 블럭스는 한 번 몫만 늘었다", reward ~= nil and BigNum.eq(afterFirst, BigNum.add(before, reward :: any))
		and BigNum.eq(data.blox, afterFirst))
	check("수령 두 번: 가방 광석은 한 번만 인벤토리로", data.ores[1] == ores0 + 4, string.format("%d → %d", ores0, data.ores[1]))
end

-- 2. 실패(포기) 뒤 수령 ---------------------------------------------------------------------------------
do
	local cleared = clearedRun(1)
	putInBag(1, 3)
	local blox0 = data.blox
	local ores0 = data.ores[1]
	local abandoned = ChallengeService.abandonRun(P)
	local ok = ChallengeService.cashout(P, "dupe_test")
	check("실패 뒤 수령: 포기한 런은 수령되지 않는다", cleared and abandoned and not ok)
	check("실패 뒤 수령: 블럭스 그대로 · 가방은 사라짐(인벤토리 그대로)", BigNum.eq(data.blox, blox0) and data.ores[1] == ores0)
end

-- 3. 환생 중 수령: 환생은 yield 없이 런을 버린다 — 그 뒤 수령은 런 없음 ---------------------------------------
do
	local cleared = clearedRun(1)
	putInBag(1, 2)
	local ores0 = data.ores[1]
	data.blox = BigNum.new(1, 6)
	local fake: any = setmetatable({
		getBlox = function(p)
			return CurrencyService.get(p, "blox")
		end,
		abandonRun = ChallengeService.abandonRun,
		subtractBlox = function(p, amount, reason)
			return (CurrencyService.subtract(p, "blox", amount, reason))
		end,
		setBlox = function(p, amount, reason)
			return (CurrencyService.set(p, "blox", amount, reason))
		end,
		getRebirths = function(p)
			return CurrencyService.get(p, "rebirths")
		end,
		addRebirths = function(p, amount, reason)
			return CurrencyService.add(p, "rebirths", amount, reason)
		end,
	}, { __index = function()
		return function()
			return true -- 바깥(속도 · 패드 · 층 되돌리기)은 성공으로 친다
		end
	end })
	local okR = RebirthService._pure.runRebirth(fake, P, "dupe_test")
	local bloxAfterRebirth = data.blox
	local okC = ChallengeService.cashout(P, "dupe_test")
	check("환생 중 수령: 환생 성공 · 런은 버려져 수령 실패", cleared and okR and not okC)
	check("환생 중 수령: 블럭스는 환생 뒤 값 그대로(보상 안 더함) · 가방 광석 안 들어옴",
		BigNum.eq(data.blox, bloxAfterRebirth) and data.ores[1] == ores0)
end

-- 4. 인벤토리 관문 연달아(재료는 한 번 몫) ---------------------------------------------------------------
do
	data.ores = EconomyV2Logic.newInv()
	data.ores[1] = Config.CRAFT_INPUT
	local id = "pick_c2"
	local c1 = InventoryService.craft(P, { [1] = Config.CRAFT_INPUT }, "pickaxe", { id }, { rare = 1 }, "dupe_craft")
	local c2 = InventoryService.craft(P, { [1] = Config.CRAFT_INPUT }, "pickaxe", { id }, { rare = 1 }, "dupe_craft")
	local owned = data.equipment.pickaxe[id]
	check("제작 연달아: 광석 한 번 몫 → 한 번만 · 광석 0 · 곡괭이 1 · 토큰 1", c1 and not c2 and data.ores[1] == 0 and owned ~= nil
		and owned.count == 1 and data.tokens.rare == 1)

	data.tokens.rare = 3 -- pick_r1 교환 비용 3
	local e1 = InventoryService.exchange(P, "pickaxe", "pick_r1", { rare = 3 }, "dupe_exchange")
	local e2 = InventoryService.exchange(P, "pickaxe", "pick_r1", { rare = 3 }, "dupe_exchange")
	check("교환 연달아: 토큰 한 번 몫 → 한 번만 · 토큰 0 · 곡괭이 1", e1 and not e2 and data.tokens.rare == 0 and data.equipment.pickaxe.pick_r1.count == 1)

	local start = Config.START_PICKAXE
	local cost = EconomyV2Logic.enhanceCost(0, start) :: number
	data.ores = EconomyV2Logic.newInv()
	data.ores[1] = math.ceil(cost / Config.ORE_POINTS[1])
	local h1 = InventoryService.enhance(P, "pickaxe", start, "dupe_enhance")
	local h2 = InventoryService.enhance(P, "pickaxe", start, "dupe_enhance")
	check("강화 연달아: 광석 한 번 몫 → +1만 · 광석 음수 없음", h1 and not h2 and data.equipment.pickaxe[start].enh == 1 and data.ores[1] >= 0)

	local need = EconomyV2Logic.starCost(0) :: number
	data.equipment.pickaxe[start].count = 1 + need
	local s1 = InventoryService.starUp(P, "pickaxe", start, "dupe_star")
	local s2 = InventoryService.starUp(P, "pickaxe", start, "dupe_star")
	check("별 연달아: 사본 한 번 몫 → ★1만 · 남은 수 1", s1 and not s2 and data.equipment.pickaxe[start].stars == 1
		and data.equipment.pickaxe[start].count == 1)
end

-- 5. 입구로 같은 시각 연타(대장간 · 장비 — 서비스 자체 0.15초 · 제작 간격) ---------------------------------
do
	local clock = 1000
	local savedForge = ForgeService._deps
	ForgeService._deps = {
		isForgeOpen = InventoryService.isForgeOpen,
		getOres = InventoryService.getOres,
		getTokens = InventoryService.getTokens,
		getOwned = function(p)
			return InventoryService.getOwned(p, "pickaxe")
		end,
		craft = InventoryService.craft,
		exchange = InventoryService.exchange,
		ownsSkipPass = function()
			return false
		end,
		ownsTriple = function()
			return false
		end,
		send = noop,
		rand = function()
			return 0.5
		end,
		now = function()
			return clock
		end,
	} :: any
	ForgeService._reset(P)
	data.forgeOpen = true
	data.ores = EconomyV2Logic.newInv()
	data.ores[1] = Config.CRAFT_INPUT * 3
	local total0 = 0
	for _, n in pairs(InventoryService.getOwned(P, "pickaxe") or {}) do
		total0 += n
	end
	local oks = 0
	for _ = 1, 30 do
		ForgeService.handleRequest(P, { action = "craft", combo = { 1, 1, 1, 1, 1 } })
	end
	local total1 = 0
	for _, n in pairs(InventoryService.getOwned(P, "pickaxe") or {}) do
		total1 += n
	end
	oks = total1 - total0
	check("대장간 연타(같은 시각 30번): 제작 1번 · 광석은 그 몫만 줄었다", oks == 1 and data.ores[1] == Config.CRAFT_INPUT * 2,
		string.format("제작 %d · 광석 %d", oks, data.ores[1]))
	ForgeService._reset(P)
	ForgeService._deps = savedForge

	local savedEq = EquipmentService._deps
	EquipmentService._deps = {
		isForgeOpen = InventoryService.isForgeOpen,
		getEquipment = function(p)
			return InventoryService.getEquipment(p, "pickaxe")
		end,
		getEquipped = function(p)
			return InventoryService.getEquipped(p, "pickaxe")
		end,
		getOres = InventoryService.getOres,
		equip = InventoryService.equip,
		enhance = InventoryService.enhance,
		starUp = InventoryService.starUp,
		onEquipped = noop,
		send = noop,
		now = function()
			return clock
		end,
	} :: any
	EquipmentService._reset(P)
	local start = Config.START_PICKAXE
	local enh0 = data.equipment.pickaxe[start].enh
	data.ores = EconomyV2Logic.newInv()
	data.ores[10] = 999
	for _ = 1, 30 do
		EquipmentService.handleRequest(P, { action = "enhance", id = start })
	end
	check("장비 연타(같은 시각 30번): 강화는 +1만", data.equipment.pickaxe[start].enh == enh0 + 1, tostring(data.equipment.pickaxe[start].enh))
	EquipmentService._reset(P)
	EquipmentService._deps = savedEq
end

local valid = Schema.validate(data)
check("끝: 프로필이 스키마 검사를 통과한다(음수 · 깨진 값 없음)", valid)

ChallengeService.abandonRun(P)
OreDropService._reset(P)
OreDropService._deps = savedOre
ProfileManager._detachTestProfile(P)

print(string.format("[DupeTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[DupeTests] %d test(s) failed", failed))
end

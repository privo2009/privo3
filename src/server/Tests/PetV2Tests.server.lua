--!strict
-- 새 경제 펫 · 새 게임패스 · 제한 지역 검증(지시서 #35).
-- PetService 런타임(가짜 deps — #37부터 코인 부화만) · PetAutoHatchService(가짜 deps) · ShopConfig 새 패스 자리 · ShopEffectsLogic.v2PassActive ·
-- 가짜 소유(GamepassService resolveTestPasses) · 제한 지역 판정 · 손 모델 R6 · 플래그 꺼짐.
-- 숫자는 Config에서 읽는다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Schema = require(ServerScriptService.Server.Data.Schema)
local PetService = require(ServerScriptService.Server.Systems.PetService)
local PetAutoHatchService = require(ServerScriptService.Server.Systems.PetAutoHatchService)
local GamepassService = require(ServerScriptService.Server.Systems.GamepassService)
local HeldPickaxeService = require(ServerScriptService.Server.Systems.HeldPickaxeService)

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

-- 가짜 세계: 프로필(Schema.new) · 블럭스 · 코인 · 시계 · 롤(언제나 첫 종)
local function newWorld()
	local data = Schema.new()
	data.lifetimeBlox = BigNum.new(1, 30) -- 알 전부 해금
	local w = { data = data, blox = BigNum.new(1, 30), coins = BigNum.new(0, 0), now = 100, saves = 0, triple = false, skip = false,
		bloxCalls = 0, coinCalls = 0 }
	local deps: any = {
		now = function()
			return w.now
		end,
		getData = function()
			return w.data
		end,
		roll = function(tiers, _luck)
			return tiers[1], 1
		end,
		save = function()
			w.saves += 1
		end,
		setAttribute = function() end,
		hasSlotPass = function()
			return false
		end,
		hasStoragePass = function()
			return false
		end,
		hasHatchPass = function()
			return w.triple
		end,
		getCoins = function()
			return w.coins
		end,
		subtractCoins = function(_p, amount, _r)
			w.coinCalls += 1
			w.coins = BigNum.sub(w.coins, amount)
			return true
		end,
		hasHatchSkipPass = function()
			return w.skip
		end,
	}
	return w, PetService._pure.createRuntime(deps)
end

local P = { Name = "PetV2Fake" } :: any
local unit = L.eggCoinCost(1) :: any

-- 1. 코인 부화: 부족 · 차감 · 지급 --------------------------------------------------------------------
do
	local w, rt = newWorld()
	w.coins = BigNum.sub(unit, BigNum.new(1, 0))
	local a, why = rt.hatch(P, 1, "test")
	check("코인 부화: 모자라면 insufficient_coins · 코인 · 펫 그대로", not a and why == PetService.REASON_INSUFFICIENT_COINS and w.coinCalls == 0
		and next(w.data.pets.owned) == nil)
	w.coins = BigNum.mul(unit, BigNum.fromNumber(10))
	local b, r = rt.hatch(P, 1, "test")
	check("코인 부화: 알 코인 가격만큼 차감 · 펫 1마리 · 블럭스는 그대로", b and r.petId == PetConfig.Eggs[1].pets[1].id
		and BigNum.eq(w.coins, BigNum.mul(unit, BigNum.fromNumber(9))) and w.bloxCalls == 0 and w.coinCalls == 1)
end

-- 2. 간격 강제: 무료 · 즉시 부화 -----------------------------------------------------------------------
do
	local w, rt = newWorld()
	w.coins = BigNum.mul(unit, BigNum.fromNumber(10))
	rt.hatch(P, 1, "test")
	w.now += Config.HATCH_SKIP_SEC - 0.1
	local b, why = rt.hatch(P, 1, "test")
	w.now += 0.1
	local c = rt.hatch(P, 1, "test")
	check("간격(무료): 스킵 시점(HATCH_SKIP_SEC) 전에는 too_soon · 지나면 된다", not b and why == PetService.REASON_TOO_SOON and c)
	w.skip = true
	w.now += Config.HATCH_MIN_INTERVAL_SEC
	local d = rt.hatch(P, 1, "test")
	check("간격(즉시 부화): 최소 간격마다 1회", d)
end

-- 3. 트리플: 코인 3배 · 3마리 -------------------------------------------------------------------------
do
	local w, rt = newWorld()
	w.coins = BigNum.mul(unit, BigNum.fromNumber(3))
	local a, why = rt.hatchMany(P, 1, 3, "test")
	check("트리플: Triple Hatch가 없으면 거부", not a and why == PetService.REASON_HATCH_PASS_REQUIRED)
	w.triple = true
	local b, list = rt.hatchMany(P, 1, 3, "test")
	check("트리플: 코인 3배 한 번에 · 3마리", b and #list == 3 and BigNum.eq(w.coins, BigNum.new(0, 0)) and w.coinCalls == 1)
end

-- 5. 자동 부화: 반복 · 멈춤 · 크게 알림 · 트리플 ---------------------------------------------------------------
local savedAuto = PetAutoHatchService._deps
local okRun, errRun = pcall(function()
	local sent = {}
	local queue = {}
	local triple = false
	local multiCalls = 0
	PetAutoHatchService._deps = {
		hatch = function()
			return table.unpack(table.remove(queue, 1))
		end,
		hatchMulti = function()
			multiCalls += 1
			return table.unpack(table.remove(queue, 1))
		end,
		ownsTriple = function()
			return triple
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
		notify = function() end,
		now = function()
			return 0
		end,
	}
	PetAutoHatchService._reset(P)
	PetAutoHatchService.setAuto(P, true, 1)
	queue = {
		{ true, { petId = "a", rarity = 1, isNew = true } },
		{ false, "too_soon" },
		{ true, { petId = "b", rarity = Config.HATCH_BIG_NOTICE_RARITY, isNew = false } },
		{ false, PetService.REASON_INSUFFICIENT_COINS },
	}
	PetAutoHatchService.tick(P)
	PetAutoHatchService.tick(P)
	PetAutoHatchService.tick(P)
	local s = PetAutoHatchService._state(P) :: any
	local lastResult
	for _, p in ipairs(sent) do
		if p.kind == "auto_hatch_result" then
			lastResult = p
		end
	end
	check("자동 부화: 간격마다 반복(간격 전은 조용히) · 좋은 등급만 크게", s.on and s.count == 2 and lastResult ~= nil and #lastResult.big == 1
		and lastResult.big[1] == "b")
	PetAutoHatchService.tick(P)
	local last = sent[#sent]
	check("자동 부화: 코인이 모자라면 멈추고 알린다", not s.on and last.kind == "auto_hatch_state" and last.on == false
		and last.reason == PetService.REASON_INSUFFICIENT_COINS)
	triple = true
	PetAutoHatchService.setAuto(P, true, 1)
	queue = { { true, { { petId = "a", rarity = 1 }, { petId = "a", rarity = 1 }, { petId = "c", rarity = 1 } } } }
	PetAutoHatchService.tick(P)
	check("자동 부화: Triple Hatch가 켜져 있으면 3마리씩", multiCalls == 1 and (PetAutoHatchService._state(P) :: any).count == 3)
	PetAutoHatchService.setAuto(P, true, "x")
	check("자동 부화: 알 번호가 이상하면 켜지 않는다", not (PetAutoHatchService._state(P) :: any).on)
	PetAutoHatchService._reset(P)
end)
PetAutoHatchService._deps = savedAuto
check("자동 부화 가짜 세계: 오류 없이 끝남", okRun, tostring(errRun))

-- 6. 새 게임패스 4개: ID nil이면 숨김 · 효과 없음 / 가짜 소유면 효과 ------------------------------------------------
do
	local nilAll, absent = true, true
	for _, key in ipairs(ShopConfig.V2_PASS_ORDER) do
		nilAll = nilAll and ShopConfig.V2_GAMEPASS_IDS[key] == nil
		absent = absent and ShopConfig.get(key) == nil and table.find(ShopConfig.GAMEPASS_ORDER, key) == nil and not ShopConfig.isRegistered(key)
	end
	check("새 패스: 커밋 ID nil(사람 등록 대기) · 상품 표 · 상점 순서에 없음", nilAll and absent)
	local v = ShopConfig.V2_PASSES
	check("새 패스: 가격 Big Bag 99 · Instant Craft 79 · Triple Craft 99 · Instant Hatch 49 · 가방 ×2",
		v.bigBag.priceRobux == 99 and v.instantCraft.priceRobux == 79 and v.tripleCraft.priceRobux == 99 and v.instantHatch.priceRobux == 49
		and v.bigBag.effect.mult == Config.BIG_BAG_MULT)
	check("새 패스: 효과 자리 = ShopConfig ID(큰 가방 · 즉시 제작 · 트리플 제작 · 즉시 부화)", Config.BIG_BAG_PASS_ID == ShopConfig.V2_GAMEPASS_IDS.bigBag
		and Config.CRAFT_SKIP_PASS_ID == ShopConfig.V2_GAMEPASS_IDS.instantCraft and Config.TRIPLE_CRAFT_PASS_ID == ShopConfig.V2_GAMEPASS_IDS.tripleCraft
		and Config.HATCH_SKIP_PASS_ID == ShopConfig.V2_GAMEPASS_IDS.instantHatch)
	-- 가짜 소유(TEST_GAMEPASSES): ID가 있는 표라면 그 키를 가진 것으로 친다 → 새 경제 · 제한 아님이면 효과
	local catalog = {
		get = function(key: string)
			return if key == "bigBag" then { key = "bigBag", kind = "gamepass", id = 999 } else nil
		end,
	}
	local set = GamepassService._pure.resolveTestPasses({ "bigBag" }, true, catalog)
	local view = { owns = function(k: string)
		return set ~= nil and set[k] == true
	end, restricted = false, boostOf = function()
		return 1
	end }
	local active = ShopEffectsLogic.v2PassActive(view :: any, "bigBag")
	local cap1 = L.bagCapacity(Config.START_PICKAXE)
	local cap2 = L.bagCapacity(Config.START_PICKAXE, if active then Config.BIG_BAG_MULT else nil)
	check("새 패스: 가짜 소유(TEST_GAMEPASSES)면 큰 가방 효과(용량 ×2)", active and cap2 == cap1 * 2)
end

-- 7. 제한 지역: 숨김 목록 · 켜고 끔 ------------------------------------------------------------------------------
do
	local listOk = true
	for _, key in ipairs({ "bigBag", "instantCraft", "tripleCraft", "instantHatch", "hatch3x" }) do
		listOk = listOk and L.isRestrictedRandom(key)
	end
	check("제한 지역: 새 패스 4개 · Triple Hatch는 숨김 목록(#37 배선 — 꺼짐 줄은 지웠다)", listOk and not L.isRestrictedRandom("damage2x")
		and not L.isRestrictedRandom("autoAdvance"))
	local function view(restricted: boolean)
		return { owns = function()
			return true
		end, restricted = restricted, boostOf = function()
			return 1
		end } :: any
	end
	check("제한 지역: 제한 유저는 Triple Hatch 효과 끔(새 경제) · 제한 아니면 켬",
		not ShopEffectsLogic.v2PassActive(view(true), "hatch3x") and ShopEffectsLogic.v2PassActive(view(false), "hatch3x"))
end

-- 8. 손 모델 R6 -----------------------------------------------------------------------------------------------
do
	local character = Instance.new("Model")
	local arm = Instance.new("Part")
	arm.Name = "Right Arm"
	arm.Parent = character
	local m = HeldPickaxeService.attach(character, Config.START_PICKAXE)
	local handle = if m ~= nil then m:FindFirstChild("Handle") else nil
	local weld = if handle ~= nil then handle:FindFirstChildOfClass("WeldConstraint") else nil
	check("손 모델: R6(RightHand 없음)이면 Right Arm에 붙인다", m ~= nil and weld ~= nil and weld.Part0 == arm)
	character:Destroy()
end

print(string.format("[PetV2Tests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PetV2Tests] %d test(s) failed", failed))
end

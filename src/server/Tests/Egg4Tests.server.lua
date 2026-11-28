--!strict
-- 알 4 검증(지시서 #49 1부 — 25층 뒤 코인 쓸 곳). 설정(25층 · 500만 · 펫 ×1.4 · 이름) · 해금(25층 전 잠김 · 뒤 열림 · 환생과 무관한 깬 층) ·
-- PetService 런타임(가짜 deps — 코인 부족 거부 · 차감 · 지급 · 즉시 · 트리플 부화) · 확률표 합 정확히 100% · 0% 없음(펫 행운 패스 켠 확률도) ·
-- 안내(25층 → egg4) · 에셋 자리. 숫자는 Config에서 읽는다. (2부 제한 지역 줍기 네 경우는 OreDropServiceTests)

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local OnboardingTipsLogic = require(ReplicatedStorage.Shared.OnboardingTipsLogic)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Schema = require(ServerScriptService.Server.Data.Schema)
local PetService = require(ServerScriptService.Server.Systems.PetService)

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

local E3, E4 = PetConfig.Eggs[3], PetConfig.Eggs[4]
local FLOOR = PetConfig.EGG_UNLOCK_FLOOR[4]

-- 1. 설정 -------------------------------------------------------------------------------------------------
do
	local multOk = E4 ~= nil and #E4.pets == PetConfig.TIER_COUNT
	if multOk then
		for tier = 1, PetConfig.TIER_COUNT do
			local want = math.floor(PetConfig.LADDER[tier] * PetConfig.EGG_RATIO ^ 3 * 10000 + 0.5) / 10000
			multOk = multOk and math.abs(E4.pets[tier].mult - want) < 1e-9 and E4.pets[tier].baseChance == E3.pets[tier].baseChance
		end
	end
	check("설정: 알 4 · 펫 4종 · 배수 = 사다리 × 1.4^3(알 3 다음 단계) · 확률 모양 = 알 3", multOk)
	local world = WorldConfig.get(1) :: any
	check("설정: 25층으로 연다(unlockFloor) · 월드 1 알 목록 · 코인 500만(TEMP) · 알 간 규칙(알 4 최저 > 알 3 최고) · validate",
		FLOOR == 25 and E4.unlockFloor == FLOOR and table.find(world.eggPacks, 4) ~= nil
			and BigNum.eq(L.eggCoinCost(4) :: any, BigNum.new(5, 6)) and E4.pets[1].mult > E3.pets[#E3.pets].mult and PetConfig.validate())
	local names = true
	for _, def in ipairs(E4.pets) do
		names = names and Locale.template("en", "pet.name." .. def.id) ~= nil and Locale.template("ko", "pet.name." .. def.id) ~= nil
	end
	check("이름: 알 4 · 펫 4종 en · ko(임시 — NameKeys 규칙)", names and Locale.template("en", "egg.name.4") ~= nil)
end

-- 2. 해금: 깬 가장 깊은 층(stats.bestRunDepth) 25부터 — 블럭스 · 환생과 무관 -----------------------------------------
do
	local big = BigNum.new(1, 300)
	local u24 = PetConfig.getUnlockedEggs(big, 1, FLOOR - 1)
	local u25 = PetConfig.getUnlockedEggs(big, 1, FLOOR)
	local zeroBlox = PetConfig.isUnlocked(4, BigNum.new(0, 0), 1, FLOOR)
	check("해금: 24층까지 잠김 · 25층을 깨면 열림 · 깬 층을 모르면 잠김 · 블럭스 0이어도 층이면 열림",
		table.find(u24, 4) == nil and table.find(u25, 4) ~= nil and not PetConfig.isUnlocked(4, big, 1, nil) and zeroBlox
			and #PetConfig.getUnlockedEggs(big, 1) == 3)
end

-- PetService 런타임(가짜 deps — PetV2Tests와 같은 꼴)
local function newWorld(depth: number)
	local data = Schema.new()
	data.lifetimeBlox = BigNum.new(1, 30)
	data.stats.bestRunDepth = depth
	local w = { data = data, coins = BigNum.new(0, 0), now = 100, triple = false, skip = false, coinCalls = 0, reasons = {} }
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
		save = function() end,
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
		subtractCoins = function(_p, amount, reason)
			w.coinCalls += 1
			table.insert(w.reasons, reason)
			w.coins = BigNum.sub(w.coins, amount)
			return true
		end,
		hasHatchSkipPass = function()
			return w.skip
		end,
	}
	return w, PetService._pure.createRuntime(deps)
end

local P = { Name = "Egg4Fake" } :: any
local unit = L.eggCoinCost(4) :: any

-- 3. 서버 부화: 잠김 · 코인 부족 거부 · 차감 · 지급 ---------------------------------------------------------------
do
	local w, rt = newWorld(FLOOR - 1)
	w.coins = BigNum.mul(unit, BigNum.fromNumber(10))
	local a, why = rt.hatch(P, 4, "test")
	check("서버: 25층 전에는 egg_locked · 코인 그대로", not a and why == PetService.REASON_EGG_LOCKED and w.coinCalls == 0)
	local w2, rt2 = newWorld(FLOOR)
	w2.coins = BigNum.sub(unit, BigNum.new(1, 0))
	local b, why2 = rt2.hatch(P, 4, "test")
	check("서버: 25층 뒤 · 코인 모자라면 insufficient_coins · 펫 그대로", not b and why2 == PetService.REASON_INSUFFICIENT_COINS and w2.coinCalls == 0
		and next(w2.data.pets.owned) == nil)
	w2.coins = BigNum.mul(unit, BigNum.fromNumber(2))
	local c, r = rt2.hatch(P, 4, "test")
	check("서버: 500만 차감 · 알 4 펫 1마리 · 사유 pet_hatch_egg4", c and r.petId == E4.pets[1].id and BigNum.eq(w2.coins, unit)
		and w2.coinCalls == 1 and string.find(w2.reasons[1], "pet_hatch_egg4", 1, true) ~= nil)
end

-- 4. 즉시 · 트리플 부화와 함께 ----------------------------------------------------------------------------------
do
	local w, rt = newWorld(FLOOR)
	w.coins = BigNum.mul(unit, BigNum.fromNumber(10))
	rt.hatch(P, 4, "test")
	w.skip = true
	w.now += Config.HATCH_MIN_INTERVAL_SEC
	local a = rt.hatch(P, 4, "test")
	w.triple = true
	w.now += Config.HATCH_MIN_INTERVAL_SEC
	local b, list = rt.hatchMany(P, 4, 3, "test")
	check("즉시 부화: 최소 간격마다 · 트리플: 3배 코인 한 번에 3마리(알 4)", a and b and #list == 3 and list[1].petId == E4.pets[1].id
		and BigNum.eq(w.coins, BigNum.mul(unit, BigNum.fromNumber(5))))
end

-- 5. 확률표(구매 전 공개): 합 정확히 100% · 0% 없음 — 지금 행운 · 펫 행운 패스(×2) 켠 행운 둘 다 -----------------------------
do
	local function shownOk(luck: number): boolean
		local texts = RollOdds.percentages(RollOdds.distribution(E4.pets, luck))
		local dec = 0
		for _, t in ipairs(texts) do
			local frac = string.match(t, "%.(%d+)%%")
			dec = math.max(dec, if frac ~= nil then #frac else 0)
		end
		local units = 0
		for _, t in ipairs(texts) do
			local n = tonumber(string.sub(t, 1, -2)) or -1
			if n <= 0 then
				return false
			end
			units += math.floor(n * 10 ^ dec + 0.5)
		end
		return #texts == PetConfig.TIER_COUNT and units == math.floor(100 * 10 ^ dec + 0.5)
	end
	local pass = ShopConfig.get("petLuck2x")
	local mult = if pass ~= nil then pass.effect.mult else 2
	check("확률표: 알 4 네 줄 합 정확히 100% · 0% 없음(행운 1 · 펫 행운 패스 ×2)", shownOk(1) and shownOk(mult))
end

-- 6. 안내 · 에셋 자리 -------------------------------------------------------------------------------------------
do
	local d = Schema.new()
	d.stats.bestRunDepth = FLOOR - 1
	local before = OnboardingTipsLogic.facts(d).egg4
	d.stats.bestRunDepth = FLOOR
	local after = OnboardingTipsLogic.facts(d).egg4
	check("안내: 25층을 처음 깨면 egg4 안내 · 그 전에는 없음", before ~= nil and not before.trigger and after.trigger and not after.past)
	local slots = AssetSlots.list()
	local found = { egg = false, pets = 0 }
	for _, slot in ipairs(slots) do
		if slot.key == "egg_4" then
			found.egg = true
		end
		for _, def in ipairs(E4.pets) do
			if slot.key == "pet_" .. def.id then
				found.pets += 1
			end
		end
	end
	check("에셋 자리: 알 4 그림 1 · 펫 모델 4(값 없으면 임시 표시)", found.egg and found.pets == 4)
end

print(string.format("[Egg4Tests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[Egg4Tests] %d test(s) failed", failed))
end

--!strict
-- 모든 Config 모듈의 validate()를 실행. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 1-3 검증: Config 골격이 자기 자신의 값 정합성을 통과하는지 확인.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local Config = ReplicatedStorage.Shared.Config
local WorldConfig = require(Config.WorldConfig)
local StageConfig = require(Config.StageConfig)
local UpgradeConfig = require(Config.UpgradeConfig)
local ShopConfig = require(Config.ShopConfig)
local ShopSlotConfig = require(Config.ShopSlotConfig)
local AuraConfig = require(Config.AuraConfig)
local TitleConfig = require(Config.TitleConfig)
local PetConfig = require(Config.PetConfig)
local AssetConfig = require(Config.AssetConfig)
local ClickPadConfig = require(Config.ClickPadConfig)
local LevelConfig = require(Config.LevelConfig)
local RebirthConfig = require(Config.RebirthConfig)
local WarpConfig = require(Config.WarpConfig)
local AttackConfig = require(Config.AttackConfig)
local ArenaConfig = require(Config.ArenaConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)

-- LevelConfig의 상한이 실제로 PadLayout에서 유도되는지 확인하려면 원본을 흔들어봐야 한다.
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)

-- BigNum.pow는 log10 경유라 마지막 자리에 부동소수점 잡음이 남는다. 기대값 비교는
-- 상대오차로 한다 (BigNum의 유효자리는 12자리이므로 1e-9면 충분히 빡빡하다).
local function approxEq(actual: BigNum.BigNumber, expected: BigNum.BigNumber): boolean
	return math.abs(BigNum.toRatio(actual, expected) - 1) < 1e-9
end

local passed = 0
local failed = 0

local function check(name: string, fn: () -> boolean)
	local ok, result = pcall(fn)
	if ok and result then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, ok and "" or (" - " .. tostring(result))))
	end
end

check("WorldConfig.validate", function()
	return WorldConfig.validate()
end)

check("StageConfig.validate", function()
	return StageConfig.validate()
end)

check("UpgradeConfig.validate", function()
	return UpgradeConfig.validate()
end)

check("ShopConfig.validate", function()
	return ShopConfig.validate()
end)

check("ShopSlotConfig.validate", function()
	return ShopSlotConfig.validate()
end)

check("ShopSlotConfig: HUD 구좌 4개 = 2배 힘 · 자동 클리커 · 2배 블럭스 · 2배 데미지 · ShopConfig 원본값 그대로(지시서 #16)", function()
	-- 값을 여기 다시 적었다면 ShopConfig를 바꿔도 이 테스트가 안 걸린다 — 원본을 다시 조회해서 대조해야 "복사됐다"를 잡는다.
	local slots = ShopSlotConfig.TEMP_SLOTS
	local keys = { "strength2x", "autoClicker", "blox2x", "damage2x" }
	for i, key in ipairs(keys) do
		local def = ShopConfig.get(key) :: any
		if slots[i].key ~= key or slots[i].priceRobux ~= def.priceRobux then
			return false
		end
	end
	return slots[1].priceRobux == 3 and slots[2].priceRobux == 49 and slots[3].priceRobux == 199 and slots[4].priceRobux == 149
end)

check("ShopConfig: 블럭스를 로벅스로 파는 상품이 없다 (P1 — 지시서 #11)", function()
	for _, def in pairs(ShopConfig.Products) do
		if def.effect.type == "blox" then
			return false
		end
	end
	return ShopConfig.get("bloxPackSmall") == nil and ShopConfig.get("bloxPackLarge") == nil
end)

check("ShopConfig.validate: 블럭스 상품이 다시 들어오면 거부", function()
	local products = ShopConfig.Products :: any
	local ids = ShopConfig.PRODUCT_IDS :: any
	products._probe = { key = "_probe", kind = "product", id = 9999, priceRobux = 99, effect = { type = "blox" }, paidRandom = false }
	ids._probe = 9999 -- ID 검사를 지나 블럭스 검사에 걸리게
	local ok = pcall(ShopConfig.validate)
	products._probe = nil
	ids._probe = nil
	return not ok and ShopConfig.validate()
end)

-- ShopConfig 상품 목록 (지시서 #16 — 2026-10-25 사람 결정) ------------------------------------------
local function count(kind: string): number
	local n = 0
	for _, def in pairs(ShopConfig.Products) do
		if def.kind == kind then
			n += 1
		end
	end
	return n
end
check("ShopConfig: 게임패스 13 + 계단 10 · 개발자 상품 8 + 운동기구 선해금 8 · ID 전부 등록(지시서 #17 — 0 없음)", function()
	for _, def in pairs(ShopConfig.Products) do
		if def.id <= 0 or not ShopConfig.isRegistered(def.key) then
			return false
		end
	end
	return count("gamepass") == 23 and count("product") == 16 and #ShopConfig.STRENGTH_TIERS == 10 and #ShopConfig.GYM_UNLOCKS == 8
		and #ShopConfig.GAMEPASS_ORDER == 13
end)
check("ShopConfig: 가격이 사람 결정 목록(2026-10-30 대시보드 가격 — 계단 32x부터 바뀜)과 같다", function()
	local expect = { autoClicker = 49, autoClickerOP = 89, rebirth2x = 99, hatch3x = 99, petLuck2x = 99, petStorage100 = 49, damage2x = 149,
		petSlots3 = 199, blox2x = 199, auraLuck10x = 299, titleLuck10x = 299, voidTrainingZone = 799, autoAdvance = 199,
		strength2x = 3, strength4x = 9, strength8x = 29, strength16x = 79, strength32x = 149, strength64x = 249, strength128x = 399,
		strength256x = 499, strength512x = 599, strength1024x = 699, luckyRoll5 = 49, luckyRoll15 = 149, superRoll5 = 99, superRoll15 = 249,
		strengthPotion = 19, damagePotion = 19, luckPotion = 29, potionBundle = 999, gymUnlock1 = 29, gymUnlock2 = 49, gymUnlock3 = 79,
		gymUnlock4 = 99, gymUnlock5 = 149, gymUnlock6 = 199, gymUnlock7 = 299, gymUnlock8 = 449 }
	local n = 0
	for key, price in pairs(expect) do
		n += 1
		local def = ShopConfig.get(key)
		if def == nil or def.priceRobux ~= price then
			error(key)
		end
	end
	return n == count("gamepass") + count("product")
end)
check("ShopConfig: 폐기 · 미룸 상품이 없다(자동 수령 · 승리 포션 · 게임패스 번들 · 워프 팩)", function()
	return ShopConfig.get("autoCollect") == nil and ShopConfig.get("victoryPotion") == nil and ShopConfig.get("bundle") == nil
		and ShopConfig.get("warpPack") == nil
end)
check("ShopConfig: 행운 상품(paidRandom) = 펫 · 아우라 · 칭호 행운 패스 · 럭키 · 슈퍼 롤 · 행운 포션 · 포션 번들", function()
	local expect = { petLuck2x = true, auraLuck10x = true, titleLuck10x = true, luckyRoll5 = true, luckyRoll15 = true, superRoll5 = true,
		superRoll15 = true, luckPotion = true, potionBundle = true }
	for key, def in pairs(ShopConfig.Products) do
		if def.paidRandom ~= (expect[key] == true) then
			error(key)
		end
	end
	return true
end)
check("ShopConfig.validate 거부: 행운 표시가 효과와 다름 · 계단 가격 순증가 아님 · 같은 ID 두 상품", function()
	local d = ShopConfig.get("luckPotion") :: any
	d.paidRandom = false
	local ok1 = pcall(ShopConfig.validate)
	d.paidRandom = true
	local t = ShopConfig.get("strength4x") :: any
	t.priceRobux = 2
	local ok2 = pcall(ShopConfig.validate)
	t.priceRobux = 9
	local a, b = ShopConfig.get("damage2x") :: any, ShopConfig.get("blox2x") :: any
	local aId, bId = a.id, b.id
	local gp = ShopConfig.GAMEPASS_IDS :: any
	a.id, b.id = 777, 777
	gp.damage2x, gp.blox2x = 777, 777
	local ok3 = pcall(ShopConfig.validate)
	a.id, b.id = aId, bId
	gp.damage2x, gp.blox2x = aId, bId
	return not ok1 and not ok2 and not ok3 and ShopConfig.validate()
end)
check("ShopConfig.validate 거부(지시서 #17): ID 0 · 게임패스 키가 상품 ID 표에 · 게임패스 ID를 개발자 상품에 · 종류 달라도 같은 ID", function()
	local gp, pr = ShopConfig.GAMEPASS_IDS :: any, ShopConfig.PRODUCT_IDS :: any
	local dmg, potion = ShopConfig.get("damage2x") :: any, ShopConfig.get("strengthPotion") :: any
	local dmgId, potionId = dmg.id, potion.id
	dmg.id, gp.damage2x = 0, 0
	local ok1 = pcall(ShopConfig.validate)
	dmg.id, gp.damage2x = dmgId, dmgId
	pr.damage2x = dmgId
	local ok2 = pcall(ShopConfig.validate)
	pr.damage2x = nil
	potion.id = dmgId -- 상품 표 값과 다르다(게임패스 ID를 옮겨 적은 실수)
	local ok3 = pcall(ShopConfig.validate)
	potion.id, pr.strengthPotion = dmgId, dmgId -- 표까지 맞춰도 게임패스와 같은 ID
	local ok4 = pcall(ShopConfig.validate)
	potion.id, pr.strengthPotion = potionId, potionId
	return not ok1 and not ok2 and not ok3 and not ok4 and ShopConfig.validate()
end)
check("ShopConfig ID 표: 게임패스 23 · 개발자 상품 16 · 각 상품 id = 그 종류 표 값", function()
	local ng, np = 0, 0
	for _ in pairs(ShopConfig.GAMEPASS_IDS) do
		ng += 1
	end
	for _ in pairs(ShopConfig.PRODUCT_IDS) do
		np += 1
	end
	for key, def in pairs(ShopConfig.Products) do
		local want = if def.kind == "gamepass" then ShopConfig.GAMEPASS_IDS[key] else ShopConfig.PRODUCT_IDS[key]
		if def.id ~= want then
			error(key)
		end
	end
	return ng == 23 and np == 16
end)
check("ShopConfig.rollCreditLuck(지시서 #17): 럭키 = 럭키 상품 luckMult · 슈퍼 = 슈퍼 상품 · 모르면 nil · 다르면 validate 거부", function()
	local lucky = (ShopConfig.get("luckyRoll5") :: any).effect
	local super = (ShopConfig.get("superRoll15") :: any).effect
	local ok1 = ShopConfig.rollCreditLuck("lucky") == lucky.luckMult and ShopConfig.rollCreditLuck("super") == super.luckMult
		and ShopConfig.rollCreditLuck("mega") == nil and ShopConfig.rollCreditLuck(5) == nil
	local e15 = (ShopConfig.get("luckyRoll15") :: any).effect
	local saved = e15.luckMult
	e15.luckMult = saved + 1
	local okBad = pcall(ShopConfig.validate)
	e15.luckMult = saved
	return ok1 and not okBad and ShopConfig.validate()
end)
check("ShopConfig.ownedHigher(지시서 #17 R1 · R2)", function()
	local function owns(set: { [string]: boolean })
		return function(k: string)
			return set[k] == true
		end
	end
	local has8 = owns({ strength8x = true })
	local hasOP = owns({ autoClickerOP = true })
	return ShopConfig.ownedHigher("strength2x", has8) == ShopConfig.REASON_LADDER_OWNED_HIGHER
		and ShopConfig.ownedHigher("strength4x", has8) == ShopConfig.REASON_LADDER_OWNED_HIGHER
		and ShopConfig.ownedHigher("strength8x", has8) == nil -- 같은 단계는 already_owned 몫
		and ShopConfig.ownedHigher("strength16x", has8) == nil
		and ShopConfig.ownedHigher("autoClicker", hasOP) == ShopConfig.REASON_AUTO_OWNED_HIGHER
		and ShopConfig.ownedHigher("autoClickerOP", owns({ autoClicker = true })) == nil
		and ShopConfig.ownedHigher("autoClicker", owns({})) == nil and ShopConfig.ownedHigher("damage2x", has8) == nil
end)
check("ShopConfig: 자동 클리커 둘 다 있으면 높은 쪽(30) · 하나면 15 · 없으면 0", function()
	local function owns(set: { [string]: boolean })
		return function(k: string)
			return set[k] == true
		end
	end
	return ShopConfig.autoClickRate(owns({ autoClicker = true, autoClickerOP = true })) == 30
		and ShopConfig.autoClickRate(owns({ autoClicker = true })) == 15 and ShopConfig.autoClickRate(owns({})) == 0
end)
check("ShopConfig: 행운 패스는 그 뽑기에만(아우라 10 · 칭호 10 · 펫 2) · 계단 상태(지금 · 다음) · findById", function()
	local function owns(k: string)
		return k == "auraLuck10x" or k == "petLuck2x" or k == "strength2x" or k == "strength8x"
	end
	local cur, nxt = ShopConfig.strengthTierState(owns)
	local none, first = ShopConfig.strengthTierState(function()
		return false
	end)
	local top, after = ShopConfig.strengthTierState(function()
		return true
	end)
	local def = ShopConfig.get("hatch3x") :: any
	local found = ShopConfig.findById("gamepass", def.id)
	local wrongKind = ShopConfig.findById("product", def.id)
	return ShopConfig.luckPassMult("aura", owns) == 10 and ShopConfig.luckPassMult("title", owns) == 1 and ShopConfig.luckPassMult("pet", owns) == 2
		and cur == "strength8x" and nxt == "strength16x" and none == nil and first == "strength2x" and top == "strength1024x" and after == nil
		and found == "hatch3x" and wrongKind == nil and ShopConfig.findById("gamepass", 0) == nil
end)

check("AuraConfig.validate", function()
	return AuraConfig.validate()
end)

-- 아우라 (지시서 #11 A1 · A2 · G4) ---------------------------------------------------------------
check("AuraConfig: m = LADDER × PACK_RATIO^(팩-1) (A2 — 팩 4 · 5도 같은 비율)", function()
	for packId, pack in pairs(AuraConfig.Packs) do
		for tier, aura in ipairs(pack.auras) do
			local expect = AuraConfig.LADDER[tier] * AuraConfig.PACK_RATIO ^ (packId - 1)
			if math.abs(aura.mult - expect) > 1e-4 then
				return false
			end
		end
	end
	return true
end)

check("AuraConfig: 아우라 하나에 m 하나 (힘 · 데미지 따로 두지 않는다 — A1)", function()
	local a = AuraConfig.Packs[1].auras[1] :: any
	return a.strengthMult == nil and a.damageMult == nil and type(a.mult) == "number"
end)

check("AuraConfig: common은 폴백(확률 없음) · 위 셋 확률 0.3 · 0.09 · 0.01 모양", function()
	local p = AuraConfig.Packs[1].auras
	return p[1].baseChance == nil and p[2].baseChance == 0.3 and p[3].baseChance == 0.09 and p[4].baseChance == 0.01
end)

check("AuraConfig: 롤 비용 1K부터 팩마다 1000배 · 해금 필드 없음 (G2 · G3)", function()
	for packId, pack in pairs(AuraConfig.Packs) do
		if not BigNum.eq(pack.rollCost, BigNum.new(1, 3 * packId)) or (pack :: any).unlockLifetimeBlox ~= nil then
			return false
		end
	end
	return true
end)

check("AuraConfig.validate: G4 위반(팩 비율이 사다리보다 작다) 거부 · 되돌리면 통과", function()
	local saved = AuraConfig.PACK_RATIO
	AuraConfig.PACK_RATIO = 1.01 -- 팩 2 최저 = 팩 1 최저 × 1.01 < 팩 1 최고(사다리가 단조 증가라 언제나 위반)
	AuraConfig.rebuild()
	local ok = pcall(AuraConfig.validate)
	AuraConfig.PACK_RATIO = saved
	AuraConfig.rebuild()
	return not ok and AuraConfig.validate()
end)

check("AuraConfig.validate: 팩 안 m이 단조가 아니면 거부", function()
	local saved = table.clone(AuraConfig.LADDER)
	AuraConfig.LADDER[3] = AuraConfig.LADDER[2]
	AuraConfig.rebuild()
	local ok = pcall(AuraConfig.validate)
	AuraConfig.LADDER = saved
	AuraConfig.rebuild()
	return not ok and AuraConfig.validate()
end)

check("AuraConfig: get · isHigher · 롤 시계 > 0", function()
	local p1, p2 = AuraConfig.Packs[1], AuraConfig.Packs[2]
	local def, packId, tier = AuraConfig.get(p2.auras[3].id)
	return def == p2.auras[3] and packId == 2 and tier == 3 and AuraConfig.get("ghost") == nil
		and AuraConfig.isHigher(p2.auras[1].id, p1.auras[4].id) and not AuraConfig.isHigher(p1.auras[1].id, p1.auras[2].id)
		and AuraConfig.isHigher(p1.auras[1].id, false) and AuraConfig.ROLL_INTERVAL_SEC > 0
end)

check("TitleConfig.validate", function()
	return TitleConfig.validate()
end)

check("PetConfig.validate", function()
	return PetConfig.validate()
end)

check("AssetConfig.validate", function()
	return AssetConfig.validate()
end)

check("ClickPadConfig.validate", function()
	return ClickPadConfig.validate()
end)

check("LevelConfig.validate", function()
	return LevelConfig.validate()
end)

check("RebirthConfig.validate", function()
	return RebirthConfig.validate()
end)

check("WarpConfig.validate", function()
	return WarpConfig.validate()
end)

check("AttackConfig.validate", function()
	return AttackConfig.validate()
end)

check("ArenaConfig.validate", function()
	return ArenaConfig.validate()
end)

-- 각 모듈이 실제로 사용 가능한 값을 돌려주는지 스모크 테스트 --------------------

check("StageConfig.getHp(1)이 BigNum을 반환", function()
	local hp = StageConfig.getHp(1)
	return type(hp) == "table" and type(hp.m) == "number" and type(hp.e) == "number"
end)

check("StageConfig.hasStage: 0층과 최종 층 다음은 없다", function()
	local finalStage = 0
	for _, world in pairs(WorldConfig.Worlds) do
		finalStage = math.max(finalStage, world.stageRange[2])
	end
	return StageConfig.hasStage(1) == true
		and StageConfig.hasStage(finalStage) == true
		and StageConfig.hasStage(finalStage + 1) == false
		and StageConfig.hasStage(0) == false
end)

check("StageConfig.isFinalStage: 최종 층만 true", function()
	local finalStage = 0
	for _, world in pairs(WorldConfig.Worlds) do
		finalStage = math.max(finalStage, world.stageRange[2])
	end
	return StageConfig.isFinalStage(finalStage) == true and StageConfig.isFinalStage(finalStage - 1) == false
end)

check("UpgradeConfig.getCostAtLevel이 레벨에 따라 증가", function()
	local cost0 = UpgradeConfig.getCostAtLevel("punchDamage", 0)
	local cost5 = UpgradeConfig.getCostAtLevel("punchDamage", 5)
	return BigNum.gt(cost5, cost0)
end)

check("ShopConfig: 힘 배수 게임패스는 최고 단계만 적용된다", function()
	-- 10개 단계를 전부 "소유"한 것으로 가정해도 누적 곱셈이 아니라 최고 배수(1024x) 하나만 나와야 한다.
	local mult = ShopConfig.strengthTierMult(function(_key: string)
		return true
	end)
	local mid = ShopConfig.strengthTierMult(function(key: string)
		return key == "strength4x" or key == "strength16x"
	end)
	return mult == 1024 and mid == 16
end)

-- TitleConfig validate가 규칙 위반을 잡는다 (지시서 #10 G5) — 표를 잠깐 바꿨다가 되돌린다 ---------------
local function titleValidateRejects(mutate: (any) -> ()): boolean
	local titles = TitleConfig.Titles :: any
	local saved = {}
	for i, def in ipairs(titles) do
		saved[i] = table.clone(def)
	end
	local savedLen = #titles
	mutate(titles)
	local ok = pcall(TitleConfig.validate)
	for i = 1, math.max(#titles, savedLen) do
		titles[i] = saved[i]
	end
	return not ok
end

check("TitleConfig.validate: 폴백에 확률이 있으면 거부", function()
	return titleValidateRejects(function(t)
		t[1].baseChance = 0.5
	end)
end)
check("TitleConfig.validate: 폴백 배수가 1이 아니면 거부", function()
	return titleValidateRejects(function(t)
		t[1].mult = 1.01
	end)
end)
check("TitleConfig.validate: 배수가 단조 증가가 아니면 거부", function()
	return titleValidateRejects(function(t)
		t[3].mult = t[2].mult
	end)
end)
check("TitleConfig.validate: 높은 등급 확률이 더 크면 거부", function()
	return titleValidateRejects(function(t)
		t[#t].baseChance = t[2].baseChance
	end)
end)
check("TitleConfig.validate: 폴백 제외 확률 합 > 1이면 거부", function()
	return titleValidateRejects(function(t)
		t[2].baseChance = 0.999
		t[3].baseChance = 0.99
	end)
end)
check("TitleConfig.validate: 되돌린 뒤 원래 표는 통과", function()
	return TitleConfig.validate()
end)
check("TitleConfig: 폴백 id로 조회 · 높은 등급 비교", function()
	local t = TitleConfig.Titles
	local def, i = TitleConfig.get(t[1].id)
	return def == t[1] and i == 1 and TitleConfig.get("ghost") == nil
		and TitleConfig.isHigher(t[2].id, t[1].id) and not TitleConfig.isHigher(t[1].id, t[2].id)
		and TitleConfig.isHigher(t[1].id, false) and not TitleConfig.isHigher("ghost", false)
end)

-- 파생 함수 (v5, 지시서 #10 S12 · S13) -------------------------------------------------------

check("PetConfig.getSlots: 기본 · 업그레이드 · 게임패스 · 상한", function()
	local base, up, pass, max = PetConfig.BaseSlots, PetConfig.UpgradeSlotBonus, PetConfig.GamepassSlotBonus, PetConfig.MaxSlots
	return PetConfig.getSlots(0, false) == base
		and PetConfig.getSlots(1, false) == math.min(base + up, max)
		and PetConfig.getSlots(0, true) == math.min(base + pass, max)
		and PetConfig.getSlots(1, true) == max
		and PetConfig.getSlots(99, true) == max
end)

check("PetConfig.getSlots: 깨진 레벨(음수 · nan · 소수 · nil)은 0 또는 내림", function()
	local base = PetConfig.BaseSlots
	return PetConfig.getSlots(-3, false) == base
		and PetConfig.getSlots(0 / 0, false) == base
		and PetConfig.getSlots(0.9, false) == base
		and PetConfig.getSlots((nil :: any), false) == base
end)

check("PetConfig.getStorage: 기본 / 게임패스", function()
	return PetConfig.getStorage(false) == PetConfig.BaseStorage
		and PetConfig.getStorage(true) == PetConfig.BaseStorage + PetConfig.GamepassStorageBonus
end)

check("AuraConfig.getUnlockedPacks: lifetimeBlox 축 — 롤 1회 비용에서 열린다", function()
	local world = WorldConfig.get(1) :: any
	local first = AuraConfig.Packs[world.auraPacks[1]]
	local second = AuraConfig.Packs[world.auraPacks[2]]
	local below = BigNum.div(first.rollCost, BigNum.fromNumber(2))
	local justBelowSecond = BigNum.div(second.rollCost, BigNum.fromNumber(2))
	return #AuraConfig.getUnlockedPacks(BigNum.new(0, 0), 1) == 0
		and #AuraConfig.getUnlockedPacks(below, 1) == 0
		and #AuraConfig.getUnlockedPacks(first.rollCost, 1) == 1
		and #AuraConfig.getUnlockedPacks(justBelowSecond, 1) == 1
		and #AuraConfig.getUnlockedPacks(second.rollCost, 1) == 2
end)

check("AuraConfig.getUnlockedPacks: 월드 축 — 그 월드에 없는 팩은 아무리 벌어도 안 열린다", function()
	local world = WorldConfig.get(1) :: any
	local got = AuraConfig.getUnlockedPacks(BigNum.new(1, 2000), 1)
	if #got ~= #world.auraPacks then
		return false
	end
	for i, packId in ipairs(world.auraPacks) do
		if got[i] ~= packId then
			return false
		end
	end
	return #AuraConfig.getUnlockedPacks(BigNum.new(1, 2000), 999) == 0
end)

check("WorldConfig: 월드 1 아우라 팩에 팩 4 · 5가 없다 (G3/S8 — 월드 2로 옮김)", function()
	local world = WorldConfig.get(1) :: any
	for _, packId in ipairs(world.auraPacks) do
		if packId == 4 or packId == 5 then
			return false
		end
	end
	return true
end)

-- 펫 (지시서 #12 E1 · E2 · E3 · E4) ---------------------------------------------------------------
check("PetConfig: m = LADDER × EGG_RATIO^(알-1) (E2) · 펫 하나에 m 하나", function()
	for eggId, egg in pairs(PetConfig.Eggs) do
		for tier, pet in ipairs(egg.pets) do
			local expect = PetConfig.LADDER[tier] * PetConfig.EGG_RATIO ^ (eggId - 1)
			if math.abs(pet.mult - expect) > 1e-4 or (pet :: any).strengthMult ~= nil then
				return false
			end
		end
	end
	return true
end)

check("PetConfig: 부화 비용 100 / 100K / 100M (E1 확정) · 일반은 폴백 · 0.3 / 0.09 / 0.01", function()
	local e = PetConfig.Eggs
	local p = e[1].pets
	return BigNum.eq(e[1].rollCost, BigNum.new(1, 2)) and BigNum.eq(e[2].rollCost, BigNum.new(1, 5)) and BigNum.eq(e[3].rollCost, BigNum.new(1, 8))
		and p[1].baseChance == nil and p[2].baseChance == 0.3 and p[3].baseChance == 0.09 and p[4].baseChance == 0.01
end)

check("PetConfig: 해금 = lifetimeBlox ≥ 부화 비용 (G8) · 월드 1 알 1~3", function()
	local e = PetConfig.Eggs
	local none = PetConfig.getUnlockedEggs(BigNum.sub(e[1].rollCost, BigNum.fromNumber(1)), 1)
	local one = PetConfig.getUnlockedEggs(e[1].rollCost, 1)
	local two = PetConfig.getUnlockedEggs(e[2].rollCost, 1)
	local all = PetConfig.getUnlockedEggs(BigNum.new(1, 300), 1)
	return #none == 0 and #one == 1 and #two == 2 and #all == 3 and PetConfig.isInWorld(3, 1) and not PetConfig.isInWorld(4, 1)
		and #PetConfig.getUnlockedEggs(BigNum.new(1, 300), 999) == 0
end)

check("PetConfig: 실효 증가분 = (m − 1) × CRAFT_FACTOR^(단계 − 1) (E3) · 깨진 값은 0", function()
	local pet = PetConfig.Eggs[2].pets[3]
	local f = PetConfig.CRAFT_FACTOR
	local ok = true
	for level = 1, PetConfig.MAX_LEVEL do
		ok = ok and math.abs(PetConfig.effectiveGain(pet.id, level) - (pet.mult - 1) * f ^ (level - 1)) < 1e-12
	end
	return ok and PetConfig.effectiveGain(pet.id, 0) == 0 and PetConfig.effectiveGain(pet.id, PetConfig.MAX_LEVEL + 1) == 0
		and PetConfig.effectiveGain(pet.id, 1.5) == 0 and PetConfig.effectiveGain("ghost", 1) == 0
end)

check("PetConfig.totalMult: 1 + Σ 실효 증가분 · 빈 목록 1 · 빈 슬롯은 0 (G9)", function()
	local a, b = PetConfig.Eggs[1].pets[2], PetConfig.Eggs[3].pets[4]
	local list = { { petId = a.id, tier = 1 }, { petId = b.id, tier = 3 } }
	local expect = 1 + PetConfig.effectiveGain(a.id, 1) + PetConfig.effectiveGain(b.id, 3)
	local holey: any = { { petId = a.id, tier = 1 } }
	holey[3] = { petId = b.id, tier = 3 } -- 가운데 nil 구멍
	return math.abs(PetConfig.totalMult(list) - expect) < 1e-12 and PetConfig.totalMult({}) == 1 and PetConfig.totalMult(nil) == 1
		and math.abs(PetConfig.totalMult(holey) - expect) < 1e-12
end)

check("PetConfig: 강화 단계 4 (이름은 Strings pet.level.* — 겹침 검사는 LocaleTests, 지시서 #L1 K6)", function()
	return PetConfig.MAX_LEVEL == 4
		and PetConfig.CRAFT_REQUIREMENT == 3 and PetConfig.isLevel(4) and not PetConfig.isLevel(5) and not PetConfig.isLevel(0)
end)

check("PetConfig.validate: 알 간 규칙 위반(비율이 사다리보다 작다) 거부 · 되돌리면 통과", function()
	local saved = PetConfig.EGG_RATIO
	PetConfig.EGG_RATIO = 1.01
	PetConfig.rebuild()
	local ok = pcall(PetConfig.validate)
	PetConfig.EGG_RATIO = saved
	PetConfig.rebuild()
	return not ok and PetConfig.validate()
end)

check("PetConfig.validate: 알 안 m 단조 · m ≥ 1 · CRAFT_FACTOR > 1 · 비용 순증가 위반 거부", function()
	local savedL = table.clone(PetConfig.LADDER)
	PetConfig.LADDER[3] = PetConfig.LADDER[2]
	PetConfig.rebuild()
	local okMono = pcall(PetConfig.validate)
	PetConfig.LADDER = { 0.9, 1.1, 1.2, 1.4 }
	PetConfig.rebuild()
	local okLow = pcall(PetConfig.validate)
	PetConfig.LADDER = savedL
	PetConfig.rebuild()
	local savedF = PetConfig.CRAFT_FACTOR
	PetConfig.CRAFT_FACTOR = 1
	local okF = pcall(PetConfig.validate)
	PetConfig.CRAFT_FACTOR = savedF
	local savedE = table.clone(PetConfig.EGG_COST_EXPONENTS)
	PetConfig.EGG_COST_EXPONENTS[3] = PetConfig.EGG_COST_EXPONENTS[2]
	PetConfig.rebuild()
	local okC = pcall(PetConfig.validate)
	PetConfig.EGG_COST_EXPONENTS = savedE
	PetConfig.rebuild()
	return not okMono and not okLow and not okF and not okC and PetConfig.validate()
end)

check("PetConfig: 장착 Attribute 직렬화 왕복 · 깨진 조각은 건너뛴다", function()
	local a, b = PetConfig.Eggs[1].pets[1], PetConfig.Eggs[2].pets[4]
	local s = PetConfig.serializeEquipped({ { petId = a.id, tier = 1 }, { petId = b.id, tier = 4 } })
	local back = PetConfig.parseEquipped(s)
	local junk = PetConfig.parseEquipped(s .. ",ghost:1," .. a.id .. ":9,,garbage")
	return s == a.id .. ":1," .. b.id .. ":4" and #back == 2 and back[2].petId == b.id and back[2].tier == 4
		and #junk == 2 and #PetConfig.parseEquipped("") == 0 and #PetConfig.parseEquipped(nil) == 0
end)

check("AssetConfig: btn_yellow의 9-slice 여백이 사방 24px로 균일", function()
	-- 균일하지 않으면 9-slice 전제가 깨지고, 최소 크기 제약(높이 48 = 상하 마진 합)의 근거도 무너진다.
	-- (G1 실측 근거는 `docs/UI_HANDOFF.md` "G1 — 버튼 9-slice > 최소 크기 제약")
	local button = AssetConfig.Buttons.yellow
	local left = button.slice.Min.X
	local top = button.slice.Min.Y
	local right = button.size.X - button.slice.Max.X
	local bottom = button.size.Y - button.slice.Max.Y
	return left == 24 and top == 24 and right == 24 and bottom == 24
end)


check("ClickPadConfig: 월드1 패드24 파워 = basePower × powerGrowth^23", function()
	-- 절대값을 하드코딩하지 않는다 — basePower는 4-2-f 튜닝 대상이라 움직인다.
	-- Config에서 직접 뽑아 기대값을 만든다 (ClickServiceTests의 같은 패턴).
	local set = ClickPadConfig.getSet(1)
	local expected = BigNum.mul(set.basePower, BigNum.pow(BigNum.fromNumber(set.powerGrowth), 23))
	return approxEq(ClickPadConfig.getPadPower(1, 24), expected)
end)

check("ClickPadConfig: 월드1 패드2~5 해금 조건 = bloxBase × 10 · 30 · 100 · 300 (1·3 사다리)", function()
	local base = (WorldConfig.get(1) :: any).bloxBase
	local expected = { [2] = 10, [3] = 30, [4] = 100, [5] = 300 }
	for index, n in pairs(expected) do
		if not BigNum.eq(ClickPadConfig.getPadUnlock(1, index), BigNum.mul(base, BigNum.fromNumber(n))) then
			return false
		end
	end
	return true
end)

check("ClickPadConfig: 월드1 패드24 해금 조건 = bloxBase × 1T (사다리 22칸)", function()
	local base = (WorldConfig.get(1) :: any).bloxBase
	return BigNum.eq(ClickPadConfig.getPadUnlock(1, 24), BigNum.mul(base, BigNum.new(1, 12)))
end)

check("ClickPadConfig: 모든 패드 조건의 가수가 1 또는 3 (bloxBase가 1일 때 깔끔한 단위)", function()
	local base = (WorldConfig.get(1) :: any).bloxBase
	if not BigNum.eq(base, BigNum.new(1, 0)) then
		return true -- bloxBase가 1이 아니면 이 성질을 약속하지 않는다(WorldConfig 주석)
	end
	for index = 2, ClickPadConfig.getSet(1).count do
		local m = ClickPadConfig.getPadUnlock(1, index).m
		if m ~= 1 and m ~= 3 then
			return false
		end
	end
	return true
end)

check("ClickPadConfig: 패드1은 조건이 0이라 항상 열려 있다", function()
	local zero = BigNum.new(0, 0)
	return BigNum.eq(ClickPadConfig.getPadUnlock(1, 1), zero)
		and ClickPadConfig.isUnlocked(1, 1, zero) == true
end)

check("ClickPadConfig: lifetimeBlox 0이면 해금 개수 1", function()
	-- 패드2 조건은 bloxBase × unlockStart(> 0)이므로 0으로는 절대 열리지 않는다.
	return ClickPadConfig.getUnlockedPadCount(1, BigNum.new(0, 0)) == 1
		and ClickPadConfig.isUnlocked(1, 2, BigNum.new(0, 0)) == false
end)

check("ClickPadConfig: 해금 개수는 조건을 만족하는 최고 인덱스까지 늘어난다", function()
	-- 패드3 조건에 딱 맞춘 값이면 3개, 거기서 조금 모자라면 2개여야 한다.
	local pad3 = ClickPadConfig.getPadUnlock(1, 3)
	local justUnder = BigNum.mul(pad3, BigNum.new(9.9, -1)) -- 조건의 99%
	return ClickPadConfig.getUnlockedPadCount(1, pad3) == 3
		and ClickPadConfig.getUnlockedPadCount(1, justUnder) == 2
end)

-- ===== LevelConfig ===================================================================

check("LevelConfig: 레벨 0이면 속도가 BASE_WALK_SPEED", function()
	-- 힘 0({m=0,e=0})과 힘 1({m=1,e=0}) 둘 다 2 미만이라 레벨 0이다(L1).
	local zero = BigNum.new(0, 0)
	local one = BigNum.new(1, 0)
	return LevelConfig.getLevel(zero) == 0
		and LevelConfig.getLevel(one) == 0
		and LevelConfig.getMaxSpeed(zero) == LevelConfig.BASE_WALK_SPEED
		and LevelConfig.getMaxSpeed(one) == LevelConfig.BASE_WALK_SPEED
end)

check("LevelConfig: 힘이 0 이하면 레벨 0 (음수 지수로 새지 않는다)", function()
	-- 0 < 힘 < 1이면 e가 음수로 들어온다. 접지 않으면 속도가 기본값 아래로 내려간다.
	local half = BigNum.new(5, -1) -- 0.5
	local negative = BigNum.new(-3, 5) -- -3e5
	return LevelConfig.getLevel(half) == 0
		and LevelConfig.getLevel(negative) == 0
		and LevelConfig.getMaxSpeed(half) == LevelConfig.BASE_WALK_SPEED
end)

-- ----- L1 레벨 = floor(log₂(힘)) (2026-10-24 사람 결정 — 지시서 #13) -----

check("L1: 1 · 2 · 3 · 4 → 레벨 0 · 1 · 1 · 2 (힘 < 2이면 0)", function()
	return LevelConfig.getLevel(BigNum.new(1, 0)) == 0
		and LevelConfig.getLevel(BigNum.new(2, 0)) == 1
		and LevelConfig.getLevel(BigNum.new(3, 0)) == 1
		and LevelConfig.getLevel(BigNum.new(4, 0)) == 2
		and LevelConfig.getLevel(BigNum.new(1.999999, 0)) == 0
end)

check("L1: 예시 1K → 9 · 4M → 21 · 1B → 29 · 4×10^16 → 55 (DESIGN \"레벨\")", function()
	return LevelConfig.getLevel(BigNum.new(1, 3)) == 9
		and LevelConfig.getLevel(BigNum.new(4, 6)) == 21
		and LevelConfig.getLevel(BigNum.new(1, 9)) == 29
		and LevelConfig.getLevel(BigNum.new(4, 16)) == 55
end)

-- 2^k 경계: 정확히 2^k(BigNum.pow로 만든 값)이면 k, 가수를 1 ulp 내리면 k − 1, 올리면 k.
-- 정규화를 거치면 1 ulp가 12자리 반올림에 지워지므로 {m, e}를 직접 만든다(getLevel은 형태만 본다).
local function ulpOf(m: number): number
	return 2 ^ (math.floor(math.log(m, 2)) - 52)
end
check("L1: 2^k 정확히 → k · 가수 1 ulp 아래 → k − 1 · 위 → k (k = 1~64 · 100 · 1000 · 6000)", function()
	local ks = {}
	for k = 1, 64 do
		table.insert(ks, k)
	end
	table.insert(ks, 100)
	table.insert(ks, 1000)
	table.insert(ks, 6000)
	for _, k in ipairs(ks) do
		local p = LevelConfig.powerOfLevel(k)
		local below = { m = p.m - ulpOf(p.m), e = p.e }
		local above = { m = p.m + ulpOf(p.m), e = p.e }
		if LevelConfig.getLevel(p) ~= k or LevelConfig.getLevel(below) ~= k - 1 or LevelConfig.getLevel(above) ~= k then
			error(string.format("k=%d: 정확히 %d · 아래 %d · 위 %d", k, LevelConfig.getLevel(p), LevelConfig.getLevel(below), LevelConfig.getLevel(above)))
		end
	end
	return true
end)

-- 2^k − 1은 12자리 안(k ≤ 39)에서만 BigNum이 정확히 담는다 — 13자리부터는 반올림이 2^k로 되돌린다(BigNum 유효자리 12).
check("L1: 정수 2^k를 fromNumber로 만들어도 k (k = 1~52) · 2^k − 1은 k − 1 (k = 1~39 — 게임 값이 숫자에서 올 때)", function()
	for k = 1, 52 do
		if LevelConfig.getLevel(BigNum.fromNumber(2 ^ k)) ~= k then
			error("2^" .. k)
		end
		if k <= 39 and LevelConfig.getLevel(BigNum.fromNumber(2 ^ k - 1)) ~= k - 1 then
			error("2^" .. k .. " - 1")
		end
	end
	return true
end)

check("L1: 10^2000대에서도 정밀도가 깨지지 않는다 (10^2000 → 6643 · 경계에서 먼 값은 로그식과 같다)", function()
	if LevelConfig.getLevel(BigNum.new(1, 2000)) ~= 6643 then
		error("10^2000 → " .. LevelConfig.getLevel(BigNum.new(1, 2000)))
	end
	-- 경계에서 0.1칸 이상 떨어진 값만 대조한다(경계 바로 옆은 위의 ulp 테스트가 맡는다)
	local rng = Random.new(13)
	for _ = 1, 400 do
		local p = BigNum.new(rng:NextNumber(1, 9.99), rng:NextInteger(0, 2500))
		local lg = (math.log10(p.m) + p.e) / math.log10(2)
		local frac = lg - math.floor(lg)
		if frac > 0.1 and frac < 0.9 and LevelConfig.getLevel(p) ~= math.floor(lg) then
			error(string.format("%s: %d vs %d", BigNum.tostring(p), LevelConfig.getLevel(p), math.floor(lg)))
		end
	end
	return true
end)

check("L1: 레벨 바 진행률 = (힘 − 2^L) ÷ 2^L — 2^k에서 0 · 1.5×2^k에서 0.5 · 2^(k+1) 바로 아래는 1 미만", function()
	for _, k in ipairs({ 0, 1, 5, 21, 48, 55, 300, 6000 }) do
		local p = LevelConfig.powerOfLevel(k)
		local nextBelow = LevelConfig.powerOfLevel(k + 1)
		nextBelow = { m = nextBelow.m - ulpOf(nextBelow.m), e = nextBelow.e }
		local atK = LevelConfig.getLevelProgress(p)
		local mid = LevelConfig.getLevelProgress(BigNum.mul(p, BigNum.new(1.5, 0)))
		local top = LevelConfig.getLevelProgress(nextBelow)
		if math.abs(atK) > 1e-9 or math.abs(mid - 0.5) > 1e-9 or not (top >= 0.999 and top < 1) then
			error(string.format("k=%d: %.12f / %.12f / %.12f", k, atK, mid, top))
		end
	end
	return true
end)

check("L1: 레벨 바 진행률은 언제나 0 이상 1 미만 (0 · 0.5 · 음수 · 무작위 3000개)", function()
	if LevelConfig.getLevelProgress(BigNum.new(0, 0)) ~= 0 or LevelConfig.getLevelProgress(BigNum.new(5, -1)) ~= 0
		or LevelConfig.getLevelProgress(BigNum.new(-3, 5)) ~= 0 or math.abs(LevelConfig.getLevelProgress(BigNum.new(1.5, 0)) - 0.5) > 1e-9 then
		return false
	end
	local rng = Random.new(1013)
	for _ = 1, 3000 do
		local p = BigNum.new(rng:NextNumber(1, 9.999999), rng:NextInteger(0, 2100))
		local v = LevelConfig.getLevelProgress(p)
		if not (v >= 0 and v < 1) then
			error(BigNum.tostring(p) .. " → " .. tostring(v))
		end
	end
	return true
end)

check("L2: 상한 아래에서는 최대 속도 = 기본 + 레벨 (레벨 0~47)", function()
	local base = LevelConfig.BASE_WALK_SPEED
	for level = 0, LevelConfig.getSpeedCapLevel() - 1 do
		if LevelConfig.getMaxSpeed(LevelConfig.powerOfLevel(level)) ~= base + level then
			error("level " .. level)
		end
	end
	return true
end)

check("L2: 상한 닿는 레벨 = MAX_WALK_SPEED − 기본(지금 48 · 힘 약 2.8×10^14) · 그 전 레벨은 상한 − 1", function()
	local capLevel = LevelConfig.getSpeedCapLevel()
	local cap = LevelConfig.getMaxWalkSpeed()
	return capLevel == cap - LevelConfig.BASE_WALK_SPEED
		and LevelConfig.getMaxSpeed(LevelConfig.powerOfLevel(capLevel)) == cap
		and LevelConfig.getMaxSpeed(LevelConfig.powerOfLevel(capLevel - 1)) == cap - 1
		and math.abs(BigNum.toRatio(LevelConfig.powerOfLevel(48), BigNum.new(2.81474976710656, 14)) - 1) < 1e-9
end)

check("LevelConfig: 상한을 넘으면 지수를 올려도 속도가 멈춘다", function()
	local cap = LevelConfig.getMaxWalkSpeed()
	-- 상한에 확실히 걸리는 지수 두 개. 값이 서로 같고 상한과 같아야 한다.
	local a = LevelConfig.getMaxSpeed(BigNum.new(1, 500))
	local b = LevelConfig.getMaxSpeed(BigNum.new(1, 900))
	return a == cap and b == cap
end)

check("LevelConfig: 10^2000이면 레벨 6643(L1), 속도는 상한", function()
	-- 레벨 자체에는 상한이 없다. 멈추는 것은 속도뿐이다 (DESIGN.md "레벨").
	local huge = BigNum.new(1, 2000)
	return LevelConfig.getLevel(huge) == 6643 and LevelConfig.getMaxSpeed(huge) == LevelConfig.getMaxWalkSpeed()
end)

check("L2: 환생 직후 힘(Schema 초기값 — RebirthService가 쓰는 값)이면 레벨 0 · 속도 기본", function()
	local Schema = require(script.Parent.Parent.Data.Schema)
	local fresh = Schema.new().strength
	return LevelConfig.getLevel(fresh) == 0 and LevelConfig.getMaxSpeed(fresh) == LevelConfig.BASE_WALK_SPEED
		and LevelConfig.getLevelProgress(fresh) == 0
end)

check("LevelConfig: 발판 깊이가 절반이면 상한도 절반 (유도가 실제로 돈다)", function()
	-- 상수를 박았는지 유도하는지를 가르는 테스트다. PAD_SIZE를 흔들어 상한이 따라오는지 본다.
	--
	-- ⚠️ ConfigTests에서 원본 모듈을 건드리는 유일한 케이스다. 중간에 error가 나도 복구가
	-- 반드시 돌아야 뒤따르는 케이스들이 오염된 PAD_SIZE로 돌지 않는다. 그래서 흔든 뒤의
	-- 본문을 pcall로 감싸고 복구를 그 바깥에 둔다.
	-- 다만 pcall이 실패를 삼키면 안 된다 — 복구를 마친 뒤 원래 error를 그대로 다시 던져서
	-- check()의 pcall이 메시지째 받아 [FAIL]에 찍게 한다.
	--
	-- ⚠️ 줄이는 변은 **축 방향 변**이어야 한다. 예전에는 `.Z`로 박혀 있었고 그때는
	-- PadLayout.AXIS가 (0,0,-1)이라 우연히 맞았다. 4-2-a에서 축이 +X로 바뀌면서
	-- `.Z`는 깊이 계산에 쓰이지 않는 변이 됐다 — 그대로 뒀다면 상한이 안 변하는 것이
	-- 정상인데 테스트는 절반을 기대하므로 [FAIL]이 뜬다. 반대로 축이 또 바뀌었을 때
	-- 조용히 통과해버리는 쪽이 더 나쁘다: 유도가 도는지 재는 테스트가 아무것도
	-- 못 재게 된다. LevelConfig.depthAlong이 축 투영을 쓰는 것과 같은 이유다.
	local original = PadLayout.PAD_SIZE
	local axis = PadLayout.AXIS
	local full = LevelConfig.getMaxWalkSpeed()

	local function halveIfOnAxis(component: number, axisComponent: number): number
		return if math.abs(axisComponent) > 0 then component / 2 else component
	end

	PadLayout.PAD_SIZE = Vector3.new(
		halveIfOnAxis(original.X, axis.X),
		halveIfOnAxis(original.Y, axis.Y),
		halveIfOnAxis(original.Z, axis.Z)
	)
	local ok, result = pcall(function()
		return LevelConfig.getMaxWalkSpeed()
	end)
	PadLayout.PAD_SIZE = original -- 성공·실패와 무관하게 반드시 복구된다

	if not ok then
		error(result, 0) -- level 0: 안쪽 error의 위치 정보를 덧씌우지 않는다
	end

	return math.abs((result :: number) - full / 2) < 1e-9 and LevelConfig.getMaxWalkSpeed() == full
end)

check("LevelConfig: 상한이 공식과 일치한다", function()
	-- getMaxWalkSpeed가 소스를 읽어 deriveMaxWalkSpeed를 태우는지 (둘이 따로 놀지 않는지).
	local depth = LevelConfig.getMinPartDepth()
	local expected = depth * LevelConfig.REFERENCE_FPS / LevelConfig.MIN_FRAMES_ON_PART
	return LevelConfig.getMaxWalkSpeed() == expected and LevelConfig.deriveMaxWalkSpeed(depth) == expected
end)

-- ===== ArenaConfig ===================================================================
--
-- 아레나 좌표는 파트 75개(스테이지 25 × 블록·발판·벽)의 자리를 정한다. 주기가 파생이
-- 아니라 상수로 박히면 폭을 조정했을 때 그 전부가 어긋나고, 증상은 "걸어가다 벽에
-- 막힌다" 같은 모양으로만 나타난다. 아래는 파생이 실제로 도는지를 재는 절이다.

check("ArenaConfig: 확정 구조의 좌표가 그대로 나온다", function()
	-- 확정값을 여기 박는 것이 맞다. 이 절은 "구조가 바뀌지 않았는가"를 재는 자리이고,
	-- 파생식으로 다시 쓰면 식이 틀려도 자기 자신과 일치해서 통과한다.
	-- 2026-10-23 지시서 #8(맵 템포): 폭 148 · 띠 24 · 스폰 -200 (이전 160 · 40 · -400).
	return ArenaConfig.getStagePitch() == 172
		and ArenaConfig.getStageCenterX(1) == 0
		and ArenaConfig.getStageCenterX(2) == 172
		and ArenaConfig.getCashoutX(1) == 86
		and ArenaConfig.getAdvanceX(1) == 98
		and ArenaConfig.getEntranceX() == -74
		and ArenaConfig.SPAWN_X == -200
		and ArenaConfig.getSpawnToEntrance() == 126
end)

check("ArenaConfig: 스테이지 폭을 흔들면 주기·발판·벽이 전부 따라온다 (유도가 실제로 돈다)", function()
	-- 상수를 박았는지 유도하는지를 가르는 테스트다. LevelConfig의 PAD_SIZE 흔들기와
	-- 같은 형태이고, 복구를 pcall 바깥에 두는 이유도 같다 — 중간에 error가 나도
	-- 뒤따르는 케이스들이 오염된 STAGE_WIDTH로 돌면 안 된다.
	local original = ArenaConfig.STAGE_WIDTH

	ArenaConfig.STAGE_WIDTH = original * 2
	local ok, result = pcall(function()
		return {
			pitch = ArenaConfig.getStagePitch(),
			center2 = ArenaConfig.getStageCenterX(2),
			cashout = ArenaConfig.getCashoutX(1),
			advance = ArenaConfig.getAdvanceX(1),
			entrance = ArenaConfig.getEntranceX(),
			entrance2 = ArenaConfig.getStageEntranceX(2),
		}
	end)
	ArenaConfig.STAGE_WIDTH = original -- 성공·실패와 무관하게 반드시 복구된다

	if not ok then
		error(result, 0) -- level 0: 안쪽 error의 위치 정보를 덧씌우지 않는다
	end

	local r = result :: any
	-- 폭 148 → 296이면 주기 172 → 320, 발판 86 → 160, 벽 98 → 172, 입구 -74 → -148.
	-- 2층 입구는 320 - 148 = 172 — 벽과 같은 자리다(벽을 통과하면 다음 층 시작 면).
	return r.pitch == 320
		and r.center2 == 320
		and r.cashout == 160
		and r.advance == 172
		and r.entrance == -148
		and r.entrance2 == 172
		and ArenaConfig.getStagePitch() == 172 -- 복구 확인
end)

check("ArenaConfig: 스테이지 N의 입구 X가 중심을 따라 움직인다", function()
	-- 검증 스크립트(Bootstrap moveToStageEntrance)가 캐릭터를 세우는 자리다.
	-- 층마다 "중심 - 폭/2"여야 하고, 그 상대 위치가 같아야 dist가 층과 무관하게 80으로
	-- 재현된다. 어긋나면 스테이지 2에서만 out_of_range가 뜨고 원인이 안 보인다.
	local stageEdge = ArenaConfig.STAGE_WIDTH / 2

	-- 확정값. 주기 172, 폭 148이면 1층 -74, 2층 98, 3층 270이다.
	local fixedOk = ArenaConfig.getStageEntranceX(1) == -74
		and ArenaConfig.getStageEntranceX(2) == 98
		and ArenaConfig.getStageEntranceX(3) == 270

	-- 상대 위치가 층과 무관하게 같은가. 이것이 dist 재현의 근거다.
	local relativeOk = true
	for stage = 1, 5 do
		local offset = ArenaConfig.getStageCenterX(stage) - ArenaConfig.getStageEntranceX(stage)
		if offset ~= stageEdge then
			relativeOk = false
		end
	end

	-- getEntranceX가 별칭인가. 식이 두 벌이 되면 여기서 갈린다.
	local aliasOk = ArenaConfig.getEntranceX() == ArenaConfig.getStageEntranceX(1)

	-- 진행 벽을 통과하면 곧바로 다음 층 시작 면이다.
	local wallOk = ArenaConfig.getAdvanceX(1) == ArenaConfig.getStageEntranceX(2)
		and ArenaConfig.getAdvanceX(4) == ArenaConfig.getStageEntranceX(5)

	return fixedOk and relativeOk and aliasOk and wallOk
end)

check("ArenaConfig: 패드 24장이 스폰 구역 안 · 챌린지 입구 앞에 들어간다", function()
	-- 두 파일이 같은 축·같은 스폰 지점을 쓰는지 실제 좌표로 확인한다. 패드가 입구를
	-- 넘어가면 챌린지 구간에 패드가 서고, 4-2-a에서 없애기로 한 구조가 되살아난다.
	local count = ClickPadConfig.getSet(1).count
	local positions = PadLayout.computeLayout(count)
	local first = positions[1].X
	local last = positions[count].X

	-- 지시서 #8 M1: 패드는 통로 옆 2줄이고 스폰 바로 뒤(-220)에서 시작해 게이트 앞(-88)에서 끝난다.
	return first < ArenaConfig.SPAWN_X
		and first > ArenaConfig.SPAWN_ZONE_X_MIN
		and last < ArenaConfig.getEntranceX()
		and first == -220
		and last == -88
end)

check("LevelConfig: 수령 발판이 깊이 소스에 등록돼 있다", function()
	-- 등록이 빠지면 발판 깊이를 8 아래로 내려도 이동속도 상한이 안 따라 내려간다.
	-- 증상은 "빠르게 지나가면 발판이 가끔 안 밟힌다" 하나뿐이라 원인이 안 보인다.
	local found = false
	for _, source in ipairs(LevelConfig.DEPTH_SOURCES) do
		if source.name == "cashoutPad" then
			found = true
		end
	end
	return found
end)

check("LevelConfig: 발판 깊이가 최소 깊이(8) 이상이라 상한이 안 내려간다", function()
	-- 발판을 추가한 것이 기존 상한을 깎지 않았는지. 깎였다면 패드보다 얕게 만든 것이다.
	local depth = ArenaConfig.CASHOUT_PAD_SIZE.X -- 진행축이 X다
	return depth >= 8 and LevelConfig.getMinPartDepth() <= depth
end)

check("ArenaConfig: PadLayout.AXIS는 재공개일 뿐 두 번째 원본이 아니다", function()
	-- 양쪽에 따로 적으면 축을 틀었을 때 패드만 남거나 스테이지만 남는다.
	return PadLayout.AXIS == ArenaConfig.AXIS
end)

check("StageConfig: BLOCK_COUNT_STEPS는 월드 안에서 감소하지 않는다", function()
	-- validate()가 표를 직접 보지만, 여기서는 실제 getBlockCount 결과로도 확인한다.
	-- 개수가 줄면 총HP 증가율이 블록당 증가율보다 작아져 곡선 규약 1이 총HP 축에서 깨진다.
	for _, world in pairs(WorldConfig.Worlds) do
		local prev = StageConfig.getBlockCount(world.stageRange[1])
		for stage = world.stageRange[1] + 1, world.stageRange[2] do
			local count = StageConfig.getBlockCount(stage)
			if count < prev then
				return false
			end
			prev = count
		end
	end
	return true
end)

-- ===== RebirthConfig =================================================================
--
-- 환생 규칙은 DESIGN.md "3. 화폐와 배수 > 환생"이 원본이다: floor(블럭스 ÷ 1000).
-- ⚠️ 아래 어디에도 1000을 적지 않는다. 전부 BLOX_PER_REBIRTH에서 유도한다 —
-- 상수를 바꿨을 때 테스트가 옛 값을 붙잡고 통과하면 그게 제일 나쁜 경우다.

local COST = RebirthConfig.BLOX_PER_REBIRTH

-- n번째 환생분에 해당하는 블럭스. (배수 n을 얻는 최소 금액)
local function bloxFor(multiplier: number, offset: number): BigNum.BigNumber
	return BigNum.fromNumber(COST * multiplier + offset)
end

local function gained(blox: BigNum.BigNumber): BigNum.BigNumber
	return RebirthConfig.getGainedRebirths(blox)
end

local function isInt(value: BigNum.BigNumber, expected: number): boolean
	return BigNum.eq(value, BigNum.fromNumber(expected))
end

-- 경계 -----------------------------------------------------------------------------

check("RebirthConfig: 비용보다 1 적으면 배수 0", function()
	return isInt(gained(bloxFor(1, -1)), 0)
end)

check("RebirthConfig: 비용 정확히면 배수 1", function()
	return isInt(gained(bloxFor(1, 0)), 1)
end)

check("RebirthConfig: 비용보다 1 많으면 여전히 배수 1", function()
	return isInt(gained(bloxFor(1, 1)), 1)
end)

check("RebirthConfig: 비용 2배보다 1 적으면 배수 1", function()
	return isInt(gained(bloxFor(2, -1)), 1)
end)

check("RebirthConfig: 비용 2배면 배수 2", function()
	return isInt(gained(bloxFor(2, 0)), 2)
end)

check("RebirthConfig: 0이면 배수 0", function()
	return isInt(gained(BigNum.new(0, 0)), 0)
end)

-- 거부 -----------------------------------------------------------------------------

check("RebirthConfig: 0에서는 환생 불가", function()
	return RebirthConfig.canRebirth(BigNum.new(0, 0)) == false
end)

check("RebirthConfig: 비용보다 1 적으면 환생 불가", function()
	return RebirthConfig.canRebirth(bloxFor(1, -1)) == false
end)

check("RebirthConfig: 비용 정확히면 환생 가능", function()
	return RebirthConfig.canRebirth(bloxFor(1, 0)) == true
end)

-- 버림 -----------------------------------------------------------------------------
--
-- ⚠️ 이 절이 실제로 관측되는 것은 몫의 지수가 작을 때뿐이다. 근거는 RebirthConfig
-- 상단 "floor의 BigNum 성질" — 후반에 버림이 안 먹는 것은 정상이다.

check("RebirthConfig: 나머지는 버린다 (2배 직전 → 1)", function()
	return isInt(gained(bloxFor(2, -1)), 1)
end)

check("RebirthConfig: 나머지는 버린다 (3배 직전 → 2)", function()
	return isInt(gained(bloxFor(3, -1)), 2)
end)

check("RebirthConfig: 나머지는 버린다 (비용의 9.99배 → 9)", function()
	return isInt(gained(BigNum.fromNumber(COST * 10 - 1)), 9)
end)

check("RebirthConfig: 반올림이 아니라 버림이다", function()
	-- 반올림이면 비용의 1.9배가 2가 된다. 1이어야 한다.
	return isInt(gained(BigNum.fromNumber(math.floor(COST * 1.9))), 1)
end)

-- 대수 구간 -------------------------------------------------------------------------

check("RebirthConfig: 임계 지수 이상이면 floor가 입력을 그대로 돌려준다", function()
	local threshold = RebirthConfig._pure.INTEGER_EXPONENT
	-- 소수부가 있어 보이는 가수를 일부러 넣는다. 그 지수에서는 이미 정수다.
	local big = BigNum.new(1.23456789012, threshold)
	local floored = RebirthConfig._pure.floorBig(big)
	return floored.m == big.m and floored.e == big.e
end)

check("RebirthConfig: 임계 지수를 훨씬 넘는 값도 그대로 통과", function()
	local big = BigNum.new(4.44444444444, 300)
	local floored = RebirthConfig._pure.floorBig(big)
	return floored.m == big.m and floored.e == big.e
end)

check("RebirthConfig: 대수 구간에서도 getGainedRebirths가 유한한 값을 준다", function()
	local huge = BigNum.new(5, 2000)
	local result = gained(huge)
	-- 몫은 지수가 3 작아진다. inf/nan이 되면 프로필이 영구 손상된다 (절대 규칙 1).
	return result.m == result.m and result.e == result.e and result.e > 1990
end)

check("RebirthConfig: 임계 지수가 BigNum 실측 유효자리와 일치한다", function()
	-- ⚠️ 이 케이스를 지우지 말 것. INTEGER_EXPONENT는 BigNum의 SIGNIFICANT_DIGITS에서
	-- 유도된 값인데 그 상수가 export되지 않아 직접 읽을 수 없다. 그래서 실측한다:
	-- 1 + 10^-k가 1과 구분되는 가장 큰 k가 곧 (유효자리 - 1)이고, 그 값이 임계 지수다.
	-- BigNum 쪽 상수가 바뀌면 여기서 갈라진다 — 갈라진 채 두면 그 사이 지수 구간에서
	-- 버림이 조용히 건너뛰어진다.
	--
	-- ⚠️ 값 생성과 비교를 **반드시 BigNum 연산으로** 한다. raw Lua로 `1 + 10^-k`를 만들거나
	--    `==`로 비교하면 재는 대상이 BigNum의 유효자리가 아니라 double의 정밀도(k≈15~16)가
	--    되어 11과 안 맞는다. 그때 테스트는 조용히 통과하는 게 아니라 실패하지만,
	--    원인이 이 줄에 있다는 걸 알아채는 데 시간이 든다.
	local one = BigNum.new(1, 0)
	local measured = 0
	for k = 1, 20 do
		if BigNum.eq(BigNum.add(one, BigNum.new(1, -k)), one) then
			break
		end
		measured = k
	end
	return measured == RebirthConfig._pure.INTEGER_EXPONENT
end)

check("RebirthConfig: floorBig은 음수를 거부한다", function()
	-- 조용히 0으로 접으면 상위 경로의 버그가 증상만 남기고 사라진다.
	local ok = pcall(function()
		RebirthConfig._pure.floorBig(BigNum.new(-2, 0))
	end)
	return ok == false
end)

-- ===== StrengthMultiplier ============================================================

check("StrengthMultiplier: rebirths 0이면 배수 1", function()
	return isInt(StrengthMultiplier.compute({ rebirths = BigNum.new(0, 0) }), 1)
end)

check("StrengthMultiplier: rebirths 5면 배수 6", function()
	return isInt(StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(5) }), 6)
end)

check("StrengthMultiplier: 대수 배수도 1을 더한다", function()
	local result = StrengthMultiplier.compute({ rebirths = BigNum.new(1, 30) })
	-- 1e30에 1을 더해도 유효자리 밖이라 값은 그대로다. 깨지지 않는 것이 확인 대상이다.
	return result.e == 30 and result.m == result.m
end)

check("StrengthMultiplier: 빈 테이블이면 배수 1", function()
	return isInt(StrengthMultiplier.compute({}), 1)
end)

check("StrengthMultiplier: nil이면 배수 1", function()
	return isInt(StrengthMultiplier.compute(nil), 1)
end)

check("StrengthMultiplier: 엉뚱한 값은 에러 없이 배수 없음으로 접는다", function()
	-- 필드가 BigNum이 아닐 때 터지면 안 된다 — 로드 전 상태가 이 경로를 탄다.
	return isInt(StrengthMultiplier.compute({ rebirths = 5 :: any }), 1)
end)

check("StrengthMultiplier: 반환값을 고쳐도 다음 호출이 오염되지 않는다", function()
	-- BigNum 값은 평범한 테이블이라 상수를 재사용하면 호출자가 상수를 고칠 수 있다.
	local first = StrengthMultiplier.compute(nil)
	first.m = 999
	return isInt(StrengthMultiplier.compute(nil), 1)
end)

check("StrengthMultiplier: 환생 배수와 RebirthConfig가 같은 축을 쓴다", function()
	-- 비용의 3배를 벌어 환생하면 배수는 1 + 3 = 4가 되어야 한다.
	-- 두 모듈을 이어서 재는 유일한 케이스다 — 따로따로 맞아도 이어지지 않을 수 있다.
	local rebirths = RebirthConfig.getGainedRebirths(bloxFor(3, 0))
	return isInt(StrengthMultiplier.compute({ rebirths = rebirths }), 4)
end)

print(string.format("[ConfigTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ConfigTests] %d test(s) failed", failed))
end

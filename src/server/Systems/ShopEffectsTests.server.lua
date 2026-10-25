--!strict
-- 로벅스 효과 검증 (지시서 #16 4단계 · DESIGN 9장 S4 · S5 · S6 · S13 · 공허 OR). 소유 · 제한 · 부스트를 View로 직접 만든다 —
-- GamepassService · PolicyGate · 프로필을 건드리지 않는다.
--   효과마다 미보유 1 · 보유 시 정확한 배수 / 계단 최고만 / 공허 × 계단 곱 / 2배 환생 얻는 수 / 각 결합 자리에서 한 번만 /
--   행운 상품은 제한 유저면 1 / 자동 클리커 높은 쪽만

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local ShopEffects = require(ServerScriptService.Server.Systems.ShopEffects)
local AttackService = require(ServerScriptService.Server.Systems.AttackService)
local ChallengeService = require(ServerScriptService.Server.Systems.ChallengeService)
local GymService = require(ServerScriptService.Server.Systems.GymService)
local RollService = require(ServerScriptService.Server.Systems.RollService)
local ClickService = require(ServerScriptService.Server.Systems.ClickService)

local E = ShopEffects._pure

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

-- keys = 보유 패스, restricted = 제한, boosts = 종류 → 배수
local function view(keys: { string }?, restricted: boolean?, boosts: { [string]: number }?): ShopEffects.View
	local set: { [string]: boolean } = {}
	for _, k in ipairs(keys or {}) do
		set[k] = true
	end
	return {
		owns = function(k: string)
			return set[k] == true
		end,
		restricted = restricted == true,
		boostOf = function(t: string)
			return if boosts ~= nil and boosts[t] ~= nil then boosts[t] else 1
		end,
	}
end

local function mult(key: string): number
	return (ShopConfig.get(key) :: any).effect.mult
end

-- 1. 미보유 1 · 보유 시 정확한 배수 -----------------------------------------------------------------------
do
	local none = view()
	local t, p = E.strength(none)
	local d, dp = E.damage(none)
	check("미보유: 계단 · 힘 포션 · 데미지 · 데미지 포션 · 블럭스 · 환생 전부 1", t == 1 and p == 1 and d == 1 and dp == 1 and E.blox(none) == 1
		and E.rebirth(none) == 1)
	check("미보유: 자동 클리커 0", E.autoClickRate(none) == 0)
	local d2 = E.damage(view({ "damage2x" }))
	check("2배 데미지 = ShopConfig 배수", d2 == mult("damage2x") and d2 == 2)
	check("2배 블럭스 = ShopConfig 배수", E.blox(view({ "blox2x" })) == mult("blox2x"))
	check("2배 환생 = ShopConfig 배수", E.rebirth(view({ "rebirth2x" })) == mult("rebirth2x"))
	local _t, sp = E.strength(view(nil, false, { strength = 2 }))
	local _d, dmp = E.damage(view(nil, false, { damage = 2 }))
	check("힘 포션 · 데미지 포션: 부스트 배수 그대로", sp == 2 and dmp == 2)
	check("자동 클리커 15 · OP 30 · 둘 다면 30(높은 쪽만)", E.autoClickRate(view({ "autoClicker" })) == 15
		and E.autoClickRate(view({ "autoClickerOP" })) == 30 and E.autoClickRate(view({ "autoClicker", "autoClickerOP" })) == 30)
end

-- 2. 계단 최고만 -----------------------------------------------------------------------------------------
do
	local t = E.strength(view({ "strength2x", "strength8x", "strength4x" }))
	check("계단: 2 · 4 · 8을 가지면 8(곱하면 64 — 금지)", t == 8, tostring(t))
	local all = {}
	for _, k in ipairs(ShopConfig.STRENGTH_TIERS) do
		table.insert(all, k)
	end
	check("계단: 전부 가지면 최고 1024", E.strength(view(all)) == 1024)
	local m = StrengthMultiplier.compute({ tierMult = 8 })
	check("StrengthMultiplier: 계단 8만 있으면 8(한 번만)", BigNum.eq(m, BigNum.fromNumber(8)), BigNum.tostring(m))
	local m2 = StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(3), tierMult = 8, potionMult = 2 })
	check("StrengthMultiplier: (1 + 3) × 계단 8 × 힘 포션 2 = 64", BigNum.eq(m2, BigNum.fromNumber(64)), BigNum.tostring(m2))
	local m3 = StrengthMultiplier.compute({ potionMult = 2 })
	check("StrengthMultiplier: 앞 항이 없어도 힘 포션이 곱해진다", BigNum.eq(m3, BigNum.fromNumber(2)))
	check("StrengthMultiplier: 깨진 계단 · 포션 값은 1", BigNum.eq(StrengthMultiplier.compute({ tierMult = 0 / 0, potionMult = 0.5 }), BigNum.fromNumber(1)))
end

-- 3. 공허 OR · 공허 × 계단 곱 -------------------------------------------------------------------------------
do
	local count = GymConfig.getCount()
	local voidIndex = GymConfig.findByGamepass("voidTrainingZone") :: number
	local centers = GymLayout.computeLayout(count)
	local function on(index: number): Vector3
		local c = centers[index]
		return Vector3.new(c.X, c.Y + 3, c.Z)
	end
	local zero = BigNum.new(0, 0)
	local noUnlock = GymService._pure.shopUnlockedWith({}, function()
		return false
	end)
	check("공허: 게임패스 없으면 잠김(배수 1)", GymLayout.resolve(on(voidIndex), BigNum.new(1, 300), noUnlock).multiplier == 1)
	local withPass = GymService._pure.shopUnlockedWith({}, function(k: string)
		return k == "voidTrainingZone"
	end)
	local r = GymLayout.resolve(on(voidIndex), zero, withPass)
	check("공허: 게임패스 소유 OR → 열림 · 공허 배수", r.unlocked and r.multiplier == GymConfig.getMultiplier(voidIndex))
	local record = GymService._pure.shopUnlockedWith({ ["3"] = true }, function()
		return false
	end)
	check("선해금 기록 OR → 환생 0이어도 기구 3 열림", GymLayout.resolve(on(3), zero, record).unlocked and not GymLayout.resolve(on(4), zero, record).unlocked)
	local ownsProductKey = GymService._pure.shopUnlockedWith({}, function(k: string)
		return k == GymConfig.getShopKey(3)
	end)
	check("선해금은 기록만 본다(개발자 상품 키 '소유'는 열지 않는다)", not GymLayout.resolve(on(3), zero, ownsProductKey).unlocked)
	check("환생 해금은 그대로(shopUnlocked 없이도)", GymLayout.resolve(on(1), GymConfig.getUnlockRebirths(1)).unlocked)
	-- 공허 × 계단: 클릭 1회 값(패드 × 기구) × 힘 배수(계단) — ClickService.computeGain이 두 자리를 곱한다
	local padPower = BigNum.fromNumber(5)
	local clickPower = BigNum.mul(padPower, BigNum.fromNumber(r.multiplier))
	local gain = ClickService._pure.computeGain(clickPower, 1, StrengthMultiplier.compute({ tierMult = 16 }))
	local expect = BigNum.fromNumber(5 * GymConfig.getMultiplier(voidIndex) * 16)
	check("공허 × 계단 곱: 패드 5 × 공허 배수 × 계단 16", BigNum.eq(gain, expect), BigNum.tostring(gain) .. " vs " .. BigNum.tostring(expect))
end

-- 4. 1펀치 데미지 · 수령 블럭스: 결합 자리에서 한 번만 -----------------------------------------------------------
do
	local dm = AttackService.combineDamageMultiplier({ punchDamage = 1.5, auraMult = 3, passMult = 2, potionMult = 2 })
	check("데미지 결합: 1.5 × 3 × 2배 데미지 2 × 포션 2 = 18", math.abs(dm - 18) < 1e-9, tostring(dm))
	check("데미지 결합: 2배 데미지만 → 2(한 번만)", AttackService.combineDamageMultiplier({ passMult = 2 }) == 2)
	check("데미지 결합: 깨진 패스 값은 1", AttackService.combineDamageMultiplier({ passMult = 0 / 0, potionMult = math.huge }) == 1)
	local bm = ChallengeService.combineBloxMultiplier({ bloxGain = 1.2, titleMult = 1.5, passMult = 2 })
	check("블럭스 결합: 1.2 × 1.5 × 2배 블럭스 2 = 3.6", math.abs(bm - 3.6) < 1e-9, tostring(bm))
	check("블럭스 결합: 2배 블럭스만 → 2(한 번만)", ChallengeService.combineBloxMultiplier({ passMult = 2 }) == 2)
end

-- 5. 2배 환생 얻는 수 ------------------------------------------------------------------------------------
do
	local blox = BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH * 5 + 500)
	check("2배 환생: 5.5배분 블럭스 → 배수 없이 5 · 2배면 10", BigNum.eq(RebirthConfig.getGainedRebirths(blox), BigNum.fromNumber(5))
		and BigNum.eq(RebirthConfig.getGainedRebirths(blox, E.rebirth(view({ "rebirth2x" }))), BigNum.fromNumber(10)))
	check("2배 환생: 깨진 배수는 1", BigNum.eq(RebirthConfig.getGainedRebirths(blox, 0 / 0), BigNum.fromNumber(5)))
	local below = BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH - 1)
	check("2배 환생: 환생 가능 여부 · 버려지는 양은 배수와 상관없다", not RebirthConfig.canRebirth(below)
		and BigNum.eq(RebirthConfig.getLeftover(blox), BigNum.fromNumber(500)))
end

-- 6. 행운: 패스 · 포션, 제한 유저면 1 ----------------------------------------------------------------------
do
	local owner = view({ "petLuck2x", "auraLuck10x", "titleLuck10x" }, false, { luck = 2 })
	local pet = E.luckOptions(owner, "pet")
	local aura = E.luckOptions(owner, "aura")
	local title = E.luckOptions(owner, "title")
	check("행운 패스: 펫 2 · 아우라 10 · 칭호 10 — 그 뽑기 것만", pet.luckPassMult == 2 and aura.luckPassMult == 10 and title.luckPassMult == 10)
	check("행운 포션: 세 뽑기 모두 2", pet.boostMult == 2 and aura.boostMult == 2 and title.boostMult == 2)
	local restricted = view({ "petLuck2x", "auraLuck10x", "titleLuck10x" }, true, { luck = 2, strength = 2 })
	local rp = E.luckOptions(restricted, "pet")
	local ra = E.luckOptions(restricted, "aura")
	check("제한 유저: 보유한 행운 패스 · 행운 포션 효과가 꺼진다(1)", rp.luckPassMult == 1 and rp.boostMult == 1 and ra.luckPassMult == 1)
	local _t, sp = E.strength(restricted)
	check("제한 유저: 행운 상품이 아닌 힘 포션은 그대로", sp == 2)
	local data = { upgrades = { petLuck = 0 } }
	local luck = RollService.computeLuck("pet", data, E.luckOptions(owner, "pet"))
	local base = UpgradeConfig.getEffect("petLuck", 0)
	check("computeLuck: 업그레이드 × 펫 행운 패스 2 × 행운 포션 2 (한 번씩)", math.abs(luck - base * 4) < 1e-9, tostring(luck))
	check("computeLuck: 제한이면 업그레이드만", RollService.computeLuck("pet", data, rp) == base)
end

print(string.format("[ShopEffectsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ShopEffectsTests] %d test(s) failed", failed))
end

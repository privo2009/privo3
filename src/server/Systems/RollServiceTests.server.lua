--!strict
-- RollService 검증 (지시서 #10 3단계): 행운 체인(G14) · 행운 업그레이드 효과(G13) · 롤 상품은 아우라만(G15) ·
-- 깨진 배수 방어 · RNG 주입과 복구 · seed 결정성. 기대값은 UpgradeConfig에서 읽는다(숫자를 박지 않는다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local RollService = require(script.Parent.RollService)

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

local function close(a: number, b: number): boolean
	return math.abs(a - b) < 1e-12
end

local function dataWith(name: string, level: number)
	return { upgrades = { [name] = level } }
end

-- 1. 행운 업그레이드 효과 = 1 + 증가량 × 레벨 (G13) -------------------------------------------------
for kind, def in pairs(RollService.KINDS) do
	local name = def.luckUpgrade
	local per = UpgradeConfig.getEffectPerLevel(name)
	check(kind .. ": 0레벨 행운 = ×1 (곱셈 항이라 0이면 확률이 0이 된다)", close(RollService.computeLuck(kind, dataWith(name, 0)), 1))
	check(kind .. ": 3레벨 행운 = 1 + 증가량 × 3", close(RollService.computeLuck(kind, dataWith(name, 3)), 1 + per * 3))
	check(kind .. ": 프로필이 없으면 0레벨", close(RollService.computeLuck(kind, nil), 1))
end

do
	local per = UpgradeConfig.getEffectPerLevel("titleLuck")
	check("다른 뽑기의 행운 업그레이드는 섞이지 않는다", close(RollService.computeLuck("title", { upgrades = { auraLuck = 50, petLuck = 9 } }), 1)
		and close(RollService.computeLuck("title", { upgrades = { titleLuck = 2, auraLuck = 50 } }), 1 + per * 2))
	check("깨진 레벨(음수 · nan · 문자열)은 0레벨", close(RollService.computeLuck("title", dataWith("titleLuck", -4)), 1)
		and close(RollService.computeLuck("title", dataWith("titleLuck", 0 / 0)), 1)
		and close(RollService.computeLuck("title", { upgrades = { titleLuck = "9" } }), 1))
end

-- 2. 체인의 나머지 항 (G14) -------------------------------------------------------------------
do
	local base = RollService.computeLuck("aura", dataWith("auraLuck", 2))
	check("아우라: 롤 상품 배수가 곱해진다 (G15)", close(RollService.computeLuck("aura", dataWith("auraLuck", 2), { rollProductMult = 5 }), base * 5))
	check("타이틀: 롤 상품 배수는 무시 (아우라 전용)", close(RollService.computeLuck("title", nil, { rollProductMult = 100 }), 1))
	check("펫: 롤 상품 배수는 무시 (아우라 전용)", close(RollService.computeLuck("pet", nil, { rollProductMult = 100 }), 1))
	check("행운 게임패스 · 부스트가 곱해진다", close(RollService.computeLuck("title", nil, { luckPassMult = 10, boostMult = 2 }), 20))
	check("옵션이 없으면 체인 = 행운 업그레이드", close(RollService.computeLuck("title", dataWith("titleLuck", 4)), UpgradeConfig.getEffect("titleLuck", 4)))
end

do
	local f = RollService._pure.factor
	check("깨진 배수(nil · nan · 1 미만 · inf · 문자열)는 1", f(nil) == 1 and f(0 / 0) == 1 and f(0.5) == 1 and f(math.huge) == 1 and f("5") == 1)
	check("정상 배수는 그대로", f(1) == 1 and f(10) == 10)
	check("모르는 뽑기 종류는 error", not pcall(RollService.computeLuck, "drone", nil))
end

-- 3. RNG 주입 · 복구 ----------------------------------------------------------------------------
do
	local tiers = { { id = "f" }, { id = "x", baseChance = 0.5 } }
	RollService._setRandom(function()
		return 0.1
	end)
	local hit = RollService.roll(tiers, 1)
	RollService._setRandom(function()
		return 0.9
	end)
	local miss = RollService.roll(tiers, 1)
	RollService._resetRandom()
	check("주입한 난수로 판정한다 (0.1 → x, 0.9 → 폴백)", hit.id == "x" and miss.id == "f")

	local ok, _, index = pcall(RollService.roll, tiers, 1)
	check("복구 뒤 서버 RNG로 돈다 (결과가 유효한 등급)", ok and (index == 1 or index == 2))
end

-- 4. seed 결정성 ----------------------------------------------------------------------------------
do
	local a, b = RollService.seededRandom(42), RollService.seededRandom(42)
	local same = true
	for _ = 1, 50 do
		if a() ~= b() then
			same = false
		end
	end
	local c = RollService.seededRandom(43)
	check("같은 seed → 같은 난수 열", same)
	check("다른 seed → 다른 난수 열", RollService.seededRandom(42)() ~= c())
end

-- 5. 결과 코드는 서로 다른 문자열 ----------------------------------------------------------------------
do
	local codes = {
		RollService.RESULT_NEW, RollService.RESULT_DUPLICATE, RollService.REASON_NO_PROFILE, RollService.REASON_INSUFFICIENT_BLOX,
		RollService.REASON_RATE_LIMITED, RollService.REASON_INVALID, RollService.REASON_PARTIAL_FAILURE,
	}
	local seen: { [string]: boolean } = {}
	local unique = true
	for _, c in ipairs(codes) do
		if type(c) ~= "string" or seen[c] then
			unique = false
		end
		seen[c] = true
	end
	check("결과 · 사유 코드 7개가 서로 다른 문자열", unique)
	check("잔액 부족 코드는 상점과 같은 문자열 (UI 문구 공유)", RollService.REASON_INSUFFICIENT_BLOX == UpgradeConfig.REASON_INSUFFICIENT_BLOX)
end

-- ===== 앞 항이 없어도 뒤 항이 곱해진다 (지시서 #12 2단계 — #11 StrengthMultiplier ipairs 구멍과 같은 종류) =====
do
	local close = function(a: number, b: number): boolean
		return math.abs(a - b) < 1e-9
	end
	check("행운 체인: 업그레이드 없음 · 롤 상품 없음이어도 행운 게임패스 · 부스트는 곱해진다",
		close(RollService.computeLuck("aura", nil, { rollProductMult = nil, luckPassMult = 2, boostMult = 3 }), 6))
	check("행운 체인: 롤 상품이 깨져도(nan) 뒤 항은 곱해진다",
		close(RollService.computeLuck("aura", nil, { rollProductMult = 0 / 0, luckPassMult = 2 }), 2))
	check("행운 체인(펫): 업그레이드 0 · 롤 상품 비대상이어도 행운 게임패스는 곱해진다",
		close(RollService.computeLuck("pet", nil, { luckPassMult = 2 }), 2))
end

print(string.format("[RollServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RollServiceTests] %d test(s) failed", failed))
end

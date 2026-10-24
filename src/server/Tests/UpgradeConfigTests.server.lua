--!strict
-- UpgradeConfig 검증 (지시서 #7 2단계): 노출 4종 · 비노출 4종(S0), 효과는 레벨에 선형(S1),
-- 펀치 속도 증가량 유도 · 최대 레벨 = 상한(S2), 이동속도 효과가 있어도 MAX_WALK_SPEED 이하(S3),
-- 비용 단조 증가, 구매 판정(canBuy) 사유 3종, validate가 규약 위반을 잡는가.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local Schema = require(script.Parent.Parent.Data.Schema)

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
	return math.abs(a - b) < 1e-9
end

local EXPOSED = { "punchDamage", "punchSpeed", "moveSpeed", "bloxGain", "titleLuck", "auraLuck" } -- titleLuck #10 · auraLuck #11
local HIDDEN = { "petLuck", "petSlots" }

-- 1. validate · 노출 구분 ---------------------------------------------------------------------
do
	local ok, err = pcall(UpgradeConfig.validate)
	check("validate 통과", ok, tostring(err))
	check("SHOP_ORDER = 1차 4종 + 칭호 행운 + 아우라 행운 순서", table.concat(UpgradeConfig.SHOP_ORDER, ",") == table.concat(EXPOSED, ","))
	for _, name in ipairs(EXPOSED) do
		check("노출: " .. name, UpgradeConfig.isExposed(name))
	end
	for _, name in ipairs(HIDDEN) do
		check("비노출(Phase 7): " .. name, UpgradeConfig.Upgrades[name] ~= nil and not UpgradeConfig.isExposed(name))
	end
	check("없는 이름 · nil · 숫자는 노출 아님", not UpgradeConfig.isExposed("radius") and not UpgradeConfig.isExposed(nil) and not UpgradeConfig.isExposed(1))

	-- 프로필 스키마의 upgrades 키가 Config 8키와 1:1이다(비노출 4종을 지우지 않았다)
	local template = Schema.new()
	local schemaKeys, configKeys = 0, 0
	local allIn = true
	for name in pairs(template.upgrades) do
		schemaKeys += 1
		if UpgradeConfig.Upgrades[name] == nil then
			allIn = false
		end
	end
	for _ in pairs(UpgradeConfig.Upgrades) do
		configKeys += 1
	end
	check("스키마 upgrades 키 = Config 키 (8)", allIn and schemaKeys == configKeys and configKeys == 8, string.format("%d/%d", schemaKeys, configKeys))
end

-- 2. 효과는 레벨에 선형 (S1) -------------------------------------------------------------------
for _, name in ipairs(EXPOSED) do
	local step = UpgradeConfig.getEffect(name, 1) - UpgradeConfig.getEffect(name, 0)
	local linear = step > 0
	for level = 1, 15 do
		local d = UpgradeConfig.getEffect(name, level + 1) - UpgradeConfig.getEffect(name, level)
		if UpgradeConfig.isMaxLevel(name, level + 1) and UpgradeConfig.isMaxLevel(name, level) then
			break
		end
		if not close(d, step) then
			linear = false
		end
	end
	check("S1 선형: " .. name .. " 레벨당 증가가 일정하다", linear)
	check("S1: " .. name .. " 0레벨 효과 = 기본값", close(UpgradeConfig.getEffect(name, 0), UpgradeConfig.getEffectBase(name)))
end
check("펀치 데미지 · 블럭스 획득 0레벨은 ×1", close(UpgradeConfig.getEffect("punchDamage", 0), 1) and close(UpgradeConfig.getEffect("bloxGain", 0), 1))
check("이동속도 0레벨 보너스는 0", close(UpgradeConfig.getEffect("moveSpeed", 0), 0))

-- 3. 펀치 속도 (S2) ----------------------------------------------------------------------------
do
	local maxLevel = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number
	local expectedStep = (AttackConfig.PUNCH_SPEED_MAX - AttackConfig.PUNCH_SPEED_BASE) / maxLevel
	check("S2: 증가량 = (상한 − 기본) ÷ 최대 레벨", close(UpgradeConfig.getEffectPerLevel("punchSpeed"), expectedStep))
	check("S2: 0레벨 = PUNCH_SPEED_BASE", close(UpgradeConfig.getEffect("punchSpeed", 0), AttackConfig.PUNCH_SPEED_BASE))
	check("S2: 최대 레벨 = PUNCH_SPEED_MAX", close(UpgradeConfig.getEffect("punchSpeed", maxLevel), AttackConfig.PUNCH_SPEED_MAX))
	check("S2: 최대 레벨보다 높은 값은 상한에서 멈춘다", close(UpgradeConfig.getEffect("punchSpeed", maxLevel + 7), AttackConfig.PUNCH_SPEED_MAX))
	check("S2: 증가량을 Config에 따로 적지 않았다", UpgradeConfig.Upgrades.punchSpeed.effectPerLevel == nil)

	-- 상한을 흔들면 증가량이 따라온다(유도값인가)
	local saved = AttackConfig.PUNCH_SPEED_MAX
	AttackConfig.PUNCH_SPEED_MAX = saved + 1
	local ok, top = pcall(UpgradeConfig.getEffect, "punchSpeed", maxLevel)
	AttackConfig.PUNCH_SPEED_MAX = saved
	check("S2: PUNCH_SPEED_MAX를 바꾸면 최대 레벨 효과가 따라온다", ok and close(top :: number, saved + 1), tostring(top))
end

-- 4. 이동속도 (S3) -----------------------------------------------------------------------------
do
	local cap = LevelConfig.getMaxWalkSpeed()
	local maxLevel = UpgradeConfig.Upgrades.moveSpeed.maxLevel :: number
	local topBonus = UpgradeConfig.getEffect("moveSpeed", maxLevel)
	local zero = BigNum.new(0, 0)
	check("S3: 업그레이드 0이면 기존 식 그대로", LevelConfig.getMaxSpeed(zero, 0) == LevelConfig.getMaxSpeed(zero)
		and LevelConfig.getMaxSpeed(zero) == LevelConfig.BASE_WALK_SPEED)
	check("S3: 16 + 레벨 + 업그레이드", close(LevelConfig.getMaxSpeed(BigNum.new(1, 5), UpgradeConfig.getEffect("moveSpeed", 3)),
		math.min(LevelConfig.BASE_WALK_SPEED + 5 + UpgradeConfig.getEffect("moveSpeed", 3), cap)))
	check("S3: 힘이 아주 커도 · 업그레이드를 다 사도 MAX_WALK_SPEED를 넘지 않는다", LevelConfig.getMaxSpeed(BigNum.new(1, 2000), topBonus) == cap)
	check("S3: 터무니없는 보너스(1e9)도 MAX_WALK_SPEED에서 잘린다", LevelConfig.getMaxSpeed(zero, 1e9) == cap)
	check("S3: 음수 · NaN 보너스는 0으로 본다", LevelConfig.getMaxSpeed(zero, -50) == LevelConfig.BASE_WALK_SPEED
		and LevelConfig.getMaxSpeed(zero, 0 / 0) == LevelConfig.BASE_WALK_SPEED)
end

-- 5. 비용 단조 증가 ----------------------------------------------------------------------------
for _, name in ipairs(EXPOSED) do
	local maxLevel = UpgradeConfig.Upgrades[name].maxLevel
	local last = math.min(if maxLevel ~= nil then maxLevel - 1 else 60, 60)
	local increasing = true
	for level = 0, last - 1 do
		if not BigNum.gt(UpgradeConfig.getCostAtLevel(name, level + 1), UpgradeConfig.getCostAtLevel(name, level)) then
			increasing = false
		end
	end
	check("비용 단조 증가: " .. name, increasing)
end

-- 6. 구매 판정 canBuy ---------------------------------------------------------------------------
do
	local rich = BigNum.new(1, 100)
	local ok1, r1 = UpgradeConfig.canBuy("radius", 0, rich)
	check("canBuy: 없는 항목 → invalid_upgrade", not ok1 and r1 == UpgradeConfig.REASON_INVALID_UPGRADE)
	local ok2, r2 = UpgradeConfig.canBuy("petLuck", 0, rich)
	check("canBuy: 비노출 항목 → invalid_upgrade", not ok2 and r2 == UpgradeConfig.REASON_INVALID_UPGRADE)
	local ok3, r3 = UpgradeConfig.canBuy(nil, 0, rich)
	check("canBuy: nil → invalid_upgrade", not ok3 and r3 == UpgradeConfig.REASON_INVALID_UPGRADE)
	local maxLevel = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number
	local ok4, r4 = UpgradeConfig.canBuy("punchSpeed", maxLevel, rich)
	check("canBuy: 최대 레벨 → max_level (블럭스가 많아도)", not ok4 and r4 == UpgradeConfig.REASON_MAX_LEVEL)
	local cost = UpgradeConfig.getCostAtLevel("punchDamage", 3)
	local ok5, r5, c5 = UpgradeConfig.canBuy("punchDamage", 3, BigNum.sub(cost, BigNum.fromNumber(1)))
	check("canBuy: 모자라면 insufficient_blox + 비용", not ok5 and r5 == UpgradeConfig.REASON_INSUFFICIENT_BLOX and c5 ~= nil and BigNum.eq(c5 :: any, cost))
	local ok6, r6, c6 = UpgradeConfig.canBuy("punchDamage", 3, cost)
	check("canBuy: 딱 맞으면 가능 + 비용은 getCostAtLevel", ok6 and r6 == nil and c6 ~= nil and BigNum.eq(c6 :: any, cost))
end

-- 6b. 이동 속도 최대 속도 도달 (지시서 #8) -----------------------------------------------------------
do
	local rich = BigNum.new(1, 100)
	local strong = BigNum.new(1, 200) -- 레벨 200 — 업그레이드 0이어도 최대 속도가 상한
	local weak = BigNum.new(1, 0)
	check("이동 속도: 힘이 아주 크면 이미 상한 — capped", UpgradeConfig.isMoveSpeedCapped(0, strong))
	check("이동 속도: 힘이 작으면 상한 아님", not UpgradeConfig.isMoveSpeedCapped(0, weak))
	local ok1, r1 = UpgradeConfig.canBuy("moveSpeed", 0, rich, { strength = strong })
	check("canBuy: 최대 속도 도달 → max_speed_reached (블럭스가 많아도)", not ok1 and r1 == UpgradeConfig.REASON_MAX_SPEED_REACHED)
	local ok2 = UpgradeConfig.canBuy("moveSpeed", 0, rich, { strength = weak })
	check("canBuy: 상한 아래면 산다", ok2)
	local ok3 = UpgradeConfig.canBuy("moveSpeed", 0, rich)
	check("canBuy: 힘을 안 주면 그 판정을 건너뛴다(시뮬레이터 · 옛 호출부)", ok3)
	local ok4 = UpgradeConfig.canBuy("punchDamage", 0, rich, { strength = strong })
	check("canBuy: 다른 항목은 힘과 무관", ok4)
	local top = UpgradeConfig.Upgrades.moveSpeed.maxLevel :: number
	local _, r5 = UpgradeConfig.canBuy("moveSpeed", top, rich, { strength = strong })
	check("canBuy: 최대 레벨이 최대 속도 도달보다 먼저", r5 == UpgradeConfig.REASON_MAX_LEVEL)
end

-- 7. validate가 규약 위반을 잡는다 ---------------------------------------------------------------
local function rejects(label: string, mutate: () -> (), restore: () -> ())
	mutate()
	local ok = pcall(UpgradeConfig.validate)
	restore()
	check("validate 거부: " .. label, not ok)
end

do
	local defs = UpgradeConfig.Upgrades
	local g = defs.punchDamage.costGrowth
	rejects("노출 항목 비용 증가율 1(단조 증가 아님)", function() defs.punchDamage.costGrowth = 1 end, function() defs.punchDamage.costGrowth = g end)
	local m = defs.punchSpeed.maxLevel
	rejects("펀치 속도 최대 레벨 없음(S2)", function() defs.punchSpeed.maxLevel = nil end, function() defs.punchSpeed.maxLevel = m end)
	local order = UpgradeConfig.SHOP_ORDER
	rejects("노출 항목이 SHOP_ORDER에 없음", function() UpgradeConfig.SHOP_ORDER = { "punchDamage", "punchSpeed", "moveSpeed" } end, function() UpgradeConfig.SHOP_ORDER = order end)
	rejects("비노출 항목을 SHOP_ORDER에 넣음", function() UpgradeConfig.SHOP_ORDER = { "punchDamage", "punchSpeed", "moveSpeed", "bloxGain", "titleLuck", "auraLuck", "petLuck" } end, function() UpgradeConfig.SHOP_ORDER = order end)
	local ok = pcall(UpgradeConfig.validate)
	check("흔든 뒤 원래대로 validate 통과", ok)
end

print(string.format("[UpgradeConfigTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UpgradeConfigTests] %d test(s) failed", failed))
end

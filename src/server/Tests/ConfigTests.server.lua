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
local AuraConfig = require(Config.AuraConfig)
local TitleConfig = require(Config.TitleConfig)
local PetConfig = require(Config.PetConfig)
local AssetConfig = require(Config.AssetConfig)
local ClickPadConfig = require(Config.ClickPadConfig)
local LevelConfig = require(Config.LevelConfig)
local RebirthConfig = require(Config.RebirthConfig)
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

check("AuraConfig.validate", function()
	return AuraConfig.validate()
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
	local mult = ShopConfig.getActiveStrengthMultiplier(function(_id: number)
		return true
	end)
	return mult == 1024
end)

check("PetConfig.getNextTier: 최고 등급은 nil", function()
	return PetConfig.getNextTier(4) == nil and PetConfig.getNextTier(1) == 2
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


check("ClickPadConfig: 월드1 패드24 파워 = 8.39M (1 × 2^23)", function()
	return approxEq(ClickPadConfig.getPadPower(1, 24), BigNum.new(8.388608, 6))
end)

check("ClickPadConfig: 월드1 패드24 해금 조건 = 1.13T (bloxBase × 36 × 3^22)", function()
	return approxEq(ClickPadConfig.getPadUnlock(1, 24), BigNum.new(1.129718145924, 12))
end)

check("ClickPadConfig: 패드1은 조건이 0이라 항상 열려 있다", function()
	local zero = BigNum.new(0, 0)
	return BigNum.eq(ClickPadConfig.getPadUnlock(1, 1), zero)
		and ClickPadConfig.isUnlocked(1, 1, zero) == true
end)

check("ClickPadConfig: lifetimeBlox 0이면 해금 개수 1", function()
	-- 패드2 조건은 bloxBase × 36이므로 0으로는 절대 열리지 않는다.
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
	-- 힘 0({m=0,e=0})과 힘 1({m=1,e=0}) 둘 다 지수가 0이라 레벨 0이다.
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

check("LevelConfig: 상한 미만에서는 지수 +1이 속도 +1", function()
	-- 상한(현재 80)에 닿기 한참 전 구간에서만 성립하는 성질이다.
	local base = LevelConfig.BASE_WALK_SPEED
	for exponent = 0, 10 do
		local speed = LevelConfig.getMaxSpeed(BigNum.new(1, exponent))
		if speed >= LevelConfig.getMaxWalkSpeed() then
			return false -- 이 구간이 이미 상한이면 테스트 전제가 깨진 것이다
		end
		if speed ~= base + exponent then
			return false
		end
	end
	return true
end)

check("LevelConfig: 상한을 넘으면 지수를 올려도 속도가 멈춘다", function()
	local cap = LevelConfig.getMaxWalkSpeed()
	-- 상한에 확실히 걸리는 지수 두 개. 값이 서로 같고 상한과 같아야 한다.
	local a = LevelConfig.getMaxSpeed(BigNum.new(1, 500))
	local b = LevelConfig.getMaxSpeed(BigNum.new(1, 900))
	return a == cap and b == cap
end)

check("LevelConfig: 10^2000이면 레벨 2000, 속도는 상한", function()
	-- 레벨 자체에는 상한이 없다. 멈추는 것은 속도뿐이다 (DESIGN.md "레벨").
	local huge = BigNum.new(1, 2000)
	return LevelConfig.getLevel(huge) == 2000 and LevelConfig.getMaxSpeed(huge) == LevelConfig.getMaxWalkSpeed()
end)

check("LevelConfig: 발판 깊이가 절반이면 상한도 절반 (유도가 실제로 돈다)", function()
	-- 상수를 박았는지 유도하는지를 가르는 테스트다. PAD_SIZE를 흔들어 상한이 따라오는지 본다.
	--
	-- ⚠️ ConfigTests에서 원본 모듈을 건드리는 유일한 케이스다. 중간에 error가 나도 복구가
	-- 반드시 돌아야 뒤따르는 케이스들이 오염된 PAD_SIZE로 돌지 않는다. 그래서 흔든 뒤의
	-- 본문을 pcall로 감싸고 복구를 그 바깥에 둔다.
	-- 다만 pcall이 실패를 삼키면 안 된다 — 복구를 마친 뒤 원래 error를 그대로 다시 던져서
	-- check()의 pcall이 메시지째 받아 [FAIL]에 찍게 한다.
	local original = PadLayout.PAD_SIZE
	local full = LevelConfig.getMaxWalkSpeed()

	PadLayout.PAD_SIZE = Vector3.new(original.X, original.Y, original.Z / 2)
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

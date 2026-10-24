--!strict
-- SuccessRateReport(확률적 플레이어 성공률 시뮬레이터)의 계산 계약 검증.
-- Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
--
-- 리포트 숫자가 믿을 만한지는 "게임과 같은 식인가"에 달려 있다. 여기서는 그 식만 본다 —
-- 펀치 간격 · 1회 데미지 = 힘(속도 미곱) · 반경 밖 시간 · 걷기 시간 · 결정성.
-- ⚠️ 설정 숫자를 리터럴로 적지 않는다. 기대값은 Config에서 다시 유도한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
local SuccessRateReport = require(ServerScriptService.Server.Tools.SuccessRateReport)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)

local checkClose = TestHelpers.checkClose

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

local TIMER = StageConfig.CHALLENGE_TIMER_SEC
local INTERVAL = 1 / AttackConfig.PUNCH_SPEED_BASE
local MODEL = SuccessRateReport.MODEL

-- 런 중 클릭을 끄고 돌린다(힘 고정). 끝나면 원래 값으로 되돌린다.
local function withoutRunClicks(fn: () -> ())
	local saved = MODEL.RUN_CLICK_FACTOR
	MODEL.RUN_CLICK_FACTOR = 0
	local ok, err = pcall(fn)
	MODEL.RUN_CLICK_FACTOR = saved
	if not ok then
		error(err)
	end
end

local function playerWith(strength: BigNum.BigNumber)
	local p = SuccessRateReport.newPlayer(Random.new(1))
	p.strength = strength
	return p
end

-- 1. 압도적인 힘 → 첫 펀치에 클리어 ---------------------------------------------------
do
	local p = playerWith(BigNum.new(1, 300))
	local o = SuccessRateReport.simulateStage(p, 1, 0, 0)
	check("압도적 힘: 클리어", o.cleared == true)
	check("압도적 힘: 펀치 1회", o.punches == 1, tostring(o.punches))
	check("압도적 힘: 남은 시간 = 타이머", checkClose(o.timeLeft, TIMER), tostring(o.timeLeft))
end

-- 2. 반경 밖 시간이 타이머 이상 → 펀치 0회, 실패 ---------------------------------------
do
	local p = playerWith(BigNum.new(1, 300))
	local o = SuccessRateReport.simulateStage(p, 1, TIMER + 1, 0)
	check("반경 밖 내내: 실패", o.cleared == false)
	check("반경 밖 내내: 펀치 0회", o.punches == 0, tostring(o.punches))
	check("반경 밖 내내: 남은 시간 0", o.timeLeft == 0)
end

-- 3. 펀치 횟수 = 간격으로만 정해진다 (속도를 데미지에 곱하지 않는다) ---------------------
withoutRunClicks(function()
	local strength = BigNum.new(1, 0)
	local p = playerWith(strength)
	-- HP를 못 깎을 만큼 약하게 두려면 총HP가 힘 × 최대 펀치 수보다 커야 한다.
	local maxPunches = math.floor(TIMER / INTERVAL) + 1
	local hp = StageConfig.getTotalHp(StageConfig.hasStage(25) and 25 or 1)
	check("전제: 25층(또는 1층) HP > 힘 1 × 최대 펀치", BigNum.gt(hp, BigNum.fromNumber(maxPunches)))
	local o = SuccessRateReport.simulateStage(p, StageConfig.hasStage(25) and 25 or 1, 0, 0)
	check("약한 힘: 실패", o.cleared == false)
	check("약한 힘: 펀치 수 = floor(타이머 ÷ 간격) + 1", o.punches == maxPunches, string.format("%d vs %d", o.punches, maxPunches))
	check("런 중 클릭 0이면 힘 그대로", BigNum.eq(p.strength, strength), string.format("m=%s e=%s", tostring(p.strength.m), tostring(p.strength.e)))
end)

-- 4. 총HP = 힘 × k 이면 정확히 k번째 펀치에 클리어 ---------------------------------------
withoutRunClicks(function()
	local hp = StageConfig.getTotalHp(1)
	local k = 4
	-- 힘 = HP / k. k번째 펀치에 남은 HP가 정확히 0 이하가 된다.
	local strength = BigNum.div(hp, BigNum.fromNumber(k))
	-- 나눗셈 반올림으로 k번에 모자랄 수 있으니 아주 조금 올린다(가수 상대 1e-9).
	strength = BigNum.mul(strength, BigNum.fromNumber(1 + 1e-9))
	local p = playerWith(strength)
	local o = SuccessRateReport.simulateStage(p, 1, 0, 0)
	check("HP = 힘×4: 클리어", o.cleared == true)
	check("HP = 힘×4: 펀치 4회", o.punches == k, tostring(o.punches))
	check(
		"HP = 힘×4: 남은 시간 = 타이머 - 3 간격",
		checkClose(o.timeLeft, TIMER - (k - 1) * INTERVAL),
		tostring(o.timeLeft)
	)
end)

-- 5. 반경 밖 시간만큼 첫 펀치가 늦어진다 ---------------------------------------------
withoutRunClicks(function()
	local p = playerWith(BigNum.new(1, 300))
	local out = 1.25
	local o = SuccessRateReport.simulateStage(p, 1, out, 0)
	check("반경 밖 1.25초: 남은 시간 = 타이머 - 1.25", checkClose(o.timeLeft, TIMER - out), tostring(o.timeLeft))
end)

-- 6. 런 중 클릭은 힘을 올린다 --------------------------------------------------------
do
	local p = playerWith(BigNum.new(1, 0))
	local before = BigNum.new(p.strength.m, p.strength.e)
	SuccessRateReport.simulateStage(p, StageConfig.hasStage(25) and 25 or 1, 0, 0)
	check("런 중 클릭으로 힘 증가", BigNum.gt(p.strength, before))
end

-- 7. 걷기 시간 = 스폰→게이트 거리 ÷ 레벨 최대속도 ------------------------------------
do
	local p = SuccessRateReport.newPlayer(Random.new(2))
	local expected = ArenaConfig.getSpawnToEntrance() / LevelConfig.getMaxSpeed(p.strength)
	local before = p.elapsedSec
	local sec = SuccessRateReport.walkToGate(p)
	check("걷기 시간 = 거리 ÷ 최대속도", checkClose(sec, expected), string.format("%s vs %s", tostring(sec), tostring(expected)))
	check("걷기 시간이 경과 시간에 더해진다", checkClose(p.elapsedSec - before, expected))
end

-- 8. 플레이어 모델 범위 ---------------------------------------------------------------
do
	local rng = Random.new(3)
	local okRate, okThreshold = true, true
	for _ = 1, 100 do
		local p = SuccessRateReport.newPlayer(rng)
		if p.clickRate < MODEL.CLICK_RATE_MIN or p.clickRate > MODEL.CLICK_RATE_MAX then
			okRate = false
		end
		if p.advanceThreshold < MODEL.ADVANCE_THRESHOLD_MIN or p.advanceThreshold > MODEL.ADVANCE_THRESHOLD_MAX then
			okThreshold = false
		end
	end
	check("클릭 속도가 모델 범위 안", okRate)
	check("진행 문턱이 모델 범위 안", okThreshold)
end

-- 8b. 진행 판단 규칙 --------------------------------------------------------------------
do
	local p = SuccessRateReport.newPlayer(Random.new(4))
	p.advanceThreshold = 0.3
	p.advanceNoise = 0
	check("time_left: 문턱 바로 위면 진행", SuccessRateReport.wantsAdvance(p, 1, TIMER * 0.3 + 0.01))
	check("time_left: 문턱 바로 아래면 수령", not SuccessRateReport.wantsAdvance(p, 1, TIMER * 0.3 - 0.01))

	local savedRule = MODEL.ADVANCE_RULE
	MODEL.ADVANCE_RULE = "growth_aware"
	local r = BigNum.toRatio(StageConfig.getTotalHp(2), StageConfig.getTotalHp(1))
	local breakEven = TIMER * (1 - 1 / r)
	local okAbove = SuccessRateReport.wantsAdvance(p, 1, breakEven + 0.01)
	local okBelow = not SuccessRateReport.wantsAdvance(p, 1, breakEven - 0.01)
	MODEL.ADVANCE_RULE = savedRule
	check("growth_aware: 손익분기(1 - 1/배율) 바로 위면 진행", okAbove)
	check("growth_aware: 손익분기 바로 아래면 수령", okBelow)
end

-- 9. 같은 seed → 같은 결과 (재현 가능) -------------------------------------------------
do
	local function once()
		local tally = {}
		local r = SuccessRateReport.simulatePlayer(Random.new(42), 2, tally)
		return r, tally
	end
	local a, ta = once()
	local b, tb = once()
	check("결정성: 런 수 같음", a.runs == b.runs, string.format("%d vs %d", a.runs, b.runs))
	check("결정성: 환생 수 같음", a.rebirths == b.rebirths)
	check("결정성: 1층 첫 시도 결과 같음", (ta[1] and ta[1].successes) == (tb[1] and tb[1].successes))
	check("2층 목표: 2층 첫 시도 기록됨", ta[2] ~= nil and ta[2].attempts == 1)
	check("층마다 첫 시도는 플레이어당 1회", ta[1] ~= nil and ta[1].attempts == 1)
end

-- 10. 워프 비교 -------------------------------------------------------------------------
check("결정 모델에는 워프가 없다", MODEL.WARP_POLICY == "none", tostring(MODEL.WARP_POLICY))
check("가격 배율 1이면 WarpConfig.cost 그대로", MODEL.WARP_PRICE_SCALE == 1
	and BigNum.eq(SuccessRateReport.warpCost(5), WarpConfig.cost(5)))

-- 판단 재료를 직접 채운 플레이어. climbSec[k] = k초(층당 1초), 걷기 2초, 마지막 런 10초.
local function warpReady(blox: BigNum.BigNumber, lastReward: BigNum.BigNumber)
	local p = SuccessRateReport.newPlayer(Random.new(5))
	p.blox = blox
	p.lastWalkSec = 2
	p.lastRunSec = 10
	p.lastRunReward = lastReward
	for k = 1, 4 do
		p.climbSec[k] = k
	end
	return p
end

do
	local fresh = SuccessRateReport.newPlayer(Random.new(5))
	check("워프: 판단 재료가 없으면 걷는다", SuccessRateReport.chooseWarp(fresh) == nil)

	local poor = warpReady(BigNum.new(0, 0), BigNum.new(1, 300))
	check("워프: 돈이 모자라면 걷는다", SuccessRateReport.chooseWarp(poor) == nil)

	-- 보상이 워프 비용에 비해 압도적이면 비용 시간 ≈ 0 → 아낀 시간이 가장 큰 층(5층) 선택.
	local rich = warpReady(BigNum.new(1, 300), BigNum.new(1, 300))
	check("워프: 거의 공짜면 걸어서 깬 최고층+1까지 간다", SuccessRateReport.chooseWarp(rich) == 5,
		tostring(SuccessRateReport.chooseWarp(rich)))

	-- 마지막 런 보상이 아주 작으면 비용 시간이 아낀 시간보다 크다.
	local slow = warpReady(BigNum.new(1, 300), BigNum.new(1, -300))
	check("워프: 비용을 버는 시간이 더 길면 걷는다", SuccessRateReport.chooseWarp(slow) == nil)

	local failed_ = warpReady(BigNum.new(1, 300), BigNum.new(0, 0))
	check("워프: 마지막 런 보상 0이면 걷는다", SuccessRateReport.chooseWarp(failed_) == nil)
end

-- 워프 런은 걷지 않고 그 층부터 시작한다.
do
	local p = playerWith(BigNum.new(1, 300))
	local tally = {}
	local seen = {}
	local before = p.elapsedSec
	SuccessRateReport.runOnce(p, Random.new(6), tally, seen, 3)
	check("워프 런: 1·2층에 들어가지 않는다", seen[1] == nil and seen[2] == nil)
	check("워프 런: 3층부터 시작", seen[3] == true)
	check("워프 런: 클리어 기록(climbSec)을 덮지 않는다", next(p.climbSec) == nil)
	check("워프 런: 걷지 않는다(걷기 시간 미기록)", p.lastWalkSec == nil)
	check("워프 런: 런 길이 = 경과 시간", p.lastRunSec ~= nil and checkClose(p.lastRunSec, p.elapsedSec - before))

	local walkedP = playerWith(BigNum.new(1, 300))
	SuccessRateReport.runOnce(walkedP, Random.new(6), {}, {}, nil)
	check("걸어간 런: climbSec[1]이 기록된다", walkedP.climbSec[1] ~= nil)
	check("걸어간 런: 걷기 시간이 기록된다", walkedP.lastWalkSec ~= nil and walkedP.lastWalkSec > 0)
end

-- 11. 진행 문턱 구간 비교 ------------------------------------------------------------------
do
	local bands = SuccessRateReport.THRESHOLD_BANDS
	check("문턱 구간 3개", #bands == 3, tostring(#bands))
	check("문턱 구간 순서 50~90 · 30~70 · 10~50",
		bands[1].min == 0.5 and bands[1].max == 0.9
			and bands[2].min == 0.3 and bands[2].max == 0.7
			and bands[3].min == 0.1 and bands[3].max == 0.5)
	check("첫 구간만 목표 기준", bands[1].target and not bands[2].target and not bands[3].target)
	check("첫 구간 = 결정 모델 문턱",
		bands[1].min == MODEL.ADVANCE_THRESHOLD_MIN and bands[1].max == MODEL.ADVANCE_THRESHOLD_MAX)

	-- segmentSums: 직접 만든 첫 시도 표를 구간별로 더한다.
	local fake = {
		[1] = { attempts = 2, successes = 1 },
		[2] = { attempts = 3, successes = 3 },
	}
	local sums = SuccessRateReport.segmentSums(fake, 2)
	check("segmentSums: maxStage 위 구간은 빠진다", #sums == 1, tostring(#sums))
	check("segmentSums: 첫 구간 1~2층으로 잘림", sums[1] ~= nil and sums[1].from == 1 and sums[1].to == 2)
	check("segmentSums: 합산", sums[1] ~= nil and sums[1].attempts == 5 and sums[1].successes == 4)

	-- 같은 seed면 같은 결과. 작은 표본(2명, 3층까지)으로 두 번 돌린다.
	-- ⚠️ noYield = true. MODEL을 바꾼 채 yield하면 같은 Play의 리포트가 그 값으로 계산한다
	--    (SuccessRateReport.runBand 주석). 이 테스트 파일은 처음부터 끝까지 yield하지 않아야 한다.
	local savedMin, savedMax = MODEL.ADVANCE_THRESHOLD_MIN, MODEL.ADVANCE_THRESHOLD_MAX
	local a = SuccessRateReport.runBand(bands[3], 2, 3, true)
	local b = SuccessRateReport.runBand(bands[3], 2, 3, true)
	local same = #a.segments == #b.segments and a.medianFinalMin == b.medianFinalMin and a.reached == b.reached
	for i, seg in ipairs(a.segments) do
		local other = b.segments[i]
		if other == nil or other.attempts ~= seg.attempts or other.successes ~= seg.successes then
			same = false
		end
	end
	check("runBand: 같은 seed → 같은 결과", same)
	check("runBand: 끝나면 MODEL 문턱이 원래대로",
		MODEL.ADVANCE_THRESHOLD_MIN == savedMin and MODEL.ADVANCE_THRESHOLD_MAX == savedMax)
	check("runBand: 플레이어 수 기록", a.players == 2)
end

-- 12. 운동기구 훈련 ------------------------------------------------------------------------
do
	local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
	local p = SuccessRateReport.newPlayer(Random.new(7))
	local before = BigNum.new(p.strength.m, p.strength.e)
	check("환생 0이면 기구를 못 쓴다", SuccessRateReport.trainAtGym(p, 30) == 0)
	check("기구를 못 쓰면 힘·시간 그대로", BigNum.eq(p.strength, before) and p.elapsedSec == 0)

	p.rebirths = GymConfig.getUnlockRebirths(1)
	local t0 = p.elapsedSec
	check("기구 1 조건이면 기구 1을 쓴다", SuccessRateReport.trainAtGym(p, 30) == 1)
	check("훈련 시간이 경과 시간에 더해진다", checkClose(p.elapsedSec - t0, 30))

	-- 같은 클릭 수를 기구 없이 넣은 것보다 정확히 기구 배수만큼 더 오른다.
	local a = SuccessRateReport.newPlayer(Random.new(8))
	a.rebirths = GymConfig.getUnlockRebirths(1)
	local b = SuccessRateReport.newPlayer(Random.new(8))
	b.rebirths = GymConfig.getUnlockRebirths(1)
	local base = BigNum.new(a.strength.m, a.strength.e)
	SuccessRateReport.trainAtGym(a, 10)
	-- 기구 없는 같은 클릭 수의 힘은 시뮬레이터와 같은 식(ClickService.computeGain)으로 따로 계산해 비율로 본다.
	local gainA = BigNum.sub(a.strength, base)
	local clicks = math.floor(a.clickRate * 10)
	local padPower = ClickPadConfig.getPadPower(1, a.padIndex)
	local mult = StrengthMultiplier.compute({ rebirths = a.rebirths })
	local plain = BigNum.mul(BigNum.mul(padPower, BigNum.fromNumber(clicks)), mult)
	check("기구 클릭 힘 = 기구 없는 클릭 힘 × 기구 배수",
		checkClose(BigNum.toRatio(gainA, plain), GymConfig.getMultiplier(1)),
		tostring(BigNum.toRatio(gainA, plain)))
	check("훈련 0초면 아무것도 안 한다", SuccessRateReport.trainAtGym(b, 0) == 0)

	-- 공허 구매자: 환생 0이어도 공허를 쓴다. ⚠️ MODEL을 바꾼 채 yield하지 않는다(runBand noYield와 같은 이유).
	local void = GymConfig.findByGamepass("voidTrainingZone")
	check("결정 모델은 공허를 사지 않는다", SuccessRateReport.MODEL.OWNS_VOID_ZONE == false)
	local c = SuccessRateReport.newPlayer(Random.new(9))
	local savedOwns = SuccessRateReport.MODEL.OWNS_VOID_ZONE
	SuccessRateReport.MODEL.OWNS_VOID_ZONE = true
	local usedVoid = SuccessRateReport.trainAtGym(c, 10)
	SuccessRateReport.MODEL.OWNS_VOID_ZONE = savedOwns
	check("공허 구매자는 환생 0이어도 공허를 쓴다", void ~= nil and usedVoid == void, tostring(usedVoid))
end

-- 업그레이드 (S5 — 지시서 #7) ------------------------------------------------------------------
do
	check("결정 모델 업그레이드 규칙 = s5", SuccessRateReport.MODEL.UPGRADE_POLICY == "s5", tostring(SuccessRateReport.MODEL.UPGRADE_POLICY))
	local fresh = SuccessRateReport.newPlayer(Random.new(10))
	local allZero = true
	local n = 0
	for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		n += 1
		if fresh.upgrades[name] ~= 0 then
			allZero = false
		end
	end
	check("새 플레이어: 노출 항목 전부 레벨 0 (지시서 #10부터 칭호 행운 포함)", allZero and n == #UpgradeConfig.SHOP_ORDER and n > 0)
	check("효과는 UpgradeConfig.getEffect 그대로", SuccessRateReport.effect({ punchSpeed = 5 }, "punchSpeed") == UpgradeConfig.getEffect("punchSpeed", 5))

	-- 예산이 가장 싼 것보다 작으면 아무것도 안 산다
	local TARGETS = SuccessRateReport.S5_TARGETS
	check("S5': 구매 대상 = 1차 4종 (행운 업그레이드 제외 — 지시서 #11)", table.concat(TARGETS, ",") == "punchDamage,punchSpeed,moveSpeed,bloxGain")
	local cheapest = UpgradeConfig.getCostAtLevel(TARGETS[1], 0)
	for _, name in ipairs(TARGETS) do
		local c = UpgradeConfig.getCostAtLevel(name, 0)
		if BigNum.lt(c, cheapest) then
			cheapest = c
		end
	end
	local l0 = SuccessRateReport.newUpgradeLevels()
	local spent0, count0 = SuccessRateReport.buyCheapestFirst(l0, BigNum.sub(cheapest, BigNum.fromNumber(1)))
	check("S5: 예산 < 가장 싼 값이면 0개", count0 == 0 and BigNum.eq(spent0, BigNum.new(0, 0)))

	-- 가장 싼 것부터: 매번 지금 레벨 기준으로 제일 싼 항목을 산다 → 쓴 양 ≤ 예산, 남은 예산으로는 아무것도 못 산다
	local levels = SuccessRateReport.newUpgradeLevels()
	local budget = BigNum.fromNumber(999)
	local spent, count = SuccessRateReport.buyCheapestFirst(levels, budget)
	check("S5: 쓴 양 ≤ 예산", BigNum.lte(spent, budget), BigNum.tostring(spent))
	local left = BigNum.sub(budget, spent)
	local canMore = false
	for _, name in ipairs(TARGETS) do
		if UpgradeConfig.canBuy(name, levels[name], left) then
			canMore = true
		end
	end
	check("S5: 남은 예산으로 더 살 수 있는 것이 없다", not canMore and count > 0, string.format("count=%d left=%s", count, BigNum.tostring(left)))
	local sumLevels = 0
	for _, name in ipairs(TARGETS) do
		sumLevels += levels[name]
	end
	check("S5: 산 횟수 = 레벨 합", sumLevels == count)
	check("S5': 행운 업그레이드는 사지 않는다", (levels.titleLuck or 0) == 0 and (levels.auraLuck or 0) == 0)

	-- 최대 레벨 항목은 건너뛴다
	local maxed = SuccessRateReport.newUpgradeLevels()
	maxed.punchSpeed = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number
	SuccessRateReport.buyCheapestFirst(maxed, BigNum.fromNumber(999))
	check("S5: 최대 레벨 항목은 더 안 산다", maxed.punchSpeed == UpgradeConfig.Upgrades.punchSpeed.maxLevel)

	-- 예산 = 환생하면 버려질 나머지
	check("getLeftover: 1999 → 999", BigNum.eq(RebirthConfig.getLeftover(BigNum.fromNumber(1999)), BigNum.fromNumber(999)))
	check("getLeftover: 500 → 500 (환생 못 해도 전부 나머지)", BigNum.eq(RebirthConfig.getLeftover(BigNum.fromNumber(500)), BigNum.fromNumber(500)))
	check("getLeftover: 3000 → 0", BigNum.eq(RebirthConfig.getLeftover(BigNum.fromNumber(3000)), BigNum.new(0, 0)))
	check("getLeftover: 아주 크면 0 이상(음수 잡음 없음)", RebirthConfig.getLeftover(BigNum.new(1.234567, 30)).m >= 0)

	-- 업그레이드 TEMP 후보 스윕: 갈아끼운 값은 끝나면 되돌아온다
	local before = UpgradeConfig.Upgrades.punchDamage.effectPerLevel
	local seen: number? = nil
	SuccessRateReport.withUpgradeOverride({ punchDamage = { effectPerLevel = 0.5 } }, function()
		seen = UpgradeConfig.Upgrades.punchDamage.effectPerLevel
	end)
	check("withUpgradeOverride: 안에서는 바뀐 값", seen == 0.5)
	check("withUpgradeOverride: 끝나면 원래 값", UpgradeConfig.Upgrades.punchDamage.effectPerLevel == before)
	local okErr = pcall(SuccessRateReport.withUpgradeOverride, { punchDamage = { costGrowth = 1 } }, function() end)
	check("withUpgradeOverride: 규약 위반 후보는 에러 + 되돌림", not okErr and UpgradeConfig.Upgrades.punchDamage.costGrowth > 1)
	check("업그레이드 스윕 단독 모드는 커밋 값 false", SuccessRateReport.SIM.UPGRADE_SWEEP_ONLY == false)

	-- 걷는 동안 클릭 (지시서 #8 진단 스위치). 결정 모델은 true, false면 걷기는 시간만 더한다.
	check("결정 모델: 걷는 동안 클릭한다", SuccessRateReport.MODEL.CLICK_WHILE_WALKING == true)
	local walker = SuccessRateReport.newPlayer(Random.new(11))
	local before = walker.strength
	SuccessRateReport.MODEL.CLICK_WHILE_WALKING = false
	local ok, sec = pcall(SuccessRateReport.walkToGate, walker)
	SuccessRateReport.MODEL.CLICK_WHILE_WALKING = true
	check("걷는 동안 클릭 없음: 힘 그대로 · 시간은 더한다", ok and BigNum.eq(walker.strength, before) and checkClose(walker.elapsedSec, sec :: number))
end

-- 칭호 행동 모델 S7 (지시서 #10 6단계) --------------------------------------------------------------
do
	local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
	local T = TitleConfig.Titles
	local N = #T
	check("결정 모델 칭호 규칙 = s7 · 자동 롤 기준 10%", MODEL.TITLE_POLICY == "s7" and MODEL.TITLE_AUTO_SHARE == 0.10)
	check("칭호 스윕 단독 모드는 커밋 값 false", SuccessRateReport.SIM.TITLE_SWEEP_ONLY == false)

	local p = SuccessRateReport.newPlayer(Random.new(5))
	check("새 플레이어: 칭호 없음 · 자동 롤 끔 · 배수 1", p.titleIndex == 0 and p.autoRoll == false and SuccessRateReport.titleMult(p) == 1)
	p.titleIndex = N
	check("칭호 배수 = TitleConfig 값", SuccessRateReport.titleMult(p) == T[N].mult)
	MODEL.TITLE_POLICY = "none"
	local noneMult = SuccessRateReport.titleMult(p)
	MODEL.TITLE_POLICY = "s7"
	check("칭호 없음 모델에서는 배수 1", noneMult == 1)

	-- 자동 롤 켜기 판단: 비용 ≤ 벌이 × 10%
	local cost = SuccessRateReport.autoRollCostPerSec()
	local q = SuccessRateReport.newPlayer(Random.new(6))
	SuccessRateReport.decideAutoRoll(q)
	check("판단 재료가 없으면 그대로(끔)", q.autoRoll == false)
	local runSec = 10
	local atThreshold = BigNum.mul(BigNum.div(cost, BigNum.fromNumber(MODEL.TITLE_AUTO_SHARE)), BigNum.fromNumber(runSec))
	q.lastRunReward, q.lastRunSec, q.lastBest = BigNum.mul(atThreshold, BigNum.fromNumber(1.001)), runSec, 7
	q.elapsedSec = 120
	SuccessRateReport.decideAutoRoll(q)
	check("벌이가 기준 바로 위 → 켠다 · 켠 시각 · 층 기록", q.autoRoll and q.autoOnSec == 120 and q.autoOnStage == 7)
	q.lastRunReward = BigNum.mul(atThreshold, BigNum.fromNumber(0.999))
	SuccessRateReport.decideAutoRoll(q)
	check("벌이가 기준 바로 아래 → 끈다 · 처음 켠 시각은 남는다", not q.autoRoll and q.autoOnSec == 120)
	q.lastRunReward = BigNum.new(0, 0)
	q.autoRoll = true
	SuccessRateReport.decideAutoRoll(q)
	check("실패한 런(보상 0)으로는 바꾸지 않는다", q.autoRoll == true)

	-- 자동 롤 지출 · 장착
	local r = SuccessRateReport.newPlayer(Random.new(7))
	r.autoRoll = true
	r.titleRandom = function()
		return 0 -- 가장 높은 등급부터 걸린다
	end
	r.blox = BigNum.mul(TitleConfig.ROLL_COST, BigNum.fromNumber(3.5))
	local rolled = SuccessRateReport.spendAutoRolls(r, TitleConfig.ROLL_INTERVAL_SEC * 5)
	check("자동 롤: 간격 5개 · 돈은 3.5회분 → 3회만 굴리고 남은 틱은 건너뛴다", rolled == 3 and r.titleRolls == 3,
		tostring(rolled))
	check("자동 롤: 지갑에서 뺀다", BigNum.eq(r.blox, BigNum.mul(TitleConfig.ROLL_COST, BigNum.fromNumber(0.5))))
	check("자동 롤: 더 높은 등급 → 장착", r.titleIndex == N)
	r.titleRandom = function()
		return 0.999999 -- 폴백
	end
	r.blox = BigNum.mul(TitleConfig.ROLL_COST, BigNum.fromNumber(2))
	SuccessRateReport.spendAutoRolls(r, TitleConfig.ROLL_INTERVAL_SEC * 2)
	check("자동 롤: 낮은 결과로 장착이 내려가지 않는다", r.titleIndex == N)
	local half = SuccessRateReport.newPlayer(Random.new(8))
	half.autoRoll, half.titleRandom, half.blox = true, r.titleRandom, BigNum.fromNumber(1e6)
	check("자동 롤: 간격 반 개는 다음으로 넘긴다", SuccessRateReport.spendAutoRolls(half, TitleConfig.ROLL_INTERVAL_SEC * 0.5) == 0
		and SuccessRateReport.spendAutoRolls(half, TitleConfig.ROLL_INTERVAL_SEC * 0.5) == 1)
	local off = SuccessRateReport.newPlayer(Random.new(9))
	off.titleRandom, off.blox = r.titleRandom, BigNum.fromNumber(1e6)
	check("자동 롤 끔이면 굴리지 않는다", SuccessRateReport.spendAutoRolls(off, 100) == 0)

	-- 칭호 배수가 클릭 힘과 수령액에 한 번씩 들어간다
	local function walkGain(index: number): BigNum.BigNumber
		local w = SuccessRateReport.newPlayer(Random.new(12))
		w.titleIndex = index
		local before = w.strength
		SuccessRateReport.walkToGate(w)
		return BigNum.sub(w.strength, before)
	end
	local plain, titled = walkGain(0), walkGain(N)
	check("클릭 힘: 칭호 배수만큼 (한 번)", math.abs(BigNum.toRatio(titled, plain) - T[N].mult) < 0.05,
		string.format("%.4f vs %.4f", BigNum.toRatio(titled, plain), T[N].mult))

	local function cashoutReward(index: number): BigNum.BigNumber
		local c = SuccessRateReport.newPlayer(Random.new(13))
		c.strength = BigNum.new(1, 300)
		c.advanceThreshold = 2 -- 절대 진행하지 않는다 → 1층 수령
		c.titleIndex = index
		local before = c.blox
		withoutRunClicks(function()
			SuccessRateReport.runOnce(c, Random.new(14), {}, {})
		end)
		return BigNum.sub(c.blox, before)
	end
	local base, boosted = cashoutReward(0), cashoutReward(N)
	check("수령액: 층 보상 × 칭호 배수 (한 번)", math.abs(BigNum.toRatio(boosted, base) - T[N].mult) < 1e-9,
		string.format("%.6f", BigNum.toRatio(boosted, base)))

	-- 배수 후보 갈아끼우기: 끝나면 되돌린다 · 권한 밖(최고 > 3.0)은 거부
	local orig = T[N].mult
	local seenTop: number? = nil
	local cand = {}
	for i, def in ipairs(T) do
		cand[i] = def.mult
	end
	cand[N] = 2.5
	SuccessRateReport.withTitleMults(cand, function()
		seenTop = T[N].mult
	end)
	check("withTitleMults: 안에서는 후보 값 · 끝나면 원래 값", seenTop == 2.5 and T[N].mult == orig)
	cand[N] = 3.5
	local okBig = pcall(SuccessRateReport.withTitleMults, cand, function() end)
	check("withTitleMults: 최고 ×3.0 초과 후보는 거부 + 되돌림", not okBig and T[N].mult == orig)
end

-- 아우라 행동 모델 A4 (지시서 #11 6단계) ---------------------------------------------------------------
do
	local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
	local AttackService = require(ServerScriptService.Server.Systems.AttackService)
	local P1, P2 = AuraConfig.Packs[1], AuraConfig.Packs[2]
	check("결정 모델 아우라 규칙 = a4 · 환생 직전 20%", MODEL.AURA_POLICY == "a4" and MODEL.AURA_REBIRTH_SHARE == 0.20)
	check("아우라 스윕 단독 모드는 커밋 값 false", SuccessRateReport.SIM.AURA_SWEEP_ONLY == false)

	local p = SuccessRateReport.newPlayer(Random.new(21))
	check("새 플레이어: 아우라 없음 · m 1", p.auraId == nil and SuccessRateReport.auraMult(p) == 1)
	p.auraRandom = function()
		return 0 -- 가장 높은 등급
	end
	p.lifetimeBlox = P2.rollCost -- 팩 1 · 2 열림
	p.blox = BigNum.mul(P2.rollCost, BigNum.fromNumber(10)) -- 20% = 팩 2 두 번
	local before = p.blox
	local n = SuccessRateReport.spendAuraBeforeRebirth(p)
	check("A4: 해금된 가장 높은 팩(2)을 20%로 닿는 만큼 (2회)", n == 2 and BigNum.eq(p.blox, BigNum.sub(before, BigNum.mul(P2.rollCost, BigNum.fromNumber(2)))))
	check("A4: 더 높은 m → 장착", p.auraId == P2.auras[4].id and SuccessRateReport.auraMult(p) == P2.auras[4].mult)
	check("A4: 팩 첫 롤 시각 기록", p.packFirstSec[2] ~= nil)
	p.auraRandom = function()
		return 0.999999 -- 일반(폴백)
	end
	SuccessRateReport.spendAuraBeforeRebirth(p)
	check("A4: 낮은 결과로 장착이 내려가지 않는다", p.auraId == P2.auras[4].id)
	local poor = SuccessRateReport.newPlayer(Random.new(22))
	poor.auraRandom = p.auraRandom
	poor.lifetimeBlox = P1.rollCost
	poor.blox = BigNum.mul(P1.rollCost, BigNum.fromNumber(4.9)) -- 20%는 1회분 미만
	check("A4: 20%가 롤 비용 미만이면 굴리지 않는다", SuccessRateReport.spendAuraBeforeRebirth(poor) == 0 and BigNum.eq(poor.blox, BigNum.mul(P1.rollCost, BigNum.fromNumber(4.9))))
	local locked = SuccessRateReport.newPlayer(Random.new(23))
	locked.auraRandom = p.auraRandom
	locked.blox = BigNum.new(1, 30)
	check("A4: 열린 팩이 없으면 굴리지 않는다", SuccessRateReport.spendAuraBeforeRebirth(locked) == 0)
	MODEL.AURA_POLICY = "none"
	local noneN = SuccessRateReport.spendAuraBeforeRebirth(p)
	local noneM = SuccessRateReport.auraMult(p)
	MODEL.AURA_POLICY = "a4"
	check("아우라 없음 모델: 굴리지 않고 m 1", noneN == 0 and noneM == 1)

	-- m이 클릭 힘과 1펀치 데미지에 한 번씩 (A10 — 게임과 같은 함수)
	local function walkGain(auraId: string?): BigNum.BigNumber
		local w = SuccessRateReport.newPlayer(Random.new(24))
		w.auraId = auraId
		local s0 = w.strength
		SuccessRateReport.walkToGate(w)
		return BigNum.sub(w.strength, s0)
	end
	local m = P2.auras[4].mult
	check("클릭 힘: m만큼 (한 번)", math.abs(BigNum.toRatio(walkGain(P2.auras[4].id), walkGain(nil)) - m) < 0.05)
	-- 1펀치: 힘 1에 HP가 m 펀치분인 층은 아우라 없이 실패, 있으면 1펀치(같은 시드)
	local q = SuccessRateReport.newPlayer(Random.new(25))
	q.auraId = P2.auras[4].id
	q.strength = BigNum.fromNumber(1)
	local hp = StageConfig.getTotalHp(1)
	q.strength = BigNum.div(hp, BigNum.fromNumber(m * 0.999))
	local outcome
	withoutRunClicks(function()
		outcome = SuccessRateReport.simulateStage(q, 1, 0, 0)
	end)
	check("1펀치 데미지: 힘 × m (한 번) — HP를 힘 × m 바로 아래로 두면 1펀치에 깬다", outcome.cleared and outcome.punches == 1)
	check("결합 함수는 게임과 같다", AttackService.combineDamageMultiplier({ punchDamage = 1, auraMult = m }) == m)

	-- 후보 갈아끼우기: 끝나면 되돌린다 · G4 위반 후보는 거부
	local orig = P1.auras[4].mult
	local seen: number? = nil
	SuccessRateReport.withAuraParams({ 1.02, 1.04, 1.06, 1.08 }, 1.5, function()
		seen = AuraConfig.Packs[1].auras[4].mult
	end)
	check("withAuraParams: 안에서는 후보 · 끝나면 원래", seen == 1.08 and AuraConfig.Packs[1].auras[4].mult == orig)
	local okBad = pcall(SuccessRateReport.withAuraParams, nil, 1.01, function() end)
	check("withAuraParams: G4 위반(비율 1.01) 거부 + 되돌림", not okBad and AuraConfig.Packs[2].auras[1].mult > AuraConfig.Packs[1].auras[4].mult)
end

print(string.format("[SuccessRateReportTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SuccessRateReportTests] %d test(s) failed", failed))
end

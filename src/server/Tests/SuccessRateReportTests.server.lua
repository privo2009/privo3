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
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
local SuccessRateReport = require(ServerScriptService.Server.Tools.SuccessRateReport)

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

print(string.format("[SuccessRateReportTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SuccessRateReportTests] %d test(s) failed", failed))
end

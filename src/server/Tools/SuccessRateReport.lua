--!strict
-- 확률적 플레이어 성공률 시뮬레이터 (Phase 4-2-f). "층별 첫 도달 성공률이 목표 범위에 드는가"에
-- 답할 숫자를 뽑는다. DESIGN.md "목표 성공률 > 측정 규약"의 시뮬레이션 우선 원칙을 따른다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다 — Config만 읽고
--    순수 계산 후 print한다. 켠 채로 커밋해도 어떤 계정도 오염되지 않는다.
--
-- ===== StandardPathReport와 무엇이 다른가 ==============================================
--
-- StandardPathReport는 결정론 + 완전 정보다 — "깰 수 있는 층만 들어간다"라서 성공률이
-- 항상 0 아니면 1이고, 시간 축(몇 분에 몇 층)만 답한다. 이 리포트는 플레이어를 확률로 둔다:
--
--   클릭 속도        플레이어마다 MODEL.CLICK_RATE_MIN~MAX 균등 무작위
--   반경 밖 시간     층마다 0~MODEL.OUT_OF_RADIUS_MAX_SEC 균등 무작위 (층 시작에 몰아 둔다)
--   런 중 클릭       평소 속도 × MODEL.RUN_CLICK_FACTOR
--   진행 판단        직전 층을 남은 시간 ≥ (타이머 × 문턱)으로 깼으면 진행, 아니면 수령.
--                    문턱은 플레이어마다 MODEL.ADVANCE_THRESHOLD_MIN~MAX 균등 무작위
--
-- 위 네 모델 값은 2026-10-21 사람 결정이다(4-2-f 플레이어 모델). 바꾸려면 사람 결정을 받는다.
-- 그래서 SIM(관측 해상도)과 MODEL(플레이어 가정)을 다른 테이블에 둔다.
--
-- 성공률 = 그 층에 **처음 들어간** 시도 중 클리어한 비율 (플레이어 전체 합산).
-- 같은 층의 두 번째 이후 시도는 세지 않는다 — "처음 도달했을 때"가 측정 규약이다.
--
-- ===== 게임 코드와 같은 식을 쓴다 =====================================================
--
--   클릭 획득   padPower × 클릭수 × 배수   (ClickService.computeGain과 같은 식)
--   배수 결합   StrengthMultiplier.compute
--   1회 데미지  힘 그대로                   (AttackService.computePunchDamage)
--   펀치 간격   1 / AttackConfig.PUNCH_SPEED_BASE
--   걷기        스폰 → 입장 게이트 거리(ArenaConfig.getSpawnToEntrance) ÷ LevelConfig.getMaxSpeed(힘)
--               런은 게이트에서 서므로(DESIGN.md "런 시작") 걷는 시간은 20초 밖이고, 그동안은
--               평소 속도로 클릭한다. 수령·실패 뒤에는 스폰으로 돌아오므로 런마다 한 번 걷는다
--
-- ⚠️ 펀치 속도를 1회 데미지에 곱하지 않는다 (CLAUDE.md 금지 사항). 속도는 간격으로만 들어간다.
--
-- ===== 재지 않는 것 ===================================================================
--
--   - 클리어 뒤 진행 벽까지 걷는 시간·클리어 대기 중 클릭. 클리어한 런은 만료되지 않으므로
--     실제 유저는 클리어 후 서서 힘을 더 모을 수 있다 — 여기서는 즉시 판단한다고 본다
--   - 워프·뽑기·게임패스·드론. 무과금 표준 플레이어다
--   - 환생 시점 판단은 StandardPathReport와 같은 "정체" 규칙에 인내심(SIM.REBIRTH_PATIENCE_RUNS)을
--     붙였다. 확률 모델에서는 한 번 운 나쁜 런으로 정체가 되기 때문이다
--
-- 사용: Bootstrap의 SUCCESS_RATE_REPORT_ENABLED 블록이 부른다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local Schema = require(script.Parent.Parent.Data.Schema)

type BigNumber = BigNum.BigNumber

local SuccessRateReport = {}

-- ===== 플레이어 모델 (사람 결정 2026-10-21) ===========================================
--
-- ⚠️ 게임 밸런스 값이 아니라 "유저가 어떻게 논다고 보는가"다. 하지만 성공률을 직접 움직이므로
--    판정 기준과 같은 무게다 — 임의로 바꾸지 말 것.
local MODEL = {
	-- 클릭 속도(회/초). 실측 한 손가락 약 6, 수동 상한 ClickService.MANUAL_CLICK_LIMIT 10.
	CLICK_RATE_MIN = 6,
	CLICK_RATE_MAX = 10,

	-- 층마다 반경 밖에 있는 시간(초)의 상한. 0~이 값 균등.
	-- 게이트 중앙으로 들어가면 이미 반경 안이라(VERIFY_CHALLENGE 실측) 구조적 손해는 0이고,
	-- 이 값은 가장자리 진입·잠깐 벗어남 같은 조작 편차다.
	OUT_OF_RADIUS_MAX_SEC = 2,

	-- 런 중 클릭 속도 = 평소 × 이 값. 블록 곁을 지키느라 신경이 나뉜다는 가정.
	RUN_CLICK_FACTOR = 0.5,

	-- 진행 문턱 = 타이머 대비 남은 시간 비율. 직전 층을 이 비율 이상 남기고 깼으면 진행.
	ADVANCE_THRESHOLD_MIN = 0.10,
	ADVANCE_THRESHOLD_MAX = 0.50,

	-- 진행 판단 규칙. "time_left"가 사람 결정(위 문턱). "growth_aware"는 비교용 변형이다 —
	-- 다음 층 HP 배율 r에서 같은 DPS로 깰 수 있는 손익분기 남은 비율 1 - 1/r에 플레이어별
	-- 편차 ±ADVANCE_NOISE를 더한 문턱을 쓴다(r은 StageConfig에서 읽는다 — 새 숫자 없음).
	ADVANCE_RULE = "time_left",
	ADVANCE_NOISE = 0,
}
SuccessRateReport.MODEL = MODEL

-- ===== 시뮬레이터 파라미터 ===========================================================
--
-- ⚠️ 관측 해상도와 중단 조건이다. 바꿔도 게임도 플레이어 가정도 변하지 않는다.
local SIM = {
	PLAYERS = 200,
	SEED = 20261021,
	WORLD_ID = 1,

	-- 플레이어 한 명의 중단 조건. 최고층 첫 시도가 기록되면 그 전에 끝난다.
	MAX_RUNS_PER_PLAYER = 3000,
	MAX_SIM_SEC_PER_PLAYER = 6 * 3600,

	-- 이번 생애 최고층을 이 런 수 동안 못 넘기면 정체로 보고 환생한다(환생 가능할 때).
	REBIRTH_PATIENCE_RUNS = 3,

	-- 서버 스크립트 시간 초과를 피하려고 이 런 수마다 한 번 양보한다.
	YIELD_EVERY_RUNS = 200,
}
SuccessRateReport.SIM = SIM

-- ===== 상태 =========================================================================

export type Player = {
	clickRate: number,
	advanceThreshold: number,
	advanceNoise: number,
	strength: BigNumber,
	blox: BigNumber,
	lifetimeBlox: BigNumber,
	rebirths: BigNumber,
	padIndex: number,
	elapsedSec: number,
	runCount: number,
	rebirthCount: number,
}

local function copyBig(v: BigNumber): BigNumber
	return BigNum.new(v.m, v.e)
end

function SuccessRateReport.newPlayer(rng: Random): Player
	local template = Schema.new()
	return {
		clickRate = rng:NextNumber(MODEL.CLICK_RATE_MIN, MODEL.CLICK_RATE_MAX),
		advanceThreshold = rng:NextNumber(MODEL.ADVANCE_THRESHOLD_MIN, MODEL.ADVANCE_THRESHOLD_MAX),
		advanceNoise = rng:NextNumber(-MODEL.ADVANCE_NOISE, MODEL.ADVANCE_NOISE),
		strength = copyBig(template.strength),
		blox = copyBig(template.blox),
		lifetimeBlox = copyBig(template.lifetimeBlox),
		rebirths = copyBig(template.rebirths),
		padIndex = ClickPadConfig.getUnlockedPadCount(SIM.WORLD_ID, template.lifetimeBlox),
		elapsedSec = 0,
		runCount = 0,
		rebirthCount = 0,
	}
end

-- 클릭 n번만큼 힘을 올린다. ClickService.computeGain과 같은 식.
local function addClicks(p: Player, clicks: number)
	if clicks <= 0 then
		return
	end
	local padPower = ClickPadConfig.getPadPower(SIM.WORLD_ID, p.padIndex)
	local multiplier = StrengthMultiplier.compute({ rebirths = p.rebirths })
	local gain = BigNum.mul(BigNum.mul(padPower, BigNum.fromNumber(clicks)), multiplier)
	p.strength = BigNum.add(p.strength, gain)
end

-- 스폰 → 입장 게이트. 걷는 동안 평소 속도로 클릭한다. 걸린 초를 돌려준다.
function SuccessRateReport.walkToGate(p: Player): number
	local speed = LevelConfig.getMaxSpeed(p.strength)
	local sec = ArenaConfig.getSpawnToEntrance() / speed
	addClicks(p, math.floor(p.clickRate * sec))
	p.elapsedSec += sec
	return sec
end

-- ===== 한 층 =========================================================================
--
-- 이벤트 단위로 돈다 — 틱이 아니라 펀치마다 한 번. 펀치 사이에 쌓인 클릭을 먼저 힘에 더하고
-- 그 힘으로 때린다. 첫 펀치 시각 = 반경 밖 시간 + 펀치 위상(0~간격 균등).
--
-- 반환: 클리어 여부, 남은 시간(클리어면 그 순간, 실패면 0). 플레이어 상태는 제자리에서 바뀐다
-- (실패해도 런 중 클릭으로 자란 힘은 남는다 — ClickService는 런과 무관하다).
export type StageOutcome = { cleared: boolean, timeLeft: number, punches: number }

function SuccessRateReport.simulateStage(p: Player, stage: number, outOfRadiusSec: number, phase: number): StageOutcome
	local timer = StageConfig.CHALLENGE_TIMER_SEC
	local interval = 1 / AttackConfig.PUNCH_SPEED_BASE
	local runClickRate = p.clickRate * MODEL.RUN_CLICK_FACTOR

	local remaining = StageConfig.getTotalHp(stage)
	local zero = BigNum.new(0, 0)

	local t = 0
	local clickCarry = 0
	local nextPunch = outOfRadiusSec + phase
	local punches = 0

	while nextPunch <= timer do
		clickCarry += runClickRate * (nextPunch - t)
		local clicks = math.floor(clickCarry)
		clickCarry -= clicks
		addClicks(p, clicks)
		t = nextPunch

		remaining = BigNum.sub(remaining, p.strength)
		punches += 1
		if BigNum.lte(remaining, zero) then
			p.elapsedSec += t
			return { cleared = true, timeLeft = timer - t, punches = punches }
		end
		nextPunch += interval
	end

	-- 실패: 남은 시간 동안의 클릭도 힘에 들어간다.
	clickCarry += runClickRate * (timer - t)
	addClicks(p, math.floor(clickCarry))
	p.elapsedSec += timer
	return { cleared = false, timeLeft = 0, punches = punches }
end

-- ===== 한 런 =========================================================================
--
-- firstTry[stage] = { attempts, successes } 에 "처음 들어간 시도"만 더한다.
-- seen[stage]는 이 플레이어가 그 층에 들어간 적이 있는가.
export type Tally = { attempts: number, successes: number }

local function tally(firstTry: { [number]: Tally }, seen: { [number]: boolean }, stage: number, cleared: boolean)
	if seen[stage] then
		return
	end
	seen[stage] = true
	local t = firstTry[stage]
	if t == nil then
		t = { attempts = 0, successes = 0 }
		firstTry[stage] = t
	end
	t.attempts += 1
	if cleared then
		t.successes += 1
	end
end

-- 직전 층을 남은 시간 timeLeft로 깼을 때 다음 층에 들어가는가.
function SuccessRateReport.wantsAdvance(p: Player, stage: number, timeLeft: number): boolean
	local timer = StageConfig.CHALLENGE_TIMER_SEC
	if MODEL.ADVANCE_RULE == "growth_aware" then
		local r = BigNum.toRatio(StageConfig.getTotalHp(stage + 1), StageConfig.getTotalHp(stage))
		return timeLeft >= timer * (1 - 1 / r + p.advanceNoise)
	end
	return timeLeft >= timer * p.advanceThreshold
end

-- 돌려주는 값: 이번 런에서 클리어한 최고층(0 = 1층도 못 깸).
local function runOnce(p: Player, rng: Random, firstTry: { [number]: Tally }, seen: { [number]: boolean }): number
	p.runCount += 1
	SuccessRateReport.walkToGate(p)

	local interval = 1 / AttackConfig.PUNCH_SPEED_BASE
	local stage = 1
	local best = 0

	while true do
		local out = rng:NextNumber(0, MODEL.OUT_OF_RADIUS_MAX_SEC)
		local phase = rng:NextNumber(0, interval)
		local outcome = SuccessRateReport.simulateStage(p, stage, out, phase)
		tally(firstTry, seen, stage, outcome.cleared)

		if not outcome.cleared then
			return best -- 실패: 보상 0, 스폰 복귀
		end
		best = stage

		local nextExists = StageConfig.hasStage(stage + 1)
		if not (nextExists and SuccessRateReport.wantsAdvance(p, stage, outcome.timeLeft)) then
			break
		end
		stage += 1
	end

	-- 수령. 보상은 갱신이라 도달한 층의 값 하나만 받는다.
	local reward = StageConfig.getBloxReward(best)
	p.blox = BigNum.add(p.blox, reward)
	p.lifetimeBlox = BigNum.add(p.lifetimeBlox, reward)
	p.padIndex = ClickPadConfig.getUnlockedPadCount(SIM.WORLD_ID, p.lifetimeBlox)
	return best
end

-- RebirthService와 같은 대상: blox 0, 힘 초기값, rebirths 누적. lifetimeBlox·패드 유지.
local function rebirth(p: Player)
	p.rebirths = BigNum.add(p.rebirths, RebirthConfig.getGainedRebirths(p.blox))
	p.blox = BigNum.new(0, 0)
	p.strength = copyBig(Schema.new().strength)
	p.rebirthCount += 1
end

export type PlayerResult = {
	reachedFinal: boolean,
	finalFirstSec: number?, -- 최고층에 처음 들어간 시각
	runs: number,
	rebirths: number,
	maxStageSeen: number,
}

function SuccessRateReport.simulatePlayer(rng: Random, maxStage: number, firstTry: { [number]: Tally }): PlayerResult
	local p = SuccessRateReport.newPlayer(rng)
	local seen: { [number]: boolean } = {}
	local bestThisLife = 0
	local stale = 0
	local finalFirstSec: number? = nil

	while p.runCount < SIM.MAX_RUNS_PER_PLAYER and p.elapsedSec < SIM.MAX_SIM_SEC_PER_PLAYER do
		local before = p.elapsedSec
		local reached = runOnce(p, rng, firstTry, seen)
		if seen[maxStage] and finalFirstSec == nil then
			finalFirstSec = before
			break
		end

		if reached > bestThisLife then
			bestThisLife = reached
			stale = 0
		else
			stale += 1
		end
		if stale >= SIM.REBIRTH_PATIENCE_RUNS and RebirthConfig.canRebirth(p.blox) then
			rebirth(p)
			bestThisLife = 0
			stale = 0
		end

		if p.runCount % SIM.YIELD_EVERY_RUNS == 0 then
			task.wait()
		end
	end

	local maxSeen = 0
	for stage in pairs(seen) do
		maxSeen = math.max(maxSeen, stage)
	end
	return {
		reachedFinal = finalFirstSec ~= nil,
		finalFirstSec = finalFirstSec,
		runs = p.runCount,
		rebirths = p.rebirthCount,
		maxStageSeen = maxSeen,
	}
end

-- ===== 출력 =========================================================================

local function findLastStage(): number
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		stage += 1
	end
	return stage
end

local function hpSegments(): { WorldConfig.GrowthSegment }
	local world = WorldConfig.get(SIM.WORLD_ID)
	assert(world ~= nil, "SuccessRateReport: 월드가 없다")
	return (world :: WorldConfig.WorldDef).hpGrowthSegments
end

local function pct(t: Tally?): string
	if t == nil or t.attempts == 0 then
		return "     -"
	end
	return string.format("%5.1f%%", 100 * t.successes / t.attempts)
end

local function median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	table.sort(xs)
	local mid = math.floor((#xs + 1) / 2)
	return xs[mid]
end

-- 비교용 변형. ⚠️ 사람 결정 모델을 바꾸는 것이 아니라 "규칙이 결과를 얼마나 움직이는가"를
-- 옆에 놓고 보는 자리다. 첫 줄(빈 덮어쓰기)이 사람 결정 모델이고 표 전체를 찍는다.
local VARIANTS: { { label: string, override: { [string]: any } } } = {
	{ label = "결정 모델 (남은 시간 10~50%)", override = {} },
	{ label = "남은 시간 50~90%", override = { ADVANCE_THRESHOLD_MIN = 0.5, ADVANCE_THRESHOLD_MAX = 0.9 } },
	{ label = "배율 인식 ±0", override = { ADVANCE_RULE = "growth_aware", ADVANCE_NOISE = 0 } },
	{ label = "배율 인식 ±10%p", override = { ADVANCE_RULE = "growth_aware", ADVANCE_NOISE = 0.1 } },
	{ label = "배율 인식 ±20%p", override = { ADVANCE_RULE = "growth_aware", ADVANCE_NOISE = 0.2 } },
}

local function runModel(label: string, full: boolean)
	local maxStage = findLastStage()
	local rng = Random.new(SIM.SEED)
	local firstTry: { [number]: Tally } = {}
	local results: { PlayerResult } = {}

	local startedAt = os.clock()
	for _ = 1, SIM.PLAYERS do
		table.insert(results, SuccessRateReport.simulatePlayer(rng, maxStage, firstTry))
		task.wait()
	end
	local tookSec = os.clock() - startedAt

	print(string.format("[SUCCESSRATE] ----- %s -----", label))
	print(string.format(
		"[SUCCESSRATE] 모델: 클릭 %g~%g/초 · 반경 밖 0~%g초/층 · 런 중 클릭 ×%g · 규칙 %s (문턱 %g~%g%%, 편차 ±%g%%p)",
		MODEL.CLICK_RATE_MIN, MODEL.CLICK_RATE_MAX, MODEL.OUT_OF_RADIUS_MAX_SEC, MODEL.RUN_CLICK_FACTOR,
		MODEL.ADVANCE_RULE, MODEL.ADVANCE_THRESHOLD_MIN * 100, MODEL.ADVANCE_THRESHOLD_MAX * 100, MODEL.ADVANCE_NOISE * 100
	))
	print(string.format(
		"[SUCCESSRATE] 표본: 플레이어 %d · seed %d · 환생 인내 %d런 · 계산 %.1f초",
		SIM.PLAYERS, SIM.SEED, SIM.REBIRTH_PATIENCE_RUNS, tookSec
	))

	if full then
		print("[SUCCESSRATE] 층 | 첫 시도 | 성공 | 성공률")
		for stage = 1, maxStage do
			local t = firstTry[stage]
			print(string.format(
				"[SUCCESSRATE] %2d | %6d | %6d | %s",
				stage, t and t.attempts or 0, t and t.successes or 0, pct(t)
			))
		end
	end

	-- HP 세그먼트별 합산. 구간 경계는 WorldConfig에서 읽는다 — 목표 % 는 여기 적지 않는다
	-- (원본 DESIGN.md "목표 성공률" 표. 판정은 읽는 사람이 그 표와 대조한다).
	for _, seg in ipairs(hpSegments()) do
		local sum: Tally = { attempts = 0, successes = 0 }
		local lowest: number? = nil
		local highest: number? = nil
		for stage = seg.from, math.min(seg.to, maxStage) do
			local t = firstTry[stage]
			if t ~= nil and t.attempts > 0 then
				sum.attempts += t.attempts
				sum.successes += t.successes
				local r = t.successes / t.attempts
				lowest = if lowest == nil then r else math.min(lowest, r)
				highest = if highest == nil then r else math.max(highest, r)
			end
		end
		print(string.format(
			"[SUCCESSRATE] 구간 %2d~%2d층 (HP ×%.1f): 합산 %s · 층별 %s~%s · 시도 %d",
			seg.from, seg.to, seg.growth, pct(sum),
			if lowest ~= nil then string.format("%.1f%%", lowest * 100) else "-",
			if highest ~= nil then string.format("%.1f%%", highest * 100) else "-",
			sum.attempts
		))
	end

	local finals: { number } = {}
	local reached = 0
	local rebirthsSum = 0
	local runsSum = 0
	for _, r in ipairs(results) do
		if r.reachedFinal and r.finalFirstSec ~= nil then
			reached += 1
			table.insert(finals, r.finalFirstSec / 60)
		end
		rebirthsSum += r.rebirths
		runsSum += r.runs
	end
	local med = median(finals)
	print(string.format(
		"[SUCCESSRATE] %d층 첫 진입: %d/%d명 · 중앙값 %s분 · 평균 런 %.0f · 평균 환생 %.1f회",
		maxStage, reached, #results, if med ~= nil then string.format("%.1f", med) else "-",
		runsSum / #results, rebirthsSum / #results
	))
end

function SuccessRateReport.run()
	print("[SUCCESSRATE] ===== 확률적 플레이어 성공률 (4-2-f) =====")
	for i, variant in ipairs(VARIANTS) do
		local saved: { [string]: any } = {}
		for k, v in pairs(variant.override) do
			saved[k] = (MODEL :: any)[k]
			;(MODEL :: any)[k] = v
		end
		runModel(variant.label, i == 1)
		for k, v in pairs(saved) do
			(MODEL :: any)[k] = v
		end
	end
	print("[SUCCESSRATE] 끝.")
end

return SuccessRateReport

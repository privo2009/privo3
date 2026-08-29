--!strict
-- 표준 경로 시뮬레이터 (Phase 4-2-f). "17층 절벽이 실제로 유저를 막는가"에 답할 숫자를 뽑는다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다.
--    프로필을 읽지도 쓰지도 않는다 — Config만 읽고 순수 계산 후 print한다.
--    그래서 "측정 전 힘 초기화" 전제와 무관하고(→ DESIGN.md "Play 측정 항목"),
--    켠 채로 커밋해도 어떤 계정도 오염되지 않는다.
--
-- 왜 Play로는 못 재는가: DESIGN.md "목표 성공률 > 측정 규약"이 시뮬레이션 우선이라고
-- 못박고 있다. 사람이 반복 플레이하면 표본이 안 나온다.
--
-- ===== 수치는 여기 없다 ===============================================================
--
-- ⚠️ 밸런싱 수치를 이 파일에 복사하지 말 것. 전부 Config에서 읽는다.
--    HP·보상·타이머 → StageConfig / 패드 → ClickPadConfig / 환생 → RebirthConfig /
--    펀치 속도 → AttackConfig / 힘 초기값 → Schema.
--    Config에 없는 값을 여기 상수로 적어야 하는 상황이 오면 그건 Config가 비어 있다는 뜻이다.
--
-- 아래 SIM 테이블만 예외다. 그것은 **시뮬레이터 파라미터이지 게임 밸런스 값이 아니다.**
--
-- ===== 게임 코드와 같은 식을 쓴다 =====================================================
--
-- 계산식을 새로 만들지 않는다. 실물과 어긋나면 리포트가 거짓말을 하기 때문이다:
--   클릭 획득   padPower × 클릭수 × 배수   (ClickService.computeGain과 같은 식)
--   배수 결합   StrengthMultiplier.compute (직접 곱하지 않는다)
--   1회 데미지  힘 그대로                   (AttackService.computePunchDamage)
--   펀치 간격   1 / AttackConfig.PUNCH_SPEED_BASE
--
-- ⚠️ 펀치 속도를 1회 데미지에 곱하지 않는다. 이중 계산이 되어 실제 DPS가 속도의 제곱이
--    된다 (CLAUDE.md 금지 사항). 속도는 **간격**으로만 들어간다.
--
-- ===== 이번 판이 재지 않는 것 =========================================================
--
-- ⚠️ 거리 판정을 넣지 않았다. 캐릭터가 판정 반경 안에 계속 있다고 가정한다.
--    즉 결과는 DESIGN.md "펀치와 딜 총량"의 **이론 상한 D 기준이고 실제 딜은 이보다 작다.**
--    패드를 밟으러 가는 이동 시간도 계산하지 않는다. 워프도 쓰지 않는다
--    (blox를 환생과 같은 지갑에서 빼가 변수가 하나 늘어난다).
--
-- 사용:
--   Bootstrap의 STANDARD_PATH_REPORT_ENABLED 블록이 부른다. 출력이 필요 없을 때 그 플래그를 끈다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local Schema = require(script.Parent.Parent.Data.Schema)

type BigNumber = BigNum.BigNumber

local StandardPathReport = {}

-- ===== 시뮬레이터 파라미터 ===========================================================
--
-- ⚠️ 이것은 **시뮬레이터 자체의 상수이지 게임 밸런스 값이 아니다.** 게임 수치는 전부
--    Config에서 읽는다. 여기 있는 값을 바꿔도 게임은 변하지 않는다 — 관측 해상도와
--    중단 조건만 변한다.
local SIM = {
	-- 틱 간격(초). 작을수록 정확하고 느리다. 펀치 간격(0.5초)의 1/10이라
	-- 펀치 타이밍이 틱 경계에 눌리지 않는다.
	DT_SEC = 0.05,

	-- 클릭률 3종(회/초). 단일값을 정하지 않고 밴드로 본다.
	-- 근거는 실측이다 — 평범한 한손가락이 약 6, 버터플라이가 11~12로 측정됐고,
	-- 수동 클릭 상한(ClickService.MANUAL_CLICK_LIMIT = 10) 위는 서버가 받지 않아
	-- 도달 불가 구간이다. 자동 클릭은 전부 유료 게임패스라 무과금 표준에 넣지 않는다.
	CLICK_RATES = { 6, 8, 10 },

	-- 무한 루프 방지. 도달하면 경고와 함께 중단한다.
	MAX_RUNS = 1000,

	-- 총 틱 예산. 서버 시작을 붙잡지 않기 위한 안전장치다 —
	-- MAX_RUNS만으로는 런 하나가 길어질 때를 막지 못한다.
	-- 층 하나가 항상 20초를 끝까지 도므로(여유배수 측정) 층당 400틱 고정이다.
	--
	-- ⚠️ 이 카운터는 **커밋된 경로의 틱만 센다.** 못 깰 층을 확인하려고 돌린 탐색은
	--    상태와 함께 버려지므로 잡히지 않는다. 실제 계산량은 이 값보다 크다 —
	--    작업량 측정기가 아니라 폭주 방지용 상한으로만 쓸 것.
	MAX_TICKS = 20000000,

	-- 절벽 판정 임계. "16→17 체류가 이웃 층 평균 체류의 몇 배 이상이면 절벽인가".
	-- ⚠️ **이번 판단을 위한 기준선이지 게임 밸런스 값이 아니다.** 게임에는 이 숫자가
	--    존재하지 않는다. 숫자를 본 뒤에 기준을 정하면 원하는 결론에 맞추게 되므로
	--    **보기 전에 고정했다.**
	CLIFF_RATIO_THRESHOLD = 2.0,

	WORLD_ID = 1,
}

-- ===== 표시 헬퍼 =====================================================================
--
-- ⚠️ raw number로 푸는 지점은 전부 여기다. 게임 수치는 그 전까지 BigNum으로만 다룬다.
--    m × 10^e를 직접 계산하면 e가 조금만 커도 inf가 되므로(10^2000), 나눗셈을 BigNum
--    안에서 먼저 끝내거나 로그 차이로 받는다.
--
-- BigNum.toRatio도 같은 일을 하지만 ±10^308에서 포화한다. 여유배수는 초반 층에서 그
-- 범위를 넘길 수 있어 로그 차이로 받는다. CurveReport에 같은 성격의 지역 헬퍼가 있으나
-- export되지 않고, 공용으로 빼려면 그 파일을 열어야 해서(이번 범위 밖) 여기 최소판을 둔다.

local function log10(value: BigNumber): number
	if value.m <= 0 then
		return -math.huge
	end
	return math.log10(value.m) + value.e
end

-- a / b 를 상용로그 차이로. 자릿수가 아무리 벌어져도 inf/0이 되지 않는다.
local function ratioLog10(a: BigNumber, b: BigNumber): number
	return log10(a) - log10(b)
end

-- 10^x 를 사람이 읽는 문자열로. ← raw number 변환 지점
local function formatPow10(x: number): string
	if x == -math.huge then
		return "0"
	end
	if x ~= x then
		return "nan"
	end
	local e = math.floor(x)
	local m = 10 ^ (x - e)
	if e >= -4 and e <= 4 then
		return string.format("%.4g", m * 10 ^ e)
	end
	return string.format("%.2fe%d", m, e)
end

-- ===== 상태 =========================================================================

type SimState = {
	strength: BigNumber,
	blox: BigNumber,
	lifetimeBlox: BigNumber,
	rebirths: BigNumber, -- 누적 환생 배수분. 배수 = 1 + 이 값
	padIndex: number,
	elapsedSec: number,
	runCount: number,
	rebirthCount: number,
	ticks: number,
}

local function copyBig(v: BigNumber): BigNumber
	return BigNum.new(v.m, v.e)
end

local function copyState(s: SimState): SimState
	return {
		strength = copyBig(s.strength),
		blox = copyBig(s.blox),
		lifetimeBlox = copyBig(s.lifetimeBlox),
		rebirths = copyBig(s.rebirths),
		padIndex = s.padIndex,
		elapsedSec = s.elapsedSec,
		runCount = s.runCount,
		rebirthCount = s.rebirthCount,
		ticks = s.ticks,
	}
end

-- 신규 프로필과 같은 시작점. ⚠️ 힘 초기값은 0이 아니라 1이다 — Schema가 원본이고
-- 여기 숫자로 적지 않는다 (RebirthService도 같은 이유로 Schema.new()를 쓴다).
local function newState(): SimState
	local template = Schema.new()
	return {
		strength = copyBig(template.strength),
		blox = copyBig(template.blox),
		lifetimeBlox = copyBig(template.lifetimeBlox),
		rebirths = copyBig(template.rebirths),
		padIndex = ClickPadConfig.getUnlockedPadCount(SIM.WORLD_ID, template.lifetimeBlox),
		elapsedSec = 0,
		runCount = 0,
		rebirthCount = 0,
		ticks = 0,
	}
end

-- ===== 한 층 시뮬레이션 ==============================================================
--
-- 닫힌 식으로 클리어 시간을 구하지 않는다. 런 도중에도 클릭으로 힘이 계속 자라서
-- 데미지가 매 펀치마다 달라지기 때문이다.
--
-- 입력 상태를 바꾸지 않고 새 상태를 돌려준다. 호출자가 "이 층을 깰 수 있는가"를
-- 먼저 물어본 뒤(완전 정보) 커밋할지 버릴지 정하기 때문이다.
type StageResult = {
	cleared: boolean,
	state: SimState, -- 클리어 시점 스냅샷 (실패면 20초 끝 상태)
	dealtFull: BigNumber, -- 20초를 끝까지 때렸을 때의 누적 데미지
	spentSec: number,
}

-- ⚠️ 클리어해도 루프를 끊지 않고 20초를 끝까지 돈다. 이유는 **여유배수를 재기 위해서다.**
--    클리어 순간에 멈추면 누적 데미지가 총HP 언저리에서 끊겨 여유배수가 항상 1.0이 되고,
--    "얼마나 여유가 있었나"라는 질문 자체가 사라진다.
--    다만 **커밋하는 상태는 클리어 시점 스냅샷이다** — 실제로는 클리어 즉시 다음 층으로
--    넘어가므로 남은 시간을 이 층에서 쓰지 않는다.
local function simulateStage(input: SimState, stage: number, clickRate: number): StageResult
	local s = copyState(input)

	local padPower = ClickPadConfig.getPadPower(SIM.WORLD_ID, s.padIndex)
	-- ⚠️ 배수는 여기서 결합한다. 직접 곱하지 않는다 (곱셈 지점이 흩어지면 하나가 빠져도
	--    조용히 어긋난다 — StrengthMultiplier 상단 주석).
	local multiplier = StrengthMultiplier.compute({ rebirths = s.rebirths })

	local totalHp = StageConfig.getTotalHp(stage)
	local timerSec = StageConfig.CHALLENGE_TIMER_SEC
	local punchInterval = 1 / AttackConfig.PUNCH_SPEED_BASE

	local remaining = totalHp
	local dealtFull = BigNum.new(0, 0)
	local zero = BigNum.new(0, 0)

	local cleared = false
	local clearedState: SimState? = nil
	local spentSec = timerSec

	local t = 0
	local clickCarry = 0
	local punchCarry = 0

	while t < timerSec do
		t += SIM.DT_SEC
		s.elapsedSec += SIM.DT_SEC
		s.ticks += 1

		-- 클릭 누적: 소수점 이하는 다음 틱으로 넘긴다 (클릭은 정수 단위다).
		clickCarry += clickRate * SIM.DT_SEC
		local clicks = math.floor(clickCarry)
		if clicks > 0 then
			clickCarry -= clicks
			-- ClickService.computeGain과 같은 식: padPower × 클릭수 × 배수
			local gain = BigNum.mul(BigNum.mul(padPower, BigNum.fromNumber(clicks)), multiplier)
			s.strength = BigNum.add(s.strength, gain)
		end

		-- 펀치: 간격이 돌아온 만큼 때린다. ⚠️ 속도를 데미지에 곱하지 않는다.
		punchCarry += SIM.DT_SEC
		while punchCarry >= punchInterval do
			punchCarry -= punchInterval
			-- 1회 데미지 = 힘 그대로 (AttackService.computePunchDamage)
			dealtFull = BigNum.add(dealtFull, s.strength)
			if not cleared then
				remaining = BigNum.sub(remaining, s.strength)
				if BigNum.lte(remaining, zero) then
					cleared = true
					spentSec = t
					clearedState = copyState(s)
				end
			end
		end
	end

	return {
		cleared = cleared,
		state = clearedState or s,
		dealtFull = dealtFull,
		spentSec = spentSec,
	}
end

-- ===== 층 기록 ======================================================================
--
-- "처음 도달했을 때" 기준이다 (DESIGN.md 측정 규약). 나중에 다시 온 값이 아니다.
type StageRecord = {
	stage: number,
	runNo: number,
	strengthAtEntry: BigNumber,
	dealtFull: BigNumber,
	totalHp: BigNumber,
	padIndex: number,
	rebirths: BigNumber,
	rebirthCount: number, -- 그 층에 처음 닿은 시점까지의 환생 횟수
	elapsedSec: number,
	spentSec: number,
}

-- ===== 한 런 =======================================================================
--
-- 정지 규칙: 시뮬레이터는 결정론적이라 성공률이 0 아니면 1이다. 그래서 정지선 37%는
-- "깰 수 있는 최대 층까지 진행하고 그 층에서 수령"으로 환원된다 (완전 정보 가정 —
-- 표준 = 의도한 경로를 따라온 유저). DESIGN.md "펀치와 딜 총량 > 안전층의 정의"와 같은 개념이다.
--
-- 깰 수 없는 층에는 **들어가지 않는다.** 들어갔다가 실패하면 보상이 0이 되기 때문이다
-- (푸시-유어-럭). 그래서 다음 층을 먼저 시뮬레이션해 보고 커밋 여부를 정한다.
local function runOnce(state: SimState, clickRate: number, records: { [number]: StageRecord }): (SimState, number)
	state.runCount += 1
	local runNo = state.runCount

	local function record(stage: number, entry: SimState, result: StageResult)
		if records[stage] ~= nil then
			return
		end
		records[stage] = {
			stage = stage,
			runNo = runNo,
			strengthAtEntry = copyBig(entry.strength),
			dealtFull = result.dealtFull,
			totalHp = StageConfig.getTotalHp(stage),
			padIndex = entry.padIndex,
			rebirths = copyBig(entry.rebirths),
			rebirthCount = entry.rebirthCount,
			elapsedSec = entry.elapsedSec,
			spentSec = result.spentSec,
		}
	end

	-- 1층은 유일하게 "실패해도 커밋"한다. 클릭은 런과 무관하게 힘을 올리므로
	-- (ClickService는 ChallengeService를 참조하지 않는다) 실패한 20초에도 힘은 자랐다.
	local first = simulateStage(state, 1, clickRate)
	if not first.cleared then
		return first.state, 0
	end
	record(1, state, first)
	state = first.state

	local stage = 1
	while true do
		local nextStage = stage + 1
		if not StageConfig.hasStage(nextStage) then
			break -- 설계된 종착점. 다음 월드가 생기면 저절로 풀린다.
		end

		local entry = state
		local probe = simulateStage(entry, nextStage, clickRate)
		if not probe.cleared then
			break -- 완전 정보: 못 깰 층에는 들어가지 않는다
		end

		record(nextStage, entry, probe)
		state = probe.state
		stage = nextStage
	end

	-- 수령. 보상은 갱신(덮어쓰기)이라 도달한 층의 값 하나만 받는다 — 누적이 아니다.
	-- CurrencyService.add가 blox와 lifetimeBlox를 함께 올리는 것과 같다.
	local reward = StageConfig.getBloxReward(stage)
	state.blox = BigNum.add(state.blox, reward)
	state.lifetimeBlox = BigNum.add(state.lifetimeBlox, reward)

	-- 파워는 세팅이지 누적이 아니다. 열린 패드가 있으면 즉시 그 패드로 바꾼다.
	state.padIndex = ClickPadConfig.getUnlockedPadCount(SIM.WORLD_ID, state.lifetimeBlox)

	return state, stage
end

-- 환생. **진행 한계에 닿으면** 환생한다 (결정 2).
--
-- ⚠️ "진행 한계"를 월드 최고층 도달로만 읽으면 시뮬레이터가 교착한다. 표준 경로는
--    환생 배수 없이는 15~16층에서 멈추므로 25층에 영영 닿지 못하고, 그러면 환생이
--    한 번도 일어나지 않아 배수 트랙 전체가 죽는다(실측: 런 1000회에 환생 0회).
--    그래서 판정은 **더 이상 층이 늘지 않는 시점**이다 — 25층 도달은 그 특수한 경우다.
--    DESIGN.md "클릭 파워 패드 > 세트는 월드1 통과용이 아니다"가 25층 이후의 성장 목표를
--    패드와 환생 배수로 적고 있는 것과도 맞는다.
--
-- ⚠️ RebirthService와 같은 순서·같은 대상이다. 특히 **힘이 1로 초기화된다** —
--    이걸 빼면 결과가 통째로 낙관적이 된다. lifetimeBlox와 rebirths는 유지된다
--    (그래서 패드는 환생해도 잠기지 않는다).
--
-- bestThisLife: 이번 생애에서 도달한 최고층. 갱신에 실패하면 정체로 본다.
local function maybeRebirth(state: SimState, reachedStage: number, maxStage: number, bestThisLife: number): (SimState, number)
	if not RebirthConfig.canRebirth(state.blox) then
		return state, math.max(bestThisLife, reachedStage) -- 조건 미달. 채울 때까지 런을 반복한다.
	end
	if reachedStage < maxStage and reachedStage > bestThisLife then
		return state, reachedStage -- 아직 전진 중이다. 환생하지 않는다.
	end

	local gained = RebirthConfig.getGainedRebirths(state.blox)
	state.rebirths = BigNum.add(state.rebirths, gained)
	state.blox = BigNum.new(0, 0)
	state.strength = copyBig(Schema.new().strength)
	state.rebirthCount += 1
	return state, 0 -- 새 생애
end

-- ===== 클릭률 한 종 돌리기 ===========================================================

type RateResult = {
	clickRate: number,
	records: { [number]: StageRecord },
	finalState: SimState,
	stoppedReason: string,
}

local function simulateRate(clickRate: number, maxStage: number): RateResult
	local state = newState()
	local records: { [number]: StageRecord } = {}
	local stoppedReason = "최고층 첫 도달까지 기록 완료"
	local bestThisLife = 0

	while true do
		if records[maxStage] ~= nil then
			break -- 목적 달성. 더 돌 이유가 없다.
		end
		if state.runCount >= SIM.MAX_RUNS then
			stoppedReason = string.format("⚠️ 런 상한 %d 도달 — 중단", SIM.MAX_RUNS)
			break
		end
		if state.ticks >= SIM.MAX_TICKS then
			stoppedReason = string.format("⚠️ 틱 예산 %d 소진 — 중단", SIM.MAX_TICKS)
			break
		end

		local reached: number
		state, reached = runOnce(state, clickRate, records)
		state, bestThisLife = maybeRebirth(state, reached, maxStage, bestThisLife)
	end

	return { clickRate = clickRate, records = records, finalState = state, stoppedReason = stoppedReason }
end

-- ===== 출력 ========================================================================

-- 층 전환에 걸린 시간·런·환생. 다음 층 기록과의 차이로 뽑는다.
-- 마지막 층은 다음이 없으므로 nil이다.
local function transitionOf(records: { [number]: StageRecord }, stage: number)
	local here, next_ = records[stage], records[stage + 1]
	if here == nil or next_ == nil then
		return nil
	end
	return {
		staySec = next_.elapsedSec - here.elapsedSec,
		runs = next_.runNo - here.runNo,
		rebirths = next_.rebirthCount - here.rebirthCount,
	}
end

local function printRateTable(result: RateResult, maxStage: number)
	print(string.format("\n===== 클릭률 %d회/초 =====", result.clickRate))
	print("  층 | 런 | 진입 시점 힘 | 20초 딜 총량 |         총HP | 여유배수 | 소요초 | 패드 | 환생(누적) | 도달(분) | 체류(분) | 런수 | 환생수")
	print("  ---+----+--------------+--------------+--------------+----------+--------+------+------------+----------+----------+------+-------")

	for stage = 1, maxStage do
		local r = result.records[stage]
		if r == nil then
			print(string.format("  %2d |  - | (도달 못 함)", stage))
		else
			-- 여유배수 = 20초 딜 총량 ÷ 총HP. 20초를 끝까지 때렸을 때의 값이므로
			-- 소요초가 20보다 작을수록 여유배수가 1보다 커진다.
			--
			-- 체류/런수/환생수는 **이 층에 처음 닿은 뒤 다음 층에 처음 닿을 때까지**의 값이다.
			-- 환생수를 나란히 두는 이유: 체류가 길 때 그것이 환생 대기인지 아닌지를 갈라야
			-- 한다. 환생 대기라면 절벽이 아니라 환생 단가(RebirthConfig.BLOX_PER_REBIRTH)
			-- 문제이고, 그건 튜닝 지도의 다른 항목이다.
			local tr = transitionOf(result.records, stage)
			local stayText, runsText, rebirthText = "       -", "   -", "     -"
			if tr ~= nil then
				stayText = string.format("%8.2f", tr.staySec / 60)
				runsText = string.format("%4d", tr.runs)
				rebirthText = string.format("%6d", tr.rebirths)
			end

			print(string.format(
				"  %2d | %2d | %12s | %12s | %12s | %8s | %6.1f |  %2d  | %10s | %8.1f | %s | %s | %s",
				stage,
				r.runNo,
				Formatter.format(r.strengthAtEntry),
				Formatter.format(r.dealtFull),
				Formatter.format(r.totalHp),
				formatPow10(ratioLog10(r.dealtFull, r.totalHp)), -- ← raw number 변환 지점
				r.spentSec,
				r.padIndex,
				Formatter.format(r.rebirths),
				r.elapsedSec / 60,
				stayText,
				runsText,
				rebirthText
			))
		end
	end

	print(string.format(
		"  런 %d회 / 환생 %d회 / 누적 %.1f분 — %s",
		result.finalState.runCount,
		result.finalState.rebirthCount,
		result.finalState.elapsedSec / 60,
		result.stoppedReason
	))

	-- 구간별 체류 합. 도달 시간만 보면 **늘어난 시간이 어디에 붙었는지** 모른다.
	-- 뒤 구간에 몰려 있으면 HP 세그먼트 조정이 의도대로 후반만 건드린 것이고,
	-- 전 구간에 퍼져 있으면 환생 주기가 통째로 밀린 것이다 — 후자면 손잡이가
	-- 세그먼트가 아니라는 뜻이라 결론이 달라진다.
	--
	-- ⚠️ 구간 경계는 **WorldConfig.hpGrowthSegments에서 파생한다.** 1/8/9/16/17/25를
	--    여기 상수로 적지 말 것 — 세그먼트 구성이 바뀌면 이 표도 따라 움직여야 한다.
	local world = WorldConfig.get(SIM.WORLD_ID)
	if world ~= nil then
		local parts = {}
		for _, segment in ipairs((world :: WorldConfig.WorldDef).hpGrowthSegments) do
			-- 체류는 "그 층 → 다음 층"이라 구간 마지막 층의 체류는 다음 구간 첫 층으로
			-- 넘어가는 시간이다. 그래서 합치면 전체 구간과 정확히 맞는다(망원급수).
			local sum = 0
			local missing = false
			for stage = segment.from, segment.to do
				local tr = transitionOf(result.records, stage)
				if tr ~= nil then
					sum += tr.staySec
				elseif stage < segment.to or result.records[stage] == nil then
					missing = true -- 마지막 층은 체류가 없는 것이 정상이다
				end
			end
			table.insert(parts, string.format(
				"%d~%d층 %.1f분%s",
				segment.from,
				segment.to,
				sum / 60,
				missing and " ⚠️" or ""
			))
		end
		print("  구간 체류 합: " .. table.concat(parts, " / "))
	end
end

-- ===== 검산 ========================================================================
--
-- ⚠️ 첫 출력을 믿지 않기 위한 절이다. CurveReport가 "리포트는 출력되나 수치 검산 미완"으로
--    남아 있던 전례가 있어, 같은 일을 반복하지 않도록 리포트가 스스로 찍는다.

local function printCurveCheck(maxStage: number)
	print("\n===== 검산 (a) 층별 전층대비 비율 =====")
	print("  ⚠️ 블록HP 비가 세그먼트 설정값(3.0 / 4.0 / 7.0)과 같아야 한다.")
	print("     총HP 비는 초반에 다르다 — 블록 개수가 3→4→5→6→7로 늘기 때문이다")
	print("     (8층부터 7개 고정이라 그 뒤로는 둘이 일치한다).")
	print("  층 | 블록HP 비 | 총HP 비 | 보상 비 | 보상÷총HP 비")
	print("  ---+-----------+---------+---------+-------------")

	for stage = 2, maxStage do
		local hpRatio = 10 ^ ratioLog10(StageConfig.getHp(stage), StageConfig.getHp(stage - 1))
		local totalRatio = 10 ^ ratioLog10(StageConfig.getTotalHp(stage), StageConfig.getTotalHp(stage - 1))
		local rewardRatio = 10 ^ ratioLog10(StageConfig.getBloxReward(stage), StageConfig.getBloxReward(stage - 1))
		print(string.format(
			"  %2d | %9.3f | %7.3f | %7.3f | %11.3f",
			stage,
			hpRatio,
			totalRatio,
			rewardRatio,
			rewardRatio / totalRatio
		))
	end
end

-- ===== 절벽 판정 ====================================================================
--
-- 체류 시간만으로는 절벽인지 알 수 없다. "16→17이 1.8분"은 이웃 층도 1.8분이면
-- 평범한 것이고 이웃이 0.3분이면 절벽이다. **반드시 이웃과 대조한다.**
--
-- ⚠️ 임계(SIM.CLIFF_RATIO_THRESHOLD)는 숫자를 보기 전에 고정했다. 보고 나서 정하면
--    원하는 결론에 기준을 맞추게 된다.
local function printCliffVerdict(results: { RateResult })
	local function staySec(records: { [number]: StageRecord }, stage: number): number?
		local tr = transitionOf(records, stage)
		return tr ~= nil and tr.staySec or nil
	end

	-- 경계 stage→stage+1 의 체류를, 그 앞 두 전환의 평균과 견준다.
	local function judge(label: string, results2: { RateResult }, boundary: number)
		print(string.format("\n  --- %s ---", label))
		print("  클릭률 | 경계 체류 | 이웃 평균 |  비율 | 판정      | 그 구간 런/환생")
		print("  -------+-----------+-----------+-------+-----------+----------------")
		for _, result in ipairs(results2) do
			local here = staySec(result.records, boundary)
			local n1 = staySec(result.records, boundary - 2)
			local n2 = staySec(result.records, boundary - 1)
			if here == nil or n1 == nil or n2 == nil then
				print(string.format("  %6d | (구간 미도달)", result.clickRate))
			else
				local neighbour = (n1 + n2) / 2
				local ratio = here / neighbour -- ← raw number. 둘 다 초 단위라 BigNum이 아니다.
				local verdict = ratio >= SIM.CLIFF_RATIO_THRESHOLD and "절벽 실재" or "절벽 없음"
				local tr = transitionOf(result.records, boundary)
				print(string.format(
					"  %6d | %7.2f분 | %7.2f분 | %5.2f | %-9s | 런 %d회 / 환생 %d회",
					result.clickRate,
					here / 60,
					neighbour / 60,
					ratio,
					verdict,
					tr ~= nil and tr.runs or 0,
					tr ~= nil and tr.rebirths or 0
				))
			end
		end
	end

	print(string.format("\n================ 절벽 판정 (임계 %.1f배) ================", SIM.CLIFF_RATIO_THRESHOLD))
	judge("16→17 (세그먼트 4.0 → 7.0)", results, 16)
	judge("대조군 8→9 (세그먼트 3.0 → 4.0)", results, 8)

	print("")
	print("  ⚠️ 대조군을 함께 보는 이유: 8→9도 같은 배수로 튄다면 그것은 17층 고유의 문제가")
	print("     아니라 **세그먼트 경계 자체의 성질**이라는 뜻이다. 그 경우 결론은")
	print("     \"17층을 손본다\"가 아니라 \"경계 구조를 손본다\"로 바뀐다.")
	print("  ⚠️ 환생 수가 함께 큰 구간은 절벽이 아니라 **환생 대기**일 수 있다. 그쪽이면")
	print("     조정 대상은 HP 세그먼트가 아니라 환생 단가(RebirthConfig)다.")
end

-- ===== 시각 누적 검산 ===============================================================
--
-- 체류 시간을 새로 쓰기 시작했으므로, 시각이 어디선가 새면 절벽 판정이 통째로 틀어진다.
local function printTimeAudit(results: { RateResult }, maxStage: number)
	print("\n===== 검산 (e) 시각 누적 =====")
	for _, result in ipairs(results) do
		local first, last = result.records[1], result.records[maxStage]
		if first == nil or last == nil then
			print(string.format("  클릭률 %2d: (전 구간 미도달 — 검산 생략)", result.clickRate))
		else
			local staySum = 0
			local monotonic = true
			for stage = 1, maxStage - 1 do
				local tr = transitionOf(result.records, stage)
				if tr == nil then
					monotonic = false
				else
					staySum += tr.staySec
					if tr.staySec < 0 then
						monotonic = false
					end
				end
			end
			local span = last.elapsedSec - first.elapsedSec
			-- 체류합과 구간은 망원급수라 정의상 같다. 여기서 잡히는 것은 뺄셈 실수뿐이다.
			print(string.format(
				"  클릭률 %2d: 체류합 %.4f분 / 1→%d층 구간 %.4f분 / 차 %.2e초 / 단조 %s",
				result.clickRate,
				staySum / 60,
				maxStage,
				span / 60,
				math.abs(staySum - span),
				monotonic and "예" or "아니오 ⚠️"
			))

			-- 구간 체류 합끼리 더하면 전체와 같아야 한다.
			-- ⚠️ 이건 망원급수 항등식이 **아니다.** 구간 경계는 WorldConfig에서 파생하므로,
			--    세그먼트가 stageRange를 빈틈이나 겹침 없이 덮지 못하면 여기서 어긋난다.
			--    즉 이 줄이 실제로 검사하는 것은 **파생한 경계가 전 구간을 덮는가**다.
			local world = WorldConfig.get(SIM.WORLD_ID)
			if world ~= nil then
				local segSum = 0
				for _, segment in ipairs((world :: WorldConfig.WorldDef).hpGrowthSegments) do
					for stage = segment.from, segment.to do
						local tr = transitionOf(result.records, stage)
						if tr ~= nil then
							segSum += tr.staySec
						end
					end
				end
				print(string.format(
					"             구간 합 계 %.4f분 / 차 %.2e초 %s",
					segSum / 60,
					math.abs(segSum - span),
					math.abs(segSum - span) < 1e-6 and "" or "⚠️ 세그먼트가 전 구간을 덮지 못한다"
				))
			end
		end
	end
end

local function printVerdict(results: { RateResult }, maxStage: number)
	local function marginLog(r: StageRecord): number
		-- 여유배수 = 20초를 끝까지 때렸을 때의 딜 ÷ 총HP.
		-- ⚠️ DESIGN.md "펀치와 딜 총량"의 D = 힘 × 펀치속도 × 20 은 힘이 20초 내내
		--    고정이라고 본 식이다. 실제로는 클릭으로 힘이 자라므로 그 적분값을 쓴다 —
		--    같은 개념의 더 정확한 값이다.
		return ratioLog10(r.dealtFull, r.totalHp)
	end

	print("\n================ 결론: 17층 절벽 ================")
	print("  클릭률 | 16층 여유배수 | 17층 여유배수 |  17÷16 | 16층 도달 | 17층 도달 | 절벽 체류")
	print("  -------+---------------+---------------+--------+-----------+-----------+----------")

	for _, result in ipairs(results) do
		local r16 = result.records[16]
		local r17 = result.records[17]
		if r16 == nil or r17 == nil then
			print(string.format("  %6d | (16층 또는 17층 도달 못 함)", result.clickRate))
		else
			local m16 = marginLog(r16)
			local m17 = marginLog(r17)
			print(string.format(
				"  %6d | %13s | %13s | %6s | %8.1f분 | %8.1f분 | %7.1f분",
				result.clickRate,
				formatPow10(m16), -- ← raw number 변환 지점
				formatPow10(m17),
				formatPow10(m17 - m16),
				r16.elapsedSec / 60,
				r17.elapsedSec / 60,
				(r17.elapsedSec - r16.elapsedSec) / 60
			))
		end
	end

	-- 검산 (b) --------------------------------------------------------------------
	print("\n===== 검산 (b) 1층 여유배수 =====")
	for _, result in ipairs(results) do
		local r1 = result.records[1]
		if r1 ~= nil then
			print(string.format(
				"  클릭률 %2d: %s (소요 %.1f초)",
				result.clickRate,
				formatPow10(marginLog(r1)),
				r1.spentSec
			))
		end
	end
	print("  1에 가까우면 계산이 틀렸을 수 있다 — 1층은 여유가 넉넉해야 하는 층이다.")

	-- 검산 (c) --------------------------------------------------------------------
	print("\n===== 검산 (c) 17층 여유배수 ÷ 16층 여유배수 =====")
	-- 힘이 전혀 자라지 않았다면 D가 고정이므로 비 = 총HP(16)/총HP(17) = 1/7.0 이다.
	-- ⚠️ 0.386이 아니다 — 그 값은 보상÷총HP 축(2.7÷7.0)이고 여기는 D÷총HP 축이다.
	--    축을 섞으면 정상 결과가 "틀렸다"로 판정된다.
	local floorRatio = 10 ^ ratioLog10(StageConfig.getTotalHp(16), StageConfig.getTotalHp(17))
	print(string.format("  하한(힘 성장이 0일 때) = 총HP(16) / 총HP(17) = %.4f", floorRatio))
	for _, result in ipairs(results) do
		local r16, r17 = result.records[16], result.records[17]
		if r16 ~= nil and r17 ~= nil then
			local actual = 10 ^ (marginLog(r17) - marginLog(r16))
			local mark = actual > floorRatio and "OK (그 사이 힘이 자랐다)" or "⚠️ 하한 이하 — 힘 성장 계산 확인 필요"
			print(string.format("  클릭률 %2d: %.4f  %s", result.clickRate, actual, mark))
		end
	end

	-- 검산 (d) --------------------------------------------------------------------
	--
	-- ⚠️ 원래 기준("같은 층의 여유배수가 클릭률에 대해 단조 증가")은 성립하지 않는다.
	--    각 클릭률은 그 층에 **서로 다른 상태로** 도달하기 때문이다 — 환생 누적도 패드도
	--    다르다. 그래서 여유배수는 클릭률에 대해 매끄럽지 않고 뒤집히는 층이 생긴다.
	--    구조적으로 단조인 것은 **도달 시각**이다: 많이 클릭하면 모든 층에 더 빨리 닿는다.
	--    그쪽을 기준으로 삼는다.
	print("\n===== 검산 (d) 클릭률이 높을수록 같은 층에 빨리 도달하는가 =====")
	local violations = 0
	for stage = 1, maxStage do
		local prev: number? = nil
		local ok = true
		for _, result in ipairs(results) do
			local r = result.records[stage]
			if r == nil then
				ok = false
				break
			end
			if prev ~= nil and r.elapsedSec > prev then
				ok = false
			end
			prev = r.elapsedSec
		end
		if not ok then
			violations += 1
			print(string.format("  ⚠️ %2d층: 도달 시각이 클릭률에 대해 단조 감소하지 않음 (또는 미도달)", stage))
		end
	end
	if violations == 0 then
		print("  전 층에서 클릭률이 높을수록 도달이 빠르다. OK")
	end
end

-- ===== 진입점 =======================================================================

function StandardPathReport.run()
	local world = WorldConfig.get(SIM.WORLD_ID)
	assert(world ~= nil, "StandardPathReport: 월드가 없다")
	local maxStage = (world :: WorldConfig.WorldDef).stageRange[2]

	print("[StandardPathReport] 표준 경로 시뮬레이터 (4-2-f) — 값의 원본은 Config, 여기엔 수치가 없다")
	print(string.format(
		"  dt=%.2f초 / 클릭률 %d·%d·%d회초 / 런 상한 %d / 펀치 %.0f회초 / 타이머 %d초 / 패드 %d개",
		SIM.DT_SEC,
		SIM.CLICK_RATES[1],
		SIM.CLICK_RATES[2],
		SIM.CLICK_RATES[3],
		SIM.MAX_RUNS,
		AttackConfig.PUNCH_SPEED_BASE,
		StageConfig.CHALLENGE_TIMER_SEC,
		ClickPadConfig.getSet(SIM.WORLD_ID).count
	))
	print("  ⚠️ 거리 판정 없음 — 캐릭터가 반경 안에 계속 있다고 가정한 **이론 상한**이다.")
	print("     이동 시간과 워프도 계산하지 않는다. 실제 딜은 이보다 작다.")
	print("")
	print("  ⚠️ **이 리포트는 시간 축이다. 성공률 축이 아니다.**")
	print("     결정론 시뮬레이션 + 정지선 규칙이므로 성공률은 항상 0 아니면 1이고,")
	print("     표준 플레이어는 정의상 항상 한계층에서 논다. 여유배수가 전 구간 1~1.5에")
	print("     눌리는 것은 그 구조적 귀결이지 버그가 아니다.")
	print("     DESIGN.md \"목표 성공률\"의 95% / 65~85% / 40~55%는 확률적 플레이어 분포를")
	print("     전제한 값이라 이 출력과 축이 다르다. **두 숫자를 나란히 놓고 비교하지 말 것.**")
	print("     절벽 판정에는 영향이 없다 — 절벽은 \"그 층에서 막히는가\"의 문제이지")
	print("     \"그 층 성공률이 몇 %인가\"가 아니다.")

	local results: { RateResult } = {}
	for _, rate in ipairs(SIM.CLICK_RATES) do
		table.insert(results, simulateRate(rate, maxStage))
	end

	for _, result in ipairs(results) do
		printRateTable(result, maxStage)
	end

	printCurveCheck(maxStage)
	printVerdict(results, maxStage)
	printCliffVerdict(results)
	printTimeAudit(results, maxStage)

	print("\n[StandardPathReport] 끝.")
end

return StandardPathReport

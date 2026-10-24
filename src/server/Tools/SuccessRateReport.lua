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
--                    클리어 뒤 서서 힘을 모으는 것은 게임이 허용하지만(DESIGN.md "런 시작") 여기서는 즉시 판단한다.
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
--   1회 데미지  힘 × 펀치 데미지 배수       (AttackService.computePunchDamage — 배수는 UpgradeConfig.getEffect)
--   펀치 간격   1 / 펀치 속도               (UpgradeConfig.getEffect("punchSpeed", 레벨) — 0레벨 = PUNCH_SPEED_BASE)
--   수령액      층 보상 × 블럭스 계통 배수  (ChallengeService.combineBloxMultiplier — 블럭스 획득 업그레이드 × 칭호)
--   칭호        RollLogic.roll(TitleConfig.Titles, RollService.computeLuck("title", …), 칭호 전용 seed RNG) — 서버와 같은 판정
--   걷기        스폰 → 입장 게이트 거리(ArenaConfig.getSpawnToEntrance) ÷ LevelConfig.getMaxSpeed(힘, 이동속도 효과)
--               런은 게이트에서 서므로(DESIGN.md "런 시작") 걷는 시간은 20초 밖이고, 그동안은
--               평소 속도로 클릭한다. 수령·실패 뒤에는 스폰으로 돌아오므로 런마다 한 번 걷는다
--
-- ⚠️ 펀치 속도를 1회 데미지에 곱하지 않는다 (CLAUDE.md 금지 사항). 속도는 간격으로만 들어간다.
--
-- ===== 업그레이드 구매 규칙 (S5, 2026-10-22 사람 결정 — 지시서 #7 · S5' 2026-10-24 — 지시서 #11) =====
--
-- S5': 구매 대상은 1차 4종(S5_TARGETS)으로 고정한다. 행운 업그레이드는 표준 플레이어가 사지 않는다 — 상점에 열릴 때마다
-- 예산을 나눠 가져 펀치 데미지 레벨이 줄어드는 착시가 쌓인다(#10 "칭호 없음" 비교 17~25층 60.8 → 57.2%).
--
-- 환생 직전, 어차피 버려질 나머지(RebirthConfig.getLeftover — BLOX_PER_REBIRTH 미만)로 가장 싼 업그레이드부터
-- 살 수 있는 만큼 산다(buyCheapestFirst). 업그레이드는 환생해도 남는다. 결정 모델 = MODEL.UPGRADE_POLICY "s5".
-- "none"은 비교 줄(업그레이드 0 — 지시서 #7 이전의 모든 측정이 이 가정이었다).
--
-- ===== 재지 않는 것 ===================================================================
--
--   - 클리어 뒤 진행 벽까지 걷는 시간·클리어 대기 중 클릭. 클리어한 런은 만료되지 않으므로
--     실제 유저는 클리어 후 서서 힘을 더 모을 수 있다 — 여기서는 즉시 판단한다고 본다
--   - 로벅스 상품 · 게임패스 · 드론 · 아우라 · 펫(#11 · #12). 무과금 표준 플레이어다. 블럭스로 사는 칭호 뽑기는 넣는다(S6 · S7)
--   - 워프는 결정 모델에 없다(MODEL.WARP_POLICY = "none"). "greedy"는 비교용 상한이다 —
--     아래 "워프 비교" 참고
--   - 환생 시점 판단은 StandardPathReport와 같은 "정체" 규칙에 인내심(SIM.REBIRTH_PATIENCE_RUNS)을
--     붙였다. 확률 모델에서는 한 번 운 나쁜 런으로 정체가 되기 때문이다
--
-- ===== 칭호 행동 모델 (S7, 2026-10-24 사람 결정 — 지시서 #10) =======================================
--
-- 자동 롤 비용(초당 TitleConfig.ROLL_COST ÷ ROLL_INTERVAL_SEC 블럭스)이 그 시점 블럭스 벌이(초당 — 마지막 런 보상 ÷ 런 길이)의
-- TITLE_AUTO_SHARE 이하이면 켜고, 아니면 끈다(매 런 시작에 다시 판단). 켜져 있는 동안 흐른 시간만큼 간격마다 1회 굴리고
-- 지갑에서 뺀다 — 환생 · S5 업그레이드 예산과 같은 지갑이다. 모자라면 그 틱은 건너뛴다(게임과 같다).
-- 더 높은 등급이 나오면 바로 장착한다(게임은 자동 장착). 칭호는 환생해도 남는다(RebirthService가 cosmetics를 건드리지 않는다).
-- 칭호 배수는 클릭 힘(StrengthMultiplier.compute)과 수령액(ChallengeService.combineBloxMultiplier) 두 자리에서 한 번씩 곱한다.
-- 칭호 난수는 별도 seed(SIM.TITLE_SEED)로 굴린다 — 플레이어 모델 난수열을 바꾸지 않아 "칭호 없음" 비교 줄과 같은 플레이어가 된다.
--
-- 사용: Bootstrap의 SUCCESS_RATE_REPORT_ENABLED 블록이 부른다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)

local Schema = require(script.Parent.Parent.Data.Schema)
local RollLogic = require(script.Parent.Parent.Systems.RollLogic)
local RollService = require(script.Parent.Parent.Systems.RollService)
local ChallengeService = require(script.Parent.Parent.Systems.ChallengeService)

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
	-- 2026-10-21 첫 결정은 10~50%였고, 돌려 보니 HP ×3 이상에서는 거의 언제나 못 깰 층에
	-- 들어가는 규칙이라(손익분기 1 - 1/3 = 67%) 같은 날 50~90%로 다시 결정했다(docs/PENDING.md).
	ADVANCE_THRESHOLD_MIN = 0.50,
	ADVANCE_THRESHOLD_MAX = 0.90,

	-- 진행 판단 규칙. "time_left"가 사람 결정(위 문턱). "growth_aware"는 비교용 변형이다 —
	-- 다음 층 HP 배율 r에서 같은 DPS로 깰 수 있는 손익분기 남은 비율 1 - 1/r에 플레이어별
	-- 편차 ±ADVANCE_NOISE를 더한 문턱을 쓴다(r은 StageConfig에서 읽는다 — 새 숫자 없음).
	ADVANCE_RULE = "time_left",
	ADVANCE_NOISE = 0,

	-- 워프 사용 규칙. "none"이 결정 모델이다(사람 결정 모델에 워프가 없다). "greedy"는
	-- 비교용 상한 — 아래 chooseWarp 참고. 상한이라 실제 유저보다 워프를 잘 쓴다.
	WARP_POLICY = "none",
	-- 워프 가격 배율(시뮬레이터 안에서만). 1이면 WarpConfig.cost 그대로. WarpConfig는 건드리지 않는다.
	WARP_PRICE_SCALE = 1,

	-- 운동기구에서 클릭하는 시간(초). "이번 생애 최고층을 못 넘긴 런" 뒤에 한 번, 열린 기구 중
	-- 가장 좋은 것에서 평소 클릭 속도로 클릭한다. 열린 기구가 없으면 하지 않는다. 0이면 기구를 안 쓴다.
	-- ⚠️ 사람 결정은 "아무 때나 힘을 올리고 싶을 때 기구 위에서 클릭"이다(2026-10-21). "막혔을 때
	--    30초"는 그 결정을 시뮬레이터로 옮기면서 Claude가 고른 해석이다 — 사람 결정 모델 값이 아니다.
	--    로벅스 선해금은 넣지 않는다(무과금 표준 플레이어). 기구까지 걷는 시간도 넣지 않는다.
	GYM_TRAIN_SEC = 30,

	-- 공허 훈련 구역(로벅스 전용 기구)을 샀는가. 결정 모델은 false(무과금). true는 구매자 비교 줄 —
	-- 처음부터 공허에서 GYM_TRAIN_SEC초 훈련한다(환생 기구보다 언제나 세다 — GymConfig.validate).
	OWNS_VOID_ZONE = false,

	-- 스폰 → 게이트를 걷는 동안 평소 속도로 클릭하는가. true가 결정 모델(파일 상단 "걷기"). false는 진단 비교 줄 —
	-- 지시서 #8(로비 단축)에서 성공률이 움직인 원인이 걷는 동안의 클릭인지 가르려고 둔다.
	CLICK_WHILE_WALKING = true,

	-- 업그레이드 구매 규칙. "s5"가 결정 모델(2026-10-22 사람 결정 S5 — 파일 상단), "none"은 업그레이드 0 비교 줄.
	UPGRADE_POLICY = "s5",

	-- 칭호 행동 규칙. "s7"이 결정 모델(2026-10-24 사람 결정 S7 — 파일 상단 "칭호 행동 모델"), "none"은 칭호 없음 비교 줄(지시서 #10 이전).
	TITLE_POLICY = "s7",
	-- 자동 롤을 켜는 기준: 자동 롤 비용 ≤ 블럭스 벌이 × 이 비율 (S7 — 10%)
	TITLE_AUTO_SHARE = 0.10,
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

	-- true면 run()이 결정 모델 · 업그레이드 0 · 업그레이드 TEMP 후보만 돈다(후보를 빨리 비교할 때). 커밋 값은 false.
	UPGRADE_SWEEP_ONLY = false,

	-- 칭호 뽑기 난수 seed(플레이어 모델 난수와 따로 — 파일 상단 "칭호 행동 모델").
	TITLE_SEED = 20261024,

	-- true면 run()이 결정 모델 · 칭호 없음 · 칭호 배수 후보만 돈다(지시서 #10 6단계 후보 비교). 커밋 값은 false.
	TITLE_SWEEP_ONLY = false,
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
	lifeBlox: BigNumber, -- 이번 생애 누적 blox. 패드 해금 기준, 환생하면 0
	rebirths: BigNumber,
	padIndex: number,
	elapsedSec: number,
	runCount: number,
	rebirthCount: number,
	-- 워프 판단 재료. 마지막 "걸어서 시작한" 런의 값이다.
	lastWalkSec: number?,
	climbSec: { [number]: number }, -- climbSec[k] = 런 시작(게이트)부터 k층 클리어까지 걸린 초
	-- 마지막 런(워프 포함)의 보상과 길이(걷기 포함). 벌이 속도 = 보상 ÷ 길이
	lastRunReward: BigNumber?,
	lastRunSec: number?,
	warps: number,
	warpStageSum: number,
	upgrades: { [string]: number }, -- 업그레이드 레벨(노출 항목). 환생해도 남는다(S5)
	upgradeSpent: BigNumber, -- 업그레이드에 쓴 블럭스 합(관측용)
	-- 칭호(S7). titleIndex = 장착 칭호의 TitleConfig.Titles 인덱스(0 = 아직 없음). 환생해도 남는다
	titleIndex: number,
	autoRoll: boolean,
	rollCarry: number, -- 자동 롤 간격 누적(초 → 롤 수)
	titleRolls: number,
	titleSpent: BigNumber,
	autoOnSec: number?, -- 자동 롤을 처음 켠 시각
	autoOnStage: number?, -- 그때 마지막 런 최고층
	lastBest: number, -- 마지막 런 최고층
	titleRandom: (() -> number)?, -- 칭호 난수(simulatePlayer가 넣는다). 없으면 칭호 롤을 하지 않는다
}

local function copyBig(v: BigNumber): BigNumber
	return BigNum.new(v.m, v.e)
end

-- ===== 업그레이드 (S5) =====================================================================

-- S5' 구매 대상(1차 4종). 상점 노출 목록(UpgradeConfig.SHOP_ORDER)과 다르다 — 행운 줄은 상점에 있지만 표준 플레이어는 안 산다.
SuccessRateReport.S5_TARGETS = { "punchDamage", "punchSpeed", "moveSpeed", "bloxGain" }

-- 노출 항목 레벨 0(행운 줄 포함 — 레벨은 0으로 남는다).
function SuccessRateReport.newUpgradeLevels(): { [string]: number }
	local levels: { [string]: number } = {}
	for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		levels[name] = 0
	end
	return levels
end

-- S5': 예산 안에서 S5_TARGETS 중 가장 싼 업그레이드부터 하나씩 산다(살 수 있는 것이 없을 때까지). 값이 같으면 목록 앞쪽.
-- 판정은 게임과 같은 UpgradeConfig.canBuy(최대 레벨 · 잔액). levels를 제자리에서 올린다. 쓴 양 · 산 횟수를 돌려준다.
-- StandardPathReport도 이 함수를 부른다(규칙을 두 곳에 두지 않는다).
function SuccessRateReport.buyCheapestFirst(levels: { [string]: number }, budget: BigNumber): (BigNumber, number)
	local remaining = BigNum.new(budget.m, budget.e)
	local spent = BigNum.new(0, 0)
	local count = 0
	while true do
		local bestName: string? = nil
		local bestCost: BigNumber? = nil
		for _, name in ipairs(SuccessRateReport.S5_TARGETS) do
			local ok, _reason, cost = UpgradeConfig.canBuy(name, levels[name] or 0, remaining)
			if ok and cost ~= nil and (bestCost == nil or BigNum.lt(cost, bestCost :: BigNumber)) then
				bestName, bestCost = name, cost
			end
		end
		if bestName == nil or bestCost == nil then
			break
		end
		remaining = BigNum.sub(remaining, bestCost)
		spent = BigNum.add(spent, bestCost)
		levels[bestName] = (levels[bestName] or 0) + 1
		count += 1
	end
	return spent, count
end

-- 업그레이드 효과. 식은 UpgradeConfig.getEffect 하나(게임 · 상점 창과 같은 함수).
function SuccessRateReport.effect(levels: { [string]: number }, name: string): number
	return UpgradeConfig.getEffect(name, levels[name] or 0)
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
		lifeBlox = copyBig(template.lifeBlox),
		rebirths = copyBig(template.rebirths),
		padIndex = ClickPadConfig.getUnlockedPadCount(SIM.WORLD_ID, template.lifeBlox),
		elapsedSec = 0,
		runCount = 0,
		rebirthCount = 0,
		lastWalkSec = nil,
		climbSec = {},
		lastRunReward = nil,
		lastRunSec = nil,
		warps = 0,
		warpStageSum = 0,
		upgrades = SuccessRateReport.newUpgradeLevels(),
		upgradeSpent = BigNum.new(0, 0),
		titleIndex = 0,
		autoRoll = false,
		rollCarry = 0,
		titleRolls = 0,
		titleSpent = BigNum.new(0, 0),
		autoOnSec = nil,
		autoOnStage = nil,
		lastBest = 0,
		titleRandom = nil,
	}
end

-- ===== 칭호 (S7) =========================================================================

-- 장착 칭호 배수(힘 = 블럭스). 칭호 없음 모델이거나 아직 없으면 1. 게임과 같은 TitleConfig.multOf.
function SuccessRateReport.titleMult(p: Player): number
	if MODEL.TITLE_POLICY ~= "s7" or p.titleIndex <= 0 then
		return 1
	end
	return TitleConfig.multOf(TitleConfig.Titles[p.titleIndex].id)
end

-- 자동 롤 초당 비용.
function SuccessRateReport.autoRollCostPerSec(): BigNumber
	return BigNum.div(TitleConfig.ROLL_COST, BigNum.fromNumber(TitleConfig.ROLL_INTERVAL_SEC))
end

-- S7: 자동 롤 비용 ≤ 블럭스 벌이 × TITLE_AUTO_SHARE 이면 켠다. 벌이 = 마지막 런 보상 ÷ 런 길이(워프 판단과 같은 재료).
-- 재료가 없으면(첫 런 전 · 실패한 런) 지금 상태를 유지한다 — 한 번 실패로 껐다 켰다 하지 않는다.
function SuccessRateReport.decideAutoRoll(p: Player)
	if MODEL.TITLE_POLICY ~= "s7" then
		p.autoRoll = false
		return
	end
	local reward, runSec = p.lastRunReward, p.lastRunSec
	if reward == nil or runSec == nil or runSec <= 0 or reward.m <= 0 then
		return
	end
	local earnPerSec = BigNum.div(reward, BigNum.fromNumber(runSec))
	local on = BigNum.lte(SuccessRateReport.autoRollCostPerSec(), BigNum.mul(earnPerSec, BigNum.fromNumber(MODEL.TITLE_AUTO_SHARE)))
	if on and not p.autoRoll and p.autoOnSec == nil then
		p.autoOnSec = p.elapsedSec
		p.autoOnStage = p.lastBest
	end
	p.autoRoll = on
end

-- 자동 롤이 켜진 동안 sec초가 흘렀다. 간격마다 1회 — 지갑에서 비용을 빼고 굴린다. 모자라면 남은 틱은 건너뛴다.
-- 굴린 수를 돌려준다.
function SuccessRateReport.spendAutoRolls(p: Player, sec: number): number
	if MODEL.TITLE_POLICY ~= "s7" or not p.autoRoll or p.titleRandom == nil or sec <= 0 then
		return 0
	end
	p.rollCarry += sec / TitleConfig.ROLL_INTERVAL_SEC
	local n = math.floor(p.rollCarry)
	p.rollCarry -= n
	local cost = TitleConfig.ROLL_COST
	local luck = RollService.computeLuck("title", { upgrades = p.upgrades })
	local rolled = 0
	for _ = 1, n do
		if BigNum.lt(p.blox, cost) then
			break
		end
		p.blox = BigNum.sub(p.blox, cost)
		p.titleSpent = BigNum.add(p.titleSpent, cost)
		local _, index = RollLogic.roll(TitleConfig.Titles, luck, p.titleRandom :: () -> number)
		if index > p.titleIndex then
			p.titleIndex = index -- 더 높은 등급이면 바로 장착(S7)
		end
		rolled += 1
	end
	p.titleRolls += rolled
	return rolled
end

-- 클릭 n번만큼 힘을 올린다. ClickService.computeGain과 같은 식. gymMultiplier는 운동기구 위에서만(없으면 1).
local function addClicks(p: Player, clicks: number, gymMultiplier: number?)
	if clicks <= 0 then
		return
	end
	local padPower = ClickPadConfig.getPadPower(SIM.WORLD_ID, p.padIndex)
	local multiplier = StrengthMultiplier.compute({ rebirths = p.rebirths, titleMult = SuccessRateReport.titleMult(p) })
	local gain = BigNum.mul(BigNum.mul(padPower, BigNum.fromNumber(clicks)), multiplier)
	if gymMultiplier ~= nil and gymMultiplier ~= 1 then
		gain = BigNum.mul(gain, BigNum.fromNumber(gymMultiplier))
	end
	p.strength = BigNum.add(p.strength, gain)
end

-- 운동기구에서 sec초 클릭한다. 환생 수로 열린 기구 중 가장 좋은 것을 쓴다(공허를 샀으면 공허).
-- 쓴 기구 번호(0 = 안 씀).
function SuccessRateReport.trainAtGym(p: Player, sec: number): number
	if sec <= 0 then
		return 0
	end
	local index = GymConfig.getUnlockedCount(p.rebirths)
	if MODEL.OWNS_VOID_ZONE then
		index = GymConfig.findByGamepass("voidTrainingZone") or index
	end
	if index == 0 then
		return 0
	end
	addClicks(p, math.floor(p.clickRate * sec), GymConfig.getMultiplier(index))
	p.elapsedSec += sec
	SuccessRateReport.spendAutoRolls(p, sec)
	return index
end

-- 스폰 → 입장 게이트. 걷는 동안 평소 속도로 클릭한다. 걸린 초를 돌려준다.
function SuccessRateReport.walkToGate(p: Player): number
	local speed = LevelConfig.getMaxSpeed(p.strength, SuccessRateReport.effect(p.upgrades, "moveSpeed"))
	local sec = ArenaConfig.getSpawnToEntrance() / speed
	if MODEL.CLICK_WHILE_WALKING then
		addClicks(p, math.floor(p.clickRate * sec))
	end
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
	local interval = 1 / SuccessRateReport.effect(p.upgrades, "punchSpeed")
	local damageMultiplier = BigNum.fromNumber(SuccessRateReport.effect(p.upgrades, "punchDamage"))
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

		remaining = BigNum.sub(remaining, BigNum.mul(p.strength, damageMultiplier))
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
-- startStage가 있으면 워프 런이다 — 걷지 않고(워프는 그 층에서 런을 바로 세운다,
-- WarpService) 그 층부터 시작한다. 없으면 게이트를 지나 1층부터(EntranceGateService).
function SuccessRateReport.runOnce(
	p: Player,
	rng: Random,
	firstTry: { [number]: Tally },
	seen: { [number]: boolean },
	startStage: number?
): number
	p.runCount += 1
	SuccessRateReport.decideAutoRoll(p) -- S7: 매 런 시작에 마지막 런 벌이로 다시 판단한다
	local runStartedAt = p.elapsedSec
	local walked = startStage == nil
	if walked then
		p.lastWalkSec = SuccessRateReport.walkToGate(p)
		table.clear(p.climbSec)
	end
	local gateAt = p.elapsedSec

	local interval = 1 / SuccessRateReport.effect(p.upgrades, "punchSpeed")
	local stage = startStage or 1
	local best = 0

	while true do
		local out = rng:NextNumber(0, MODEL.OUT_OF_RADIUS_MAX_SEC)
		local phase = rng:NextNumber(0, interval)
		local outcome = SuccessRateReport.simulateStage(p, stage, out, phase)
		tally(firstTry, seen, stage, outcome.cleared)

		if not outcome.cleared then
			p.lastRunReward = BigNum.new(0, 0)
			p.lastRunSec = p.elapsedSec - runStartedAt
			p.lastBest = best
			SuccessRateReport.spendAutoRolls(p, p.lastRunSec :: number) -- 런 동안 흐른 시간의 자동 롤
			return best -- 실패: 보상 0, 스폰 복귀
		end
		best = stage
		if walked then
			p.climbSec[stage] = p.elapsedSec - gateAt
		end

		local nextExists = StageConfig.hasStage(stage + 1)
		if not (nextExists and SuccessRateReport.wantsAdvance(p, stage, outcome.timeLeft)) then
			break
		end
		stage += 1
	end

	-- 런 동안 흐른 시간의 자동 롤 — 보상이 들어오기 전 지갑에서 쓴다(게임에서도 런 중에 굴린다).
	SuccessRateReport.spendAutoRolls(p, p.elapsedSec - runStartedAt)

	-- 수령. 보상은 갱신이라 도달한 층의 값 하나만 받는다. 블럭스 계통 배수는 ChallengeService.combineBloxMultiplier — 게임과 같은 함수.
	local bloxMultiplier = ChallengeService.combineBloxMultiplier({
		bloxGain = SuccessRateReport.effect(p.upgrades, "bloxGain"),
		titleMult = SuccessRateReport.titleMult(p),
	})
	local reward = BigNum.mul(StageConfig.getBloxReward(best), BigNum.fromNumber(bloxMultiplier))
	p.blox = BigNum.add(p.blox, reward)
	p.lifetimeBlox = BigNum.add(p.lifetimeBlox, reward)
	p.lifeBlox = BigNum.add(p.lifeBlox, reward)
	p.padIndex = ClickPadConfig.getUnlockedPadCount(SIM.WORLD_ID, p.lifeBlox)
	p.lastRunReward = reward
	p.lastRunSec = p.elapsedSec - runStartedAt
	p.lastBest = best
	return best
end
local runOnce = SuccessRateReport.runOnce

-- ===== 워프 비교 =====================================================================
--
-- 질문: "워프로 아낀 시간이 그 비용을 버는 시간보다 큰가." 결정 모델에는 워프가 없으므로
-- 이 규칙은 비교용 **상한**이다 — 워프를 가장 잘 쓰는 플레이어로도 이득이 없으면 실제
-- 유저에게도 없다.
--
-- 매 런 전에 N = 2..(마지막으로 걸어서 깬 최고층)을 본다.
--   아낀 시간  = 걷기 + 1층부터 N-1층 클리어까지(마지막으로 걸어서 시작한 런의 실측)
--   비용 시간  = 워프 비용 ÷ 마지막 런 보상 × 마지막 런 길이 (그 돈을 다시 버는 시간)
-- 이득(아낀 - 비용)이 가장 큰 N으로 워프한다. 양수인 N이 없거나 돈이 모자라면 걸어간다.
-- ⚠️ 환생 배수 손실은 따로 세지 않는다 — blox는 배수로 선형 환산되므로 "다시 버는 시간"에 들어 있다.
function SuccessRateReport.warpCost(stage: number): BigNumber
	return BigNum.mul(WarpConfig.cost(stage), BigNum.fromNumber(MODEL.WARP_PRICE_SCALE))
end

function SuccessRateReport.chooseWarp(p: Player): number?
	local reward, runSec, walkSec = p.lastRunReward, p.lastRunSec, p.lastWalkSec
	if reward == nil or runSec == nil or walkSec == nil or reward.m <= 0 or runSec <= 0 then
		return nil
	end
	local bestStage: number? = nil
	local bestGain = 0
	local n = 2
	while p.climbSec[n - 1] ~= nil and StageConfig.hasStage(n) do
		local cost = SuccessRateReport.warpCost(n)
		if BigNum.gte(p.blox, cost) then
			local saved = walkSec + p.climbSec[n - 1]
			local costSec = BigNum.toRatio(cost, reward) * runSec
			local gain = saved - costSec
			if gain > bestGain then
				bestGain = gain
				bestStage = n
			end
		end
		n += 1
	end
	return bestStage
end

-- RebirthService와 같은 대상: blox 0, 힘 초기값, rebirths 누적, lifeBlox 0 · 패드 1. lifetimeBlox 유지.
local function rebirth(p: Player)
	-- S5: 환생 직전 버려질 나머지로 업그레이드(나머지만 쓰므로 얻는 배수는 그대로다).
	if MODEL.UPGRADE_POLICY == "s5" then
		local spent = SuccessRateReport.buyCheapestFirst(p.upgrades, RebirthConfig.getLeftover(p.blox))
		p.upgradeSpent = BigNum.add(p.upgradeSpent, spent)
	end
	p.rebirths = BigNum.add(p.rebirths, RebirthConfig.getGainedRebirths(p.blox))
	p.blox = BigNum.new(0, 0)
	p.strength = copyBig(Schema.new().strength)
	p.lifeBlox = BigNum.new(0, 0)
	p.padIndex = 1
	p.rebirthCount += 1
	-- 힘이 초기화됐으니 지난 생애의 클리어 기록으로 워프를 고르면 못 깰 층으로 간다.
	table.clear(p.climbSec)
	p.lastWalkSec = nil
end

export type PlayerResult = {
	reachedFinal: boolean,
	finalFirstSec: number?, -- 최고층에 처음 들어간 시각
	runs: number,
	rebirths: number,
	maxStageSeen: number,
	warps: number,
	warpStageSum: number,
	finalRebirthsLog10: number?, -- 최고층 첫 진입 시점의 환생 수(rebirths) 상용로그
	upgrades: { [string]: number }, -- 끝났을 때 업그레이드 레벨
	finalTitleIndex: number, -- 최고층 첫 진입 시점(또는 끝났을 때) 장착 칭호 인덱스. 0 = 없음
	autoOnMin: number?, -- 자동 롤을 처음 켠 시각(분)
	autoOnStage: number?,
	titleRolls: number,
}

function SuccessRateReport.simulatePlayer(rng: Random, maxStage: number, firstTry: { [number]: Tally }, titleRandom: (() -> number)?): PlayerResult
	local p = SuccessRateReport.newPlayer(rng)
	p.titleRandom = titleRandom
	local seen: { [number]: boolean } = {}
	local bestThisLife = 0
	local stale = 0
	local finalFirstSec: number? = nil
	local finalRebirthsLog10: number? = nil

	while p.runCount < SIM.MAX_RUNS_PER_PLAYER and p.elapsedSec < SIM.MAX_SIM_SEC_PER_PLAYER do
		local before = p.elapsedSec
		local warpTo: number? = nil
		if MODEL.WARP_POLICY == "greedy" then
			warpTo = SuccessRateReport.chooseWarp(p)
		end
		if warpTo ~= nil then
			p.blox = BigNum.sub(p.blox, SuccessRateReport.warpCost(warpTo))
			p.warps += 1
			p.warpStageSum += warpTo
		end
		local reached = runOnce(p, rng, firstTry, seen, warpTo)
		if seen[maxStage] and finalFirstSec == nil then
			finalFirstSec = before
			finalRebirthsLog10 = if p.rebirths.m > 0 then math.log10(p.rebirths.m) + p.rebirths.e else nil
			break
		end

		if reached > bestThisLife then
			bestThisLife = reached
			stale = 0
		else
			stale += 1
			SuccessRateReport.trainAtGym(p, MODEL.GYM_TRAIN_SEC)
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
		warps = p.warps,
		warpStageSum = p.warpStageSum,
		finalRebirthsLog10 = finalRebirthsLog10,
		upgrades = p.upgrades,
		finalTitleIndex = p.titleIndex,
		autoOnMin = if p.autoOnSec ~= nil then (p.autoOnSec :: number) / 60 else nil,
		autoOnStage = p.autoOnStage,
		titleRolls = p.titleRolls,
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
	{ label = "결정 모델 (남은 시간 50~90% · 업그레이드 S5 · 칭호 S7)", override = {} },
	{ label = "칭호 없음 (비교 — 지시서 #10 이전 가정)", override = { TITLE_POLICY = "none" } },
	{ label = "업그레이드 0 (비교 — 지시서 #7 이전 가정)", override = { UPGRADE_POLICY = "none" } },
	{ label = "운동기구 안 씀 (비교)", override = { GYM_TRAIN_SEC = 0 } },
	{ label = "공허 훈련 구역 구매자 (비교)", override = { OWNS_VOID_ZONE = true } },
	{ label = "첫 결정 (남은 시간 10~50%)", override = { ADVANCE_THRESHOLD_MIN = 0.1, ADVANCE_THRESHOLD_MAX = 0.5 } },
	{ label = "배율 인식 ±0", override = { ADVANCE_RULE = "growth_aware", ADVANCE_NOISE = 0 } },
	{ label = "배율 인식 ±10%p", override = { ADVANCE_RULE = "growth_aware", ADVANCE_NOISE = 0.1 } },
	{ label = "배율 인식 ±20%p", override = { ADVANCE_RULE = "growth_aware", ADVANCE_NOISE = 0.2 } },
}

-- HP 곡선 후보 스윕. ⚠️ WorldConfig를 고치는 것이 아니라 메모리에서 잠깐 갈아끼운다
-- (StandardPathReport 파워 스윕과 같은 패턴). 끝나면 원래 표를 되돌린다. 후보는 결정 모델로만 돈다.
-- ⚠️ 후보값은 판단 재료이지 결정이 아니다 — 고르는 것은 사람이다(게임 수치).
-- 곡선 규약 1(HP > 보상 2.7)을 깨는 후보는 넣지 않는다.
local CURVE_VARIANTS: { { label: string, segments: { WorldConfig.GrowthSegment } } } = {
	{ label = "A  1~8 ×2.85 / 9~16 ×4.0 / 17~25 ×7.0", segments = {
		{ from = 1, to = 8, growth = 2.85 }, { from = 9, to = 16, growth = 4.0 }, { from = 17, to = 25, growth = 7.0 } } },
	{ label = "B  1~8 ×2.85 / 9~16 ×4.0 / 17~25 ×6.5", segments = {
		{ from = 1, to = 8, growth = 2.85 }, { from = 9, to = 16, growth = 4.0 }, { from = 17, to = 25, growth = 6.5 } } },
	{ label = "C  1~8 ×2.8 / 9~16 ×4.0 / 17~25 ×6.0", segments = {
		{ from = 1, to = 8, growth = 2.8 }, { from = 9, to = 16, growth = 4.0 }, { from = 17, to = 25, growth = 6.0 } } },
	-- D(2.8 / 3.8 / 6.0)는 2026-10-21 채택돼 WorldConfig 현재값이 됐다. 대신 옛 곡선을 비교로 둔다.
	{ label = "옛  1~8 ×3.0 / 9~16 ×4.0 / 17~25 ×7.0", segments = {
		{ from = 1, to = 8, growth = 3.0 }, { from = 9, to = 16, growth = 4.0 }, { from = 17, to = 25, growth = 7.0 } } },
}

local function runModel(label: string, full: boolean, compact: boolean?)
	local maxStage = findLastStage()
	local rng = Random.new(SIM.SEED)
	local titleRandom = RollService.seededRandom(SIM.TITLE_SEED)
	local firstTry: { [number]: Tally } = {}
	local results: { PlayerResult } = {}

	local startedAt = os.clock()
	for _ = 1, SIM.PLAYERS do
		table.insert(results, SuccessRateReport.simulatePlayer(rng, maxStage, firstTry, titleRandom))
		task.wait()
	end
	local tookSec = os.clock() - startedAt

	print(string.format("[SUCCESSRATE] ----- %s -----", label))
	print(string.format(
		"[SUCCESSRATE] 모델: 클릭 %g~%g/초 · 반경 밖 0~%g초/층 · 런 중 클릭 ×%g · 규칙 %s (문턱 %g~%g%%, 편차 ±%g%%p) · 업그레이드 %s",
		MODEL.CLICK_RATE_MIN, MODEL.CLICK_RATE_MAX, MODEL.OUT_OF_RADIUS_MAX_SEC, MODEL.RUN_CLICK_FACTOR,
		MODEL.ADVANCE_RULE, MODEL.ADVANCE_THRESHOLD_MIN * 100, MODEL.ADVANCE_THRESHOLD_MAX * 100, MODEL.ADVANCE_NOISE * 100,
		MODEL.UPGRADE_POLICY
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

	if compact then
		local cells = {}
		for stage = 1, maxStage do
			local t = firstTry[stage]
			table.insert(cells, if t ~= nil and t.attempts > 0 then string.format("%d", math.floor(100 * t.successes / t.attempts + 0.5)) else "-")
		end
		print("[SUCCESSRATE] 층별% 1→" .. maxStage .. ": " .. table.concat(cells, " "))
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
			"[SUCCESSRATE] 구간 %2d~%2d층 (HP ×%g): 합산 %s · 층별 %s~%s · 시도 %d",
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
	local warpsSum = 0
	local warpStageSum = 0
	for _, r in ipairs(results) do
		warpsSum += r.warps
		warpStageSum += r.warpStageSum
		if r.reachedFinal and r.finalFirstSec ~= nil then
			reached += 1
			table.insert(finals, r.finalFirstSec / 60)
		end
		rebirthsSum += r.rebirths
		runsSum += r.runs
	end
	local med = median(finals)
	local rebirthLogs: { number } = {}
	for _, r in ipairs(results) do
		if r.finalRebirthsLog10 ~= nil then
			table.insert(rebirthLogs, r.finalRebirthsLog10)
		end
	end
	local medRebirthLog = median(rebirthLogs)
	print(string.format(
		"[SUCCESSRATE] %d층 첫 진입: %d/%d명 · 중앙값 %s분 · 평균 런 %.0f · 평균 환생 %.1f회 · 그때 환생 수 중앙값 %s · 운동기구 %s초",
		maxStage, reached, #results, if med ~= nil then string.format("%.1f", med) else "-",
		runsSum / #results, rebirthsSum / #results,
		if medRebirthLog ~= nil then string.format("10^%.2f", medRebirthLog) else "-",
		tostring(MODEL.GYM_TRAIN_SEC)
	))
	if MODEL.UPGRADE_POLICY ~= "none" then
		local parts = {}
		for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
			local xs = {}
			for _, r in ipairs(results) do
				table.insert(xs, r.upgrades[name] or 0)
			end
			local m = median(xs)
			table.insert(parts, string.format("%s %s", name, if m ~= nil then tostring(m) else "-"))
		end
		print("[SUCCESSRATE] 업그레이드 레벨 중앙값(끝났을 때, S5): " .. table.concat(parts, " · "))
	end
	if MODEL.TITLE_POLICY == "s7" then
		print("[SUCCESSRATE] " .. SuccessRateReport.titleSummaryText(results))
	end
	if MODEL.WARP_POLICY ~= "none" then
		print(string.format(
			"[SUCCESSRATE] 워프: 런의 %.1f%% · 평균 목표층 %s · 가격 ×%g",
			100 * warpsSum / math.max(runsSum, 1),
			if warpsSum > 0 then string.format("%.1f", warpStageSum / warpsSum) else "-",
			MODEL.WARP_PRICE_SCALE
		))
	end
end

-- 칭호 요약 한 줄: 최고층 첫 진입 시점 장착 분포 · 자동 롤을 켠 시점(분 · 층) 중앙값 · 롤 수 중앙값.
function SuccessRateReport.titleSummaryText(results: { PlayerResult }): string
	local counts: { [number]: number } = {}
	local onMin: { number } = {}
	local onStage: { number } = {}
	local rolls: { number } = {}
	local never = 0
	for _, r in ipairs(results) do
		counts[r.finalTitleIndex] = (counts[r.finalTitleIndex] or 0) + 1
		if r.autoOnMin ~= nil then
			table.insert(onMin, r.autoOnMin)
			table.insert(onStage, r.autoOnStage or 0)
		else
			never += 1
		end
		table.insert(rolls, r.titleRolls)
	end
	local parts = { string.format("없음 %d", counts[0] or 0) }
	for i, def in ipairs(TitleConfig.Titles) do
		table.insert(parts, string.format("%s %d", def.name, counts[i] or 0))
	end
	local m, s, k = median(onMin), median(onStage), median(rolls)
	return string.format(
		"칭호(S7): 최고층 첫 진입 시점 장착 %s · 자동 롤 켠 시점 중앙값 %s분 · %s층 (안 켠 사람 %d) · 롤 수 중앙값 %s",
		table.concat(parts, " · "),
		if m ~= nil then string.format("%.1f", m) else "-",
		if s ~= nil then tostring(s) else "-",
		never,
		if k ~= nil then tostring(k) else "-"
	)
end

-- 칭호 배수 후보 (지시서 #10 6단계 권한 — TitleConfig mult만, 폴백 1.0 고정 · 단조 · 최고 ×3.0 이하).
-- ⚠️ TitleConfig를 고치는 것이 아니라 메모리에서 잠깐 갈아끼운다(업그레이드 후보와 같은 패턴). 끝나면 되돌린다.
-- mults는 Titles 순서(희귀도 낮은 순) 배열이다.
-- 측정(2026-10-24, 지시서 #10 6단계 — 200명 · 같은 seed, 17~25층 목표 40~55% ±10%p, 25층 중앙값 기준선 49.9분의 90% 이상):
--   기준선(지시서 #10 전, 칭호 없음 · 상점 4종)        98.2 / 84.4 / 60.8% · 49.9분
--   T0 결정 모델(S5 + S7, 시작값 1.05/1.1/1.2/1.4/1.8)  96.9 / 80.8 / 55.8% · 46.1분 (−7.6%)  ← 지킬 것 전부 안 → 바꾸지 않았다
--   칭호 없음 비교(상점에 칭호 행운은 있다)             97.2 / 82.1 / 57.2% · 49.2분 — S5가 칭호 행운에도 나머지를 나눠 쓴다
--   25층 시점 장착: 챔피언 125 · 레전드 68 · 신화 5 · 파괴자 2명. 자동 롤 켠 시점 중앙값 10.0분 · 9층, 롤 수 중앙값 2033
SuccessRateReport.TITLE_VARIANTS = {
	{ label = "T0  현재 TitleConfig", mults = nil },
} :: { { label: string, mults: { number }? } }

function SuccessRateReport.withTitleMults(mults: { number }?, fn: () -> ())
	if mults == nil then
		fn()
		return
	end
	local saved: { number } = {}
	for i, def in ipairs(TitleConfig.Titles) do
		saved[i] = def.mult
		def.mult = mults[i]
	end
	local ok, err = pcall(function()
		TitleConfig.validate()
		assert(TitleConfig.Titles[1].mult == 1, "후보: 폴백 1.0 고정")
		assert(TitleConfig.Titles[#TitleConfig.Titles].mult <= 3, "후보: 최고 ×3.0 이하(권한)")
		fn()
	end)
	for i, def in ipairs(TitleConfig.Titles) do
		def.mult = saved[i]
	end
	if not ok then
		error(err)
	end
end

-- ===== 진행 문턱 구간 비교 ==============================================================
--
-- 같은 플레이어 모델·같은 seed에서 진행 문턱 구간만 바꿔 HP 구간별 성공률과 최종층 첫 진입
-- 중앙값을 한 표로 나란히 찍는다. 첫 줄(50~90%)이 목표 기준이다(2026-10-21 사람 결정 —
-- 성공률 목표는 조심형 플레이어 기준, DESIGN.md "목표 성공률 > 측정 규약").
-- ⚠️ 판단 재료이지 결정이 아니다. 나머지 두 줄은 "덜 조심하면 얼마나 떨어지는가"를 보는 자리다.
export type Band = { label: string, min: number, max: number, target: boolean }
SuccessRateReport.THRESHOLD_BANDS = {
	{ label = "50~90%", min = 0.50, max = 0.90, target = true },
	{ label = "30~70%", min = 0.30, max = 0.70, target = false },
	{ label = "10~50%", min = 0.10, max = 0.50, target = false },
} :: { Band }

export type SegmentSum = { from: number, to: number, attempts: number, successes: number }

-- HP 구간별 첫 시도 합산. 구간 경계는 WorldConfig에서 읽고 maxStage에서 자른다.
-- maxStage보다 위에서 시작하는 구간은 넣지 않는다.
function SuccessRateReport.segmentSums(firstTry: { [number]: Tally }, maxStage: number): { SegmentSum }
	local out: { SegmentSum } = {}
	for _, seg in ipairs(hpSegments()) do
		if seg.from <= maxStage then
			local sum: SegmentSum = { from = seg.from, to = math.min(seg.to, maxStage), attempts = 0, successes = 0 }
			for stage = sum.from, sum.to do
				local t = firstTry[stage]
				if t ~= nil then
					sum.attempts += t.attempts
					sum.successes += t.successes
				end
			end
			table.insert(out, sum)
		end
	end
	return out
end

export type BandResult = { band: Band, segments: { SegmentSum }, medianFinalMin: number?, reached: number, players: number }

-- 문턱 구간 하나를 같은 seed로 돌린다. MODEL은 잠깐 바꿨다가 (에러가 나도) 되돌린다.
--
-- ⚠️ noYield: 테스트는 반드시 true로 부른다. MODEL은 모듈 하나를 Play 전체가 공유한다 —
--    MODEL을 바꾼 채 yield하면 그 사이 같은 Play에서 도는 리포트(Bootstrap SUCCESS_RATE_REPORT)가
--    바뀐 문턱으로 계산한다. 2026-10-21 실측: 이 경합으로 리포트 결정 모델 줄이 Play마다 달랐다
--    (25층 도달 200명 ↔ 197명). 테스트를 yield 없이 돌리면 원자적이라 끼어들 틈이 없다.
function SuccessRateReport.runBand(band: Band, players: number, maxStage: number, noYield: boolean?): BandResult
	local savedMin, savedMax = MODEL.ADVANCE_THRESHOLD_MIN, MODEL.ADVANCE_THRESHOLD_MAX
	MODEL.ADVANCE_THRESHOLD_MIN, MODEL.ADVANCE_THRESHOLD_MAX = band.min, band.max
	local ok, result = pcall(function(): BandResult
		local rng = Random.new(SIM.SEED)
		local titleRandom = RollService.seededRandom(SIM.TITLE_SEED)
		local firstTry: { [number]: Tally } = {}
		local finals: { number } = {}
		for _ = 1, players do
			local r = SuccessRateReport.simulatePlayer(rng, maxStage, firstTry, titleRandom)
			if r.reachedFinal and r.finalFirstSec ~= nil then
				table.insert(finals, r.finalFirstSec / 60)
			end
			if not noYield then
				task.wait()
			end
		end
		return {
			band = band,
			segments = SuccessRateReport.segmentSums(firstTry, maxStage),
			medianFinalMin = median(finals),
			reached = #finals,
			players = players,
		}
	end)
	MODEL.ADVANCE_THRESHOLD_MIN, MODEL.ADVANCE_THRESHOLD_MAX = savedMin, savedMax
	if not ok then
		error(result)
	end
	return result
end

local function printBandTable()
	local maxStage = findLastStage()
	print("[SUCCESSRATE] ===== 진행 문턱 구간 비교 (목표 기준 = 50~90%, 나머지 모델·seed 동일) =====")
	local header = { "문턱" }
	for _, seg in ipairs(hpSegments()) do
		table.insert(header, string.format("%d~%d층(×%g)", seg.from, seg.to, seg.growth))
	end
	table.insert(header, string.format("%d층 첫 진입 중앙값", maxStage))
	print("[SUCCESSRATE] " .. table.concat(header, " | "))
	for _, band in ipairs(SuccessRateReport.THRESHOLD_BANDS) do
		local r = SuccessRateReport.runBand(band, SIM.PLAYERS, maxStage)
		local cells = { band.label .. (if band.target then " (목표 기준)" else "") }
		for _, seg in ipairs(r.segments) do
			table.insert(cells, pct({ attempts = seg.attempts, successes = seg.successes }))
		end
		table.insert(cells, if r.medianFinalMin ~= nil
			then string.format("%.1f분 (%d/%d명)", r.medianFinalMin, r.reached, r.players)
			else string.format("- (%d/%d명)", r.reached, r.players))
		print("[SUCCESSRATE] " .. table.concat(cells, " | "))
	end
end

-- 워프 비교. 첫 줄이 현재 가격, 나머지는 "얼마면 쓰이는가"를 보는 가격 배율이다.
-- ⚠️ 판단 재료이지 결정이 아니다 — 워프 가격은 사람이 정한다(게임 수치).
local WARP_VARIANTS: { { label: string, override: { [string]: any } } } = {
	{ label = "워프 상한 · 현재 가격", override = { WARP_POLICY = "greedy", WARP_PRICE_SCALE = 1 } },
	{ label = "워프 상한 · 가격 ×0.1", override = { WARP_POLICY = "greedy", WARP_PRICE_SCALE = 0.1 } },
	{ label = "워프 상한 · 가격 ×0.01", override = { WARP_POLICY = "greedy", WARP_PRICE_SCALE = 0.01 } },
}

-- 업그레이드 TEMP 후보 스윕 (지시서 #7 4단계). ⚠️ UpgradeConfig를 고치는 것이 아니라 메모리에서 잠깐 갈아끼운다
-- (HP 곡선 후보와 같은 패턴). 끝나면 원래 값을 되돌린다. 후보는 결정 모델(S5)로만 돈다.
-- 지시서 #7 "추가 권한": 최대 레벨 · 기준 비용 · 비용 증가율 · 펀치 데미지/블럭스 획득 증가량만 만진다.
-- 펀치 속도 증가량은 S2 유도값이라 후보에 넣지 않는다(최대 레벨을 바꾸면 따라 바뀐다).
export type UpgradeOverride = { [string]: { [string]: any } }
SuccessRateReport.UPGRADE_VARIANTS = {
	{ label = "U0  현재 UpgradeConfig", override = {} },
	-- 조정 이력(2026-10-22, 지시서 #7 4단계 — 결정 모델 S5, 17~25층 합산. 목표 40~55% ±10%p):
	--   첫 TEMP 기준 10 · 데미지/블럭스 0.1 → 68.7% (업그레이드 0은 47.8%)
	--   1차: 기준 50 → 56.4 · 기준 100 → 58.4 · 0.05 → 56.3 · 증가율 1.3/1.35 → 62.8 · 펀치 속도만 못 사게(진단) → 66.8 · 0.05 + 기준 50 → 58.3
	--   2차: 블럭스 못 사게(진단) → 65.1 · 데미지 못 사게(진단) → 57.1 (펀치 데미지가 주원인) · 0.03 → 60.3
	--        0.05 + 기준 100 → 53.8 ← 채택(U10) · 0.05 + 증가율 1.3/1.35 → 58.1 · 최대 10레벨 → 69.1
	--   3차: 데미지 0.03 · 블럭스 0.05 + 기준 100 → 57.4 · 0.05 + 기준 200 → 49.8 · 블럭스 0.1 → 61.2 · 무한 증가율 1.2 → 54.2
	--   기준 200은 가운데에 더 가깝지만 25층까지 각 2레벨뿐이라 상점이 월드 1에서 거의 의미가 없다 → 기준 100(각 4레벨)을 골랐다(Claude 판단)
	{ label = "첫 TEMP  기준 10 · 데미지/블럭스 0.1 (비교)", override = {
		punchDamage = { baseCost = 10, effectPerLevel = 0.1 }, punchSpeed = { baseCost = 10 }, moveSpeed = { baseCost = 10 }, bloxGain = { baseCost = 10, effectPerLevel = 0.1 } } },
	{ label = "기준 200 (비교)", override = {
		punchDamage = { baseCost = 200 }, punchSpeed = { baseCost = 200 }, moveSpeed = { baseCost = 200 }, bloxGain = { baseCost = 200 } } },
} :: { { label: string, override: UpgradeOverride } }

-- override를 적용한 채 fn을 돈다. 에러가 나도 되돌린다. baseCost는 숫자로 적는다(BigNum.fromNumber로 바꾼다).
function SuccessRateReport.withUpgradeOverride(override: UpgradeOverride, fn: () -> ())
	local saved: { [string]: { [string]: any } } = {}
	for name, fields in pairs(override) do
		local def = (UpgradeConfig.Upgrades :: any)[name]
		saved[name] = {}
		for key, value in pairs(fields) do
			saved[name][key] = { value = def[key] }
			def[key] = if key == "baseCost" then BigNum.fromNumber(value) else value
		end
	end
	local ok, err = pcall(function()
		UpgradeConfig.validate()
		fn()
	end)
	for name, fields in pairs(saved) do
		local def = (UpgradeConfig.Upgrades :: any)[name]
		for key, box in pairs(fields) do
			def[key] = box.value
		end
	end
	if not ok then
		error(err)
	end
end

function SuccessRateReport.run()
	print("[SUCCESSRATE] ===== 확률적 플레이어 성공률 (4-2-f) =====")
	if SIM.TITLE_SWEEP_ONLY then
		for i = 1, 2 do
			local variant = VARIANTS[i]
			local saved: { [string]: any } = {}
			for k, v in pairs(variant.override) do
				saved[k] = (MODEL :: any)[k]
				;(MODEL :: any)[k] = v
			end
			runModel(variant.label, false, true)
			for k, v in pairs(saved) do
				(MODEL :: any)[k] = v
			end
		end
		print("[SUCCESSRATE] ===== 칭호 배수 후보 (결정 모델 S5 + S7) =====")
		for _, variant in ipairs(SuccessRateReport.TITLE_VARIANTS) do
			local ok, err = pcall(SuccessRateReport.withTitleMults, variant.mults, function()
				runModel(variant.label, false, true)
			end)
			if not ok then
				print(string.format("[SUCCESSRATE] %s — 권한 · 규약 위반으로 건너뜀: %s", variant.label, tostring(err)))
			end
		end
		print("[SUCCESSRATE] (TITLE_SWEEP_ONLY) 끝.")
		return
	end
	for i, variant in ipairs(VARIANTS) do
		if SIM.UPGRADE_SWEEP_ONLY and i > 2 then
			break
		end
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

	if SIM.UPGRADE_SWEEP_ONLY then
		print("[SUCCESSRATE] (UPGRADE_SWEEP_ONLY — HP 곡선 · 워프 · 문턱 비교 건너뜀)")
	else
		print("[SUCCESSRATE] ===== HP 곡선 후보 (결정 모델) =====")
		local world = WorldConfig.get(SIM.WORLD_ID) :: WorldConfig.WorldDef
		local original = world.hpGrowthSegments
		for _, variant in ipairs(CURVE_VARIANTS) do
			world.hpGrowthSegments = variant.segments
			local ok, err = pcall(WorldConfig.validate)
			if ok then
				runModel(variant.label, false, true)
			else
				print(string.format("[SUCCESSRATE] %s — 규약 위반으로 건너뜀: %s", variant.label, tostring(err)))
			end
		end
		world.hpGrowthSegments = original

		print("[SUCCESSRATE] ===== 워프 비교 (결정 모델 + 워프 상한 규칙) =====")
		for _, variant in ipairs(WARP_VARIANTS) do
			local saved: { [string]: any } = {}
			for k, v in pairs(variant.override) do
				saved[k] = (MODEL :: any)[k]
				;(MODEL :: any)[k] = v
			end
			runModel(variant.label, false, true)
			for k, v in pairs(saved) do
				(MODEL :: any)[k] = v
			end
		end
		printBandTable()
	end

	-- 로비 걷기 비교 (지시서 #8 1단계). ⚠️ ArenaConfig · LevelConfig를 고치는 것이 아니라 메모리에서 잠깐 갈아끼운다.
	-- 로비를 줄이자(스폰 → 게이트 20초 → 4초) 성공률이 올랐다 — 그 원인이 걷기인지 가르는 진단 줄이다.
	print("[SUCCESSRATE] ===== 로비 걷기 비교 (결정 모델, 진단) =====")
	do
		local LevelConfigMod = LevelConfig :: any
		local savedSpawn, savedBase = ArenaConfig.SPAWN_X, LevelConfigMod.BASE_WALK_SPEED
		local ok, err = pcall(function()
			ArenaConfig.SPAWN_X = ArenaConfig.getEntranceX() - 320
			LevelConfigMod.BASE_WALK_SPEED = 16
			runModel("옛 로비 걷기 (320 studs · 기본 속도 16)", false, true)
		end)
		ArenaConfig.SPAWN_X, LevelConfigMod.BASE_WALK_SPEED = savedSpawn, savedBase
		if not ok then
			error(err)
		end
		local savedClick = MODEL.CLICK_WHILE_WALKING
		MODEL.CLICK_WHILE_WALKING = false
		local ok2, err2 = pcall(runModel, "걷는 동안 클릭 없음 (새 로비, 진단)", false, true)
		MODEL.CLICK_WHILE_WALKING = savedClick
		if not ok2 then
			error(err2)
		end
	end

	print("[SUCCESSRATE] ===== 업그레이드 TEMP 후보 (결정 모델 S5) =====")
	for _, variant in ipairs(SuccessRateReport.UPGRADE_VARIANTS) do
		local ok, err = pcall(SuccessRateReport.withUpgradeOverride, variant.override, function()
			runModel(variant.label, false, true)
		end)
		if not ok then
			print(string.format("[SUCCESSRATE] %s — 규약 위반으로 건너뜀: %s", variant.label, tostring(err)))
		end
	end
	print("[SUCCESSRATE] 끝.")
end

return SuccessRateReport

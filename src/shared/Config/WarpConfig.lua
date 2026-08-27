--!strict
-- 워프 비용 계산.
--
--   비용 = TEMP_COST_BASE × TEMP_COST_RATIO^(목표층 - 1)
--
-- **절대 기준이다.** 현재 위치를 참조하지 않는다 — 목표 스테이지 하나만 받는다.
-- 규칙과 근거(왜 거리 기준이 아닌지, maxStage 리셋과 어떻게 얽히는지)는
-- DESIGN.md "3. 화폐와 배수 > 블럭스 소비처"가 원본이다.
-- ⚠️ 근거를 여기로 복사하지 말 것.
--
-- 이 모듈은 순수하다. Player·프로필·진행 상태(maxStage, run)를 보지 않고,
-- 다른 Service를 require하지 않는다. 같은 입력이면 항상 같은 값이다.

local BigNum = require(script.Parent.Parent.BigNum)
local StageConfig = require(script.Parent.StageConfig)

type BigNumber = BigNum.BigNumber

local WarpConfig = {}

-- ===== 튜닝 수치 =====================================================================
--
-- ⚠️ TEMP — 4-2-f 실측 튜닝 대상. 근거 없는 임시값이다.
-- bloxBase = 1 과 같은 성격이며, 확정값으로 취급하지 말 것.
--
-- 자리값을 고른 근거(확정 근거가 아니라 "왜 이 자리인지"):
--   BASE  = 100 — 1층 워프가 1층 보상 100판어치. bloxBase = 1 위에 얹은 값이라
--                 bloxBase가 움직이면 이 의미도 같이 움직인다.
--                 (WorldConfig의 clickPadSet.unlockMultiplier = 36과 같은 성격)
--   RATIO = 3.0 — 보상 성장률 2.7(WorldConfig.bloxGrowthSegments)보다 가파르다.
--                 같거나 완만하면 워프가 정상 진행보다 싸져서 진행이 뚫린다.
--
-- ⚠️ 3.0과 2.7의 차이는 층이 오를수록 **복리로 쌓인다.** 25층이면
--    (3.0/2.7)^24 ≈ 12.7배 — 1층에서 100판어치였던 것이 25층에서는 1270판어치가 된다.
--    이게 의도(후반 워프는 사치품)인지 과한지는 4-2-f에서 볼 문제다.
--    여기서는 "이 비율차가 누적된다"는 사실만 남긴다. 두 값 중 하나만 건드리면
--    후반 비용이 눈에 띄는 것보다 훨씬 크게 움직인다.
local TEMP_COST_BASE = 100
local TEMP_COST_RATIO = 3.0

-- ===== 거부 사유 코드 =================================================================
--
-- ⚠️ 코드만 둔다. 표시 문구를 여기 넣지 말 것 — 매핑은 Phase 6 UI가 한다.
-- 형태는 RebirthService.REASON_*와 같다(모듈 테이블에 공개 + lowercase snake 값).
--
-- ⚠️ 값은 RebirthService와 공유하지 않는다. "블럭스 부족"이 양쪽에 있지만
-- not_enough_blox(환생)와 insufficient_blox(워프)는 유저에게 다른 안내가 필요하다.
-- 사유 코드를 각 모듈이 자기 테이블에 선언하는 구조 자체가 값 공유가 아니라
-- 형태 공유라는 뜻이다 — 값을 공유할 작정이었다면 공용 상수 파일을 뒀을 것이다.
--
-- ⚠️ 정의는 여기 하나다. WarpService는 이 값을 **재공개만** 한다
-- (WarpService.REASON_X = WarpConfig.REASON_X). 판정이 이 파일에 있는데
-- 사유 이름이 Service에 있으면 사유를 하나 늘릴 때 두 파일이 갈라진다.
-- 재공개를 두는 이유는 UI 접근점을 Service로 통일하기 위해서다 —
-- 정의는 한 곳(Config), 부르는 곳은 한 곳(Service).
WarpConfig.REASON_INVALID_STAGE = "invalid_stage"
WarpConfig.REASON_STAGE_OUT_OF_RANGE = "stage_out_of_range"
WarpConfig.REASON_INSUFFICIENT_BLOX = "insufficient_blox"

local REASON_INVALID_STAGE = WarpConfig.REASON_INVALID_STAGE
local REASON_STAGE_OUT_OF_RANGE = WarpConfig.REASON_STAGE_OUT_OF_RANGE
local REASON_INSUFFICIENT_BLOX = WarpConfig.REASON_INSUFFICIENT_BLOX

-- 스테이지 번호로 쓸 수 있는 값인가. **범위는 보지 않는다** — 26층은 여기를 통과하고
-- 담당 월드가 없다는 이유로 따로 거부된다. 두 가지는 성격이 다르다:
-- 이쪽은 호출자가 잘못 만든 값이고, 저쪽은 아직 월드가 없는 정상적인 층이다.
local function isUsableStage(stage: any): boolean
	return type(stage) == "number" and stage == stage and stage % 1 == 0 and stage >= 1
end

-- 목표 스테이지의 워프 비용.
--
-- ⚠️ 범위를 보지 않는다. cost는 수식이고 범위는 정책이다 — 26층에도 수식상의 값은
-- 존재하며, "갈 수 있는가"는 canWarp이 판정한다. 둘을 여기서 합치면 월드가 늘어날 때
-- 비용 곡선이 범위 판정에 끌려다닌다.
--
-- ⚠️ 반대로 stage 자체가 스테이지 번호가 아닌 경우(소수·0·음수·nil)는 터뜨린다.
-- 정상 거부가 아니라 호출자 버그다. 조용히 접으면 "워프했는데 엉뚱한 층 값이
-- 청구됐다"로 증상만 남고 원인이 사라진다. 사유 코드가 필요한 쪽은 canWarp을 쓴다.
-- (RebirthConfig.floorBig이 음수를 다루는 방식과 같다)
--
-- ⚠️ 그래서 **호출자 계약이 붙는다.** WarpService는 검증되지 않은 입력에 cost를 직접
-- 부르지 않는다. 반드시 canWarp을 먼저 통과시키고, 그 반환값으로 받은 비용을 쓴다.
-- 목표층은 결국 UI(Phase 6 텔레포트 창)에서 오고 클라가 보낸 값은 전부 검증 대상이다
-- (CLAUDE.md 절대 규칙 3). UI가 nil이나 소수를 보내면 여기서 서버 error가 나는데,
-- 같은 입력을 canWarp은 REASON_INVALID_STAGE로 접는다.
-- 사유 코드로 접혀야 할 것이 서버 에러가 되면 안 된다.
function WarpConfig.cost(targetStage: number): BigNumber
	assert(
		isUsableStage(targetStage),
		string.format("WarpConfig.cost: 목표층(%s)은 1 이상의 정수여야 함", tostring(targetStage))
	)

	-- 1층이 기준점이므로 지수는 stage - 1. BigNum.pow는 log10 기반이라 반복 곱과 달리
	-- 오차가 누적되지 않는다 (StageConfig.segmentedGrowthMultiplier와 같은 관용구).
	local growth = BigNum.pow(BigNum.fromNumber(TEMP_COST_RATIO), targetStage - 1)
	return BigNum.mul(BigNum.fromNumber(TEMP_COST_BASE), growth)
end

-- 워프가 가능한가.
--
--   가능  true,  비용(BigNum)
--   거부  false, "사유코드"  (REASON_* 상수 중 하나)
--
-- ⚠️ 판정 순서가 계약이다: 사용 가능한 값인가 → 갈 수 있는 층인가 → 낼 수 있는가.
-- 순서를 바꾸면 26층을 물었을 때 "블럭스 부족"이 나온다(비용은 계산되니까) —
-- 유저가 블럭스를 모아도 영영 못 가는데 부족하다고 안내하게 된다.
--
-- ⚠️ 범위 밖 층은 **정상 거부다.** error로 터뜨리지 않는다. 상한은 숫자가 아니라
-- WorldConfig에서 파생된다 — 판정이 "25보다 큰가"가 아니라 "이 층을 담당하는 월드가
-- 있는가"이므로, 월드 2가 추가되면 이 파일을 고치지 않고도 상한이 따라 올라간다.
-- (같은 원리 → DESIGN.md "8. 월드 > 최종 월드의 마지막 층")
function WarpConfig.canWarp(currentBlox: BigNumber, targetStage: number): (boolean, any)
	if not isUsableStage(targetStage) then
		return false, REASON_INVALID_STAGE
	end

	-- ⚠️ 상한을 여기 적지 말 것. StageConfig.hasStage가 WorldConfig를 조회한다.
	if not StageConfig.hasStage(targetStage) then
		return false, REASON_STAGE_OUT_OF_RANGE
	end

	local cost = WarpConfig.cost(targetStage)

	-- 경계는 이상(>=)이다. 비용과 정확히 같으면 통과한다.
	if not BigNum.gte(currentBlox, cost) then
		return false, REASON_INSUFFICIENT_BLOX
	end

	return true, cost
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- (RebirthConfig._pure / ClickService._pure와 같은 패턴)
WarpConfig._pure = {
	TEMP_COST_BASE = TEMP_COST_BASE,
	TEMP_COST_RATIO = TEMP_COST_RATIO,
	isUsableStage = isUsableStage,
}

function WarpConfig.validate(): boolean
	assert(
		type(TEMP_COST_BASE) == "number" and TEMP_COST_BASE > 0,
		string.format("WarpConfig: TEMP_COST_BASE(%s)는 0보다 커야 함", tostring(TEMP_COST_BASE))
	)

	-- 1 이하면 지수가 아니다 — 층이 올라도 비용이 그대로거나 싸진다.
	assert(
		type(TEMP_COST_RATIO) == "number" and TEMP_COST_RATIO > 1,
		string.format("WarpConfig: TEMP_COST_RATIO(%s)는 1보다 커야 함", tostring(TEMP_COST_RATIO))
	)

	-- 1층은 어느 월드 설정에서도 존재해야 한다. 없으면 아래 경계 검사가 의미를 잃는다.
	assert(StageConfig.hasStage(1), "WarpConfig: 1층을 담당하는 월드가 없음")

	-- 경계가 실제로 비용에 서 있는지. 상수만 보고 지나가면 부등호가 한 칸 어긋나
	-- 있어도(>= 대신 >) 통과한다. (RebirthConfig.validate와 같은 이유)
	local cost1 = WarpConfig.cost(1)
	local justBelow = BigNum.sub(cost1, BigNum.fromNumber(1))

	local exactOk = WarpConfig.canWarp(cost1, 1)
	assert(exactOk, "WarpConfig: 비용과 정확히 같은 블럭스로 워프가 가능해야 함")

	local belowOk, belowReason = WarpConfig.canWarp(justBelow, 1)
	assert(
		not belowOk and belowReason == REASON_INSUFFICIENT_BLOX,
		string.format("WarpConfig: 비용보다 1 적으면 %s로 거부되어야 함", REASON_INSUFFICIENT_BLOX)
	)

	-- 상한이 WorldConfig에서 파생되는지. 숫자를 적지 않고 "없는 층"을 찾아 확인한다.
	local beyond = 1
	while StageConfig.hasStage(beyond) do
		beyond = beyond + 1
	end

	-- ⚠️ "충분한 블럭스"를 1e300 같은 고정값으로 두지 않는다. 월드가 늘어 비용이 그
	-- 값을 넘기면 이 검사가 조용히 INSUFFICIENT_BLOX를 보게 되어 확인하려던 것과
	-- 다른 것을 확인하게 된다. 곡선에서 직접 뽑는다 (cost는 범위 밖에도 값을 준다).
	local beyondOk, beyondReason = WarpConfig.canWarp(BigNum.mul(WarpConfig.cost(beyond), BigNum.fromNumber(10)), beyond)
	assert(
		not beyondOk and beyondReason == REASON_STAGE_OUT_OF_RANGE,
		string.format(
			"WarpConfig: 담당 월드가 없는 층(%d)은 블럭스가 충분해도 %s로 거부되어야 함",
			beyond,
			REASON_STAGE_OUT_OF_RANGE
		)
	)

	-- 사유 코드가 서로 겹치면 UI가 세 상황을 구분하지 못한다.
	assert(
		REASON_INVALID_STAGE ~= REASON_STAGE_OUT_OF_RANGE
			and REASON_STAGE_OUT_OF_RANGE ~= REASON_INSUFFICIENT_BLOX
			and REASON_INVALID_STAGE ~= REASON_INSUFFICIENT_BLOX,
		"WarpConfig: 거부 사유 코드가 중복됨"
	)

	return true
end

return WarpConfig

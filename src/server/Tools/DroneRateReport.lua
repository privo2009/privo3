--!strict
-- 드론 수입 환산 리포트. DESIGN.md "5. 드론"의 "능동 플레이가 분당 20~60배 효율이어야
-- 한다"를 실측으로 판정한다. 드론 스테이지 오프셋이 현재 명세상 maxStage - 2인데
-- 이 값이 그 규약을 만족하는지 이 리포트 결과로 확정한다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다.
--    프로필·CurrencyService·(플레이어의) maxStage를 읽지 않는다 — Config와
--    StandardPathReport의 정적 시뮬레이션 결과만 읽어 순수 계산 후 print한다.
--    여기서 다루는 "층" 1~25는 전부 **가상의 maxStage 값**이다. 특정 플레이어의
--    진행도가 아니다 (DESIGN.md "5. 드론"의 "드론 스테이지 = maxStage - 2"에서
--    maxStage는 프로필 필드이지만, 이 리포트는 그 필드를 읽지 않고 1~25 전체를 스윕한다).
--
-- 모양은 두 선례를 섞었다:
--   Tests/WarpConversionReport — 층별 정적 환산 + 로그 출력이라는 리포트의 모양.
--   Tools/StandardPathReport   — Bootstrap 플래그로 켜고 끄는 방식(기본 false), 파일
--                                 위치(Tools), 파일명 규칙(.lua 모듈 + .run()).
--
-- ===== 수치는 여기 없다 ===============================================================
--
-- ⚠️ 밸런싱 수치를 이 파일에 복사하지 말 것.
--    보상 곡선(bloxBase, bloxGrowthSegments) → WorldConfig / StageConfig.getBloxReward.
--    능동 벌이 속도                          → StandardPathReport.simulateAll (읽기 전용).
--    드론 수입 공식(1대 = 60초당 그 층 보상 1회, 상한 5대, 오프라인 상한 8시간)은
--    DESIGN.md "5. 드론"에 있는 그대로이고, 이 파일은 그 식만 적용한다 — 임의로
--    지급 주기·배수·상한을 새로 정하지 않았다.
--
-- 아래 SWEEP 테이블만 예외다. 그것은 **이 리포트 자체의 스윕 파라미터이지 게임 밸런스
-- 값이 아니다.** 지시된 범위(층 1~25, 오프셋 0~5) 그대로다 — 이 파일이 새로 정한 수치가
-- 아니다.
--
-- ===== 능동 벌이 속도를 어떻게 뽑았는가 ===============================================
--
-- StandardPathReport는 run() 하나만 공개하던 리포트였다. 이 리포트가 필요로 하는
-- "층별 능동 벌이 속도(분당)"를 반환값으로도 모듈 API로도 노출하지 않아서, 그 파일에
-- StandardPathReport.simulateAll(maxStage) / getClickRates()를 export로 추가했다
-- (별도 커밋). 이 파일은 그 함수가 돌려주는 StageRecord만 읽는다 — 시뮬레이션 로직은
-- 재구현하지 않는다.
--
-- 여기까지 오는 데 세 번 틀렸다. 세 번 다 남긴다 — 같은 자리를 다시 파지 않기 위해서다.
--
-- ⚠️ 1차: "층 N 진입 시점 lifetimeBlox → 층 N+1 진입 시점 lifetimeBlox"의 증가량을
--    시간차로 나눴다. 표준 경로는 정지선(37%)에 걸릴 때까지 여러 층을 한 런 안에서 내리
--    통과하고, blox는 그 런이 끝나 커밋되는 순간에만 한 번 붙는다(runOnce:
--    "state.blox = BigNum.add(...)"는 런당 1회). 런 중간에 지나친 층들은 그 구간 동안
--    늘어난 lifetimeBlox가 실제로 0이라서, 대부분의 층에서 벌이 속도를 0으로 찍고
--    커밋이 일어난 층에만 몰아준다 — 층별 축이 사실상 사라진다.
--
-- ⚠️ 2차: "지금 이 층에서 수령했다면" 가정으로 바꾸되, 분모를 시작부터의 **누적** 시간
--    T(N)(= N층 첫 도달까지 걸린 elapsedSec)으로 썼다 — reward(N) ÷ T(N). 앞 구간이
--    굼뜨면(예: 초반 절벽) 그 저효율이 뒤 층까지 희석되어 남아 후반 벌이 속도가 실제보다
--    낮게 나온다. 이 리포트가 정하는 값이 바로 그 비율로 고르는 오프셋이므로, 후반
--    과소평가는 판정 자체를 뒤집을 수 있는 오류였다.
--
-- ⚠️ 3차: 분모를 T(N) - T(N-1)로 좁혔다 — 그런데 이건 **N-1층에서 파밍한 시간**이다.
--    N층 벌이 속도의 분모가 아니라 N-1층 벌이 속도의 분모를 한 칸 밀어 쓴 것이었다.
--
-- 그래서 쓰는 정의: 분모는 **N층에 도달한 뒤 N+1층으로 넘어가기까지 걸린 시간**이다 —
-- StandardPathReport가 printRateTable에서 "체류(분)"으로 이미 찍고 있는 바로 그 값이다
-- (내부 함수 transitionOf가 하는 계산과 같다. export되지 않아 여기서 elapsedSec 두 개의
-- 차로 다시 만든다 — 시뮬레이션을 재구현하는 게 아니라 이미 노출된 값의 산술이다).
--   체류(N) = T(N+1) - T(N)      (1층 포함 모든 층 — T(0)을 쓰지 않는다, 2차·3차와 다르다)
--   능동 벌이 속도(N층, 분당) = StageConfig.getBloxReward(N) ÷ 체류(N) × 60
--
-- 의미: "N층에 선 채로 다음 층을 준비하는 그 시간 동안, N층 보상 1회어치를 벌었다".
-- reward(N)이 실제 커밋값이 아니라 보상 곡선 함수값이라는 점은 앞선 정의들과 같다 —
-- 런 중간 통과 여부와 무관하고, 커밋 시점에 몰리는 문제가 없다는 성질도 그대로 유지된다.
--
-- ⚠️ 마지막 층(FLOOR_MAX = 25)은 다음 층이 없어 체류를 만들 수 없다 — StandardPathReport
--    시뮬레이터가 그 층에 처음 닿는 순간 기록을 멈춘다(다음 월드가 아직 없어서이기도
--    하다). 그 층은 "-"로 비우고 범위·중앙값 집계에서 제외한다. 24층 값을 재활용하거나
--    다른 값으로 대체하지 않는다 — 근거 없이 채우면 틀린 숫자가 판단 근거가 된다.
--
-- ===== 이 정의가 보상 곡선과 어떻게 관계되는가 ========================================
--
-- 비율(N층, 오프셋 k) = 능동 벌이 속도(N) ÷ 드론1대수입(N-k)
--                     = [reward(N) ÷ 체류(N)] ÷ reward(N-k)
--                     = [reward(N) ÷ reward(N-k)] ÷ 체류(N)
-- 월드 1의 bloxGrowthSegments는 stageRange 전체(1~25)가 성장률 단일 구간이므로,
-- N과 N-k가 둘 다 이 범위 안이면 reward(N) ÷ reward(N-k) = growth^k로 정확히 약분된다
-- (segmentedGrowthMultiplier가 bloxBase를 공통 인수로 곱하고 시작하므로 bloxBase는
-- 분자·분모에서 완전히 사라진다). 즉:
--   비율(N, k) = growth^k ÷ 체류(N)
-- **bloxBase를 바꿔도 이 표는 움직이지 않는다** — bloxBase는 reward(N)과 reward(N-k)
-- 양쪽에 똑같이 곱해져 약분되기 때문이다. 반면 **growth(현재 2.7)는 약분되지 않고
-- 남는다** — growth를 바꾸면 growth^k가 바뀌어 이 표의 절대값도 함께 움직인다. 체류(N)
-- 자체는 hpGrowthSegments·공격·클릭 파워 등 완전히 다른 축에서 나오므로 보상 곡선과
-- 아예 무관하다.
--
-- 아래 실제 계산은 이 닫힌 식을 쓰지 않고 StageConfig.getBloxReward를 그대로 두 번
-- 불러 BigNum으로 나눈다 — 위 약분은 "현재 월드 1이 단일 성장 구간이라 성립하는" 사실
-- 확인용이고, bloxGrowthSegments가 여러 구간으로 늘어나면 이 닫힌 식은 깨지지만
-- getBloxReward를 직접 부르는 아래 코드는 그때도 그대로 맞다.
--
-- ⚠️ [1](오프셋 스윕)은 StandardPathReport 밴드(6/8/10) 세 클릭률을 전부 찍는다 — 체류
--    시간이 클릭률마다 다르므로 하나만 보면 그 결론이 다른 클릭률에서도 성립하는지 알
--    수 없다. [2](오프라인 환산)는 기준 클릭률 8 하나만 쓴다 — WarpConversionReport가
--    "기준 단가"로 쓴 것과 같은 기준점이고, 오프라인 환산까지 세 벌로 찍으면 표가 너무
--    커진다(오프셋 6 × 클릭률 3 × 층 25 × 드론대수 2).
--
-- 사용:
--   Bootstrap의 DRONE_RATE_REPORT_ENABLED 블록이 부른다. 기본값 false.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)

-- 읽기 전용 require. 이 모듈을 고치지 않는다 — StandardPathReport.simulateAll이
-- 돌려주는 값만 쓴다.
local StandardPathReport = require(script.Parent.StandardPathReport)

type BigNumber = BigNum.BigNumber
type StageRecord = StandardPathReport.StageRecord
type RateResult = StandardPathReport.RateResult

local DroneRateReport = {}

-- ===== 이 리포트의 스윕 파라미터 =====================================================
--
-- ⚠️ 게임 밸런스 값이 아니다. 작업 지시가 못박은 스윕 범위 그대로다 — 이 파일이 새로
--    정한 수치가 아니고, 여기 있는 값을 바꿔도 게임은 변하지 않는다.
local SWEEP = {
	FLOOR_MIN = 1,
	FLOOR_MAX = 25,
	OFFSET_MIN = 0,
	OFFSET_MAX = 5,

	-- WarpConversionReport가 "기준 단가"로 쓴 것과 같은 클릭률. StandardPathReport의
	-- 밴드(6/8/10) 중 중앙값이다.
	REFERENCE_CLICK_RATE = 8,

	DRONE_COUNTS = { 1, 5 }, -- DESIGN.md "5. 드론": 상한 5대
	OFFLINE_HOURS = 8, -- DESIGN.md "5. 드론": 오프라인 상한 8시간

	-- DESIGN.md "5. 드론": "능동 플레이가 분당 20~60배 효율이어야 한다"의 판정 기준선.
	THRESHOLD_LOW = 20,
	THRESHOLD_HIGH = 60,

	-- DESIGN.md 명세상 현재 값(드론 스테이지 = maxStage - 2). 표시용 — 이 리포트가
	-- 오프셋을 이 값으로 강제하지 않는다. 스윕 결과 전체를 보고 이 값이 맞는지 확인하는
	-- 것이 이 리포트의 목적이다.
	CURRENT_OFFSET = 2,
}

local WORLD_ID = 1

-- ===== 헬퍼 =========================================================================

-- a / b를 배수(raw number)로. 이 리포트가 다루는 값은 25층 보상(성장률 2.7배/층 기준
-- 2.7^24 ≈ 4.4e10 안팎)이라 BigNum.toRatio의 포화 범위(±10^308)를 넘지 않는다 —
-- WarpConversionReport와 같은 이유로 로그 차이 우회가 필요 없다.
local function ratio(a: BigNumber, b: BigNumber): number
	return BigNum.toRatio(a, b)
end

-- Formatter.format은 tier(= floor(e/3)) >= 0만 지원한다(값이 1 미만이면 e < 0이라
-- Formatter.lua 상단 assert가 터진다 — StandardPathReport.formatPowerValue와 같은 우회).
-- droneIncome(=reward, stage≥1이면 항상 ≥1)은 이 경로를 안 밟지만 earnRate는 이론상
-- reward가 아주 작고 elapsedSec이 아주 클 때 1 미만으로 내려갈 수 있어 방어적으로 둔다.
local function formatBig(value: BigNumber): string
	if value.e >= 0 then
		return Formatter.format(value)
	end
	return string.format("%.4f", value.m * 10 ^ value.e)
end

local function median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local n = #sorted
	if n % 2 == 1 then
		return sorted[(n + 1) / 2]
	end
	return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

-- ===== 능동 벌이 속도 =================================================================
--
-- run()이 StandardPathReport.simulateAll을 한 번만 돌려서 [1](세 클릭률 전부)과
-- [2](기준 클릭률만) 양쪽에 같은 결과를 넘긴다 — 두 번 돌 이유가 없다.
-- 이 함수는 그 결과들 중 기준 클릭률(8) 하나를 골라낸다.
local function findReferenceResult(results: { RateResult }): RateResult
	local clickRates = StandardPathReport.getClickRates()
	local referenceIndex: number? = nil
	for i, rate in ipairs(clickRates) do
		if rate == SWEEP.REFERENCE_CLICK_RATE then
			referenceIndex = i
			break
		end
	end
	assert(
		referenceIndex ~= nil,
		string.format(
			"DroneRateReport: StandardPathReport의 클릭률 밴드에 기준 단가 %d가 없다 (밴드: %s)",
			SWEEP.REFERENCE_CLICK_RATE,
			table.concat(clickRates, ",")
		)
	)

	return results[referenceIndex :: number]
end

-- N층에 도달한 뒤 N+1층으로 넘어가기까지 걸린 시간(초) — StandardPathReport의
-- "체류(분)"과 같은 계산(elapsedSec 두 값의 차)이다. 마지막 층(다음 기록이 없는 층)이나
-- 시뮬레이터가 도달하지 못한 층에서는 nil이다.
local function staySecAtFloor(records: { [number]: StageRecord }, floor: number): number?
	local here = records[floor]
	local next_ = records[floor + 1]
	if here == nil or next_ == nil then
		return nil
	end
	return next_.elapsedSec - here.elapsedSec
end

-- "N층에 선 채로 다음 층을 준비하는 그 시간 동안 N층 보상 1회어치를 벌었다" 가정의
-- 능동 벌이 속도(분당) — reward(N) ÷ 체류(N) × 60. 파일 상단 "능동 벌이 속도를 어떻게
-- 뽑았는가" 참고.
local function earnRatePerMinAtFloor(records: { [number]: StageRecord }, floor: number): BigNumber?
	local stay = staySecAtFloor(records, floor)
	if stay == nil then
		return nil
	end
	if stay <= 0 then
		-- ⚠️ 방어 코드로 덮지 않는다 — 정상 경로에서는 시각이 항상 전진하므로(각 틱마다
		--    elapsedSec += DT_SEC, StandardPathReport 상단 SIM.DT_SEC 참고) 여기 걸리면
		--    시뮬레이터 쪽 이상이다. 조용히 "-"로 비우지 않고 어느 층에서 어떤 값이
		--    나왔는지 그대로 찍는다.
		local here = records[floor]
		local next_ = records[floor + 1]
		warn(string.format(
			"[DroneRateReport] ⚠️ %d층 체류가 0 이하다 (T(%d)=%.4f초, T(%d)=%.4f초, 체류=%.4f초) — 이 층은 비워둔다.",
			floor,
			floor + 1,
			next_ and next_.elapsedSec or -1,
			floor,
			here and here.elapsedSec or -1,
			stay
		))
		return nil
	end

	local reward = StageConfig.getBloxReward(floor)
	return BigNum.mul(BigNum.div(reward, BigNum.fromNumber(stay)), BigNum.fromNumber(60))
end

-- ===== 드론 수입 =====================================================================
--
-- DESIGN.md "5. 드론": "드론 1대 = 60초당 해당 스테이지 보상 1회". 드론 스테이지가
-- 존재하지 않으면(층 - 오프셋 < 1) nil — 오프셋이 층보다 큰 칸은 정의 자체가 없다.
local function droneStageOf(floor: number, offset: number): number?
	local droneStage = floor - offset
	if droneStage < 1 or not StageConfig.hasStage(droneStage) then
		return nil
	end
	return droneStage
end

local function droneIncomePerMinOneDrone(floor: number, offset: number): BigNumber?
	local droneStage = droneStageOf(floor, offset)
	if droneStage == nil then
		return nil
	end
	return StageConfig.getBloxReward(droneStage)
end

-- ===== [1] 오프셋 스윕 ================================================================

-- 한 (오프셋, 클릭률) 조합의 층별 표 + 범위·중앙값 요약. 마지막 층(FLOOR_MAX)은 체류가
-- 없어 항상 "-"로 비고 range/median 집계에서 빠진다 — 파일 상단 "마지막 층" 주석 참고.
local function printOffsetSweepBlock(records: { [number]: StageRecord }, offset: number)
	print("  층 | 능동 벌이 속도(분당) | 드론1대 수입(분당) |      비율")
	print("  ---+-----------------------+---------------------+-----------")

	local ratios: { number } = {}
	for floor = SWEEP.FLOOR_MIN, SWEEP.FLOOR_MAX do
		local earnRate = earnRatePerMinAtFloor(records, floor)
		local droneIncome = droneIncomePerMinOneDrone(floor, offset)

		if earnRate == nil or droneIncome == nil then
			local reason
			if droneIncome == nil then
				reason = "(드론 스테이지 없음)"
			elseif floor == SWEEP.FLOOR_MAX then
				reason = "(마지막 층 — 체류 없음)"
			else
				reason = "(시뮬레이터가 다음 층에 도달 못함)"
			end
			print(string.format("  %2d | %s", floor, reason))
		else
			local r = ratio(earnRate, droneIncome)
			table.insert(ratios, r)
			print(string.format(
				"  %2d | %21s | %19s | %9.2f",
				floor,
				formatBig(earnRate),
				formatBig(droneIncome),
				r
			))
		end
	end

	if #ratios == 0 then
		print("  (이 오프셋에서 비율을 구한 층이 없다)")
	else
		local lo, hi = ratios[1], ratios[1]
		for _, r in ipairs(ratios) do
			lo = math.min(lo, r)
			hi = math.max(hi, r)
		end
		local med = median(ratios) :: number
		local band = (lo >= SWEEP.THRESHOLD_LOW and hi <= SWEEP.THRESHOLD_HIGH) and "OK — 전 구간이 기준선 안"
			or (hi < SWEEP.THRESHOLD_LOW and "⚠️ 전 구간이 하한 밑 — 드론이 능동보다 셈")
			or (lo > SWEEP.THRESHOLD_HIGH and "⚠️ 전 구간이 상한 위 — 드론이 지나치게 약함")
			or "혼재 — 층마다 기준선 안팎이 갈림"
		print(string.format(
			"  범위 %.2f ~ %.2f배 / 중앙값 %.2f배 (%d개 층, 마지막 층 제외) — %s",
			lo,
			hi,
			med,
			#ratios,
			band
		))
	end
end

-- results: StandardPathReport.simulateAll이 돌려주는 순서 그대로(클릭률 6/8/10) 전부.
-- 체류 시간이 클릭률마다 다르므로 [1]은 하나로 뭉치지 않고 세 벌을 다 찍는다.
local function printOffsetSweep(results: { RateResult })
	print(string.format(
		"\n================ [1] 오프셋 스윕 (판정 기준선 %d배 / %d배) ================",
		SWEEP.THRESHOLD_LOW,
		SWEEP.THRESHOLD_HIGH
	))
	print("  비율 = 능동 벌이 속도(분당, 그 층) / 드론 1대 수입(분당) = reward(층 - 오프셋)")
	print("  능동 벌이 속도(그 층) = reward(그 층) ÷ 체류(그 층) — 체류 = 그 층 도달부터 다음 층 도달까지 걸린 시간.")
	print("  ⚠️ 이 표는 보상 곡선의 bloxBase와 무관하다(분자·분모에서 약분). growth(현재 2.7)에는")
	print("     여전히 의존한다 — 비율(N,k) = growth^k ÷ 체류(N) (파일 상단 \"보상 곡선과 어떻게 관계되는가\" 참고).")
	print(string.format(
		"  ⚠️ 현재 명세 오프셋 = %d (DESIGN.md \"드론 스테이지 = maxStage - 2\"). 아래 블록에서 표시를 본다.",
		SWEEP.CURRENT_OFFSET
	))

	for offset = SWEEP.OFFSET_MIN, SWEEP.OFFSET_MAX do
		local marker = offset == SWEEP.CURRENT_OFFSET and "  ← 현재 명세" or ""
		print(string.format("\n--- 오프셋 %d%s ---", offset, marker))

		for _, result in ipairs(results) do
			print(string.format("\n  [클릭률 %d]", result.clickRate))
			printOffsetSweepBlock(result.records, offset)
		end
	end
end

-- ===== [2] 오프라인 8시간 환산 =======================================================

local function formatMinutes(value: number): string
	if value ~= value or value == math.huge then
		return "     nan"
	end
	if value >= 100000 then
		return string.format("%.3e", value)
	end
	return string.format("%10.2f", value)
end

local function printOfflineConversion(records: { [number]: StageRecord })
	local offlineMinutes = SWEEP.OFFLINE_HOURS * 60

	print(string.format(
		"\n================ [2] 오프라인 %d시간 환산 ================",
		SWEEP.OFFLINE_HOURS
	))
	print(string.format(
		"  \"오프라인 %d시간 수입 = 능동 플레이 몇 분어치인가\" = 드론대수 × %d분 × 드론1대수입(분당) ÷ 능동벌이속도(분당, 그 층)",
		SWEEP.OFFLINE_HOURS,
		offlineMinutes
	))
	print(string.format(
		"  ⚠️ [1]은 클릭률 3벌을 다 찍지만 이 표는 기준 클릭률 %d 하나만 쓴다(표가 오프셋×층×클릭률×드론대수로",
		SWEEP.REFERENCE_CLICK_RATE
	))
	print("     불어나는 것을 피하려는 것이지 값이 다르다는 뜻이 아니다). 드론 스테이지가 없는 칸([1]과 같은 이유)은 비어있다.")

	for offset = SWEEP.OFFSET_MIN, SWEEP.OFFSET_MAX do
		local marker = offset == SWEEP.CURRENT_OFFSET and "  ← 현재 명세" or ""
		print(string.format("\n--- 오프셋 %d%s ---", offset, marker))

		local header = "  층 |"
		local sep = "  ---+"
		for _, count in ipairs(SWEEP.DRONE_COUNTS) do
			header = header .. string.format(" 드론%d대 몇 분어치 |", count)
			sep = sep .. "--------------------+"
		end
		print(header)
		print(sep)

		for floor = SWEEP.FLOOR_MIN, SWEEP.FLOOR_MAX do
			local earnRate = earnRatePerMinAtFloor(records, floor)
			local droneIncome = droneIncomePerMinOneDrone(floor, offset)

			local row = string.format("  %2d |", floor)
			if earnRate == nil or droneIncome == nil then
				for _ in ipairs(SWEEP.DRONE_COUNTS) do
					row = row .. "                    |"
				end
			else
				local r = ratio(earnRate, droneIncome)
				for _, count in ipairs(SWEEP.DRONE_COUNTS) do
					local minutesWorth = count * offlineMinutes / r
					row = row .. string.format(" %18s |", formatMinutes(minutesWorth))
				end
			end
			print(row)
		end
	end
end

-- ===== 진입점 =======================================================================

function DroneRateReport.run()
	local world = WorldConfig.get(WORLD_ID)
	assert(world ~= nil, "DroneRateReport: 월드가 없다")

	local clickRates = StandardPathReport.getClickRates()
	print("[DroneRateReport] 드론 수입 환산 리포트 — 값의 원본은 Config, 여기엔 수치가 없다")
	print(string.format(
		"  층 %d~%d / 오프셋 %d~%d / [1] 클릭률 %s 전부 / [2] 기준 클릭률 %d만 / 드론 %s대 / 오프라인 상한 %d시간",
		SWEEP.FLOOR_MIN,
		SWEEP.FLOOR_MAX,
		SWEEP.OFFSET_MIN,
		SWEEP.OFFSET_MAX,
		table.concat(clickRates, "·"),
		SWEEP.REFERENCE_CLICK_RATE,
		table.concat(SWEEP.DRONE_COUNTS, "/"),
		SWEEP.OFFLINE_HOURS
	))
	print("  ⚠️ 게임 상태를 읽지 않는다 — 프로필도 CurrencyService도 플레이어의 maxStage도 참조하지 않는다.")
	print("     여기서 스윕하는 층 1~25는 전부 가상의 maxStage 값이다.")

	local results = StandardPathReport.simulateAll(SWEEP.FLOOR_MAX)
	local reference = findReferenceResult(results)

	printOffsetSweep(results)
	printOfflineConversion(reference.records)

	print("\n[DroneRateReport] 끝.")
end

return DroneRateReport

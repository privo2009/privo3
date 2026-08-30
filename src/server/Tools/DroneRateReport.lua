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
-- ⚠️ 처음에는 "층 N 진입 시점 lifetimeBlox → 층 N+1 진입 시점 lifetimeBlox"의 증가량을
--    시간차로 나누려 했다. **틀렸다.** 표준 경로는 정지선(37%)에 걸릴 때까지 여러 층을
--    한 런 안에서 내리 통과하고, blox는 그 런이 끝나 커밋되는 순간에만 한 번 붙는다
--    (runOnce: "state.blox = BigNum.add(...)"는 런당 1회). 즉 런 중간에 지나친 층들은
--    그 구간 동안 늘어난 lifetimeBlox가 실제로 0이라서, 그 방식은 대부분의 층에서 벌이
--    속도를 0으로 잘못 찍고 커밋이 일어난 층에만 몰아준다 — 층별 축이 사실상 사라진다.
--
-- 그래서 쓰는 정의: **"지금 이 층에서 수령했다면"** 가정이다.
--   능동 벌이 속도(그 층, 분당) = StageConfig.getBloxReward(그 층) ÷ 그 층 첫 도달까지
--                                걸린 elapsedSec × 60
-- reward(그 층)는 게임이 실제로 그 층 수령에 매기는 값이고(챌린지의 두 선택 중 "수령"),
-- elapsedSec은 StandardPathReport가 이미 "도달(분)" 열로 찍는 값과 같다 — 그 층에
-- 설 수 있게 되기까지 투입된 누적 능동 플레이 시간이다. 이 정의는:
--   - 모든 층 1~25에 항상 값이 있다 (마지막 층도 포함 — elapsedSec은 도달하는 순간
--     기록되고, reward도 그 층 값이 바로 나온다. lifetimeBlox 델타 방식과 달리 "다음
--     층 기록"이 필요 없다).
--   - 런 중간 통과 여부와 무관하다 — 실제로 그 순간 수령을 선택했다면 나왔을 값이므로
--     커밋 시점에 몰리는 문제가 없다.
--
-- ⚠️ 클릭률은 StandardPathReport 밴드(6/8/10) 중 8만 쓴다. WarpConversionReport가
--    "기준 단가·클릭률 8"이라 부른 것과 같은 기준점이다 — 이 리포트가 새로 정한 값이
--    아니라 기존 선례를 따른 것이다. 세 클릭률을 전부 펼치면 오프셋×층 격자 표가 클릭률
--    축까지 늘어나 지시된 표 모양(오프셋×층)을 벗어난다.
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

-- ===== 능동 벌이 속도 (기준 클릭률 8) ================================================
--
-- StandardPathReport.simulateAll을 한 번만 돌려서 캐싱한다 — 오프셋 스윕(0~5)과
-- 오프라인 환산 양쪽이 같은 능동 벌이 속도를 참조하므로 두 번 돌 이유가 없다.
local function getReferenceResult(): RateResult
	local results = StandardPathReport.simulateAll(SWEEP.FLOOR_MAX)

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

-- "지금 이 층에서 수령했다면" 가정의 능동 벌이 속도(분당). 그 층에 시뮬레이터가
-- 도달하지 못했으면(런/틱 예산 소진 등) nil이다 — 파일 상단 "능동 벌이 속도를 어떻게
-- 뽑았는가" 참고.
local function earnRatePerMinAtFloor(records: { [number]: StageRecord }, floor: number): BigNumber?
	local record = records[floor]
	if record == nil or record.elapsedSec <= 0 then
		return nil
	end

	local reward = StageConfig.getBloxReward(floor)
	return BigNum.mul(BigNum.div(reward, BigNum.fromNumber(record.elapsedSec)), BigNum.fromNumber(60))
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

local function printOffsetSweep(records: { [number]: StageRecord })
	print(string.format(
		"\n================ [1] 오프셋 스윕 (판정 기준선 %d배 / %d배) ================",
		SWEEP.THRESHOLD_LOW,
		SWEEP.THRESHOLD_HIGH
	))
	print(string.format(
		"  비율 = 능동 벌이 속도(분당, 그 층, 클릭률 %d 기준) / 드론 1대 수입(분당) = reward(층 - 오프셋)",
		SWEEP.REFERENCE_CLICK_RATE
	))
	print(string.format(
		"  ⚠️ 현재 명세 오프셋 = %d (DESIGN.md \"드론 스테이지 = maxStage - 2\"). 그 줄을 찾으려면 아래 블록에서 표시를 본다.",
		SWEEP.CURRENT_OFFSET
	))

	for offset = SWEEP.OFFSET_MIN, SWEEP.OFFSET_MAX do
		local marker = offset == SWEEP.CURRENT_OFFSET and "  ← 현재 명세" or ""
		print(string.format("\n--- 오프셋 %d%s ---", offset, marker))
		print("  층 | 능동 벌이 속도(분당) | 드론1대 수입(분당) |      비율")
		print("  ---+-----------------------+---------------------+-----------")

		local ratios: { number } = {}
		for floor = SWEEP.FLOOR_MIN, SWEEP.FLOOR_MAX do
			local earnRate = earnRatePerMinAtFloor(records, floor)
			local droneIncome = droneIncomePerMinOneDrone(floor, offset)

			if earnRate == nil or droneIncome == nil then
				local reason = droneIncome == nil and "(드론 스테이지 없음)" or "(시뮬레이터가 이 층에 도달 못함)"
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
				"  범위 %.2f ~ %.2f배 / 중앙값 %.2f배 (%d개 층) — %s",
				lo,
				hi,
				med,
				#ratios,
				band
			))
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
	print("  ⚠️ [1]과 같은 층·같은 능동 벌이 속도(클릭률 기준값)를 쓴다. 드론 스테이지가 없는 칸([1]과 같은 이유)은 비어있다.")

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

	print("[DroneRateReport] 드론 수입 환산 리포트 — 값의 원본은 Config, 여기엔 수치가 없다")
	print(string.format(
		"  층 %d~%d / 오프셋 %d~%d / 기준 클릭률 %d / 드론 %s대 / 오프라인 상한 %d시간",
		SWEEP.FLOOR_MIN,
		SWEEP.FLOOR_MAX,
		SWEEP.OFFSET_MIN,
		SWEEP.OFFSET_MAX,
		SWEEP.REFERENCE_CLICK_RATE,
		table.concat(SWEEP.DRONE_COUNTS, "/"),
		SWEEP.OFFLINE_HOURS
	))
	print("  ⚠️ 게임 상태를 읽지 않는다 — 프로필도 CurrencyService도 플레이어의 maxStage도 참조하지 않는다.")
	print("     여기서 스윕하는 층 1~25는 전부 가상의 maxStage 값이다.")

	local reference = getReferenceResult()

	printOffsetSweep(reference.records)
	printOfflineConversion(reference.records)

	print("\n[DroneRateReport] 끝.")
end

return DroneRateReport

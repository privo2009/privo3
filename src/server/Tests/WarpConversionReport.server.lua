--!strict
-- 워프 TEMP 두 값(TEMP_COST_BASE / TEMP_COST_RATIO) 환산 리포트 (4-2-f 우선순위 4).
-- Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 CurveReport 옆에서 함께 출력된다.
--
-- ⚠️ StandardPathReport에는 넣지 않는다. 워프는 환생과 같은 지갑(blox)을 쓰므로,
--    표준 경로 시뮬레이터에 워프 소비를 넣으면 방금 확정한 환생 주기(BLOX_PER_REBIRTH
--    스윕 결과)가 통째로 움직인다. 이 리포트는 시뮬레이터가 아니라 **모델 밖 환산**이다 —
--    각 층의 워프 비용을 다른 잣대(그 층 보상, 환생 단가, 실측 벌이 속도)로 나눠볼 뿐,
--    아무 상태도 진행시키지 않는다.
--
-- 이것도 리포트다. pass/fail을 세지 않고 숫자만 찍는다 (CurveReport와 같은 성격).
--
-- ⚠️ WarpConfig / RebirthConfig / WorldConfig는 읽기만 한다. 값을 바꾸지 않는다.
--    수치는 전부 그 세 Config에서 읽는다 — 이 파일에 게임 수치를 하드코딩하지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

type BigNumber = BigNum.BigNumber

-- ===== "몇 분어치"의 근거 (⚠️ Config 값이 아니라 실측 참조점) =========================
--
-- StandardPathReport(기준 단가·클릭률 8)를 실제로 돌려서 나온 값이다. Config에서 유도할
-- 수 없는 수치라 상수로 남긴다 — 이 두 값 자체가 게임 밸런스가 아니라 "그때 그 실행의
-- 관측값"이기 때문이다.
--
-- ⚠️ 구간별 벌이 속도가 전혀 다르므로 이 평균값을 저층에 그대로 쓰면 크게 틀린다.
--    그래서 이 리포트는 "몇 분어치" 열을 **25층(도달 시점) 한 점에만** 채운다.
--    나머지 층은 "-"로 비워둔다 — 근거 없이 채우면 틀린 숫자가 판단 근거가 된다.
--
-- ⚠️ StandardPathReport의 시뮬레이터 파라미터(SIM.CLICK_RATES, 세그먼트 등)가 바뀌면
--    이 두 값도 다시 재야 한다. 재측정 없이 이 상수만 남아있으면 조용히 낡은 값이 된다.
local REFERENCE = {
	ELAPSED_MIN = 48.7, -- 25층 첫 도달까지 걸린 시간(분)
	LIFETIME_BLOX = BigNum.new(1.4153, 11), -- 그 시점 lifetimeBlox (141.53B)
}

-- a / b를 배수(일반 number)로. 이 리포트가 다루는 값들은 10^13 안팎이라 BigNum.toRatio의
-- 포화 범위(±10^308)를 넘지 않는다 — StandardPathReport처럼 로그 차이로 우회할 필요가 없다.
local function ratio(a: BigNumber, b: BigNumber): number
	return BigNum.toRatio(a, b)
end

local world = WorldConfig.get(1)
assert(world ~= nil, "WarpConversionReport: 월드 1이 없다")
local maxStage = (world :: WorldConfig.WorldDef).stageRange[2]

print("\n[WarpConversionReport] 워프 TEMP 두 값 환산 리포트 (4-2-f 우선순위 4)")
print("  값의 원본은 WarpConfig / RebirthConfig / WorldConfig — 여기엔 게임 수치가 없다.")
print(string.format(
	"  워프 비용 = TEMP_COST_BASE(%d) × TEMP_COST_RATIO(%.1f)^(목표층-1)",
	WarpConfig._pure.TEMP_COST_BASE,
	WarpConfig._pure.TEMP_COST_RATIO
))
print(string.format("  BLOX_PER_REBIRTH = %d", RebirthConfig.BLOX_PER_REBIRTH))
print(string.format(
	"  \"몇 분어치\" 근거(실측, 25층 한 점만): %d층 첫 도달 %.1f분 / lifetimeBlox %s",
	maxStage,
	REFERENCE.ELAPSED_MIN,
	Formatter.format(REFERENCE.LIFETIME_BLOX)
))

print("\n  층 |       워프 비용 |       그층 보상 | 몇 판어치 | 몇 환생어치 |  몇 분어치")
print("  ---+------------------+------------------+-----------+-------------+-----------")

for stage = 1, maxStage do
	local warpCost = WarpConfig.cost(stage)
	local stageReward = StageConfig.getBloxReward(stage)

	local runsWorth = ratio(warpCost, stageReward)
	local rebirthsWorth = ratio(warpCost, BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH))

	local minutesText = "         -"
	if stage == maxStage then
		-- 워프 비용 ÷ 그 시점 lifetimeBlox × 그 시점까지 걸린 분 = 그 blox를 버는 데 걸리는 시간(분).
		local minutesWorth = ratio(warpCost, REFERENCE.LIFETIME_BLOX) * REFERENCE.ELAPSED_MIN
		minutesText = string.format("%9.1f분", minutesWorth)
	end

	print(string.format(
		"  %2d | %16s | %16s | %8.1f판 | %10.1f회 | %s",
		stage,
		Formatter.format(warpCost),
		Formatter.format(stageReward),
		runsWorth,
		rebirthsWorth,
		minutesText
	))
end

print("\n  ⚠️ \"몇 분어치\"는 25층 한 점만 근거가 있다. 다른 층에 같은 평균 단가를 적용하면")
print("     저층에서 크게 틀린다 — 구간별 벌이 속도가 다르기 때문이다 (위 REFERENCE 주석 참고).")
print("[WarpConversionReport] 끝. 판단은 4-2-f에서 — 이 리포트는 숫자만 낸다.")

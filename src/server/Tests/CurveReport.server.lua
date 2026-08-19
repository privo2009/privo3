--!strict
-- 커브 검산 리포트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 출력된다.
--
-- 이건 테스트가 아니라 **리포트**다. pass/fail을 세지 않고 숫자만 찍는다.
-- 커브 계약의 pass/fail은 이미 다른 곳이 맡고 있다:
--   곡선 규약 1 (HP 증가율 > 보상 증가율)  → WorldConfig.validate()
--   단조 증가 / 값 범위                    → StageConfig.validate()
-- 여기서 다시 assert하면 같은 계약이 두 곳에 생겨서 어긋난다.
--
-- ⚠️ 성장식을 여기에 다시 구현하지 말 것. StageConfig.getHp/getBloxReward/getBlockCount를
--    그대로 호출한다. 계산식 복사본을 만들면 "코드는 고쳤는데 검산은 옛날 식"이 된다 —
--    CLAUDE.md가 경고하는 바로 그 어긋남이다.
--
-- WorldConfig의 커브를 만졌을 때 이 출력을 보고 판단한다:
--   - 층별 블록HP / 총HP / 보상이 의도한 자릿수인가
--   - 보상/총HP 비율이 단조 하락하는가 (진행이 점점 불리해지는가)
--   - 구간별 평균 증가율이 세그먼트 설정값과 일치하는가
--   - 첫 환생(1000 블럭스)이 몇 층에서 열리는가
--
-- 목표 성공률(DESIGN.md 1. 챌린지)은 여기서 못 잰다. 힘 성장이 있어야 계산되므로
-- Phase 4-2-b(패드)와 4-2-d(환생)가 붙은 뒤 4-2-f에서 다룬다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

type BigNumber = BigNum.BigNumber

-- 환생 1배수의 문턱 (DESIGN.md 3. 화폐와 배수 > 환생: 1000 블럭스 = +1x).
local REBIRTH_THRESHOLD = BigNum.new(1, 3)

-- BigNum은 {가수, 지수}라 상용로그가 그대로 나온다. 비율/기하평균은 이 로그 위에서 계산한다 —
-- BigNum.div로 10^2000급 값을 나누면 표현은 되지만 여기서 필요한 건 배수의 자릿수뿐이다.
local function log10(value: BigNumber): number
	if value.m <= 0 then
		return -math.huge
	end
	return math.log10(value.m) + value.e
end

-- a / b 를 배수(일반 number)로. 자릿수 차이가 크면 inf/0이 되므로 로그 차이로 돌려준다.
local function ratioLog10(a: BigNumber, b: BigNumber): number
	return log10(a) - log10(b)
end

-- 10^x 를 사람이 읽는 문자열로. x가 커도 안전하게 "1.23e45" 형태로 떨어진다.
local function formatPow10(x: number): string
	if x == -math.huge then
		return "0"
	end
	local e = math.floor(x)
	local m = 10 ^ (x - e)
	if e >= -3 and e <= 3 then
		return string.format("%.3f", m * 10 ^ e)
	end
	return string.format("%.2fe%d", m, e)
end

-- 구간 [fromStage, toStage]의 층당 평균 증가율(기하평균). 로그 차이를 칸 수로 나눈다.
local function averageGrowth(getter: (number) -> BigNumber, fromStage: number, toStage: number): number
	local steps = toStage - fromStage
	if steps <= 0 then
		return 1
	end
	return 10 ^ (ratioLog10(getter(toStage), getter(fromStage)) / steps)
end

local function reportWorld(worldId: number, world: WorldConfig.WorldDef)
	local startStage, endStage = world.stageRange[1], world.stageRange[2]

	print(string.format("\n===== 월드 %d (%s) : %d~%d층 =====", worldId, world.name, startStage, endStage))
	print("  층 |     블록HP |       총HP |       보상 | 벽 | 보상/총HP")
	print("  ---+------------+------------+------------+----+-----------")

	local firstRebirthStage: number? = nil
	local prevRatio: number? = nil
	local ratioMonotonic = true

	for stage = startStage, endStage do
		local hp = StageConfig.getHp(stage)
		local total = StageConfig.getTotalHp(stage)
		local reward = StageConfig.getBloxReward(stage)
		local blocks = StageConfig.getBlockCount(stage)

		-- 보상/총HP: 진행이 얼마나 수지맞는가. 층이 오를수록 떨어져야 한다.
		local ratio = ratioLog10(reward, total)
		if prevRatio ~= nil and ratio > prevRatio then
			ratioMonotonic = false
		end
		prevRatio = ratio

		if firstRebirthStage == nil and BigNum.gte(reward, REBIRTH_THRESHOLD) then
			firstRebirthStage = stage
		end

		print(string.format("  %2d | %10s | %10s | %10s | %2d | %9s", stage, Formatter.format(hp), Formatter.format(total), Formatter.format(reward), blocks, formatPow10(ratio)))
	end

	-- 전 구간 요약 ------------------------------------------------------------
	print(string.format("\n  [전 구간] %d~%d층", startStage, endStage))
	print(string.format("    평균 HP 증가율    %.3fx / 층", averageGrowth(StageConfig.getHp, startStage, endStage)))
	print(string.format("    평균 보상 증가율   %.3fx / 층", averageGrowth(StageConfig.getBloxReward, startStage, endStage)))

	local dropLog = ratioLog10(StageConfig.getBloxReward(startStage), StageConfig.getTotalHp(startStage))
		- ratioLog10(StageConfig.getBloxReward(endStage), StageConfig.getTotalHp(endStage))
	print(string.format("    보상/총HP 하락폭   %s 배", formatPow10(dropLog)))
	print(string.format("    보상/총HP 단조 하락 %s", ratioMonotonic and "예 (진행이 점점 불리해짐)" or "아니오 ⚠️ 어딘가에서 진행이 다시 유리해진다"))

	-- 세그먼트별 요약: 설정값과 실측 평균이 어긋나면 세그먼트 경계 계산이 틀린 것이다 ----
	print("\n  [세그먼트별] 설정값 대비 실측 평균")
	for _, segment in ipairs(world.hpGrowthSegments) do
		local from = math.max(segment.from, startStage)
		local to = math.min(segment.to, endStage)
		local actual = averageGrowth(StageConfig.getHp, from, to)
		local mark = math.abs(actual - segment.growth) < 0.01 and "" or "  ⚠️ 설정값과 다름"
		print(string.format("    HP   %2d~%2d층  설정 %.2fx  실측 %.3fx%s", from, to, segment.growth, actual, mark))
	end
	for _, segment in ipairs(world.bloxGrowthSegments) do
		local from = math.max(segment.from, startStage)
		local to = math.min(segment.to, endStage)
		local actual = averageGrowth(StageConfig.getBloxReward, from, to)
		local mark = math.abs(actual - segment.growth) < 0.01 and "" or "  ⚠️ 설정값과 다름"
		print(string.format("    보상 %2d~%2d층  설정 %.2fx  실측 %.3fx%s", from, to, segment.growth, actual, mark))
	end

	-- 정지선: 보상 증가율이 전 구간 고정이면 하나로 떨어진다 (DESIGN.md 곡선 규약 4) --------
	local firstSegment = world.bloxGrowthSegments[1]
	if #world.bloxGrowthSegments == 1 then
		print(string.format("\n  [정지선] 1 / %.2f = %.1f%% — 전 구간 하나 (곡선 규약 3·4 만족)", firstSegment.growth, 100 / firstSegment.growth))
	else
		print("\n  [정지선] ⚠️ 보상 세그먼트가 여러 개다. 곡선 규약 3 위반 — 정지선이 구간마다 달라진다")
		for _, segment in ipairs(world.bloxGrowthSegments) do
			print(string.format("    %2d~%2d층  1 / %.2f = %.1f%%", segment.from, segment.to, segment.growth, 100 / segment.growth))
		end
	end

	-- 첫 환생 도달 층 --------------------------------------------------------
	if firstRebirthStage ~= nil then
		print(string.format("\n  [첫 환생] %d층 보상이 %s 로 1000 돌파 — 여기서 환생 1배수가 열린다", firstRebirthStage, Formatter.format(StageConfig.getBloxReward(firstRebirthStage))))
	else
		print(string.format("\n  [첫 환생] 이 월드 안에서는 1000 블럭스에 도달하지 못한다 (%d층 보상 %s)", endStage, Formatter.format(StageConfig.getBloxReward(endStage))))
	end
end

local ids = {}
for id in pairs(WorldConfig.Worlds) do
	table.insert(ids, id)
end
table.sort(ids)

print("[CurveReport] 커브 검산 리포트 — 값의 원본은 WorldConfig.lua")
for _, id in ipairs(ids) do
	reportWorld(id, WorldConfig.Worlds[id])
end
print("\n[CurveReport] 끝. 목표 성공률 검증은 힘 성장 구현 후 Phase 4-2-f에서.")

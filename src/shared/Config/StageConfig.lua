--!strict
-- 스테이지별 HP / 보상 / 블록 개수 계산. 값을 저장하지 않고 WorldConfig의 성장식으로 매번 계산한다.
-- 블록 HP만 서버가 들고, 큐브 개수는 클라가 HP 비율로 역산한다 (DESIGN.md 2. 블록).

local BigNum = require(script.Parent.Parent.BigNum)
local WorldConfig = require(script.Parent.WorldConfig)

type BigNumber = BigNum.BigNumber
type WorldDef = WorldConfig.WorldDef

local StageConfig = {}

-- 블록 배치 상한 (DESIGN.md: 이중 원 구조 최대 16개).
local MAX_BLOCK_COUNT = 16

-- 월드 안에서 몇 번째 층인가(1부터) → 그 층의 블록 개수.
-- 레퍼런스 25층 실측을 그대로 옮긴 값이다 (레퍼런스는 이것을 "벽"이라 부르지만, 우리
-- 문서에서 벽은 진행 벽 하나를 가리키므로 여기서는 블록으로 쓴다).
-- 총HP = 블록HP × 이 개수. 7층부터 7개로 고정되므로 이후 총HP는 블록HP 곡선을 그대로 따른다.
--
-- 월드 2는 4개에서 다시 시작한다 (DESIGN.md 8. 월드 > 월드 전환 완급). 월드마다 다른
-- 스케줄이 필요해지는 시점에 WorldConfig로 옮긴다 — 지금은 월드 1뿐이라 여기 둔다.
local BLOCK_COUNT_STEPS = {
	{ from = 1, to = 1, count = 3 },
	{ from = 2, to = 2, count = 4 },
	{ from = 3, to = 5, count = 5 },
	{ from = 6, to = 6, count = 6 },
	{ from = 7, to = 25, count = 7 },
}

-- 챌린지 타이머(초). DESIGN.md 1. 챌린지: "20초는 상한이지 라운드 길이가 아니다".
-- 지금은 고정값. 초반 18초→후반 0.5초 같은 스테이지별 체감 단축은 이후 밸런싱 단계에서 다룬다.
StageConfig.CHALLENGE_TIMER_SEC = 20

local function stageOffset(stage: number, world: WorldDef): number
	return stage - world.stageRange[1]
end

-- 성장 세그먼트를 따라 구간별로 다른 배율을 곱해 stage까지의 누적 성장 배수를 계산한다.
-- 시작 스테이지(offset 0) 자체는 성장이 적용되지 않고, 그다음 스테이지로 넘어갈 때마다
-- "도착한 스테이지가 속한 구간"의 growth가 한 번씩 곱해진다.
-- HP(가속)와 보상(고정) 양쪽이 같은 함수를 쓴다.
local function segmentedGrowthMultiplier(stage: number, world: WorldDef, segments: { WorldConfig.GrowthSegment }): BigNumber
	local startStage = world.stageRange[1]
	local multiplier = BigNum.new(1, 0)

	for _, segment in ipairs(segments) do
		local lower = math.max(segment.from, startStage + 1)
		local upper = math.min(segment.to, stage)
		local steps = upper - lower + 1
		if steps > 0 then
			multiplier = BigNum.mul(multiplier, BigNum.pow(BigNum.fromNumber(segment.growth), steps))
		end
	end

	return multiplier
end

function StageConfig.getWorld(stage: number): WorldDef
	local world = WorldConfig.getByStage(stage)
	assert(world ~= nil, string.format("StageConfig: 스테이지 %d에 해당하는 월드가 없음", stage))
	return world :: WorldDef
end

-- 그 스테이지를 담당하는 월드가 실재하는가. getWorld는 없으면 assert로 터지므로,
-- "가도 되는 층인지" 물어보는 쪽은 반드시 이걸 먼저 쓴다.
function StageConfig.hasStage(stage: number): boolean
	return WorldConfig.getByStage(stage) ~= nil
end

-- 현재 정의된 마지막 층인가 (= 다음 층을 담당할 월드가 아직 없다).
-- 월드 중간이면 같은 월드에서, 월드 끝이면 다음 월드에서 stage+1이 찾히므로
-- "stageRange 끝 도달"과 "다음 월드 없음"을 따로 볼 필요가 없다 — 한 번의 조회로 둘 다 덮인다.
-- WorldConfig에 월드를 추가하면 이 함수가 자동으로 false를 돌려주기 시작한다 (코드 수정 불필요).
function StageConfig.isFinalStage(stage: number): boolean
	return not StageConfig.hasStage(stage + 1)
end

-- "지금 나가면 받는" 클리어 보상. 누적이 아니라 스테이지마다 갱신되는 값이다 (푸시-유어-럭).
function StageConfig.getHp(stage: number): BigNumber
	local world = StageConfig.getWorld(stage)
	return BigNum.mul(world.hpBase, segmentedGrowthMultiplier(stage, world, world.hpGrowthSegments))
end

function StageConfig.getBloxReward(stage: number): BigNumber
	local world = StageConfig.getWorld(stage)
	return BigNum.mul(world.bloxBase, segmentedGrowthMultiplier(stage, world, world.bloxGrowthSegments))
end

-- 한 스테이지를 클리어하려면 부숴야 하는 블록의 총량 = getHp × getBlockCount.
function StageConfig.getTotalHp(stage: number): BigNumber
	return BigNum.mul(StageConfig.getHp(stage), BigNum.fromNumber(StageConfig.getBlockCount(stage)))
end

function StageConfig.getBlockCount(stage: number): number
	local world = StageConfig.getWorld(stage)
	local worldFloor = stageOffset(stage, world) + 1 -- 월드 안에서 몇 번째 층인가 (1부터)

	for _, step in ipairs(BLOCK_COUNT_STEPS) do
		if worldFloor >= step.from and worldFloor <= step.to then
			return math.min(step.count, MAX_BLOCK_COUNT)
		end
	end

	-- 스케줄 마지막 구간을 넘어가면 마지막 개수를 유지한다 (월드가 더 길어져도 안전).
	return math.min(BLOCK_COUNT_STEPS[#BLOCK_COUNT_STEPS].count, MAX_BLOCK_COUNT)
end

function StageConfig.validate(): boolean
	for _, world in pairs(WorldConfig.Worlds) do
		local startStage, endStage = world.stageRange[1], world.stageRange[2]
		local step = math.max(1, math.floor((endStage - startStage) / 10))

		local prevHp: BigNumber? = nil
		local prevReward: BigNumber? = nil
		for stage = startStage, endStage, step do
			local hp = StageConfig.getHp(stage)
			assert(BigNum.gt(hp, BigNum.new(0, 0)), string.format("StageConfig: 스테이지 %d의 HP가 0 이하", stage))
			if prevHp then
				assert(BigNum.gte(hp, prevHp), string.format("StageConfig: 스테이지 %d의 HP가 이전보다 낮음", stage))
			end
			prevHp = hp

			local reward = StageConfig.getBloxReward(stage)
			assert(BigNum.gt(reward, BigNum.new(0, 0)), string.format("StageConfig: 스테이지 %d의 보상이 0 이하", stage))
			if prevReward then
				assert(BigNum.gte(reward, prevReward), string.format("StageConfig: 스테이지 %d의 보상이 이전보다 낮음", stage))
			end
			prevReward = reward

			local blockCount = StageConfig.getBlockCount(stage)
			assert(blockCount >= 1 and blockCount <= MAX_BLOCK_COUNT, string.format("StageConfig: 스테이지 %d의 블록 개수(%d)가 범위를 벗어남", stage, blockCount))
		end
	end

	return true
end

return StageConfig

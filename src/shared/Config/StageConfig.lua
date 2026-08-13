--!strict
-- 스테이지별 HP / 보상 / 블록 개수 계산. 값을 저장하지 않고 WorldConfig의 성장식으로 매번 계산한다.
-- 블록 HP만 서버가 들고, 큐브 개수는 클라가 HP 비율로 역산한다 (DESIGN.md 2. 블록).

local BigNum = require(script.Parent.Parent.BigNum)
local WorldConfig = require(script.Parent.WorldConfig)

type BigNumber = BigNum.BigNumber
type WorldDef = WorldConfig.WorldDef

local StageConfig = {}

-- 블록 배치 상한 (DESIGN.md: 이중 원 구조 최대 16개). 값은 임시.
local MAX_BLOCK_COUNT = 16
local BLOCK_COUNT_START = 1
local STAGES_PER_BLOCK = 5 -- 임시: N스테이지마다 블록 1개 추가

-- 챌린지 타이머(초). DESIGN.md 1. 챌린지: "20초는 상한이지 라운드 길이가 아니다".
-- 지금은 고정값. 초반 18초→후반 0.5초 같은 스테이지별 체감 단축은 이후 밸런싱 단계에서 다룬다.
StageConfig.CHALLENGE_TIMER_SEC = 20

local function stageOffset(stage: number, world: WorldDef): number
	return stage - world.stageRange[1]
end

-- world.bloxGrowthSegments를 따라 구간별로 다른 배율을 곱해 stage까지의 누적 성장 배수를 계산한다.
-- 시작 스테이지(offset 0) 자체는 성장이 적용되지 않고, 그다음 스테이지로 넘어갈 때마다
-- "도착한 스테이지가 속한 구간"의 growth가 한 번씩 곱해진다.
local function segmentedGrowthMultiplier(stage: number, world: WorldDef): BigNumber
	local startStage = world.stageRange[1]
	local multiplier = BigNum.new(1, 0)

	for _, segment in ipairs(world.bloxGrowthSegments) do
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

-- "지금 나가면 받는" 클리어 보상. 누적이 아니라 스테이지마다 갱신되는 값이다 (푸시-유어-럭).
function StageConfig.getHp(stage: number): BigNumber
	local world = StageConfig.getWorld(stage)
	local offset = stageOffset(stage, world)
	return BigNum.mul(world.hpBase, BigNum.pow(BigNum.fromNumber(world.hpGrowth), offset))
end

function StageConfig.getBloxReward(stage: number): BigNumber
	local world = StageConfig.getWorld(stage)
	return BigNum.mul(world.bloxBase, segmentedGrowthMultiplier(stage, world))
end

function StageConfig.getBlockCount(stage: number): number
	local world = StageConfig.getWorld(stage)
	local offset = stageOffset(stage, world)
	local count = BLOCK_COUNT_START + math.floor(offset / STAGES_PER_BLOCK)
	return math.min(count, MAX_BLOCK_COUNT)
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

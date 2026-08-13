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

local function stageOffset(stage: number, world: WorldDef): number
	return stage - world.stageRange[1]
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
	local offset = stageOffset(stage, world)
	return BigNum.mul(world.bloxBase, BigNum.pow(BigNum.fromNumber(world.bloxGrowth), offset))
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

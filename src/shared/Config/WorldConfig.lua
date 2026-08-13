--!strict
-- 월드는 확장 가능하게만 설계한다. 월드 2 추가 시 Worlds 테이블에 항목만 붙이면 된다.
-- 스테이지 번호는 월드를 넘어 연속 (1~100, 101~200, ...). DESIGN.md 8. 월드 참고.

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type GrowthSegment = {
	from: number, -- 시작 스테이지 (포함)
	to: number, -- 끝 스테이지 (포함)
	growth: number, -- 이 구간에서 스테이지 1칸당 곱해지는 배율
}

export type WorldDef = {
	id: number,
	name: string,
	material: string,
	stageRange: { number }, -- { 시작, 끝 } (둘 다 포함)
	hpBase: BigNumber,
	hpGrowth: number, -- 스테이지당 HP 배율
	bloxBase: BigNumber,
	bloxGrowthSegments: { GrowthSegment }, -- 구간별 보상 배율. stageRange를 빈틈/중복 없이 덮어야 함
	eggPacks: { number }, -- PetConfig.Eggs 인덱스
	auraPacks: { number }, -- AuraConfig.Packs 인덱스
}

local WorldConfig = {}

local Worlds: { [number]: WorldDef } = {
	[1] = {
		id = 1,
		name = "나무",
		material = "wood",
		stageRange = { 1, 100 },
		hpBase = BigNum.new(1, 2), -- 100 (임시)
		hpGrowth = 1.35,
		bloxBase = BigNum.new(1, 0), -- 1 (임시)
		-- 구간별 보상 성장률. 값은 임시 (Phase 3에서 실플레이 데이터로 튜닝 예정).
		bloxGrowthSegments = {
			{ from = 1, to = 20, growth = 1.3 },
			{ from = 21, to = 40, growth = 1.4 },
			{ from = 41, to = 60, growth = 1.5 },
			{ from = 61, to = 80, growth = 1.6 },
			{ from = 81, to = 100, growth = 1.7 },
		},
		eggPacks = { 1, 2, 3 },
		auraPacks = { 1, 2, 3, 4, 5 },
	},
}

WorldConfig.Worlds = Worlds

function WorldConfig.get(worldId: number): WorldDef?
	return Worlds[worldId]
end

function WorldConfig.getByStage(stage: number): WorldDef?
	for _, world in pairs(Worlds) do
		if stage >= world.stageRange[1] and stage <= world.stageRange[2] then
			return world
		end
	end
	return nil
end

-- bloxGrowthSegments가 world.stageRange를 빈틈/중복/역순 없이 정확히 덮는지 확인한다.
local function validateGrowthSegments(worldId: number, world: WorldDef)
	local segments = world.bloxGrowthSegments
	assert(type(segments) == "table" and #segments > 0, string.format("WorldConfig: 월드 %d의 bloxGrowthSegments가 비어있음", worldId))

	local expectedFrom = world.stageRange[1]
	for i, segment in ipairs(segments) do
		assert(segment.from == expectedFrom, string.format("WorldConfig: 월드 %d의 bloxGrowthSegments[%d] 시작이 이어지지 않음 (기대=%d, 실제=%d)", worldId, i, expectedFrom, segment.from))
		assert(segment.to >= segment.from, string.format("WorldConfig: 월드 %d의 bloxGrowthSegments[%d] 끝이 시작보다 작음", worldId, i))
		assert(segment.growth > 1, string.format("WorldConfig: 월드 %d의 bloxGrowthSegments[%d] growth는 1보다 커야 함", worldId, i))
		expectedFrom = segment.to + 1
	end

	local lastCovered = expectedFrom - 1
	assert(lastCovered == world.stageRange[2], string.format("WorldConfig: 월드 %d의 bloxGrowthSegments가 stageRange 끝(%d)까지 덮지 못함 (마지막=%d)", worldId, world.stageRange[2], lastCovered))
end

function WorldConfig.validate(): boolean
	local ids = {}
	for id in pairs(Worlds) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local expectedStart = 1
	for _, id in ipairs(ids) do
		local world = Worlds[id]
		assert(world.id == id, string.format("WorldConfig: 월드 키(%d)와 id(%d)가 다름", id, world.id))
		assert(type(world.stageRange) == "table" and #world.stageRange == 2, string.format("WorldConfig: 월드 %d의 stageRange는 {시작,끝} 형태여야 함", id))

		local startStage, endStage = world.stageRange[1], world.stageRange[2]
		assert(startStage == expectedStart, string.format("WorldConfig: 월드 %d의 stageRange 시작이 연속되지 않음 (기대=%d, 실제=%d)", id, expectedStart, startStage))
		assert(endStage >= startStage, string.format("WorldConfig: 월드 %d의 stageRange 끝이 시작보다 작음", id))

		assert(world.hpGrowth > 1, string.format("WorldConfig: 월드 %d의 hpGrowth는 1보다 커야 함", id))
		validateGrowthSegments(id, world)
		assert(BigNum.gt(world.hpBase, BigNum.new(0, 0)), string.format("WorldConfig: 월드 %d의 hpBase는 0보다 커야 함", id))
		assert(BigNum.gt(world.bloxBase, BigNum.new(0, 0)), string.format("WorldConfig: 월드 %d의 bloxBase는 0보다 커야 함", id))
		assert(type(world.material) == "string" and #world.material > 0, string.format("WorldConfig: 월드 %d의 material이 비어있음", id))
		assert(#world.eggPacks > 0, string.format("WorldConfig: 월드 %d의 eggPacks가 비어있음", id))
		assert(#world.auraPacks > 0, string.format("WorldConfig: 월드 %d의 auraPacks가 비어있음", id))

		expectedStart = endStage + 1
	end

	return true
end

return WorldConfig

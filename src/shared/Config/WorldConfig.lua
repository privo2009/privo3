--!strict
-- 월드는 확장 가능하게만 설계한다. 월드 2 추가 시 Worlds 테이블에 항목만 붙이면 된다.
-- 스테이지 번호는 월드를 넘어 연속 (1~25, 26~50, ...). DESIGN.md 8. 월드 참고.

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
	hpGrowthSegments: { GrowthSegment }, -- 구간별 HP 배율. stageRange를 빈틈/중복 없이 덮어야 함
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
		stageRange = { 1, 25 },
		hpBase = BigNum.new(1, 2), -- 100
		-- 구간별 HP 성장률. 뒤로 갈수록 가팔라진다 (DESIGN.md 1. 챌린지 > 곡선 규약 2).
		-- 레퍼런스 25층 실측은 6.22x/층이지만 그쪽은 시간 무제한이다. 우리는 20초 타이머가
		-- 있어 같은 배율도 체감 난이도가 더 높으므로 완만하게 잡았다 (평균 4.54x/층).
		hpGrowthSegments = {
			{ from = 1, to = 8, growth = 3.0 },
			{ from = 9, to = 16, growth = 4.0 },
			{ from = 17, to = 25, growth = 7.0 },
		},
		bloxBase = BigNum.new(1, 0), -- 1
		-- 보상 성장률은 전 구간 고정 (곡선 규약 3). "한 층 더 가면 2.7배"라는 판단 기준이
		-- 게임 내내 변하지 않아야 유저가 예측할 수 있다. 정지선 = 1/2.7 = 37%.
		-- HP 증가율(평균 4.54x)이 항상 이보다 크다 = 곡선 규약 1.
		bloxGrowthSegments = {
			{ from = 1, to = 25, growth = 2.7 },
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

-- 성장 세그먼트가 world.stageRange를 빈틈/중복/역순 없이 정확히 덮는지 확인한다.
-- hpGrowthSegments / bloxGrowthSegments 양쪽에 같은 규칙을 적용한다.
local function validateGrowthSegments(worldId: number, world: WorldDef, fieldName: string, segments: { GrowthSegment })
	assert(type(segments) == "table" and #segments > 0, string.format("WorldConfig: 월드 %d의 %s가 비어있음", worldId, fieldName))

	local expectedFrom = world.stageRange[1]
	for i, segment in ipairs(segments) do
		assert(segment.from == expectedFrom, string.format("WorldConfig: 월드 %d의 %s[%d] 시작이 이어지지 않음 (기대=%d, 실제=%d)", worldId, fieldName, i, expectedFrom, segment.from))
		assert(segment.to >= segment.from, string.format("WorldConfig: 월드 %d의 %s[%d] 끝이 시작보다 작음", worldId, fieldName, i))
		assert(segment.growth > 1, string.format("WorldConfig: 월드 %d의 %s[%d] growth는 1보다 커야 함", worldId, fieldName, i))
		expectedFrom = segment.to + 1
	end

	local lastCovered = expectedFrom - 1
	assert(lastCovered == world.stageRange[2], string.format("WorldConfig: 월드 %d의 %s가 stageRange 끝(%d)까지 덮지 못함 (마지막=%d)", worldId, fieldName, world.stageRange[2], lastCovered))
end

-- stage가 속한 세그먼트의 growth. 세그먼트가 stageRange를 전부 덮는 것은
-- validateGrowthSegments가 보장하므로 여기서는 못 찾으면 설정 오류다.
function WorldConfig.growthAt(segments: { GrowthSegment }, stage: number): number
	for _, segment in ipairs(segments) do
		if stage >= segment.from and stage <= segment.to then
			return segment.growth
		end
	end
	error(string.format("WorldConfig: 스테이지 %d를 덮는 성장 세그먼트가 없음", stage))
end

-- 곡선 규약 1 (DESIGN.md 1. 챌린지 > 곡선 규약): HP 증가율은 보상 증가율보다 항상 크다.
-- 뒤집히면 진행이 무조건 이득이 되어 푸시-유어-럭이 성립하지 않는다.
-- 수치는 튜닝 대상이지만 이 부등호는 튜닝으로도 깨면 안 되므로 여기서 막는다.
local function validateCurveContract(worldId: number, world: WorldDef)
	for stage = world.stageRange[1], world.stageRange[2] do
		local hpGrowth = WorldConfig.growthAt(world.hpGrowthSegments, stage)
		local bloxGrowth = WorldConfig.growthAt(world.bloxGrowthSegments, stage)
		assert(hpGrowth > bloxGrowth, string.format("WorldConfig: 월드 %d 스테이지 %d에서 곡선 규약 1 위반 — HP 증가율(%.2f)이 보상 증가율(%.2f)보다 크지 않음", worldId, stage, hpGrowth, bloxGrowth))
	end
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

		validateGrowthSegments(id, world, "hpGrowthSegments", world.hpGrowthSegments)
		validateGrowthSegments(id, world, "bloxGrowthSegments", world.bloxGrowthSegments)
		validateCurveContract(id, world)
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

--!strict
-- 블록 모델의 큐브를 HP 비율로 숨기고, 그 자리에 파편 연출을 낸다. 클라 전용 (CLAUDE.md 규칙 4).
--
-- 절대 원칙:
--   - 서버는 HP만 준다. destroyedCount는 여기서 역산한다
--     (DESIGN.md 2장: destroyedCount = floor(총큐브수 × (1 - hp/maxHp)))
--   - 파괴 순서는 BlockShuffle.computeDestructionOrder(seed)로 서버와 동일하게 재현한다.
--     그 순열이 가리키는 값은 BlockModelGenerator가 큐브에 붙여둔 GridIndex Attribute와
--     대응된다 — 순열 앞에서부터 destroyedCount개를 골라 그 GridIndex 큐브를 숨긴다
--   - 큐브는 제거(Destroy)가 아니라 Transparency/CanCollide로 숨긴다
--     (Instance 생성/제거 반복 금지, CLAUDE.md 규칙 4)
--   - 파편은 ParticlePool에서만 빌린다. 풀이 비면 연출을 생략하고 큐브 숨김은 그대로 진행한다
--     (게임 진행이 연출보다 우선 — 파편 실패가 파괴 자체를 막으면 안 됨)
--   - 물리 금지. 파편 낙하는 Heartbeat 기반 수동 애니메이션(위치를 직접 계산해서 대입)이고
--     TweenService/물리 엔진을 쓰지 않는다

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BlockShuffle = require(ReplicatedStorage.Shared.BlockShuffle)
local ParticlePool = require(script.Parent.ParticlePool)

local ChunkBreaker = {}

local FRAGMENT_FALL_DURATION_SEC = 0.4
local FRAGMENT_FALL_DISTANCE_STUDS = 6
local FRAGMENT_SIZE_RATIO = 0.6 -- 파편 크기 = 큐브 크기 × 이 비율. 임시값(디자인 담당 조정 가능)

type ActiveFragment = {
	part: BasePart,
	startPosition: Vector3,
	startedAt: number,
}

-- 낙하 중인 파편은 전부 여기 하나에 모아서 Heartbeat 한 번으로 같이 갱신한다
-- (ChunkBreaker 인스턴스가 여러 개 동시에 있어도 애니메이션 루프는 전역 하나).
local activeFragments: { ActiveFragment } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local function stepFragment(fragment: ActiveFragment, now: number): boolean
	local elapsed = now - fragment.startedAt
	local t = elapsed / FRAGMENT_FALL_DURATION_SEC

	if t >= 1 then
		ParticlePool.release(fragment.part)
		return false -- 끝남, 목록에서 제거
	end

	-- 수동 낙하 애니메이션: 가속도 느낌만 흉내낸 순수 계산(t^2), 물리 엔진 사용 안 함.
	local eased = t * t
	local yOffset = -FRAGMENT_FALL_DISTANCE_STUDS * eased
	fragment.part.Position = fragment.startPosition + Vector3.new(0, yOffset, 0)
	fragment.part.Transparency = 0.9 * t -- 서서히 사라짐

	return true
end

local function ensureAnimationLoopRunning()
	if heartbeatConnection ~= nil then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if #activeFragments == 0 then
			return
		end

		local now = os.clock()
		local stillActive: { ActiveFragment } = {}

		for _, fragment in ipairs(activeFragments) do
			if stepFragment(fragment, now) then
				table.insert(stillActive, fragment)
			end
		end

		activeFragments = stillActive
	end)
end

-- 큐브 하나가 부서진 자리에서 파편 연출을 시작한다. 풀이 비었으면 조용히 아무 것도 안 한다.
local function spawnFragmentEffect(cube: BasePart)
	local fragment = ParticlePool.acquire()
	if fragment == nil then
		return -- 풀 소진: 연출 생략. 큐브 숨김은 호출부에서 별도로 이미 처리함
	end

	fragment.Size = cube.Size * FRAGMENT_SIZE_RATIO
	fragment.Color = cube.Color
	fragment.Material = cube.Material
	fragment.CFrame = cube.CFrame
	fragment.Transparency = 0

	table.insert(activeFragments, {
		part = fragment,
		startPosition = cube.Position,
		startedAt = os.clock(),
	})

	ensureAnimationLoopRunning()
end

-- 큐브를 숨긴다 (제거 아님 — Instance 생성/제거 반복 금지).
local function hideCube(cube: BasePart)
	cube.Transparency = 1
	cube.CanCollide = false
end

-- model 하위의 모든 BasePart 중 GridIndex Attribute가 붙은 것을 인덱스로 모은다.
local function collectCubesByGridIndex(model: Model): { [number]: BasePart }
	local cubes: { [number]: BasePart } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local gridIndex = descendant:GetAttribute("GridIndex")
			if type(gridIndex) == "number" then
				cubes[gridIndex] = descendant
			end
		end
	end
	return cubes
end

export type ChunkBreakerHandle = {
	setHp: (self: ChunkBreakerHandle, hp: number, maxHp: number) -> (),
}

-- model: BlockModelGenerator가 만든 블록 모델(큐브마다 GridIndex Attribute가 있어야 함)
-- totalCubes: 이 블록의 총 큐브 수 (gridSize^3)
-- seed: 서버가 이 블록에 부여한 파괴 순서 시드 (BlockSnapshotEntry.seed)
function ChunkBreaker.new(model: Model, totalCubes: number, seed: number): ChunkBreakerHandle
	assert(totalCubes >= 1, "ChunkBreaker.new: totalCubes는 1 이상이어야 함")

	local cubesByGridIndex = collectCubesByGridIndex(model)
	local destructionOrder = BlockShuffle.computeDestructionOrder(seed, totalCubes)
	local destroyedCount = 0

	local self = {} :: ChunkBreakerHandle

	-- 서버가 보낸 hp/maxHp로 destroyedCount를 다시 계산하고, 새로 죽은 큐브만 숨긴 뒤
	-- 파편을 낸다. 이미 처리된 개수보다 작거나 같으면 아무 것도 안 한다(멱등).
	function self:setHp(hp: number, maxHp: number)
		assert(maxHp > 0, "ChunkBreaker:setHp: maxHp는 0보다 커야 함")

		local ratio = math.clamp(hp / maxHp, 0, 1)
		local targetDestroyedCount = math.clamp(math.floor(totalCubes * (1 - ratio)), 0, totalCubes)

		if targetDestroyedCount <= destroyedCount then
			return
		end

		for i = destroyedCount + 1, targetDestroyedCount do
			local gridIndex = destructionOrder[i]
			local cube = cubesByGridIndex[gridIndex]
			if cube ~= nil then
				spawnFragmentEffect(cube)
				hideCube(cube)
			end
		end

		destroyedCount = targetDestroyedCount
	end

	return self
end

return ChunkBreaker

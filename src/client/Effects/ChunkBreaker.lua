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

-- 한 번에 여러 큐브가 부서질 때, 전부 같은 프레임에 숨기지 않고 순열 순서대로 이 시간
-- 안에 나눠서 숨긴다. 큐브 개수에 비례시키지 않는다 — 몇 개든 이 상한 안에서 끝나야
-- 후반(오버플로우로 한 번에 여러 블록이 동시에 부서지는 경우)에도 진행이 안 막힌다.
local DEFAULT_STAGGER_DURATION_SEC = 0.25

-- ===== 파편 샘플링 (파편 풀 고갈 대비) =================================================
-- 한 번에 부서지는 큐브가 많아지면(오버플로우로 여러 블록이 겹칠 때) 전부 파편을 내려다
-- 풀(200개)이 앞쪽 블록에서 동나서 뒤쪽 블록은 파편이 하나도 안 뜨는 비대칭이 생긴다.
-- 배치가 작을 때는 전부 내고, 커지면 배치 크기에 비례해서 솎아낸다. 큐브 숨김 자체(게임
-- 상태)는 샘플링과 무관하게 항상 전부 처리된다 — 안 뜨는 건 파편(연출)뿐이다.
-- 두 상수 다 BlockLayoutConfig의 배율처럼 눈으로 보면서 튜닝하는 값이다.

-- 배치 크기가 이 값 이하면 솎아내지 않고 전부 파편을 낸다. 초반처럼 배치가 작을 때
-- 파편이 듬성듬성해서 초라해 보이는 걸 막기 위함.
local SAMPLE_FULL_EFFECT_MAX_BATCH_SIZE = 6

-- 배치가 위 기준보다 크면, 배치 하나당 파편이 대략 이 개수 정도로만 나오도록 간격을
-- 둔다(간격 = ceil(배치크기 / 이 값)). 배치가 커질수록 간격도 같이 커져서, 배치 크기와
-- 무관하게 한 배치가 풀에서 가져가는 몫이 대략 이 값 언저리로 유지된다.
local SAMPLE_TARGET_FRAGMENT_COUNT = 12

-- batchSize개 중 몇 개마다 하나씩 파편을 낼지. 1이면 전부, 2면 하나 걸러 하나...
local function computeSampleInterval(batchSize: number): number
	if batchSize <= SAMPLE_FULL_EFFECT_MAX_BATCH_SIZE then
		return 1
	end
	return math.max(1, math.ceil(batchSize / SAMPLE_TARGET_FRAGMENT_COUNT))
end

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

type BatchEntry = {
	cube: BasePart,
	thread: thread?, -- task.delay가 반환한 스레드. 이미 처리됐거나 즉시 처리된 경우 nil
	revealed: boolean,
	emitFragment: boolean, -- 샘플링 결과. false여도 큐브 숨김은 그대로 함
}

-- model: BlockModelGenerator가 만든 블록 모델(큐브마다 GridIndex Attribute가 있어야 함)
-- totalCubes: 이 블록의 총 큐브 수 (gridSize^3)
-- seed: 서버가 이 블록에 부여한 파괴 순서 시드 (BlockSnapshotEntry.seed)
-- staggerDurationSec: 한 번에 여러 큐브가 부서질 때 나눠서 숨기는 데 쓸 총 시간 상한.
--   생략하면 DEFAULT_STAGGER_DURATION_SEC. 0을 주면 즉시 처리(자동 진행 모드용).
function ChunkBreaker.new(model: Model, totalCubes: number, seed: number, staggerDurationSec: number?): ChunkBreakerHandle
	assert(totalCubes >= 1, "ChunkBreaker.new: totalCubes는 1 이상이어야 함")

	local cubesByGridIndex = collectCubesByGridIndex(model)
	local destructionOrder = BlockShuffle.computeDestructionOrder(seed, totalCubes)
	local staggerDuration = staggerDurationSec or DEFAULT_STAGGER_DURATION_SEC
	local destroyedCount = 0

	-- 현재 진행 중인 스태거 배치. 비어있으면 진행 중인 배치 없음.
	local currentBatch: { BatchEntry } = {}

	local function revealEntry(entry: BatchEntry)
		if entry.revealed then
			return
		end
		entry.revealed = true
		entry.thread = nil

		if entry.emitFragment then
			spawnFragmentEffect(entry.cube)
		end
		hideCube(entry.cube)
	end

	-- 진행 중이던 배치를 전부 즉시 완료 처리한다 (예약된 task.delay는 취소하고 그 자리에서
	-- 바로 숨김) — 새 setHp가 오면 이전 배치가 밀린 채로 계속 깔짝거리지 않게 한다.
	local function flushCurrentBatch()
		for _, entry in ipairs(currentBatch) do
			if entry.thread ~= nil then
				task.cancel(entry.thread)
				entry.thread = nil
			end
			revealEntry(entry)
		end
		currentBatch = {}
	end

	-- indices(destructionOrder 상의 위치들)를 staggerDuration 안에 순서대로 나눠서 숨긴다.
	-- 개수가 몇 개든 마지막 큐브의 지연 시간이 staggerDuration을 넘지 않는다(비례 금지).
	local function startStaggerBatch(indices: { number })
		local batch: { BatchEntry } = {}
		local batchSize = #indices
		local sampleInterval = computeSampleInterval(batchSize)

		for batchPos, orderIndex in ipairs(indices) do
			local gridIndex = destructionOrder[orderIndex]
			local cube = cubesByGridIndex[gridIndex]
			if cube ~= nil then
				local entry: BatchEntry = {
					cube = cube,
					thread = nil,
					revealed = false,
					emitFragment = (batchPos - 1) % sampleInterval == 0,
				}
				local delaySec = ((batchPos - 1) / batchSize) * staggerDuration

				if delaySec <= 0 then
					revealEntry(entry)
				else
					entry.thread = task.delay(delaySec, function()
						revealEntry(entry)
					end)
				end

				table.insert(batch, entry)
			end
		end

		currentBatch = batch
	end

	local self = {} :: ChunkBreakerHandle

	-- 서버가 보낸 hp/maxHp로 destroyedCount를 다시 계산하고, 새로 죽은 큐브만 처리한다.
	-- 이미 처리된 개수보다 작거나 같으면 아무 것도 안 한다(멱등). destroyedCount 자체는
	-- 배치 시작 시점에 바로 갱신된다 — 스태거는 "보여주는 타이밍"만 늦출 뿐, 논리적 상태는
	-- 밀리지 않는다.
	function self:setHp(hp: number, maxHp: number)
		assert(maxHp > 0, "ChunkBreaker:setHp: maxHp는 0보다 커야 함")

		-- 진행 중이던 스태거가 있으면 먼저 즉시 완료 처리 (밀리지 않게).
		flushCurrentBatch()

		local ratio = math.clamp(hp / maxHp, 0, 1)
		local targetDestroyedCount = math.clamp(math.floor(totalCubes * (1 - ratio)), 0, totalCubes)

		if targetDestroyedCount <= destroyedCount then
			return
		end

		local indices = {}
		for i = destroyedCount + 1, targetDestroyedCount do
			table.insert(indices, i)
		end
		destroyedCount = targetDestroyedCount

		-- staggerDuration <= 0이면 startStaggerBatch 내부에서 모든 delaySec가 0으로 계산돼
		-- 전부 즉시(동기) 처리된다 — 별도 "즉시 경로"를 안 둬도 자동 진행 모드가 된다.
		startStaggerBatch(indices)
	end

	return self
end

return ChunkBreaker

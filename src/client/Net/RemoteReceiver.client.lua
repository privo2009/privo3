--!strict
-- 서버 신호 수신부. Phase 4-2-a 배선의 3단계.
-- 채널 정의와 payload 형태는 Shared/Remotes.lua에 있다 — 이름 문자열을 여기 다시 적지 않는다.
--
-- 하는 일:
--   BlockDamaged    → 블록별 HP를 ChunkBreaker에 넘겨 파편 연출을 돌린다
--   RunStateChanged → 새 층이면 블록 모델을 만든다. 그 외에는 print만 한다 —
--                     HUD는 Phase 6이고 여기서 UI를 만들지 않는다
--                     (스테이지 번호는 maxHp 역산에도 쓰이므로 기억해둔다)
--
-- 서버가 보내는 것은 블록 HP뿐이다. 큐브 개수·파괴 순서는 전부 이쪽에서 역산한다
-- (CLAUDE.md "4. 파편·파티클은 클라이언트 전용"). 파편 상한 200·풀링·물리 금지는
-- ChunkBreaker와 ParticlePool 안에 이미 들어 있으므로 이 파일은 그 계약을 건드리지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local BlockModelBuilder = require(ReplicatedStorage.Shared.BlockModelBuilder)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ChunkBreaker = require(script.Parent.Parent.Effects.ChunkBreaker)

-- ===== 블록 모델은 클라가 만든다 (4-2-a2) ==============================================
--
-- 예전에는 서버(BlockSpawner)가 모델을 만들어 전원에게 복제했고, 이 파일은 Workspace에서
-- 자기 것을 찾기만 했다. 그 방식은 2인 이상이면 블록이 같은 자리에 겹쳤다.
--
-- 지금은 각 클라가 자기 블록만 만든다. 레퍼런스 게임과 같은 방식이다 — 스테이지는 전원이
-- 공유하고 다른 플레이어의 캐릭터는 보이지만, 그가 부수는 블록은 아예 보이지 않는다.
-- 얻는 것:
--   - 서버 블록 파트가 0이 된다 (30명 × 7블록 × 64큐브 = 13,440파트가 사라진다)
--   - 내 화면에 내 것만 있으므로 UserId 폴더도, 개인 구역도, 좌표 오프셋도 필요 없다
--   - 좌표를 원점 고정으로 둘 수 있다 — 겹칠 대상이 없다 (BlockLayout.lua 상단 참고)
--
-- 만드는 데 필요한 재료 4가지 중 3개는 클라가 이미 안다:
--   개수   StageConfig.getBlockCount(stage)
--   좌표   BlockLayout.computeLayout(개수)     ← 서버 판정 좌표와 같은 함수다
--   maxHp  StageConfig.getHp(stage)
--   시드   서버가 진입 때 무작위로 뽑는 값이라 이것만 전달된다
--          → RunStateChanged payload의 seeds (근거는 Remotes.lua 주석)
--
-- ⚠️ CanCollide = true로 둔다.
--    자동 공격이 근접이라 블록 앞까지 걸어가야 하고, 부딪혀 멈추는 것이 사거리를 몸으로
--    알려준다. 모델이 클라 소유라 유저가 CanCollide를 끄고 통과할 수 있지만 실익이 없다 —
--    통과해봐야 진행은 벽으로만 되고 데미지는 서버가 계산한다. 방어 코드를 넣지 않는다.

local BLOCK_CONTAINER_NAME = "LocalBlocks"

local TOTAL_CUBES = BlockLayoutConfig.GRID_SIZE ^ 3

local channels = Remotes.getClient()

local currentStage: number? = nil
local handles: { [number]: ChunkBreaker.ChunkBreakerHandle } = {}
local models: { [number]: Model } = {}
local currentSeeds: { number } = {}
local warnedMissing: { [number]: boolean } = {}

-- 내 블록만 담는 로컬 폴더. 클라가 만든 것이라 서버에도 다른 플레이어에게도 안 보인다.
local function getContainer(): Folder
	local existing = Workspace:FindFirstChild(BLOCK_CONTAINER_NAME)
	if existing ~= nil then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = BLOCK_CONTAINER_NAME
	folder.Parent = Workspace
	return folder
end

-- ===== 템플릿 캐시 =====================================================================
--
-- 재질별로 한 번만 확보하고 계속 복제해 쓴다. 캐시가 없으면 층 전환마다 64파트짜리
-- 템플릿을 새로 만들고 버리게 된다 — 만들자마자 3~7번 복제하고 원본을 지우는 꼴이다.
--
-- ReplicatedStorage.BlockModels에 디자인 담당이 넣어둔 모델이 있으면 그것이 잡히고
-- (Parent가 그 폴더), 없으면 즉석 생성본이 잡힌다(Parent가 nil). 어느 쪽이든 그대로
-- 들고 있으면 된다 — Parent가 nil인 모델도 Clone은 정상 동작하고, 화면에 안 나오므로
-- 오히려 템플릿으로 적합하다. 폴더에 있는 원본은 절대 Destroy하지 않는다.
local templates: { [string]: Model } = {}

local function getTemplate(materialName: string): Model
	local cached = templates[materialName]
	if cached ~= nil then
		return cached
	end

	local template = BlockModelBuilder.getOrCreateTemplate(materialName)
	templates[materialName] = template
	return template
end

-- 이전 층의 모델을 전부 지운다. 층 전환과 런 종료 양쪽에서 부른다.
--
-- 풀링하지 않는다. 층마다 3~7개를 Destroy하고 다시 Clone한다 — 파편은 초당 수백 개라
-- 풀링이 필수지만(CLAUDE.md 규칙 4) 블록은 20초에 한 번 3~7개다. 그리고 이미 재사용하고
-- 있다: 64개 큐브를 매번 Instance.new로 만드는 게 아니라 템플릿 하나를 Clone한다.
-- 재사용하면 오히려 깨진다 — ChunkBreaker가 큐브의 Transparency/CanCollide를 바꿔 숨기므로,
-- 부서진 모델을 다시 쓰면 다음 층에서 이미 숨겨진 큐브가 그대로 보인다.
local function clearModels()
	for _, model in pairs(models) do
		model:Destroy()
	end
	models = {}
	handles = {}
	currentSeeds = {}
	warnedMissing = {}
end

-- 이번 층의 블록 모델을 세운다. 좌표는 서버가 판정에 쓰는 것과 같은 함수로 구하고
-- (BlockLayout.computeLayout), 시드만 서버가 보낸 것을 쓴다.
local function buildModels(stage: number, seeds: { number })
	clearModels()

	local count = StageConfig.getBlockCount(stage)

	if #seeds ~= count then
		-- 시드 개수가 블록 개수와 다르면 어느 블록의 순서가 밀렸는지 알 수 없다.
		-- 조용히 어긋난 연출을 보여주느니 경고하고 만들지 않는다.
		warn(string.format(
			"[RemoteReceiver] stage %d: 시드 %d개인데 블록은 %d개다. 모델을 만들지 않는다.",
			stage,
			#seeds,
			count
		))
		return
	end

	currentSeeds = seeds

	local positions = BlockLayout.computeLayout(count)
	local template = getTemplate(StageConfig.getWorld(stage).material)
	local container = getContainer()

	for i = 1, count do
		local model = template:Clone()
		model.Name = string.format("Block_%d", i)
		BlockModelBuilder.moveModelCenterTo(model, positions[i] + Vector3.new(0, BlockLayout.GROUND_Y_OFFSET, 0))
		model.Parent = container
		models[i] = model
	end
end

local function getHandle(index: number): ChunkBreaker.ChunkBreakerHandle?
	local existing = handles[index]
	if existing ~= nil then
		return existing
	end

	local model = models[index]
	if model == nil then
		if not warnedMissing[index] then
			warnedMissing[index] = true
			warn(string.format("[RemoteReceiver] 블록 %d의 모델이 없다. 연출 생략.", index))
		end
		return nil
	end

	local seed = currentSeeds[index]
	if type(seed) ~= "number" then
		if not warnedMissing[index] then
			warnedMissing[index] = true
			warn(string.format("[RemoteReceiver] 블록 %d의 시드가 없다. 연출 생략.", index))
		end
		return nil
	end

	-- staggerDurationSec은 기본값을 쓴다. 자동 진행 모드에서 0으로 바꾸는 것은 그 단계의 일이다.
	local handle = ChunkBreaker.new(model, TOTAL_CUBES, seed)
	handles[index] = handle
	return handle
end

-- ChunkBreaker.setHp는 평범한 number를 받는다. hp를 그대로 풀어 넣으면 안 된다 —
-- 후반 HP는 10^2000까지 가므로 m * 10^e가 inf가 되고, inf/inf = nan이 되어 비율이 통째로
-- 깨진다. BigNum.toRatio가 나눗셈을 BigNum 안에서 먼저 끝내주므로 그걸 쓴다
-- (그 함수 주석에 순서가 왜 중요한지 적혀 있다. 검증은 BigNumTests 11번 섹션).
-- setHp에 (비율, 1)을 넘기는 이유: setHp가 하는 계산이 hp/maxHp라 결과가 동일하고,
-- 큰 수를 number로 푸는 지점이 아예 없어진다.
local function hpRatio(hp: BigNum.BigNumber, maxHp: BigNum.BigNumber): number
	return math.clamp(BigNum.toRatio(hp, maxHp), 0, 1)
end

channels.blockDamaged.OnClientEvent:Connect(function(changes: Remotes.BlockDamagedPayload)
	local stage = currentStage
	if stage == nil then
		-- RunStateChanged가 먼저 와야 어느 스테이지인지 알고, 그래야 maxHp가 나온다.
		-- 서버는 startRun에서 상태를 먼저 보내므로 정상 흐름에서는 여기 걸리지 않는다.
		warn("[RemoteReceiver] 스테이지를 모르는 상태에서 BlockDamaged가 왔다. 연출 생략.")
		return
	end

	local maxHp = StageConfig.getHp(stage)

	for _, change in ipairs(changes) do
		local handle = getHandle(change.index)
		if handle ~= nil then
			-- destroyed 필드는 따로 쓰지 않는다. destroyed면 hp가 0이고, 비율 0은
			-- ChunkBreaker에서 "전부 파괴"와 같은 뜻이라 hp 하나로 충분하다.
			handle:setHp(hpRatio(change.hp, maxHp), 1)
		end
	end
end)

channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	local state = payload.state

	if payload.active and state.stage ~= currentStage then
		-- 새 층이다. 이전 층 모델을 전부 지우고 이번 층 것을 세운다.
		-- 핸들도 같이 버려진다 — 그 층의 모델·시드에 묶여 있던 것이라 재사용할 수 없다.
		buildModels(state.stage, payload.seeds)
	end

	if payload.active then
		currentStage = state.stage
	else
		-- 런이 끝났다. 모델은 남겨둔다 — 유저가 수령 발판과 진행 벽을 고르는 동안
		-- 부서진 블록이 그대로 있는 것이 자연스럽다. 다음 층에 진입하면 그때 치운다.
		-- (예전 서버 방식의 "생성 직전에만 제거한다"와 같은 규칙이다)
		currentStage = nil
	end

	-- HUD는 Phase 6이다. 여기서는 배선이 맞는지 눈으로 확인할 수 있게 찍기만 한다.
	print(string.format(
		"[RemoteReceiver] RunStateChanged reason=%s active=%s stage=%d cleared=%s canAdvance=%s timeLeft=%.1f reward=%s",
		payload.reason,
		tostring(payload.active),
		state.stage,
		tostring(state.cleared),
		tostring(state.canAdvance),
		state.timeLeft,
		BigNum.tostring(state.reward)
	))
end)

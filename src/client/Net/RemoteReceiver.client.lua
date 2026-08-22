--!strict
-- 서버 신호 수신부. Phase 4-2-a 배선의 3단계.
-- 채널 정의와 payload 형태는 Shared/Remotes.lua에 있다 — 이름 문자열을 여기 다시 적지 않는다.
--
-- 하는 일:
--   BlockDamaged    → 블록별 HP를 ChunkBreaker에 넘겨 파편 연출을 돌린다
--   RunStateChanged → print만 한다. HUD는 Phase 6이고 여기서 UI를 만들지 않는다
--                     (다만 스테이지 번호는 아래 maxHp 역산에 필요해서 기억해둔다)
--
-- 서버가 보내는 것은 블록 HP뿐이다. 큐브 개수·파괴 순서는 전부 이쪽에서 역산한다
-- (CLAUDE.md "4. 파편·파티클은 클라이언트 전용"). 파편 상한 200·풀링·물리 금지는
-- ChunkBreaker와 ParticlePool 안에 이미 들어 있으므로 이 파일은 그 계약을 건드리지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ChunkBreaker = require(script.Parent.Parent.Effects.ChunkBreaker)

-- ===== 블록 모델을 찾는 계약 =============================================================
--
-- ⚠️ 아직 성립하지 않는 계약이다. 지금 서버는 블록 모델을 월드에 만들지 않는다
--    (BlockService는 "Instance를 생성하지 않는다"고 못박은 순수 데이터 모듈이고,
--     BlockModelGenerator는 개발 도구다). 그래서 이 파일은 신호를 받아도 붙일 모델이 없어
--    연출을 건너뛴다 — 아래 경고가 그 상태를 알려준다.
--
-- 모델을 실제로 배치하는 단계에서 이 세 가지만 맞춰주면 그때부터 바로 붙는다:
--   1. 블록 모델들을 Workspace.Blocks 폴더 아래에 둔다
--   2. 모델마다 BlockIndex 어트리뷰트 = BlockChange.index
--   3. 모델마다 Seed 어트리뷰트 = 서버가 그 블록에 부여한 파괴 순서 시드
--
-- 시드만 어트리뷰트로 받는 이유: 나머지는 클라가 이미 알고 있다. 총 큐브 수는
-- BlockLayoutConfig, 블록 1개의 maxHp는 StageConfig.getHp(stage)로 나온다. 시드만
-- 서버가 진입 때 무작위로 뽑는 값이라 전달이 필요하다. 채널을 하나 더 파지 않고
-- 어트리뷰트로 보내는 쪽을 골랐다 — 블록마다 한 번 정해지면 안 바뀌는 값이라
-- 매 타격 payload에 실을 이유가 없다.

local BLOCK_CONTAINER_NAME = "Blocks"
local BLOCK_INDEX_ATTRIBUTE = "BlockIndex"
local SEED_ATTRIBUTE = "Seed"

local TOTAL_CUBES = BlockLayoutConfig.GRID_SIZE ^ 3

local channels = Remotes.getClient()

local currentStage: number? = nil
local handles: { [number]: ChunkBreaker.ChunkBreakerHandle } = {}
local warnedMissing: { [number]: boolean } = {}

local function findBlockModel(index: number): Model?
	local container = Workspace:FindFirstChild(BLOCK_CONTAINER_NAME)
	if container == nil then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(BLOCK_INDEX_ATTRIBUTE) == index then
			return child
		end
	end
	return nil
end

local function getHandle(index: number): ChunkBreaker.ChunkBreakerHandle?
	local existing = handles[index]
	if existing ~= nil then
		return existing
	end

	local model = findBlockModel(index)
	if model == nil then
		if not warnedMissing[index] then
			warnedMissing[index] = true
			warn(string.format(
				"[RemoteReceiver] 블록 %d의 모델을 못 찾았다. Workspace.%s 아래에 %s=%d인 Model이 필요하다. 연출 생략.",
				index,
				BLOCK_CONTAINER_NAME,
				BLOCK_INDEX_ATTRIBUTE,
				index
			))
		end
		return nil
	end

	local seed = model:GetAttribute(SEED_ATTRIBUTE)
	if type(seed) ~= "number" then
		if not warnedMissing[index] then
			warnedMissing[index] = true
			warn(string.format("[RemoteReceiver] 블록 %d 모델에 %s 어트리뷰트가 없다. 연출 생략.", index, SEED_ATTRIBUTE))
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
		-- 새 층이다. 이전 층의 핸들은 그 층의 모델·시드에 묶여 있으므로 버린다.
		-- (핸들은 큐브를 숨기기만 하고 Instance를 만들지 않으므로 버려도 남는 게 없다)
		handles = {}
		warnedMissing = {}
	end

	if payload.active then
		currentStage = state.stage
	else
		currentStage = nil
		handles = {}
		warnedMissing = {}
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

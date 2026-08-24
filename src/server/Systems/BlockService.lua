--!strict
-- 블록 HP/파괴 순서 시드 관리. DESIGN.md "2. 블록" 기준.
--
-- 절대 원칙:
--   - 서버는 블록 HP와 파괴 순서 시드만 들고 있는다. 큐브 개수/상태는 저장도 전송도 안 함
--     (클라가 destroyedCount = floor(총큐브수 × (1 - hp/maxHp))로 역산)
--   - 파괴 순서는 시드 기반 결정론적 셔플. 순서 배열 자체는 전송하지 않는다
--     (셔플 알고리즘은 src/shared/BlockShuffle.lua — 서버/클라가 반드시 같은 걸 써야 해서 공유 모듈로 뺐다)
--   - 클라는 "어느 블록을 맞췄는지" 보내지 않는다. 서버가 원점 좌표 기준 가까운 순으로 판정한다
--   - 반경 개념 없음. 힘은 데미지 풀이다 — 가까운 블록부터 HP만큼 소진하고, 남으면 다음
--     블록으로 흘러간다 (DESIGN.md 2장 "데미지 오버플로우")
--   - profile을 직접 건드리지 않는다 (재화는 ChallengeService가 CurrencyService로 처리, Phase 3-3)
--   - Instance를 생성하지 않는다 (3-4 모델 작업 전까지는 순수 데이터 모듈)
--
-- 배치/셔플/데미지 오버플로우 계산은 전부 Player·Instance 없이 동작하는 순수 함수로 분리했고,
-- BlockService._pure로 노출해서 BlockServiceTests.server.lua가 직접 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local BlockShuffle = require(ReplicatedStorage.Shared.BlockShuffle)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local Schema = require(script.Parent.Parent.Data.Schema)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local GameTypes = require(ReplicatedStorage.Shared.GameTypes)

type BigNumber = BigNum.BigNumber

export type BlockState = {
	position: Vector3,
	maxHp: BigNumber,
	hp: BigNumber,
	destroyed: boolean,
	seed: number, -- 이 블록의 파괴 순서 셔플 시드. 블록마다 다름
}

-- 정의는 Shared/GameTypes.lua 한 곳에 있다. 이 타입은 RemoteEvent로 클라에 건너가므로
-- 서버·클라가 같은 정의를 봐야 한다. 여기서는 별칭만 두고 기존 이름을 그대로 유지한다
-- (BlockService.BlockChange로 참조하던 코드는 손대지 않아도 된다).
export type BlockChange = GameTypes.BlockChange

export type BlockSnapshotEntry = {
	index: number,
	position: Vector3,
	maxHp: BigNumber,
	hp: BigNumber,
	destroyed: boolean,
	seed: number,
}

type BlockSet = {
	stage: number,
	blocks: { BlockState },
}

local BlockService = {}

-- ===== 배치 좌표 (순수) ==============================================================
-- 계산 자체는 Shared/BlockLayout.lua에 있다. 4-2-a2에서 블록 렌더링이 클라로 넘어가면서
-- 클라도 같은 좌표를 계산해야 해서 나갔다 — 좌표를 전송하지 않고 양쪽이 count 하나로
-- 각자 구한다. 좌표가 원점 고정인 이유(플레이어별 오프셋을 붙이면 안 되는 이유)도
-- 그 파일 상단에 있다.
--
-- 여기서 별칭만 잡는 이유: 아래 buildBlockSet과 _pure 노출이 이 이름을 그대로 쓰고 있고,
-- BlockServiceTests가 _pure.computeLayout을 호출한다. 호출부를 건드리지 않는다.
local computeLayout = BlockLayout.computeLayout

-- ===== 블록 세트 생성 (순수) ============================================================

-- count/maxHp/baseSeed만으로 블록 배열을 만든다. baseSeed 하나에서 블록마다 다른 seed를 뽑아
-- 쓰므로("블록별로 다른 시드") 같은 baseSeed면 항상 같은 결과가 나온다.
local function buildBlockSet(count: number, maxHp: BigNumber, baseSeed: number): { BlockState }
	local positions = computeLayout(count)
	local rng = Random.new(baseSeed)

	local blocks: { BlockState } = {}
	for i = 1, count do
		blocks[i] = {
			position = positions[i],
			maxHp = maxHp,
			hp = maxHp,
			destroyed = false,
			seed = rng:NextInteger(1, 2147483647),
		}
	end
	return blocks
end

-- ===== 데미지 처리 (순수) ===============================================================

-- 힘은 데미지 풀이다. originPosition에서 가까운 순으로 활성(안 죽은) 블록을 정렬해서
-- damage를 순서대로 소진한다 — 반경 개념 없음 (DESIGN.md 2장 "데미지 오버플로우").
--   블록 HP <= 남은 데미지: 그 블록을 파괴하고, 남은 데미지에서 HP만큼 차감한 뒤 다음 블록으로
--   블록 HP >  남은 데미지: 그 블록 HP만 깎고 종료 (남은 데미지 0)
-- blocks를 직접 수정하고(제자리), 이번 호출로 실제 바뀐 블록만 changes로 반환한다.
-- changes의 index는 원래 blocks 배열 기준 위치다 (거리순 정렬은 내부 처리 순서에만 쓴다).
local function applyDamageToBlocks(blocks: { BlockState }, originPosition: Vector3, damage: BigNumber): { BlockChange }
	local changes: { BlockChange } = {}

	if not Schema.isBigNum(damage) or damage.m < 0 then
		return changes
	end

	local active: { { index: number, block: BlockState, distance: number } } = {}
	for index, block in ipairs(blocks) do
		if not block.destroyed then
			table.insert(active, {
				index = index,
				block = block,
				distance = (originPosition - block.position).Magnitude,
			})
		end
	end

	table.sort(active, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.index < b.index -- 거리가 같으면 결정론적으로 원래 순서대로
	end)

	local remaining = damage
	for _, entry in ipairs(active) do
		if BigNum.lte(remaining, BigNum.new(0, 0)) then
			break
		end

		local block = entry.block

		if BigNum.lte(block.hp, remaining) then
			remaining = BigNum.sub(remaining, block.hp)
			block.hp = BigNum.new(0, 0)
			block.destroyed = true
		else
			block.hp = BigNum.sub(block.hp, remaining)
			remaining = BigNum.new(0, 0)
		end

		table.insert(changes, { index = entry.index, hp = block.hp, destroyed = block.destroyed })
	end

	return changes
end

-- ===== 클리어/스냅샷 (순수) =============================================================

local function isBlockSetCleared(blocks: { BlockState }): boolean
	for _, block in ipairs(blocks) do
		if not block.destroyed then
			return false
		end
	end
	return true
end

local function buildSnapshot(blocks: { BlockState }): { BlockSnapshotEntry }
	local snapshot: { BlockSnapshotEntry } = {}
	for index, block in ipairs(blocks) do
		snapshot[index] = {
			index = index,
			position = block.position,
			maxHp = block.maxHp,
			hp = block.hp,
			destroyed = block.destroyed,
			seed = block.seed,
		}
	end
	return snapshot
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
BlockService._pure = {
	computeLayout = computeLayout,
	buildBlockSet = buildBlockSet,
	applyDamageToBlocks = applyDamageToBlocks,
	isBlockSetCleared = isBlockSetCleared,
	buildSnapshot = buildSnapshot,
}

-- ===== 공개 API (Player 상태 보관) ======================================================

local blockSets: { [Player]: BlockSet } = {}

-- 플레이어가 나가면 참조를 정리한다 (ProfileManager.profiles와 동일한 이유 — 안 지우면 Player
-- 인스턴스가 이 테이블에 영구히 붙잡혀 있게 된다).
Players.PlayerRemoving:Connect(function(player: Player)
	blockSets[player] = nil
end)

-- 스테이지 진입 시 블록 세트를 (다시) 만든다. 개수/HP는 StageConfig 기준
-- (StageConfig.getHp가 WorldConfig의 hpBase/hpGrowthSegments로 계산한 값을 그대로 씀).
function BlockService.enterStage(player: Player, stage: number): { BlockSnapshotEntry }
	local count = StageConfig.getBlockCount(stage)
	local maxHp = StageConfig.getHp(stage)
	local baseSeed = Random.new():NextInteger(1, 2147483647)

	local blocks = buildBlockSet(count, maxHp, baseSeed)
	blockSets[player] = { stage = stage, blocks = blocks }

	return buildSnapshot(blocks)
end

-- originPosition에서 가까운 순으로 활성 블록에 damage(데미지 풀)를 소진하고, 이번 타격으로
-- 바뀐 블록들의 {index, hp, destroyed} 목록을 반환한다. 활성 블록 세트가 없으면 nil.
function BlockService.applyDamage(player: Player, originPosition: Vector3, damage: BigNumber): { BlockChange }?
	local set = blockSets[player]
	if set == nil then
		warn(string.format("[BlockService] applyDamage 실패: %s(%d) 활성 블록 세트 없음", player.Name, player.UserId))
		return nil
	end

	return applyDamageToBlocks(set.blocks, originPosition, damage)
end

function BlockService.isCleared(player: Player): boolean
	local set = blockSets[player]
	if set == nil then
		return false
	end
	return isBlockSetCleared(set.blocks)
end

-- 클라 초기 동기화용 스냅샷. 활성 블록 세트가 없으면 nil.
function BlockService.getSnapshot(player: Player): { BlockSnapshotEntry }?
	local set = blockSets[player]
	if set == nil then
		return nil
	end
	return buildSnapshot(set.blocks)
end

return BlockService

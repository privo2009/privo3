--!strict
-- 블록 모델을 월드에 실제로 배치하는 모듈. Phase 4-2-a의 마지막 조각.
--
-- 왜 서버가 만드는가: 블록은 서버 권위 대상이고, 근접 공격 판정이 "플레이어 위치에서
-- 가까운 블록부터"이므로 서버가 좌표를 알고 있어야 한다. 클라가 만들면 그 좌표가
-- 클라 소유가 된다.
--
-- 이 모듈은 계산을 하지 않는다. 좌표·시드·개수는 전부 BlockService가 enterStage에서
-- 만들어 스냅샷으로 돌려준 값을 그대로 옮겨 심는다. 새로 뽑는 값이 하나도 없어야
-- 서버가 판정에 쓰는 좌표와 화면에 보이는 위치가 어긋날 수 없다.
--
-- 의존 방향: ChallengeService → BlockSpawner → (BlockModelGenerator, BlockService 타입)
--   BlockService는 이 모듈을 몰라야 한다. "BlockService는 ChallengeService를 몰라야 한다"와
--   같은 규칙이다 — 아래쪽 계층이 위쪽을 require하기 시작하면 순환이 생긴다.
--
-- 생성/제거 짝: 제거는 다음 생성 직전에만 한다(spawnForStage 첫 줄). 런이 끝날 때는
-- 치우지 않는다 — 유저가 수령 발판과 진행 벽을 고르는 동안 부서진 블록이 남아 있는 것이
-- 자연스럽다. 예외는 PlayerRemoving 하나뿐이고, 그건 정리 안 하면 영영 남기 때문이다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local BlockService = require(script.Parent.BlockService)
local BlockModelGenerator = require(script.Parent.Parent.Tools.BlockModelGenerator)

type BlockSnapshotEntry = BlockService.BlockSnapshotEntry

-- ===== 클라와의 계약 =====================================================================
--
-- Client/Net/RemoteReceiver.client.lua가 이 세 가지로 모델을 찾는다. 이름을 바꾸면
-- 양쪽을 같이 고쳐야 한다.
--   1. Workspace.Blocks 아래
--   2. BlockIndex 어트리뷰트 = BlockChange.index
--   3. Seed 어트리뷰트 = 서버가 그 블록에 부여한 파괴 순서 시드
--
-- 여기에 하나를 더한다: Blocks 바로 아래가 아니라 플레이어별 하위 폴더에 넣는다.
--
-- 근거는 BlockService의 구조다. blockSets[player]로 플레이어마다 따로 들고 있고,
-- 같은 index의 블록이라도 A는 50%, B는 100%일 수 있다. 즉 블록은 공유가 아니라
-- 플레이어별이다. 그런데 모델을 Blocks 바로 아래에 평평하게 깔면 BlockIndex=1인 모델이
-- 접속자 수만큼 생겨서, 클라가 자기 것을 고를 방법이 없다. 폴더로 갈라야 한다.
--
-- ⚠️ 남는 문제: BlockService._pure.computeLayout이 주는 좌표는 원점 기준 고정값이라
--    플레이어가 여럿이면 블록이 같은 자리에 겹쳐 서 있게 된다. 이건 여기서 오프셋을
--    붙여 해결할 수 없다 — 서버의 거리 판정이 쓰는 좌표(BlockService가 들고 있는 값)와
--    화면 위치가 어긋나서 "가까운 블록부터"가 틀어진다. 플레이어별 개인 구역은
--    BlockService의 레이아웃 단계에서 다뤄야 하고, 그때까지 이 모듈은 서버가 판정에
--    쓰는 좌표를 그대로 따른다.
local CONTAINER_NAME = "Blocks"
local BLOCK_INDEX_ATTRIBUTE = "BlockIndex"
local SEED_ATTRIBUTE = "Seed"

-- BlockService의 레이아웃 좌표는 전부 Y=0(수평면)이라 그대로 쓰면 블록 절반이 바닥에
-- 묻힌다. 블록 바닥이 Y=0에 오도록 중심을 반 칸 띄운다 (previewLayout과 같은 기준).
local Y_OFFSET = (BlockLayoutConfig.GRID_SIZE * BlockLayoutConfig.CUBE_SIZE) / 2

local BlockSpawner = {}

-- ===== 템플릿 =========================================================================
--
-- 풀링하지 않는다. 층마다 3~7개를 Destroy하고 다시 Clone한다. 두 가지 이유다:
--
--   1. 규모가 다르다. 파편은 초당 수백 개라 풀링이 필수지만(CLAUDE.md 규칙 4), 블록은
--      20초에 한 번 3~7개다. 그리고 이미 재사용하고 있다 — 64개 큐브를 매번 Instance.new로
--      만드는 게 아니라 템플릿 하나를 Clone한다. 반복 루프의 Instance.new를 피하라는
--      규칙이 요구하는 재사용은 이 지점에서 이미 충족된다.
--   2. 재사용하면 오히려 깨진다. ChunkBreaker는 클라에서 큐브의 Transparency/CanCollide를
--      바꿔 숨기는데, 그건 클라 로컬 변경이라 서버가 되돌릴 수 없다. 부서진 모델을 서버가
--      재사용하면 다음 층에서 그 클라는 이미 숨겨진 큐브를 그대로 보게 된다. Destroy 후
--      새로 복제해야 복제본이 깨끗한 상태로 내려간다.
local templates: { [string]: Model } = {}

local function getTemplate(materialName: string): Model
	local cached = templates[materialName]
	if cached ~= nil then
		return cached
	end

	-- ServerStorage.BlockModels에 디자인 담당이 넣어둔 모델이 있으면 그걸 쓴다.
	-- 없을 때만 즉석 생성본이 나온다.
	local template = BlockModelGenerator.getOrCreateTemplate(materialName)

	if template.Parent == nil then
		local folder = ServerStorage:FindFirstChild("BlockModels")
		if folder == nil then
			local created = Instance.new("Folder")
			created.Name = "BlockModels"
			created.Parent = ServerStorage
			folder = created
		end
		template.Parent = folder
	end

	templates[materialName] = template
	return template
end

-- ===== 컨테이너 =======================================================================

local function getContainer(): Folder
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = Workspace
	return folder
end

local function playerFolderName(player: Player): string
	return tostring(player.UserId)
end

-- ChallengeServiceTests는 { Name, UserId }만 있는 가짜 Player 테이블로 startRun/advance를
-- 굴린다. 그대로 두면 테스트를 돌릴 때마다 Workspace에 블록 수백 개가 생기고, 가짜
-- 플레이어는 PlayerRemoving이 오지 않아 영영 안 지워진다. 실제 접속자에게만 배치한다.
local function isRealPlayer(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
end

-- ===== 공개 API =======================================================================

function BlockSpawner.despawn(player: Player)
	if not isRealPlayer(player) then
		return
	end

	local container = Workspace:FindFirstChild(CONTAINER_NAME)
	if container == nil then
		return
	end

	local folder = container:FindFirstChild(playerFolderName(player))
	if folder ~= nil then
		folder:Destroy()
	end
end

-- snapshot은 BlockService.enterStage가 방금 돌려준 것을 그대로 넘긴다.
-- 좌표도 시드도 여기서 새로 만들지 않는다 — 서버가 판정에 쓰는 값과 같아야 하기 때문이다.
function BlockSpawner.spawnForStage(player: Player, stage: number, snapshot: { BlockSnapshotEntry })
	if not isRealPlayer(player) then
		return
	end

	-- 제거는 여기 한 곳에서만 한다. 생성 직전이라 짝이 어긋날 수 없다.
	BlockSpawner.despawn(player)

	local folder = Instance.new("Folder")
	folder.Name = playerFolderName(player)
	folder.Parent = getContainer()

	local template = getTemplate(StageConfig.getWorld(stage).material)

	for _, entry in ipairs(snapshot) do
		local model = template:Clone()
		model.Name = string.format("Block_%d", entry.index)
		model:SetAttribute(BLOCK_INDEX_ATTRIBUTE, entry.index)
		model:SetAttribute(SEED_ATTRIBUTE, entry.seed)

		BlockModelGenerator.moveModelCenterTo(model, entry.position + Vector3.new(0, Y_OFFSET, 0))
		model.Parent = folder
	end
end

-- 나간 플레이어의 블록은 반드시 치운다. "런이 끝나도 남겨둔다"는 규칙의 유일한 예외다 —
-- 안 치우면 되돌아올 주인이 없는 채로 월드에 영영 남는다.
Players.PlayerRemoving:Connect(function(player: Player)
	BlockSpawner.despawn(player)
end)

return BlockSpawner

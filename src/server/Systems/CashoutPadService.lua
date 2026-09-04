--!strict
-- 수령 발판. 밟으면 ChallengeService.cashout()이 불린다.
--
-- 좌표의 원본은 Shared/Config/ArenaConfig(getCashoutX / CASHOUT_LATERAL_OFFSET)이고
-- 판정의 원본은 ChallengeService(run.cleared)다. 이 파일은 그 둘을 잇는 파트를
-- Workspace에 얹는 일만 한다 — 좌표식도 클리어 판정도 여기에 쓰지 말 것.
-- (PadService가 PadLayout / ClickPadConfig를 대하는 방식과 같다)
--
-- ===== Touched는 신호일 뿐 권한이 아니다 ==============================================
--
-- 발판은 "밟혔다"만 말한다. 클리어했는지도, 보상이 얼마인지도 판정하지 않는다 —
-- 전부 ChallengeService.cashout()이 서버 런 상태로 정한다 (CLAUDE.md 절대 규칙 3).
-- 그래서 이 파일에는 run.cleared를 읽어 분기하는 코드가 없다. 읽는 곳이 둘이 되면
-- 언젠가 갈라지고, 갈라진 쪽이 발판이면 그건 재화 누수다.
--
-- ===== 런당 1회 보장이 어디에 있는가 ===================================================
--
-- 두 겹이다. 둘 다 필요하고 역할이 다르다:
--
--   1. **권위** — ChallengeService.cashout()이 성공하면 런을 지운다(runs[player] = nil).
--      그래서 두 번째 수령은 "활성 런 없음"으로 거부된다. 지급이 두 번 일어나지
--      않는다는 보장은 전적으로 여기에 있다. 이 파일이 아니다.
--      Touched 핸들러 안에는 yield가 없으므로 같은 프레임의 두 접촉이 둘 다
--      "클리어됨"을 읽고 지나가는 창은 없다 — 읽기와 cashout 호출 사이가 원자적이다.
--
--   2. **소음 차단** — 그럼에도 시간 디바운스를 둔다. Touched는 캐릭터가 발판 위에
--      서 있기만 해도 팔다리 파트마다 반복 발화하므로, 없으면 수령 직후부터
--      "활성 런 없음" warn이 초당 수십 줄 쏟아진다. PadService가 잠긴 패드에서
--      같은 문제를 겪었고 같은 방식으로 막았다.
--
-- ⚠️ 1번을 이 파일로 옮기지 말 것. 발판이 "이미 수령했다"를 스스로 기억하면 자동 수령
-- 게임패스(Phase 8)나 자동 진행이 같은 런을 수령할 때 그 기억을 우회한다 —
-- 진입점이 늘어도 보장이 한 곳에 있어야 하는 이유다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ChallengeService = require(script.Parent.ChallengeService)

local CashoutPadService = {}

local CONTAINER_NAME = "CashoutPads"

-- 수령 발판 크기. 정본은 ArenaConfig.CASHOUT_PAD_SIZE다 — 여기가 아니다.
-- LevelConfig가 이 깊이를 읽어 이동속도 상한을 유도하므로 shared에 있어야 한다
-- (그 이유는 ArenaConfig의 해당 주석에 있다).
local PAD_SIZE = ArenaConfig.CASHOUT_PAD_SIZE

-- 수령 = 노랑. docs/UI.md "3. 색"이 원본이다.
local PAD_COLOR = Color3.fromHex("#FFC61A")

-- 같은 발판을 다시 처리하기까지의 최소 간격(초).
-- PadService.TOUCH_DEBOUNCE_SEC과 같은 값이고 같은 이유다 — 서 있기만 해도 팔다리
-- 파트가 각각 여러 번 때린다. 그쪽 상수를 require하지 않는 것은 두 발판이 서로의
-- 사정에 끌려다니면 안 되기 때문이다(패드 디바운스를 튜닝했다고 수령이 따라 변하면 안 된다).
local TOUCH_DEBOUNCE_SEC = 0.5

-- ===== 순수 로직 =====================================================================

export type PadState = {
	lastTouchAt: number,
}

local function newPadState(): PadState
	return { lastTouchAt = 0 }
end

-- 발판 하나의 좌표. 진행축에서 옆으로 비켜 있다.
--
-- ⚠️ 축 위에 두면 다음 스테이지로 걸어가다 밟아서 런이 끝난다. 수령은 런당 1회고
-- 되돌릴 수 없으므로 사고로 밟히면 안 된다 (DESIGN.md "1. 챌린지").
-- 비키는 거리는 ArenaConfig.CASHOUT_LATERAL_OFFSET이고 근거는 캐릭터 폭이다.
--
-- ⚠️ 100·20을 여기 적지 않는다. 스테이지 폭을 조정하면 발판 75개가 전부 따라 움직여야 한다.
local function getPadPosition(stage: number): Vector3
	return Vector3.new(
		ArenaConfig.getCashoutX(stage),
		PAD_SIZE.Y / 2, -- 지면 위에 얹힌다 (그대로 두면 절반이 바닥에 묻힌다)
		ArenaConfig.CASHOUT_LATERAL_OFFSET
	)
end

-- 밟힘을 처리할 것인가.
--
--   "debounced"  같은 창 안의 재접촉. 아무것도 하지 않는다
--   "ok"         cashout을 부른다
--
-- ⚠️ 여기서 클리어 여부를 보지 않는다. 그것은 cashout이 판정한다 — 이 함수가
-- run.cleared를 읽기 시작하면 판정처가 둘이 된다.
--
-- ⚠️ 디바운스에 걸리지 않은 접촉은 **런이 없어도** lastTouchAt을 갱신한다. 갱신하지
-- 않으면 수령 직후 발판 위에 서 있는 동안 창이 매번 열려서 "활성 런 없음" warn이
-- 초당 수십 줄 나온다 (PadService가 잠긴 패드에서 같은 처리를 하는 이유와 같다).
local function applyTouch(state: PadState, now: number): (PadState, string)
	if (now - state.lastTouchAt) < TOUCH_DEBOUNCE_SEC then
		return state, "debounced"
	end
	return { lastTouchAt = now }, "ok"
end

-- 발판을 세울 스테이지 목록. 최종 층에도 발판은 선다 —
-- 진행 벽이 막혀도 수령은 가능하다(ChallengeService.canCashout이 벽과 독립이다).
local function stagesToBuild(lastStage: number): { number }
	local stages = {}
	for stage = 1, lastStage do
		table.insert(stages, stage)
	end
	return stages
end

local function findLastStage(): number
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		stage += 1
	end
	return stage
end

CashoutPadService._pure = {
	newPadState = newPadState,
	applyTouch = applyTouch,
	getPadPosition = getPadPosition,
	stagesToBuild = stagesToBuild,
	findLastStage = findLastStage,
	PAD_SIZE = PAD_SIZE,
	PAD_COLOR = PAD_COLOR,
	TOUCH_DEBOUNCE_SEC = TOUCH_DEBOUNCE_SEC,
}

-- ===== 런타임 =========================================================================

local states: { [Player]: PadState } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)

-- deps로 cashout을 주입받는다. 테스트가 진짜 ChallengeService 없이 호출 순서와
-- 횟수를 잴 수 있게 하기 위한 이음매다 (RebirthService/WarpService와 같은 패턴).
export type Deps = {
	cashout: (Player, string?) -> (boolean, any),
	now: () -> number,
}

local defaultDeps: Deps = {
	cashout = ChallengeService.cashout,
	now = os.clock, -- 챌린지 타이머와 같은 시계 (CLAUDE.md 절대 규칙 3)
}

-- 밟힘 처리. 디바운스를 통과하면 cashout을 부른다.
--
-- ⚠️ 이 함수 안에 yield가 없다. 있으면 같은 프레임의 두 접촉이 둘 다 "런이 살아
-- 있음"을 보고 지나가는 창이 생긴다 — 그 창이 곧 이중 지급이다.
local function handleTouch(deps: Deps, player: Player, stage: number)
	local state = states[player] or newPadState()
	local nextState, result = applyTouch(state, deps.now())
	states[player] = nextState

	if result == "debounced" then
		return
	end

	-- 실패 사유(런 없음 / 미클리어 / 지급 거부)는 전부 cashout이 로깅한다.
	-- 여기서 미리 걸러 warn을 만들면 같은 사실이 두 곳에서 찍힌다.
	deps.cashout(player, "cashout_pad_stage_" .. tostring(stage))
end

CashoutPadService._handleTouch = handleTouch

-- ⚠️ 지환 파트 교체 지점. 지금은 임시 기본 파트다. 교체할 때 바뀌지 않아야 하는
-- 계약은 PadService.createPadPart와 같은 셋이다:
--   - Anchored = true    (물리 시뮬레이션 금지 — CLAUDE.md 절대 규칙 4)
--   - CanCollide = true  (올라서는 발판이다. 클릭 파워 패드와 다른 점이 여기다 —
--                         그쪽은 밟고 지나가는 물건이라 false다)
--   - Touched 연결과 CashoutStage Attribute
--
-- ⚠️ 파티클·이펙트를 여기에 만들지 말 것 (절대 규칙 4). 수령 연출은 클라 몫이다.
-- ⚠️ BillboardGui(예상 획득량)를 붙이지 말 것 — Phase 6이다.
local function createPadPart(stage: number, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = string.format("CashoutPad_%02d", stage)
	part.Size = PAD_SIZE
	part.Position = getPadPosition(stage)
	part.Anchored = true
	part.CanCollide = true
	part.Color = PAD_COLOR
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("CashoutStage", stage)

	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if character == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player == nil then
			return
		end
		handleTouch(defaultDeps, player, stage)
	end)

	part.Parent = parent
	return part
end

local initialized = false

function CashoutPadService.init()
	if initialized then
		warn("[CashoutPadService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- Play 반복·핫리로드로 남은 파트를 걷어낸다. 겹쳐 세우면 한 번 밟을 때 Touched가
	-- 두 배로 발화한다 (PadService.init과 같은 이유·같은 처리).
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace

	local stages = stagesToBuild(findLastStage())
	for _, stage in ipairs(stages) do
		createPadPart(stage, container)
	end

	print(string.format("[CashoutPadService] 수령 발판 %d개 (1~%d층)", #stages, #stages))
end

return CashoutPadService

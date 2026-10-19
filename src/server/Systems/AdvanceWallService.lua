--!strict
-- 진행 벽 트리거. 통과하면 ChallengeService.advance()가 불린다. 3c 커밋 2.
--
-- 좌표의 원본은 Shared/Config/ArenaConfig(getAdvanceWallCenter / getAdvanceWallSize)이고
-- 판정의 원본은 ChallengeService(run.cleared, 다음 층 유무)다. 이 파일은 그 둘을 잇는
-- 보이지 않는 트리거를 Workspace에 얹는 일만 한다 — 좌표식도 클리어 판정도 여기에 쓰지 말 것.
-- (CashoutPadService와 같은 구조다)
--
-- ===== 보이는 벽과 판정하는 벽은 다른 파트다 ===========================================
--
-- 여기 세우는 것은 **판정용** 트리거다: 투명(1) · 충돌 없음 · Touched만 받는다.
-- 막고 보여주는 벽은 클라가 자기 런 상태로 따로 그린다(client/World/AdvanceWallRenderer).
-- 런 상태는 플레이어마다 다른데 서버 파트는 모두에게 하나라서, 서버 파트로 막으면
-- 한 사람의 "열림"이 다른 사람의 "닫힘"을 덮는다.
-- 두 파트는 ArenaConfig.getAdvanceWallCenter 하나로 위치를 얻어서 같은 자리에 겹친다.
--
-- ===== Touched는 신호일 뿐 권한이 아니다 ==============================================
--
-- 트리거는 "통과했다"만 말한다. 클리어 여부도, 다음 층이 있는지도 판정하지 않는다 —
-- 전부 ChallengeService.advance()가 서버 런 상태로 정한다 (CLAUDE.md 절대 규칙 3).
-- 그래서 이 파일은 run.cleared를 읽지 않는다. 읽는 것은 런의 **층 번호**뿐이고,
-- 그것은 판정이 아니라 "이 트리거가 이 플레이어의 지금 층 것인가"를 가리는 데 쓴다.
--
-- ===== 런당 1회 보장이 어디에 있는가 ===================================================
--
-- CashoutPadService와 같은 두 겹이다:
--   1. **권위** — advance()가 성공하면 런의 층이 N+1로 바뀐다. 그래서 같은 트리거 N에
--      다시 닿아도 아래 층 비교에서 걸러지고, advance가 두 번 불리지 않는다.
--   2. **소음 차단** — 시간 디바운스. 캐릭터 팔다리 파트마다 Touched가 반복 발화한다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ChallengeService = require(script.Parent.ChallengeService)

local AdvanceWallService = {}

local CONTAINER_NAME = "AdvanceWallTriggers"

local TOUCH_DEBOUNCE_SEC = ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC

-- ===== 순수 로직 =====================================================================

export type TouchState = {
	lastTouchAt: number,
}

local function newTouchState(): TouchState
	return { lastTouchAt = 0 }
end

-- 디바운스. 의미는 CashoutPadService.applyTouch와 같다 — 창 밖 접촉은 런이 없어도
-- lastTouchAt을 갱신한다(갱신하지 않으면 벽 자리에 서 있는 동안 창이 매번 열린다).
local function applyTouch(state: TouchState, now: number): (TouchState, string)
	if (now - state.lastTouchAt) < TOUCH_DEBOUNCE_SEC then
		return state, "debounced"
	end
	return { lastTouchAt = now }, "ok"
end

-- 트리거 하나의 명세. 위치·크기를 숫자로 내준다 — 파트 생성은 이것을 소비만 한다.
export type TriggerSpec = {
	stage: number,
	x: number,
	y: number,
	z: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
}

-- 트리거를 세울 층 전체. 다음 층이 있는 층 N마다 하나다 — 최종 층에는 세우지 않는다
-- (통과해도 advance가 정상 거부할 뿐이고, 막는 것은 클라 벽의 닫힘 상태다).
--
-- ⚠️ 개수를 적지 말 것. StageConfig에서 파생되므로 월드가 붙으면 저절로 는다.
local function buildTriggerSpecs(): { TriggerSpec }
	local size = ArenaConfig.getAdvanceWallSize()
	local specs: { TriggerSpec } = {}
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		local x, y, z = ArenaConfig.getAdvanceWallCenter(stage)
		table.insert(specs, {
			stage = stage,
			x = x,
			y = y,
			z = z,
			sizeX = size.X,
			sizeY = size.Y,
			sizeZ = size.Z,
		})
		stage += 1
	end
	return specs
end

AdvanceWallService._pure = {
	newTouchState = newTouchState,
	applyTouch = applyTouch,
	buildTriggerSpecs = buildTriggerSpecs,
	TOUCH_DEBOUNCE_SEC = TOUCH_DEBOUNCE_SEC,
}

-- ===== 런타임 =========================================================================

local states: { [Player]: TouchState } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)

-- deps 이음매. 테스트가 진짜 ChallengeService 없이 호출 횟수와 source를 잰다
-- (CashoutPadService.Deps와 같은 패턴).
export type Deps = {
	getRunState: (Player) -> { stage: number }?,
	advance: (Player, string?) -> boolean,
	now: () -> number,
}

local defaultDeps: Deps = {
	getRunState = ChallengeService.getRunState :: any,
	advance = ChallengeService.advance,
	now = os.clock, -- 챌린지 타이머와 같은 시계 (CLAUDE.md 절대 규칙 3)
}

-- 통과 처리.
--   1. 플레이어 단위 디바운스
--   2. 런이 없으면 아무것도 안 한다
--   3. 런의 층이 이 트리거의 층이 아니면 아무것도 안 한다 (로그 없음)
--      — 공용 트리거라 다른 층 자리에서 진행되는 것을 막고, 진행 직후 방금 지난
--        트리거에 겹쳐 있을 때 새 런에 대한 거부 로그가 쏟아지는 것을 막는다
--   4. advance. 클리어 판정은 advance가 한다 — 여기서 cleared를 미리 보지 않는다
--
-- ⚠️ 이 함수 안에 yield가 없다 (CashoutPadService.handleTouch와 같은 이유).
local function handleTouch(deps: Deps, player: Player, wallStage: number)
	local state = states[player] or newTouchState()
	local nextState, result = applyTouch(state, deps.now())
	states[player] = nextState

	if result == "debounced" then
		return
	end

	local run = deps.getRunState(player)
	if run == nil then
		return
	end

	if run.stage ~= wallStage then
		return
	end

	-- 거부 사유(미클리어 / 최종 층)는 전부 advance가 로깅한다.
	deps.advance(player, "advance_wall_stage_" .. tostring(wallStage))
end

AdvanceWallService._handleTouch = handleTouch

-- 트리거 파트. 보이지도 막지도 않는다 — Touched만 받는다.
-- ⚠️ 파티클·이펙트를 여기에 만들지 말 것 (절대 규칙 4). 연출은 클라 몫이다.
local function createTriggerPart(spec: TriggerSpec, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = string.format("AdvanceWallTrigger_%02d", spec.stage)
	part.Size = Vector3.new(spec.sizeX, spec.sizeY, spec.sizeZ)
	part.Position = Vector3.new(spec.x, spec.y, spec.z)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	-- 통로 전체를 덮는 보이지 않는 판이다. 레이캐스트(카메라 가림·마우스 대상)에 걸리면 안 된다.
	-- Touched는 CanTouch로 받으므로 영향이 없다.
	part.CanQuery = false
	part.Transparency = 1
	part:SetAttribute("AdvanceStage", spec.stage)

	local stage = spec.stage
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

function AdvanceWallService.init()
	if initialized then
		warn("[AdvanceWallService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- Play 반복·핫리로드로 남은 파트를 걷어낸다 (CashoutPadService.init과 같은 이유).
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace

	local specs = buildTriggerSpecs()
	for _, spec in ipairs(specs) do
		createTriggerPart(spec, container)
	end

	if #specs > 0 then
		print(string.format(
			"[AdvanceWallService] 진행 벽 트리거 %d개 (%d~%d층)",
			#specs,
			specs[1].stage,
			specs[#specs].stage
		))
	else
		print("[AdvanceWallService] 진행 벽 트리거 0개 (다음 층이 있는 층이 없음)")
	end
end

return AdvanceWallService

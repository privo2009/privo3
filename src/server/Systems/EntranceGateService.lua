--!strict
-- 챌린지 입장 게이트. 지나가면 ChallengeService.startRun(player, 1)이 불린다.
--
-- 런 시작 = 이 게이트를 지나는 순간이다. 20초 타이머는 startRun 시점부터 흐르므로,
-- 스폰에서 입구까지 걷는 시간은 더 이상 20초에 들어가지 않는다 (DESIGN.md "1. 챌린지").
--
-- 좌표의 원본은 Shared/Config/ArenaConfig(getEntranceGateCenter / getEntranceGateSize)다.
-- 이 파일은 그 자리에 보이지 않는 트리거를 얹는 일만 한다 — 좌표식을 여기에 쓰지 말 것.
-- (AdvanceWallService와 같은 구조다)
--
-- ===== 이미 런이 있으면 아무것도 안 한다 ==============================================
--
-- 게이트는 런이 **없을 때만** 런을 세운다. 진행 중이거나 클리어 대기 중인 런을 새 1층
-- 런으로 덮어쓰면 보상이 사라지고 층이 되돌아간다. 이 경우 로그도 찍지 않는다 —
-- 게이트 안에 서 있기만 해도 팔다리 파트마다 Touched가 반복되므로, 찍으면 소음이다.
--
-- ⚠️ 판정은 여전히 ChallengeService에 있다. 이 파일은 "지났다"와 "지금 런이 없다"만
-- 보고, 몇 층부터인지·보상이 얼마인지는 startRun이 정한다.
--
-- ===== 디바운스 =======================================================================
--
-- 진행 벽과 같은 시간 디바운스를 둔다. 창의 의미도 같다(창 안의 재접촉은 무시,
-- 창 밖 접촉은 런이 있어도 시각을 갱신). 상수는 ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC을
-- **공유한다** — 게이트만 다르게 튜닝할 근거가 없고, 두 트리거가 같은 소음 문제를 같은
-- 방법으로 막는다는 것이 한 숫자로 드러나는 편이 낫다. 갈라야 할 이유가 생기면 그때 나눈다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local ChallengeService = require(script.Parent.ChallengeService)

local EntranceGateService = {}

local CONTAINER_NAME = "EntranceGate"
local PART_NAME = "EntranceGateTrigger"

-- 게이트가 세우는 런의 층. 입구는 스테이지 1의 시작 면이다(ArenaConfig.getEntranceX).
local START_STAGE = 1

local TOUCH_DEBOUNCE_SEC = ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC

-- ===== 순수 로직 =====================================================================

export type TouchState = {
	lastTouchAt: number,
}

local function newTouchState(): TouchState
	return { lastTouchAt = 0 }
end

-- 디바운스. 의미는 AdvanceWallService.applyTouch와 같다.
local function applyTouch(state: TouchState, now: number): (TouchState, string)
	if (now - state.lastTouchAt) < TOUCH_DEBOUNCE_SEC then
		return state, "debounced"
	end
	return { lastTouchAt = now }, "ok"
end

export type GateSpec = {
	x: number,
	y: number,
	z: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
}

local function buildGateSpec(): GateSpec
	local x, y, z = ArenaConfig.getEntranceGateCenter()
	local size = ArenaConfig.getEntranceGateSize()
	return {
		x = x,
		y = y,
		z = z,
		sizeX = size.X,
		sizeY = size.Y,
		sizeZ = size.Z,
	}
end

EntranceGateService._pure = {
	newTouchState = newTouchState,
	applyTouch = applyTouch,
	buildGateSpec = buildGateSpec,
	TOUCH_DEBOUNCE_SEC = TOUCH_DEBOUNCE_SEC,
	START_STAGE = START_STAGE,
	CONTAINER_NAME = CONTAINER_NAME,
	PART_NAME = PART_NAME,
}

-- ===== 런타임 =========================================================================

local states: { [Player]: TouchState } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)

-- deps 이음매 (AdvanceWallService.Deps와 같은 패턴).
export type Deps = {
	getRunState: (Player) -> any?,
	startRun: (Player, number?) -> boolean,
	now: () -> number,
}

local defaultDeps: Deps = {
	getRunState = ChallengeService.getRunState :: any,
	startRun = ChallengeService.startRun,
	now = os.clock, -- 챌린지 타이머와 같은 시계 (CLAUDE.md 절대 규칙 3)
}

-- 통과 처리.
--   1. 플레이어 단위 디바운스
--   2. 런이 이미 있으면 아무것도 안 한다 (로그 없음)
--   3. 없으면 startRun(player, 1)
--
-- ⚠️ 이 함수 안에 yield가 없다. 있으면 같은 프레임의 두 접촉이 둘 다 "런 없음"을 보고
-- 런을 두 번 세우는 창이 생긴다.
local function handleTouch(deps: Deps, player: Player)
	local state = states[player] or newTouchState()
	local nextState, result = applyTouch(state, deps.now())
	states[player] = nextState

	if result == "debounced" then
		return
	end

	if deps.getRunState(player) ~= nil then
		return
	end

	local ok = deps.startRun(player, START_STAGE)
	-- 런당 한 줄이다(위 두 분기가 소음을 이미 걸렀다). 런이 어디서 섰는지 로그로 갈린다 —
	-- 같은 startRun을 Bootstrap 검증·환생·워프도 부른다.
	print(string.format("[EntranceGateService] %s 입장 -> startRun(%d) = %s", player.Name, START_STAGE, tostring(ok)))
end

EntranceGateService._handleTouch = handleTouch

-- 트리거 파트. 보이지도 막지도 않는다 — Touched만 받는다.
-- ⚠️ 파티클·이펙트를 여기에 만들지 말 것 (절대 규칙 4). 시각 표시는 U4 몫이다.
local function createGatePart(spec: GateSpec, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = PART_NAME
	part.Size = Vector3.new(spec.sizeX, spec.sizeY, spec.sizeZ)
	part.Position = Vector3.new(spec.x, spec.y, spec.z)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	-- 통로 전체를 덮는 보이지 않는 판이다. 레이캐스트에 걸리면 안 된다 (진행 벽 트리거와 같다).
	part.CanQuery = false
	part.Transparency = 1

	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if character == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player == nil then
			return
		end
		handleTouch(defaultDeps, player)
	end)

	part.Parent = parent
	return part
end

local initialized = false

function EntranceGateService.init()
	if initialized then
		warn("[EntranceGateService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- Play 반복·핫리로드로 남은 파트를 걷어낸다 (AdvanceWallService.init과 같은 이유).
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace

	local spec = buildGateSpec()
	createGatePart(spec, container)

	print(string.format(
		"[EntranceGateService] 입장 게이트 X=%.1f 크기 %.1f x %.1f x %.1f",
		spec.x,
		spec.sizeX,
		spec.sizeY,
		spec.sizeZ
	))
end

return EntranceGateService

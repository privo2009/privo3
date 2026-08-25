--!strict
-- 클릭 파워 패드의 런타임. 파트를 세우고, 밟은 신호를 받아, 플레이어별 선택 상태를 들고 있다.
--
-- 값의 원본은 Shared/Config/ClickPadConfig(파워·해금 조건)와 Shared/PadLayout(좌표)이다.
-- 이 파일은 그 둘을 Workspace에 얹고 선택 상태를 관리하는 일만 한다 — 파워 계산식이나
-- 좌표식을 여기에 다시 쓰지 말 것.
--
-- ===== 판정은 전부 서버다 (CLAUDE.md 3) ================================================
--
-- Touched는 신호일 뿐 권한이 아니다. 밟았다는 사실만으로 패드가 적용되지 않는다 —
-- 그 패드가 실제로 해금 상태인지는 서버가 프로필의 lifetimeBlox로 매번 판정한다.
-- 클라는 파트를 밟는 것 외에 이 경로에 개입할 수단이 없다(RemoteEvent를 두지 않았다).
--
-- ===== 선택은 세팅이지 누적이 아니다 ===================================================
--
-- 밟으면 그 패드 값으로 "바뀐다". 낮은 패드를 밟으면 내려간다.
-- 이게 맞는 이유: 올라가기만 한다면 유저는 최고 패드를 한 번 찍고 다시는 패드를 안 본다.
-- 내려갈 수 있어야 "지금 어느 패드에 서 있는가"가 계속 의미를 갖는다. 그리고 내려가는 것이
-- 손해이므로 낮은 패드를 밟을 조작 유인 자체가 없다 — 막을 이유가 없는 동작이다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)

type BigNumber = BigNum.BigNumber

local PadService = {}

-- Workspace에 세우는 패드가 속한 월드.
-- ⚠️ 지금은 월드가 1개뿐이라 상수로 둔다. 월드 2가 생기면 여기서 갈라진다 — 패드 파트는
-- Workspace에 하나만 서고 전원이 같은 것을 밟는데, clickPadSet은 월드마다 다르기 때문이다.
-- 그때는 월드별 패드 구역을 따로 세우거나(공간 분리) 플레이어별로 스트리밍해야 한다.
-- 지금 미리 만들지 않는 이유: 어느 쪽인지는 맵이 나와야 정해진다.
local PAD_WORLD_ID = 1

-- 같은 패드를 다시 처리하기까지의 최소 간격(초).
-- Touched는 연타·재접촉으로 중복 발화한다(CLAUDE.md 3). 캐릭터가 패드 위에 서 있기만 해도
-- 팔다리 파트가 각각 여러 번 때리므로, 이게 없으면 한 번 밟을 때 로그가 수십 줄 쌓이고
-- 잠긴 패드에서는 warn이 그만큼 쏟아진다.
local TOUCH_DEBOUNCE_SEC = 0.5

local PAD_CONTAINER_NAME = "ClickPads"

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

export type PadState = {
	selectedIndex: number,
	lastTouchIndex: number?,
	lastTouchAt: number,
}

-- 밟기 시도 하나를 처리해서 (새 상태, 결과)를 돌려준다. 상태를 제자리에서 고치지 않는다.
-- 결과는 "ok" / "debounced" / "locked" 셋 중 하나다.
--
-- 잠긴 패드도 lastTouchAt을 갱신한다 — 갱신하지 않으면 잠긴 패드 위에 서 있는 동안
-- 디바운스가 매번 열려서 warn이 초당 수십 줄 나온다.
local function applyTouch(
	state: PadState,
	worldId: number,
	index: number,
	lifetimeBlox: BigNumber,
	now: number
): (PadState, string)
	if state.lastTouchIndex == index and (now - state.lastTouchAt) < TOUCH_DEBOUNCE_SEC then
		return state, "debounced"
	end

	-- 이름을 next로 쓰지 않는다 — 전역 next()를 가린다.
	local moved: PadState = {
		selectedIndex = state.selectedIndex,
		lastTouchIndex = index,
		lastTouchAt = now,
	}

	if not ClickPadConfig.isUnlocked(worldId, index, lifetimeBlox) then
		return moved, "locked"
	end

	-- 세팅이지 누적이 아니다. 낮은 패드면 내려간다 (파일 상단 주석 참고).
	moved.selectedIndex = index
	return moved, "ok"
end

-- 저장된 인덱스를 현재 Config + lifetimeBlox 기준으로 다시 재본다.
--
-- 왜 필요한가: 인덱스는 프로필에 남지만 그 인덱스의 해금 조건은 WorldConfig에 있다.
-- 조건을 올리는 튜닝(4-2-f)을 하면 이미 저장된 인덱스가 조건 미달이 된다. 그대로 두면
-- 유저가 해금하지 않은 파워를 계속 쓰게 되므로, 로드 시점에 만족하는 최고 인덱스로 내린다.
-- 값이 아니라 인덱스를 저장하는 이유도 같다 — 파워값을 저장했다면 이 재검증 자체가 불가능하다.
--
-- 깨진 값(nil, 실수, 0 이하, count 초과)도 여기서 1..count로 접는다. Schema는 Config를
-- 몰라야 해서 상한(count)을 검사할 수 없기 때문에, 상한 판정은 이쪽 책임이다.
local function clampSelectedIndex(worldId: number, storedIndex: any, lifetimeBlox: BigNumber): number
	local set = ClickPadConfig.getSet(worldId)

	local index = storedIndex
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 then
		index = 1
	elseif index > set.count then
		index = set.count
	end

	local maxUnlocked = ClickPadConfig.getUnlockedPadCount(worldId, lifetimeBlox)
	if index > maxUnlocked then
		index = maxUnlocked
	end

	return index
end

local function newPadState(selectedIndex: number): PadState
	return {
		selectedIndex = selectedIndex,
		lastTouchIndex = nil,
		lastTouchAt = 0,
	}
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- (BlockService._pure와 같은 패턴)
PadService._pure = {
	applyTouch = applyTouch,
	clampSelectedIndex = clampSelectedIndex,
	newPadState = newPadState,
	TOUCH_DEBOUNCE_SEC = TOUCH_DEBOUNCE_SEC,
}

-- ===== 공개 API (Player 상태 보관) =====================================================

local states: { [Player]: PadState } = {}
local initialized = false

-- 플레이어가 나가면 참조를 정리한다 (BlockService.blockSets와 같은 이유 — 안 지우면 Player
-- 인스턴스가 이 테이블에 영구히 붙잡혀 있게 된다).
Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)

-- 프로필에서 lifetimeBlox를 읽는다.
-- CurrencyService.get을 쓰지 않는 이유: lifetimeBlox는 CURRENCIES 목록에 없어서 assert로 막힌다
-- (add로 blox를 넣을 때 파생 갱신되는 값이라 직접 증감 대상이 아니다). 여기서는 읽기만 하므로
-- CLAUDE.md 규칙 2(직접 "수정" 금지)에 걸리지 않는다.
local function readLifetimeBlox(profile: any): BigNumber
	local raw = profile.Data.lifetimeBlox
	if type(raw) ~= "table" or type(raw.m) ~= "number" or type(raw.e) ~= "number" then
		warn("[PadService] lifetimeBlox가 BigNum 형태가 아님 - 0으로 취급")
		return BigNum.new(0, 0)
	end
	return BigNum.deserialize(raw)
end

local function handleTouch(player: Player, index: number)
	local profile = ProfileManager.get(player)
	if profile == nil then
		-- 프로필 로드 전에 밟은 경우. 판정 근거가 없으니 아무것도 하지 않는다.
		return
	end

	local state = states[player]
	if state == nil then
		-- onLoaded보다 Touched가 먼저 온 경우. 저장값 기준으로 지금 만든다.
		state = newPadState(clampSelectedIndex(PAD_WORLD_ID, profile.Data.progress.selectedPadIndex, readLifetimeBlox(profile)))
		states[player] = state
	end

	local nextState, result = applyTouch(state, PAD_WORLD_ID, index, readLifetimeBlox(profile), os.clock())
	states[player] = nextState

	if result == "debounced" then
		return
	end

	if result == "locked" then
		warn(string.format(
			"[PadService] %s(%d) 잠긴 패드 %d 밟음 - 무시 (필요 lifetimeBlox=%s)",
			player.Name,
			player.UserId,
			index,
			BigNum.tostring(ClickPadConfig.getPadUnlock(PAD_WORLD_ID, index))
		))
		return
	end

	-- 선택이 실제로 바뀐 경우에만 저장한다. 같은 패드를 다시 밟는 것은 상태 변화가 아니다.
	if nextState.selectedIndex ~= state.selectedIndex then
		profile.Data.progress.selectedPadIndex = nextState.selectedIndex
		print(string.format(
			"[PadService] %s(%d) 패드 %d 선택 (파워=%s)",
			player.Name,
			player.UserId,
			nextState.selectedIndex,
			BigNum.tostring(ClickPadConfig.getPadPower(PAD_WORLD_ID, nextState.selectedIndex))
		))
	end
end

-- 패드 파트 하나를 만든다.
--
-- ⚠️ 지환 파트 교체 지점. 지금은 임시 기본 파트다. 실제 파트가 들어오면 여기를
-- ReplicatedStorage 템플릿 Clone으로 바꾼다 — BlockModelBuilder.getOrCreateTemplate이 선례고,
-- 템플릿을 ReplicatedStorage에 두는 이유(클라가 ServerStorage를 볼 수 없다)도 거기 적혀 있다.
-- 교체할 때 바뀌지 않아야 하는 계약은 아래 세 가지뿐이다:
--   - Anchored = true       (물리 시뮬레이션 금지)
--   - CanCollide = false    (밟고 지나가는 물건이지 올라서는 발판이 아니다)
--   - Touched 연결과 PadIndex Attribute
-- 색·재질·BillboardGui는 클라 시각 표현이라 이 파일의 범위가 아니다(4-2-b 이후).
local function createPadPart(index: number, position: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = string.format("ClickPad_%02d", index)
	part.Size = PadLayout.PAD_SIZE
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("PadIndex", index)

	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if character == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player == nil then
			return
		end
		handleTouch(player, index)
	end)

	part.Parent = parent
	return part
end

-- 패드를 Workspace에 세우고 프로필 로드 훅을 건다.
function PadService.init()
	if initialized then
		warn("[PadService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	local set = ClickPadConfig.getSet(PAD_WORLD_ID)
	local positions = PadLayout.computeLayout(set.count)

	-- Play를 반복하거나 핫리로드된 경우 이전 패드가 남아 있을 수 있다. 겹쳐 세우면
	-- 같은 자리에 파트가 둘이 되어 한 번 밟을 때 Touched가 두 배로 발화한다.
	local existing = Workspace:FindFirstChild(PAD_CONTAINER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = PAD_CONTAINER_NAME
	container.Parent = Workspace

	for i = 1, set.count do
		createPadPart(i, positions[i], container)
	end

	-- 로드 시 재검증. 저장된 인덱스를 지금의 Config + lifetimeBlox로 다시 재서 클램프한다.
	ProfileManager.onLoaded(function(player: Player, profile: any)
		local stored = profile.Data.progress.selectedPadIndex
		local clamped = clampSelectedIndex(PAD_WORLD_ID, stored, readLifetimeBlox(profile))

		if clamped ~= stored then
			warn(string.format(
				"[PadService] %s(%d) selectedPadIndex 클램프: %s -> %d (해금 조건 미달 또는 범위 밖)",
				player.Name,
				player.UserId,
				tostring(stored),
				clamped
			))
			profile.Data.progress.selectedPadIndex = clamped
		end

		states[player] = newPadState(clamped)
	end)

	print(string.format("[PadService] 월드 %d 패드 %d개 생성 완료", PAD_WORLD_ID, set.count))
end

-- 현재 선택된 패드의 클릭 파워. 선택 상태가 없으면 패드 1 값이다.
--
-- 상태가 없는 경우: 프로필 로드 전이거나(onLoaded 미도달) PadService.init()을 안 부른 상태.
-- 둘 다 "아직 아무것도 밟지 않았다"와 같으므로 패드 1로 답하는 것이 맞다 — nil을 돌려주면
-- 호출부마다 0 처리인지 1 처리인지 제각각 정하게 된다.
function PadService.getClickPower(player: Player): BigNumber
	local state = states[player]
	local index = if state ~= nil then state.selectedIndex else 1
	return ClickPadConfig.getPadPower(PAD_WORLD_ID, index)
end

-- 현재 선택된 패드 인덱스. 상태가 없으면 1.
function PadService.getSelectedIndex(player: Player): number
	local state = states[player]
	return if state ~= nil then state.selectedIndex else 1
end

return PadService

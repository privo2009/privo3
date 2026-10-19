--!strict
-- 진행 벽의 모습을 런 상태에서 계산한다. 순수 모듈이다 — 인스턴스를 만들지 않고,
-- Player·프로필·Service를 보지 않으며, warn도 찍지 않는다.
--
-- 입력은 RunStateChanged의 상태 형태다 (active는 payload에, 나머지는 payload.state에 있다 —
-- 호출자가 한 테이블로 모아 넘긴다). 판정 자체는 서버(ChallengeService.advance)가 하고,
-- 이 함수는 그 판정 결과(cleared/canAdvance)를 "어떻게 보이는가"로 옮기기만 한다.
--
--   active ≠ true                         → 보이지 않음
--   active, cleared=false                 → 닫힘 (중립 회색, 불투명, 충돌 O)
--   active, cleared, canAdvance=true      → 열림 (진행·도박 보라, 반투명, 충돌 X)
--   active, cleared, canAdvance=false     → 닫힘 (최종층 — 위 닫힘과 같은 모습)
--
-- ⚠️ 위치는 ArenaConfig.getAdvanceWallCenter(stage)를 **부른다** (x는 그 안에서
-- getAdvanceX다). 같은 식을 여기서 다시 계산하지 말 것 — 두 벌이 되면 폭을 바꿨을 때
-- 벽만 옛 자리에 남고, 서버 트리거(같은 함수를 쓴다)와 보이는 벽이 갈라진다.
-- ⚠️ 색은 hex가 아니라 UiTheme 역할 키다. 실제 Color3는 렌더 쪽이 UiTheme.Colors에서 꺼낸다.

local ArenaConfig = require(script.Parent.Config.ArenaConfig)
local UiTheme = require(script.Parent.Config.UiTheme)

local AdvanceWallView = {}

export type Input = {
	active: boolean?,
	stage: number?,
	cleared: boolean?,
	canAdvance: boolean?,
}

export type View = {
	visible: boolean,
	open: boolean,
	canCollide: boolean,
	colorRole: UiTheme.ColorRole,
	transparency: number,
	-- stage가 유효할 때만 채운다. 없거나 잘못됐으면 nil.
	x: number?,
	y: number?,
	z: number?,
	size: Vector3?,
	-- nil이 아닌 잘못된 stage(0·음수·소수·NaN 등)일 때만 "invalid_stage".
	-- nil 입력·stage 없음은 정상 상황이라 넣지 않는다. 경고를 찍을지는 호출자 몫이다.
	invalid: string?,
}

local CLOSED_TRANSPARENCY = 0

-- 보이지 않는 벽은 막지도 않는다. 렌더 쪽이 visible을 빠뜨리고 값을 그대로 꽂아도
-- 안 보이고 안 막히게 하려는 값이다 (투명 1 · 충돌 X).
local function hidden(x: number?, y: number?, z: number?, size: Vector3?, invalid: string?): View
	return {
		visible = false,
		open = false,
		canCollide = false,
		colorRole = "neutral",
		transparency = 1,
		x = x,
		y = y,
		z = z,
		size = size,
		invalid = invalid,
	}
end

local function isValidStage(stage: any): boolean
	return type(stage) == "number" and stage == stage and stage % 1 == 0 and stage >= 1
end

function AdvanceWallView.compute(state: Input?): View
	if state == nil or state.stage == nil then
		return hidden(nil, nil, nil, nil, nil)
	end

	if not isValidStage(state.stage) then
		return hidden(nil, nil, nil, nil, "invalid_stage")
	end

	local stage = state.stage :: number
	local x, y, z = ArenaConfig.getAdvanceWallCenter(stage)
	local size = ArenaConfig.getAdvanceWallSize()

	if state.active ~= true then
		return hidden(x, y, z, size, nil)
	end

	if state.cleared == true and state.canAdvance == true then
		return {
			visible = true,
			open = true,
			canCollide = false,
			colorRole = "advance",
			transparency = ArenaConfig.ADVANCE_WALL_OPEN_TRANSPARENCY,
			x = x,
			y = y,
			z = z,
			size = size,
			invalid = nil,
		}
	end

	-- 미클리어, 또는 클리어했지만 다음 층이 없다(최종층).
	return {
		visible = true,
		open = false,
		canCollide = true,
		colorRole = "neutral",
		transparency = CLOSED_TRANSPARENCY,
		x = x,
		y = y,
		z = z,
		size = size,
		invalid = nil,
	}
end

return AdvanceWallView

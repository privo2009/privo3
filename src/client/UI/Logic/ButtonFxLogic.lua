--!strict
-- 버튼 반응 상태 전이 · 목표 Scale · 트윈 종류 · 잘림 상한 (지시서 #21 A — docs/UI.md "UI 효과"). 순수 모듈 — 화면은 Components/ButtonFx.
--
--   상태   idle(기본) · hover(마우스 올림) · pressed(누름)
--   사건   enter · leave(마우스가 들어옴 · 나감) · down · up(누름 · 뗌) · disable(비활성)
--   규칙   idle + enter → hover / hover + leave → idle / idle · hover + down → pressed
--          pressed + leave → idle(누른 채 밖으로 — 1로 돌아간다. 클릭 처리는 엔진 Activated 그대로 — 여기서 하지 않는다)
--          pressed + up → 안에 있으면 hover · 아니면 idle(터치는 올림이 없어 언제나 idle)
--          비활성이면 어떤 사건이든 idle(반응하지 않는다)
--   트윈   → pressed: PRESS(Quad Out) / pressed → 다른 것: RELEASE(Back Out) / 그 밖: HOVER(Quad Out)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)

local ButtonFxLogic = {}

export type State = "idle" | "hover" | "pressed"
export type Event = "enter" | "leave" | "down" | "up" | "disable"

export type Ctx = {
	inside: boolean, -- 사건 뒤 마우스가 버튼 위에 있나
	touch: boolean, -- 터치 입력인가(올림 없음)
	disabled: boolean,
}

function ButtonFxLogic.transition(state: State, event: Event, ctx: Ctx): State
	if ctx.disabled or event == "disable" then
		return "idle"
	end
	if event == "down" then
		return "pressed"
	elseif event == "up" then
		if state ~= "pressed" then
			return state
		end
		return if ctx.inside and not ctx.touch then "hover" else "idle"
	elseif event == "enter" then
		if ctx.touch or state == "pressed" then
			return state
		end
		return "hover"
	elseif event == "leave" then
		return "idle"
	end
	return state
end

function ButtonFxLogic.targetScale(state: State): number
	if state == "hover" then
		return UIFxConfig.HOVER_SCALE
	elseif state == "pressed" then
		return UIFxConfig.PRESS_SCALE
	end
	return 1
end

export type TweenSpec = { time: number, style: Enum.EasingStyle, direction: Enum.EasingDirection }

-- clipped = 자르는 조상 안이라 커지는 쪽을 줄였다(fitScale). 그때 뗌은 Back(넘침)을 쓰지 않는다 — 넘친 만큼 잘리므로 올림과 같은 Quad로.
function ButtonFxLogic.tweenSpec(from: State, to: State, clipped: boolean?): TweenSpec
	if to == "pressed" then
		return { time = UIFxConfig.PRESS_TIME, style = UIFxConfig.PRESS_STYLE, direction = UIFxConfig.PRESS_DIRECTION }
	elseif from == "pressed" and clipped then
		return { time = UIFxConfig.RELEASE_TIME, style = UIFxConfig.HOVER_STYLE, direction = UIFxConfig.HOVER_DIRECTION }
	elseif from == "pressed" then
		return { time = UIFxConfig.RELEASE_TIME, style = UIFxConfig.RELEASE_STYLE, direction = UIFxConfig.RELEASE_DIRECTION }
	end
	return { time = UIFxConfig.HOVER_TIME, style = UIFxConfig.HOVER_STYLE, direction = UIFxConfig.HOVER_DIRECTION }
end

-- 잘림 상한: 가운데 기준으로 s배 커져도 자르는 조상(ClipsDescendants · ScrollingFrame) 사각형 안에 머무는 가장 큰 s.
-- rect · clip = {x0, y0, x1, y1}(화면 픽셀). 이미 밖으로 나가 있으면(스크롤) 1 — 커지지 않을 뿐 줄이지는 않는다.
function ButtonFxLogic.fitScale(rect: { number }, clip: { number }): number
	local w, h = rect[3] - rect[1], rect[4] - rect[2]
	if w <= 0 or h <= 0 then
		return 1
	end
	local cx, cy = (rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2
	local halfX = math.min(cx - clip[1], clip[3] - cx)
	local halfY = math.min(cy - clip[2], clip[4] - cy)
	local s = math.min(halfX / (w / 2), halfY / (h / 2))
	return if s ~= s then 1 else math.max(1, s)
end

-- 실제로 쓰는 목표 Scale: 커지는 쪽(올림 · Back 넘침)은 잘림 상한 안으로 줄인다. 줄어드는 쪽(누름)은 그대로.
function ButtonFxLogic.cappedScale(state: State, cap: number): number
	local s = ButtonFxLogic.targetScale(state)
	if s > 1 then
		return math.min(s, cap)
	end
	return s
end

return ButtonFxLogic

--!strict
-- 수령 발판 하나의 모습을 내 런 상태에서 계산한다. 순수 모듈이다 — 인스턴스를 만들지 않고,
-- Player·프로필·Service를 보지 않는다. AdvanceWallView와 같은 자리·같은 방식이다.
--
-- 발판은 층마다 서 있는 서버 파트이고 전원이 공유한다. "이 발판이 내게 켜져 있는가"는
-- 나만의 상태라, 클라가 자기 화면에서만 칠한다(CashoutPadRenderer). 판정은 여전히
-- 서버(ChallengeService.cashout + CashoutPadService의 층 대조)다 — 이 함수는 그 판정이
-- "통과할 상태인가"를 보이는 색으로 옮기기만 한다.
--
--   active, cleared, stage == 발판 층   → 켜짐 (수령·안전 노랑)
--   그 밖 전부 (런 없음·미클리어·다른 층) → 꺼짐 (중립 회색)
--
-- ⚠️ 켜짐 조건을 서버 판정보다 넓히지 말 것. 켜진 발판을 밟았는데 수령이 안 되면 거짓 신호다.
-- ⚠️ 색은 hex가 아니라 UiTheme 역할 키다. 실제 Color3는 렌더 쪽이 UiTheme.Colors에서 꺼낸다.

local UiTheme = require(script.Parent.Config.UiTheme)

local CashoutPadView = {}

export type Input = {
	active: boolean?,
	stage: number?,
	cleared: boolean?,
}

export type View = {
	lit: boolean,
	colorRole: UiTheme.ColorRole,
}

local LIT: View = { lit = true, colorRole = "cashout" }
local UNLIT: View = { lit = false, colorRole = "neutral" }

-- 서버 파트가 처음 만들어질 때의 색도 이 꺼짐 역할이다(CashoutPadService) — 렌더러가
-- 붙기 전이나 런 상태를 아직 못 받았을 때 켜진 발판이 보이지 않게 하려는 것이다.
CashoutPadView.UNLIT_ROLE = UNLIT.colorRole

function CashoutPadView.compute(state: Input?, padStage: number): View
	if state == nil or state.active ~= true or state.cleared ~= true then
		return UNLIT
	end
	if state.stage ~= padStage then
		return UNLIT
	end
	return LIT
end

return CashoutPadView

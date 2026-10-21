--!strict
-- 런 표시층 안내(클리어 선택 · 실패)를 무엇으로 띄울지 정한다 (U4, 지시서 #5). 순수 모듈 —
-- 화면(Screens/Overlay/RunNotice)은 이 결과만 그린다. docs/UI.md "6. 패널 > 레이어 우선순위".
--
--   클리어 선택 안내   클리어 후 런이 살아 있는 동안. "발판 = 수령 / 벽 = 진행". 최종층이면 "수령만 가능"
--   실패              시간 초과로 런이 끝났을 때. 획득 0
--   숨김              새 층 진입 · 수령 · 포기로 상황이 바뀌었을 때
--   nil               이 전이로는 바꿀 것이 없다(지금 표시를 그대로 둔다)
--
-- 둘 다 비차단이다(모달 금지). 실패 뒤 다시 하려면 입장 게이트를 걸어서 지나면 되고 화면 조작이
-- 필요 없으므로 차단할 이유가 없다 — docs/UI.md의 "실패는 조건부 비차단" 서술을 이 근거로 확정했다.

local RunNoticeLogic = {}

export type Kind = "clear" | "clearFinal" | "fail" | "hide"

export type Input = {
	active: boolean,
	reason: string,
	cleared: boolean,
	canAdvance: boolean,
}

function RunNoticeLogic.decide(input: Input): Kind?
	if input.active then
		if input.cleared and (input.reason == "cleared" or input.reason == "sync") then
			return if input.canAdvance then "clear" else "clearFinal"
		end
		if input.reason == "start" or input.reason == "advance" or input.reason == "sync" then
			return "hide"
		end
		return nil
	end
	if input.reason == "timeout" then
		return "fail"
	end
	return "hide"
end

-- 표시 시간(초). 둘 다 "짧게"다 — 클리어 안내는 선택지를 처음 알려 주는 용도라 고르는 동안 계속
-- 띄우지 않는다(3D 표시가 발판·벽 위에 남아 있다). 시각 튜닝값이다(게임 수치 아님).
RunNoticeLogic.DURATION_SEC = {
	clear = 5,
	clearFinal = 5,
	fail = 4,
}

return RunNoticeLogic

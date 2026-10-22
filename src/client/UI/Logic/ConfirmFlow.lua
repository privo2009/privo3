--!strict
-- 되돌릴 수 없는 버튼의 확인 단계 (환생 창 · 월드·워프 창 공용). 순수 모듈.
--
-- 한 번 누름으로는 절대 실행되지 않는다. 첫 누름은 "확인 중"으로 바꿀 뿐이고, windowSec 안에 한 번 더
-- 눌러야 "send"가 나온다. 시간이 지나거나 cancel하면 처음으로 돌아간다. 잠겨 있으면 "locked"이고
-- 확인 상태도 풀린다(잠긴 버튼을 두 번 눌러 잠금이 풀리는 순간 바로 실행되는 일이 없게).

local ConfirmFlow = {}

export type Action = "askConfirm" | "send" | "locked"

export type Flow = {
	press: (now: number, enabled: boolean) -> Action,
	cancel: () -> (),
	isArmed: (now: number) -> boolean,
}

function ConfirmFlow.new(windowSec: number): Flow
	local armedAt: number? = nil

	local function isArmed(now: number): boolean
		local armed = armedAt
		return armed ~= nil and now - armed <= windowSec
	end

	return {
		press = function(now: number, enabled: boolean): Action
			if not enabled then
				armedAt = nil
				return "locked"
			end
			if isArmed(now) then
				armedAt = nil
				return "send"
			end
			armedAt = now
			return "askConfirm"
		end,
		cancel = function()
			armedAt = nil
		end,
		isArmed = isArmed,
	}
end

return ConfirmFlow

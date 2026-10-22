--!strict
-- 같은 줄 접기 (Phase 6 지시서 #8 4단계). 같은 플레이어 · 같은 거부 사유 로그가 짧은 시간 안에 반복되면 한 줄로 접는다.
--
-- 왜: 수령 발판 · 진행 벽은 Touched로 들어오고 Touched는 서 있는 동안 계속 발화한다. 클리어 전에 발판 위에 서 있으면
-- "cashout 거부 … 아직 클리어 안 됨"이 초당 여러 줄 찍혀 정작 봐야 할 줄이 밀려난다(GetLogHistory 보관량에도 상한이 있다 —
-- CLAUDE.md "GetLogHistory도 보관량에 상한").
--
-- 규칙:
--   첫 줄은 반드시 찍는다(키가 처음이거나 창이 지났으면)
--   창(windowSec) 안의 같은 키는 찍지 않고 센다
--   창이 지난 뒤 같은 키가 다시 오면, 먼저 "같은 줄 N번 더 — 접음" 한 줄을 찍고 새 줄을 찍는다
-- 판정은 바꾸지 않는다 — 로그 출력만 거른다. 시계와 출력은 주입한다(테스트가 시간을 돌린다).

local LogFold = {}

LogFold.WINDOW_SEC = 5 -- Claude가 정한 값(세션 로그): 발판 위에 서 있는 몇 초 동안의 반복을 한 묶음으로 본다

type Entry = { startedAt: number, suppressed: number, lastMessage: string }

export type Folder = {
	log: (key: string, message: string) -> boolean, -- 찍었으면 true
	suppressedCount: (key: string) -> number,
}

function LogFold.new(windowSec: number, clock: () -> number, emit: (string) -> ()): Folder
	local entries: { [string]: Entry } = {}
	local folder = {}

	function folder.log(key: string, message: string): boolean
		local now = clock()
		local entry = entries[key]
		if entry ~= nil and now - entry.startedAt < windowSec then
			entry.suppressed += 1
			entry.lastMessage = message
			return false
		end
		if entry ~= nil and entry.suppressed > 0 then
			emit(string.format("%s (앞선 %g초 동안 같은 줄 %d번 더 — 접음)", entry.lastMessage, windowSec, entry.suppressed))
		end
		emit(message)
		entries[key] = { startedAt = now, suppressed = 0, lastMessage = message }
		return true
	end

	function folder.suppressedCount(key: string): number
		local entry = entries[key]
		return if entry ~= nil then entry.suppressed else 0
	end

	return folder :: Folder
end

return LogFold

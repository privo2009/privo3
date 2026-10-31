--!strict
-- UTC 하루 경계 (지시서 #20 D2 — DESIGN.md 9장 "일일 보상"). 순수 함수 — 시각은 부르는 쪽이 넘긴다(서버는 os.time() — 절대 규칙 3).
--
--   dayNumber(t)        UTC 일 번호 = floor(t / 86400). 1970-01-01 = 0. 하루 경계는 UTC 0시
--   secondsToNextDay(t) 다음 UTC 0시까지 남은 초(1 ~ 86400). 0시 정각이면 86400(하루 전체)
-- os.time()은 UTC 기준 초다(로블록스 엔진 문서 — os.time은 유닉스 시각). 기기 시계를 쓰지 않는다(서버에서만 부른다).

local DayClock = {}

DayClock.SECONDS_PER_DAY = 86400

local function finite(t: any): number
	return if type(t) == "number" and t == t and t ~= math.huge and t ~= -math.huge then t else 0
end

function DayClock.dayNumber(t: number): number
	return math.floor(finite(t) / DayClock.SECONDS_PER_DAY)
end

function DayClock.secondsToNextDay(t: number): number
	local s = finite(t)
	return (DayClock.dayNumber(s) + 1) * DayClock.SECONDS_PER_DAY - math.floor(s)
end

-- HH:MM(올림 — 남은 59초는 1분으로 보인다). 표시용(클라 창).
function DayClock.hhmm(seconds: number): string
	local s = math.max(0, math.ceil(finite(seconds) / 60) * 60)
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	return string.format("%02d:%02d", h, m)
end

return DayClock

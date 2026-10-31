--!strict
-- 일일 보상 판정 (지시서 #20 D1 · D2 — DESIGN.md 9장 "일일 보상 > 판정"). 순수 — 서버 DailyService가 부르고, 테스트가 그대로 잰다.
--
--   status(daily, today)
--     lastClaimDay == today                    → 오늘 받음: canClaim false · day = streak(오늘 받은 칸)
--     lastClaimDay == today − 1 · streak < 칸 수 → 연속: canClaim true · day = streak + 1
--     그 밖(처음 · 이틀 이상 비움 · 어제 7일째)   → canClaim true · day = 1 (D1)
--     shownStreak = 창에 "받음"으로 칠할 칸 수(끊긴 연속은 0 — 화면에서도 1일부터)
--   afterClaim(day, today) → 저장할 {streak = day, lastClaimDay = today}

local DailyRewardConfig = require(script.Parent.Config.DailyRewardConfig)

local DailyLogic = {}

export type Status = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number, -- 받을 칸(받을 수 있을 때) 또는 오늘 받은 칸
	shownStreak: number, -- 받음으로 칠할 칸 수
}

local function whole(v: any, lo: number, hi: number, fallback: number): number
	if type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi then
		return v
	end
	return fallback
end

function DailyLogic.status(daily: any, today: number): Status
	local cycle = DailyRewardConfig.CYCLE_DAYS
	local d = if type(daily) == "table" then daily else {}
	local streak = whole(d.streak, 0, cycle, 0)
	local last = whole(d.lastClaimDay, 0, math.huge, 0)
	if last ~= 0 and last == today and streak >= 1 then
		return { canClaim = false, claimedToday = true, day = streak, shownStreak = streak }
	end
	if last ~= 0 and last == today - 1 and streak >= 1 and streak < cycle then
		return { canClaim = true, claimedToday = false, day = streak + 1, shownStreak = streak }
	end
	return { canClaim = true, claimedToday = false, day = 1, shownStreak = 0 }
end

function DailyLogic.afterClaim(day: number, today: number): { streak: number, lastClaimDay: number }
	return { streak = day, lastClaimDay = today }
end

return DailyLogic

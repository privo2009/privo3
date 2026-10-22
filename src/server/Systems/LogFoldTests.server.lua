--!strict
-- LogFold 검증 (지시서 #8 4단계): 첫 줄은 반드시 찍는다 · 창 안의 반복은 접는다 · 창이 지나면 "N번 더" 한 줄 + 새 줄 ·
-- 키(플레이어 · 사유)가 다르면 서로 접지 않는다. 시계와 출력을 주입해 굴린다.

local LogFold = require(script.Parent.LogFold)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local clock = 0
local lines: { string } = {}
local folder = LogFold.new(5, function()
	return clock
end, function(message: string)
	table.insert(lines, message)
end)

check("첫 줄은 찍는다", folder.log("1|cashout_not_cleared", "거부 A") == true and #lines == 1 and lines[1] == "거부 A")
clock = 0.1
check("창 안 반복은 접는다", folder.log("1|cashout_not_cleared", "거부 A") == false and #lines == 1)
clock = 2
folder.log("1|cashout_not_cleared", "거부 A")
folder.log("1|cashout_not_cleared", "거부 A")
check("접은 횟수를 센다", folder.suppressedCount("1|cashout_not_cleared") == 3)

check("다른 사유는 따로 — 첫 줄 찍음", folder.log("1|advance_not_cleared", "거부 B") == true and #lines == 2)
check("다른 플레이어는 따로 — 첫 줄 찍음", folder.log("2|cashout_not_cleared", "거부 A2") == true and #lines == 3)

clock = 6 -- 창(5초)이 지났다
check("창이 지나면 다시 찍는다", folder.log("1|cashout_not_cleared", "거부 A'") == true)
check("먼저 'N번 더 — 접음' 요약 한 줄", #lines == 5 and string.find(lines[4], "3번 더", 1, true) ~= nil and string.find(lines[4], "접음", 1, true) ~= nil, lines[4])
check("그다음 새 줄", lines[5] == "거부 A'")
check("새 창에서 횟수는 0부터", folder.suppressedCount("1|cashout_not_cleared") == 0)

clock = 20
local before = #lines
folder.log("2|cashout_not_cleared", "거부 A2")
check("반복이 없었으면 요약 줄 없이 새 줄만", #lines == before + 1)

-- ChallengeService가 실제로 접는다 — 같은 가짜 플레이어가 클리어 전 cashout을 거듭 시도해도 판정은 그대로(false)
do
	local ChallengeService = require(script.Parent.ChallengeService)
	local fake = { Name = "LogFoldTestPlayer", UserId = 999980 } :: any
	ChallengeService.startRun(fake, 1)
	local allRejected = true
	for _ = 1, 5 do
		local ok = ChallengeService.cashout(fake, "cashout_pad")
		if ok ~= false then
			allRejected = false
		end
	end
	check("ChallengeService: 접어도 판정은 그대로(클리어 전 cashout 5번 모두 거부)", allRejected)
	ChallengeService.abandonRun(fake)
end

print(string.format("[LogFoldTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LogFoldTests] %d test(s) failed", failed))
end

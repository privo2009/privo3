--!strict
-- 테스트 끝 표시 (지시서 #26 단계 1) — 순수 로직.
--
-- 테스트 파일은 저마다 혼자 돌고 "[이름] N passed, M failed" 한 줄을 찍고 끝난다. 러너가 따로 없어서
-- "이 쪽 테스트가 다 끝났다"를 알 길이 없었다 — 늦게 찍히는 파일(LocaleClientTests · FxTests처럼 기다리는 파일)이
-- 아직인지 빠진 것인지 읽는 쪽이 90초를 세며 짐작해야 했다.
--
-- 끝 표시 스크립트(Server/Tests/TestRunDone · Client/Tests/TestRunDone, Studio 전용)가 이 모듈로
--   1. 기대 목록 = 그 쪽 컨테이너 아래 이름이 "Tests"로 끝나는 스크립트(Script · LocalScript)
--   2. 찍힌 요약 줄을 LogService에서 몇 번이고 다시 읽어 모은다(시각 + 문장으로 같은 줄을 한 번만 센다)
--   3. 다 모이거나 상한(WAIT_SEC)이 지나면 끝 줄 하나를 찍는다:
--      "[TestRunDone] server 69/69 files · 2963 passed, 0 failed"
-- 끝 줄은 CLAUDE.md 읽기 코드의 필터("%d+ passed, %d+ failed")에 걸리도록 같은 꼴로 끝난다 — 읽기 코드를 바꾸지 않는다.
-- 끝 줄은 테스트 행이 아니다(ROADMAP 표 대조에서 뺀다). 빠진 파일 · 두 번 찍힌 파일은 따로 warn 줄로 남긴다.
--
-- 줄을 계속 모아 두므로, 나중에 출력이 많아 LogService 보관량에서 앞쪽 요약 줄이 밀려나도 끝 줄의 합계는 그대로다.

local TestRunLogic = {}

TestRunLogic.TAG = "TestRunDone"
TestRunLogic.WAIT_SEC = 90 -- CLAUDE.md "기다리기"의 상한과 같다
TestRunLogic.POLL_SEC = 0.5

-- 요약 줄 하나를 읽는다. 아니면 nil. 끝 줄 자신은 "[TestRunDone] server …"라 이 꼴에 맞지 않는다.
function TestRunLogic.parse(message: string): (string?, number?, number?)
	local name, p, f = string.match(message, "^%[(%w+)%] (%d+) passed, (%d+) failed$")
	if name == nil or name == TestRunLogic.TAG then
		return nil, nil, nil
	end
	return name, tonumber(p), tonumber(f)
end

-- 기대 목록: container 아래 이름이 "Tests"로 끝나는 Script · LocalScript(모듈 제외). 이름 순.
function TestRunLogic.expected(container: Instance): { string }
	local names = {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BaseScript") and string.sub(d.Name, -5) == "Tests" then
			table.insert(names, d.Name)
		end
	end
	table.sort(names)
	return names
end

export type Collector = {
	feed: (key: string, message: string) -> (),
	complete: () -> boolean,
	result: () -> { seen: number, expected: number, passed: number, failed: number, missing: { string }, dups: { string } },
}

function TestRunLogic.newCollector(expected: { string }): Collector
	local want: { [string]: boolean } = {}
	for _, n in ipairs(expected) do
		want[n] = true
	end
	local keys: { [string]: boolean } = {}
	local rows: { [string]: { passed: number, failed: number, times: number } } = {}
	local seen = 0

	local function feed(key: string, message: string)
		if keys[key] then
			return
		end
		keys[key] = true
		local name, p, f = TestRunLogic.parse(message)
		if name == nil or not want[name] then
			return
		end
		local row = rows[name]
		if row == nil then
			rows[name] = { passed = p :: number, failed = f :: number, times = 1 }
			seen += 1
		else
			row.times += 1
		end
	end

	local function complete(): boolean
		return seen >= #expected
	end

	local function result()
		local passed, failed, missing, dups = 0, 0, {}, {}
		for _, n in ipairs(expected) do
			local row = rows[n]
			if row == nil then
				table.insert(missing, n)
			else
				passed += row.passed
				failed += row.failed
				if row.times > 1 then
					table.insert(dups, n)
				end
			end
		end
		return { seen = seen, expected = #expected, passed = passed, failed = failed, missing = missing, dups = dups }
	end

	return { feed = feed, complete = complete, result = result }
end

-- 끝 줄. side = "server" | "client". 같은 파일이 두 번 찍혔으면 합계는 첫 줄 것만 더한다.
function TestRunLogic.doneLine(side: string, r: { seen: number, expected: number, passed: number, failed: number }): string
	return string.format("[%s] %s %d/%d files · %d passed, %d failed", TestRunLogic.TAG, side, r.seen, r.expected, r.passed, r.failed)
end

-- 이 쪽(server · client) 끝 표시를 돌린다. 스크립트 두 개가 부른다. Studio가 아니면 아무것도 하지 않는다(TestGate — #27 T1).
function TestRunLogic.run(side: string, container: Instance)
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	local LogService = game:GetService("LogService")
	local expected = TestRunLogic.expected(container)
	local collector = TestRunLogic.newCollector(expected)
	local deadline = os.clock() + TestRunLogic.WAIT_SEC
	while true do
		for _, e in LogService:GetLogHistory() do
			collector.feed(tostring(e.timestamp) .. " " .. e.message, e.message)
		end
		if collector.complete() or os.clock() >= deadline then
			break
		end
		task.wait(TestRunLogic.POLL_SEC)
	end
	local r = collector.result()
	print(TestRunLogic.doneLine(side, r))
	if #r.missing > 0 then
		warn(string.format("[%s] %s 상한 %d초 안에 안 찍힌 파일 %d개: %s", TestRunLogic.TAG, side, TestRunLogic.WAIT_SEC, #r.missing,
			table.concat(r.missing, ", ")))
	end
	if #r.dups > 0 then
		warn(string.format("[%s] %s 두 번 이상 찍힌 파일: %s", TestRunLogic.TAG, side, table.concat(r.dups, ", ")))
	end
end

return TestRunLogic

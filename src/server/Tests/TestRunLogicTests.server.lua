--!strict
-- TestRunLogic 검증 (지시서 #26 단계 1). Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- 테스트 끝 표시가 요약 줄을 맞게 읽고 · 기대 목록을 맞게 모으고 · 끝 줄이 CLAUDE.md 읽기 코드의 필터에 걸리는지 본다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestRunLogic = require(ReplicatedStorage.Shared.TestRunLogic)

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

-- 1. 요약 줄 읽기 ------------------------------------------------------------------------------
do
	local n, p, f = TestRunLogic.parse("[BigNumTests] 96 passed, 0 failed")
	check("요약 줄: 이름 · passed · failed", n == "BigNumTests" and p == 96 and f == 0)
	local n2, _, f2 = TestRunLogic.parse("[HudLayoutTests] 40 passed, 3 failed")
	check("요약 줄: failed가 있어도 읽는다", n2 == "HudLayoutTests" and f2 == 3)
	check("요약 줄 아님: 다른 로그", TestRunLogic.parse("[ClickInput] 클릭 수집 시작") == nil)
	check("요약 줄 아님: 앞뒤에 글이 붙은 줄(K11 안내 등)", TestRunLogic.parse("x [BigNumTests] 1 passed, 0 failed") == nil
		and TestRunLogic.parse("[BigNumTests] 1 passed, 0 failed!") == nil)
	check("요약 줄 아님: 오류 줄(… test(s) failed)", TestRunLogic.parse("[BigNumTests] 2 test(s) failed") == nil)
end

-- 2. 끝 줄 -----------------------------------------------------------------------------------
do
	local line = TestRunLogic.doneLine("server", { seen = 69, expected = 69, passed = 2963, failed = 0 })
	check("끝 줄 꼴", line == "[TestRunDone] server 69/69 files · 2963 passed, 0 failed", line)
	check("끝 줄은 CLAUDE.md 읽기 코드 필터(%d+ passed, %d+ failed)에 걸린다", string.find(line, "%d+ passed, %d+ failed") ~= nil)
	check("끝 줄은 테스트 행으로 읽히지 않는다", TestRunLogic.parse(line) == nil)
	check("끝 줄 이름(TAG)으로 된 요약 꼴 줄도 행이 아니다", TestRunLogic.parse("[TestRunDone] 1 passed, 0 failed") == nil)
end

-- 3. 모으기 ----------------------------------------------------------------------------------
do
	local c = TestRunLogic.newCollector({ "ATests", "BTests" })
	check("처음엔 덜 모였다", not c.complete())
	c.feed("1.0 [ATests] 3 passed, 0 failed", "[ATests] 3 passed, 0 failed")
	c.feed("1.0 [ATests] 3 passed, 0 failed", "[ATests] 3 passed, 0 failed") -- 같은 줄을 다시 읽음(폴링)
	c.feed("1.1 [ZTests] 9 passed, 0 failed", "[ZTests] 9 passed, 0 failed") -- 기대 목록 밖
	c.feed("1.2 [Other] hello", "[Other] hello")
	local r1 = c.result()
	check("같은 줄을 다시 읽어도 한 번 · 목록 밖 이름은 안 센다", r1.seen == 1 and r1.passed == 3 and #r1.dups == 0,
		string.format("seen=%d passed=%d dups=%d", r1.seen, r1.passed, #r1.dups))
	check("빠진 파일 목록", #r1.missing == 1 and r1.missing[1] == "BTests" and not c.complete())
	c.feed("2.0 [BTests] 4 passed, 1 failed", "[BTests] 4 passed, 1 failed")
	local r2 = c.result()
	check("다 모이면 complete · 합계", c.complete() and r2.seen == 2 and r2.expected == 2 and r2.passed == 7 and r2.failed == 1)
	c.feed("3.0 [ATests] 3 passed, 0 failed", "[ATests] 3 passed, 0 failed") -- 시각이 다른 같은 문장 = 두 번 찍힘
	local r3 = c.result()
	check("두 번 찍힌 파일은 dups에 · 합계는 첫 줄만", #r3.dups == 1 and r3.dups[1] == "ATests" and r3.passed == 7 and r3.seen == 2)
	local empty = TestRunLogic.newCollector({})
	check("기대 목록이 비면 바로 complete(0/0)", empty.complete() and empty.result().expected == 0)
end

-- 4. 기대 목록 -------------------------------------------------------------------------------
do
	local root = Instance.new("Folder")
	local sub = Instance.new("Folder")
	sub.Parent = root
	local function add(class: string, name: string, parent: Instance)
		local s = Instance.new(class :: any)
		s.Name = name
		s.Parent = parent
	end
	add("Script", "ZetaTests", root)
	add("Script", "AlphaTests", sub)
	add("LocalScript", "BetaTests", sub)
	add("ModuleScript", "HelperTests", sub) -- 모듈은 테스트가 아니다
	add("Script", "TestRunDone", root) -- 끝 표시 자신
	add("Script", "CurveReport", root)
	add("Script", "TestsHelper", root) -- "Tests"로 끝나지 않는다
	local names = TestRunLogic.expected(root)
	check("기대 목록: Tests로 끝나는 Script · LocalScript만 · 이름 순", table.concat(names, ",") == "AlphaTests,BetaTests,ZetaTests",
		table.concat(names, ","))
	root:Destroy()
end

-- 5. 실물 기대 목록 — 이 서버의 *Tests 스크립트에 이 파일이 들어 있다 --------------------------------------
do
	local names = TestRunLogic.expected(script.Parent.Parent)
	check("실물: 서버 기대 목록에 이 파일(TestRunLogicTests)이 있다 · TestRunDone은 없다",
		table.find(names, "TestRunLogicTests") ~= nil and table.find(names, "TestRunDone") == nil, tostring(#names))
	check("상한 = CLAUDE.md 기다리기 상한 90초 · 폴링 0.5초", TestRunLogic.WAIT_SEC == 90 and TestRunLogic.POLL_SEC == 0.5)
end

print(string.format("[TestRunLogicTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TestRunLogicTests] %d test(s) failed", failed))
end

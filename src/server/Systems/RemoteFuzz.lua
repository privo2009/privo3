--!strict
-- 리모트 입구 흔들기 공통 도우미(지시서 #38 — 테스트 전용 · 게임 코드는 부르지 않는다).
-- 입구 = RemoteGuard 문(모양 · 연타) + 서비스 처리. 둘을 같은 순서로 이어 붙여 잘못된 인자 묶음과 연타를 넣고
-- "거부되고 상태는 그대로"(바꾸는 deps가 한 번도 안 불림)를 본다. 쓰는 곳: RemoteGuardTests.
--
-- spec:
--   name       리모트 이름(RemoteGuard 통 크기를 고른다)
--   make()     새 입구 하나 → (onRequest(player, payload, now) → out, calls) — calls[key] = 바꾸는 deps 호출 수
--   valid      정상 요청(대조 — 이것은 받아들여져야 한다). nil이면 대조를 건너뛴다(payload를 안 읽는 입구 · 등록 상품이 없는 입구)
--   fields     { 필드 = "number" | "string"(정해진 값) | "id"(모양만) | "boolean" | "array" } — 그 필드만 바꾼 변형을 만든다
--   noControl  true면 대조를 건너뛰고 변형만 본다(등록 상품 ID가 없는 입구)
--   payloadFree true면 payload를 읽지 않는 입구(환생 · 일일 · 동기화) — 변형 검사 대신 "오류 없음"만
--   gap        연타 검사 간격(초 — 기본 0.001)

local RemoteGuard = require(script.Parent.RemoteGuard)

local RemoteFuzz = {}

local LONG = string.rep("x", 300)
local NUMBER_BAD = { 0 / 0, math.huge, -math.huge, -1, 0, 1.5, -0.5, 1e308, -1e308, 2 ^ 53 + 2, 1e15 }
local STRING_BAD = { "", LONG, string.rep("가", 80), "\0" }
local WRONG_TYPE = { true, false, 1, -1, "x", {}, { 1, 2, 3 }, { a = 1 } }

-- payload 통째로 잘못된 것(모양 문이 거르거나 서비스가 거른다)
function RemoteFuzz.wholeBad(): { { label: string, value: any } }
	local deep = { a = { b = { c = { d = { e = 1 } } } } }
	local wide = {}
	for i = 1, 200 do
		wide["k" .. i] = i
	end
	local list = {
		{ label = "nil", value = nil },
		{ label = "true", value = true },
		{ label = "숫자", value = 7 },
		{ label = "NaN", value = 0 / 0 },
		{ label = "inf", value = math.huge },
		{ label = "문자열", value = "craft" },
		{ label = "긴 문자열", value = string.rep("a", 10000) },
		{ label = "빈 표", value = {} },
		{ label = "배열", value = { 1, 2, 3 } },
		{ label = "깊은 표", value = deep },
		{ label = "큰 표", value = wide },
		{ label = "action 숫자", value = { action = 1 } },
		{ label = "action 모름", value = { action = "nope" } },
		{ label = "action 긴 글", value = { action = LONG } },
		{ label = "action 표", value = { action = {} } },
	}
	return list
end

local function wrongFor(kind: string): { any }
	local out = {}
	for _, v in ipairs(WRONG_TYPE) do
		local t = type(v)
		local same = (kind == "number" and t == "number") or ((kind == "string" or kind == "id") and t == "string") or (kind == "boolean" and t == "boolean")
			or (kind == "array" and t == "table")
		if not same then
			table.insert(out, v)
		end
	end
	if kind == "number" then
		for _, v in ipairs(NUMBER_BAD) do
			table.insert(out, v)
		end
	elseif kind == "string" then
		for _, v in ipairs(STRING_BAD) do
			table.insert(out, v)
		end
		table.insert(out, "nope_unknown")
	elseif kind == "id" then
		-- id는 모양만 문에서 본다(빈 글 · 긴 글). 있는 id인지는 그 서비스(보유 · 설정표)가 판정한다
		table.insert(out, "")
		table.insert(out, LONG)
	end
	return out
end

-- 정상 요청에서 필드 하나만 바꾼 변형들. 배열 필드는 원소 하나씩 · 길이도 바꾼다.
function RemoteFuzz.variants(valid: { [string]: any }, fields: { [string]: string }): { { label: string, value: any } }
	local out = {}
	for field, kind in pairs(fields) do
		local missing = table.clone(valid)
		missing[field] = nil
		table.insert(out, { label = field .. "=nil", value = missing })
		for i, bad in ipairs(wrongFor(kind)) do
			local p = table.clone(valid)
			p[field] = bad
			table.insert(out, { label = string.format("%s#%d=%s", field, i, string.sub(tostring(bad), 1, 12)), value = p })
		end
		if kind == "array" then
			local arr = valid[field] :: { any }
			for idx = 1, #arr do
				for j, bad in ipairs(wrongFor("number")) do
					local p = table.clone(valid)
					local copy = table.clone(arr)
					copy[idx] = bad
					p[field] = copy
					table.insert(out, { label = string.format("%s[%d]#%d", field, idx, j), value = p })
				end
			end
			local short = table.clone(valid)
			short[field] = { table.unpack(arr, 1, math.max(0, #arr - 1)) }
			table.insert(out, { label = field .. " 짧음", value = short })
			local long = table.clone(valid)
			local more = table.clone(arr)
			table.insert(more, arr[1])
			long[field] = more
			table.insert(out, { label = field .. " 김", value = long })
		end
	end
	return out
end

local function total(calls: { [string]: number }): number
	local n = 0
	for _, c in pairs(calls) do
		n += c
	end
	return n
end

-- 입구 하나를 흔든다. 결과: { controlOk, badLeaks = {라벨}, wholeLeaks = {라벨}, spamCalls, errors = {글} }
function RemoteFuzz.run(spec: any): any
	local report = { controlOk = true, badLeaks = {}, wholeLeaks = {}, spamCalls = 0, errors = {} }
	local P = ({ Name = "fuzz", UserId = 1 } :: any)
	local function through(onRequest: any, gate: any, payload: any, now: number): boolean
		if not gate.check(P, spec.name, payload, now) then
			return false
		end
		local ok, err = pcall(onRequest, P, payload, now)
		if not ok then
			table.insert(report.errors, string.sub(tostring(err), 1, 160))
		end
		return true
	end
	-- 대조
	if spec.valid ~= nil and not spec.noControl then
		local onRequest, calls = spec.make()
		through(onRequest, RemoteGuard._pure.newGate(), spec.valid, 100)
		report.controlOk = total(calls) >= 1
	end
	-- 통째로 잘못된 payload
	for _, case in ipairs(RemoteFuzz.wholeBad()) do
		local onRequest, calls = spec.make()
		through(onRequest, RemoteGuard._pure.newGate(), case.value, 100)
		if not spec.payloadFree and total(calls) > 0 then
			table.insert(report.wholeLeaks, case.label)
		end
	end
	-- 필드 하나씩
	if spec.valid ~= nil and spec.fields ~= nil and not spec.payloadFree then
		for _, case in ipairs(RemoteFuzz.variants(spec.valid, spec.fields)) do
			local onRequest, calls = spec.make()
			through(onRequest, RemoteGuard._pure.newGate(), case.value, 100)
			if total(calls) > 0 then
				table.insert(report.badLeaks, case.label)
			end
		end
	end
	-- 연타: 같은 요청 20번을 짧은 간격으로
	do
		local onRequest, calls = spec.make()
		local gate = RemoteGuard._pure.newGate()
		local payload = spec.valid or spec.spamPayload or {}
		for i = 0, 19 do
			through(onRequest, gate, payload, 200 + i * (spec.gap or 0.001))
		end
		report.spamCalls = total(calls)
	end
	return report
end

-- 바꾸는 deps를 세는 가짜 묶음. reads = 읽기 deps(그대로), mutators = { 이름 = 돌려줄 함수 }.
function RemoteFuzz.spyDeps(reads: { [string]: any }, mutators: { [string]: (...any) -> ...any }): (any, { [string]: number })
	local calls: { [string]: number } = {}
	local deps = table.clone(reads)
	for key, fn in pairs(mutators) do
		calls[key] = 0
		deps[key] = function(...)
			calls[key] += 1
			return fn(...)
		end
	end
	return deps, calls
end

return RemoteFuzz

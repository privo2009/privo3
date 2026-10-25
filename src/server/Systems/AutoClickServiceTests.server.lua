--!strict
-- AutoClickService 검증 (지시서 #16 4단계 · DESIGN 9장 S8). 가짜 deps로 굴린다 — 실제 클릭 · 프로필을 건드리지 않는다.
--   초당 횟수(15 · 30 · 소수 이월) · 수동 무시(켜져 있는 동안) · 수동 상한 10 불변 · 미보유 잠김(not_owned) · 보유가 사라지면 끔 ·
--   세션 토글(나가면 지운다) · payload 위생 · 빈도

local ServerScriptService = game:GetService("ServerScriptService")

local AutoClickService = require(ServerScriptService.Server.Systems.AutoClickService)
local ClickService = require(ServerScriptService.Server.Systems.ClickService)

local pure = AutoClickService._pure
local C = ClickService._pure

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

local function newWorld(rate: number)
	local w: any = { rate = rate, clicks = 0, batches = 0, sent = {} }
	w.runtime = pure.createRuntime({
		rateOf = function()
			return w.rate
		end,
		click = function(_p, n: number)
			w.clicks += n
			w.batches += 1
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w
end

local P: any = { Name = "AutoClickTest", UserId = 901 }
local STEP = pure.MIN_INTERVAL_SEC

-- 1. payload · 빈도 · 잠김 ------------------------------------------------------------------------------
do
	check("payload: boolean만", pure.readOn({ on = true }) == true and pure.readOn({ on = false }) == false and pure.readOn({ on = 1 }) == nil
		and pure.readOn(true) == nil)
	local w = newWorld(0)
	local r = w.runtime.onRequest(P, { on = true }, 0)
	check("미보유: 켜기 거부 not_owned · 꺼진 채 · 초당 0", not r.ok and r.reason == AutoClickService.REASON_NOT_OWNED and not r.on and r.rate == 0
		and not w.runtime.isOn(P))
	w.runtime.tick(1)
	check("미보유: 클릭을 만들지 않는다", w.clicks == 0)
	local bad = w.runtime.onRequest(P, { on = "yes" }, STEP)
	check("payload 틀림 → invalid_request", not bad.ok and bad.reason == AutoClickService.REASON_INVALID)
	local fast = w.runtime.onRequest(P, { on = false }, STEP * 1.5)
	check("빈도: 간격 안 두 번째 → rate_limited", not fast.ok and fast.reason == AutoClickService.REASON_RATE_LIMITED)
end

-- 2. 초당 횟수 ------------------------------------------------------------------------------------------
do
	local w = newWorld(15)
	local r = w.runtime.onRequest(P, { on = true }, 0)
	check("보유(15): 켜기 성공 · on · 초당 15", r.ok and r.on and r.rate == 15 and w.runtime.isOn(P))
	for _ = 1, 5 do
		w.runtime.tick(0.2)
	end
	check("자동 클리커 15: 1초에 정확히 15회", w.clicks == 15, tostring(w.clicks))
	for _ = 1, 50 do
		w.runtime.tick(0.2)
	end
	check("자동 클리커 15: 11초에 165회(오차 누적 없음)", w.clicks == 165, tostring(w.clicks))
	local op = newWorld(30)
	op.runtime.onRequest(P, { on = true }, 0)
	for _ = 1, 5 do
		op.runtime.tick(0.2)
	end
	check("OP 자동 클리커 30: 1초에 30회", op.clicks == 30, tostring(op.clicks))
	local odd = newWorld(15)
	odd.runtime.onRequest(P, { on = true }, 0)
	for _ = 1, 10 do
		odd.runtime.tick(0.1) -- 배치당 1.5회 → 소수는 다음 배치로
	end
	check("소수 이월: 0.1초 × 10 = 15회", odd.clicks == 15, tostring(odd.clicks))
	local off = w.runtime.onRequest(P, { on = false }, STEP)
	local before = w.clicks
	w.runtime.tick(1)
	check("끄기: 성공 · 더 만들지 않는다", off.ok and not off.on and w.clicks == before and not w.runtime.isOn(P))
end

-- 3. 수동 무시 · 수동 상한 10 불변 ---------------------------------------------------------------------------
do
	local w = newWorld(15)
	check("수동 차단: 꺼져 있으면 false", not w.runtime.isActive(P))
	w.runtime.onRequest(P, { on = true }, 0)
	check("수동 차단: 켜져 있고 보유면 true(수동 클릭은 힘에 안 들어간다)", w.runtime.isActive(P))
	w.rate = 0
	check("수동 차단: 보유가 사라지면 false(수동으로 돌아간다)", not w.runtime.isActive(P))
	check("수동 상한: 10 그대로", C.MANUAL_CLICK_LIMIT == 10)
	-- 자동 경로(passAll)는 상한 윈도우를 쓰지 않는다 — 자동으로 30회 넣은 뒤에도 수동은 윈도우 안에서 10회까지 통과
	local state = C.newClickState()
	local s1, autoAccepted = C.passAll(state, 30)
	local _s2, manualAccepted, manualRejected = C.applyClicks(s1, 25, 0)
	check("자동 30회 뒤에도 수동은 10회 통과 · 15회 버림(윈도우 공유 안 함)", autoAccepted == 30 and manualAccepted == 10 and manualRejected == 15)
end

-- 4. 보유가 사라지면 끈다 · 세션 토글 -----------------------------------------------------------------------
do
	local w = newWorld(15)
	w.runtime.onRequest(P, { on = true }, 0)
	w.rate = 0
	w.runtime.tick(0.2)
	local last = w.sent[#w.sent]
	check("보유가 사라지면 루프가 끄고 알린다(not_owned · on false)", not w.runtime.isOn(P) and last.reason == AutoClickService.REASON_NOT_OWNED
		and last.on == false and w.clicks == 0)
	w.rate = 15
	w.runtime.onRequest(P, { on = true }, STEP)
	w.runtime.onRemoving(P)
	check("세션 토글: 나가면 지운다(다시 오면 꺼짐)", not w.runtime.isOn(P))
	check("모든 요청에 결과 1건", #w.sent == 3)
end

-- 5. 실물 연결: ClickService에 수동 차단 훅이 달렸다(init 뒤) — 상태를 바꾸지 않는 확인만 ---------------------------------------
do
	local fake: any = { Name = "AutoClickHook", UserId = 902 }
	check("실물: 접속하지 않은 플레이어는 자동 꺼짐", not AutoClickService.isOn(fake))
end

print(string.format("[AutoClickServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AutoClickServiceTests] %d test(s) failed", failed))
end

--!strict
-- AutoAdvanceService 검증 (지시서 #18 — DESIGN "1. 챌린지 > 자동 진행 모드" AA0 ~ AA13). 가짜 세계로 굴린다 —
-- 실제 런 · 실제 프로필 · 실제 캐릭터를 건드리지 않는다. 진행 벽 트리거는 실물 AdvanceWallService._handleTouch에 가짜 deps.
--   요청 위생 · 미보유 · 목표층 · 런 중 · 캐릭터 · 시작(1층 런 → 이동 순서) · 클리어 → 간격 뒤 advance("auto") 한 번 · 이동은 advance 뒤 ·
--   벽 트리거 이중 진행 없음 · 디바운스 · 목표층 cashout("auto") · 반복 간격 · 실패 · 사람 수동 수령 · 중지(런 유지) · 캐릭터 없음 ·
--   퇴장 · 안전층 고정 · 단일 루프(여러 명) · 구매 직후 · 안전층 함수 경계 · 워프 · 환생 auto_active · PlayerState 요약

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local AutoAdvanceConfig = require(ReplicatedStorage.Shared.Config.AutoAdvanceConfig)
local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
local Systems = ServerScriptService.Server.Systems
local AutoAdvanceService = require(Systems.AutoAdvanceService)
local AdvanceWallService = require(Systems.AdvanceWallService)
local WarpRequestService = require(Systems.WarpRequestService)
local RebirthRequestService = require(Systems.RebirthRequestService)
local PlayerStateService = require(Systems.PlayerStateService)

local S = AutoAdvanceService
local ADV = AutoAdvanceConfig.ADVANCE_DELAY_SEC
local REP = AutoAdvanceConfig.REPEAT_DELAY_SEC
local GAP = AutoAdvanceConfig.REQUEST_MIN_INTERVAL_SEC

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

-- 가짜 세계. 플레이어마다 런(stage · cleared · canAdvance) · 소유 · 캐릭터 · 안전층. calls에 순서대로 기록한다.
local function newWorld()
	local w: any = { runs = {}, owned = {}, char = {}, safe = {}, calls = {}, sent = {}, notified = 0, lastStage = 25 }
	local function log(s: string)
		table.insert(w.calls, s)
	end
	w.rt = S._pure.createRuntime({
		owns = function(p)
			return w.owned[p] == true
		end,
		getRunState = function(p)
			return w.runs[p]
		end,
		startRun = function(p, stage)
			log("start:" .. stage)
			w.runs[p] = { stage = stage, cleared = false, canAdvance = stage < w.lastStage }
			return true
		end,
		advance = function(p, src)
			local r = w.runs[p]
			if r == nil or not r.cleared or not r.canAdvance then
				log("advance_rejected")
				return false
			end
			log("advance:" .. src .. ":" .. r.stage)
			w.runs[p] = { stage = r.stage + 1, cleared = false, canAdvance = r.stage + 1 < w.lastStage }
			return true
		end,
		cashout = function(p, src)
			local r = w.runs[p]
			if r == nil or not r.cleared then
				return false
			end
			log("cashout:" .. src .. ":" .. r.stage)
			w.runs[p] = nil
			return true
		end,
		moveToEntrance = function(p, stage)
			log("move:" .. stage)
			return true
		end,
		hasCharacter = function(p)
			return w.char[p] ~= false
		end,
		safeFloorOf = function(p)
			return w.safe[p] or 5
		end,
		notify = function()
			w.notified += 1
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
		log = function() end,
	})
	return w
end

local function has(calls: { string }, s: string): number
	local n = 0
	for _, c in ipairs(calls) do
		if c == s then
			n += 1
		end
	end
	return n
end

local A: any = { Name = "AutoA", UserId = 1801 }
local B: any = { Name = "AutoB", UserId = 1802 }

-- 1. 요청 위생 · 거부 ----------------------------------------------------------------------------------
do
	local r = S._pure.readRequest
	local a1, t1 = r({ action = "start", target = 3 })
	local a2 = r({ action = "stop", target = 99 })
	check("readRequest: start + 목표층 · stop · 그 밖 nil", a1 == "start" and t1 == 3 and a2 == "stop" and r({ action = "go" }) == nil
		and r("start") == nil)
	local w = newWorld()
	local t = 0
	local function ask(p: any, payload: any)
		t += GAP
		return w.rt.onRequest(p, payload, t)
	end
	check("미보유 → not_owned · 런 없음", ask(A, { action = "start", target = 3 }).reason == S.REASON_NOT_OWNED and w.runs[A] == nil)
	w.owned[A] = true
	local bad = { 0, 26, 1.5, "3", 0 / 0 }
	local allBad = true
	for _, v in ipairs(bad) do
		if ask(A, { action = "start", target = v }).reason ~= S.REASON_INVALID_TARGET then
			allBad = false
		end
	end
	check("잘못된 목표층(0 · 26 · 1.5 · \"3\" · NaN) → invalid_target", allBad and w.runs[A] == nil and AutoAdvanceLogic.maxTarget() == 25)
	w.runs[A] = { stage = 4, cleared = false, canAdvance = true }
	check("이미 런이 있으면 → run_active(런 그대로)", ask(A, { action = "start", target = 3 }).reason == S.REASON_RUN_ACTIVE and w.runs[A].stage == 4)
	w.runs[A] = nil
	w.char[A] = false
	check("캐릭터 없음 → no_character", ask(A, { action = "start", target = 3 }).reason == S.REASON_NO_CHARACTER)
	w.char[A] = nil
	check("꺼져 있을 때 stop → not_active", ask(A, { action = "stop" }).reason == S.REASON_NOT_ACTIVE)
	check("모르는 action → invalid", ask(A, { action = "x" }).reason == S.REASON_INVALID)
	w.rt.onRequest(A, { action = "start", target = 3 }, t + GAP * 0.1)
	check("빈도 상한 → rate_limited", w.sent[#w.sent].reason == S.REASON_RATE_LIMITED)
	check("거부 경로는 런을 세우지 않았다", has(w.calls, "start:1") == 0)
end

-- 2. 시작 → 진행 → 목표층 수령 → 반복 -----------------------------------------------------------------
do
	local w = newWorld()
	w.owned[A] = true
	w.safe[A] = 7
	local out = w.rt.onRequest(A, { action = "start", target = 3 }, 0)
	check("시작: ok · 목표 3 · 안전층 7(그 순간 값) · 1층 런 → 1층 입구(런이 먼저)", out.ok and out.target == 3 and out.safeFloor == 7
		and w.calls[1] == "start:1" and w.calls[2] == "move:1" and w.notified >= 1)
	local s = w.rt.summary(A)
	check("요약: 켜짐 · 목표 · 안전층 · 반복 1 · 상한 25", s.active and s.target == 3 and s.safeFloor == 7 and s.runs == 1 and s.maxTarget == 25)
	check("자동 중 시작 다시 → already_active", w.rt.onRequest(A, { action = "start", target = 4 }, GAP).reason == S.REASON_ALREADY_ACTIVE)
	w.rt.tick(1)
	check("클리어 전: 아무것도 안 한다", #w.calls == 2)
	w.runs[A].cleared = true
	w.rt.tick(2)
	w.rt.tick(2 + ADV * 0.5)
	check("클리어 직후 ~ 진행 간격 전: advance 안 한다", has(w.calls, "advance:auto:1") == 0)
	w.rt.tick(2 + ADV + 0.01)
	check("진행 간격 뒤: advance(\"auto\") 한 번 → 2층 · 이동은 advance 뒤(2층 입구)", has(w.calls, "advance:auto:1") == 1
		and w.calls[#w.calls - 1] == "advance:auto:1" and w.calls[#w.calls] == "move:2" and w.runs[A].stage == 2)
	w.rt.tick(3)
	w.rt.tick(4)
	check("advance는 한 번만(다음 틱에 다시 부르지 않는다)", has(w.calls, "advance:auto:1") == 1 and has(w.calls, "advance_rejected") == 0)

	-- 벽 트리거 이중 진행: 옮긴 자리 = 진행 벽 1 트리거. 런이 이미 2층이라 트리거 1은 걸러진다
	local wallAdvances = 0
	local wallDeps = {
		getRunState = function(p)
			return w.runs[p]
		end,
		advance = function()
			wallAdvances += 1
			return true
		end,
		now = function()
			return 100
		end,
	}
	AdvanceWallService._handleTouch(wallDeps :: any, A, 1)
	check("벽 트리거 1(옮긴 자리)에 닿아도 advance 안 함(런이 2층)", wallAdvances == 0)
	w.runs[A].cleared = true
	local t0 = 200
	wallDeps.now = function()
		return t0
	end
	AdvanceWallService._handleTouch(wallDeps :: any, A, 2)
	wallDeps.now = function()
		return t0 + AdvanceWallService._pure.TOUCH_DEBOUNCE_SEC * 0.5
	end
	AdvanceWallService._handleTouch(wallDeps :: any, A, 2)
	check("런당 1회 디바운스: 창 안 재접촉은 한 번만", wallAdvances == 1)
	-- 사람이 직접 벽으로 진행한 것으로 친다(막지 않는다): 가짜 세계에서 2 → 3층
	w.runs[A] = { stage = 3, cleared = false, canAdvance = true }

	w.runs[A].cleared = true
	w.rt.tick(10)
	check("목표층(3) 클리어 → 바로 cashout(\"auto\") · advance 안 함", has(w.calls, "cashout:auto:3") == 1 and has(w.calls, "advance:auto:3") == 0
		and w.runs[A] == nil)
	w.rt.tick(10.1)
	w.rt.tick(10.1 + REP * 0.5)
	check("반복 간격 전: 다음 런 안 세운다", has(w.calls, "start:1") == 1)
	w.rt.tick(10.1 + REP + 0.01)
	check("반복 간격 뒤: 다시 1층 런 → 1층 입구 · 반복 2", has(w.calls, "start:1") == 2 and w.calls[#w.calls] == "move:1"
		and w.rt.summary(A).runs == 2)
	check("안전층 고정: 힘이 바뀌어도 반복 중 다시 재지 않는다", (function()
		w.safe[A] = 12
		w.rt.tick(20)
		return w.rt.summary(A).safeFloor == 7
	end)())

	-- 실패(시간 초과): 런이 없어진다 → 반복 이어짐
	w.runs[A] = nil
	w.rt.tick(30)
	w.rt.tick(30 + REP + 0.01)
	check("실패(런 소멸) → 반복 이어짐 · 반복 3", has(w.calls, "start:1") == 3 and w.rt.summary(A).runs == 3)

	-- 사람이 직접 발판으로 수령: 런이 없어진다 → 반복 이어짐
	w.runs[A].cleared = true
	w.runs[A] = nil -- 수동 수령(cashout_pad)으로 끝난 것
	w.rt.tick(40)
	w.rt.tick(40 + REP + 0.01)
	check("사람 수동 수령 → 반복 이어짐 · 반복 4", w.rt.summary(A).runs == 4)

	-- 중지: 자동만 꺼지고 런은 남는다
	local runBefore = w.runs[A]
	local stopOut = w.rt.onRequest(A, { action = "stop" }, 1000)
	check("중지 → 응답 stop ok 하나(따로 꺼짐 알림 없음) · 자동 꺼짐 · 런 그대로", stopOut.ok and not w.rt.isActive(A) and w.runs[A] == runBefore
		and w.sent[#w.sent].action == "stop" and w.sent[#w.sent - 1].action ~= "stopped")
	w.runs[A].cleared = true
	w.rt.tick(2000)
	w.rt.tick(2000 + ADV + 1)
	check("중지 뒤: 클리어해도 자동 advance · cashout 없음(손으로 이어간다)", has(w.calls, "advance:auto:1") == 1
		and has(w.calls, "cashout:auto:1") == 0)
	check("꺼지면 요약은 지금 힘으로 잰 안전층(12) · 반복 0", not w.rt.summary(A).active and w.rt.summary(A).safeFloor == 12
		and w.rt.summary(A).runs == 0)
end

-- 3. 캐릭터 없음 · 퇴장 · 단일 루프 · 구매 직후 ---------------------------------------------------------
do
	local w = newWorld()
	w.owned[A], w.owned[B] = true, true
	w.rt.onRequest(A, { action = "start", target = 5 }, 0)
	w.rt.onRequest(B, { action = "start", target = 5 }, 0)
	w.runs[A].cleared, w.runs[B].cleared = true, true
	w.rt.tick(1)
	w.rt.tick(1 + ADV + 0.01)
	check("단일 루프: 한 틱에 두 명 다 진행", w.runs[A].stage == 2 and w.runs[B].stage == 2)
	w.char[A] = false
	w.rt.tick(5)
	check("캐릭터 없음(죽음 · 리스폰) → 꺼짐 · character_lost 알림 · 다른 사람은 그대로", not w.rt.isActive(A) and w.rt.isActive(B)
		and w.sent[#w.sent].reason == S.REASON_CHARACTER_LOST)
	w.rt.onRemoving(B)
	check("퇴장 → 꺼짐", not w.rt.isActive(B))

	local w2 = newWorld()
	check("구매 전 → not_owned", w2.rt.onRequest(A, { action = "start", target = 2 }, 0).reason == S.REASON_NOT_OWNED)
	w2.owned[A] = true -- 구매 완료 이벤트로 세션 소유가 바뀐 것
	check("구매 직후 같은 세션 → 시작 ok", w2.rt.onRequest(A, { action = "start", target = 2 }, GAP).ok)

	-- 마지막 층: 목표층보다 낮아도 더 갈 층이 없으면 수령(최종 층에서 진행 벽이 안 열리는 것과 같은 종착점)
	local w3 = newWorld()
	w3.owned[A] = true
	w3.lastStage = 2
	w3.rt.onRequest(A, { action = "start", target = 25 }, 0)
	w3.runs[A].cleared = true
	w3.rt.tick(1)
	w3.rt.tick(1 + ADV + 0.01)
	w3.runs[A].cleared = true
	w3.rt.tick(5)
	check("마지막 층(더 갈 층 없음) → 목표층 전이어도 cashout(\"auto\")", has(w3.calls, "cashout:auto:2") == 1 and w3.runs[A] == nil)
end

-- 4. 안전층 함수 ----------------------------------------------------------------------------------------
do
	local hp = { BigNum.fromNumber(100), BigNum.fromNumber(200), BigNum.fromNumber(400) }
	local function hpOf(s: number)
		return hp[s]
	end
	-- D = 10 × 2 × 10 = 200
	check("D = 1펀치 × 초당 × 초", BigNum.eq(AutoAdvanceLogic.dealTotal(BigNum.fromNumber(10), 2, 10), BigNum.fromNumber(200)))
	check("경계: 총HP = D인 층은 안전(포함)", AutoAdvanceLogic.safeFloor(BigNum.fromNumber(10), 2, 10, hpOf, 3) == 2)
	check("경계: 총HP가 D를 조금 넘으면 그 층은 아님", AutoAdvanceLogic.safeFloor(BigNum.fromNumber(9.99), 2, 10, hpOf, 3) == 1)
	check("힘이 오르면 안전층이 오른다", AutoAdvanceLogic.safeFloor(BigNum.fromNumber(20), 2, 10, hpOf, 3) == 3)
	check("1층도 못 깨면 0", AutoAdvanceLogic.safeFloor(BigNum.fromNumber(1), 2, 10, hpOf, 3) == 0)
	local gappy = { BigNum.fromNumber(100), BigNum.fromNumber(999), BigNum.fromNumber(150) }
	check("연속 조건: 중간 층에서 막히면 뒤 층은 보지 않는다", AutoAdvanceLogic.safeFloor(BigNum.fromNumber(10), 2, 10, function(s)
		return gappy[s]
	end, 3) == 1)
	check("실물 표: 1층 총HP = D면 1층 안전 · 타이머 20초", AutoAdvanceLogic.safeFloor(BigNum.div(StageConfig.getTotalHp(1),
		BigNum.fromNumber(2 * StageConfig.CHALLENGE_TIMER_SEC)), 2) >= 1)
	check("버튼 종류: 목표 ≤ 안전 safe · 넘으면 risky · 기본 목표 = 안전층(0이면 1)", AutoAdvanceLogic.startKind(5, 5) == "safe"
		and AutoAdvanceLogic.startKind(6, 5) == "risky" and AutoAdvanceLogic.defaultTarget(0) == 1 and AutoAdvanceLogic.defaultTarget(9) == 9)
	check("AutoAdvanceConfig.validate · 진행 간격 1초 이하", AutoAdvanceConfig.validate() and ADV <= 1 and REP == 3)
end

-- 5. 자동 중 워프 · 환생 → auto_active(AA9) -------------------------------------------------------------
do
	local warped, reborn = 0, 0
	local warp = WarpRequestService._pure.createHandler({
		warp = function()
			warped += 1
			return true, BigNum.new(1, 0)
		end,
		send = function() end,
		isAutoActive = function()
			return true
		end,
	})
	local wr = warp.onRequest(A, { stage = 5 }, 0)
	check("워프: 자동 중 → auto_active · 워프 안 함", not wr.ok and wr.reason == S.REASON_AUTO_ACTIVE and warped == 0)
	local rebirth = RebirthRequestService._pure.createHandler({
		rebirth = function()
			reborn += 1
			return true, {}
		end,
		send = function() end,
		isAutoActive = function()
			return true
		end,
	})
	local rr = rebirth.onRequest(A, 0)
	check("환생: 자동 중 → auto_active · 환생 안 함", not rr.ok and rr.reason == S.REASON_AUTO_ACTIVE and reborn == 0)
	local off = RebirthRequestService._pure.createHandler({
		rebirth = function()
			reborn += 1
			return true, {}
		end,
		send = function() end,
		isAutoActive = function()
			return false
		end,
	})
	check("환생: 자동 꺼짐이면 원래대로", off.onRequest(A, 0).ok and reborn == 1)
end

-- 6. PlayerState 요약 -----------------------------------------------------------------------------------
do
	local data = require(ServerScriptService.Server.Data.Schema).new()
	local pure = PlayerStateService._pure
	local base = pure.buildSnapshot(data, 16, 16, 1)
	check("PlayerState: 자동 요약 기본 = 꺼짐 · 0 · 상한", type(base.autoAdvance) == "table" and base.autoAdvance.active == false
		and base.autoAdvance.maxTarget == AutoAdvanceLogic.maxTarget())
	local on = pure.buildSnapshot(data, 16, 16, 1, nil, nil, { active = true, target = 5, safeFloor = 7, runs = 2, maxTarget = 25 })
	local more = pure.buildSnapshot(data, 16, 16, 1, nil, nil, { active = true, target = 5, safeFloor = 7, runs = 3, maxTarget = 25 })
	check("PlayerState: 반복 횟수가 다르면 다르다 · 같으면 같다", not pure.snapshotsEqual(on, more) and pure.snapshotsEqual(on,
		pure.buildSnapshot(data, 16, 16, 1, nil, nil, { active = true, target = 5, safeFloor = 7, runs = 2, maxTarget = 25 })))
end

print(string.format("[AutoAdvanceServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AutoAdvanceServiceTests] %d test(s) failed", failed))
end

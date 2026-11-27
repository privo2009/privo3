--!strict
-- 소프트 셧다운 검증(지시서 #48 1부). Studio는 실제 게시 · 순간이동을 못 하므로 가짜 deps(순간이동 · 저장 · 시계)로 흐름만 본다.
-- 실제 확인은 2월 비공개 서버에서 새 버전 게시(PENDING "#48 남은 것" 사람 확인).
--   순서(화면 → 런 포기 → 저장 끝 → 대기실로) · Studio는 순간이동 안 함 · 다시 시도(1초 · Flooded 15초 · 5번) · 다 실패하면 다시 접속 안내(킥) ·
--   대기실 판정 · 재시작 예정 지연 · 대기실 → 새 서버(표시 없이) · 겹쳐 부르기 · 서버 종료 저장 공유(alreadyEnded)

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SoftShutdown = require(ServerScriptService.Server.Systems.SoftShutdown)
local SoftShutdownConfig = require(ReplicatedStorage.Shared.Config.SoftShutdownConfig)
local ProfileManager = require(ServerScriptService.Server.Data.ProfileManager)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

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

-- 가짜 deps: 일어난 일을 순서대로 적는다. teleportResults = 시도마다 (성공, 오류) — 다 쓰면 성공
local function makeDeps(opts: { players: { any }, studio: boolean?, unsaved: number?, teleportResults: { { any } }? })
	local events: { string } = {}
	local waits: { number } = {}
	local teleports: { { reserve: boolean, n: number, placeId: number } } = {}
	local kicks = 0
	local results = opts.teleportResults or {}
	local deps: SoftShutdown.Deps = {
		players = function()
			return opts.players
		end,
		isStudio = opts.studio == true,
		placeId = 4242,
		notify = function(p: any)
			table.insert(events, "notify:" .. tostring(p))
		end,
		abandonRun = function(p: any)
			table.insert(events, "abandon:" .. tostring(p))
		end,
		saveAll = function(timeoutSec: number): number
			table.insert(events, "save:" .. tostring(timeoutSec))
			return opts.unsaved or 0
		end,
		teleport = function(placeId: number, list: { any }, reserve: boolean): (boolean, string?)
			table.insert(events, "teleport")
			table.insert(teleports, { reserve = reserve, n = #list, placeId = placeId })
			local r = table.remove(results, 1)
			if r == nil then
				return true, nil
			end
			return r[1], r[2]
		end,
		wait = function(sec: number)
			table.insert(waits, sec)
		end,
		log = function(_line: string) end,
		kick = function(_p: any)
			kicks += 1
		end,
	}
	return deps, events, waits, teleports, function()
		return kicks
	end
end

-- 1. 순서: 화면 → 런 포기 → 저장(상한 SAVE_TIMEOUT_SEC) → 대기실로(예약 · 한 번에 모두) -----------------------
do
	SoftShutdown._resetForTest()
	local deps, events, _waits, teleports = makeDeps({ players = { "A", "B" } })
	local r = SoftShutdown.evacuate(deps, "close")
	local want = { "notify:A", "notify:B", "abandon:A", "abandon:B", "save:" .. SoftShutdownConfig.SAVE_TIMEOUT_SEC, "teleport" }
	check("순서: 화면 → 런 포기(가방 · 수령 전 블럭스 버림) → 저장 끝 → 순간이동", table.concat(events, ",") == table.concat(want, ","), table.concat(events, ","))
	check("대기실로: 예약 서버(ShouldReserveServer) · 같은 플레이스 · 2명 한 번에", #teleports == 1 and teleports[1].reserve == true
		and teleports[1].placeId == 4242 and teleports[1].n == 2 and r.status == "teleported" and r.attempts == 1)
end

-- 2. 빈 서버: 아무것도 안 한다(저장은 ProfileManager BindToClose가 따로) ------------------------------------
do
	SoftShutdown._resetForTest()
	local deps, events = makeDeps({ players = {} })
	local r = SoftShutdown.evacuate(deps, "close")
	check("빈 서버: 화면 · 저장 · 순간이동 없음", r.status == "empty" and #events == 0)
end

-- 3. Studio: 저장까지 하고 순간이동은 건너뜀 --------------------------------------------------------------
do
	SoftShutdown._resetForTest()
	local deps, events, _w, teleports, kicks = makeDeps({ players = { "A" }, studio = true })
	local r = SoftShutdown.evacuate(deps, "close")
	check("Studio: 저장은 하고 순간이동 · 킥 없음", r.status == "studio" and #teleports == 0 and kicks() == 0
		and table.find(events, "save:" .. SoftShutdownConfig.SAVE_TIMEOUT_SEC) ~= nil)
end

-- 4. 다시 시도: 두 번 실패 → 세 번째 성공(1초씩) · Flooded면 15초 -----------------------------------------
do
	SoftShutdown._resetForTest()
	local deps, _e, waits = makeDeps({ players = { "A" }, teleportResults = { { false, "HTTP 500" }, { false, "Teleport Flooded" } } })
	local r = SoftShutdown.evacuate(deps, "close")
	check("다시 시도: 실패 2번 뒤 성공 · 시도 3", r.status == "teleported" and r.attempts == 3)
	check("다시 시도 간격: 보통 1초 · Flooded 15초(공식 문서 예시)", #waits == 2 and waits[1] == SoftShutdownConfig.RETRY_DELAY_SEC
		and waits[2] == SoftShutdownConfig.FLOODED_DELAY_SEC)
end

-- 5. 끝까지 실패: 5번 · 남은 사람은 "다시 접속" 안내로 내보낸다(세션이 이미 끝나 저장 없이 놀게 두지 않는다) ---------
do
	SoftShutdown._resetForTest()
	local fails = {}
	for i = 1, 10 do
		fails[i] = { false, "boom" }
	end
	local deps, _e, _w, teleports, kicks = makeDeps({ players = { "A", "B", "C" }, teleportResults = fails })
	local r = SoftShutdown.evacuate(deps, "restart")
	check("끝까지 실패: 시도 TELEPORT_ATTEMPTS번 · 3명 다시 접속 안내", r.status == "teleport_failed"
		and #teleports == SoftShutdownConfig.TELEPORT_ATTEMPTS and kicks() == 3)
end

-- 6. 저장이 상한을 넘겨도 옮긴다(남으면 서버와 함께 끊긴다 — 세션 잠금이 이어받는다) --------------------------
do
	SoftShutdown._resetForTest()
	local deps, _e, _w, teleports = makeDeps({ players = { "A" }, unsaved = 1 })
	local r = SoftShutdown.evacuate(deps, "close")
	check("저장 상한 넘김: 남은 수를 돌려주고 그래도 옮긴다", r.unsaved == 1 and #teleports == 1 and r.status == "teleported")
end

-- 7. 겹쳐 부르기(재시작 예정 + BindToClose): 두 번째는 busy — 저장 · 순간이동을 두 번 걸지 않는다 ---------------
do
	SoftShutdown._resetForTest()
	local inner: any = nil
	local deps = makeDeps({ players = { "A" } })
	local outerSave = deps.saveAll
	deps.saveAll = function(t: number): number
		inner = SoftShutdown.evacuate(deps, "close")
		return outerSave(t)
	end
	local r = SoftShutdown.evacuate(deps, "restart")
	check("겹쳐 부르기: 안쪽은 busy · 바깥은 끝까지", inner ~= nil and inner.status == "busy" and r.status == "teleported")
	SoftShutdown._resetForTest()
end

-- 8. 대기실 → 새 서버: 예약 아님(공개 서버 = 새 버전) · 빈 대기실은 아무것도 안 함 --------------------------------
do
	local deps, _e, _w, teleports = makeDeps({ players = { "A", "B" } })
	local r = SoftShutdown.release(deps)
	local deps2, events2 = makeDeps({ players = {} })
	local r2 = SoftShutdown.release(deps2)
	check("대기실 → 새 서버: 예약 아님 · 저장 · 런 포기 없음 · 빈 대기실 그대로", r.status == "teleported" and #teleports == 1
		and teleports[1].reserve == false and r2.status == "empty" and #events2 == 0)
end

-- 9. 대기실 판정(예약 서버만 — VIP 서버 · 공개 서버 · Studio 아님) ----------------------------------------------
do
	local isHolding = SoftShutdownConfig.isHoldingServer
	check("대기실 판정: 예약 서버(id · 주인 0)만 · VIP(주인 있음) · 공개 · Studio 아님",
		isHolding(false, "abc", 0) and not isHolding(false, "abc", 123) and not isHolding(false, "", 0) and not isHolding(true, "abc", 0))
end

-- 10. 재시작 예정 지연(Roblox가 옮기기 RESTART_LEAD_SEC 전에 시작) ---------------------------------------------
do
	local lead = SoftShutdownConfig.RESTART_LEAD_SEC
	local d = SoftShutdownConfig.delayBeforeEvacuate
	check("재시작 예정: 유닉스 시각 · 남은 초 둘 다 · 지났거나 짧으면 바로 · 값 없음 바로",
		d(2000000000 + 300, 2000000000) == 300 - lead and d(600, 0) == 600 - lead and d(5, 0) == 0
			and d(2000000000 - 50, 2000000000) == 0 and d(nil, 0) == 0 and d(0 / 0, 0) == 0)
end

-- 11. 서버 종료 저장을 둘이 같이 쓴다: 두 번째 부르는 쪽은 EndSession을 다시 걸지 않고 기다리기만(#48 alreadyEnded) -----
do
	local ends = 0
	local list: { [any]: any } = {}
	list[1] = {
		EndSession = function()
			ends += 1
		end,
	}
	local t = 0
	local remaining = ProfileManager._pure.drainOnClose(list, 3, function()
		return t
	end, function()
		t += 1
	end, true)
	check("서버 종료 저장 공유: alreadyEnded면 EndSession 0번 · 상한까지 기다림", ends == 0 and remaining == 1 and t == 3)
end

-- 12. 문장 · 값: 업데이트 화면 · 재시작 예정 · 다시 접속 문장(en · ko) · 값 범위 ------------------------------------
do
	local keys = { "overlay.updating", "overlay.restartSoon", "overlay.announce", "kick.updating" }
	local missing = {}
	for _, k in ipairs(keys) do
		if Locale.template("en", k) == nil or Locale.template("ko", k) == nil then
			table.insert(missing, k)
		end
	end
	check("문장: 업데이트 화면 · 재시작 · 공지 · 다시 접속(en · ko)", #missing == 0, table.concat(missing, ","))
	check("값: 다시 시도 5번 · 저장 상한 + 옮길 몫 ≤ BindToClose 약 30초 · 대기 2 ~ 30초",
		SoftShutdownConfig.TELEPORT_ATTEMPTS == 5 and SoftShutdownConfig.SAVE_TIMEOUT_SEC < SoftShutdownConfig.CLOSE_HOLD_SEC
			and SoftShutdownConfig.CLOSE_HOLD_SEC <= 30 and SoftShutdownConfig.HOLD_SEC >= 2 and SoftShutdownConfig.HOLD_SEC <= 30)
end

print(string.format("[SoftShutdownTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SoftShutdownTests] %d test(s) failed", failed))
end

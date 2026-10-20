--!strict
-- 런 중 사망 = 포기 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
--
-- deps 이음매만 쓴다 — 진짜 ChallengeService도 Humanoid도 없이 검증한다
-- (EntranceGateServiceTests와 같은 방식). 실제로 죽었을 때 abandon되는지는 Studio Play 몫이다.

local ServerScriptService = game:GetService("ServerScriptService")

local RunDeathService = require(ServerScriptService.Server.Systems.RunDeathService)

local pure = RunDeathService._pure

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

local nextPlayerId = 0
local function newWorld(hasRun: boolean)
	nextPlayerId += 1

	local w = {
		hasRun = hasRun,
		abandonCalls = 0,
		player = ({ Name = string.format("RunDeathTestPlayer%d", nextPlayerId) } :: any) :: Player,
	}

	local deps = {
		getRunState = function(_player: Player): any
			if w.hasRun then
				return { stage = 3 }
			end
			return nil
		end,
		-- 실물처럼 abandon이 런을 지운다.
		abandonRun = function(_player: Player): boolean
			w.abandonCalls += 1
			local had = w.hasRun
			w.hasRun = false
			return had
		end,
	}

	return w, deps
end

-- 1. 런 있음 → abandon 1회 ----------------------------------------------------------------
do
	local w, deps = newWorld(true)
	local called = pure.handleDied(deps, w.player, pure.newDeathState())
	check("런 있음: abandon 1회", w.abandonCalls == 1, tostring(w.abandonCalls))
	check("런 있음: handleDied가 true", called == true)
	check("런 있음: abandon 뒤 런이 없다", w.hasRun == false)
end

-- 2. 런 없음 → 0회 ------------------------------------------------------------------------
do
	local w, deps = newWorld(false)
	local called = pure.handleDied(deps, w.player, pure.newDeathState())
	check("런 없음: abandon 0회", w.abandonCalls == 0, tostring(w.abandonCalls))
	check("런 없음: handleDied가 false", called == false)
end

-- 3. 같은 죽음에 두 번 불리지 않는다 --------------------------------------------------------
do
	-- 상태 표시가 막는다. abandon이 런을 지우지 않는 경우(실패)로 흉내내 2번 보장을 빼고 잰다.
	local w, deps = newWorld(true)
	deps.abandonRun = function(_player: Player): boolean
		w.abandonCalls += 1
		return false -- 런이 그대로 남는다
	end
	local death = pure.newDeathState()
	pure.handleDied(deps, w.player, death)
	pure.handleDied(deps, w.player, death)
	check("같은 죽음 두 번: abandon 1회 (런이 남아 있어도)", w.abandonCalls == 1, tostring(w.abandonCalls))
	check("같은 죽음: 처리 표시가 남는다", death.handled == true)
end

do
	-- 리스폰 뒤 새 죽음은 새 상태다 — 새 런이 있으면 다시 abandon된다.
	local w, deps = newWorld(true)
	pure.handleDied(deps, w.player, pure.newDeathState())
	w.hasRun = true -- 다시 입장해 런을 세웠다
	pure.handleDied(deps, w.player, pure.newDeathState())
	check("다른 죽음(리스폰 뒤): 런이 있으면 다시 abandon", w.abandonCalls == 2, tostring(w.abandonCalls))
end

do
	-- 첫 죽음 때 런이 없었으면 표시는 남고, 같은 죽음 신호가 다시 와도 abandon하지 않는다.
	local w, deps = newWorld(false)
	local death = pure.newDeathState()
	pure.handleDied(deps, w.player, death)
	w.hasRun = true
	pure.handleDied(deps, w.player, death)
	check("런 없이 죽은 뒤 같은 신호 재발화: abandon 0회", w.abandonCalls == 0, tostring(w.abandonCalls))
end

print(string.format("[RunDeathServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RunDeathServiceTests] %d test(s) failed", failed))
end

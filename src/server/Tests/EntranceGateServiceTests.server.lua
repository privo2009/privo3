--!strict
-- 챌린지 입장 게이트 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
--
-- 순수 함수와 deps 이음매만 쓴다 — 진짜 ChallengeService도 Instance도 없이 검증한다
-- (AdvanceWallServiceTests와 같은 방식). 실제로 걸어서 런이 서는지는 Bootstrap
-- VERIFY_CHALLENGE가 매 Play 확인한다(게이트를 걸어 지나가 런을 기다린다).
--
-- ⚠️ 설정 숫자를 여기 리터럴로 적지 않는다. 기대값은 ArenaConfig에서 다시 유도한다.
-- ⚠️ 케이스마다 새 플레이어 테이블을 만든다 (CashoutPadServiceTests 상단, U3-10a).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local EntranceGateService = require(ServerScriptService.Server.Systems.EntranceGateService)

local pure = EntranceGateService._pure

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

local DEBOUNCE = ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC

local nextPlayerId = 0
-- hasRun: 처음부터 활성 런이 있는가. startRun이 성공하면 런이 생긴다 — 실물과 같다.
local function newWorld(hasRun: boolean)
	nextPlayerId += 1

	local w = {
		hasRun = hasRun,
		startCalls = 0,
		stages = {} :: { number },
		clock = 100.0,
		player = ({ Name = string.format("EntranceGateTestPlayer%d", nextPlayerId) } :: any) :: Player,
	}

	local deps = {
		getRunState = function(_player: Player): any
			if w.hasRun then
				return { stage = 1 }
			end
			return nil
		end,
		startRun = function(_player: Player, stage: number?): boolean
			w.startCalls += 1
			table.insert(w.stages, stage or -1)
			w.hasRun = true
			return true
		end,
		now = function(): number
			return w.clock
		end,
	}

	return w, deps
end

-- 1. 런 없음 → startRun 한 번, 1층 -------------------------------------------------------
do
	local w, deps = newWorld(false)
	EntranceGateService._handleTouch(deps, w.player)
	check("런 없음: startRun 1회", w.startCalls == 1, tostring(w.startCalls))
	check("런 없음: 1층 런을 세운다", w.stages[1] == 1, tostring(w.stages[1]))
	check("START_STAGE = 1", pure.START_STAGE == 1, tostring(pure.START_STAGE))
end

-- 2. 런 있음 → 아무것도 안 한다 ----------------------------------------------------------
do
	local w, deps = newWorld(true)
	EntranceGateService._handleTouch(deps, w.player)
	check("런 있음: startRun 0회 (진행 중인 런을 덮지 않는다)", w.startCalls == 0, tostring(w.startCalls))

	-- 창 밖에서 다시 지나도 런이 있는 한 그대로다.
	w.clock += DEBOUNCE + 0.01
	EntranceGateService._handleTouch(deps, w.player)
	check("런 있음: 창 밖 재통과도 startRun 0회", w.startCalls == 0, tostring(w.startCalls))
end

-- 3. 게이트 안에 서 있기 — 런을 세운 뒤의 반복 접촉은 런을 다시 세우지 않는다 ----------------
do
	local w, deps = newWorld(false)
	for _ = 1, 10 do
		EntranceGateService._handleTouch(deps, w.player)
		w.clock += 0.05
	end
	check("연속 접촉 10회(창 안·밖 섞임): startRun 1회", w.startCalls == 1, tostring(w.startCalls))
end

-- 4. 디바운스 — 창 안의 재접촉은 런 상태를 보지도 않는다 ----------------------------------
do
	-- 런이 아직 안 선 상태에서 창 안 두 번: 두 번째는 걸러진다.
	local w, deps = newWorld(false)
	deps.startRun = function(_player: Player, _stage: number?): boolean
		w.startCalls += 1
		return false -- 런이 서지 않는 경우(실패)를 흉내낸다
	end
	EntranceGateService._handleTouch(deps, w.player)
	w.clock += DEBOUNCE / 2
	EntranceGateService._handleTouch(deps, w.player)
	check("창 안 두 번: startRun 1회", w.startCalls == 1, tostring(w.startCalls))

	w.clock += DEBOUNCE
	EntranceGateService._handleTouch(deps, w.player)
	check("창 밖이면 다시 시도한다", w.startCalls == 2, tostring(w.startCalls))
end

do
	local s0 = pure.newTouchState()
	local s1, r1 = pure.applyTouch(s0, 100.0)
	check("applyTouch: 첫 접촉 ok", r1 == "ok", tostring(r1))
	local s2, r2 = pure.applyTouch(s1, 100.0 + DEBOUNCE / 2)
	check("applyTouch: 창 안 debounced", r2 == "debounced", tostring(r2))
	check("applyTouch: 무시된 접촉은 상태를 바꾸지 않음", s2 == s1)
	check("디바운스 창 = ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC (공유)", pure.TOUCH_DEBOUNCE_SEC == DEBOUNCE)
end

-- 5. 플레이어별 격리 ----------------------------------------------------------------------
do
	local a, depsA = newWorld(false)
	local b, depsB = newWorld(false)
	check("케이스마다 다른 플레이어를 쓴다", a.player ~= b.player)

	EntranceGateService._handleTouch(depsA, a.player)
	EntranceGateService._handleTouch(depsB, b.player)
	check("A의 입장이 처리된다", a.startCalls == 1, tostring(a.startCalls))
	check("B는 A의 디바운스에 걸리지 않는다", b.startCalls == 1, tostring(b.startCalls))
end

-- 6. 스펙 — 위치·크기는 ArenaConfig 파생 ---------------------------------------------------
do
	local spec = pure.buildGateSpec()
	check("스펙: x == getEntranceX()", spec.x == ArenaConfig.getEntranceX(), tostring(spec.x))
	check("스펙: x == 스테이지 1 시작 면", spec.x == ArenaConfig.getStageEntranceX(1), tostring(spec.x))
	check("스펙: 깊이(X) == ADVANCE_WALL_DEPTH", spec.sizeX == ArenaConfig.ADVANCE_WALL_DEPTH, tostring(spec.sizeX))
	check("스펙: 높이(Y) == BOUNDARY_HEIGHT", spec.sizeY == ArenaConfig.BOUNDARY_HEIGHT, tostring(spec.sizeY))
	check("스펙: 폭(Z) == CHALLENGE_ZONE_Z_HALF × 2", spec.sizeZ == ArenaConfig.CHALLENGE_ZONE_Z_HALF * 2, tostring(spec.sizeZ))
	check("스펙: 아랫면이 지면(Y=0)", spec.y - spec.sizeY / 2 == 0, tostring(spec.y - spec.sizeY / 2))
	check("스펙: 통로 중심(Z=0)", spec.z == 0, tostring(spec.z))

	-- 게이트가 스폰 구역 안쪽 끝에서 챌린지 쪽에 걸쳐 있다 — 스폰 지점과 패드는 게이트 밖이다.
	check("스펙: 스폰 지점이 게이트 앞(스폰 쪽)", ArenaConfig.SPAWN_X < spec.x - spec.sizeX / 2)

	-- 스테이지 1 블록 바깥면보다 앞이다 — 게이트 안에 서도 블록에 끼지 않는다.
	-- OUTER_RADIUS는 블록 **중심**까지라 바깥면은 BLOCK_SPAN/2를 더한다 (BlockLayout 주석).
	local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
	local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
	local outerFace = ArenaConfig.getStageCenterX(1) - (BlockLayout.OUTER_RADIUS + BlockLayoutConfig.BLOCK_SPAN / 2)
	local gateFar = spec.x + spec.sizeX / 2
	check(
		"스펙: 게이트 먼 면이 스테이지 1 블록 바깥면보다 앞",
		gateFar < outerFace,
		string.format("게이트 먼 면=%.1f 블록 바깥면=%.1f", gateFar, outerFace)
	)

	local ok = pcall(ArenaConfig.validate)
	check("ArenaConfig.validate()가 게이트 크기를 받아들인다", ok)
end

print(string.format("[EntranceGateServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EntranceGateServiceTests] %d test(s) failed", failed))
end

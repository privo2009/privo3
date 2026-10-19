--!strict
-- 진행 벽 트리거 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다. 3c 커밋 2.
--
-- 순수 함수와 deps 이음매만 쓴다 — 진짜 ChallengeService도 Instance도 없이 검증한다
-- (CashoutPadServiceTests와 같은 방식). 실제로 걸어서 통과되는지는 Studio Play 육안 확인 몫이다.
--
-- ⚠️ 설정 숫자를 여기 리터럴로 적지 않는다. 기대값은 ArenaConfig·StageConfig에서 다시 유도한다.
-- ⚠️ 케이스마다 새 플레이어 테이블을 만든다. 디바운스 상태가 플레이어 키 싱글턴이라
-- 공유하면 앞 케이스의 시각이 뒤 케이스를 막는다 (CashoutPadServiceTests 상단, U3-10a).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local AdvanceWallService = require(ServerScriptService.Server.Systems.AdvanceWallService)

local pure = AdvanceWallService._pure

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
local function newWorld(runStage: number?)
	nextPlayerId += 1

	local w = {
		runStage = runStage,
		advanceCalls = 0,
		sources = {} :: { string },
		clock = 100.0,
		player = ({ Name = string.format("AdvanceWallTestPlayer%d", nextPlayerId) } :: any) :: Player,
	}

	local deps = {
		getRunState = function(_player: Player): { stage: number }?
			if w.runStage == nil then
				return nil
			end
			return { stage = w.runStage :: number }
		end,
		advance = function(_player: Player, source: string?): boolean
			w.advanceCalls += 1
			table.insert(w.sources, source or "nil")
			return true
		end,
		now = function(): number
			return w.clock
		end,
	}

	return w, deps
end

-- 1. 층 일치 + 런 있음 → advance 한 번, source에 층 번호 ---------------------------------
for _, stage in ipairs({ 1, 3 }) do
	local w, deps = newWorld(stage)
	AdvanceWallService._handleTouch(deps, w.player, stage)
	check(string.format("%d층 일치: advance 1회", stage), w.advanceCalls == 1, tostring(w.advanceCalls))
	local expected = "advance_wall_stage_" .. tostring(stage)
	check(string.format("%d층 일치: source = %s", stage, expected), w.sources[1] == expected, tostring(w.sources[1]))
end

-- 2. 층 불일치 → 호출 0 ---------------------------------------------------------------
do
	-- 다른 층 자리의 트리거
	local w, deps = newWorld(3)
	AdvanceWallService._handleTouch(deps, w.player, 1)
	check("층 불일치(런 3, 벽 1): advance 0회", w.advanceCalls == 0, tostring(w.advanceCalls))

	-- 진행 직후 방금 지난 트리거에 겹쳐 있는 경우 (런 N+1, 벽 N)
	local w2, deps2 = newWorld(2)
	AdvanceWallService._handleTouch(deps2, w2.player, 1)
	check("층 불일치(런 2, 벽 1): advance 0회", w2.advanceCalls == 0, tostring(w2.advanceCalls))
end

-- 3. 런 없음 → 호출 0 -----------------------------------------------------------------
do
	local w, deps = newWorld(nil)
	AdvanceWallService._handleTouch(deps, w.player, 1)
	check("런 없음: advance 0회", w.advanceCalls == 0, tostring(w.advanceCalls))
end

-- 4. 디바운스 --------------------------------------------------------------------------
do
	local w, deps = newWorld(1)
	AdvanceWallService._handleTouch(deps, w.player, 1)
	w.clock += DEBOUNCE / 2
	AdvanceWallService._handleTouch(deps, w.player, 1)
	check("창 안 두 번: advance 1회", w.advanceCalls == 1, tostring(w.advanceCalls))
end

do
	local w, deps = newWorld(1)
	AdvanceWallService._handleTouch(deps, w.player, 1)
	w.clock += DEBOUNCE + DEBOUNCE / 2
	AdvanceWallService._handleTouch(deps, w.player, 1)
	check("창 밖 두 번: advance 2회", w.advanceCalls == 2, tostring(w.advanceCalls))
end

do
	-- 의미가 CashoutPadService와 같은가: 런이 없을 때의 접촉도 창을 연다(시각 갱신).
	local w, deps = newWorld(nil)
	AdvanceWallService._handleTouch(deps, w.player, 1)
	w.runStage = 1
	w.clock += DEBOUNCE / 2
	AdvanceWallService._handleTouch(deps, w.player, 1)
	check("런 없을 때의 접촉도 창을 연다: 창 안 재접촉은 advance 0회", w.advanceCalls == 0, tostring(w.advanceCalls))
end

do
	local state = pure.newTouchState()
	local s1, r1 = pure.applyTouch(state, 100.0)
	check("applyTouch: 첫 접촉 ok", r1 == "ok", tostring(r1))
	local s2, r2 = pure.applyTouch(s1, 100.0 + DEBOUNCE / 2)
	check("applyTouch: 창 안 debounced", r2 == "debounced", tostring(r2))
	check("applyTouch: 무시된 접촉은 상태를 바꾸지 않음", s2 == s1)
	check("디바운스 창 = ArenaConfig.ADVANCE_WALL_DEBOUNCE_SEC", pure.TOUCH_DEBOUNCE_SEC == DEBOUNCE)
end

-- 5. 플레이어별 격리 --------------------------------------------------------------------
do
	local a, depsA = newWorld(1)
	local b, depsB = newWorld(1)
	check("케이스마다 다른 플레이어를 쓴다", a.player ~= b.player)

	AdvanceWallService._handleTouch(depsA, a.player, 1)
	-- 같은 시각에 B가 처음 닿는다. A의 디바운스에 걸리면 안 된다.
	AdvanceWallService._handleTouch(depsB, b.player, 1)
	check("A의 접촉이 처리된다", a.advanceCalls == 1, tostring(a.advanceCalls))
	check("B는 A의 디바운스에 걸리지 않는다", b.advanceCalls == 1, tostring(b.advanceCalls))
	check("A의 호출 수가 B 때문에 늘지 않는다", a.advanceCalls == 1, tostring(a.advanceCalls))
end

-- 6. 스펙 — 트리거가 서는 층과 좌표 ------------------------------------------------------
do
	-- 기대 집합: {N | hasStage(N+1)}. 정의된 층(1부터 연속)을 훑으며 StageConfig에서 구한다.
	local expected: { [number]: boolean } = {}
	local expectedCount = 0
	local lastStage = 0
	local n = 1
	while StageConfig.hasStage(n) do
		lastStage = n
		if StageConfig.hasStage(n + 1) then
			expected[n] = true
			expectedCount += 1
		end
		n += 1
	end

	local specs = pure.buildTriggerSpecs()
	local seen: { [number]: boolean } = {}
	local allExpected = true
	local duplicate = false
	for _, spec in ipairs(specs) do
		if seen[spec.stage] then
			duplicate = true
		end
		seen[spec.stage] = true
		if not expected[spec.stage] then
			allExpected = false
		end
	end
	local allSeen = true
	for stage in pairs(expected) do
		if not seen[stage] then
			allSeen = false
		end
	end

	check("스펙: 개수 == {N | hasStage(N+1)}의 크기", #specs == expectedCount, string.format("스펙=%d 기대=%d", #specs, expectedCount))
	check("스펙: 모든 스펙 층이 기대 집합 안", allExpected)
	check("스펙: 기대 집합의 모든 층에 스펙이 있다", allSeen)
	check("스펙: 같은 층이 두 번 없다", not duplicate)
	check("스펙: 최종층에는 트리거가 없다", lastStage >= 1 and not seen[lastStage], string.format("최종층=%d", lastStage))

	local size = ArenaConfig.getAdvanceWallSize()
	local posOk, sizeOk = true, true
	local firstBad: string? = nil
	for _, spec in ipairs(specs) do
		local cx, cy, cz = ArenaConfig.getAdvanceWallCenter(spec.stage)
		if not (spec.x == cx and spec.y == cy and spec.z == cz) then
			posOk = false
			firstBad = firstBad or string.format("%d층 (%s,%s,%s) 기대 (%s,%s,%s)", spec.stage, tostring(spec.x), tostring(spec.y), tostring(spec.z), tostring(cx), tostring(cy), tostring(cz))
		end
		if not (spec.sizeX == size.X and spec.sizeY == size.Y and spec.sizeZ == size.Z) then
			sizeOk = false
		end
	end
	check("스펙: 각 x,y,z == getAdvanceWallCenter(N)", posOk, firstBad)
	check("스펙: 각 크기 == getAdvanceWallSize()", sizeOk)

	-- 1층만 보면 층 오프셋을 빠뜨려도 멀쩡해 보인다 (docs/PENDING.md 함정 절).
	if #specs >= 2 then
		check("스펙: 이웃 트리거의 x가 다르다", specs[1].x ~= specs[2].x)
	end
end

print(string.format("[AdvanceWallServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AdvanceWallServiceTests] %d test(s) failed", failed))
end

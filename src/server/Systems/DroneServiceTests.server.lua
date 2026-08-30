--!strict
-- DroneService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 5 검증: 나머지 보존 / 오프라인 상한 / 시각 되감김 방어 / droneStage 없음 /
-- count 배수 / in-flight 겹침 방어 / lifetimeBlox 연동.
--
-- RebirthServiceTests와 같은 이유로 DroneService._pure에 **기록용 deps**를 넣어
-- 검증한다. 실제 서비스를 태우면 가짜 Player로는 ProfileManager.get이 nil을 줘서
-- 모든 경로가 "프로필 없음" 한 갈래로 끝나 분기·순서를 볼 수 없다.
--
-- 여기서 다루지 않는 것: 실제 프로필 왕복, ProfileManager.onLoaded 실배선,
-- RunService.Heartbeat 주기 루프의 실제 타이밍. 그쪽은 Play 육안 확인 몫이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local DroneConfig = require(ReplicatedStorage.Shared.Config.DroneConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local DroneService = require(script.Parent.DroneService)

local pure = DroneService._pure

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local fakePlayer = { Name = "TestPlayer", UserId = 1 } :: any

-- 드론 스테이지가 확실히 존재하는(1~25) maxStage. 절대값을 하드코딩하지 않는다 —
-- STAGE_OFFSET이 바뀌어도 이 테스트들이 여전히 "드론 스테이지 있음" 조건을 보게 하려면
-- 그 값을 기준으로 유도해야 한다.
local VALID_MAX_STAGE = DroneConfig.STAGE_OFFSET + 5
local VALID_DRONE_STAGE = VALID_MAX_STAGE - DroneConfig.STAGE_OFFSET
local REWARD_ONE_CYCLE = StageConfig.getBloxReward(VALID_DRONE_STAGE)

-- ===== 기록용 세계 ====================================================================

type World = {
	maxStage: number,
	count: number,
	lastCollectAt: number,
	hasProfile: boolean,
	blox: BigNum.BigNumber,
	lifetimeBlox: BigNum.BigNumber,
	grantCalls: { { amount: BigNum.BigNumber, reason: string } },
	setLastCollectAtCalls: number,
	saveCalls: number,
	failGrant: boolean,
	failSetLastCollectAt: boolean,
	failSave: boolean,
}

local function newWorld(overrides: { maxStage: number?, count: number?, lastCollectAt: number? }?): World
	local o = overrides or {}
	return {
		maxStage = o.maxStage or VALID_MAX_STAGE,
		count = o.count or 1,
		lastCollectAt = o.lastCollectAt or 0,
		hasProfile = true,
		blox = BigNum.new(0, 0),
		lifetimeBlox = BigNum.new(0, 0),
		grantCalls = {},
		setLastCollectAtCalls = 0,
		saveCalls = 0,
		failGrant = false,
		failSetLastCollectAt = false,
		failSave = false,
	}
end

-- ⚠️ 반환 타입을 DroneService.Deps로 못박지 않는다. fakePlayer가 {Name=,UserId=} :: any라
-- 아래 함수들의 첫 인자가 Player가 아니라 any인데, 호출부에서 :: any로 넘긴다
-- (RebirthServiceTests.depsFor와 같은 이유·같은 패턴).
local function depsFor(w: World)
	return {
		getState = function(_p: any)
			if not w.hasProfile then
				return nil
			end
			return { maxStage = w.maxStage, count = w.count, lastCollectAt = w.lastCollectAt }
		end,
		grantBlox = function(_p: any, amount: BigNum.BigNumber, reason: string)
			if w.failGrant then
				return false
			end
			table.insert(w.grantCalls, { amount = amount, reason = reason })
			-- 실제 CurrencyService.applyAdd의 blox 분기를 흉내낸다: blox add는 항상
			-- lifetimeBlox를 같은 양만큼 함께 올린다. "lifetimeBlox가 함께 오르는가"를
			-- 이 파일 안에서 자기완결적으로 재려면 그 성질을 여기서 재현해야 한다 —
			-- 진짜 보장은 CurrencyServiceTests가 잰다.
			w.blox = BigNum.add(w.blox, amount)
			w.lifetimeBlox = BigNum.add(w.lifetimeBlox, amount)
			return true
		end,
		setLastCollectAt = function(_p: any, value: number)
			w.setLastCollectAtCalls += 1
			if w.failSetLastCollectAt then
				return false
			end
			w.lastCollectAt = value
			return true
		end,
		save = function(_p: any)
			w.saveCalls += 1
			if w.failSave then
				return false
			end
			return true
		end,
	}
end

-- ===== 1. 나머지 보존 =================================================================

do
	local w = newWorld({ lastCollectAt = 0 })
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 90, "test")

	check("90초 경과: 1사이클만 지급", result.cycles == 1, tostring(result.cycles))
	check("90초 경과: 지급액 = reward × 1 × count", BigNum.eq(result.granted, REWARD_ONE_CYCLE), BigNum.tostring(result.granted))
	check("90초 경과: lastCollectAt이 60만큼만 전진(90이 아니다)", w.lastCollectAt == 60, tostring(w.lastCollectAt))
end

-- ===== 2. 오프라인 상한 ================================================================

do
	local w = newWorld({ lastCollectAt = 0 })
	local tenHours = 10 * 60 * 60
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, tenHours, "test")

	local expectedCycles = DroneConfig.OFFLINE_CAP_SEC / DroneConfig.INTERVAL_SEC
	check("10시간 경과: 8시간분 사이클만", result.cycles == expectedCycles, tostring(result.cycles))
	check(
		"10시간 경과: 지급액 = reward × (8시간/주기) × count",
		BigNum.eq(result.granted, BigNum.mul(REWARD_ONE_CYCLE, BigNum.fromNumber(expectedCycles))),
		BigNum.tostring(result.granted)
	)
	check("10시간 경과: lastCollectAt = now (초과분은 버림)", w.lastCollectAt == tenHours, tostring(w.lastCollectAt))
end

-- ===== 3. 시각 되감김 방어 =============================================================

do
	local w = newWorld({ lastCollectAt = 1000 })
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 500, "test")

	check("시계 되감김: 지급 없음", BigNum.eq(result.granted, BigNum.new(0, 0)))
	check("시계 되감김: cycles 0", result.cycles == 0, tostring(result.cycles))
	check("시계 되감김: lastCollectAt이 now로 보정됨", w.lastCollectAt == 500, tostring(w.lastCollectAt))
	check("시계 되감김: 저장을 시도했다", w.saveCalls == 1, tostring(w.saveCalls))
end

-- ===== 4. droneStage < 1 ==============================================================

do
	-- maxStage가 오프셋보다 작거나 같으면 droneStage <= 0.
	local w = newWorld({ maxStage = DroneConfig.STAGE_OFFSET, lastCollectAt = 0 })
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 90, "test")

	check("droneStage<1: 지급 없음", BigNum.eq(result.granted, BigNum.new(0, 0)), BigNum.tostring(result.granted))
	check("droneStage<1: cycles는 그래도 소진된다", result.cycles == 1, tostring(result.cycles))
	check("droneStage<1: lastCollectAt은 그래도 전진한다", w.lastCollectAt == 60, tostring(w.lastCollectAt))
	check("droneStage<1: grantBlox는 안 불렸다", #w.grantCalls == 0, tostring(#w.grantCalls))
end

-- ===== 5. count 배수 ===================================================================

do
	local w = newWorld({ lastCollectAt = 0, count = 3 })
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 90, "test")

	check(
		"count 3: 지급액이 3배",
		BigNum.eq(result.granted, BigNum.mul(REWARD_ONE_CYCLE, BigNum.fromNumber(3))),
		BigNum.tostring(result.granted)
	)
end

-- ===== 6. in-flight 겹침 방어 ===========================================================

do
	local w = newWorld({ lastCollectAt = 0 })
	local deps = depsFor(w) :: any
	local inFlight: { [any]: boolean } = {}

	local originalGrant = deps.grantBlox
	local nestedResult: DroneService.CollectResult? = nil
	local nestedCallsSeenByGrant = 0

	-- grantBlox 안에서 같은 플레이어에 대해 다시 collect를 부른다 — 바깥 호출이 아직
	-- inFlight 중일 때 겹쳐 부르는 상황을 동기적으로 재현한다.
	deps.grantBlox = function(p: any, amount: BigNum.BigNumber, reason: string)
		nestedCallsSeenByGrant += 1
		nestedResult = pure.guardedCollect(deps, inFlight, fakePlayer, DroneConfig.INTERVAL_SEC, "reentrant")
		return originalGrant(p, amount, reason)
	end

	local outerResult = pure.guardedCollect(deps, inFlight, fakePlayer, DroneConfig.INTERVAL_SEC, "outer")

	check("겹친 호출이 실제로 안에서 났다", nestedCallsSeenByGrant == 1, tostring(nestedCallsSeenByGrant))
	check(
		"겹친(중첩) 호출은 지급 없이 막힌다",
		nestedResult ~= nil and BigNum.eq((nestedResult :: DroneService.CollectResult).granted, BigNum.new(0, 0)),
		nestedResult and BigNum.tostring((nestedResult :: DroneService.CollectResult).granted) or "nil"
	)
	check("겹친(중첩) 호출은 cycles도 0", nestedResult ~= nil and (nestedResult :: DroneService.CollectResult).cycles == 0)
	check("바깥 호출은 막히지 않고 정상 지급된다", BigNum.eq(outerResult.granted, REWARD_ONE_CYCLE), BigNum.tostring(outerResult.granted))
	check("바깥 호출이 끝난 뒤에는 in-flight가 풀린다", inFlight[fakePlayer] == nil)
end

-- ===== 7. lifetimeBlox가 함께 오르는가 ==================================================

do
	local w = newWorld({ lastCollectAt = 0, count = 2 })
	local before = w.lifetimeBlox
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 90, "test")

	check(
		"lifetimeBlox가 지급액만큼 함께 올랐다",
		BigNum.eq(w.lifetimeBlox, BigNum.add(before, result.granted)),
		BigNum.tostring(w.lifetimeBlox)
	)
	check("blox도 같은 양만큼 올랐다", BigNum.eq(w.blox, result.granted), BigNum.tostring(w.blox))
end

-- ===== 8. 프로필 없음 =================================================================

do
	local w = newWorld({ lastCollectAt = 0 })
	w.hasProfile = false
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 90, "test")

	check("프로필 없음: 지급 없음", BigNum.eq(result.granted, BigNum.new(0, 0)))
	check("프로필 없음: cycles 0", result.cycles == 0)
	check("프로필 없음: 아무 것도 안 불렀다", #w.grantCalls == 0 and w.setLastCollectAtCalls == 0 and w.saveCalls == 0)
end

-- ===== 9. 지급 실패 — 재시도 가능해야 한다 (부분 실패가 아니다) ========================

do
	local w = newWorld({ lastCollectAt = 0 })
	w.failGrant = true
	local result = pure.runCollect(depsFor(w) :: any, fakePlayer, 90, "test")

	check("지급 실패: 지급 없음으로 보고된다", BigNum.eq(result.granted, BigNum.new(0, 0)))
	check(
		"지급 실패: lastCollectAt을 건드리지 않는다 (다음 호출이 이번 구간을 재시도)",
		w.lastCollectAt == 0,
		tostring(w.lastCollectAt)
	)
	check("지급 실패: setLastCollectAt은 아예 안 불렸다", w.setLastCollectAtCalls == 0, tostring(w.setLastCollectAtCalls))
end

-- ===== 10. source 정규화 ===============================================================

check("source nil은 unknown으로 접힌다", pure.normalizeSource(nil) == "unknown")
check("source 빈 문자열도 unknown으로 접힌다", pure.normalizeSource("") == "unknown")
check("정상 source는 그대로", pure.normalizeSource("load") == "load")

do
	local seen: string? = nil
	local w = newWorld({ lastCollectAt = 0 })
	local deps = depsFor(w) :: any
	deps.grantBlox = function(_p: any, amount: BigNum.BigNumber, reason: string)
		seen = reason
		w.blox = BigNum.add(w.blox, amount)
		return true
	end
	pure.runCollect(deps, fakePlayer, 90, "load")
	check("source가 reason에 실린다", seen == "drone_collect_load", tostring(seen))
end

print(string.format("[DroneServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[DroneServiceTests] %d test(s) failed", failed))
end

--!strict
-- AttackService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-e2 검증: 반경 밖에서 applyDamage를 **부르지 않는가** / 데미지에 펀치 속도가
-- 곱해지지 않는가 / 캐릭터가 없을 때 터지지 않는가.
--
-- AttackService._pure.runPunch에 **기록용 deps**를 넣어 검증한다. 실제 서비스를 태우지
-- 않는 이유는 Instance를 피하려는 것이 아니라, 실제 서비스로는 **볼 수 없기 때문**이다:
-- 가짜 Player 테이블이면 ChallengeService.getRunState가 nil을 주므로 모든 경로가
-- "런 없음" 한 갈래로 끝나고, 정작 확인해야 할 "반경 밖일 때 안 불렀는가"가 가려진다.
-- (RebirthServiceTests · WarpServiceTests가 존재하는 이유와 같은 제약이다)
--
-- ⚠️ 반경 값(92.8)을 이 파일에 숫자로 적지 않는다. AttackConfig에서 받아 쓴다 —
-- 적으면 마진을 튜닝했을 때(4-2-f) Config는 따라가는데 테스트만 옛 값에서 깨진다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local AttackService = require(script.Parent.AttackService)

local pure = AttackService._pure

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

local ORIGIN = pure.CLUSTER_ORIGIN
local RADIUS = AttackConfig.getRadius()

-- 원점에서 정확히 distance만큼 떨어진 위치. 축은 아무거나 좋다 — 판정은 거리만 본다.
local function positionAt(distance: number): Vector3
	return ORIGIN + Vector3.new(distance, 0, 0)
end

local STRENGTH = BigNum.new(5, 3) -- 5000

-- ===== 기록용 세계 ====================================================================
--
-- 프로필·캐릭터 대신 쓰는 평범한 테이블. deps가 여기에 쓰고, 테스트는 호출 여부를 본다.
type World = {
	run: { stage: number, cleared: boolean }?,
	strength: BigNum.BigNumber?,
	position: Vector3?,
	damageCalls: { { position: Vector3, damage: BigNum.BigNumber } },
	returnNil: boolean,
}

local function newWorld(): World
	return {
		run = { stage = 3, cleared = false },
		strength = STRENGTH,
		position = positionAt(0),
		damageCalls = {},
		returnNil = false,
	}
end

local function depsFor(w: World)
	return {
		getRunState = function(_p: Player)
			return w.run
		end,
		getStrength = function(_p: Player)
			return w.strength
		end,
		getPosition = function(_p: Player)
			return w.position
		end,
		applyDamage = function(_p: Player, position: Vector3, damage: BigNum.BigNumber)
			table.insert(w.damageCalls, { position = position, damage = damage })
			if w.returnNil then
				return nil
			end
			return {}
		end,
	}
end

-- ===== 반경 안이면 때린다 =============================================================

do
	local w = newWorld()
	w.position = positionAt(0) -- 클러스터 중심
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check("반경 안(중심) — applyDamage가 호출된다", #w.damageCalls == 1, tostring(#w.damageCalls))
	check("반경 안 — 결과가 ok", outcome.result == AttackService.RESULT_OK, outcome.result)
	check("반경 안 — 거리가 기록된다", outcome.distance ~= nil and outcome.distance < 1e-6)
end

do
	-- 경계. 정확히 반경 거리는 사거리 **안**이다 (AttackConfig.isInRange가 소유하는 규약).
	local w = newWorld()
	w.position = positionAt(RADIUS)
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check(
		"정확히 반경 거리 — 때린다 (경계는 이하)",
		#w.damageCalls == 1 and outcome.result == AttackService.RESULT_OK,
		outcome.result
	)
end

-- ===== 반경 밖이면 부르지 않는다 ======================================================

do
	-- ⚠️ 이 파일에서 가장 중요한 케이스다. 데미지 0을 넣는 것과 **호출 자체를 건너뛰는 것**은
	-- 다르다. 0을 넣으면 BlockDamaged가 발화해 클라가 매 0.5초 빈 연출을 돌고,
	-- 서버 로그에도 "때렸다"가 남아 반경 판정이 도는지 보이지 않는다.
	local w = newWorld()
	w.position = positionAt(RADIUS + 1)
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check("반경 밖 — applyDamage가 아예 호출되지 않는다 (0이 아니라 미호출)", #w.damageCalls == 0, tostring(#w.damageCalls))
	check("반경 밖 — 결과가 out_of_range", outcome.result == AttackService.RESULT_OUT_OF_RANGE, outcome.result)
	check("반경 밖 — 거리는 기록된다 (얼마나 멀리 있는지 봐야 한다)", outcome.distance ~= nil)
	check("반경 밖 — 데미지는 계산조차 하지 않는다", outcome.damage == nil)
end

do
	-- 아주 멀리. 패드 24 근처를 상정한다.
	local w = newWorld()
	w.position = positionAt(RADIUS * 4)
	pure.runPunch(depsFor(w) :: any, fakePlayer)
	check("아주 먼 거리 — 여전히 미호출", #w.damageCalls == 0)
end

-- ===== 런 상태 =======================================================================

do
	local w = newWorld()
	w.run = nil
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check("런 비활성 — 아무 일도 일어나지 않는다", #w.damageCalls == 0)
	check("런 비활성 — 결과가 no_run", outcome.result == AttackService.RESULT_NO_RUN, outcome.result)
	-- ⚠️ 런 검사가 가장 앞이어야 한다. ChallengeService.applyDamage는 런이 없으면 warn을
	-- 찍으므로, 여기서 안 거르면 0.5초마다 로그가 도배된다.
	check("런 비활성 — 거리조차 재지 않는다 (가장 앞에서 걸린다)", outcome.distance == nil)
end

do
	local w = newWorld()
	w.run = { stage = 3, cleared = true }
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check("이미 클리어 — 때리지 않는다", #w.damageCalls == 0)
	check("이미 클리어 — 결과가 cleared (no_run과 구분된다)", outcome.result == AttackService.RESULT_CLEARED, outcome.result)
end

-- ===== 데미지 정의 ====================================================================

do
	-- 데미지가 힘에 비례한다.
	local a = newWorld()
	a.strength = BigNum.new(1, 3) -- 1000
	pure.runPunch(depsFor(a) :: any, fakePlayer)

	local b = newWorld()
	b.strength = BigNum.new(2, 3) -- 2000
	pure.runPunch(depsFor(b) :: any, fakePlayer)

	check("데미지가 힘과 같다", BigNum.eq(a.damageCalls[1].damage, BigNum.new(1, 3)), BigNum.tostring(a.damageCalls[1].damage))
	check(
		"힘이 2배면 데미지도 2배 (비례한다)",
		BigNum.eq(b.damageCalls[1].damage, BigNum.mul(a.damageCalls[1].damage, BigNum.fromNumber(2)))
	)
end

do
	-- ⚠️ 이 파일에서 두 번째로 중요한 케이스다. 이중 계산 회귀 방지.
	-- 펀치 속도는 **주기를 정할 뿐** 1회 데미지에 곱해지지 않는다. 곱하면 실제 DPS가
	-- 속도의 제곱에 비례해서 4-2-f 성공률 계산이 통째로 틀어진다.
	local w = newWorld()
	w.strength = STRENGTH
	pure.runPunch(depsFor(w) :: any, fakePlayer)

	local dealt = w.damageCalls[1].damage
	check("데미지에 펀치 속도가 곱해지지 않았다", BigNum.eq(dealt, STRENGTH), BigNum.tostring(dealt))
	check(
		"데미지 ≠ 힘 × 펀치속도 (이중 계산이면 여기서 깨진다)",
		not BigNum.eq(dealt, BigNum.mul(STRENGTH, BigNum.fromNumber(AttackConfig.PUNCH_SPEED_BASE))),
		string.format("dealt=%s speed=%s", BigNum.tostring(dealt), tostring(AttackConfig.PUNCH_SPEED_BASE))
	)

	-- computePunchDamage 자체도 직접 확인한다. 인자가 힘 하나뿐이라는 것이
	-- 속도가 들어올 자리가 없다는 구조적 증거다.
	check("computePunchDamage의 인자는 1개다 (속도가 들어올 자리가 없다)", debug.info(pure.computePunchDamage, "a") == 1)
end

do
	-- 프로필의 BigNum 테이블을 그대로 넘기면 하류가 고칠 때 플레이어의 힘이 바뀐다.
	local w = newWorld()
	local source = BigNum.new(7, 5)
	w.strength = source
	pure.runPunch(depsFor(w) :: any, fakePlayer)

	local dealt = w.damageCalls[1].damage
	check("데미지는 힘과 다른 테이블이다 (원본 오염 방지)", dealt ~= source)

	dealt.m = 999
	check("데미지를 고쳐도 원본 힘이 안 바뀐다", BigNum.eq(source, BigNum.new(7, 5)), BigNum.tostring(source))
end

-- ===== 없는 것들에 대한 가드 ==========================================================

do
	local w = newWorld()
	w.position = nil
	local ok, outcome = pcall(pure.runPunch, depsFor(w) :: any, fakePlayer)

	check("캐릭터 없음 — 에러 없이 스킵된다", ok, tostring(outcome))
	check("캐릭터 없음 — applyDamage 미호출", #w.damageCalls == 0)
	check("캐릭터 없음 — 결과가 no_character", ok and (outcome :: any).result == AttackService.RESULT_NO_CHARACTER)
end

do
	local w = newWorld()
	w.strength = nil
	local ok, outcome = pcall(pure.runPunch, depsFor(w) :: any, fakePlayer)

	check("힘 없음(프로필 미로드) — 에러 없이 스킵된다", ok, tostring(outcome))
	check("힘 없음 — applyDamage 미호출", #w.damageCalls == 0)
	check("힘 없음 — 결과가 no_strength", ok and (outcome :: any).result == AttackService.RESULT_NO_STRENGTH)
	-- 거리는 이미 쟀으므로 남아 있어야 한다. 어디서 걸렸는지 로그로 갈리게 하려는 것이다.
	check("힘 없음 — 거리는 기록된다", ok and (outcome :: any).distance ~= nil)
end

do
	-- 하류가 nil을 돌려주는 경우(그 사이 런이 사라졌거나 이미 클리어).
	local w = newWorld()
	w.returnNil = true
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check("하류가 거부 — 호출은 했으나 결과가 no_changes", #w.damageCalls == 1 and outcome.result == AttackService.RESULT_NO_CHANGES, outcome.result)
end

-- ===== 판정 원점과 주기 ==============================================================

do
	check("클러스터 원점은 (0,0,0)이다", ORIGIN == Vector3.new(0, 0, 0), tostring(ORIGIN))

	-- 원점은 방향과 무관하다. 어느 축으로 나가도 같은 거리면 같은 판정이어야 한다.
	local inside = newWorld()
	inside.position = ORIGIN + Vector3.new(0, 0, RADIUS)
	pure.runPunch(depsFor(inside) :: any, fakePlayer)

	local outside = newWorld()
	outside.position = ORIGIN + Vector3.new(0, 0, RADIUS + 1)
	pure.runPunch(depsFor(outside) :: any, fakePlayer)

	check("판정은 방향이 아니라 거리만 본다", #inside.damageCalls == 1 and #outside.damageCalls == 0)
end

do
	-- 주기가 AttackConfig에서 나온다. 하드코딩이면 여기서 깨진다.
	check(
		"펀치 주기 = 1 / PUNCH_SPEED_BASE",
		math.abs(pure.punchInterval() - 1 / AttackConfig.PUNCH_SPEED_BASE) < 1e-9,
		string.format("%.4f", pure.punchInterval())
	)

	local original = AttackConfig.PUNCH_SPEED_BASE
	AttackConfig.PUNCH_SPEED_BASE = original * 2
	local doubled = pure.punchInterval()
	AttackConfig.PUNCH_SPEED_BASE = original

	check(
		"속도를 2배로 하면 주기가 절반 (Config 파생이다)",
		math.abs(doubled - pure.punchInterval() / 2) < 1e-9,
		string.format("%.4f", doubled)
	)
end

-- ===== 결과 코드 =====================================================================

do
	local codes = {
		AttackService.RESULT_OK,
		AttackService.RESULT_NO_RUN,
		AttackService.RESULT_CLEARED,
		AttackService.RESULT_NO_CHARACTER,
		AttackService.RESULT_NO_STRENGTH,
		AttackService.RESULT_OUT_OF_RANGE,
		AttackService.RESULT_NO_CHANGES,
	}
	local seen: { [string]: boolean } = {}
	local unique = true
	for _, code in ipairs(codes) do
		if seen[code] or type(code) ~= "string" or #code == 0 then
			unique = false
		end
		seen[code] = true
	end
	-- 코드가 겹치면 Bootstrap VERIFY가 원인을 가르지 못한다. 그게 이 코드들의 유일한 용도다.
	check("결과 코드 7개가 전부 다른 비어있지 않은 문자열", unique)
end

print(string.format("[AttackServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AttackServiceTests] %d test(s) failed", failed))
end

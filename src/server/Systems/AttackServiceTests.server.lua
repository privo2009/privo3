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
--
-- ⚠️ 경계 검사가 왜 "정확히 반경"이 아니라 float32 이웃으로 재는지는
-- 아래 "경계를 float32 이웃으로 재는 이유" 참고. 2026-08-28 Play 실측 근거가 거기 있다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
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

-- ⚠️ TestHelpers.checkClose를 쓰지 못한다. 그 파일은 src/client/Tests에 있고 Rojo가
-- StarterPlayerScripts로 보내므로 서버 스크립트가 require할 수 없다
-- (ArenaServiceTests/CashoutPadServiceTests와 같은 제약·같은 처리).
-- 같은 상대오차(1e-6)로 같은 반환 형태(boolean, detail)를 쓴다 — 기준을 바꾼 것이 아니다.
local RELATIVE_TOLERANCE = 1e-6
local function checkClose(actual: number, expected: number): (boolean, string)
	local diff = actual - expected
	local relative = if expected ~= 0 then diff / expected else diff
	return math.abs(relative) < RELATIVE_TOLERANCE,
		string.format("기대값=%.17g 실제값=%.17g 차이=%.3e", expected, actual, diff)
end

-- newWorld()가 세우는 런의 층. 아래 positionAt이 이 층의 클러스터 원점을 기준으로
-- 좌표를 만들므로, 둘이 갈리면 모든 거리 케이스가 통째로 틀어진다 — 상수를 하나 두고
-- 양쪽이 그것을 본다.
--
-- ⚠️ 1이 아닌 층을 쓰는 것이 의도다(4-2-a2b 이전부터 3이었다). 1층은 클러스터 원점이
-- X=0이라 오프셋을 안 더해도 통과한다 — 유도가 끊겨도 안 걸리는 층이다.
local RUN_STAGE = 3

-- 그 층의 클러스터 중심. ⚠️ 200×(N-1)을 여기서 계산하지 말 것 — 실물 판정이 쓰는 것과
-- **같은 함수**를 통과해야 이 테스트가 "판정이 렌더와 같은 원점을 쓰는가"를 실제로 잰다.
local ORIGIN = BlockLayout.getStageOrigin(RUN_STAGE)
local RADIUS = AttackConfig.getRadius()

-- 클러스터 중심에서 정확히 distance만큼 떨어진 위치. 축은 아무거나 좋다 — 판정은 거리만 본다.
-- stage를 주면 그 층의 중심 기준이다(생략하면 RUN_STAGE).
local function positionAt(distance: number, stage: number?): Vector3
	local origin = if stage == nil then ORIGIN else BlockLayout.getStageOrigin(stage)
	return origin + Vector3.new(distance, 0, 0)
end

-- ===== 경계를 float32 이웃으로 재는 이유 ==============================================
--
-- **정확히 반경 거리인 점은 런타임에 존재하지 않는다.** `Vector3` 성분은 float32인데
-- `getRadius()`는 float64를 주기 때문이다. 반경을 Vector3에 넣으면 float32 격자로 올림돼
-- 반경보다 커지고, 그 값으로는 당연히 사거리 밖 판정이 난다.
--
-- 2026-08-28 Play 실측 (이 파일에 임시 프로브를 넣어 찍은 값):
--
--   getRadius() 원본 double   92.799999999999997
--   Vector3에 넣었다 뺀 값     92.800003051757812
--   차이                      3.0517578153421709e-06   ← 소수점 6째 자리에서 갈린다
--   isInRange(잰 거리)        false
--   isInRange(반경 double)    true      ← isInRange에는 결함이 없다
--
-- ⚠️ 그래서 "정확히 반경으로 재라"고 되돌리지 말 것. 그건 도달 불가능한 점을 찍는 것이고,
-- 실패의 원인은 판정 로직이 아니라 **테스트가 요구한 입력이 표현 불가능**했던 것이다.
-- 대신 반경을 감싸는 **float32 두 이웃**으로 잰다. 런타임이 실제로 도달할 수 있는 가장
-- 가까운 두 점이므로 "경계는 이하" 계약은 실질적으로 그대로 검증된다 — 축소가 아니다.
--
-- ⚠️ 4-2-f에서 걸릴 함정 — 이웃값을 상수로 적지 말 것.
-- 범인은 마진 배율이 아니라 `OUTER_RING_MULT = 3.8`이다. `BLOCK_SPAN(16) × 3.8 = 60.8`의
-- `.8`이 이진수로 떨어지지 않아, **마진을 무엇으로 바꿔도 반경에 `.8`이 남는다.**
-- 즉 4-2-f에서 마진만 튜닝해도 이 테스트가 이유 없이 색을 바꿀 수 있었다.
-- 아래처럼 `getRadius()`에서 파생시키면 반경이 어디로 움직이든 이웃도 따라가므로 그 문제가
-- 사라진다. (반경 값을 이 파일에 숫자로 적지 않는 것과 같은 이유다 — 파일 상단 참고)

-- 런타임과 같은 경로로 값을 float32 격자에 재운다. Vector3 성분이 float32라는 사실
-- 자체를 이용하는 것이라, 별도의 비트 조작 없이 "실제로 저장되는 값"을 그대로 얻는다.
local function snapToFloat32(value: number): number
	return Vector3.new(value, 0, 0).X
end

-- 반경 자리의 float32 격자 간격. `math.frexp`는 지수를 **정확히** 준다 —
-- `math.log(x, 2)`는 2의 거듭제곱 근처에서 한 칸 어긋날 수 있어 쓰지 않는다.
local _, RADIUS_EXPONENT = math.frexp(RADIUS)
local FLOAT32_GAP = 2 ^ (RADIUS_EXPONENT - 24) -- float32 유효숫자 24비트

-- 반경을 감싸는 두 격자점. 재운 값이 반경보다 큰지 작은지는 반올림 방향에 달렸으므로
-- (튜닝하면 뒤집힐 수 있다) 양쪽을 다 다룬다.
local RADIUS_SNAPPED = snapToFloat32(RADIUS)
local RADIUS_BELOW, RADIUS_ABOVE
if RADIUS_SNAPPED > RADIUS then
	RADIUS_ABOVE = RADIUS_SNAPPED
	RADIUS_BELOW = RADIUS_SNAPPED - FLOAT32_GAP
else
	RADIUS_BELOW = RADIUS_SNAPPED
	RADIUS_ABOVE = RADIUS_SNAPPED + FLOAT32_GAP
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
		run = { stage = RUN_STAGE, cleared = false },
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
	-- 파생 자체를 먼저 검증한다. 이게 없으면 반경을 튜닝했을 때 이웃 계산이 깨져도
	-- **엉뚱한 점을 재면서 초록으로 통과**한다 — 아래 두 경계 검사가 의미를 잃는다.
	check(
		"경계 파생 — 아래 이웃이 float32 격자 위에 있다",
		snapToFloat32(RADIUS_BELOW) == RADIUS_BELOW,
		string.format("%.17g", RADIUS_BELOW)
	)
	check(
		"경계 파생 — 위 이웃이 float32 격자 위에 있다",
		snapToFloat32(RADIUS_ABOVE) == RADIUS_ABOVE,
		string.format("%.17g", RADIUS_ABOVE)
	)
	check(
		"경계 파생 — 두 이웃이 반경을 감싼다 (아래 <= 반경 < 위)",
		RADIUS_BELOW <= RADIUS and RADIUS > RADIUS_BELOW - FLOAT32_GAP and RADIUS_ABOVE > RADIUS,
		string.format("%.17g <= %.17g < %.17g", RADIUS_BELOW, RADIUS, RADIUS_ABOVE)
	)
end

do
	-- 경계 안쪽. 반경 바로 아래 float32는 사거리 **안**이다
	-- (AttackConfig.isInRange가 소유하는 "경계는 이하" 규약).
	local w = newWorld()
	w.position = positionAt(RADIUS_BELOW)
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check(
		"경계 — 반경 바로 아래 float32는 때린다 (경계는 이하)",
		#w.damageCalls == 1 and outcome.result == AttackService.RESULT_OK,
		outcome.result
	)
end

do
	-- 경계 바깥쪽. 한 칸만 넘어가도 사거리 밖이어야 한다.
	-- 위아래 두 점이 붙어 있어야 "경계가 정확히 여기"라는 것이 검증된다 —
	-- 한쪽만 재면 판정선이 어디로 밀려도 통과한다.
	local w = newWorld()
	w.position = positionAt(RADIUS_ABOVE)
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check(
		"경계 — 반경 바로 위 float32는 때리지 않는다",
		#w.damageCalls == 0 and outcome.result == AttackService.RESULT_OUT_OF_RANGE,
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
	w.run = { stage = RUN_STAGE, cleared = true }
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

end

-- ===== 방향 독립성 ===================================================================
--
-- 판정은 거리만 본다. 어느 축으로 나가도 같은 거리면 같은 결과여야 한다.
--
-- ⚠️ **경계 거리를 쓰지 않는다.** 경계에서 재면 위 float32 문제와 섞여, 방향 때문에
-- 깨진 것인지 경계 때문에 깨진 것인지 구분할 수 없다. 경계는 위 두 검사가 전담한다.
-- (옛 검사는 이 둘을 한 단언에 섞어 놓았고, 실제로 경계 쪽이 깨지면서 이름과 다른
--  이유로 실패했다. 그리고 X 결과와 Z 결과를 비교한 적이 없어 방향 독립성을 직접
--  검증하지도 않았다 — 그래서 나눴다.)

do
	-- 세 축을 같은 거리로 재서 **서로 비교한다.** 축마다 따로 단언하면 셋이 나란히
	-- 틀렸을 때 통과한다 — 비교가 있어야 "방향이 결과를 바꾸지 않는다"가 검증된다.
	local function measureAxes(distance: number)
		local offsets = {
			X = Vector3.new(distance, 0, 0),
			Y = Vector3.new(0, distance, 0),
			Z = Vector3.new(0, 0, distance),
		}

		local out: { [string]: { calls: number, result: string, distance: number } } = {}
		for axis, offset in pairs(offsets) do
			local w = newWorld()
			w.position = ORIGIN + offset
			local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)
			out[axis] = {
				calls = #w.damageCalls,
				result = outcome.result,
				distance = outcome.distance or -1,
			}
		end
		return out
	end

	-- 사거리 한참 안쪽 / 한참 바깥쪽. 둘 다 경계에서 멀리 떨어뜨린다.
	local inside = measureAxes(RADIUS / 2)
	local outside = measureAxes(RADIUS * 2)

	check(
		"방향 독립 — 세 축이 같은 거리를 같은 값으로 잰다",
		inside.X.distance == inside.Y.distance and inside.Y.distance == inside.Z.distance,
		string.format("X=%.17g Y=%.17g Z=%.17g", inside.X.distance, inside.Y.distance, inside.Z.distance)
	)

	check(
		"방향 독립 — 사거리 안이면 세 축 모두 때린다",
		inside.X.calls == 1 and inside.Y.calls == 1 and inside.Z.calls == 1,
		string.format("X=%d Y=%d Z=%d", inside.X.calls, inside.Y.calls, inside.Z.calls)
	)

	check(
		"방향 독립 — 사거리 밖이면 세 축 모두 안 때린다",
		outside.X.calls == 0 and outside.Y.calls == 0 and outside.Z.calls == 0,
		string.format("X=%d Y=%d Z=%d", outside.X.calls, outside.Y.calls, outside.Z.calls)
	)

	check(
		"방향 독립 — 세 축이 같은 결과 코드를 낸다",
		inside.X.result == inside.Z.result and outside.X.result == outside.Z.result,
		string.format("안=%s/%s 밖=%s/%s", inside.X.result, inside.Z.result, outside.X.result, outside.Z.result)
	)
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

-- ===== 판정 원점이 스테이지를 따라간다 (4-2-a2b) =======================================
--
-- 반경은 그대로고 원점만 움직인다. 그래서 "블록중심에서 얼마나 떨어졌는가"는 층과
-- 무관하게 같은 답을 줘야 하고, "월드 좌표 몇에 서 있는가"는 층마다 달라져야 한다.
--
-- ⚠️ 200이나 80을 여기 적지 않는다. ArenaConfig / BlockLayout에서 읽는다.

do
	-- 스테이지 폭의 절반 = 스테이지 끝. 반경(92.8)이 이보다 크다는 것이 92.8의 근거이고
	-- (→ docs/UI_HANDOFF.md "92.8이 왜 디자인에 필요한가"), 그 관계가 층마다 성립해야 한다.
	local stageEdge = ArenaConfig.STAGE_WIDTH / 2

	for _, stage in ipairs({ 1, 2, RUN_STAGE, 7 }) do
		local w = newWorld()
		w.run = { stage = stage, cleared = false }

		-- 블록중심에서 스테이지 끝(±80)만큼 떨어진 두 점. 둘 다 사거리 안이어야 한다.
		for _, sign in ipairs({ 1, -1 }) do
			w.damageCalls = {}
			w.position = positionAt(stageEdge * sign, stage)
			local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

			check(
				string.format("스테이지 %d: 블록중심 %+d이 사거리 안", stage, stageEdge * sign),
				outcome.result == AttackService.RESULT_OK,
				string.format("result=%s dist=%s", outcome.result, tostring(outcome.distance))
			)
			check(
				string.format("스테이지 %d: 그 지점의 거리가 %d이다 (원점이 따라왔다)", stage, stageEdge),
				checkClose(outcome.distance or -1, stageEdge)
			)
		end
	end
end

do
	-- 다른 스테이지의 블록은 사거리 밖이어야 한다. 주기(200)가 반경(92.8)의 두 배를
	-- 넘으므로 이웃 층조차 닿지 않는다 — 이것이 층이 분리돼 있다는 것의 실질이다.
	--
	-- ⚠️ "200 > 92.8 × 2"를 전제로 깔지 않고 먼저 확인한다. 폭을 좁히면 이 검사가
	-- 무의미해지는데, 그때 조용히 통과하면 안 된다.
	check(
		"주기가 반경의 두 배보다 크다 (이웃 층이 겹치지 않는다는 전제)",
		ArenaConfig.getStagePitch() > RADIUS * 2,
		string.format("주기=%.1f 반경×2=%.1f", ArenaConfig.getStagePitch(), RADIUS * 2)
	)

	for _, other in ipairs({ RUN_STAGE - 1, RUN_STAGE + 1, 1 }) do
		local w = newWorld()
		-- 런은 RUN_STAGE인데 캐릭터는 다른 층의 블록 중심에 서 있다.
		w.position = positionAt(0, other)
		local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

		check(
			string.format("런 %d층에서 %d층 블록 위치는 사거리 밖", RUN_STAGE, other),
			outcome.result == AttackService.RESULT_OUT_OF_RANGE,
			string.format("result=%s dist=%s", outcome.result, tostring(outcome.distance))
		)
		check(
			string.format("런 %d층에서 %d층 위치는 applyDamage를 안 부른다", RUN_STAGE, other),
			#w.damageCalls == 0,
			tostring(#w.damageCalls)
		)
	end
end

do
	-- 스테이지 1은 클러스터 원점이 X=0이라 4-2-a2b 이전과 완전히 같아야 한다.
	-- 회귀가 없다는 것을 이 층으로 확인한다.
	check("스테이지 1의 클러스터 원점이 월드 원점이다", BlockLayout.getStageOrigin(1) == Vector3.zero)
	check("stage 없이 부르면 원점이다 (기존 호출부 동작 보존)", BlockLayout.getStageOrigin(nil) == Vector3.zero)

	local w = newWorld()
	w.run = { stage = 1, cleared = false }
	w.position = Vector3.new(0, 0, 0) -- 월드 원점 = 1층 블록 중심
	local outcome = pure.runPunch(depsFor(w) :: any, fakePlayer)

	check("스테이지 1: 월드 원점에서 때려진다", outcome.result == AttackService.RESULT_OK, outcome.result)
	check("스테이지 1: 거리가 0이다", checkClose(outcome.distance or -1, 0))

	w.damageCalls = {}
	w.position = Vector3.new(RADIUS + 1, 0, 0)
	local far = pure.runPunch(depsFor(w) :: any, fakePlayer)
	check("스테이지 1: 반경 밖은 여전히 out_of_range", far.result == AttackService.RESULT_OUT_OF_RANGE, far.result)
end

print(string.format("[AttackServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AttackServiceTests] %d test(s) failed", failed))
end

--!strict
-- AttackConfig 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-e2 Prompt 1 검증: 펀치 속도 관계 / 반경이 파생인가 / 경계.
--
-- ⚠️ 반경 값(92.8)이나 최외곽(68.8)을 이 파일에 숫자로 적지 않는다.
-- 적는 순간 "Config가 맞는가"가 아니라 "내가 적은 숫자와 같은가"를 재게 되고,
-- BlockLayoutConfig를 튜닝하면 Config는 따라가는데 테스트만 옛 값에서 깨진다.
-- 전부 파생값끼리 비교한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local Config = ReplicatedStorage.Shared.Config
local BlockLayoutConfig = require(Config.BlockLayoutConfig)
local AttackConfig = require(Config.AttackConfig)

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

-- 부동소수 비교. 반경은 BLOCK_SPAN × 배율 곱셈에서 나오므로 정확히 일치하지 않을 수 있다.
local function nearly(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

-- ===== 펀치 속도 =====================================================================

do
	check(
		"PUNCH_SPEED_BASE가 PUNCH_SPEED_MAX 이하다",
		AttackConfig.PUNCH_SPEED_BASE <= AttackConfig.PUNCH_SPEED_MAX,
		string.format("base=%s max=%s", tostring(AttackConfig.PUNCH_SPEED_BASE), tostring(AttackConfig.PUNCH_SPEED_MAX))
	)
	check("PUNCH_SPEED_BASE는 0보다 크다", AttackConfig.PUNCH_SPEED_BASE > 0)
	check("PUNCH_SPEED_MAX는 0보다 크다", AttackConfig.PUNCH_SPEED_MAX > 0)

	-- ⚠️ raw number다. BigNum 테이블이 아니다 — 게임 수치가 아니라 상한이 못박힌 값이다.
	-- 누군가 BigNum으로 바꾸면 AttackService의 주기 계산(1 / 속도)이 조용히 깨진다.
	check("펀치 속도는 raw number다 (BigNum이 아니다)", type(AttackConfig.PUNCH_SPEED_BASE) == "number" and type(AttackConfig.PUNCH_SPEED_MAX) == "number")
end

-- ===== 반경이 파생인가 ================================================================

do
	local arena = AttackConfig.getArenaRadius()
	local margin = AttackConfig.getMargin()
	local radius = AttackConfig.getRadius()

	-- 아레나 = 최외곽 링 중심 + 블록 반 칸. 바깥면 기준이라는 것이 계약이다.
	check(
		"아레나 반지름 = OUTER_RADIUS + BLOCK_SPAN/2 (중심이 아니라 바깥면)",
		nearly(arena, BlockLayout.OUTER_RADIUS + BlockLayoutConfig.BLOCK_SPAN / 2),
		string.format("%.4f", arena)
	)

	check(
		"마진 = BLOCK_SPAN × RADIUS_MARGIN_MULT (절대 studs가 아니다)",
		nearly(margin, BlockLayoutConfig.BLOCK_SPAN * AttackConfig.RADIUS_MARGIN_MULT),
		string.format("%.4f", margin)
	)

	-- ⚠️ 가장 중요한 케이스. 마진이 실제로 더해졌는가.
	check(
		"반경이 최외곽 바깥면보다 크다 (마진이 실제로 더해졌다)",
		radius > arena,
		string.format("반경 %.4f vs 아레나 %.4f", radius, arena)
	)
	check("반경 = 아레나 + 마진", nearly(radius, arena + margin), string.format("%.4f", radius))

	-- 반경이 최외곽 **중심**보다도 커야 한다. 기준점을 중심으로 잘못 잡으면
	-- 이 차이가 BLOCK_SPAN/2만큼 줄어드는데, 위 검사만으로는 그것을 못 본다.
	check(
		"반경이 최외곽 링 중심보다 BLOCK_SPAN/2 + 마진만큼 크다",
		nearly(radius - BlockLayout.OUTER_RADIUS, BlockLayoutConfig.BLOCK_SPAN / 2 + margin)
	)
end

do
	-- ⚠️ 이 파일에서 두 번째로 중요한 케이스다. 반경이 하드코딩이면 여기서 깨진다.
	-- BlockLayout.OUTER_RADIUS를 잠시 바꿔 반경이 따라오는지 본다.
	--
	-- 원복을 pcall로 감싸지 않는다 — 사이에 yield가 없어 다른 코드가 끼어들 수 없고,
	-- getRadius가 터지면 그 자체가 실패로 보여야 한다.
	local original = BlockLayout.OUTER_RADIUS
	local before = AttackConfig.getRadius()

	BlockLayout.OUTER_RADIUS = original + 100
	local after = AttackConfig.getRadius()
	BlockLayout.OUTER_RADIUS = original

	check(
		"반경 유도가 하드코딩이 아니다 — 최외곽이 바뀌면 반경도 따라 바뀐다",
		nearly(after - before, 100),
		string.format("최외곽 +100 → 반경 %+.4f (기대 +100)", after - before)
	)
	check(
		"원복 후 반경이 원래 값으로 돌아온다",
		nearly(AttackConfig.getRadius(), before),
		string.format("%.4f vs %.4f", AttackConfig.getRadius(), before)
	)

	-- 마진 배율도 같은 방식으로. 이쪽이 4-2-f에서 실제로 만질 값이다.
	local originalMult = AttackConfig.RADIUS_MARGIN_MULT
	AttackConfig.RADIUS_MARGIN_MULT = originalMult + 1
	local widened = AttackConfig.getRadius()
	AttackConfig.RADIUS_MARGIN_MULT = originalMult

	check(
		"마진 배율을 1 올리면 반경이 BLOCK_SPAN만큼 늘어난다",
		nearly(widened - before, BlockLayoutConfig.BLOCK_SPAN),
		string.format("%+.4f (기대 +%.4f)", widened - before, BlockLayoutConfig.BLOCK_SPAN)
	)
end

-- ===== 경계 =========================================================================

do
	local radius = AttackConfig.getRadius()

	check("중심(거리 0)은 사거리 안", AttackConfig.isInRange(0))
	check("아레나 가장자리는 사거리 안", AttackConfig.isInRange(AttackConfig.getArenaRadius()))
	check("정확히 반경 거리는 사거리 안 (경계는 이하, 미만 아님)", AttackConfig.isInRange(radius))
	check("반경보다 조금 먼 거리는 사거리 밖", not AttackConfig.isInRange(radius + 0.001))
	check("반경의 2배는 사거리 밖", not AttackConfig.isInRange(radius * 2))

	-- 호출자가 잘못된 값을 넘겨도 터지지 않고 "사거리 밖"으로 접힌다.
	-- ⚠️ 거리는 AttackService가 Vector3 연산으로 만드는 값이라 nan이 나올 여지가 있고,
	-- nan은 비교가 전부 false라 조용히 통과할 수 있다. 명시적으로 막는다.
	check("nan 거리는 사거리 밖", not AttackConfig.isInRange(0 / 0))
	check("문자열은 사거리 밖 (터지지 않는다)", not AttackConfig.isInRange("10" :: any))
	check("nil은 사거리 밖 (터지지 않는다)", not AttackConfig.isInRange(nil :: any))
end

-- ===== validate가 잘못된 값을 거부하는가 ==============================================

do
	check("정상 상태에서 validate 통과", (pcall(AttackConfig.validate)))

	-- 각 필드를 하나씩 망가뜨려 validate가 잡는지 본다. 반드시 원복한다.
	local function rejects(label: string, field: string, badValue: any)
		local original = (AttackConfig :: any)[field]
		;(AttackConfig :: any)[field] = badValue
		local ok = pcall(AttackConfig.validate)
		;(AttackConfig :: any)[field] = original
		check(string.format("validate가 %s를 거부한다", label), not ok)
	end

	rejects("PUNCH_SPEED_BASE > MAX", "PUNCH_SPEED_BASE", AttackConfig.PUNCH_SPEED_MAX + 1)
	rejects("PUNCH_SPEED_BASE = 0", "PUNCH_SPEED_BASE", 0)
	rejects("PUNCH_SPEED_BASE 음수", "PUNCH_SPEED_BASE", -1)
	rejects("PUNCH_SPEED_MAX = 0", "PUNCH_SPEED_MAX", 0)
	rejects("마진 배율 0 (마진 없음)", "RADIUS_MARGIN_MULT", 0)
	rejects("마진 배율 음수 (반경이 아레나 안으로 들어온다)", "RADIUS_MARGIN_MULT", -1)
	rejects("마진 배율이 숫자가 아님", "RADIUS_MARGIN_MULT", "1.5")

	-- 망가뜨린 뒤 원복이 실제로 됐는지. 안 되면 이후 모든 테스트가 오염된다.
	check("망가뜨린 값이 전부 원복됐다", (pcall(AttackConfig.validate)))
end

-- ⚠️ "ClickPadConfig를 참조하지 않는다"는 계약은 여기서 테스트하지 않는다.
-- 그건 require 목록의 구조적 성질이라 런타임에 잴 수 있는 것이 아니고,
-- 억지로 만든 검사는 항상 통과해서 아무것도 막지 못한다.
-- 그 계약은 AttackConfig.lua 상단 주석과 코드 리뷰가 지킨다.

print(string.format("[AttackConfigTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AttackConfigTests] %d test(s) failed", failed))
end

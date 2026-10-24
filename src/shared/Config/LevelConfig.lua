--!strict
-- 레벨과 캐릭터 최대 이동속도 계산.
--
-- 레벨 = floor(log₂(힘)) — 힘 2배마다 +1, 효과 = 레벨 1당 최대 이동속도 +1.
-- 확정값과 근거(L1 · L2 — 2026-10-24 사람 결정, 도달 범위)는 DESIGN.md "레벨"이 원본이다.
-- ⚠️ 근거를 여기로 복사하지 말 것. 수치가 두 곳에 있으면 반드시 어긋난다.
--
--   레벨      = floor(log₂(힘)), 힘 < 2이면 0                       (L1)
--   레벨 바   = (힘 − 2^레벨) ÷ 2^레벨 — 그 레벨 안에서의 위치, 0 이상 1 미만
--   최대속도  = min(BASE_WALK_SPEED + 레벨, MAX_WALK_SPEED)          (L2 — 이동 속도 업그레이드는 L3으로 없어졌다)
--
-- ⚠️ 레벨을 쓰는 곳(SpeedService 최대 속도 · HUD PowerBlock 레벨 바 · 시뮬레이터 걷기 시간)은 전부 이 파일의
--    getLevel · getLevelProgress · getMaxSpeed를 부른다. 자기 식으로 다시 계산하는 곳을 두지 않는다.
--
-- ===== 상한은 상수가 아니라 유도값이다 ================================================
--
-- MAX_WALK_SPEED를 숫자로 박으면 안 된다. 지환이 발판 파트를 교체하는 순간 바운딩 박스가
-- 바뀌는데 상한만 옛 값에 남아 조용히 어긋나기 때문이다. 그래서 파트 깊이에서 매번 유도한다:
--
--   MAX_WALK_SPEED = 파트 깊이(studs) × REFERENCE_FPS ÷ MIN_FRAMES_ON_PART
--
-- 근거: Touched는 프레임 단위 겹침 판정이라 캐릭터가 파트 위에 최소 3프레임은 있어야
-- 프레임 드랍 한 번을 흡수한다. 2프레임이면 드랍 한 번에 관통하고, 1프레임(30fps·속도 240)
-- 이면 상시 관통한다. 수령 발판을 밟으려다 통과해버리면 푸시-유어-럭의 선택이 사고로
-- 뒤집히므로, 이 상한은 편의값이 아니라 코어 루프의 안전 장치다.
--
-- ===== 왜 Config가 PadLayout을 require하는가 ==========================================
--
-- 보통은 반대 방향이다(PadLayout이 Config를 읽는다). 여기서 방향이 뒤집힌 이유는 상한의
-- 입력이 "설정값"이 아니라 "실제 파트의 기하"이기 때문이다. 깊이를 Config에 따로 적어두면
-- 그게 곧 하드코딩이고, 위에서 피하려던 어긋남이 그대로 생긴다.
--
-- 현재 require 그래프는 순환이 아니다:
--   Config/LevelConfig → PadLayout       → Config/BlockLayoutConfig → (없음)
--                                        → Config/ArenaConfig      → (없음)
--                      → Config/ArenaConfig → (없음)
-- ⚠️ 만약 나중에 BlockLayoutConfig나 PadLayout이나 ArenaConfig가 LevelConfig를 필요로 하게 되면 그 순간
--    진짜 순환이 된다. 그때는 파트 깊이만 별도 모듈(예: PartGeometry)로 빼서 양쪽이
--    그것을 읽게 한다 — LevelConfig에 깊이 숫자를 되돌려 적는 것은 답이 아니다.

local BigNum = require(script.Parent.Parent.BigNum)
local PadLayout = require(script.Parent.Parent.PadLayout)
local ArenaConfig = require(script.Parent.ArenaConfig)

type BigNumber = BigNum.BigNumber

local LevelConfig = {}

-- 레벨 0의 속도이자 환생 직후의 속도다.
--
-- 2026-10-23 지시서 #8(M2 · M3): 로블록스 기본값 16 → 32. 첫 직접 플레이에서 로비 · 층 사이 걷기가 지루했다.
-- 목표 이동 시간(스폰 → 게이트 4초, 층 → 진행 벽 5초)은 거리 축소와 이 값을 함께 써서 맞췄다(ArenaConfig "템포").
-- ⚠️ 기본값이 오르면 최대 속도 상한(MAX_WALK_SPEED, 발판 깊이 유도 — 지금 80)에 닿는 레벨이 앞당겨진다:
--    16일 때 레벨 64 → 32일 때 레벨 48(getSpeedCapLevel). 그 레벨부터는 레벨이 최대 속도를 더 올리지 못한다.
LevelConfig.BASE_WALK_SPEED = 32

-- 상한 유도에 쓰는 기준 프레임레이트. 저사양 기기 기준이다 —
-- 고사양 기준으로 잡으면 정작 관통이 나는 기기에서 상한이 무의미해진다.
LevelConfig.REFERENCE_FPS = 30

-- 파트 위에 최소 몇 프레임 있어야 Touched를 신뢰할 수 있는가.
-- 3 = 드랍 1회 흡수. 2는 드랍 시 관통, 1은 상시 관통이라 validate()가 2 미만을 거부한다.
LevelConfig.MIN_FRAMES_ON_PART = 3

-- ===== 깊이 소스 =====================================================================
--
-- ⚠️ 상한은 **가장 얕은 파트**가 결정한다. 지금 등록된 소스는 클릭 파워 패드 · 수령 발판 ·
-- 진행 벽 셋이다. 파트가 더 들어오면 여기에 줄을 추가하기만 하면 min()이 알아서 잡는다.
-- 소스가 하나라고 min()을 지우지 말 것 — 파트가 늘어나는 것이 전제다.
--
-- get이 함수인 이유: 모듈 로드 시점에 값을 복사해두면 PAD_SIZE가 교체돼도 안 따라온다.
-- 매번 읽어야 "파트를 바꾸면 상한이 따라온다"가 성립한다.
export type DepthSource = {
	name: string,
	get: () -> number,
}

-- 진행 방향(axis) 성분만 뽑는다. axis는 단위 축 벡터라는 전제이고, 그 전제는
-- PadLayout.AXIS 주석이 보장한다(단위 벡터). 축이 Z에서 X로 바뀌어도 따라온다 —
-- size.Z로 고정해두면 축을 튼 순간 엉뚱한 변을 깊이로 쓴다.
local function depthAlong(size: Vector3, axis: Vector3): number
	return math.abs(axis.X) * size.X + math.abs(axis.Y) * size.Y + math.abs(axis.Z) * size.Z
end

LevelConfig.DEPTH_SOURCES = {
	{
		name = "클릭 파워 패드",
		get = function(): number
			return depthAlong(PadLayout.PAD_SIZE, PadLayout.AXIS)
		end,
	},
	-- 4-2-a 커밋 3b에서 추가. 위 TODO가 예고하던 그것이다.
	-- 지환 전달 명세는 docs/UI_ASSET_SPEC.md "5-1. 수령 발판 · 진행 벽 — 최소 깊이".
	--
	-- ⚠️ 크기가 ArenaConfig에 있는 이유는 그 파일 CASHOUT_PAD_SIZE 주석에 있다 —
	-- 파트를 세우는 Service(서버 전용)에 두면 이 Config가 서버 모듈을 require해야 한다.
	-- ⚠️ 축은 ArenaConfig.AXIS다. PadLayout.AXIS와 같은 값이지만(그쪽이 재공개다)
	-- 발판은 패드가 아니므로 패드의 축을 빌려 쓰지 않는다.
	{
		name = "수령 발판",
		get = function(): number
			return depthAlong(ArenaConfig.CASHOUT_PAD_SIZE, ArenaConfig.AXIS)
		end,
	},
	-- 3c 커밋 1에서 추가. 진행 벽은 통과(Touched)로 advance를 부르므로 수령 발판과
	-- 같은 관통 하한이 걸린다. 깊이의 정본은 ArenaConfig.ADVANCE_WALL_DEPTH다.
	{
		name = "진행 벽",
		get = function(): number
			return depthAlong(ArenaConfig.getAdvanceWallSize(), ArenaConfig.AXIS)
		end,
	},
} :: { DepthSource }

-- 등록된 파트 중 가장 얕은 깊이(studs).
function LevelConfig.getMinPartDepth(): number
	local sources = LevelConfig.DEPTH_SOURCES
	assert(#sources >= 1, "LevelConfig: 깊이 소스가 하나도 없음 - 상한을 유도할 수 없다")

	local shallowest: number? = nil
	for _, source in ipairs(sources) do
		local depth = source.get()
		assert(
			type(depth) == "number" and depth > 0 and depth == depth and depth ~= math.huge,
			string.format("LevelConfig: 깊이 소스 '%s'가 유한한 양수를 주지 않음 (%s)", source.name, tostring(depth))
		)
		if shallowest == nil or depth < shallowest then
			shallowest = depth
		end
	end

	return shallowest :: number
end

-- 깊이 하나로부터 상한을 구하는 순수 함수. 실제 소스와 분리해 둔 이유는 테스트가
-- 임의의 깊이로 공식만 따로 검사할 수 있어야 하기 때문이다.
function LevelConfig.deriveMaxWalkSpeed(depth: number): number
	return depth * LevelConfig.REFERENCE_FPS / LevelConfig.MIN_FRAMES_ON_PART
end

-- 현재 파트 구성에서의 최대 이동속도 상한.
-- 매번 계산한다 — 캐시하면 파트 교체가 반영되지 않는다(이 모듈의 존재 이유가 그것이다).
function LevelConfig.getMaxWalkSpeed(): number
	return LevelConfig.deriveMaxWalkSpeed(LevelConfig.getMinPartDepth())
end

-- ===== 레벨 (L1) =====================================================================
--
-- ⚠️ raw number로 변환하지 않는다 (CLAUDE.md 절대 규칙 1). 힘은 10^2000까지 커지므로 m * 10^e를 계산하는
--    순간 inf가 된다. log₂(힘) = (log10(가수) + 지수) ÷ log10(2) — 가수와 지수를 따로 더하므로 지수가 커도 안전하다.
--
-- ⚠️ 부동소수점 추정만으로 floor를 하지 않는다. 힘이 정확히 2^k이면 (log10(m) + e) ÷ log10(2)가 k − 1e-15로
--    떨어져 floor가 한 칸 아래로 갈 수 있다. 그래서 추정값을 낸 뒤 **BigNum 비교로 확정한다** —
--    레벨 L의 정의는 "2^L ≤ 힘 < 2^(L+1)인 L"이고, 2^L은 BigNum.pow(2, L)(BigNum이 다른 모든 값과 같은
--    12자리 정규화로 만든 값)이다. 경계 테스트(2^k ± 가수 1 ulp)가 이 정의를 잰다(ConfigTests).
--
-- 0과 음수: BigNum은 0을 {m = 0, e = 0}으로 고정하고 부호는 m에 있다. m ≤ 0이면 레벨 0.
-- 0 < 힘 < 2 구간도 0이다(L1 "힘 < 2이면 0") — 레벨이 음수면 속도가 기본값 아래로 내려간다.

local TWO = BigNum.new(2, 0)
local LOG10_2 = math.log10(2)

-- 2^level (BigNum). level은 0 이상의 정수.
function LevelConfig.powerOfLevel(level: number): BigNumber
	return BigNum.pow(TWO, level)
end

local function assertBig(power: any, fn: string)
	assert(
		type(power) == "table" and type(power.m) == "number" and type(power.e) == "number",
		"LevelConfig." .. fn .. ": power는 BigNum {m, e}여야 함"
	)
end

-- 힘 → 레벨. floor(log₂(힘)), 힘 < 2이면 0.
function LevelConfig.getLevel(power: BigNumber): number
	assertBig(power, "getLevel")
	if power.m <= 0 or BigNum.lt(power, TWO) then
		return 0
	end

	local level = math.max(1, math.floor((math.log10(power.m) + power.e) / LOG10_2))
	-- 경계 확정(위 ⚠️). 추정은 많아야 한 칸 어긋나지만 루프로 둔다 — 횟수에 기대지 않는다.
	while level > 1 and BigNum.lt(power, LevelConfig.powerOfLevel(level)) do
		level -= 1
	end
	while BigNum.gte(power, LevelConfig.powerOfLevel(level + 1)) do
		level += 1
	end
	return level
end

-- 레벨 바에 1을 그대로 넣지 않는다 — "0 이상 1 미만" 계약(꽉 찬 바는 다음 레벨이다).
-- BigNum 나눗셈이 12자리로 반올림해 2^(L+1) 바로 아래 힘의 비가 정확히 2가 되는 경우를 여기서 접는다.
LevelConfig.PROGRESS_MAX = 1 - 1e-9

-- 힘 → 레벨 바 진행률 = (힘 − 2^L) ÷ 2^L. 그 레벨 안에서의 위치, 0 이상 1 미만.
-- 레벨 0은 2^0 = 1 기준이다 — 힘 1 → 0, 힘 1.5 → 0.5, 힘 1 미만 → 0.
function LevelConfig.getLevelProgress(power: BigNumber): number
	assertBig(power, "getLevelProgress")
	if power.m <= 0 then
		return 0
	end
	local base = LevelConfig.powerOfLevel(LevelConfig.getLevel(power))
	local progress = BigNum.toRatio(power, base) - 1
	if progress ~= progress or progress < 0 then
		return 0
	end
	return math.min(progress, LevelConfig.PROGRESS_MAX)
end

-- 최대 속도가 MAX_WALK_SPEED에 처음 닿는 레벨(L2 — 지금 80 − 32 = 48). 시뮬레이터 요약(BALANCE_SUMMARY)이 쓴다.
function LevelConfig.getSpeedCapLevel(): number
	return math.max(0, math.ceil(LevelConfig.getMaxWalkSpeed() - LevelConfig.BASE_WALK_SPEED))
end

-- 힘 → 최대 이동속도 = min(BASE_WALK_SPEED + 레벨, MAX_WALK_SPEED) (L2).
--
-- ⚠️ 이 값은 "지금 세팅해야 할 속도"가 아니라 "넘으면 안 되는 천장"이다. 유저가 고른
-- 커스텀 스피드는 서버가 min(요청값, 이 값)으로 잘라서 쓴다 (DESIGN.md "커스텀 스피드").
-- 그리고 min()은 다시 호출될 때만 클램프다 — 환생으로 천장이 내려가면 반드시 속도
-- 재적용 경로를 다시 태워야 한다. 접속 시·환생 시 두 지점이 그 자리다.
--
-- 이동 속도 업그레이드 항은 없다(L3 — 2026-10-24 사람 결정으로 상점에서 지웠다). 이동 속도는 레벨로만 오른다.
function LevelConfig.getMaxSpeed(power: BigNumber): number
	return math.min(LevelConfig.BASE_WALK_SPEED + LevelConfig.getLevel(power), LevelConfig.getMaxWalkSpeed())
end

function LevelConfig.validate(): boolean
	assert(
		LevelConfig.MIN_FRAMES_ON_PART >= 2,
		string.format(
			"LevelConfig: MIN_FRAMES_ON_PART(%s)는 2 이상이어야 함 - 1프레임은 상시 관통 영역",
			tostring(LevelConfig.MIN_FRAMES_ON_PART)
		)
	)

	local maxWalkSpeed = LevelConfig.getMaxWalkSpeed()
	assert(
		maxWalkSpeed == maxWalkSpeed and maxWalkSpeed ~= math.huge and maxWalkSpeed > 0,
		string.format("LevelConfig: MAX_WALK_SPEED(%s)가 유한한 양수가 아님", tostring(maxWalkSpeed))
	)

	-- 상한이 기본보다 낮으면 레벨 효과가 통째로 죽는다(항상 상한에 걸린다).
	-- 발판을 너무 얕게 만들었을 때 여기서 걸려야 한다.
	assert(
		maxWalkSpeed > LevelConfig.BASE_WALK_SPEED,
		string.format(
			"LevelConfig: MAX_WALK_SPEED(%.2f)가 BASE_WALK_SPEED(%d) 이하 - 파트 깊이가 너무 얕다",
			maxWalkSpeed,
			LevelConfig.BASE_WALK_SPEED
		)
	)

	assert(
		LevelConfig.getMaxSpeed(BigNum.new(0, 0)) == LevelConfig.BASE_WALK_SPEED,
		"LevelConfig: 힘 0의 속도가 BASE_WALK_SPEED가 아님"
	)

	-- 힘에 대해 단조 비감소. 상한 부근에서 꺾이거나 되돌아가면 여기서 걸린다.
	-- 상한(현재 80 — 레벨 48 · 힘 약 2.8e14)을 확실히 넘기도록 지수 범위를 넉넉히 잡는다.
	local prev = LevelConfig.getMaxSpeed(BigNum.new(0, 0))
	for exponent = 0, 200 do
		local speed = LevelConfig.getMaxSpeed(BigNum.new(1, exponent))
		assert(
			speed >= prev,
			string.format("LevelConfig: 지수 %d에서 속도가 감소함 (%.2f → %.2f)", exponent, prev, speed)
		)
		prev = speed
	end
	assert(prev == maxWalkSpeed, "LevelConfig: 힘 1e200에서도 최대 속도가 상한에 닿지 않음")

	return true
end

return LevelConfig

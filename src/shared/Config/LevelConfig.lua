--!strict
-- 레벨과 캐릭터 최대 이동속도 계산.
--
-- 레벨 = 힘의 지수, 효과 = 레벨 1당 최대 이동속도 +1.
-- 확정값과 근거(N=1을 고른 이유, 월드별 도달 범위)는 DESIGN.md "레벨"이 원본이다.
-- ⚠️ 근거를 여기로 복사하지 말 것. 수치가 두 곳에 있으면 반드시 어긋난다.
--
--   레벨      = 힘의 지수 (N=1)
--   최대속도  = min(BASE_WALK_SPEED + 레벨, MAX_WALK_SPEED)
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
--   Config/LevelConfig → PadLayout → Config/BlockLayoutConfig → (없음)
-- ⚠️ 만약 나중에 BlockLayoutConfig나 PadLayout이 LevelConfig를 필요로 하게 되면 그 순간
--    진짜 순환이 된다. 그때는 파트 깊이만 별도 모듈(예: PartGeometry)로 빼서 양쪽이
--    그것을 읽게 한다 — LevelConfig에 깊이 숫자를 되돌려 적는 것은 답이 아니다.

local BigNum = require(script.Parent.Parent.BigNum)
local PadLayout = require(script.Parent.Parent.PadLayout)

type BigNumber = BigNum.BigNumber

local LevelConfig = {}

-- 로블록스 기본 WalkSpeed. 레벨 0의 속도이자 환생 직후의 속도다.
LevelConfig.BASE_WALK_SPEED = 16

-- 상한 유도에 쓰는 기준 프레임레이트. 저사양 기기 기준이다 —
-- 고사양 기준으로 잡으면 정작 관통이 나는 기기에서 상한이 무의미해진다.
LevelConfig.REFERENCE_FPS = 30

-- 파트 위에 최소 몇 프레임 있어야 Touched를 신뢰할 수 있는가.
-- 3 = 드랍 1회 흡수. 2는 드랍 시 관통, 1은 상시 관통이라 validate()가 2 미만을 거부한다.
LevelConfig.MIN_FRAMES_ON_PART = 3

-- ===== 깊이 소스 =====================================================================
--
-- ⚠️ 상한은 **가장 얕은 파트**가 결정한다. 지금 등록된 소스는 클릭 파워 패드 하나뿐이지만,
-- 수령 발판·진행 벽 파트가 들어오면 여기에 줄을 추가하기만 하면 min()이 알아서 잡는다.
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
	-- TODO(4-2-c 이후): 수령 발판 / 진행 벽 파트가 생기면 여기에 추가한다.
	-- 지환 전달 명세는 HANDOFF "신규 — 수령 발판 · 진행 벽 최소 깊이".
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

-- 힘 → 레벨. 힘의 지수를 그대로 쓴다(N=1).
--
-- ⚠️ raw number로 변환하지 않는다 (CLAUDE.md 절대 규칙 1). 힘은 10^2000까지 커지므로
-- m * 10^e를 계산하는 순간 inf가 된다. 지수는 e 필드에 이미 있으니 그것만 읽으면 된다.
--
-- 0과 음수: BigNum은 0을 {m = 0, e = 0}으로 고정하므로 e만 봐서는 0과 1을 구분할 수 없다
-- (1도 {m = 1, e = 0}이다). 그래서 m을 먼저 본다. 부호도 m에 있다(정규화가 |m|을 쓴다).
-- 0 < 힘 < 1 구간은 e가 음수로 들어오므로 math.max로 접는다 — 레벨이 음수면 속도가
-- 기본값 아래로 내려간다.
function LevelConfig.getLevel(power: BigNumber): number
	assert(
		type(power) == "table" and type(power.m) == "number" and type(power.e) == "number",
		"LevelConfig.getLevel: power는 BigNum {m, e}여야 함"
	)

	if power.m <= 0 then
		return 0
	end

	return math.max(0, power.e)
end

-- 힘 → 최대 이동속도.
--
-- ⚠️ 이 값은 "지금 세팅해야 할 속도"가 아니라 "넘으면 안 되는 천장"이다. 유저가 고른
-- 커스텀 스피드는 서버가 min(요청값, 이 값)으로 잘라서 쓴다 (DESIGN.md "커스텀 스피드").
-- 그리고 min()은 다시 호출될 때만 클램프다 — 환생으로 천장이 내려가면 반드시 속도
-- 재적용 경로를 다시 태워야 한다. 접속 시·환생 시 두 지점이 그 자리다.
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

	-- 레벨에 대해 단조 비감소. 상한 부근에서 꺾이거나 되돌아가면 여기서 걸린다.
	-- 상한(현재 80)을 확실히 넘기도록 지수 범위를 넉넉히 잡는다.
	local prev = LevelConfig.getMaxSpeed(BigNum.new(0, 0))
	for exponent = 0, 200 do
		local speed = LevelConfig.getMaxSpeed(BigNum.new(1, exponent))
		assert(
			speed >= prev,
			string.format("LevelConfig: 지수 %d에서 속도가 감소함 (%.2f → %.2f)", exponent, prev, speed)
		)
		prev = speed
	end

	return true
end

return LevelConfig

--!strict
-- 근접 자동 공격의 수치. 펀치 속도와 판정 반경.
--
-- 블록은 **근접하면 자동으로 공격된다. 클릭 입력이 아니다** —
-- 규칙과 근거는 DESIGN.md "2. 블록 > 공격 방식"이 원본이다. ⚠️ 근거를 여기로 복사하지 말 것.
--
-- ===== 클릭과 다른 트랙이다 (⚠️ ClickPadConfig와 섞지 말 것) ===========================
--
--   수동 클릭 상한 10/sec   힘 트랙        오토마우스 방어선 (밸런스 값이 아니다)
--   펀치 속도      2/sec    블록 공격 트랙  밸런스 값
--
-- 이 둘은 성격이 정반대다. 클릭 상한은 올리면 자동 클리커 게임패스의 가치가 깎이는
-- **수익 모델 상수**이고(ClickService 상단 참고), 펀치 속도는 20초 안에 총HP를 깎을 수
-- 있는지를 정하는 **난이도 상수**다. DESIGN.md에서 둘이 나란히 적혀 있는 것은 문서상의
-- 배치일 뿐이며, 그 배치를 코드가 따라가면 트랙 구분이 코드에서도 흐려진다.
-- ⚠️ 그래서 이 파일은 ClickPadConfig를 require하지 않고, 그쪽에 무엇도 추가하지 않는다.
--
-- ===== 튜닝 수치 =====================================================================
--
-- ⚠️ TEMP — RADIUS_MARGIN_MULT는 4-2-f 실측 튜닝 대상이다. 근거 없는 임시값이며
-- 파워 1 · bloxBase = 1 · WarpConfig의 TEMP_COST_* 와 **같은 성격**이다.
-- 확정값으로 취급하지 말 것.
--
-- 2026-08-28 실측 (좌표 원점 = 블록 클러스터 중심). 다음 세션이 근거를 다시 파지 않도록 남긴다:
--
--   최외곽 링 중심 (BlockLayout.OUTER_RADIUS)   60.8
--   최외곽 블록 바깥면                          68.8   ← 반경 기준점
--   판정 반경 (마진 배율 1.5 = 24 studs)        92.8
--
--   패드 1  중심  88.8  (근접 모서리 84.8)   ← 반경 안. 유일하다
--   패드 2  중심 100.8  (근접 모서리 96.8)   ← 여기부터 반경 밖
--   패드 24 중심 364.8  (근접 모서리 360.8)
--
-- **패드 24개 중 23개가 반경 밖이다.** 이것이 마진 1.5를 고른 근거다 —
-- 거리 폴링을 택한 이유는 20초 동안 "블록 곁을 지킬 것인가 패드를 밟으러 갈 것인가"라는
-- 판단을 만들기 위해서인데, 반경이 아레나를 통째로 덮으면 나갈 일이 없어서
-- **이름만 거리 폴링인 상시 발동**이 된다. 패드 2 이상을 밟으려면 반드시 딜이 끊긴다.
--
-- 패드 1만 반경 안인 것은 의도다. 패드 1은 basePower이고 해금 조건이 0이라
-- "아무것도 고르지 않은 상태"이므로, 거기 서 있는 동안 딜이 유지되는 쪽이 자연스럽다.
--
-- ⚠️ 마진을 낮추기 전에 위 실측을 다시 볼 것. 1.0으로 내리면 반경 84.8이 되어
-- 패드 1(근접 모서리 84.8)이 경계에 정확히 걸린다 — 부동소수 비교가 결과를 정하는
-- 자리가 되므로 피한다.
--
-- ⚠️ 패드 좌표는 PadLayout의 초안값에서 나온 것이고 그 파일 상단이 "맵과 지환 파트가
-- 들어오면 전부 조정 대상"이라고 못박고 있다. **아레나 배치가 바뀌면 이 마진의 근거도
-- 함께 무너진다.** 그때는 배율만 만지지 말고 위 실측부터 다시 낼 것.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)

local AttackConfig = {}

-- ===== 펀치 속도 =====================================================================
--
-- 근거 → DESIGN.md "클릭 파워 패드"의 `펀치 속도 기본 2회/초, 상한 5회/초`.
-- 상한이 있는 이유는 UpgradeConfig의 punchSpeed가 maxLevel을 갖기 때문이다 —
-- 업그레이드로 무한히 올라가면 20초 타이머의 의미가 사라진다.
--
-- ⚠️ raw number다. BigNum이 아니다. 게임 수치가 아니기 때문이다 —
-- 상한이 5로 못박혀 있어 커질 수 없고, 초당 횟수는 실수다.
-- (ClickService가 클릭 "횟수"를 raw number로 다루는 것과 같은 판단)
-- BigNum이 되는 지점은 `힘 × 펀치 데미지`이고 그건 AttackService의 몫이다.
AttackConfig.PUNCH_SPEED_BASE = 2
AttackConfig.PUNCH_SPEED_MAX = 5

-- ===== 판정 반경 =====================================================================
--
-- 블록 클러스터 중심에서 이 거리 안에 있을 때만 펀치가 들어간다.
-- **층별로 변하지 않는다. 항상 고정이다** — 최대 배치를 기준으로 잡았기 때문이고,
-- 최대 배치의 최외곽은 count와 무관하다(BlockLayout.OUTER_RADIUS 주석 참고).
--
-- ⚠️ 발판·벽 최소 깊이 8 studs를 참조하지 말 것. 숫자가 비슷하더라도 **근거가 다르다.**
-- 그쪽은 고속 이동 시 Touched 관통을 막으려고 나온 값이고(→ docs/PENDING.md
-- "신규 — 수령 발판 · 진행 벽 최소 깊이") 근접 판정과 아무 관계가 없다.
-- **발판 깊이를 바꿀 때 이 반경이 따라 움직이면 안 된다.**
-- 두 값은 별개 Config에 있고 서로 참조하지 않는다.

-- 아레나 가장자리에서 더 걸어나갈 수 있는 거리 = BLOCK_SPAN × 이 배율.
--
-- ⚠️ 절대 studs로 적지 말 것. BlockLayoutConfig의 관례다 — 배치 반지름이 전부
-- "BLOCK_SPAN × 배율"이라, 마진만 절대값이면 블록 크기를 튜닝했을 때 마진의
-- 의미(블록 몇 개분의 여유인가)가 조용히 달라진다.
AttackConfig.RADIUS_MARGIN_MULT = 1.5

-- 판정 반경 = 최외곽 블록의 **바깥면** + 마진.
--
-- ⚠️ 중심이 아니라 바깥면 기준이다. 마진 값이 "블록 표면에서 걸어나갈 수 있는 거리"로
-- 곧이곧대로 읽혀야 하기 때문이다. 중심 기준이면 Config에 적힌 24와 실제 여유 16이
-- BLOCK_SPAN/2 만큼 어긋나고, 이 값은 4-2-f에서 손으로 만질 값이라 의미가 어긋나면
-- 만질 때마다 암산이 낀다.
--
-- ⚠️ 반경도 최외곽도 상수로 적지 말 것. 전부 파생이다 — 배치가 바뀌면 반경이 따라
-- 움직여야 한다 (워프 상한을 WorldConfig에서 파생시킨 것과 같은 원리).
function AttackConfig.getRadius(): number
	return BlockLayout.OUTER_RADIUS + BlockLayoutConfig.BLOCK_SPAN / 2 + AttackConfig.getMargin()
end

-- 마진의 실제 studs 값. 반경에서 아레나를 뺀 나머지다.
function AttackConfig.getMargin(): number
	return BlockLayoutConfig.BLOCK_SPAN * AttackConfig.RADIUS_MARGIN_MULT
end

-- 최외곽 블록의 바깥면까지의 거리. 반경의 기준점이고, 테스트가 "마진이 실제로
-- 더해졌는가"를 재는 기준이기도 하다.
function AttackConfig.getArenaRadius(): number
	return BlockLayout.OUTER_RADIUS + BlockLayoutConfig.BLOCK_SPAN / 2
end

-- 이 거리에서 펀치가 들어가는가. 경계는 **이하**다 —
-- 정확히 반경에 서 있으면 들어간다 (WarpConfig.canWarp의 경계 규약과 같다).
--
-- ⚠️ 거리 계산은 호출자가 한다. 이 파일은 Vector3도 Player도 모른다 —
-- 순수 Config이므로 "얼마인가"만 답하고 "누가 어디 있는가"는 AttackService가 안다.
function AttackConfig.isInRange(distance: number): boolean
	return type(distance) == "number" and distance == distance and distance <= AttackConfig.getRadius()
end

function AttackConfig.validate(): boolean
	assert(
		type(AttackConfig.PUNCH_SPEED_BASE) == "number" and AttackConfig.PUNCH_SPEED_BASE > 0,
		string.format("AttackConfig: PUNCH_SPEED_BASE(%s)는 0보다 커야 함", tostring(AttackConfig.PUNCH_SPEED_BASE))
	)
	assert(
		type(AttackConfig.PUNCH_SPEED_MAX) == "number" and AttackConfig.PUNCH_SPEED_MAX > 0,
		string.format("AttackConfig: PUNCH_SPEED_MAX(%s)는 0보다 커야 함", tostring(AttackConfig.PUNCH_SPEED_MAX))
	)

	-- 기본이 상한을 넘으면 업그레이드가 시작부터 무의미하고, 어느 쪽이 진짜 상한인지
	-- 호출자가 물어야 한다. 같은 값은 허용한다 — 상한에 도달한 상태가 될 수 있다.
	assert(
		AttackConfig.PUNCH_SPEED_BASE <= AttackConfig.PUNCH_SPEED_MAX,
		string.format(
			"AttackConfig: PUNCH_SPEED_BASE(%s)가 PUNCH_SPEED_MAX(%s)보다 큼",
			tostring(AttackConfig.PUNCH_SPEED_BASE),
			tostring(AttackConfig.PUNCH_SPEED_MAX)
		)
	)

	-- 0 이하면 마진이 없거나 음수라 반경이 아레나 안으로 들어온다 — 블록 옆에 서 있어도
	-- 딜이 안 들어가는 상태가 되고, 증상이 "공격이 가끔 안 먹는다"로만 나타난다.
	assert(
		type(AttackConfig.RADIUS_MARGIN_MULT) == "number" and AttackConfig.RADIUS_MARGIN_MULT > 0,
		string.format("AttackConfig: RADIUS_MARGIN_MULT(%s)는 0보다 커야 함", tostring(AttackConfig.RADIUS_MARGIN_MULT))
	)

	-- 파생이 실제로 성립하는지. 상수만 보고 지나가면 getRadius가 최외곽을 빼먹어도
	-- 통과한다. (RebirthConfig.validate / WarpConfig.validate와 같은 이유)
	local arena = AttackConfig.getArenaRadius()
	local radius = AttackConfig.getRadius()

	assert(
		arena > 0,
		string.format("AttackConfig: 아레나 반지름(%.4f)이 0 이하 — BlockLayout 파생이 끊겼다", arena)
	)
	assert(
		radius > arena,
		string.format("AttackConfig: 판정 반경(%.4f)이 아레나 반지름(%.4f)보다 크지 않음 — 마진이 더해지지 않았다", radius, arena)
	)

	-- 경계가 실제로 그 값에 서 있는지. 부등호가 한 칸 어긋나 있어도(<= 대신 <)
	-- 상수 검사만으로는 통과한다.
	assert(AttackConfig.isInRange(radius), "AttackConfig: 정확히 반경 거리에서 사거리 안이어야 함 (경계는 이하)")
	assert(not AttackConfig.isInRange(radius + 1), "AttackConfig: 반경보다 먼 거리는 사거리 밖이어야 함")
	assert(AttackConfig.isInRange(0), "AttackConfig: 중심(거리 0)은 사거리 안이어야 함")

	return true
end

return AttackConfig

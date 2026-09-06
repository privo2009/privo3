--!strict
-- BlockService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 3-1 검증: 배치 좌표 비중첩 / 데미지 오버플로우(거리순 소진) / 클리어 판정.
-- 파괴 순서 셔플(computeDestructionOrder) 검증은 src/server/Tests/BlockShuffleTests로 옮겼다 —
-- 그 알고리즘이 src/shared/BlockShuffle.lua로 이동했기 때문 (서버/클라 공유 모듈).
--
-- BlockService._pure의 순수 함수만 호출한다 — Player/Instance 없이 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local BlockService = require(script.Parent.BlockService)

local pure = BlockService._pure

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

-- positions가 서로 minDistance 이상 떨어져 있는지(=블록끼리 안 겹치는지) 검증한다.
-- 절대 좌표값을 하드코딩해서 비교하지 않고 "관계"(거리)만 확인 — BlockLayoutConfig의
-- 반지름 배율이 바뀌어도 이 테스트는 그대로 유효하다.
local function allSeparatedByAtLeast(positions: { Vector3 }, minDistance: number): boolean
	for i = 1, #positions do
		for j = i + 1, #positions do
			if (positions[i] - positions[j]).Magnitude < minDistance then
				return false
			end
		end
	end
	return true
end

-- 1. computeLayout: 개수별 배치 좌표가 겹치지 않는지 (1, 4, 8, 16개) --------------------------
-- "겹치지 않는다"는 두 좌표가 서로 다르다는 뜻이 아니라, 블록 한 변(BLOCK_SPAN) 이상
-- 떨어져 있어야 한다는 뜻이다 — BlockModelGenerator가 만드는 실제 블록 크기 기준.

for _, count in ipairs({ 1, 4, 8, 16 }) do
	local positions = pure.computeLayout(count)
	check(string.format("computeLayout(%d): 개수만큼 좌표가 나옴", count), #positions == count)
	check(
		string.format("computeLayout(%d): 블록끼리 겹치지 않음 (BLOCK_SPAN=%.1f 이상 간격)", count, BlockLayoutConfig.BLOCK_SPAN),
		allSeparatedByAtLeast(positions, BlockLayoutConfig.BLOCK_SPAN)
	)
end

-- 경계 사이(5, 9)에서도 겹치지 않는지 확인 (원형/이중원 전환 지점)

for _, count in ipairs({ 5, 9 }) do
	local positions = pure.computeLayout(count)
	check(
		string.format("computeLayout(%d): 블록끼리 겹치지 않음 (전환 지점)", count),
		allSeparatedByAtLeast(positions, BlockLayoutConfig.BLOCK_SPAN)
	)
end

-- 2. applyDamageToBlocks: 데미지 오버플로우 (DESIGN.md 2장) -------------------------------
-- 반경 개념 없음 — 힘은 데미지 풀이고, origin에서 가까운 순으로 블록을 정렬해 HP만큼
-- 소진하고 남으면 다음 블록으로 흘러간다. 파괴된 블록의 hp는 뺄셈이 아니라 항상
-- {m=0,e=0}을 직접 대입해서 만들기 때문에, 예전처럼 별도 "0 클램프" 테스트가 필요 없다 —
-- 이 알고리즘 자체가 구조적으로 음수 HP를 만들 수 없다.

do
	-- 데미지가 HP보다 작을 때: 부분 데미지만 적용되고 파괴되지 않음
	local blocks = {
		{ position = Vector3.new(0, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 1 }, -- HP 10
	}
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(6, 0)) -- 데미지 6

	check("부분 데미지: HP가 데미지만큼만 줄어듦 (10-6=4)", BigNum.eq(blocks[1].hp, BigNum.new(4, 0)))
	check("부분 데미지: 파괴되지 않음", blocks[1].destroyed == false)
	check(
		"부분 데미지: changes에 기록됨",
		#changes == 1 and changes[1].destroyed == false and BigNum.eq(changes[1].hp, BigNum.new(4, 0))
	)
end

do
	-- 정확히 하나를 부술 때: 데미지 == HP
	local blocks = {
		{ position = Vector3.new(0, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 1 }, -- HP 10
	}
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(1, 1)) -- 데미지 10

	check("정확히 파괴: HP == 0", BigNum.eq(blocks[1].hp, BigNum.new(0, 0)))
	check("정확히 파괴: destroyed == true", blocks[1].destroyed == true)
	check("정확히 파괴: changes 1건", #changes == 1 and changes[1].destroyed == true)
end

do
	-- 여러 개를 부수고 남는 데미지가 다음으로 흘러가는지
	local blocks = {
		{ position = Vector3.new(0, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 1 }, -- HP 10
		{ position = Vector3.new(10, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 2 }, -- HP 10
		{ position = Vector3.new(20, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 3 }, -- HP 10
	}
	-- 데미지 25: 블록1(10) 파괴, 15 남음 -> 블록2(10) 파괴, 5 남음 -> 블록3에 5 적용(생존)
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(2.5, 1))

	check("오버플로우: 블록1 파괴", blocks[1].destroyed == true and BigNum.eq(blocks[1].hp, BigNum.new(0, 0)))
	check("오버플로우: 블록2 파괴", blocks[2].destroyed == true and BigNum.eq(blocks[2].hp, BigNum.new(0, 0)))
	check("오버플로우: 블록3은 5데미지만 받고 생존 (HP 10-5=5)", blocks[3].destroyed == false and BigNum.eq(blocks[3].hp, BigNum.new(5, 0)))
	check("오버플로우: changes에 3건 전부 기록됨", #changes == 3)
end

do
	-- 전체 HP를 초과할 때 전부 파괴 (남는 데미지는 버려짐, 에러 없음)
	local blocks = {
		{ position = Vector3.new(0, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 1 }, -- HP 10
		{ position = Vector3.new(10, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 2 }, -- HP 10
		{ position = Vector3.new(20, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 3 }, -- HP 10
	}
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(5, 1)) -- 데미지 50 (총 HP 30)

	check("총 HP 초과: 전부 파괴됨", blocks[1].destroyed and blocks[2].destroyed and blocks[3].destroyed)
	check("총 HP 초과: changes 3건 (남는 20 데미지는 그냥 버려짐)", #changes == 3)
end

do
	-- 거리순 정렬이 실제로 적용되는지: blocks 배열 순서와 거리 순서를 일부러 반대로 둔다.
	local blocks = {
		{ position = Vector3.new(100, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 1 }, -- 배열상 1번째, 멀리 있음
		{ position = Vector3.new(5, 0, 0), maxHp = BigNum.new(1, 1), hp = BigNum.new(1, 1), destroyed = false, seed = 2 }, -- 배열상 2번째, 가까움
	}
	-- 하나만 파괴할 데미지. 배열 순서대로면 blocks[1](먼 블록)이 맞아야 하지만,
	-- 거리순이면 blocks[2](가까운 블록)가 맞아야 한다.
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(1, 1))

	check("거리순: 가까운 블록(배열상 2번째)이 파괴됨", blocks[2].destroyed == true)
	check("거리순: 먼 블록(배열상 1번째)은 안 건드림", blocks[1].destroyed == false and BigNum.eq(blocks[1].hp, BigNum.new(1, 1)))
	check("거리순: changes에는 실제로 파괴된 블록의 index(2)만 기록됨", #changes == 1 and changes[1].index == 2)
end

do
	-- 잘못된 데미지 값(음수)은 거부 — 아무것도 안 바뀜
	local blocks = {
		{ position = Vector3.new(0, 0, 0), maxHp = BigNum.new(1, 0), hp = BigNum.new(1, 0), destroyed = false, seed = 1 },
	}
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(-5, 0))
	check("음수 데미지는 거부됨 (변경 없음)", #changes == 0 and BigNum.eq(blocks[1].hp, BigNum.new(1, 0)))
end

-- 3. buildBlockSet: 블록마다 다른 시드가 나오는지 ---------------------------------------------

do
	local blocks = pure.buildBlockSet(8, BigNum.new(1, 2), 777)
	local uniqueSeeds = {}
	for _, block in ipairs(blocks) do
		uniqueSeeds[block.seed] = true
	end
	local uniqueCount = 0
	for _ in pairs(uniqueSeeds) do
		uniqueCount = uniqueCount + 1
	end
	check("buildBlockSet: 블록 8개가 서로 다른 시드를 가짐", uniqueCount == 8)
end

-- 4. isBlockSetCleared: 전부 파괴 시에만 true ---------------------------------------------

do
	local blocks = pure.buildBlockSet(3, BigNum.new(1, 0), 1)
	check("아무 것도 안 부순 상태는 클리어 아님", pure.isBlockSetCleared(blocks) == false)

	pure.applyDamageToBlocks(blocks, blocks[1].position, BigNum.new(1, 0))
	pure.applyDamageToBlocks(blocks, blocks[2].position, BigNum.new(1, 0))
	check("일부만 부순 상태는 아직 클리어 아님", pure.isBlockSetCleared(blocks) == false)

	pure.applyDamageToBlocks(blocks, blocks[3].position, BigNum.new(1, 0))
	check("전부 부순 상태는 클리어", pure.isBlockSetCleared(blocks) == true)
end

-- ===== 스테이지 오프셋 (4-2-a2b) ======================================================
--
-- 블록 클러스터가 층마다 다른 X에 선다. 여기서 재는 것은 두 가지다:
-- 클러스터가 **통째로** 옮겨졌는가(상대 배치는 그대로), 그리고 그 자리가
-- 서버 판정이 쓰는 것과 **같은 유도**에서 나왔는가.
--
-- ⚠️ 200이나 80을 여기 적지 않는다. ArenaConfig / BlockLayout에서 읽는다.

-- ⚠️ TestHelpers.checkClose를 쓰지 못한다(서버라 src/client를 require할 수 없다).
-- 같은 상대오차·같은 반환 형태의 헬퍼를 둔다 — AttackServiceTests와 같은 처리다.
--
-- ⚠️ tol 인자는 **원본(TestHelpers.checkClose)에 원래 있는 것**이다. 새 헬퍼를 만든
-- 것이 아니라 이 사본이 빠뜨리고 있던 매개변수를 맞춘 것이다.
-- ⚠️ 호출부에 손으로 정한 숫자를 넘기지 말 것. 반드시 좌표에서 유도한다.
local RELATIVE_TOLERANCE = 1e-6
local function checkClose(actual: number, expected: number, tol: number?): (boolean, string)
	local tolerance = tol or RELATIVE_TOLERANCE
	local diff = actual - expected
	local relative = if expected ~= 0 then diff / expected else diff
	return math.abs(relative) < tolerance,
		string.format("기대값=%.17g 실제값=%.17g 차이=%.3e", expected, actual, diff)
end

-- 어떤 값이 놓인 자리의 float32 격자 간격. float32 유효숫자가 24비트로 고정이라
-- 절대 간격이 값의 크기에 비례한다 (AttackServiceTests에 같은 함수·같은 근거).
--
-- ⚠️ **진행 축(X)에만 오프셋이 실린다는 것이 요점이다.** 블록 좌표는 Z에도 있지만
-- Z는 원점 스케일에 남고 X만 굵은 격자로 간다. 축 대칭을 전제한 비교는 오프셋이
-- 0인 1층에서만 통과한다 — 2026-09-05 Play에서 이 파일의 fail 3건이 전부 그것이었다.
local function float32GapAt(value: number): number
	local _, exponent = math.frexp(value)
	return 2 ^ (exponent - 24)
end

do
	-- 스테이지 1은 원점이라 4-2-a2b 이전과 완전히 같아야 한다. 회귀 확인용 층이다.
	check("스테이지 1의 클러스터 원점이 월드 원점", BlockLayout.getStageOrigin(1) == Vector3.zero)
	check("stage 없이 부르면 원점 (기존 호출부 동작 보존)", BlockLayout.getStageOrigin(nil) == Vector3.zero)

	local base = pure.computeLayout(8)
	local stage1 = pure.computeLayout(8, 1)
	local same = true
	for i = 1, 8 do
		if (base[i] - stage1[i]).Magnitude > 1e-6 then
			same = false
		end
	end
	check("스테이지 1 좌표가 stage 생략과 동일 (1층에는 회귀가 없다)", same)
end

do
	-- 클러스터가 통째로 옮겨졌는가. 각 블록이 정확히 getStageOrigin(N)만큼 밀려야 하고,
	-- 블록 사이의 상대 배치는 한 톨도 안 바뀌어야 한다.
	for _, stage in ipairs({ 2, 3, 9 }) do
		local origin = BlockLayout.getStageOrigin(stage)
		local base = pure.computeLayout(16)
		local moved = pure.computeLayout(16, stage)

		check(
			string.format("스테이지 %d: 좌표 개수가 같다", stage),
			#moved == #base,
			string.format("%d vs %d", #moved, #base)
		)

		-- ⚠️ 이쪽이 1e-6으로 통과하는 것은 우연이 아니라 **반올림이 잔차를 지우기**
		-- 때문이다. moved[i] - base[i]는 결과가 origin.X 자리(예: 400)에 놓이는데,
		-- 그 자리 격자가 3.05e-05라 잔차(실측 최악 5.7e-06)가 반 칸에 못 미쳐 정확히
		-- 400으로 도로 반올림된다. 아래 상대 배치 검사는 결과가 작은 값이라 그 지우기가
		-- 일어나지 않고, 그래서 같은 크기의 오차가 거기서만 드러난다. 두 줄의 임계가
		-- 달라 보이는 이유가 이것이다 — 기준이 다른 것이 아니다.
		local allShifted = true
		for i = 1, #base do
			if ((moved[i] - base[i]) - origin).Magnitude > 1e-6 then
				allShifted = false
			end
		end
		check(string.format("스테이지 %d: 모든 블록이 getStageOrigin(%d)만큼 밀렸다", stage, stage), allShifted)

		-- 상대 배치 보존. 첫 블록 기준 상대 벡터가 그대로여야 한다.
		--
		-- ⚠️ **허용 폭을 넓혀서 통과시키는 것이 아니다.** 상한을 오프셋에서 유도한다:
		-- moved[i]와 moved[1]은 둘 다 float32(base.X + origin.X)로 저장되므로 각각
		-- 그 자리 격자의 절반까지 어긋난다. 둘을 빼면 최대 **한 칸**이다.
		--
		-- 2026-09-06 실측 최악값(격자 대비): 2층 0.375칸 / 3층 0.188칸 / 9층 0.484칸 /
		-- 25층 0.129칸 — 전부 한 칸 안이다. 상한은 원래 이 크기였고, 옛 1e-6은
		-- 3층 격자(3.05e-05)의 1/30이라 **어떤 코드로도 통과할 수 없는 값**이었다.
		-- 실제 실패도 2·3·9층에서만 났다 (1층은 오프셋이 0이라 격자가 안 굵어진다).
		--
		-- 진짜 배치 버그는 studs 단위로 어긋나므로 이 상한을 지나지 못한다.
		local tolerance = float32GapAt(origin.X)

		local worst = 0
		for i = 2, #base do
			local before = base[i] - base[1]
			local after = moved[i] - moved[1]
			worst = math.max(worst, (after - before).Magnitude)
		end

		-- 기대값 0이면 checkClose는 절대오차로 떨어진다(원본 TestHelpers와 같은 규약).
		-- 15개 중 최악값 하나로 판정한다 — 어느 블록이 걸렸는지보다 얼마나 어긋났는지가
		-- 관심사이고, 그 값이 격자 몇 칸인지가 원인을 바로 말해준다.
		check(
			string.format("스테이지 %d: 블록 사이 상대 배치는 그대로", stage),
			checkClose(worst, 0, tolerance),
			string.format("최악 오차=%.3e 상한=%.3e (격자의 %.3f칸)", worst, tolerance, worst / tolerance)
		)
	end
end

do
	-- 자리가 ArenaConfig 유도에서 나오는가. 오프셋을 어딘가에 상수로 박았다면
	-- 여기서 갈린다.
	for _, stage in ipairs({ 1, 2, 5 }) do
		local origin = BlockLayout.getStageOrigin(stage)
		check(
			string.format("스테이지 %d 원점 X가 ArenaConfig.getStageCenterX와 일치", stage),
			checkClose(origin.X, ArenaConfig.getStageCenterX(stage))
		)
		check(string.format("스테이지 %d 원점은 수평면 위 (Y=0, Z=0)", stage), origin.Y == 0 and origin.Z == 0)
	end
end

do
	-- buildBlockSet이 stage를 좌표까지 실어보내는가. computeLayout만 고치고 이쪽에
	-- 안 넘기면 서버가 아는 블록 위치가 옛 자리에 남는다.
	local stage = 4
	local origin = BlockLayout.getStageOrigin(stage)
	local maxHp = BigNum.new(1, 3)

	local blocks = pure.buildBlockSet(4, maxHp, 12345, stage)
	local expected = pure.computeLayout(4, stage)

	local matched = true
	for i = 1, 4 do
		if (blocks[i].position - expected[i]).Magnitude > 1e-6 then
			matched = false
		end
	end
	check("buildBlockSet 좌표가 computeLayout(count, stage)와 일치", matched)

	check(
		"buildBlockSet 좌표가 그 층의 원점 근처에 있다",
		(blocks[1].position - origin).Magnitude < ArenaConfig.STAGE_WIDTH,
		string.format("거리=%.1f", (blocks[1].position - origin).Magnitude)
	)

	-- stage 생략 시 원점. 기존 호출 형태가 그대로 도는지.
	local legacy = pure.buildBlockSet(4, maxHp, 12345)
	check(
		"buildBlockSet을 stage 없이 부르면 원점 (기존 동작 보존)",
		(legacy[1].position - pure.computeLayout(4)[1]).Magnitude < 1e-6
	)
end

print(string.format("[BlockServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BlockServiceTests] %d test(s) failed", failed))
end

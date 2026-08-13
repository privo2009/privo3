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

print(string.format("[BlockServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BlockServiceTests] %d test(s) failed", failed))
end

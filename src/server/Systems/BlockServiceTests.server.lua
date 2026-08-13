--!strict
-- BlockService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 3-1 검증: 배치 좌표 비중첩 / 반경 판정 경계값 / HP 0 클램프 / 클리어 판정.
-- 파괴 순서 셔플(computeDestructionOrder) 검증은 src/server/Tests/BlockShuffleTests로 옮겼다 —
-- 그 알고리즘이 src/shared/BlockShuffle.lua로 이동했기 때문 (서버/클라 공유 모듈).
--
-- BlockService._pure의 순수 함수만 호출한다 — Player/Instance 없이 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
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

local function allDistinct(positions: { Vector3 }): boolean
	for i = 1, #positions do
		for j = i + 1, #positions do
			if positions[i] == positions[j] then
				return false
			end
		end
	end
	return true
end

-- 1. computeLayout: 개수별 배치 좌표가 겹치지 않는지 (1, 4, 8, 16개) --------------------------

for _, count in ipairs({ 1, 4, 8, 16 }) do
	local positions = pure.computeLayout(count)
	check(string.format("computeLayout(%d): 개수만큼 좌표가 나옴", count), #positions == count)
	check(string.format("computeLayout(%d): 좌표가 서로 겹치지 않음", count), allDistinct(positions))
end

-- 경계 사이(5, 9)에서도 겹치지 않는지 확인 (원형/이중원 전환 지점)

for _, count in ipairs({ 5, 9 }) do
	local positions = pure.computeLayout(count)
	check(string.format("computeLayout(%d): 좌표가 서로 겹치지 않음 (전환 지점)", count), allDistinct(positions))
end

-- 2. isWithinRadius: 경계값 --------------------------------------------------------------

do
	local origin = Vector3.new(0, 0, 0)
	local blockPos = Vector3.new(5, 0, 0) -- 거리 정확히 5

	check("반경과 거리가 정확히 같으면 안(포함)", pure.isWithinRadius(origin, blockPos, 5) == true)
	check("반경보다 살짝 먼 블록은 밖", pure.isWithinRadius(origin, blockPos, 4.999) == false)
	check("반경보다 넉넉히 큰 경우 안", pure.isWithinRadius(origin, blockPos, 10) == true)
	check("거리가 0(원점에 겹침)이면 항상 안", pure.isWithinRadius(origin, origin, 0) == true)
end

-- 3. applyDamageToBlocks: HP 0 클램프 (음수 HP를 만들지 않음) -------------------------------

do
	local blocks = {
		{ position = Vector3.new(0, 0, 0), maxHp = BigNum.new(1, 0), hp = BigNum.new(1, 0), destroyed = false, seed = 1 },
	}

	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(5, 0), 1) -- HP 1에 데미지 5

	check("데미지가 HP를 넘겨도 hp는 0으로 클램프됨", BigNum.eq(blocks[1].hp, BigNum.new(0, 0)))
	check("클램프된 블록은 destroyed == true", blocks[1].destroyed == true)
	check("changes에 클램프된 블록이 기록됨", #changes == 1 and changes[1].destroyed == true and BigNum.eq(changes[1].hp, BigNum.new(0, 0)))
end

do
	-- 반경 밖 블록은 damage가 커도 전혀 안 바뀜
	local blocks = {
		{ position = Vector3.new(100, 0, 0), maxHp = BigNum.new(1, 0), hp = BigNum.new(1, 0), destroyed = false, seed = 1 },
	}
	local changes = pure.applyDamageToBlocks(blocks, Vector3.new(0, 0, 0), BigNum.new(5, 0), 1)
	check("반경 밖 블록은 변경되지 않음", #changes == 0 and BigNum.eq(blocks[1].hp, BigNum.new(1, 0)))
end

-- 4. buildBlockSet: 블록마다 다른 시드가 나오는지 ---------------------------------------------

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

-- 5. isBlockSetCleared: 전부 파괴 시에만 true ---------------------------------------------

do
	local blocks = pure.buildBlockSet(3, BigNum.new(1, 0), 1)
	check("아무 것도 안 부순 상태는 클리어 아님", pure.isBlockSetCleared(blocks) == false)

	pure.applyDamageToBlocks(blocks, blocks[1].position, BigNum.new(1, 0), 0)
	pure.applyDamageToBlocks(blocks, blocks[2].position, BigNum.new(1, 0), 0)
	check("일부만 부순 상태는 아직 클리어 아님", pure.isBlockSetCleared(blocks) == false)

	pure.applyDamageToBlocks(blocks, blocks[3].position, BigNum.new(1, 0), 0)
	check("전부 부순 상태는 클리어", pure.isBlockSetCleared(blocks) == true)
end

print(string.format("[BlockServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BlockServiceTests] %d test(s) failed", failed))
end

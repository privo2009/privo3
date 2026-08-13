--!strict
-- BlockShuffle 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 3-1 검증(원래 BlockServiceTests에 있던 셔플 테스트를 이쪽으로 옮김):
-- 같은 시드는 같은 순서, 다른 시드는 다른 순서.
--
-- src/shared/BlockShuffle.lua는 서버와 클라가 함께 쓰는 모듈이라, 테스트는 실제로
-- 실행되는 서버 스크립트 위치(src/server/Tests)에 두고 여기서 그 모듈을 require한다.
-- (Script는 ReplicatedStorage 밑에서는 자동 실행되지 않음 — ServerScriptService/Workspace만 실행됨)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockShuffle = require(ReplicatedStorage.Shared.BlockShuffle)

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

local function isPermutation(order: { number }, count: number): boolean
	if #order ~= count then
		return false
	end
	local seen = {}
	for _, v in ipairs(order) do
		if v < 1 or v > count or seen[v] then
			return false
		end
		seen[v] = true
	end
	return true
end

-- computeDestructionOrder: 같은 시드는 같은 순서, 다른 시드는 다른 순서 ------------------------

do
	local orderA1 = BlockShuffle.computeDestructionOrder(42, 10)
	local orderA2 = BlockShuffle.computeDestructionOrder(42, 10)
	local orderB = BlockShuffle.computeDestructionOrder(43, 10)

	check("같은 시드는 항상 유효한 순열", isPermutation(orderA1, 10))

	local sameOrder = true
	for i = 1, 10 do
		if orderA1[i] ~= orderA2[i] then
			sameOrder = false
			break
		end
	end
	check("같은 시드(42)는 매번 같은 순서를 냄", sameOrder)

	local differentOrder = false
	for i = 1, 10 do
		if orderA1[i] ~= orderB[i] then
			differentOrder = true
			break
		end
	end
	check("다른 시드(42 vs 43)는 다른 순서를 냄", differentOrder)
end

print(string.format("[BlockShuffleTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BlockShuffleTests] %d test(s) failed", failed))
end

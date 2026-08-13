--!strict
-- 서버와 클라가 동일한 파괴 순서를 재현하기 위한 공유 모듈.
-- 한쪽만 수정하면 서버/클라 큐브 상태가 어긋난다. 반드시 함께 유지할 것.

local BlockShuffle = {}

function BlockShuffle.computeDestructionOrder(seed: number, count: number): { number }
	local order = {}
	for i = 1, count do
		order[i] = i
	end

	local rng = Random.new(seed)
	for i = count, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end

	return order
end

return BlockShuffle

--!strict
-- 차단층 범용 큐 (Phase 7 지시서 #11 A6 — docs/UI.md "6. 패널 > 레이어 우선순위 > 차단층 큐 우선순위"). 순수 모듈.
--
--   한 번에 하나만 보인다. 지금 보이는 것을 닫으면(dismiss) 다음 것이 올라온다. 보이는 것을 가로채지 않는다 —
--   우선순위가 더 높은 것이 들어와도 지금 것이 닫힌 뒤에 먼저 올라온다.
--   우선순위 숫자가 작을수록 먼저(PRIORITY). 같은 우선순위는 들어온 순서.
--   뽑기 결과(아우라 #11 · 펫 #12) · 일일 보상 · 첫 접속 안내가 이 큐를 같이 쓴다. 로딩은 지금 LoadingScreen이 따로 연다
--   (데이터가 없으므로 다른 것이 뜰 수 없다 — 우선순위 1의 뜻이 구조로 이미 지켜진다).

local BlockingQueueLogic = {}

BlockingQueueLogic.PRIORITY = {
	loading = 1,
	firstJoin = 2,
	dailyReward = 3,
	rollResult = 4,
}

export type Item<T> = { priority: number, value: T, seq: number }

export type Queue<T> = {
	push: (priority: number, value: T) -> boolean, -- 지금 보이는 것이 바뀌었는가(비어 있다가 올라왔으면 true)
	current: () -> T?,
	dismiss: () -> T?, -- 지금 것을 닫고 다음 것을 올린다. 다음 것(없으면 nil)
	size: () -> number, -- 보이는 것 + 기다리는 것
}

function BlockingQueueLogic.new<T>(): Queue<T>
	local shown: Item<T>? = nil
	local waiting: { Item<T> } = {}
	local seq = 0
	local q = {}

	local function takeNext()
		if #waiting == 0 then
			shown = nil
			return
		end
		local best = 1
		for i = 2, #waiting do
			local a, b = waiting[i], waiting[best]
			if a.priority < b.priority or (a.priority == b.priority and a.seq < b.seq) then
				best = i
			end
		end
		shown = table.remove(waiting, best)
	end

	function q.push(priority: number, value: T): boolean
		seq += 1
		table.insert(waiting, { priority = priority, value = value, seq = seq })
		if shown == nil then
			takeNext()
			return true
		end
		return false
	end

	function q.current(): T?
		return if shown ~= nil then shown.value else nil
	end

	function q.dismiss(): T?
		takeNext()
		return q.current()
	end

	function q.size(): number
		return #waiting + (if shown ~= nil then 1 else 0)
	end

	return q :: Queue<T>
end

return BlockingQueueLogic

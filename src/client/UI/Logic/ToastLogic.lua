--!strict
-- 토스트 큐 (Phase 7 지시서 #10 — docs/UI.md "6. 패널 > 레이어 우선순위"). 순수 모듈 — 화면은 Screens/Overlay/ToastStack.
--
--   세로로 최대 MAX_VISIBLE개까지 동시에 보인다. 넘치면 큐에서 기다린다.
--   보이는 것은 HOLD_SEC 뒤에 사라진다 — 먼저 뜬 것(오래된 것)부터. 빈 자리가 생기면 큐 맨 앞이 올라온다.
--   시각은 인자로 받는다(테스트가 시계를 주입한다).

local ToastLogic = {}

ToastLogic.MAX_VISIBLE = 3 -- docs/UI.md
ToastLogic.HOLD_SEC = 3 -- Claude 판단(세션 로그): 한 줄 문구를 읽고도 남는 시간, 자동 롤이 초당 1회라 길면 큐가 밀린다

export type Item<T> = { value: T, shownAt: number? }

export type Queue<T> = {
	push: (value: T, now: number) -> (),
	tick: (now: number) -> boolean, -- 보이는 목록이 바뀌었는가
	visible: () -> { T }, -- 위(오래된 것)부터
	waiting: () -> number,
	nextExpiryIn: (now: number) -> number?, -- 가장 오래된 것이 사라질 때까지 남은 초. 보이는 것이 없으면 nil
	-- 동시에 보이는 수를 바꾼다(#L2 — 폰에서 2). 줄이면 넘치는 것(나중에 뜬 것)을 큐 맨 앞으로 돌려보낸다 — 잃지 않는다
	setLimit: (limit: number, now: number) -> boolean,
}

function ToastLogic.new<T>(maxVisible: number?, holdSec: number?): Queue<T>
	local limit: number = maxVisible or ToastLogic.MAX_VISIBLE
	local hold = holdSec or ToastLogic.HOLD_SEC
	local shown: { Item<T> } = {}
	local queued: { T } = {}
	local q = {}

	local function promote(now: number): boolean
		local changed = false
		while #shown < limit and #queued > 0 do
			table.insert(shown, { value = table.remove(queued, 1) :: T, shownAt = now })
			changed = true
		end
		return changed
	end

	function q.push(value: T, now: number)
		table.insert(queued, value)
		promote(now)
	end

	function q.tick(now: number): boolean
		local changed = false
		while #shown > 0 and now - (shown[1].shownAt :: number) >= hold do
			table.remove(shown, 1)
			changed = true
		end
		return promote(now) or changed
	end

	function q.visible(): { T }
		local out: { T } = {}
		for i, item in ipairs(shown) do
			out[i] = item.value
		end
		return out
	end

	function q.waiting(): number
		return #queued
	end

	function q.setLimit(newLimit: number, now: number): boolean
		if newLimit == limit or newLimit < 1 then
			return false
		end
		limit = newLimit
		local changed = false
		while #shown > limit do
			local item = table.remove(shown) :: Item<T>
			table.insert(queued, 1, item.value)
			changed = true
		end
		return promote(now) or changed
	end

	function q.nextExpiryIn(now: number): number?
		local first = shown[1]
		if first == nil then
			return nil
		end
		return math.max(0, (first.shownAt :: number) + hold - now)
	end

	return q :: Queue<T>
end

return ToastLogic

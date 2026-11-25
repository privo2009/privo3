--!strict
-- 클라 → 서버 입구 공통 문(지시서 #38 — 리모트 보안). 모든 OnServerEvent는 RemoteGuard.connect로 붙인다.
-- 목록 · 리모트마다의 검사는 docs/REMOTES.md(원본은 이 파일의 POLICIES와 각 서비스 코드).
--
-- 서비스가 받기 전에 세 가지를 공통으로 한다(서비스 자체 검사 — 타입 · 범위 · 권한 · 자체 빈도 상한 — 는 그대로 둔다):
--   1. 모양 예산: payload에 허용 타입만(nil · boolean · 유한한 number · 짧은 string · 작은 table).
--      NaN · inf · Instance · 함수 · 아주 긴 문자열 · 깊거나 큰 표는 서비스까지 가지 않는다(조용히 버림)
--   2. 연타 상한: 플레이어 × 리모트마다 토큰 통. 기본은 0.15초에 1번(대장간 · 장비 · 펫 자동과 같은 방식).
--      클라가 주기로 묶어 보내는 입구(ClickInput 0.2초 · SyncRequest 접속 직후 몇 번)는 통을 넉넉히 준다 — POLICIES
--   3. 오류 격리: 처리 중 오류가 나도 연결은 살아 있고 다음 요청은 그대로 처리된다(warn은 리모트마다 60초에 한 번)
-- 버린 요청은 응답하지 않는다 — 정상 플레이로는 닿지 않는 빈도 · 모양이다. 버린 수는 stats()로 본다.
-- 나가면 그 플레이어의 통 · 기록을 지운다.

local Players = game:GetService("Players")

local RemoteGuard = {}

RemoteGuard.DEFAULT_GAP_SEC = 0.15
RemoteGuard.MAX_DEPTH = 3 -- payload 표 깊이(payload 자체가 1)
RemoteGuard.MAX_KEYS = 32 -- 표 하나의 키 수
RemoteGuard.MAX_TOTAL = 128 -- payload 전체 값 수
RemoteGuard.MAX_STRING = 200 -- 문자열 길이(바이트) — 코드 입력 · id · 키보다 넉넉하다
RemoteGuard.ERROR_WARN_SEC = 60

export type Policy = { rate: number, burst: number }

-- 리모트 이름 → 통. 없으면 기본(0.15초에 1번 · 몰아 쓰기 1).
RemoteGuard.POLICIES = {
	ClickInput = { rate = 10, burst = 4 } :: Policy, -- 클라 0.2초 묶음(초당 5) · 네트워크 몰림 여유. 클릭 수 상한은 ClickService 창이 따로 잰다
	SpeedRequest = { rate = 10, burst = 4 } :: Policy, -- SpeedRequestService 창이 따로 잰다
	SyncRequest = { rate = 2, burst = 10 } :: Policy, -- 접속 · 리스폰 직후 수신부 여러 개가 한꺼번에 부른다(서버가 모아 한 번 답한다)
} :: { [string]: Policy }

local function defaultPolicy(): Policy
	return { rate = 1 / RemoteGuard.DEFAULT_GAP_SEC, burst = 1 }
end

function RemoteGuard.policyOf(name: string): Policy
	return RemoteGuard.POLICIES[name] or defaultPolicy()
end

-- ===== 순수 함수 =================================================================================

-- payload 모양 검사. (통과, 사유)
local function checkShape(payload: any): (boolean, string?)
	local total = 0
	local function visit(v: any, depth: number): string?
		total += 1
		if total > RemoteGuard.MAX_TOTAL then
			return "too_many_values"
		end
		local t = type(v)
		if t == "nil" or t == "boolean" then
			return nil
		elseif t == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				return "not_finite"
			end
			return nil
		elseif t == "string" then
			return if #v > RemoteGuard.MAX_STRING then "string_too_long" else nil
		elseif t == "table" then
			if depth > RemoteGuard.MAX_DEPTH then
				return "too_deep"
			end
			local keys = 0
			for k, child in pairs(v) do
				keys += 1
				if keys > RemoteGuard.MAX_KEYS then
					return "too_many_keys"
				end
				local kt = type(k)
				if kt == "string" then
					if #k > RemoteGuard.MAX_STRING then
						return "string_too_long"
					end
				elseif kt == "number" then
					if k ~= k or k == math.huge or k == -math.huge then
						return "not_finite"
					end
				else
					return "bad_key"
				end
				local why = visit(child, depth + 1)
				if why ~= nil then
					return why
				end
			end
			return nil
		end
		return "bad_type" -- Instance · Vector3 · 함수 · buffer 등 — 우리 입구는 어디서도 받지 않는다
	end
	local why = visit(payload, 1)
	return why == nil, why
end

export type Gate = {
	check: (player: any, name: string, payload: any, now: number) -> (boolean, string?),
	forget: (player: any) -> (),
	stats: () -> { [string]: { [string]: number } },
	_buckets: (player: any) -> { [string]: { tokens: number, at: number } }?,
}

-- 통 묶음 하나(실물은 모듈이 하나 갖고, 테스트는 따로 만든다).
local function newGate(policyOf: ((string) -> Policy)?): Gate
	local pick = policyOf or RemoteGuard.policyOf
	local buckets: { [any]: { [string]: { tokens: number, at: number } } } = {}
	local counts: { [string]: { [string]: number } } = {}
	local function count(name: string, what: string)
		local c = counts[name]
		if c == nil then
			c = {}
			counts[name] = c
		end
		c[what] = (c[what] or 0) + 1
	end
	local gate = {}
	function gate.check(player: any, name: string, payload: any, now: number): (boolean, string?)
		local ok, why = checkShape(payload)
		if not ok then
			count(name, why :: string)
			return false, why
		end
		local policy = pick((string.match(name, "^[^#]+") :: string)) -- "SyncRequest#2"도 SyncRequest 통 크기
		local mine = buckets[player]
		if mine == nil then
			mine = {}
			buckets[player] = mine
		end
		local b = mine[name]
		if b == nil then
			b = { tokens = policy.burst, at = now }
			mine[name] = b
		end
		b.tokens = math.min(policy.burst, b.tokens + math.max(0, now - b.at) * policy.rate)
		b.at = now
		if b.tokens < 1 - 1e-9 then
			count(name, "rate_limited")
			return false, "rate_limited"
		end
		b.tokens -= 1
		count(name, "passed")
		return true, nil
	end
	function gate.forget(player: any)
		buckets[player] = nil
	end
	function gate.stats()
		return counts
	end
	function gate._buckets(player: any)
		return buckets[player]
	end
	return gate :: any
end

-- 처리 함수를 오류 격리로 감싼다. (처리됐나, 오류 글)
local lastWarnAt: { [string]: number } = {}
local function runIsolated(name: string, fn: (any, any) -> (), player: any, payload: any, now: number, warnFn: ((string) -> ())?): (boolean, string?)
	local ok, err = xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end, player, payload)
	if not ok then
		local last = lastWarnAt[name]
		if last == nil or now - last >= RemoteGuard.ERROR_WARN_SEC then
			lastWarnAt[name] = now
			local line = string.format("[RemoteGuard] %s 처리 오류(연결은 그대로 · %d초에 한 번만 찍는다): %s", name, RemoteGuard.ERROR_WARN_SEC,
				string.sub(tostring(err), 1, 400))
			if warnFn ~= nil then
				warnFn(line)
			else
				warn(line)
			end
		end
		return false, tostring(err)
	end
	return true, nil
end

RemoteGuard._pure = { checkShape = checkShape, newGate = newGate, runIsolated = runIsolated }

-- ===== 실물 =====================================================================================

local live = newGate()
local connected: { [string]: number } = {}
local removingHooked = false

-- 리모트 하나를 붙인다. fn(player, payload)는 모양 · 연타를 통과한 요청만 받는다.
function RemoteGuard.connect(remote: RemoteEvent, fn: (Player, any) -> ()): RBXScriptConnection
	local name = remote.Name
	connected[name] = (connected[name] or 0) + 1
	if not removingHooked then
		removingHooked = true
		Players.PlayerRemoving:Connect(function(player: Player)
			live.forget(player)
		end)
	end
	-- 같은 리모트를 두 서비스가 들으면(SyncRequest) 통도 서비스마다 따로 둔다 — 한쪽이 다른 쪽 몫을 먹지 않게
	local key = if connected[name] > 1 then name .. "#" .. connected[name] else name
	return remote.OnServerEvent:Connect(function(player: Player, payload: any)
		local now = os.clock()
		if player.Parent ~= Players then
			return -- 나가는 중
		end
		local ok = live.check(player, key, payload, now)
		if not ok then
			return
		end
		runIsolated(name, fn :: any, player, payload, now)
	end)
end

-- 붙은 리모트 이름 → 붙은 수(테스트 · 문서 대조용)
function RemoteGuard.connected(): { [string]: number }
	return table.clone(connected)
end

-- 리모트 이름 → { passed · rate_limited · 모양 사유 = 수 }
function RemoteGuard.stats(): { [string]: { [string]: number } }
	return live.stats()
end

-- 테스트 전용: 실물 통에 남은 플레이어 기록(나가면 nil이어야 한다)
function RemoteGuard._liveBuckets(player: any)
	return live._buckets(player)
end

return RemoteGuard

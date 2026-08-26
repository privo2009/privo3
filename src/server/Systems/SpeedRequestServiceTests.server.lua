--!strict
-- SpeedRequestService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-c 검증: 요청 빈도 상한 / 폐기 / 폐기 로그 억제 / 응답 payload 형태.
--
-- SpeedRequestService._pure의 순수 함수만 호출한다 — Player/Humanoid 없이 검증한다
-- (SpeedServiceTests와 같은 방식). RemoteEvent 발화와 실제 Humanoid 반영은 여기서
-- 다루지 않는다: 그쪽은 Instance가 필요해서 Studio Play 육안 확인 몫이다.
--
-- ===== 값 검증(숫자 아님 · nan · inf · 0 이하 · 최대치 잘림)은 이 파일에도 있다 ========
--
-- 그 로직의 원본은 SpeedService이고 SpeedServiceTests가 이미 검증한다. 여기서 다시
-- 재는 이유는 **채널을 통과한 값도 같은 관문을 지나는지**가 별개의 질문이기 때문이다.
-- SpeedRequestService가 언젠가 자체 검증을 끼워넣거나 setCustomSpeed 대신 다른 경로를
-- 부르게 되면 SpeedServiceTests는 그대로 통과하면서 채널만 조용히 뚫린다.
-- 그래서 아래 "채널을 통과한 값" 절은 두 _pure를 **합성해서** 잰다 — 로직을 복사하지
-- 않고 원본을 그대로 태우므로, 원본이 바뀌면 이 테스트도 함께 따라간다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SpeedRequestService = require(script.Parent.SpeedRequestService)
local SpeedService = require(script.Parent.SpeedService)

local pure = SpeedRequestService._pure
local speedPure = SpeedService._pure

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

local LIMIT = pure.REQUEST_LIMIT
local WINDOW = pure.WINDOW_SEC

-- 1. 요청 빈도 상한 --------------------------------------------------------------------

do
	local state = pure.newRequestState()
	local now = 100.0

	local allAllowed = true
	for _ = 1, LIMIT do
		local allowed: boolean
		state, allowed = pure.takeSlot(state, now)
		if not allowed then
			allAllowed = false
		end
	end

	check("상한만큼의 요청은 전부 통과한다", allAllowed, string.format("limit=%d", LIMIT))
	check("통과분만 창에 쌓인다", #state.times == LIMIT, tostring(#state.times))
end

do
	local state = pure.newRequestState()
	local now = 100.0

	for _ = 1, LIMIT do
		state = (pure.takeSlot(state, now))
	end

	local nextState, allowed = pure.takeSlot(state, now)
	check("상한을 넘는 요청은 폐기된다", not allowed)
	check("폐기된 요청은 창에 쌓이지 않는다", #nextState.times == LIMIT, tostring(#nextState.times))
	check("폐기는 집계에 남는다", nextState.droppedSinceLog == 1, tostring(nextState.droppedSinceLog))
end

do
	-- 창이 지나면 자리가 돌아온다. 상한이 "누적 총량"이 아니라 "창 안의 양"임을 확인한다.
	local state = pure.newRequestState()
	local now = 100.0

	for _ = 1, LIMIT do
		state = (pure.takeSlot(state, now))
	end

	local _, blockedNow = pure.takeSlot(state, now)
	check("창이 차 있는 동안은 막힌다", not blockedNow)

	local recovered, allowedLater = pure.takeSlot(state, now + WINDOW + 0.01)
	check("창이 지나면 다시 통과한다", allowedLater)
	check("창 밖 기록은 버려진다", #recovered.times == 1, tostring(#recovered.times))
end

do
	-- 경계값. 정확히 WINDOW_SEC 지난 기록은 창 밖이다(now - t < WINDOW가 거짓).
	local state = pure.newRequestState()
	local now = 100.0

	for _ = 1, LIMIT do
		state = (pure.takeSlot(state, now))
	end

	local _, allowedAtEdge = pure.takeSlot(state, now + WINDOW)
	check("창 길이와 정확히 같은 시점은 창 밖으로 본다", allowedAtEdge)
end

do
	-- 클라가 시각을 정할 수 없으므로 같은 배치가 같은 now를 공유한다.
	-- 그 상황에서도 상한이 제대로 걸리는지 (한 프레임에 몰아 보내는 경우).
	local state = pure.newRequestState()
	local now = 100.0

	local accepted = 0
	local dropped = 0
	for _ = 1, LIMIT * 4 do
		local allowed: boolean
		state, allowed = pure.takeSlot(state, now)
		if allowed then
			accepted += 1
		else
			dropped += 1
		end
	end

	check("한 시점에 몰아 보내도 통과분은 상한까지다", accepted == LIMIT, tostring(accepted))
	check("나머지는 전부 폐기된다", dropped == LIMIT * 3, tostring(dropped))
	check("폐기 수가 누적된다", state.droppedSinceLog == LIMIT * 3, tostring(state.droppedSinceLog))
end

-- 2. 폐기 로그 억제 ---------------------------------------------------------------------

do
	local state = pure.newRequestState()
	local now = 100.0

	local _, shouldLog = pure.takeDropLog(state, now)
	check("폐기가 없으면 로그도 없다", not shouldLog)
end

do
	local state = pure.newRequestState()
	local now = 100.0

	for _ = 1, LIMIT + 3 do
		state = (pure.takeSlot(state, now))
	end

	local logged, shouldLog, dropped = pure.takeDropLog(state, now)
	check("폐기가 있으면 한 번 찍는다", shouldLog)
	check("억제된 동안의 폐기 수를 함께 싣는다", dropped == 3, tostring(dropped))
	check("찍은 뒤 누적은 0으로 비운다", logged.droppedSinceLog == 0, tostring(logged.droppedSinceLog))

	-- 곧바로 또 폐기가 나도 억제 간격 안에서는 찍지 않는다.
	local more = pure.takeSlot(logged, now)
	local _, shouldLogAgain = pure.takeDropLog(more, now + 0.1)
	check("억제 간격 안에서는 다시 찍지 않는다", not shouldLogAgain)

	local _, shouldLogLater = pure.takeDropLog(more, now + pure.DROP_LOG_QUIET_SEC + 0.01)
	check("억제 간격이 지나면 다시 찍는다", shouldLogLater)
end

-- 3. 채널을 통과한 값도 SpeedService의 관문을 지난다 ------------------------------------
--
-- 아래는 "채널 → 값 검증 → 응답 payload"를 두 _pure의 합성으로 재현한 것이다.
-- 검증 로직을 여기 복사하지 않는다 — speedPure.applyRequest를 그대로 태운다.

-- 요청 하나가 채널을 통과했을 때 클라에 무엇이 돌아가는지.
-- (새 상태, payload 또는 nil, 값이 받아들여졌는가)
local function routeRequest(
	speedState: SpeedService.SpeedState,
	windowState: SpeedRequestService.RequestState,
	raw: any,
	maxSpeed: number,
	now: number
): (SpeedService.SpeedState, SpeedRequestService.RequestState, Remotes.SpeedAppliedPayload?, boolean)
	local nextWindow, allowed = pure.takeSlot(windowState, now)
	if not allowed then
		-- 폐기: 응답 자체가 없다.
		return speedState, nextWindow, nil, false
	end

	local nextSpeed, applied, accepted = speedPure.applyRequest(speedState, raw, maxSpeed)
	return nextSpeed, nextWindow, pure.buildApplied(applied, maxSpeed), accepted
end

do
	local maxSpeed = 18
	local speedState = speedPure.newSpeedState()
	local windowState = pure.newRequestState()

	local _s, _w, payload, accepted = routeRequest(speedState, windowState, 12, maxSpeed, 100.0)

	check("정상값은 통과한다", accepted)
	check("응답에 실리는 것은 실제 적용값이다", payload ~= nil and payload.speed == 12, tostring(payload and payload.speed))
	check("응답에 현재 최대치가 함께 실린다", payload ~= nil and payload.maxSpeed == maxSpeed)
end

do
	local maxSpeed = 18
	local speedState = speedPure.newSpeedState()
	local windowState = pure.newRequestState()

	local _s, _w, payload, accepted = routeRequest(speedState, windowState, 9999, maxSpeed, 100.0)

	check("최대치 초과는 거부가 아니라 잘림이다", accepted)
	check("잘린 값이 응답에 실린다", payload ~= nil and payload.speed == maxSpeed, tostring(payload and payload.speed))
end

do
	-- 거부되는 값들. 전부 "응답은 오되 현재 적용값이 실린다"여야 한다.
	local maxSpeed = 18

	-- ⚠️ 테이블 생성자 안에 nil을 그대로 넣지 말 것. 배열이 그 자리에서 잘려서 뒤 항목이
	-- 조용히 검사에서 빠진다 — 검사 목록이 줄어드는 종류의 사고라 통과해도 알 수 없다.
	-- 인덱스로 직접 넣고 개수는 labels로 센다.
	local labels = { "0", "음수", "nan", "inf", "-inf", "문자열", "boolean", "nil", "테이블" }
	local bad: { [number]: any } = {}
	bad[1] = 0
	bad[2] = -5
	bad[3] = 0 / 0
	bad[4] = math.huge
	bad[5] = -math.huge
	bad[6] = "20"
	bad[7] = true
	bad[8] = nil -- 명시적으로 둔다. 아래 루프는 labels 개수만큼 도므로 건너뛰지 않는다
	bad[9] = {}

	local allRejected = true
	local allAnswered = true
	local allCurrentValue = true

	for i = 1, #labels do
		-- 세션 값을 12로 정해둔 상태에서 잘못된 값이 오는 상황.
		local speedState = speedPure.applyRequest(speedPure.newSpeedState(), 12, maxSpeed)
		local windowState = pure.newRequestState()

		local _s, _w, payload, accepted = routeRequest(speedState, windowState, bad[i], maxSpeed, 100.0)

		if accepted then
			allRejected = false
			warn(string.format("[FAIL] 거부되어야 할 값이 통과: %s", labels[i]))
		end
		if payload == nil then
			allAnswered = false
		elseif payload.speed ~= 12 then
			allCurrentValue = false
			warn(string.format("[FAIL] 거부 응답에 현재값이 아닌 값: %s -> %s", labels[i], tostring(payload.speed)))
		end
	end

	check("0 이하 / nan / inf / 숫자 아님 / nil은 전부 거부", allRejected)
	check("거부여도 응답은 보낸다 (클라 표시가 어긋난 채 남지 않게)", allAnswered)
	check("거부 응답에는 지금 적용 중인 값이 실린다", allCurrentValue)
end

do
	-- 폐기는 다르다. 응답 자체가 없어야 한다 — 여기서 응답하면 플러딩에 플러딩으로 답하게 된다.
	local maxSpeed = 18
	local speedState = speedPure.newSpeedState()
	local windowState = pure.newRequestState()
	local now = 100.0

	for _ = 1, LIMIT do
		speedState, windowState = routeRequest(speedState, windowState, 12, maxSpeed, now)
	end

	local _s, _w, payload = routeRequest(speedState, windowState, 12, maxSpeed, now)
	check("폐기된 요청에는 응답하지 않는다", payload == nil)
end

do
	-- 폐기는 세션 값도 건드리면 안 된다. 건드리면 상한이 곧 속도 조작 수단이 된다.
	local maxSpeed = 18
	local speedState = speedPure.applyRequest(speedPure.newSpeedState(), 12, maxSpeed)
	local windowState = pure.newRequestState()
	local now = 100.0

	for _ = 1, LIMIT do
		local _s, nextWindow = routeRequest(speedState, windowState, 5, maxSpeed, now)
		windowState = nextWindow
	end

	local after = routeRequest(speedState, windowState, 5, maxSpeed, now)
	check("폐기된 요청은 세션 값을 바꾸지 않는다", after.requested == 12, tostring(after.requested))
end

-- 4. 상수의 성격 -------------------------------------------------------------------------

do
	-- 이 상한은 부하 가드다. 클릭 상한(오토마우스 방어선 = 수익 축)보다 낮아야 한다 —
	-- 높아지는 순간 배치도 없는 채널이 클릭 경로보다 시끄러워진다.
	local ClickService = require(script.Parent.ClickService)
	check(
		"속도 요청 상한은 클릭 상한보다 낮다",
		LIMIT < ClickService._pure.MANUAL_CLICK_LIMIT,
		string.format("speed=%d, click=%d", LIMIT, ClickService._pure.MANUAL_CLICK_LIMIT)
	)
	check(
		"폐기 로그 억제 간격은 창보다 길다",
		pure.DROP_LOG_QUIET_SEC > WINDOW,
		string.format("window=%.1f, log=%.1f", WINDOW, pure.DROP_LOG_QUIET_SEC)
	)
end

do
	-- 응답에 실리는 최대치는 LevelConfig가 상한을 씌운 값이라 유한하다.
	-- inf가 실리면 직렬화 제약 3번에 걸려 payload가 통째로 깨진다.
	local cap = LevelConfig.getMaxWalkSpeed()
	check("최대치는 유한하다 (직렬화 제약)", cap == cap and cap ~= math.huge, tostring(cap))
	local payload = pure.buildApplied(cap, cap)
	check("payload 두 필드가 모두 채워진다", payload.speed ~= nil and payload.maxSpeed ~= nil)
end

print(string.format("[SpeedRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SpeedRequestServiceTests] %d test(s) failed", failed))
end

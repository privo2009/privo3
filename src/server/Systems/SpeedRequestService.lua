--!strict
-- SpeedRequest 채널의 수신부. 4-2-c의 마지막 조각이자 이 프로젝트 두 번째 클라→서버 경로다.
--
-- 하는 일:
--   1. 클라가 보낸 속도 요청을 받는다 (SpeedRequest 채널)
--   2. 슬라이딩 윈도우로 상한을 넘는 요청을 폐기한다
--   3. 통과분을 SpeedService.setCustomSpeed에 넘긴다
--   4. 실제 적용값과 현재 최대치를 SpeedApplied로 돌려보낸다
--
-- ===== 왜 SpeedService가 직접 받지 않는가 =============================================
--
-- SpeedService는 "값을 정하고 Humanoid에 얹어 유지하는" 모듈이고, 여기는 "클라 입력을
-- 받아 그 모듈에 넘기는" 모듈이다. 나눈 이유는 상한의 성격이 다르기 때문이다:
-- SpeedService의 min()은 **누가 부르든** 적용되는 규칙이고(서버 내부 호출도 포함),
-- 아래 윈도우 상한은 **클라 입력 경로에만** 있어야 하는 방어선이다. 환생 처리나 UI
-- 되돌림이 서버에서 setCustomSpeed를 불렀는데 "초당 5회"에 걸려 무시되면 안 된다.
-- ClickService가 SOURCE_MANUAL로 같은 구분을 파일 안에서 한 것을, 여기서는 파일로 나눴다.
--
-- ===== 값 검증은 여기에 없다 (중요) ====================================================
--
-- 숫자 아님 · nil · nan · inf · 0 이하 거부와 최대치 min() 클램프는 전부
-- SpeedService.setCustomSpeed 안에 있다(sanitizeRequest / applyRequest).
-- ⚠️ 그 검사를 이 파일에 다시 쓰지 말 것. 두 곳에 있으면 반드시 갈라지고,
--    갈라진 순간 어느 쪽이 통과시켰는지 알 수 없게 된다. 여기서 재는 것은 **빈도**뿐이다.
--
-- 그래서 이 파일이 클라 값에 대해 하는 일은 딱 하나다: payload에서 speed 필드를 꺼내
-- 그대로 넘긴다. 꺼낸 값이 무엇이든(문자열·nil·nan) 검사는 SpeedService가 한다.
--
-- ===== 거부에도 응답한다 ===============================================================
--
-- setCustomSpeed는 거부여도 **현재 실제 적용 중인 속도**를 돌려준다. 그 값을 그대로
-- SpeedApplied에 실어 보낸다. 거부야말로 클라 표시가 어긋나 있는 경우이므로 여기서
-- 침묵하면 잘못된 값이 화면에 남는다 (Remotes.lua SpeedAppliedPayload 주석).
--
-- 응답하지 않는 경우는 하나뿐이다: 윈도우 상한에 걸려 **폐기**된 요청.
-- 폐기에까지 응답하면 초당 수백 발화를 보낸 클라에게 서버가 초당 수백 발화로 답하게 된다 —
-- 막으려던 것과 똑같은 부하를 스스로 만드는 셈이다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SpeedService = require(script.Parent.SpeedService)

local SpeedRequestService = {}

-- 채널은 모듈 로드 시 한 번 확보한다 (ClickService와 같은 패턴).
local channels = Remotes.getServer()

-- ===== 요청 빈도 상한 (⚠️ 밸런스가 아니다) ============================================
--
-- 클릭 상한(10회/초)과 성격이 완전히 다르다. 클릭 상한은 오토마우스 방어선이라
-- 게임패스 가치를 떠받치는 수익 축이지만, 이 값은 **부하 가드일 뿐**이다.
-- 속도를 빨리 바꿔서 얻는 이득이 없기 때문이다 — 어차피 min(요청, 최대치)이라
-- 몇 번을 보내든 도달할 수 있는 상한은 같다.
--
-- 5회/초를 고른 근거 — 두 방향에서 눌린 값이다:
--   아래: 숫자 직접 입력은 슬라이더와 달리 **입력 확정 시 1회**다. 정상 사용의 정점은
--         오타를 고쳐 다시 넣는 경우(2~3회 연속)이고, 여기에 여유를 둬야 정직한 유저가
--         걸리지 않는다. 1~2회로 조이면 "빨리 고쳐 넣었더니 안 먹는다"가 된다
--   위:   요청 1회의 비용은 Humanoid 쓰기 1회 + FireClient 1회다. 30명 × 5회/초면
--         초당 150회로, 클릭 경로(초당 300발화를 피하려고 배치를 넣은 그 규모)의
--         절반이다. 이보다 올리면 배치도 없는 채널이 클릭보다 시끄러워진다
--
-- ⚠️ 클라가 루프로 밀어넣는 경우를 위해 있는 값이다. 정상 클라는 여기 닿지 않는다.
--    닿는다면 그건 UI가 입력 중간값을 매 글자마다 보내고 있다는 뜻이므로, 상한을
--    올리지 말고 Phase 6 UI에서 확정 시 1회만 보내도록 고칠 것.
local REQUEST_LIMIT = 5

-- 상한을 재는 창의 길이(초). "초당 5회"의 그 '초'다.
local WINDOW_SEC = 1.0

-- 폐기 로그를 다시 찍기까지의 최소 간격(초).
--
-- ⚠️ 폐기를 조용히 버리지 않는다. 이 프로젝트에서 반복해서 데인 것이 "조용히 틀린 값"이라
-- (PadService NOTIFY_QUIET_SEC / SpeedService VIOLATION_LOG_QUIET_SEC와 같은 이유),
-- 요청이 사라지는데 서버에 아무 흔적이 없으면 "SpeedApplied가 안 온다"를 배선 버그로
-- 오진하게 된다. 대신 상한에 걸린 클라는 계속 걸려 있으므로 억제 간격을 둔다.
-- 그 사이 폐기된 수는 누적해서 다음 로그에 함께 싣는다.
local DROP_LOG_QUIET_SEC = 5.0

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

export type RequestState = {
	-- 통과시킨 요청의 처리 시각들. 항상 REQUEST_LIMIT개 이하다.
	times: { number },
	lastDropLogAt: number,
	droppedSinceLog: number,
}

local function newRequestState(): RequestState
	return {
		times = {},
		lastDropLogAt = 0,
		droppedSinceLog = 0,
	}
end

-- 요청 하나를 윈도우에 통과시켜 (새 상태, 통과 여부)를 돌려준다.
-- 상태를 제자리에서 고치지 않는다 (ClickService.applyClicks와 같은 규약).
--
-- ⚠️ 타임스탬프는 서버가 받은 시각(now)이다. 클라가 보낸 시각을 쓰지 않는다 —
-- 시각을 클라가 정할 수 있으면 과거로 흩뿌려서 윈도우를 무한히 비울 수 있다.
local function takeSlot(state: RequestState, now: number): (RequestState, boolean)
	local times: { number } = {}
	for _, t in ipairs(state.times) do
		if now - t < WINDOW_SEC then
			table.insert(times, t)
		end
	end

	if #times >= REQUEST_LIMIT then
		return {
			times = times,
			lastDropLogAt = state.lastDropLogAt,
			droppedSinceLog = state.droppedSinceLog + 1,
		}, false
	end

	table.insert(times, now)
	return {
		times = times,
		lastDropLogAt = state.lastDropLogAt,
		droppedSinceLog = state.droppedSinceLog,
	}, true
end

-- 지금 폐기 로그를 찍어도 되는지 판단하고, 찍는다면 그 사실을 상태에 기록한다.
-- (새 상태, 찍을지, 직전 로그 이후 폐기된 총량)을 돌려준다.
-- (ClickService.takeRejectNotice와 같은 형태다)
local function takeDropLog(state: RequestState, now: number): (RequestState, boolean, number)
	if state.droppedSinceLog <= 0 then
		return state, false, 0
	end
	if (now - state.lastDropLogAt) < DROP_LOG_QUIET_SEC then
		return state, false, 0
	end

	return {
		times = state.times,
		lastDropLogAt = now,
		droppedSinceLog = 0,
	}, true, state.droppedSinceLog
end

-- 클라에 돌려보낼 payload를 만든다.
--
-- ⚠️ 두 필드 모두 항상 채운다. 선택 필드로 만들면 nil인 키가 직렬화에서 통째로 사라져서
-- 수신부가 다른 형태를 받는다 (Remotes.lua 직렬화 제약 2번).
-- speed에 들어가는 것은 **서버가 정한 실제 적용값**이지 클라가 보낸 요청값이 아니다.
local function buildApplied(applied: number, maxSpeed: number): Remotes.SpeedAppliedPayload
	return {
		speed = applied,
		maxSpeed = maxSpeed,
	}
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- (ClickService._pure / SpeedService._pure와 같은 패턴)
SpeedRequestService._pure = {
	newRequestState = newRequestState,
	takeSlot = takeSlot,
	takeDropLog = takeDropLog,
	buildApplied = buildApplied,
	REQUEST_LIMIT = REQUEST_LIMIT,
	WINDOW_SEC = WINDOW_SEC,
	DROP_LOG_QUIET_SEC = DROP_LOG_QUIET_SEC,
}

-- ===== 공개 API (Player 상태 보관) =====================================================

local states: { [Player]: RequestState } = {}
local initialized = false

local function getState(player: Player): RequestState
	local state = states[player]
	if state == nil then
		state = newRequestState()
		states[player] = state
	end
	return state
end

-- 관측용 누적 집계. 상시 유지 대상이다 (Bootstrap VERIFY print가 이걸 읽는다).
--
-- 왜 필요한가: 이 채널에는 UI가 없어서(Phase 6) 요청 경로가 실제로 도는지 확인할
-- 화면상의 흔적이 아무 데도 없다. 배선이 통째로 끊겨도 캐릭터는 최대속도로 멀쩡히
-- 걸어다니므로 증상이 나타나지 않는다 — SpeedService의 WalkSpeed print가 있어야 했던
-- 것과 같은 종류의 사각이다.
--   applied  setCustomSpeed까지 도달한 요청 수 (거부 포함. 채널이 살아 있다는 증거)
--   dropped  윈도우 상한에 걸려 폐기된 요청 수
--   last     마지막으로 실제 적용된 속도. 0이면 아직 한 번도 도달하지 않았다
export type RequestStats = {
	applied: number,
	dropped: number,
	last: number,
}

local stats: { [Player]: RequestStats } = {}

local function getStatsEntry(player: Player): RequestStats
	local entry = stats[player]
	if entry == nil then
		entry = { applied = 0, dropped = 0, last = 0 }
		stats[player] = entry
	end
	return entry
end

-- 이 플레이어의 요청 경로 집계. 한 번도 요청이 없었으면 전부 0이다.
function SpeedRequestService.getStats(player: Player): RequestStats
	local entry = getStatsEntry(player)
	-- 복사본을 준다. 호출자가 집계를 고칠 수 있으면 관측 지점이 관측 대상을 바꾼다.
	return { applied = entry.applied, dropped = entry.dropped, last = entry.last }
end

-- 요청 하나를 처리한다. (실제 적용된 속도, 폐기되었는가)를 돌려준다.
--
-- ⚠️ 폐기된 요청의 첫 반환값은 nil이다. 0이나 최대치 같은 그럴듯한 숫자를 돌려주면
-- 호출자가 "그 속도로 적용됐다"로 읽는다. 폐기는 아무 일도 일어나지 않은 것이고,
-- 지금 적용 중인 값을 알아내려고 여기서 reapply를 부르면 폐기 1건당 Humanoid 쓰기가
-- 생겨서 상한을 둔 이유가 사라진다.
--
-- ⚠️ requested는 검증되지 않은 클라 값이다. 타입조차 보장되지 않으므로 any로 받아
-- 그대로 SpeedService에 넘긴다 (파일 상단 "값 검증은 여기에 없다" 참고).
function SpeedRequestService.handleRequest(player: Player, requested: any): (number?, boolean)
	local now = os.clock()

	local nextState, allowed = takeSlot(getState(player), now)
	states[player] = nextState

	if not allowed then
		local entry = getStatsEntry(player)
		entry.dropped += 1

		local logState, shouldLog, dropped = takeDropLog(states[player], now)
		states[player] = logState
		if shouldLog then
			warn(string.format(
				"[SpeedRequestService] %s(%d) 요청 상한 초과 - %d건 폐기 (상한 %d회/%.0f초)",
				player.Name,
				player.UserId,
				dropped,
				REQUEST_LIMIT,
				WINDOW_SEC
			))
		end

		-- 폐기에는 응답하지 않는다 (파일 상단 "거부에도 응답한다" 참고).
		return nil, true
	end

	-- 값 검증·클램프는 전적으로 여기 안에서 일어난다. 반환값은 요청값이 아니라
	-- 서버가 정한 실제 적용값이고, 거부된 요청이면 현재 적용 중인 값이 돌아온다.
	local applied = SpeedService.setCustomSpeed(player, requested)
	local maxSpeed = SpeedService.getMaxSpeed(player)

	local entry = getStatsEntry(player)
	entry.applied += 1
	entry.last = applied

	channels.speedApplied:FireClient(player, buildApplied(applied, maxSpeed))

	return applied, false
end

-- SpeedRequest 수신을 연결한다.
--
-- ⚠️ 순서: SpeedService.init() 뒤여야 한다. 최대치 계산은 SpeedService가 하고,
-- 그쪽이 서지 않은 상태에서 요청이 들어오면 Humanoid 세팅 경로가 아직 없다.
function SpeedRequestService.init()
	if initialized then
		warn("[SpeedRequestService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	channels.speedRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		-- payload는 클라가 만든 값이다. 테이블이 아닐 수도, 필드가 없을 수도 있다.
		-- 꺼낸 값의 검사는 SpeedService가 한다 — 여기서 미리 거르지 말 것.
		local raw = if type(payload) == "table" then payload.speed else nil
		SpeedRequestService.handleRequest(player, raw)
	end)

	-- 나간 플레이어 참조 정리 (ClickService.states / SpeedService.states와 같은 이유).
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
		stats[player] = nil
	end)

	print(string.format(
		"[SpeedRequestService] 속도 요청 수신 시작 (상한 %d회/%.0f초)",
		REQUEST_LIMIT,
		WINDOW_SEC
	))
end

return SpeedRequestService

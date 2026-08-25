--!strict
-- 클릭 입력 → 힘 증가. 이 프로젝트 최초의 클라→서버 경로를 받는 쪽이다.
--
-- 하는 일:
--   1. 클라가 배치로 보낸 클릭 수를 받는다 (ClickInput 채널)
--   2. 슬라이딩 윈도우로 초당 상한을 넘는 분을 버린다
--   3. 통과분 × PadService.getClickPower(player) 만큼 힘을 올린다
--   4. 버려진 분이 있으면 ClickRejected로 알린다 (억제됨)
--
-- ===== 판정은 전부 서버다 (CLAUDE.md 3) ================================================
--
-- 클라는 "몇 번 눌렀다"까지만 말한다. 그 값조차 주장이지 사실이 아니다 —
-- 타입·범위를 다시 재고(sanitizeCount), 빈도를 윈도우로 자른다(applyClicks).
-- 힘 증가량은 payload에 없다. 서버가 그 플레이어의 현재 패드에서 직접 구한다.
--
-- ===== 힘 증감은 CurrencyService만 통과한다 (CLAUDE.md 2) ==============================
--
-- strength는 CurrencyService.CURRENCIES에 이미 있다(strength / blox 둘뿐). 여기서
-- profile.Data.strength를 직접 건드리는 코드를 절대 만들지 말 것.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CurrencyService = require(script.Parent.CurrencyService)
local PadService = require(script.Parent.PadService)

type BigNumber = BigNum.BigNumber

local ClickService = {}

-- 채널은 모듈 로드 시 한 번 확보한다 (ChallengeService와 같은 패턴).
-- getServer()는 없으면 만들고 있으면 그것을 주므로 여러 서비스가 각자 불러도 안전하다.
local channels = Remotes.getServer()

-- ===== 수동 클릭 상한 (⚠️ 밸런스 튜닝값이 아니다) ======================================
--
-- 이 값은 **오토마우스 방어선**이다. 게임 난이도를 맞추려고 정한 숫자가 아니다.
--
-- 왜 필요한가: 오토마우스는 게임 밖에서 도는 프로그램이라 OS가 만든 진짜 마우스 입력을
-- 넣는다. 서버 입장에서 사람이 누른 것과 완전히 동일해서 입력만 봐서는 구분할 수단이
-- 아예 없다. 구분이 불가능하므로 남는 방법은 "사람이 낼 수 있는 속도 이상은 받지 않는다"
-- 하나뿐이고, 그 선이 이 상수다.
--
-- 이 선이 없으면 자동 클리커 게임패스 두 개(일반 15회/초 49로벅스, OP 30회/초 89로벅스)가
-- 통째로 무의미해진다. 오토마우스로 30회/초를 공짜로 낼 수 있는데 89로벅스를 낼 이유가
-- 없기 때문이다. 즉 이 값은 수익 모델 자체를 떠받치고 있다.
--
-- ⚠️ 그래서 "체감이 답답하다", "10은 너무 낮다" 같은 이유로 올리면 안 된다. 올리는
--    만큼 게임패스의 가치가 깎이고, 상한을 15 이상으로 올리는 순간 일반 자동 클리커는
--    팔 물건이 없어진다. 클릭이 답답하면 상한이 아니라 패드 파워(ClickPadConfig)를
--    조정하는 것이 맞다 — 그쪽이 밸런스 축이다.
local MANUAL_CLICK_LIMIT = 10

-- 상한을 재는 창의 길이(초). "초당 10회"의 그 '초'다.
local WINDOW_SEC = 1.0

-- 클라가 한 배치에 담을 수 있는 최대 클릭 수.
-- ⚠️ 이건 밸런스도 방어선도 아니고 위생 가드다. 실질 판정은 전적으로 윈도우가 한다 —
-- 클라가 count = 1e9를 보내도 통과분은 그 순간 윈도우에 남은 자리(최대 10)뿐이다.
-- 그럼에도 자르는 이유는 터무니없는 값으로 루프를 돌거나 산술을 하지 않기 위해서다.
-- 정상 클라의 한 배치는 SEND_PERIOD(0.2초) × 10회/초 = 2회 안팎이라 20은 충분히 넉넉하다.
local MAX_BATCH_COUNT = MANUAL_CLICK_LIMIT * 2

-- ClickRejected 통지를 다시 보내기까지의 최소 간격(초).
-- 상한에 걸린 유저는 손을 멈출 때까지 계속 걸려 있다. 버려질 때마다 보내면 초당 수십 번
-- FireClient가 되어 통지 자체가 부하가 된다 — 막으려던 것과 같은 종류의 낭비다.
-- PadService의 NOTIFY_QUIET_SEC이 같은 이유로 있는 선례다.
-- 1초인 이유: 이 통지의 용도는 "지금 상한에 걸려 있다"는 상태 표시(Phase 6 안내 문구)라
-- 한 번 뜬 뒤에는 갱신이 잦을 이유가 없다. 그 사이 버려진 수는 dropped에 누적해서 보낸다.
local REJECT_NOTIFY_SEC = 1.0

-- 호출 경로 태그. ChallengeService.advance/cashout의 source 패턴과 같은 목적이다.
--
-- ⚠️ Phase 8 자동 클리커가 붙는 자리가 여기다. 자동 클릭도 결국 "클릭 N회 처리"이므로
-- 같은 processClicks를 탄다. 다만 상한 검사는 **수동 경로에만** 적용된다:
--   - 수동은 클라가 보낸 입력이다 → 검증 대상이고 오토마우스 방어선이 필요하다
--   - 자동은 서버가 스스로 도는 루프다 → 클라 입력이 아니라 검증할 것이 없고,
--     상한도 다르다(게임패스 등급별 15 / 30회/초). 그 속도는 루프 주기가 정한다
--
-- 이 구분이 안전한 이유: 클라가 도달할 수 있는 유일한 입구는 아래 OnServerEvent
-- 핸들러 하나이고, 거기서 source는 SOURCE_MANUAL로 **고정**된다. 클라는 source를
-- 보내지 않으므로 상한 없는 경로를 스스로 고를 수단이 없다.
-- ⚠️ 나중에 source를 payload에서 읽게 바꾸면 그 순간 이 방어선이 통째로 뚫린다.
ClickService.SOURCE_MANUAL = "manual"
local SOURCE_MANUAL = ClickService.SOURCE_MANUAL

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================
--
-- ⚠️ 클릭 "횟수"와 타임스탬프는 raw number로 다룬다. BigNum 대상이 아니다 —
-- 횟수는 상한(10) 때문에 절대 커질 수 없고 os.clock()은 초 단위 실수다. 둘 다 게임
-- 수치가 아니다. 게임 수치가 되는 지점은 computeGain 하나뿐이고, 거기서 즉시 BigNum으로
-- 넘어간다. 힘은 10^2000까지 커지므로 그 뒤로는 raw 산술이 한 번도 없어야 한다.

export type ClickState = {
	-- 통과시킨 클릭의 처리 시각들. 항상 MANUAL_CLICK_LIMIT개 이하다.
	times: { number },
	lastRejectNotifyAt: number,
	droppedSinceNotify: number,
}

local function newClickState(): ClickState
	return {
		times = {},
		lastRejectNotifyAt = 0,
		droppedSinceNotify = 0,
	}
end

-- 클라가 보낸 count를 신뢰 가능한 정수로 접는다. 통과 못 하면 0(= 처리할 것 없음)이다.
-- nan은 raw ~= raw로, inf는 (inf % 1)이 nan이라 정수 검사에서 함께 걸러진다.
local function sanitizeCount(raw: any): number
	if type(raw) ~= "number" or raw ~= raw or raw % 1 ~= 0 or raw < 1 then
		return 0
	end
	if raw > MAX_BATCH_COUNT then
		return MAX_BATCH_COUNT
	end
	return raw
end

-- 클릭 한 배치를 윈도우에 통과시켜 (새 상태, 통과 수, 버린 수)를 돌려준다.
-- 상태를 제자리에서 고치지 않는다 (PadService.applyTouch와 같은 규약).
--
-- ⚠️ 타임스탬프는 전부 서버가 받은 시각(now)이다. 클라가 "언제 눌렀는지"를 보내오더라도
-- 쓰지 않는다 — 시각을 클라가 정할 수 있으면 과거로 흩뿌려서 윈도우를 무한히 비울 수 있다.
-- 한 배치가 같은 시각을 공유하는 것은 그래서 의도된 동작이다.
local function applyClicks(state: ClickState, count: number, now: number): (ClickState, number, number)
	-- 창 밖으로 나간 기록을 버린다. 남는 개수가 곧 지금 차 있는 양이다.
	local times: { number } = {}
	for _, t in ipairs(state.times) do
		if now - t < WINDOW_SEC then
			table.insert(times, t)
		end
	end

	local room = MANUAL_CLICK_LIMIT - #times
	if room < 0 then
		room = 0
	end

	local accepted = if count < room then count else room
	local rejected = count - accepted

	for _ = 1, accepted do
		table.insert(times, now)
	end

	return {
		times = times,
		lastRejectNotifyAt = state.lastRejectNotifyAt,
		droppedSinceNotify = state.droppedSinceNotify + rejected,
	}, accepted, rejected
end

-- 상한을 재지 않고 전부 통과시킨다 (자동 클리커 경로용, Phase 8).
-- 윈도우 기록도 남기지 않는다 — 자동 클릭이 창을 채우면 그 직후의 수동 클릭이 자기
-- 상한에 못 미치는데도 막힌다. 두 경로는 서로의 예산을 잡아먹지 않아야 한다.
local function passAll(state: ClickState, count: number): (ClickState, number, number)
	return state, count, 0
end

-- 힘 증가량 = 통과 횟수 × 현재 패드 파워.
-- ⚠️ 반드시 BigNum으로 곱한다. 패드 24는 파워가 8.39e6이고 환생·게임패스 배수가 붙으면
-- 그 위로 더 간다. raw number로 곱하면 언젠가 조용히 정밀도가 깨진다 (CLAUDE.md 1).
local function computeGain(padPower: BigNumber, accepted: number): BigNumber
	if accepted <= 0 then
		return BigNum.new(0, 0)
	end
	return BigNum.mul(padPower, BigNum.fromNumber(accepted))
end

-- 지금 ClickRejected를 보내도 되는지 판단하고, 보낸다면 그 사실을 상태에 기록한다.
-- (새 상태, 보낼지, 직전 통지 이후 버려진 총량)을 돌려준다.
local function takeRejectNotice(state: ClickState, now: number): (ClickState, boolean, number)
	if state.droppedSinceNotify <= 0 then
		return state, false, 0
	end
	if (now - state.lastRejectNotifyAt) < REJECT_NOTIFY_SEC then
		return state, false, 0
	end

	local dropped = state.droppedSinceNotify
	return {
		times = state.times,
		lastRejectNotifyAt = now,
		droppedSinceNotify = 0,
	}, true, dropped
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- (PadService._pure / BlockService._pure와 같은 패턴)
ClickService._pure = {
	newClickState = newClickState,
	sanitizeCount = sanitizeCount,
	applyClicks = applyClicks,
	passAll = passAll,
	computeGain = computeGain,
	takeRejectNotice = takeRejectNotice,
	MANUAL_CLICK_LIMIT = MANUAL_CLICK_LIMIT,
	WINDOW_SEC = WINDOW_SEC,
	MAX_BATCH_COUNT = MAX_BATCH_COUNT,
	REJECT_NOTIFY_SEC = REJECT_NOTIFY_SEC,
}

-- ===== 공개 API (Player 상태 보관) =====================================================

local states: { [Player]: ClickState } = {}
local initialized = false

-- 나간 플레이어 참조 정리 (PadService.states와 같은 이유).
Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
end)

local function getState(player: Player): ClickState
	local state = states[player]
	if state == nil then
		state = newClickState()
		states[player] = state
	end
	return state
end

-- 클릭 count회를 처리한다. (통과 수, 버린 수)를 돌려준다.
--
-- source == SOURCE_MANUAL이면 상한 검사를 받고, 그 외(자동 클리커 등)는 전부 통과한다.
-- 판정 근거는 위 SOURCE_MANUAL 주석에 있다.
function ClickService.processClicks(player: Player, count: number, source: string?): (number, number)
	local src = if type(source) == "string" and #source > 0 then source else "unknown"

	if count <= 0 then
		return 0, 0
	end

	local state = getState(player)
	local now = os.clock()

	local nextState: ClickState, accepted: number, rejected: number
	if src == SOURCE_MANUAL then
		nextState, accepted, rejected = applyClicks(state, count, now)
	else
		nextState, accepted, rejected = passAll(state, count)
	end
	states[player] = nextState

	if accepted > 0 then
		local gain = computeGain(PadService.getClickPower(player), accepted)
		-- 실패해도(프로필 미로드 등) 윈도우는 되돌리지 않는다. 윈도우가 재는 것은
		-- "입력이 얼마나 빨리 들어왔는가"이지 "지급이 성공했는가"가 아니다.
		-- CurrencyService가 실패 사유를 자체 warn으로 남긴다.
		CurrencyService.add(player, "strength", gain, "click_" .. src)
	end

	if rejected > 0 then
		local noticeState, shouldNotify, dropped = takeRejectNotice(states[player], now)
		states[player] = noticeState
		if shouldNotify then
			local payload: Remotes.ClickRejectedPayload = {
				limitPerSec = MANUAL_CLICK_LIMIT,
				dropped = dropped,
			}
			channels.clickRejected:FireClient(player, payload)
		end
	end

	return accepted, rejected
end

-- ClickInput 수신을 연결한다.
function ClickService.init()
	if initialized then
		warn("[ClickService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	channels.clickInput.OnServerEvent:Connect(function(player: Player, payload: any)
		-- payload는 클라가 만든 값이다. 테이블이 아닐 수도, 필드가 없을 수도 있다.
		local raw = if type(payload) == "table" then payload.count else nil
		local count = sanitizeCount(raw)
		if count <= 0 then
			return
		end

		-- ⚠️ source는 여기서 고정된다. payload에서 읽지 말 것 (위 SOURCE_MANUAL 주석).
		ClickService.processClicks(player, count, SOURCE_MANUAL)
	end)

	print(string.format(
		"[ClickService] 클릭 수신 시작 (수동 상한 %d회/%.0f초, 배치 상한 %d)",
		MANUAL_CLICK_LIMIT,
		WINDOW_SEC,
		MAX_BATCH_COUNT
	))
end

return ClickService

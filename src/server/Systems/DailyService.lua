--!strict
-- 일일 보상 서버 (지시서 #20 D1 ~ D5 — DESIGN.md 9장 "일일 보상"). 판정은 Shared/DailyLogic(순수), 보상표는 Shared/Config/DailyRewardConfig,
-- 지급은 RewardService(전부 아니면 0). 이 파일은 "오늘"을 정하고 · 요청 채널을 받고 · 기록(daily)을 쓴다.
--
-- ===== 오늘 =============================================================================
--
--   오늘 = DayClock.dayNumber(os.time()) + 날짜 오프셋. 서버 시계만 쓴다(절대 규칙 3 — 클라 시간 신뢰 금지)
--   날짜 오프셋 = Bootstrap TEST_DAY_OFFSET(Studio 전용, 기본 nil). **Mock 프리셋과 함께일 때만** 켜진다 — 실제 프로필에 가짜 날짜를 남기지 않는다.
--   Studio가 아니거나 · 프리셋이 없거나 · 정수가 아니면 무시하고 경고한다(resolveOffset). 커밋 값 nil은 DailyServiceTests가 잰다
--
-- ===== 받기 (DailyRequest "claim") ==========================================================
--
--   1. 빈도         플레이어당 REQUEST_MIN_INTERVAL_SEC에 1회 → rate_limited
--   2. 형태         action ~= "claim" → invalid
--   3. 프로필       없으면 no_profile
--   4. 오늘 받았나   DailyLogic.status → already_claimed
--   5. 지급         RewardService.grant(그 칸 보상, "daily_day<n>") — 거부면 그 사유(storage_full 등) · 기록을 바꾸지 않는다
--                   (그날 안에 보관함을 비우면 다시 받을 수 있다 — D4. 날이 바뀌면 DailyLogic이 1일로 돌린다)
--   6. 기록         daily = {streak = 칸, lastClaimDay = 오늘} — 지급과 같은 프로필 표라 함께 저장된다
-- 창을 여는 것만으로는 아무것도 쓰지 않는다(기록은 6에서만).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayClock = require(ReplicatedStorage.Shared.DayClock)
local DailyLogic = require(ReplicatedStorage.Shared.DailyLogic)
local DailyRewardConfig = require(ReplicatedStorage.Shared.Config.DailyRewardConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)

local DailyService = {}

DailyService.REASON_RATE_LIMITED = "rate_limited"
DailyService.REASON_INVALID = "invalid"
DailyService.REASON_NO_PROFILE = "no_profile"
DailyService.REASON_ALREADY_CLAIMED = "already_claimed"

export type Summary = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number,
	streak: number,
	secondsToReset: number,
	today: number,
}

local function idleSummary(): Summary
	return { canClaim = false, claimedToday = false, day = 1, streak = 0, secondsToReset = 0, today = 0 }
end

-- 날짜 오프셋을 켜도 되는가. 돌려주는 값: (오프셋 — 꺼지면 0, 로그 한 줄 또는 nil, "warn" | "print" | nil)
function DailyService.resolveOffset(requested: any, isStudio: boolean, mockPreset: string?): (number, string?, string?)
	if requested == nil then
		return 0, nil, nil
	end
	if not isStudio then
		return 0, string.format("[DailyService] ERROR Studio가 아닌데 TEST_DAY_OFFSET(%s)이 켜져 있다 — 무시한다. Bootstrap의 TEST_DAY_OFFSET을 nil로 되돌릴 것",
			tostring(requested)), "warn"
	end
	if type(requested) ~= "number" or requested ~= requested or requested % 1 ~= 0 or math.abs(requested) > 3650 then
		return 0, string.format("[DailyService] ERROR TEST_DAY_OFFSET(%s)은 정수(일)여야 한다 — 무시한다", tostring(requested)), "warn"
	end
	if mockPreset == nil then
		return 0, string.format("[DailyService] ⚠️ TEST_DAY_OFFSET(%d)은 Mock 프리셋(TEST_PRESET)과 함께만 켜진다 — 실제 프로필이라 무시한다", requested), "warn"
	end
	return requested, string.format("[DailyService] ⚠️ TEST_DAY_OFFSET %+d일 — Mock 프리셋 %s에서만. 서버 \"오늘\"에 더한다", requested, mockPreset), "print"
end

export type Deps = {
	now: () -> number, -- os.time
	dayOffset: number,
	getData: (Player) -> any?,
	grant: (Player, any, string) -> (boolean, any),
	notify: (Player) -> (),
	send: (Player, Remotes.DailyResultPayload) -> (),
}

local function createRuntime(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local runtime = {}

	function runtime.today(): number
		return DayClock.dayNumber(deps.now()) + deps.dayOffset
	end

	function runtime.summary(player: Player): Summary
		local data = deps.getData(player)
		if type(data) ~= "table" then
			return idleSummary()
		end
		local today = runtime.today()
		local st = DailyLogic.status(data.daily, today)
		return {
			canClaim = st.canClaim,
			claimedToday = st.claimedToday,
			day = st.day,
			streak = st.shownStreak,
			secondsToReset = DayClock.secondsToNextDay(deps.now()),
			today = today,
		}
	end

	-- 받기. (성공, 사유 — 성공이면 nil, 받은 칸 — 거부면 0)
	function runtime.claim(player: Player): (boolean, string?, number)
		local data = deps.getData(player)
		if type(data) ~= "table" then
			return false, DailyService.REASON_NO_PROFILE, 0
		end
		local today = runtime.today()
		local st = DailyLogic.status(data.daily, today)
		if not st.canClaim then
			return false, DailyService.REASON_ALREADY_CLAIMED, 0
		end
		local ok, value = deps.grant(player, DailyRewardConfig.DAYS[st.day], string.format("daily_day%d", st.day))
		if not ok then
			return false, tostring(value), 0
		end
		data.daily = DailyLogic.afterClaim(st.day, today)
		deps.notify(player)
		return true, nil, st.day
	end

	function runtime.onRequest(player: Player, payload: any, clock: number): Remotes.DailyResultPayload
		local out: Remotes.DailyResultPayload
		local last = lastAt[player]
		if last ~= nil and clock - last < DailyRewardConfig.REQUEST_MIN_INTERVAL_SEC then
			out = { ok = false, reason = DailyService.REASON_RATE_LIMITED, day = 0 }
		else
			lastAt[player] = clock
			if type(payload) ~= "table" or payload.action ~= "claim" then
				out = { ok = false, reason = DailyService.REASON_INVALID, day = 0 }
			else
				local ok, reason, day = runtime.claim(player)
				out = { ok = ok, reason = reason or "", day = day }
			end
		end
		deps.send(player, out)
		return out
	end

	function runtime.onRemoving(player: Player)
		lastAt[player] = nil
	end

	return runtime
end

DailyService._pure = {
	createRuntime = createRuntime,
	idleSummary = idleSummary,
}

local live: any = nil
local requestedOffset: any = nil
local registered = false

-- 테스트가 커밋 값(nil)을 확인하는 통로(TestPresetGate.register와 같은 방식).
function DailyService.isRegistered(): boolean
	return registered
end

function DailyService.getRequestedOffset(): any
	return requestedOffset
end

-- 상태 요약(PlayerStateService). init 전 · 프로필 없음이면 받을 것 없음.
function DailyService.summary(player: Player): Summary
	if live == nil then
		return idleSummary()
	end
	return live.summary(player)
end

export type InitDeps = {
	testDayOffset: any,
	isStudio: boolean,
	mockPreset: string?,
	getData: (Player) -> any?,
	grant: (Player, any, string) -> (boolean, any),
	notify: (Player) -> (),
}

function DailyService.init(services: InitDeps)
	if live ~= nil then
		warn("[DailyService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	requestedOffset = services.testDayOffset
	registered = true
	local offset, line, level = DailyService.resolveOffset(services.testDayOffset, services.isStudio, services.mockPreset)
	if line ~= nil then
		if level == "warn" then
			warn(line)
		else
			print(line)
		end
	end
	local channels = Remotes.getServer()
	live = createRuntime({
		now = os.time,
		dayOffset = offset,
		getData = services.getData,
		grant = services.grant,
		notify = services.notify,
		send = function(player: Player, payload: Remotes.DailyResultPayload)
			channels.dailyResult:FireClient(player, payload)
		end,
	})
	channels.dailyRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = live.onRequest(player, payload, os.clock())
		local s = live.summary(player)
		print(string.format("[DailyService] %s(%d) 받기 → ok=%s reason=%s day=%d · 연속 %d · 오늘 %d", player.Name, player.UserId, tostring(out.ok),
			out.reason, out.day, s.streak, s.today))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		live.onRemoving(player)
	end)
	-- 접속 때 한 줄(실물 확인 근거 — 자동 등장은 클라가 이 요약으로 판정한다)
	ProfileManager.onLoaded(function(player: Player)
		local s = live.summary(player)
		print(string.format("[DailyService] %s(%d) 접속 — 오늘 UTC 일 %d · 받을 수 있음=%s · 칸 %d · 받음 %d칸", player.Name, player.UserId, s.today,
			tostring(s.canClaim), s.day, s.streak))
	end)
	print(string.format("[DailyService] 일일 보상 준비 완료 (오늘 UTC 일 %d · 오프셋 %+d · 다음 리셋까지 %d초)", live.today(), offset,
		DayClock.secondsToNextDay(os.time())))
end

return DailyService

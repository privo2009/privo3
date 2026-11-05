--!strict
-- 첫 접속 안내 서버 (지시서 #20 O1 ~ O5 — DESIGN.md 9장 "첫 접속 안내"). 단계 · 완료 보상의 원본은 Shared/Config/OnboardingConfig.
--
-- ===== 단계 판정 — 서버가 이미 아는 신호 ======================================================
--
--   1 click   ClickService.onManualAccepted(받아 준 수동 클릭 수) — 세션 메모리로 더해 CLICK_TARGET이 되면 넘어간다(자동 클리커는 세지 않는다)
--   2 start   ChallengeService.onRunEvent "start"(입장 게이트 · 워프 · 자동 진행 — 런이 서는 모든 길)
--   3 cleared ChallengeService.onRunEvent "cleared"(어느 층이든 — 워프로 다른 층부터 해도 막히지 않게)
--   4 choice  ChallengeService.onRunEvent "cashout" 또는 "advance"
--   5 finish  OnboardingRequest "finish"(확인 버튼) → 완료 보상(RewardService — 전부 아니면 0) → done
-- 신호는 **지금 단계의 신호일 때만** 받는다. 순서가 어긋난 신호(1단계에서 온 "cleared" 등)는 버린다 — 단계를 건너뛰지 않는다.
-- 단계를 마칠 때마다 LogOnboardingFunnelStepEvent(player, 단계, 이름)를 분석 래퍼(Analytics.funnel — 지시서 #23 A5)로 부른다(O5 — Studio에서는 보내지지 않는다).
-- 건너뛰기(OnboardingRequest "skip"): done = true · 보상 없음 · 분석 이벤트 없음(마친 단계가 아니다). 확인 단계는 클라 창이 한 번 더 묻는다.
-- 기록은 프로필 onboarding{step, done}(O4 — 다시 들어오면 그 단계부터). 1단계 클릭 수는 저장하지 않는다(나갔다 오면 그 단계 처음부터 센다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local Analytics = require(script.Parent.Analytics)

local OnboardingService = {}

OnboardingService.REASON_RATE_LIMITED = "rate_limited"
OnboardingService.REASON_INVALID = "invalid"
OnboardingService.REASON_NO_PROFILE = "no_profile"
OnboardingService.REASON_ALREADY_DONE = "already_done"
OnboardingService.REASON_NOT_READY = "not_ready"

export type Summary = { step: number, done: boolean }

export type Deps = {
	getData: (Player) -> any?,
	grant: (Player, any, string) -> (boolean, any),
	notify: (Player) -> (),
	logFunnel: (Player, number, string) -> (),
	send: (Player, Remotes.OnboardingResultPayload) -> (),
	log: (string) -> (),
}

local function stateOf(data: any): any?
	if type(data) ~= "table" or type(data.onboarding) ~= "table" then
		return nil
	end
	local o = data.onboarding
	if type(o.step) ~= "number" or type(o.done) ~= "boolean" then
		return nil
	end
	return o
end

local function createRuntime(deps: Deps)
	local clicks: { [Player]: number } = {}
	local lastAt: { [Player]: number } = {}
	local runtime = {}

	local function complete(player: Player, o: any, step: number)
		deps.logFunnel(player, step, OnboardingConfig.STEPS[step].funnelName)
		o.step = step + 1
		deps.log(string.format("[Onboarding] %s %d단계(%s) 마침 → %d단계", player.Name, step, OnboardingConfig.STEPS[step].signal, o.step))
		deps.notify(player)
	end

	-- 서버 신호. kind = "click"(n = 받아 준 수) · 런 전이 이유("start" · "cleared" · "cashout" · "advance" · 그 밖은 무시).
	-- 넘어갔으면 true.
	function runtime.signal(player: Player, kind: string, n: number?): boolean
		local o = stateOf(deps.getData(player))
		if o == nil or o.done or o.step >= OnboardingConfig.STEP_COUNT then
			return false
		end
		local step = o.step
		local want = OnboardingConfig.STEPS[step].signal
		if want == "click" then
			if kind ~= "click" then
				return false
			end
			clicks[player] = (clicks[player] or 0) + math.max(0, math.floor(n or 0))
			if clicks[player] < OnboardingConfig.CLICK_TARGET then
				return false
			end
			clicks[player] = nil
		elseif want == "choice" then
			if kind ~= "cashout" and kind ~= "advance" then
				return false
			end
		elseif kind ~= want then
			return false
		end
		complete(player, o, step)
		return true
	end

	function runtime.summary(player: Player): Summary
		local o = stateOf(deps.getData(player))
		if o == nil then
			return { step = 1, done = true } -- 프로필 전 — 안내를 띄우지 않는다
		end
		return { step = o.step, done = o.done }
	end

	-- 요청 판정(빈도 제외). 성공이면 nil, 아니면 사유.
	local function judge(player: Player, action: string): string?
		local data = deps.getData(player)
		local o = stateOf(data)
		if o == nil then
			return OnboardingService.REASON_NO_PROFILE
		end
		if o.done then
			return OnboardingService.REASON_ALREADY_DONE
		end
		if action == "skip" then
			o.done = true
			clicks[player] = nil
			deps.log(string.format("[Onboarding] %s 건너뜀(%d단계에서) — 보상 없음", player.Name, o.step))
			deps.notify(player)
			return nil
		end
		-- finish
		if o.step < OnboardingConfig.STEP_COUNT then
			return OnboardingService.REASON_NOT_READY
		end
		local ok, value = deps.grant(player, OnboardingConfig.COMPLETE_REWARDS, "onboarding_complete")
		if not ok then
			return tostring(value)
		end
		deps.logFunnel(player, OnboardingConfig.STEP_COUNT, OnboardingConfig.STEPS[OnboardingConfig.STEP_COUNT].funnelName)
		o.done = true
		deps.log(string.format("[Onboarding] %s 다 마침 — 완료 보상 지급", player.Name))
		deps.notify(player)
		return nil
	end

	function runtime.onRequest(player: Player, payload: any, clock: number): Remotes.OnboardingResultPayload
		local action = if type(payload) == "table" and (payload.action == "finish" or payload.action == "skip") then payload.action :: string else nil
		local out: Remotes.OnboardingResultPayload
		local last = lastAt[player]
		if last ~= nil and clock - last < OnboardingConfig.REQUEST_MIN_INTERVAL_SEC then
			out = { action = action or "", ok = false, reason = OnboardingService.REASON_RATE_LIMITED }
		else
			lastAt[player] = clock
			if action == nil then
				out = { action = "", ok = false, reason = OnboardingService.REASON_INVALID }
			else
				local reason = judge(player, action)
				out = { action = action, ok = reason == nil, reason = reason or "" }
			end
		end
		deps.send(player, out)
		return out
	end

	function runtime.onRemoving(player: Player)
		clicks[player] = nil
		lastAt[player] = nil
	end

	return runtime
end

OnboardingService._pure = {
	createRuntime = createRuntime,
}

local live: any = nil

function OnboardingService.summary(player: Player): Summary
	if live == nil then
		return { step = 1, done = true }
	end
	return live.summary(player)
end

-- 분석 이벤트(O5). 실패는 게임 동작에 영향 없이 로그 한 줄만(Studio에서는 보내지지 않는다 — 공식 funnel-events 문서).
local function logFunnel(player: Player, step: number, name: string)
	-- 래퍼 하나로(지시서 #23 A5) — pcall · 상한 · 결과 줄은 Analytics가 맡는다
	Analytics.funnel(player, step, name)
end

export type InitDeps = {
	getData: (Player) -> any?,
	grant: (Player, any, string) -> (boolean, any),
	notify: (Player) -> (),
	onRunEvent: ((Player, string, number) -> ()) -> (),
	onManualAccepted: ((Player, number) -> ()) -> (),
}

function OnboardingService.init(services: InitDeps)
	if live ~= nil then
		warn("[OnboardingService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	local channels = Remotes.getServer()
	live = createRuntime({
		getData = services.getData,
		grant = services.grant,
		notify = services.notify,
		logFunnel = logFunnel,
		send = function(player: Player, payload: Remotes.OnboardingResultPayload)
			channels.onboardingResult:FireClient(player, payload)
		end,
		log = print,
	})
	services.onRunEvent(function(player: Player, reason: string)
		live.signal(player, reason)
	end)
	services.onManualAccepted(function(player: Player, accepted: number)
		live.signal(player, "click", accepted)
	end)
	channels.onboardingRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = live.onRequest(player, payload, os.clock())
		print(string.format("[Onboarding] %s(%d) 요청 %s → ok=%s reason=%s", player.Name, player.UserId, out.action, tostring(out.ok), out.reason))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		live.onRemoving(player)
	end)
	ProfileManager.onLoaded(function(player: Player)
		local st = live.summary(player)
		print(string.format("[Onboarding] %s(%d) 접속 — step=%d done=%s", player.Name, player.UserId, st.step, tostring(st.done)))
	end)
	print(string.format("[OnboardingService] 첫 접속 안내 준비 완료 (%d단계 · 클릭 %d회)", OnboardingConfig.STEP_COUNT, OnboardingConfig.CLICK_TARGET))
end

return OnboardingService

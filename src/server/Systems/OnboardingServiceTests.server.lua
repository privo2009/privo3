--!strict
-- 첫 접속 안내 검증 (지시서 #20 단계 6 — O1 ~ O5). OnboardingService 런타임(가짜 deps) · RewardService 런타임 · OnboardingConfig.
-- 실제 프로필 · 실제 분석 이벤트를 건드리지 않는다(logFunnel은 기록만 한다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local OnboardingService = require(script.Parent.OnboardingService)
local RewardService = require(script.Parent.RewardService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ChallengeService = require(script.Parent.ChallengeService)
local ClickService = require(script.Parent.ClickService)
local Schema = require(script.Parent.Parent.Data.Schema)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local A: any = { Name = "A", UserId = 1 }
local N = OnboardingConfig.STEP_COUNT

local function world(data: any?)
	local w: any = { funnel = {}, sent = {}, notified = 0 }
	w.data = data or Schema.new()
	w.reward = RewardService._pure.createRuntime({
		getData = function()
			return w.data
		end,
		addBlox = function()
			return true
		end,
		petRoom = function()
			return 10
		end,
		grantPet = function()
			return true
		end,
		notify = function() end,
		log = function() end,
	})
	w.rt = OnboardingService._pure.createRuntime({
		getData = function()
			return w.data
		end,
		grant = function(p, rewards, src)
			return w.reward.grant(p, rewards, src)
		end,
		notify = function()
			w.notified += 1
		end,
		logFunnel = function(_, step, name)
			table.insert(w.funnel, { step = step, name = name })
		end,
		send = function(_, payload)
			table.insert(w.sent, payload)
		end,
		log = function() end,
	})
	return w
end

-- 1. 단계마다 신호 → 다음 단계 ------------------------------------------------------------------------------
do
	local w = world()
	check("새 프로필: 1단계 · 끝나지 않음", w.rt.summary(A).step == 1 and not w.rt.summary(A).done)
	w.rt.signal(A, "click", 4)
	check("1단계: 클릭 4회로는 그대로", w.data.onboarding.step == 1)
	local moved = w.rt.signal(A, "click", OnboardingConfig.CLICK_TARGET - 4)
	check("1단계: 합 10회 → 2단계 · 분석 이벤트(1, 이름) · 통지", moved and w.data.onboarding.step == 2 and w.funnel[1].step == 1
		and w.funnel[1].name == OnboardingConfig.STEPS[1].funnelName and w.notified == 1)
	check("2단계: 런 시작 → 3단계", w.rt.signal(A, "start") and w.data.onboarding.step == 3)
	check("3단계: 층 클리어 → 4단계", w.rt.signal(A, "cleared") and w.data.onboarding.step == 4)
	check("4단계: 수령 → 5단계 · 분석 이벤트 1 ~ 4 차례", w.rt.signal(A, "cashout") and w.data.onboarding.step == 5 and #w.funnel == 4
		and w.funnel[2].step == 2 and w.funnel[3].step == 3 and w.funnel[4].step == 4)
	check("5단계: 신호로는 넘어가지 않는다(확인 버튼만)", not w.rt.signal(A, "cashout") and not w.rt.signal(A, "click", 50) and w.data.onboarding.step == 5)
	local before = w.data.potions.strength
	local out = w.rt.onRequest(A, { action = "finish" }, 1)
	check("5단계 확인 → 끝남 · 완료 보상 힘 포션 1 · 분석 이벤트 5", out.ok and w.data.onboarding.done and w.data.potions.strength == before + 1
		and #w.funnel == 5 and w.funnel[5].step == N)
	local again = w.rt.onRequest(A, { action = "finish" }, 2)
	check("완료 보상은 1회 — 다시 finish → already_done · 보관함 그대로", not again.ok and again.reason == OnboardingService.REASON_ALREADY_DONE
		and w.data.potions.strength == before + 1)
	check("끝난 뒤 신호는 무시", not w.rt.signal(A, "click", 99) and #w.funnel == 5)
end
do
	local w = world()
	w.data.onboarding.step = 4
	check("4단계: 진행(advance)으로도 넘어간다", w.rt.signal(A, "advance") and w.data.onboarding.step == 5)
end

-- 2. 순서가 어긋난 신호는 버린다(Claude 결정 — DESIGN 9장) --------------------------------------------------------
do
	local w = world()
	check("1단계에서 온 cleared · start · cashout은 버린다", not w.rt.signal(A, "cleared") and not w.rt.signal(A, "start")
		and not w.rt.signal(A, "cashout") and w.data.onboarding.step == 1)
	w.data.onboarding.step = 2
	check("2단계에서 온 클릭 · cleared는 버린다", not w.rt.signal(A, "click", 50) and not w.rt.signal(A, "cleared") and w.data.onboarding.step == 2)
	w.data.onboarding.step = 3
	check("3단계에서 온 start · timeout · abandon은 버린다", not w.rt.signal(A, "start") and not w.rt.signal(A, "timeout")
		and not w.rt.signal(A, "abandon") and w.data.onboarding.step == 3)
	local early = w.rt.onRequest(A, { action = "finish" }, 1)
	check("5단계 전 finish → not_ready · 보상 없음", not early.ok and early.reason == OnboardingService.REASON_NOT_READY and w.data.potions.strength == 0)
end

-- 3. 재접속 이어가기 · 건너뛰기 · 기존 프로필 ----------------------------------------------------------------------
do
	local w = world()
	w.rt.signal(A, "click", 7)
	w.data.onboarding.step = 3 -- 저장된 단계(다른 세션에서 3단계까지 왔다)
	local w2 = world(w.data) -- 같은 프로필 표로 세션을 다시 연다
	check("재접속: 저장된 단계부터 이어간다(3단계)", w2.rt.summary(A).step == 3 and w2.rt.signal(A, "cleared") and w.data.onboarding.step == 4)
	local w3 = world()
	w3.rt.signal(A, "click", 7)
	local w4 = world(w3.data)
	w4.rt.signal(A, "click", 7)
	check("재접속: 1단계 클릭 수는 세션 메모리(나갔다 오면 처음부터 — 7 + 7은 새 세션에서 7)", w3.data.onboarding.step == 1)
	w4.rt.signal(A, "click", 3)
	check("…새 세션에서 10회가 되면 넘어간다", w3.data.onboarding.step == 2)
end
do
	local w = world()
	w.data.onboarding.step = 2
	local out = w.rt.onRequest(A, { action = "skip" }, 1)
	check("건너뛰기 → 끝남 · 보상 없음 · 분석 이벤트 없음 · 통지", out.ok and w.data.onboarding.done and w.data.potions.strength == 0 and #w.funnel == 0
		and w.notified == 1)
	check("건너뛴 뒤 finish · skip → already_done", w.rt.onRequest(A, { action = "finish" }, 2).reason == OnboardingService.REASON_ALREADY_DONE
		and w.rt.onRequest(A, { action = "skip" }, 3).reason == OnboardingService.REASON_ALREADY_DONE)
end
do
	local old = Schema.new() :: any
	old.onboarding = { step = N, done = true } -- v8 마이그레이션이 끝남으로 둔 기존 프로필
	local w = world(old)
	check("기존 프로필(끝남): 요약 done · 신호 무시 · 보상 없음", w.rt.summary(A).done and not w.rt.signal(A, "click", 50)
		and w.rt.onRequest(A, { action = "finish" }, 1).reason == OnboardingService.REASON_ALREADY_DONE and old.potions.strength == 0)
end

-- 4. 요청 채널 · 설정 · 연결 ---------------------------------------------------------------------------------
do
	local w = world()
	w.rt.onRequest(A, { action = "skip" }, 1)
	local fast = w.rt.onRequest(A, { action = "skip" }, 1.1)
	check("빈도 상한 안 두 번째 → rate_limited", fast.reason == OnboardingService.REASON_RATE_LIMITED)
	local bad = w.rt.onRequest(A, { action = "next" }, 5)
	local notTable = w.rt.onRequest(A, 7, 6)
	check("모르는 action · 표 아님 → invalid", bad.reason == OnboardingService.REASON_INVALID and notTable.reason == OnboardingService.REASON_INVALID
		and bad.action == "")
	local np = world()
	np.data = nil
	check("프로필 없음 → no_profile · 요약은 끝남(안내를 띄우지 않는다)", np.rt.onRequest(A, { action = "skip" }, 1).reason == OnboardingService.REASON_NO_PROFILE
		and np.rt.summary(A).done)
	check("OnboardingConfig.validate · 5단계 = Schema.LIMITS.ONBOARDING_STEPS · 클릭 10 · 완료 보상 힘 포션 1", OnboardingConfig.validate()
		and N == Schema.LIMITS.ONBOARDING_STEPS and OnboardingConfig.CLICK_TARGET == 10 and OnboardingConfig.COMPLETE_REWARDS[1].kind == "strength"
		and OnboardingConfig.COMPLETE_REWARDS[1].count == 1)
	check("신호 훅이 있다(ChallengeService.onRunEvent · ClickService.onManualAccepted)", type(ChallengeService.onRunEvent) == "function"
		and type(ClickService.onManualAccepted) == "function")
	local pure = PlayerStateService._pure
	local data = Schema.new() :: any
	local a = pure.buildSnapshot(data, 16, 16, 1, nil, nil, nil, nil, { step = 2, done = false })
	local b = pure.buildSnapshot(data, 16, 16, 1, nil, nil, nil, nil, { step = 3, done = false })
	check("PlayerState: onboarding 요약을 싣는다 · 단계가 바뀌면 다르다 · 없으면 끝남", a.onboarding.step == 2 and not pure.snapshotsEqual(a, b)
		and pure.buildSnapshot(data, 16, 16, 1).onboarding.done == true)
end

print(string.format("[OnboardingServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[OnboardingServiceTests] %d test(s) failed", failed))
end

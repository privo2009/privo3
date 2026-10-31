--!strict
-- 첫 접속 안내 단계 (지시서 #20 O1 ~ O5 — DESIGN.md 9장 "첫 접속 안내"). 수치 · 단계의 원본은 이 파일이다.
--
--   STEPS[n]  n단계 — signal = 서버가 이미 아는 신호(OnboardingService가 받는다), funnelName = 분석 이벤트 단계 이름(O5 — 화면 글자가 아니다)
--             1 클릭 10회(수동 · ClickService가 받아 준 수) / 2 런 시작 / 3 층 클리어 / 4 첫 수령 또는 첫 진행 / 5 확인 버튼
--   화면 글자는 Strings "onboarding.step.<n>"(Locale.t) — 여기 두지 않는다
--   단계 수는 Schema.LIMITS.ONBOARDING_STEPS와 같아야 한다(테스트가 대조한다 — Schema는 Config를 모른다)

local RewardLogic = require(script.Parent.Parent.RewardLogic)

export type Step = { signal: string, funnelName: string }

local OnboardingConfig = {}

OnboardingConfig.STEPS = {
	{ signal = "click", funnelName = "ClickToGrowPower" },
	{ signal = "start", funnelName = "PassEntranceGate" },
	{ signal = "cleared", funnelName = "ClearFirstFloor" },
	{ signal = "choice", funnelName = "CashoutOrAdvance" }, -- 수령("cashout") 또는 진행("advance")
	{ signal = "finish", funnelName = "PadsAndRebirth" }, -- 확인 버튼(OnboardingRequest finish)
} :: { Step }

OnboardingConfig.STEP_COUNT = #OnboardingConfig.STEPS
OnboardingConfig.CLICK_TARGET = 10 -- 1단계: 수동 클릭 10회(O2)
-- 다 마치면(건너뛰기 제외) 보관함에 힘 포션 1개(O3)
OnboardingConfig.COMPLETE_REWARDS = { { type = "potion", kind = "strength", count = 1 } } :: { RewardLogic.Reward }
OnboardingConfig.REQUEST_MIN_INTERVAL_SEC = 0.5 -- 다른 Request 서비스와 같은 꼴

function OnboardingConfig.validate(): boolean
	assert(OnboardingConfig.STEP_COUNT == 5, "OnboardingConfig: 안내는 5단계(O2)")
	assert(OnboardingConfig.STEPS[OnboardingConfig.STEP_COUNT].signal == "finish", "OnboardingConfig: 마지막 단계는 확인 버튼")
	assert(OnboardingConfig.CLICK_TARGET >= 1 and OnboardingConfig.CLICK_TARGET % 1 == 0, "OnboardingConfig: CLICK_TARGET은 1 이상 정수")
	assert(RewardLogic.isValidList(OnboardingConfig.COMPLETE_REWARDS), "OnboardingConfig: 완료 보상 형식이 틀림")
	local seen = {}
	for i, step in ipairs(OnboardingConfig.STEPS) do
		assert(type(step.funnelName) == "string" and #step.funnelName > 0 and not seen[step.funnelName],
			string.format("OnboardingConfig: %d단계 funnelName이 비었거나 겹침", i))
		seen[step.funnelName] = true
	end
	return true
end

return OnboardingConfig

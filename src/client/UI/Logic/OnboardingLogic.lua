--!strict
-- 첫 접속 안내 띠 · 3D 빛기둥 판정 (지시서 #20 O1 ~ O3 — DESIGN.md 9장 "첫 접속 안내"). 순수 모듈 — 화면은
-- Screens/Overlay/OnboardingBand, 3D는 World/OnboardingPointer.client.
--
-- 단계 · 끝남은 서버 원본(PlayerState onboarding)이다. 클라는 보여 주기만 한다 — 단계를 넘기는 것은 서버 신호(클릭 · 런 전이)와
-- OnboardingRequest(finish · skip)뿐이다. 건너뛰기는 두 번 누름(ConfirmFlow — 다른 창의 확인 단계와 같은 꼴, O3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local ConfirmFlow = require(script.Parent.ConfirmFlow)

local OnboardingLogic = {}

OnboardingLogic.SKIP_CONFIRM_SEC = 5
OnboardingLogic.PENDING_TIMEOUT_SEC = 3

export type View = {
	visible: boolean,
	step: number,
	text: string,
	progress: string,
	showFinish: boolean, -- 5단계: 확인 버튼
	finishText: string,
	skipText: string,
}

local function readStep(onboarding: any): (number, boolean)
	local o = if type(onboarding) == "table" then onboarding else {}
	local done = if type(o.done) == "boolean" then o.done else true
	local step = if type(o.step) == "number" and o.step == o.step then math.clamp(math.floor(o.step), 1, OnboardingConfig.STEP_COUNT) else 1
	return step, done
end

-- 띠 표시 값. 끝났으면 숨긴다. skipArmed = 건너뛰기를 한 번 눌러 확인을 기다리는 중.
function OnboardingLogic.view(onboarding: any, skipArmed: boolean): View
	local step, done = readStep(onboarding)
	return {
		visible = not done,
		step = step,
		text = Locale.t("onboarding.step." .. tostring(step)),
		progress = Locale.t("onboarding.progress", { n = step, total = OnboardingConfig.STEP_COUNT }),
		showFinish = step >= OnboardingConfig.STEP_COUNT,
		finishText = Locale.t("onboarding.finish"),
		skipText = if skipArmed then Locale.t("onboarding.skipConfirm") else Locale.t("onboarding.skip"),
	}
end

-- 3D 빛기둥 자리(지면 기준 X · Z — 높이는 렌더러가 정한다). 1단계는 대상이 없다(nil — 기둥을 숨긴다).
-- runStage = 지금 런의 층(없으면 1) — 4단계 발판은 그 층의 것.
function OnboardingLogic.target(onboarding: any, runStage: number?): Vector3?
	local step, done = readStep(onboarding)
	if done then
		return nil
	end
	if step == 2 then
		local x, _, z = ArenaConfig.getEntranceGateCenter()
		return Vector3.new(x, 0, z)
	elseif step == 3 then
		return Vector3.new(ArenaConfig.getStageCenterX(math.max(1, runStage or 1)), 0, 0)
	elseif step == 4 then
		return Vector3.new(ArenaConfig.getCashoutX(math.max(1, runStage or 1)), 0, ArenaConfig.CASHOUT_LATERAL_OFFSET)
	elseif step == 5 then
		local pad = PadLayout.computeLayout(2)[2] -- 다음에 열 패드(2번) — 1번은 처음부터 열려 있다
		return Vector3.new(pad.X, 0, pad.Z)
	end
	return nil
end

function OnboardingLogic.newSkipConfirm(): ConfirmFlow.Flow
	return ConfirmFlow.new(OnboardingLogic.SKIP_CONFIRM_SEC)
end

-- 결과 → 토스트 문구(끝났을 때만). 완료 보상 글자는 Config 표(힘 포션 1)에서.
function OnboardingLogic.doneText(): string
	local r = OnboardingConfig.COMPLETE_REWARDS[1]
	return Locale.t("onboarding.done", { reward = Names.boost(r.kind :: string) .. " " .. Locale.t("daily.reward.count", { count = r.count }) })
end

return OnboardingLogic

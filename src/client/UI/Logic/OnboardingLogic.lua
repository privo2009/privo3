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
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)

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
-- economyV2(#36 — 없으면 커밋 플래그): 4단계 문장만 새 경제용(진행과 수령의 차이 — 실패하면 못 받는다)
function OnboardingLogic.view(onboarding: any, skipArmed: boolean, economyV2: boolean?): View
	local step, done = readStep(onboarding)
	local v2 = if economyV2 == nil then EconomyV2Logic.isOn() else economyV2
	return {
		visible = not done,
		step = step,
		text = Locale.t(if v2 and step == 4 then "onboarding.step.4.v2" else "onboarding.step." .. tostring(step)),
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

-- 새 경제 안내 하나를 띠에 보일 값(#36): 머리 "안내" · 문장 · 버튼 "알겠어요"
function OnboardingLogic.tipView(key: string): { progress: string, text: string, buttonText: string }
	return {
		progress = Locale.t("onboarding.tip.title"),
		text = Locale.t("onboarding.tip." .. key),
		buttonText = Locale.t("onboarding.finish"),
	}
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

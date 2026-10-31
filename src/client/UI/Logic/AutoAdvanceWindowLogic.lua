--!strict
-- 자동 진행 설정 창 · HUD 버튼 · 상태 줄의 값과 문구 (Phase 8 지시서 #18 — docs/UI.md "지시서 #18"). 순수 모듈.
--
-- 안전층 · 반복 횟수는 서버 값이다(Store "autoAdvance" — PlayerState). 창은 표시만 한다(AA5).
-- 목표층 범위 · 버튼 색은 Shared/AutoAdvanceLogic(서버와 같은 함수 — maxTarget · startKind · defaultTarget).
--   HUD 세 상태  locked(미보유 — 누르면 구매 요청) · off(보유 — 누르면 설정 창) · on(켜짐 — 누르면 중지)
--   시작 버튼    목표 ≤ 안전층 "safe"(노랑 btn_yellow · "시작 · 안전") / 넘으면 "risky"(보라 btn_purple · "시작 · 도박") — AA7

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
local AutoAdvanceConfig = require(ReplicatedStorage.Shared.Config.AutoAdvanceConfig)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local AutoAdvanceWindowLogic = {}

AutoAdvanceWindowLogic.TITLE = Locale.t("auto.window.title")
AutoAdvanceWindowLogic.NOTE_REPEAT = Locale.t("auto.note.repeat")
AutoAdvanceWindowLogic.NOTE_BOOST = Locale.t("auto.note.boost")
AutoAdvanceWindowLogic.TARGET_LABEL = Locale.t("auto.target")
AutoAdvanceWindowLogic.PURCHASE_KEY = AutoAdvanceConfig.GAMEPASS_KEY

export type Summary = { active: boolean, target: number, safeFloor: number, runs: number, maxTarget: number }

local function num(v: any, fallback: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else fallback
end

-- Store 값을 믿을 수 있는 꼴로(첫 PlayerState 전에는 기본값).
function AutoAdvanceWindowLogic.read(summary: any): Summary
	local s = if type(summary) == "table" then summary else {}
	return {
		active = s.active == true,
		target = math.floor(num(s.target, 0)),
		safeFloor = math.max(0, math.floor(num(s.safeFloor, 0))),
		runs = math.max(0, math.floor(num(s.runs, 0))),
		maxTarget = math.max(1, math.floor(num(s.maxTarget, AutoAdvanceLogic.maxTarget()))),
	}
end

function AutoAdvanceWindowLogic.owns(shop: any): boolean
	return ShopEffectsLogic.fromSummary(shop).owns(AutoAdvanceConfig.GAMEPASS_KEY)
end

function AutoAdvanceWindowLogic.hudState(summary: any, shop: any): string
	if not AutoAdvanceWindowLogic.owns(shop) then
		return "locked"
	end
	return if AutoAdvanceWindowLogic.read(summary).active then "on" else "off"
end

-- 켜져 있을 때 HUD 상태 줄. 꺼져 있으면 "".
function AutoAdvanceWindowLogic.statusText(summary: any): string
	local s = AutoAdvanceWindowLogic.read(summary)
	if not s.active then
		return ""
	end
	return Locale.t("auto.status", { target = s.target, runs = s.runs })
end

function AutoAdvanceWindowLogic.clampTarget(target: number, maxTarget: number): number
	return math.clamp(math.floor(target), AutoAdvanceLogic.FIRST_STAGE, maxTarget)
end

export type View = {
	safeText: string,
	target: number,
	targetText: string,
	canMinus: boolean,
	canPlus: boolean,
	kind: string, -- "safe" | "risky"
	startText: string,
	startColor: string, -- Button.ColorName
}

-- 창 한 장. chosen = 사람이 −/+로 고른 목표층(없으면 기본 = 안전층).
function AutoAdvanceWindowLogic.view(summary: any, chosen: number?): View
	local s = AutoAdvanceWindowLogic.read(summary)
	local target = AutoAdvanceWindowLogic.clampTarget(chosen or AutoAdvanceLogic.defaultTarget(s.safeFloor), s.maxTarget)
	local kind = AutoAdvanceLogic.startKind(target, s.safeFloor)
	return {
		safeText = if s.safeFloor >= AutoAdvanceLogic.FIRST_STAGE then Locale.t("auto.safe", { n = s.safeFloor }) else Locale.t("auto.safeNone"),
		target = target,
		targetText = Locale.t("auto.targetValue", { n = target }),
		canMinus = target > AutoAdvanceLogic.FIRST_STAGE,
		canPlus = target < s.maxTarget,
		kind = kind,
		startText = Locale.t(if kind == "safe" then "auto.start.safe" else "auto.start.risky"),
		startColor = if kind == "safe" then "yellow" else "purple",
	}
end

-- 결과 → 문구(토스트 · 창 상태 줄). 보여 줄 것이 없으면 nil.
function AutoAdvanceWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if payload.action == "stopped" then
		return AutoAdvanceWindowLogic.reasonText(tostring(payload.reason))
	end
	if payload.ok then
		return Locale.t(if payload.action == "start" then "auto.started" else "auto.stopped")
	end
	return AutoAdvanceWindowLogic.reasonText(tostring(payload.reason))
end

function AutoAdvanceWindowLogic.reasonText(code: string): string
	if code == "run_active" then
		return Locale.t("auto.reason.run_active")
	elseif code == "character_lost" then
		return Locale.t("auto.reason.character_lost")
	elseif code == "not_owned" then
		return Locale.t("auto.reason.not_owned")
	elseif code == "invalid_target" then
		return Locale.t("auto.reason.invalid_target", { max = AutoAdvanceLogic.maxTarget() })
	elseif code == "no_character" then
		return Locale.t("warp.reason.no_character")
	elseif code == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif code == "stopped" then
		return Locale.t("auto.stopped")
	elseif code == "auto_active" then
		return Locale.t("common.reason.auto_active")
	end
	return Locale.t("common.reason.failed")
end

return AutoAdvanceWindowLogic

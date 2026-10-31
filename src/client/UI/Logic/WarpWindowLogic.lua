--!strict
-- 월드·워프 창의 표시 값 · 잠김 사유 · 쪽 나누기 (Phase 6 지시서 #6). 순수 모듈 — 화면은
-- Screens/Window/WarpWindow.
--
-- 값은 원본에서 나온다: 비용 = WarpConfig.cost, 살 수 있는가 = WarpConfig.canWarp(서버 WarpService가
-- 부르는 그 함수), 층 수 = StageConfig.hasStage. 활성 런 여부(W1)는 서버 RunStateChanged에서 온다.
-- 화면 값은 안내일 뿐이고, 실제 워프 여부는 서버가 요청을 받은 순간 다시 판정한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local ConfirmFlow = require(script.Parent.ConfirmFlow)

type BigNumber = BigNum.BigNumber

local WarpWindowLogic = {}

WarpWindowLogic.PAGE_SIZE = 5 -- 한 쪽에 보이는 층 수. 시각 배치값(세션 로그)
WarpWindowLogic.CONFIRM_WINDOW_SEC = 5
WarpWindowLogic.REASON_RUN_ACTIVE = "run_active" -- 서버 WarpService.REASON_RUN_ACTIVE와 같은 문자열

function WarpWindowLogic.lastStage(): number
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		stage += 1
	end
	return stage
end

function WarpWindowLogic.pageCount(): number
	return math.ceil(WarpWindowLogic.lastStage() / WarpWindowLogic.PAGE_SIZE)
end

export type Row = {
	stage: number,
	cost: BigNumber,
	canWarp: boolean,
	reason: string?, -- 못 가면 사유 코드
}

-- 한 층의 행. 활성 런이 있으면(W1) 잔액과 상관없이 run_active로 잠근다.
function WarpWindowLogic.row(stage: number, blox: BigNumber, runActive: boolean): Row
	local cost = WarpConfig.cost(stage)
	if runActive then
		return { stage = stage, cost = cost, canWarp = false, reason = WarpWindowLogic.REASON_RUN_ACTIVE }
	end
	local ok, value = WarpConfig.canWarp(blox, stage)
	if ok then
		return { stage = stage, cost = cost, canWarp = true, reason = nil }
	end
	return { stage = stage, cost = cost, canWarp = false, reason = value }
end

-- page쪽(1부터)의 행들.
function WarpWindowLogic.rows(page: number, blox: BigNumber, runActive: boolean): { Row }
	local out = {}
	local first = (page - 1) * WarpWindowLogic.PAGE_SIZE + 1
	local last = math.min(first + WarpWindowLogic.PAGE_SIZE - 1, WarpWindowLogic.lastStage())
	for stage = first, last do
		table.insert(out, WarpWindowLogic.row(stage, blox, runActive))
	end
	return out
end

-- 창을 열 때 고를 층: 지금 갈 수 있는 가장 높은 층(가장 쓸모 있는 선택). 없으면 1층.
function WarpWindowLogic.defaultStage(blox: BigNumber): number
	local best = 1
	for stage = 1, WarpWindowLogic.lastStage() do
		if WarpConfig.canWarp(blox, stage) then
			best = stage
		end
	end
	return best
end

function WarpWindowLogic.pageOf(stage: number): number
	return math.floor((stage - 1) / WarpWindowLogic.PAGE_SIZE) + 1
end

-- 사유 코드 → 화면 문구. 코드는 WarpConfig.REASON_* · WarpService.REASON_* · "rate_limited"와 같다.
function WarpWindowLogic.reasonText(code: string): string
	if code == WarpWindowLogic.REASON_RUN_ACTIVE then
		return Locale.t("warp.reason.run_active")
	elseif code == WarpConfig.REASON_INSUFFICIENT_BLOX then
		return Locale.t("common.reason.insufficient_blox")
	elseif code == WarpConfig.REASON_INVALID_STAGE or code == WarpConfig.REASON_STAGE_OUT_OF_RANGE then
		return Locale.t("warp.reason.invalid_stage")
	elseif code == "no_character" then
		return Locale.t("warp.reason.no_character")
	elseif code == "no_profile" then
		return Locale.t("common.reason.no_profile")
	elseif code == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif code == "auto_active" then
		return Locale.t("common.reason.auto_active") -- 자동 진행 중(지시서 #18 AA9 — 사유 + 끄라는 안내)
	elseif code == "start_run_failed" or code == "subtract_failed" then
		-- start_run_failed는 블럭스가 이미 빠진 뒤의 사고다 — "못 했다"로 안내하면 거짓말이 된다.
		return Locale.t("common.reason.partial_failure")
	end
	return Locale.t("warp.reason.failed")
end

function WarpWindowLogic.newConfirm(): ConfirmFlow.Flow
	return ConfirmFlow.new(WarpWindowLogic.CONFIRM_WINDOW_SEC)
end

return WarpWindowLogic

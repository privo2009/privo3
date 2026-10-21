--!strict
-- 3D 안내 BillboardGui의 내용(보일지 · 문구 · 색 역할)을 정한다 (U4, 지시서 #5). 순수 모듈 —
-- 그리는 쪽은 World/WorldLabels.client.lua. 값은 전부 서버 · Config 원본에서 온다
-- (런 보상은 서버 RunStateChanged, 다음 층 보상은 StageConfig, 패드는 ClickPadConfig).
-- 클라에서 식을 다시 세우지 않는다 — Config 함수를 그대로 부른다.
--
-- 색 역할(docs/UI.md "3. 색 > 3D 오브젝트 색 배정"):
--   수령 발판 위    cashout(노랑, 수령·안전)
--   진행 벽 위      advance(보라, 진행·도박). 최종층은 neutral(회색)
--   클릭 파워 패드   해금 power(주황) / 미해금 neutral(회색)
--   입장 게이트     neutral(회색) — 행동 선택이 아니라 위치 안내라서(Claude 판단, 세션 로그)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)

type BigNumber = BigNum.BigNumber

local WorldLabelLogic = {}

local WORLD_ID = 1 -- 지금 월드는 1 하나다(PadService와 같은 가정)

export type Label = {
	visible: boolean,
	title: string, -- 첫 줄
	detail: string, -- 둘째 줄 ("" 이면 한 줄)
	role: UiTheme.ColorRole,
}

local HIDDEN: Label = { visible = false, title = "", detail = "", role = "neutral" }

export type RunInput = {
	active: boolean,
	stage: number,
	cleared: boolean,
	canAdvance: boolean,
	reward: BigNumber, -- 서버가 보낸 지금 수령액
}

-- 현재 층 수령 발판 위. 켜진 발판(내 런 클리어 + 그 층)에만 뜬다 — CashoutPadView와 같은 조건.
function WorldLabelLogic.cashout(run: RunInput?, padStage: number): Label
	if run == nil or not run.active or not run.cleared or run.stage ~= padStage then
		return HIDDEN
	end
	return {
		visible = true,
		title = "수령",
		detail = "+" .. Formatter.format(run.reward),
		role = "cashout",
	}
end

-- 진행 벽 위. 클리어 뒤에만 뜬다. 다음 층이 있으면 그 층 보상(StageConfig 원본), 최종층이면 안내 문구.
function WorldLabelLogic.wall(run: RunInput?): Label
	if run == nil or not run.active or not run.cleared then
		return HIDDEN
	end
	if not run.canAdvance then
		return { visible = true, title = "다음 월드", detail = "준비 중", role = "neutral" }
	end
	return {
		visible = true,
		title = "진행",
		detail = "다음 층 +" .. Formatter.format(StageConfig.getBloxReward(run.stage + 1)),
		role = "advance",
	}
end

-- 클릭 파워 패드 위. 파워와 해금 조건(이번 생애 누적 블럭스). 값은 ClickPadConfig 원본.
function WorldLabelLogic.pad(index: number, lifeBlox: BigNumber): Label
	local power = ClickPadConfig.getPadPower(WORLD_ID, index)
	local unlocked = ClickPadConfig.isUnlocked(WORLD_ID, index, lifeBlox)
	if unlocked then
		return { visible = true, title = "클릭 " .. Formatter.format(power), detail = "", role = "power" }
	end
	return {
		visible = true,
		title = "클릭 " .. Formatter.format(power),
		detail = "필요 " .. Formatter.format(ClickPadConfig.getPadUnlock(WORLD_ID, index)),
		role = "neutral",
	}
end

-- 입장 게이트. 위치 안내만. 런 중에는 숨긴다(이미 지나왔다).
function WorldLabelLogic.gate(runActive: boolean): Label
	if runActive then
		return HIDDEN
	end
	return { visible = true, title = "입장", detail = "지나가면 시작", role = "neutral" }
end

WorldLabelLogic.HIDDEN = HIDDEN

return WorldLabelLogic

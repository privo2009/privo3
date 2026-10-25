--!strict
-- 환생 창의 표시 값 · 확인 단계 · 사유 문구 (Phase 6 지시서 #5). 순수 모듈 — 화면은
-- Screens/Window/RebirthWindow. docs/UI.md "1. 화면 목록 > 환생 창 — 반드시 보여야 하는 것".
--
-- 값은 서버와 같은 함수에서 나온다: 얻는 배수 = RebirthConfig.getGainedRebirths(블럭스)
-- (서버 RebirthService.runRebirth가 부르는 그 함수), 배수 = StrengthMultiplier.compute.
-- 화면 값은 안내일 뿐이고, 실제 환생 여부는 서버가 요청을 받은 순간 다시 판정한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local ConfirmFlow = require(script.Parent.ConfirmFlow)

type BigNumber = BigNum.BigNumber

local RebirthWindowLogic = {}

export type View = {
	blox: BigNumber,
	gained: BigNumber, -- 얻는 배수
	wasted: BigNumber, -- 버려지는 양 (1000 미만 나머지 — 환생은 전액 소모라 이만큼은 아무것도 안 된다)
	canRebirth: boolean,
	lockReason: string?, -- 잠긴 이유 코드 (canRebirth=false일 때)
	multiplierNow: BigNumber,
	multiplierAfter: BigNumber,
}

-- shop = Store "shop"(지시서 #16 S6). 2배 환생을 가졌으면 얻는 배수가 2배다 — 서버 RebirthService와 같은 함수 · 같은 배수 인자.
-- 환생할 수 있는가 · 버려지는 양은 배수와 상관없다.
function RebirthWindowLogic.compute(blox: BigNumber, rebirths: BigNumber, shop: any?): View
	local mult = if shop ~= nil then ShopEffectsLogic.rebirth(ShopEffectsLogic.fromSummary(shop)) else nil
	local gained = RebirthConfig.getGainedRebirths(blox, mult)
	-- 버려지는 양은 RebirthConfig.getLeftover가 원본이다(시뮬레이터의 S5 업그레이드 예산과 같은 함수 — 지시서 #7).
	-- 블럭스가 아주 크면 나머지가 표현되지 않아 0이다(음수 잡음도 0으로 접는다).
	local wasted = RebirthConfig.getLeftover(blox)
	local can = RebirthConfig.canRebirth(blox)
	return {
		blox = blox,
		gained = gained,
		wasted = wasted,
		canRebirth = can,
		lockReason = if can then nil else "not_enough_blox",
		multiplierNow = StrengthMultiplier.compute({ rebirths = rebirths }),
		multiplierAfter = StrengthMultiplier.compute({ rebirths = BigNum.add(rebirths, gained) }),
	}
end

-- 사유 코드 → 화면 문구. 코드는 서버 RebirthService.REASON_* · RebirthRequestService.REASON_RATE_LIMITED
-- 와 같은 문자열이다. 모르는 코드는 일반 문구.
function RebirthWindowLogic.reasonText(code: string): string
	if code == "not_enough_blox" then
		return Locale.t("rebirth.reason.not_enough_blox", { cost = Formatter.format(BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH)) })
	elseif code == "no_profile" then
		return Locale.t("common.reason.no_profile")
	elseif code == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif code == "partial_failure" then
		-- 부작용이 이미 생긴 뒤의 사고다. "환생하지 못했다"로 안내하면 거짓말이 된다(RebirthService 상단).
		return Locale.t("common.reason.partial_failure")
	end
	return Locale.t("rebirth.reason.failed")
end

-- 환생하면 바뀌는 것 / 남는 것. 문서가 아니라 RebirthService.runRebirth가 실제로 하는 일을 읽어 맞췄다
-- (괄호 안은 그 함수의 단계 번호). 그쪽 단계가 바뀌면 여기도 바꾼다.
RebirthWindowLogic.RESETS = {
	Locale.t("rebirth.reset.blox"), -- 4
	Locale.t("rebirth.reset.power"), -- 6
	Locale.t("rebirth.reset.floor"), -- 7 · 8
	Locale.t("rebirth.reset.pad"), -- 11 (lifeBlox 0, 선택 패드 1)
	Locale.t("rebirth.reset.speed"), -- 10
	Locale.t("rebirth.reset.run"), -- 3
}
-- 상점 업그레이드: runRebirth의 deps에는 업그레이드를 바꾸는 통로가 없다 — 남는다(UpgradeServiceTests 5번이 확인한다, 지시서 #7).
RebirthWindowLogic.KEEPS = Locale.t("rebirth.keeps")

-- 창에 그리는 줄. 초기화 목록을 두 개씩 한 줄로 묶는다(지시서 #8 — 한 줄에 하나씩 6줄이면 줄 높이가 낮아 글자가 거의 안 읽혔다).
RebirthWindowLogic.RESET_PER_LINE = 2
function RebirthWindowLogic.resetLines(): { string }
	local lines = {}
	for i = 1, #RebirthWindowLogic.RESETS, RebirthWindowLogic.RESET_PER_LINE do
		local items = {}
		for j = i, math.min(i + RebirthWindowLogic.RESET_PER_LINE - 1, #RebirthWindowLogic.RESETS) do
			table.insert(items, RebirthWindowLogic.RESETS[j])
		end
		table.insert(lines, "· " .. table.concat(items, "   · "))
	end
	return lines
end

-- 버려지는 양 강조(빨강)를 켤까. 0이면 끈다 — 버릴 것이 없는데 경고색이 뜨면 잘못 읽힌다(지시서 #8).
function RebirthWindowLogic.shouldWarnWasted(wasted: BigNumber): boolean
	return wasted.m > 0
end

-- 버려지는 양 옆 안내 + 상점 창으로 가는 버튼(지시서 #7 6단계). 버려질 나머지를 업그레이드에 먼저 쓰라는 안내다
-- (시뮬레이터 표준 플레이어의 구매 규칙 S5와 같은 행동).
RebirthWindowLogic.SHOP_HINT = Locale.t("rebirth.shopHint")
RebirthWindowLogic.SHOP_BUTTON_TEXT = Locale.t("rebirth.shopButton")

-- ===== 확인 단계 ==============================================================================
--
-- 한 번 누름으로는 절대 실행되지 않는다. 첫 누름은 "확인 중"으로 바꿀 뿐이고, CONFIRM_WINDOW_SEC 안에
-- 한 번 더 눌러야 요청이 나간다. 시간이 지나거나 취소하면 처음으로 돌아간다.

RebirthWindowLogic.CONFIRM_WINDOW_SEC = 5 -- 시각 튜닝값(세션 로그)

export type ConfirmAction = ConfirmFlow.Action

-- 확인 단계는 월드·워프 창과 같은 규칙이라 UI/Logic/ConfirmFlow로 옮겼다(지시서 #6). 이름은 그대로 둔다.
function RebirthWindowLogic.newConfirm(): ConfirmFlow.Flow
	return ConfirmFlow.new(RebirthWindowLogic.CONFIRM_WINDOW_SEC)
end

return RebirthWindowLogic

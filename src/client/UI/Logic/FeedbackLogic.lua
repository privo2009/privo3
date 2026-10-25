--!strict
-- 피드백 표시 판정 (Phase 6 지시서 #8 2단계) — 순수 모듈. 첫 직접 플레이에서 "환생 직후 달라진 걸 느끼기 어렵다",
-- "운동기구 위에서 클릭해도 더 빨리 오르는지 체감되지 않는다"가 나왔다. 목적은 하나다 — **"환생하면 빨라진다"를 눈으로 보이게.**
--
--   클릭 +숫자 팝업   클릭마다 실제로 붙은 힘. 서버 확정값(PlayerState strength)의 증가분이다 — 클라가 클릭 수로 다시 세지 않는다.
--                     ClickService 배치 주기마다 묶여 온다. 기구 위면 그 배수가 이미 들어 있고, 배수도 옆에 적는다
--   HUD 환생 배수     힘 수치 옆. StrengthMultiplier.compute — 서버 ClickService가 쓰는 그 함수
--   환생 안내         환생하는 순간 "×이전 → ×이후"와 초기화 사실. 서버 RebirthResult의 gained · total
--
-- 그리는 쪽: World/ClickPopups.client.lua · Screens/Hud/PowerBlock · Screens/Overlay/RebirthNotice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

type BigNumber = BigNum.BigNumber

local FeedbackLogic = {}

-- ===== 클릭 +숫자 팝업 ======================================================================

-- 팝업 풀 크기 · 떠 있는 시간 · 올라가는 높이(studs). Claude가 정한 시각 값(세션 로그).
-- 배치 주기(0.2초)마다 하나씩 뜨므로 1.2초면 동시에 최대 6개 — 풀 8개면 모자라지 않는다.
FeedbackLogic.POPUP_POOL_SIZE = 8
FeedbackLogic.POPUP_LIFETIME_SEC = 1.2
FeedbackLogic.POPUP_RISE_STUDS = 3

-- 이전 힘 → 지금 힘의 증가분. 줄었거나(환생 초기화) 같으면 nil — 팝업을 띄우지 않는다.
-- ⚠️ 차가 너무 작아 BigNum 정밀도 밖이면(지수 차 13 이상 — 0 소실) 0이 되어 nil이다. 띄울 것이 없는 게 맞다.
function FeedbackLogic.gainOf(prev: BigNumber?, now: BigNumber?): BigNumber?
	if prev == nil or now == nil or not BigNum.gt(now, prev) then
		return nil
	end
	local gain = BigNum.sub(now, prev)
	if gain.m <= 0 then
		return nil
	end
	return gain
end

-- 팝업 문구. 기구 배수가 1보다 크면 함께 적는다 — 같은 클릭이 기구 위에서 몇 배인지 보이게.
function FeedbackLogic.popupText(gain: BigNumber, gymMultiplier: number?): string
	local amount = Formatter.format(gain)
	if gymMultiplier ~= nil and gymMultiplier > 1 then
		return Locale.t("feedback.popup.gym", { amount = amount, mult = FeedbackLogic.formatMultiplier(gymMultiplier) })
	end
	return Locale.t("feedback.popup", { amount = amount })
end

-- 1.2 → "1.2", 2 → "2", 100 → "100" (기구 배수는 작은 수라 Formatter의 소수 2자리를 쓰지 않는다)
function FeedbackLogic.formatMultiplier(value: number): string
	if value % 1 == 0 then
		return tostring(math.floor(value))
	end
	return (string.gsub(string.format("%.2f", value), "0+$", ""))
end

-- 팝업 한 개의 진행률(0..1) → 위로 오른 높이 · 투명도. 앞 60%는 진하게, 뒤 40% 동안 사라진다.
function FeedbackLogic.popupFrame(progress: number): (number, number)
	local t = math.clamp(progress, 0, 1)
	local rise = FeedbackLogic.POPUP_RISE_STUDS * t
	local transparency = if t < 0.6 then 0 else (t - 0.6) / 0.4
	return rise, transparency
end

-- ===== HUD 환생 배수 ========================================================================

-- 지금 힘 배수(환생 배수). 서버 ClickService가 클릭 힘에 곱하는 그 함수다.
function FeedbackLogic.multiplierOf(rebirths: BigNumber): BigNumber
	return StrengthMultiplier.compute({ rebirths = rebirths })
end

-- ===== 환생 안내 ============================================================================

FeedbackLogic.REBIRTH_TITLE = Locale.t("feedback.rebirth.title")
FeedbackLogic.REBIRTH_RESET_TEXT = Locale.t("feedback.rebirth.reset")
FeedbackLogic.REBIRTH_HOLD_SEC = 5 -- Claude가 정한 시각 값(세션 로그)

export type RebirthNotice = {
	title: string,
	change: string, -- "힘 배수 ×A → ×B"
	reset: string,
	before: BigNumber,
	after: BigNumber,
}

-- 서버 결과(gained · total)로 안내 문구를 만든다. 이전 배수 = total − gained의 배수.
function FeedbackLogic.rebirthNotice(total: BigNumber, gained: BigNumber): RebirthNotice
	local prevRebirths = BigNum.sub(total, gained)
	if prevRebirths.m < 0 then
		prevRebirths = BigNum.new(0, 0)
	end
	local before = FeedbackLogic.multiplierOf(prevRebirths)
	local after = FeedbackLogic.multiplierOf(total)
	return {
		title = FeedbackLogic.REBIRTH_TITLE,
		change = Locale.t("feedback.rebirth.change", { before = Formatter.format(before), after = Formatter.format(after) }),
		reset = FeedbackLogic.REBIRTH_RESET_TEXT,
		before = before,
		after = after,
	}
end

return FeedbackLogic

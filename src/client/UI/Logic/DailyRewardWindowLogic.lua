--!strict
-- 일일 보상 창 · HUD 아이콘 배지 · 자동 등장 판정 (지시서 #20 D1 ~ D5 — DESIGN.md 9장 "일일 보상"). 순수 모듈 — 화면은
-- Screens/Overlay/DailyRewardWindow · Screens/Hud/DailyIcon.
--
-- 값은 서버 원본이다: 받을 수 있나 · 칸 · 받은 칸 · 다음 리셋까지는 PlayerState daily(서버 os.time — 클라 시계를 쓰지 않는다).
-- 칸의 보상 글자는 DailyRewardConfig(서버가 주는 표와 같은 표) + RewardLogic.bloxAmount(서버가 주는 양과 같은 식 — maxStage는 PlayerState).
-- 남은 시간만 클라가 센다: 서버가 보낸 남은 초 − (지금 − 받은 시각). os.clock 차이라 기기 시계와 무관하다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardConfig = require(ReplicatedStorage.Shared.Config.DailyRewardConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local RewardLogic = require(ReplicatedStorage.Shared.RewardLogic)
local DayClock = require(ReplicatedStorage.Shared.DayClock)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local PetWindowLogic = require(script.Parent.PetWindowLogic)

local DailyRewardWindowLogic = {}

DailyRewardWindowLogic.PENDING_TIMEOUT_SEC = 3 -- 결과가 안 오면 받기 버튼을 다시 연다(다른 창의 대기와 같은 꼴)

export type Summary = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number,
	streak: number,
	secondsToReset: number,
	today: number,
	receivedAt: number,
}

local function num(v: any, fallback: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else fallback
end

function DailyRewardWindowLogic.read(raw: any): Summary
	local s = if type(raw) == "table" then raw else {}
	return {
		canClaim = s.canClaim == true,
		claimedToday = s.claimedToday == true,
		day = math.clamp(math.floor(num(s.day, 1)), 1, DailyRewardConfig.CYCLE_DAYS),
		streak = math.clamp(math.floor(num(s.streak, 0)), 0, DailyRewardConfig.CYCLE_DAYS),
		secondsToReset = math.max(0, num(s.secondsToReset, 0)),
		today = num(s.today, 0),
		receivedAt = num(s.receivedAt, 0),
	}
end

export type Cell = {
	day: number,
	dayText: string,
	name: string, -- 보상 이름(포션 이름 · "블럭스" · 펫 이름)
	amount: string, -- 개수 · 블럭스 양 · 펫 희귀도(리미티드). 받은 칸은 "받음"
	state: string, -- "claimed" | "today" | "future"
	isPet: boolean,
	rarityTier: number, -- 펫 칸의 UiTheme.Rarity 단계(아니면 0)
}

-- 칸 한 줄 보상(첫 항목 — 표의 칸은 지금 항목 하나씩이다)의 이름 · 양.
local function rewardTexts(reward: RewardLogic.Reward, maxStage: any): (string, string, boolean, number)
	if reward.type == "potion" then
		return Names.boost(reward.kind :: string), Locale.t("daily.reward.count", { count = reward.count }), false, 0
	elseif reward.type == "bloxScaled" then
		return Locale.t("daily.reward.blox"), Formatter.format(RewardLogic.bloxAmount(maxStage, reward.k :: number)), false, 0
	end
	local _, _, rarity = PetConfig.get(reward.petId)
	local r = rarity or 1
	return Names.pet(reward.petId :: string), Names.rarity(r), true, DailyRewardWindowLogic.rarityTierOf(r)
end

-- 펫 희귀도 코드 → UiTheme.Rarity 단계. 펫 창과 같은 표(PetWindowLogic.rarityTier — 리미티드는 tier6, docs/UI.md "지시서 #20").
function DailyRewardWindowLogic.rarityTierOf(rarity: number): number
	return PetWindowLogic.rarityTier(rarity)
end

-- 7칸. 받은 칸 = 1 ~ streak(오늘 받았으면 오늘 칸 포함) · 오늘 칸 = day(받을 수 있을 때) · 나머지 future.
function DailyRewardWindowLogic.cells(raw: any, maxStage: any): { Cell }
	local s = DailyRewardWindowLogic.read(raw)
	local out: { Cell } = {}
	for day, rewards in ipairs(DailyRewardConfig.DAYS) do
		local name, amount, isPet, tier = rewardTexts(rewards[1], maxStage)
		local state = "future"
		if day <= s.streak then
			state = "claimed"
		elseif s.canClaim and day == s.day then
			state = "today"
		end
		table.insert(out, {
			day = day,
			dayText = Locale.t("daily.day", { n = day }),
			name = name,
			amount = if state == "claimed" then Locale.t("daily.claimed") else amount,
			state = state,
			isPet = isPet,
			rarityTier = tier,
		})
	end
	return out
end

-- 다음 UTC 0시까지 남은 초(서버 값을 받은 뒤로 센다). 0 아래로 안 간다.
function DailyRewardWindowLogic.secondsLeft(raw: any, now: number): number
	local s = DailyRewardWindowLogic.read(raw)
	return math.max(0, s.secondsToReset - math.max(0, now - s.receivedAt))
end

function DailyRewardWindowLogic.timerText(raw: any, now: number): string
	return Locale.t("daily.next", { time = DayClock.hhmm(DailyRewardWindowLogic.secondsLeft(raw, now)) })
end

-- 받기 버튼: 받을 수 있고 대기 중이 아니면 켜짐. 오늘 받았으면 "내일 또".
function DailyRewardWindowLogic.button(raw: any, pending: boolean): { enabled: boolean, text: string }
	local s = DailyRewardWindowLogic.read(raw)
	if s.canClaim then
		return { enabled = not pending, text = Locale.t("daily.claim") }
	end
	return { enabled = false, text = Locale.t("daily.comeBack") }
end

-- 사유 코드 → 문구. 코드는 서버 DailyService · RewardService와 같은 문자열.
function DailyRewardWindowLogic.reasonText(code: string): string
	if code == "storage_full" then
		return Locale.t("daily.reason.storage_full")
	elseif code == "already_claimed" then
		return Locale.t("daily.reason.already_claimed")
	elseif code == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif code == "no_profile" then
		return Locale.t("common.reason.no_profile")
	end
	return Locale.t("daily.reason.failed")
end

-- 결과 → 창 상태 문구(성공이면 "n일째 보상을 받았어요").
function DailyRewardWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" or type(payload.ok) ~= "boolean" then
		return nil
	end
	if payload.ok then
		return Locale.t("daily.result.ok", { n = num(payload.day, 1) })
	end
	return DailyRewardWindowLogic.reasonText(tostring(payload.reason))
end

-- HUD 아이콘 배지: 받을 게 있으면.
function DailyRewardWindowLogic.badge(raw: any): boolean
	return DailyRewardWindowLogic.read(raw).canClaim
end

-- 자동 등장(D5): 받을 게 있고 · 첫 접속 안내가 끝났고 · 런 중이 아니고 · 이 세션에서 그 일 번호로 아직 안 띄웠으면.
function DailyRewardWindowLogic.shouldAutoShow(raw: any, onboarding: any, runActive: boolean, shownDay: number?): boolean
	local s = DailyRewardWindowLogic.read(raw)
	local done = type(onboarding) == "table" and onboarding.done == true
	return s.canClaim and done and not runActive and s.today ~= 0 and s.today ~= shownDay
end

return DailyRewardWindowLogic

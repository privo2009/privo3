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
--   운동기구 위     열림 power(주황) / 잠김 neutral(회색) / 공허 premium(남색) — 지시서 #8 M4와 같은 배정

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)

-- 작은 배수(1.2 · 2 · 100)는 Formatter의 소수 2자리 대신 짧게 적는다.
local function formatSmall(value: number): string
	if value % 1 == 0 then
		return tostring(math.floor(value))
	end
	return (string.gsub(string.format("%.2f", value), "0+$", ""))
end

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
	-- 서버가 보낸 다음 층 수령액(블럭스 획득량 업그레이드 반영). 없으면 StageConfig 층 보상(배수 1) — 지시서 #7
	nextReward: BigNumber?,
}

-- 현재 층 수령 발판 위. 켜진 발판(내 런 클리어 + 그 층)에만 뜬다 — CashoutPadView와 같은 조건.
function WorldLabelLogic.cashout(run: RunInput?, padStage: number): Label
	if run == nil or not run.active or not run.cleared or run.stage ~= padStage then
		return HIDDEN
	end
	return {
		visible = true,
		title = Locale.t("world.cashout.title"),
		detail = Locale.t("world.cashout.reward", { amount = Formatter.format(run.reward) }),
		role = "cashout",
	}
end

-- 진행 벽 위. 클리어 뒤에만 뜬다. 다음 층이 있으면 그 층 보상(서버 nextReward — 업그레이드 배수는 서버가 곱한다.
-- 클라에서 곱하지 않는다), 최종층이면 안내 문구.
function WorldLabelLogic.wall(run: RunInput?): Label
	if run == nil or not run.active or not run.cleared then
		return HIDDEN
	end
	if not run.canAdvance then
		return { visible = true, title = Locale.t("world.wall.nextWorld"), detail = Locale.t("world.wall.comingSoon"), role = "neutral" }
	end
	return {
		visible = true,
		title = Locale.t("world.wall.title"),
		detail = Locale.t("world.wall.nextReward", { amount = Formatter.format(run.nextReward or StageConfig.getBloxReward(run.stage + 1)) }),
		role = "advance",
	}
end

-- 클릭 파워 패드 위. 파워와 해금 조건(이번 생애 누적 블럭스). 값은 ClickPadConfig 원본.
function WorldLabelLogic.pad(index: number, lifeBlox: BigNumber): Label
	local power = ClickPadConfig.getPadPower(WORLD_ID, index)
	local unlocked = ClickPadConfig.isUnlocked(WORLD_ID, index, lifeBlox)
	if unlocked then
		return { visible = true, title = Locale.t("world.pad.power", { power = Formatter.format(power) }), detail = "", role = "power" }
	end
	return {
		visible = true,
		title = Locale.t("world.pad.power", { power = Formatter.format(power) }),
		detail = Locale.t("world.pad.need", { amount = Formatter.format(ClickPadConfig.getPadUnlock(WORLD_ID, index)) }),
		role = "neutral",
	}
end

-- 패드 표시를 띄울 패드인가 (Phase 6 지시서 #6). 24장이 한 줄이라 다 띄우면 스폰에서 겹쳐 안 읽혔다.
-- 유저가 패드에서 내리는 판단은 셋뿐이라 그 셋만 띄운다(Claude 판단, 세션 로그):
--   지금 세팅된 패드           — 내가 어디 서 있었나
--   열린 것 중 가장 좋은 패드  — 밟으러 갈 곳 (지금 패드와 같으면 하나)
--   다음 해금 대상             — 얼마 더 모아야 하나 (전부 열렸으면 없다)
export type PadRole = "current" | "best" | "next"

function WorldLabelLogic.padRole(index: number, selectedIndex: number, unlockedCount: number): PadRole?
	if index == selectedIndex then
		return "current"
	elseif index == unlockedCount then
		return "best"
	elseif index == unlockedCount + 1 then
		return "next"
	end
	return nil
end

function WorldLabelLogic.isPadShown(index: number, selectedIndex: number, unlockedCount: number): boolean
	return WorldLabelLogic.padRole(index, selectedIndex, unlockedCount) ~= nil
end

-- 역할별 높이(지면 위 studs). 세 패드가 붙어 있어(간격 12) 스폰 쪽에서 보면 같은 높이의 표시가 겹친다 —
-- 계단처럼 높이를 달리해 위아래로 벌린다(2026-10-22 Play 스크린샷). 표시 높이 3 + 틈 1.5.
WorldLabelLogic.PAD_HEIGHT = {
	current = 4,
	best = 8.5,
	["next"] = 13,
}

-- 역할별 빌보드 크기(studs). "다음 해금"은 패드 줄에서 스폰과 가장 먼 쪽이고 두 줄이라 같은 크기로는
-- 55 studs 밖에서 글자가 작았다(2026-10-22 S3_pad_labels_spawn2) → 2배(지시서 #7, Claude 판단).
-- 1.6배는 폰(Galaxy A06 시뮬레이션) 66 studs에서 둘째 줄("필요 …")이 여전히 작았다(S7_1_phone_pad_labels).
-- 맨 위 칸이라 키워도 아래 둘을 가리지 않는다. 가로 16은 패드 간격(12)보다 넓지만 높이가 달라 겹치지 않는다.
WorldLabelLogic.PAD_SIZE = {
	current = Vector2.new(8, 3),
	best = Vector2.new(8, 3),
	["next"] = Vector2.new(16, 6),
}

-- ===== 운동기구 위 (지시서 #8 2d) =============================================================
--
-- 9개 전부 띄우면 패드처럼 겹친다. 유저가 기구에서 내리는 판단만 남긴다(Claude 판단, 세션 로그 — 패드 표시와 같은 규칙):
--   지금 올라서 있는 기구   "사용 중" — 배수가 지금 붙고 있다(잠긴 기구면 "잠김")
--   열린 것 중 가장 센 기구  올라갈 곳
--   다음 해금 대상          환생 몇 번이면 열리나
--   공허 훈련 구역          항상 — 로벅스 전용(준비 중), 가장 센 기구가 무엇인지 보인다
-- 값은 GymConfig 원본(배수 · 필요 환생 수). 올라서 있는지는 GymLayout.resolve — 서버 GymService와 같은 함수.
export type GymRole = "current" | "best" | "next" | "void"

function WorldLabelLogic.gymRole(index: number, standingIndex: number?, unlockedCount: number): GymRole?
	if GymConfig.isRobuxOnly(index) then
		return "void"
	elseif index == standingIndex then
		return "current"
	elseif index == unlockedCount then
		return "best"
	elseif index == unlockedCount + 1 then
		return "next"
	end
	return nil
end

WorldLabelLogic.GYM_SIZE = Vector2.new(9, 3.2)
WorldLabelLogic.GYM_VOID_SIZE = Vector2.new(12, 3.6)
-- 지면 위 studs. 서 있는 캐릭터 머리(약 5)와 클릭 팝업(머리 위 → 약 8.5)보다 위. 기구는 2줄 격자라 통로에서 보면 Z로 벌어져
-- 있어 패드처럼 높이를 계단으로 두지 않는다.
WorldLabelLogic.GYM_HEIGHT = 10

-- 기구 위 표시. standing = 지금 이 기구 위에 서 있는가. shopUnlocked = 로벅스로 열렸는가(지시서 #16 — GymLayout.shopUnlocked).
function WorldLabelLogic.gym(index: number, rebirths: BigNumber, standing: boolean, shopUnlocked: ((number) -> boolean)?): Label
	local multiplierText = Locale.t("world.gym.mult", { mult = formatSmall(GymConfig.getMultiplier(index)) })
	local bought = shopUnlocked ~= nil and shopUnlocked(index)
	if GymConfig.isRobuxOnly(index) then
		local registered = ShopConfig.isRegistered(GymConfig.getShopKey(index))
		return {
			visible = true,
			title = Locale.t("world.gym.voidMult", { mult = formatSmall(GymConfig.getMultiplier(index)) }),
			detail = if bought then (if standing then Locale.t("world.gym.inUse") else "") elseif registered then Locale.t("world.gym.robuxOnly") else Locale.t("world.gym.robuxOnlySoon"),
			role = "premium",
		}
	end
	if GymConfig.isUnlockedByRebirths(index, rebirths) or bought then
		return { visible = true, title = multiplierText, detail = if standing then Locale.t("world.gym.inUse") else "", role = "power" }
	end
	return {
		visible = true,
		title = multiplierText,
		detail = Locale.t(if standing then "world.gym.lockedNeed" else "world.gym.need", { amount = Formatter.format(GymConfig.getUnlockRebirths(index)) }),
		role = "neutral",
	}
end

-- ===== 패드 · 운동기구 본체 색 (지시서 #8 M4) ====================================================
--
-- 해금은 플레이어마다 다르므로(패드 = 이번 생애 누적 블럭스, 기구 = 환생 수) 클라가 자기 화면만 칠한다
-- (World/LobbyRenderer — CashoutPadRenderer와 같은 방식. 서버 파트 색은 복제되지 않는다).
--   패드   해금 power(주황) / 미해금 neutral(회색)
--   기구   해금 power(주황) / 미해금 neutral(회색) / 공허(로벅스 전용) premium(남색) + 금테(cashout 노랑 — LobbyRenderer)
function WorldLabelLogic.padBodyRole(index: number, lifeBlox: BigNumber): UiTheme.ColorRole
	return if ClickPadConfig.isUnlocked(WORLD_ID, index, lifeBlox) then "power" else "neutral"
end

function WorldLabelLogic.gymBodyRole(index: number, rebirths: BigNumber, shopUnlocked: ((number) -> boolean)?): UiTheme.ColorRole
	if GymConfig.isRobuxOnly(index) then
		return "premium"
	end
	-- 선해금(지시서 #17)으로 열린 기구도 열린 색
	local bought = shopUnlocked ~= nil and shopUnlocked(index)
	return if GymConfig.isUnlockedByRebirths(index, rebirths) or bought then "power" else "neutral"
end

-- 잠긴 기구 옆 "로벅스로 열기" 프롬프트(지시서 #17 — DESIGN 9장 "창별 상품 버튼"). 켤지 · 누르면 요청할 상품 키 · 글자.
-- 켬 = 아직 안 열림(환생 수 · 선해금 · 공허 게임패스 모두 아님) + 대시보드에 등록됨. 공허는 게임패스, 나머지는 선해금 개발자 상품.
export type GymPrompt = { enabled: boolean, key: string, actionText: string, objectText: string }
function WorldLabelLogic.gymPrompt(index: number, rebirths: BigNumber, shopUnlocked: ((number) -> boolean)?): GymPrompt
	local key = GymConfig.getShopKey(index)
	local bought = shopUnlocked ~= nil and shopUnlocked(index)
	local open = bought or (not GymConfig.isRobuxOnly(index) and GymConfig.isUnlockedByRebirths(index, rebirths))
	return {
		enabled = not open and ShopConfig.isRegistered(key),
		key = key,
		actionText = Locale.t("world.gym.buyPrompt"),
		objectText = Locale.t("world.gym.buyObject", { name = Names.product(key), price = string.format("%d R$", GymConfig.getRobuxPrice(index)) }),
	}
end

-- 입장 게이트. 위치 안내만. 런 중에는 숨긴다(이미 지나왔다).
function WorldLabelLogic.gate(runActive: boolean): Label
	if runActive then
		return HIDDEN
	end
	return { visible = true, title = Locale.t("world.gate.title"), detail = Locale.t("world.gate.detail"), role = "neutral" }
end

WorldLabelLogic.HIDDEN = HIDDEN

return WorldLabelLogic

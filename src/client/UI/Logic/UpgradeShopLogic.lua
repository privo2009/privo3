--!strict
-- 상점 창(업그레이드)의 표시 값 · 잠김 · 사유 문구 · 중복 요청 막기 (Phase 6 지시서 #7 U5). 순수 모듈 —
-- 화면은 Screens/Window/UpgradeShopWindow.
--
-- 값은 서버 · Config 원본에서 나온다: 레벨은 서버 PlayerState(Store "upgrades"), 효과 · 비용 · 살 수 있는가는
-- UpgradeConfig.getEffect · getCostAtLevel · canBuy(서버 UpgradeService가 부르는 그 함수). 클라에서 식을 다시 세우지 않는다.
-- 화면 값은 안내일 뿐이고, 실제 구매 여부는 서버가 요청을 받은 순간 다시 판정한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

type BigNumber = BigNum.BigNumber

local UpgradeShopLogic = {}

-- 항목 이름 (화면 문구). 키는 UpgradeConfig.SHOP_ORDER.
UpgradeShopLogic.NAMES = {
	punchDamage = "펀치 데미지",
	punchSpeed = "펀치 속도",
	bloxGain = "블럭스 획득",
	titleLuck = "칭호 행운", -- 지시서 #10 (G13 — 칭호 뽑기 확률 배수)
	auraLuck = "아우라 행운", -- 지시서 #11 (A11)
	petSlots = "펫 장착 슬롯", -- 지시서 #12 (E7 — +1, 최대 1레벨)
	petLuck = "펫 행운", -- 지시서 #12 (E7)
} :: { [string]: string }

UpgradeShopLogic.BUY_TEXT = "구매"
UpgradeShopLogic.MAX_TEXT = "MAX"

-- 효과 값 → 문구. 단위만 붙인다(값은 UpgradeConfig.getEffect가 준다).
function UpgradeShopLogic.formatEffect(name: string, value: number): string
	if name == "punchSpeed" then
		return string.format("%.2f회/초", value)
	elseif name == "petSlots" then
		return string.format("슬롯 +%d", math.floor(value + 0.5)) -- 지시서 #12 (슬롯 수 식은 PetConfig.getSlots)
	end
	if UpgradeShopLogic.isLuck(name) then
		return string.format("행운 ×%.2f", value) -- 지시서 #11 P3
	end
	return string.format("×%.2f", value) -- punchDamage · bloxGain (배수)
end

-- 행운 줄(titleLuck · auraLuck · petLuck). 효과 문구가 "행운 ×현재 → ×다음"이다(P3).
function UpgradeShopLogic.isLuck(name: string): boolean
	return name == "titleLuck" or name == "auraLuck" or name == "petLuck"
end

export type Row = {
	name: string,
	title: string, -- "펀치 데미지  Lv 3/20" (무한이면 "Lv 3")
	effectText: string, -- "×1.15 → ×1.20" (최대 레벨이면 지금 효과만)
	isMax: boolean,
	canBuy: boolean,
	reason: string?, -- 잠긴 이유 코드 (UpgradeConfig.REASON_*)
	cost: BigNumber?, -- 다음 레벨 비용 (최대 레벨이면 nil)
	buttonText: string,
	footText: string, -- 버튼 아래 한 줄: 비용 · 잠긴 이유 · 최대 레벨
}

function UpgradeShopLogic.levelOf(levels: any, name: string): number
	local v = if type(levels) == "table" then levels[name] else nil
	if type(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.floor(v)
end

function UpgradeShopLogic.row(name: string, level: number, blox: BigNumber): Row
	local def = UpgradeConfig.Upgrades[name]
	local maxLevel = def.maxLevel
	local title = UpgradeShopLogic.NAMES[name] or name
	local levelText = if maxLevel ~= nil then string.format("Lv %d/%d", level, maxLevel) else string.format("Lv %d", level)
	local isMax = UpgradeConfig.isMaxLevel(name, level)
	local now = UpgradeShopLogic.formatEffect(name, UpgradeConfig.getEffect(name, level))

	if isMax then
		return {
			name = name,
			title = title .. "  " .. levelText,
			effectText = now .. " (최대)",
			isMax = true,
			canBuy = false,
			reason = UpgradeConfig.REASON_MAX_LEVEL,
			cost = nil,
			buttonText = UpgradeShopLogic.MAX_TEXT,
			footText = UpgradeShopLogic.reasonText(UpgradeConfig.REASON_MAX_LEVEL),
		}
	end

	local ok, reason, cost = UpgradeConfig.canBuy(name, level, blox)
	local nextText = if UpgradeShopLogic.isLuck(name)
		then string.format("×%.2f", UpgradeConfig.getEffect(name, level + 1)) -- "행운 ×현재 → ×다음"
		else UpgradeShopLogic.formatEffect(name, UpgradeConfig.getEffect(name, level + 1))
	local costText = (if cost ~= nil then Formatter.format(cost) else "-") .. " 블럭스"
	return {
		name = name,
		title = title .. "  " .. levelText,
		effectText = now .. " → " .. nextText,
		isMax = false,
		canBuy = ok,
		reason = reason,
		cost = cost,
		buttonText = UpgradeShopLogic.BUY_TEXT,
		footText = if ok or reason == nil then costText else string.format("%s (%s)", UpgradeShopLogic.reasonText(reason), costText),
	}
end

-- 상점 줄. 순서는 UpgradeConfig.SHOP_ORDER(노출 항목 — 지시서 #13 L3 뒤 7종).
function UpgradeShopLogic.rows(levels: any, blox: BigNumber): { Row }
	local out = {}
	for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		table.insert(out, UpgradeShopLogic.row(name, UpgradeShopLogic.levelOf(levels, name), blox))
	end
	return out
end

-- 사유 코드 → 화면 문구. 코드는 UpgradeConfig.REASON_* · 서버 UpgradeService.REASON_* · "rate_limited".
function UpgradeShopLogic.reasonText(code: string): string
	if code == UpgradeConfig.REASON_MAX_LEVEL then
		return "최대 레벨"
	elseif code == UpgradeConfig.REASON_INSUFFICIENT_BLOX then
		return "블럭스가 모자라요"
	elseif code == UpgradeConfig.REASON_INVALID_UPGRADE then
		return "살 수 없는 항목이에요"
	elseif code == "no_profile" then
		return "데이터를 불러오는 중이에요"
	elseif code == "rate_limited" then
		return "잠시 뒤에 다시 눌러 주세요"
	elseif code == "partial_failure" then
		-- 블럭스가 빠진 뒤의 사고다. "사지 못했다"로 안내하면 거짓말이 된다(UpgradeService 상단).
		return "문제가 생겼어요. 관리자에게 알려 주세요"
	end
	return "사지 못했어요"
end

-- ===== 중복 요청 막기 (S8 — 확인 단계 없이 한 번 눌러 바로 산다) ==================================
--
-- 요청을 보내면 결과가 올 때까지 같은 항목을 다시 보내지 않는다. 결과가 안 오면(서버 응답 유실)
-- PENDING_TIMEOUT_SEC 뒤에 다시 받는다. 서버도 빈도를 자른다(UpgradeRequestService) — 두 겹이다.
UpgradeShopLogic.PENDING_TIMEOUT_SEC = 2 -- Claude 판단(세션 로그): 응답은 보통 0.1초 안에 온다

export type Pending = {
	isPending: (name: string, now: number) -> boolean,
	tryBegin: (name: string, now: number) -> boolean,
	finish: (name: string) -> (),
}

function UpgradeShopLogic.newPending(): Pending
	local startedAt: { [string]: number } = {}
	local pending = {}
	function pending.isPending(name: string, now: number): boolean
		local t = startedAt[name]
		return t ~= nil and now - t < UpgradeShopLogic.PENDING_TIMEOUT_SEC
	end
	function pending.tryBegin(name: string, now: number): boolean
		if pending.isPending(name, now) then
			return false
		end
		startedAt[name] = now
		return true
	end
	function pending.finish(name: string)
		startedAt[name] = nil
	end
	return pending :: Pending
end

return UpgradeShopLogic

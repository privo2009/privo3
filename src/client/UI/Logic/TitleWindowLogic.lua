--!strict
-- 타이틀(칭호) 창의 표시 값 · 잠김 · 사유 문구 · 토스트 문구 · 중복 요청 막기 (Phase 7 지시서 #10). 순수 모듈 —
-- 화면은 Screens/Window/TitleWindow, 토스트는 Screens/Overlay/ToastStack.
--
-- 값은 서버 · Config 원본에서 나온다: 보유 · 장착 · 자동 롤은 서버 PlayerState(Store "titles"), 배수 · 확률 · 비용은
-- TitleConfig, 행운은 UpgradeConfig.getEffect("titleLuck", 레벨) — 서버 RollService.computeLuck에서 지금 1이 아닌 유일한 항이다
-- (롤 상품은 아우라 전용, 행운 게임패스 · 부스트는 Phase 8 전까지 1 — DESIGN.md "6. 뽑기 3종 > 공통").
-- ⚠️ 판정은 서버다(절대 규칙 3). 여기 확률은 **표시**다. 롤 가능 여부도 안내일 뿐이고 서버가 다시 판정한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

type BigNumber = BigNum.BigNumber

local TitleWindowLogic = {}

TitleWindowLogic.TITLE = "칭호"
TitleWindowLogic.EQUIP_TEXT = "장착"
TitleWindowLogic.EQUIPPED_TEXT = "장착 중"
TitleWindowLogic.LOCKED_TEXT = "-"
TitleWindowLogic.OWNED_TEXT = "보유"
TitleWindowLogic.NOT_OWNED_TEXT = "미보유"
TitleWindowLogic.FALLBACK_CHANCE_TEXT = "나머지"
TitleWindowLogic.AUTO_ON_TEXT = "자동 뽑기 켜짐"
TitleWindowLogic.AUTO_OFF_TEXT = "자동 뽑기 꺼짐"

-- 서버 사유 코드(RollService.REASON_* · TitleService.REASON_* · TitleRequestService). RollService는 서버 전용이라 문자열을 여기 둔다 —
-- 같은 문자열인지는 서버 테스트가 잰다(RollServiceTests "잔액 부족 코드는 상점과 같은 문자열").
TitleWindowLogic.REASONS = {
	insufficient_blox = "블럭스가 모자라요",
	rate_limited = "잠시 뒤에 다시 눌러 주세요",
	no_profile = "데이터를 불러오는 중이에요",
	not_owned = "아직 없는 칭호예요",
	invalid_request = "할 수 없는 요청이에요",
	partial_failure = "문제가 생겼어요. 관리자에게 알려 주세요", -- 블럭스가 빠진 뒤의 사고(상점과 같은 이유)
} :: { [string]: string }

function TitleWindowLogic.reasonText(code: string): string
	return TitleWindowLogic.REASONS[code] or "하지 못했어요"
end

-- 롤 버튼 문구 · 자동 롤 안내. 비용 · 간격은 TitleConfig 원본.
function TitleWindowLogic.rollButtonText(): string
	return string.format("1회 뽑기 (%s 블럭스)", Formatter.format(TitleConfig.ROLL_COST))
end

function TitleWindowLogic.autoNoteText(): string
	local perSec = BigNum.div(TitleConfig.ROLL_COST, BigNum.fromNumber(TitleConfig.ROLL_INTERVAL_SEC))
	return string.format("자동 뽑기는 초당 %s 블럭스를 씁니다", Formatter.format(perSec))
end

function TitleWindowLogic.multText(mult: number): string
	return string.format("힘·블럭스 ×%.2f", mult)
end

-- 확률 → 문구. 유효 숫자 두 자리 근처로 접는다(20.0% · 2.0% · 0.20% · 0.020% · 0.0020%). 1 이상이면 100%.
function TitleWindowLogic.chanceText(p: number): string
	if type(p) ~= "number" or p ~= p or p <= 0 then
		return "0%"
	end
	local pct = math.min(p, 1) * 100
	if pct >= 1 then
		return string.format("%.1f%%", pct)
	elseif pct >= 0.1 then
		return string.format("%.2f%%", pct)
	elseif pct >= 0.01 then
		return string.format("%.3f%%", pct)
	end
	return string.format("%.4f%%", pct)
end

-- 지금 행운(표시용). levels = Store "upgrades".
function TitleWindowLogic.luckOf(levels: any): number
	local v = if type(levels) == "table" then levels.titleLuck else nil
	local level = if type(v) == "number" and v == v and v >= 0 then math.floor(v) else 0
	return UpgradeConfig.getEffect("titleLuck", level)
end

export type Row = {
	id: string,
	name: string,
	tier: number, -- 희귀도 단계(TitleConfig.Titles 인덱스 = UiTheme.Rarity tier)
	multText: string,
	chanceText: string,
	owned: boolean,
	equipped: boolean,
	statusText: string,
	buttonText: string,
	canEquip: boolean,
}

local function ownedSet(summary: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(summary) == "table" and type(summary.owned) == "table" then
		for _, id in ipairs(summary.owned) do
			if type(id) == "string" then
				set[id] = true
			end
		end
	end
	return set
end

-- 6줄. 위가 가장 귀한 등급이다(희귀도 높은 순 — 목표가 위에 보인다). summary = Store "titles", levels = Store "upgrades".
function TitleWindowLogic.rows(summary: any, levels: any): { Row }
	local owned = ownedSet(summary)
	local equippedId = if type(summary) == "table" and type(summary.equipped) == "string" then summary.equipped else ""
	local luck = TitleWindowLogic.luckOf(levels)
	local out: { Row } = {}
	for tier = #TitleConfig.Titles, 1, -1 do
		local def = TitleConfig.Titles[tier]
		local isOwned = owned[def.id] == true
		local isEquipped = isOwned and equippedId == def.id
		local chance = if def.baseChance == nil then TitleWindowLogic.FALLBACK_CHANCE_TEXT else TitleWindowLogic.chanceText((def.baseChance :: number) * luck)
		table.insert(out, {
			id = def.id,
			name = def.name,
			tier = tier,
			multText = TitleWindowLogic.multText(def.mult),
			chanceText = chance,
			owned = isOwned,
			equipped = isEquipped,
			statusText = if isOwned then TitleWindowLogic.OWNED_TEXT else TitleWindowLogic.NOT_OWNED_TEXT,
			buttonText = if isEquipped then TitleWindowLogic.EQUIPPED_TEXT elseif isOwned then TitleWindowLogic.EQUIP_TEXT else TitleWindowLogic.LOCKED_TEXT,
			canEquip = isOwned and not isEquipped,
		})
	end
	return out
end

export type RollState = { canRoll: boolean, footText: string }

-- 롤 버튼 상태. 블럭스가 비용보다 적으면 잠근다(안내 — 서버가 다시 판정한다).
function TitleWindowLogic.rollState(blox: any): RollState
	local cost = TitleConfig.ROLL_COST
	local have = if type(blox) == "table" then blox else BigNum.new(0, 0)
	if BigNum.lt(have, cost) then
		return { canRoll = false, footText = TitleWindowLogic.reasonText("insufficient_blox") }
	end
	return { canRoll = true, footText = "" }
end

function TitleWindowLogic.autoText(on: boolean): string
	return if on then TitleWindowLogic.AUTO_ON_TEXT else TitleWindowLogic.AUTO_OFF_TEXT
end

local function nameOf(id: any): string
	local def = TitleConfig.get(id)
	return if def ~= nil then def.name else tostring(id)
end

-- 요청 결과 → 상태 문구(nil이면 문구를 비운다). payload = Remotes.TitleResultPayload.
function TitleWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if not payload.ok then
		return TitleWindowLogic.reasonText(tostring(payload.reason))
	end
	if payload.action == "roll" then
		if payload.isNew then
			return "새 칭호! " .. nameOf(payload.titleId)
		end
		return "이미 있는 칭호: " .. nameOf(payload.titleId)
	elseif payload.action == "equip" then
		return "장착: " .. nameOf(payload.titleId)
	end
	return nil
end

-- ===== 토스트 (S15 — 신규 칭호만, 알림층 비차단) ====================================================

export type Toast = { text: string, tier: number }

-- "새 칭호! <이름> (힘·블럭스 ×N)" — 희귀도 색. 모르는 id면 nil(띄우지 않는다).
function TitleWindowLogic.toastFor(titleId: any): Toast?
	local def, tier = TitleConfig.get(titleId)
	if def == nil or tier == nil then
		return nil
	end
	return { text = string.format("새 칭호! %s (%s)", def.name, TitleWindowLogic.multText(def.mult)), tier = tier }
end

-- TitleResult가 토스트를 띄우는가: 성공 + 새 칭호(수동 롤 응답 · 자동 롤 알림 둘 다). 중복은 조용히 사라진다.
function TitleWindowLogic.shouldToast(payload: any): boolean
	return type(payload) == "table" and payload.ok == true and payload.isNew == true
		and (payload.action == "roll" or payload.action == "autoRoll")
end

-- ===== 중복 요청 막기 (확인 단계 없음 — 소액 반복, 상점 S8과 같다) =================================
--
-- 키(roll · equip · auto)마다 결과가 올 때까지 다시 보내지 않는다. 결과가 안 오면 PENDING_TIMEOUT_SEC 뒤에 푼다.
-- 서버도 빈도를 자른다(TitleRequestService · 롤 시계) — 두 겹이다.
TitleWindowLogic.PENDING_TIMEOUT_SEC = 2 -- Claude 판단: 상점과 같은 값

export type Pending = {
	isPending: (key: string, now: number) -> boolean,
	tryBegin: (key: string, now: number) -> boolean,
	finish: (key: string) -> (),
}

function TitleWindowLogic.newPending(): Pending
	local startedAt: { [string]: number } = {}
	local pending = {}
	function pending.isPending(key: string, now: number): boolean
		local t = startedAt[key]
		return t ~= nil and now - t < TitleWindowLogic.PENDING_TIMEOUT_SEC
	end
	function pending.tryBegin(key: string, now: number): boolean
		if pending.isPending(key, now) then
			return false
		end
		startedAt[key] = now
		return true
	end
	function pending.finish(key: string)
		startedAt[key] = nil
	end
	return pending :: Pending
end

-- 결과 payload가 어느 대기 키를 푸는가. 자동 롤 알림은 아무것도 풀지 않는다.
function TitleWindowLogic.pendingKeyOf(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if payload.action == "roll" then
		return "roll"
	elseif payload.action == "equip" then
		return "equip"
	elseif payload.action == "setAuto" then
		return "auto"
	end
	return nil
end

return TitleWindowLogic

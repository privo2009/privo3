--!strict
-- 아우라 창 검증 (지시서 #11 5단계): 표시 값(AuraConfig · 서버 원본) · 확률 합 100(P3) · 행운 문구 · 잠김 사유(해금 · 잔액) ·
-- 요청이 한 번만 나가는가 · 팩 탭 · 칭호 버튼 · 희귀도 색 매핑. 실물 싱글톤이 아니라 Store.new()로 굴린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Store = require(script.Parent.Parent.UI.Store)
local AuraWindowLogic = require(script.Parent.Parent.UI.Logic.AuraWindowLogic)
local AuraWindow = require(script.Parent.Parent.UI.Screens.Window.AuraWindow)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local P1, P2 = AuraConfig.Packs[1], AuraConfig.Packs[2]
local WORLD = WorldConfig.get(1) :: any
local function summary(owned: { string }, equipped: string, pack: number?)
	return { owned = owned, equipped = equipped, selectedPack = pack or 1, hideOtherAuras = false, world = 1 }
end

-- 1. 카드 값 · 확률 -------------------------------------------------------------------------------
do
	local cards = AuraWindowLogic.cards(summary({}, ""), {}, 1)
	check("카드 4장 · 일반 → 전설 순", #cards == 4 and cards[1].id == P1.auras[1].id and cards[4].id == P1.auras[4].id)
	check("배수 문구 = '힘·데미지 ×m' (A1)", cards[4].multText == Locale.t("aura.mult", { mult = string.format("%.2f", P1.auras[4].mult) }))
	local texts, dec = RollOdds.percentages(RollOdds.distribution(P1.auras, 1))
	check("확률 = 실제 등장 확률(RollOdds)", cards[1].chanceText == texts[1] and cards[4].chanceText == texts[4], cards[1].chanceText)
	local units = 0
	for _, c in ipairs(cards) do
		units += math.floor((tonumber((string.gsub(c.chanceText, "%%", ""))) :: number) * 10 ^ dec + 0.5)
	end
	check("카드 넷 확률 합 = 정확히 100% (P3)", units == 100 * 10 ^ dec)
	local L = 8
	local lucky = AuraWindowLogic.cards(summary({}, ""), { auraLuck = L }, 1)
	local lt = RollOdds.percentages(RollOdds.distribution(P1.auras, UpgradeConfig.getEffect("auraLuck", L)))
	check("행운 반영 확률 = auraLuck 효과", lucky[4].chanceText == lt[4], lucky[4].chanceText)
	check("행운 문구 = '행운 ×N 적용'", AuraWindowLogic.luckText({ auraLuck = L }) == RollOdds.luckText(UpgradeConfig.getEffect("auraLuck", L)))
	check("희귀도 매핑: 일반 tier1 · 희귀 tier3 · 영웅 tier4 · 전설 tier5", cards[1].rarityTier == 1 and cards[2].rarityTier == 3 and cards[3].rarityTier == 4 and cards[4].rarityTier == 5)

	local owned = AuraWindowLogic.cards(summary({ P1.auras[2].id, P1.auras[3].id }, P1.auras[3].id), {}, 1)
	check("장착 중: 못 누름 · '장착 중'", owned[3].equipped and not owned[3].canEquip and owned[3].buttonText == AuraWindowLogic.EQUIPPED_TEXT)
	check("보유: 장착 가능", owned[2].owned and owned[2].canEquip)
	check("미보유: 잠김", not owned[4].owned and not owned[4].canEquip and owned[4].buttonText == AuraWindowLogic.LOCKED_TEXT)
end

-- 2. 팩 탭 · 잠김 사유 -------------------------------------------------------------------------------
do
	local tabs = AuraWindowLogic.packs(summary({}, ""), P1.rollCost)
	check("탭 = 그 월드의 팩", #tabs == #WORLD.auraPacks)
	check("팩 1 열림 · 팩 2 잠김(해금 = 롤 비용)", tabs[1].unlocked and not tabs[2].unlocked
		and string.find(tabs[2].infoText, Formatter.format(P2.rollCost), 1, true) ~= nil, tabs[2].infoText)
	check("저장된 팩이 월드에 없으면 첫 팩", AuraWindowLogic.shownPack(summary({}, "", 99)) == WORLD.auraPacks[1]
		and AuraWindowLogic.shownPack(summary({}, "", 2)) == 2)

	local locked = AuraWindowLogic.rollState(summary({}, ""), P1.rollCost, BigNum.new(1, 30), 2)
	check("잠긴 팩 → 못 굴림 · pack_locked 문구", not locked.canRoll and locked.footText == AuraWindowLogic.reasonText("pack_locked"))
	local poor = AuraWindowLogic.rollState(summary({}, ""), P1.rollCost, BigNum.sub(P1.rollCost, BigNum.fromNumber(1)), 1)
	check("블럭스 부족 → 못 굴림 · 사유", not poor.canRoll and poor.footText == AuraWindowLogic.reasonText("insufficient_blox"))
	local ok = AuraWindowLogic.rollState(summary({}, ""), P1.rollCost, P1.rollCost, 1)
	check("딱 맞으면 굴림 · 버튼에 비용", ok.canRoll and string.find(ok.buttonText, Formatter.format(P1.rollCost), 1, true) ~= nil)
	local generic = AuraWindowLogic.reasonText("???")
	for code in pairs(AuraWindowLogic.REASONS) do
		check("문구: " .. code, AuraWindowLogic.reasonText(code) ~= generic)
	end
end

-- 3. 결과 판정 (A6) -------------------------------------------------------------------------------
do
	local newLow = { action = "roll", ok = true, reason = "", auraId = P1.auras[1].id, packId = 1, tier = 1, isNew = true, equipped = true }
	local dupLow = { action = "roll", ok = true, reason = "", auraId = P1.auras[2].id, packId = 1, tier = 2, isNew = false, equipped = false }
	local dupEpic = { action = "roll", ok = true, reason = "", auraId = P1.auras[3].id, packId = 1, tier = 3, isNew = false, equipped = false }
	check("모달: 새 아우라는 등급 무관", AuraWindowLogic.shouldModal(newLow))
	check("모달: 중복 하위 등급은 아님(창 문구로만)", not AuraWindowLogic.shouldModal(dupLow) and AuraWindowLogic.resultText(dupLow) ~= nil)
	check("모달: 중복이어도 epic 이상", AuraWindowLogic.shouldModal(dupEpic))
	check("모달: 거부 · 장착은 아님", not AuraWindowLogic.shouldModal({ action = "roll", ok = false, tier = 4, isNew = true })
		and not AuraWindowLogic.shouldModal({ action = "equip", ok = true, isNew = true }))
	local v = AuraWindowLogic.resultView(newLow) :: any
	check("모달 내용: 머리말 · 이름 · 희귀도 · 배수", v.heading == Locale.t("aura.modal.new") and v.name == Names.aura(P1.auras[1].id) and v.rarityTier == 1
		and string.find(v.detail, AuraWindowLogic.multText(P1.auras[1].mult), 1, true) ~= nil)
	local t = AuraWindowLogic.toastFor(dupEpic) :: any
	check("런 중 토스트 문구 · 희귀도", t ~= nil and string.find(t.text, Names.aura(P1.auras[3].id), 1, true) ~= nil and t.tier == 4)
end

-- 4. 창 — 요청 한 번만 · 탭 · 칭호 버튼 ------------------------------------------------------------------
do
	local store = Store.new()
	store.setSource(function(s)
		s("blox", BigNum.mul(P1.rollCost, BigNum.fromNumber(5)))
		s("lifetimeBlox", P2.rollCost)
		s("auras", summary({ P1.auras[1].id }, "", 1))
	end)
	local clock = 0
	local sends: { any } = {}
	local titles = 0
	local h = AuraWindow.create({
		store = store,
		sendRequest = function(p)
			table.insert(sends, p)
		end,
		onClose = function() end,
		openTitles = function()
			titles += 1
		end,
		now = function()
			return clock
		end,
	})
	local d = h._debug
	d.pressRoll()
	d.pressRoll()
	check("뽑기: 결과 대기 중 두 번째는 안 나간다 · 팩 번호 실림", #sends == 1 and sends[1].action == "roll" and sends[1].pack == 1)
	h.onResult({ action = "roll", ok = true, reason = "", auraId = P1.auras[1].id, packId = 1, tier = 1, isNew = false, equipped = false })
	check("뽑기: 결과 뒤에도 롤 시계 동안 잠김 · 상태 문구", d.rollButton.isDisabled() and d.status.Text ~= "")
	clock += AuraConfig.ROLL_INTERVAL_SEC + 0.01
	h.refresh()
	d.pressRoll()
	check("뽑기: 롤 시계가 지나면 다시 나간다", #sends == 2)
	d.pressEquip(1)
	check("장착: 보유 · 미장착이면 equip 1건", sends[3] ~= nil and sends[3].action == "equip" and sends[3].auraId == P1.auras[1].id)
	d.pressEquip(4)
	check("장착: 미보유는 안 나간다", #sends == 3)
	d.pressTab(2)
	check("탭: 다른 팩을 누르면 바로 바뀌고 selectPack 1건", d.shownPack() == 2 and sends[4] ~= nil and sends[4].action == "selectPack" and sends[4].pack == 2)
	check("탭: 팩 2 카드로 바뀐다", d.view()[1].id == P2.auras[1].id)
	d.pressTab(2)
	check("탭: 같은 팩을 다시 누르면 아무것도 안 나간다", #sends == 4)
	h.onResult({ action = "selectPack", ok = false, reason = "invalid_request", auraId = "", packId = 0, tier = 0, isNew = false, equipped = false })
	check("탭: 서버가 거부하면 저장된 팩으로 되돌린다", d.shownPack() == 1)
	d.pressTitles()
	check("칭호 버튼 → 칭호 창 열기", titles == 1)
	local colorOk = true
	for i, parts in ipairs(d.cards) do
		if parts.name.TextColor3 ~= UiTheme.rarityColor(d.view()[i].rarityTier) then
			colorOk = false
		end
	end
	check("카드 이름 = 희귀도 색", colorOk)
	check("행운 줄 · 안내 줄이 채워진다", d.luck.Text == AuraWindowLogic.luckText(nil) and d.info.Text ~= "")
	check("큰 창 · Offset 0", h.root.Size.X.Offset == 0 and h.root.Size.Y.Offset == 0)
	h.root:Destroy()
end

do
	local store = Store.new()
	store.setSource(function(s)
		s("blox", BigNum.new(1, 30))
		s("lifetimeBlox", BigNum.new(0, 0))
		s("auras", summary({}, "", 1))
	end)
	local sends = 0
	local h = AuraWindow.create({ store = store, sendRequest = function() sends += 1 end, onClose = function() end, openTitles = function() end })
	h._debug.pressRoll()
	check("잠긴 팩: 뽑기 회색 · 요청 없음 · 사유", h._debug.rollButton.isDisabled() and sends == 0 and h._debug.rollFoot.Text == AuraWindowLogic.reasonText("pack_locked"))
	h.root:Destroy()
end

print(string.format("[AuraWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AuraWindowTests] %d test(s) failed", failed))
end

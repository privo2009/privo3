--!strict
-- 펫 창 · 펫 추적 표시 검증 (지시서 #12 4단계): 표시 값(PetConfig · 서버 원본) · 확률 합 100(P3) · 행운 문구 · 잠김 사유(해금 · 보관함 · 잔액) ·
-- 요청이 한 번만 나가는가 · 격자 · 장착 슬롯 수가 파생값을 따른다 · 크래프팅 가능 판정 · 놓아주기 확인 단계 · 결과 연출 판정 ·
-- 추적 렌더러 계획(풀 상한 · 숨기기 · 내 펫 먼저). 실물 싱글톤이 아니라 Store.new()로 굴린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Store = require(script.Parent.Parent.UI.Store)
local PetWindowLogic = require(script.Parent.Parent.UI.Logic.PetWindowLogic)
local PetWindow = require(script.Parent.Parent.UI.Screens.Window.PetWindow)
local PetRenderLogic = require(script.Parent.Parent.World.PetRenderLogic)

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

local E1, E2, E3 = PetConfig.Eggs[1], PetConfig.Eggs[2], PetConfig.Eggs[3]

local function entry(uid: string, petId: string, level: number?)
	return { uid = uid, petId = petId, level = level or 1 }
end

local function summary(owned: { any }?, equipped: { string }?, slots: number?, storage: number?)
	return { owned = owned or {}, equipped = equipped or {}, slots = slots or PetConfig.getSlots(0, false),
		storage = storage or PetConfig.getStorage(false), hideOtherPets = false, world = 1 }
end

-- 1. 알 · 확률 · 행운 ------------------------------------------------------------------------------
do
	local tabs = PetWindowLogic.eggs(summary(), E2.rollCost)
	check("알 탭: 월드 1 알 3개 · 열린 둘 · 잠긴 셋째", #tabs == 3 and tabs[1].unlocked and tabs[2].unlocked and not tabs[3].unlocked)
	check("잠긴 알: 해금 조건 = 부화 1회 비용(G8)", string.find(tabs[3].infoText, Formatter.format(E3.rollCost), 1, true) ~= nil and tabs[3].label == Locale.t("pet.egg.tabLocked", { egg = Names.egg(3) }))
	check("열린 알: 1회 비용", string.find(tabs[1].infoText, Formatter.format(E1.rollCost), 1, true) ~= nil)
	check("처음 보이는 알 = 열린 것 중 가장 높은 알", PetWindowLogic.defaultEgg(summary(), E2.rollCost) == 2 and PetWindowLogic.defaultEgg(summary(), BigNum.new(0, 0)) == 1)

	local odds = PetWindowLogic.odds(1, {})
	local texts, dec = RollOdds.percentages(RollOdds.distribution(E1.pets, 1))
	check("확률 줄 4개 = 실제 등장 확률(RollOdds) · 이름 · ×m", #odds == 4 and string.find(odds[1].text, texts[1], 1, true) ~= nil
		and string.find(odds[4].text, Names.pet(E1.pets[4].id), 1, true) ~= nil and string.find(odds[4].text, string.format("×%.2f", E1.pets[4].mult), 1, true) ~= nil)
	local units = 0
	for _, t in ipairs(texts) do
		units += math.floor((tonumber((string.gsub(t, "%%", ""))) :: number) * 10 ^ dec + 0.5)
	end
	check("확률 넷 합 = 정확히 100% (P3)", units == 100 * 10 ^ dec)
	local L = 9
	local lucky = PetWindowLogic.odds(1, { petLuck = L })
	local lt = RollOdds.percentages(RollOdds.distribution(E1.pets, UpgradeConfig.getEffect("petLuck", L)))
	check("행운 반영 확률 = petLuck 효과", string.find(lucky[4].text, lt[4], 1, true) ~= nil, lucky[4].text)
	check("행운 문구 = '행운 ×N 적용'", PetWindowLogic.luckText({ petLuck = L }) == RollOdds.luckText(UpgradeConfig.getEffect("petLuck", L)))
	check("희귀도 매핑: 아우라와 같다(1 · 3 · 4 · 5)", odds[1].rarityTier == 1 and odds[2].rarityTier == 3 and odds[3].rarityTier == 4 and odds[4].rarityTier == 5)
end

-- 2. 부화 잠김 사유 --------------------------------------------------------------------------------
do
	local rich = BigNum.mul(E2.rollCost, BigNum.fromNumber(10))
	check("부화 가능: 열린 알 · 자리 있음 · 잔액 충분", PetWindowLogic.hatchState(summary(), E2.rollCost, rich, 1).canHatch)
	check("부화 버튼 = 비용", PetWindowLogic.hatchState(summary(), E2.rollCost, rich, 2).buttonText == Locale.t("pet.hatchCost", { cost = Formatter.format(E2.rollCost) }))
	local locked = PetWindowLogic.hatchState(summary(), E2.rollCost, rich, 3)
	check("잠긴 알 → egg_locked 문구", not locked.canHatch and locked.footText == PetWindowLogic.reasonText("egg_locked"))
	local full = {}
	for i = 1, 3 do
		full[i] = entry(tostring(i), E1.pets[1].id)
	end
	local st = PetWindowLogic.hatchState(summary(full, {}, 2, 3), E2.rollCost, rich, 1)
	check("보관함 가득(파생 저장 공간) → storage_full 문구", not st.canHatch and st.footText == PetWindowLogic.reasonText("storage_full"))
	local poor = PetWindowLogic.hatchState(summary(), E2.rollCost, BigNum.sub(E1.rollCost, BigNum.fromNumber(1)), 1)
	check("잔액 부족 → insufficient_blox 문구", not poor.canHatch and poor.footText == PetWindowLogic.reasonText("insufficient_blox"))
end

-- 3. 격자 · 슬롯 · 상세 ------------------------------------------------------------------------------
do
	local owned = { entry("1", E1.pets[1].id), entry("2", E2.pets[2].id), entry("3", E1.pets[1].id, 3), entry("4", E1.pets[3].id) }
	local s = summary(owned, { "4" })
	local g = PetWindowLogic.grid(s)
	check("격자: 보유 전부 · 장착 먼저 · 그다음 실효 증가분 큰 순", #g == 4 and g[1].uid == "4" and g[2].gain >= g[3].gain and g[3].gain >= g[4].gain)
	check("격자: 이름 · 강화 단계 이름 · 희귀도 색 단계", g[1].name == Names.pet(E1.pets[3].id) and g[1].levelName == Names.petLevel(1) and g[1].rarityTier == 4)
	check("보유 문구 = 보유 수 / 파생 저장 공간", PetWindowLogic.storageText(s) == Locale.t("pet.storage", { n = 4, max = PetConfig.getStorage(false) }))
	local slots = PetWindowLogic.slots(s)
	check("장착 슬롯 수 = 파생 슬롯(기본)", #slots == PetConfig.getSlots(0, false) and slots[1].uid == "4" and slots[2].uid == nil
		and slots[2].text == PetWindowLogic.EMPTY_SLOT_TEXT)
	check("장착 슬롯 수 = 파생 슬롯(업그레이드 +1)", #PetWindowLogic.slots(summary(owned, { "4" }, PetConfig.getSlots(1, false))) == PetConfig.getSlots(1, false))
	check("장착 문구 = 장착 수 / 슬롯", PetWindowLogic.slotsText(s) == Locale.t("pet.slots", { n = 1, max = PetConfig.getSlots(0, false) }))

	local d4 = PetWindowLogic.detail(s, "4") :: PetWindowLogic.Detail
	check("상세(장착 중): 해제 · 놓아주기 막힘 · 사유", d4.equipped and d4.equipText == PetWindowLogic.UNEQUIP_TEXT and not d4.canRelease
		and d4.releaseFoot == PetWindowLogic.reasonText("pet_equipped"))
	local d1 = PetWindowLogic.detail(s, "1") :: PetWindowLogic.Detail
	check("상세(보유): 장착 가능 · 놓아주기 가능 · 실효 증가분 문구", d1.canEquip and d1.canRelease
		and string.find(d1.infoText, PetWindowLogic.gainText(PetConfig.effectiveGain(E1.pets[1].id, 1)), 1, true) ~= nil)
	check("상세: 크래프팅은 같은 펫 3마리가 있어야 (2/3이면 막힘)", not d1.canCraft and string.find(d1.craftText, "(2/3)", 1, true) == nil
		and string.find(d1.craftText, "(1/3)", 1, true) ~= nil)
	local three = { entry("1", E1.pets[1].id), entry("2", E1.pets[1].id), entry("3", E1.pets[1].id) }
	local d3 = PetWindowLogic.detail(summary(three), "2") :: PetWindowLogic.Detail
	check("상세: 같은 petId · 같은 단계 3마리면 크래프팅 가능 · 다음 단계 이름", d3.canCraft and string.find(d3.craftText, Names.petLevel(2), 1, true) ~= nil)
	local top = PetWindowLogic.detail(summary({ entry("9", E1.pets[1].id, PetConfig.MAX_LEVEL) }), "9") :: PetWindowLogic.Detail
	check("상세: 최고 단계면 크래프팅 없음", not top.canCraft and top.craftText == Locale.t("pet.craftMax"))
	local fullSlots = summary({ entry("1", E1.pets[1].id), entry("2", E1.pets[2].id), entry("3", E1.pets[3].id) }, { "1", "2" })
	check("상세: 슬롯이 차면 장착 막힘(파생 슬롯)", not (PetWindowLogic.detail(fullSlots, "3") :: PetWindowLogic.Detail).canEquip)
	check("상세: 없는 uid → nil", PetWindowLogic.detail(s, "404") == nil and PetWindowLogic.detail(s, nil) == nil)
end

-- 4. 결과 연출 판정 (E8) ---------------------------------------------------------------------------
do
	local base = { action = "hatch", ok = true, reason = "", uid = "5", petId = E1.pets[1].id, eggId = 1, rarity = 1, level = 1, isNew = false, equipped = false }
	check("모달: 중복 하위 등급은 안 띄운다", not PetWindowLogic.shouldModal(base))
	local n = table.clone(base)
	n.isNew = true
	check("모달: 새 펫이면 띄운다", PetWindowLogic.shouldModal(n))
	local epic = table.clone(base)
	epic.petId = E1.pets[3].id
	epic.rarity = 3
	check("모달: 영웅(3) 이상이면 중복이어도 띄운다", PetWindowLogic.shouldModal(epic))
	local craft = table.clone(n)
	craft.action = "craft"
	check("모달: 크래프팅 · 거부는 안 띄운다(창 안 문구)", not PetWindowLogic.shouldModal(craft) and not PetWindowLogic.shouldModal({ action = "hatch", ok = false, isNew = true }))
	local v = PetWindowLogic.resultView(n) :: PetWindowLogic.ResultView
	check("모달 내용: 머리말 · 이름 · 희귀도 색 단계", v.heading == Locale.t("pet.modal.new") and v.name == Names.pet(E1.pets[1].id) and v.rarityTier == 1)
	local toast = PetWindowLogic.toastFor(epic)
	check("런 중 토스트: 한 줄 · 희귀도 단계", toast ~= nil and string.find(toast.text, Names.pet(E1.pets[3].id), 1, true) ~= nil and toast.tier == 4)
	check("상태 문구: 거부 사유 · 크래프팅 결과", PetWindowLogic.resultText({ action = "hatch", ok = false, reason = "storage_full" }) == PetWindowLogic.reasonText("storage_full")
		and string.find(PetWindowLogic.resultText({ action = "craft", ok = true, petId = E1.pets[1].id, level = 2 }) :: string, Names.petLevel(2), 1, true) ~= nil)
end

-- 5. 창: 요청 한 번만 · 놓아주기 확인 단계 · 격자 · 슬롯 -------------------------------------------------
do
	local store = Store.new()
	local setter: any = nil
	local owned = { entry("1", E1.pets[1].id), entry("2", E1.pets[1].id), entry("3", E1.pets[1].id), entry("4", E1.pets[2].id) }
	store.setSource(function(s)
		setter = s
		s("blox", BigNum.mul(E1.rollCost, BigNum.fromNumber(10)))
		s("lifetimeBlox", E1.rollCost)
		s("upgrades", { petLuck = 0 })
		s("pets", summary(owned, { "4" }))
	end)
	local clock = 100
	local sends: { any } = {}
	local h = PetWindow.create({
		store = store,
		sendRequest = function(p)
			table.insert(sends, p)
		end,
		onClose = function() end,
		now = function()
			return clock
		end,
	})
	task.wait()
	h.refresh()
	check("창: 큰 창(Large)", math.abs(h.root.Size.X.Scale - 0.85) < 1e-6)
	check("창: 확률 줄 4개 희귀도 색", h._debug.odds[4].TextColor3 == UiTheme.rarityColor(5) and h._debug.odds[1].Text ~= "")
	check("창: 보이는 알 = 열린 알 1 · 부화 버튼 켜짐", h._debug.shownEgg() == 1 and not h._debug.hatchButton.isDisabled())
	local visibleCells = 0
	for _, c in ipairs(h._debug.cells) do
		if c.frame.Visible then
			visibleCells += 1
		end
	end
	check("창: 격자 칸 수 = 보유 수 · 스크롤 캔버스 ≥ 1", visibleCells == 4 and h._debug.grid.CanvasSize.Y.Scale >= 1)
	local shownSlots = 0
	for _, sl in ipairs(h._debug.slots) do
		if sl.frame.Visible then
			shownSlots += 1
		end
	end
	check("창: 장착 슬롯 칸 = 파생 슬롯", shownSlots == PetConfig.getSlots(0, false))
	check("창: 칸 · 버튼 크기 Scale만(Offset 0)", h._debug.grid.Size.X.Offset == 0 and h._debug.cells[1].frame.Size.Y.Offset == 0
		and h._debug.hatchButton.root.Size.Y.Offset == 0)

	h._debug.pressHatch()
	h._debug.pressHatch()
	check("부화: 결과 대기 중 두 번째는 안 나간다 · 알 번호만 싣는다", #sends == 1 and sends[1].action == "hatch" and sends[1].egg == 1 and sends[1].cost == nil)
	h.onResult({ action = "hatch", ok = true, reason = "", uid = "5", petId = E1.pets[1].id, eggId = 1, rarity = 1, level = 1, isNew = false, equipped = false })
	h._debug.pressHatch()
	check("부화: 결과 뒤에도 롤 시계 동안은 안 나간다", #sends == 1)
	clock += PetConfig.HATCH_INTERVAL_SEC + 0.01
	h._debug.pressHatch()
	check("부화: 시계가 지나면 다시 나간다", #sends == 2)
	h.onResult({ action = "hatch", ok = false, reason = "storage_full", uid = "", petId = "", eggId = 0, rarity = 0, level = 0, isNew = false, equipped = false })
	check("부화 거부 → 상태 문구", h._debug.status.Text == PetWindowLogic.reasonText("storage_full"))

	h._debug.select("1")
	check("고르기: 이름 · 희귀도 색", h._debug.selName.Text == Names.pet(E1.pets[1].id) and h._debug.selected() == "1")
	check("고르기: 같은 펫 3마리 → 크래프팅 켜짐", not h._debug.craftButton.isDisabled())
	h._debug.pressCraft()
	h._debug.pressCraft()
	check("크래프팅: 한 번만 · uid만 싣는다", #sends == 3 and sends[3].action == "craft" and sends[3].uid == "1")

	h._debug.pressRelease()
	check("놓아주기: 첫 누름은 확인 단계(요청 없음 · 문구 바뀜)", #sends == 3 and h._debug.releaseLabel.Text == PetWindowLogic.RELEASE_CONFIRM_TEXT)
	clock += PetWindowLogic.RELEASE_CONFIRM_SEC + 0.1
	h._debug.pressRelease()
	check("놓아주기: 확인 시간이 지나면 처음부터(요청 없음)", #sends == 3)
	h._debug.pressRelease()
	check("놓아주기: 확인 시간 안 두 번째 누름에만 요청", #sends == 4 and sends[4].action == "release" and sends[4].uid == "1")
	h._debug.select("4")
	h._debug.pressRelease()
	h._debug.pressRelease()
	check("놓아주기: 장착 중이면 버튼 잠김 · 요청 없음", h._debug.releaseButton.isDisabled() and #sends == 4)
	h._debug.pressEquip()
	check("장착 중 펫 → 해제 요청", #sends == 5 and sends[5].action == "unequip" and sends[5].uid == "4")
	h._debug.pressBest()
	check("최고 장착 → equipBest 요청(필드 없음)", #sends == 6 and sends[6].action == "equipBest" and sends[6].uid == nil)

	-- 서버가 크래프팅 결과를 실어 오면 재료가 사라지고 새 펫이 고른 상태가 된다
	h.onResult({ action = "craft", ok = true, reason = "", uid = "6", petId = E1.pets[1].id, eggId = 1, rarity = 1, level = 2, isNew = false, equipped = false })
	setter("pets", summary({ entry("4", E1.pets[2].id), entry("6", E1.pets[1].id, 2) }, { "4" }, PetConfig.getSlots(1, false)))
	task.wait()
	h.refresh()
	check("크래프팅 결과: 새 펫을 고른다", h._debug.selected() == "6" and h._debug.selName.Text == Names.pet(E1.pets[1].id))
	visibleCells = 0
	for _, c in ipairs(h._debug.cells) do
		if c.frame.Visible then
			visibleCells += 1
		end
	end
	shownSlots = 0
	for _, sl in ipairs(h._debug.slots) do
		if sl.frame.Visible then
			shownSlots += 1
		end
	end
	check("보유가 줄면 칸을 숨긴다(풀) · 슬롯 수가 파생값을 따라 는다", visibleCells == 2 and shownSlots == PetConfig.getSlots(1, false))
	h.root:Destroy()
end

-- 6. 추적 렌더러 계획 (E9) --------------------------------------------------------------------------
do
	local a = PetConfig.serializeEquipped({ { petId = E1.pets[1].id, tier = 1 }, { petId = E2.pets[4].id, tier = 3 } })
	local plans = PetRenderLogic.plan({ { key = "other", attribute = a, isLocal = false }, { key = "me", attribute = a, isLocal = true } }, false)
	check("계획: 내 펫이 먼저", #plans == 2 and plans[1].key == "me")
	check("계획: 강화 단계 2 이상이면 껍질(파트 2) · 크기는 단계별", plans[1].pets[1].parts == 1 and plans[1].pets[2].parts == 2
		and plans[1].pets[2].size == PetConfig.DISPLAY.SIZE_BY_LEVEL[3])
	local hidden = PetRenderLogic.plan({ { key = "other", attribute = a, isLocal = false }, { key = "me", attribute = a, isLocal = true } }, true)
	check("숨기기: 다른 사람 펫은 빠지고 내 펫은 남는다", #hidden == 1 and hidden[1].key == "me")
	local crowd = {}
	local six = {}
	for i = 1, PetConfig.MaxSlots do
		six[i] = { petId = E3.pets[4].id, tier = PetConfig.MAX_LEVEL }
	end
	local big = PetConfig.serializeEquipped(six)
	for i = 1, 40 do
		crowd[i] = { key = i, attribute = big, isLocal = i == 25 }
	end
	local many = PetRenderLogic.plan(crowd, false)
	check("상한: 사람이 많아도 파트 합 ≤ MAX_TOTAL_PARTS · 내 펫은 다 그린다", PetRenderLogic.totalParts(many) <= PetConfig.DISPLAY.MAX_TOTAL_PARTS
		and many[1].key == 25 and #many[1].pets == PetConfig.MaxSlots)
	check("계획: 깨진 Attribute는 빈 계획", #PetRenderLogic.plan({ { key = "x", attribute = "ghost:1,,", isLocal = false } }, false) == 0)
	local o1, o2 = PetRenderLogic.offset(1, 2), PetRenderLogic.offset(2, 2)
	check("자리: 캐릭터 뒤(+Z) · 가운데 정렬", o1.Z > 0 and math.abs(o1.X + o2.X) < 1e-9 and o1.X < o2.X)
	check("치는 모습: 반경 밖이면 0 · 안이면 0~1", PetRenderLogic.punchPhase(false, 1.3, 1) == 0
		and PetRenderLogic.punchPhase(true, 1.3, 1) >= 0 and PetRenderLogic.punchPhase(true, 1.3, 1) <= 1)
end

print(string.format("[PetWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PetWindowTests] %d test(s) failed", failed))
end

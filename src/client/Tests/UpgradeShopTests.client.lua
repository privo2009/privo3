--!strict
-- 상점 창(업그레이드) 검증 (Phase 6 지시서 #7 U5): 표시 값(UpgradeConfig 원본) · 잠김(최대 레벨 MAX · 블럭스 부족) ·
-- 사유 문구 · 구매 요청이 한 번만 나가는가(결과 대기 중 · 잠김) · 로벅스 자리는 숨김 · 창 규격.
-- 실물 싱글톤이 아니라 Store.new()로 굴린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Store = require(script.Parent.Parent.UI.Store)
local UpgradeShopLogic = require(script.Parent.Parent.UI.Logic.UpgradeShopLogic)
local UpgradeShopWindow = require(script.Parent.Parent.UI.Screens.Window.UpgradeShopWindow)
local PurchaseClient = require(script.Parent.Parent.Net.PurchaseClient)

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

-- 1. 표시 값 — UpgradeConfig 원본 ------------------------------------------------------------------
do
	local rich = BigNum.new(1, 30)
	local r = UpgradeShopLogic.row("punchDamage", 3, rich)
	check("값: 비용 = getCostAtLevel(지금 레벨)", r.cost ~= nil and BigNum.eq(r.cost :: any, UpgradeConfig.getCostAtLevel("punchDamage", 3)))
	check("값: 효과 문구 = getEffect(지금) → getEffect(다음)", r.effectText == UpgradeShopLogic.formatEffect("punchDamage", UpgradeConfig.getEffect("punchDamage", 3))
		.. " → " .. UpgradeShopLogic.formatEffect("punchDamage", UpgradeConfig.getEffect("punchDamage", 4)), r.effectText)
	check("값: 비용 문구에 Formatter 값", string.find(r.footText, Formatter.format(UpgradeConfig.getCostAtLevel("punchDamage", 3)), 1, true) ~= nil, r.footText)
	check("값: 무한 항목은 Lv N", string.find(r.title, Locale.t("upgrade.level", { n = 3 }), 1, true) ~= nil and string.find(r.title, "/", 1, true) == nil, r.title)
	local s = UpgradeShopLogic.row("punchSpeed", 2, rich)
	check("값: 상한 항목은 Lv N/최대", string.find(s.title, Locale.t("upgrade.levelMax", { n = 2, max = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number }), 1, true) ~= nil, s.title)
	check("값: 펀치 속도 단위", string.find(s.effectText, Locale.t("upgrade.effect.perSec", { value = string.format("%.2f", UpgradeConfig.getEffect("punchSpeed", 2)) }), 1, true) ~= nil, s.effectText)
	check("값: 살 수 있으면 켜짐 · 사유 없음", r.canBuy and r.reason == nil and r.buttonText == UpgradeShopLogic.BUY_TEXT)
	local rows = UpgradeShopLogic.rows({}, rich)
	local order = {}
	for _, row in ipairs(rows) do
		table.insert(order, row.name)
	end
	check("값: 7줄(L3) · SHOP_ORDER 순서", table.concat(order, ",") == table.concat(UpgradeConfig.SHOP_ORDER, ",") and #order == 7, table.concat(order, ","))
	check("값: 레벨 표가 비면 0레벨로 본다", UpgradeShopLogic.levelOf({}, "bloxGain") == 0 and UpgradeShopLogic.levelOf(nil, "bloxGain") == 0)
	local luckRow = UpgradeShopLogic.row("titleLuck", 2, rich)
	local expectLuck = Locale.t("upgrade.effect.luck", { value = string.format("%.2f", UpgradeConfig.getEffect("titleLuck", 2)) }) .. string.format(" → ×%.2f", UpgradeConfig.getEffect("titleLuck", 3))
	check("값: 행운 줄 효과 = '행운 ×현재 → ×다음' (지시서 #11 P3)", luckRow.effectText == expectLuck, luckRow.effectText)
end

-- 2. 잠김 ------------------------------------------------------------------------------------------
do
	local top = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number
	local m = UpgradeShopLogic.row("punchSpeed", top, BigNum.new(1, 30))
	check("잠김: 최대 레벨 → MAX · 못 산다 · 비용 없음", m.isMax and not m.canBuy and m.buttonText == UpgradeShopLogic.MAX_TEXT and m.cost == nil)
	check("잠김: 최대 레벨 문구", m.footText == UpgradeShopLogic.reasonText(UpgradeConfig.REASON_MAX_LEVEL))
	local cost = UpgradeConfig.getCostAtLevel("bloxGain", 0)
	local poor = UpgradeShopLogic.row("bloxGain", 0, BigNum.sub(cost, BigNum.fromNumber(1)))
	check("잠김: 블럭스 부족 → 못 산다 + 사유", not poor.canBuy and poor.reason == UpgradeConfig.REASON_INSUFFICIENT_BLOX
		and string.find(poor.footText, UpgradeShopLogic.reasonText(UpgradeConfig.REASON_INSUFFICIENT_BLOX), 1, true) ~= nil, poor.footText)
	local exact = UpgradeShopLogic.row("bloxGain", 0, cost)
	check("잠김: 딱 맞으면 산다(서버 canBuy와 같은 경계)", exact.canBuy)
end

-- 2b. 이동 속도 줄 삭제 (L3, 지시서 #13 — 지시서 #8 "최대 속도 도달" 잠금도 함께 없어졌다) -------------------------
do
	local names = {}
	for _, row in ipairs(UpgradeShopLogic.rows({}, BigNum.new(1, 30))) do
		names[row.name] = true
	end
	check("L3: 상점에 이동 속도 줄이 없다 · 이름 표에도 없다", names.moveSpeed == nil and not Locale.has("upgrade.name.moveSpeed"))
	check("L3: '최대 속도 도달' 문구가 어떤 줄에도 없다(힘이 커도)", (function()
		for _, row in ipairs(UpgradeShopLogic.rows({}, BigNum.new(1, 30))) do
			if string.find(row.footText, "최대 속도", 1, true) ~= nil or string.find(row.footText, "Max speed", 1, true) ~= nil then
				return false
			end
		end
		return true
	end)())
end

-- 3. 사유 문구 -------------------------------------------------------------------------------------
do
	local generic = UpgradeShopLogic.reasonText("???")
	for _, code in ipairs({ UpgradeConfig.REASON_MAX_LEVEL, UpgradeConfig.REASON_INSUFFICIENT_BLOX, UpgradeConfig.REASON_INVALID_UPGRADE, "rate_limited", "no_profile", "partial_failure" }) do
		check("문구: " .. code, UpgradeShopLogic.reasonText(code) ~= generic)
	end
end

-- 4. 창 ------------------------------------------------------------------------------------------
local function makeWindow(bloxValue: BigNum.BigNumber, levels: { [string]: number })
	local store = Store.new()
	store.setSource(function(setter)
		setter("blox", bloxValue)
		setter("upgrades", levels)
	end)
	local clock = 0
	local w = { sends = {} :: { string }, closes = 0 }
	local handle = UpgradeShopWindow.create({
		store = store,
		sendRequest = function(name: string)
			table.insert(w.sends, name)
		end,
		-- 로벅스 탭 요청은 가짜로 받는다(이 파일은 업그레이드 탭만 본다 — 로벅스 탭은 RobuxShopTests)
		purchase = PurchaseClient.new({ send = function() end }),
		onClose = function()
			w.closes += 1
		end,
		now = function()
			return clock
		end,
	})
	local function advance(sec: number)
		clock += sec
	end
	return handle, w, advance
end

do
	local zeros = { punchDamage = 0, punchSpeed = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number, bloxGain = 0, auraLuck = 0, titleLuck = 0, petLuck = 0, petSlots = 0 }
	local blox = UpgradeConfig.getCostAtLevel("punchDamage", 0) -- 0레벨 하나는 딱 살 수 있다
	local handle, w, advance = makeWindow(blox, zeros)

	check("창: 작은 창 60% × 70%", math.abs(handle.root.Size.X.Scale - 0.6) < 1e-6 and math.abs(handle.root.Size.Y.Scale - 0.7) < 1e-6)
	local n = 0
	for _ in pairs(handle._debug.rows) do
		n += 1
	end
	check("창: 줄 수 = SHOP_ORDER (지시서 #13 L3 뒤 7 — 펫 슬롯 · 펫 행운 포함)", n == #UpgradeConfig.SHOP_ORDER and n == 7)
	local L = UpgradeShopWindow.Layout
	check("창: 7줄도 스크롤 목록 — 줄은 목록 안 · 캔버스 > 보이는 높이", handle._debug.rows.petLuck.frame.Parent == handle._debug.list
		and handle._debug.list.CanvasSize.Y.Scale > 1 and math.abs(handle._debug.list.CanvasSize.Y.Scale - L.CANVAS_K) < 1e-5) -- UDim Scale은 float32
	check("창: 줄 높이는 #11 값 그대로(본문 기준 0.15 — 폰 줄 안 두 칸 11px)", math.abs(handle._debug.rows.punchDamage.frame.Size.Y.Scale * L.LIST_H * L.CANVAS_K - L.ROW_H) < 1e-5
		and handle._debug.rows.punchDamage.frame.Size.Y.Offset == 0)
	check("창: 펫 슬롯 줄 = '슬롯 +0 → 슬롯 +1'", handle._debug.rows.petSlots.effect.Text == Locale.t("upgrade.effect.slots", { n = 0 }) .. " → " .. Locale.t("upgrade.effect.slots", { n = 1 }), handle._debug.rows.petSlots.effect.Text)
	check("창: 펫 행운 줄 = '행운 ×현재 → ×다음'(P3)", string.find(handle._debug.rows.petLuck.effect.Text, Locale.t("upgrade.effect.luck", { value = "" }), 1, true) == 1
		and string.find(handle._debug.rows.petLuck.effect.Text, "→ ×", 1, true) ~= nil)
	local dmg = handle._debug.rows.punchDamage
	check("창: 줄 문구 = 로직 값", dmg.title.Text == UpgradeShopLogic.row("punchDamage", 0, blox).title and dmg.effect.Text == UpgradeShopLogic.row("punchDamage", 0, blox).effectText)
	check("창: 살 수 있는 줄은 버튼 켜짐", not dmg.button.isDisabled())
	check("창: 최대 레벨 줄은 MAX · 회색", handle._debug.rows.punchSpeed.buttonLabel.Text == UpgradeShopLogic.MAX_TEXT and handle._debug.rows.punchSpeed.button.isDisabled())
	local noSlot = true
	for _, parts in pairs(handle._debug.rows) do
		if parts.frame:FindFirstChild("RobuxSlot") ~= nil then
			noSlot = false
		end
	end
	check("창: RobuxSlot(숨김 자리)은 지웠다 — 업그레이드는 로벅스로 팔지 않는다(지시서 #16)", noSlot)
	check("창: 처음 탭은 업그레이드 · 업그레이드 목록만 보인다", handle._debug.tab() == UpgradeShopWindow.TAB_UPGRADE and handle._debug.list.Visible
		and not handle._debug.robuxList.Visible)

	-- 한 번 누르면 한 번 나간다(확인 단계 없음 — S8)
	handle._debug.press("punchDamage")
	check("구매: 한 번 누름에 요청 1회 · 항목 이름", #w.sends == 1 and w.sends[1] == "punchDamage")
	check("구매: 결과 대기 중에는 버튼 잠김", dmg.button.isDisabled())
	handle._debug.press("punchDamage")
	advance(0.5)
	handle._debug.press("punchDamage")
	check("구매: 결과 대기 중 연타는 더 안 나간다", #w.sends == 1, tostring(#w.sends))

	-- 결과가 오면 다시 받는다
	handle.onResult({ ok = true, reason = "", name = "punchDamage", level = 1, cost = blox })
	check("결과: 성공 문구", handle._debug.status.Text == UpgradeShopWindow.successText("punchDamage", 1, blox), handle._debug.status.Text)
	check("결과: 대기 풀림 → 다시 누를 수 있다", not dmg.button.isDisabled())
	handle._debug.press("punchDamage")
	check("결과 뒤 다시 누르면 다시 나간다", #w.sends == 2)

	-- 결과가 안 오면 시간이 지난 뒤 다시 받는다
	advance(UpgradeShopLogic.PENDING_TIMEOUT_SEC + 0.1)
	handle._debug.press("punchDamage")
	check("대기 시간이 지나면 다시 나간다", #w.sends == 3)
	handle.onResult({ ok = false, reason = UpgradeConfig.REASON_INSUFFICIENT_BLOX, name = "punchDamage", level = 0, cost = { m = 0, e = 0 } })
	check("결과: 거부 사유 문구", handle._debug.status.Text == UpgradeShopLogic.reasonText(UpgradeConfig.REASON_INSUFFICIENT_BLOX))

	-- 잠긴 줄은 눌러도 안 나간다
	handle._debug.press("punchSpeed")
	check("잠김: 최대 레벨 줄은 눌러도 요청 없음", #w.sends == 3)
	handle.root:Destroy()
end

do
	-- 블럭스 0이면 4줄 다 잠김, 눌러도 아무것도 안 나간다
	local handle, w = makeWindow(BigNum.new(0, 0), {})
	local allLocked = true
	for _, parts in pairs(handle._debug.rows) do
		if not parts.button.isDisabled() then
			allLocked = false
		end
	end
	check("잠김: 블럭스 0이면 4줄 다 회색", allLocked)
	for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		handle._debug.press(name)
	end
	check("잠김: 블럭스 0이면 어떤 줄도 요청 없음", #w.sends == 0)
	handle._debug.close()
	check("창: X는 onClose를 부른다", w.closes == 1)
	handle.root:Destroy()
end

print(string.format("[UpgradeShopTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UpgradeShopTests] %d test(s) failed", failed))
end

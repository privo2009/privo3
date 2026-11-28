--!strict
-- 유료 랜덤 상품 확률 표시 점검 (지시서 #27 단계 2 — docs/POLICY_CHECK.md "상품 × 화면 점검표"의 테스트 원본).
-- 공식 https://create.roblox.com/docs/production/monetization/paid-random-items (2026-11-20 다시 읽음):
--   ① 사기 전에 결과 전부 · 실제 확률(% · 합 100) ② 확률을 바꾸는 상품은 사기 전에 설명 ③ 활성 중엔 바뀐 확률을 보인다
--   ④ 제한 유저(ArePaidRandomItemsRestricted)는 유료 랜덤 · 행운 상품을 쓸 수 없다(우리 처리 = 숨김 · 효과 끔)
-- 순수 로직(RobuxShopLogic · 창 Logic) + 아우라 창 실물(확률 보기 버튼) + 폰 틀 705×338(그 Play의 언어)로 잰다. 실제 구매 · 요청 없음.
-- 지시서 #28(6 · 7절): 칭호 · 펫 창 확률 보기(지금 ↔ 행운 패스를 더하면 — OddsPreviewLogic) · 상점 행운 패스 줄 "확률 보기"(O2) · 제한 · 보유 숨김.
-- #28 후속(8절): 아우라 창 "×10 패스를 더하면" 단계 · 상점 아우라 줄 · 토글 글자 행운 배수 꼴(뒤 0 없음).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local UI = script.Parent.Parent.UI
local Store = require(UI.Store)
local TextMinimum = require(UI.TextMinimum)
local RobuxShopLogic = require(UI.Logic.RobuxShopLogic)
local AuraWindowLogic = require(UI.Logic.AuraWindowLogic)
local TitleWindowLogic = require(UI.Logic.TitleWindowLogic)
local PetWindowLogic = require(UI.Logic.PetWindowLogic)
local AuraWindow = require(UI.Screens.Window.AuraWindow)
local TitleWindow = require(UI.Screens.Window.TitleWindow)
local PetWindow = require(UI.Screens.Window.PetWindow)
local UpgradeShopWindow = require(UI.Screens.Window.UpgradeShopWindow)
local OddsPreviewLogic = require(UI.Logic.OddsPreviewLogic)
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

local function shop(passes: { string }?, restricted: boolean, luckBoost: number?, credits: any?): any
	return {
		gamepasses = passes or {},
		paidRandomRestricted = restricted,
		boosts = if luckBoost ~= nil then { { type = "luck", mult = luckBoost, remainingSec = 600, receivedAt = 0 } } else {},
		autoClick = false,
		potions = { strength = 0, damage = 0, luck = 3 },
		rollCredits = credits or { lucky = 2, super = 1 },
		gymUnlocks = {},
	}
end

local function rowByKey(rows: { any }, key: string): any
	for _, r in ipairs(rows) do
		if r.key == key then
			return r
		end
	end
	return nil
end

-- 표시 합 = 정확히 100(표시 자릿수에서) — RollOddsTests와 같은 방식
local function sums100(texts: { string }): boolean
	local dec = 0
	for _, t in ipairs(texts) do
		local frac = string.match(t, "%.(%d+)%%")
		dec = math.max(dec, if frac ~= nil then #frac else 0)
	end
	local units = 0
	for _, t in ipairs(texts) do
		local v = tonumber((string.gsub(t, "%%", ""))) or -1
		units += math.floor(v * 10 ^ dec + 0.5)
	end
	return units == 100 * 10 ^ dec
end

local function chanceTexts(cards: { any }): { string }
	local out = {}
	for i, c in ipairs(cards) do
		out[i] = c.chanceText
	end
	return out
end

local levels0 = { auraLuck = 0, titleLuck = 0, petLuck = 0 }
local auraBase = UpgradeConfig.getEffect("auraLuck", 0)

-- 1. 럭키 · 슈퍼 롤(개발자 상품 — 로벅스로 사는 뽑기) ----------------------------------------------------------
do
	-- 1a. 구매 전: 아우라 창 로벅스 탭 줄(파는 곳은 여기 하나 — 상점 창에는 없다) = 행운 배수 숫자 + 고른 팩 가장 귀한 것의 a% → b%
	local packId = 2
	local tiers = AuraConfig.Packs[packId].auras
	local ctx = { upgrades = levels0, auras = { selectedPack = packId } }
	local okRows, bad = 0, {}
	for _, key in ipairs({ "luckyRoll5", "luckyRoll15", "superRoll5", "superRoll15" }) do
		local def = ShopConfig.get(key) :: any
		local row = rowByKey(RobuxShopLogic.windowRows("aura", shop(nil, false), ctx), key)
		local before = RollOdds.percentages(RollOdds.distribution(tiers, auraBase))
		local after = RollOdds.percentages(RollOdds.distribution(tiers, auraBase * def.effect.luckMult))
		local want = Locale.t("shop.oddsChange", { mult = string.format("%g", def.effect.luckMult), name = require(ReplicatedStorage.Shared.Localization.Names).aura(tiers[#tiers].id),
			before = before[#tiers], after = after[#tiers] })
		if row ~= nil and row.detail == want then
			okRows += 1
		else
			table.insert(bad, key .. "=" .. tostring(row and row.detail))
		end
	end
	check("럭키 · 슈퍼 롤 줄(구매 전 — 아우라 창 로벅스 탭): 행운 배수 숫자 + 고른 팩(2) 가장 귀한 것 a% → b% · 상점 창에는 없다", okRows == 4
		and rowByKey(RobuxShopLogic.rows(shop(nil, false), ctx), "luckyRoll5") == nil, table.concat(bad, " | "))
	-- 1b. 결과 전부 · 실제 확률: 아우라 창 확률 보기 럭키 · 슈퍼 = 팩 4장 전부 · 행운 × 그 롤 배수 · 합 100 — 팩 셋 모두
	local allOk, why = true, ""
	for pid, pack in pairs(AuraConfig.Packs) do
		for _, mode in ipairs({ "lucky", "super" }) do
			local cards = AuraWindowLogic.cards(nil, levels0, pid, shop(nil, false), mode)
			local expect = RollOdds.percentages(RollOdds.distribution(pack.auras, auraBase * (ShopConfig.rollCreditLuck(mode) :: number)))
			local texts = chanceTexts(cards)
			if #cards ~= #pack.auras or table.concat(texts, ",") ~= table.concat(expect, ",") or not sums100(texts) then
				allOk, why = false, string.format("pack %d %s: %s vs %s", pid, mode, table.concat(texts, ","), table.concat(expect, ","))
			end
		end
	end
	check("럭키 · 슈퍼 롤: 아우라 창 확률 보기 = 결과 전부 · 행운 × 롤 배수(서버 rollProductMult와 같은 항) · 합 100(모든 팩)", allOk, why)
	-- 1c. 행운 패스 · 포션이 있으면 롤 확률에도 들어간다(서버: 업그레이드 × 패스 × 포션 × 롤 배수)
	local withPass = AuraWindowLogic.modeLuck(levels0, shop({ "auraLuck10x" }, false, 2), "super")
	check("럭키 · 슈퍼 롤: 패스 ×10 · 포션 ×2가 롤 배수와 함께 곱해진다", math.abs(withPass - auraBase * 10 * 2 * 100) < 1e-9, tostring(withPass))
	-- 1d. 모드 순환 · 제한 유저
	local m1 = AuraWindowLogic.nextOddsMode("normal", shop(nil, false))
	local m2 = AuraWindowLogic.nextOddsMode(m1, shop(nil, false))
	local m3 = AuraWindowLogic.nextOddsMode(m2, shop(nil, false))
	local m4 = AuraWindowLogic.nextOddsMode(m3, shop(nil, false))
	check("확률 보기: 보통 → ×10 패스를 더하면 → 럭키 → 슈퍼 → 보통(#28 후속 ①)", m1 == "pass" and m2 == "lucky" and m3 == "super" and m4 == "normal")
	check("확률 보기: 제한 유저는 보통만(럭키 모드를 넘겨도 보통 확률)", AuraWindowLogic.nextOddsMode("normal", shop(nil, true)) == "normal"
		and AuraWindowLogic.modeLuck(levels0, shop(nil, true), "lucky") == auraBase)
	-- 1e. 제한 유저: 상품 줄 · 창 상품 · 사용 버튼이 없다
	local rowsR = RobuxShopLogic.rows(shop(nil, true), {})
	local anyCredit = false
	for _, r in ipairs(rowsR) do
		local def = ShopConfig.get(r.buyKey or r.key)
		if def ~= nil and def.paidRandom then
			anyCredit = true
		end
	end
	local auraWin = RobuxShopLogic.windowRows("aura", shop(nil, true), {})
	local lucky = AuraWindowLogic.creditState(nil, BigNum.new(1, 30), shop(nil, true), 1, "lucky")
	check("제한 유저: 상점 · 아우라 창 상품에 행운 상품 0줄 · 롤 사용 버튼 숨김 · 쓸 수 없음", not anyCredit and #auraWin == 0 and not lucky.visible and not lucky.canUse,
		string.format("상점 행운 %s · 창 %d", tostring(anyCredit), #auraWin))
	-- #48 정책 재점검: 창마다의 로벅스 칸도 로벅스 탭과 같은 숨김(행운 상품 + 숨김 목록 — 펫 창 Triple Hatch가 보이던 것을 고침)
	local leaks = {}
	for window in pairs(RobuxShopLogic.WINDOW_PRODUCTS) do
		for _, r in ipairs(RobuxShopLogic.windowRows(window, shop(nil, true), {})) do
			local def = ShopConfig.get(r.key)
			if def ~= nil and (def.paidRandom or EconomyV2Logic.isRestrictedRandom(r.key)) then
				table.insert(leaks, window .. ":" .. r.key)
			end
		end
	end
	check("제한 유저(#48): 창 로벅스 칸에도 행운 상품 · 숨김 목록(Triple Hatch 등) 0줄 — 로벅스 탭과 같다", #leaks == 0, table.concat(leaks, ","))
	-- #49 "Enhanced resource drops": 자동 진행의 드롭 전부 줍기는 구매 전 설명에 · 제한 유저는 그 효과가 없어 줍기를 말하지 않는 문장
	local aaFree = rowByKey(RobuxShopLogic.rows(shop(nil, false), {}), "autoAdvance")
	local aaRestricted = rowByKey(RobuxShopLogic.rows(shop(nil, true), {}), "autoAdvance")
	check("자동 진행 설명(#49): 일반 = 드롭 전부 줍기 포함 · 제한 = 줍기 없는 문장(상품은 그대로 판다)", aaFree ~= nil and aaRestricted ~= nil
		and aaFree.detail == Locale.t("shop.autoAdvance.descPickup") and aaRestricted.detail == Locale.t("shop.autoAdvance.desc"))
end

-- 2. 행운 게임패스(10배 아우라 · 10배 칭호 · 2배 펫) -----------------------------------------------------------
do
	local ctx = { upgrades = levels0, auras = { selectedPack = 1 } }
	local rows = RobuxShopLogic.rows(shop(nil, false), ctx)
	local bad = {}
	for _, key in ipairs({ "auraLuck10x", "titleLuck10x", "petLuck2x" }) do
		local def = ShopConfig.get(key) :: any
		local r = rowByKey(rows, key)
		local prefix = Locale.t("shop.oddsChange", { mult = string.format("%g", def.effect.mult), name = "", before = "", after = "" })
		prefix = string.sub(prefix, 1, (string.find(prefix, ":", 1, true) or 1))
		if r == nil or string.find(r.detail, prefix, 1, true) ~= 1 or string.find(r.detail, "→", 1, true) == nil then
			table.insert(bad, key .. "=" .. tostring(r and r.detail))
		end
	end
	check("행운 패스 줄(구매 전): '행운 ×N:' 숫자 설명 + 가장 귀한 것 a% → b%(셋 다)", #bad == 0, table.concat(bad, " | "))
	-- 보유 후 창 확률 갱신
	local tAfter = TitleWindowLogic.luckOf(levels0, shop({ "titleLuck10x" }, false))
	local aAfter = AuraWindowLogic.luckOf(levels0, shop({ "auraLuck10x" }, false))
	local pAfter = PetWindowLogic.luckOf(levels0, shop({ "petLuck2x" }, false))
	check("행운 패스 보유: 칭호 ×10 · 아우라 ×10 · 펫 ×2가 창 확률 행운에 들어간다",
		math.abs(tAfter - UpgradeConfig.getEffect("titleLuck", 0) * 10) < 1e-9 and math.abs(aAfter - auraBase * 10) < 1e-9
			and math.abs(pAfter - UpgradeConfig.getEffect("petLuck", 0) * 2) < 1e-9)
	local aCards = AuraWindowLogic.cards(nil, levels0, 1, shop({ "auraLuck10x" }, false))
	local expect = RollOdds.percentages(RollOdds.distribution(AuraConfig.Packs[1].auras, auraBase * 10))
	check("행운 패스 보유: 아우라 카드 확률 = 행운 ×10 실제 확률 · 합 100", table.concat(chanceTexts(aCards), ",") == table.concat(expect, ",")
		and sums100(chanceTexts(aCards)))
	-- 제한 유저면 보유해도 효과 없음(창 확률도 기본)
	check("행운 패스 + 제한 유저: 창 확률은 기본 행운(효과 꺼짐)", AuraWindowLogic.luckOf(levels0, shop({ "auraLuck10x" }, true)) == auraBase
		and TitleWindowLogic.luckOf(levels0, shop({ "titleLuck10x" }, true)) == UpgradeConfig.getEffect("titleLuck", 0)
		and PetWindowLogic.luckOf(levels0, shop({ "petLuck2x" }, true)) == UpgradeConfig.getEffect("petLuck", 0))
end

-- 3. 행운 포션 · 포션 번들(개발자 상품) -------------------------------------------------------------------------
do
	local potion = ShopConfig.BOOSTS.luck
	local desc = RobuxShopLogic.row("luckPotion", shop(nil, false), {}).detail
	check("행운 포션 줄(구매 전): 배수 · 시간이 숫자로 있다(×2 · 15분)", string.find(desc, tostring(potion.mult), 1, true) ~= nil
		and string.find(desc, tostring(math.floor(potion.durationSec / 60)), 1, true) ~= nil, desc)
	local on = shop(nil, false, potion.mult)
	local off = shop(nil, false, nil)
	check("행운 포션 켬: 칭호 · 아우라 · 펫 창 행운 ×2 · 끝나면(부스트 없음) 돌아온다",
		TitleWindowLogic.luckOf(levels0, on) == 2 * TitleWindowLogic.luckOf(levels0, off) and AuraWindowLogic.luckOf(levels0, on) == 2 * AuraWindowLogic.luckOf(levels0, off)
			and PetWindowLogic.luckOf(levels0, on) == 2 * PetWindowLogic.luckOf(levels0, off))
	local tRows = TitleWindowLogic.rows(nil, levels0, on)
	local tTexts = {}
	for i, r in ipairs(tRows) do
		tTexts[i] = r.chanceText
	end
	check("행운 포션 켬: 칭호 표 = 결과 전부(칭호 수) · 합 100", #tRows == #TitleConfig.Titles and sums100(tTexts), tostring(#tRows))
	check("행운 포션 + 제한 유저: 포션 효과 1(창 확률 기본)", AuraWindowLogic.luckOf(levels0, shop(nil, true, potion.mult)) == auraBase)
	local rowsR = RobuxShopLogic.rows(shop(nil, true), {})
	check("제한 유저: 행운 포션 · 포션 번들 줄을 숨긴다", rowByKey(rowsR, "luckPotion") == nil and rowByKey(rowsR, "potionBundle") == nil
		and (ShopConfig.get("potionBundle") :: any).paidRandom == true)
end

-- 4. 뽑기 창 셋 — 결과 전부 · 합 100 · 리미티드 펫은 알 목록에 없다 ------------------------------------------------
do
	local bad = {}
	for eggId, egg in pairs(PetConfig.Eggs) do
		local odds = PetWindowLogic.odds(eggId, levels0, shop(nil, false))
		local texts = {}
		for i, o in ipairs(odds) do
			texts[i] = string.match(o.text, "[%d%.]+%%") or "?"
		end
		if #odds ~= #egg.pets or not sums100(texts) then
			table.insert(bad, "egg " .. eggId)
		end
		for _, def in ipairs(egg.pets) do
			if table.find(PetConfig.LIMITED_IDS, def.id) ~= nil then
				table.insert(bad, "limited in egg " .. eggId)
			end
		end
	end
	check("펫 창: 알마다 결과 전부 · 합 100 · 리미티드 펫은 어느 알에도 없다(뽑기가 아니다)", #bad == 0, table.concat(bad, ", "))
end

-- 5. 아우라 창 실물 — 확률 보기 버튼(보통 → 럭키 → 슈퍼) · 제한 유저 숨김 · 폰 틀 글자 ---------------------------
do
	local purchase = PurchaseClient.new({ send = function() end })
	local function make(s: any): any
		local store = Store.new()
		store.setSource(function(setter)
			setter("shop", s)
			setter("lifetimeBlox", BigNum.mul(AuraConfig.Packs[1].rollCost, BigNum.fromNumber(10)))
		end)
		return AuraWindow.create({ store = store, purchase = purchase, sendRequest = function() end, onClose = function() end, openTitles = function() end })
	end
	local w = make(shop(nil, false))
	task.wait()
	local d = w._debug
	local normal = chanceTexts(d.view())
	d.pressOddsMode() -- 더하면(#28 후속 ① — 8절이 잰다)
	d.pressOddsMode()
	local luckyTexts = chanceTexts(d.view())
	local luckyLabel = d.oddsLabel.Text
	d.pressOddsMode()
	local superCard = d.cards[4].chance.Text
	d.pressOddsMode()
	local expectSuper = RollOdds.percentages(RollOdds.distribution(AuraConfig.Packs[d.shownPack()].auras, auraBase * 100))
	check("창: 확률 보기 버튼이 보이고 행운 글자는 숨는다(제한 아님)", d.oddsButton.root.Visible and not d.luck.Visible)
	check("창: 누르면 럭키 → 카드 확률이 바뀌고 글자에 럭키 · 행운 숫자", table.concat(luckyTexts, ",") ~= table.concat(normal, ",")
		and luckyLabel == Locale.t("aura.odds.lucky", { luck = OddsPreviewLogic.luckNum(auraBase * 5) }), luckyLabel)
	check("창: 슈퍼 = 카드 칸에 행운 ×100 실제 확률 · 네 번 누르면 보통", superCard == expectSuper[4] and d.oddsMode() == "normal"
		and table.concat(chanceTexts(d.view()), ",") == table.concat(normal, ","), superCard .. " vs " .. expectSuper[4])
	w.root:Destroy()
	local wr = make(shop(nil, true))
	task.wait()
	wr._debug.pressOddsMode()
	check("창: 제한 유저 → 확률 보기 버튼 없음 · 행운 글자 · 보통 확률 그대로", not wr._debug.oddsButton.root.Visible and wr._debug.luck.Visible
		and wr._debug.oddsMode() == "normal")
	wr.root:Destroy()

	-- 폰 틀(705×338) — 그 Play의 언어로 확률 보기 세 글자 넘침 0 · 11px
	local gui = Instance.new("ScreenGui")
	gui.Name = "PaidRandomPhone"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local wp = make(shop({ "auraLuck10x" }, false, 2))
	wp.root.Parent = phone
	wp.root.Visible = true
	local bad, worst = {}, math.huge
	for _ = 1, 3 do
		task.wait()
		task.wait()
		local l = wp._debug.oddsLabel
		worst = math.min(worst, l.AbsoluteSize.Y)
		if not l.TextFits or l.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
			table.insert(bad, string.format("[%dx%d] %s", l.AbsoluteSize.X, l.AbsoluteSize.Y, l.Text))
		end
		for _, c in ipairs(wp._debug.cards) do
			if not c.chance.TextFits then
				table.insert(bad, c.chance.Text)
			end
		end
		wp._debug.pressOddsMode()
	end
	check(string.format("폰(%s): 확률 보기 글자 셋 · 카드 확률 넘침 0 · 최소 %.1fpx ≥ 11", Locale.current(), worst), #bad == 0 and worst >= TextScale.MIN_TEXT_PX - 0.5,
		table.concat(bad, " | "))
	print(string.format("[PaidRandomPolicyTests] 폰 705×338(%s): 확률 보기 %.0fx%.0f · %s", Locale.current(), wp._debug.oddsLabel.AbsoluteSize.X,
		wp._debug.oddsLabel.AbsoluteSize.Y, wp._debug.oddsLabel.Text))
	gui:Destroy()
end

-- 6. 칭호 · 펫 확률 보기 — 로직(지시서 #28 O1 · O2) -----------------------------------------------------------
-- "패스를 더하면" = 그 패스를 산 뒤 창이 보일 확률(서버 computeLuck의 luckPassMult 자리 — 그 체인은 위 2절 · 서버 RollServiceTests가 잰다)
do
	local function titleTexts(rows: { any }): { string }
		local out = {}
		for i, r in ipairs(rows) do
			out[i] = r.chanceText
		end
		return out
	end
	local function petTexts(odds: { any }): { string }
		local out = {}
		for i, o in ipairs(odds) do
			out[i] = string.match(o.text, "[%d%.]+%%") or "?"
		end
		return out
	end
	check("패스 키: 칭호 titleLuck10x ×10 · 펫 petLuck2x ×2 · 아우라 auraLuck10x(ShopConfig luckPass)", OddsPreviewLogic.passKey("title") == "titleLuck10x"
		and OddsPreviewLogic.passKey("pet") == "petLuck2x" and OddsPreviewLogic.passKey("aura") == "auraLuck10x"
		and OddsPreviewLogic.passMult("title") == 10 and OddsPreviewLogic.passMult("pet") == 2)
	check("볼 수 있음: 안 가짐 · 제한 아님만(가졌으면 숨김 · 제한이면 숨김)", OddsPreviewLogic.canPreview("title", shop(nil, false))
		and OddsPreviewLogic.canPreview("pet", shop(nil, false)) and not OddsPreviewLogic.canPreview("title", shop({ "titleLuck10x" }, false))
		and not OddsPreviewLogic.canPreview("pet", shop({ "petLuck2x" }, false)) and not OddsPreviewLogic.canPreview("title", shop(nil, true))
		and not OddsPreviewLogic.canPreview("pet", shop(nil, true)))
	-- 칭호: 포션 없음 · 포션 ×2 · 업그레이드 레벨 3에서 — 더하면 = 산 뒤 창 확률, 지금 = 지금 창 확률. 합 100
	local tBad = {}
	for _, case in ipairs({ { lv = 0, boost = nil }, { lv = 0, boost = 2 }, { lv = 3, boost = 2 } }) do
		local lv = { titleLuck = case.lv, petLuck = case.lv, auraLuck = 0 }
		local now = titleTexts(TitleWindowLogic.rows(nil, lv, shop(nil, false, case.boost)))
		local off = titleTexts(TitleWindowLogic.rows(nil, lv, shop(nil, false, case.boost), false))
		local on = titleTexts(TitleWindowLogic.rows(nil, lv, shop(nil, false, case.boost), true))
		local bought = titleTexts(TitleWindowLogic.rows(nil, lv, shop({ "titleLuck10x" }, false, case.boost)))
		if table.concat(off, ",") ~= table.concat(now, ",") or table.concat(on, ",") ~= table.concat(bought, ",") or #on ~= #TitleConfig.Titles
			or not sums100(on) or not sums100(off) or table.concat(on, ",") == table.concat(off, ",") then
			table.insert(tBad, string.format("lv%d boost%s: %s / %s", case.lv, tostring(case.boost), table.concat(on, ","), table.concat(bought, ",")))
		end
	end
	check("칭호 확률 보기: 지금 = 지금 창 · 더하면 = x10 Title Luck 산 뒤 창 확률(업그레이드 · 포션 포함) · 결과 전부 · 합 100", #tBad == 0,
		table.concat(tBad, " | "))
	-- 펫: 알마다 · 포션 ×2 — 더하면 = x2 Pet Luck 산 뒤 확률
	local pBad = {}
	for eggId, egg in pairs(PetConfig.Eggs) do
		local on = petTexts(PetWindowLogic.odds(eggId, levels0, shop(nil, false, 2), true))
		local bought = petTexts(PetWindowLogic.odds(eggId, levels0, shop({ "petLuck2x" }, false, 2)))
		local off = petTexts(PetWindowLogic.odds(eggId, levels0, shop(nil, false, 2), false))
		local now = petTexts(PetWindowLogic.odds(eggId, levels0, shop(nil, false, 2)))
		if table.concat(on, ",") ~= table.concat(bought, ",") or table.concat(off, ",") ~= table.concat(now, ",") or #on ~= #egg.pets or not sums100(on) then
			table.insert(pBad, "egg " .. eggId)
		end
	end
	check("펫 확률 보기: 알마다 더하면 = x2 Pet Luck 산 뒤 확률 · 지금 = 지금 · 결과 전부 · 합 100", #pBad == 0, table.concat(pBad, ", "))
	-- 가졌거나 제한이면 켜도 지금 그대로(가진 패스 · 켜진 포션은 "지금"에 이미 들어 있다)
	local ownedT = titleTexts(TitleWindowLogic.rows(nil, levels0, shop({ "titleLuck10x" }, false), true))
	local ownedT0 = titleTexts(TitleWindowLogic.rows(nil, levels0, shop({ "titleLuck10x" }, false)))
	local resP = petTexts(PetWindowLogic.odds(1, levels0, shop(nil, true), true))
	local resP0 = petTexts(PetWindowLogic.odds(1, levels0, shop(nil, true)))
	check("확률 보기: 가졌으면 · 제한 유저면 켜도 지금 확률 그대로(두 번 곱하지 않는다)", table.concat(ownedT, ",") == table.concat(ownedT0, ",")
		and table.concat(resP, ",") == table.concat(resP0, ","))
	local base = TitleWindowLogic.luckOf(levels0, shop(nil, false))
	check("토글 글자: 지금 · 더하면에 행운 숫자(뒤 0 없음)와 패스 이름(배수)", OddsPreviewLogic.toggleText("title", false, base)
		== Locale.t("odds.preview.now", { luck = OddsPreviewLogic.luckNum(base) }) and OddsPreviewLogic.toggleText("title", true, base * 10)
		== Locale.t("odds.preview.pass", { pass = Locale.t("odds.passName", { mult = "10" }), luck = OddsPreviewLogic.luckNum(base * 10) }))
	-- O2: 상점 로벅스 탭 행운 패스 줄 — 칭호 · 펫(안 가짐)만 둘째 버튼 "확률 보기". 설명(배수 + 가장 귀한 것)은 그대로. 창 상품 줄에는 없다
	local rows = RobuxShopLogic.rows(shop(nil, false), { upgrades = levels0 })
	local t, pp, a = rowByKey(rows, "titleLuck10x"), rowByKey(rows, "petLuck2x"), rowByKey(rows, "auraLuck10x")
	local ownedRows = RobuxShopLogic.rows(shop({ "titleLuck10x", "petLuck2x", "auraLuck10x" }, false), { upgrades = levels0 })
	check("상점 행운 패스 줄: 칭호 · 펫 · 아우라(#28 후속 ①)에 확률 보기(linkRoll) · 설명 '행운 ×N:' 그대로 · 가지면 없음", t.linkRoll == "title"
		and pp.linkRoll == "pet" and t.useText == RobuxShopLogic.LINK_TEXT and a.linkRoll == "aura" and rowByKey(ownedRows, "titleLuck10x").linkRoll == nil
		and rowByKey(ownedRows, "petLuck2x").linkRoll == nil and rowByKey(ownedRows, "auraLuck10x").linkRoll == nil and string.find(t.detail, "→", 1, true) ~= nil)
	check("창 상품 줄(칭호 · 펫 창 안)에는 확률 보기 버튼이 없다(그 창이 이미 토글을 가진다)",
		(RobuxShopLogic.windowRows("title", shop(nil, false))[1] :: any).linkRoll == nil
		and (rowByKey(RobuxShopLogic.windowRows("pet", shop(nil, false)), "petLuck2x") :: any).linkRoll == nil)
end

-- 7. 칭호 · 펫 창 실물 — 토글 · 보유 · 제한 숨김 · 요청 없음 · 상점 줄에서 열기 · 폰 틀 ---------------------------
do
	local requests, buys = 0, 0
	local purchase = PurchaseClient.new({ send = function()
		buys += 1
	end })
	local function storeWith(s: any): (any, any)
		local store = Store.new()
		local setter: any = nil
		store.setSource(function(set)
			setter = set
			set("shop", s)
			set("upgrades", levels0)
			set("blox", BigNum.new(1, 30))
			set("lifetimeBlox", BigNum.new(1, 30))
		end)
		return store, function(v: any)
			setter("shop", v)
		end
	end
	local function titleWin(s: any): (any, (any) -> ())
		local store, setShop = storeWith(s)
		return TitleWindow.create({ store = store, purchase = purchase, sendRequest = function()
			requests += 1
		end, onClose = function() end }), setShop
	end
	local function petWin(s: any): (any, (any) -> ())
		local store, setShop = storeWith(s)
		return PetWindow.create({ store = store, purchase = purchase, sendRequest = function()
			requests += 1
		end, onClose = function() end }), setShop
	end
	local function chances(w: any): string
		local out = {}
		for i, r in ipairs(w._debug.rows) do
			out[i] = r.chance.Text
		end
		return table.concat(out, ",")
	end
	local function petChances(w: any): string
		local out = {}
		for i, l in ipairs(w._debug.odds) do
			out[i] = l.Text
		end
		return table.concat(out, ",")
	end
	-- 칭호 창
	local tw, setT = titleWin(shop(nil, false))
	task.wait()
	local d = tw._debug
	local before = chances(tw)
	d.pressOdds()
	local onText = chances(tw)
	local wantOn = {}
	for i, r in ipairs(TitleWindowLogic.rows(nil, levels0, shop({ "titleLuck10x" }, false))) do
		wantOn[i] = r.chanceText
	end
	check("칭호 창: 토글이 보이고 행운 글자는 숨는다 · 누르면 6줄 확률 = 산 뒤 확률 · 글자에 패스 배수", d.oddsButton.root.Visible and not d.luckLine.Visible
		and d.preview() and onText == table.concat(wantOn, ",") and onText ~= before
		and d.oddsLabel.Text == OddsPreviewLogic.toggleText("title", true, TitleWindowLogic.luckOf(levels0, shop(nil, false)) * 10), d.oddsLabel.Text)
	d.pressOdds()
	check("칭호 창: 다시 누르면 지금 확률", not d.preview() and chances(tw) == before)
	d.pressOdds()
	setT(shop({ "titleLuck10x" }, false))
	task.wait()
	check("칭호 창: 패스를 가지면 토글이 숨고 행운 글자 · 확률은 가진 확률(켠 상태가 풀린다)", not d.oddsButton.root.Visible and d.luckLine.Visible
		and not d.preview() and chances(tw) == onText)
	setT(shop(nil, true))
	task.wait()
	tw.showOdds()
	check("칭호 창: 제한 유저 → 토글 없음 · showOdds도 켜지 않는다", not d.oddsButton.root.Visible and d.luckLine.Visible and not d.preview())
	setT(shop(nil, false))
	task.wait()
	tw.showOdds()
	check("칭호 창: showOdds(상점 줄에서) → 더하면으로 켠다", d.preview() and chances(tw) == onText)
	tw.root:Destroy()
	-- 펫 창
	local pw, setP = petWin(shop(nil, false))
	task.wait()
	local pd = pw._debug
	local pBefore = petChances(pw)
	pd.pressOdds()
	local pOn = petChances(pw)
	local pWant = {}
	for i, o in ipairs(PetWindowLogic.odds(pd.shownEgg(), levels0, shop({ "petLuck2x" }, false))) do
		pWant[i] = o.text
	end
	check("펫 창: 토글 · 누르면 고른 알 4종 확률 = x2 Pet Luck 산 뒤 확률 · 다시 누르면 지금", pd.oddsButton.root.Visible and not pd.luck.Visible
		and pOn == table.concat(pWant, ",") and pOn ~= pBefore)
	pd.pressOdds()
	local pOff = petChances(pw)
	pd.pressRobuxTab()
	pw.showOdds()
	check("펫 창: 다시 누르면 지금 · showOdds는 로벅스 탭을 닫고 더하면으로", pOff == pBefore and pd.preview() and not pd.robuxShown())
	setP(shop({ "petLuck2x" }, false))
	task.wait()
	local hidOwned = not pd.oddsButton.root.Visible and pd.luck.Visible and not pd.preview()
	setP(shop(nil, true))
	task.wait()
	check("펫 창: 가지면 · 제한 유저면 토글 숨김 · 행운 글자", hidOwned and not pd.oddsButton.root.Visible and pd.luck.Visible)
	pw.root:Destroy()
	-- 상점 줄 → 그 창(O2): 누르면 openOdds(roll) 한 번 · 구매 요청 없음
	local opened = {}
	local sstore = storeWith(shop(nil, false))
	local sw = UpgradeShopWindow.create({ store = sstore, purchase = purchase, sendRequest = function()
		requests += 1
	end, onClose = function() end, openOdds = function(roll: string)
		table.insert(opened, roll)
	end })
	sw._debug.selectTab(UpgradeShopWindow.TAB_ROBUX)
	task.wait()
	local view = sw._debug.robuxView()
	local idx: { [string]: number } = {}
	for i, r in ipairs(view) do
		idx[r.key] = i
	end
	local titleRow = sw._debug.robuxRows[idx.titleLuck10x]
	sw._debug.pressUse(idx.titleLuck10x)
	sw._debug.pressUse(idx.petLuck2x)
	sw._debug.pressUse(idx.auraLuck10x)
	check("상점 줄: 확률 보기 버튼이 보이고 켜져 있다 · 누르면 그 창(title · pet · aura)", titleRow.use.root.Visible and not titleRow.use.isDisabled()
		and titleRow.useLabel.Text == RobuxShopLogic.LINK_TEXT and sw._debug.robuxRows[idx.auraLuck10x].use.root.Visible
		and #opened == 3 and opened[1] == "title" and opened[2] == "pet" and opened[3] == "aura", table.concat(opened, ","))
	sw.root:Destroy()
	check("요청 없음: 확률 보기 · 상점 줄 누름은 서버 요청 · 구매 요청을 보내지 않는다", requests == 0 and buys == 0,
		string.format("요청 %d · 구매 %d", requests, buys))

	-- 폰 틀(705×338) — 그 Play의 언어로 칭호 · 펫 토글 두 상태 · 상점 줄 버튼 넘침 0 · 11px
	local gui = Instance.new("ScreenGui")
	gui.Name = "OddsPreviewPhone"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local bad, worst = {}, math.huge
	local function measure(l: TextLabel)
		worst = math.min(worst, l.AbsoluteSize.Y)
		if not l.TextFits or l.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
			table.insert(bad, string.format("[%dx%d] %s", l.AbsoluteSize.X, l.AbsoluteSize.Y, l.Text))
		end
	end
	local samples = {}
	for _, make in ipairs({ titleWin, petWin }) do
		local w = make(shop(nil, false, 2))
		w.root.Parent = phone
		w.root.Visible = true
		for _ = 1, 2 do
			task.wait()
			task.wait()
			measure(w._debug.oddsLabel)
			table.insert(samples, string.format("%.0fx%.0f %s", w._debug.oddsLabel.AbsoluteSize.X, w._debug.oddsLabel.AbsoluteSize.Y, w._debug.oddsLabel.Text))
			w._debug.pressOdds()
		end
		w.root:Destroy()
	end
	local sp = UpgradeShopWindow.create({ store = (storeWith(shop(nil, false))), purchase = purchase, sendRequest = function() end, onClose = function() end,
		openOdds = function() end })
	sp.root.Parent = phone
	sp.root.Visible = true
	sp._debug.selectTab(UpgradeShopWindow.TAB_ROBUX)
	task.wait()
	task.wait()
	for i, r in ipairs(sp._debug.robuxView()) do
		if r.linkRoll ~= nil then
			measure(sp._debug.robuxRows[i].useLabel)
			measure(sp._debug.robuxRows[i].title)
		end
	end
	sp.root:Destroy()
	check(string.format("폰(%s): 칭호 · 펫 토글 두 상태 · 상점 확률 보기 버튼 · 줄 이름 넘침 0 · 최소 %.1fpx ≥ 11", Locale.current(), worst), #bad == 0
		and worst >= TextScale.MIN_TEXT_PX - 0.5, table.concat(bad, " | "))
	print(string.format("[PaidRandomPolicyTests] 폰 705×338(%s): %s", Locale.current(), table.concat(samples, " · ")))
	gui:Destroy()
end

-- 8. 아우라 창 "×10 패스를 더하면"(#28 후속 ①) · 토글 글자 행운 배수 꼴(후속 ②) ------------------------------------
do
	local free, owned, restricted = shop(nil, false, 2), shop({ "auraLuck10x" }, false, 2), shop(nil, true)
	local function walk(s: any): string
		local out, m = {}, "normal"
		for _ = 1, 5 do
			m = AuraWindowLogic.nextOddsMode(m, s)
			table.insert(out, m)
		end
		return table.concat(out, ",")
	end
	check("아우라 단계 · 순서: 보통 → 더하면 → 럭키 → 슈퍼 → 보통(안 가짐)", walk(free) == "pass,lucky,super,normal,pass", walk(free))
	check("아우라: x10 Aura Luck을 가지면 더하면을 건너뛴다(보통 → 럭키 → 슈퍼) · 그 모드는 보통으로 풀린다", walk(owned) == "lucky,super,normal,lucky,super"
		and AuraWindowLogic.validOddsMode("pass", owned) == "normal" and AuraWindowLogic.modeLuck(levels0, owned, "pass") == AuraWindowLogic.luckOf(levels0, owned),
		walk(owned))
	check("아우라: 제한 유저는 더하면도 없다(보통만 · 행운 그대로)", walk(restricted) == "normal,normal,normal,normal,normal"
		and AuraWindowLogic.validOddsMode("pass", restricted) == "normal" and AuraWindowLogic.modeLuck(levels0, restricted, "pass") == auraBase)
	-- 더하면 = 그 패스를 산 뒤 보통 확률(업그레이드 · 포션 포함 · 서버 computeLuck luckPassMult 자리) · 결과 전부 · 합 100 — 팩 셋 · 레벨 둘
	local bad = {}
	for _, lv in ipairs({ 0, 4 }) do
		local levels = { auraLuck = lv, titleLuck = 0, petLuck = 0 }
		for pid, pack in pairs(AuraConfig.Packs) do
			local on = chanceTexts(AuraWindowLogic.cards(nil, levels, pid, free, "pass"))
			local bought = chanceTexts(AuraWindowLogic.cards(nil, levels, pid, owned, "normal"))
			local now = chanceTexts(AuraWindowLogic.cards(nil, levels, pid, free, "normal"))
			if #on ~= #pack.auras or table.concat(on, ",") ~= table.concat(bought, ",") or table.concat(on, ",") == table.concat(now, ",") or not sums100(on) then
				table.insert(bad, string.format("lv%d pack%d %s / %s", lv, pid, table.concat(on, ","), table.concat(bought, ",")))
			end
		end
	end
	check("아우라 더하면: 카드 4장 = x10 Aura Luck 산 뒤 확률(지금과 다름) · 합 100(팩 셋 · 레벨 0 · 4)", #bad == 0, table.concat(bad, " | "))
	check("행운 배수 꼴: 20 · 2.5 · 1.25 · 100(뒤 0 없음)", OddsPreviewLogic.luckNum(20) == "20" and OddsPreviewLogic.luckNum(2.5) == "2.5"
		and OddsPreviewLogic.luckNum(1.25) == "1.25" and OddsPreviewLogic.luckNum(100) == "100" and OddsPreviewLogic.luckNum(7.5) == "7.5",
		table.concat({ OddsPreviewLogic.luckNum(20), OddsPreviewLogic.luckNum(2.5), OddsPreviewLogic.luckNum(1.25), OddsPreviewLogic.luckNum(100) }, ","))
	local passText = OddsPreviewLogic.toggleText("aura", true, 20)
	check("토글 글자 세 창 공통 키: 아우라 더하면 = odds.preview.pass(패스 이름 ×10 · 행운 20) · '20.00' 없음",
		AuraWindowLogic.oddsModeText("pass", levels0, shop(nil, false)) == OddsPreviewLogic.toggleText("aura", true, auraBase * 10)
		and passText == Locale.t("odds.preview.pass", { pass = Locale.t("odds.passName", { mult = "10" }), luck = "20" })
		and string.find(passText, "20.00", 1, true) == nil, passText)

	-- 창 실물: 토글 · showOdds(상점 줄) · 사면 · 제한이면 풀림
	local purchase = PurchaseClient.new({ send = function() end })
	local setter: any = nil
	local store = Store.new()
	store.setSource(function(set)
		setter = set
		set("shop", free)
		set("upgrades", levels0)
		set("lifetimeBlox", BigNum.mul(AuraConfig.Packs[1].rollCost, BigNum.fromNumber(10)))
	end)
	local w = AuraWindow.create({ store = store, purchase = purchase, sendRequest = function() end, onClose = function() end, openTitles = function() end })
	task.wait()
	local d = w._debug
	d.pressOddsMode()
	local wantOn = chanceTexts(AuraWindowLogic.cards(nil, levels0, d.shownPack(), owned, "normal"))
	check("아우라 창: 첫 누름 = 더하면 · 카드 확률 = 산 뒤 확률 · 글자 = 공통 토글", d.oddsMode() == "pass"
		and table.concat(chanceTexts(d.view()), ",") == table.concat(wantOn, ",")
		and d.oddsLabel.Text == OddsPreviewLogic.toggleText("aura", true, AuraWindowLogic.luckOf(levels0, free) * 10), d.oddsLabel.Text)
	d.pressOddsMode()
	d.pressOddsMode()
	d.pressOddsMode()
	d.pressRobuxTab()
	w.showOdds()
	local shown = d.oddsMode() == "pass" and not d.robuxShown()
	setter("shop", owned)
	task.wait()
	local ownedOk = d.oddsMode() == "normal" and d.oddsButton.root.Visible
	setter("shop", restricted)
	task.wait()
	w.showOdds()
	check("아우라 창: showOdds → 로벅스 탭 닫고 더하면 · 사면 보통으로 풀림 · 제한이면 버튼 없음 · showOdds도 보통", shown and ownedOk
		and d.oddsMode() == "normal" and not d.oddsButton.root.Visible and d.luck.Visible)
	w.root:Destroy()

	-- 폰 틀(705×338) — 그 Play의 언어로 아우라 네 단계 글자(안 가짐) 넘침 0 · 11px
	local gui = Instance.new("ScreenGui")
	gui.Name = "AuraPassPhone"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local pstore = Store.new()
	pstore.setSource(function(set)
		set("shop", free)
		set("upgrades", levels0)
		set("lifetimeBlox", BigNum.mul(AuraConfig.Packs[1].rollCost, BigNum.fromNumber(10)))
	end)
	local wp = AuraWindow.create({ store = pstore, purchase = purchase, sendRequest = function() end, onClose = function() end, openTitles = function() end })
	wp.root.Parent = phone
	wp.root.Visible = true
	local pbad, worst, samples = {}, math.huge, {}
	for _ = 1, 4 do
		task.wait()
		task.wait()
		local l = wp._debug.oddsLabel
		worst = math.min(worst, l.AbsoluteSize.Y)
		if not l.TextFits or l.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
			table.insert(pbad, string.format("[%dx%d] %s", l.AbsoluteSize.X, l.AbsoluteSize.Y, l.Text))
		end
		table.insert(samples, string.format("%.0fx%.0f %s", l.AbsoluteSize.X, l.AbsoluteSize.Y, l.Text))
		wp._debug.pressOddsMode()
	end
	check(string.format("폰(%s): 아우라 확률 보기 네 단계 글자 넘침 0 · 최소 %.1fpx ≥ 11", Locale.current(), worst), #pbad == 0
		and worst >= TextScale.MIN_TEXT_PX - 0.5, table.concat(pbad, " | "))
	print(string.format("[PaidRandomPolicyTests] 폰 705×338(%s) 아우라: %s", Locale.current(), table.concat(samples, " · ")))
	gui:Destroy()
end

print(string.format("[PaidRandomPolicyTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PaidRandomPolicyTests] %d test(s) failed", failed))
end

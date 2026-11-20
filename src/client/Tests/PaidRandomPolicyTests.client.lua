--!strict
-- 유료 랜덤 상품 확률 표시 점검 (지시서 #27 단계 2 — docs/POLICY_CHECK.md "상품 × 화면 점검표"의 테스트 원본).
-- 공식 https://create.roblox.com/docs/production/monetization/paid-random-items (2026-11-20 다시 읽음):
--   ① 사기 전에 결과 전부 · 실제 확률(% · 합 100) ② 확률을 바꾸는 상품은 사기 전에 설명 ③ 활성 중엔 바뀐 확률을 보인다
--   ④ 제한 유저(ArePaidRandomItemsRestricted)는 유료 랜덤 · 행운 상품을 쓸 수 없다(우리 처리 = 숨김 · 효과 끔)
-- 순수 로직(RobuxShopLogic · 창 Logic) + 아우라 창 실물(확률 보기 버튼) + 폰 틀 705×338(그 Play의 언어)로 잰다. 실제 구매 · 요청 없음.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
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
	check("확률 보기: 보통 → 럭키 → 슈퍼 → 보통", m1 == "lucky" and m2 == "super" and m3 == "normal")
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
	d.pressOddsMode()
	local luckyTexts = chanceTexts(d.view())
	local luckyLabel = d.oddsLabel.Text
	d.pressOddsMode()
	local superCard = d.cards[4].chance.Text
	d.pressOddsMode()
	local expectSuper = RollOdds.percentages(RollOdds.distribution(AuraConfig.Packs[d.shownPack()].auras, auraBase * 100))
	check("창: 확률 보기 버튼이 보이고 행운 글자는 숨는다(제한 아님)", d.oddsButton.root.Visible and not d.luck.Visible)
	check("창: 누르면 럭키 → 카드 확률이 바뀌고 글자에 럭키 · 행운 숫자", table.concat(luckyTexts, ",") ~= table.concat(normal, ",")
		and string.find(luckyLabel, string.format("%.2f", auraBase * 5), 1, true) ~= nil, luckyLabel)
	check("창: 슈퍼 = 카드 칸에 행운 ×100 실제 확률 · 세 번 누르면 보통", superCard == expectSuper[4] and d.oddsMode() == "normal"
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

print(string.format("[PaidRandomPolicyTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PaidRandomPolicyTests] %d test(s) failed", failed))
end

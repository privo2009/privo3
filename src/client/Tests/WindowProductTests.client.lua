--!strict
-- 창별 상품 버튼 검증 (지시서 #17 5단계 — DESIGN 9장 "창별 상품 버튼" · docs/UI.md "지시서 #17").
--   아우라 창: 로벅스 탭(상품 5줄 · 누르면 구매 요청) · 럭키 · 슈퍼 롤 사용(남은 횟수 · 잠긴 팩 · 제한 유저 숨김 · rollCredit 요청 한 번)
--   펫 창: 로벅스 탭(4줄) · ×3 부화(3배 부화 보유면 켜짐 · hatch3 요청)
--   칭호 창: 10배 칭호 행운 버튼(구매 · 보유 · 제한 숨김) · 평소 상태 줄에 확률 변화 숫자
--   폰 틀(Galaxy A06 뷰포트 705×338) 안에 세 창을 그려 그 Play의 언어로: 보이는 글자 칸 넘침 0 · 11px 이상
-- 실제 로벅스 프롬프트를 띄우지 않는다 — 구매 · 요청은 가짜 send로 받는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local UI = script.Parent.Parent.UI
local Store = require(UI.Store)
local TextMinimum = require(UI.TextMinimum)
local AuraWindow = require(UI.Screens.Window.AuraWindow)
local PetWindow = require(UI.Screens.Window.PetWindow)
local TitleWindow = require(UI.Screens.Window.TitleWindow)
local RobuxShopLogic = require(UI.Logic.RobuxShopLogic)
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

local function shop(passes: { string }?, restricted: boolean?, credits: { lucky: number, super: number }?): any
	return {
		gamepasses = passes or {},
		paidRandomRestricted = restricted == true,
		boosts = {},
		autoClick = false,
		potions = { strength = 0, damage = 0, luck = 0 },
		rollCredits = credits or { lucky = 0, super = 0 },
		gymUnlocks = {},
	}
end

local function world(s: any): any
	local store = Store.new()
	store.setSource(function(setter)
		setter("shop", s)
		setter("lifetimeBlox", BigNum.mul(AuraConfig.Packs[1].rollCost, BigNum.fromNumber(10)))
		setter("blox", BigNum.mul(PetConfig.Eggs[1].rollCost, BigNum.fromNumber(100)))
	end)
	return store
end

local function fakePurchase(): (any, { string })
	local sent: { string } = {}
	return PurchaseClient.new({
		send = function(key: string)
			table.insert(sent, key)
		end,
	}), sent
end

-- 1. 아우라 창 ------------------------------------------------------------------------------------------
do
	local purchase, bought = fakePurchase()
	local requests: { any } = {}
	local store = world(shop(nil, false, { lucky = 2, super = 0 }))
	local w = AuraWindow.create({ store = store, purchase = purchase, sendRequest = function(p)
		table.insert(requests, p)
	end, onClose = function() end, openTitles = function() end })
	task.wait()
	local d = w._debug
	check("아우라: 로벅스 탭 보인다(제한 아님) · 처음은 카드", d.robuxTab.root.Visible and not d.robuxShown() and not d.robux.list.Visible)
	d.pressRobuxTab()
	check("아우라: 로벅스 탭 → 상품 5줄 · 카드 숨김", d.robuxShown() and d.robux.list.Visible and #d.robux.view() == 5
		and not d.cards[1].frame.Visible)
	d.robux.pressBuy(1)
	check("아우라: 상품 줄 구매 → 그 키(luckyRoll5)로 요청 한 번", #bought == 1 and bought[1] == "luckyRoll5")
	d.pressTab(1)
	check("아우라: 팩 탭을 누르면 카드로 돌아온다", not d.robuxShown() and d.cards[1].frame.Visible)
	check("아우라: 럭키 롤 사용(2) 켜짐 · 슈퍼(0) 잠김", d.useButtons.lucky.root.Visible and not d.useButtons.lucky.isDisabled()
		and d.useButtons.super.isDisabled() and d.useLabels.lucky.Text == Locale.t("aura.useLucky", { n = 2 }))
	d.pressUse("lucky")
	d.pressUse("lucky")
	check("아우라: 사용 → rollCredit 요청 한 번(팩 · credit) · 블럭스 비용 없음", #requests == 1 and requests[1].action == "rollCredit"
		and requests[1].credit == "lucky" and requests[1].pack == d.shownPack())
	d.pressUse("super")
	check("아우라: 남은 0이면 눌러도 요청 없음", #requests == 1)
	store.setSource(function(setter)
		setter("shop", shop(nil, true, { lucky = 5, super = 5 }))
	end)
	task.wait()
	check("아우라: 제한 유저 → 사용 버튼 · 로벅스 탭 숨김(S13)", not d.useButtons.lucky.root.Visible and not d.robuxTab.root.Visible)
	w.root:Destroy()
end

-- 2. 펫 창 ---------------------------------------------------------------------------------------------
do
	local purchase, bought = fakePurchase()
	local requests: { any } = {}
	local store = world(shop(nil, false))
	local w = PetWindow.create({ store = store, purchase = purchase, sendRequest = function(p)
		table.insert(requests, p)
	end, onClose = function() end })
	task.wait()
	local d = w._debug
	check("펫: ×3 부화 — 3배 부화 없으면 잠김", d.hatch3Button.isDisabled())
	d.pressHatch3()
	check("펫: 잠긴 ×3 부화는 요청 없음", #requests == 0)
	d.pressRobuxTab()
	check("펫: 로벅스 탭 → 상품 4줄(3배 부화 · 2배 펫 행운 · +100 저장 · +3 장착)", d.robuxShown() and #d.robux.view() == 4
		and d.robux.view()[1].key == "hatch3x")
	d.robux.pressBuy(1)
	check("펫: 3배 부화 구매 → hatch3x 요청", #bought == 1 and bought[1] == "hatch3x")
	store.setSource(function(setter)
		setter("shop", shop({ "hatch3x" }, false))
	end)
	task.wait()
	check("펫: 3배 부화 보유 → 상품 줄 '보유 중' · ×3 부화 켜짐", d.robux.view()[1].state == "owned" and not d.hatch3Button.isDisabled())
	d.pressRobuxTab()
	d.pressHatch3()
	check("펫: ×3 부화 → hatch3 요청(고른 알)", #requests == 1 and requests[1].action == "hatch3" and requests[1].egg == d.shownEgg())
	w.root:Destroy()
end

-- 3. 칭호 창 -------------------------------------------------------------------------------------------
do
	local purchase, bought = fakePurchase()
	local store = world(shop(nil, false))
	local w = TitleWindow.create({ store = store, purchase = purchase, sendRequest = function() end, onClose = function() end })
	task.wait()
	local d = w._debug
	check("칭호: 10배 칭호 행운 버튼 보인다 · 가격", d.productButton.root.Visible and string.find(d.productLabel.Text, "299", 1, true) ~= nil)
	check("칭호: 평소 상태 줄 = 확률 변화 숫자", string.find(d.status.Text, "→", 1, true) ~= nil, d.status.Text)
	d.pressProduct()
	d.pressProduct()
	check("칭호: 누르면 titleLuck10x 요청 한 번", #bought == 1 and bought[1] == "titleLuck10x")
	store.setSource(function(setter)
		setter("shop", shop({ "titleLuck10x" }, false))
	end)
	task.wait()
	check("칭호: 보유면 '· 보유 중' · 잠김 · 확률 숫자 없음", d.productButton.isDisabled() and string.find(d.status.Text, "→", 1, true) == nil)
	store.setSource(function(setter)
		setter("shop", shop(nil, true))
	end)
	task.wait()
	check("칭호: 제한 유저 → 버튼 숨김", not d.productButton.root.Visible)
	w.root:Destroy()
end

-- 4. 폰 틀 705×338 — 세 창의 새 칸(로벅스 탭 · 사용 · ×3 · 상품 버튼) 넘침 0 · 11px (그 Play의 언어) -----------------
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "WindowProductPhoneFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local function measure(root: Instance): (number, number, number, string)
		local minH, count, bad = math.huge, 0, 0
		local badText = ""
		for _, obj in ipairs(root:GetDescendants()) do
			if obj:IsA("TextLabel") and obj.Text ~= "" then
				local visible = true
				local node: Instance? = obj
				while node ~= nil and node ~= gui do
					if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
						visible = false
						break
					end
					node = node.Parent
				end
				if visible then
					count += 1
					minH = math.min(minH, obj.AbsoluteSize.Y)
					if not obj.TextFits or obj.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
						bad += 1
						badText = obj.Name .. "(" .. obj.Text .. ")"
					end
				end
			end
		end
		return minH, count, bad, badText
	end
	local function settle()
		task.wait()
		task.wait()
	end

	local store = world(shop(nil, false, { lucky = 15, super = 15 }))
	local p = fakePurchase()
	local aura = AuraWindow.create({ store = store, purchase = p, sendRequest = function() end, onClose = function() end, openTitles = function() end })
	aura.root.Parent = phone
	settle()
	local h1, n1, b1, t1 = measure(aura.root)
	check(string.format("폰: 아우라 카드 + 사용 버튼 글자 %d칸 — 넘침 0 · 최소 %.1fpx ≥ 11", n1, h1), b1 == 0 and h1 >= TextScale.MIN_TEXT_PX - 0.5, t1)
	aura._debug.pressRobuxTab()
	settle()
	local h2, n2, b2, t2 = measure(aura.root)
	check(string.format("폰: 아우라 로벅스 탭 글자 %d칸 — 넘침 0 · 최소 %.1fpx ≥ 11", n2, h2), b2 == 0 and h2 >= TextScale.MIN_TEXT_PX - 0.5, t2)
	aura.root:Destroy()

	local pet = PetWindow.create({ store = store, purchase = p, sendRequest = function() end, onClose = function() end })
	pet.root.Parent = phone
	settle()
	local h3, n3, b3, t3 = measure(pet.root)
	check(string.format("폰: 펫 창(×3 부화 포함) 글자 %d칸 — 넘침 0 · 최소 %.1fpx ≥ 11", n3, h3), b3 == 0 and h3 >= TextScale.MIN_TEXT_PX - 0.5, t3)
	pet._debug.pressRobuxTab()
	settle()
	local h4, n4, b4, t4 = measure(pet.root)
	check(string.format("폰: 펫 로벅스 탭 글자 %d칸 — 넘침 0 · 최소 %.1fpx ≥ 11", n4, h4), b4 == 0 and h4 >= TextScale.MIN_TEXT_PX - 0.5, t4)
	pet.root:Destroy()

	local title = TitleWindow.create({ store = store, purchase = p, sendRequest = function() end, onClose = function() end })
	title.root.Parent = phone
	settle()
	local h5, n5, b5, t5 = measure(title.root)
	check(string.format("폰: 칭호 창(상품 버튼 · 확률 줄) 글자 %d칸 — 넘침 0 · 최소 %.1fpx ≥ 11", n5, h5), b5 == 0 and h5 >= TextScale.MIN_TEXT_PX - 0.5, t5)
	title.root:Destroy()
	print(string.format("[WindowProductTests] 폰 705×338(%s): 아우라 %.1f · %.1f · 펫 %.1f · %.1f · 칭호 %.1fpx · 넘침 %d", Locale.current(), h1, h2, h3, h4,
		h5, b1 + b2 + b3 + b4 + b5))
	gui:Destroy()
end

print(string.format("[WindowProductTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[WindowProductTests] %d test(s) failed", failed))
end

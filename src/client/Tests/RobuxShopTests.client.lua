--!strict
-- 로벅스 상점 UI 검증 (지시서 #16 5단계 — docs/UI.md "지시서 #16"). 가짜 Store · 가짜 구매 요청으로 굴린다 — 실제 프롬프트를 띄우지 않는다.
--   탭 전환 · 표시 값(ShopConfig 원본) · 보유 / 준비 중 / 구매 가능 · 행운 줄 확률 숫자 · 제한 유저 숨김 · 계단 "지금 단계" ·
--   구좌 요청 한 번만 · HUD 구좌 · 자동 클리커 잠김 · 부스트 표시 · 뽑기 창 행운(패스 · 포션) · 공허 기구 표시

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Store = require(script.Parent.Parent.UI.Store)
local RobuxShopLogic = require(script.Parent.Parent.UI.Logic.RobuxShopLogic)
local BoostTimersLogic = require(script.Parent.Parent.UI.Logic.BoostTimersLogic)
local TitleWindowLogic = require(script.Parent.Parent.UI.Logic.TitleWindowLogic)
local PetWindowLogic = require(script.Parent.Parent.UI.Logic.PetWindowLogic)
local UpgradeShopWindow = require(script.Parent.Parent.UI.Screens.Window.UpgradeShopWindow)
local ShopSlots = require(script.Parent.Parent.UI.Screens.Hud.ShopSlots)
local AutoTools = require(script.Parent.Parent.UI.Screens.Hud.AutoTools)
local BoostTimers = require(script.Parent.Parent.UI.Screens.Hud.BoostTimers)
local PurchaseClient = require(script.Parent.Parent.Net.PurchaseClient)
local WorldLabelLogic = require(script.Parent.Parent.World.WorldLabelLogic)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)

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

local function shop(passes: { string }?, restricted: boolean?, boosts: { any }?, auto: boolean?): any
	return { gamepasses = passes or {}, paidRandomRestricted = restricted == true, boosts = boosts or {}, autoClick = auto == true }
end

local function rowByKey(rows: { RobuxShopLogic.Row }, key: string): RobuxShopLogic.Row?
	for _, r in ipairs(rows) do
		if r.key == key then
			return r
		end
	end
	return nil
end

-- ID를 잠깐 채운다(클라 메모리 — 이 블록 안에서만, yield 없이 되돌린다). 서버 ID는 그대로 0이라 실제 프롬프트는 어디서도 안 뜬다.
local function withIds(ids: { [string]: number }, fn: () -> ())
	local saved: { [string]: number } = {}
	for key, id in pairs(ids) do
		local def = ShopConfig.get(key) :: any
		saved[key] = def.id
		def.id = id
	end
	local ok, err = pcall(fn)
	for key, id in pairs(saved) do
		(ShopConfig.get(key) :: any).id = id
	end
	if not ok then
		error(err)
	end
end

-- 1. 줄 · 상태 · 표시 값 ----------------------------------------------------------------------------
do
	local rows = RobuxShopLogic.rows(shop(nil, false))
	check("줄: 계단 한 줄 + 게임패스 13(제한 아님)", #rows == 1 + #ShopConfig.GAMEPASS_ORDER and rows[1].key == RobuxShopLogic.LADDER_KEY)
	local allMatch = true
	for i, key in ipairs(ShopConfig.GAMEPASS_ORDER) do
		local r = rows[i + 1]
		local def = ShopConfig.get(key) :: ShopConfig.ProductDef
		if r.key ~= key or r.title ~= Names.product(key) or r.footText ~= RobuxShopLogic.priceText(def.priceRobux) then
			allMatch = false
		end
	end
	check("표시 값: 순서 · 이름 · 가격 = ShopConfig 원본", allMatch)
	local dmg = rowByKey(rows, "damage2x") :: RobuxShopLogic.Row
	check("준비 중: ID 0이면 '준비 중' · 누를 수 없음 · 가격은 보인다", dmg.state == "notRegistered" and not dmg.canBuy
		and dmg.buttonText == RobuxShopLogic.NOT_REGISTERED_TEXT and dmg.buyKey == nil and dmg.footText == "149 R$")
	local owned = rowByKey(RobuxShopLogic.rows(shop({ "damage2x" }, false)), "damage2x") :: RobuxShopLogic.Row
	check("보유: '보유 중' · 누를 수 없음 · 가격 숨김", owned.state == "owned" and not owned.canBuy and owned.buttonText == RobuxShopLogic.OWNED_TEXT
		and owned.footText == "")
	withIds({ damage2x = 777 }, function()
		local buy = rowByKey(RobuxShopLogic.rows(shop(nil, false)), "damage2x") :: RobuxShopLogic.Row
		check("구매 가능: ID가 있고 미보유면 초록 '구매' · 그 키로 요청", buy.state == "buy" and buy.canBuy and buy.buyKey == "damage2x"
			and buy.buttonText == RobuxShopLogic.BUY_TEXT)
	end)
end

-- 2. 계단 "지금 단계" ---------------------------------------------------------------------------------
do
	local none = RobuxShopLogic.rows(shop())[1]
	check("계단: 보유 없음 → '지금 ×1' · 다음 2배 힘 · 가격 3 R$", none.title == Locale.t("shop.ladder.title", { mult = 1 })
		and string.find(none.detail, Names.product("strength2x"), 1, true) ~= nil and none.footText == "3 R$")
	local mid = RobuxShopLogic.rows(shop({ "strength2x", "strength8x" }))[1]
	check("계단: 2 · 8 보유 → '지금 ×8'(최고 하나) · 다음 16배", mid.title == Locale.t("shop.ladder.title", { mult = 8 })
		and string.find(mid.detail, Names.product("strength16x"), 1, true) ~= nil)
	withIds({ strength16x = 888 }, function()
		local r = RobuxShopLogic.rows(shop({ "strength8x" }))[1]
		check("계단: 다음 단계 ID가 있으면 그 키로 요청", r.canBuy and r.buyKey == "strength16x")
	end)
	local top = RobuxShopLogic.rows(shop({ "strength1024x" }))[1]
	check("계단: 최고 단계면 '최고 단계' · 누를 수 없음", top.state == "max" and not top.canBuy and top.buttonText == RobuxShopLogic.MAX_TEXT)
end

-- 3. 행운 줄 확률 숫자 · 제한 유저 숨김 ---------------------------------------------------------------------
do
	local ctx = { upgrades = { auraLuck = 0 }, auras = { selectedPack = 1 } }
	local aura = rowByKey(RobuxShopLogic.rows(shop(nil, false), ctx), "auraLuck10x") :: RobuxShopLogic.Row
	local tiers = AuraConfig.Packs[1].auras
	local base = UpgradeConfig.getEffect("auraLuck", 0)
	local before = RollOdds.percentages(RollOdds.distribution(tiers, base))
	local after = RollOdds.percentages(RollOdds.distribution(tiers, base * 10))
	local expect = string.format("%s %s → %s", Names.aura(tiers[#tiers].id), before[#tiers], after[#tiers])
	check("행운 줄: 확률 변화 숫자 = RollOdds(지금 → 10배)", aura.detail == expect, aura.detail .. " vs " .. expect)
	check("행운 줄: 칭호 · 펫도 숫자가 있다", string.find((rowByKey(RobuxShopLogic.rows(shop(nil, false), ctx), "titleLuck10x") :: any).detail, "%", 1, true) ~= nil
		and string.find((rowByKey(RobuxShopLogic.rows(shop(nil, false), ctx), "petLuck2x") :: any).detail, "→", 1, true) ~= nil)
	local potion = shop(nil, false, { { type = "luck", mult = 2, remainingSec = 60, receivedAt = 0 } })
	local withPotion = rowByKey(RobuxShopLogic.rows(potion, ctx), "auraLuck10x") :: RobuxShopLogic.Row
	local b2 = RollOdds.percentages(RollOdds.distribution(tiers, base * 2))
	check("행운 줄: 행운 포션 활성 중이면 '지금' 확률에 포션이 들어 있다", string.find(withPotion.detail, b2[#tiers] .. " →", 1, true) ~= nil, withPotion.detail)
	local restricted = RobuxShopLogic.rows(shop(nil, true), ctx)
	check("제한 유저: 행운 상품 줄 3개를 숨긴다", #restricted == 1 + #ShopConfig.GAMEPASS_ORDER - 3 and rowByKey(restricted, "petLuck2x") == nil
		and rowByKey(restricted, "auraLuck10x") == nil and rowByKey(restricted, "titleLuck10x") == nil and rowByKey(restricted, "damage2x") ~= nil)
	check("첫 PlayerState 전(Store 기본값)은 제한으로 본다 — 행운 줄이 안 보인다", rowByKey(RobuxShopLogic.rows(Store.new().get("shop")), "auraLuck10x") == nil)
end

-- 4. 결과 문구 ---------------------------------------------------------------------------------------
do
	check("문구: ID 0 → '준비 중이에요'", RobuxShopLogic.resultText({ key = "damage2x", kind = "gamepass", phase = "prompt", ok = false, reason = "not_registered" })
		== Locale.t("shop.reason.not_registered"))
	check("문구: 프롬프트를 띄웠으면 없음 · 닫았으면 없음", RobuxShopLogic.resultText({ key = "damage2x", phase = "prompt", ok = true, reason = "" }) == nil
		and RobuxShopLogic.resultText({ key = "damage2x", phase = "finished", ok = false, reason = "cancelled" }) == nil)
	check("문구: 구매 완료 = 이름 + 완료", RobuxShopLogic.resultText({ key = "damage2x", phase = "finished", ok = true, reason = "" }) == Locale.t("shop.purchased", { name = Names.product("damage2x") }))
	local generic = RobuxShopLogic.reasonText("???")
	local distinct = true
	for _, code in ipairs({ "already_owned", "restricted", "rate_limited", "invalid_key", "prompt_failed", "not_registered" }) do
		if RobuxShopLogic.reasonText(code) == generic then
			distinct = false
		end
	end
	check("문구: 사유 코드마다 따로", distinct)
end

-- 5. 구매 요청 한 번만 ------------------------------------------------------------------------------------
do
	local clock = 0
	local sent = {}
	local client = PurchaseClient.new({
		send = function(key: string)
			table.insert(sent, key)
		end,
		now = function()
			return clock
		end,
	})
	check("요청: 처음은 나간다", client.request("damage2x") and #sent == 1 and sent[1] == "damage2x")
	check("요청: 결과 전 같은 키 연타는 안 나간다", not client.request("damage2x") and #sent == 1 and client.isPending("damage2x"))
	check("요청: 다른 키는 따로", client.request("blox2x") and #sent == 2)
	local got = nil
	client.onResult(function(p)
		got = p
	end)
	client.handleResult({ key = "damage2x", kind = "gamepass", phase = "prompt", ok = false, reason = "not_registered" })
	task.wait()
	check("결과: 대기를 풀고 듣는 쪽에 넘긴다", not client.isPending("damage2x") and got ~= nil and got.reason == "not_registered")
	check("결과 뒤 다시 나간다", client.request("damage2x") and #sent == 3)
	clock += PurchaseClient.PENDING_TIMEOUT_SEC + 0.1
	check("결과가 안 와도 시간이 지나면 다시 나간다", client.request("damage2x") and #sent == 4)
end

-- 6. 상점 창 탭 · 로벅스 줄 -------------------------------------------------------------------------------
do
	local store = Store.new()
	store.setSource(function(setter)
		setter("shop", shop({ "blox2x" }, false))
	end)
	local sent = {}
	local client = PurchaseClient.new({
		send = function(key: string)
			table.insert(sent, key)
		end,
	})
	local handle = UpgradeShopWindow.create({ store = store, sendRequest = function() end, purchase = client, onClose = function() end })
	check("탭: 처음은 업그레이드 · 업그레이드 탭만 하늘", handle._debug.tab() == UpgradeShopWindow.TAB_UPGRADE
		and handle._debug.tabs.upgrade.selected.root.Visible and not handle._debug.tabs.robux.selected.root.Visible)
	handle._debug.selectTab(UpgradeShopWindow.TAB_ROBUX)
	check("탭 전환: 로벅스 목록만 보인다 · 로벅스 탭이 하늘", handle._debug.robuxList.Visible and not handle._debug.list.Visible
		and handle._debug.tabs.robux.selected.root.Visible and not handle._debug.tabs.upgrade.selected.root.Visible)
	local view = handle._debug.robuxView()
	local bloxIndex = 0
	for i, r in ipairs(view) do
		if r.key == "blox2x" then
			bloxIndex = i
		end
	end
	local parts = handle._debug.robuxRows[bloxIndex]
	check("로벅스 줄: 보유 = '보유 중' · 회색(잠김)", parts.buttonLabel.Text == RobuxShopLogic.OWNED_TEXT and parts.button.isDisabled())
	check("로벅스 줄: 제한 아님 → 줄 14개가 보인다", #view == 1 + #ShopConfig.GAMEPASS_ORDER and handle._debug.robuxRows[#view].frame.Visible)
	check("로벅스 줄: 크기는 Scale만(Offset 0)", parts.frame.Size.Y.Offset == 0 and parts.frame.Position.Y.Offset == 0)
	handle._debug.pressRobux(bloxIndex)
	check("로벅스 줄: 보유 줄은 눌러도 요청 없음", #sent == 0)
	withIds({ damage2x = 999 }, function()
		handle.refresh()
		local v = handle._debug.robuxView()
		for i, r in ipairs(v) do
			if r.key == "damage2x" then
				handle._debug.pressRobux(i)
				handle._debug.pressRobux(i)
			end
		end
	end)
	check("로벅스 줄: 구매 가능 줄은 누르면 그 키로 한 번만 요청", #sent == 1 and sent[1] == "damage2x", tostring(#sent))
	store.setSource(function(setter)
		setter("shop", shop({ "blox2x" }, true))
	end)
	task.wait()
	check("제한 유저: 창 줄 수가 줄고 남는 줄은 숨는다", #handle._debug.robuxView() == 1 + #ShopConfig.GAMEPASS_ORDER - 3
		and not handle._debug.robuxRows[#ShopConfig.GAMEPASS_ORDER + 1].frame.Visible)
	handle._debug.selectTab(UpgradeShopWindow.TAB_UPGRADE)
	check("탭: 다시 업그레이드로", handle._debug.list.Visible and not handle._debug.robuxList.Visible)
	handle.root:Destroy()
end

-- 7. HUD 구좌 · 자동 클리커 잠김 ---------------------------------------------------------------------------
do
	local store = Store.new()
	local requested = {}
	local slots = ShopSlots.create({
		store = store,
		requestPurchase = function(key: string)
			table.insert(requested, key)
		end,
	})
	local tile = slots.root:FindFirstChild("blox2x") :: Frame
	check("구좌: 타일마다 HitArea(누르면 구매 요청)", tile ~= nil and tile:FindFirstChild("HitArea") ~= nil)
	slots._debug.press("blox2x")
	check("구좌: 누르면 그 상품 키로 요청(ID 0도 보낸다 — 서버가 '준비 중'으로 답한다)", #requested == 1 and requested[1] == "blox2x")
	store.setSource(function(setter)
		setter("shop", shop({ "blox2x" }))
	end)
	task.wait()
	check("구좌: 보유면 가격 대신 '보유'", (tile:FindFirstChild("Price") :: TextLabel).Text == ShopSlots.OWNED_TEXT)
	slots.root:Destroy()

	local toolStore = Store.new()
	local purchases, toggles = {}, {}
	local clock = 0
	local tools = AutoTools.create({
		store = toolStore,
		requestPurchase = function(key: string)
			table.insert(purchases, key)
		end,
		sendAutoClick = function(on: boolean)
			table.insert(toggles, on)
		end,
		now = function()
			return clock
		end,
	})
	local icon = (tools.root:FindFirstChild("AutoClicker") :: Frame):FindFirstChild("Icon") :: Frame
	check("자동 클리커: 미보유면 잠김(중립 어두운 밝기 — 자동 진행 버튼과 같다)", tools._debug.isLocked() and icon.BackgroundColor3 == UiTheme.Colors.neutral.dark)
	tools._debug.press()
	check("자동 클리커 잠김: 누르면 구매 요청(autoClicker) · 토글 요청 없음", #purchases == 1 and purchases[1] == AutoTools.PURCHASE_KEY and #toggles == 0)
	toolStore.setSource(function(setter)
		setter("shop", shop({ "autoClicker" }))
	end)
	task.wait()
	check("자동 클리커: 보유면 풀린다(꺼짐 밝기)", not tools._debug.isLocked() and icon.BackgroundColor3 == UiTheme.Colors.neutral.base)
	tools._debug.press()
	tools._debug.press()
	check("자동 클리커: 누르면 켜기 요청 1번(결과 전 연타는 안 나간다)", #toggles == 1 and toggles[1] == true)
	tools.onAutoClickResult({ ok = true, reason = "", on = true, rate = 15 })
	check("자동 클리커: 결과가 오면 켜짐(밝기 · 테두리 두 채널)", tools._debug.isAutoClickerEnabled() and icon.BackgroundColor3 == UiTheme.Colors.neutral.light)
	tools._debug.press()
	check("자동 클리커: 다시 누르면 끄기 요청", #toggles == 2 and toggles[2] == false)
	toolStore.setSource(function(setter)
		setter("shop", shop({ "autoClicker" }, false, nil, false))
	end)
	tools.root:Destroy()
end

-- 8. 부스트 표시 ------------------------------------------------------------------------------------------
do
	check("시계: 14:32 · 1:02:03 · 0 아래는 0:00", BoostTimersLogic.clockText(872) == "14:32" and BoostTimersLogic.clockText(3723) == "1:02:03"
		and BoostTimersLogic.clockText(-5) == "0:00")
	local s = shop(nil, false, { { type = "strength", mult = 2, remainingSec = 900, receivedAt = 100 }, { type = "luck", mult = 2, remainingSec = 30, receivedAt = 100 } })
	local lines = BoostTimersLogic.lines(s, 100)
	check("줄: '힘 ×2 15:00' · 순서 그대로", #lines == 2 and lines[1] == Locale.t("hud.boost.line", { name = Names.boost("strength", true), mult = "×2", time = "15:00" }) and lines[2] == Locale.t("hud.boost.line", { name = Names.boost("luck", true), mult = "×2", time = "0:30" }), table.concat(lines, " | "))
	local later = BoostTimersLogic.lines(s, 100 + 40)
	check("받은 뒤로 센다: 40초 뒤 힘 14:20 · 행운은 끝나 빠진다", #later == 1 and later[1] == Locale.t("hud.boost.line", { name = Names.boost("strength", true), mult = "×2", time = "14:20" }), table.concat(later, " | "))
	check("없으면 빈 목록", #BoostTimersLogic.lines(shop(), 0) == 0)
	local store = Store.new()
	local clock = 100
	local hud = BoostTimers.create({ store = store, autoTick = false, now = function()
		return clock
	end })
	check("HUD: 활성 없으면 줄이 하나도 안 보인다(숨김)", not hud._debug.labels[1].Visible and not hud._debug.labels[2].Visible)
	store.setSource(function(setter)
		setter("shop", s)
	end)
	task.wait()
	check("HUD: 활성 2개 → 줄 2개 · 문구", hud._debug.labels[1].Visible and hud._debug.labels[1].Text == Locale.t("hud.boost.line", { name = Names.boost("strength", true), mult = "×2", time = "15:00" }) and hud._debug.labels[2].Visible
		and not hud._debug.labels[3].Visible)
	-- UDim Scale은 float32로 읽힌다(TestHelpers 상단) — 오차로 비교한다
	check("HUD: 우측 레일 맨 위 · Scale만", math.abs(hud.root.Position.Y.Scale - BoostTimers.TOP) < 1e-6 and hud.root.Position.Y.Offset == 0
		and hud.root.Size.X.Offset == 0, tostring(hud.root.Position.Y.Scale))
	hud.root:Destroy()
end

-- 9. 뽑기 창 행운 · 공허 기구 표시 ---------------------------------------------------------------------------
do
	local levels = { titleLuck = 0, petLuck = 0 }
	local base = UpgradeConfig.getEffect("titleLuck", 0)
	check("칭호 창: 행운 패스 보유 → 확률 표 행운 ×10(서버 computeLuck과 같은 항)",
		math.abs(TitleWindowLogic.luckOf(levels, shop({ "titleLuck10x" }, false)) - base * 10) < 1e-9)
	check("칭호 창: 제한 유저면 패스가 있어도 1", TitleWindowLogic.luckOf(levels, shop({ "titleLuck10x" }, true)) == base)
	check("칭호 창: shop을 안 주면 예전과 같다(업그레이드만)", TitleWindowLogic.luckOf(levels) == base)
	local pbase = UpgradeConfig.getEffect("petLuck", 0)
	check("펫 창: 펫 행운 패스 2 × 행운 포션 2 = 4", math.abs(PetWindowLogic.luckOf(levels,
		shop({ "petLuck2x" }, false, { { type = "luck", mult = 2, remainingSec = 10, receivedAt = 0 } })) - pbase * 4) < 1e-9)
	local RebirthWindowLogic = require(script.Parent.Parent.UI.Logic.RebirthWindowLogic)
	local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
	local blox = BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH * 3 + 10)
	local v1 = RebirthWindowLogic.compute(blox, BigNum.new(0, 0), shop())
	local v2 = RebirthWindowLogic.compute(blox, BigNum.new(0, 0), shop({ "rebirth2x" }))
	check("환생 창: 2배 환생이면 얻는 배수 2배(3 → 6) · 버려지는 양은 같다(S6)", BigNum.eq(v1.gained, BigNum.fromNumber(3))
		and BigNum.eq(v2.gained, BigNum.fromNumber(6)) and BigNum.eq(v1.wasted, v2.wasted))
	local voidIndex = GymConfig.findByGamepass("voidTrainingZone") :: number
	local zero = BigNum.new(0, 0)
	local notOwned = WorldLabelLogic.gym(voidIndex, zero, false, GymLayout.shopUnlocked(nil, function()
		return false
	end))
	check("공허 표시: 미보유 · ID 0 → '로벅스 전용(준비 중)'", notOwned.detail == Locale.t("world.gym.robuxOnlySoon"))
	local owned = WorldLabelLogic.gym(voidIndex, zero, true, GymLayout.shopUnlocked(nil, function(k: string)
		return k == "voidTrainingZone"
	end))
	check("공허 표시: 보유 · 서 있음 → '사용 중'", owned.detail == Locale.t("world.gym.inUse") and owned.role == "premium")
end

-- 10. 폰 크기(Galaxy A06 뷰포트 705×338) 틀 안에서 그린다 — 상점 두 탭 · 부스트 표시: 글자 하한 11px · 넘침 0 -------------
-- 기기 시뮬레이터를 켜지 않고도 매 Play 잰다: 테스트 전용 ScreenGui 안의 705×338 틀(테스트 틀만 Offset — 화면 코드는 Scale만)에
-- 실물 화면 모듈을 붙이고 TextMinimum을 건 뒤, 보이는 글자 칸마다 TextFits(하한 크기로 칸에 들어가는가)와 칸 높이 ≥ 11px를 본다.
do
	local Players = game:GetService("Players")
	local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
	local TextMinimum = require(script.Parent.Parent.UI.TextMinimum)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RobuxShopPhoneFit"
	gui.AutoLocalize = false -- K10(#L2): 우리 코드가 만드는 GUI 루트는 전부 끈다(LocaleTests 검사 대상)
	gui.ResetOnSpawn = false
	local phone = Instance.new("Frame")
	phone.Name = "Phone"
	phone.Size = UDim2.fromOffset(705, 338)
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local store = Store.new()
	store.setSource(function(setter)
		setter("shop", shop({ "strength8x", "blox2x" }, false, {
			{ type = "strength", mult = 2, remainingSec = 899, receivedAt = os.clock() },
			{ type = "damage", mult = 2, remainingSec = 3700, receivedAt = os.clock() },
			{ type = "luck", mult = 2, remainingSec = 61, receivedAt = os.clock() },
		}))
	end)
	local window = UpgradeShopWindow.create({ store = store, sendRequest = function() end,
		purchase = PurchaseClient.new({ send = function() end }), onClose = function() end })
	window.root.Parent = phone
	local hud = BoostTimers.create({ store = store, autoTick = false })
	hud.root.Parent = phone

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

	task.wait()
	task.wait()
	local h1, n1, bad1, t1 = measure(window.root)
	check(string.format("폰: 업그레이드 탭 글자 %d칸 — 넘침 0 · 칸 높이 최소 %.1fpx ≥ 11", n1, h1), n1 > 0 and bad1 == 0 and h1 >= TextScale.MIN_TEXT_PX - 0.5, t1)
	window._debug.selectTab(UpgradeShopWindow.TAB_ROBUX)
	task.wait()
	task.wait()
	local h2, n2, bad2, t2 = measure(window.root)
	check(string.format("폰: 로벅스 탭 글자 %d칸 — 넘침 0 · 칸 높이 최소 %.1fpx ≥ 11", n2, h2), n2 > 0 and bad2 == 0 and h2 >= TextScale.MIN_TEXT_PX - 0.5, t2)
	hud.refresh()
	task.wait()
	task.wait()
	local h3, n3, bad3, t3 = measure(hud.root)
	check(string.format("폰: 부스트 표시 %d줄 — 넘침 0 · 칸 높이 최소 %.1fpx ≥ 11", n3, h3), n3 == 3 and bad3 == 0 and h3 >= TextScale.MIN_TEXT_PX - 0.5, t3)
	local bx = hud.root.AbsolutePosition.X
	check("폰: 부스트 표시는 우측 레일 안(중앙 금지 구역 밖)", bx >= phone.AbsoluteSize.X * (1 - 0.2) - 0.5)
	print(string.format("[RobuxShopTests] 폰 705×338: 업그레이드 탭 최소 %.1fpx · 로벅스 탭 최소 %.1fpx · 부스트 줄 %.1fpx · 넘침 %d",
		h1, h2, h3, bad1 + bad2 + bad3))
	gui:Destroy()
end

print(string.format("[RobuxShopTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RobuxShopTests] %d test(s) failed", failed))
end

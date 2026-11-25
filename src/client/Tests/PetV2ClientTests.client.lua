--!strict
-- 새 경제 펫 · 상점 클라 검증(지시서 #35).
--   펫 창 로직(코인 비용 · 잔액 · 사유 · 트리플 코인 3배 · 제한 지역 Triple Hatch 끔) · 펫 창(코인 버튼 문구 · 자동 부화 토글 요청) ·
--   부화 연출(스킵 HATCH_SKIP_SEC · 닫힘 HATCH_ANIM_SEC) · 상태(자동 부화) · 로벅스 탭(제한 지역 켜고 끔 · 새 패스 ID nil이면 줄 없음)

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local PetWindowLogic = require(script.Parent.Parent.UI.Logic.PetWindowLogic)
local RobuxShopLogic = require(script.Parent.Parent.UI.Logic.RobuxShopLogic)
local PetWindow = require(script.Parent.Parent.UI.Screens.Window.PetWindow)
local Store = require(script.Parent.Parent.UI.Store)
local HatchFx = require(script.Parent.Parent.Economy.HatchFx)
local EconomyV2State = require(script.Parent.Parent.Economy.EconomyV2State)

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

local unit = L.eggCoinCost(1) :: any
local summary = { owned = {}, equipped = {}, storage = 50, slots = 3, world = 1 }
local rich = BigNum.new(1, 30)

-- 1. 펫 창 로직 ------------------------------------------------------------------------------------------
do
	local poor = PetWindowLogic.hatchState(summary, rich, BigNum.new(0, 0), 1) -- #37 배선: 셋째 인자가 코인
	local ok = PetWindowLogic.hatchState(summary, rich, BigNum.mul(unit, BigNum.fromNumber(2)), 1)
	check("부화(새 경제): 코인 가격 문구 · 코인이 모자라면 insufficient_coins(블럭스가 많아도)", not poor.canHatch
		and poor.buttonText == Locale.t("pet.hatchCostCoins", { cost = Formatter.format(unit) })
		and poor.footText == PetWindowLogic.reasonText("insufficient_coins"))
	check("부화(새 경제): 코인이 있으면 된다(블럭스 0이어도)", ok.canHatch)
	local shopOwn = { gamepasses = { "hatch3x" }, boosts = {}, paidRandomRestricted = false }
	local shopRestricted = { gamepasses = { "hatch3x" }, boosts = {}, paidRandomRestricted = true }
	local three = BigNum.mul(unit, BigNum.fromNumber(3))
	local t1 = PetWindowLogic.hatch3State(summary, rich, three, 1, shopOwn)
	local t2 = PetWindowLogic.hatch3State(summary, rich, BigNum.sub(three, BigNum.new(1, 0)), 1, shopOwn)
	local t3 = PetWindowLogic.hatch3State(summary, rich, three, 1, shopRestricted)
	check("트리플(새 경제): 코인 3배 · 모자라면 못 함 · 제한 지역이면 꺼짐", t1.canHatch and not t2.canHatch and not t3.canHatch
		and t1.buttonText == Locale.t("pet.hatch3Coins", { n = 3, cost = Formatter.format(three) }))
end

-- 2. 펫 창(새 경제 — 코인 · 자동 부화 토글) ---------------------------------------------------------------------
do
	local store = Store.new()
	store.setSource(function(set)
		set("pets", summary)
		set("lifetimeBlox", rich)
		set("blox", BigNum.new(0, 0))
		set("upgrades", { petLuck = 0 })
	end)
	local econ = EconomyV2State.new()
	econ.apply({ kind = "snapshot", bag = {}, used = 0, cap = 20, coins = BigNum.mul(unit, BigNum.fromNumber(5)), ores = {}, forgeOpen = true, drops = {} })
	local sentAuto = {}
	local gui = Instance.new("ScreenGui")
	local w = PetWindow.create({
		store = store,
		sendRequest = function() end,
		onClose = function() end,
		econ = econ,
		sendAuto = function(p)
			table.insert(sentAuto, p)
		end,
	})
	w.root.Parent = gui
	task.wait()
	w.refresh()
	local auto = w.root:FindFirstChild("AutoHatchButton", true)
	local hatchLabel = w._debug.hatchLabel :: TextLabel
	local shownCost = L.eggCoinCost(w._debug.shownEgg()) :: any -- 창은 열린 알 중 가장 높은 것을 보인다
	check("펫 창(새 경제): 부화 버튼이 코인 가격(보이는 알) · 자동 부화 토글이 있다", auto ~= nil
		and hatchLabel.Text == Locale.t("pet.hatchCostCoins", { cost = Formatter.format(shownCost) }), hatchLabel.Text)
	econ.apply({ kind = "auto_hatch_state", on = true, count = 4 })
	local label = if auto ~= nil then auto:FindFirstChild("Label", true) :: TextLabel? else nil
	check("펫 창(새 경제): 자동 부화 상태(켜짐 · 마리 수)가 토글 글자에", label ~= nil and label.Text == Locale.t("pet.auto.on", { count = "4" }))
	gui:Destroy()
end

-- 3. 부화 연출(스킵 5초) -----------------------------------------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	local now = 0
	local fx = HatchFx.create({ parent = gui, autoStep = false, clock = function()
		return now
	end })
	fx.show({ { petId = "egg1_common", rarity = 1 } })
	local d = fx._debug
	local open0 = fx.isOpen() and not d.skip.Visible and not d.names[1].Visible
	fx.step(HatchFx.REVEAL_SEC)
	local revealed = d.names[1].Visible and d.names[1].Text ~= ""
	fx.step(Config.HATCH_SKIP_SEC - 0.01)
	local before = d.skip.Visible
	fx.step(Config.HATCH_SKIP_SEC)
	local after = d.skip.Visible
	fx.step(Config.HATCH_ANIM_SEC)
	check("부화 연출: 알 → 결과 이름 · 스킵은 HATCH_SKIP_SEC에 · 연출 길이가 지나면 닫힘", open0 and revealed and not before and after and not fx.isOpen())
	gui:Destroy()
end

-- 4. 로벅스 탭: 제한 지역 켜고 끔 · 새 패스 ----------------------------------------------------------------------
do
	local function keys(shop: any): { [string]: boolean }
		local out = {}
		for _, r in ipairs(RobuxShopLogic.rows(shop, nil)) do
			out[r.key] = true
		end
		return out
	end
	local unrestricted = keys({ gamepasses = {}, boosts = {}, paidRandomRestricted = false })
	local restricted = keys({ gamepasses = {}, boosts = {}, paidRandomRestricted = true })
	check("로벅스 탭(새 경제): 제한 아니면 Triple Hatch 보임 · 제한이면 Triple Hatch · 행운 패스 숨김",
		unrestricted.hatch3x == true and restricted.hatch3x == nil and restricted.petLuck2x == nil and restricted.damage2x == true)
	local none = true
	for _, key in ipairs(ShopConfig.V2_PASS_ORDER) do
		none = none and unrestricted[key] == nil
	end
	check("로벅스 탭: 새 패스 4개는 ID nil이면 줄 없음", none)
end

-- 5. 상태(자동 부화) ---------------------------------------------------------------------------------------------
do
	local s = EconomyV2State.new()
	s.apply({ kind = "auto_hatch_state", on = true, count = 0 })
	s.apply({ kind = "auto_hatch_result", results = {}, count = 6, big = {} })
	local v = s.get()
	check("상태: 자동 부화 켜짐 · 마리 수 · 공용 상태는 하나", v.autoHatchOn and v.autoHatchCount == 6 and EconomyV2State.shared() == EconomyV2State.shared())
end

print(string.format("[PetV2ClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PetV2ClientTests] %d test(s) failed", failed))
end

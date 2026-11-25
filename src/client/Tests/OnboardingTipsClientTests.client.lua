--!strict
-- 새 경제 안내 · HUD 칸 · 에셋 자리 클라 검증(지시서 #36).
--   안내 줄(OnboardingTipsClient — silent 건너뜀 · 차례 · 한 번 · 보인 시간만 셈 · 강조 붙이기) · 안내 띠(기존 안내 뒤에 같은 띠 · "알겠어요") ·
--   4단계 새 경제 문장 · 상태(tips · tip) · HUD 코인 · 가방 칸 · 레일 칸 숨김(자리 그대로) · 그림 자리 · 드롭 · 대장간 모델 틀 · 부화 연출 그림

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local Client = script.Parent.Parent
local OnboardingTipsClient = require(Client.Economy.OnboardingTipsClient)
local EconomyV2State = require(Client.Economy.EconomyV2State)
local DropRenderer = require(Client.Economy.DropRenderer)
local ForgeSite = require(Client.Economy.ForgeSite)
local HatchFx = require(Client.Economy.HatchFx)
local OnboardingBand = require(Client.UI.Screens.Overlay.OnboardingBand)
local OnboardingLogic = require(Client.UI.Logic.OnboardingLogic)
local EconomyHud = require(Client.UI.Screens.Hud.EconomyHud)
local MenuRail = require(Client.UI.Screens.Hud.MenuRail)
local Store = require(Client.UI.Store)

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

-- 1. 안내 줄 -------------------------------------------------------------------------------------------------
do
	local attached, detached = {}, {}
	local tips = OnboardingTipsClient.create({
		attach = function(g)
			table.insert(attached, g)
		end,
		detach = function(g)
			table.insert(detached, g)
		end,
	})
	local coinGui = Instance.new("Frame")
	local bloxGui = Instance.new("Frame")
	tips.register("coins", coinGui)
	tips.register("blox", bloxGui)
	tips.onEvent({ kind = "tip", key = "blox", silent = true })
	local none = tips.current()
	tips.onEvent({ kind = "tip", key = "blox", silent = false })
	tips.onEvent({ kind = "tip", key = "coins", silent = false })
	tips.onEvent({ kind = "tip", key = "coins", silent = false })
	tips.onEvent({ kind = "tip", key = "nope", silent = false })
	check("안내 줄: 글 없는 것은 안 넣음 · 차례(blox → coins) · 같은 것 두 번 · 모르는 키는 버림", none == nil and tips.current() == "blox"
		and #tips._debug.queue == 2)
	check("강조: 지금 안내의 자리에 빛 띠", attached[#attached] == bloxGui and tips._debug.highlighted() == bloxGui)
	tips.step(OnboardingConfig.TIP_SHOW_SEC + 1, false)
	local stillBlox = tips.current() == "blox"
	tips.step(OnboardingConfig.TIP_SHOW_SEC, true)
	check("시간: 띠에 보일 때만 센다 · TIP_SHOW_SEC가 지나면 다음 것", stillBlox and tips.current() == "coins" and detached[#detached] == bloxGui
		and tips._debug.highlighted() == coinGui)
	tips.dismiss()
	check("알겠어요: 다음 것 · 다 보면 강조도 뗀다", tips.current() == nil and tips._debug.highlighted() == nil and detached[#detached] == coinGui)
	coinGui:Destroy()
	bloxGui:Destroy()
end

-- 2. 안내 띠 ---------------------------------------------------------------------------------------------------
do
	local tips = OnboardingTipsClient.create({ attach = function() end, detach = function() end })
	local showing = false
	local source = { current = tips.current, dismiss = tips.dismiss, subscribe = tips.subscribe, setShowing = function(on: boolean)
		showing = on
	end }
	local store = Store.new()
	store.setSource(function(setter)
		setter("onboarding", { step = 3, done = false })
	end)
	local b = OnboardingBand.create({ store = store, send = function() end, tips = source })
	tips.onEvent({ kind = "tip", key = "coins", silent = false })
	local mainFirst = b._debug.text.Text == Locale.t("onboarding.step.3") and not showing
	store.setSource(function(setter)
		setter("onboarding", { step = 5, done = true })
	end)
	task.wait()
	b.refresh()
	local tipShown = b._debug.panel.Visible and b._debug.text.Text == Locale.t("onboarding.tip.coins")
		and b._debug.progress.Text == Locale.t("onboarding.tip.title") and b._debug.buttonLabel.Text == Locale.t("onboarding.finish") and showing
	check("띠: 기존 안내 중에는 기존 단계(안내는 기다림) · 끝나면 같은 띠에 새 경제 안내", mainFirst and tipShown)
	b._debug.press()
	check("띠: 알겠어요 → 다음 것 · 없으면 숨김 · 요청 안 보냄", tips.current() == nil and not b._debug.panel.Visible and #b._debug.sent == 0)
	b.root:Destroy()
	local s2 = Store.new()
	s2.setSource(function(setter)
		setter("onboarding", { step = 5, done = true })
	end)
	local plain = OnboardingBand.create({ store = s2, send = function() end })
	check("띠(꺼짐 — tips 없음): 끝났으면 숨김 · 지금 그대로", not plain._debug.panel.Visible)
	plain.root:Destroy()
	check("4단계 문장: 진행 · 수령 차이(v2 — #37 다: 꺼짐 문장은 지웠다)",
		OnboardingLogic.view({ step = 4, done = false }, false).text == Locale.t("onboarding.step.4.v2"))
end

-- 3. 상태 · HUD 칸 ------------------------------------------------------------------------------------------------
do
	local s = EconomyV2State.new()
	s.apply({ kind = "tips", seen = { "blox" }, off = false })
	s.apply({ kind = "tip", key = "coins", silent = true })
	local v = s.get()
	check("상태: tips 전체 · tip 하나(글 없어도 칸은 지난 것으로)", v.tipsSeen.blox == true and v.tipsSeen.coins == true and v.tipsOff == false)
	local gui = Instance.new("ScreenGui")
	local hud = EconomyHud.create(gui)
	local base = { coins = BigNum.new(0, 0), bagUsed = 0, bagCap = 20, forgeOpen = false }
	local function withSeen(seen: any): any
		local t = table.clone(base)
		t.tipsSeen = seen
		return t
	end
	hud.set(withSeen({}))
	local hidden = not hud.coinRow.Visible and not hud.bagRow.Visible
	hud.set(withSeen({ coins = true }))
	local coinOnly = hud.coinRow.Visible and not hud.bagRow.Visible
	hud.set(base)
	check("HUD: 코인 · 가방 칸은 그 안내를 지나야 보임 · 안내 상태가 없으면(지금 값) 그대로 보임", hidden and coinOnly and hud.coinRow.Visible and hud.bagRow.Visible)
	gui:Destroy()
	local rail = MenuRail.create(0.2)
	local tile = rail.item("Rebirth") :: Frame
	local before = #rail.root:GetChildren()
	rail.setItemShown("Rebirth", false)
	local anyVisible = false
	for _, c in ipairs(tile:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then
			anyVisible = true
		end
	end
	local hiddenOk = tile.Visible and not anyVisible and #rail.root:GetChildren() == before
	rail.setItemShown("Rebirth", true)
	local hit = tile:FindFirstChild("HitArea", true) :: GuiObject?
	check("레일: 칸 숨김은 자리 그대로(칸 Frame은 보임 · 안만 숨김) · 다시 보임", hiddenOk and hit ~= nil and hit.Visible)
	rail.root:Destroy()
end

-- 4. 에셋 자리(가짜 값 · 가짜 틀) ---------------------------------------------------------------------------------
do
	local f = Instance.new("Frame")
	local none = AssetSlots.applyImage(f, nil)
	local img = AssetSlots.applyImage(f, 777)
	local hiddenAgain = AssetSlots.applyImage(f, nil)
	check("그림 자리: 값이 없으면 임시 도형 · 있으면 그 그림(rbxassetid) · 다시 없으면 숨김", none == nil and img ~= nil and img.Image == "rbxassetid://777"
		and hiddenAgain == nil and not (img :: ImageLabel).Visible)
	f:Destroy()
end
do
	local folder = Instance.new("Folder")
	local tpl = Instance.new("Part")
	tpl.Size = Vector3.new(2, 3, 2)
	tpl.Name = "ore_1"
	local r = DropRenderer.create({ parent = folder, autoStep = false, template = function(key: string): Instance?
		return if key == "ore_1" then tpl else nil
	end })
	r.spawn({ { id = 1, ore = 1, position = Vector3.zero }, { id = 2, ore = 2, position = Vector3.zero } })
	local p1, p2 = r.partOf(1), r.partOf(2)
	check("드롭: 틀이 있으면 그 모델(크기 그대로 · 고정 · 충돌 끔) · 없으면 임시 도형", p1 ~= nil and p1.Size == tpl.Size and p1.Anchored and not p1.CanCollide
		and p1:GetAttribute("PoolKey") == "ore_1" and p2 ~= nil and p2:GetAttribute("PoolKey") == "temp")
	r.destroy()
	folder:Destroy()
	tpl:Destroy()
end
do
	local parent = Instance.new("Folder")
	local tpl = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Parent = tpl
	tpl.PrimaryPart = body
	local site = ForgeSite.create({ parent = parent, onOpen = function() end, template = function(key: string): Instance?
		return if key == "forge_site" then tpl else nil
	end })
	site.setOpen(true)
	local m = site.model()
	local fromTpl = m ~= nil and m:FindFirstChild("Body") ~= nil and site.prompt() ~= nil and (site.prompt() :: any).Parent.Name == "Body"
		and (m :: any).Body.Anchored
	site.destroy()
	local plain = ForgeSite.create({ parent = parent, onOpen = function() end, template = function()
		return nil
	end })
	plain.setOpen(true)
	local temp = plain.model() ~= nil and (plain.model() :: any):FindFirstChild("Base") ~= nil
	plain.destroy()
	check("대장간: 틀이 있으면 그 모델(프롬프트는 주 파트 · 고정) · 없으면 임시 도형", fromTpl and temp)
	parent:Destroy()
	tpl:Destroy()
end
do
	local gui = Instance.new("ScreenGui")
	local fx = HatchFx.create({ parent = gui, autoStep = false, clock = function()
		return 0
	end })
	check("부화 연출: 그림 자리가 nil이면 임시 알 칸(빛 그림 없음)", fx._debug.egg.BackgroundTransparency == 0 and fx._debug.burst == nil
		and fx._debug.egg:FindFirstChild("SlotImage") == nil)
	gui:Destroy()
end

-- 5. 펫 모델 · 토큰 아이콘 자리(#37 6단계) -------------------------------------------------------------------
do
	local PetRenderLogic = require(Client.World.PetRenderLogic)
	local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
	local tpl = Instance.new("Part")
	tpl.Size = Vector3.new(2, 2, 2)
	local id = PetConfig.Eggs[1].pets[1].id
	local function find(key: string): Instance?
		return if key == "pet_" .. id then tpl else nil
	end
	local pet: any = { petId = id, level = 2, size = PetConfig.DISPLAY.SIZE_BY_LEVEL[2] }
	local got = PetRenderLogic.templateOf(id, find)
	local none = PetRenderLogic.templateOf(PetConfig.Eggs[1].pets[2].id, find)
	local size = PetRenderLogic.templateSize(tpl, pet)
	check("펫 모델: 틀이 있으면 그 파트 · 없으면 nil(임시 구) · 크기는 단계 비율", got == tpl and none == nil
		and math.abs(size.X - 2 * PetConfig.DISPLAY.SIZE_BY_LEVEL[2] / PetConfig.DISPLAY.SIZE_BY_LEVEL[1]) < 1e-6)
	tpl:Destroy()

	local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
	local ForgeWindow = require(Client.UI.Screens.Window.ForgeWindow)
	local saved = Config.TOKEN_VISUALS.rare.iconId
	local w = ForgeWindow.create({ send = function() end, onClose = function() end })
	w._debug.setExTab("rare")
	local before = w._debug.haveText:FindFirstChild("SlotImage")
	Config.TOKEN_VISUALS.rare.iconId = 5150
	w._debug.setExTab("rare")
	local img = w._debug.haveText:FindFirstChild("SlotImage") :: ImageLabel?
	Config.TOKEN_VISUALS.rare.iconId = saved
	check("토큰 아이콘: 값이 없으면 글자만 · 있으면 교환소 보유 줄에 그 그림(rbxassetid)", before == nil and img ~= nil and img.Image == "rbxassetid://5150" and img.Visible)
	w.root:Destroy()
end

print(string.format("[OnboardingTipsClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[OnboardingTipsClientTests] %d test(s) failed", failed))
end

--!strict
-- UI 미리보기 화면(Studio 전용 — 2026-11-26 지시서 #39 5단계 · docs/UI.md "UI 키트 > 미리보기 화면").
-- 켜는 곳: WindowBoot의 TEST_UI_PREVIEW(커밋 값 nil — tools/check_test_gate.py · UiKitTests가 본다).
-- 켜면 화면 왼쪽에 창 목록이 생긴다 — 누르면 그 창을 **예시 데이터**로 연다(8층까지 플레이하지 않고 창별 확인).
--
--   - 창은 실물 창 모듈의 create()를 예시 Store(Store.new) · 예시 새 경제 상태로 따로 만든다. 요청 · 구매는 아무 데도 보내지 않는다
--     (sendRequest · send · purchase가 빈 함수). 서버 · 프로필은 건드리지 않는다
--   - LANG: 지금 언어를 SUPPORTED의 다음 언어로 바꾸고(en → ko → es → pt → fr → de) 창을 다시 만든다. ⚠️ 모듈을 불러올 때 정해지는 문장(창 제목 상수 등 61곳)은 접속 언어 그대로다 —
--     전부 보려면 Bootstrap TEST_LOCALE을 같이 켠다
--   - LONG: 모든 문장을 두 번 이어 붙여(Locale._setStretch) 넘침을 본다
--   - KIT: 키트 견본 — 버튼 6색 · 탭 · 게이지 · 등급별 칸(장비 6 · 희귀도 6) · 확률 표 줄 · 토스트
--   - 오버레이(결과 모달 · 일일 보상 · 환생 알림 · 토스트 · 부화 연출)는 예시 값으로 띄운다
-- 글자: 목록 버튼은 개발 도구 표시(창 이름 · LANG · LONG · KIT)라 Strings 키를 쓰지 않는다 — 플레이어에게 보이지 않는다(게시 빌드에서 돌지 않음).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestGate = require(ReplicatedStorage.Shared.TestGate)

local UiPreview = {}

local requested: any = nil
local registered = false

-- WindowBoot가 커밋 값을 알린다(UiKitTests가 nil인지 본다 — TestPresetGate와 같은 통로)
function UiPreview.register(flag: any)
	registered = true
	requested = flag
end
function UiPreview.isRegistered(): boolean
	return registered
end
function UiPreview.getRequested(): any
	return requested
end

-- 켤까: Studio이고 플래그가 켜져 있을 때만(TestGate.flagOn)
function UiPreview.shouldRun(flag: any, isStudio: boolean?): boolean
	return TestGate.flagOn(flag, isStudio)
end

-- 창 목록(이름 = 미리보기 버튼 글자). 순서 = 1월 확인 순서(새 경제 → 뽑기 → 진행 → 설정 · 오버레이)
UiPreview.WINDOWS = {
	"Forge", "Equipment", "Pet", "Title", "Aura", "Shop", "Rebirth", "Warp", "AutoAdvance", "Settings", "Code",
	"Daily", "Result", "RebirthNotice", "Toast", "Hatch", "KIT",
}

-- ===== 예시 데이터 =====================================================================================

function UiPreview.sampleState(): { [string]: any }
	local BigNum = require(ReplicatedStorage.Shared.BigNum)
	local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
	local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
	local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
	local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
	local titles = {}
	for i, def in ipairs(TitleConfig.Titles) do
		if i % 2 == 1 then
			table.insert(titles, def.id)
		end
	end
	local auras = {}
	for _, a in ipairs(((AuraConfig.Packs[1] :: any) or {}).auras or {}) do
		table.insert(auras, a.id)
	end
	local pets = {}
	local n = 0
	for egg = 1, #PetConfig.Eggs do
		for _, def in ipairs(PetConfig.Eggs[egg].pets) do
			n += 1
			table.insert(pets, { uid = tostring(n), petId = def.id, level = 1 + (n % 3) })
		end
	end
	local upgrades = {}
	for name in pairs(UpgradeConfig.Upgrades or {}) do
		upgrades[name] = 3
	end
	return {
		strength = BigNum.new(1.23, 15),
		blox = BigNum.new(4.56, 12),
		lifetimeBlox = BigNum.new(7.89, 14),
		lifeBlox = BigNum.new(1.5, 13),
		rebirths = BigNum.fromNumber(15),
		maxStage = 24,
		padIndex = 12,
		upgrades = upgrades,
		titles = { owned = titles, equipped = titles[1] or "", autoRoll = false },
		auras = { owned = auras, equipped = auras[1] or "", selectedPack = 1, hideOtherAuras = false, world = 1 },
		pets = { owned = pets, equipped = { pets[1] and pets[1].uid or "" }, slots = 3, storage = 50, hideOtherPets = false, world = 1 },
		shop = { gamepasses = {}, paidRandomRestricted = false, boosts = { { type = "luck", mult = 2, remainingSec = 300, receivedAt = os.clock() } },
			autoClick = false, potions = { strength = 2, damage = 1, luck = 3 }, rollCredits = { lucky = 2, super = 1 }, gymUnlocks = {} },
		autoAdvance = { active = false, target = 20, safeFloor = 10, runs = 0, maxTarget = 25 },
		daily = { canClaim = true, claimedToday = false, day = 3, streak = 2, secondsToReset = 3600, today = 100, receivedAt = os.clock() },
		onboarding = { step = 2, done = false },
		settings = { reduceMotion = false, sfxEnabled = true },
	}
end

function UiPreview.sampleStore(): any
	local Store = require(script.Parent.Parent.UI.Store)
	local store = Store.new()
	local state = UiPreview.sampleState()
	store.setSource(function(set)
		for key, v in pairs(state) do
			set(key :: any, v)
		end
	end)
	return store
end

-- 새 경제 값(대장간 · 장비 · 코인). 곡괭이는 등급마다 하나 이상 · 광석 전부 · 토큰 전부
function UiPreview.sampleEconomy(): { [string]: any }
	local BigNum = require(ReplicatedStorage.Shared.BigNum)
	local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
	local ores = {}
	for k = 1, Config.ORE_COUNT do
		ores[k] = k * 7
	end
	local equipment = {}
	local owned = {}
	local equipped = ""
	for i, def in ipairs(Config.PICKAXES) do
		if i % 2 == 1 or i == #Config.PICKAXES then
			equipment[def.id] = { count = i, stars = i % 6, enh = i % 11 }
			owned[def.id] = i
			equipped = def.id
		end
	end
	return {
		coins = BigNum.new(3.21, 9),
		bagUsed = 18,
		bagCap = 20,
		bag = ores,
		ores = ores,
		forgeOpen = true,
		tokens = { rare = 12, epic = 6, mythic = 2, legendary = 1 },
		owned = owned,
		autoOn = false,
		autoCount = 0,
		equipment = equipment,
		equipped = equipped,
		autoHatchOn = false,
		autoHatchCount = 0,
		tipsSeen = {},
		tipsOff = false,
	}
end

-- ===== 화면 ===========================================================================================

type Built = { root: GuiObject, open: (() -> ())?, close: (() -> ())? }

local function noop() end

local function build(name: string, store: any, gui: ScreenGui): Built?
	local PurchaseClient = require(script.Parent.Parent.Net.PurchaseClient)
	local fakePurchase = PurchaseClient.new({ send = noop } :: any)
	local Screens = script.Parent.Parent.UI.Screens
	local econValues = UiPreview.sampleEconomy()
	local econ = {
		get = function()
			return econValues
		end,
		subscribe = noop,
		apply = function()
			return false
		end,
	}
	if name == "Forge" then
		local w = require(Screens.Window.ForgeWindow).create({ send = noop, onClose = noop, openEquipment = noop })
		w.set(econValues)
		return { root = w.root }
	elseif name == "Equipment" then
		local w = require(Screens.Window.EquipmentWindow).create({ send = noop, onClose = noop })
		w.set(econValues)
		return { root = w.root }
	elseif name == "Pet" then
		local w = require(Screens.Window.PetWindow).create({ store = store, sendRequest = noop, purchase = fakePurchase, onClose = noop, econ = econ,
			sendAuto = noop })
		return { root = w.root, open = w.onOpen }
	elseif name == "Title" then
		local w = require(Screens.Window.TitleWindow).create({ store = store, sendRequest = noop, purchase = fakePurchase, onClose = noop })
		return { root = w.root }
	elseif name == "Aura" then
		local w = require(Screens.Window.AuraWindow).create({ store = store, sendRequest = noop, purchase = fakePurchase, onClose = noop,
			openTitles = noop })
		return { root = w.root }
	elseif name == "Shop" then
		local w = require(Screens.Window.UpgradeShopWindow).create({ store = store, sendRequest = noop, purchase = fakePurchase,
			potion = fakePurchase, onClose = noop })
		return { root = w.root }
	elseif name == "Rebirth" then
		local w = require(Screens.Window.RebirthWindow).create({ store = store, sendRequest = noop, onClose = noop, openShop = noop })
		return { root = w.root }
	elseif name == "Warp" then
		local w = require(Screens.Window.WarpWindow).create({ store = store, sendRequest = noop, onClose = noop })
		return { root = w.root, open = w.onOpen }
	elseif name == "AutoAdvance" then
		local AutoAdvanceClient = require(script.Parent.Parent.Net.AutoAdvanceClient)
		local w = require(Screens.Window.AutoAdvanceWindow).create({ store = store, client = AutoAdvanceClient.new({ send = noop } :: any),
			onClose = noop })
		return { root = w.root, open = w.onOpen }
	elseif name == "Settings" then
		local w = require(Screens.Window.SettingsWindow).create({ store = store, sendRequest = noop, onClose = noop, openCode = noop })
		return { root = w.root }
	elseif name == "Code" then
		local w = require(Screens.Window.CodeWindow).create({ send = noop, onClose = noop })
		return { root = w.root }
	elseif name == "Daily" then
		local w = require(Screens.Overlay.DailyRewardWindow).create({ store = store, sendClaim = noop })
		return { root = w.root, open = w.show, close = w.hide }
	elseif name == "Result" then
		local w = require(Screens.Overlay.ResultModal).create()
		return { root = w.root, open = function()
			local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
			w.show({ heading = Locale.t("pet.hatching"), name = "Legendary Sample", rarityTier = 6, detail = "x3.5" })
		end, close = w.hide }
	elseif name == "RebirthNotice" then
		local BigNum = require(ReplicatedStorage.Shared.BigNum)
		local w = require(Screens.Overlay.RebirthNotice).create()
		return { root = w.root, open = function()
			w.show({ title = "Rebirth!", change = "x1.5 → x2.0", reset = "Blox · Floor", before = BigNum.new(1.5, 0), after = BigNum.new(2, 0) })
		end }
	elseif name == "Toast" then
		local w = require(Screens.Overlay.ToastStack).create()
		return { root = w.root, open = function()
			for tier = 1, 6 do
				w.push({ text = "Tier " .. tier .. " sample toast", tier = tier })
			end
		end }
	elseif name == "Hatch" then
		local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
		local w = require(script.Parent.Parent.Economy.HatchFx).create({ parent = gui })
		local pets = {}
		for i = 1, math.min(3, #PetConfig.Eggs[1].pets) do
			table.insert(pets, { petId = PetConfig.Eggs[1].pets[#PetConfig.Eggs[1].pets - i + 1].id })
		end
		return { root = w.root, open = function()
			w.show(pets)
		end }
	elseif name == "KIT" then
		return { root = UiPreview.kitSheet() }
	end
	return nil
end

-- 창 하나를 예시 데이터로 만든다(UiKitTests가 목록 전부를 만들어 본다). 없는 이름이면 nil
UiPreview.build = build

-- 키트 견본 한 장 — 1월 템플릿이 바꾸는 부품이 전부 한 화면에 있다
function UiPreview.kitSheet(): Frame
	local Kit = require(script.Parent.Parent.UI.Components.Kit)
	local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
	local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
	local panel = Kit.panel("Large", "UI KIT")
	panel.root.Name = "KitSheet"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }
	-- 버튼 6색 · 눌림 · 비활성
	for i, color in ipairs({ "yellow", "purple", "blue", "green", "red", "gray" }) do
		local b = Kit.labeledButton("Btn_" .. color, body, color :: any, (i - 1) * 0.165, 0, 0.155, 0.09, color)
		table.insert(raise, b.root)
	end
	local pressed = Kit.labeledButton("Pressed", body, "blue", 0, 0.1, 0.155, 0.09, "pressed")
	pressed.setPressed(true)
	local disabled = Kit.labeledButton("Disabled", body, "blue", 0.165, 0.1, 0.155, 0.09, "disabled")
	disabled.setDisabled(true)
	table.insert(raise, pressed.root)
	table.insert(raise, disabled.root)
	-- 탭 둘(고른 것 · 안 고른 것)
	local t1 = Kit.tab("TabOn", body, 0.35, 0.1, 0.15, 0.09, "tab on")
	t1.setSelected(true)
	local t2 = Kit.tab("TabOff", body, 0.51, 0.1, 0.15, 0.09, "tab off")
	table.insert(raise, t1.button.root)
	table.insert(raise, t2.button.root)
	-- 게이지
	local g = Kit.gauge("Gauge", body, 0.68, 0.12, 0.3, 0.05)
	g.root.ZIndex = Kit.Z_TEXT
	g.fill.ZIndex = Kit.Z_TEXT
	g.set(0.62)
	-- 장비 등급 칸(C1)
	for i, grade in ipairs({ "common", "rare", "epic", "mythic", "legendary", "next" }) do
		local card = Kit.card("Grade_" .. grade, body, (i - 1) * 0.165, 0.22, 0.155, 0.2,
			{ fill = UiTheme.Colors.neutral.dark, alpha = UiTheme.Skin.alpha.cell, line = UiTheme.Skin.line.slot, lineColor = Kit.gradeColor(grade),
				image = "card" }, Kit.Z_TEXT)
		local l = Kit.text("Name", card, "small", 0.05, 0.3, 0.9, 0.4, Enum.TextXAlignment.Center)
		l.Text = if grade == "next" then "???" else Locale.t("grade." .. grade)
		l.TextColor3 = Kit.gradeColor(grade)
	end
	-- 희귀도 6단계(칭호 · 아우라 · 펫)
	for tier = 1, 6 do
		local card = Kit.card("Rarity_" .. tier, body, (tier - 1) * 0.165, 0.45, 0.155, 0.12,
			{ fill = UiTheme.Colors.neutral.dark, alpha = UiTheme.Skin.alpha.cell, line = UiTheme.Skin.line.cell, lineColor = Kit.rarityColor(tier) },
			Kit.Z_TEXT)
		local l = Kit.text("Name", card, "small", 0.05, 0.2, 0.9, 0.6, Enum.TextXAlignment.Center)
		l.Text = "tier" .. tier
		l.TextColor3 = Kit.rarityColor(tier)
	end
	-- 확률 표 줄 · 토스트 줄
	local odds = Kit.box("Odds", body, 0, 0.6, 0.48, 0.38, Kit.Z_TEXT)
	for i = 1, 5 do
		local nameL, pctL = Kit.oddsRow(odds, i, 1 / 5, 0.68)
		nameL.Text = Locale.t("grade." .. ({ "common", "rare", "epic", "mythic", "legendary" })[i])
		nameL.TextColor3 = Kit.gradeColor(({ "common", "rare", "epic", "mythic", "legendary" })[i])
		pctL.Text = string.format("%.2f%%", 60 / i)
	end
	for tier = 1, 3 do
		local row = Kit.toastRow("Toast" .. tier, "small")
		row.Position = UDim2.fromScale(0.52, 0.6 + (tier - 1) * 0.1)
		row.Size = UDim2.fromScale(0.46, 0.08)
		row.ZIndex = Kit.Z_TEXT
		row.Text = "toast tier " .. (tier * 2) .. " "
		row.TextColor3 = Kit.rarityColor(tier * 2)
		row.Parent = body
	end
	Kit.raiseButtons(raise)
	return panel.root
end

function UiPreview.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	if not UiPreview.shouldRun(requested) then
		return
	end
	local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
	local Button = require(script.Parent.Parent.UI.Components.Button)
	local WindowParts = require(script.Parent.Parent.UI.Components.WindowParts)

	local gui = Instance.new("ScreenGui")
	gui.Name = "UiPreviewGui"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false
	gui.DisplayOrder = 200 -- 실물 HUD · 창 · 오버레이 위
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromScale(1, 1)
	stage.Parent = gui

	local current: Built? = nil
	local currentName: string? = nil
	local function show(name: string)
		if current ~= nil then
			if current.close ~= nil then
				pcall(current.close :: () -> ())
			end
			current.root:Destroy()
			current = nil
		end
		stage:ClearAllChildren()
		currentName = name
		local ok, built = pcall(build, name, UiPreview.sampleStore(), gui)
		if not ok or built == nil then
			warn(string.format("[UiPreview] %s 창을 못 만들었다 — %s", name, tostring(built)))
			return
		end
		local b = built :: Built
		b.root.Parent = stage
		b.root.Visible = true
		if b.open ~= nil then
			(b.open :: () -> ())()
		end
		current = b
		print(string.format("[UiPreview] %s · 언어 %s · LONG %s", name, Locale.current(), tostring(Locale._isStretched())))
	end

	-- 목록(왼쪽 띠 — 화면 폭 9%)
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundColor3 = Color3.new(0, 0, 0)
	list.BackgroundTransparency = 0.4
	list.Position = UDim2.fromScale(0, 0.02)
	list.Size = UDim2.fromScale(0.09, 0.96)
	list.ZIndex = 50
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.004, 0)
	layout.Parent = list
	local items = table.clone(UiPreview.WINDOWS)
	table.insert(items, "LANG")
	table.insert(items, "LONG")
	local rowH = 1 / (#items + 1)
	for i, name in ipairs(items) do
		local b = Button.create({ size = "Small", color = if name == "KIT" then "purple" elseif i > #UiPreview.WINDOWS then "green" else "gray",
			widthScale = 1, heightScale = rowH })
		b.root.Name = "Item_" .. name
		b.root.LayoutOrder = i
		b.root.Parent = list
		local label, hit = WindowParts.decorateButton(b, name)
		label.AutoLocalize = false
		WindowParts.raiseButtons({ b.root })
		for _, o in ipairs(b.root:GetDescendants()) do
			if o:IsA("GuiObject") then
				o.ZIndex += 50
			end
		end
		hit.Activated:Connect(function()
			if name == "LANG" then -- 지금 언어 → SUPPORTED의 다음 언어(en → ko → es → pt → fr → de → en — 지시서 #40)
				local codes = Locale.SUPPORTED
				local nextCode = codes[1]
				for idx, code in ipairs(codes) do
					if code == Locale.current() then
						nextCode = codes[idx % #codes + 1]
					end
				end
				Locale._setCurrent(nextCode)
			elseif name == "LONG" then
				Locale._setStretch(not Locale._isStretched())
			else
				show(name)
				return
			end
			if currentName ~= nil then
				show(currentName :: string)
			end
		end)
	end
	print("[UiPreview] 켜짐 — 왼쪽 목록에서 창을 고른다(예시 데이터 · 요청은 안 나간다). 커밋 전에 WindowBoot TEST_UI_PREVIEW = nil")
end

return UiPreview

--!strict
-- 새 경제 클라 진입점(지시서 #32).
-- 켜져 있으면: 서버 EconomyEvent를 받아 → 상태(EconomyV2State) · 드롭 표시(DropRenderer) · 코인 이펙트(CoinFx) · HUD(EconomyHud).
-- 대장간 알림 · 안내 토스트는 OverlayBoot가 같은 채널을 듣고 띄운다(토스트 칸이 그쪽에 있다).
-- #33: 대장간 창(ForgeWindow — ScreenController "Forge") · 로비 임시 대장간(ForgeSite — 근접 프롬프트) · HUD 대장간 버튼.
--      대장간이 열리기 전에는 셋 다 안 보인다(창을 여는 길이 없다). 요청은 ForgeRequest, 결과는 EconomyEvent forge_* kind.
-- 판정은 전부 서버다 — 여기는 받은 것을 그린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyV2State = require(script.Parent.EconomyV2State)
local DropRenderer = require(script.Parent.DropRenderer)
local CoinFx = require(script.Parent.CoinFx)
local EconomyHud = require(script.Parent.Parent.UI.Screens.Hud.EconomyHud)
local ForgeWindow = require(script.Parent.Parent.UI.Screens.Window.ForgeWindow)
local EquipmentWindow = require(script.Parent.Parent.UI.Screens.Window.EquipmentWindow)
local ForgeSite = require(script.Parent.ForgeSite)
local ScreenController = require(script.Parent.Parent.UI.ScreenController)
local HatchFx = require(script.Parent.HatchFx)
local OnboardingTipsClient = require(script.Parent.OnboardingTipsClient)

local gui = Instance.new("ScreenGui")
gui.Name = "EconomyV2Gui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- 코인 이펙트가 카메라 뷰포트 좌표를 그대로 쓴다(HudGui와 같은 설정)
gui.DisplayOrder = 1
gui.AutoLocalize = false -- 글자는 Strings 키(Locale.t) — 자동 번역을 끈다(K10 · #37 켜 보고 잡은 결함)
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local state = EconomyV2State.shared() -- 펫 창(#35)이 같은 상태를 읽는다
local hud = EconomyHud.create(gui)
hud.set(state.get())
state.subscribe(hud.set)
-- 접속 직후에는 기본 UI 인셋이 0으로 읽힐 수 있다(Play 실측 #32). #33부터 EconomyHud가 인셋 변경 신호(TopbarInset)로 다시 맞춘다

local drops = DropRenderer.create()
local coins = CoinFx.create({ parent = gui, target = hud.coinTarget })

local channels = Remotes.getClient()

-- ===== 대장간(#33) ===================================================================================
local forgeWindow = ForgeWindow.create({
	send = function(payload: any)
		channels.forgeRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Forge")
	end,
	openEquipment = function()
		ScreenController.open("Equipment")
	end,
})
-- 장비 창(#34) — 대장간이 열린 뒤에만 연다(HUD 장비 버튼 · 대장간 창 링크)
local equipmentWindow = EquipmentWindow.create({
	send = function(payload: any)
		channels.equipmentRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Equipment")
	end,
})
ScreenController.register("Equipment", "Window", function()
	return equipmentWindow.root
end)
ScreenController.register("Forge", "Window", function()
	return forgeWindow.root
end)
local function openForge()
	if state.get().forgeOpen then
		ScreenController.open("Forge")
	end
end
local site = ForgeSite.create({ onOpen = openForge })
hud.forgeHit.Activated:Connect(openForge)
hud.equipHit.Activated:Connect(function()
	if state.get().forgeOpen then
		ScreenController.open("Equipment")
	end
end)
state.subscribe(function(values)
	site.setOpen(values.forgeOpen)
	forgeWindow.set(values)
	equipmentWindow.set(values)
end)
-- 새 경제 안내(#36): 강조 자리 · 안내 상태 다시 받기(접속 직후 보낸 것을 놓쳤을 수 있다)
local tips = OnboardingTipsClient.shared()
-- 강조는 줄(가로 목록) 대신 그 안의 아이콘 · 글자에 붙인다 — 빛 띠 덮개가 목록의 칸이 되어 글자를 밀었다(#36 Play 실측)
tips.register("coins", hud.coinIcon)
tips.register("bag", hud.bagName)
tips.register("forge", hud.forgeButton)
tips.register("equip", hud.equipButton)
channels.onboardingTipRequest:FireServer({ action = "sync" })
channels.forgeRequest:FireServer({ action = "sync" })
channels.equipmentRequest:FireServer({ action = "sync" })

-- 부화 연출(#35 — 손으로 부화한 결과마다 · 스킵 5초). 결과 모달 대신이다(OverlayBoot는 새 경제면 부화 모달을 띄우지 않는다)
local hatchGui = Instance.new("ScreenGui")
hatchGui.Name = "HatchFxGui"
hatchGui.ResetOnSpawn = false
hatchGui.IgnoreGuiInset = true
hatchGui.AutoLocalize = false
hatchGui.DisplayOrder = 50 -- 펫 창(Window 층) 위에 덮는다
hatchGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local hatchFx = HatchFx.create({ parent = hatchGui })
channels.petResult.OnClientEvent:Connect(function(payload: any)
	if type(payload) == "table" and payload.ok == true and (payload.action == "hatch" or payload.action == "hatch3")
		and type(payload.pets) == "table" and #payload.pets > 0 then
		hatchFx.show(payload.pets)
	end
end)

channels.economyEvent.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind == "snapshot" then
		drops.clear()
		if type(payload.drops) == "table" then
			drops.spawn(payload.drops)
		end
	elseif kind == "drops" and type(payload.drops) == "table" then
		drops.spawn(payload.drops)
	elseif kind == "clear" then
		drops.clear()
	elseif kind == "picked" and type(payload.ids) == "table" then
		drops.pick(payload.ids)
	elseif kind == "coins" and type(payload.positions) == "table" then
		coins.burst(payload.positions)
	end
	state.apply(payload)
	tips.onEvent(payload)
	forgeWindow.onEvent(payload)
	equipmentWindow.onEvent(payload)
end)

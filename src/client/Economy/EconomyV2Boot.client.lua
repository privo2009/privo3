--!strict
-- 새 경제 클라 진입점(지시서 #32). ⚠️ 플래그 ECONOMY_V2가 꺼져 있으면 첫 줄에서 끝난다 — 아무것도 만들지 않는다(지금 게임과 같다).
-- 켜져 있으면: 서버 EconomyEvent를 받아 → 상태(EconomyV2State) · 드롭 표시(DropRenderer) · 코인 이펙트(CoinFx) · HUD(EconomyHud).
-- 대장간 알림 · 안내 토스트는 OverlayBoot가 같은 채널을 듣고 띄운다(토스트 칸이 그쪽에 있다).
-- #33: 대장간 창(ForgeWindow — ScreenController "Forge") · 로비 임시 대장간(ForgeSite — 근접 프롬프트) · HUD 대장간 버튼.
--      대장간이 열리기 전에는 셋 다 안 보인다(창을 여는 길이 없다). 요청은 ForgeRequest, 결과는 EconomyEvent forge_* kind.
-- 판정은 전부 서버다 — 여기는 받은 것을 그린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not require(ReplicatedStorage.Shared.EconomyV2Logic).isOn() then
	return
end

local Players = game:GetService("Players")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyV2State = require(script.Parent.EconomyV2State)
local DropRenderer = require(script.Parent.DropRenderer)
local CoinFx = require(script.Parent.CoinFx)
local EconomyHud = require(script.Parent.Parent.UI.Screens.Hud.EconomyHud)
local ForgeWindow = require(script.Parent.Parent.UI.Screens.Window.ForgeWindow)
local ForgeSite = require(script.Parent.ForgeSite)
local ScreenController = require(script.Parent.Parent.UI.ScreenController)

local gui = Instance.new("ScreenGui")
gui.Name = "EconomyV2Gui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- 코인 이펙트가 카메라 뷰포트 좌표를 그대로 쓴다(HudGui와 같은 설정)
gui.DisplayOrder = 1
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local state = EconomyV2State.new()
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
})
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
state.subscribe(function(values)
	site.setOpen(values.forgeOpen)
	forgeWindow.set(values)
end)
channels.forgeRequest:FireServer({ action = "sync" })

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
	forgeWindow.onEvent(payload)
end)

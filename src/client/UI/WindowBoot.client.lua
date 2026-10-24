--!strict
-- Window 층 화면(환생 창 · 월드·워프 창)을 ScreenController에 등록하고 서버 채널에 배선한다
-- (Phase 6 지시서 #5 · #6). MenuRail의 "환생" 칸이 "Rebirth", "워프" 칸이 "Warp"로 open한다.
--
-- 요청은 RebirthRequest로 보내고(payload 비어 있음 — 결과값을 싣지 않는다), 결과는 RebirthResult로 받는다.
-- 바뀐 값(블럭스 · 배수)은 PlayerState → Store로 들어와 창이 스스로 다시 그린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScreenController = require(script.Parent.ScreenController)
local RebirthWindow = require(script.Parent.Screens.Window.RebirthWindow)

local channels = Remotes.getClient()

local rebirthWindow = RebirthWindow.create({
	sendRequest = function()
		local payload: Remotes.RebirthRequestPayload = {}
		channels.rebirthRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Rebirth")
	end,
	-- 상점으로(지시서 #7). Window 층은 하나만 열린다 — open이 환생 창을 닫는다.
	openShop = function()
		ScreenController.open("Shop")
	end,
})

ScreenController.register("Rebirth", "Window", function()
	return rebirthWindow.root
end)

channels.rebirthResult.OnClientEvent:Connect(function(payload: Remotes.RebirthResultPayload)
	rebirthWindow.onResult(payload)
end)

-- ===== 월드·워프 창 (지시서 #6) =================================================================

local WarpWindow = require(script.Parent.Screens.Window.WarpWindow)
local StateSync = require(script.Parent.Parent.Net.StateSync)

local warpWindow = WarpWindow.create({
	sendRequest = function(stage: number)
		local payload: Remotes.WarpRequestPayload = { stage = stage }
		channels.warpRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Warp")
	end,
})

ScreenController.register("Warp", "Window", function()
	return warpWindow.root
end)

-- 열릴 때마다 지금 갈 수 있는 가장 높은 층을 다시 고른다.
-- ⚠️ 숨긴 채로 시작해야 한다. Visible=true로 만들어 두면 첫 open에서 값이 안 바뀌어 신호가 안 나고,
--    만들 때(Store가 아직 더미값일 때) 고른 층이 남는다(2026-10-22 Play: 블럭스 32인데 25층이 골라져 있었다).
warpWindow.root.Visible = false
warpWindow.root:GetPropertyChangedSignal("Visible"):Connect(function()
	if warpWindow.root.Visible then
		warpWindow.onOpen()
	end
end)

channels.warpResult.OnClientEvent:Connect(function(payload: Remotes.WarpResultPayload)
	warpWindow.onResult(payload)
end)

-- W1: 활성 런이 있으면 워프 버튼을 잠근다. 런 상태는 서버 RunStateChanged가 원본이다.
channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	warpWindow.setRunActive(payload.active)
end)

-- ===== 상점 창 — 업그레이드 (지시서 #7) ==========================================================
-- 요청은 UpgradeRequest{name}(레벨 · 비용을 싣지 않는다), 결과는 UpgradeResult. 바뀐 레벨 · 블럭스는 PlayerState → Store.

local UpgradeShopWindow = require(script.Parent.Screens.Window.UpgradeShopWindow)

local shopWindow = UpgradeShopWindow.create({
	sendRequest = function(name: string)
		local payload: Remotes.UpgradeRequestPayload = { name = name }
		channels.upgradeRequest:FireServer(payload)
	end,
	onClose = function()
		ScreenController.close("Shop")
	end,
})

ScreenController.register("Shop", "Window", function()
	return shopWindow.root
end)

channels.upgradeResult.OnClientEvent:Connect(function(payload: Remotes.UpgradeResultPayload)
	shopWindow.onResult(payload)
end)

-- ===== 타이틀(칭호) 창 (지시서 #10) ==============================================================
-- 요청은 TitleRequest{action, titleId?, on?}(결과 · 비용 · 확률을 싣지 않는다), 결과는 TitleResult.
-- 바뀐 블럭스 · 칭호 목록은 PlayerState → Store. 새 칭호 토스트는 OverlayBoot가 같은 TitleResult로 띄운다.
-- 아우라 창의 "칭호" 버튼이 "Title"로 연다(지시서 #11 — Window 단일 오픈이라 아우라 창이 닫힌다).

local TitleWindow = require(script.Parent.Screens.Window.TitleWindow)

local titleWindow = TitleWindow.create({
	sendRequest = function(payload)
		local p: Remotes.TitleRequestPayload = { action = payload.action, titleId = payload.titleId, on = payload.on }
		channels.titleRequest:FireServer(p)
	end,
	onClose = function()
		ScreenController.close("Title")
	end,
})

ScreenController.register("Title", "Window", function()
	return titleWindow.root
end)

channels.titleResult.OnClientEvent:Connect(function(payload: Remotes.TitleResultPayload)
	titleWindow.onResult(payload)
end)

-- ===== 아우라 창 (지시서 #11 A5) ================================================================
-- 요청은 AuraRequest{action, pack?, auraId?}, 결과는 AuraResult(요청한 사람에게 1건). 결과 모달 · 런 중 토스트는 OverlayBoot.
-- 메뉴 레일 넷째 칸 "아우라"가 "Aura"로 연다.

local AuraWindow = require(script.Parent.Screens.Window.AuraWindow)

local auraWindow = AuraWindow.create({
	sendRequest = function(payload)
		local p: Remotes.AuraRequestPayload = { action = payload.action, pack = payload.pack, auraId = payload.auraId }
		channels.auraRequest:FireServer(p)
	end,
	onClose = function()
		ScreenController.close("Aura")
	end,
	openTitles = function()
		ScreenController.open("Title")
	end,
})

ScreenController.register("Aura", "Window", function()
	return auraWindow.root
end)

channels.auraResult.OnClientEvent:Connect(function(payload: Remotes.AuraResultPayload)
	auraWindow.onResult(payload)
end)

-- ===== 설정 창 (지시서 #11 A8) ==================================================================
-- 요청은 SettingsRequest{key, value}(서버 화이트리스트), 결과는 SettingsResult. 메뉴 레일 "설정" 칸이 "Settings"로 연다.

local SettingsWindow = require(script.Parent.Screens.Window.SettingsWindow)

local settingsWindow = SettingsWindow.create({
	sendRequest = function(payload)
		local p: Remotes.SettingsRequestPayload = { key = payload.key, value = payload.value }
		channels.settingsRequest:FireServer(p)
	end,
	onClose = function()
		ScreenController.close("Settings")
	end,
})

ScreenController.register("Settings", "Window", function()
	return settingsWindow.root
end)

channels.settingsResult.OnClientEvent:Connect(function(payload: Remotes.SettingsResultPayload)
	settingsWindow.onResult(payload)
end)

-- ===== 펫 창 (지시서 #12) =======================================================================
-- 요청은 PetRequest{action, egg?, uid?}, 결과는 PetResult(요청한 사람에게 1건). 결과 모달 · 런 중 토스트는 OverlayBoot.
-- 메뉴 레일 다섯째 칸 "펫 목록"이 "Pet"으로 연다.

local PetWindow = require(script.Parent.Screens.Window.PetWindow)

local petWindow = PetWindow.create({
	sendRequest = function(payload)
		local p: Remotes.PetRequestPayload = { action = payload.action, egg = payload.egg, uid = payload.uid }
		channels.petRequest:FireServer(p)
	end,
	onClose = function()
		ScreenController.close("Pet")
	end,
})

ScreenController.register("Pet", "Window", function()
	return petWindow.root
end)
petWindow.root:GetPropertyChangedSignal("Visible"):Connect(function()
	if petWindow.root.Visible then
		petWindow.onOpen()
	end
end)

channels.petResult.OnClientEvent:Connect(function(payload: Remotes.PetResultPayload)
	petWindow.onResult(payload)
end)

StateSync.request()

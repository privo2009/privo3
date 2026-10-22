--!strict
-- Overlay 화면(로딩 · 오류 · 런 표시층 안내)을 ScreenController에 등록하고 배선한다 (U4, 지시서 #5).
-- HudBoot.client.lua와 같은 자리 — 화면 모듈은 ModuleScript라 누군가 require해서 살려야 한다.
--
--   로딩       시작하자마자 연다. 첫 PlayerState가 오면 닫는다. TIMEOUT_SEC를 넘기면 닫고 오류를 연다
--   런 안내    RunStateChanged를 RunNoticeLogic에 넣어 나온 대로 띄운다(비차단)
--   환생 안내  RebirthResult가 성공이면 "×이전 → ×이후"를 잠깐 띄운다(알림층, 지시서 #8)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScreenController = require(script.Parent.ScreenController)
local LoadingScreen = require(script.Parent.Screens.Overlay.LoadingScreen)
local ErrorNotice = require(script.Parent.Screens.Overlay.ErrorNotice)
local RunNotice = require(script.Parent.Screens.Overlay.RunNotice)
local RunNoticeLogic = require(script.Parent.Logic.RunNoticeLogic)
local RebirthNotice = require(script.Parent.Screens.Overlay.RebirthNotice)
local FeedbackLogic = require(script.Parent.Logic.FeedbackLogic)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local PlayerStateClient = require(script.Parent.Parent.Net.PlayerStateClient)
local StateSync = require(script.Parent.Parent.Net.StateSync)

local loading = LoadingScreen.create()
local errorNotice = ErrorNotice.create()
local runNotice = RunNotice.create()
local rebirthNotice = RebirthNotice.create()

ScreenController.register("Loading", "Overlay", function()
	return loading.root
end)
ScreenController.register("ErrorNotice", "Overlay", function()
	return errorNotice.root
end)
ScreenController.register("RunNotice", "Overlay", function()
	return runNotice.root
end)
ScreenController.register("RebirthNotice", "Overlay", function()
	return rebirthNotice.root
end)

-- ===== 로딩 ==================================================================================

local startedAt = os.clock()
local settled = false

local function settle(state: LoadingScreen.State)
	if settled or state == "loading" then
		return
	end
	settled = true
	ScreenController.close("Loading")
	if state == "timeout" then
		errorNotice.setText(ErrorNotice.LOADING_TIMEOUT_TEXT)
		ScreenController.open("ErrorNotice")
		warn(string.format("[OverlayBoot] %d초 안에 첫 상태를 받지 못했다 - 오류 표시", LoadingScreen.TIMEOUT_SEC))
	else
		print(string.format("[OverlayBoot] 첫 상태 수신 - 로딩 닫음 (%.2f초)", os.clock() - startedAt))
	end
end

ScreenController.open("Loading")
PlayerStateClient.onFirstState(function()
	settle(LoadingScreen.decide(true, os.clock() - startedAt))
end)
task.delay(LoadingScreen.TIMEOUT_SEC, function()
	settle(LoadingScreen.decide(PlayerStateClient.hasReceived(), os.clock() - startedAt))
end)

-- ===== 런 표시층 안내 =========================================================================

ScreenController.open("RunNotice") -- 화면은 열어 두고, 보일지는 RunNotice.show가 root.Visible로 정한다

local channels = Remotes.getClient()
channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	local kind = RunNoticeLogic.decide({
		active = payload.active,
		reason = payload.reason,
		cleared = payload.state.cleared,
		canAdvance = payload.state.canAdvance,
	})
	if kind ~= nil then
		runNotice.show(kind)
	end
end)

-- ===== 환생 안내 (지시서 #8) ====================================================================

ScreenController.open("RebirthNotice") -- 열어 두고, 보일지는 RebirthNotice.show가 root.Visible로 정한다
channels.rebirthResult.OnClientEvent:Connect(function(payload: Remotes.RebirthResultPayload)
	if type(payload) ~= "table" or not payload.ok or type(payload.total) ~= "table" or type(payload.gained) ~= "table" then
		return
	end
	rebirthNotice.show(FeedbackLogic.rebirthNotice(BigNum.new(payload.total.m, payload.total.e), BigNum.new(payload.gained.m, payload.gained.e)))
end)
StateSync.request()

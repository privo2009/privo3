--!strict
-- Overlay 화면(로딩 · 오류 · 런 표시층 안내)을 ScreenController에 등록하고 배선한다 (U4, 지시서 #5).
-- HudBoot.client.lua와 같은 자리 — 화면 모듈은 ModuleScript라 누군가 require해서 살려야 한다.
--
--   로딩       시작하자마자 연다. 첫 PlayerState가 오면 닫는다. TIMEOUT_SEC를 넘기면 닫고 오류를 연다
--   런 안내    RunStateChanged를 RunNoticeLogic에 넣어 나온 대로 띄운다(비차단)
--   환생 안내  RebirthResult가 성공이면 "×이전 → ×이후"를 잠깐 띄운다(알림층, 지시서 #8)
--   토스트     TitleResult가 새 칭호면 "새 칭호! 이름 (힘·블럭스 ×N)"(알림층, 최대 3개 · 큐, 지시서 #10)
--   결과 모달  AuraResult가 새 아우라이거나 epic 이상이면 차단층 큐(한 번에 하나). 런 중이면 모달 대신 토스트(지시서 #11 A6)
--              PetResult(부화)가 새 펫이거나 영웅 이상이면 같은 큐 · 같은 규칙(지시서 #12 E8)

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
local ToastStack = require(script.Parent.Screens.Overlay.ToastStack)
local TitleWindowLogic = require(script.Parent.Logic.TitleWindowLogic)
local toastStack = ToastStack.create()

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
ScreenController.register("ToastStack", "Overlay", function()
	return toastStack.root
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
-- 런 진행 중인가(클리어 대기 포함 — active가 true인 동안). 결과 모달 대신 토스트를 고르는 데 쓴다(A6).
local runActive = false
channels.runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	runActive = payload.active == true
end)

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
-- ===== 토스트 — 새 칭호 (지시서 #10 S15) ==========================================================
-- 수동 롤 응답(action "roll")과 자동 롤 알림(action "autoRoll") 둘 다 같은 채널로 온다. 중복은 서버가 보내지 않거나 isNew false다.

ScreenController.open("ToastStack") -- 열어 두고, 줄마다 Visible로 보인다
channels.titleResult.OnClientEvent:Connect(function(payload: Remotes.TitleResultPayload)
	if not TitleWindowLogic.shouldToast(payload) then
		return
	end
	local toast = TitleWindowLogic.toastFor(payload.titleId)
	if toast ~= nil then
		toastStack.push(toast)
	end
end)
-- ===== 차단층 큐 — 뽑기 결과 모달 (지시서 #11 A6) ===================================================
-- 큐는 범용이다(BlockingQueueLogic — 펫 · 일일 보상이 같은 큐를 쓴다). 한 번에 하나, "확인"으로 닫으면 다음이 올라온다.

local ResultModal = require(script.Parent.Screens.Overlay.ResultModal)
local BlockingQueueLogic = require(script.Parent.Logic.BlockingQueueLogic)
local AuraWindowLogic = require(script.Parent.Logic.AuraWindowLogic)
local PetWindowLogic = require(script.Parent.Logic.PetWindowLogic)

local resultModal = ResultModal.create()
ScreenController.register("ResultModal", "Overlay", function()
	return resultModal.root
end)
ScreenController.open("ResultModal") -- 열어 두고, 보일지는 show / hide가 정한다
local blockingQueue = BlockingQueueLogic.new() :: BlockingQueueLogic.Queue<ResultModal.View>

local function renderQueue()
	local v = blockingQueue.current()
	if v ~= nil then
		resultModal.show(v)
	else
		resultModal.hide()
	end
end
resultModal.onConfirm(function()
	blockingQueue.dismiss()
	renderQueue()
end)

channels.auraResult.OnClientEvent:Connect(function(payload: Remotes.AuraResultPayload)
	if not AuraWindowLogic.shouldModal(payload) then
		return -- 중복 하위 등급 · 거부는 창 안 상태 문구로만
	end
	if runActive then
		local toast = AuraWindowLogic.toastFor(payload)
		if toast ~= nil then
			toastStack.push(toast)
		end
		return
	end
	local view = AuraWindowLogic.resultView(payload)
	if view ~= nil and blockingQueue.push(BlockingQueueLogic.PRIORITY.rollResult, view) then
		renderQueue()
	end
end)

channels.petResult.OnClientEvent:Connect(function(payload: Remotes.PetResultPayload)
	if not PetWindowLogic.shouldModal(payload) then
		return -- 중복 하위 등급 · 크래프팅 · 장착 · 거부는 창 안 상태 문구로만
	end
	if runActive then
		local toast = PetWindowLogic.toastFor(payload)
		if toast ~= nil then
			toastStack.push(toast)
		end
		return
	end
	local view = PetWindowLogic.resultView(payload)
	if view ~= nil and blockingQueue.push(BlockingQueueLogic.PRIORITY.rollResult, view) then
		renderQueue()
	end
end)

-- 로벅스 구매 결과 토스트(지시서 #16): 거부 사유(ID 0 = "준비 중" · 이미 보유 · 제한 …) · 게임패스 구매 완료.
-- HUD 구좌 · 자동 클리커 잠김 · 상점 창 로벅스 탭이 같은 PurchaseClient로 보낸다 — 결과 문구는 RobuxShopLogic 하나.
local PurchaseClient = require(script.Parent.Parent.Net.PurchaseClient)
local RobuxShopLogic = require(script.Parent.Logic.RobuxShopLogic)
PurchaseClient.get().onResult(function(payload: Remotes.PurchaseResultPayload)
	local text = RobuxShopLogic.resultText(payload)
	if text ~= nil then
		toastStack.push({ text = text, tier = 1 })
	end
end)

-- 자동 진행 결과 토스트(지시서 #18): 켰다 · 껐다 · 서버가 껐다(character_lost) · HUD에서 보낸 중지의 거부.
-- 시작 거부는 설정 창 상태 줄이 보인다(창이 열려 있다) — 토스트로 겹쳐 띄우지 않는다.
local AutoAdvanceClient = require(script.Parent.Parent.Net.AutoAdvanceClient)
local AutoAdvanceWindowLogic = require(script.Parent.Logic.AutoAdvanceWindowLogic)
AutoAdvanceClient.get().onResult(function(payload: Remotes.AutoAdvanceResultPayload)
	if type(payload) ~= "table" or (payload.action == "start" and not payload.ok) then
		return
	end
	local text = AutoAdvanceWindowLogic.resultText(payload)
	if text ~= nil then
		toastStack.push({ text = text, tier = 1 })
	end
end)

StateSync.request()

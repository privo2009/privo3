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
--   일일 보상  받을 게 있고 · 첫 접속 안내가 끝났고 · 런 중이 아니면 세션마다 그 일 번호에 한 번 차단층 큐 3번(지시서 #20 D5).
--              HUD 일일 보상 아이콘(Navigation.openDaily)으로도 연다. 결과 모달과 같은 큐 — 한 번에 하나
--   안내 띠    첫 접속 안내(런 표시층 — 비차단, 지시서 #20 O1). 끝나면(다 마침) 토스트 "안내 끝!"

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

-- 일일 보상 창(지시서 #20 D5) — 같은 차단층 큐를 쓴다. 큐 칸은 { kind = "result", view } 또는 { kind = "daily" }
local DailyRewardWindow = require(script.Parent.Screens.Overlay.DailyRewardWindow)
local DailyRewardWindowLogic = require(script.Parent.Logic.DailyRewardWindowLogic)
local Store = require(script.Parent.Store)
local dailyWindow = DailyRewardWindow.create({
	sendClaim = function()
		local payload: Remotes.DailyRequestPayload = { action = "claim" }
		channels.dailyRequest:FireServer(payload)
	end,
})
ScreenController.register("DailyRewardWindow", "Overlay", function()
	return dailyWindow.root
end)
ScreenController.open("DailyRewardWindow") -- 열어 두고, 보일지는 show / hide가 정한다
channels.dailyResult.OnClientEvent:Connect(function(payload: Remotes.DailyResultPayload)
	dailyWindow.onResult(payload)
end)

type QueueItem = { kind: string, view: ResultModal.View? }
local blockingQueue = BlockingQueueLogic.new() :: BlockingQueueLogic.Queue<QueueItem>
local dailyQueued = false

local function renderQueue()
	local item = blockingQueue.current()
	if item ~= nil and item.kind == "result" and item.view ~= nil then
		dailyWindow.hide()
		resultModal.show(item.view)
	elseif item ~= nil and item.kind == "daily" then
		resultModal.hide()
		dailyWindow.show()
	else
		resultModal.hide()
		dailyWindow.hide()
	end
end
local function dismissQueue()
	local item = blockingQueue.current()
	if item ~= nil and item.kind == "daily" then
		dailyQueued = false
	end
	blockingQueue.dismiss()
	renderQueue()
end
resultModal.onConfirm(dismissQueue)
dailyWindow.onClose(dismissQueue)

local function pushDaily()
	if dailyQueued then
		return
	end
	dailyQueued = true
	if blockingQueue.push(BlockingQueueLogic.PRIORITY.dailyReward, { kind = "daily" }) then
		renderQueue()
	end
end
require(script.Parent.Navigation).onOpenDaily(pushDaily)

-- 자동 등장(D5): 세션마다 그 일 번호에 한 번. 안내가 끝나고 · 런이 끝나면 다시 판정한다
local shownDay: number? = nil
local function maybeAutoShowDaily()
	local daily = Store.get("daily")
	if DailyRewardWindowLogic.shouldAutoShow(daily, Store.get("onboarding"), runActive, shownDay) then
		shownDay = DailyRewardWindowLogic.read(daily).today
		print(string.format("[OverlayBoot] 일일 보상 자동 등장 — 오늘 UTC 일 %d · 칸 %d", shownDay :: number, DailyRewardWindowLogic.read(daily).day))
		pushDaily()
	end
end
-- 한 PlayerState의 setter가 다 끝난 뒤에 판정한다(task.defer — 키 하나만 바뀐 중간 상태를 읽지 않게)
Store.subscribe("daily", function()
	task.defer(maybeAutoShowDaily)
end)
Store.subscribe("onboarding", function()
	task.defer(maybeAutoShowDaily)
end)
channels.runStateChanged.OnClientEvent:Connect(function()
	task.defer(maybeAutoShowDaily) -- runActive가 위 연결에서 먼저 바뀐 뒤
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
	if view ~= nil and blockingQueue.push(BlockingQueueLogic.PRIORITY.rollResult, { kind = "result", view = view }) then
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
	if view ~= nil and blockingQueue.push(BlockingQueueLogic.PRIORITY.rollResult, { kind = "result", view = view }) then
		renderQueue()
	end
end)

-- ===== 첫 접속 안내 띠 (지시서 #20 O1 ~ O3) ======================================================
local OnboardingBand = require(script.Parent.Screens.Overlay.OnboardingBand)
local OnboardingLogic = require(script.Parent.Logic.OnboardingLogic)
local onboardingBand = OnboardingBand.create({
	send = function(action: string)
		local payload: Remotes.OnboardingRequestPayload = { action = action }
		channels.onboardingRequest:FireServer(payload)
	end,
})
ScreenController.register("OnboardingBand", "Overlay", function()
	return onboardingBand.root
end)
ScreenController.open("OnboardingBand") -- 열어 두고, 보일지는 안내 상태(PlayerState onboarding)가 정한다
-- 창이 열려 있으면 띠를 숨긴다(큰 창의 X 버튼 자리와 겹친다 — 창을 닫으면 다시 보인다)
ScreenController.onWindowChanged(function(anyOpen: boolean)
	onboardingBand.setSuppressed(anyOpen)
end)
channels.onboardingResult.OnClientEvent:Connect(function(payload: Remotes.OnboardingResultPayload)
	onboardingBand.onResult(payload)
	if type(payload) == "table" and payload.ok and payload.action == "finish" then
		toastStack.push({ text = OnboardingLogic.doneText(), tier = 1 })
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

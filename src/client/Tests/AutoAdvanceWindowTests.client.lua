--!strict
-- 자동 진행 설정 창 · HUD 버튼 · 상태 줄 검증 (지시서 #18 — docs/UI.md "지시서 #18").
--   창 표시 값 = 서버 요약 · 목표층 범위(1 ~ 상한) · 기본 = 안전층 · 버튼 색 · 글자 전환(안전층 경계) · 요청 한 번만 · 켜지면 창 닫힘 ·
--   HUD 세 상태(잠김 → 구매 요청 · 꺼짐 → 창 · 켜짐 → 중지) · 상태 줄 · 사유 문구 · 워프 · 환생 auto_active 문구 ·
--   새 문장 en · ko · 폰 틀(705×338) 넘침 0 · 11px(그 Play의 언어)
-- 실제 요청을 보내지 않는다 — 가짜 send.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
local UI = script.Parent.Parent.UI
local Store = require(UI.Store)
local TextMinimum = require(UI.TextMinimum)
local AutoAdvanceWindowLogic = require(UI.Logic.AutoAdvanceWindowLogic)
local WarpWindowLogic = require(UI.Logic.WarpWindowLogic)
local RebirthWindowLogic = require(UI.Logic.RebirthWindowLogic)
local AutoAdvanceWindow = require(UI.Screens.Window.AutoAdvanceWindow)
local AutoTools = require(UI.Screens.Hud.AutoTools)
local AutoAdvanceClient = require(script.Parent.Parent.Net.AutoAdvanceClient)

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

local L = AutoAdvanceWindowLogic
local MAX = AutoAdvanceLogic.maxTarget()

local function shop(owned: boolean): any
	return { gamepasses = if owned then { "autoAdvance" } else {}, paidRandomRestricted = false, boosts = {}, autoClick = false }
end
local function auto(active: boolean, target: number, safe: number, runs: number): any
	return { active = active, target = target, safeFloor = safe, runs = runs, maxTarget = MAX }
end

-- 1. 순수 로직 --------------------------------------------------------------------------------------------
do
	check("HUD 세 상태: 미보유 locked · 보유 꺼짐 off · 켜짐 on", L.hudState(auto(false, 0, 5, 0), shop(false)) == "locked"
		and L.hudState(auto(false, 0, 5, 0), shop(true)) == "off" and L.hudState(auto(true, 7, 5, 2), shop(true)) == "on")
	local v = L.view(auto(false, 0, 7, 0), nil)
	check("창: 안전층 = 서버 값 · 기본 목표 = 안전층", v.safeText == Locale.t("auto.safe", { n = 7 }) and v.target == 7
		and v.targetText == Locale.t("auto.targetValue", { n = 7 }))
	check("버튼: 목표 = 안전층 → 노랑 '시작 · 안전'", v.kind == "safe" and v.startColor == "yellow" and v.startText == Locale.t("auto.start.safe"))
	local r = L.view(auto(false, 0, 7, 0), 8)
	check("버튼: 안전층 + 1 → 보라 '시작 · 도박'(색과 글자 둘 다)", r.kind == "risky" and r.startColor == "purple"
		and r.startText == Locale.t("auto.start.risky") and r.startText ~= v.startText)
	check("목표층 범위: 1 아래 · 상한 위로 안 간다 · 양끝에서 −/+ 잠김", L.view(auto(false, 0, 7, 0), 0).target == 1
		and L.view(auto(false, 0, 7, 0), MAX + 5).target == MAX and not L.view(auto(false, 0, 7, 0), 1).canMinus
		and not L.view(auto(false, 0, 7, 0), MAX).canPlus and L.view(auto(false, 0, 7, 0), 5).canMinus)
	local none = L.view(auto(false, 0, 0, 0), nil)
	check("안전층 0: '아직 없어요' · 기본 목표 1 · 도박", none.safeText == Locale.t("auto.safeNone") and none.target == 1 and none.kind == "risky")
	check("상태 줄: 켜짐만 '자동 · 목표 N층 · M회'", L.statusText(auto(true, 9, 7, 3)) == Locale.t("auto.status", { target = 9, runs = 3 })
		and L.statusText(auto(false, 0, 7, 0)) == "")
	check("첫 PlayerState 전(이상한 값)도 안 죽는다", L.read(nil).maxTarget == MAX and L.read({ safeFloor = 0 / 0 }).safeFloor == 0)
	local generic = L.reasonText("???")
	local distinct = true
	for _, code in ipairs({ "run_active", "character_lost", "not_owned", "invalid_target", "no_character", "rate_limited", "auto_active" }) do
		if L.reasonText(code) == generic then
			distinct = false
		end
	end
	check("사유 문구: 코드마다 따로", distinct)
	check("결과 문구: 서버가 끔(character_lost) · 켬 · 끔", L.resultText({ action = "stopped", ok = true, reason = "character_lost" })
		== Locale.t("auto.reason.character_lost") and L.resultText({ action = "start", ok = true, reason = "" }) == Locale.t("auto.started")
		and L.resultText({ action = "stop", ok = true, reason = "" }) == Locale.t("auto.stopped"))
	check("워프 · 환생 창: auto_active = '자동 진행 중 — 끄고 다시'", WarpWindowLogic.reasonText("auto_active") == Locale.t("common.reason.auto_active")
		and RebirthWindowLogic.reasonText("auto_active") == Locale.t("common.reason.auto_active"))
	local keys = { "common.reason.auto_active", "auto.window.title", "auto.safe", "auto.safeNone", "auto.note.repeat", "auto.note.boost",
		"auto.target", "auto.targetValue", "auto.start.safe", "auto.start.risky", "auto.status", "auto.started", "auto.stopped",
		"auto.reason.run_active", "auto.reason.character_lost", "auto.reason.not_owned", "auto.reason.invalid_target" }
	local both = true
	for _, k in ipairs(keys) do
		local e = (Strings :: any).Entries[k]
		if e == nil or type(e.en) ~= "string" or type(e.ko) ~= "string" or e.en == "" or e.ko == "" then
			both = false
		end
	end
	check("새 문장 17키 en · ko 다 있다", both)
end

-- 2. 요청 한 번만 -------------------------------------------------------------------------------------------
do
	local sent = {}
	local c = AutoAdvanceClient.new({ send = function(p)
		table.insert(sent, p)
	end })
	c.start(5)
	c.start(5)
	c.stop()
	check("요청: 결과 전에는 한 번만(시작 · 중지 공용)", #sent == 1 and sent[1].action == "start" and sent[1].target == 5)
	c.handleResult({ action = "stopped", ok = true, reason = "character_lost", target = 5, safeFloor = 3 })
	c.stop()
	check("서버가 끈 알림은 대기를 풀지 않는다 · 응답이 오면 푼다", #sent == 1)
	c.handleResult({ action = "start", ok = true, reason = "", target = 5, safeFloor = 3 })
	c.stop()
	check("응답 뒤에는 다시 보낸다", #sent == 2 and sent[2].action == "stop")
end

-- 3. 설정 창 ----------------------------------------------------------------------------------------------
do
	local store = Store.new()
	store.setSource(function(setter)
		setter("shop", shop(true))
		setter("autoAdvance", auto(false, 0, 6, 0))
	end)
	local sent = {}
	local client = AutoAdvanceClient.new({ send = function(p)
		table.insert(sent, p)
	end })
	local closed = 0
	local w = AutoAdvanceWindow.create({ store = store, client = client, onClose = function()
		closed += 1
	end })
	task.wait()
	local d = w._debug
	check("창: 안전층 · 목표층 칸 = 서버 값 · 노랑만 보인다", d.safe.Text == Locale.t("auto.safe", { n = 6 })
		and d.value.Text == Locale.t("auto.targetValue", { n = 6 }) and d.startSafe.root.Visible and not d.startRisky.root.Visible)
	d.pressPlus()
	check("+ → 7층 · 보라만 보인다 · 글자 '도박'", d.view().target == 7 and d.startRisky.root.Visible and not d.startSafe.root.Visible
		and d.startRiskyLabel.Text == Locale.t("auto.start.risky"))
	d.pressMinus()
	check("− → 6층 · 다시 노랑", d.view().target == 6 and d.startSafe.root.Visible)
	d.pressStart()
	d.pressStart()
	check("시작: 고른 목표층으로 한 번만", #sent == 1 and sent[1].action == "start" and sent[1].target == 6)
	client.handleResult({ action = "start", ok = false, reason = "run_active", target = 0, safeFloor = 0 })
	task.wait()
	check("시작 거부 → 창 상태 줄에 사유 · 창은 열린 채", d.status.Text == Locale.t("auto.reason.run_active") and closed == 0)
	d.pressStart()
	client.handleResult({ action = "start", ok = true, reason = "", target = 6, safeFloor = 6 })
	task.wait()
	check("시작 ok → 창을 닫는다", closed == 1)
	w.onOpen()
	check("다시 열면 기본 목표 = 안전층으로 돌아간다", d.view().target == 6 and d.status.Text == "")
	w.root:Destroy()
end

-- 4. HUD 자동 진행 버튼 · 상태 줄 ---------------------------------------------------------------------------
do
	local store = Store.new()
	local purchases, opened, stopped = {}, 0, 0
	local tools = AutoTools.create({
		store = store,
		requestPurchase = function(k)
			table.insert(purchases, k)
		end,
		openAutoAdvance = function()
			opened += 1
		end,
		stopAutoAdvance = function()
			stopped += 1
		end,
	})
	local d = tools._debug
	d.pressAdvance()
	check("HUD 잠김(미보유): 누르면 autoAdvance 구매 요청 · 상태 줄 숨김", d.advanceState() == "locked" and purchases[1] == "autoAdvance"
		and not d.status.Visible)
	store.setSource(function(setter)
		setter("shop", shop(true))
		setter("autoAdvance", auto(false, 0, 5, 0))
	end)
	task.wait()
	d.pressAdvance()
	check("HUD 꺼짐(보유): 누르면 설정 창 · 테두리 검정", d.advanceState() == "off" and opened == 1 and d.advanceStroke.Color == Color3.new(0, 0, 0))
	store.setSource(function(setter)
		setter("autoAdvance", auto(true, 9, 5, 3))
	end)
	task.wait()
	d.pressAdvance()
	check("HUD 켜짐: 누르면 중지 · 테두리 노랑(두 채널) · 상태 줄 보인다", d.advanceState() == "on" and stopped == 1
		and d.advanceStroke.Color ~= Color3.new(0, 0, 0) and d.status.Visible and d.status.Text == Locale.t("auto.status", { target = 9, runs = 3 }))
	check("상태 줄: 자동 도구 위(바닥이 도구 윗변 위) · Scale만", d.status.AbsolutePosition.Y <= tools.root.AbsolutePosition.Y + 0.5
		and d.status.Size.Y.Offset == 0 and d.status.Position.Y.Offset == 0)
	tools.root:Destroy()
end

-- 5. 폰 틀 705×338 — 설정 창 · 상태 줄 넘침 0 · 11px(그 Play의 언어) --------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "AutoAdvancePhoneFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local function measure(root: Instance): (number, number, string)
		local minH, bad, badText = math.huge, 0, ""
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
					minH = math.min(minH, obj.AbsoluteSize.Y)
					if not obj.TextFits or obj.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
						bad += 1
						badText = obj.Name .. "(" .. obj.Text .. ")"
					end
				end
			end
		end
		return minH, bad, badText
	end

	local store = Store.new()
	store.setSource(function(setter)
		setter("shop", shop(true))
		setter("autoAdvance", auto(false, 0, 25, 0)) -- 두 자리 층
	end)
	local w = AutoAdvanceWindow.create({ store = store, client = AutoAdvanceClient.new({ send = function() end }), onClose = function() end })
	w.root.Parent = phone
	task.wait()
	task.wait()
	local h1, b1, t1 = measure(w.root)
	w._debug.pressMinus()
	task.wait()
	local h2, b2, t2 = measure(w.root) -- 안전 · 도박 글자 둘 다(24 < 25 → 안전, 위에서 25 = 안전)
	store.setSource(function(setter)
		setter("autoAdvance", auto(false, 0, 3, 0))
	end)
	w.onOpen()
	w._debug.pressPlus()
	task.wait()
	local h3, b3, t3 = measure(w.root) -- 도박
	check(string.format("폰: 설정 창(안전 · 도박) 넘침 0 · 최소 %.1fpx ≥ 11", math.min(h1, h2, h3)), b1 + b2 + b3 == 0
		and math.min(h1, h2, h3) >= TextScale.MIN_TEXT_PX - 0.5, t1 .. t2 .. t3)
	w.root:Destroy()

	local hudStore = Store.new()
	hudStore.setSource(function(setter)
		setter("shop", shop(true))
		setter("autoAdvance", auto(true, 25, 25, 999)) -- 가장 긴 꼴
	end)
	local tools = AutoTools.create({ store = hudStore })
	tools.root.Parent = phone
	task.wait()
	task.wait()
	local status = tools._debug.status
	check(string.format("폰: 상태 줄 '%s' 넘침 0 · %.1fpx ≥ 11", status.Text, status.AbsoluteSize.Y), status.TextFits
		and status.AbsoluteSize.Y >= TextScale.MIN_TEXT_PX - 0.5, string.format("%.0fx%.0f", status.AbsoluteSize.X, status.AbsoluteSize.Y))
	print(string.format("[AutoAdvanceWindowTests] 폰 705×338(%s): 창 최소 %.1fpx · 상태 줄 %.0fx%.0f fits=%s", Locale.current(),
		math.min(h1, h2, h3), status.AbsoluteSize.X, status.AbsoluteSize.Y, tostring(status.TextFits)))
	gui:Destroy()
end

print(string.format("[AutoAdvanceWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AutoAdvanceWindowTests] %d test(s) failed", failed))
end

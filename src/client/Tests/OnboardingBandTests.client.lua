--!strict
-- 첫 접속 안내 띠 · 3D 빛기둥 자리 검증 (지시서 #20 단계 7 — O1 ~ O3). 실제 요청을 보내지 않는다 — 가짜 send · Store.new().
--   단계 문구(서버 단계 그대로) · 끝나면 숨김 · 건너뛰기 두 번 누름 · 5단계 확인 한 번만 · 3D 대상 · 자리(중앙 금지 · 런 안내와 안 겹침) ·
--   새 문장 en · ko · 폰 틀(705×338) 넘침 0 · 11px
--   (#26) 토스트와 자리 나누기 — 띠가 보이는 동안 토스트는 띠 아래 칸 · 띠 보임 알림 · 폰 틀에서 띠와 겹침 0 · 긴 문구 넘침 0 · 11px

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local UI = script.Parent.Parent.UI
local Layout = require(UI.Layout)
local Store = require(UI.Store)
local TextMinimum = require(UI.TextMinimum)
local L = require(UI.Logic.OnboardingLogic)
local OnboardingBand = require(UI.Screens.Overlay.OnboardingBand)
local OverlayParts = require(UI.Screens.Overlay.OverlayParts)
local ChallengeInfo = require(UI.Screens.Hud.ChallengeInfo)

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

-- 1. 표시 값 · 3D 대상 ------------------------------------------------------------------------------------------
do
	local v1 = L.view({ step = 1, done = false }, false)
	check("1단계: 보인다 · 문구 onboarding.step.1 · '1/5단계' · 건너뛰기", v1.visible and v1.text == Locale.t("onboarding.step.1")
		and v1.progress == Locale.t("onboarding.progress", { n = 1, total = OnboardingConfig.STEP_COUNT }) and not v1.showFinish
		and v1.skipText == Locale.t("onboarding.skip"))
	local v5 = L.view({ step = 5, done = false }, false)
	check("5단계: 확인 버튼(알겠어요)", v5.showFinish and v5.finishText == Locale.t("onboarding.finish") and v5.text == Locale.t("onboarding.step.5"))
	check("끝남 · 요약 없음(첫 상태 전)은 숨김", not L.view({ step = 3, done = true }, false).visible and not L.view(nil, false).visible)
	check("건너뛰기 확인 대기 중이면 글자가 '한 번 더'", L.view({ step = 2, done = false }, true).skipText == Locale.t("onboarding.skipConfirm"))
	local gx, _, gz = ArenaConfig.getEntranceGateCenter()
	local t2 = L.target({ step = 2, done = false }, nil) :: Vector3
	local t4 = L.target({ step = 4, done = false }, 3) :: Vector3
	check("3D 대상: 1단계 없음 · 2 입장 게이트 · 3 런 층 블록 · 4 그 층 수령 발판 · 5 패드 · 끝나면 없음",
		L.target({ step = 1, done = false }) == nil and t2.X == gx and t2.Z == gz
			and (L.target({ step = 3, done = false }, 2) :: Vector3).X == ArenaConfig.getStageCenterX(2)
			and t4.X == ArenaConfig.getCashoutX(3) and t4.Z == ArenaConfig.CASHOUT_LATERAL_OFFSET
			and L.target({ step = 5, done = false }) ~= nil and L.target({ step = 2, done = true }) == nil)
end

-- 2. 띠 — 건너뛰기 두 번 · 확인 한 번만 ------------------------------------------------------------------------------
do
	local store = Store.new()
	store.setSource(function(setter)
		setter("onboarding", { step = 2, done = false })
	end)
	local clock = 100
	local b = OnboardingBand.create({ store = store, send = function() end, now = function()
		return clock
	end })
	check("띠: 단계 2 문구 · 보인다", b._debug.panel.Visible and b._debug.text.Text == Locale.t("onboarding.step.2"))
	b._debug.press()
	check("건너뛰기 한 번: 아직 안 보냄 · '한 번 더'", #b._debug.sent == 0 and b._debug.buttonLabel.Text == Locale.t("onboarding.skipConfirm"))
	clock += 1
	b._debug.press()
	check("두 번째(확인 시간 안) → skip 1건", #b._debug.sent == 1 and b._debug.sent[1] == "skip")
	clock += 1
	b._debug.press()
	check("대기 중 세 번째는 안 나간다", #b._debug.sent == 1)
	b.onResult({ action = "skip", ok = true, reason = "" })
	store.setSource(function(setter)
		setter("onboarding", { step = 2, done = true })
	end)
	check("끝나면(서버 done) 띠가 숨는다", not b._debug.panel.Visible)
	store.setSource(function(setter)
		setter("onboarding", { step = 3, done = false })
	end)
	b.setSuppressed(true)
	local hidden = not b._debug.panel.Visible
	b.setSuppressed(false)
	check("창이 열려 있으면 숨고(창 X 버튼을 가리지 않게) 닫히면 다시 보인다", hidden and b._debug.panel.Visible)
	b.root:Destroy()

	local s5 = Store.new()
	s5.setSource(function(setter)
		setter("onboarding", { step = 5, done = false })
	end)
	local b5 = OnboardingBand.create({ store = s5, send = function() end, now = function()
		return clock
	end })
	b5._debug.press()
	b5._debug.press()
	check("5단계: 확인은 한 번 누름으로 finish 1건 · 대기 중 두 번째는 안 나간다", #b5._debug.sent == 1 and b5._debug.sent[1] == "finish")
	clock += 100
	local s9 = Store.new()
	s9.setSource(function(setter)
		setter("onboarding", { step = 2, done = false })
	end)
	local b9 = OnboardingBand.create({ store = s9, send = function() end, now = function()
		return clock
	end })
	b9._debug.press()
	clock += L.SKIP_CONFIRM_SEC + 1
	b9._debug.press()
	check("건너뛰기 확인 시간이 지나면 처음부터(두 번째 누름은 다시 '한 번 더')", #b9._debug.sent == 0)
	b5.root:Destroy()
	b9.root:Destroy()
end

-- 3. 자리 — 중앙 금지 밖 · 챌린지 정보 · 런 안내와 안 겹침 ------------------------------------------------------------
do
	local x0, y0 = OnboardingBand.X0, OnboardingBand.TOP
	local x1, y1 = x0 + OnboardingBand.WIDTH, y0 + OnboardingBand.HEIGHT
	check("띠: 중앙 금지 구역 밖(상단 정보 띠 안) · 오른쪽 여백 3%", not Layout.overlapsCenterForbidden(x0, y0, x1, y1) and y1 <= Layout.TOP_HEIGHT
		and x1 <= 1 - Layout.EDGE_MARGIN + 1e-6)
	local info = ChallengeInfo.create()
	local _, _, cx1 = Layout.getBounds(info.root)
	check("띠: 챌린지 정보(상단 가운데) 오른쪽 · 런 안내(오른쪽 레일 y 0.15 아래)보다 위", x0 >= cx1 and y1 <= Layout.TOP_HEIGHT
		and OverlayParts.RIGHT_RAIL_LEFT >= x0)
	info.root:Destroy()
	local keys = {}
	for i = 1, OnboardingConfig.STEP_COUNT do
		table.insert(keys, "onboarding.step." .. i)
	end
	for _, k in ipairs({ "onboarding.progress", "onboarding.skip", "onboarding.skipConfirm", "onboarding.finish", "onboarding.done" }) do
		table.insert(keys, k)
	end
	local missing = {}
	for _, key in ipairs(keys) do
		local e = (Strings.Entries :: any)[key]
		if type(e) ~= "table" or type(e.en) ~= "string" or e.en == "" or type(e.ko) ~= "string" or e.ko == "" then
			table.insert(missing, key)
		end
	end
	check("새 문장(첫 접속 안내) en · ko 둘 다", #missing == 0, table.concat(missing, ", "))
end

-- 4. 폰 틀 705×338 — 단계 1 ~ 5 넘침 0 · 11px(그 Play의 언어) ---------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "OnboardingPhoneFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local store = Store.new()
	local b = OnboardingBand.create({ store = store, send = function() end })
	b.root.Parent = phone
	local worst, bad, badText = math.huge, 0, ""
	for step = 1, OnboardingConfig.STEP_COUNT do
		store.setSource(function(setter)
			setter("onboarding", { step = step, done = false })
		end)
		task.wait()
		task.wait()
		for _, obj in ipairs(b.root:GetDescendants()) do
			if obj:IsA("TextLabel") and obj.Text ~= "" then
				worst = math.min(worst, obj.AbsoluteSize.Y)
				if not obj.TextFits or obj.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
					bad += 1
					badText = obj.Name .. "(" .. obj.Text .. ")"
				end
			end
		end
	end
	check(string.format("폰: 안내 띠 1 ~ 5단계 넘침 0 · 최소 %.1fpx ≥ 11", worst), bad == 0 and worst >= TextScale.MIN_TEXT_PX - 0.5, badText)
	print(string.format("[OnboardingBandTests] 폰 705×338(%s): 띠 %.0fx%.0f · 최소 %.1fpx", Locale.current(), b.root.AbsoluteSize.X, b.root.AbsoluteSize.Y,
		worst))
	gui:Destroy()
end

-- 5. 토스트와 자리 나누기 (지시서 #26 — #20 "알려진 것": 안내 띠와 토스트가 같은 칸이라 안내 중 토스트가 띠를 덮었다) ----------------------
-- 띠가 보이는 동안 토스트는 띠 바로 아래 오른쪽 레일 칸(오류 칸과 같은 자리)으로 내려가 한 번에 1개 · 감싸기로 보인다.
do
	local ToastStack = require(UI.Screens.Overlay.ToastStack)
	local ErrorNotice = require(UI.Screens.Overlay.ErrorNotice)
	local RunNotice = require(UI.Screens.Overlay.RunNotice)

	-- 5a. 자리(Scale) — 띠와 안 겹침 · 중앙 금지 밖 · 런 안내 위 · 오른쪽 여백 안 · 오류 칸과 같은 사각형
	local tb = ToastStack.BelowBounds
	local bandY1 = OnboardingBand.TOP + OnboardingBand.HEIGHT
	check("자리 나누기: 띠 아래 칸은 띠 아래에서 시작한다(겹침 0)", tb.y0 >= bandY1, string.format("칸 y0=%.3f 띠 y1=%.3f", tb.y0, bandY1))
	check("자리 나누기: 띠 아래 칸은 중앙 금지 구역 밖 · 오른쪽 여백 안", not Layout.overlapsCenterForbidden(tb.x0, tb.y0, tb.x1, tb.y1)
		and tb.x1 <= 1 - Layout.EDGE_MARGIN + 1e-9)
	check("자리 나누기: 띠 아래 칸은 런 안내(오른쪽 레일) 위에서 끝난다", tb.y1 <= RunNotice.TOP + 1e-9, string.format("y1=%.3f 런 안내=%.3f", tb.y1, RunNotice.TOP))
	local eb = ErrorNotice.Bounds
	check("자리 나누기: 띠 아래 칸 = 오류 칸(같은 사각형 — 오류가 열려 있으면 내리지 않는다)", math.abs(tb.x0 - eb.x0) < 1e-9 and math.abs(tb.y0 - eb.y0) < 1e-9
		and math.abs(tb.x1 - eb.x1) < 1e-9 and math.abs(tb.y1 - eb.y1) < 1e-9)

	-- 5b. 띠 보임 알림 — 보일 때 true · 창이 열려 숨으면 false · 끝나면 false(값이 바뀔 때만)
	local store = Store.new()
	local seen: { boolean } = {}
	local band = OnboardingBand.create({
		store = store,
		send = function() end,
		onShown = function(on: boolean)
			table.insert(seen, on)
		end,
	})
	local initial = #seen
	store.setSource(function(setter)
		setter("onboarding", { step = 2, done = false })
	end)
	task.wait()
	local afterShow = #seen
	band.setSuppressed(true)
	band.setSuppressed(true)
	local afterSuppress = #seen
	band.setSuppressed(false)
	store.setSource(function(setter)
		setter("onboarding", { step = 5, done = true })
	end)
	task.wait()
	check("자리 나누기: 띠 보임 알림 — 더미(끝남)는 알림 없음 · 보이면 true 한 번", initial == 0 and afterShow == 1 and seen[1] == true,
		string.format("처음 %d · 보인 뒤 %d", initial, afterShow))
	check("자리 나누기: 창이 열려 숨으면 false 한 번(같은 값은 다시 알리지 않음) · 다시 보이면 true · 끝나면 false",
		afterSuppress == 2 and seen[2] == false and seen[3] == true and seen[4] == false and #seen == 4 and not band.isShown(), tostring(#seen))
	band.root:Destroy()

	-- 5c. 토스트 쪽 — 내리면 칸이 바뀌고 1개만 보인다(나머지는 기다린다) · 되돌리면 원래 칸 · 3개
	local clock = 0
	local stack = ToastStack.create(function()
		return clock
	end)
	stack.setBelowBand(true)
	for i = 1, 3 do
		stack.push({ text = "t" .. i, tier = 1 })
	end
	local function visibleCount(): number
		local n = 0
		for _, row in ipairs(stack._rows) do
			if row.Visible then
				n += 1
			end
		end
		return n
	end
	check("자리 나누기: 내리면 칸 = 띠 아래 칸 · 1개만 보임 · 감싸기", stack._isBelowBand() and visibleCount() == ToastStack.BELOW_VISIBLE
		and math.abs(stack.root.Position.X.Scale - tb.x0) < 1e-6 and math.abs(stack.root.Position.Y.Scale - tb.y0) < 1e-6 and stack._rows[1].TextWrapped,
		string.format("보임 %d", visibleCount()))
	check("자리 나누기: 나머지 2개는 큐에서 기다린다(잃지 않는다)", stack._rows[1].Text == "t1 " and #stack._queue.visible() == 1 and stack._queue.waiting() == 2,
		stack._rows[1].Text .. " 기다림 " .. tostring(stack._queue.waiting()))
	stack.setBelowBand(false)
	check("자리 나누기: 띠가 사라지면 원래 칸 · 기다리던 것이 올라와 3개", not stack._isBelowBand() and visibleCount() == 3
		and math.abs(stack.root.Position.X.Scale - ToastStack.Bounds.x0) < 1e-6 and math.abs(stack.root.Position.Y.Scale - ToastStack.Bounds.y0) < 1e-6,
		string.format("보임 %d", visibleCount()))
	stack.root:Destroy()

	-- 5d. 폰 틀 705×338(그 Play의 언어) — 띠(1단계) + 띠 아래 토스트: 겹침 0 · 가장 긴 토스트 문구들이 넘침 0 · 11px
	local Config = ReplicatedStorage.Shared.Config
	local TitleConfig = require(Config.TitleConfig)
	local AuraConfig = require(Config.AuraConfig)
	local PetConfig = require(Config.PetConfig)
	local ShopConfig = require(Config.ShopConfig)
	local Names = require(ReplicatedStorage.Shared.Localization.Names)
	local TitleWindowLogic = require(UI.Logic.TitleWindowLogic)
	local AuraWindowLogic = require(UI.Logic.AuraWindowLogic)
	local PetWindowLogic = require(UI.Logic.PetWindowLogic)
	local RobuxShopLogic = require(UI.Logic.RobuxShopLogic)
	local AutoAdvanceWindowLogic = require(UI.Logic.AutoAdvanceWindowLogic)
	local function longest(list: { any }, nameOf: (any) -> string): any
		local best, bestLen = nil, -1
		for _, v in ipairs(list) do
			local len = utf8.len(nameOf(v)) or 0
			if len > bestLen then
				best, bestLen = v, len
			end
		end
		return best
	end
	local texts: { string } = {}
	local function add(entry: any)
		if type(entry) == "table" and type(entry.text) == "string" then
			table.insert(texts, entry.text)
		elseif type(entry) == "string" then
			table.insert(texts, entry)
		end
	end
	local longTitle = longest(TitleConfig.Titles, function(def)
		return Names.title(def.id)
	end)
	add(TitleWindowLogic.toastFor(longTitle.id))
	local allAuras = {}
	for _, pack in pairs(AuraConfig.Packs) do
		for _, def in ipairs(pack.auras) do
			table.insert(allAuras, def)
		end
	end
	local longAura = longest(allAuras, function(def)
		return Names.aura(def.id)
	end)
	local _a, packId, tier = AuraConfig.get(longAura.id)
	add(AuraWindowLogic.toastFor({ action = "roll", ok = true, auraId = longAura.id, packId = packId, tier = tier, isNew = true, equipped = false }))
	local allPets = {}
	for _, egg in pairs(PetConfig.Eggs) do
		for _, def in ipairs(egg.pets) do
			table.insert(allPets, def)
		end
	end
	local longPet = longest(allPets, function(def)
		return Names.pet(def.id)
	end)
	add(PetWindowLogic.toastFor({ action = "hatch", ok = true, petId = longPet.id, level = 1, isNew = true, equipped = false }))
	local productKeys = {}
	for key in pairs(ShopConfig.Products) do
		table.insert(productKeys, key)
	end
	table.sort(productKeys)
	local longKey = longest(productKeys, function(key)
		return Names.product(key)
	end)
	add(RobuxShopLogic.resultText({ phase = "finished", ok = true, key = longKey }))
	for _, code in ipairs({ "not_registered", "already_owned", ShopConfig.REASON_LADDER_OWNED_HIGHER, ShopConfig.REASON_AUTO_OWNED_HIGHER, "restricted",
		"rate_limited" }) do
		add(RobuxShopLogic.reasonText(code))
	end
	add(AutoAdvanceWindowLogic.resultText({ action = "start", ok = true }))
	for _, code in ipairs({ "run_active", "character_lost", "not_owned", "invalid_target", "no_character", "stopped", "auto_active" }) do
		add(AutoAdvanceWindowLogic.reasonText(code))
	end
	add(L.doneText())

	local gui = Instance.new("ScreenGui")
	gui.Name = "OnboardingToastSplit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local phoneStore = Store.new()
	local phoneStack = ToastStack.create()
	phoneStack.root.Parent = phone
	phoneStack.root.Visible = true
	local phoneBand = OnboardingBand.create({ store = phoneStore, send = function() end, onShown = phoneStack.setBelowBand })
	phoneBand.root.Parent = phone
	phoneStore.setSource(function(setter)
		setter("onboarding", { step = 1, done = false })
	end)
	task.wait()
	local bad, worst, overlap = {}, math.huge, 0
	for _, text in ipairs(texts) do
		phoneStack.push({ text = text, tier = 1 })
		task.wait()
		task.wait()
		local row = phoneStack._rows[1]
		worst = math.min(worst, row.AbsoluteSize.Y)
		if not row.Visible or row.Text ~= text .. " " or not row.TextFits or row.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
			table.insert(bad, string.format("[%dx%d fits=%s] %s", row.AbsoluteSize.X, row.AbsoluteSize.Y, tostring(row.TextFits), text))
		end
		local panel = phoneBand._debug.panel
		local px0, py0 = panel.AbsolutePosition.X, panel.AbsolutePosition.Y
		local px1, py1 = px0 + panel.AbsoluteSize.X, py0 + panel.AbsoluteSize.Y
		local rx0, ry0 = row.AbsolutePosition.X, row.AbsolutePosition.Y
		local rx1, ry1 = rx0 + row.AbsoluteSize.X, ry0 + row.AbsoluteSize.Y
		if math.min(px1, rx1) - math.max(px0, rx0) >= 1 and math.min(py1, ry1) - math.max(py0, ry0) >= 1 then
			overlap += 1
		end
		phoneStack._queue.tick(math.huge) -- 다음 문구를 바로 올린다(시간을 기다리지 않는다)
		phoneStack._render()
	end
	check(string.format("폰(%s): 안내 띠가 보이는 동안 토스트가 띠와 겹치지 않는다(문구 %d개)", Locale.current(), #texts),
		phoneBand.isShown() and phoneStack._isBelowBand() and overlap == 0, string.format("겹침 %d", overlap))
	check(string.format("폰(%s): 띠 아래 토스트 — 가장 긴 칭호 · 아우라 · 펫 · 구매 · 자동 진행 · 안내 끝 문구 넘침 0 · 최소 %.1fpx ≥ 11", Locale.current(), worst),
		#texts >= 18 and #bad == 0, table.concat(bad, " | "))
	print(string.format("[OnboardingBandTests] 폰 705×338(%s): 띠 아래 토스트 %.0fx%.0f · 문구 %d개 · 최소 %.1fpx", Locale.current(),
		phoneStack._rows[1].AbsoluteSize.X, phoneStack._rows[1].AbsoluteSize.Y, #texts, worst))
	gui:Destroy()
end

print(string.format("[OnboardingBandTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[OnboardingBandTests] %d test(s) failed", failed))
end

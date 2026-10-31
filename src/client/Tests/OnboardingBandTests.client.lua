--!strict
-- 첫 접속 안내 띠 · 3D 빛기둥 자리 검증 (지시서 #20 단계 7 — O1 ~ O3). 실제 요청을 보내지 않는다 — 가짜 send · Store.new().
--   단계 문구(서버 단계 그대로) · 끝나면 숨김 · 건너뛰기 두 번 누름 · 5단계 확인 한 번만 · 3D 대상 · 자리(중앙 금지 · 런 안내와 안 겹침) ·
--   새 문장 en · ko · 폰 틀(705×338) 넘침 0 · 11px

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

print(string.format("[OnboardingBandTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[OnboardingBandTests] %d test(s) failed", failed))
end

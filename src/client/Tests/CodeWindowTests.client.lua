--!strict
-- 코드 입력 창 · 설정 창 "코드 입력" 버튼 검증 (지시서 #20 단계 7 — C4 · C6). 실제 요청을 보내지 않는다 — 가짜 send.
--   입력 글자를 결과에 쓰지 않는다 · 보내면 입력칸을 비운다 · 요청 한 번만 · 사유 문구 · PlaceholderText Strings ·
--   새 문장 en · ko · 폰 틀(705×338) 넘침 0 · 11px · 입력칸과 확인 버튼이 창 위쪽(키보드에 안 가린다)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UI = script.Parent.Parent.UI
local TextMinimum = require(UI.TextMinimum)
local CodeWindowLogic = require(UI.Logic.CodeWindowLogic)
local CodeWindow = require(UI.Screens.Window.CodeWindow)
local SettingsWindow = require(UI.Screens.Window.SettingsWindow)
local Store = require(UI.Store)

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

local SECRET = "MySecretTyping123"
local function potion(kind: string, count: number): any
	return { type = "potion", kind = kind, count = count, k = 0, petId = "" }
end

-- 1. 결과 문구 — 서버 결과와 Strings로만 ------------------------------------------------------------------------
do
	local ok = CodeWindowLogic.resultText({ ok = true, reason = "", rewards = { potion("strength", 2), potion("damage", 2) }, blox = BigNum.new(0, 0) })
	check("성공: '받았어요! 힘 포션 2개 · 데미지 포션 2개'(보상은 서버 결과에서)", ok == Locale.t("code.result.ok", {
		rewards = Names.boost("strength") .. " " .. Locale.t("daily.reward.count", { count = 2 }) .. CodeWindowLogic.SEPARATOR .. Names.boost("damage")
			.. " " .. Locale.t("daily.reward.count", { count = 2 }) }))
	check("사유: 없는 코드 · 이미 받음 · 만료 · 막힘 · 보관함 가득 · 빈도 · 모르는 것", CodeWindowLogic.resultText({ ok = false, reason = "not_found" })
		== Locale.t("code.reason.not_found") and CodeWindowLogic.resultText({ ok = false, reason = "already_redeemed" }) == Locale.t("code.reason.already_redeemed")
		and CodeWindowLogic.resultText({ ok = false, reason = "expired" }) == Locale.t("code.reason.expired")
		and CodeWindowLogic.resultText({ ok = false, reason = "too_many_attempts" }) == Locale.t("code.reason.too_many_attempts")
		and CodeWindowLogic.resultText({ ok = false, reason = "storage_full" }) == Locale.t("daily.reason.storage_full")
		and CodeWindowLogic.resultText({ ok = false, reason = "rate_limited" }) == Locale.t("common.reason.rate_limited")
		and CodeWindowLogic.resultText({ ok = false, reason = "boom" }) == Locale.t("code.reason.failed"))
	check("형태가 틀린 결과 → nil(문구를 만들지 않는다)", CodeWindowLogic.resultText(nil) == nil and CodeWindowLogic.resultText({ reason = "x" }) == nil)
end

-- 2. 창 — 입력 글자를 되보이지 않는다(C4) · 한 번만 · Enter ---------------------------------------------------------
do
	local sent: { string } = {}
	local clock = 10
	local closed = 0
	local w = CodeWindow.create({ send = function(code)
		table.insert(sent, code)
	end, onClose = function()
		closed += 1
	end, now = function()
		return clock
	end })
	check("입력칸: PlaceholderText = Strings · 처음엔 빈칸 · 포커스해도 안 지움(ClearTextOnFocus false) · 결과 줄도 빈칸(기본 'Label' 아님)",
		w._debug.box.PlaceholderText == Locale.t("code.placeholder") and w._debug.box.Text == "" and w._debug.box.ClearTextOnFocus == false
			and w._debug.result.Text == "")
	w._debug.box.Text = SECRET
	w._debug.submit()
	check("확인: 입력 글자 그대로 1건 보냄 · 입력칸을 바로 비움", #sent == 1 and sent[1] == SECRET and w._debug.box.Text == "")
	w._debug.box.Text = "again"
	w._debug.submit()
	check("대기 중 두 번째 확인은 안 나간다(요청 한 번만)", #sent == 1)
	w.onResult({ ok = false, reason = "not_found", rewards = {}, blox = BigNum.new(0, 0) })
	check("결과 문구에 입력 글자가 없다 · '없는 코드예요'", w._debug.result.Text == Locale.t("code.reason.not_found")
		and string.find(w._debug.result.Text, SECRET, 1, true) == nil)
	w.onResult({ ok = true, reason = "", rewards = { potion("strength", 2) }, blox = BigNum.new(0, 0) })
	check("성공 문구에도 입력 글자가 없다", string.find(w._debug.result.Text, SECRET, 1, true) == nil and w._debug.result.Text ~= "")
	w.reset()
	check("닫으면(reset) 결과 · 입력칸을 지운다", w._debug.result.Text == "" and w._debug.box.Text == "")
	w.root:Destroy()
end

-- 3. 설정 창 "코드 입력" 버튼 ----------------------------------------------------------------------------------
do
	local opened = 0
	local store = Store.new()
	local s = SettingsWindow.create({ store = store, sendRequest = function() end, onClose = function() end, openCode = function()
		opened += 1
	end })
	check("설정 창: '코드 입력' 버튼(Strings) · HitArea", s._debug.codeLabel.Text == Locale.t("settings.codeButton") and s._debug.codeHit:IsA("TextButton"))
	check("코드 입력 버튼: 토글 줄 아래 · Scale만", (s._debug.codeHit.Parent :: GuiObject).Position.Y.Scale > 0
		and (s._debug.codeHit.Parent :: GuiObject).Position.Y.Offset == 0)
	s.root:Destroy()
	local keys = { "settings.codeButton", "code.title", "code.placeholder", "code.submit", "code.result.ok", "code.reason.not_found",
		"code.reason.already_redeemed", "code.reason.expired", "code.reason.too_many_attempts", "code.reason.failed" }
	local missing = {}
	for _, key in ipairs(keys) do
		local e = (Strings.Entries :: any)[key]
		if type(e) ~= "table" or type(e.en) ~= "string" or e.en == "" or type(e.ko) ~= "string" or e.ko == "" then
			table.insert(missing, key)
		end
	end
	check("새 문장(코드 입력) en · ko 둘 다", #missing == 0, table.concat(missing, ", "))
end

-- 4. 폰 틀 705×338 — 넘침 0 · 11px · 입력칸과 확인이 화면 위쪽 반 안 ----------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "CodePhoneFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local w = CodeWindow.create({ send = function() end, onClose = function() end })
	w.root.Parent = phone
	w.onResult({ ok = false, reason = "too_many_attempts", rewards = {}, blox = BigNum.new(0, 0) }) -- 가장 긴 사유
	task.wait()
	task.wait()
	local minH, bad, badText = math.huge, 0, ""
	for _, obj in ipairs(w.root:GetDescendants()) do
		if (obj:IsA("TextLabel") or obj:IsA("TextBox")) and (obj :: any).Text ~= "" then
			minH = math.min(minH, (obj :: GuiObject).AbsoluteSize.Y)
			if not (obj :: any).TextFits or (obj :: GuiObject).AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
				bad += 1
				badText = obj.Name .. "(" .. (obj :: any).Text .. ")"
			end
		end
	end
	check(string.format("폰: 코드 창 넘침 0 · 최소 %.1fpx ≥ 11", minH), bad == 0 and minH >= TextScale.MIN_TEXT_PX - 0.5, badText)
	local box = w._debug.box
	local submitRoot = w._debug.submitHit.Parent :: GuiObject
	local boxBottom = box.AbsolutePosition.Y + box.AbsoluteSize.Y
	local submitBottom = submitRoot.AbsolutePosition.Y + submitRoot.AbsoluteSize.Y
	check(string.format("폰: 입력칸 · 확인 버튼 아랫변이 화면 위 45%% 안(키보드에 안 가린다) — %.0f · %.0f / 338", boxBottom, submitBottom),
		boxBottom <= 338 * 0.45 and submitBottom <= 338 * 0.45)
	print(string.format("[CodeWindowTests] 폰 705×338(%s): 최소 %.1fpx · 입력칸 아랫변 %.0fpx · 확인 아랫변 %.0fpx", Locale.current(), minH, boxBottom,
		submitBottom))
	gui:Destroy()
end

print(string.format("[CodeWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[CodeWindowTests] %d test(s) failed", failed))
end

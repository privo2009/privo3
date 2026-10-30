--!strict
-- 클라 언어 처리 검증 (지시서 #L2 K10 · K11).
--   K10  우리 코드가 만드는 GUI 루트(ScreenGui · BillboardGui · SurfaceGui)는 전부 AutoLocalize = false
--        — 번역은 Strings(Locale.t)가 한다. 로블록스 자동 번역이 그 위에 한 번 더 덮이지 않게 한다.
--        PlayerGui · Workspace 아래 LayerCollector를 전부 훑는다. 예외는 우리 코드 밖 두 가지뿐:
--        Studio 카메라 도구 Freecam(로블록스가 넣는다) · 플레이스 파일 StarterGui에 있는 것의 복사본(코드가 만든 것이 아니다)
--   K11  Studio에서 클라는 서버 언어 신호(LocaleReady)를 받은 뒤에 첫 언어를 고른다 — TEST_LOCALE이 계정 언어와 달라도
--        첫 화면부터 그 언어다. 고른 언어 = TEST_LOCALE(켰으면) 또는 계정 언어
-- 이 파일은 읽기만 한다(인스턴스 · 프로필을 바꾸지 않는다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- K10 ----------------------------------------------------------------------------------------------
do
	-- 화면이 다 세워질 때까지 기다린다(HUD 3층 · 3D 안내 라벨). 상한 15초.
	local deadline = os.clock() + 15
	while os.clock() < deadline do
		if playerGui:FindFirstChild("HudGui") ~= nil and playerGui:FindFirstChild("PadLabel_01") ~= nil then
			break
		end
		task.wait(0.2)
	end
	task.wait(0.5)

	local ours, outside, bad = 0, {}, {}
	local function scan(root: Instance)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("LayerCollector") then
				if d.Name == "Freecam" or StarterGui:FindFirstChild(d.Name) ~= nil then
					table.insert(outside, d.Name)
				else
					ours += 1
					if (d :: any).AutoLocalize ~= false then
						table.insert(bad, d:GetFullName())
					end
				end
			end
		end
	end
	scan(playerGui)
	scan(Workspace)
	check(string.format("K10: 우리 GUI 루트 %d개 전부 AutoLocalize = false", ours), ours > 0 and #bad == 0, table.concat(bad, ", "))
	check("K10: 화면 3층(HudGui · WindowGui · OverlayGui)이 검사 대상에 들어 있다",
		playerGui:FindFirstChild("HudGui") ~= nil and playerGui:FindFirstChild("WindowGui") ~= nil and playerGui:FindFirstChild("OverlayGui") ~= nil)
	print(string.format("[LocaleClientTests] K10 우리 코드 밖 GUI 루트(검사 제외): %s", if #outside > 0 then table.concat(outside, ", ") else "없음"))
end

-- 토스트 큐 동시 수 바꾸기 (ToastLogic.setLimit — #L2 폰 예외) -------------------------------------------------
do
	local ToastLogic = require(script.Parent.Parent.UI.Logic.ToastLogic)
	local q = ToastLogic.new()
	for i = 1, 3 do
		q.push("t" .. i, 0)
	end
	local changed = q.setLimit(2, 0)
	local v = q.visible()
	check("setLimit: 3 → 2면 나중 것이 큐 맨 앞으로(잃지 않는다)", changed and #v == 2 and v[1] == "t1" and v[2] == "t2" and q.waiting() == 1)
	q.push("t4", 0)
	check("setLimit: 돌려보낸 것이 새로 넣은 것보다 먼저", q.waiting() == 2)
	q.tick(ToastLogic.HOLD_SEC + 0.1)
	local after = q.visible()
	check("setLimit: 보이던 것이 지면 돌려보낸 것부터 올라온다", #after == 2 and after[1] == "t3" and after[2] == "t4")
	check("setLimit: 다시 3으로 늘리면 기다리던 것이 바로 올라온다(없으면 그대로)", q.setLimit(3, 0) == false and #q.visible() == 2)
end

-- K11 ----------------------------------------------------------------------------------------------
do
	local test = ReplicatedStorage:GetAttribute(Locale.TEST_LOCALE_ATTRIBUTE)
	local expected = if test ~= nil and Locale.isSupported(test) then test else Locale.fromLocaleId(player.LocaleId)
	check("K11: 지금 언어 = TEST_LOCALE(켰으면) 또는 계정 언어", Locale.current() == expected,
		string.format("current=%s expected=%s test=%s localeId=%s", Locale.current(), tostring(expected), tostring(test), player.LocaleId))
	local first, early = Locale._firstPick()
	if RunService:IsStudio() then
		check("K11: 처음 기억한 언어는 서버 신호를 받은 뒤에 골랐다(Studio)", first ~= nil and first.ready == true and first.code == expected,
			if first ~= nil then string.format("code=%s ready=%s", first.code, tostring(first.ready)) else "nil")
		check("K11: 신호 전에 기억 없이 고른 호출 0(기다릴 수 없는 자리에서 먼저 불린 적 없음)", early == 0, tostring(early))
	end
	print(string.format("[LocaleClientTests] K11 언어=%s (TEST_LOCALE=%s · 계정 %s)", Locale.current(), tostring(test), player.LocaleId))
end

-- 알림층 글자 맞춤 (#L2 단계 3) — 폰 크기(Galaxy A06 뷰포트 705×338) 틀 안에 실물 알림 화면을 그려 지금 언어로 잰다 -----------------
-- 런 안내(클리어 · 마지막 층 · 실패) · 로딩 · 로딩 시간 초과 오류 · 환생 안내 · 토스트(가장 긴 칭호) · 결과 모달(가장 긴 아우라 · 펫 이름).
-- 보이는 글자 칸마다 TextFits(하한 크기로 들어가는가) · 칸 높이 ≥ 11px. 알림 문장은 모듈이 처음 불릴 때 언어를 정한다 —
-- 그래서 이 절은 그 Play의 언어 하나만 잰다(계정 언어 Play = 영어, TEST_LOCALE "ko" Play = 한국어).
do
	local BigNum = require(ReplicatedStorage.Shared.BigNum)
	local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
	local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
	local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
	local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
	local Names = require(ReplicatedStorage.Shared.Localization.Names)
	local UI = script.Parent.Parent.UI
	local TextMinimum = require(UI.TextMinimum)
	local RunNotice = require(UI.Screens.Overlay.RunNotice)
	local ErrorNotice = require(UI.Screens.Overlay.ErrorNotice)
	local LoadingScreen = require(UI.Screens.Overlay.LoadingScreen)
	local RebirthNotice = require(UI.Screens.Overlay.RebirthNotice)
	local ToastStack = require(UI.Screens.Overlay.ToastStack)
	local ResultModal = require(UI.Screens.Overlay.ResultModal)
	local FeedbackLogic = require(UI.Logic.FeedbackLogic)
	local AuraWindowLogic = require(UI.Logic.AuraWindowLogic)
	local PetWindowLogic = require(UI.Logic.PetWindowLogic)
	local TitleWindowLogic = require(UI.Logic.TitleWindowLogic)

	local gui = Instance.new("ScreenGui")
	gui.Name = "LocaleOverlayFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Name = "Phone"
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset(화면 코드는 Scale만)
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = playerGui

	local function measure(root: Instance): (number, number, { string })
		local minH, n, bad = math.huge, 0, {}
		for _, o in ipairs(root:GetDescendants()) do
			if o:IsA("TextLabel") and o.Text ~= "" then
				local shown = true
				local node: Instance? = o
				while node ~= nil and node ~= gui do
					if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
						shown = false
						break
					end
					node = node.Parent
				end
				if shown then
					n += 1
					minH = math.min(minH, o.AbsoluteSize.Y)
					if not o.TextFits or o.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
						table.insert(bad, string.format("%s[%dx%d](%s)", o.Name, o.AbsoluteSize.X, o.AbsoluteSize.Y, o.Text))
					end
				end
			end
		end
		return minH, n, bad
	end
	local function longest(list: { any }, nameOf: (any) -> string): any
		local best, bestLen = nil, -1
		for _, def in ipairs(list) do
			local len = utf8.len(nameOf(def)) or 0
			if len > bestLen then
				best, bestLen = def, len
			end
		end
		return best
	end
	local function settle()
		task.wait()
		task.wait()
	end

	local results: { string } = {}
	local function judge(label: string, root: Instance)
		settle()
		local minH, n, bad = measure(root)
		check(string.format("알림 폰(%s): %s 글자 %d칸 넘침 0 · 최소 %.1fpx ≥ 11", Locale.current(), label, n, minH), n > 0 and #bad == 0, table.concat(bad, ", "))
		table.insert(results, string.format("%s %.1fpx", label, minH))
	end

	local run = RunNotice.create()
	run.root.Parent = phone
	for _, kind in ipairs({ "clear", "clearFinal", "fail" }) do
		run.show(kind :: any)
		judge("run." .. kind, run.root)
	end
	local err = ErrorNotice.create()
	err.root.Parent = phone
	err.setText(ErrorNotice.LOADING_TIMEOUT_TEXT)
	err.root.Visible = true
	judge("error.loadingTimeout", err.root)
	local loading = LoadingScreen.create()
	loading.root.Parent = phone
	loading.root.Visible = true
	judge("loading", loading.root)
	local notice = RebirthNotice.create()
	notice.root.Parent = phone
	notice.show(FeedbackLogic.rebirthNotice(BigNum.fromNumber(1234), BigNum.fromNumber(1200)))
	judge("rebirthNotice", notice.root)
	local longTitle = longest(TitleConfig.Titles, function(def)
		return Names.title(def.id)
	end)
	local function toastJudge(label: string, entry: any)
		local stack = ToastStack.create()
		stack.root.Parent = phone
		stack.root.Visible = true
		stack.push(entry)
		judge(label, stack.root)
		stack.root:Destroy()
	end
	toastJudge("toast.title(" .. Names.title(longTitle.id) .. ")", TitleWindowLogic.toastFor(longTitle.id))
	local modal = ResultModal.create()
	modal.root.Parent = phone
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
	local auraView = AuraWindowLogic.resultView({ action = "roll", ok = true, auraId = longAura.id, packId = packId, tier = tier, isNew = true, equipped = true })
	modal.show(auraView :: any)
	judge("modal.aura(" .. Names.aura(longAura.id) .. ")", modal.root)
	local auraPayload = { action = "roll", ok = true, auraId = longAura.id, packId = packId, tier = tier, isNew = true, equipped = false }
	toastJudge("toast.aura(" .. Names.aura(longAura.id) .. ")", AuraWindowLogic.toastFor(auraPayload))
	local allPets = {}
	for _, egg in pairs(PetConfig.Eggs) do
		for _, def in ipairs(egg.pets) do
			table.insert(allPets, def)
		end
	end
	local longPet = longest(allPets, function(def)
		return Names.pet(def.id)
	end)
	local petView = PetWindowLogic.resultView({ action = "hatch", ok = true, petId = longPet.id, level = 1, isNew = true, equipped = true })
	modal.show(petView :: any)
	judge("modal.pet(" .. Names.pet(longPet.id) .. ")", modal.root)
	local petPayload = { action = "hatch", ok = true, petId = longPet.id, level = 1, isNew = true, equipped = false }
	toastJudge("toast.pet(" .. Names.pet(longPet.id) .. ")", PetWindowLogic.toastFor(petPayload))

	-- 토스트 폰 예외(#L2 사람 결정): 낮은 화면에서는 동시 2개 · 두 줄. 3개를 넣으면 2개 보이고 1개는 기다린다(잃지 않는다)
	local stack = ToastStack.create()
	stack.root.Parent = phone
	stack.root.Visible = true
	settle()
	for i = 1, 3 do
		stack.push({ text = "t" .. i, tier = 1 })
	end
	local shownCount = 0
	for _, row in ipairs(stack._rows) do
		if row.Visible then
			shownCount += 1
		end
	end
	check("토스트 폰 예외: 338px 높이면 2개 · 두 줄(감싸기)", stack._isCompact() and shownCount == ToastStack.COMPACT_VISIBLE
		and stack._rows[1].TextWrapped and stack._queue.waiting() == 1, string.format("compact=%s shown=%d waiting=%d",
		tostring(stack._isCompact()), shownCount, stack._queue.waiting()))
	stack.root:Destroy()
	print(string.format("[LocaleClientTests] 알림 폰 705×338(%s): %s", Locale.current(), table.concat(results, " · ")))
	gui:Destroy()
end

-- 글꼴 하나 (#17 F1) — 우리 화면의 글자는 전부 UiTheme.FONT. 소스 쪽 검사(Enum.Font 직접 사용 금지)는 tools/check_fonts.py
-- (게임 스크립트는 다른 스크립트의 Source를 읽을 수 없어 Play 테스트로는 화면 쪽만 잰다)
do
	local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
	local wrong, n = {}, 0
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("LayerCollector") and gui.Name ~= "Freecam" and StarterGui:FindFirstChild(gui.Name) == nil then
			for _, o in ipairs(gui:GetDescendants()) do
				if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" then
					n += 1
					if (o :: any).Font ~= UiTheme.FONT then
						table.insert(wrong, gui.Name .. "." .. o.Name)
					end
				end
			end
		end
	end
	check(string.format("F1: 글자 %d칸 전부 UiTheme.FONT(%s)", n, UiTheme.FONT.Name), n > 0 and #wrong == 0, table.concat(wrong, ", "))
end

-- 힘 블록 환생 배수 라벨 (#17 F2) — 폰 틀(705×338)에서 한 줄 · 넘침 0 · 아래 값과 안 겹침(그 Play의 언어)
do
	local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
	local Store = require(script.Parent.Parent.UI.Store)
	local TextMinimum = require(script.Parent.Parent.UI.TextMinimum)
	local PowerBlock = require(script.Parent.Parent.UI.Screens.Hud.PowerBlock)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LocalePowerBlockFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = playerGui
	local block = PowerBlock.create(Store.new())
	block.root.Parent = phone
	task.wait()
	task.wait()
	local caption = block.root:FindFirstChild("Caption", true) :: TextLabel
	local value = block._debug.multiplierLabel
	local oneLine = caption.TextBounds.Y <= TextScale.MIN_TEXT_PX * 1.8
	check(string.format("F2: 폰 환생 배수 라벨 한 줄 · 넘침 0 · %.1fpx ≥ 11 (%s)", caption.AbsoluteSize.Y, caption.Text),
		caption.TextFits and oneLine and caption.AbsoluteSize.Y >= TextScale.MIN_TEXT_PX - 0.5,
		string.format("fits=%s bounds=%.0fx%.0f box=%.0fx%.0f", tostring(caption.TextFits), caption.TextBounds.X, caption.TextBounds.Y,
			caption.AbsoluteSize.X, caption.AbsoluteSize.Y))
	check("F2: 라벨 아래 끝이 값 위 끝을 넘지 않는다", caption.AbsolutePosition.Y + caption.AbsoluteSize.Y <= value.AbsolutePosition.Y + 0.5,
		string.format("caption bottom %.1f value top %.1f", caption.AbsolutePosition.Y + caption.AbsoluteSize.Y, value.AbsolutePosition.Y))
	local power = block.root:FindFirstChild("PowerValue", true) :: TextLabel
	check("F2: 배수 칸이 힘 수치 칸과 안 겹친다", caption.AbsolutePosition.X >= power.AbsolutePosition.X + power.AbsoluteSize.X - 0.5,
		string.format("caption left %.1f power right %.1f", caption.AbsolutePosition.X, power.AbsolutePosition.X + power.AbsoluteSize.X))
	check(string.format("F2: 폰 배수 값 칸 %.1fpx ≥ 11", value.AbsoluteSize.Y), value.AbsoluteSize.Y >= TextScale.MIN_TEXT_PX - 0.5)
	print(string.format("[LocaleClientTests] F2 폰 705×338(%s): 라벨 %.0fx%.0f 글자 %.0fx%.0f fits=%s", Locale.current(), caption.AbsoluteSize.X,
		caption.AbsoluteSize.Y, caption.TextBounds.X, caption.TextBounds.Y, tostring(caption.TextFits)))
	gui:Destroy()
end

print(string.format("[LocaleClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LocaleClientTests] %d test(s) failed", failed))
end

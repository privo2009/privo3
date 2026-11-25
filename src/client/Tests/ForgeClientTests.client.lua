--!strict
-- 대장간 클라 검증(지시서 #33). 모듈을 직접 만들어 굴린다.
--   창 로직(ForgeWindowLogic — 칸 넣기 · 빼기 · 가진 수 · 게이지 · 받을 토큰 · 자동 채우기 · 확률 줄 0% 금지 · 교환 줄 · ??? 잠김) ·
--   창(ForgeWindow — 게이지 칸 · 확률표 · 결과 연출 스킵 5초 · 자동 제작 목록 · 교환소 탭 · AutoLocalize false · UiTheme.FONT · 등급 색) ·
--   HUD 대장간 버튼(열렸을 때만) · 로비 임시 대장간(ForgeSite — 근접 프롬프트) · 플래그 꺼짐이면 아무것도 안 만든다

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local ProximityConfig = require(ReplicatedStorage.Shared.Config.ProximityConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Logic = require(script.Parent.Parent.UI.Logic.ForgeWindowLogic)
local ForgeWindow = require(script.Parent.Parent.UI.Screens.Window.ForgeWindow)
local EconomyHud = require(script.Parent.Parent.UI.Screens.Hud.EconomyHud)
local ForgeSite = require(script.Parent.Parent.Economy.ForgeSite)

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

local N = Config.CRAFT_INPUT

-- 1. 창 로직 ------------------------------------------------------------------------------------------
do
	local inv = L.newInv()
	inv[1], inv[10] = 2, 4
	local sel = Logic.newSelection()
	local a = Logic.add(sel, inv, 1) and Logic.add(sel, inv, 1)
	local b = Logic.add(sel, inv, 1)
	check("칸 넣기: 가진 수를 넘지 않는다", a and not b and #sel.ores == 2)
	Logic.add(sel, inv, 10)
	Logic.add(sel, inv, 10)
	Logic.add(sel, inv, 10)
	local c = Logic.add(sel, inv, 10)
	local points, slots = Logic.gauge(sel)
	check("칸 넣기: 5칸까지 · 게이지 = 정수 점수 ÷ 10 내림", not c and Logic.isFull(sel) and points == 32 and slots == 3)
	Logic.remove(sel, 1)
	local p2, s2 = Logic.gauge(sel)
	check("칸 빼기: 누른 칸이 빠지고 게이지가 다시 찬다", #sel.ores == 4 and p2 == 31 and s2 == 3 and not Logic.isFull(sel))
	local small = L.newInv()
	small[1], small[10] = 1, 2
	Logic.clamp(sel, small)
	check("인벤토리가 줄면 넘는 칸을 뺀다", #sel.ores == 3 and Logic.usedOf(sel, 10) == 2)
	check("받을 토큰: 0칸 없음 · 3칸 신화", Logic.tokensText(0) == Locale.t("forge.tokens.none")
		and string.find(Logic.tokensText(3), Locale.t("token.mythic"), 1, true) ~= nil)
	local fillInv = L.newInv()
	fillInv[2], fillInv[8] = 10, 5
	local f = Logic.fill(fillInv)
	check("자동 채우기: 공유 bestCombo와 같다", table.concat(f.ores, ",") == table.concat(L.bestCombo(fillInv) or {}, ","))
	local zeroOk, sumOk = true, true
	for s = 0, N do
		local sum = 0
		for _, line in ipairs(Logic.oddsLines(s)) do
			sum += line.pct
			zeroOk = zeroOk and (line.pct == 0) == (line.text == "0%")
		end
		sumOk = sumOk and math.abs(sum - 100) < 1e-9
	end
	check("확률 줄: 칸마다 합 100 · 0이 아닌 확률은 0%로 안 보인다", zeroOk and sumOk)
	local lines = Logic.exchangeLines("rare", { rare = 4 }, { pick_r1 = 2 })
	check("교환 줄: 등급 곡괭이 · 비용 · 보유 · 교환 가능", #lines == 4 and lines[1].cost == 3 and lines[1].owned == 2 and lines[1].can
		and lines[2].can and not lines[3].can)
	check("교환 줄: ???(next)는 빈 목록 · 잠긴 탭", #Logic.exchangeLines("next", { next = 9 }, {}) == 0 and Logic.isLockedTab("next")
		and not Logic.isLockedTab("rare"))
	check("크게 알리기: 신화 이상만", Logic.isBigNotice("mythic") and Logic.isBigNotice("legendary") and not Logic.isBigNotice("epic"))
end

-- 2. 창 -----------------------------------------------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	local sent = {}
	local now = 0
	local w = ForgeWindow.create({
		send = function(p)
			table.insert(sent, p)
		end,
		onClose = function() end,
		clock = function()
			return now
		end,
		autoStep = false,
	})
	w.root.Parent = gui
	local inv = L.newInv()
	inv[10] = 5
	w.set({ ores = inv, tokens = { rare = 4 }, owned = {}, autoOn = false, autoCount = 0, forgeOpen = true })
	local d = w._debug
	d.fill()
	local filled = 0
	for _, g in ipairs(d.gaugeCells) do
		if g.BackgroundColor3 == UiTheme.Colors.advance.base then
			filled += 1
		end
	end
	check("창: 자동 채우기 → 게이지 5칸 · 확률표 = 5칸", #d.sel().ores == N and filled == N
		and d.oddsTitle.Text == Locale.t("forge.odds.title", { slots = tostring(N) }) and not d.craftB.isDisabled())
	local oddsOk = true
	for i, line in ipairs(Logic.oddsLines(N)) do
		local row = d.oddsRows[i]
		oddsOk = oddsOk and row.pct.Text == line.text and row.name.TextColor3 == UiTheme.equipGradeColor(line.rarity)
	end
	check("창: 확률표 15줄 = 로직 · 이름 글자는 등급 색", oddsOk)
	local id = Config.PICKAXES[#Config.PICKAXES].id
	w.onEvent({ kind = "craft_result", ok = true, ids = { id }, isNew = { true }, slots = N, auto = false, ores = L.newInv() })
	local shown = d.overlay.Visible and not d.skip.Visible and d.resultNames[1].TextColor3 == UiTheme.equipGradeColor("legendary")
	w.step(Config.CRAFT_SKIP_SEC - 0.01)
	local before = d.skip.Visible
	w.step(Config.CRAFT_SKIP_SEC)
	local after = d.skip.Visible and d.overlay.Visible
	w.step(Config.CRAFT_ANIM_SEC)
	check("결과 연출: 등급 색 이름 · 스킵은 CRAFT_SKIP_SEC에 나타남 · 연출 길이가 지나면 닫힘", shown and not before and after and not d.overlay.Visible)
	check("결과 뒤: 인벤토리가 줄면 칸도 비운다", #d.sel().ores == 0)
	w.onEvent({ kind = "craft_result", ok = true, ids = { Config.START_PICKAXE }, isNew = { false }, slots = 0, auto = true, autoCount = 1, ores = L.newInv() })
	check("자동 제작 결과: 연출 없이 목록 맨 위에", not d.overlay.Visible and d.logRows[1].Text ~= "")
	d.setExTab("next")
	local lockedOk = d.locked.Visible and not d.exRows[1].root.Visible
	d.setExTab("rare")
	check("교환소: ??? 탭은 잠긴 칸 · 희귀 탭은 곡괭이 4줄(비용 · 교환 가능)", lockedOk and not d.locked.Visible and d.exRows[1].root.Visible
		and d.exRows[4].root.Visible and not d.exRows[1].b.isDisabled() and d.exRows[4].b.isDisabled())
	local autoOk, fontOk = true, true
	for _, obj in ipairs(w.root:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			if obj:IsA("TextLabel") then
				autoOk = autoOk and (obj.AutoLocalize == false or obj.Text == "")
			end
			fontOk = fontOk and ((obj :: any).Font == UiTheme.FONT or obj:IsA("TextButton"))
		end
	end
	check("창: 글자 AutoLocalize false · UiTheme.FONT", autoOk and fontOk)
	gui:Destroy()
end

-- 3. HUD 대장간 버튼 ---------------------------------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	local hud = EconomyHud.create(gui)
	hud.set({ coins = BigNum.new(0, 0), bagUsed = 0, bagCap = 20, forgeOpen = false })
	local closed = not hud.forgeRow.Visible
	hud.set({ coins = BigNum.new(0, 0), bagUsed = 0, bagCap = 20, forgeOpen = true, autoOn = true, autoCount = 3 })
	check("HUD: 대장간 버튼은 열렸을 때만 · 자동 제작 상태(횟수)", closed and hud.forgeRow.Visible
		and hud.autoStatus.Text == Locale.t("forge.auto.status", { count = "3" }))
	gui:Destroy()
end

-- 4. 로비 임시 대장간 -------------------------------------------------------------------------------------
do
	local folder = Instance.new("Folder")
	local opened = 0
	local site = ForgeSite.create({ parent = folder, onOpen = function()
		opened += 1
	end })
	site.setOpen(false)
	local none = site.model() == nil and #folder:GetChildren() == 0
	site.setOpen(true)
	local p = site.prompt()
	check("대장간: 닫혀 있으면 없음 · 열리면 임시 도형 + 근접 프롬프트(거리 = ProximityConfig)", none and site.model() ~= nil and p ~= nil
		and (p :: ProximityPrompt).MaxActivationDistance == ProximityConfig.FORGE_PROMPT_DISTANCE and not (p :: ProximityPrompt).AutoLocalize
		and (site.model() :: Model).PrimaryPart ~= nil and ((site.model() :: Model).PrimaryPart :: BasePart).Anchored)
	site.setOpen(true)
	check("대장간: 두 번 열어도 하나", #folder:GetChildren() == 1)
	site.destroy()
	check("대장간: 지우면 없음", #folder:GetChildren() == 0 and opened == 0)
	folder:Destroy()
end


print(string.format("[ForgeClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ForgeClientTests] %d test(s) failed", failed))
end

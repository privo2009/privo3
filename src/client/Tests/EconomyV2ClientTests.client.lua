--!strict
-- 새 경제 클라 표시 검증(지시서 #32). 모듈을 직접 만들어 굴린다.
--   상태(EconomyV2State — 서버 신호 kind별 반영) · 드롭 표시(DropRenderer — 풀링 · 물리 없음 · 줍기 날아감 · 층 이동 지움) ·
--   코인 이펙트(CoinFx — 한 번 상한 · 풀링 · Scale만) · HUD(EconomyHud — Strings 키 · AutoLocalize false · UiTheme.FONT · 자리)

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local EconomyV2State = require(script.Parent.Parent.Economy.EconomyV2State)
local DropRenderer = require(script.Parent.Parent.Economy.DropRenderer)
local CoinFx = require(script.Parent.Parent.Economy.CoinFx)
local EconomyHud = require(script.Parent.Parent.UI.Screens.Hud.EconomyHud)
local Layout = require(script.Parent.Parent.UI.Layout)

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

-- 1. 상태 --------------------------------------------------------------------------------------------
do
	local s = EconomyV2State.new()
	local seen = 0
	s.subscribe(function()
		seen += 1
	end)
	s.apply({ kind = "snapshot", bag = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, used = 1, cap = 20, coins = { m = 3, e = 2 }, ores = { 5, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
		forgeOpen = false, drops = {} })
	local v = s.get()
	check("상태: 시작값(가방 · 코인 · 인벤토리 · 대장간)", v.bagUsed == 1 and v.bagCap == 20 and BigNum.eq(v.coins, BigNum.new(3, 2)) and v.ores[1] == 5
		and not v.forgeOpen and seen == 1)
	s.apply({ kind = "coins", amount = { m = 1, e = 0 }, total = { m = 3.01, e = 2 }, positions = {} })
	s.apply({ kind = "picked", ids = { 1 }, bag = { 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, used = 2, cap = 20 })
	s.apply({ kind = "forge_open", stage = 8 })
	v = s.get()
	check("상태: 코인 합계 · 가방 · 대장간 열림 반영", BigNum.eq(v.coins, BigNum.new(3.01, 2)) and v.bagUsed == 2 and v.forgeOpen and seen == 4)
	check("상태: 모르는 꼴은 무시", not s.apply(nil) and not s.apply({ kind = "drops", stage = 1, drops = {} }) and seen == 4)
end

-- 2. 드롭 표시 ----------------------------------------------------------------------------------------
do
	local folder = Instance.new("Folder")
	local now = 0
	local target = Vector3.new(0, 10, 0)
	local r = DropRenderer.create({ parent = folder, autoStep = false, clock = function()
		return now
	end, getTarget = function()
		return target
	end })
	local list = {}
	for i = 1, 5 do
		table.insert(list, { id = i, ore = i, position = Vector3.new(i, 0, 0) })
	end
	r.spawn(list)
	local part = r.partOf(3) :: BasePart
	check("드롭: 그린다 · 광석 재질 색 · 물리 없음(Anchored · CanCollide false)", r.activeCount() == 5 and part ~= nil and part.Color == Config.ORE_VISUALS[3].color
		and part.Anchored and not part.CanCollide and part.Parent == folder)
	r.spawn({ list[1] })
	check("드롭: 같은 id 두 번은 무시", r.activeCount() == 5)
	r.step(1)
	check("드롭: 바닥 위에 떠 있다", part.Position.Y > 0)
	r.pick({ 1, 2 })
	r.step(now + DropRenderer.FLY_SEC / 2)
	local midFlying = r.activeCount() == 3 and r.poolSize() == 0
	now = 10
	r.step(now)
	check("줍기: 날아가며 사라진 뒤 풀로 돌아간다", midFlying and r.poolSize() == 2)
	r.clear()
	check("층 이동: 전부 지우고 풀로", r.activeCount() == 0 and r.poolSize() == 5)
	r.spawn(list)
	check("풀링: 다시 그려도 새 Part를 만들지 않는다", r.poolSize() == 0 and #folder:GetChildren() == 5)
	r.destroy()
	folder:Destroy()
end

-- 3. 코인 이펙트 ---------------------------------------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	local now = 0
	local fx = CoinFx.create({ parent = gui, autoStep = false, clock = function()
		return now
	end, toScreen = function(p: Vector3)
		return Vector2.new(p.X, p.Y)
	end, target = function()
		return Vector2.new(0, 0)
	end })
	local many = {}
	for i = 1, CoinFx.MAX_PER_BURST + 4 do
		table.insert(many, Vector3.new(i, i, 0))
	end
	local n = fx.burst(many)
	local scaleOnly = true
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("GuiObject") then
			scaleOnly = scaleOnly and c.Position.X.Offset == 0 and c.Size.X.Offset == 0 and c.Size.Y.Offset == 0
		end
	end
	check("코인: 한 번에 상한까지만 · Scale만(Offset 0)", n == CoinFx.MAX_PER_BURST and fx.flying() == n and scaleOnly)
	now = 10
	fx.step(now)
	check("코인: 다 날아가면 풀로 돌아간다", fx.flying() == 0 and fx.poolSize() == n)
	fx.destroy()
	gui:Destroy()
end

-- 4. HUD -----------------------------------------------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	local hud = EconomyHud.create(gui)
	hud.set({ coins = BigNum.new(1.5, 4), bagUsed = 3, bagCap = 20 })
	check("HUD: 코인 = Formatter · 가방 = Strings 키(지금 / 최대)", hud.coinValue.Text == Formatter.format(BigNum.new(1.5, 4))
		and hud.bagValue.Text == Locale.t("econ.bag.value", { used = "3", cap = "20" }) and hud.bagName.Text == Locale.t("econ.bag.label"))
	check("HUD: AutoLocalize false · UiTheme.FONT", not hud.bagValue.AutoLocalize and not hud.bagName.AutoLocalize and not hud.coinValue.AutoLocalize
		and hud.bagValue.Font == UiTheme.FONT and hud.coinValue.Font == UiTheme.FONT)
	hud.set({ coins = BigNum.new(0, 0), bagUsed = 20, bagCap = 20 })
	check("HUD: 가득 차면 경고색(위험)", hud.bagValue.TextColor3 == UiTheme.Colors.danger.light)
	local x0, y0, x1, y1 = Layout.getBounds(hud.root)
	check("HUD: 자리 — 좌측 레일 오른쪽 상단 띠 · 중앙 금지 구역 밖 · ChallengeInfo(0.35~) 왼쪽", x0 >= Layout.RAIL_WIDTH and x1 <= 0.35
		and y1 <= Layout.TOP_HEIGHT and not Layout.overlapsCenterForbidden(x0, y0, x1, y1))
	local keysOk = true
	for _, key in ipairs({ "econ.coins.label", "econ.bag.label", "econ.bag.value", "econ.forge.open", "econ.forge.hint" }) do
		keysOk = keysOk and Locale.template("en", key) ~= nil and Locale.template("ko", key) ~= nil -- 원문만 본다(자리 표시 WARN 없이 — #38)
	end
	check("문구: 새 키 5개 en · ko", keysOk)
	gui:Destroy()
end

print(string.format("[EconomyV2ClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EconomyV2ClientTests] %d test(s) failed", failed))
end

--!strict
-- UI 효과 2종 검증 (지시서 #21 — docs/UI.md "UI 효과"). 수치는 Shared/Config/UIFxConfig에서 읽는다(여기 다시 적지 않는다).
--   버튼 반응: 상태 전이 · 목표 Scale · 트윈 종류 · 잘림 상한 · 실물(가운데 기준 · 쉬면 원래 배치 · 비활성 · 격자 · 목록 · 다른 UIScale · 파괴 정리 ·
--             공용 진입점 · 직접 만든 HitArea 연결)
--   빛 띠: 키포인트 · Offset 진행 · 가시성 · 한 화면 상한 · 색 · 실물(덮개 ZIndex · 글씨 색 그대로 · 그라디언트 값 · 숨으면 멈춤 ·
--         상한 · 그림 덮개 · 둥근 모서리 · 떼기 · 파괴 정리 · HUD 구좌 · 상점 줄 연결)
-- 실제 요청을 보내지 않는다. 가짜 GUI는 끝나면 지운다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
local checkClose = TestHelpers.checkClose
local UI = script.Parent.Parent.UI
local ButtonFxLogic = require(UI.Logic.ButtonFxLogic)
local ShineLogic = require(UI.Logic.ShineLogic)
local ButtonFx = require(UI.Components.ButtonFx)
local Shine = require(UI.Components.Shine)
local Button = require(UI.Components.Button)
local WindowParts = require(UI.Components.WindowParts)
local RobuxList = require(UI.Components.RobuxList)
local Store = require(UI.Store)
local ShopSlots = require(UI.Screens.Hud.ShopSlots)
local MenuRail = require(UI.Screens.Hud.MenuRail)
local AutoTools = require(UI.Screens.Hud.AutoTools)
local DailyIcon = require(UI.Screens.Hud.DailyIcon)
local BoostTimers = require(UI.Screens.Hud.BoostTimers)
local RobuxShopLogic = require(UI.Logic.RobuxShopLogic)

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

local L = ButtonFxLogic
local function ctx(inside: boolean, touch: boolean?, disabled: boolean?): ButtonFxLogic.Ctx
	return { inside = inside, touch = touch == true, disabled = disabled == true }
end

-- 1. 설정 ------------------------------------------------------------------------------------------------
check("UIFxConfig.validate · 켜짐(커밋 값 — UI_FX_ENABLED) · 스크린샷 멈춤 nil(커밋 값) · 프리미엄 = 금테 노랑(cashout.base) · 기본 = 흰색",
	UIFxConfig.validate() and UIFxConfig.ENABLED == true and UIFxConfig.DEBUG_FREEZE_OFFSET == nil and UIFxConfig.SHINE_COLOR_PREMIUM == UiTheme.Colors.cashout.base
	and UIFxConfig.SHINE_COLOR_DEFAULT == Color3.new(1, 1, 1))

-- 2. 버튼 상태 전이 · 목표 Scale ----------------------------------------------------------------------------------
check("전이: 기본 + 올림 → hover · hover + 나감 → 기본", L.transition("idle", "enter", ctx(true)) == "hover"
	and L.transition("hover", "leave", ctx(false)) == "idle")
check("전이: 누름 → pressed(기본 · hover 어디서든)", L.transition("idle", "down", ctx(true)) == "pressed"
	and L.transition("hover", "down", ctx(true)) == "pressed")
check("전이: 뗌 — 위에 있으면 hover · 아니면 기본", L.transition("pressed", "up", ctx(true)) == "hover"
	and L.transition("pressed", "up", ctx(false)) == "idle")
check("전이: 누른 채 밖으로 → 기본(1로 돌아간다)", L.transition("pressed", "leave", ctx(false)) == "idle")
check("전이: 터치는 올림이 없다 — 뗌은 언제나 기본 · 올림 사건 무시", L.transition("pressed", "up", ctx(true, true)) == "idle"
	and L.transition("idle", "enter", ctx(true, true)) == "idle")
check("전이: 비활성이면 어떤 사건이든 기본", L.transition("idle", "enter", ctx(true, false, true)) == "idle"
	and L.transition("hover", "down", ctx(true, false, true)) == "idle" and L.transition("pressed", "disable", ctx(true)) == "idle")
check("전이: 누르고 있을 때 올림 · 누르지 않았을 때 뗌은 그대로", L.transition("pressed", "enter", ctx(true)) == "pressed"
	and L.transition("hover", "up", ctx(true)) == "hover")
check("목표 Scale = 설정 값(기본 1 · 올림 HOVER · 누름 PRESS)", L.targetScale("idle") == 1 and L.targetScale("hover") == UIFxConfig.HOVER_SCALE
	and L.targetScale("pressed") == UIFxConfig.PRESS_SCALE)
do
	local h, p, r = L.tweenSpec("idle", "hover"), L.tweenSpec("hover", "pressed"), L.tweenSpec("pressed", "hover")
	check("트윈: 올림 Quad Out HOVER_TIME · 누름 Quad Out PRESS_TIME · 뗌 Back Out RELEASE_TIME", h.time == UIFxConfig.HOVER_TIME
		and h.style == Enum.EasingStyle.Quad and h.direction == Enum.EasingDirection.Out and p.time == UIFxConfig.PRESS_TIME
		and r.time == UIFxConfig.RELEASE_TIME and r.style == Enum.EasingStyle.Back)
	check("트윈: 잘리는 자리에서 뗌은 Back(넘침) 대신 Quad", L.tweenSpec("pressed", "hover", true).style == Enum.EasingStyle.Quad)
end
check("잘림 상한: 넉넉하면 올림 그대로 · 꽉 차면 1 · 이미 밖이면 1 · 누름은 그대로",
	L.cappedScale("hover", L.fitScale({ 40, 40, 60, 60 }, { 0, 0, 100, 100 })) == UIFxConfig.HOVER_SCALE
		and L.fitScale({ 0, 40, 100, 60 }, { 0, 0, 100, 100 }) == 1 and L.fitScale({ -10, 0, 30, 20 }, { 0, 0, 100, 100 }) == 1
		and L.cappedScale("pressed", 1) == UIFxConfig.PRESS_SCALE)
check("잘림 상한: 가운데 기준 여유만큼(폭 80 · 여유 10씩 → 1.25)", checkClose(L.fitScale({ 10, 10, 90, 90 }, { 0, 0, 100, 100 }), 1.25))

-- 3. 빛 띠 순수 계산 ---------------------------------------------------------------------------------------
do
	local half, peak = UIFxConfig.SHINE_BAND_HALF_WIDTH, UIFxConfig.SHINE_PEAK_TRANSPARENCY
	local kp = ShineLogic.keypoints(half, peak)
	local sorted, inRange = true, true
	for i, k in ipairs(kp) do
		if k.time < 0 or k.time > 1 or k.value < 0 or k.value > 1 then
			inRange = false
		end
		if i > 1 and k.time <= kp[i - 1].time then
			sorted = false
		end
	end
	check("키포인트: 0 ~ 1 안 · 오름차순 · 첫 0 · 끝 1", sorted and inRange and kp[1].time == 0 and kp[#kp].time == 1)
	check("키포인트: 띠 폭 = 반폭 × 2(가운데 0.5) · 가운데 = PEAK · 가장자리 1", checkClose(kp[4].time - kp[2].time, half * 2)
		and kp[3].time == 0.5 and checkClose(kp[3].value, peak) and kp[1].value == 1 and kp[2].value == 1 and kp[4].value == 1 and kp[5].value == 1)
	local wide = ShineLogic.keypoints(0.9, -1)
	check("키포인트: 범위 밖 반폭 · 투명도는 잘라서 정렬을 지킨다", wide[2].time > 0 and wide[4].time < 1 and wide[3].value == 0)
	local lin = function(a: number)
		return a
	end
	local sweep = UIFxConfig.SHINE_SWEEP_TIME
	check("Offset: 시작 −1 · 반 0 · 끝 1 · 지나간 뒤 · 시작 전 −1", ShineLogic.offsetAt(0, lin) == -1 and checkClose(ShineLogic.offsetAt(sweep / 2, lin), 0)
		and checkClose(ShineLogic.offsetAt(sweep, lin), 1) and ShineLogic.offsetAt(sweep + 0.01, lin) == -1 and ShineLogic.offsetAt(-0.1, lin) == -1)
	check("색: premium = 금테 노랑 · 그 밖 흰색 · 진행 보라는 어디에도 없다", ShineLogic.colorOf("premium") == UiTheme.Colors.cashout.base
		and ShineLogic.colorOf("default") == Color3.new(1, 1, 1) and ShineLogic.colorOf("purple") == Color3.new(1, 1, 1)
		and ShineLogic.colorOf("premium") ~= UiTheme.Colors.advance.base)
end
do
	-- 가짜 나무: a(gui) → b(gui) → s(screen) → root
	local function node(kind: string, parent: any?, visible: boolean?, enabled: boolean?): any
		return { kind = kind, parent = parent, visible = visible ~= false, enabled = enabled ~= false }
	end
	local access: ShineLogic.NodeAccess = {
		parentOf = function(n)
			return n.parent
		end,
		isGui = function(n)
			return n.kind == "gui"
		end,
		visibleOf = function(n)
			return n.visible
		end,
		isScreenGui = function(n)
			return n.kind == "screen"
		end,
		enabledOf = function(n)
			return n.enabled
		end,
		isRoot = function(n)
			return n.kind == "root"
		end,
	}
	local root = node("root")
	local s = node("screen", root)
	local b = node("gui", s)
	local a = node("gui", b)
	check("가시성: 대상 · 조상 · ScreenGui 전부 보이면 true", ShineLogic.isVisible(a, access))
	b.visible = false
	check("가시성: 조상 하나가 숨으면 false", not ShineLogic.isVisible(a, access))
	b.visible = true
	s.enabled = false
	check("가시성: ScreenGui Enabled=false면 false", not ShineLogic.isVisible(a, access))
	check("가시성: 나무에 붙지 않았으면 false", not ShineLogic.isVisible(node("gui", nil), access))
	local picks = ShineLogic.pickActive({
		{ visible = true, priority = 0, order = 1 },
		{ visible = true, priority = 1, order = 2 },
		{ visible = false, priority = 9, order = 3 },
		{ visible = true, priority = 0, order = 4 },
		{ visible = true, priority = 1, order = 5 },
	}, 3)
	check("상한: 보이는 것 중 우선순위 높은 순 · 붙인 순으로 상한까지(숨은 것 제외)", #picks == 3 and picks[1] == 2 and picks[2] == 5 and picks[3] == 1)
end

-- 4. 실물 — 버튼 반응 ---------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "UiFxTest"
gui.ResetOnSpawn = false
gui.AutoLocalize = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function freeButton(anchor: Vector2?): (Frame, TextButton)
	local root = Instance.new("Frame")
	root.AnchorPoint = anchor or Vector2.new(0, 0)
	root.Position = UDim2.fromScale(0.3, 0.3)
	root.Size = UDim2.fromScale(0.2, 0.1)
	root.Parent = gui
	local hit = Instance.new("TextButton")
	hit.Name = "HitArea"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Parent = root
	return root, hit
end
local function center(g: GuiObject): Vector2
	return g.AbsolutePosition + g.AbsoluteSize / 2
end

do
	local root, hit = freeButton()
	task.wait()
	local pos0, anchor0, c0, size0 = root.Position, root.AnchorPoint, center(root), root.AbsoluteSize
	local h = ButtonFx.attach(hit) :: ButtonFx.Handle
	check("붙이기: UIScale 하나(이름 ButtonFxScale) · Size · Position 그대로 · 쉬는 동안 1", h ~= nil and h.scale.Name == ButtonFx.SCALE_NAME
		and h.scale.Scale == 1 and root.Position == pos0 and root.Size == UDim2.fromScale(0.2, 0.1))
	h._debug.fire("enter", false, true)
	h._debug.settle()
	task.wait()
	check("올림: hover · Scale = HOVER_SCALE", h.state() == "hover" and checkClose(h.scale.Scale, UIFxConfig.HOVER_SCALE))
	check("올림: 가운데 기준으로 커진다(AnchorPoint (0,0)이어도 — 가운데 1px 안 · 크기 = 원래 × HOVER)", (center(root) - c0).Magnitude <= 1
		and math.abs(root.AbsoluteSize.X - size0.X * UIFxConfig.HOVER_SCALE) <= 1, string.format("c0=%s c=%s", tostring(c0), tostring(center(root))))
	h._debug.fire("down", false, true)
	h._debug.settle()
	task.wait()
	check("누름: pressed · Scale = PRESS_SCALE · 가운데 그대로", h.state() == "pressed" and checkClose(h.scale.Scale, UIFxConfig.PRESS_SCALE)
		and (center(root) - c0).Magnitude <= 1)
	h._debug.fire("up", false, true)
	check("뗌(위에 있음): hover로", h.state() == "hover" and checkClose(h._debug.goal(), UIFxConfig.HOVER_SCALE))
	h._debug.fire("down", false, true)
	h._debug.fire("leave", false, false)
	h._debug.settle()
	task.wait()
	check("누른 채 밖으로: 기본 · Scale 1 · 쉬면 AnchorPoint · Position이 원래 값 그대로", h.state() == "idle" and h.scale.Scale == 1
		and root.AnchorPoint == anchor0 and root.Position == pos0 and not h._debug.isShifted())
	h._debug.fire("down", true, true)
	h._debug.fire("up", true, nil)
	check("터치: 누름 → 뗌이면 바로 기본(올림 없음)", h.state() == "idle")
	hit.Active = false
	h._debug.fire("enter", false, true)
	check("비활성(Active=false): 반응하지 않는다", h.state() == "idle" and h._debug.goal() == 1)
	hit.Active = true
	check("이미 붙인 HitArea에 다시 붙이면 같은 손잡이", ButtonFx.attach(hit) == h)
	local before = h._debug.connections()
	root:Destroy()
	task.wait()
	check("파괴: 연결 · 트윈 정리(연결 0) · 목록에서 빠짐", before > 0 and h._debug.connections() == 0 and ButtonFx.get(hit) == nil)
end
do
	local b = Button.create({ size = "Small", color = "yellow", widthScale = 0.2 })
	b.root.Position = UDim2.fromScale(0.5, 0.5)
	b.root.Parent = gui
	local _, hit = WindowParts.decorateButton(b, "x")
	local h = ButtonFx.get(hit)
	check("공용 진입점: WindowParts.hitArea(decorateButton · 닫기 X)는 기본으로 붙는다", h ~= nil)
	b.setDisabled(true)
	if h ~= nil then
		h._debug.fire("enter", false, true)
		check("비활성 표현(공용 Button 회색): 반응하지 않는다", h.state() == "idle")
		b.setDisabled(false)
		h._debug.fire("enter", false, true)
		check("다시 켜지면 반응한다", h.state() == "hover")
	end
	b.root:Destroy()
end
do
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(0.5, 0.5)
	holder.Parent = gui
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.4, 0.4)
	grid.Parent = holder
	local item = Instance.new("Frame")
	item.Parent = holder
	local hit = WindowParts.hitArea(item)
	local h = ButtonFx.get(hit) :: ButtonFx.Handle
	task.wait()
	local pos0 = item.Position
	h._debug.fire("enter", false, true)
	h._debug.settle()
	check("격자 칸: 방식 direct(UIScale만 — 격자는 칸 가운데 기준) · Position 그대로", h.mode() == "direct" and item.Position == pos0
		and not h._debug.isShifted())
	holder:Destroy()
	local listHolder = Instance.new("Frame")
	listHolder.Parent = gui
	Instance.new("UIListLayout").Parent = listHolder
	local listItem = Instance.new("Frame")
	listItem.Parent = listHolder
	local lh = ButtonFx.get(WindowParts.hitArea(listItem)) :: ButtonFx.Handle
	lh._debug.fire("enter", false, true)
	check("목록 칸: 크기를 바꾸지 않는다(목록이 다시 배치돼 이웃이 밀린다) · skipped에 남긴다", lh._debug.goal() == 1
		and #ButtonFx.skipped >= 1 and ButtonFx.skipped[#ButtonFx.skipped].reason == "list_layout")
	listHolder:Destroy()
end
do
	local root, hit = freeButton()
	local foreign = Instance.new("UIScale")
	foreign.Scale = 0.8
	foreign.Parent = root
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Parent = root
	local h = ButtonFx.attach(hit) :: ButtonFx.Handle
	local body = root:FindFirstChild(ButtonFx.BODY_NAME)
	check("다른 UIScale: 덮지 않고(0.8 그대로) 안쪽 래퍼에 우리 UIScale · 글자는 래퍼로 · HitArea는 그대로", h.mode() == "wrapper"
		and checkClose(foreign.Scale, 0.8) and body ~= nil and label.Parent == body and hit.Parent == root and h.scale.Parent == body,
		string.format("mode=%s body=%s label=%s hit=%s scale=%s", h.mode(), tostring(body), tostring(label.Parent), tostring(hit.Parent),
			tostring(h.scale.Parent)))
	root:Destroy()
end
do
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromScale(0.1, 0.1)
	scroll.Size = UDim2.fromScale(0.4, 0.3)
	scroll.CanvasSize = UDim2.fromScale(0, 2)
	scroll.Parent = gui
	local row = Instance.new("Frame")
	row.Size = UDim2.fromScale(1, 0.1)
	row.Parent = scroll
	local h = ButtonFx.get(WindowParts.hitArea(row)) :: ButtonFx.Handle
	task.wait()
	h._debug.fire("enter", false, true)
	check("스크롤 목록 안 줄(폭 꽉 참): 올림을 잘리지 않게 줄인다(배치는 그대로)", h._debug.goal() < UIFxConfig.HOVER_SCALE
		and h._debug.goal() >= 1, tostring(h._debug.goal()))
	scroll:Destroy()
end
do
	-- 직접 만든 HitArea(공용 진입점 밖)에도 붙었나
	local store = Store.new()
	local slots = ShopSlots.create({ store = store })
	local rail = MenuRail.create(0.2)
	local tools = AutoTools.create({ store = store })
	local icon = DailyIcon.create({ store = store, onPress = function() end })
	local timers = BoostTimers.create({ store = store, autoTick = false, onPress = function() end })
	local function attachedAll(root: Instance): (number, number)
		local n, ok = 0, 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("TextButton") and d.Name == "HitArea" then
				n += 1
				if ButtonFx.get(d) ~= nil then
					ok += 1
				end
			end
		end
		return n, ok
	end
	local missing = {}
	for name, root in pairs({ ShopSlots = slots.root, MenuRail = rail.root, AutoTools = tools.root, DailyIcon = icon.root, BoostTimers = timers.root }) do
		local n, ok = attachedAll(root)
		if n == 0 or n ~= ok then
			table.insert(missing, string.format("%s %d/%d", name, ok, n))
		end
	end
	check("직접 만든 HitArea 연결: 구좌 · 메뉴 · 자동 도구 · 출석 아이콘 · 부스트 표시 전부", #missing == 0, table.concat(missing, ", "))

	-- 5. 실물 — 빛 띠 HUD 구좌 연결 -----------------------------------------------------------------------------
	local strength = slots.root:FindFirstChild("strength2x") :: GuiObject
	local blox = slots.root:FindFirstChild("blox2x") :: GuiObject
	local auto = slots.root:FindFirstChild("autoClicker") :: GuiObject
	check("HUD 구좌: 2배 힘(다음 계단) · 2배 블럭스에 빛 띠 · 자동 클리커에는 없음", Shine.isAttached(strength) and Shine.isAttached(blox)
		and not Shine.isAttached(auto))
	store.setSource(function(setter)
		setter("shop", { gamepasses = { "blox2x" }, paidRandomRestricted = false, boosts = {}, autoClick = false })
	end)
	check("HUD 구좌: 2배 블럭스를 가지면 빛 띠를 뗀다", not Shine.isAttached(blox) and Shine.isAttached(strength))
	for _, r in ipairs({ slots.root, rail.root, tools.root, icon.root, timers.root }) do
		r:Destroy()
	end
end

-- 6. 실물 — 빛 띠 덮개 --------------------------------------------------------------------------------------
do
	local fake = 1000
	Shine._debug.setClock(function()
		return fake
	end)
	local tile = Instance.new("Frame")
	tile.Position = UDim2.fromScale(0.6, 0.6)
	tile.Size = UDim2.fromScale(0.1, 0.1)
	tile.BackgroundColor3 = UiTheme.Colors.robux.base
	tile.Parent = gui
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.ZIndex = 2
	price.TextColor3 = Color3.new(1, 1, 1)
	price.Text = "3 R$"
	price.Parent = tile
	check("붙이기: true", Shine.attach(tile, { preset = "default", priority = 5 }))
	local overlay = Shine._debug.overlayOf(tile) :: GuiObject
	local g = Shine._debug.gradientOf(tile) :: UIGradient
	check("덮개: 대상의 자식 · 크기 1 × 1 · 글씨보다 낮은 ZIndex · AutoLocalize false · 입력 안 받음", overlay ~= nil and overlay.Parent == tile
		and overlay.Size == UDim2.fromScale(1, 1) and overlay.ZIndex < price.ZIndex and overlay.AutoLocalize == false and overlay.Active == false)
	check("그라디언트: Rotation = SHINE_ANGLE · 키포인트 = ShineLogic · 시작 Offset −1 · 색 흰색(덮개 색 그대로)", g.Rotation == UIFxConfig.SHINE_ANGLE
		and #g.Transparency.Keypoints == #ShineLogic.keypoints(UIFxConfig.SHINE_BAND_HALF_WIDTH, UIFxConfig.SHINE_PEAK_TRANSPARENCY)
		and g.Offset.X == -1 and g.Color.Keypoints[1].Value == Color3.new(1, 1, 1))
	Shine._debug.step()
	local startAt = Shine._debug.startAtOf(tile) :: number
	check("시작 지연: 0 ~ SHINE_START_JITTER_MAX", startAt ~= nil and startAt >= fake and startAt <= fake + UIFxConfig.SHINE_START_JITTER_MAX)
	fake = startAt + UIFxConfig.SHINE_SWEEP_TIME / 2
	Shine._debug.step()
	check("지나가는 중: Offset이 −1과 1 사이(가운데 근처) · 덮개 보임 · 글씨 색 그대로", math.abs(g.Offset.X) < 0.5 and overlay.Visible
		and price.TextColor3 == Color3.new(1, 1, 1), tostring(g.Offset.X))
	fake = startAt + UIFxConfig.SHINE_INTERVAL + UIFxConfig.SHINE_SWEEP_TIME + 0.01
	Shine._debug.step()
	check("지나간 뒤 · 다음 간격 시작: SHINE_INTERVAL마다 다시(시작 시각이 간격만큼 밀린다)", checkClose(Shine._debug.startAtOf(tile) :: number,
		startAt + UIFxConfig.SHINE_INTERVAL) and g.Offset.X == -1)
	tile.Visible = false
	Shine._debug.step()
	check("숨으면 멈춘다(덮개 숨김 · Offset −1)", not Shine._debug.isRunning(tile) and not overlay.Visible and g.Offset.X == -1)
	tile.Visible = true
	gui.Enabled = false
	Shine._debug.step()
	local pausedByGui = not Shine._debug.isRunning(tile)
	gui.Enabled = true
	Shine._debug.step()
	check("ScreenGui가 꺼지면 멈추고 켜지면 재개", pausedByGui and Shine._debug.isRunning(tile))
	-- 상한: 우선순위 높은 4개를 더 붙이면 그중 3개만 돈다(실물 HUD 구좌는 우선순위 0이라 밀린다)
	local more: { Frame } = {}
	for i = 1, 4 do
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(0.05, 0.05)
		f.Parent = gui
		Shine.attach(f, { priority = 10 })
		table.insert(more, f)
	end
	Shine._debug.step()
	local running = 0
	for _, f in ipairs(more) do
		if Shine._debug.isRunning(f) then
			running += 1
		end
	end
	check("한 화면 상한: 동시에 도는 것은 SHINE_MAX_ACTIVE개(우선순위 높은 순) · 나머지는 멈춤", running == UIFxConfig.SHINE_MAX_ACTIVE
		and Shine._debug.activeCount() == UIFxConfig.SHINE_MAX_ACTIVE and not Shine._debug.isRunning(tile))
	for _, f in ipairs(more) do
		Shine.detach(f)
	end
	Shine.attach(tile, { preset = "premium" })
	check("프리셋 바꾸기: 덮개 색 = 금테 노랑", overlay.BackgroundColor3 == UiTheme.Colors.cashout.base)
	Shine.detach(tile)
	check("떼기: 덮개 없어짐 · 목록에서 빠짐", tile:FindFirstChild(Shine.OVERLAY_NAME) == nil and not Shine.isAttached(tile))
	local round = Instance.new("Frame")
	round.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = round
	Shine.attach(round)
	local ro = Shine._debug.overlayOf(round) :: GuiObject
	check("둥근 모서리: 덮개도 같은 UICorner(모양 밖으로 새지 않게)", ro:FindFirstChildOfClass("UICorner") ~= nil
		and (ro:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius == corner.CornerRadius)
	round:Destroy()
	task.wait()
	check("파괴: 대상이 없어지면 정리", not Shine.isAttached(round))
	local img = Instance.new("ImageLabel")
	img.Image = "rbxassetid://1"
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = Rect.new(10, 10, 20, 20)
	img.Parent = gui
	Shine.attach(img)
	local io = Shine._debug.overlayOf(img) :: ImageLabel
	check("9-slice 그림: 덮개 = 같은 그림 · 같은 SliceCenter의 ImageLabel(그림 모양 안에서만 보인다)", io:IsA("ImageLabel")
		and io.Image == img.Image and io.SliceCenter == img.SliceCenter and io.ScaleType == Enum.ScaleType.Slice and io.BackgroundTransparency == 1)
	Shine.detach(img)
	img:Destroy()
	tile:Destroy()
	Shine._debug.setClock(nil)
end

-- 7. 상점 로벅스 탭 줄 연결 ------------------------------------------------------------------------------------
do
	local raise = {}
	local list = RobuxList.create({ name = "FxList", parent = gui, position = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.5, 0.5),
		rowH = 0.2, rowGap = 0.02, maxRows = 30, raise = raise, purchase = { request = function()
			return true
		end, isPending = function()
			return false
		end } })
	local shop = { gamepasses = {}, paidRandomRestricted = false, boosts = {}, autoClick = false, potions = { strength = 0, damage = 0, luck = 0 },
		rollCredits = { lucky = 0, super = 0 }, gymUnlocks = {} }
	local rows = RobuxShopLogic.rows(shop)
	list.render(rows)
	local shining, wrong = {}, {}
	for i, r in ipairs(rows) do
		local on = Shine.isAttached(list.rows[i].frame)
		if on then
			table.insert(shining, r.key)
		end
		if on ~= (UIFxConfig.SHINE_TARGETS[r.key] ~= nil and r.canBuy) then
			table.insert(wrong, r.key)
		end
	end
	table.sort(shining)
	check("상점 줄: 계단(다음 단계) · 2배 블럭스 줄에만 빛 띠", #wrong == 0 and table.concat(shining, ",") == "blox2x,strengthLadder",
		table.concat(shining, ",") .. " / " .. table.concat(wrong, ","))
	list.render({})
	local any = false
	for _, p in ipairs(list.rows) do
		any = any or Shine.isAttached(p.frame)
	end
	check("줄이 사라지면 빛 띠도 뗀다", not any)
	list.list:Destroy()
end

gui:Destroy()

print(string.format("[UiFxTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UiFxTests] %d test(s) failed", failed))
end

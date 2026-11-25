--!strict
-- 대장간 창 (큰 창, Window 층 — 지시서 #33 · DESIGN 16장 "대장간 화면"). 만드는 곳은 EconomyV2Boot.
--
-- 탭 둘: 제작 · 교환소.
--   제작   광석 10종 칸(가진 수 — 누르면 다음 빈 칸에 넣는다) · 넣은 광석 5칸(누르면 뺀다) · 게이지 5칸(정수 점수 → 칸) · 받을 토큰 ·
--          자동 채우기 · 비우기 · 제작 · 자동 제작 토글 + 상태 · 확률표(지금 칸 수의 15종 — 제작 전에 항상 보인다 · 다른 칸 수 탭) ·
--          자동 제작 결과 목록(최근 AUTO_CRAFT_LOG_MAX줄). 제작 결과는 연출(임시 — 좋은 등급일수록 크게)이고 스킵 버튼은 CRAFT_SKIP_SEC에 나타난다
--   교환소 등급 탭(희귀 · 에픽 · 신화 · 전설 · ???) — 곡괭이 · 비용 · 보유 · 교환 버튼. ??? 탭은 잠긴 칸
-- 판정은 전부 서버다(ForgeService) — 이 창은 요청(send)을 보내고 받은 결과를 그린다. 문장은 Strings 키 · AutoLocalize false · UiTheme.FONT.
-- 등급 색(UiTheme.EquipGrade)은 아이템 테두리와 이름 글자에만 쓴다(docs/UI.md "장비 등급 색"). 위치 · 크기는 Scale만.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots) -- 에셋 자리(#36 — 값이 있으면 그 그림 · 없으면 임시 도형)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local ForgeWindowLogic = require(script.Parent.Parent.Parent.Logic.ForgeWindowLogic)

local ForgeWindow = {}

local Z_OVERLAY = 20
local LEFT_W = 0.58
local RIGHT_X = 0.62
local RIGHT_W = 0.38

export type Deps = {
	send: (payload: any) -> (),
	onClose: () -> (),
	clock: (() -> number)?,
	autoStep: boolean?, -- false면 연출 시간을 step(now)로 직접 굴린다(테스트)
	notify: ((text: string, rarity: string) -> ())?, -- 신화 이상 크게 알리기(토스트) — 없으면 안 알림
	openEquipment: (() -> ())?, -- 장비 창으로(#34) — 없으면 버튼을 만들지 않는다
}

export type Handle = {
	root: Frame,
	set: (values: any) -> (),
	onEvent: (payload: any) -> (),
	step: (now: number) -> (),
	showTab: (name: string) -> (),
	_debug: any,
}

local function frame(name: string, parent: Instance, x: number, y: number, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.ZIndex = WindowParts.Z_TEXT
	f.Parent = parent
	return f
end

local function text(name: string, parent: Instance, level: any, x: number, y: number, w: number, h: number, align: Enum.TextXAlignment?): TextLabel
	local label = WindowParts.makeText(name, parent, level, x, y, w, h, align)
	label.AutoLocalize = false
	label.Text = ""
	return label
end

local function button(name: string, parent: Instance, color: Button.ColorName, x: number, y: number, w: number, h: number, caption: string)
	local b = Button.create({ size = "Small", color = color, widthScale = w, heightScale = h })
	b.root.Name = name
	b.root.Position = UDim2.fromScale(x, y)
	b.root.ZIndex = WindowParts.Z_BUTTON
	b.root.Parent = parent
	local label, hit = WindowParts.decorateButton(b, caption)
	label.AutoLocalize = false
	label.TextScaled = true
	WindowParts.raiseButtons({ b.root })
	return b, label, hit
end

local function stroke(parent: Instance, color: Color3, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function rarityOf(id: string): string
	local def = EconomyV2Logic.pickaxe(id)
	return if def ~= nil then def.rarity else "common"
end

local function pickName(id: string): string
	local def = EconomyV2Logic.pickaxe(id)
	return if def ~= nil then Locale.t(def.nameKey) else id
end

function ForgeWindow.create(deps: Deps): Handle
	local clock = deps.clock or os.clock
	local panel = Panel.create("Large", Locale.t("forge.title"))
	panel.root.Name = "ForgeWindow"
	panel.titleLabel.AutoLocalize = false
	local body = panel.body
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons({ panel.closeButton.root })

	local values: any = { ores = EconomyV2Logic.newInv(), tokens = {}, owned = {}, autoOn = false, autoCount = 0, forgeOpen = false }
	local sel = ForgeWindowLogic.newSelection()
	local oddsTab: number? = nil -- nil = 지금 칸 수를 따라간다
	local exTab = "rare"
	local log: { string } = {}
	local message = ""

	-- ===== 탭 ==========================================================================================
	local craftTabB, _, craftTabHit = button("CraftTab", body, "blue", 0, 0, 0.18, 0.08, Locale.t("forge.tab.craft"))
	local exTabB, _, exTabHit = button("ExchangeTab", body, "blue", 0.2, 0, 0.18, 0.08, Locale.t("forge.tab.exchange"))
	if deps.openEquipment ~= nil then
		local _, _, equipHit = button("EquipmentLink", body, "gray", 0.4, 0, 0.18, 0.08, Locale.t("equip.open"))
		equipHit.Activated:Connect(function()
			(deps.openEquipment :: () -> ())()
		end)
	end
	local craftFrame = frame("Craft", body, 0, 0.1, 1, 0.9)
	local exFrame = frame("Exchange", body, 0, 0.1, 1, 0.9)

	-- ===== 제작: 광석 칸 =================================================================================
	local oreCells: { { root: Frame, name: TextLabel, count: TextLabel, hit: TextButton } } = {}
	local cellW = LEFT_W / 5
	for k = 1, Config.ORE_COUNT do
		local col, row = (k - 1) % 5, (k - 1) // 5
		local cell = frame("Ore" .. k, craftFrame, col * cellW, row * 0.15, cellW - 0.01, 0.135)
		cell.BackgroundTransparency = 0.15
		cell.BackgroundColor3 = Config.ORE_VISUALS[k].color -- 임시 도형(광석 재질 색 — iconId 자리)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.15, 0)
		corner.Parent = cell
		local nameL = text("Name", cell, "small", 0.04, 0.02, 0.92, 0.5, Enum.TextXAlignment.Center)
		nameL.Text = Locale.t(EconomyV2Logic.oreNameKey(k))
		local countL = text("Count", cell, "small", 0.04, 0.5, 0.92, 0.46, Enum.TextXAlignment.Center)
		local hit = WindowParts.hitArea(cell)
		AssetSlots.applyImage(cell, Config.ORE_VISUALS[k].iconId, { position = UDim2.fromScale(0.5, 0.3), size = UDim2.fromScale(0.5, 0.5) })
		oreCells[k] = { root = cell, name = nameL, count = countL, hit = hit }
	end

	-- ===== 제작: 넣은 광석 5칸 · 게이지 =================================================================
	local slotCells: { { root: Frame, label: TextLabel, hit: TextButton } } = {}
	for i = 1, Config.CRAFT_INPUT do
		local cell = frame("Slot" .. i, craftFrame, (i - 1) * cellW, 0.32, cellW - 0.01, 0.16)
		cell.BackgroundTransparency = 0.2
		cell.BackgroundColor3 = UiTheme.Colors.neutral.dark
		stroke(cell, Color3.new(1, 1, 1), 2)
		local label = text("Label", cell, "small", 0.04, 0.1, 0.92, 0.8, Enum.TextXAlignment.Center)
		local hit = WindowParts.hitArea(cell)
		slotCells[i] = { root = cell, label = label, hit = hit }
	end
	local gaugeCells: { Frame } = {}
	for i = 1, Config.CRAFT_INPUT do
		local g = frame("Gauge" .. i, craftFrame, (i - 1) * cellW, 0.505, cellW - 0.01, 0.05)
		g.BackgroundTransparency = 0
		g.BackgroundColor3 = UiTheme.Colors.neutral.dark
		gaugeCells[i] = g
	end
	local gaugeText = text("GaugeText", craftFrame, "small", 0, 0.565, LEFT_W, 0.06)
	local tokenText = text("TokenText", craftFrame, "small", 0, 0.625, LEFT_W, 0.06)

	local _, _, fillHit = button("Fill", craftFrame, "gray", 0, 0.7, 0.18, 0.11, Locale.t("forge.fill"))
	local _, _, clearHit = button("Clear", craftFrame, "gray", 0.2, 0.7, 0.16, 0.11, Locale.t("forge.clear"))
	local craftB, _, craftHit = button("CraftButton", craftFrame, "purple", 0.38, 0.7, 0.2, 0.11, Locale.t("forge.craft"))
	local autoB, autoLabel, autoHit = button("AutoToggle", craftFrame, "gray", 0, 0.84, 0.3, 0.11, Locale.t("forge.auto.off"))
	local statusText = text("Status", craftFrame, "small", 0.32, 0.84, LEFT_W - 0.32, 0.11)

	-- ===== 제작: 확률표 · 자동 제작 목록(오른쪽) ===========================================================
	local oddsTitle = text("OddsTitle", craftFrame, "small", RIGHT_X, 0, RIGHT_W, 0.06)
	local oddsTabs: { { b: any, hit: TextButton } } = {}
	local tabW = RIGHT_W / (Config.CRAFT_INPUT + 1)
	for s = 0, Config.CRAFT_INPUT do
		local b, _, hit = button("OddsTab" .. s, craftFrame, "gray", RIGHT_X + s * tabW, 0.065, tabW - 0.004, 0.065,
			Locale.t("forge.odds.tab", { n = tostring(s) }))
		oddsTabs[s + 1] = { b = b, hit = hit }
	end
	local oddsList = frame("OddsList", craftFrame, RIGHT_X, 0.14, RIGHT_W, 0.68) -- 15줄(Play #33 — 0.56이면 글자가 너무 작았다)
	local oddsRows: { { name: TextLabel, pct: TextLabel } } = {}
	local rowH = 1 / #Config.PICKAXES
	for i = 1, #Config.PICKAXES do
		local nameL = text("Name" .. i, oddsList, "small", 0, (i - 1) * rowH, 0.68, rowH * 0.95)
		local pctL = text("Pct" .. i, oddsList, "small", 0.68, (i - 1) * rowH, 0.32, rowH * 0.95, Enum.TextXAlignment.Right)
		oddsRows[i] = { name = nameL, pct = pctL }
	end
	local logFrame = frame("AutoLog", craftFrame, RIGHT_X, 0.83, RIGHT_W, 0.17)
	local logRows: { TextLabel } = {}
	for i = 1, Config.AUTO_CRAFT_LOG_MAX do
		logRows[i] = text("Log" .. i, logFrame, "small", 0, (i - 1) / Config.AUTO_CRAFT_LOG_MAX, 1, 0.95 / Config.AUTO_CRAFT_LOG_MAX)
	end

	-- ===== 교환소 ======================================================================================
	local exTabs: { [string]: { b: any, hit: TextButton } } = {}
	for i, r in ipairs(ForgeWindowLogic.EXCHANGE_TABS) do
		local b, label, hit = button("Tab_" .. r, exFrame, "gray", (i - 1) * 0.2, 0, 0.19, 0.09, Locale.t("grade." .. r))
		label.TextColor3 = UiTheme.equipGradeColor(r) -- 이름 글자(등급 색 예외 — 탭 이름은 등급 이름이다)
		exTabs[r] = { b = b, hit = hit }
	end
	local haveText = text("Have", exFrame, "medium", 0, 0.11, 1, 0.07)
	local exRows: { any } = {}
	for i = 1, 4 do
		local row = frame("Row" .. i, exFrame, 0, 0.2 + (i - 1) * 0.16, 1, 0.14)
		row.BackgroundTransparency = 0.3
		row.BackgroundColor3 = UiTheme.Colors.neutral.dark
		local border = stroke(row, UiTheme.EquipGrade.common, 3)
		local nameL = text("Name", row, "medium", 0.02, 0.1, 0.44, 0.8)
		local costL = text("Cost", row, "small", 0.47, 0.1, 0.16, 0.8)
		local ownL = text("Owned", row, "small", 0.63, 0.1, 0.16, 0.8)
		local b, _, hit = button("ExchangeButton", row, "blue", 0.8, 0.1, 0.18, 0.8, Locale.t("forge.ex.button"))
		exRows[i] = { root = row, border = border, name = nameL, cost = costL, owned = ownL, b = b, hit = hit, id = nil :: string? }
	end
	local locked = frame("Locked", exFrame, 0.2, 0.25, 0.6, 0.4)
	locked.BackgroundTransparency = 0.3
	locked.BackgroundColor3 = UiTheme.Colors.neutral.dark
	stroke(locked, UiTheme.EquipGrade.next, 3)
	local lockedText = text("Text", locked, "medium", 0.05, 0.1, 0.9, 0.8, Enum.TextXAlignment.Center)
	lockedText.Text = Locale.t("forge.ex.locked")
	local exMessage = text("Message", exFrame, "small", 0, 0.86, 1, 0.08, Enum.TextXAlignment.Center)

	-- ===== 결과 연출(임시) ===============================================================================
	local overlay = Instance.new("Frame")
	overlay.Name = "ResultOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = Z_OVERLAY
	overlay.Visible = false
	overlay.Parent = body
	AssetSlots.applyImage(overlay, Config.CRAFT_FX_VISUAL.imageId, { size = UDim2.fromScale(0.6, 0.9) }) -- 제작 연출 그림(#36 — 이름 뒤)
	local resultNames: { TextLabel } = {}
	for i = 1, Config.TRIPLE_CRAFT_COUNT do
		local l = text("Name" .. i, overlay, "large", 0.1, 0.2 + (i - 1) * 0.14, 0.8, 0.12, Enum.TextXAlignment.Center)
		l.ZIndex = Z_OVERLAY + 1
		local sc = Instance.new("UIScale")
		sc.Parent = l
		resultNames[i] = l
	end
	local resultNew = text("New", overlay, "medium", 0.1, 0.08, 0.8, 0.1, Enum.TextXAlignment.Center)
	resultNew.ZIndex = Z_OVERLAY + 1
	resultNew.TextColor3 = UiTheme.Colors.cashout.light
	local resultTokens = text("Tokens", overlay, "medium", 0.1, 0.64, 0.8, 0.08, Enum.TextXAlignment.Center)
	resultTokens.ZIndex = Z_OVERLAY + 1
	local skipB, skipLabel, skipHit = button("Skip", overlay, "gray", 0.4, 0.78, 0.2, 0.11, Locale.t("forge.skip"))
	for _, obj in ipairs(skipB.root:GetDescendants()) do
		if obj:IsA("GuiObject") then
			obj.ZIndex = Z_OVERLAY + 2
		end
	end
	skipB.root.ZIndex = Z_OVERLAY + 2
	skipLabel.ZIndex = Z_OVERLAY + 3
	skipHit.ZIndex = Z_OVERLAY + 4
	skipB.root.Visible = false
	local resultStart: number? = nil

	-- ===== 그리기 ======================================================================================
	local function currentSlots(): number
		local _, slots = ForgeWindowLogic.gauge(sel)
		return slots
	end

	local function renderOdds()
		local s = oddsTab or currentSlots()
		oddsTitle.Text = Locale.t("forge.odds.title", { slots = tostring(s) })
		for i, tab in ipairs(oddsTabs) do
			tab.b.setPressed(i - 1 == s)
		end
		for i, line in ipairs(ForgeWindowLogic.oddsLines(s)) do
			local row = oddsRows[i]
			row.name.Text = pickName(line.id)
			row.name.TextColor3 = UiTheme.equipGradeColor(line.rarity)
			row.pct.Text = line.text
		end
	end

	local function renderCraft()
		local inv = values.ores
		for k, cell in ipairs(oreCells) do
			local left = (inv[k] or 0) - ForgeWindowLogic.usedOf(sel, k)
			cell.count.Text = "×" .. tostring(left)
			cell.root.BackgroundTransparency = if left > 0 then 0.15 else 0.7
		end
		for i, cell in ipairs(slotCells) do
			local k = sel.ores[i]
			if k ~= nil then
				cell.label.Text = Locale.t(EconomyV2Logic.oreNameKey(k))
				cell.root.BackgroundColor3 = Config.ORE_VISUALS[k].color
				AssetSlots.applyImage(cell.root, Config.ORE_VISUALS[k].iconId)
			else
				AssetSlots.applyImage(cell.root, nil)
				cell.label.Text = ""
				cell.root.BackgroundColor3 = UiTheme.Colors.neutral.dark
			end
		end
		local points, slots = ForgeWindowLogic.gauge(sel)
		for i, g in ipairs(gaugeCells) do
			g.BackgroundColor3 = if i <= slots then UiTheme.Colors.advance.base else UiTheme.Colors.neutral.dark
		end
		gaugeText.Text = Locale.t("forge.gauge", { slots = tostring(slots), max = tostring(Config.CRAFT_INPUT), points = tostring(points) })
		tokenText.Text = ForgeWindowLogic.tokensText(slots)
		craftB.setDisabled(not ForgeWindowLogic.isFull(sel) or overlay.Visible)
		autoLabel.Text = Locale.t(if values.autoOn then "forge.auto.on" else "forge.auto.off")
		autoB.setPressed(values.autoOn)
		statusText.Text = if values.autoOn then Locale.t("forge.auto.status", { count = tostring(values.autoCount) }) else message
		for i, row in ipairs(logRows) do
			row.Text = log[i] or ""
		end
		renderOdds()
	end

	local function renderExchange()
		local tokens = values.tokens or {}
		local isLocked = ForgeWindowLogic.isLockedTab(exTab)
		for r, tab in pairs(exTabs) do
			tab.b.setPressed(r == exTab)
		end
		haveText.Text = Locale.t("forge.ex.have", { token = ForgeWindowLogic.tokenName(exTab), n = tostring(tokens[exTab] or 0) })
		-- 토큰 아이콘(#37 — TOKEN_VISUALS · 값이 없으면 글자만)
		local tv = Config.TOKEN_VISUALS[exTab]
		AssetSlots.applyImage(haveText, if tv ~= nil then tv.iconId else nil, { position = UDim2.fromScale(0.97, 0.5), size = UDim2.fromScale(0.06, 1) })
		locked.Visible = isLocked
		local lines = if isLocked then {} else ForgeWindowLogic.exchangeLines(exTab, tokens, values.owned or {})
		for i, row in ipairs(exRows) do
			local line = lines[i]
			row.root.Visible = line ~= nil
			row.id = if line ~= nil then line.id else nil
			if line ~= nil then
				local color = UiTheme.equipGradeColor(exTab)
				row.border.Color = color
				row.name.Text = pickName(line.id)
				row.name.TextColor3 = color
				row.cost.Text = Locale.t("forge.ex.cost", { n = tostring(line.cost) })
				row.owned.Text = if line.owned > 0 then Locale.t("forge.ex.owned", { n = tostring(line.owned) }) else Locale.t("forge.ex.notOwned")
				row.b.setDisabled(not line.can)
			end
		end
	end

	local function render()
		renderCraft()
		renderExchange()
	end

	local function showTab(name: string)
		craftFrame.Visible = name == "craft"
		exFrame.Visible = name == "exchange"
		craftTabB.setPressed(name == "craft")
		exTabB.setPressed(name == "exchange")
	end

	local function closeResult()
		overlay.Visible = false
		resultStart = nil
		skipB.root.Visible = false
		render()
	end

	local function showResult(payload: any)
		local ids = payload.ids or {}
		local best = "common"
		local order = { common = 1, rare = 2, epic = 3, mythic = 4, legendary = 5 }
		for i, l in ipairs(resultNames) do
			local id = ids[i]
			l.Visible = id ~= nil
			if id ~= nil then
				local r = rarityOf(id)
				l.Text = string.format("%s · %s", Locale.t("grade." .. r), pickName(id))
				l.TextColor3 = UiTheme.equipGradeColor(r)
				local sc = l:FindFirstChildOfClass("UIScale")
				if sc ~= nil then
					sc.Scale = ForgeWindowLogic.resultScale(r)
				end
				if (order[r] or 0) > (order[best] or 0) then
					best = r
				end
			end
		end
		local anyNew = false
		for _, v in ipairs(payload.isNew or {}) do
			anyNew = anyNew or v == true
		end
		resultNew.Text = if anyNew then Locale.t("forge.result.new") else ""
		resultTokens.Text = ForgeWindowLogic.tokensText(tonumber(payload.slots) or 0, true)
		overlay.Visible = true
		skipB.root.Visible = false
		resultStart = clock()
		craftB.setDisabled(true)
		return best
	end

	local function step(now: number)
		if resultStart == nil then
			return
		end
		local t = now - (resultStart :: number)
		skipB.root.Visible = t >= Config.CRAFT_SKIP_SEC
		if t >= Config.CRAFT_ANIM_SEC then
			closeResult()
		end
	end

	local function pushLog(line: string)
		table.insert(log, 1, line)
		while #log > Config.AUTO_CRAFT_LOG_MAX do
			table.remove(log)
		end
	end

	local function onEvent(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local kind = payload.kind
		if kind == "craft_result" then
			if payload.ok == true then
				if type(payload.ores) == "table" then
					values.ores = payload.ores
				end
				ForgeWindowLogic.clamp(sel, values.ores)
				for _, id in ipairs(payload.ids or {}) do
					local r = rarityOf(id)
					pushLog(string.format("%s · %s", Locale.t("grade." .. r), pickName(id)))
					if payload.auto == true and ForgeWindowLogic.isBigNotice(r) and deps.notify ~= nil then
						deps.notify(Locale.t("forge.big", { name = pickName(id) }), r)
					end
				end
				message = ""
				if payload.auto ~= true then
					showResult(payload)
				end
			else
				message = ForgeWindowLogic.reasonText(payload.reason)
			end
		elseif kind == "auto_state" then
			if payload.on ~= true and payload.reason ~= nil then
				message = Locale.t("forge.auto.stopped", { reason = ForgeWindowLogic.reasonText(payload.reason) })
			end
		elseif kind == "exchange_result" then
			if payload.ok == true and type(payload.id) == "string" then
				exMessage.Text = Locale.t("forge.ex.done", { name = pickName(payload.id) })
			else
				exMessage.Text = ForgeWindowLogic.reasonText(payload.reason)
			end
		end
		render()
	end

	-- ===== 입력 ========================================================================================
	for k, cell in ipairs(oreCells) do
		cell.hit.Activated:Connect(function()
			if ForgeWindowLogic.add(sel, values.ores, k) then
				oddsTab = nil
				render()
			end
		end)
	end
	for i, cell in ipairs(slotCells) do
		cell.hit.Activated:Connect(function()
			if ForgeWindowLogic.remove(sel, i) then
				oddsTab = nil
				render()
			end
		end)
	end
	for i, tab in ipairs(oddsTabs) do
		tab.hit.Activated:Connect(function()
			oddsTab = i - 1
			renderOdds()
		end)
	end
	fillHit.Activated:Connect(function()
		sel = ForgeWindowLogic.fill(values.ores)
		oddsTab = nil
		if #sel.ores == 0 then
			message = ForgeWindowLogic.reasonText("not_enough_ore")
		end
		render()
	end)
	clearHit.Activated:Connect(function()
		sel = ForgeWindowLogic.newSelection()
		oddsTab = nil
		render()
	end)
	craftHit.Activated:Connect(function()
		if not ForgeWindowLogic.isFull(sel) or overlay.Visible then
			return
		end
		deps.send({ action = "craft", combo = table.clone(sel.ores) })
	end)
	autoHit.Activated:Connect(function()
		if values.autoOn then
			deps.send({ action = "auto", on = false })
		elseif ForgeWindowLogic.isFull(sel) then
			deps.send({ action = "auto", on = true, combo = table.clone(sel.ores) })
		else
			deps.send({ action = "auto", on = true, fill = true }) -- 칸이 비어 있으면 자동 채우기 조합으로 반복
		end
	end)
	skipHit.Activated:Connect(closeResult)
	craftTabHit.Activated:Connect(function()
		showTab("craft")
	end)
	exTabHit.Activated:Connect(function()
		showTab("exchange")
	end)
	for r, tab in pairs(exTabs) do
		tab.hit.Activated:Connect(function()
			exTab = r
			exMessage.Text = ""
			renderExchange()
		end)
	end
	for _, row in ipairs(exRows) do
		row.hit.Activated:Connect(function()
			if row.id ~= nil and not row.b.isDisabled() then
				deps.send({ action = "exchange", id = row.id })
			end
		end)
	end
	closeHit.Activated:Connect(function()
		deps.onClose()
	end)

	local conn: RBXScriptConnection? = nil
	if deps.autoStep ~= false then
		conn = RunService.Heartbeat:Connect(function()
			step(clock())
		end)
	end
	panel.root.Destroying:Connect(function()
		if conn ~= nil then
			conn:Disconnect()
		end
	end)

	showTab("craft")
	render()

	return {
		root = panel.root,
		set = function(v: any)
			values = v
			ForgeWindowLogic.clamp(sel, values.ores)
			render()
		end,
		onEvent = onEvent,
		step = step,
		showTab = showTab,
		_debug = {
			sel = function()
				return sel
			end,
			oreCells = oreCells,
			slotCells = slotCells,
			gaugeCells = gaugeCells,
			gaugeText = gaugeText,
			tokenText = tokenText,
			oddsRows = oddsRows,
			oddsTabs = oddsTabs,
			oddsTitle = oddsTitle,
			overlay = overlay,
			skip = skipB.root,
			resultNames = resultNames,
			exRows = exRows,
			exTabs = exTabs,
			haveText = haveText,
			locked = locked,
			logRows = logRows,
			craftB = craftB,
			fill = function()
				sel = ForgeWindowLogic.fill(values.ores)
				render()
			end,
			setExTab = function(r: string)
				exTab = r
				renderExchange()
			end,
		},
	}
end

return ForgeWindow

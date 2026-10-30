--!strict
-- 펫 창 (큰 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 7 지시서 #12.
-- 메뉴 레일 다섯째 칸 "펫 목록"(screenName "Pet")이 연다.
--
-- 위에서부터(본문 기준 — 수치는 docs/UI.md "지시서 #12" 절):
--   알 탭 1~3(고른 탭 하늘 · 나머지 회색 · 잠긴 알은 "OO 알 잠김") · 오른쪽 끝 "최고 장착"(회색)
--   안내 줄(고른 알 부화 비용 또는 해금 조건) · 오른쪽 "행운 ×N 적용"(P3)
--   확률 줄: 종 4개 "이름 ×m · 실제 확률%"(희귀도 색, 합 100)
--   부화 버튼(하늘 btn_blue + 비용) · 그 옆 잠긴 이유 · 오른쪽 상태 문구
--   왼쪽 아래: "보유 N / 저장 공간" + 보유 격자(스크롤 — 저장 공간 50, 게임패스면 150)
--   오른쪽 아래: "장착 N / 슬롯" + 장착 슬롯(파생 슬롯 수) · 고른 펫 이름 · 정보 · 장착/해제 · 크래프팅 · 놓아주기(확인 단계)
-- 값 · 문구는 UI/Logic/PetWindowLogic(순수). 결과 대기 중에는 그 버튼을 잠근다. 놓아주기는 되돌릴 수 없어 두 번 눌러야 한다(ConfirmFlow).
--
-- 지시서 #17(창별 상품 버튼 — docs/UI.md "지시서 #17"):
--   알 탭 오른쪽 "로벅스" 탭 — 누르면 아래 칸(보유 격자 · 장착 · 고른 펫) 자리에 상품 목록(3배 부화 · 2배 펫 행운 · +100 저장 · +3 장착 —
--   Components/RobuxList). 다시 누르거나 알 탭을 누르면 돌아온다.
--   부화 버튼 오른쪽 "×3 부화" — 3배 부화 게임패스가 있으면 켜진다(없으면 잠김 · 로벅스 탭에서 산다). 비용 3배(S18)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local PetWindowLogic = require(script.Parent.Parent.Parent.Logic.PetWindowLogic)
local TitleWindowLogic = require(script.Parent.Parent.Parent.Logic.TitleWindowLogic)
local ConfirmFlow = require(script.Parent.Parent.Parent.Logic.ConfirmFlow)
local RobuxShopLogic = require(script.Parent.Parent.Parent.Logic.RobuxShopLogic)
local RobuxList = require(script.Parent.Parent.Parent.Components.RobuxList)
local PurchaseClient = require(script.Parent.Parent.Parent.Parent.Net.PurchaseClient)

local PetWindow = {}

-- 본문 기준 배치. Claude가 정했다(docs/UI.md "지시서 #12" 절).
local TAB_H, TAB_W, TAB_GAP, MAX_TABS = 0.09, 0.19, 0.015, 3
local BEST_W = 0.2
local INFO_Y, INFO_H = 0.1, 0.06
local ODDS_Y, ODDS_H = 0.17, 0.07
-- 지시서 #17: 부화 줄에 ×3 부화 버튼을 넣으려고 부화 버튼 0.32 → 0.24, 잠긴 이유 칸을 그 오른쪽으로 옮겼다
local HATCH_Y, HATCH_H, HATCH_W = 0.25, 0.1, 0.24
local HATCH3_X, HATCH3_W = 0.26, 0.16
local HATCH_FOOT_X, HATCH_FOOT_W = 0.43, 0.2
local ROBUX_TAB_X, ROBUX_TAB_W = MAX_TABS * (TAB_W + TAB_GAP), 0.17 -- 알 탭 셋 다음(최고 장착 버튼 0.8 앞까지)
local LIST_ROW_H, LIST_ROW_GAP = 0.24, 0.008 -- 상품 목록(아래 칸 높이 0.63) 기준 — 본문 약 0.15(상점 로벅스 탭 줄과 같은 높이)
local STATUS_X = 0.64
local LEFT_W = 0.62
local RIGHT_X, RIGHT_W = 0.65, 0.35
local HEAD_Y, HEAD_H = 0.37, 0.06
local GRID_Y, GRID_H = 0.44, 0.56
local GRID_COLS = 4
local CELL_VH = 0.25 -- 격자 칸 높이(격자 보이는 높이 기준) — 4줄이 보인다
local CELL_GAP = 0.015
local SLOT_Y, SLOT_ROW_H, SLOT_COLS = 0.44, 0.075, 3
local SEL_NAME_Y, SEL_NAME_H = 0.61, 0.07
local SEL_INFO_Y, SEL_INFO_H = 0.68, 0.06
local EQUIP_Y, CRAFT_Y, RELEASE_Y, BTN_H = 0.75, 0.835, 0.92, 0.075
local SCROLLBAR_PX = 6 -- ScrollBarThickness는 픽셀 정수 속성이라 Scale로 줄 수 없다(docs/UI.md "지시서 #12")
PetWindow.Layout = { GRID_Y = GRID_Y, GRID_H = GRID_H, CELL_VH = CELL_VH, GRID_COLS = GRID_COLS }

export type Deps = {
	store: any?,
	sendRequest: (payload: { action: string, egg: number?, uid: string? }) -> (),
	purchase: PurchaseClient.Client?, -- 로벅스 상품 구매(지시서 #17). 생략하면 실물(PurchaseClient.get)
	onClose: () -> (),
	now: (() -> number)?,
}

type CellParts = { frame: Frame, name: TextLabel, level: TextLabel, stroke: UIStroke, hit: TextButton }
type TabParts = { button: Button.ButtonHandle, label: TextLabel, hit: TextButton }
type SlotParts = { frame: Frame, label: TextLabel, hit: TextButton }

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	onOpen: () -> (),
	_debug: {
		pressHatch: () -> (),
		pressHatch3: () -> (),
		pressRobuxTab: () -> (),
		robuxShown: () -> boolean,
		robux: RobuxList.Handle,
		robuxTab: Button.ButtonHandle,
		hatch3Button: Button.ButtonHandle,
		hatch3Label: TextLabel,
		pressTab: (index: number) -> (),
		pressBest: () -> (),
		select: (uid: string?) -> (),
		pressEquip: () -> (),
		pressCraft: () -> (),
		pressRelease: () -> (),
		selected: () -> string?,
		shownEgg: () -> number,
		grid: ScrollingFrame,
		cells: { CellParts },
		cellView: () -> { PetWindowLogic.Cell },
		slots: { SlotParts },
		tabs: { TabParts },
		odds: { TextLabel },
		hatchButton: Button.ButtonHandle,
		hatchLabel: TextLabel,
		hatchFoot: TextLabel,
		info: TextLabel,
		luck: TextLabel,
		storage: TextLabel,
		slotsText: TextLabel,
		selName: TextLabel,
		selInfo: TextLabel,
		equipButton: Button.ButtonHandle,
		equipLabel: TextLabel,
		craftButton: Button.ButtonHandle,
		craftLabel: TextLabel,
		releaseButton: Button.ButtonHandle,
		releaseLabel: TextLabel,
		status: TextLabel,
	},
}

function PetWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local purchase: PurchaseClient.Client = deps.purchase or PurchaseClient.get()
	local panel = Panel.create("Large", PetWindowLogic.TITLE)
	panel.root.Name = "PetWindow"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }

	local function makeButton(name: string, color: Button.ColorName, x: number, y: number, w: number, h: number, parent: Instance, text: string)
		local b = Button.create({ size = "Small", color = color, widthScale = w, heightScale = h })
		b.root.Name = name
		b.root.Position = UDim2.fromScale(x, y)
		b.root.ZIndex = WindowParts.Z_BUTTON
		b.root.Parent = parent
		local label, hit = WindowParts.decorateButton(b, text)
		table.insert(raise, b.root)
		return b, label, hit
	end

	-- 알 탭(아우라 창과 같은 방식 — 탭마다 회색 위에 하늘 한 벌을 겹쳐 두고 고른 탭만 켠다)
	local tabs: { TabParts } = {}
	local tabBlue: { Button.ButtonHandle } = {}
	for i = 1, MAX_TABS do
		local x = (i - 1) * (TAB_W + TAB_GAP)
		local gray, label, hit = makeButton("Tab" .. i, "gray", x, 0, TAB_W, TAB_H, body, "")
		local blue = Button.create({ size = "Small", color = "blue", widthScale = 1, heightScale = 1 })
		blue.root.Name = "Selected"
		blue.root.Position = UDim2.fromScale(0, 0)
		blue.root.ZIndex = WindowParts.Z_BUTTON
		blue.root.Visible = false
		blue.root.Parent = gray.root
		tabs[i] = { button = gray, label = label, hit = hit }
		tabBlue[i] = blue
	end
	local _bestBtn, _bestLabel, bestHit = makeButton("BestButton", "gray", 1 - BEST_W, 0, BEST_W, TAB_H, body, PetWindowLogic.BEST_TEXT)
	local robuxTab, _robuxTabLabel, robuxTabHit = makeButton("RobuxTab", "green", ROBUX_TAB_X, 0, ROBUX_TAB_W, TAB_H, body,
		RobuxShopLogic.ROBUX_TAB_TEXT)

	local info = WindowParts.makeText("Info", body, "small", 0, INFO_Y, 0.62, INFO_H)
	local luck = WindowParts.makeText("LuckLine", body, "small", 0.62, INFO_Y, 0.38, INFO_H, Enum.TextXAlignment.Right)
	local odds: { TextLabel } = {}
	for i = 1, PetConfig.TIER_COUNT do
		odds[i] = WindowParts.makeText("Odds" .. i, body, "small", (i - 1) * 0.25, ODDS_Y, 0.245, ODDS_H, Enum.TextXAlignment.Center)
	end

	local hatchButton, hatchLabel, hatchHit = makeButton("HatchButton", "blue", 0, HATCH_Y, HATCH_W, HATCH_H, body, PetWindowLogic.HATCH_TEXT)
	local hatch3Button, hatch3Label, hatch3Hit = makeButton("Hatch3Button", "blue", HATCH3_X, HATCH_Y, HATCH3_W, HATCH_H, body, "")
	local hatchFoot = WindowParts.makeText("HatchFoot", body, "small", HATCH_FOOT_X, HATCH_Y, HATCH_FOOT_W, HATCH_H, Enum.TextXAlignment.Center)
	hatchFoot.TextWrapped = true
	local status = WindowParts.makeText("Status", body, "small", STATUS_X, HATCH_Y, 1 - STATUS_X, HATCH_H, Enum.TextXAlignment.Center)
	status.TextWrapped = true

	-- 왼쪽: 보유 격자
	local storage = WindowParts.makeText("Storage", body, "small", 0, HEAD_Y, LEFT_W, HEAD_H)
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromScale(0, GRID_Y)
	grid.Size = UDim2.fromScale(LEFT_W, GRID_H)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = SCROLLBAR_PX
	grid.CanvasSize = UDim2.fromScale(0, 1)
	grid.ZIndex = 3
	grid.Parent = body

	local cells: { CellParts } = {}
	-- 칸은 필요할 때 만들고 지우지 않는다(풀 — 보유가 줄면 숨긴다). 반복 루프의 Instance.new가 아니다(보유 수만큼 한 번씩).
	local function ensureCell(i: number): CellParts
		local c = cells[i]
		if c ~= nil then
			return c
		end
		local frame = Instance.new("Frame")
		frame.Name = "Cell" .. i
		frame.BackgroundColor3 = UiTheme.Colors.neutral.dark
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = grid
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = UiTheme.Colors.cashout.base
		stroke.Enabled = false
		stroke.Parent = frame
		local name = WindowParts.makeText("Name", frame, "small", 0.04, 0.05, 0.92, 0.5, Enum.TextXAlignment.Center)
		local level = WindowParts.makeText("Level", frame, "small", 0.04, 0.55, 0.92, 0.4, Enum.TextXAlignment.Center)
		local hit = WindowParts.hitArea(frame)
		c = { frame = frame, name = name, level = level, stroke = stroke, hit = hit }
		cells[i] = c
		return c
	end

	-- 오른쪽: 장착 슬롯 · 고른 펫
	local slotsText = WindowParts.makeText("SlotsText", body, "small", RIGHT_X, HEAD_Y, RIGHT_W, HEAD_H)
	local slotParts: { SlotParts } = {}
	local slotW = RIGHT_W / SLOT_COLS
	for i = 1, PetConfig.MaxSlots do
		local col = (i - 1) % SLOT_COLS
		local row = math.floor((i - 1) / SLOT_COLS)
		local frame = Instance.new("Frame")
		frame.Name = "Slot" .. i
		frame.Position = UDim2.fromScale(RIGHT_X + col * slotW, SLOT_Y + row * SLOT_ROW_H)
		frame.Size = UDim2.fromScale(slotW * 0.95, SLOT_ROW_H * 0.9)
		frame.BackgroundColor3 = UiTheme.Colors.neutral.dark
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = body
		local label = WindowParts.makeText("Label", frame, "small", 0.03, 0.05, 0.94, 0.9, Enum.TextXAlignment.Center)
		local hit = WindowParts.hitArea(frame)
		slotParts[i] = { frame = frame, label = label, hit = hit }
	end
	local selName = WindowParts.makeText("SelName", body, "medium", RIGHT_X, SEL_NAME_Y, RIGHT_W, SEL_NAME_H, Enum.TextXAlignment.Center)
	local selInfo = WindowParts.makeText("SelInfo", body, "small", RIGHT_X, SEL_INFO_Y, RIGHT_W, SEL_INFO_H, Enum.TextXAlignment.Center)
	local equipButton, equipLabel, equipHit = makeButton("EquipButton", "blue", RIGHT_X, EQUIP_Y, RIGHT_W, BTN_H, body, PetWindowLogic.EQUIP_TEXT)
	local craftButton, craftLabel, craftHit = makeButton("CraftButton", "blue", RIGHT_X, CRAFT_Y, RIGHT_W, BTN_H, body, PetWindowLogic.CRAFT_TEXT)
	local releaseButton, releaseLabel, releaseHit = makeButton("ReleaseButton", "gray", RIGHT_X, RELEASE_Y, RIGHT_W, BTN_H, body, PetWindowLogic.RELEASE_TEXT)

	-- 상품 목록(아래 칸 자리 — 로벅스 탭을 골랐을 때만, 지시서 #17)
	local resultText: string? = nil
	local robux = RobuxList.create({
		name = "RobuxList",
		parent = body,
		position = UDim2.fromScale(0, HEAD_Y),
		size = UDim2.fromScale(1, 1 - HEAD_Y),
		rowH = LIST_ROW_H,
		rowGap = LIST_ROW_GAP,
		maxRows = #RobuxShopLogic.WINDOW_PRODUCTS.pet,
		raise = raise,
		purchase = purchase,
		onPressed = function()
			resultText = nil
		end,
	})
	robux.list.Visible = false
	local robuxShown = false
	-- 로벅스 탭을 고르면 숨기는 아래 칸(격자 · 장착 · 고른 펫). 슬롯 칸은 원래 표시(파생 슬롯 수만큼)를 render가 정하므로
	-- 로벅스 탭일 때 숨기기만 한다(돌아오면 render가 다시 켠다)
	local lower: { GuiObject } = { storage, grid, slotsText, selName, selInfo, equipButton.root, craftButton.root, releaseButton.root }

	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local pending = TitleWindowLogic.newPending()
	local hatchCooldownUntil = -math.huge
	local cellView: { PetWindowLogic.Cell } = {}
	local tabView: { PetWindowLogic.EggTab } = {}
	local shownEgg: number? = nil -- 세션 안 선택(저장하지 않는다 — 스키마를 늘리지 않는다)
	local selected: string? = nil
	local releaseFlow = ConfirmFlow.new(PetWindowLogic.RELEASE_CONFIRM_SEC)

	local function egg(): number
		return shownEgg or PetWindowLogic.defaultEgg(source.get("pets"), source.get("lifetimeBlox"))
	end

	local function render()
		local t = now()
		local summary = source.get("pets")
		local eggId = egg()
		tabView = PetWindowLogic.eggs(summary, source.get("lifetimeBlox"))
		for i, parts in ipairs(tabs) do
			local tab = tabView[i]
			parts.button.root.Visible = tab ~= nil
			tabBlue[i].root.Visible = tab ~= nil and tab.eggId == eggId
			if tab ~= nil then
				parts.label.Text = tab.label
				if tab.eggId == eggId then
					info.Text = tab.infoText
				end
			end
		end
		luck.Text = PetWindowLogic.luckText(source.get("upgrades"), source.get("shop"))
		local oddView = PetWindowLogic.odds(eggId, source.get("upgrades"), source.get("shop"))
		for i, label in ipairs(odds) do
			local o = oddView[i]
			label.Text = if o ~= nil then o.text else ""
			if o ~= nil then
				label.TextColor3 = UiTheme.rarityColor(o.rarityTier)
			end
		end
		local hatch = PetWindowLogic.hatchState(summary, source.get("lifetimeBlox"), source.get("blox"), eggId)
		hatchLabel.Text = hatch.buttonText
		hatchButton.setDisabled(not hatch.canHatch or pending.isPending("hatch", t) or t < hatchCooldownUntil)
		hatchFoot.Text = hatch.footText
		local hatch3 = PetWindowLogic.hatch3State(summary, source.get("lifetimeBlox"), source.get("blox"), eggId, source.get("shop"))
		hatch3Label.Text = hatch3.buttonText
		hatch3Button.setDisabled(not hatch3.canHatch or pending.isPending("hatch3", t) or pending.isPending("hatch", t) or t < hatchCooldownUntil)
		-- 로벅스 탭(지시서 #17)
		robux.render(RobuxShopLogic.windowRows("pet", source.get("shop"), { upgrades = source.get("upgrades"), pets = summary,
			lifetimeBlox = source.get("lifetimeBlox") }))
		robux.list.Visible = robuxShown

		-- 격자
		storage.Text = PetWindowLogic.storageText(summary)
		cellView = PetWindowLogic.grid(summary)
		local rows = math.ceil(#cellView / GRID_COLS)
		local k = math.max(1, rows * CELL_VH) -- 캔버스 높이(보이는 높이 배수). 자식 Scale은 캔버스 기준이다
		grid.CanvasSize = UDim2.fromScale(0, k)
		local cellW = (1 - CELL_GAP * (GRID_COLS - 1)) / GRID_COLS
		for i, c in ipairs(cellView) do
			local parts = ensureCell(i)
			local col = (i - 1) % GRID_COLS
			local row = math.floor((i - 1) / GRID_COLS)
			parts.frame.Position = UDim2.fromScale(col * (cellW + CELL_GAP), row * CELL_VH / k)
			parts.frame.Size = UDim2.fromScale(cellW, (CELL_VH - CELL_GAP) / k)
			parts.frame.Visible = true
			parts.name.Text = c.name
			parts.name.TextColor3 = UiTheme.rarityColor(c.rarityTier)
			parts.level.Text = if c.equipped then c.levelName .. PetWindowLogic.EQUIPPED_SUFFIX_TEXT else c.levelName
			parts.stroke.Enabled = c.uid == selected
		end
		for i = #cellView + 1, #cells do
			cells[i].frame.Visible = false
		end

		-- 장착 슬롯
		slotsText.Text = PetWindowLogic.slotsText(summary)
		local slotView = PetWindowLogic.slots(summary)
		for i, parts in ipairs(slotParts) do
			local s = slotView[i]
			parts.frame.Visible = s ~= nil
			if s ~= nil then
				parts.label.Text = s.text
				parts.label.TextColor3 = if s.rarityTier ~= nil then UiTheme.rarityColor(s.rarityTier) else UiTheme.Colors.neutral.base
			end
		end

		-- 고른 펫
		-- 고른 uid가 지금 보유에 없으면(놓아줬거나 재료로 쓰였거나 — 또는 부화 · 크래프팅 결과가 PlayerState보다 먼저 왔다)
		-- "고르지 않음"으로 보인다. 고른 값은 지우지 않는다 — 결과 펫이 곧 PlayerState로 들어오면 그대로 고른 상태가 된다.
		local d = PetWindowLogic.detail(summary, selected)
		if d == nil then
			releaseFlow.cancel()
		end
		selName.Text = if d ~= nil then d.name else PetWindowLogic.NO_SELECTION_TEXT
		selName.TextColor3 = if d ~= nil then UiTheme.rarityColor(d.rarityTier) else Color3.new(1, 1, 1)
		selInfo.Text = if d ~= nil then (if d.releaseFoot ~= "" and releaseFlow.isArmed(t) then d.releaseFoot else d.infoText) else ""
		equipLabel.Text = if d ~= nil then d.equipText else PetWindowLogic.EQUIP_TEXT
		equipButton.setDisabled(d == nil or not d.canEquip or pending.isPending("equip", t) or pending.isPending("unequip", t))
		craftLabel.Text = if d ~= nil then d.craftText else PetWindowLogic.CRAFT_TEXT
		craftButton.setDisabled(d == nil or not d.canCraft or pending.isPending("craft", t))
		releaseLabel.Text = if d ~= nil and releaseFlow.isArmed(t) then PetWindowLogic.RELEASE_CONFIRM_TEXT else PetWindowLogic.RELEASE_TEXT
		releaseButton.setDisabled(d == nil or not d.canRelease or pending.isPending("release", t))
		status.Text = resultText or ""
		for _, g in ipairs(lower) do
			g.Visible = not robuxShown
		end
		if robuxShown then
			for _, s in ipairs(slotParts) do
				s.frame.Visible = false
			end
		end
	end

	local function send(key: string, payload: { action: string, egg: number?, uid: string? })
		if not pending.tryBegin(key, now()) then
			return
		end
		resultText = nil
		deps.sendRequest(payload)
		render()
		task.delay(TitleWindowLogic.PENDING_TIMEOUT_SEC + 0.05, render)
	end

	local function pressHatch()
		render()
		local eggId = egg()
		if not PetWindowLogic.hatchState(source.get("pets"), source.get("lifetimeBlox"), source.get("blox"), eggId).canHatch or now() < hatchCooldownUntil then
			return
		end
		send("hatch", { action = "hatch", egg = eggId })
	end

	local function pressHatch3()
		render()
		local eggId = egg()
		if not PetWindowLogic.hatch3State(source.get("pets"), source.get("lifetimeBlox"), source.get("blox"), eggId, source.get("shop")).canHatch
			or now() < hatchCooldownUntil then
			return
		end
		send("hatch3", { action = "hatch3", egg = eggId })
	end

	local function pressRobuxTab()
		robuxShown = not robuxShown
		resultText = nil
		render()
	end

	local function pressTab(index: number)
		if robuxShown then
			robuxShown = false -- 알 탭을 누르면 아래 칸으로 돌아온다
			render()
		end
		local tab = tabView[index]
		if tab == nil or tab.eggId == egg() then
			return
		end
		shownEgg = tab.eggId
		resultText = nil
		render()
	end

	local function pressBest()
		send("equipBest", { action = "equipBest" })
	end

	local function select(uid: string?)
		if uid ~= selected then
			releaseFlow.cancel()
		end
		selected = uid
		render()
	end

	local function pressEquip()
		render()
		local d = PetWindowLogic.detail(source.get("pets"), selected)
		if d == nil or not d.canEquip then
			return
		end
		if d.equipped then
			send("unequip", { action = "unequip", uid = d.uid })
		else
			send("equip", { action = "equip", uid = d.uid })
		end
	end

	local function pressCraft()
		render()
		local d = PetWindowLogic.detail(source.get("pets"), selected)
		if d ~= nil and d.canCraft then
			send("craft", { action = "craft", uid = d.uid })
		end
	end

	local function pressRelease()
		render()
		local d = PetWindowLogic.detail(source.get("pets"), selected)
		local action = releaseFlow.press(now(), d ~= nil and d.canRelease and not pending.isPending("release", now()))
		if action == "send" and d ~= nil then
			send("release", { action = "release", uid = d.uid })
		else
			render()
			if action == "askConfirm" then
				task.delay(PetWindowLogic.RELEASE_CONFIRM_SEC + 0.05, render) -- 확인 시간이 지나면 글자를 되돌린다
			end
		end
	end

	local function onResult(payload: any)
		local key = PetWindowLogic.pendingKeyOf(payload)
		if key == nil then
			return
		end
		pending.finish(key)
		if key == "hatch" or key == "hatch3" then
			hatchCooldownUntil = now() + PetConfig.HATCH_INTERVAL_SEC
			task.delay(PetConfig.HATCH_INTERVAL_SEC + 0.05, render)
		end
		if payload.ok and (key == "hatch" or key == "hatch3" or key == "craft") and type(payload.uid) == "string" and payload.uid ~= "" then
			selected = payload.uid -- 새로 생긴 펫을 고른다(PlayerState가 곧 그 펫을 실어 온다)
			releaseFlow.cancel()
		end
		resultText = PetWindowLogic.resultText(payload)
		render()
	end

	local function onOpen()
		resultText = nil
		releaseFlow.cancel()
		render()
	end

	for i, parts in ipairs(tabs) do
		parts.hit.Activated:Connect(function()
			pressTab(i)
		end)
	end
	-- 격자 칸은 지연 생성이라 연결도 생성 때 — ensureCell을 감싸 한 번만 잇는다
	local connected: { [number]: boolean } = {}
	local baseEnsure = ensureCell
	ensureCell = function(i: number): CellParts
		local c = baseEnsure(i)
		if not connected[i] then
			connected[i] = true
			c.hit.Activated:Connect(function()
				local v = cellView[i]
				if v ~= nil then
					select(v.uid)
				end
			end)
		end
		return c
	end
	for i, parts in ipairs(slotParts) do
		parts.hit.Activated:Connect(function()
			local s = PetWindowLogic.slots(source.get("pets"))[i]
			if s ~= nil and s.uid ~= nil then
				select(s.uid)
			end
		end)
	end
	hatchHit.Activated:Connect(pressHatch)
	hatch3Hit.Activated:Connect(pressHatch3)
	robuxTabHit.Activated:Connect(pressRobuxTab)
	purchase.onResult(function(payload)
		if robuxShown then
			resultText = RobuxShopLogic.resultText(payload)
		end
		render()
	end)
	bestHit.Activated:Connect(pressBest)
	equipHit.Activated:Connect(pressEquip)
	craftHit.Activated:Connect(pressCraft)
	releaseHit.Activated:Connect(pressRelease)
	closeHit.Activated:Connect(function()
		resultText = nil
		releaseFlow.cancel()
		render()
		deps.onClose()
	end)
	source.subscribe("pets", render)
	source.subscribe("upgrades", render)
	source.subscribe("shop", render) -- 행운 패스 · 행운 포션 → 현재 확률(지시서 #16)
	source.subscribe("blox", render)
	source.subscribe("lifetimeBlox", render)

	render()

	return {
		root = panel.root,
		refresh = render,
		onResult = onResult,
		onOpen = onOpen,
		_debug = {
			pressHatch = pressHatch,
			pressHatch3 = pressHatch3,
			pressRobuxTab = pressRobuxTab,
			robuxShown = function()
				return robuxShown
			end,
			robux = robux,
			robuxTab = robuxTab,
			hatch3Button = hatch3Button,
			hatch3Label = hatch3Label,
			pressTab = pressTab,
			pressBest = pressBest,
			select = select,
			pressEquip = pressEquip,
			pressCraft = pressCraft,
			pressRelease = pressRelease,
			selected = function()
				return selected
			end,
			shownEgg = egg,
			grid = grid,
			cells = cells,
			cellView = function()
				return cellView
			end,
			slots = slotParts,
			tabs = tabs,
			odds = odds,
			hatchButton = hatchButton,
			hatchLabel = hatchLabel,
			hatchFoot = hatchFoot,
			info = info,
			luck = luck,
			storage = storage,
			slotsText = slotsText,
			selName = selName,
			selInfo = selInfo,
			equipButton = equipButton,
			equipLabel = equipLabel,
			craftButton = craftButton,
			craftLabel = craftLabel,
			releaseButton = releaseButton,
			releaseLabel = releaseLabel,
			status = status,
		},
	}
end

return PetWindow

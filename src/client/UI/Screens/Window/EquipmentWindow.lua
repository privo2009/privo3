--!strict
-- 장비 창 (큰 창, Window 층 — 지시서 #34 · DESIGN 16장 "장비 화면"). ⚠️ 새 경제 플래그 뒤에서만 만든다(EconomyV2Boot).
--
-- 탭: 곡괭이 하나(칼은 EquipmentWindowLogic.KINDS에 종류가 늘면 탭이 늘 자리).
--   왼쪽  15칸 등급순 — 칸마다 이름(등급 색) · 보유 × · 별 · 강화 · 배수 · 장착 표시 · 없는 곡괭이는 실루엣(???)
--   오른쪽 고른 곡괭이 — 장착 · 강화(다음 비용 · 쓰일 광석 · 배수 바뀜) · 별 올리기(필요한 여벌 · 배수 바뀜) · 결과 글자
-- 판정은 전부 서버다(EquipmentService) — 요청(send)을 보내고 받은 상태를 그린다. 문장은 Strings 키 · AutoLocalize false · UiTheme.FONT.
-- 등급 색(UiTheme.EquipGrade)은 칸 테두리와 이름 글자에만(docs/UI.md "장비 등급 색"). 위치 · 크기는 Scale만.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots) -- 에셋 자리(#36 — 값이 있으면 그 그림 · 없으면 임시 도형)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Logic = require(script.Parent.Parent.Parent.Logic.EquipmentWindowLogic)

local EquipmentWindow = {}

local GRID_W = 0.6
local COLS = 5
local ROWS = 3
local DETAIL_X = 0.63
local DETAIL_W = 0.37
local SILHOUETTE = Color3.fromRGB(25, 25, 30)

export type Deps = {
	send: (payload: any) -> (),
	onClose: () -> (),
}

export type Handle = {
	root: Frame,
	set: (values: any) -> (),
	onEvent: (payload: any) -> (),
	select: (id: string) -> (),
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
	WindowParts.raiseButtons({ b.root })
	return b, label, hit
end

function EquipmentWindow.create(deps: Deps): Handle
	local panel = Panel.create("Large", Locale.t("equip.title"))
	panel.root.Name = "EquipmentWindow"
	panel.titleLabel.AutoLocalize = false
	local body = panel.body
	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons({ panel.closeButton.root })

	local values: any = { equipment = {}, equipped = "", ores = EconomyV2Logic.newInv() }
	local selected: string? = nil
	local message = ""

	-- 종류 탭(지금 곡괭이 하나)
	local tabB = button("Tab_pickaxe", body, "blue", 0, 0, 0.18, 0.08, Locale.t("equip.tab.pickaxe"))
	tabB.setPressed(true)

	-- ===== 15칸 =================================================================================
	local grid = frame("Grid", body, 0, 0.1, GRID_W, 0.9)
	local cellW, cellH = 1 / COLS, 1 / ROWS
	local cells: { any } = {}
	for i = 1, COLS * ROWS do
		local col, row = (i - 1) % COLS, (i - 1) // COLS
		local cell = frame("Cell" .. i, grid, col * cellW + 0.005, row * cellH + 0.01, cellW - 0.01, cellH - 0.02)
		cell.BackgroundTransparency = 0.15
		cell.BackgroundColor3 = UiTheme.Colors.neutral.dark
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = cell
		local badge = text("Equipped", cell, "small", 0.04, 0.02, 0.92, 0.2, Enum.TextXAlignment.Center)
		badge.TextColor3 = UiTheme.Colors.cashout.light
		local name = text("Name", cell, "small", 0.04, 0.22, 0.92, 0.26, Enum.TextXAlignment.Center)
		local info = text("Info", cell, "small", 0.04, 0.5, 0.92, 0.22, Enum.TextXAlignment.Center)
		local mult = text("Mult", cell, "small", 0.04, 0.74, 0.92, 0.22, Enum.TextXAlignment.Center)
		local hit = WindowParts.hitArea(cell)
		cells[i] = { root = cell, stroke = stroke, badge = badge, name = name, info = info, mult = mult, hit = hit, id = "" }
	end

	-- ===== 고른 곡괭이 ==============================================================================
	local detail = frame("Detail", body, DETAIL_X, 0.1, DETAIL_W, 0.9)
	local dName = text("Name", detail, "medium", 0, 0, 1, 0.09)
	local dOwned = text("Owned", detail, "small", 0, 0.1, 1, 0.06)
	local dMult = text("Mult", detail, "small", 0, 0.16, 1, 0.06)
	local equipB, _, equipHit = button("EquipButton", detail, "blue", 0, 0.24, 1, 0.1, Locale.t("equip.equip"))
	local enhText = text("EnhanceText", detail, "small", 0, 0.36, 1, 0.1)
	local enhMult = text("EnhanceMult", detail, "small", 0, 0.46, 1, 0.05)
	local enhB, _, enhHit = button("EnhanceButton", detail, "purple", 0, 0.52, 1, 0.1, Locale.t("equip.enhance"))
	local starText = text("StarText", detail, "small", 0, 0.64, 1, 0.08)
	local starMult = text("StarMult", detail, "small", 0, 0.72, 1, 0.05)
	local starB, _, starHit = button("StarButton", detail, "purple", 0, 0.78, 1, 0.1, Locale.t("equip.star"))
	local msg = text("Message", detail, "small", 0, 0.9, 1, 0.08, Enum.TextXAlignment.Center)
	for _, l in ipairs({ enhText, starText }) do
		l.TextWrapped = true
	end

	local function render()
		local list = Logic.cells(values.equipment or {}, values.equipped or "")
		if selected == nil then
			selected = values.equipped ~= "" and values.equipped or list[1].id
		end
		local cur = list[1]
		for i, c in ipairs(list) do
			local ui = cells[i]
			ui.id = c.id
			local color = UiTheme.equipGradeColor(c.rarity)
			ui.name.Text = Logic.nameOf(c)
			-- 곡괭이 아이콘(#36 — 가진 것만 · 없으면 실루엣 그대로)
			local visual = Config.PICKAXE_VISUALS[c.id]
			AssetSlots.applyImage(ui.root, if c.owned and visual ~= nil then visual.iconId else nil,
				{ position = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.6, 0.6) })
			if c.owned then
				ui.root.BackgroundColor3 = UiTheme.Colors.neutral.dark
				ui.stroke.Color = color -- 테두리(등급 색 예외)
				ui.name.TextColor3 = color -- 이름 글자(등급 색 예외)
				ui.info.Text = string.format("%s %s %s", Locale.t("equip.count", { n = tostring(c.count) }), Locale.t("equip.stars", { n = tostring(c.stars) }),
					Locale.t("equip.enh", { n = tostring(c.enh) }))
				ui.mult.Text = Locale.t("equip.mult", { mult = Logic.multText(c.mult) })
			else
				-- 실루엣(도감): 어두운 칸 · ??? · 숫자 없음
				ui.root.BackgroundColor3 = SILHOUETTE
				ui.stroke.Color = UiTheme.Colors.neutral.dark
				ui.name.TextColor3 = UiTheme.Colors.neutral.base
				ui.info.Text = ""
				ui.mult.Text = ""
			end
			ui.badge.Text = if c.equipped then Locale.t("equip.equipped") else ""
			ui.stroke.Thickness = if c.id == selected then 5 else 3
			if c.id == selected then
				cur = c
			end
		end
		-- 고른 곡괭이
		local color = UiTheme.equipGradeColor(cur.rarity)
		dName.Text = string.format("%s · %s", Locale.t("grade." .. cur.rarity), Logic.nameOf(cur))
		dName.TextColor3 = if cur.owned then color else UiTheme.Colors.neutral.base
		if not cur.owned then
			dOwned.Text = Locale.t("equip.notOwned")
			dMult.Text = ""
			enhText.Text, enhMult.Text, starText.Text, starMult.Text = "", "", "", ""
			equipB.setDisabled(true)
			enhB.setDisabled(true)
			starB.setDisabled(true)
		else
			dOwned.Text = Locale.t("equip.owned", { n = tostring(cur.count), spare = tostring(EconomyV2Logic.spareOf(cur.count)) })
			dMult.Text = Locale.t("equip.mult", { mult = Logic.multText(cur.mult) })
			equipB.setDisabled(cur.equipped)
			local ep = Logic.enhancePreview(cur, values.ores or EconomyV2Logic.newInv())
			enhText.Text, enhMult.Text = ep.text, ep.multText
			enhB.setDisabled(ep.canMax or ep.take == nil)
			local sp = Logic.starPreview(cur)
			starText.Text, starMult.Text = sp.text, sp.multText
			starB.setDisabled(not sp.can)
		end
		msg.Text = message
	end

	local function select(id: string)
		selected = id
		message = ""
		render()
	end

	for _, ui in ipairs(cells) do
		ui.hit.Activated:Connect(function()
			if ui.id ~= "" then
				select(ui.id)
			end
		end)
	end
	local function request(action: string, b: any)
		if selected ~= nil and not b.isDisabled() then
			deps.send({ action = action, id = selected })
		end
	end
	equipHit.Activated:Connect(function()
		request("equip", equipB)
	end)
	enhHit.Activated:Connect(function()
		request("enhance", enhB)
	end)
	starHit.Activated:Connect(function()
		request("star", starB)
	end)
	closeHit.Activated:Connect(function()
		deps.onClose()
	end)

	render()

	return {
		root = panel.root,
		set = function(v: any)
			values = v
			render()
		end,
		onEvent = function(payload: any)
			if type(payload) ~= "table" or payload.kind ~= "equipment_result" then
				return
			end
			if payload.ok == true then
				local def = EconomyV2Logic.pickaxe(payload.id)
				local name = if def ~= nil then Locale.t(def.nameKey) else ""
				message = Locale.t("equip.done." .. (if payload.action == "equip" or payload.action == "enhance" then payload.action else "star"),
					{ name = name })
			else
				message = Logic.reasonText(payload.reason)
			end
			render()
		end,
		select = select,
		_debug = {
			cells = cells,
			equipB = equipB,
			enhB = enhB,
			starB = starB,
			enhText = enhText,
			enhMult = enhMult,
			starText = starText,
			dName = dName,
			msg = msg,
		},
	}
end

return EquipmentWindow

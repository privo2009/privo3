--!strict
-- UI 키트 · 테마 · 미리보기 검증(2026-11-26 지시서 #39 7단계). Studio Play에서 클라 시작 때 자동 실행된다.
--   1. 테마 역할 이름(role · grade · rarity · text) · 모르는 이름은 오류
--   2. 스킨 기본값 = #39 이전 화면 코드에 흩어져 있던 숫자(모양이 안 바뀐다)
--   3. 스킨 덮기 · 되돌리기(제자리 — Colors 표 참조가 새 값을 본다)
--   4. 키트 부품(글자 · 칸 · 탭 · 게이지 · 토스트 · 확률 줄 · 재화 칸 · 모달 · 막 · 스킨 그림)
--   5. 틀 여백(Panel.layout) — 0이면 #39 이전 값과 같다 · 두꺼워지면 본문이 그만큼 안으로
--   6. 미리보기 플래그 게이트(TestGate.flagOn · 커밋 값 nil) · 창 전부 예시 데이터로 만들어진다
--   7. AssetSlots UI 칸 · 넘침 확인(Locale 늘이기)
-- ⚠️ 스킨을 바꾸는 검사는 같은 줄 흐름에서 바로 되돌린다(중간에 기다리지 않는다 — 다른 테스트가 같은 스킨을 읽는다).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local TestGate = require(ReplicatedStorage.Shared.TestGate)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Components = script.Parent.Parent.UI.Components
local Kit = require(Components.Kit)
local Panel = require(Components.Panel)
local Button = require(Components.Button)
local UiPreview = require(script.Parent.Parent.Tools.UiPreview)

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

-- 엔진 속성 · Vector2는 32비트 실수로 담긴다(0.15 → 0.150000006) — 1e-5 안이면 같은 값
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-5
end

-- 1. 테마 역할 이름 ------------------------------------------------------------------------------------
do
	check("역할: role.power = Colors.power.base", UiTheme.color("role.power") == UiTheme.Colors.power.base)
	check("역할: role.danger.light = Colors.danger.light", UiTheme.color("role.danger.light") == UiTheme.Colors.danger.light)
	check("역할: grade.epic = EquipGrade.epic(C1)", UiTheme.color("grade.epic") == UiTheme.EquipGrade.epic)
	check("역할: rarity 3단계 = Rarity.tier3", UiTheme.color("rarity." .. "tier3") == UiTheme.Rarity.tier3)
	check("역할: text.main 흰색 · text.stroke 검정", UiTheme.color("text.main") == Color3.new(1, 1, 1) and UiTheme.color("text.stroke") == Color3.new(0, 0, 0))
	local allRoles = true
	for role, entry in pairs(UiTheme.Colors) do
		for _, step in ipairs({ "light", "base", "dark" }) do
			allRoles = allRoles and UiTheme.color("role." .. role .. "." .. step) == (entry :: any)[step]
		end
	end
	check("역할: 8역할 × 3단계 전부 이름으로 읽힌다", allRoles)
	local ok1 = pcall(UiTheme.color, "role.nope")
	local ok2 = pcall(UiTheme.color, "grade")
	local ok3 = pcall(UiTheme.color, "colour.power")
	check("역할: 모르는 이름은 오류(오타를 흰색으로 그리지 않는다)", not ok1 and not ok2 and not ok3)
end

-- 2. 스킨 기본값 = #39 이전 숫자 ----------------------------------------------------------------------------
do
	local S = UiTheme.Skin
	check("스킨 기본: 글꼴 BuilderSansBold(F1) = UiTheme.FONT", S.font.Name == "BuilderSansBold" and UiTheme.FONT == S.font)
	check("스킨 기본: 테두리 asset 3 · modal 4 · notice 3 · band 2 · cell 2 · cellToday 4 · slot 3 · slotSelected 5",
		S.line.asset == 3 and S.line.modal == 4 and S.line.notice == 3 and S.line.band == 2 and S.line.cell == 2 and S.line.cellToday == 4
			and S.line.slot == 3 and S.line.slotSelected == 5)
	check("스킨 기본: 투명도 dim .45 · hatchDim .35 · band .15 · cell .15 · cellSoft .2 · row .3 · toast .1",
		near(S.alpha.dim, 0.45) and near(S.alpha.hatchDim, 0.35) and near(S.alpha.band, 0.15) and near(S.alpha.cell, 0.15)
			and near(S.alpha.cellSoft, 0.2) and near(S.alpha.row, 0.3) and near(S.alpha.toast, 0.1))
	check("스킨 기본: 둥글기 round 0.5 · cell 0.15", S.corner.round == UDim.new(0.5, 0) and S.corner.cell == UDim.new(0.15, 0))
	check("스킨 기본: 틀 여백 0.02 · 틀 두께 0 · 크기 (0.6, 0.7) · (0.85, 0.85)", near(S.panel.margin, 0.02) and S.panel.frameInset == 0
		and S.panel.small == Vector2.new(0.6, 0.7) and S.panel.large == Vector2.new(0.85, 0.85))
	check("스킨 기본: 버튼 높이 0.09 · 0.06 · 눌림 2px · 어둡게 0.8 (Button 상수와 같다)", near(S.button.heightBig, 0.09) and near(S.button.heightSmall, 0.06)
		and S.button.pressOffsetPx == 2 and near(S.button.pressDarken, 0.8) and Button.HEIGHT_BIG == S.button.heightBig and Button.HEIGHT_SMALL == S.button.heightSmall)
	check("스킨 기본: 바탕 silhouette (25,25,30) · egg (245,235,210) · shade 검정", S.fill.silhouette == Color3.fromRGB(25, 25, 30)
		and S.fill.egg == Color3.fromRGB(245, 235, 210) and S.fill.shade == Color3.new(0, 0, 0))
	check("스킨 기본: 색 표는 UiTheme.Colors · Rarity · EquipGrade 그 표(복사본 아님)", S.colors == UiTheme.Colors and S.rarity == UiTheme.Rarity
		and S.equipGrade == UiTheme.EquipGrade)
	check("스킨 기본: 그림 칸 없음(images 비어 있음 — 지금 모양)", next(S.images) == nil)
	check("스킨 파일(Config/UiSkin) 커밋 값 = 빈 표(기본 모양)", next(require(ReplicatedStorage.Shared.Config.UiSkin)) == nil)
end

-- 3. 스킨 덮기 · 되돌리기 ----------------------------------------------------------------------------------
do
	local before = UiTheme.Colors.power.base
	local red = Color3.fromRGB(200, 10, 10)
	-- 다른 글꼴 하나(목록에서 기본이 아닌 첫 항목 — 글꼴 이름을 코드에 쓰지 않는다: tools/check_fonts.py)
	local otherFont: Enum.Font = UiTheme.FONT
	for _, f in ipairs(Enum.Font:GetEnumItems()) do
		if f ~= UiTheme.FONT then
			otherFont = f :: any
			break
		end
	end
	UiTheme.applySkin({ font = otherFont, line = { modal = 9 }, colors = { power = { base = red } }, images = { card = { id = 123 } } })
	local applied = UiTheme.FONT == otherFont and otherFont.Name ~= "BuilderSansBold" and UiTheme.Skin.line.modal == 9 and UiTheme.Colors.power.base == red
		and UiTheme.color("role.power") == red and UiTheme.Skin.line.cell == 2 and UiTheme.Skin.images.card.id == 123
	UiTheme.resetSkin()
	check("스킨 덮기: 적은 칸만 바뀐다(글꼴 · 두께 · 색 — 같은 Colors 표가 새 값을 본다)", applied)
	check("스킨 되돌리기: 기본으로(글꼴 · 두께 · 색 · 그림 칸)", UiTheme.FONT.Name == "BuilderSansBold" and UiTheme.Skin.line.modal == 4
		and UiTheme.Colors.power.base == before and next(UiTheme.Skin.images) == nil)
	UiTheme.applySkin(nil)
	check("스킨 덮기: 표가 아니면 아무것도 안 한다", UiTheme.Skin.line.modal == 4)
end

-- 4. 키트 부품 --------------------------------------------------------------------------------------------
do
	local label = Instance.new("TextLabel")
	local stroke, size = Kit.styleText(label, "medium")
	check("styleText: 흰 글자 · 글꼴 · TextScaled", label.TextColor3 == Color3.new(1, 1, 1) and label.Font == UiTheme.FONT and label.TextScaled)
	check("styleText: 검은 외곽선(Contextual) · 크기 상한 = 단계 값", stroke.Color == Color3.new(0, 0, 0)
		and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and size.MaxTextSize == TextScale.Levels.medium.maxTextSize)
	label:Destroy()

	local holder = Instance.new("Frame")
	local card, cs = Kit.card("C", holder, 0.1, 0.2, 0.3, 0.4, { fill = UiTheme.Colors.neutral.dark, alpha = 0.15, line = 3,
		lineColor = Kit.gradeColor("epic"), lineMode = Enum.ApplyStrokeMode.Border, corner = "cell" }, 4)
	local s = cs :: UIStroke
	check("card: 자리 · 크기 · Z · 바탕", card.Position == UDim2.fromScale(0.1, 0.2) and card.Size == UDim2.fromScale(0.3, 0.4) and card.ZIndex == 4
		and card.BackgroundColor3 == UiTheme.Colors.neutral.dark and near(card.BackgroundTransparency, 0.15) and card.Parent == holder)
	check("card: 등급 테두리(두께 · 색 · Border) · 둥글기", s.Thickness == 3 and s.Color == UiTheme.EquipGrade.epic
		and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Border and (card:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius == UDim.new(0.15, 0))
	local plain, ps = Kit.card("P", holder, 0, 0, 1, 1, {})
	check("card: 스타일이 비면 투명 틀 · 테두리 없음", ps == nil and plain.BackgroundTransparency == 1 and plain:FindFirstChildOfClass("UIStroke") == nil)
	check("gradeColor: 모르는 등급은 common", Kit.gradeColor("nope") == UiTheme.EquipGrade.common)
	local okCorner = pcall(Kit.corner, holder, "nope")
	check("corner: 모르는 둥글기 이름은 오류", not okCorner)

	-- 스킨 그림: 없으면 안 깐다 · 있으면 9-slice 그림 + 바탕 투명
	check("skinImage: 그림 칸이 비면 nil(지금 모양)", Kit.skinImage(plain, "card") == nil and plain:FindFirstChild("SkinImage") == nil)
	UiTheme.applySkin({ images = { card = { id = 4242, slice = Rect.new(10, 10, 20, 20) } } })
	local styled = Kit.card("S", holder, 0, 0, 1, 1, { fill = UiTheme.Colors.neutral.dark, alpha = 0, image = "card" })
	UiTheme.resetSkin()
	local img = styled:FindFirstChild("SkinImage") :: ImageLabel?
	check("skinImage: 그림 칸이 있으면 9-slice 그림을 깔고 바탕을 비운다", img ~= nil and img.Image == "rbxassetid://4242"
		and img.ScaleType == Enum.ScaleType.Slice and img.SliceCenter == Rect.new(10, 10, 20, 20) and styled.BackgroundTransparency == 1)

	local tab = Kit.tab("T", holder, 0, 0, 0.2, 0.1, "Tab")
	local hidden = tab.selected.root.Visible == false
	tab.setSelected(true)
	local shown = tab.selected.root.Visible
	tab.setSelected(false)
	check("tab: 회색 버튼 위 하늘 한 벌 · setSelected로 켜고 끈다", hidden and shown and not tab.selected.root.Visible
		and tab.selected.root.Parent == tab.button.root and tab.label.Text == "Tab" and tab.hit:IsA("TextButton"))

	local g = Kit.gauge("G", holder, 0, 0.5, 1, 0.1, { anchor = Vector2.new(0, 0.5) })
	g.set(0.25)
	local quarter = g.fill.Size == UDim2.fromScale(0.25, 1)
	g.set(2)
	local over = g.fill.Size == UDim2.fromScale(1, 1)
	g.set(-1)
	check("gauge: 비율 · 0~1로 자른다 · 기본색(neutral.dark · power.base)", quarter and over and g.fill.Size == UDim2.fromScale(0, 1)
		and g.root.BackgroundColor3 == UiTheme.Colors.neutral.dark and g.fill.BackgroundColor3 == UiTheme.Colors.power.base
		and g.root.AnchorPoint == Vector2.new(0, 0.5))

	local toast = Kit.toastRow("Toast", "small")
	check("toastRow: 어두운 바탕(.1) · 오른쪽 정렬 · 흰 글자 외곽선", toast.BackgroundColor3 == UiTheme.Colors.neutral.dark
		and near(toast.BackgroundTransparency, 0.1) and toast.TextXAlignment == Enum.TextXAlignment.Right
		and toast:FindFirstChildOfClass("UIStroke") ~= nil)
	toast:Destroy()

	local n1, p1 = Kit.oddsRow(holder, 2, 0.1, 0.68)
	check("oddsRow: 이름 왼쪽 · 확률 오른쪽 정렬 · 줄 자리", n1.Position == UDim2.fromScale(0, 0.1) and p1.Position == UDim2.fromScale(0.68, 0.1)
		and p1.TextXAlignment == Enum.TextXAlignment.Right and near(n1.Size.Y.Scale, 0.095))

	local row = Instance.new("Frame")
	local chip = Kit.currencyChip(row, { color = Color3.fromRGB(255, 200, 0), iconId = nil, level = "small" })
	check("currencyChip: 둥근 아이콘(색 원) + 숫자 칸", chip.icon.Parent == row and chip.value.label.Parent == row
		and (chip.icon:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius == UDim.new(0.5, 0) and chip.icon.BackgroundTransparency == 0)
	row:Destroy()

	local panel, ms = Kit.modalPanel("M", holder, 0.5, 0.4, 20, { lineColor = UiTheme.Colors.cashout.base })
	check("modalPanel: 가운데 · 숨김 · 테두리 modal(4) · 색", panel.AnchorPoint == Vector2.new(0.5, 0.5) and not panel.Visible and ms.Thickness == 4
		and ms.Color == UiTheme.Colors.cashout.base and panel.ZIndex == 20)
	local dim = Kit.dim("D", holder)
	check("dim: 입력을 막는 막(.45 · 버튼 색 반응 없음)", dim:IsA("TextButton") and near(dim.BackgroundTransparency, 0.45) and dim.AutoButtonColor == false
		and dim.Text == "")
	holder:Destroy()
end

-- 5. 틀 여백(Panel.layout) ---------------------------------------------------------------------------------
do
	-- #39 이전 Panel.create의 식(heightFractionToRootScale · widthFractionToRootScaleX · Y)을 그대로 다시 계산해 비교한다
	local ASPECT = 1920 / 1080
	local allSame = true
	for _, size in ipairs({ "Small", "Large" }) do
		local dims = if size == "Small" then Vector2.new(0.6, 0.7) else Vector2.new(0.85, 0.85)
		local mx, my = 0.02 / dims.X, (0.02 * ASPECT) / dims.Y
		local th = TextScale.Levels.large.heightFraction / dims.Y
		local r = Panel.layout(size :: any, 0)
		allSame = allSame and r.titlePos == Vector2.new(0.5, my) and r.titleSize == Vector2.new(1 - mx * 2, th)
			and r.closePos == Vector2.new(1 - mx, my) and r.bodyPos == Vector2.new(mx, th + my * 2)
			and r.bodySize == Vector2.new(1 - mx * 2, 1 - th - my * 3) and r.closeHeight == Button.HEIGHT_SMALL / dims.Y
	end
	check("틀 여백 0: 제목 · X · 본문 자리가 #39 이전 식과 똑같다(Small · Large)", allSame)

	local base = Panel.layout("Large", 0)
	local thick = Panel.layout("Large", 0.03)
	check("틀 여백 0.03: 본문이 위 · 왼쪽으로 들어가고 그만큼 작아진다", thick.bodyPos.X > base.bodyPos.X and thick.bodyPos.Y > base.bodyPos.Y
		and near(base.bodySize.X - thick.bodySize.X, thick.insetX * 2) and near(base.bodySize.Y - thick.bodySize.Y, thick.insetY * 2))
	check("틀 여백 0.03: 제목은 아래로 · X는 안으로(틀 그림 위에 올라가지 않는다)", thick.titlePos.Y > base.titlePos.Y and thick.closePos.X < base.closePos.X
		and near(thick.closePos.X, 1 - thick.insetX - thick.marginX))
	check("틀 여백 0.03: 본문이 틀 안쪽(가장자리에서 두께 이상 떨어진다)", thick.bodyPos.X >= thick.insetX and thick.bodyPos.Y >= thick.insetY
		and thick.bodyPos.X + thick.bodySize.X <= 1 - thick.insetX + 1e-5 and thick.bodyPos.Y + thick.bodySize.Y <= 1 - thick.insetY + 1e-5)
	check("틀 여백: 두께는 같은 px(가로 환산 = 세로 ÷ 기준 화면비)", near(thick.insetX * 0.85 * ASPECT, thick.insetY * 0.85))

	UiTheme.applySkin({ panel = { frameInset = 0.03 } })
	local p = Panel.create("Large", "x")
	UiTheme.resetSkin()
	check("틀 여백: Panel.create가 스킨 두께를 뺀다", p.body.Position == UDim2.fromScale(thick.bodyPos.X, thick.bodyPos.Y)
		and p.body.Size == UDim2.fromScale(thick.bodySize.X, thick.bodySize.Y))
	p.root:Destroy()
end

-- 6. 미리보기 플래그 게이트 · 창 만들기 ------------------------------------------------------------------------
do
	check("flagOn: nil · false면 Studio여도 꺼짐", not TestGate.flagOn(nil, true) and not TestGate.flagOn(false, true))
	check("flagOn: 켰어도 Studio가 아니면 꺼짐 · Studio면 켜짐", not TestGate.flagOn(true, false) and TestGate.flagOn(true, true))
	check("미리보기: Studio가 아니면 돌지 않는다(게시 빌드)", not UiPreview.shouldRun(true, false))
	check("미리보기: WindowBoot TEST_UI_PREVIEW 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)",
		UiPreview.isRegistered() and UiPreview.getRequested() == nil, tostring(UiPreview.getRequested()))
	check("커밋 검사 도구 목록에 TEST_UI_PREVIEW(TestGate.STUDIO_FLAGS)", table.find(TestGate.STUDIO_FLAGS, "TEST_UI_PREVIEW") ~= nil)

	local gui = Instance.new("ScreenGui")
	local bad = {}
	for _, name in ipairs(UiPreview.WINDOWS) do
		local ok, built = pcall(UiPreview.build, name, UiPreview.sampleStore(), gui)
		if not ok or built == nil then
			table.insert(bad, name .. ":" .. tostring(built))
		else
			(built :: any).root:Destroy()
		end
	end
	gui:Destroy()
	check("미리보기: 목록의 창 전부 예시 데이터로 만들어진다(요청 없음)", #bad == 0, table.concat(bad, " · "))

	local econ = UiPreview.sampleEconomy()
	local grades: { [string]: boolean } = {}
	local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
	for _, def in ipairs(EconomyV2Config.PICKAXES) do
		if econ.equipment[def.id] ~= nil then
			grades[def.rarity] = true
		end
	end
	check("미리보기 예시: 곡괭이 등급 5종이 다 있다(common · rare · epic · mythic · legendary)", grades.common and grades.rare and grades.epic
		and grades.mythic and grades.legendary or false)
end

-- 7. AssetSlots UI 칸 · 넘침 확인 ---------------------------------------------------------------------------
do
	local list = AssetSlots.uiList()
	local regCount = 0
	for _ in pairs(AssetRegistry.Entries) do
		regCount += 1
	end
	local seen: { [string]: boolean } = {}
	local ui, kit, dup, noIdOk = 0, 0, false, true
	for _, slot in ipairs(list) do
		dup = dup or seen[slot.key] == true
		seen[slot.key] = true
		if string.sub(slot.key, 1, 3) == "ui_" then
			ui += 1
			local arrived = AssetRegistry.resolve(string.sub(slot.key, 4)).arrived
			noIdOk = noIdOk and ((slot.id ~= nil) == arrived)
		elseif string.sub(slot.key, 1, 4) == "kit_" then
			kit += 1
			noIdOk = noIdOk and slot.id == nil and type(slot.use) == "string"
		end
	end
	check("UI 칸: AssetRegistry 전부(ui_) + 키트 그림 칸 전부(kit_) · 키 중복 없음", ui == regCount and kit == #AssetSlots.KIT_IMAGE_SLOTS and not dup
		and #list == regCount + #AssetSlots.KIT_IMAGE_SLOTS)
	check("UI 칸: 값이 없으면 id nil(지금 모양) · 도착한 것만 id", noIdOk)
	check("UI 칸: 키트 그림 칸 목록 = KitBase(키트가 쓰는 목록)", Kit.IMAGE_SLOTS == AssetSlots.KIT_IMAGE_SLOTS)

	local normal = Locale.t("forge.title")
	Locale._setStretch(true)
	local long = Locale.t("forge.title")
	Locale._setStretch(false)
	check("넘침 확인: 늘이기를 켜면 문장이 두 배 · 끄면 그대로", long == normal .. " " .. normal and Locale.t("forge.title") == normal
		and not Locale._isStretched())
end

print(string.format("[UiKitTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UiKitTests] %d test(s) failed", failed))
end

--!strict
-- MenuRail 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-2b 착수 준비.

local Layout = require(script.Parent.Parent.UI.Layout)
local BloxDisplay = require(script.Parent.Parent.UI.Screens.Hud.BloxDisplay)
local MenuRail = require(script.Parent.Parent.UI.Screens.Hud.MenuRail)

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

-- HudBoot.client.lua와 같은 방식으로 BloxDisplay 아래에 이어 붙인다
-- (숫자를 새로 정하지 않고 그 파일의 여백 값 0.02를 그대로 재현한다).
local MENU_RAIL_TOP_GAP = 0.02

local bloxDisplay = BloxDisplay.create()
local _, _, _, bloxDisplayBottom = Layout.getBounds(bloxDisplay.root)
local menuRail = MenuRail.create(bloxDisplayBottom + MENU_RAIL_TOP_GAP)

-- 1. 6개가 생성된다 (개수를 하드코딩하지 않고 MenuRail.Items와 대조) -----------------------

do
	local expectedCount = #MenuRail.Items
	check("MenuRail.Items가 비어있지 않다(전제 확인)", expectedCount > 0)

	local found = 0
	for _, item in ipairs(MenuRail.Items) do
		local itemRow = menuRail.root:FindFirstChild(item.screenName)
		if itemRow ~= nil then
			found += 1
		end
	end
	check(
		string.format("MenuRail.Items 목록(%d개)이 전부 생성된다", expectedCount),
		found == expectedCount,
		string.format("found=%d", found)
	)
end

-- 2. 좌측 레일 20% 폭 안에 들어간다 --------------------------------------------------

do
	local x0, _, x1, _ = Layout.getBounds(menuRail.root)
	check("MenuRail이 좌측 레일(20%) 안에 있다", x0 >= 0 and x1 <= Layout.RAIL_WIDTH, string.format("x0=%.4f x1=%.4f", x0, x1))
end

-- 3. 세로 합계가 화면 높이를 넘지 않는다 -----------------------------------------------

do
	local _, y0, _, y1 = Layout.getBounds(menuRail.root)
	check("MenuRail 세로 합계가 화면 높이(1.0)를 넘지 않는다", y1 <= 1.0, string.format("y0=%.4f y1=%.4f", y0, y1))
end

-- 4. BloxDisplay 영역과 겹치지 않는다 -------------------------------------------------

do
	local _, _, _, bloxY1 = Layout.getBounds(bloxDisplay.root)
	local _, menuY0, _, _ = Layout.getBounds(menuRail.root)
	check(
		"MenuRail이 BloxDisplay 아래에서 시작해 겹치지 않는다",
		menuY0 >= bloxY1,
		string.format("bloxY1=%.4f menuY0=%.4f", bloxY1, menuY0)
	)
end

-- 5. 각 타일에 UIAspectRatioConstraint가 있다, 6. 라벨이 전부 있고 한글 2~4자다 --------------

for _, item in ipairs(MenuRail.Items) do
	local itemRow = menuRail.root:FindFirstChild(item.screenName)
	check(string.format("'%s' 항목이 있다", item.screenName), itemRow ~= nil)
	if itemRow then
		local tile = itemRow:FindFirstChild("Tile")
		check(string.format("'%s' 타일이 있다", item.screenName), tile ~= nil)
		if tile then
			local aspect = tile:FindFirstChildOfClass("UIAspectRatioConstraint")
			check(string.format("'%s' 타일에 UIAspectRatioConstraint가 있다", item.screenName), aspect ~= nil)
			if aspect then
				check(
					string.format("'%s' 타일이 정사각형이다(AspectRatio == 1)", item.screenName),
					(aspect :: UIAspectRatioConstraint).AspectRatio == 1
				)
			end
		end

		local label = itemRow:FindFirstChild("Label") :: TextLabel?
		check(string.format("'%s' 라벨이 있다", item.screenName), label ~= nil)
		if label then
			local charCount = utf8.len(label.Text) or 0
			check(
				string.format("'%s' 라벨('%s')이 한글 2~4자다", item.screenName, label.Text),
				charCount >= 2 and charCount <= 4,
				tostring(charCount)
			)
		end
	end
end

-- 7. 중앙 금지 구역을 침범하지 않는다 -------------------------------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(menuRail.root)
	check(
		"MenuRail이 중앙 금지 구역을 침범하지 않는다",
		not Layout.overlapsCenterForbidden(x0, y0, x1, y1),
		string.format("x0=%.4f y0=%.4f x1=%.4f y1=%.4f", x0, y0, x1, y1)
	)
end

-- 8. Offset을 쓰지 않는다 (허용 예외 없음 — MenuRail은 전부 Scale) ----------------------

do
	check("root Size.X.Offset == 0", menuRail.root.Size.X.Offset == 0)
	check("root Size.Y.Offset == 0", menuRail.root.Size.Y.Offset == 0)
	check("root Position.X.Offset == 0", menuRail.root.Position.X.Offset == 0)
	check("root Position.Y.Offset == 0", menuRail.root.Position.Y.Offset == 0)

	for _, item in ipairs(MenuRail.Items) do
		local itemRow = menuRail.root:FindFirstChild(item.screenName)
		if itemRow then
			check(
				string.format("'%s' Size.X.Offset == 0", item.screenName),
				(itemRow :: Frame).Size.X.Offset == 0
			)
			check(
				string.format("'%s' Size.Y.Offset == 0", item.screenName),
				(itemRow :: Frame).Size.Y.Offset == 0
			)
		end
	end
end

print(string.format("[MenuRailTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[MenuRailTests] %d test(s) failed", failed))
end

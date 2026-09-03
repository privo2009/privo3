--!strict
-- ShopSlots 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-6 착수 준비.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopSlotConfig = require(ReplicatedStorage.Shared.Config.ShopSlotConfig)
local Layout = require(script.Parent.Parent.UI.Layout)
local ShopSlots = require(script.Parent.Parent.UI.Screens.Hud.ShopSlots)
local TestHelpers = require(script.Parent.TestHelpers)
local checkClose = TestHelpers.checkClose

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

local handle = ShopSlots.create()

-- 1. Config 4종이 전부 렌더된다 (개수를 하드코딩하지 않고 ShopSlotConfig와 대조) -------

do
	local slots = ShopSlotConfig.TEMP_SLOTS
	check("ShopSlotConfig.TEMP_SLOTS가 4개다(전제 확인)", #slots == 4)

	local found = 0
	for _, slot in ipairs(slots) do
		if handle.root:FindFirstChild(slot.key) ~= nil then
			found += 1
		end
	end
	check(string.format("구좌 %d개가 전부 생성된다", #slots), found == #slots, string.format("found=%d", found))
end

-- 2. 타일이 8% 정사각이다 --------------------------------------------------------------

for _, slot in ipairs(ShopSlotConfig.TEMP_SLOTS) do
	local tile = handle.root:FindFirstChild(slot.key) :: Frame?
	check(string.format("'%s' 타일이 있다", slot.key), tile ~= nil)
	if tile then
		local aspect = tile:FindFirstChildOfClass("UIAspectRatioConstraint")
		check(string.format("'%s' 타일에 UIAspectRatioConstraint가 있다", slot.key), aspect ~= nil)
		if aspect then
			check(
				string.format("'%s' 타일이 정사각형이다(AspectRatio == 1)", slot.key),
				(aspect :: UIAspectRatioConstraint).AspectRatio == 1
			)
		end

		local price = tile:FindFirstChild("Price") :: TextLabel?
		check(string.format("'%s' 가격 라벨이 있다", slot.key), price ~= nil)
		if price then
			check(
				string.format("'%s' 가격 라벨에 가격(%d)이 들어간다", slot.key, slot.priceRobux),
				string.find(price.Text, tostring(slot.priceRobux), 1, true) ~= nil,
				price.Text
			)
		end
	end
end

-- 3. 2행 2열 배치다 (행마다 Y가 같고, 열마다 X가 다르다) --------------------------------

do
	local slots = ShopSlotConfig.TEMP_SLOTS
	local columns = 2
	local rows = math.ceil(#slots / columns)

	for row = 1, rows do
		local leftIndex = (row - 1) * columns + 1
		local rightIndex = leftIndex + 1
		local leftSlot = slots[leftIndex]
		local rightSlot = slots[rightIndex]

		if leftSlot and rightSlot then
			local leftTile = handle.root:FindFirstChild(leftSlot.key) :: Frame
			local rightTile = handle.root:FindFirstChild(rightSlot.key) :: Frame

			if leftTile and rightTile then
				local leftX0, leftY0 = Layout.getBounds(leftTile)
				local rightX0, rightY0 = Layout.getBounds(rightTile)

				check(
					string.format("%d행: 두 타일의 Y가 같다(같은 행)", row),
					checkClose(leftY0, rightY0)
				)
				check(
					string.format("%d행: 왼쪽 타일의 X가 오른쪽보다 작다", row),
					leftX0 < rightX0,
					string.format("left=%.4f right=%.4f", leftX0, rightX0)
				)
			end
		end
	end
end

-- 4. 하단 띠(Y 0.75~1.00) 안, 하단 여백 미침범 -----------------------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	check(
		"ShopSlots 상단이 하단 띠(75%) 안쪽이다",
		y0 >= (1 - Layout.BOTTOM_HEIGHT),
		string.format("y0=%.6f 하단띠상단=%.6f", y0, 1 - Layout.BOTTOM_HEIGHT)
	)
	check(
		"ShopSlots 하단이 하단 여백 경계와 정확히 같다(그 이상 내려가지 않는다)",
		checkClose(y1, 1 - Layout.BOTTOM_MARGIN_HEIGHT)
	)
end

-- 5. 우측 레일(20%) 안에 있고 중앙 금지 구역을 침범하지 않는다 -------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	check(
		"ShopSlots가 우측 레일(20%) 안에 있다",
		x0 >= 1 - Layout.RAIL_WIDTH,
		string.format("x0=%.4f 레일시작=%.4f", x0, 1 - Layout.RAIL_WIDTH)
	)
	check(
		"ShopSlots가 중앙 금지 구역을 침범하지 않는다",
		not Layout.overlapsCenterForbidden(x0, y0, x1, y1),
		string.format("x0=%.4f y0=%.4f x1=%.4f y1=%.4f", x0, y0, x1, y1)
	)
end

-- 6. Offset을 쓰지 않는다 (허용 예외 없음) ----------------------------------------------

do
	check("root Size.X.Offset == 0", handle.root.Size.X.Offset == 0)
	check("root Size.Y.Offset == 0", handle.root.Size.Y.Offset == 0)
	check("root Position.X.Offset == 0", handle.root.Position.X.Offset == 0)
	check("root Position.Y.Offset == 0", handle.root.Position.Y.Offset == 0)
end

print(string.format("[ShopSlotsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ShopSlotsTests] %d test(s) failed", failed))
end

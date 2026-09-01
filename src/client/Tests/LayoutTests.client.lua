--!strict
-- Layout 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-2 착수 준비.

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

-- 1. 구역 값이 docs/UI.md "2. 세이프존 > 구역 비율" 초안과 일치한다 -----------------------

check("RAIL_WIDTH == 0.20", Layout.RAIL_WIDTH == 0.20)
check("TOP_HEIGHT == 0.15", Layout.TOP_HEIGHT == 0.15)
check("BOTTOM_HEIGHT == 0.25", Layout.BOTTOM_HEIGHT == 0.25)
check("EDGE_MARGIN == 0.03", Layout.EDGE_MARGIN == 0.03)

check("CenterForbidden.left == RAIL_WIDTH", Layout.CenterForbidden.left == Layout.RAIL_WIDTH)
check("CenterForbidden.right == 1 - RAIL_WIDTH", Layout.CenterForbidden.right == 1 - Layout.RAIL_WIDTH)
check("CenterForbidden.top == TOP_HEIGHT", Layout.CenterForbidden.top == Layout.TOP_HEIGHT)
check("CenterForbidden.bottom == 1 - BOTTOM_HEIGHT", Layout.CenterForbidden.bottom == 1 - Layout.BOTTOM_HEIGHT)

-- 2. 중앙 금지 판정 헬퍼가 경계에서 올바르게 동작한다 -----------------------------------

-- 완전히 중앙 금지 구역 안에 있는 사각형 (0.5,0.5 부근 아주 작은 박스).
check(
	"중앙 한가운데 작은 박스는 침범이다",
	Layout.overlapsCenterForbidden(0.49, 0.49, 0.51, 0.51)
)

-- 완전히 좌측 레일 안에 있는 사각형 (중앙 금지 밖).
check(
	"좌측 레일 안의 박스는 침범이 아니다",
	not Layout.overlapsCenterForbidden(0.0, 0.4, 0.1, 0.5)
)

-- 좌측 레일 폭(0.20)에 정확히 맞춘 박스 — 경계에 닿을 뿐 넘지 않는다.
check(
	"레일 폭에 정확히 맞춘 박스는 침범이 아니다(경계는 겹침이 아니다)",
	not Layout.overlapsCenterForbidden(0.0, 0.4, Layout.RAIL_WIDTH, 0.5)
)

-- 레일 폭을 아주 조금이라도 넘으면 침범이다.
check(
	"레일 폭을 살짝 넘긴 박스는 침범이다",
	Layout.overlapsCenterForbidden(0.0, 0.4, Layout.RAIL_WIDTH + 0.001, 0.5)
)

-- 상단 정보 높이(0.15)에 정확히 맞춘 박스 — 경계에 닿을 뿐 넘지 않는다.
check(
	"상단 정보 높이에 정확히 맞춘 박스는 침범이 아니다",
	not Layout.overlapsCenterForbidden(0.4, 0.0, 0.5, Layout.TOP_HEIGHT)
)

check(
	"상단 정보 높이를 살짝 넘긴 박스는 침범이다",
	Layout.overlapsCenterForbidden(0.4, 0.0, 0.5, Layout.TOP_HEIGHT + 0.001)
)

-- 화면 전체를 덮는 박스는 당연히 침범이다.
check("화면 전체 박스는 침범이다", Layout.overlapsCenterForbidden(0, 0, 1, 1))

-- 3. getBounds: AnchorPoint를 반영해 경계를 구한다 -------------------------------------

do
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromScale(0.5, 0.1)
	frame.Size = UDim2.fromScale(0.2, 0.05)

	local x0, y0, x1, y1 = Layout.getBounds(frame)
	check("getBounds: x0 == 0.4 (AnchorPoint.X 보정)", math.abs(x0 - 0.4) < 1e-9, tostring(x0))
	check("getBounds: x1 == 0.6", math.abs(x1 - 0.6) < 1e-9, tostring(x1))
	check("getBounds: y0 == 0.1 (AnchorPoint.Y == 0이라 보정 없음)", math.abs(y0 - 0.1) < 1e-9, tostring(y0))
	check("getBounds: y1 == 0.15", math.abs(y1 - 0.15) < 1e-9, tostring(y1))
end

-- 4. getTopInset이 숫자를 돌려준다 (기기별 실측값이라 부호·정확한 값은 검증하지 않는다) ---

check("getTopInset()이 number를 돌려준다", type(Layout.getTopInset()) == "number")

print(string.format("[LayoutTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LayoutTests] %d test(s) failed", failed))
end

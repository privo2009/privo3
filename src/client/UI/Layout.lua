--!strict
-- 세이프존 구역 골격. 문서 원본은 docs/UI.md "2. 세이프존"이다.
--
-- ⚠️ 이 값들은 초안이다. docs/UI.md가 "레퍼런스 기준 초안. G4 더미 HUD에서
-- 실측 후 확정한다"고 명시한다 — 나중에 이 숫자를 확정값으로 오해하지 말 것.
--
-- ⚠️ UiTheme이 색에 대해 그랬듯, 실행 가능한 코드가 필요해 여기로 옮겨왔다.
-- 값을 고칠 때는 반드시 docs/UI.md "2. 세이프존"과 이 파일을 함께 고친다.

local GuiService = game:GetService("GuiService")

local Layout = {}

-- 구역 비율 (docs/UI.md "2. 세이프존 > 구역 비율")
Layout.RAIL_WIDTH = 0.20 -- 좌측/우측 레일 폭
Layout.TOP_HEIGHT = 0.15 -- 상단 정보 높이
Layout.BOTTOM_HEIGHT = 0.25 -- 하단 띠 높이
Layout.EDGE_MARGIN = 0.03 -- 가장자리 여백 (화면 폭 대비, docs/UI.md "2. 세이프존 > 규칙")

-- 중앙 금지 구역: 좌/우 레일과 상/하단 띠를 제외한 나머지 (docs/UI.md "2. 세이프존").
export type Rect = { left: number, top: number, right: number, bottom: number }

local CENTER_FORBIDDEN: Rect = {
	left = Layout.RAIL_WIDTH,
	top = Layout.TOP_HEIGHT,
	right = 1 - Layout.RAIL_WIDTH,
	bottom = 1 - Layout.BOTTOM_HEIGHT,
}

Layout.CenterForbidden = CENTER_FORBIDDEN

-- [x0,x1] x [y0,y1] (화면 기준 Scale 좌표)가 중앙 금지 구역과 겹치는지 판정한다.
-- 경계는 겹침이 아니다 — 레일이 정확히 20%에서 끝나는 것은 침범이 아니라 정상이다
-- (닫힌 구간끼리 맞닿는 것을 겹침으로 치면 레일 폭 그대로 쓰는 요소가 전부 걸린다).
function Layout.overlapsCenterForbidden(x0: number, y0: number, x1: number, y1: number): boolean
	local overlapsX = x0 < CENTER_FORBIDDEN.right and x1 > CENTER_FORBIDDEN.left
	local overlapsY = y0 < CENTER_FORBIDDEN.bottom and y1 > CENTER_FORBIDDEN.top
	return overlapsX and overlapsY
end

-- GuiObject의 AnchorPoint/Position/Size에서 화면 기준 경계 사각형을 구한다.
-- ⚠️ Scale 성분만 본다. Offset 성분(발판 인셋 보정, 버튼 눌림 등 이 프로젝트가 이미
-- 허용한 픽셀 예외들)은 "이 요소가 개념적으로 어느 구역에 속하는가"를 바꾸지 않는
-- 미세 보정이라는 것이 이 프로젝트의 입장이다 — 그래서 구역 판정에서는 뺀다.
function Layout.getBounds(frame: GuiObject): (number, number, number, number)
	local width = frame.Size.X.Scale
	local height = frame.Size.Y.Scale
	local x0 = frame.Position.X.Scale - frame.AnchorPoint.X * width
	local y0 = frame.Position.Y.Scale - frame.AnchorPoint.Y * height
	return x0, y0, x0 + width, y0 + height
end

-- 로블록스 기본 UI(상단바)가 차지하는 픽셀 높이. HudGui는 IgnoreGuiInset = true라서
-- (x, 0) 좌표가 실제 화면 맨 위와 겹치므로, 화면 맨 위에 붙는 HUD 요소는 이만큼
-- 아래로 내려야 기본 UI와 겹치지 않는다. 기기·화면 크기마다 다르므로(모바일 노치 등)
-- 상수로 박지 않고 매번 조회한다. Position의 Offset 성분에만 쓴다 — Rect.new
-- SliceCenter · UIStroke.Thickness · Button 눌림 오프셋과 같은 성격의 픽셀 예외다.
function Layout.getTopInset(): number
	local topLeftInset = GuiService:GetGuiInset()
	return topLeftInset.Y
end

return Layout

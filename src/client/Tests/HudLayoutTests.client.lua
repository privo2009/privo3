--!strict
-- HUD 레이아웃 테스트 (U3-3). Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동
-- 실행된다. 실제로 렌더된 HudGui(PlayerGui에 붙은 진짜 HUD)를 대상으로 한다 —
-- MenuRailTests처럼 분리된 인스턴스(Layout.getBounds로 Scale만 보는 것)가 아니라
-- HudVisibilityTests와 같은 종류의 실물 검증이다. AbsoluteSize/AbsolutePosition은
-- PlayerGui에 실제로 붙어 렌더된 인스턴스에서만 유효하기 때문이다.
--
-- ===== U3-2 관측(1차·2차)에서 이미 실물로 확인된 원인 둘 (docs/PENDING.md 참고) ==========
--
--   1. UIAspectRatioConstraint의 AspectType 기본값은 FitWithinMaxSize다.
--      DominantAxis는 AspectType=ScaleWithParentSize일 때만 동작하는데, 이 저장소
--      어디서도 AspectType을 세팅하지 않는다 — "Size.X=0 + DominantAxis=Height로
--      렌더 시점에 폭을 역산" 관례(BloxDisplay.lua:54,64 / ChallengeInfo.lua:93 /
--      MenuRail.lua:91, 셋 다 손으로 재구현한 같은 관례)가 **처음부터 성립한 적이
--      없다.** FitWithinMaxSize는 Size 자체를 "이 상자 안에 비율 유지하며 넣어라"로
--      읽어서 상자 폭(Size.X)이 0이면 결과가 0x0이 된다. 영향받는 9개:
--      BloxDisplay/Icon, BloxDisplay/Value, ChallengeInfo/Timer,
--      MenuRail/{Shop,Rebirth,Drone,Aura,Pet,Settings}/Tile. (Drone은 2026-10-21 Warp로 바뀜)
--   2. 세 ScreenGui(Hud/Window/Overlay)가 전부 IgnoreGuiInset=true인데
--      (ScreenController.lua createScreenGui), GetGuiInset() topLeft=(0,58)만큼의
--      인셋을 아무도 빼주고 있지 않다. BloxDisplay·ChallengeInfo 계열이 로블록스
--      topbar 아래(AbsPos.Y가 음수)로 들어간다.
--
-- **그래서 이 테스트는 지금 red가 정상이다.** 위 9개 + 상단 인셋을 침범하는 요소들이
-- fail로 뜨지 않으면 오히려 이 테스트가 뭔가를 놓치고 있다는 뜻이다. green이 나오면
-- 테스트를 고쳐야 한다는 신호이지, HUD가 고쳐졌다는 신호가 아니다 — 수정 자체는
-- U3-4에서 한다. 이 파일은 HUD 배치 코드(Layout / BloxDisplay / ChallengeInfo /
-- MenuRail / HudBoot / AssetImage / ValuePanel / ScreenController)를 절대 고치지
-- 않는다. 읽기만 한다.
--
-- ===== 검사 2의 기준선 (U3-4B 마무리 — 이전 버전의 오해를 정정) ==========================
--
-- ⚠️ **이전 버전은 "IgnoreGuiInset이 고쳐지면 이 검사는 저절로 통과한다"고 적었는데
-- 틀린 서술이었다.** AbsolutePosition은 GUI 인셋을 포함하지 않는다 — IgnoreGuiInset=
-- false인 ScreenGui의 좌표계는 이미 topbar 아래에서 시작하므로(엔진이 원점을 인셋만큼
-- 대신 내려준다) AbsPos.Y=0은 "화면 맨 위"가 아니라 "사용 가능 영역 맨 위"다. 그
-- 상태에서 기준선을 여전히 GetGuiInset().topLeft.Y(58)로 두면 인셋을 두 번 빼는
-- 것이 된다 — 실제로 U3-4B 직후 Play에서 이 버그를 밟았다(BloxDisplay AbsPos.Y=0인데
-- "0 < 58"로 fail). **좌표계 원점이 IgnoreGuiInset에 따라 함께 움직이므로 기준선도
-- 같이 바뀌어야 한다** — 코드를 안 고쳐도 저절로 맞는 것이 아니다.
--
-- 그래서 기준선 계산 자체를 `HudLayoutGate.computeUsableBounds()`로 옮겼다(게이트의
-- computeExpectedSize와 같은 IgnoreGuiInset 판단을 쓰므로, 같은 판단이 이 파일과
-- HudLayoutReport 양쪽에 흩어져 한쪽만 고쳐지는 사고를 막는다). true면
-- GetGuiInset().topLeft/viewportSize-bottomRight가 기준선이고, false면 0/
-- viewportSize-topLeft-bottomRight가 기준선이다.
--
-- ⚠️ 기준선이 0이어도 이 검사는 여전히 유효하다 — 느슨해진 것이 아니다. AbsPos.Y가
-- 음수인 요소는 사용 가능 영역 위로 삐져나간 것이고, Position에 음수 Scale을 넣거나
-- AnchorPoint를 잘못 잡으면 실제로 발생할 수 있는 실패다.
--
-- ⚠️ CLAUDE.md의 "UI 크기·위치에 Offset 사용 금지"와 충돌하지 않는다. 그 금지는
-- **레이아웃 값**(요소를 배치하는 Position/Size)에 대한 것이고, 여기서 쓰는 픽셀은
-- **검사값**(기준선을 얼마나 침범했는지 재는 값)이다. GetGuiInset()은 애초에
-- 픽셀로만 돌아오므로 여기서 픽셀 산술을 쓰는 것은 그 규칙 위반이 아니다 — 다음
-- 세션에 이 파일을 보고 위반으로 오독하지 않도록 여기 못박아 둔다.

local RunService = game:GetService("RunService")

local ScreenController = require(script.Parent.Parent.UI.ScreenController)
local Layout = require(script.Parent.Parent.UI.Layout)
local HudLayoutGate = require(script.Parent.Parent.Tools.HudLayoutGate)
local MenuRail = require(script.Parent.Parent.UI.Screens.Hud.MenuRail)
local PowerBlock = require(script.Parent.Parent.UI.Screens.Hud.PowerBlock)
local ShopSlots = require(script.Parent.Parent.UI.Screens.Hud.ShopSlots)
local AutoTools = require(script.Parent.Parent.UI.Screens.Hud.AutoTools)
local TouchSafeLayout = require(script.Parent.Parent.UI.TouchSafeLayout)
local TextScale = require(game:GetService("ReplicatedStorage").Shared.Config.TextScale)

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

local function finish()
	print(string.format("[HudLayoutTests] %d passed, %d failed", passed, failed))
	if failed > 0 then
		error(string.format("[HudLayoutTests] %d test(s) failed", failed))
	end
end

type ElementRecord = {
	path: string,
	instance: GuiObject,
	parent: Instance,
	absPos: Vector2,
	absSize: Vector2,
}

-- HudGui 아래 GuiObject를 전부 훑는다. Visible=false인 요소와 그 자손은 제외한다 —
-- "실제로 화면에 나타나야 하는 것"만 재는 것이 목적이라, 숨겨진 가지는 재귀 자체를
-- 하지 않는다(자손이 우연히 Visible=true여도 부모가 숨겨지면 화면엔 안 보인다).
local function collect(node: Instance, path: string, records: { ElementRecord })
	for _, child in ipairs(node:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			local childPath = path .. "/" .. child.Name
			table.insert(records, {
				path = childPath,
				instance = child,
				parent = node,
				absPos = child.AbsolutePosition,
				absSize = child.AbsoluteSize,
			})
			collect(child, childPath, records)
		end
	end
end

-- 검사 1 실패 메시지: 값이 안 찍히는 실패 로그는 이 프로젝트에서 이미 한 턴을
-- 태웠다(float32 오진 → TestHelpers.checkClose가 항상 실측값을 돌려주게 된 경위,
-- TestHelpers.lua 상단). 같은 규약을 따라 AbsSize·Size·(있으면) AspectType/
-- DominantAxis를 항상 함께 남긴다.
local function formatSizeDetail(rec: ElementRecord): string
	local size = rec.instance.Size
	local detail = string.format(
		"AbsSize=(%d,%d) Size=[scale %.4f,%.4f offset %d,%d]",
		rec.absSize.X,
		rec.absSize.Y,
		size.X.Scale,
		size.Y.Scale,
		size.X.Offset,
		size.Y.Offset
	)

	local aspect = rec.instance:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint?
	if aspect ~= nil then
		detail = detail .. string.format(" AspectType=%s DominantAxis=%s", tostring(aspect.AspectType), tostring(aspect.DominantAxis))
	end

	return detail
end

local function rectIntersection(aPos: Vector2, aSize: Vector2, bPos: Vector2, bSize: Vector2): (number, number)
	local ax0, ay0 = aPos.X, aPos.Y
	local ax1, ay1 = ax0 + aSize.X, ay0 + aSize.Y
	local bx0, by0 = bPos.X, bPos.Y
	local bx1, by1 = bx0 + bSize.X, by0 + bSize.Y

	local ix0, iy0 = math.max(ax0, bx0), math.max(ay0, by0)
	local ix1, iy1 = math.min(ax1, bx1), math.min(ay1, by1)
	return math.max(0, ix1 - ix0), math.max(0, iy1 - iy0)
end

-- 검사 3: 같은 부모를 가진 형제 GuiObject 쌍의 사각형이 교차하면 fail. 예외 둘:
--
--   (a) 퇴화 교차 — 교차 폭 또는 높이가 반올림해서 0px. floor 임계로 판정한다
--       (정확히 0인 경우와, 부동소수 잔여로 미세하게 남는 sub-pixel 잔여를 함께
--       거른다). 2차 관측의 Pet/Label <-> Pet/HitArea "267x0px"가 이 케이스였다.
--   (b) HitArea류 — MenuRail 항목 전체를 덮는 투명 탭 버튼(MenuRail.lua의
--       createTile, hitArea)이라 겹치는 것 자체가 의도다.
--
--       ⚠️ 판별 근거는 이름("HitArea")이다. 한계: 이름이 바뀌거나, 다른 화면이
--       다른 이름의 "항목 전체를 덮는 버튼"을 쓰면 이 예외가 못 잡는다 — 그러면
--       그 버튼이 형제와 겹치는 게 이 검사에 다시 fail로 걸린다(오탐이 아니라
--       놓치는 방향의 한계). Attribute 같은 구조적 표식이 이름보다 튼튼하지만
--       그러려면 MenuRail.lua를 고쳐야 해서 이번(U3-3, 관측 전용) 범위 밖이다.
local function checkOverlaps(records: { ElementRecord })
	local groups: { [Instance]: { ElementRecord } } = {}
	for _, rec in ipairs(records) do
		local list = groups[rec.parent]
		if list == nil then
			list = {}
			groups[rec.parent] = list
		end
		table.insert(list, rec)
	end

	for _, siblings in pairs(groups) do
		for i = 1, #siblings do
			for j = i + 1, #siblings do
				local a, b = siblings[i], siblings[j]

				if a.instance.Name == "HitArea" or b.instance.Name == "HitArea" then
					continue
				end

				local iw, ih = rectIntersection(a.absPos, a.absSize, b.absPos, b.absSize)
				local realOverlap = math.floor(iw) >= 1 and math.floor(ih) >= 1

				check(
					string.format("'%s' <-> '%s' 겹치지 않는다", a.path, b.path),
					not realOverlap,
					string.format("교차 %.2fx%.2fpx", iw, ih)
				)
			end
		end
	end
end

-- 검사 4 — MenuRail 격자 배치 (U3-4C 후속). 실제 렌더 결과를 잰다는 점에서 검사
-- 1/2/3과 성격이 같다 - MenuRailTests(컴포넌트 단위, 독립 인스턴스)에 있던 자리가
-- 틀렸던 이유가 바로 이것이다: UIGridLayout은 자식 Size는 CellSize로 덮어쓰지만
-- Position은 건드리지 않는다(0으로 남는다) - 독립 인스턴스든 렌더 트리든 마찬가지라
-- Position 기반 검증은 애초에 이 파일(HudLayoutTests)에서도 안 통했을 것이다.
-- 여기서는 Position이 아니라 AbsolutePosition/AbsoluteSize를 쓴다 - 이건 실제 렌더
-- 결과이고, 검사 1/2/3이 이미 그렇게 하고 있다.
--
-- 행 구성은 MenuRail.Columns/MenuRail.Items에서 유도한다. 2를 여기 하드코딩하지
-- 않는다 - 나중에 열 수가 바뀌어도 이 검사가 따라간다.
local function checkMenuRailGrid()
	-- ⚠️ "잴 수 없었다"를 green으로 처리하지 않는다(이 세션에서 이미 정한 규약,
	-- 게이트 실패 처리와 같은 이유). MenuRail이 HudGui 아래 register+open돼 있지
	-- 않으면(HudBoot이 안 띄운 상태) 명시적으로 fail시키고 나머지는 생략한다.
	local entry = ScreenController._debug.entries["MenuRail"]
	local menuRailRoot = if entry ~= nil then entry.instance else nil

	local isRendered = menuRailRoot ~= nil and menuRailRoot:IsDescendantOf(ScreenController._debug.guis.Hud)
	check("MenuRail이 HudGui 아래 register+open돼 실물로 있다(격자 검증 전제)", isRendered)

	if not isRendered or menuRailRoot == nil then
		return
	end

	local columns = MenuRail.Columns
	local rows = math.ceil(#MenuRail.Items / columns)

	-- 셀 폭 수준 판정 기준. 1px 오차 같은 것으로 통과시키지 않기 위해 최소 반 칸
	-- 폭 이상 벌어져야 "다른 열"로 인정한다. 상수로 박지 않고 실측 AbsoluteSize에서
	-- 매번 유도한다 - Scale 상수를 여기서 다시 계산해 옮기면 MenuRail.lua와 두 곳이
	-- 어긋날 위험이 생긴다.
	local minColumnGapPx = menuRailRoot.AbsoluteSize.X / columns / 2

	for row = 1, rows do
		local leftIndex = (row - 1) * columns + 1
		local rightIndex = leftIndex + 1
		local leftItem = MenuRail.Items[leftIndex]
		local rightItem = MenuRail.Items[rightIndex]

		if leftItem == nil or rightItem == nil then
			continue
		end

		local leftRow = menuRailRoot:FindFirstChild(leftItem.screenName) :: GuiObject?
		local rightRow = menuRailRoot:FindFirstChild(rightItem.screenName) :: GuiObject?

		check(string.format("'%s' 항목이 실물에 있다(격자 검증 전제)", leftItem.screenName), leftRow ~= nil)
		check(string.format("'%s' 항목이 실물에 있다(격자 검증 전제)", rightItem.screenName), rightRow ~= nil)

		if leftRow == nil or rightRow == nil then
			continue
		end

		local leftPos, rightPos = leftRow.AbsolutePosition, rightRow.AbsolutePosition
		local posDetail = string.format(
			"'%s'=(%d,%d) '%s'=(%d,%d)",
			leftItem.screenName,
			leftPos.X,
			leftPos.Y,
			rightItem.screenName,
			rightPos.X,
			rightPos.Y
		)

		check(
			string.format("%d행: '%s'와 '%s'가 같은 AbsolutePosition.Y를 갖는다", row, leftItem.screenName, rightItem.screenName),
			leftPos.Y == rightPos.Y,
			posDetail
		)
		check(
			string.format("%d행: '%s'(1열)의 AbsolutePosition.X가 '%s'(2열)보다 작다", row, leftItem.screenName, rightItem.screenName),
			leftPos.X < rightPos.X,
			posDetail
		)
		check(
			string.format(
				"%d행: '%s'와 '%s'의 AbsolutePosition.X 차이가 셀 폭 수준이다(>=%dpx)",
				row,
				leftItem.screenName,
				rightItem.screenName,
				minColumnGapPx
			),
			(rightPos.X - leftPos.X) >= minColumnGapPx,
			string.format("%s 차이=%dpx 기준=%dpx", posDetail, rightPos.X - leftPos.X, minColumnGapPx)
		)
	end
end

-- 검사 7 — 항목 칸 안의 자식은 그 칸 안에 있다 (2026-10-21, U3-10b) ----------------
--
-- MenuRail 항목과 AutoTools 항목은 "칸(itemRow) 하나 = 타일/아이콘 + 라벨 + (HitArea)"다.
-- 칸 안쪽 배치가 UIListLayout이던 시절 HitArea가 리스트에 끼어 타일·라벨을 칸 높이만큼
-- 아래로 밀었는데, 검사 3(같은 부모 형제끼리)은 형제가 함께 밀려서 못 잡았고 검사 4는
-- 칸 자체(itemRow)의 자리만 봐서 못 잡았다. 여기서는 칸의 직계 자식이 칸 사각형 안에
-- 있는지 본다. 허용치 1px — sub-pixel 반올림만 거른다.
local function checkItemChildrenInsideCell(records: { ElementRecord })
	local cellParents: { [Instance]: boolean } = {}
	for _, name in ipairs({ "MenuRail", "AutoTools" }) do
		local entry = ScreenController._debug.entries[name]
		local root = if entry ~= nil then entry.instance else nil
		check(string.format("%s가 실물로 있다(검사 7 전제)", name), root ~= nil)
		if root ~= nil then
			for _, cell in ipairs(root:GetChildren()) do
				if cell:IsA("GuiObject") then
					cellParents[cell] = true
				end
			end
		end
	end

	for _, rec in ipairs(records) do
		local cell = rec.parent
		if cellParents[cell] and cell:IsA("GuiObject") then
			local cx0, cy0 = cell.AbsolutePosition.X, cell.AbsolutePosition.Y
			local cx1, cy1 = cx0 + cell.AbsoluteSize.X, cy0 + cell.AbsoluteSize.Y
			local x0, y0 = rec.absPos.X, rec.absPos.Y
			local x1, y1 = x0 + rec.absSize.X, y0 + rec.absSize.Y
			check(
				string.format("'%s'가 자기 칸 안에 있다", rec.path),
				x0 >= cx0 - 1 and y0 >= cy0 - 1 and x1 <= cx1 + 1 and y1 <= cy1 + 1,
				string.format("자식=(%d,%d)-(%d,%d) 칸=(%d,%d)-(%d,%d)", x0, y0, x1, y1, cx0, cy0, cx1, cy1)
			)
		end
	end
end

-- 검사 8 — 서로 다른 HUD 컴포넌트의 요소끼리 겹치지 않는다 (2026-10-21, U3-10b) --------
--
-- 검사 3은 같은 부모의 형제끼리만 비교한다. 2026-09-04에 AutoTools 아이콘이 ShopSlots
-- 타일과 실제로 겹쳤는데 부모가 달라 쌍으로 잡히지 않았다(docs/PENDING.md U3 진행 상태).
-- 여기서는 HudGui 직계 자식(컴포넌트)이 다른 요소 쌍을 화면 좌표로 전부 비교한다.
-- 예외는 검사 3과 같다 — HitArea(항목 전체를 덮는 탭 버튼)와 퇴화 교차(0px).
local function checkCrossComponentOverlaps(hud: Instance, records: { ElementRecord })
	local function componentOf(inst: Instance): Instance?
		local node: Instance? = inst
		while node ~= nil and node.Parent ~= hud do
			node = node.Parent
		end
		return node
	end

	local tagged = {}
	for _, rec in ipairs(records) do
		table.insert(tagged, { rec = rec, component = componentOf(rec.instance) })
	end

	local overlaps = 0
	for i = 1, #tagged do
		for j = i + 1, #tagged do
			local a, b = tagged[i], tagged[j]
			if a.component ~= nil and b.component ~= nil and a.component ~= b.component then
				if a.rec.instance.Name ~= "HitArea" and b.rec.instance.Name ~= "HitArea" then
					local iw, ih = rectIntersection(a.rec.absPos, a.rec.absSize, b.rec.absPos, b.rec.absSize)
					if math.floor(iw) >= 1 and math.floor(ih) >= 1 then
						overlaps += 1
						check(
							string.format("'%s' <-> '%s' (다른 컴포넌트) 겹치지 않는다", a.rec.path, b.rec.path),
							false,
							string.format("교차 %.2fx%.2fpx", iw, ih)
						)
					end
				end
			end
		end
	end
	-- 쌍마다 pass를 세면 개수가 요소 수의 제곱으로 불어 다른 행을 묻는다. 겹침이 없으면 한 건으로 센다.
	if overlaps == 0 then
		check("다른 컴포넌트끼리 겹치는 요소 쌍이 없다", true)
	end
end

-- 검사 5 — PowerBlock 예산 일치 (U3-5) --------------------------------------------
--
-- 블록의 AbsolutePosition/AbsoluteSize가 확정 예산(PowerBlock.BlockWidth/BlockHeight/
-- BlockBottomY)과 실제로 일치하는지 렌더 결과로 확인한다 - 검사 4(MenuRail 격자)와
-- 같은 이유로 여기서 잰다: PowerBlockTests(컴포넌트 단위, 독립 인스턴스)는 Position의
-- Scale 성분만 볼 수 있고, "화면에 실제로 몇 픽셀로 뜨는가"는 렌더 트리에서만 잴 수
-- 있다.
--
-- ⚠️ Scale 값끼리의 비교(TestHelpers.checkClose, 상대오차)가 아니라 AbsoluteSize/
-- AbsolutePosition(정수 픽셀로 반올림된 값) 비교라 정확히 같지 않을 수 있다 -
-- TestHelpers.checkClose의 대상은 "엔진이 float32로 반올림한 Scale 프로퍼티"이고
-- 여기는 그와 다른 종류의 오차(여러 단계의 Scale 곱셈 후 최종 픽셀 반올림)라 작은
-- 절대 픽셀 허용치로 비교한다(검사 4의 minColumnGapPx와 같은 종류의 픽셀 판정).
local POWER_BLOCK_PIXEL_TOLERANCE = 2

local function checkPowerBlockBudget()
	local entry = ScreenController._debug.entries["PowerBlock"]
	local root = if entry ~= nil then entry.instance else nil

	local isRendered = root ~= nil and root:IsDescendantOf(ScreenController._debug.guis.Hud)
	check("PowerBlock이 HudGui 아래 register+open돼 실물로 있다(예산 검증 전제)", isRendered)

	if not isRendered or root == nil then
		return
	end

	local hud = ScreenController._debug.guis.Hud
	local hudSize = hud.AbsoluteSize

	local expectedWidth = PowerBlock.BlockWidth * hudSize.X
	local expectedHeight = PowerBlock.BlockHeight * hudSize.Y
	local expectedBottom = PowerBlock.BlockBottomY * hudSize.Y
	local expectedCenterX = 0.5 * hudSize.X

	local absSize = root.AbsoluteSize
	local absPos = root.AbsolutePosition
	local actualBottom = absPos.Y + absSize.Y
	local actualCenterX = absPos.X + absSize.X / 2

	check(
		string.format("PowerBlock AbsoluteSize.X가 예산(화면 40%%)과 일치한다(오차<=%dpx)", POWER_BLOCK_PIXEL_TOLERANCE),
		math.abs(absSize.X - expectedWidth) <= POWER_BLOCK_PIXEL_TOLERANCE,
		string.format("actual=%d expected=%.1f", absSize.X, expectedWidth)
	)
	check(
		string.format("PowerBlock AbsoluteSize.Y가 예산(화면 16.5%%)과 일치한다(오차<=%dpx)", POWER_BLOCK_PIXEL_TOLERANCE),
		math.abs(absSize.Y - expectedHeight) <= POWER_BLOCK_PIXEL_TOLERANCE,
		string.format("actual=%d expected=%.1f", absSize.Y, expectedHeight)
	)
	check(
		string.format("PowerBlock 하단이 예산(BlockBottomY)과 일치한다(오차<=%dpx)", POWER_BLOCK_PIXEL_TOLERANCE),
		math.abs(actualBottom - expectedBottom) <= POWER_BLOCK_PIXEL_TOLERANCE,
		string.format("actual=%.1f expected=%.1f", actualBottom, expectedBottom)
	)
	check(
		string.format("PowerBlock이 화면 중앙에 있다(가로 중심, 오차<=%dpx)", POWER_BLOCK_PIXEL_TOLERANCE),
		math.abs(actualCenterX - expectedCenterX) <= POWER_BLOCK_PIXEL_TOLERANCE,
		string.format("actual=%.1f expected=%.1f", actualCenterX, expectedCenterX)
	)
end

-- 검사 6 — ShopSlots · AutoTools 예산 일치 (U3-6) -----------------------------------
--
-- 검사 5(PowerBlock)와 같은 이유·같은 방식(픽셀 허용치 비교)이다. 여기서 추가로
-- 확인하는 것은 U3-6의 핵심 결정 — **AutoTools가 하단 띠 경계 위에 있다**(하단
-- 띠 안이 아니다)는 것을 렌더 결과로 고정한다. ShopSlots/AutoTools가 기존 HUD
-- 4종과 겹치지 않는지는 이 함수가 아니라 검사 3(checkOverlaps)이 이미 본다 —
-- 그 검사는 HudGui 아래 모든 GuiObject 쌍을 훑으므로 새 화면 둘도 자동으로
-- 포함된다.
local SHOP_AUTO_PIXEL_TOLERANCE = 2

local function checkShopSlotsAndAutoToolsBudget()
	local shopEntry = ScreenController._debug.entries["ShopSlots"]
	local shopRoot = if shopEntry ~= nil then shopEntry.instance else nil
	local autoEntry = ScreenController._debug.entries["AutoTools"]
	local autoRoot = if autoEntry ~= nil then autoEntry.instance else nil

	local hud = ScreenController._debug.guis.Hud
	local shopRendered = shopRoot ~= nil and shopRoot:IsDescendantOf(hud)
	local autoRendered = autoRoot ~= nil and autoRoot:IsDescendantOf(hud)

	check("ShopSlots가 HudGui 아래 register+open돼 실물로 있다(예산 검증 전제)", shopRendered)
	check("AutoTools가 HudGui 아래 register+open돼 실물로 있다(예산 검증 전제)", autoRendered)

	local hudSize = hud.AbsoluteSize
	-- 터치 기기에서는 우하단 묶음이 점프 버튼 위로 올라간다(UI/TouchSafeLayout). 그때는 "하단 경계와 일치" 대신
	-- "점프 버튼 윗변 - 간격보다 위"를 본다.
	local jump = TouchSafeLayout.readJumpRect(hud)
	local function bottomCheck(name: string, actualBottom: number, expectedBottom: number)
		if jump == nil then
			check(string.format("%s(오차<=%dpx)", name, SHOP_AUTO_PIXEL_TOLERANCE),
				math.abs(actualBottom - expectedBottom) <= SHOP_AUTO_PIXEL_TOLERANCE,
				string.format("actual=%.1f expected=%.1f", actualBottom, expectedBottom))
		else
			local limit = ((jump :: TouchSafeLayout.Rect).y0 - TouchSafeLayout.GAP) * hudSize.Y
			check(name .. " — 터치 기기: 점프 버튼 위로 올라가 있다", actualBottom <= limit + SHOP_AUTO_PIXEL_TOLERANCE,
				string.format("actual=%.1f limit=%.1f", actualBottom, limit))
		end
	end

	if shopRendered and shopRoot ~= nil then
		local expectedWidth = (Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2) * hudSize.X
		local expectedHeight = ShopSlots.TotalHeight * hudSize.Y
		local expectedBottom = (1 - Layout.BOTTOM_MARGIN_HEIGHT) * hudSize.Y

		local absSize = shopRoot.AbsoluteSize
		local absPos = shopRoot.AbsolutePosition
		local actualBottom = absPos.Y + absSize.Y

		check(
			string.format("ShopSlots AbsoluteSize.X가 예산(우측 레일 폭)과 일치한다(오차<=%dpx)", SHOP_AUTO_PIXEL_TOLERANCE),
			math.abs(absSize.X - expectedWidth) <= SHOP_AUTO_PIXEL_TOLERANCE,
			string.format("actual=%d expected=%.1f", absSize.X, expectedWidth)
		)
		check(
			string.format("ShopSlots AbsoluteSize.Y가 예산(17.5%%)과 일치한다(오차<=%dpx)", SHOP_AUTO_PIXEL_TOLERANCE),
			math.abs(absSize.Y - expectedHeight) <= SHOP_AUTO_PIXEL_TOLERANCE,
			string.format("actual=%d expected=%.1f", absSize.Y, expectedHeight)
		)
		bottomCheck("ShopSlots 하단이 하단 여백 경계와 일치한다", actualBottom, expectedBottom)
	end

	if autoRendered and autoRoot ~= nil then
		local expectedWidth = (Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2) * hudSize.X
		local expectedHeight = AutoTools.ItemHeight * hudSize.Y
		-- 하단 띠 경계(Y = 1 - BOTTOM_HEIGHT) — 이번 결정의 핵심이라 여기서 고정 검증한다.
		local expectedBottom = (1 - Layout.BOTTOM_HEIGHT) * hudSize.Y

		local absSize = autoRoot.AbsoluteSize
		local absPos = autoRoot.AbsolutePosition
		local actualBottom = absPos.Y + absSize.Y

		check(
			string.format("AutoTools AbsoluteSize.X가 예산(우측 레일 폭)과 일치한다(오차<=%dpx)", SHOP_AUTO_PIXEL_TOLERANCE),
			math.abs(absSize.X - expectedWidth) <= SHOP_AUTO_PIXEL_TOLERANCE,
			string.format("actual=%d expected=%.1f", absSize.X, expectedWidth)
		)
		check(
			string.format("AutoTools AbsoluteSize.Y가 예산(10.5%%)과 일치한다(오차<=%dpx)", SHOP_AUTO_PIXEL_TOLERANCE),
			math.abs(absSize.Y - expectedHeight) <= SHOP_AUTO_PIXEL_TOLERANCE,
			string.format("actual=%d expected=%.1f", absSize.Y, expectedHeight)
		)
		bottomCheck("AutoTools 하단이 하단 띠 경계(Y=0.75)와 일치한다 — 하단 띠 안이 아니라 그 경계 위다", actualBottom, expectedBottom)
	end
end

-- 검사 9 — 글자 높이 하한 (Phase 6 지시서 #6). 제약에 하한이 걸려 있는가(화면 크기와 무관한 구조 검사)와
-- 지금 화면에서 실제 글자 높이가 하한 이상인가.
local function checkTextMinimum(hud: Instance)
	local missing = 0
	for _, obj in ipairs(hud:GetDescendants()) do
		if obj:IsA("UITextSizeConstraint") then
			local c = obj :: UITextSizeConstraint
			if c.MinTextSize < math.min(TextScale.MIN_TEXT_PX, c.MaxTextSize) then
				missing += 1
			end
		end
	end
	check(string.format("모든 UITextSizeConstraint에 글자 하한 %dpx가 걸려 있다", TextScale.MIN_TEXT_PX), missing == 0, tostring(missing) .. "개 빠짐")

	local tooSmall = {}
	for _, obj in ipairs(hud:GetDescendants()) do
		if obj:IsA("TextLabel") and obj.Text ~= "" then
			local label = obj :: TextLabel
			local visible = true
			local node: Instance? = label
			while node ~= nil and node ~= hud do
				if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
					visible = false
				end
				node = node.Parent
			end
			if visible and label.TextBounds.Y > 0 and label.TextBounds.Y < TextScale.MIN_TEXT_PX - 0.5 then
				table.insert(tooSmall, string.format("%s=%.1f", label.Name, label.TextBounds.Y))
			end
		end
	end
	check(string.format("보이는 글자의 실제 높이가 %dpx 이상이다", TextScale.MIN_TEXT_PX), #tooSmall == 0, table.concat(tooSmall, ", "))
end

-- 검사 11 — 구좌 가격이 칸 안에 들어온다 (지시서 #7 1단계). 글자 하한 때문에 좁은 폰 타일에서 "199 R$"가
-- 칸 밖으로 넘쳤다. 렌더된 글자 사각형(TextBounds)이 타일 안에 있는지 본다 — 하한(검사 9)과 같이 성립해야 한다.
local function checkShopPriceFits()
	local entry = ScreenController._debug.entries["ShopSlots"]
	local root = if entry ~= nil then entry.instance else nil
	if root == nil then
		check("구좌 가격 검사: ShopSlots 없음", false)
		return
	end
	local over = {}
	local count = 0
	local withUnit = 0
	for _, tile in ipairs(root:GetChildren()) do
		local price = tile:FindFirstChild("Price")
		if tile:IsA("Frame") and price ~= nil and price:IsA("TextLabel") then
			count += 1
			if string.find(price.Text, "R$", 1, true) ~= nil then
				withUnit += 1
			end
			local bounds = price.TextBounds
			local size = tile.AbsoluteSize
			if bounds.X > size.X + 0.5 or bounds.Y > size.Y + 0.5 then
				table.insert(over, string.format("%s '%s' %.0fx%.0f > %.0fx%.0f", tile.Name, price.Text, bounds.X, bounds.Y, size.X, size.Y))
			end
		end
	end
	check("구좌 가격 라벨 4개를 찾았다", count == 4, tostring(count))
	check("구좌 가격 글자가 타일 안에 들어온다", #over == 0, table.concat(over, ", "))
	check("구좌 가격 표기가 넷 다 같은 꼴이다(R$ 전부 있음 또는 전부 없음)", withUnit == 0 or withUnit == count, string.format("%d/%d", withUnit, count))
end

-- 검사 10 — 터치 조작 자리 (Phase 6 지시서 #6). TouchGui가 있을 때만 의미가 있다(PC Play에는 없다 →
-- 건너뛰었다는 사실 하나만 기록). 점프 버튼과 조이스틱 휴지 자리를 실측 사각형으로, HUD 컴포넌트 전부와
-- 화면 좌표로 비교한다.
local function checkTouchControls(hud: ScreenGui)
	local playerGui = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	if touchGui == nil then
		check("터치 조작 검사: TouchGui 없음(PC) — 건너뜀", true)
		return
	end
	local avoid = {}
	for _, name in ipairs({ "JumpButton", "ThumbstickStart" }) do
		local obj = touchGui:FindFirstChild(name, true)
		if obj ~= nil and obj:IsA("GuiObject") and obj.Visible then
			table.insert(avoid, { name = name, obj = obj :: GuiObject })
		end
	end
	for _, comp in ipairs(hud:GetChildren()) do
		if comp:IsA("GuiObject") and comp.Visible then
			for _, a in ipairs(avoid) do
				local w, h = rectIntersection(comp.AbsolutePosition, comp.AbsoluteSize, a.obj.AbsolutePosition, a.obj.AbsoluteSize)
				check(string.format("터치: '%s'가 %s와 겹치지 않는다", comp.Name, a.name), w <= 0 or h <= 0, string.format("교차 %dx%dpx", w, h))
			end
		end
	end
end

task.defer(function()
	local hud = ScreenController._debug.guis.Hud

	local gateResult = HudLayoutGate.wait(hud)
	check(
		string.format("뷰포트 게이트가 %d프레임 안에 만족됐다", HudLayoutGate.FRAME_CAP),
		gateResult.satisfied,
		string.format(
			"failureReason=%s frames=%d viewportSize=(%d,%d) HudGui.AbsoluteSize=(%d,%d) 기대크기=(%d,%d)",
			tostring(gateResult.failureReason),
			gateResult.frames,
			gateResult.viewportSize.X,
			gateResult.viewportSize.Y,
			gateResult.hudGuiAbsoluteSize.X,
			gateResult.hudGuiAbsoluteSize.Y,
			gateResult.expectedHudGuiSize.X,
			gateResult.expectedHudGuiSize.Y
		)
	)

	if not gateResult.satisfied then
		-- "측정할 수 없었다"를 green으로 처리하지 않는다. 위 게이트 실패 자체가 이미
		-- fail이고, 이 상태에서 AbsSize/AbsPos를 재는 것은 근거가 없으므로 나머지
		-- 검사는 생략한다 — 신뢰 불가능한 값으로 통과·실패를 채우는 것보다
		-- 명시적으로 하나만 fail시키는 쪽이 정직하다.
		finish()
		return
	end

	local records: { ElementRecord } = {}
	collect(hud, hud.Name, records)

	-- 검사 1 — 크기 0 --------------------------------------------------------------
	for _, rec in ipairs(records) do
		check(
			string.format("'%s' AbsSize.X>0 and AbsSize.Y>0", rec.path),
			rec.absSize.X > 0 and rec.absSize.Y > 0,
			formatSizeDetail(rec)
		)
	end

	-- 검사 2 — 상단/하단/좌/우 사용 가능 영역 이탈 -----------------------------------------
	-- 기준선은 HudLayoutGate.computeUsableBounds가 IgnoreGuiInset을 보고 정한다
	-- (파일 상단 "검사 2의 기준선" 절 참고 — 이 판단을 여기 다시 손으로 쓰지 않는다).
	local viewportSize = gateResult.viewportSize
	local bounds = HudLayoutGate.computeUsableBounds(hud, viewportSize)
	local modeText = string.format("IgnoreGuiInset=%s", tostring(hud.IgnoreGuiInset))

	-- 0.5px 오차: 폰 해상도(705×338 시뮬레이션)에서 AbsPos.Y가 -0.x로 나와 "0 >= 0"이 실패로 찍혔다
	-- (2026-10-22, 표시는 %d라 0으로 보였다). 픽셀 미만은 부동소수점 반올림이지 침범이 아니다.
	local EDGE_EPS = 0.5
	for _, rec in ipairs(records) do
		local x0, y0 = rec.absPos.X, rec.absPos.Y
		local x1, y1 = x0 + rec.absSize.X, y0 + rec.absSize.Y

		check(
			string.format("'%s' 상단이 사용 가능 영역 안쪽이다(top=%d, %s)", rec.path, bounds.top, modeText),
			y0 >= bounds.top - EDGE_EPS,
			string.format("AbsPos.Y=%.2f 기준선=%d(%s)", y0, bounds.top, modeText)
		)
		check(
			string.format("'%s' 하단이 사용 가능 영역 안쪽이다(bottom=%d, %s)", rec.path, bounds.bottom, modeText),
			y1 <= bounds.bottom + EDGE_EPS,
			string.format("AbsPos.Y+AbsSize.Y=%.2f 기준선=%d(%s)", y1, bounds.bottom, modeText)
		)
		check(
			string.format("'%s' 좌측이 사용 가능 영역 안쪽이다(left=%d, %s)", rec.path, bounds.left, modeText),
			x0 >= bounds.left - EDGE_EPS,
			string.format("AbsPos.X=%.2f 기준선=%d(%s)", x0, bounds.left, modeText)
		)
		check(
			string.format("'%s' 우측이 사용 가능 영역 안쪽이다(right=%d, %s)", rec.path, bounds.right, modeText),
			x1 <= bounds.right + EDGE_EPS,
			string.format("AbsPos.X+AbsSize.X=%.2f 기준선=%d(%s)", x1, bounds.right, modeText)
		)
	end

	-- 검사 3 — 형제 겹침 ------------------------------------------------------------
	checkOverlaps(records)

	-- 검사 4 — MenuRail 격자 배치 ----------------------------------------------------
	checkMenuRailGrid()

	-- 검사 5 — PowerBlock 예산 일치 (U3-5) --------------------------------------------
	checkPowerBlockBudget()

	-- 검사 6 — ShopSlots · AutoTools 예산 일치 (U3-6) ----------------------------------
	checkShopSlotsAndAutoToolsBudget()

	-- 검사 7 — 항목 칸 안의 자식은 칸 안에 (U3-10b) -------------------------------------
	checkItemChildrenInsideCell(records)

	-- 검사 8 — 다른 컴포넌트끼리 겹침 (U3-10b) ------------------------------------------
	checkCrossComponentOverlaps(hud, records)

	-- 검사 9 — 글자 높이 하한 (지시서 #6) ----------------------------------------------------
	checkTextMinimum(hud)

	-- 검사 10 — 터치 조작 자리 (지시서 #6) ---------------------------------------------------
	checkTouchControls(hud)

	-- 검사 11 — 구좌 가격이 칸 안에 (지시서 #7) ------------------------------------------------
	checkShopPriceFits()

	finish()
end)

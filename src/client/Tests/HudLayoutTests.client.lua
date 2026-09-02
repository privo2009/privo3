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
--      MenuRail/{Shop,Rebirth,Drone,Aura,Pet,Settings}/Tile.
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
local HudLayoutGate = require(script.Parent.Parent.Tools.HudLayoutGate)

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

	for _, rec in ipairs(records) do
		local x0, y0 = rec.absPos.X, rec.absPos.Y
		local x1, y1 = x0 + rec.absSize.X, y0 + rec.absSize.Y

		check(
			string.format("'%s' 상단이 사용 가능 영역 안쪽이다(top=%d, %s)", rec.path, bounds.top, modeText),
			y0 >= bounds.top,
			string.format("AbsPos.Y=%d 기준선=%d(%s)", y0, bounds.top, modeText)
		)
		check(
			string.format("'%s' 하단이 사용 가능 영역 안쪽이다(bottom=%d, %s)", rec.path, bounds.bottom, modeText),
			y1 <= bounds.bottom,
			string.format("AbsPos.Y+AbsSize.Y=%d 기준선=%d(%s)", y1, bounds.bottom, modeText)
		)
		check(
			string.format("'%s' 좌측이 사용 가능 영역 안쪽이다(left=%d, %s)", rec.path, bounds.left, modeText),
			x0 >= bounds.left,
			string.format("AbsPos.X=%d 기준선=%d(%s)", x0, bounds.left, modeText)
		)
		check(
			string.format("'%s' 우측이 사용 가능 영역 안쪽이다(right=%d, %s)", rec.path, bounds.right, modeText),
			x1 <= bounds.right,
			string.format("AbsPos.X+AbsSize.X=%d 기준선=%d(%s)", x1, bounds.right, modeText)
		)
	end

	-- 검사 3 — 형제 겹침 ------------------------------------------------------------
	checkOverlaps(records)

	finish()
end)

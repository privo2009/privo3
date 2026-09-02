--!strict
-- HUD 레이아웃 관측 리포트 (Phase 6 / U3-2 관측 단계). 코드 수정 없이 실제 좌표를
-- Play 로그로 찍기 위한 것 — 다음 단계에서 만들 레이아웃 테스트의 기준선을 정하는
-- 재료다. HUD 표시 상태에서 육안으로 3건이 깨져 있었다(docs/PENDING.md "HUD 표시
-- 상태에서 육안으로 3건이 보였다" 참고: 좌측 레일 라벨이 타일에 겹침 / 좌상단
-- 블럭스가 안 보임 / 상단 중앙 "대기중"이 잘림). HudVisibilityTests는
-- IsDescendantOf + Visible + AbsoluteSize까지만 봐서 이 셋을 못 잡는다.
--
-- ⚠️ 이 파일은 판정하지 않는다. 사각형 교집합·뷰포트 이탈 여부 같은 순수 기계적
-- 파생값만 찍는다. "세이프존 위반"류의 설계 규칙 판정은 다음 단계에서 이 출력을
-- 보고 사람이 정한다 — 기준선이 아직 없다.
--
-- ⚠️ HUD 인스턴스를 읽기만 한다. 배치를 바꾸지 않고, 프로필도 게임 상태도
-- 건드리지 않는다 — StandardPathReport와 같은 성격이라 켠 채로 커밋해도 안전하다.
--
-- 호출: HudBoot.client.lua 맨 끝, HUD 3종이 register+open된 *뒤*.
-- 플래그: 그 파일의 HUD_LAYOUT_REPORT_ENABLED (기본값 켜짐).
--
-- ===== 2차 개정 (관측 2차) ============================================================
--
-- 1차 게이트(HudGui.AbsoluteSize.X > 0)가 유령값을 통과시켰다. 뷰포트가 아직
-- 확정되지 않은 아주 이른 프레임에 로블록스가 물리는 임시값이 (800,600)이었고,
-- 그 값의 X는 0보다 크므로 게이트를 그냥 통과했다. 그 결과 출력 C의 AbsPos/
-- AbsSize와 출력 D의 이탈 픽셀이 전부 그 유령 해상도 기준으로 찍혔다.
--
-- 뷰포트 확정 전에는 (1,1)이 초기값이다(위 (800,600)도 같은 종류의 미확정
-- 중간값이었다) — 그래서 게이트를 "AbsoluteSize.X > 0"이 아니라
-- "ViewportSize.X > 1 and ViewportSize.Y > 1, 그리고 HudGui.AbsoluteSize가
-- ViewportSize와 일치"로 바꿨다. Workspace.CurrentCamera가 클라 부트 시점에
-- nil일 수 있어(엔진이 카메라를 만드는 시점과 부트 스크립트 실행 순서 사이에
-- 보장이 없다), 게이트 조건 중 하나로 넣어 nil이 아니게 될 때까지도 기다린다 —
-- nil 상태로 인덱싱하면 에러가 나므로 매 프레임 다시 조회한다.

local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local ScreenController = require(script.Parent.Parent.UI.ScreenController)
local HudLayoutGate = require(script.Parent.HudLayoutGate)

local HudLayoutReport = {}

local PREFIX = "[HUDLAYOUT]"

-- 게이트를 벗어난 뒤 추가로 기다리는 프레임 수.
local EXTRA_FRAMES_AFTER_RENDER = 2

type ElementRecord = {
	path: string,
	instance: GuiObject,
	parent: Instance,
	depth: number,
	absPos: Vector2,
	absSize: Vector2,
}

-- ===== 출력 A — 화면 기준 ==========================================================

local function formatUDim(u: UDim): string
	return string.format("scale %.4f offset %d", u.Scale, u.Offset)
end

local function printSectionA(hudGui: ScreenGui, gateFrames: number): (Vector2, number)
	print(PREFIX .. " ===== 출력 A: 화면 기준 =====")

	local topLeftInset, bottomRightInset = GuiService:GetGuiInset()

	local camera = Workspace.CurrentCamera
	local viewportSize: Vector2
	if camera ~= nil then
		viewportSize = camera.ViewportSize
	else
		viewportSize = Vector2.new(0, 0)
		warn(PREFIX .. " Workspace.CurrentCamera가 nil - 뷰포트 크기를 못 구했다 (0,0으로 대체, 아래 D 출력 전부 무의미)")
	end
	print(string.format("%s 뷰포트 크기(px) = %d x %d", PREFIX, viewportSize.X, viewportSize.Y))
	print(string.format("%s HudGui.AbsoluteSize = (%d, %d)", PREFIX, hudGui.AbsoluteSize.X, hudGui.AbsoluteSize.Y))

	-- ⚠️ U3-4B 후속: "일치"의 기준이 더 이상 ViewportSize 그 자체가 아니다.
	-- IgnoreGuiInset=false(U3-4B에서 그렇게 바꿨다)면 HudGui는 GetGuiInset()만큼
	-- 줄어든 크기가 정상이다 — HudLayoutGate.computeExpectedSize와 같은 식.
	-- 예전처럼 ViewportSize와 그대로 비교하면 정상 상태에서도 "불일치"로 잘못
	-- 찍힌다(HudLayoutGate.lua 상단 설명 참고).
	local expectedHudGuiSize = if hudGui.IgnoreGuiInset then viewportSize else viewportSize - topLeftInset - bottomRightInset
	print(string.format("%s 기대 HudGui.AbsoluteSize(IgnoreGuiInset=%s 기준) = (%d, %d)", PREFIX, tostring(hudGui.IgnoreGuiInset), expectedHudGuiSize.X, expectedHudGuiSize.Y))
	print(string.format(
		"%s 기대 크기와 HudGui.AbsoluteSize 일치 = %s | 게이트 대기 %d프레임",
		PREFIX,
		tostring(camera ~= nil and hudGui.AbsoluteSize == expectedHudGuiSize),
		gateFrames
	))

	print(string.format(
		"%s GetGuiInset() topLeft=(%d,%d) bottomRight=(%d,%d)",
		PREFIX,
		topLeftInset.X,
		topLeftInset.Y,
		bottomRightInset.X,
		bottomRightInset.Y
	))

	-- ⚠️ TopbarInset은 존재하지 않는 엔진 버전이 있다. 타입 정의에 없을 수도 있어
	-- `:: any`로 우회하고 pcall로 감싼다 - 실패하면 "미지원"으로 찍는다.
	local ok, topbarInset = pcall(function()
		return (GuiService :: any).TopbarInset
	end)
	if ok then
		print(string.format("%s GuiService.TopbarInset = %s", PREFIX, tostring(topbarInset)))
	else
		print(string.format("%s GuiService.TopbarInset = 미지원", PREFIX))
	end

	return viewportSize, topLeftInset.Y
end

-- ===== 출력 B — ScreenGui 목록 =====================================================

local function printSectionB(): { ScreenGui }
	print(PREFIX .. " ===== 출력 B: ScreenGui 목록 =====")

	-- "우리가 만든 ScreenGui 전부" = ScreenController 기본 인스턴스가 만든 3장.
	-- PlayerGui를 훑어 이름으로 거르는 대신 이 창구를 쓴다 - 그게 우리가 만든
	-- ScreenGui라는 것을 코드로 보장하는 유일한 방법이다.
	local guis = ScreenController._debug.guis
	local order = { "Hud", "Window", "Overlay" }
	local list: { ScreenGui } = {}

	for _, layerName in ipairs(order) do
		local gui = (guis :: any)[layerName] :: ScreenGui?
		if gui ~= nil then
			table.insert(list, gui)
			print(string.format(
				"%s %s DisplayOrder=%d IgnoreGuiInset=%s ResetOnSpawn=%s ZIndexBehavior=%s Enabled=%s AbsoluteSize=(%d,%d)",
				PREFIX,
				gui.Name,
				gui.DisplayOrder,
				tostring(gui.IgnoreGuiInset),
				tostring(gui.ResetOnSpawn),
				tostring(gui.ZIndexBehavior),
				tostring(gui.Enabled),
				gui.AbsoluteSize.X,
				gui.AbsoluteSize.Y
			))
			if gui.AbsoluteSize.X <= 0 then
				warn(string.format("%s %s.AbsoluteSize.X가 0이다 - 아래 요소 관측값도 전부 무의미할 수 있다", PREFIX, gui.Name))
			end
		end
	end

	return list
end

-- ===== 출력 C — 요소 트리 (겹침 계산용 레코드도 여기서 함께 모은다) ====================

local function formatElementLine(el: GuiObject, path: string, depth: number, ancestorClips: boolean): string
	local indent = string.rep("  ", depth)
	local pos = el.Position
	local size = el.Size

	local line = string.format(
		"%s%s%s (%s) Visible=%s ZIndex=%d ClipsDescendants=%s Anchor=(%.2f,%.2f) "
			.. "Pos=[scale %.4f,%.4f offset %d,%d] Size=[scale %.4f,%.4f offset %d,%d] "
			.. "AbsPos=(%d,%d) AbsSize=(%d,%d) BgTransparency=%.2f",
		PREFIX,
		indent,
		path,
		el.ClassName,
		tostring(el.Visible),
		el.ZIndex,
		tostring(el.ClipsDescendants),
		el.AnchorPoint.X,
		el.AnchorPoint.Y,
		pos.X.Scale,
		pos.Y.Scale,
		pos.X.Offset,
		pos.Y.Offset,
		size.X.Scale,
		size.Y.Scale,
		size.X.Offset,
		size.Y.Offset,
		el.AbsolutePosition.X,
		el.AbsolutePosition.Y,
		el.AbsoluteSize.X,
		el.AbsoluteSize.Y,
		el.BackgroundTransparency
	)

	if el:IsA("TextLabel") then
		line = line
			.. string.format(
				" Text=%q TextScaled=%s TextTransparency=%.2f TextStrokeTransparency=%.2f",
				el.Text,
				tostring(el.TextScaled),
				el.TextTransparency,
				el.TextStrokeTransparency
			)
	end

	if ancestorClips then
		line = line .. " [조상 중 ClipsDescendants=true 있음]"
	end

	return line
end

-- 작업 2 (관측 2차): GuiObject가 아니라서 1차 재귀에서 빠졌던 제약/레이아웃류.
-- 요소 자기 줄 바로 아래, 한 단계 더 들여써서 찍는다 - "요소가 왜 그 크기가
-- 됐는가"를 이 줄들 없이는 재구성할 수 없다(AbsSize가 Size.Scale만으로 안
-- 설명되는 것이 이번 관측의 핵심이다).
local function printNonGuiChild(child: Instance, depth: number)
	local indent = string.rep("  ", depth)
	local className = child.ClassName

	if className == "UIAspectRatioConstraint" then
		local c = child :: UIAspectRatioConstraint
		print(string.format(
			"%s%s[%s] AspectRatio=%.4f AspectType=%s DominantAxis=%s",
			PREFIX,
			indent,
			className,
			c.AspectRatio,
			tostring(c.AspectType),
			tostring(c.DominantAxis)
		))
	elseif className == "UIListLayout" then
		local c = child :: UIListLayout
		print(string.format(
			"%s%s[%s] FillDirection=%s HorizontalAlignment=%s VerticalAlignment=%s Padding=[%s] SortOrder=%s",
			PREFIX,
			indent,
			className,
			tostring(c.FillDirection),
			tostring(c.HorizontalAlignment),
			tostring(c.VerticalAlignment),
			formatUDim(c.Padding),
			tostring(c.SortOrder)
		))
	elseif className == "UIGridLayout" then
		local c = child :: UIGridLayout
		print(string.format(
			"%s%s[%s] CellSize=[scale %.4f,%.4f offset %d,%d] CellPadding=[scale %.4f,%.4f offset %d,%d] "
				.. "FillDirection=%s HorizontalAlignment=%s VerticalAlignment=%s SortOrder=%s",
			PREFIX,
			indent,
			className,
			c.CellSize.X.Scale,
			c.CellSize.Y.Scale,
			c.CellSize.X.Offset,
			c.CellSize.Y.Offset,
			c.CellPadding.X.Scale,
			c.CellPadding.Y.Scale,
			c.CellPadding.X.Offset,
			c.CellPadding.Y.Offset,
			tostring(c.FillDirection),
			tostring(c.HorizontalAlignment),
			tostring(c.VerticalAlignment),
			tostring(c.SortOrder)
		))
	elseif className == "UIPadding" then
		local c = child :: UIPadding
		print(string.format(
			"%s%s[%s] Top=[%s] Bottom=[%s] Left=[%s] Right=[%s]",
			PREFIX,
			indent,
			className,
			formatUDim(c.PaddingTop),
			formatUDim(c.PaddingBottom),
			formatUDim(c.PaddingLeft),
			formatUDim(c.PaddingRight)
		))
	elseif className == "UISizeConstraint" then
		local c = child :: UISizeConstraint
		print(string.format(
			"%s%s[%s] MinSize=(%.1f,%.1f) MaxSize=(%.1f,%.1f)",
			PREFIX,
			indent,
			className,
			c.MinSize.X,
			c.MinSize.Y,
			c.MaxSize.X,
			c.MaxSize.Y
		))
	elseif className == "UITextSizeConstraint" then
		local c = child :: UITextSizeConstraint
		print(string.format("%s%s[%s] MinTextSize=%d MaxTextSize=%d", PREFIX, indent, className, c.MinTextSize, c.MaxTextSize))
	elseif className == "UIScale" then
		local c = child :: UIScale
		print(string.format("%s%s[%s] Scale=%.4f", PREFIX, indent, className, c.Scale))
	elseif className == "UIStroke" then
		local c = child :: UIStroke
		print(string.format(
			"%s%s[%s] Enabled=%s Color=%s Thickness=%.2f Transparency=%.2f ApplyStrokeMode=%s",
			PREFIX,
			indent,
			className,
			tostring(c.Enabled),
			tostring(c.Color),
			c.Thickness,
			c.Transparency,
			tostring(c.ApplyStrokeMode)
		))
	elseif not child:IsA("GuiObject") then
		-- 위 목록에 없는 비-GuiObject 자식. 서술에 없던 구조이므로 조용히 넘기지
		-- 않고 최소한 무엇이 있는지는 남긴다 (추측 대신 실제 구조 보고).
		print(string.format("%s%s[%s] (미분류 비-GuiObject - Name=%s)", PREFIX, indent, className, child.Name))
	end
end

local function collect(node: Instance, path: string, depth: number, ancestorClips: boolean, records: { ElementRecord })
	for _, child in ipairs(node:GetChildren()) do
		if child:IsA("GuiObject") then
			local childPath = path .. "/" .. child.Name
			print(formatElementLine(child, childPath, depth, ancestorClips))

			for _, grandchild in ipairs(child:GetChildren()) do
				if not grandchild:IsA("GuiObject") then
					printNonGuiChild(grandchild, depth + 1)
				end
			end

			table.insert(records, {
				path = childPath,
				instance = child,
				parent = node,
				depth = depth,
				absPos = child.AbsolutePosition,
				absSize = child.AbsoluteSize,
			})

			collect(child, childPath, depth + 1, ancestorClips or child.ClipsDescendants, records)
		end
	end
end

local function printSectionC(guiList: { ScreenGui }): { ElementRecord }
	print(PREFIX .. " ===== 출력 C: 요소 트리 (비-GuiObject 자식은 한 단 더 들여씀) =====")
	local records: { ElementRecord } = {}
	for _, gui in ipairs(guiList) do
		collect(gui, gui.Name, 0, false, records)
	end
	return records
end

-- ===== 출력 D — 뷰포트 경계 ==========================================================

local function printSectionD(records: { ElementRecord }, viewportSize: Vector2, topInsetY: number)
	print(PREFIX .. " ===== 출력 D: 뷰포트 경계 =====")
	for _, rec in ipairs(records) do
		local x0, y0 = rec.absPos.X, rec.absPos.Y
		local x1, y1 = x0 + rec.absSize.X, y0 + rec.absSize.Y

		local overTop = math.max(0, -y0)
		local overLeft = math.max(0, -x0)
		local overRight = math.max(0, x1 - viewportSize.X)
		local overBottom = math.max(0, y1 - viewportSize.Y)
		-- 판정이 아니다 - GetGuiInset() 기준선과 뷰포트(0,0) 기준선을 나란히 보기 위한 값.
		local insetTopViolation = math.max(0, topInsetY - y0)

		print(string.format(
			"%s %s 위=%dpx 아래=%dpx 좌=%dpx 우=%dpx | GuiInset기준(topInset=%d) 상단침범=%dpx",
			PREFIX,
			rec.path,
			overTop,
			overBottom,
			overLeft,
			overRight,
			topInsetY,
			insetTopViolation
		))
	end
end

-- ===== 출력 E — 겹침 =================================================================

local function rectIntersection(aPos: Vector2, aSize: Vector2, bPos: Vector2, bSize: Vector2): (number?, number?)
	local ax0, ay0 = aPos.X, aPos.Y
	local ax1, ay1 = ax0 + aSize.X, ay0 + aSize.Y
	local bx0, by0 = bPos.X, bPos.Y
	local bx1, by1 = bx0 + bSize.X, by0 + bSize.Y

	local ix0, iy0 = math.max(ax0, bx0), math.max(ay0, by0)
	local ix1, iy1 = math.min(ax1, bx1), math.min(ay1, by1)
	local iw, ih = ix1 - ix0, iy1 - iy0

	if iw > 0 and ih > 0 then
		return iw, ih
	end
	return nil, nil
end

local function printSectionE(records: { ElementRecord })
	print(PREFIX .. " ===== 출력 E: 겹침 =====")

	-- 같은 부모(Instance)를 가진 형제끼리만 비교한다. 최상위 요소들(BloxDisplay 등)의
	-- parent는 GuiObject가 아니라 ScreenGui 자신이지만, 테이블 키로는 그냥 써도 된다 -
	-- Instance는 참조 동일성으로 비교되므로 그룹핑이 정확히 "같은 부모"로 갈린다.
	local groups: { [Instance]: { ElementRecord } } = {}
	for _, rec in ipairs(records) do
		local list = groups[rec.parent]
		if list == nil then
			list = {}
			groups[rec.parent] = list
		end
		table.insert(list, rec)
	end

	local foundCount = 0
	for _, siblings in pairs(groups) do
		for i = 1, #siblings do
			for j = i + 1, #siblings do
				local a, b = siblings[i], siblings[j]
				local iw, ih = rectIntersection(a.absPos, a.absSize, b.absPos, b.absSize)
				if iw ~= nil and ih ~= nil then
					foundCount += 1
					print(string.format("%s %s <-> %s 교차 %dx%dpx", PREFIX, a.path, b.path, iw, ih))
				end
			end
		end
	end

	if foundCount == 0 then
		print(PREFIX .. " 교차하는 형제 쌍 없음")
	end
end

-- ===== 게이트 =========================================================================
--
-- 실제 대기·판정 로직은 HudLayoutGate(공용 모듈)에 있다. camera_nil/viewport_ghost
-- 문구는 U3-3 때와 동일하다. size_mismatch 문구만 U3-4B 후속에서 바뀌었다 —
-- 예전엔 "HudGui.AbsoluteSize != ViewportSize"만 찍어서 IgnoreGuiInset=false로
-- 바뀐 뒤 "왜 다른지"(기대 크기가 애초에 ViewportSize가 아니게 됐다는 것)가 로그로
-- 안 보였다. 이제 기대 크기(HudLayoutGate가 IgnoreGuiInset을 반영해 계산)와 실제
-- 크기를 둘 다 찍는다.
local function waitForGate(hudGui: ScreenGui): number
	local result = HudLayoutGate.wait(hudGui)

	if result.failureReason == "camera_nil" then
		warn(string.format(
			"%s 게이트 %d프레임 뒤에도 Workspace.CurrentCamera가 nil - 포기하고 그대로 진행한다 (아래 값 전부 무의미할 수 있다)",
			PREFIX,
			result.frames
		))
	elseif result.failureReason == "viewport_ghost" then
		warn(string.format(
			"%s 게이트 %d프레임 뒤에도 ViewportSize=(%d,%d) (1x1 이하 유령값) - 이하 관측값 전부 무의미할 수 있다",
			PREFIX,
			result.frames,
			result.viewportSize.X,
			result.viewportSize.Y
		))
	elseif result.failureReason == "size_mismatch" then
		warn(string.format(
			"%s 게이트 %d프레임 뒤에도 HudGui.AbsoluteSize(%d,%d) != 기대 크기(%d,%d, IgnoreGuiInset=%s 기준, ViewportSize=%d,%d) - 이하 관측값 의심스럽다",
			PREFIX,
			result.frames,
			result.hudGuiAbsoluteSize.X,
			result.hudGuiAbsoluteSize.Y,
			result.expectedHudGuiSize.X,
			result.expectedHudGuiSize.Y,
			tostring(hudGui.IgnoreGuiInset),
			result.viewportSize.X,
			result.viewportSize.Y
		))
	end

	return result.frames
end

-- ===== 진입점 =======================================================================

function HudLayoutReport.run()
	-- task.defer: 이번 프레임에서 동기적으로 실행 중이던 스크립트(HudBoot 포함)가
	-- 전부 끝난 뒤로 미룬다 (HudVisibilityTests와 같은 근거).
	task.defer(function()
		local hudGui = ScreenController._debug.guis.Hud

		local gateFrames = waitForGate(hudGui)

		for _ = 1, EXTRA_FRAMES_AFTER_RENDER do
			RunService.Heartbeat:Wait()
		end

		print(PREFIX .. " HUD 레이아웃 관측 시작 (Phase 6 / U3-2 관측 2차 — 판정 없음, 순수 관측값만)")

		local viewportSize, topInsetY = printSectionA(hudGui, gateFrames)
		local guiList = printSectionB()
		local records = printSectionC(guiList)
		printSectionD(records, viewportSize, topInsetY)
		printSectionE(records)

		print(PREFIX .. " 끝.")
	end)
end

return HudLayoutReport

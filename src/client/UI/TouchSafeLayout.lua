--!strict
-- 터치 조작 자리 비키기 (Phase 6 지시서 #6). 폰 · 태블릿에서 로블록스가 띄우는 점프 버튼 위에 HUD가
-- 얹히지 않게, 우하단 묶음(자동 도구 + 로벅스 구좌)을 점프 버튼 위로 올린다.
--
-- 실측(2026-10-22, Galaxy A06 시뮬레이션 — 세션 로그): JumpButton (610,190) 70×70 / HudGui 705×280.
-- 우하단 묶음(585~683, 180~265)이 점프 버튼과 겹쳤다. 조이스틱 휴지 자리(29~103, 187~261)와는
-- 아무것도 겹치지 않았다.
--
-- 왜 점프 버튼만 피하는가: 조이스틱(DynamicThumbstick)은 손가락이 닿은 자리로 따라온다 — 그 위치에
-- 맞춰 HUD를 옮기면 HUD가 계속 흔들린다. 휴지 자리 겹침 없음은 HudLayoutTests가 본다.
--
-- 왜 위로 올리는가(줄이지 않는가): docs/UI.md "하단 띠가 가장 붐빈다"가 허용한 두 방법(구역 비율 조정 ·
-- 구좌 개수 축소) 중 구역 비율 조정이다. 오른쪽 레일 가운데(오류 · 런 안내 칸 아래)가 비어 있어
-- 구좌 넷을 다 지킬 수 있다. 터치 기기에서만 일어난다 — PC에는 TouchGui가 없어 이동량이 0이다.
--
-- 좌표는 Scale만 쓴다(Offset 금지). 실측 픽셀을 HudGui 크기로 나눠 Scale로 바꾼다.

local Players = game:GetService("Players")

local TouchSafeLayout = {}

export type Rect = { x0: number, y0: number, x1: number, y1: number }

-- 점프 버튼과 HUD 사이 띄울 간격(화면 높이 대비). 시각 튜닝값(세션 로그).
TouchSafeLayout.GAP = 0.02

local function overlapsX(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and a.x1 > b.x0
end

function TouchSafeLayout.overlaps(a: Rect, b: Rect): boolean
	return overlapsX(a, b) and a.y0 < b.y1 and a.y1 > b.y0
end

-- 묶음을 얼마나 올려야 하는가(Scale, 0 이상). 묶음과 가로로 겹치는 피할 사각형마다
-- "묶음 아랫변 ≤ 그 사각형 윗변 - gap"이 되게 하는 최대값. 겹치는 것이 없으면 0.
function TouchSafeLayout.computeLift(cluster: { Rect }, avoid: { Rect }, gap: number): number
	local lift = 0
	for _, a in ipairs(avoid) do
		for _, c in ipairs(cluster) do
			if overlapsX(c, a) and c.y1 > a.y0 - gap then
				lift = math.max(lift, c.y1 - (a.y0 - gap))
			end
		end
	end
	-- 한 사각형을 비키며 올라간 결과 다른 피할 사각형과 새로 겹치는지는 보지 않는다 — 피할 사각형이
	-- 점프 버튼 하나라 그런 경우가 없다. 여럿이 되면 여기를 반복으로 바꾼다.
	return lift
end

-- GuiObject의 화면 Scale 사각형(부모가 ScreenGui 바로 아래인 root 전제). AbsolutePosition을 쓰지 않는다 —
-- 위치를 바꾼 직후에는 아직 갱신되지 않았을 수 있다.
function TouchSafeLayout.scaleRect(obj: GuiObject): Rect
	local x0 = obj.Position.X.Scale - obj.AnchorPoint.X * obj.Size.X.Scale
	local y0 = obj.Position.Y.Scale - obj.AnchorPoint.Y * obj.Size.Y.Scale
	return { x0 = x0, y0 = y0, x1 = x0 + obj.Size.X.Scale, y1 = y0 + obj.Size.Y.Scale }
end

-- 실측 픽셀 사각형을 gui 크기 기준 Scale로. 두 ScreenGui의 IgnoreGuiInset이 같아야 좌표계가 같다.
function TouchSafeLayout.pixelToScale(pos: Vector2, size: Vector2, guiSize: Vector2): Rect
	return {
		x0 = pos.X / guiSize.X,
		y0 = pos.Y / guiSize.Y,
		x1 = (pos.X + size.X) / guiSize.X,
		y1 = (pos.Y + size.Y) / guiSize.Y,
	}
end

-- 지금 화면의 점프 버튼 Scale 사각형. 없거나 숨어 있으면 nil.
function TouchSafeLayout.readJumpRect(hudGui: ScreenGui): Rect?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump == nil or not jump:IsA("GuiObject") or not jump.Visible then
		return nil
	end
	local guiSize = hudGui.AbsoluteSize
	if guiSize.X <= 0 or guiSize.Y <= 0 then
		return nil
	end
	return TouchSafeLayout.pixelToScale(jump.AbsolutePosition, jump.AbsoluteSize, guiSize)
end

-- roots를 점프 버튼 위로 올리는 배선. 기준 위치를 기억했다가 매번 기준에서 다시 계산한다(누적 금지).
-- 점프 버튼이 생기거나 움직이거나 화면 크기가 바뀌면 다시 맞춘다.
function TouchSafeLayout.attach(hudGui: ScreenGui, roots: { GuiObject })
	local base: { [GuiObject]: UDim2 } = {}
	for _, root in ipairs(roots) do
		base[root] = root.Position
	end

	local function apply()
		for _, root in ipairs(roots) do
			root.Position = base[root]
		end
		local jump = TouchSafeLayout.readJumpRect(hudGui)
		if jump == nil then
			return
		end
		local cluster = {}
		for _, root in ipairs(roots) do
			table.insert(cluster, TouchSafeLayout.scaleRect(root))
		end
		local lift = TouchSafeLayout.computeLift(cluster, { jump }, TouchSafeLayout.GAP)
		if lift <= 0 then
			return
		end
		for _, root in ipairs(roots) do
			local p = base[root]
			root.Position = UDim2.fromScale(p.X.Scale, p.Y.Scale - lift)
		end
	end

	local watched: { [Instance]: boolean } = {}
	local function watchJump()
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if jump ~= nil and jump:IsA("GuiObject") and not watched[jump] then
			watched[jump] = true
			jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(apply)
			jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
			jump:GetPropertyChangedSignal("Visible"):Connect(apply)
		end
		apply()
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(function(obj: Instance)
		if obj.Name == "JumpButton" then
			task.defer(watchJump)
		end
	end)
	hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	watchJump()

	return { apply = apply }
end

return TouchSafeLayout

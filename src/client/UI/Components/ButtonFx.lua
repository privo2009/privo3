--!strict
-- 버튼 반응 — 마우스 올림 · 누름 · 뗌에 크기만 바뀐다 (지시서 #21 A — docs/UI.md "UI 효과"). 상태 · 목표값은 UI/Logic/ButtonFxLogic.
--
-- 이 프로젝트의 버튼은 "그림(Frame · 9-slice) + 덮는 투명 HitArea(TextButton)"다. attach(hit)는 hit의 부모(그림)에
-- UIScale("ButtonFxScale")을 붙여 Scale만 TweenService로 바꾼다. Size · Position은 쉬는 동안 원래 값 그대로다.
-- 입력은 HitArea가 받는다. HitArea도 그림의 자식이라 함께 커지지만 가운데 기준이라 누르던 자리는 그대로 안쪽에 있다.
--
-- ===== 가운데 기준으로 커지게 (실측 2026-11-01 — UIScale은 AnchorPoint를 기준점으로 커진다) =====================
--   부모가 UIGridLayout      칸 가운데 기준으로 커진다(실측) → UIScale만
--   AnchorPoint (0.5, 0.5)   가운데 기준 → UIScale만
--   그 밖(자유 배치)          크기가 1이 아닌 동안만 AnchorPoint (0.5, 0.5) + 같은 화면 자리를 가리키는 Position(픽셀 차이만큼)으로 바꿔 두고,
--                            1로 돌아오면 원래 값으로 되돌린다 — 쉬는 동안의 배치 값은 손대지 않은 그대로다
--   부모가 UIListLayout      커지면 목록이 다시 배치돼(실측) 이웃이 밀린다 → 크기를 바꾸지 않는다(skipped에 남긴다 — 지금 그런 버튼은 없다)
--   다른 용도의 UIScale이 있음 그것을 덮지 않고 안쪽 래퍼("ButtonFxBody", HitArea 말고 자식 전부를 옮긴다)에 우리 UIScale을 둔다
-- 잘림: ClipsDescendants · ScrollingFrame 조상 안이면 커지는 쪽을 그 사각형 안에 들게 줄인다(ButtonFxLogic.fitScale) — 배치는 그대로.
-- 비활성(반응 안 함): hit.Active == false · 옵션 isDisabled() · 공용 Button의 비활성 표현(Gray 보임 · Color 숨김).
-- 파괴되면(hit 또는 그림) 연결 · 트윈을 정리한다.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local ButtonFxLogic = require(script.Parent.Parent.Logic.ButtonFxLogic)

local ButtonFx = {}

ButtonFx.SCALE_NAME = "ButtonFxScale"
ButtonFx.BODY_NAME = "ButtonFxBody"

export type Mode = "direct" | "shift" | "wrapper"

export type Options = {
	target: GuiObject?, -- 커질 그림. 생략하면 hit.Parent
	isDisabled: (() -> boolean)?,
}

export type Handle = {
	mode: () -> Mode, -- 지금 기준으로 고른 방식(부모 · AnchorPoint는 붙인 뒤에 바뀔 수 있어 커질 때마다 다시 본다)
	scale: UIScale,
	state: () -> ButtonFxLogic.State,
	destroy: () -> (),
	_debug: { fire: (event: ButtonFxLogic.Event, touch: boolean?, inside: boolean?) -> (), settle: () -> (), goal: () -> number,
		isShifted: () -> boolean,
		connections: () -> number },
}

-- 붙이지 못한 버튼(이름 · 사유) — 보고 · 테스트용
ButtonFx.skipped = {} :: { { name: string, reason: string } }

local handles: { [Instance]: Handle } = {}

local function layoutKindOf(parent: Instance?): string?
	if parent == nil then
		return nil
	end
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("UIGridLayout") then
			return "grid"
		elseif c:IsA("UIListLayout") or c:IsA("UITableLayout") or c:IsA("UIPageLayout") then
			return "list"
		end
	end
	return nil
end

local function defaultDisabled(target: GuiObject): boolean
	local color = target:FindFirstChild("Color")
	local gray = target:FindFirstChild("Gray")
	return gray ~= nil and color ~= nil and gray:IsA("GuiObject") and color:IsA("GuiObject") and (gray :: GuiObject).Visible
		and not (color :: GuiObject).Visible
end

-- 가장 가까운 자르는 조상의 화면 사각형(없으면 nil).
local function clipRectOf(target: GuiObject): { number }?
	local cur = target.Parent
	while cur ~= nil and cur:IsA("GuiObject") do
		local g = cur :: GuiObject
		if g.ClipsDescendants or g:IsA("ScrollingFrame") then
			local p, s = g.AbsolutePosition, g.AbsoluteSize
			return { p.X, p.Y, p.X + s.X, p.Y + s.Y }
		end
		cur = cur.Parent
	end
	return nil
end

function ButtonFx.get(hit: Instance): Handle?
	return handles[hit]
end

function ButtonFx.attach(hit: GuiButton, options: Options?): Handle?
	if not UIFxConfig.ENABLED then
		return nil
	end
	local existing = handles[hit]
	if existing ~= nil then
		return existing
	end
	local o: Options = options or {} :: Options
	local parent = hit.Parent
	local target: GuiObject? = o.target or (if parent ~= nil and parent:IsA("GuiObject") then parent :: GuiObject else nil)
	if target == nil then
		table.insert(ButtonFx.skipped, { name = hit:GetFullName(), reason = "no_target" })
		return nil
	end
	local t = target :: GuiObject

	-- 우리 UIScale 자리. 래퍼만 붙일 때 정한다 — 나머지(그대로 · 자리 옮기기)는 커질 때마다 그때의 부모 · AnchorPoint로 고른다
	-- (MenuRail처럼 칸을 만든 뒤에 격자에 넣는 경우가 있다)
	local wrapped = false
	local scaleParent: GuiObject = t
	local foreign = t:FindFirstChildOfClass("UIScale")
	if foreign ~= nil and foreign.Name ~= ButtonFx.SCALE_NAME then
		wrapped = true
		local body = Instance.new("Frame")
		body.Name = ButtonFx.BODY_NAME
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.fromScale(0.5, 0.5)
		body.Size = UDim2.fromScale(1, 1)
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		body.ZIndex = t.ZIndex
		body.AutoLocalize = false
		for _, c in ipairs(t:GetChildren()) do
			if c ~= hit and (c:IsA("GuiObject") or c:IsA("UIGridLayout") or c:IsA("UIListLayout") or c:IsA("UIPadding")) then
				c.Parent = body
			end
		end
		body.Parent = t
		scaleParent = body
	end
	local function modeNow(): Mode
		if wrapped then
			return "wrapper"
		end
		if layoutKindOf(t.Parent) == "grid" or (t.AnchorPoint.X == 0.5 and t.AnchorPoint.Y == 0.5) then
			return "direct"
		end
		return "shift"
	end
	local listWarned = false
	local scale = Instance.new("UIScale")
	scale.Name = ButtonFx.SCALE_NAME
	scale.Scale = 1
	scale.Parent = scaleParent

	local state: ButtonFxLogic.State = "idle"
	local inside = false
	local touchPress = false
	local tween: Tween? = nil
	local connections: { RBXScriptConnection } = {}
	local shifted: { anchor: Vector2, position: UDim2, applied: UDim2 }? = nil
	local destroyed = false
	local lastGoal = 1

	local function isDisabled(): boolean
		return hit.Active == false or (o.isDisabled ~= nil and (o.isDisabled :: () -> boolean)()) or defaultDisabled(t)
	end

	local function applyShift()
		if shifted ~= nil or modeNow() ~= "shift" then
			return
		end
		local size = t.AbsoluteSize / math.max(scale.Scale, 1e-3)
		local ax, ay = t.AnchorPoint.X, t.AnchorPoint.Y
		local p = t.Position
		local applied = UDim2.new(p.X.Scale, p.X.Offset + (0.5 - ax) * size.X, p.Y.Scale, p.Y.Offset + (0.5 - ay) * size.Y)
		shifted = { anchor = t.AnchorPoint, position = p, applied = applied }
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = applied
	end

	local function restoreShift()
		local s = shifted
		if s == nil then
			return
		end
		shifted = nil
		if t.Position == s.applied then -- 그사이 다른 코드가 옮기지 않았으면 원래 값으로
			t.AnchorPoint = s.anchor
			t.Position = s.position
		else -- 옮겼으면 그 새 자리를 원래 AnchorPoint 기준 값으로 되돌려 둔다
			local size = t.AbsoluteSize / math.max(scale.Scale, 1e-3)
			local p = t.Position
			t.AnchorPoint = s.anchor
			t.Position = UDim2.new(p.X.Scale, p.X.Offset - (0.5 - s.anchor.X) * size.X, p.Y.Scale, p.Y.Offset - (0.5 - s.anchor.Y) * size.Y)
		end
	end

	local function goTo(newState: ButtonFxLogic.State)
		if newState == state or destroyed then
			return
		end
		local from = state
		state = newState
		local cap = 1e9
		local clipped = false
		local clip = clipRectOf(t)
		if clip ~= nil then
			local p, s = t.AbsolutePosition, t.AbsoluteSize
			local k = math.max(scale.Scale, 1e-3)
			local cx, cy = p.X + s.X / 2, p.Y + s.Y / 2
			local w, h = s.X / k, s.Y / k
			cap = ButtonFxLogic.fitScale({ cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2 }, clip)
			clipped = cap < UIFxConfig.HOVER_SCALE
		end
		local goal = ButtonFxLogic.cappedScale(newState, cap)
		if not wrapped and layoutKindOf(t.Parent) == "list" then
			-- UIListLayout 자식은 커지면 목록이 다시 배치돼 이웃이 밀린다(실측) — 크기를 바꾸지 않는다
			goal = 1
			if not listWarned then
				listWarned = true
				table.insert(ButtonFx.skipped, { name = t:GetFullName(), reason = "list_layout" })
			end
		end
		lastGoal = goal
		local spec = ButtonFxLogic.tweenSpec(from, newState, clipped)
		if goal ~= 1 then
			applyShift()
		end
		if tween ~= nil then
			(tween :: Tween):Cancel()
		end
		local tw = TweenService:Create(scale, TweenInfo.new(spec.time, spec.style, spec.direction), { Scale = goal })
		tween = tw
		tw.Completed:Connect(function(playback: Enum.PlaybackState)
			if playback == Enum.PlaybackState.Completed and state == "idle" and tween == tw then
				restoreShift()
			end
		end)
		tw:Play()
	end

	local function fire(event: ButtonFxLogic.Event, touch: boolean?, insideNow: boolean?)
		if insideNow ~= nil then
			inside = insideNow
		end
		goTo(ButtonFxLogic.transition(state, event, { inside = inside, touch = touch == true, disabled = isDisabled() }))
	end

	table.insert(connections, hit.MouseEnter:Connect(function()
		fire("enter", false, true)
	end))
	table.insert(connections, hit.MouseLeave:Connect(function()
		fire("leave", false, false)
	end))
	table.insert(connections, hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			touchPress = kind == Enum.UserInputType.Touch
			fire("down", touchPress, true)
		end
	end))
	-- 뗌은 버튼 밖에서 일어날 수도 있다 — 전체 입력에서 받는다(누르고 있을 때만 의미가 있다)
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if state == "pressed" and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			fire("up", touchPress, nil)
		end
	end))
	-- 비활성이 되면 바로 쉰다
	table.insert(connections, hit:GetPropertyChangedSignal("Active"):Connect(function()
		if isDisabled() then
			fire("disable")
		end
	end))

	local handle: Handle
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		table.clear(connections)
		if tween ~= nil then
			(tween :: Tween):Cancel()
			tween = nil
		end
		handles[hit] = nil
	end
	table.insert(connections, hit.Destroying:Connect(destroy))
	table.insert(connections, t.Destroying:Connect(destroy))

	handle = {
		mode = modeNow,
		scale = scale,
		state = function()
			return state
		end,
		destroy = destroy,
		_debug = {
			fire = fire,
			-- 진행 중인 트윈을 끝 값으로 바로 보낸다(테스트 — 기다리지 않고 끝 상태를 잰다)
			settle = function()
				local tw = tween
				if tw ~= nil then
					tw:Cancel()
					tween = nil
				end
				scale.Scale = lastGoal
				if state == "idle" then
					restoreShift()
				end
			end,
			goal = function()
				return lastGoal
			end,
			isShifted = function()
				return shifted ~= nil
			end,
			connections = function()
				return #connections
			end,
		},
	}
	handles[hit] = handle
	return handle
end

return ButtonFx

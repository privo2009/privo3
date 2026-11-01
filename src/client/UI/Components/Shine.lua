--!strict
-- 강조용 빛 띠 (지시서 #21 B — docs/UI.md "UI 효과"). 계산은 UI/Logic/ShineLogic, 수치는 Shared/Config/UIFxConfig.
--
--   Shine.attach(target, { preset = "default" | "premium", priority = 숫자 })   Shine.detach(target)
--
-- 덮개: 대상의 자식 "Shine" 하나(배경 위 · 글씨 아래 — 글씨 자식들 중 가장 낮은 ZIndex보다 1 낮게). 덮개 색 = 프리셋 색,
--   UIGradient(Transparency = 가운데만 좁게 밝은 띠 · Rotation = SHINE_ANGLE)로 띠를 만들고 Offset.X를 −1 → 1로 움직인다.
--   글씨 자체의 색은 건드리지 않는다(덮개는 글씨 아래 다른 인스턴스다).
-- 모양 밖으로 새지 않게: 덮개 크기 = 대상 크기이고 띠는 그라디언트(덮개 안쪽 무늬)라 덮개 사각형 밖으로 나가지 않는다 —
--   UIGradient.Rotation은 무늬만 돌리고 덮개 자체는 돌지 않는다(그래서 ClipsDescendants가 필요 없다 — 회전된 GuiObject가
--   ClipsDescendants에 안 잘리는 문제도 생기지 않는다). 둥근 모서리(UICorner)는 덮개에 같은 반지름을 붙이고, 도착한 9-slice
--   그림(ImageLabel)이면 덮개를 같은 그림 · 같은 SliceCenter의 ImageLabel로 만들어 그림의 불투명한 곳에만 띠가 보이게 한다.
-- 움직임: 서버 · 플레이어와 무관한 클라 연출. 하나의 Heartbeat가 모든 띠를 돌린다(띠마다 루프 · 트윈 객체를 만들지 않는다 —
--   Offset = −1 + 2 × TweenService:GetValue(진행률, Sine, InOut)). 대상이나 조상이 숨으면 멈추고(덮개도 숨김) 다시 보이면 재개.
--   한 화면 상한 SHINE_MAX_ACTIVE — 보이는 것 중 우선순위 높은 순 · 붙인 순만 돌린다. 파괴되면 정리한다.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local ShineLogic = require(script.Parent.Parent.Logic.ShineLogic)

local Shine = {}

Shine.OVERLAY_NAME = "Shine"
local VISIBILITY_CHECK_SEC = 0.2

export type Options = { preset: string?, priority: number? }

type Entry = {
	target: GuiObject,
	overlay: GuiObject,
	gradient: UIGradient,
	preset: string,
	priority: number,
	order: number,
	visible: boolean,
	running: boolean,
	startAt: number,
	destroying: RBXScriptConnection,
}

local entries: { [GuiObject]: Entry } = {}
local orderSeq = 0
local heartbeat: RBXScriptConnection? = nil
local lastVisibilityCheck = -math.huge
local clock: () -> number = os.clock
local random = Random.new()

local function ease(alpha: number): number
	return TweenService:GetValue(alpha, UIFxConfig.SHINE_SWEEP_STYLE, UIFxConfig.SHINE_SWEEP_DIRECTION)
end

local NODE_ACCESS: ShineLogic.NodeAccess = {
	parentOf = function(n: any)
		return n.Parent
	end,
	isGui = function(n: any)
		return n:IsA("GuiObject")
	end,
	visibleOf = function(n: any)
		return n.Visible
	end,
	isScreenGui = function(n: any)
		return n:IsA("LayerCollector")
	end,
	enabledOf = function(n: any)
		return n.Enabled
	end,
	isRoot = function(n: any)
		return n:IsA("PlayerGui") or n == game
	end,
}

local function isText(c: Instance): boolean
	return (c:IsA("TextLabel") or c:IsA("TextBox") or c:IsA("TextButton")) and c.Name ~= "HitArea"
end

-- 덮개 ZIndex: 글씨 자식들 중 가장 낮은 것보다 1 낮게(없으면 1). 형제 순서(ZIndexBehavior Sibling) 안에서 글씨 아래 · 대상 배경 위.
function Shine.overlayZ(target: GuiObject): number
	local textZ: number? = nil
	for _, c in ipairs(target:GetChildren()) do
		if isText(c) then
			local z = (c :: GuiObject).ZIndex
			textZ = if textZ == nil then z else math.min(textZ :: number, z)
		end
	end
	return if textZ ~= nil then (textZ :: number) - 1 else 1
end

local function makeOverlay(target: GuiObject, color: Color3): GuiObject
	local overlay: GuiObject
	local img = if target:IsA("ImageLabel") or target:IsA("ImageButton") then target :: any else nil
	if img ~= nil and img.Image ~= "" then
		local o = Instance.new("ImageLabel")
		o.Image = img.Image
		o.ScaleType = img.ScaleType
		o.SliceCenter = img.SliceCenter
		o.SliceScale = img.SliceScale
		o.ImageRectOffset = img.ImageRectOffset
		o.ImageRectSize = img.ImageRectSize
		o.ImageColor3 = color
		o.BackgroundTransparency = 1
		overlay = o
	else
		local o = Instance.new("Frame")
		o.BackgroundColor3 = color
		o.BackgroundTransparency = 0
		local corner = target:FindFirstChildOfClass("UICorner")
		if corner ~= nil then
			local c = Instance.new("UICorner")
			c.CornerRadius = corner.CornerRadius
			c.Parent = o
		end
		overlay = o
	end
	overlay.Name = Shine.OVERLAY_NAME
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Selectable = false
	overlay.AutoLocalize = false
	overlay.ZIndex = Shine.overlayZ(target)
	return overlay
end

local function makeGradient(): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = UIFxConfig.SHINE_ANGLE
	local kps = {}
	for _, kp in ipairs(ShineLogic.keypoints(UIFxConfig.SHINE_BAND_HALF_WIDTH, UIFxConfig.SHINE_PEAK_TRANSPARENCY)) do
		table.insert(kps, NumberSequenceKeypoint.new(kp.time, kp.value))
	end
	g.Transparency = NumberSequence.new(kps)
	g.Color = ColorSequence.new(Color3.new(1, 1, 1)) -- 덮개 색을 그대로 보이게(곱하기 1)
	g.Offset = Vector2.new(-1, 0)
	return g
end

local function step()
	local now = clock()
	if now - lastVisibilityCheck >= VISIBILITY_CHECK_SEC then
		lastVisibilityCheck = now
		for _, e in pairs(entries) do
			e.visible = ShineLogic.isVisible(e.target, NODE_ACCESS)
		end
	end
	local list: { Entry } = {}
	local flat: { ShineLogic.Entry } = {}
	for _, e in pairs(entries) do
		table.insert(list, e)
		table.insert(flat, { visible = e.visible, priority = e.priority, order = e.order })
	end
	local activeSet: { [Entry]: boolean } = {}
	for _, i in ipairs(ShineLogic.pickActive(flat, UIFxConfig.SHINE_MAX_ACTIVE)) do
		activeSet[list[i]] = true
	end
	for _, e in ipairs(list) do
		if activeSet[e] then
			if not e.running then
				e.running = true
				e.startAt = now + random:NextNumber(0, UIFxConfig.SHINE_START_JITTER_MAX)
			end
			while now - e.startAt >= UIFxConfig.SHINE_INTERVAL do
				e.startAt += UIFxConfig.SHINE_INTERVAL
			end
			e.overlay.Visible = true
			local freeze = UIFxConfig.DEBUG_FREEZE_OFFSET
			e.gradient.Offset = Vector2.new(if freeze ~= nil then freeze else ShineLogic.offsetAt(now - e.startAt, ease), 0)
		elseif e.running or e.overlay.Visible then
			e.running = false
			e.overlay.Visible = false
			e.gradient.Offset = Vector2.new(-1, 0)
		end
	end
end

local function ensureLoop()
	if heartbeat == nil and next(entries) ~= nil then
		heartbeat = RunService.Heartbeat:Connect(step)
	elseif heartbeat ~= nil and next(entries) == nil then
		(heartbeat :: RBXScriptConnection):Disconnect()
		heartbeat = nil
	end
end

function Shine.detach(target: GuiObject)
	local e = entries[target]
	if e == nil then
		return
	end
	entries[target] = nil
	e.destroying:Disconnect()
	e.overlay:Destroy()
	ensureLoop()
end

function Shine.attach(target: GuiObject, options: Options?): boolean
	if not UIFxConfig.ENABLED then
		return false
	end
	local o: Options = options or {}
	local preset = if o.preset == "premium" then "premium" else "default"
	local existing = entries[target]
	if existing ~= nil then
		if existing.preset ~= preset then
			existing.preset = preset
			local color = ShineLogic.colorOf(preset)
			if existing.overlay:IsA("ImageLabel") then
				(existing.overlay :: ImageLabel).ImageColor3 = color
			else
				existing.overlay.BackgroundColor3 = color
			end
		end
		existing.priority = o.priority or existing.priority
		return true
	end
	local overlay = makeOverlay(target, ShineLogic.colorOf(preset))
	local gradient = makeGradient()
	gradient.Parent = overlay
	overlay.Visible = false
	overlay.Parent = target
	orderSeq += 1
	local e: Entry = {
		target = target,
		overlay = overlay,
		gradient = gradient,
		preset = preset,
		priority = o.priority or 0,
		order = orderSeq,
		visible = ShineLogic.isVisible(target, NODE_ACCESS),
		running = false,
		startAt = 0,
		destroying = target.Destroying:Connect(function()
			Shine.detach(target)
		end),
	}
	entries[target] = e
	ensureLoop()
	return true
end

function Shine.isAttached(target: GuiObject): boolean
	return entries[target] ~= nil
end

-- 테스트 전용: 시계 바꾸기 · 한 틱 돌리기 · 지금 도는 수 · 덮개 · 기본 시계로 되돌리기
Shine._debug = {
	setClock = function(f: (() -> number)?)
		clock = f or os.clock
		lastVisibilityCheck = -math.huge
	end,
	step = function()
		lastVisibilityCheck = -math.huge
		step()
	end,
	activeCount = function(): number
		local n = 0
		for _, e in pairs(entries) do
			if e.running then
				n += 1
			end
		end
		return n
	end,
	overlayOf = function(target: GuiObject): GuiObject?
		local e = entries[target]
		return if e ~= nil then e.overlay else nil
	end,
	gradientOf = function(target: GuiObject): UIGradient?
		local e = entries[target]
		return if e ~= nil then e.gradient else nil
	end,
	startAtOf = function(target: GuiObject): number?
		local e = entries[target]
		return if e ~= nil and e.running then e.startAt else nil
	end,
	isRunning = function(target: GuiObject): boolean
		local e = entries[target]
		return e ~= nil and e.running
	end,
	count = function(): number
		local n = 0
		for _ in pairs(entries) do
			n += 1
		end
		return n
	end,
}

return Shine

"""Studio 없이 Luau 테스트 파일 하나를 luau CLI로 돌린다 (지시서 #L1 — 클라우드 세션용 보조 도구).

사용:  python3 -I tools/luau_run.py --luau <luau 실행 파일> <테스트 파일> [<테스트 파일> ...]
예:    python3 -I tools/luau_run.py --luau ~/bin/luau src/server/Tests/LocaleTests.server.lua

⚠️ Play 검증이 아니다. **Instance를 만들지 않는 순수 테스트**(Config · Logic · Locale)만 돈다.
   - default.project.json의 세 갈래(Shared · Server · Client)를 가짜 인스턴스 나무로 만들고 require를 그 나무로 푼다
   - game:GetService · RunService(IsStudio=true · IsServer/IsClient는 --client) · task.wait(가짜 시계) · warn 정도만 흉내 낸다
   - Instance.new · UDim2 · Color3 등 엔진 타입은 없다 — 그런 테스트는 여기서 실패한다(Studio에서 #L2가 돌린다)
   결과는 "참고"다. 개수는 ROADMAP 테스트 현황에 적지 않는다(실측 규칙은 CLAUDE.md 절대 규칙 8).
luau CLI: https://github.com/luau-lang/luau/releases (luau-ubuntu.zip).
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOUNTS = [
    (("ReplicatedStorage", "Shared"), "src/shared"),
    (("ServerScriptService", "Server"), "src/server"),
    (("StarterPlayer", "StarterPlayerScripts", "Client"), "src/client"),
]


def instance_name(fname):
    for suffix in (".server.lua", ".client.lua", ".lua"):
        if fname.endswith(suffix):
            return fname[: -len(suffix)]
    return None


def collect():
    """[(경로 튜플, 파일 상대경로)]"""
    out = []
    for mount, rel in MOUNTS:
        base = os.path.join(ROOT, rel)
        for d, _, files in os.walk(base):
            for f in sorted(files):
                name = instance_name(f)
                if name is None:
                    continue
                sub = os.path.relpath(os.path.join(d, f), base).replace("\\", "/").split("/")[:-1]
                out.append((mount + tuple(sub) + (name,), os.path.relpath(os.path.join(d, f), ROOT)))
    return out


PRELUDE = r'''
local __files = {}
local __cache = {}
local __loading = {}
local __clock = 0
local __attrs = {}
local __isClient = __IS_CLIENT


-- ===== 엔진 타입 흉내 (값 계산만 — 렌더링 · 물리 없음) =====
local function vecType(name, fields)
	local T = {}
	local mt = {}
	local function make(...)
		local v = setmetatable({}, mt)
		local args = { ... }
		for i, f in ipairs(fields) do v[f] = args[i] or 0 end
		return v
	end
	local function map2(a, b, op)
		local out = {}
		for i, f in ipairs(fields) do
			local av = if type(a) == "number" then a else a[f]
			local bv = if type(b) == "number" then b else b[f]
			out[i] = op(av, bv)
		end
		return make(table.unpack(out))
	end
	mt.__add = function(a, b) return map2(a, b, function(x, y) return x + y end) end
	mt.__sub = function(a, b) return map2(a, b, function(x, y) return x - y end) end
	mt.__mul = function(a, b) return map2(a, b, function(x, y) return x * y end) end
	mt.__div = function(a, b) return map2(a, b, function(x, y) return x / y end) end
	mt.__unm = function(a) return map2(a, -1, function(x, y) return x * y end) end
	mt.__eq = function(a, b) for _, f in ipairs(fields) do if rawget(a, f) ~= rawget(b, f) then return false end end return true end
	mt.__tostring = function(a) local t = {}; for _, f in ipairs(fields) do table.insert(t, tostring(rawget(a, f))) end; return table.concat(t, ", ") end
	mt.__index = function(a, k)
		if k == "Magnitude" then local s = 0; for _, f in ipairs(fields) do s += rawget(a, f) ^ 2 end; return math.sqrt(s) end
		if k == "Unit" then local m = a.Magnitude; return if m == 0 then a else a / m end
		if k == "Dot" then return function(x, y) local s = 0; for _, f in ipairs(fields) do s += rawget(x, f) * rawget(y, f) end; return s end end
		if k == "Cross" then return function(x, y) return make(x.Y * y.Z - x.Z * y.Y, x.Z * y.X - x.X * y.Z, x.X * y.Y - x.Y * y.X) end end
		if k == "Lerp" then return function(x, y, t) return x + (y - x) * t end end
		if k == "Abs" then return function(x) return map2(x, 0, function(p) return math.abs(p) end) end end
		if k == "Min" then return function(x, y) return map2(x, y, math.min) end end
		if k == "Max" then return function(x, y) return map2(x, y, math.max) end end
		if k == "FuzzyEq" then return function(x, y, e) e = e or 1e-5; for _, f in ipairs(fields) do if math.abs(rawget(x, f) - rawget(y, f)) > e then return false end end return true end end
		return nil
	end
	T.new = make
	T.zero = make()
	return T, make
end
local Vector3, v3 = vecType("Vector3", { "X", "Y", "Z" })
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0); Vector3.yAxis = v3(0, 1, 0); Vector3.zAxis = v3(0, 0, 1)
local Vector2, v2 = vecType("Vector2", { "X", "Y" })
Vector2.one = v2(1, 1)
local Color3 = {}
local c3mt = { __eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end, __tostring = function(a) return string.format("%g, %g, %g", a.R, a.G, a.B) end }
c3mt.__index = function(a, k)
	if k == "ToHex" then return function(c) return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end end
	if k == "Lerp" then return function(x, y, t) return Color3.new(x.R + (y.R - x.R) * t, x.G + (y.G - x.G) * t, x.B + (y.B - x.B) * t) end end
	if k == "ToHSV" then return function(c) return 0, 0, math.max(c.R, c.G, c.B) end end
	return nil
end
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, c3mt) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHex(h) h = string.gsub(h, "#", ""); return Color3.fromRGB(tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16)) end
function Color3.fromHSV(_, _, v) return Color3.new(v, v, v) end
local UDim = {}
local udmt = { __eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end }
udmt.__add = function(a, b) return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset) end
function UDim.new(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, udmt) end
local UDim2 = {}
local ud2mt = { __eq = function(a, b) return a.X == b.X and a.Y == b.Y end }
ud2mt.__add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
ud2mt.__index = function(a, k) if k == "Width" then return a.X elseif k == "Height" then return a.Y end return nil end
function UDim2.new(xs, xo, ys, yo) return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, ud2mt) end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
local Rect = { new = function(a, b, c, d) return { Min = v2(a, b), Max = v2(c, d), Width = (c or 0) - (a or 0), Height = (d or 0) - (b or 0) } end }
local CFrame = {}
local cfmt = {}
cfmt.__index = function(a, k)
	if k == "Position" or k == "p" then return rawget(a, "__p") end
	if k == "X" then return rawget(a, "__p").X elseif k == "Y" then return rawget(a, "__p").Y elseif k == "Z" then return rawget(a, "__p").Z end
	if k == "LookVector" then return v3(0, 0, -1) elseif k == "RightVector" then return v3(1, 0, 0) elseif k == "UpVector" then return v3(0, 1, 0) end
	if k == "Inverse" then return function(c) return CFrame.new(-c.Position) end end
	if k == "PointToWorldSpace" then return function(c, v) return c.Position + v end end
	if k == "PointToObjectSpace" then return function(c, v) return v - c.Position end end
	if k == "ToWorldSpace" or k == "ToObjectSpace" then return function(c) return c end end
	if k == "Lerp" then return function(x, y, t) return CFrame.new(x.Position + (y.Position - x.Position) * t) end end
	return nil
end
cfmt.__mul = function(a, b) if getmetatable(b) == cfmt then return CFrame.new(a.Position + b.Position) end return a.Position + b end
cfmt.__add = function(a, b) return CFrame.new(a.Position + b) end
cfmt.__sub = function(a, b) return CFrame.new(a.Position - b) end
function CFrame.new(x, y, z) local p = if type(x) == "table" then x else v3(x or 0, y or 0, z or 0); return setmetatable({ __p = p }, cfmt) end
CFrame.identity = CFrame.new()
function CFrame.lookAt(p) return CFrame.new(p) end
function CFrame.Angles() return CFrame.new() end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromAxisAngle = CFrame.Angles
local function seqType() return { new = function(...) return { Keypoints = { ... } } end } end
local NumberSequence, ColorSequence = seqType(), seqType()
local NumberSequenceKeypoint, ColorSequenceKeypoint = seqType(), seqType()
local NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
local TweenInfo = { new = function(...) return { ... } end }
local BrickColor = { new = function(n) return { Name = tostring(n), Color = Color3.new() } end }
local PhysicalProperties = { new = function(...) return { ... } end }
local Font = { new = function(f) return { Family = f } end, fromEnum = function(e) return { Family = tostring(e) } end, fromName = function(n) return { Family = n } end }
local Enum = setmetatable({}, { __index = function(_, enumName)
	local items = setmetatable({}, { __index = function(t, itemName)
		local item = setmetatable({ Name = itemName, EnumType = enumName, Value = 0 }, { __tostring = function() return "Enum." .. enumName .. "." .. itemName end })
		rawset(t, itemName, item)
		return item
	end })
	items.GetEnumItems = function() return {} end
	return items
end })

-- ===== 가짜 Instance (속성 주머니 · 자식 · 신호) =====
local function newSignal()
	local conns = {}
	local sig = {}
	function sig:Connect(f) local c = { Connected = true, f = f }; table.insert(conns, c); function c:Disconnect() self.Connected = false end; return c end
	function sig:Once(f) return sig:Connect(f) end
	function sig:Wait() __clock += 0.03; return end
	function sig:Fire(...) for _, c in ipairs(conns) do if c.Connected then c.f(...) end end end
	return sig
end
local FakeInstance = {}
local EVENTS = {}
for _, e in ipairs({ "Changed", "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave",
	"Touched", "TouchEnded", "InputBegan", "InputEnded", "InputChanged", "ChildAdded", "ChildRemoved", "DescendantAdded",
	"DescendantRemoving", "AncestryChanged", "Destroying", "Event", "OnClientEvent", "OnServerEvent", "FocusLost", "Died",
	"CharacterAdded", "CharacterRemoving", "Completed", "Heartbeat", "RenderStepped", "Stepped", "PromptGamePassPurchaseFinished",
	"PromptProductPurchaseFinished", "PromptPurchaseFinished", "MessageOut", "LastInputTypeChanged", "TouchTap", "Triggered",
	"Played", "Ended", "Loaded", "MoveToFinished", "StateChanged", "HealthChanged", "PlayerAdded", "PlayerRemoving" }) do EVENTS[e] = true end
local instMethods = {}
function instMethods:FindFirstChild(name) for _, c in ipairs(rawget(self, "__kids")) do if c.Name == name then return c end end return nil end
function instMethods:FindFirstChildOfClass(cls) for _, c in ipairs(rawget(self, "__kids")) do if c.ClassName == cls then return c end end return nil end
function instMethods:FindFirstChildWhichIsA(cls) return instMethods.FindFirstChildOfClass(self, cls) end
function instMethods:WaitForChild(name)
	local c = instMethods.FindFirstChild(self, name)
	if c == nil then c = FakeInstance.new("RemoteEvent"); c.Name = name; c.Parent = self end
	return c
end
function instMethods:FireServer() end
function instMethods:FireClient() end
function instMethods:FireAllClients() end
function instMethods:InvokeServer() return nil end
function instMethods:GetChildren() return table.clone(rawget(self, "__kids")) end
function instMethods:GetDescendants() local out = {}; local function walk(n) for _, c in ipairs(rawget(n, "__kids")) do table.insert(out, c); walk(c) end end; walk(self); return out end
function instMethods:FindFirstAncestorOfClass(cls) local p = self.Parent; while p do if p.ClassName == cls then return p end; p = p.Parent end; return nil end
function instMethods:FindFirstAncestorWhichIsA(cls) return instMethods.FindFirstAncestorOfClass(self, cls) end
function instMethods:IsA(cls) return rawget(self, "__props").ClassName == cls or cls == "Instance" or cls == "GuiObject" or cls == "GuiBase2d" or cls == "BasePart" end
function instMethods:IsDescendantOf(x) local p = self.Parent; while p do if p == x then return true end; p = p.Parent end; return false end
function instMethods:Destroy() self.Parent = nil; rawget(self, "__props").__destroyed = true end
function instMethods:ClearAllChildren() for _, c in ipairs(table.clone(rawget(self, "__kids"))) do c.Parent = nil end end
function instMethods:Clone() local n = FakeInstance.new(self.ClassName); for k, v in pairs(rawget(self, "__props")) do rawget(n, "__props")[k] = v end; rawget(n, "__props").Parent = nil; return n end
function instMethods:GetAttribute(k) return rawget(self, "__attrs")[k] end
function instMethods:SetAttribute(k, v) rawget(self, "__attrs")[k] = v end
function instMethods:GetAttributes() return table.clone(rawget(self, "__attrs")) end
function instMethods:GetPropertyChangedSignal(p) local s = rawget(self, "__sigs"); s["P:" .. p] = s["P:" .. p] or newSignal(); return s["P:" .. p] end
function instMethods:GetAttributeChangedSignal(p) return instMethods.GetPropertyChangedSignal(self, "A:" .. p) end
function instMethods:GetFullName() return tostring(self.Name) end
function instMethods:PivotTo(cf) rawget(self, "__props").CFrame = cf end
function instMethods:GetPivot() return rawget(self, "__props").CFrame or CFrame.new() end
function instMethods:Play() end
function instMethods:Stop() end
function instMethods:Emit() end
function instMethods:Fire() end
function instMethods:CaptureFocus() end
local defaults = {
	AbsoluteSize = function() return v2(0, 0) end, AbsolutePosition = function() return v2(0, 0) end, TextBounds = function() return v2(0, 0) end,
	Size = function() return UDim2.new() end, Position = function() return UDim2.new() end, Visible = function() return true end,
	Text = function() return "" end, Enabled = function() return true end, Transparency = function() return 0 end,
	ViewportSize = function() return v2(1280, 720) end,
	ZIndex = function() return 1 end, LayoutOrder = function() return 0 end, TextSize = function() return 14 end,
	BackgroundTransparency = function() return 0 end, TextTransparency = function() return 0 end, ImageTransparency = function() return 0 end,
	TextStrokeTransparency = function() return 1 end, Rotation = function() return 0 end, AnchorPoint = function() return v2(0, 0) end,
	TextScaled = function() return false end, Active = function() return false end, AutoButtonColor = function() return true end,
	BorderSizePixel = function() return 1 end, Thickness = function() return 1 end, CanvasSize = function() return UDim2.new() end,
	BackgroundColor3 = function() return Color3.new(1, 1, 1) end, TextColor3 = function() return Color3.new() end,
	ImageColor3 = function() return Color3.new(1, 1, 1) end, Color = function() return Color3.new(1, 1, 1) end, Image = function() return "" end,
	MinTextSize = function() return 1 end, MaxTextSize = function() return 100 end, AspectRatio = function() return 1 end,
	DisplayOrder = function() return 0 end, ResetOnSpawn = function() return true end, Archivable = function() return true end,
}
FakeInstance.__index = function(self, k)
	local props = rawget(self, "__props")
	if props[k] ~= nil then return props[k] end
	if instMethods[k] then return instMethods[k] end
	if defaults[k] then return defaults[k]() end
	local sigs = rawget(self, "__sigs")
	if type(k) == "string" then
		local child = instMethods.FindFirstChild(self, k)
		if child then return child end
		if EVENTS[k] then
			sigs[k] = sigs[k] or newSignal()
			return sigs[k]
		end
	end
	return nil
end
FakeInstance.__newindex = function(self, k, v)
	local props = rawget(self, "__props")
	if k == "Parent" then
		local old = props.Parent
		if old ~= nil then local kids = rawget(old, "__kids"); local i = table.find(kids, self); if i then table.remove(kids, i) end end
		if v ~= nil and getmetatable(v) == FakeInstance then table.insert(rawget(v, "__kids"), self) end
	end
	props[k] = v
	local s = rawget(self, "__sigs")["P:" .. tostring(k)]
	if s then s:Fire() end
end
FakeInstance.__tostring = function(self) return tostring(rawget(self, "__props").Name) end
function FakeInstance.new(className, parent)
	local n = setmetatable({ __props = { ClassName = className, Name = className }, __kids = {}, __attrs = {}, __sigs = {} }, FakeInstance)
	if parent then n.Parent = parent end
	return n
end
local Instance = { new = FakeInstance.new }
local Random = { new = function(seed)
	local state = (seed or 1) % 2147483647
	if state <= 0 then state += 2147483646 end
	local r = {}
	local function nextf() state = (state * 48271) % 2147483647; return state / 2147483647 end
	function r:NextNumber(a, b) a = a or 0; b = b or 1; return a + (b - a) * nextf() end
	function r:NextInteger(a, b) return a + math.floor(nextf() * (b - a + 1)) end
	function r:Shuffle(t) for i = #t, 2, -1 do local j = r:NextInteger(1, i); t[i], t[j] = t[j], t[i] end end
	function r:Clone() return Random.new(state) end
	return r
end }
local DateTime = { now = function() return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 } end }
local tick = function() return os.clock() end
local typeof = function(v)
	local mt = getmetatable(v)
	if mt == FakeInstance then return "Instance" end
	if mt == c3mt then return "Color3" end
	if mt == ud2mt then return "UDim2" end
	if mt == udmt then return "UDim" end
	if mt == cfmt then return "CFrame" end
	if type(v) == "table" and rawget(v, "X") ~= nil and rawget(v, "Z") ~= nil then return "Vector3" end
	if type(v) == "table" and rawget(v, "X") ~= nil and rawget(v, "Y") ~= nil then return "Vector2" end
	return type(v)
end
local workspace = FakeInstance.new("Workspace")
workspace.CurrentCamera = FakeInstance.new("Camera")

local Node = {}
local function newNode(name, parent, className)
	local n = setmetatable({ __name = name, __parent = parent, __children = {}, __class = className or "Folder", __attrs = {} }, Node)
	if parent then parent.__children[name] = n end
	return n
end
local methods = {}
function methods:FindFirstChild(name) return rawget(self, "__children")[name] end
-- 없는 자식을 기다리면 빈 가짜 인스턴스를 만들어 준다(서버가 만드는 Remotes 폴더 등 — Studio에서는 서버가 먼저 만든다)
function methods:WaitForChild(name)
	local c = rawget(self, "__children")[name]
	if c == nil then c = FakeInstance.new("Folder"); c.Name = name; rawget(self, "__children")[name] = c end
	return c
end
function methods:GetChildren() local t = {}; for _, c in pairs(rawget(self, "__children")) do table.insert(t, c) end; return t end
function methods:GetAttribute(k) return rawget(self, "__attrs")[k] end
function methods:SetAttribute(k, v) rawget(self, "__attrs")[k] = v end
function methods:IsA(c) return rawget(self, "__class") == c end
function methods:GetFullName() local p, parts = self, {}; while p and rawget(p, "__parent") do table.insert(parts, 1, rawget(p, "__name")); p = rawget(p, "__parent") end; return table.concat(parts, ".") end
Node.__index = function(self, k)
	if k == "Name" then return rawget(self, "__name") end
	if k == "Parent" then return rawget(self, "__parent") end
	if k == "ClassName" then return rawget(self, "__class") end
	if methods[k] then return methods[k] end
	local c = rawget(self, "__children")[k]
	if c == nil then error("가짜 인스턴스에 " .. tostring(k) .. " 없음 (" .. methods.GetFullName(self) .. ")", 2) end
	return c
end
Node.__tostring = function(self) return rawget(self, "__name") end

local DataModel = newNode("game", nil, "DataModel")
local function ensure(path)
	local n = DataModel
	for _, part in ipairs(path) do n = rawget(n, "__children")[part] or newNode(part, n) end
	return n
end

local services = {}
services.RunService = {
	IsStudio = function() return true end,
	IsServer = function() return not __isClient end,
	IsClient = function() return __isClient end,
	Heartbeat = { Connect = function() return { Disconnect = function() end } end, Wait = function() __clock += 1 / 60; return 1 / 60 end },
}
local __localPlayer = nil
if __isClient then
	__localPlayer = FakeInstance.new("Player")
	__localPlayer.Name = "Tester"
	__localPlayer.UserId = 1
	__localPlayer.LocaleId = __LOCALE_ID
	FakeInstance.new("PlayerGui", __localPlayer).Name = "PlayerGui"
	FakeInstance.new("PlayerScripts", __localPlayer).Name = "PlayerScripts"
end
services.Players = { LocalPlayer = __localPlayer,
	PlayerAdded = { Connect = function() return { Disconnect = function() end } end },
	PlayerRemoving = { Connect = function() return { Disconnect = function() end } end },
	GetPlayers = function() return {} end }
services.LocalizationService = { GetTranslatorForPlayerAsync = function() error("가짜: 클라우드 표 없음") end }
services.HttpService = { JSONEncode = function(_, v) return tostring(v) end, GenerateGUID = function() return "guid" end }
services.Workspace = workspace
local function fakeService(name) local inst = FakeInstance.new(name); services[name] = inst; return inst end
for _, name in ipairs({ "GuiService", "TweenService", "UserInputService", "TextService", "MarketplaceService", "PolicyService",
	"SoundService", "StarterGui", "Lighting", "Debris", "CollectionService", "PhysicsService", "ContextActionService", "LogService",
	"DataStoreService", "MessagingService", "PathfindingService", "TeleportService", "BadgeService", "SocialService" }) do fakeService(name) end
services.TextService.GetTextSize = function() return v2(0, 0) end
services.GuiService.GetGuiInset = function() return v2(0, 0), v2(0, 0) end
services.TweenService.Create = function() return FakeInstance.new("Tween") end
services.Debris.AddItem = function() end
services.CollectionService.GetTagged = function() return {} end
services.CollectionService.AddTag = function() end
services.CollectionService.HasTag = function() return false end
services.LogService.GetLogHistory = function() return {} end
services.UserInputService.TouchEnabled = false
services.UserInputService.KeyboardEnabled = true
services.UserInputService.GetLastInputType = function() return Enum.UserInputType.Keyboard end
services.PolicyService.GetPolicyInfoForPlayerAsync = function() return { ArePaidRandomItemsRestricted = false } end


local game = setmetatable({}, { __index = function(_, k)
	if k == "GetService" then
		return function(_, name)
			if services[name] then return services[name] end
			local top = rawget(DataModel, "__children")[name]
			if top then return top end
			error("가짜 game:GetService에 " .. name .. " 없음")
		end
	end
	if k == "Workspace" then return workspace end
	return DataModel[k]
end })
local RS = ensure({ "ReplicatedStorage" })
services.ReplicatedStorage = RS

local function __require(node)
	if type(node) ~= "table" then error("require 인자가 인스턴스가 아니다: " .. tostring(node), 2) end
	local id = rawget(node, "__file")
	if id == nil then error("require 대상이 모듈이 아니다: " .. methods.GetFullName(node), 2) end
	if __cache[id] ~= nil then return __cache[id] end
	assert(not __loading[id], "순환 require: " .. id)
	__loading[id] = true
	local v = __files[id](node)
	__loading[id] = nil
	__cache[id] = v
	return v
end
local require = __require

local task
task = {
	wait = function(s) __clock += (s or 0.03); return s or 0.03 end,
	spawn = function(f, ...) local co = coroutine.create(f); local ok, e = coroutine.resume(co, ...); if not ok then print("[luau_run] task.spawn 오류: " .. tostring(e)) end; return co end,
	defer = function(f, ...) return task.spawn(f, ...) end,
	delay = function(_, f, ...) return task.spawn(f, ...) end,
	cancel = function() end,
}
local __realOs = os
local os = setmetatable({ clock = function() return __realOs.clock() + __clock end }, { __index = __realOs })
local warn = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; print("WARN " .. table.concat(t, " ")) end
'''


# ServerPackages(Wally — 저장소에 없다)의 ProfileStore 자리. 테스트는 진짜 저장소를 쓰지 않으므로 빈 껍데기면 require가 풀린다.
PROFILESTORE_STUB = r'''
__files["(stub)ProfileStore"] = function()
	local Store = {}
	Store.__index = Store
	local function newStore() return setmetatable({ Mock = setmetatable({}, Store) }, Store) end
	function Store:StartSessionAsync() return nil end
	function Store:GetAsync() return nil end
	return { New = function() return newStore() end, IsClosing = false, IsCriticalState = false,
		OnError = { Connect = function() end }, OnOverwrite = { Connect = function() end }, OnCriticalToggle = { Connect = function() end } }
end
do local n = ensure({ "ServerScriptService", "ServerPackages", "ProfileStore" }); rawset(n, "__file", "(stub)ProfileStore"); rawset(n, "__class", "ModuleScript") end
'''


def bundle(test_rel, client, locale_id):
    parts = [PRELUDE.replace("__IS_CLIENT", "true" if client else "false").replace("__LOCALE_ID", json.dumps(locale_id))]
    entries = collect()
    target_id = None
    for path, rel in entries:
        src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        src = re.sub(r"^--!\w+", "--", src, flags=re.M)
        src = re.sub(r"^(\s*)export type ", r"\1type ", src, flags=re.M)
        fid = rel.replace("\\", "/")
        parts.append(f"__files[{json.dumps(fid)}] = function(script)\n{src}\nend")
        lua_path = "{" + ", ".join(json.dumps(p) for p in path) + "}"
        parts.append(f"do local n = ensure({lua_path}); rawset(n, '__file', {json.dumps(fid)}); rawset(n, '__class', 'ModuleScript') end")
        if os.path.abspath(os.path.join(ROOT, rel)) == os.path.abspath(test_rel):
            target_id = fid
            target_path = lua_path
    if target_id is None:
        raise SystemExit(f"테스트 파일이 src 세 갈래 안에 없다: {test_rel}")
    parts.append(PROFILESTORE_STUB)
    parts.append(f"local ok, err = pcall(__files[{json.dumps(target_id)}], ensure({target_path}))\n"
                 f"if not ok then print('ERROR ' .. tostring(err)) end")
    return "\n".join(parts)


def main():
    args = sys.argv[1:]
    luau = "luau"
    client = False
    locale_id = "en-us"
    files = []
    i = 0
    while i < len(args):
        if args[i] == "--luau":
            luau = args[i + 1]
            i += 2
        elif args[i] == "--client":
            client = True
            i += 1
        elif args[i] == "--locale-id":
            locale_id = args[i + 1]
            i += 2
        else:
            files.append(args[i])
            i += 1
    worst = 0
    for f in files:
        is_client = client or f.endswith(".client.lua")
        code = bundle(os.path.abspath(f), is_client, locale_id)
        with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as tmp:
            tmp.write(code)
        r = subprocess.run([luau, tmp.name], capture_output=True, text=True)
        os.unlink(tmp.name)
        out = (r.stdout + r.stderr).strip()
        print(f"=== {f}")
        print(out)
        if r.returncode != 0 or "ERROR " in out or re.search(r"\b[1-9]\d* failed", out):
            worst = 1
    sys.exit(worst)


if __name__ == "__main__":
    main()

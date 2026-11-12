--!strict
-- 화면 연출 공용 구동기 (지시서 #25 U1 ~ U7 — docs/UI.md "UI 효과 > 화면 연출"). 계산은 UI/Logic/FxLogic, 수치는 Shared/Config/UIFxConfig.
--
--   Fx.play(key, channel, spec, apply, onDone?)   (key, channel) 하나에 연출 하나. 같은 자리에 새로 걸면 앞 것은 그 자리에서 버린다
--   Fx.finish(key, channel)                       지금 연출을 끝값으로 보내고 onDone을 부른다(닫는 중에 다른 창을 열 때 등)
--   Fx.cancel(key, channel)                       값은 그대로 두고 버린다(onDone 없음)
--   Fx.pop(gui, peak, time)                       1 → peak → 1 (레벨 · 환생 배수). 가운데 기준으로 커진다
--   Fx.popIn(gui, spec)                           spec대로 커지며 나타남(결과 모달 · 크래프팅 결과 칸)
--   Fx.modalIn(panel, tier)                       결과 모달 등장(U2) — 영웅 이상이면 더 크게 + 빛 띠 1회
--   Fx.countUp(key, from, to, applyBig)           BigNum from → to를 log10 공간에서(U3)
--   Fx.flash(frame, from, time)                   막 투명도 from → 1 한 번, 끝나면 숨김(U5)
--
-- 움직임: Heartbeat 하나가 모든 연출을 돌린다(연출마다 루프 · 트윈 객체를 만들지 않는다). 값 = FxLogic.sample(… TweenService:GetValue).
-- 연출 줄이기(FxPrefs.reduceMotion): 걸 때 바로 끝값 + onDone. 켜는 순간 돌던 것도 전부 끝값으로 보낸다.
-- 스크린샷: UIFxConfig.DEBUG_FREEZE_PROGRESS(0 ~ 1)를 넣으면 모든 연출이 그 진행률에 멈춘다(끝나지 않는다).
-- UIScale: 연출용 UIScale은 "FxScale" 하나(창은 ScreenController의 "WindowFxScale"). 다른 UIScale(버튼 반응 "ButtonFxScale" 등)이
--   이미 붙은 인스턴스에는 둘째를 달지 않는다 — 연출을 건너뛰고 Fx.skipped에 남긴다(UIScale 둘은 어느 것이 먹을지 보장이 없다).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local FxLogic = require(script.Parent.Parent.Logic.FxLogic)
local FxPrefs = require(script.Parent.Parent.FxPrefs)
local Shine = require(script.Parent.Shine)

type BigNumber = BigNum.BigNumber

local Fx = {}

Fx.SCALE_NAME = "FxScale"

type Anim = {
	from: number,
	segments: { FxLogic.Segment },
	apply: (number) -> (),
	onDone: (() -> ())?,
	startAt: number,
}

local anims: { [Instance]: { [string]: Anim } } = {}
local heartbeat: RBXScriptConnection? = nil
local clock: () -> number = os.clock

-- 건너뛴 연출(이름 · 사유) — 보고 · 테스트용
Fx.skipped = {} :: { { name: string, reason: string } }

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(alpha, style, direction)
end

local function removeAnim(key: Instance, channel: string): Anim?
	local byKey = anims[key]
	if byKey == nil then
		return nil
	end
	local a = byKey[channel]
	byKey[channel] = nil
	if next(byKey) == nil then
		anims[key] = nil
	end
	return a
end

local function finalOf(a: Anim): number
	local last = a.segments[#a.segments]
	return if last ~= nil then last.to else a.from
end

local function step()
	local now = clock()
	local freeze = UIFxConfig.DEBUG_FREEZE_PROGRESS
	local done: { { key: Instance, channel: string, anim: Anim } } = {}
	for key, byKey in pairs(anims) do
		for channel, a in pairs(byKey) do
			local t = if freeze ~= nil then FxLogic.timeAtProgress(a.segments, freeze) else now - a.startAt
			local v, finished = FxLogic.sample(a.from, a.segments, t, ease)
			if freeze ~= nil then
				finished = false
			end
			a.apply(v)
			if finished then
				table.insert(done, { key = key, channel = channel, anim = a })
			end
		end
	end
	for _, d in ipairs(done) do
		local current = anims[d.key] and anims[d.key][d.channel]
		if current == d.anim then
			removeAnim(d.key, d.channel)
			if d.anim.onDone ~= nil then
				(d.anim.onDone :: () -> ())()
			end
		end
	end
	if next(anims) == nil and heartbeat ~= nil then
		(heartbeat :: RBXScriptConnection):Disconnect()
		heartbeat = nil
	end
end

local function ensureLoop()
	if heartbeat == nil and next(anims) ~= nil then
		heartbeat = RunService.Heartbeat:Connect(step)
	end
end

function Fx.play(key: Instance, channel: string, spec: FxLogic.Spec, apply: (number) -> (), onDone: (() -> ())?)
	removeAnim(key, channel)
	if FxPrefs.reduceMotion() then
		apply(FxLogic.finalValue(spec))
		if onDone ~= nil then
			onDone()
		end
		return
	end
	apply(spec.from)
	local byKey = anims[key]
	if byKey == nil then
		byKey = {}
		anims[key] = byKey
	end
	(byKey :: { [string]: Anim })[channel] = { from = spec.from, segments = spec.segments, apply = apply, onDone = onDone, startAt = clock() }
	ensureLoop()
end

function Fx.finish(key: Instance, channel: string)
	local a = removeAnim(key, channel)
	if a ~= nil then
		a.apply(finalOf(a))
		if a.onDone ~= nil then
			(a.onDone :: () -> ())()
		end
	end
end

function Fx.cancel(key: Instance, channel: string)
	removeAnim(key, channel)
end

function Fx.isPlaying(key: Instance, channel: string): boolean
	return anims[key] ~= nil and (anims[key] :: any)[channel] ~= nil
end

-- 돌고 있는 것 전부 끝값으로(연출 줄이기를 켠 순간). onDone이 다음 연출을 걸면(크래프팅 모이기 → 결과 칸 튀기) 그것도 끝낸다(최대 10번)
function Fx.finishAll()
	for _ = 1, 10 do
		local list: { { key: Instance, channel: string } } = {}
		for key, byKey in pairs(anims) do
			for channel in pairs(byKey) do
				table.insert(list, { key = key, channel = channel })
			end
		end
		if #list == 0 then
			return
		end
		for _, kc in ipairs(list) do
			Fx.finish(kc.key, kc.channel)
		end
	end
end

FxPrefs.onChanged(function(reduceMotion: boolean)
	if reduceMotion then
		Fx.finishAll()
	end
end)

-- ===== UIScale · 가운데 기준 =====

-- 연출용 UIScale. 다른 이름의 UIScale이 이미 있으면 nil(둘째를 달지 않는다)
function Fx.scaleOf(gui: GuiObject, name: string?): UIScale?
	local want = name or Fx.SCALE_NAME
	local found: UIScale? = nil
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("UIScale") then
			if c.Name ~= want then
				table.insert(Fx.skipped, { name = gui:GetFullName(), reason = "other_uiscale:" .. c.Name })
				return nil
			end
			found = c
		end
	end
	if found ~= nil then
		return found
	end
	local s = Instance.new("UIScale")
	s.Name = want
	s.Scale = 1
	s.Parent = gui
	return s
end

type Pivot = { anchor: Vector2, position: UDim2, applied: UDim2 }
local pivots: { [GuiObject]: Pivot } = {}

local function pivotIn(gui: GuiObject, scale: UIScale)
	if pivots[gui] ~= nil or (gui.AnchorPoint.X == 0.5 and gui.AnchorPoint.Y == 0.5) then
		return
	end
	local parent = gui.Parent
	if parent == nil or not parent:IsA("GuiBase2d") then
		return
	end
	local size = gui.AbsoluteSize / math.max(scale.Scale, 1e-3)
	local applied = FxLogic.centerPosition(gui.AnchorPoint, gui.Position, size, (parent :: GuiBase2d).AbsoluteSize)
	pivots[gui] = { anchor = gui.AnchorPoint, position = gui.Position, applied = applied }
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = applied
end

local function pivotOut(gui: GuiObject)
	local p = pivots[gui]
	if p == nil then
		return
	end
	pivots[gui] = nil
	gui.AnchorPoint = p.anchor
	if gui.Position == p.applied then
		gui.Position = p.position
	else -- 그사이 다른 코드가 옮겼으면 그만큼 원래 기준으로 옮긴다
		local cur = gui.Position
		gui.Position = UDim2.new(cur.X.Scale - (p.applied.X.Scale - p.position.X.Scale), cur.X.Offset,
			cur.Y.Scale - (p.applied.Y.Scale - p.position.Y.Scale), cur.Y.Offset)
	end
end

function Fx.isPivoted(gui: GuiObject): boolean
	return pivots[gui] ~= nil
end

-- 1 → peak → 1. 가운데가 아닌 것은 튀는 동안만 가운데 기준
function Fx.pop(gui: GuiObject, peak: number, time: number): boolean
	local scale = Fx.scaleOf(gui)
	if scale == nil then
		return false
	end
	local s = scale :: UIScale
	if not FxPrefs.reduceMotion() then
		pivotIn(gui, s)
	end
	Fx.play(gui, "pop", FxLogic.popSpec(peak, time), function(v: number)
		s.Scale = v
	end, function()
		pivotOut(gui)
	end)
	return true
end

-- spec대로 커지며 나타남(가운데 기준 대상에만 쓴다 — 모달 판 · 대역 칸)
function Fx.popIn(gui: GuiObject, spec: FxLogic.Spec, onDone: (() -> ())?): boolean
	local scale = Fx.scaleOf(gui)
	if scale == nil then
		if onDone ~= nil then
			onDone()
		end
		return false
	end
	local s = scale :: UIScale
	Fx.play(gui, "pop", spec, function(v: number)
		s.Scale = v
	end, onDone)
	return true
end

-- 결과 모달(U2): 영웅 이상이면 MODAL_RARE + 빛 띠 1회(튀기가 끝난 뒤 한 번 지나간다)
function Fx.modalIn(panel: GuiObject, tier: number?)
	Fx.popIn(panel, FxLogic.modalSpec(tier))
	if FxLogic.isRare(tier) and not FxPrefs.reduceMotion() then
		Shine.attach(panel, { once = true, delay = UIFxConfig.MODAL_RARE_TIME, priority = UIFxConfig.SHINE_ONCE_PRIORITY })
	end
end

-- 모달을 숨길 때: 연출 끝값 · 빛 띠 떼기
function Fx.modalOut(panel: GuiObject)
	Fx.finish(panel, "pop")
	Shine.detach(panel)
end

-- BigNum from → to (U3). applyBig에 매 프레임 보간값을 준다 — 마지막은 정확히 to
function Fx.countUp(key: Instance, from: BigNumber, to: BigNumber, applyBig: (BigNumber) -> ())
	local a, b = { m = from.m, e = from.e }, { m = to.m, e = to.e }
	Fx.play(key, "countUp", FxLogic.progressSpec(UIFxConfig.COUNT_UP_TIME, UIFxConfig.COUNT_UP_STYLE, UIFxConfig.COUNT_UP_DIRECTION),
		function(alpha: number)
			applyBig(FxLogic.lerpLog(a, b, alpha))
		end)
end

-- 막 한 번 번쩍(U5): 보이게 하고 투명도 from → 1, 끝나면 숨김
function Fx.flash(frame: GuiObject, from: number, time: number)
	frame.Visible = true
	Fx.play(frame, "flash", { from = from, segments = {
		{ to = 1, time = time, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out },
	} }, function(v: number)
		frame.BackgroundTransparency = v
	end, function()
		frame.Visible = false
	end)
end

-- 테스트 전용: 시계 바꾸기 · 한 틱 돌리기 · 도는 수 · 기본 시계로 되돌리기
Fx._debug = {
	setClock = function(f: (() -> number)?)
		clock = f or os.clock
	end,
	step = step,
	activeCount = function(): number
		local n = 0
		for _, byKey in pairs(anims) do
			for _ in pairs(byKey) do
				n += 1
			end
		end
		return n
	end,
	isLooping = function(): boolean
		return heartbeat ~= nil
	end,
}

return Fx

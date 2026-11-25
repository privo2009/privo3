--!strict
-- 새 경제 안내 클라(지시서 #36 — DESIGN 16장 "해금 순서 · 첫 접속 안내"). 판정은 서버(OnboardingTipsService) — 여기는 받은 안내를 차례로 보여 준다.
--
--   onEvent(payload)   EconomyEvent "tip"(silent가 아니면 줄에 넣는다)
--   current()          지금 보여 줄 안내 키(줄 맨 앞) — 안내 띠(OnboardingBand)가 기존 안내가 끝난 뒤 읽는다
--   dismiss()          "알겠어요" — 다음 것으로. 띠에 보이는 시간이 TIP_SHOW_SEC를 넘어도 다음 것으로(step)
--   register(target, gui)  강조할 자리(OnboardingConfig.V2_TIPS target 이름). 지금 안내의 자리에 빛 띠(Shine — 기존 강조 방식)를 붙인다
--   step(dt, showing)  띠에 실제로 보인 시간만 센다(창이 열려 띠가 숨으면 세지 않는다)
-- 한 번만: 서버가 보낼 때 저장한다. 클라 줄은 세션 메모리다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local OnboardingTipsLogic = require(ReplicatedStorage.Shared.OnboardingTipsLogic)

local OnboardingTipsClient = {}

export type Handle = {
	onEvent: (payload: any) -> (),
	current: () -> string?,
	dismiss: () -> (),
	subscribe: (fn: () -> ()) -> (),
	register: (target: string, gui: GuiObject) -> (),
	step: (dt: number, showing: boolean) -> (),
	_debug: { queue: { string }, highlighted: () -> GuiObject? },
}

export type Options = {
	attach: ((GuiObject) -> ())?, -- 강조 붙이기(기본 Shine.attach)
	detach: ((GuiObject) -> ())?,
}

function OnboardingTipsClient.create(options: Options?): Handle
	local o = options or {}
	local attach = o.attach or function(gui: GuiObject)
		require(script.Parent.Parent.UI.Components.Shine).attach(gui, { preset = "default", priority = 2 })
	end
	local detach = o.detach or function(gui: GuiObject)
		require(script.Parent.Parent.UI.Components.Shine).detach(gui)
	end
	local queue: { string } = {}
	local targets: { [string]: GuiObject } = {}
	local listeners: { () -> () } = {}
	local shownSec = 0
	local highlighted: GuiObject? = nil

	local function current(): string?
		return queue[1]
	end

	local function rehighlight()
		local key = current()
		local tip = if key ~= nil then OnboardingTipsLogic.tipOf(key) else nil
		local want = if tip ~= nil then targets[tip.target] else nil
		if want ~= highlighted then
			if highlighted ~= nil then
				detach(highlighted)
			end
			highlighted = want
			if want ~= nil then
				attach(want)
			end
		end
	end

	local function changed()
		shownSec = 0
		rehighlight()
		for _, fn in ipairs(listeners) do
			fn()
		end
	end

	local self = {} :: Handle
	function self.onEvent(payload: any)
		if type(payload) == "table" and payload.kind == "tip" and type(payload.key) == "string" and payload.silent ~= true
			and OnboardingTipsLogic.tipOf(payload.key) ~= nil and not table.find(queue, payload.key) then
			table.insert(queue, payload.key)
			if #queue == 1 then
				changed()
			end
		end
	end
	self.current = current
	function self.dismiss()
		if #queue > 0 then
			table.remove(queue, 1)
			changed()
		end
	end
	function self.subscribe(fn: () -> ())
		table.insert(listeners, fn)
	end
	function self.register(target: string, gui: GuiObject)
		targets[target] = gui
		rehighlight()
	end
	function self.step(dt: number, showing: boolean)
		if #queue == 0 or not showing then
			return
		end
		shownSec += dt
		if shownSec >= OnboardingConfig.TIP_SHOW_SEC then
			self.dismiss()
		end
	end
	self._debug = {
		queue = queue,
		highlighted = function()
			return highlighted
		end,
	}
	return self
end

-- 클라에서 하나(EconomyV2Boot가 신호를 넣고 · HudBoot가 자리를 붙이고 · OverlayBoot의 안내 띠가 읽는다). 시간은 띠가 보일 때만 센다
local sharedHandle: Handle? = nil
local showing = false
function OnboardingTipsClient.shared(): Handle
	if sharedHandle == nil then
		local h = OnboardingTipsClient.create()
		sharedHandle = h
		RunService.Heartbeat:Connect(function(dt: number)
			h.step(dt, showing)
		end)
	end
	return sharedHandle :: Handle
end
-- 안내 띠가 지금 안내를 보이고 있는가(OnboardingBand가 알린다)
function OnboardingTipsClient.setShowing(on: boolean)
	showing = on
end

return OnboardingTipsClient

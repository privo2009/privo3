--!strict
-- ScreenGui 3층("Hud"/"Window"/"Overlay")과 "지금 무엇이 열려 있나"를 단독으로
-- 소유한다. 서버는 창이 열렸는지 모른다 — 창 열림은 표시 상태이지 게임 상태가
-- 아니고, 실제 동작의 권한은 각 서버 Service가 이미 갖고 있다 (CLAUDE.md 규칙 3).
--
-- ⚠️ 3개의 ScreenGui로 나눈 이유는 배경 흐리게 레이어의 위치다. 그 레이어는 HUD
-- 위, 창 아래여야 하는데 DisplayOrder는 ScreenGui 단위 속성이라 하나로 합치면
-- 32화면의 ZIndex를 손으로 계산하게 된다. 합치지 말 것.
--
-- 화면은 지연 생성한다 — register() 시점에는 Instance를 만들지 않고 첫 open()에서
-- builder()를 불러 만든 뒤 재사용한다. 32개를 접속마다 전부 만들면 로딩이 길어진다.
--
-- ===== U3-4: 팩토리 + 기본 인스턴스 =======================================================
--
-- "지금 무엇이 열려 있나를 단독으로 소유한다"는 설계 결정은 그대로다. 실물 코드
-- (HudBoot·화면 3종)는 여전히 이 파일 맨 아래의 기본 인스턴스 하나만 쓰고,
-- ScreenController.register(...)/open(...)/... 호출 형태도 바뀌지 않는다.
--
-- 바뀐 것은 테스트가 더 이상 그 기본 인스턴스를 공유하지 않아도 된다는 것뿐이다.
-- ScreenControllerTests가 __Test_ 접두어로 이름만 가리고 실제로는 기본 인스턴스의
-- entries를 같이 썼던 것이 사고 원인이었다 — 끝에서 부르는 closeAll()이 이름을
-- 가리지 않고 "그 순간 열려 있는 것 전부"를 닫아서, HudBoot이 이미 띄운 진짜
-- HUD까지 같이 꺼졌다(→ docs/PENDING.md 해소 기록, U3-4). 이름으로 격리를
-- 흉내 내는 대신 상태 자체를 분리한다 — ScreenController.new()로 만든 인스턴스는
-- 자기만의 entries·ScreenGui 3장을 갖고, 기본 인스턴스와는 어떤 상태도 공유하지
-- 않는다.

-- ===== 지시서 #25 U1: 창 열기 · 닫기 연출 ===============================================================
--
-- Window 층 창만. 열기 = 창 루트 UIScale("WindowFxScale") WINDOW_OPEN_SCALE_FROM → 1 + 배경 막 투명도 1 → 원래 값,
-- 닫기 = 1 → WINDOW_CLOSE_SCALE_TO + 막 페이드 아웃, 끝나면 Visible = false(지금과 같은 닫힌 상태). 수치 UIFxConfig.
-- "열렸나"(isOpen · onWindowChanged · 단일 오픈)는 연출을 기다리지 않고 지금처럼 바로 바뀐다 — 연출은 보이는 모양만 따라간다.
-- 닫히는 연출 중에 다른 창을 열면 닫히던 창은 즉시 닫는다(겹쳐 보이지 않게). 같은 창을 다시 열면 닫힘을 끝내고 다시 연다.
-- UIScale은 창 루트(Panel root — 가운데 기준)에 단다. ButtonFx("ButtonFxScale")는 버튼 그림에 달리므로 같은 인스턴스가 아니다.
-- 기본 인스턴스만 연출한다. 테스트가 만든 new()는 { animate = true }를 넘길 때만(기존 테스트는 즉시 닫힘을 전제로 쓴다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local Fx = require(script.Parent.Components.Fx)
local FxLogic = require(script.Parent.Logic.FxLogic)

local ScreenController = {}

export type Layer = "Hud" | "Window" | "Overlay"
export type Builder = () -> GuiObject

type Entry = {
	layer: Layer,
	builder: Builder,
	instance: GuiObject?,
}

export type Debug = {
	entries: { [string]: Entry },
	guis: { [Layer]: ScreenGui },
	getBlur: () -> Frame?,
}

export type ScreenControllerInstance = {
	register: (name: string, layer: Layer, builder: Builder) -> (),
	-- 닫는 연출 중인가(isOpen은 이미 false — 보이는 모양만 남아 있다). 지시서 #25 U1
	isClosing: (name: string) -> boolean,
	open: (name: string) -> (),
	close: (name: string) -> (),
	closeAll: () -> (),
	isOpen: (name: string) -> boolean,
	-- Window 층에 열린 창이 생기거나 없어질 때 부른다(지시서 #20 — 첫 접속 안내 띠가 창을 가리지 않게 숨는다). 인자 = 지금 열린 창이 있나
	onWindowChanged: (callback: (anyOpen: boolean) -> ()) -> (),
	-- 이 인스턴스의 ScreenGui 3장을 전부 파괴한다. 테스트가 끝나고 자기 트리를
	-- 통째로 버릴 때 쓴다 — 기본 인스턴스는 게임이 끝날 때까지 부르지 않는다.
	destroy: () -> (),
	_debug: Debug,
}

local DISPLAY_ORDER: { [Layer]: number } = {
	Hud = 1,
	Window = 2,
	Overlay = 3,
}

-- namePrefix가 다르면 ScreenGui 이름이 겹치지 않는다. 기본 인스턴스는 prefix=""라
-- 지금까지와 똑같이 "HudGui"/"WindowGui"/"OverlayGui"가 된다.
local function createScreenGui(layer: Layer, namePrefix: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = namePrefix .. layer .. "Gui"
	-- K10(#L2): 번역은 Strings(Locale.t)가 한다 — 로블록스 자동 번역이 우리 번역 위에 한 번 더 덮이지 않게 끈다
	gui.AutoLocalize = false
	gui.DisplayOrder = DISPLAY_ORDER[layer]
	gui.ResetOnSpawn = false
	-- false(엔진 기본값): 좌표계 원점을 로블록스 topbar 인셋만큼 엔진이 대신
	-- 내려준다. U3-2/U3-4A 관측에서 true였을 때 BloxDisplay·ChallengeInfo·MenuRail
	-- 요소들이 topbar 아래(음수 Y)로 들어갔다 — 인셋이 58px 고정 픽셀인 반면 이
	-- 프로젝트의 레이아웃은 전부 Scale이라, Scale로 여백을 흉내내면 해상도마다
	-- 어긋난다(실측: 뷰포트 593과 830에서 검사 개수가 13/9로 서로 달랐다). Scale을
	-- 하나도 안 고치고 규칙(Offset 금지)을 지키는 길은 엔진이 원점을 옮겨주게 하는
	-- 것뿐이다(U3-4B). HudLayoutTests가 이 값을 실측으로 검증한다.
	gui.IgnoreGuiInset = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local BLUR_REST_TRANSPARENCY = 0.5 -- 막의 원래 투명도(연출은 1 ↔ 이 값)
ScreenController.WINDOW_SCALE_NAME = "WindowFxScale"

local function createBlur(parent: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Blur"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = BLUR_REST_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.ZIndex = 0
	frame.Visible = false
	frame.Parent = parent
	return frame
end

-- 인스턴스 하나를 만든다. namePrefix로만 서로 다른 인스턴스의 ScreenGui를 구분한다 —
-- 그 외에는 entries·openInLayer·guis·blur 전부 이 함수 호출마다 새로 생기는
-- 지역 상태라 인스턴스끼리 아무것도 공유하지 않는다.
local function createInstance(namePrefix: string, animate: boolean): ScreenControllerInstance
	local guis: { [Layer]: ScreenGui } = {
		Hud = createScreenGui("Hud", namePrefix),
		Window = createScreenGui("Window", namePrefix),
		Overlay = createScreenGui("Overlay", namePrefix),
	}
	local blur: Frame = createBlur(guis.Window)

	local entries: { [string]: Entry } = {}

	-- layer별로 "지금 열려 있는 이름" 집합. Window는 최대 1개, Hud/Overlay는 여러 개 가능.
	local openInLayer: { [Layer]: { [string]: boolean } } = {
		Hud = {},
		Window = {},
		Overlay = {},
	}

	local windowListeners: { (boolean) -> () } = {}
	local anyWindowOpen = false
	-- 닫는 연출 중인 창(이름 → 인스턴스). isOpen은 이미 false다
	local closing: { [string]: GuiObject } = {}
	local function updateBlur()
		local visible = next(openInLayer.Window) ~= nil
		local changed = anyWindowOpen ~= visible
		anyWindowOpen = visible
		if animate then
			if visible then
				if not blur.Visible then
					blur.BackgroundTransparency = 1
					blur.Visible = true
				end
				Fx.play(blur, "dim", FxLogic.dimSpec(blur.BackgroundTransparency, true, BLUR_REST_TRANSPARENCY), function(v: number)
					blur.BackgroundTransparency = v
				end)
			elseif blur.Visible then
				Fx.play(blur, "dim", FxLogic.dimSpec(blur.BackgroundTransparency, false, BLUR_REST_TRANSPARENCY), function(v: number)
					blur.BackgroundTransparency = v
				end, function()
					blur.Visible = false
					blur.BackgroundTransparency = BLUR_REST_TRANSPARENCY
				end)
			end
		else
			blur.Visible = visible
		end
		if changed then
			for _, cb in ipairs(windowListeners) do
				task.spawn(cb, visible)
			end
		end
	end

	local function windowScale(instance: GuiObject): UIScale?
		return Fx.scaleOf(instance, ScreenController.WINDOW_SCALE_NAME)
	end

	-- 닫는 연출을 지금 끝낸다(Visible = false)
	local function finishClosing(name: string)
		local instance = closing[name]
		if instance ~= nil then
			Fx.finish(instance, "window")
			closing[name] = nil
		end
	end

	-- Overlay 레이어 안에서 여러 개가 동시에 열렸을 때의 순서·대기열 규칙은 아직 없다
	-- (docs/UI.md "6. 패널 > 레이어 우선순위 (미정)", U4 착수 전까지 정한다). 지금은
	-- 열린 순서 그대로 쌓인다 — 규칙이 정해지면 이 함수 안에서만 처리하고 호출부는
	-- 손대지 않는다. 임의로 지금 정하지 않기 위한 빈 자리다.
	local function applyOverlayOrder(_openNames: { string }) end

	-- open/close가 서로를 부르므로(Window 레이어 단독 open 규칙) 미리 지역 변수로
	-- 선언해 상호 참조가 가능하게 한다.
	local register: (name: string, layer: Layer, builder: Builder) -> ()
	local open: (name: string) -> ()
	local close: (name: string, immediate: boolean?) -> ()
	local closeAll: () -> ()
	local isOpen: (name: string) -> boolean
	local destroy: () -> ()

	-- 화면 하나를 등록한다. builder는 첫 open()에서 딱 한 번만 불린다.
	function register(name: string, layer: Layer, builder: Builder)
		assert(entries[name] == nil, "ScreenController.register: 이미 등록된 이름: " .. name)
		entries[name] = { layer = layer, builder = builder, instance = nil }
	end

	function open(name: string)
		local entry = entries[name]
		assert(entry ~= nil, "ScreenController.open: 등록되지 않은 이름: " .. name)

		if entry.instance == nil then
			local instance = entry.builder()
			instance.Parent = guis[entry.layer]
			entry.instance = instance
		end

		if entry.layer == "Window" then
			for otherName in pairs(openInLayer.Window) do
				if otherName ~= name then
					close(otherName, true) -- 다른 창은 즉시(연출 없이) 닫는다
				end
			end
			-- 닫는 연출 중인 창(이 창 자신 포함)은 지금 끝낸다 — 겹쳐 보이지 않게
			local names = {}
			for closingName in pairs(closing) do
				table.insert(names, closingName)
			end
			for _, closingName in ipairs(names) do
				finishClosing(closingName)
			end
		end

		local wasOpen = openInLayer[entry.layer][name] == true
		local instance = entry.instance :: GuiObject
		instance.Visible = true
		openInLayer[entry.layer][name] = true

		if entry.layer == "Window" then
			if animate and not wasOpen then
				local scale = windowScale(instance)
				if scale ~= nil then
					local s = scale :: UIScale
					Fx.play(instance, "window", FxLogic.windowOpenSpec(), function(v: number)
						s.Scale = v
					end)
				end
			end
			updateBlur()
		elseif entry.layer == "Overlay" then
			local openNames = {}
			for openName in pairs(openInLayer.Overlay) do
				table.insert(openNames, openName)
			end
			applyOverlayOrder(openNames)
		end
	end

	function close(name: string, immediate: boolean?)
		local entry = entries[name]
		assert(entry ~= nil, "ScreenController.close: 등록되지 않은 이름: " .. name)

		local wasOpen = openInLayer[entry.layer][name] == true
		local instance = entry.instance
		if instance ~= nil then
			local gui = instance :: GuiObject
			local scale = if entry.layer == "Window" and animate then gui:FindFirstChild(ScreenController.WINDOW_SCALE_NAME) else nil
			if entry.layer == "Window" and animate and wasOpen and not immediate and gui.Visible and scale ~= nil then
				-- 닫는 연출: 지금 크기 → 닫힘 크기, 끝나면 숨김 · 크기 1로
				local s = scale :: UIScale
				closing[name] = gui
				Fx.play(gui, "window", FxLogic.windowCloseSpec(s.Scale), function(v: number)
					s.Scale = v
				end, function()
					gui.Visible = false
					s.Scale = 1
					if closing[name] == gui then
						closing[name] = nil
					end
				end)
			else
				if closing[name] ~= nil then
					finishClosing(name)
				end
				if scale ~= nil then
					Fx.cancel(gui, "window")
					local s = scale :: UIScale
					s.Scale = 1
				end
				gui.Visible = false
			end
		end
		openInLayer[entry.layer][name] = nil

		if entry.layer == "Window" then
			updateBlur()
		end
	end

	function closeAll()
		for name in pairs(entries) do
			if isOpen(name) then
				close(name)
			end
		end
	end

	function isOpen(name: string): boolean
		local entry = entries[name]
		assert(entry ~= nil, "ScreenController.isOpen: 등록되지 않은 이름: " .. name)
		return openInLayer[entry.layer][name] == true
	end

	function destroy()
		for _, gui in pairs(guis) do
			gui:Destroy()
		end
	end

	return {
		register = register,
		open = open,
		close = close,
		closeAll = closeAll,
		isOpen = isOpen,
		isClosing = function(name: string): boolean
			return closing[name] ~= nil
		end,
		onWindowChanged = function(callback: (boolean) -> ())
			table.insert(windowListeners, callback)
		end,
		destroy = destroy,
		-- 테스트 전용 내부 접근. 화면 코드는 쓰지 않는다.
		_debug = {
			entries = entries,
			guis = guis,
			getBlur = function(): Frame?
				return blur
			end,
		},
	}
end

-- 실물 코드(HudBoot·화면 3종)가 쓰는 단 하나의 인스턴스. prefix=""라 ScreenGui
-- 이름이 지금까지와 동일하다("HudGui"/"WindowGui"/"OverlayGui").
local defaultInstance = createInstance("", UIFxConfig.ENABLED)

-- 기존 호출 형태(ScreenController.register(...) 등)를 그대로 유지한다 — 그냥
-- 기본 인스턴스의 같은 이름 함수를 그대로 참조만 옮긴 것이라 인자·동작이 완전히
-- 같다. HudBoot.client.lua와 화면 3종은 이 파일을 고칠 필요가 없다.
ScreenController.register = defaultInstance.register
ScreenController.open = defaultInstance.open
ScreenController.close = defaultInstance.close
ScreenController.closeAll = defaultInstance.closeAll
ScreenController.isOpen = defaultInstance.isOpen
ScreenController.isClosing = defaultInstance.isClosing
ScreenController.onWindowChanged = defaultInstance.onWindowChanged
ScreenController._debug = defaultInstance._debug

-- 자기만의 entries·ScreenGui 3장을 가진 새 인스턴스를 만든다. 테스트 전용이다 —
-- 실물 코드는 절대 부르지 않는다(기본 인스턴스 하나만 쓴다는 설계를 유지).
--
-- namePrefix는 필수다. 기본 인스턴스의 ScreenGui 이름("HudGui" 등)과 겹치지
-- 않아야 하고, new()를 여러 번 불러도(예: 테스트 파일이 여럿이어도) 서로
-- 겹치면 안 된다 — 그래서 namePrefix 뒤에 호출 순번을 항상 덧붙인다. 호출자가
-- 같은 문자열을 두 번 넘겨도 최종 이름은 자동으로 달라진다.
local nextInstanceId = 1
-- options.animate = true면 Window 층 열기 · 닫기 연출(지시서 #25 U1)을 켠다 — FxTests만 쓴다
function ScreenController.new(namePrefix: string, options: { animate: boolean? }?): ScreenControllerInstance
	assert(
		type(namePrefix) == "string" and #namePrefix > 0,
		"ScreenController.new: namePrefix가 필요하다 (빈 문자열은 기본 인스턴스 전용이다)"
	)
	local id = nextInstanceId
	nextInstanceId += 1
	return createInstance(string.format("%s%d_", namePrefix, id), options ~= nil and options.animate == true)
end

return ScreenController

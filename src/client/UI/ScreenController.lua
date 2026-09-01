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

local Players = game:GetService("Players")

local ScreenController = {}

export type Layer = "Hud" | "Window" | "Overlay"
export type Builder = () -> GuiObject

type Entry = {
	layer: Layer,
	builder: Builder,
	instance: GuiObject?,
}

local DISPLAY_ORDER: { [Layer]: number } = {
	Hud = 1,
	Window = 2,
	Overlay = 3,
}

local guis: { [Layer]: ScreenGui } = {}
local blur: Frame? = nil

local entries: { [string]: Entry } = {}

-- layer별로 "지금 열려 있는 이름" 집합. Window는 최대 1개, Hud/Overlay는 여러 개 가능.
local openInLayer: { [Layer]: { [string]: boolean } } = {
	Hud = {},
	Window = {},
	Overlay = {},
}

local function createScreenGui(layer: Layer): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = layer .. "Gui"
	gui.DisplayOrder = DISPLAY_ORDER[layer]
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function createBlur(parent: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Blur"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.ZIndex = 0
	frame.Visible = false
	frame.Parent = parent
	return frame
end

local function ensureInitialized()
	if guis.Hud ~= nil then
		return
	end
	guis.Hud = createScreenGui("Hud")
	guis.Window = createScreenGui("Window")
	guis.Overlay = createScreenGui("Overlay")
	blur = createBlur(guis.Window)
end

ensureInitialized()

-- 화면 하나를 등록한다. builder는 첫 open()에서 딱 한 번만 불린다.
function ScreenController.register(name: string, layer: Layer, builder: Builder)
	assert(entries[name] == nil, "ScreenController.register: 이미 등록된 이름: " .. name)
	entries[name] = { layer = layer, builder = builder, instance = nil }
end

local function updateBlur()
	local visible = next(openInLayer.Window) ~= nil
	assert(blur ~= nil, "ScreenController: blur가 초기화되지 않음")
	;(blur :: Frame).Visible = visible
end

-- Overlay 레이어 안에서 여러 개가 동시에 열렸을 때의 순서·대기열 규칙은 아직 없다
-- (docs/UI.md "6. 패널 > 레이어 우선순위 (미정)", U4 착수 전까지 정한다). 지금은
-- 열린 순서 그대로 쌓인다 — 규칙이 정해지면 이 함수 안에서만 처리하고 호출부는
-- 손대지 않는다. 임의로 지금 정하지 않기 위한 빈 자리다.
local function applyOverlayOrder(_openNames: { string }) end

function ScreenController.open(name: string)
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
				ScreenController.close(otherName)
			end
		end
	end

	;(entry.instance :: GuiObject).Visible = true
	openInLayer[entry.layer][name] = true

	if entry.layer == "Window" then
		updateBlur()
	elseif entry.layer == "Overlay" then
		local openNames = {}
		for openName in pairs(openInLayer.Overlay) do
			table.insert(openNames, openName)
		end
		applyOverlayOrder(openNames)
	end
end

function ScreenController.close(name: string)
	local entry = entries[name]
	assert(entry ~= nil, "ScreenController.close: 등록되지 않은 이름: " .. name)

	if entry.instance ~= nil then
		(entry.instance :: GuiObject).Visible = false
	end
	openInLayer[entry.layer][name] = nil

	if entry.layer == "Window" then
		updateBlur()
	end
end

function ScreenController.closeAll()
	for name in pairs(entries) do
		if ScreenController.isOpen(name) then
			ScreenController.close(name)
		end
	end
end

function ScreenController.isOpen(name: string): boolean
	local entry = entries[name]
	assert(entry ~= nil, "ScreenController.isOpen: 등록되지 않은 이름: " .. name)
	return openInLayer[entry.layer][name] == true
end

-- 테스트 전용 내부 접근. 화면 코드는 쓰지 않는다.
ScreenController._debug = {
	entries = entries,
	guis = guis,
	getBlur = function(): Frame?
		return blur
	end,
}

return ScreenController

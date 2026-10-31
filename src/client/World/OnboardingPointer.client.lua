--!strict
-- 첫 접속 안내 3D 빛기둥 (지시서 #20 O1). 클라 전용 파트 1개(만들어 두고 자리만 옮긴다 — 반복 생성 없음, 절대 규칙 4 · 금지 사항).
-- 자리는 UI/Logic/OnboardingLogic.target: 2 입장 게이트 · 3 지금 런 층의 블록 자리 · 4 그 층 수령 발판 · 5 클릭 파워 패드 2번.
-- 1단계(클릭)와 끝남은 대상이 없다 — 기둥을 숨긴다(Parent = nil). 충돌 · 터치 · 레이 판정이 없는 장식이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Store = require(script.Parent.Parent.UI.Store)
local OnboardingLogic = require(script.Parent.Parent.UI.Logic.OnboardingLogic)

local HEIGHT = 40 -- 기둥 높이(스터드) — 멀리서도 보이게. 바닥(y 0)에서 위로
local WIDTH = 2.5

local beam = Instance.new("Part")
beam.Name = "OnboardingPointer"
beam.Anchored = true
beam.CanCollide = false
beam.CanTouch = false
beam.CanQuery = false
beam.CastShadow = false
beam.Material = Enum.Material.Neon
beam.Color = UiTheme.Colors.cashout.base
beam.Transparency = 0.35
beam.Size = Vector3.new(WIDTH, HEIGHT, WIDTH)

local runStage = 1

local function render()
	local target = OnboardingLogic.target(Store.get("onboarding"), runStage)
	if target == nil then
		beam.Parent = nil
		return
	end
	beam.CFrame = CFrame.new(target.X, HEIGHT / 2, target.Z)
	beam.Parent = Workspace
end

Store.subscribe("onboarding", render)
Remotes.getClient().runStateChanged.OnClientEvent:Connect(function(payload: Remotes.RunStateChangedPayload)
	if type(payload) == "table" and type(payload.state) == "table" and type(payload.state.stage) == "number" then
		runStage = if payload.active then payload.state.stage else 1
	end
	render()
end)
render()

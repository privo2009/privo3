--!strict
-- 로딩 (OverlayGui 차단층, 큐 1순위 — docs/UI.md "6. 패널 > 레이어 우선순위"). U4, 지시서 #5.
--
-- 서버의 첫 PlayerState(Net/PlayerStateClient)를 받을 때까지 화면 전체를 덮는다. 덮인 동안 HUD는
-- Store의 더미값을 들고 있으므로, 이 화면이 있어야 유저가 가짜 숫자를 보지 않는다.
-- TIMEOUT_SEC 안에 못 받으면 닫고 오류(알림층)로 넘긴다 — 로딩 뒤에 오류가 깔리면 무한 로딩으로
-- 보인다(UI.md "오류가 최상단인 이유").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local OverlayParts = require(script.Parent.OverlayParts)

local LoadingScreen = {}

-- 첫 상태를 기다리는 시간(초). 프로필 로드(ProfileStore)는 보통 1~2초다. 넉넉히 잡고, 넘으면
-- 데이터 쪽 문제로 보고 알린다. Claude가 정한 표시 시간(세션 로그).
LoadingScreen.TIMEOUT_SEC = 20

export type State = "loading" | "done" | "timeout"

-- 순수 판정: 받았으면 done, 시간을 넘겼으면 timeout, 아니면 loading.
function LoadingScreen.decide(received: boolean, elapsedSec: number): State
	if received then
		return "done"
	end
	if elapsedSec >= LoadingScreen.TIMEOUT_SEC then
		return "timeout"
	end
	return "loading"
end

LoadingScreen.TEXT = Locale.t("overlay.loading")

export type Handle = { root: Frame }

function LoadingScreen.create(): Handle
	local root = Instance.new("Frame")
	root.Name = "Loading"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundColor3 = UiTheme.Colors.neutral.dark
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.ZIndex = OverlayParts.Z.blocking
	root.Active = true -- 차단층: 아래 HUD로 입력이 새지 않게

	local label = OverlayParts.textRow("Text", LoadingScreen.TEXT, "large", nil)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.5, TextScale.Levels.large.heightFraction)
	label.ZIndex = OverlayParts.Z.blocking
	label.Parent = root

	return { root = root }
end

return LoadingScreen

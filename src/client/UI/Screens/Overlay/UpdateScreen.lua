--!strict
-- 업데이트 중 화면(지시서 #48 1부 소프트 셧다운). OverlayGui 맨 위(알림층) — 화면 전체를 덮고 입력을 막는다.
-- 옛 서버가 저장하고 대기실로 옮기는 동안 · 대기실에서 새 서버로 다시 보낼 때까지 보인다.
-- 같은 모양을 순간이동 화면(TeleportService:SetTeleportGui)으로도 넘긴다 — 옮기는 사이에도 같은 글이 보인다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local OverlayParts = require(script.Parent.OverlayParts)

local UpdateScreen = {}

UpdateScreen.TEXT = Locale.t("overlay.updating")

export type Handle = { root: Frame }

-- 화면 한 장(root Frame). zIndex를 안 주면 알림층 맨 위
function UpdateScreen.create(zIndex: number?): Handle
	local z = zIndex or (OverlayParts.Z.notice + 1)
	local root = Instance.new("Frame")
	root.Name = "UpdateScreen"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundColor3 = UiTheme.Colors.neutral.dark
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.ZIndex = z
	root.Active = true -- 아래로 입력이 새지 않게

	local label = OverlayParts.textRow("Text", UpdateScreen.TEXT, "large", nil)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.7, TextScale.Levels.large.heightFraction)
	label.ZIndex = z
	label.Parent = root

	return { root = root }
end

-- 순간이동 화면용 ScreenGui(같은 모양 — SetTeleportGui는 ScreenGui를 받는다)
function UpdateScreen.teleportGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpdateTeleportGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	UpdateScreen.create(1).root.Parent = gui
	return gui
end

return UpdateScreen

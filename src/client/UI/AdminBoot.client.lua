--!strict
-- 관리 도구 클라 배선(지시서 #48 4부). 서버가 이 사람을 관리자로 판정해 AdminResult{ action = "hello" }를 보낼 때만
-- 따로 된 ScreenGui("AdminGui") 하나에 여는 버튼 · 관리 창을 만든다. 관리자가 아니면 아무것도 만들지 않는다(서버도 답하지 않는다).
-- HUD · 창 층(ScreenController)과 섞지 않는다 — 게임 화면 검사(HUD 배치 · 창 목록)에 관리 도구가 끼지 않게.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Kit = require(script.Parent.Components.Kit)
local AdminWindow = require(script.Parent.Screens.Window.AdminWindow)

local channels = Remotes.getClient()
local window: AdminWindow.Handle? = nil

local function build()
	if window ~= nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.AutoLocalize = false -- K10(글자는 Strings에서)
	local holder = Instance.new("Frame")
	holder.Name = "OpenHolder"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0.01, 0.62)
	holder.Size = UDim2.fromScale(0.09, 0.07)
	holder.Parent = gui
	local _, _, openHit = Kit.labeledButton("AdminOpen", holder, "gray", 0, 0, 1, 1, Locale.t("admin.open"))
	local w = AdminWindow.create({
		send = function(payload: any)
			channels.adminRequest:FireServer(payload)
		end,
		onClose = function()
			if window ~= nil then
				window.root.Visible = false
			end
		end,
	})
	w.root.Visible = false
	w.root.Parent = gui
	window = w
	openHit.Activated:Connect(function()
		w.root.Visible = not w.root.Visible
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	print("[AdminBoot] 관리자 — 관리 창 만듦")
end

channels.adminResult.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.action == "hello" and payload.ok == true then
		build()
		return
	end
	if window ~= nil then
		window.onResult(payload)
	end
end)

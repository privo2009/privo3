--!strict
-- 로비 본체 색 (Phase 6 지시서 #8 M4). 클릭 파워 패드 · 운동기구 파트를 내 해금 상태대로 내 화면에서만 칠한다.
-- 첫 직접 플레이에서 패드 본체가 전부 회색이라 어디까지 열렸는지 안 보였다.
--
-- 해금은 플레이어마다 다르다(패드 = 이번 생애 누적 블럭스 lifeBlox, 기구 = 환생 수 rebirths) — 서버 파트 색으로는
-- 표현할 수 없다. 클라가 Color를 바꿔도 서버 · 다른 플레이어에게 복제되지 않는다(CashoutPadRenderer와 같은 방식).
-- 서버(PadService · GymService)는 파트 색을 정하지 않으므로 여기서 칠한 값이 덮이지 않는다.
-- 어떤 역할색인가는 WorldLabelLogic.padBodyRole · gymBodyRole(순수)이 정한다.
--
-- 공허 훈련 구역(로벅스 전용)은 프리미엄(남색) + 금테. 금테는 Highlight 외곽선 하나다(처음에 한 번만 만든다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Workspace = game:GetService("Workspace")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local WorldLabelLogic = require(script.Parent.WorldLabelLogic)
local Store = require(script.Parent.Parent.UI.Store)

local padFolder: Instance? = nil
local gymFolder: Instance? = nil
local voidEdge: Highlight? = nil

local function paintPads()
	if padFolder == nil then
		return
	end
	local lifeBlox = Store.get("lifeBlox")
	for _, part in ipairs((padFolder :: Instance):GetChildren()) do
		local index = part:GetAttribute("PadIndex")
		if part:IsA("BasePart") and type(index) == "number" then
			part.Color = UiTheme.Colors[WorldLabelLogic.padBodyRole(index, lifeBlox)].base
		end
	end
end

local function paintGyms()
	if gymFolder == nil then
		return
	end
	local rebirths = Store.get("rebirths")
	local shop = Store.get("shop")
	-- 선해금 · 공허 게임패스(지시서 #17)도 열린 색 — 서버와 같은 GymLayout.shopUnlocked
	local unlocked = GymLayout.shopUnlocked(if type(shop) == "table" then shop.gymUnlocks else nil, ShopEffectsLogic.fromSummary(shop).owns)
	for _, part in ipairs((gymFolder :: Instance):GetChildren()) do
		local index = part:GetAttribute("GymIndex")
		if part:IsA("BasePart") and type(index) == "number" then
			local role = WorldLabelLogic.gymBodyRole(index, rebirths, unlocked)
			part.Color = UiTheme.Colors[role].base
			if role == "premium" and voidEdge == nil then
				local edge = Instance.new("Highlight")
				edge.Name = "VoidEdge"
				edge.FillTransparency = 1
				edge.OutlineColor = UiTheme.Colors.cashout.base -- 금테
				edge.DepthMode = Enum.HighlightDepthMode.Occluded
				edge.Adornee = part
				edge.Parent = part
				voidEdge = edge
			end
		end
	end
end

Store.subscribe("lifeBlox", paintPads)
Store.subscribe("rebirths", paintGyms)
Store.subscribe("shop", paintGyms)

task.spawn(function()
	local folder = Workspace:WaitForChild("ClickPads")
	padFolder = folder
	folder.ChildAdded:Connect(paintPads)
	paintPads()
end)

task.spawn(function()
	local folder = Workspace:WaitForChild("Gyms")
	gymFolder = folder
	folder.ChildAdded:Connect(paintGyms)
	paintGyms()
end)


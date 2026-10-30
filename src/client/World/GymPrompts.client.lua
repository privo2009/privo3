--!strict
-- 잠긴 운동기구 옆 "로벅스로 열기" 프롬프트 (지시서 #17 5단계 — DESIGN 9장 "창별 상품 버튼" · docs/UI.md "지시서 #17").
--
-- 기구마다 클라 전용 ProximityPrompt를 하나 붙인다(서버에 만들지 않는다 — 내 기구 잠김은 나만의 상태다).
-- 켤지 · 글자 · 상품 키는 WorldLabelLogic.gymPrompt(순수): 아직 안 열린 기구만(환생 수 · 선해금 · 공허 게임패스 모두 아님),
-- 대시보드에 등록된 상품만. 누르면 Net/PurchaseClient로 구매 요청 — 판정 · 프롬프트는 서버(PurchaseRequestService — already_unlocked 등).
-- 공허 훈련 구역은 게임패스, 나머지는 선해금 개발자 상품이다(GymConfig.getShopKey). 글자는 Strings(Locale.t) — 화면 문장 규칙.
-- 거부 · 완료 문구는 OverlayBoot의 구매 결과 토스트가 이미 띄운다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)

local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local WorldLabelLogic = require(script.Parent.WorldLabelLogic)
local Store = require(script.Parent.Parent.UI.Store)
local PurchaseClient = require(script.Parent.Parent.Net.PurchaseClient)

local PROMPT_NAME = "BuyPrompt"
local MAX_DISTANCE = 10 -- studs. 기구 위 · 옆에 섰을 때만(라벨 표시 거리와 같은 감각)

local prompts: { [number]: ProximityPrompt } = {}

local function unlockedFn(): (number) -> boolean
	local shop = Store.get("shop")
	return GymLayout.shopUnlocked(if type(shop) == "table" then shop.gymUnlocks else nil, ShopEffectsLogic.fromSummary(shop).owns)
end

local function refresh(index: number)
	local prompt = prompts[index]
	if prompt == nil then
		return
	end
	local p = WorldLabelLogic.gymPrompt(index, Store.get("rebirths"), unlockedFn())
	prompt.Enabled = p.enabled
	prompt.ActionText = p.actionText
	prompt.ObjectText = p.objectText
	prompt:SetAttribute("ProductKey", p.key)
end

local function refreshAll()
	for index in pairs(prompts) do
		refresh(index)
	end
end

local function attach(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local index = part:GetAttribute("GymIndex")
	if type(index) ~= "number" or prompts[index] ~= nil then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		local key = prompt:GetAttribute("ProductKey")
		if prompt.Enabled and type(key) == "string" then
			PurchaseClient.get().request(key)
		end
	end)
	prompts[index] = prompt
	refresh(index)
	-- 기구는 스트리밍으로 늦게 들어온다 — 다 붙었을 때 한 줄
	local n = 0
	for _ in pairs(prompts) do
		n += 1
	end
	if n == GymConfig.getCount() then
		print(string.format("[GymPrompts] 운동기구 로벅스 프롬프트 %d개 붙음", n))
	end
end

Store.subscribe("rebirths", refreshAll)
Store.subscribe("shop", refreshAll) -- 선해금 · 공허 게임패스 · 등록

task.spawn(function()
	local folder = Workspace:WaitForChild("Gyms")
	folder.ChildAdded:Connect(attach)
	for _, part in ipairs(folder:GetChildren()) do
		attach(part)
	end
end)

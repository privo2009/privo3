--!strict
-- 손에 든 곡괭이(지시서 #34 — DESIGN 16장 "손에 든 곡괭이"). ⚠️ 플래그 ECONOMY_V2 뒤 — 꺼져 있으면 Bootstrap이 init하지 않는다(붙이지 않는다).
--
-- 다른 플레이어에게도 보여야 하므로 서버가 캐릭터에 붙인다(복제). 파편 · 파티클이 아니라 장비 모델 하나라 절대 규칙 4와 다르다.
-- 지금은 임시 도형(자루 + 머리 · 머리는 등급 색)이다. 에셋 자리: EconomyV2Config.PICKAXE_VISUALS[id] = { modelId, swingAnimId } —
-- 지금은 값이 있어도 임시 도형을 쓴다(런타임 교체 방식은 #36 에셋 주문서에서 정한다 — #32 판단과 같다). 휘두르기 애니메이션은 nil이면 없음.
-- 붙이는 곳: R15 오른손 "RightHand"(공식 문서 캐릭터 몸 규격), 없으면 "Right Arm"(R6 — 문서에 파트 이름이 적혀 있지 않아 Play로 확인한다).
-- 고정은 WeldConstraint(Part0 · Part1) — 붙이기 전에 자리를 맞춰 두고 묶는다(물리 없음 · Massless · 충돌 · 터치 · 질의 끔).
-- 갱신: 다시 스폰(CharacterAdded) · 프로필 로드 · 장착 바꿈(EquipmentService가 refresh를 부른다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)

local HeldPickaxeService = {}

HeldPickaxeService.MODEL_NAME = "HeldPickaxe"
HeldPickaxeService.HAND_NAMES = { "RightHand", "Right Arm" }

local function handOf(character: Model): BasePart?
	for _, name in ipairs(HeldPickaxeService.HAND_NAMES) do
		local p = character:FindFirstChild(name)
		if p ~= nil and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = parent
	return p
end

-- 캐릭터에 장착 곡괭이를 붙인다(있던 것은 지운다 — 언제나 하나). yield하지 않는다. 손이 없거나 모르는 곡괭이면 nil(붙인 것도 지운다)
function HeldPickaxeService.attach(character: Model, id: string?): Model?
	local old = character:FindFirstChild(HeldPickaxeService.MODEL_NAME)
	if old ~= nil then
		old:Destroy()
	end
	local def = if id ~= nil then EconomyV2Logic.pickaxe(id) else nil
	local hand = handOf(character)
	if def == nil or hand == nil then
		return nil
	end
	local size = Config.HELD_PICKAXE_SIZE
	local model = Instance.new("Model")
	model.Name = HeldPickaxeService.MODEL_NAME
	model:SetAttribute("PickaxeId", def.id)
	local handle = part("Handle", size.handle, Color3.fromRGB(110, 75, 45), model)
	-- 손 아래로 쥐고 앞으로 뻗는다: 자루 Y축이 손의 앞(−Z)을 보게 눕힌다(임시 도형 자리 — 모델이 오면 #36에서 다시)
	handle.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -size.handle.Y / 2 + 0.3) * CFrame.Angles(math.rad(-90), 0, 0)
	local head = part("Head", size.head, UiTheme.equipGradeColor(def.rarity), model)
	head.Material = Enum.Material.Metal
	head.CFrame = handle.CFrame * CFrame.new(0, size.handle.Y / 2, 0)
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = hand
	w1.Part1 = handle
	w1.Parent = handle
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = handle
	w2.Part1 = head
	w2.Parent = head
	model.PrimaryPart = handle
	model.Parent = character
	return model
end

-- ===== 바깥 세계 이음매 ==================================================================================

HeldPickaxeService._deps = {
	getEquipped = function(player: Player): string?
		return require(script.Parent.InventoryService).getEquipped(player, "pickaxe")
	end,
}

function HeldPickaxeService.refresh(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	HeldPickaxeService.attach(character, HeldPickaxeService._deps.getEquipped(player))
end

local initialized = false

function HeldPickaxeService._initialized(): boolean
	return initialized
end

function HeldPickaxeService.init()
	if initialized then
		return
	end
	initialized = true
	local function onCharacter(player: Player, character: Model)
		task.spawn(function()
			-- 몸 파트는 캐릭터가 들어온 뒤 조금 늦게 생길 수 있다(상한 5초 — 없으면 R6 이름으로)
			character:WaitForChild("RightHand", 5)
			if player.Character == character then
				HeldPickaxeService.refresh(player)
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			onCharacter(player, character)
		end)
		if player.Character ~= nil then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	ProfileManager.onLoaded(function(player: Player)
		HeldPickaxeService.refresh(player)
	end)
	print("[HeldPickaxeService] 손에 든 곡괭이 시작(임시 도형)")
end

return HeldPickaxeService

--!strict
-- 손에 든 곡괭이(지시서 #34 — DESIGN 16장 "손에 든 곡괭이").
--
-- 다른 플레이어에게도 보여야 하므로 서버가 캐릭터에 붙인다(복제). 파편 · 파티클이 아니라 장비 모델 하나라 절대 규칙 4와 다르다.
-- 지금은 임시 도형(자루 + 머리 · 머리는 등급 색)이다. 에셋 자리: EconomyV2Config.PICKAXE_VISUALS[id] = { modelId, swingAnimId } —
-- #36(DESIGN 16장 "에셋 교체 방식"): 서버 AssetLoader가 불러 둔 틀(AssetSlots "pick_<id>" — Model · 안에 "Handle" 파트)이 있으면 복제해 붙인다 —
-- Handle을 임시 자루 자리에 두고 손에 묶고, 나머지 파트는 Handle에 묶는다. 틀이 없으면 임시 도형.
-- 휘두르기(swingAnimId): 펀치마다(AttackService.onPunched) 캐릭터 Animator로 재생 — 게임 주인 계정 · 그룹 소유 애니메이션이어야 재생된다. nil이면 없음.
-- 붙이는 곳: R15 오른손 "RightHand"(공식 문서 캐릭터 몸 규격), 없으면 "Right Arm"(R6 — 문서에 파트 이름이 적혀 있지 않아 Play로 확인한다).
-- 고정은 WeldConstraint(Part0 · Part1) — 붙이기 전에 자리를 맞춰 두고 묶는다(물리 없음 · Massless · 충돌 · 터치 · 질의 끔).
-- 갱신: 다시 스폰(CharacterAdded) · 프로필 로드 · 장착 바꿈(EquipmentService가 refresh를 부른다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)

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
	local grip = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -size.handle.Y / 2 + 0.3) * CFrame.Angles(math.rad(-90), 0, 0)
	-- 모델 틀(#36)
	local tpl = HeldPickaxeService._template("pick_" .. def.id)
	local tplHandle = if tpl ~= nil and tpl:IsA("Model") then tpl:FindFirstChild("Handle", true) else nil
	if tpl ~= nil and tplHandle ~= nil and tplHandle:IsA("BasePart") then
		local m = tpl:Clone()
		m.Name = HeldPickaxeService.MODEL_NAME
		m:SetAttribute("PickaxeId", def.id)
		m:SetAttribute("FromAsset", true)
		local h = m:FindFirstChild("Handle", true) :: BasePart
		m.PrimaryPart = h
		m:PivotTo(grip * h.CFrame:Inverse() * m:GetPivot()) -- Handle이 자루 자리(grip)에 오게: 새 Handle = 새 피벗 · 피벗⁻¹ · Handle
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Massless = true
				if d ~= h then
					local w = Instance.new("WeldConstraint")
					w.Part0 = h
					w.Part1 = d
					w.Parent = d
				end
			end
		end
		local wh = Instance.new("WeldConstraint")
		wh.Part0 = hand
		wh.Part1 = h
		wh.Parent = h
		m.Parent = character
		return m
	end
	local model = Instance.new("Model")
	model.Name = HeldPickaxeService.MODEL_NAME
	model:SetAttribute("PickaxeId", def.id)
	local handle = part("Handle", size.handle, Config.HELD_PICKAXE_HANDLE_COLOR, model)
	-- 손 아래로 쥐고 앞으로 뻗는다: 자루 Y축이 손의 앞(−Z)을 보게 눕힌다(임시 도형 자리 — 모델이 오면 #36에서 다시)
	handle.CFrame = grip
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

-- 모델 틀 찾기(테스트는 가짜 틀로 바꾼다)
HeldPickaxeService._template = function(key: string): Instance?
	return AssetSlots.template(key)
end

-- 휘두르기(#36): 장착 곡괭이의 swingAnimId가 있으면 캐릭터 Animator로 재생한다. 재생했으면 true(없으면 false — 임시 도형 · 애니메이션 없음)
-- 트랙은 캐릭터 · 애니메이션마다 한 번 만든다(Animator:LoadAnimation — 반복 생성 없음)
local tracks: { [Model]: { id: string, track: AnimationTrack } } = {}
function HeldPickaxeService.swingAnimationId(id: string?): string?
	local v = if id ~= nil then Config.PICKAXE_VISUALS[id] else nil
	return if v ~= nil then AssetSlots.contentId(v.swingAnimId) else nil
end
function HeldPickaxeService.swing(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local content = HeldPickaxeService.swingAnimationId(HeldPickaxeService._deps.getEquipped(player))
	if content == nil then
		return false
	end
	local cached = tracks[character]
	if cached == nil or cached.id ~= content then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
		if animator == nil then
			return false
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = content
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if not ok or track == nil then
			return false
		end
		cached = { id = content, track = track }
		tracks[character] = cached
		character.Destroying:Connect(function()
			tracks[character] = nil
		end)
	end
	(cached :: any).track:Play()
	return true
end

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
	-- 휘두르기(#36): 펀치가 맞을 때마다(애니메이션 ID가 있을 때만 — 없으면 아무것도 하지 않는다)
	require(script.Parent.AttackService).onPunched(function(player: Player, outcome: any)
		if outcome ~= nil and outcome.result == "ok" then
			HeldPickaxeService.swing(player)
		end
	end)
	print("[HeldPickaxeService] 손에 든 곡괭이 시작(틀이 있으면 모델 · 없으면 임시 도형)")
end

return HeldPickaxeService

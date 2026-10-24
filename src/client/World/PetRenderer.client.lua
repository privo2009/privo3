--!strict
-- 펫 추적 표시 (Phase 7 지시서 #12 E9). 클라 전용 — 서버에 펫 파트를 만들지 않는다(CLAUDE.md 절대 규칙 4 · DESIGN 6장).
--
-- 서버 PetService가 Player Attribute "EquippedPets"(PetConfig.serializeEquipped 형식)를 세팅하면 모든 클라에 복제된다.
-- 이 스크립트가 모든 플레이어의 장착 펫을 캐릭터 뒤에 대체물로 그린다: 종 희귀도 색 구 + 강화 단계 2 이상이면 외곽 껍질
-- (파트 1~2개, 리깅 없음). 무엇을 그릴지는 World/PetRenderLogic.plan(내 펫 먼저 · 다른 사람은 내 hideOtherPets · 파트 합 상한).
--
-- 움직임은 클라 보간(Heartbeat — 위치만 따라간다). 내 캐릭터가 블록 판정 반경 안이면 내 펫이 블록 쪽으로 "치는 모습"을 낸다 —
-- 데미지는 없다(S9/G12 — 데미지는 펫 힘 배수로만, AttackService 단일 루프 그대로). 반경은 AttackConfig.getRadius(파생값),
-- 블록 위치는 내 클라의 LocalBlocks(RemoteReceiver가 만든다). 다른 사람 블록은 내 화면에 없으므로 다른 사람 펫은 치지 않는다.
--
-- 풀링: 파트는 풀에서 꺼내고 돌려준다. 장착이 바뀔 때만 다시 배정하고, 프레임마다 Instance.new 하지 않는다(CLAUDE.md 금지 사항).
-- 관측(값 읽기용): 폴더 Attribute PartCount · PetCount · LocalPetCount — 실물 검증이 Play 중 읽기로 확인한다(screen_capture는 3D를 못 찍는다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local PetRenderLogic = require(script.Parent.PetRenderLogic)
local Store = require(script.Parent.Parent.UI.Store)

local ATTRIBUTE = "EquippedPets" -- 서버 PetService.ATTRIBUTE와 같은 문자열
local BLOCK_CONTAINER_NAME = "LocalBlocks" -- Net/RemoteReceiver와 같은 이름
local localPlayer = Players.LocalPlayer

local folder = Instance.new("Folder")
folder.Name = "PetDisplay"
folder.Parent = Workspace

local free: { BasePart } = {}

local function newPart(): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	return p
end

local function take(): BasePart
	local p = table.remove(free) or newPart()
	p.Parent = folder
	return p
end

local function give(p: BasePart)
	p.Parent = nil
	table.insert(free, p)
end

type Shown = { owner: Player, index: number, count: number, pet: PetRenderLogic.Pet, body: BasePart, shell: BasePart?, cf: CFrame? }
local shown: { Shown } = {}

local function hideOthers(): boolean
	local p = Store.get("pets")
	return type(p) == "table" and p.hideOtherPets == true
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function hexColor(hex: string): Color3
	return if hex ~= "" then Color3.fromHex(hex) else Color3.new(1, 1, 1)
end

-- 장착 · 사람 · 숨기기가 바뀌면 배정을 다시 한다(파트는 풀로 돌려주고 다시 꺼낸다).
local function rebuild()
	for _, s in ipairs(shown) do
		give(s.body)
		if s.shell ~= nil then
			give(s.shell)
		end
	end
	table.clear(shown)
	local owners: { PetRenderLogic.Owner } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(owners, { key = player, attribute = player:GetAttribute(ATTRIBUTE), isLocal = player == localPlayer })
	end
	local plans = PetRenderLogic.plan(owners, hideOthers())
	local localCount = 0
	for _, plan in ipairs(plans) do
		local owner = plan.key :: Player
		for i, pet in ipairs(plan.pets) do
			local body = take()
			body.Name = "Pet_" .. pet.petId
			body.Size = Vector3.one * pet.size
			body.Color = UiTheme.rarityColor(pet.rarityTier)
			body.Material = Enum.Material.SmoothPlastic -- 풀에서 꺼낸 파트가 전에 껍질이었을 수 있다
			body.Transparency = 0
			local shell: BasePart? = nil
			if pet.shell then
				local sp = take()
				sp.Name = "Shell"
				sp.Size = Vector3.one * pet.size * PetConfig.DISPLAY.SHELL_SCALE
				sp.Color = hexColor(PetConfig.DISPLAY.SHELL_HEX[pet.level])
				sp.Material = Enum.Material.ForceField
				sp.Transparency = 0
				shell = sp
			end
			table.insert(shown, { owner = owner, index = i, count = #plan.pets, pet = pet, body = body, shell = shell, cf = nil })
			if owner == localPlayer then
				localCount += 1
			end
		end
	end
	folder:SetAttribute("PartCount", PetRenderLogic.totalParts(plans))
	folder:SetAttribute("PetCount", #shown)
	folder:SetAttribute("LocalPetCount", localCount)
end

-- 내 블록 묶음의 중심(런 중일 때만 블록이 있다). 없으면 nil.
local function blockCenter(): Vector3?
	local container = Workspace:FindFirstChild(BLOCK_CONTAINER_NAME)
	if container == nil then
		return nil
	end
	local sum = Vector3.zero
	local n = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			sum += child:GetPivot().Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

local parts: { BasePart } = {}
local cframes: { CFrame } = {}

RunService.Heartbeat:Connect(function(dt: number)
	if #shown == 0 then
		return
	end
	local t = os.clock()
	local alpha = PetRenderLogic.alpha(dt)
	local center = blockCenter()
	local myRoot = rootOf(localPlayer)
	local inRange = center ~= nil and myRoot ~= nil and AttackConfig.isInRange((myRoot.Position - center).Magnitude)
	table.clear(parts)
	table.clear(cframes)
	for _, s in ipairs(shown) do
		local root = rootOf(s.owner)
		if root ~= nil then
			local target = root.CFrame:PointToWorldSpace(PetRenderLogic.offset(s.index, s.count))
			if s.owner == localPlayer and inRange and center ~= nil then
				local toward = center - target
				local reach = math.min(toward.Magnitude, PetConfig.DISPLAY.SPACING) * PetRenderLogic.punchPhase(true, t, s.index)
				if toward.Magnitude > 1e-3 then
					target += toward.Unit * reach
				end
			end
			local goal = CFrame.new(target)
			local cf = if s.cf ~= nil then s.cf:Lerp(goal, alpha) else goal
			s.cf = cf
			table.insert(parts, s.body)
			table.insert(cframes, cf)
			if s.shell ~= nil then
				table.insert(parts, s.shell)
				table.insert(cframes, cf)
				if s.pet.level >= PetConfig.MAX_LEVEL then
					s.shell.Color = Color3.fromHSV((t * 0.25) % 1, 0.6, 1) -- 무지개: 색상을 돌린다
				end
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

local connections: { [Player]: RBXScriptConnection } = {}

local function track(player: Player)
	if connections[player] == nil then
		connections[player] = player:GetAttributeChangedSignal(ATTRIBUTE):Connect(rebuild)
	end
	rebuild()
end

for _, player in ipairs(Players:GetPlayers()) do
	track(player)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(function(player: Player)
	local c = connections[player]
	if c ~= nil then
		c:Disconnect()
		connections[player] = nil
	end
	task.defer(rebuild) -- 떠난 뒤 목록에서 빠진 다음에 다시
end)
Store.subscribe("pets", rebuild) -- 숨기기 설정이 바뀌면 다시

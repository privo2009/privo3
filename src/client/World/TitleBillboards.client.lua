--!strict
-- 머리 위 칭호 (Phase 7 지시서 #10 S15 (가) — 다른 플레이어에게도 보인다). 클라 전용.
--
-- 서버 TitleService가 Player Attribute "EquippedTitle"(칭호 id)을 세팅하면 모든 클라에 복제된다. 이 스크립트는
-- **모든 플레이어**(자기 포함)의 캐릭터 머리 위에 BillboardGui 하나씩을 그린다. 장착이 없거나 모르는 id면 숨긴다.
--
-- 풀링: 빌보드는 플레이어당 하나를 만들어 두고 캐릭터가 바뀌면(리스폰) Adornee만 옮긴다. 빌보드는 내 PlayerGui 밑에 둔다 —
-- 캐릭터 밑에 두면 리스폰 때 캐릭터와 함께 지워져 풀이 깨진다(Adornee가 있으면 PlayerGui 밑에서도 3D로 그려진다).
-- 반복 루프에서 Instance.new 하지 않는다(CLAUDE.md 금지 사항). 나간 플레이어의 빌보드는 풀로 돌려 다음 사람이 쓴다.
-- 크기는 studs(BillboardGui.Size의 Scale = studs — WorldLabels와 같다). AlwaysOnTop을 쓰지 않는다(다른 3D 안내와 같다).
-- 높이는 HumanoidRootPart 기준 — 머리 바로 위. 클릭 +숫자 팝업(ClickPopups — 머리 위 2.5에서 떠올라 칭호를 잠깐 지나간다). 배치값은 Claude가 정했다(docs/UI.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)

local ATTRIBUTE = "EquippedTitle" -- 서버 TitleService.ATTRIBUTE와 같은 문자열
local SIZE = Vector2.new(6, 0.8)
local HEIGHT = 3.0 -- 2.6 ~ 3.4. 2.55에서 올렸다 — 머리카락 · 모자에 가렸다(2026-10-24 캡처, AlwaysOnTop이 아니라 3D 깊이로 가려진다)
local MAX_DISTANCE = 80 -- studs. 멀리 있는 플레이어 칭호까지 다 그리면 화면이 지저분하다

type Tag = { gui: BillboardGui, label: TextLabel }

local free: { Tag } = {}
local byPlayer: { [Player]: Tag } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local function newTag(): Tag
	local gui = Instance.new("BillboardGui")
	gui.Name = "TitleTag"
	-- K10(#L2): 번역은 Strings(Locale.t)가 한다 — 로블록스 자동 번역이 우리 번역 위에 한 번 더 덮이지 않게 끈다
	gui.AutoLocalize = false
	gui.Size = UDim2.fromScale(SIZE.X, SIZE.Y)
	gui.StudsOffset = Vector3.new(0, HEIGHT, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Parent = gui
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels.medium.maxTextSize
	size.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
	return { gui = gui, label = label }
end

local function take(): Tag
	return table.remove(free) or newTag()
end

-- 지금 상태로 다시 그린다: 장착 칭호 · 캐릭터.
local function refresh(player: Player)
	local tag = byPlayer[player]
	if tag == nil then
		return
	end
	local def, tier = TitleConfig.get(player:GetAttribute(ATTRIBUTE))
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if def == nil or tier == nil or root == nil then
		tag.gui.Enabled = false
		return
	end
	tag.label.Text = Names.title(def.id)
	tag.label.TextColor3 = UiTheme.rarityColor(tier)
	tag.gui.Adornee = root :: BasePart
	tag.gui.Enabled = true
end

local function track(player: Player)
	if byPlayer[player] ~= nil then
		return
	end
	byPlayer[player] = take()
	local list: { RBXScriptConnection } = {}
	table.insert(list, player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		refresh(player)
	end))
	table.insert(list, player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		refresh(player)
	end))
	connections[player] = list
	refresh(player)
end

local function untrack(player: Player)
	local tag = byPlayer[player]
	if tag ~= nil then
		tag.gui.Enabled = false
		tag.gui.Adornee = nil
		table.insert(free, tag)
		byPlayer[player] = nil
	end
	for _, c in ipairs(connections[player] or {}) do
		c:Disconnect()
	end
	connections[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	track(player)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)

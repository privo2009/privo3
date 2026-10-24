--!strict
-- 아우라 파티클 (Phase 7 지시서 #11 A7). 클라 전용 — 서버에 파티클을 만들지 않는다(CLAUDE.md 절대 규칙 4).
--
-- 서버 AuraService가 Player Attribute "EquippedAura"를 세팅하면 모든 클라에 복제된다. 이 스크립트가 **모든 플레이어**의
-- HumanoidRootPart에 ParticleEmitter 하나씩을 붙인다(대체물: 기본 ParticleEmitter + 희귀도 색 — 실물 에셋 도착 전).
-- 방출량은 World/AuraRenderLogic.rates: 등급별 값 · 다른 사람은 내 hideOtherAuras를 따른다 · 화면 전체 합 상한(AuraConfig.PARTICLE).
--
-- 풀링: 플레이어당 이미터 하나를 만들어 두고 캐릭터가 바뀌면 새 HumanoidRootPart로 옮긴다. CharacterRemoving에서 먼저 떼어 낸다 —
-- 캐릭터와 함께 지워지면 풀이 깨진다. 반복 루프에서 Instance.new 하지 않는다(CLAUDE.md 금지 사항).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local AuraRenderLogic = require(script.Parent.AuraRenderLogic)
local AuraWindowLogic = require(script.Parent.Parent.UI.Logic.AuraWindowLogic)
local Store = require(script.Parent.Parent.UI.Store)

local ATTRIBUTE = "EquippedAura" -- 서버 AuraService.ATTRIBUTE와 같은 문자열
local localPlayer = Players.LocalPlayer

local free: { ParticleEmitter } = {}
local byPlayer: { [Player]: ParticleEmitter } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}

local function newEmitter(): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "AuraParticles"
	e.Lifetime = NumberRange.new(AuraConfig.PARTICLE.LIFETIME_SEC * 0.7, AuraConfig.PARTICLE.LIFETIME_SEC)
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 0.6
	e.Rate = 0
	e.Enabled = false
	return e
end

local function take(): ParticleEmitter
	return table.remove(free) or newEmitter()
end

local function hideOthers(): boolean
	local a = Store.get("auras")
	return type(a) == "table" and a.hideOtherAuras == true
end

-- 모든 플레이어의 방출량 · 색을 다시 정한다(상한이 전체 합이라 한 사람이 바뀌어도 전부 다시 본다).
local function refreshAll()
	local players: { Player } = {}
	local entries: { AuraRenderLogic.Entry } = {}
	for player in pairs(byPlayer) do
		table.insert(players, player)
		table.insert(entries, { auraId = player:GetAttribute(ATTRIBUTE), isLocal = player == localPlayer })
	end
	local rates = AuraRenderLogic.rates(entries, hideOthers())
	for i, player in ipairs(players) do
		local emitter = byPlayer[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local _, _, tier = AuraConfig.get(player:GetAttribute(ATTRIBUTE))
		if root == nil or tier == nil or rates[i] <= 0 then
			emitter.Enabled = false
			emitter.Rate = 0
		else
			local color = UiTheme.rarityColor(AuraWindowLogic.rarityTier(tier))
			emitter.Color = ColorSequence.new(color)
			emitter.Rate = rates[i]
			if emitter.Parent ~= root then
				emitter.Parent = root
			end
			emitter.Enabled = true
		end
	end
end

local function track(player: Player)
	if byPlayer[player] ~= nil then
		return
	end
	byPlayer[player] = take()
	local list: { RBXScriptConnection } = {}
	table.insert(list, player:GetAttributeChangedSignal(ATTRIBUTE):Connect(refreshAll))
	table.insert(list, player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		refreshAll()
	end))
	table.insert(list, player.CharacterRemoving:Connect(function()
		local e = byPlayer[player]
		if e ~= nil then
			e.Enabled = false
			e.Parent = nil -- 캐릭터와 함께 지워지지 않게 먼저 뗀다(풀 보존)
		end
	end))
	connections[player] = list
	refreshAll()
end

local function untrack(player: Player)
	local e = byPlayer[player]
	if e ~= nil then
		e.Enabled = false
		e.Parent = nil
		table.insert(free, e)
		byPlayer[player] = nil
	end
	for _, c in ipairs(connections[player] or {}) do
		c:Disconnect()
	end
	connections[player] = nil
	refreshAll()
end

for _, player in ipairs(Players:GetPlayers()) do
	track(player)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)
Store.subscribe("auras", refreshAll) -- 숨기기 설정이 바뀌면 다시

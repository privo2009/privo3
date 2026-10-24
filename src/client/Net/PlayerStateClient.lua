--!strict
-- 서버 PlayerState 채널 → Store (Phase 6 지시서 #5). HUD는 이 모듈을 모르고 Store만 구독한다.
--
-- payload는 매번 전체 스냅샷이다(Shared/Remotes.lua PlayerStatePayload). 키를 그대로 Store setter에
-- 넣는다 — Store가 "값이 실제로 바뀐 키"만 구독자에게 알린다.
-- 클라는 값을 다시 계산하지 않는다(서버 권위). 형태가 틀린 payload는 통째로 버린다 —
-- 반쪽만 반영하면 화면이 서로 다른 시점의 값을 섞어 그린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local StateSync = require(script.Parent.StateSync)

type BigNumber = BigNum.BigNumber

local PlayerStateClient = {}

-- Shared/GameTypes.PlayerStateView의 키. 순서는 의미 없다.
local BIG_KEYS = { "blox", "strength", "lifetimeBlox", "lifeBlox", "rebirths" }
local NUMBER_KEYS = { "walkSpeed", "maxWalkSpeed", "maxStage", "padIndex" }
PlayerStateClient.BIG_KEYS = BIG_KEYS
PlayerStateClient.NUMBER_KEYS = NUMBER_KEYS

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isBig(v: any): boolean
	return type(v) == "table" and isFinite(v.m) and isFinite(v.e)
end

-- 업그레이드 레벨 표(지시서 #7). UpgradeConfig의 이름마다 0 이상의 유한한 숫자여야 한다.
local function isValidUpgrades(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	for name in pairs(UpgradeConfig.Upgrades) do
		local level = v[name]
		if not isFinite(level) or level < 0 then
			return false
		end
	end
	return true
end

-- 칭호 요약(지시서 #10). owned는 문자열 배열, equipped는 문자열("" = 없음), autoRoll은 boolean.
local function isValidTitles(v: any): boolean
	if type(v) ~= "table" or type(v.owned) ~= "table" or type(v.equipped) ~= "string" or type(v.autoRoll) ~= "boolean" then
		return false
	end
	for _, id in ipairs(v.owned) do
		if type(id) ~= "string" then
			return false
		end
	end
	return true
end
PlayerStateClient.isValidTitles = isValidTitles

-- 아우라 요약(지시서 #11).
local function isValidAuras(v: any): boolean
	if type(v) ~= "table" or type(v.owned) ~= "table" or type(v.equipped) ~= "string" or type(v.hideOtherAuras) ~= "boolean"
		or not isFinite(v.selectedPack) or not isFinite(v.world) then
		return false
	end
	for _, id in ipairs(v.owned) do
		if type(id) ~= "string" then
			return false
		end
	end
	return true
end
PlayerStateClient.isValidAuras = isValidAuras

-- 펫 요약(지시서 #12).
local function isValidPets(v: any): boolean
	if type(v) ~= "table" or type(v.owned) ~= "table" or type(v.equipped) ~= "table" or type(v.hideOtherPets) ~= "boolean"
		or not isFinite(v.slots) or not isFinite(v.storage) or not isFinite(v.world) then
		return false
	end
	for _, e in ipairs(v.owned) do
		if type(e) ~= "table" or type(e.uid) ~= "string" or type(e.petId) ~= "string" or not isFinite(e.level) then
			return false
		end
	end
	for _, uid in ipairs(v.equipped) do
		if type(uid) ~= "string" then
			return false
		end
	end
	return true
end
PlayerStateClient.isValidPets = isValidPets

-- payload 형태 검사. 하나라도 틀리면 false.
function PlayerStateClient.isValidPayload(payload: any): boolean
	if type(payload) ~= "table" then
		return false
	end
	for _, key in ipairs(BIG_KEYS) do
		if not isBig(payload[key]) then
			return false
		end
	end
	for _, key in ipairs(NUMBER_KEYS) do
		if not isFinite(payload[key]) then
			return false
		end
	end
	return isValidUpgrades(payload.upgrades) and isValidTitles(payload.titles) and isValidAuras(payload.auras) and isValidPets(payload.pets)
end

-- payload를 setter에 반영한다. 형태가 틀리면 아무것도 반영하지 않고 false.
function PlayerStateClient.apply(setter: (string, any) -> (), payload: any): boolean
	if not PlayerStateClient.isValidPayload(payload) then
		return false
	end
	for _, key in ipairs(BIG_KEYS) do
		local v = payload[key]
		setter(key, BigNum.new(v.m, v.e))
	end
	for _, key in ipairs(NUMBER_KEYS) do
		setter(key, payload[key])
	end
	local levels: { [string]: number } = {}
	for name in pairs(UpgradeConfig.Upgrades) do
		levels[name] = payload.upgrades[name]
	end
	setter("upgrades", levels)
	setter("titles", payload.titles) -- Store가 깊게 복사한다
	setter("auras", payload.auras)
	setter("pets", payload.pets)
	return true
end

local received = false
local firstCallbacks: { () -> () } = {}
local started = false

-- 첫 스냅샷을 받았는가. 로딩 화면이 이것으로 닫힌다.
function PlayerStateClient.hasReceived(): boolean
	return received
end

-- 첫 스냅샷을 받으면 한 번 부른다. 이미 받았으면 바로 부른다.
function PlayerStateClient.onFirstState(callback: () -> ())
	if received then
		task.spawn(callback)
		return
	end
	table.insert(firstCallbacks, callback)
end

-- store: Store 모듈(싱글톤) 또는 Store.new() 인스턴스. 실물은 HudBoot이 한 번 부른다.
function PlayerStateClient.start(store: any)
	if started then
		warn("[PlayerStateClient] start()가 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	started = true

	local channels = Remotes.getClient()
	store.setSource(function(setter)
		channels.playerState.OnClientEvent:Connect(function(payload: Remotes.PlayerStatePayload)
			if not PlayerStateClient.apply(setter, payload) then
				warn("[PlayerStateClient] 형태가 틀린 PlayerState를 버렸다")
				return
			end
			if not received then
				received = true
				local callbacks = firstCallbacks
				firstCallbacks = {}
				for _, callback in ipairs(callbacks) do
					task.spawn(callback)
				end
			end
		end)
	end)
	StateSync.request()
end

return PlayerStateClient

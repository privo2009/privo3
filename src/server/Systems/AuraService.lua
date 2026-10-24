--!strict
-- 아우라 서버 (Phase 7 지시서 #11). 롤 · 장착 · 팩 선택 · 배수 조회. 규칙 원본은 DESIGN.md "6. 뽑기 3종 > 아우라"(A1~A11).
--
-- ===== 아우라 상태는 이 파일만 쓴다 ====================================================
--
-- profile.Data.cosmetics.ownedAuras · equippedAura, rolling.selectedPack에 대입하는 곳은 이 파일뿐이다(TitleService와 같은 규칙).
-- 배수를 쓰는 쪽(ClickService · AttackService)은 getMult만 부른다. hideOtherAuras는 SettingsRequestService가 쓴다(설정).
--
-- ===== 롤 순서 (A9) =====================================================================
--
--   1. 프로필 · 표 읽기                 없으면 no_profile
--   2. 롤 시계                          AuraConfig.ROLL_INTERVAL_SEC(남용 방지) 안 두 번째면 rate_limited
--   3. 팩 확인                          그 월드에 없거나 잠긴 팩(lifetimeBlox < 롤 비용)이면 pack_locked
--   4. 잔액 미리 보기                    비용보다 적으면 insufficient_blox — 차감을 부르지 않는다(TitleService와 같다)
--   ----- 여기까지 부작용 0 -----
--   5. CurrencyService.subtract(롤 비용)  단일 게이트(절대 규칙 2). 거부면 insufficient_blox — 아직 부작용 0, 시계도 그대로
--   6. 시계 기록 → 행운(RollService.computeLuck "aura") → 순차 판정(RollService.roll — 서버 RNG)
--   7. 새 id      보유 추가 · 더 높은 m이면 자동 장착 · 저장 1회(Profile:Save, S11)
--      중복 id    아무것도 하지 않는다(알림 · 저장 없음). 결과 1건은 요청 응답으로만 돌아간다(브로드캐스트 없음)
--
-- ===== 표시 =============================================================================
--
-- 장착 아우라 id를 Player Attribute(ATTRIBUTE)로 세팅한다 — 모든 클라에 복제된다. 각 클라가 캐릭터에 파티클을 붙인다
-- (World/AuraRenderer — 클라 전용, 풀링, 다른 사람 아우라는 내 hideOtherAuras를 따른다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.CurrencyService)
local RollService = require(script.Parent.RollService)

type BigNumber = BigNum.BigNumber

local AuraService = {}

AuraService.ATTRIBUTE = "EquippedAura"
AuraService.REASON_PACK_LOCKED = "pack_locked"
AuraService.REASON_NOT_OWNED = "not_owned"
local CLOCK_EPSILON_SEC = 0.02 -- 롤 시계 부동소수 여유(TitleService와 같은 이유)

export type RollResult = {
	auraId: string,
	packId: number,
	tier: number,
	isNew: boolean,
	equipped: boolean,
}

export type Deps = {
	now: () -> number,
	getData: (Player) -> any?,
	getBlox: (Player) -> BigNumber?,
	subtractBlox: (Player, BigNumber, string) -> boolean,
	roll: (tiers: { AuraConfig.AuraDef }, luck: number) -> (AuraConfig.AuraDef, number),
	save: (Player) -> (),
	setAttribute: (Player, string?) -> (),
}

local function tables(data: any): (any?, any?)
	if type(data) ~= "table" or type(data.cosmetics) ~= "table" or type(data.rolling) ~= "table" then
		return nil, nil
	end
	if type(data.cosmetics.ownedAuras) ~= "table" then
		return nil, nil
	end
	return data.cosmetics, data.rolling
end

local function worldOf(data: any): number
	local w = if type(data) == "table" and type(data.progress) == "table" then data.progress.currentWorld else nil
	return if type(w) == "number" then w else 1
end

local function lifetimeOf(data: any): BigNumber
	local v = if type(data) == "table" then data.lifetimeBlox else nil
	if type(v) == "table" and type(v.m) == "number" and type(v.e) == "number" then
		return BigNum.new(v.m, v.e)
	end
	return BigNum.new(0, 0)
end

-- 장착 아우라 id(알려진 것만). 없거나 모르는 id면 nil.
local function equippedId(data: any): string?
	local cosmetics = tables(data)
	if cosmetics == nil then
		return nil
	end
	local def = AuraConfig.get(cosmetics.equippedAura)
	return if def ~= nil then def.id else nil
end

local function createRuntime(deps: Deps)
	local lastRollAt: { [Player]: number } = {}
	local runtime = {}

	function runtime.roll(player: Player, packId: any, source: string): (boolean, any)
		-- 1. 프로필
		local data = deps.getData(player)
		local cosmetics = tables(data)
		if cosmetics == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		if type(packId) ~= "number" or packId % 1 ~= 0 then
			return false, RollService.REASON_INVALID
		end

		-- 2. 롤 시계
		local now = deps.now()
		local last = lastRollAt[player]
		if last ~= nil and now - last < AuraConfig.ROLL_INTERVAL_SEC - CLOCK_EPSILON_SEC then
			return false, RollService.REASON_RATE_LIMITED
		end

		-- 3. 팩 — 그 월드에 있고 열렸는가(해금 = 롤 1회 비용, G3)
		local pack = AuraConfig.Packs[packId]
		if pack == nil or not AuraConfig.isUnlocked(packId, lifetimeOf(data), worldOf(data)) then
			return false, AuraService.REASON_PACK_LOCKED
		end

		-- 4. 잔액 미리 보기
		local blox = deps.getBlox(player)
		if blox == nil or BigNum.lt(blox, pack.rollCost) then
			return false, RollService.REASON_INSUFFICIENT_BLOX
		end

		-- ===== 여기부터 부작용 =====

		-- 5. 차감
		if not deps.subtractBlox(player, pack.rollCost, string.format("aura_roll_pack%d_%s", packId, source)) then
			return false, RollService.REASON_INSUFFICIENT_BLOX
		end

		-- 6. 판정
		lastRollAt[player] = now
		local luck = RollService.computeLuck("aura", data)
		local def, tier = deps.roll(pack.auras, luck)

		-- 7. 반영
		local owned = cosmetics.ownedAuras
		if owned[def.id] then
			local dup: RollResult = { auraId = def.id, packId = packId, tier = tier, isNew = false, equipped = false }
			return true, dup
		end
		owned[def.id] = true
		local equipped = false
		if AuraConfig.isHigher(def.id, cosmetics.equippedAura) then
			cosmetics.equippedAura = def.id
			deps.setAttribute(player, def.id)
			equipped = true
		end
		deps.save(player)
		local result: RollResult = { auraId = def.id, packId = packId, tier = tier, isNew = true, equipped = equipped }
		return true, result
	end

	function runtime.equip(player: Player, auraId: any): (boolean, string?)
		local cosmetics = tables(deps.getData(player))
		if cosmetics == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		local def = AuraConfig.get(auraId)
		if def == nil then
			return false, RollService.REASON_INVALID
		end
		if not cosmetics.ownedAuras[def.id] then
			return false, AuraService.REASON_NOT_OWNED
		end
		cosmetics.equippedAura = def.id
		deps.setAttribute(player, def.id)
		return true, nil
	end

	-- 고른 팩을 저장한다. 그 월드에 있는 팩만(잠긴 팩도 고를 수 있다 — 창이 해금 조건을 보여 준다).
	function runtime.selectPack(player: Player, packId: any): (boolean, string?)
		local data = deps.getData(player)
		local _, rolling = tables(data)
		if rolling == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		if type(packId) ~= "number" or packId % 1 ~= 0 or not AuraConfig.isInWorld(packId, worldOf(data)) then
			return false, RollService.REASON_INVALID
		end
		rolling.selectedPack = packId
		return true, nil
	end

	function runtime.onRemoving(player: Player)
		lastRollAt[player] = nil
	end

	return runtime
end

AuraService._pure = {
	createRuntime = createRuntime,
	equippedId = equippedId,
	CLOCK_EPSILON_SEC = CLOCK_EPSILON_SEC,
}

-- ===== 공개 API =========================================================================

-- 장착 아우라 m. 프로필이 없거나 장착이 없으면 1. ClickService · AttackService가 부른다.
function AuraService.getMult(player: Player): number
	local profile = ProfileManager.get(player)
	if profile == nil then
		return 1
	end
	return AuraConfig.multOf(equippedId(profile.Data))
end

-- 상태 채널 요약. owned는 팩 · 등급 순, equipped는 없으면 "".
export type AuraSummary = { owned: { string }, equipped: string, selectedPack: number, hideOtherAuras: boolean }
function AuraService.summarize(data: any): AuraSummary
	local cosmetics, rolling = tables(data)
	local owned: { string } = {}
	if cosmetics ~= nil then
		for packId = 1, #AuraConfig.Packs do
			for _, def in ipairs(AuraConfig.Packs[packId].auras) do
				if cosmetics.ownedAuras[def.id] then
					table.insert(owned, def.id)
				end
			end
		end
	end
	local pack = if rolling ~= nil and type(rolling.selectedPack) == "number" then rolling.selectedPack else 1
	return {
		owned = owned,
		equipped = equippedId(data) or "",
		selectedPack = pack,
		hideOtherAuras = cosmetics ~= nil and cosmetics.hideOtherAuras == true,
	}
end

local function setAttribute(player: Player, id: string?)
	if typeof(player) == "Instance" and player:IsA("Player") then
		player:SetAttribute(AuraService.ATTRIBUTE, id)
	end
end

local REAL: Deps = {
	now = os.clock,
	getData = function(player: Player)
		local profile = ProfileManager.get(player)
		return if profile ~= nil then profile.Data else nil
	end,
	getBlox = function(player: Player)
		return CurrencyService.get(player, "blox")
	end,
	subtractBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.subtract(player, "blox", amount, reason))
	end,
	roll = function(tiers, luck)
		return RollService.roll(tiers, luck)
	end,
	save = function(player: Player)
		ProfileManager.save(player) -- S11: 새 id를 처음 얻었을 때만
	end,
	setAttribute = setAttribute,
}

local runtime = createRuntime(REAL)

function AuraService.roll(player: Player, packId: any, source: string): (boolean, any)
	local ok, value = runtime.roll(player, packId, source)
	if ok then
		print(string.format(
			"[AuraService] %s(%d) 팩 %d → %s (등급 %d)%s%s",
			player.Name, player.UserId, value.packId, value.auraId, value.tier,
			if value.isNew then " 새 아우라" else " 중복", if value.equipped then " → 자동 장착" else ""
		))
	end
	return ok, value
end

function AuraService.equip(player: Player, auraId: any): (boolean, string?)
	return runtime.equip(player, auraId)
end

function AuraService.selectPack(player: Player, packId: any): (boolean, string?)
	return runtime.selectPack(player, packId)
end

local initialized = false

function AuraService.init()
	if initialized then
		warn("[AuraService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local function onLoaded(player: Player, profile: any)
		setAttribute(player, equippedId(profile.Data))
	end
	ProfileManager.onLoaded(onLoaded)
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = ProfileManager.get(player)
		if profile ~= nil then
			onLoaded(player, profile)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)
	print(string.format("[AuraService] 준비 완료 (롤 시계 %g초)", AuraConfig.ROLL_INTERVAL_SEC))
end

return AuraService

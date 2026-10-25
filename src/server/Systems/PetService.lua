--!strict
-- 펫 서버 (Phase 7 지시서 #12). 부화 · 장착 · 해제 · 최고 장착 · 크래프팅 · 놓아주기 · 배수 조회.
-- 규칙 원본은 DESIGN.md "6. 뽑기 3종 > 펫"(E1~E11) · "3. 화폐와 배수"(E3).
--
-- ===== 펫 상태는 이 파일만 쓴다 ======================================================
--
-- profile.Data.pets.owned · equipped · nextUid에 대입하는 곳은 이 파일뿐이다(AuraService · TitleService와 같은 규칙).
-- 배수를 쓰는 쪽(ClickService · Bootstrap 관측)은 getMult만 부른다. hideOtherPets는 SettingsRequestService가 쓴다(설정).
--
-- ===== 부화 순서 (E6 · 지시서 #12 3단계) ===================================================
--
--   1. 프로필 · 표 읽기                 없으면 no_profile. 알 번호가 정수가 아니면 invalid_request
--   2. 롤 시계                          PetConfig.HATCH_INTERVAL_SEC(남용 방지) 안 두 번째면 rate_limited
--   3. 해금                             그 월드에 없거나 잠긴 알(lifetimeBlox < 부화 비용)이면 egg_locked
--   4. 저장 공간                        보유 수 ≥ 파생 저장 공간이면 storage_full
--   5. 잔액 미리 보기                    비용보다 적으면 insufficient_blox — 차감을 부르지 않는다
--   ----- 여기까지 부작용 0 -----
--   6. CurrencyService.subtract(부화 비용)  단일 게이트(절대 규칙 2). 거부면 insufficient_blox — 아직 부작용 0, 시계도 그대로
--   7. 시계 기록 → 행운(RollService.computeLuck "pet") → 순차 판정(RollService.roll — 서버 RNG)
--   8. uid = tostring(nextUid) 발급 · nextUid + 1 · 보유 추가(강화 단계 1). 빈 슬롯이 있으면 자동 장착(Claude 판단 — 아래)
--      그 petId를 지금 하나도 갖고 있지 않았으면 "새 펫" → 저장 1회(Profile:Save, S11)
--
-- 중복 petId도 보유에 더한다 — 펫은 같은 종을 모아 크래프팅하므로 아우라 · 칭호처럼 증발하지 않는다(DESIGN 6장).
-- "새 펫" 판정은 **지금 보유 기준**이다(지나간 보유 기록을 따로 저장하지 않는다 — 스키마를 늘리지 않는다).
-- 놓아준 종을 다시 얻으면 다시 "새 펫"이 된다. 저장 횟수는 종 수만큼으로 묶인다.
--
-- 자동 장착(Claude 판단): 빈 슬롯이 있을 때만 새로 얻은 펫을 장착한다. 장착된 펫을 바꾸지는 않는다 —
-- 빈 슬롯을 두면 배수가 그냥 버려지고, 교체는 "최고 장착" 버튼(equipBest)이 한다.
--
-- ===== 크래프팅 (E4) =====================================================================
--
-- craft(uid) = "이 펫과 같은 petId · 같은 강화 단계" 묶음에서 CRAFT_REQUIREMENT마리를 써서 다음 단계 1마리를 만든다.
-- 재료는 **장착하지 않은 것부터**(uid 번호 순). 장착된 것을 써야 하면 결과 펫이 **그 장착 자리를 이어받는다**
-- (첫 번째로 쓰인 장착 자리 — 나머지 장착 자리는 비운다). 결과는 새 uid. 최대 단계면 max_level, 모자라면 not_enough.
--
-- ===== 표시 ============================================================================
--
-- 장착 목록을 Player Attribute(ATTRIBUTE)에 "petId:단계,petId:단계" 문자열로 세팅한다 — 모든 클라에 복제된다.
-- 각 클라가 캐릭터 뒤에 대체물을 그린다(World/PetRenderer — 클라 전용, 풀링, 다른 사람 펫은 내 hideOtherPets를 따른다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.CurrencyService)
local RollService = require(script.Parent.RollService)
-- 로벅스 효과(지시서 #16): 펫 행운 패스 · 행운 포션(제한이면 1) · 펫 슬롯 · 저장 공간 패스 · 3배 부화.
local ShopEffects = require(script.Parent.ShopEffects)
local GamepassService = require(script.Parent.GamepassService)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

type BigNumber = BigNum.BigNumber

local PetService = {}

PetService.ATTRIBUTE = "EquippedPets"
PetService.REASON_EGG_LOCKED = "egg_locked"
PetService.REASON_STORAGE_FULL = "storage_full"
PetService.REASON_NOT_OWNED = "not_owned"
PetService.REASON_SLOTS_FULL = "slots_full"
PetService.REASON_NOT_EQUIPPED = "not_equipped"
PetService.REASON_EQUIPPED = "pet_equipped" -- 장착 중인 펫은 놓아줄 수 없다(E5)
PetService.REASON_MAX_LEVEL = "max_level"
PetService.REASON_NOT_ENOUGH = "not_enough" -- 크래프팅 재료(같은 petId · 같은 단계)가 모자란다
PetService.REASON_HATCH_PASS_REQUIRED = "hatch_pass_required" -- 3배 부화 게임패스가 없다(S18)
local CLOCK_EPSILON_SEC = 0.02 -- 롤 시계 부동소수 여유(AuraService와 같은 이유)

export type HatchResult = {
	uid: string,
	petId: string,
	eggId: number,
	rarity: number, -- 종 희귀도 1~4
	level: number, -- 강화 단계
	isNew: boolean,
	equipped: boolean,
}

export type Deps = {
	now: () -> number,
	getData: (Player) -> any?,
	getBlox: (Player) -> BigNumber?,
	subtractBlox: (Player, BigNumber, string) -> boolean,
	roll: (tiers: { PetConfig.PetDef }, luck: number) -> (PetConfig.PetDef, number),
	save: (Player) -> (),
	setAttribute: (Player, string) -> (),
	-- 게임패스는 세션 값(절대 규칙 5). Phase 8 전까지 false를 돌려준다
	hasSlotPass: (Player) -> boolean,
	hasStoragePass: (Player) -> boolean,
	-- 슬롯 게임패스 소유가 확정됐는가(조회 성공 · 미등록 · 구매 완료). 확정 전에는 장착을 자르지 않는다(S17 · E6). 없으면 확정 안 됨
	isSlotPassResolved: ((Player) -> boolean)?,
	-- computeLuck 옵션(펫 행운 패스 · 행운 포션). 없으면 1
	luckOptions: ((Player) -> RollService.LuckOptions)?,
	-- 3배 부화 게임패스(S18). 없으면 미보유
	hasHatchPass: ((Player) -> boolean)?,
}

-- pets 표. 깨졌으면 nil.
local function petsOf(data: any): any?
	if type(data) ~= "table" or type(data.pets) ~= "table" then
		return nil
	end
	local pets = data.pets
	if type(pets.owned) ~= "table" or type(pets.equipped) ~= "table" then
		return nil
	end
	return pets
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

local function slotsLevelOf(data: any): number
	local upgrades = if type(data) == "table" then data.upgrades else nil
	local raw = if type(upgrades) == "table" then upgrades.petSlots else nil
	return if type(raw) == "number" then raw else 0
end

-- 보유 펫 하나가 쓸 만한가(알려진 petId · 올바른 강화 단계).
local function validPet(entry: any): boolean
	return type(entry) == "table" and PetConfig.get(entry.petId) ~= nil and PetConfig.isLevel(entry.tier)
end

local function uidNumber(uid: string): number
	return tonumber(uid) or math.huge
end

-- 보유 uid 목록, uid 번호 순(결정적 — 크래프팅 재료 순서 · 요약 순서가 매번 같다).
local function sortedUids(owned: any): { string }
	local out: { string } = {}
	for uid, entry in pairs(owned) do
		if type(uid) == "string" and validPet(entry) then
			table.insert(out, uid)
		end
	end
	table.sort(out, function(a, b)
		local na, nb = uidNumber(a), uidNumber(b)
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return out
end

local function ownedCount(owned: any): number
	local n = 0
	for _ in pairs(owned) do
		n += 1
	end
	return n
end

local function indexOf(list: { string }, uid: string): number?
	for i, v in ipairs(list) do
		if v == uid then
			return i
		end
	end
	return nil
end

-- 장착 펫 목록(유효한 것만, 장착 순서). 배수 · Attribute의 원본.
local function equippedPets(data: any): { PetConfig.OwnedPet }
	local pets = petsOf(data)
	local out: { PetConfig.OwnedPet } = {}
	if pets == nil then
		return out
	end
	for _, uid in ipairs(pets.equipped) do
		local entry = pets.owned[uid]
		if validPet(entry) then
			table.insert(out, { petId = entry.petId, tier = entry.tier })
		end
	end
	return out
end

-- Attribute 문자열 형식의 원본은 PetConfig.serializeEquipped / parseEquipped다(클라 렌더러가 같은 함수로 읽는다).
local serialize = PetConfig.serializeEquipped

local function createRuntime(deps: Deps)
	local lastHatchAt: { [Player]: number } = {}
	local runtime = {}

	local function slotsFor(player: Player, data: any): number
		return PetConfig.getSlots(slotsLevelOf(data), deps.hasSlotPass(player))
	end

	local function publish(player: Player, data: any)
		deps.setAttribute(player, serialize(equippedPets(data)))
	end

	-- count마리를 한 번에 부화한다(1 = 보통 부화 · 3배 부화 = ShopConfig hatch3x count — S18). 성공이면 (true, { HatchResult }).
	-- 비용 = 알 비용 × count(한 번에 차감), 저장 공간이 count칸 미만이면 거부(storage_full), 롤 시계는 한 번만 쓴다.
	function runtime.hatchMany(player: Player, eggId: any, count: number, source: string): (boolean, any)
		-- 1. 프로필
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		if type(eggId) ~= "number" or eggId ~= eggId or eggId % 1 ~= 0 then
			return false, RollService.REASON_INVALID
		end

		-- 2. 롤 시계
		local now = deps.now()
		local last = lastHatchAt[player]
		if last ~= nil and now - last < PetConfig.HATCH_INTERVAL_SEC - CLOCK_EPSILON_SEC then
			return false, RollService.REASON_RATE_LIMITED
		end

		-- 3. 해금(G8 — 월드에 있고 lifetimeBlox ≥ 부화 비용)
		local egg = PetConfig.Eggs[eggId]
		if egg == nil or not PetConfig.isUnlocked(eggId, lifetimeOf(data), worldOf(data)) then
			return false, PetService.REASON_EGG_LOCKED
		end

		-- 3b. 여러 마리면 3배 부화 게임패스(S18)
		if count ~= 1 and not (deps.hasHatchPass ~= nil and deps.hasHatchPass(player)) then
			return false, PetService.REASON_HATCH_PASS_REQUIRED
		end

		-- 4. 저장 공간(E6 — 파생). count칸이 다 비어 있어야 한다
		if ownedCount(pets.owned) + count > PetConfig.getStorage(deps.hasStoragePass(player)) then
			return false, PetService.REASON_STORAGE_FULL
		end

		-- 5. 잔액 미리 보기
		local cost = if count == 1 then egg.rollCost else BigNum.mul(egg.rollCost, BigNum.fromNumber(count))
		local blox = deps.getBlox(player)
		if blox == nil or BigNum.lt(blox, cost) then
			return false, RollService.REASON_INSUFFICIENT_BLOX
		end

		-- ===== 여기부터 부작용 =====

		-- 6. 차감(한 번에)
		local tag = if count == 1 then "" else string.format("_x%d", count)
		if not deps.subtractBlox(player, cost, string.format("pet_hatch_egg%d%s_%s", eggId, tag, source)) then
			return false, RollService.REASON_INSUFFICIENT_BLOX
		end

		-- 7 · 8. 판정 · 반영 — count번. 같은 배치 안의 두 번째 같은 종은 중복이다
		lastHatchAt[player] = now
		local luck = RollService.computeLuck("pet", data, if deps.luckOptions ~= nil then deps.luckOptions(player) else nil)
		local results: { HatchResult } = {}
		local anyNew = false
		local anyEquipped = false
		for _ = 1, count do
			local def, rarity = deps.roll(egg.pets, luck)
			local isNew = true
			for _, entry in pairs(pets.owned) do
				if type(entry) == "table" and entry.petId == def.id then
					isNew = false
					break
				end
			end
			local nextUid = if type(pets.nextUid) == "number" and pets.nextUid >= 1 then math.floor(pets.nextUid) else 1
			local uid = tostring(nextUid)
			while pets.owned[uid] ~= nil do -- 깨진 nextUid로 기존 펫을 덮어쓰지 않게
				nextUid += 1
				uid = tostring(nextUid)
			end
			pets.nextUid = nextUid + 1
			pets.owned[uid] = { petId = def.id, tier = 1 }
			local equipped = false
			if #pets.equipped < slotsFor(player, data) then
				table.insert(pets.equipped, uid)
				equipped = true
				anyEquipped = true
			end
			anyNew = anyNew or isNew
			table.insert(results, { uid = uid, petId = def.id, eggId = eggId, rarity = rarity, level = 1, isNew = isNew, equipped = equipped })
		end
		if anyEquipped then
			publish(player, data)
		end
		if anyNew then
			deps.save(player) -- S11: 새 petId가 하나라도 있을 때만 · 한 번만
		end
		return true, results
	end

	function runtime.hatch(player: Player, eggId: any, source: string): (boolean, any)
		local ok, value = runtime.hatchMany(player, eggId, 1, source)
		if ok then
			return true, value[1]
		end
		return false, value
	end

	-- 장착이 슬롯보다 많으면 앞에서부터 남긴다(E6 · S17). **슬롯 게임패스 소유가 확정된 뒤에만** — 확정 전에 자르면
	-- 조회가 늦은 보유자의 장착이 날아간다. 자른 수를 돌려준다(확정 전 · 프로필 없음이면 0).
	function runtime.trimToSlots(player: Player): number
		if deps.isSlotPassResolved == nil or not deps.isSlotPassResolved(player) then
			return 0
		end
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return 0
		end
		local slots = slotsFor(player, data)
		local removed = 0
		while #pets.equipped > slots do
			table.remove(pets.equipped)
			removed += 1
		end
		if removed > 0 then
			publish(player, data)
		end
		return removed
	end

	function runtime.equip(player: Player, uid: any): (boolean, string?)
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		if type(uid) ~= "string" or not validPet(pets.owned[uid]) then
			return false, PetService.REASON_NOT_OWNED
		end
		if indexOf(pets.equipped, uid) ~= nil then
			return true, nil -- 이미 장착 — 그대로(멱등)
		end
		if #pets.equipped >= slotsFor(player, data) then
			return false, PetService.REASON_SLOTS_FULL
		end
		table.insert(pets.equipped, uid)
		publish(player, data)
		return true, nil
	end

	function runtime.unequip(player: Player, uid: any): (boolean, string?)
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		local at = if type(uid) == "string" then indexOf(pets.equipped, uid) else nil
		if at == nil then
			return false, PetService.REASON_NOT_EQUIPPED
		end
		table.remove(pets.equipped, at)
		publish(player, data)
		return true, nil
	end

	-- 실효 증가분이 큰 순으로 슬롯을 채운다(같으면 uid 번호 순 — 결정적).
	function runtime.equipBest(player: Player): (boolean, string?)
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		local uids = sortedUids(pets.owned)
		local gain: { [string]: number } = {}
		for _, uid in ipairs(uids) do
			local e = pets.owned[uid]
			gain[uid] = PetConfig.effectiveGain(e.petId, e.tier)
		end
		table.sort(uids, function(a, b)
			if gain[a] ~= gain[b] then
				return gain[a] > gain[b]
			end
			return uidNumber(a) < uidNumber(b)
		end)
		local slots = slotsFor(player, data)
		local list: { string } = {}
		for i = 1, math.min(slots, #uids) do
			list[i] = uids[i]
		end
		table.clear(pets.equipped)
		for i, uid in ipairs(list) do
			pets.equipped[i] = uid
		end
		publish(player, data)
		return true, nil
	end

	function runtime.craft(player: Player, uid: any): (boolean, any)
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		local base = if type(uid) == "string" then pets.owned[uid] else nil
		if not validPet(base) then
			return false, PetService.REASON_NOT_OWNED
		end
		if base.tier >= PetConfig.MAX_LEVEL then
			return false, PetService.REASON_MAX_LEVEL
		end
		-- 같은 묶음: 장착 안 한 것 먼저, 그다음 장착한 것(각각 uid 번호 순)
		local free: { string } = {}
		local worn: { string } = {}
		for _, u in ipairs(sortedUids(pets.owned)) do
			local e = pets.owned[u]
			if e.petId == base.petId and e.tier == base.tier then
				table.insert(if indexOf(pets.equipped, u) ~= nil then worn else free, u)
			end
		end
		local need = PetConfig.CRAFT_REQUIREMENT
		if #free + #worn < need then
			return false, PetService.REASON_NOT_ENOUGH
		end
		local materials: { string } = {}
		for _, u in ipairs(free) do
			if #materials < need then
				table.insert(materials, u)
			end
		end
		for _, u in ipairs(worn) do
			if #materials < need then
				table.insert(materials, u)
			end
		end

		-- 새 uid (부화와 같은 발급)
		local nextUid = if type(pets.nextUid) == "number" and pets.nextUid >= 1 then math.floor(pets.nextUid) else 1
		local newUid = tostring(nextUid)
		while pets.owned[newUid] ~= nil do
			nextUid += 1
			newUid = tostring(nextUid)
		end
		pets.nextUid = nextUid + 1

		-- 장착 자리 이어받기: 쓰인 장착 재료 중 가장 앞 자리에 결과를 넣고, 나머지 쓰인 장착 자리는 지운다
		local inheritAt: number? = nil
		for _, u in ipairs(materials) do
			local at = indexOf(pets.equipped, u)
			if at ~= nil and (inheritAt == nil or at < inheritAt) then
				inheritAt = at
			end
		end
		local newEquipped: { string } = {}
		for i, u in ipairs(pets.equipped) do
			if i == inheritAt then
				table.insert(newEquipped, newUid)
			elseif indexOf(materials, u) == nil then
				table.insert(newEquipped, u)
			end
		end
		for _, u in ipairs(materials) do
			pets.owned[u] = nil
		end
		pets.owned[newUid] = { petId = base.petId, tier = base.tier + 1 }
		table.clear(pets.equipped)
		for i, u in ipairs(newEquipped) do
			pets.equipped[i] = u
		end
		if inheritAt ~= nil then
			publish(player, data)
		end
		local _, eggId, rarity = PetConfig.get(base.petId)
		local result: HatchResult = {
			uid = newUid,
			petId = base.petId,
			eggId = eggId :: number,
			rarity = rarity :: number,
			level = base.tier + 1,
			isNew = false,
			equipped = inheritAt ~= nil,
		}
		return true, result
	end

	function runtime.release(player: Player, uid: any): (boolean, string?)
		local data = deps.getData(player)
		local pets = petsOf(data)
		if pets == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		if type(uid) ~= "string" or pets.owned[uid] == nil then
			return false, PetService.REASON_NOT_OWNED
		end
		if indexOf(pets.equipped, uid) ~= nil then
			return false, PetService.REASON_EQUIPPED
		end
		pets.owned[uid] = nil -- 환급 없음(E5)
		return true, nil
	end

	-- 로드 직후: 장착 목록의 깨진 uid · 중복을 걸러 Attribute를 세팅한다. 슬롯보다 많은 장착은 소유가 확정됐을 때만 자른다
	-- (trimToSlots — 확정 전이면 GamepassService.onChanged가 확정 순간에 다시 부른다).
	function runtime.onLoaded(player: Player, data: any)
		local pets = petsOf(data)
		if pets ~= nil then
			local seen: { [string]: boolean } = {}
			local clean: { string } = {}
			for _, uid in ipairs(pets.equipped) do
				if type(uid) == "string" and not seen[uid] and validPet(pets.owned[uid]) then
					seen[uid] = true
					table.insert(clean, uid)
				end
			end
			if #clean ~= #pets.equipped then
				table.clear(pets.equipped)
				for i, u in ipairs(clean) do
					pets.equipped[i] = u
				end
			end
		end
		publish(player, data)
		runtime.trimToSlots(player)
	end

	function runtime.onRemoving(player: Player)
		lastHatchAt[player] = nil
	end

	return runtime
end

PetService._pure = {
	createRuntime = createRuntime,
	equippedPets = equippedPets,
	CLOCK_EPSILON_SEC = CLOCK_EPSILON_SEC,
}

-- ===== 공개 API =========================================================================

-- 게임패스는 세션 값이다(절대 규칙 5 — GamepassService). 확정 전에는 미보유로 본다.
local function hasSlotPass(player: Player): boolean
	return GamepassService.owns(player, "petSlots3")
end

local function hasStoragePass(player: Player): boolean
	return GamepassService.owns(player, "petStorage100")
end

-- 장착 펫 배수(E3). 프로필이 없거나 장착이 없으면 1. ClickService가 부른다.
function PetService.getMult(player: Player): number
	local profile = ProfileManager.get(player)
	if profile == nil then
		return 1
	end
	return PetConfig.totalMult(equippedPets(profile.Data))
end

-- 상태 채널 요약. owned = uid 번호 순 { uid, petId, level }, equipped = 장착 uid(장착 순서), 파생 슬롯 · 저장 공간.
export type PetEntryView = { uid: string, petId: string, level: number }
export type PetSummary = {
	owned: { PetEntryView },
	equipped: { string },
	slots: number,
	storage: number,
	hideOtherPets: boolean,
	world: number,
}
function PetService.summarize(data: any, slotPass: boolean?, storagePass: boolean?): PetSummary
	local pets = petsOf(data)
	local owned: { PetEntryView } = {}
	local equipped: { string } = {}
	if pets ~= nil then
		for _, uid in ipairs(sortedUids(pets.owned)) do
			local e = pets.owned[uid]
			table.insert(owned, { uid = uid, petId = e.petId, level = e.tier })
		end
		for _, uid in ipairs(pets.equipped) do
			if type(uid) == "string" and validPet(pets.owned[uid]) then
				table.insert(equipped, uid)
			end
		end
	end
	local cosmetics = if type(data) == "table" and type(data.cosmetics) == "table" then data.cosmetics else nil
	return {
		owned = owned,
		equipped = equipped,
		slots = PetConfig.getSlots(slotsLevelOf(data), slotPass == true),
		storage = PetConfig.getStorage(storagePass == true),
		hideOtherPets = cosmetics ~= nil and cosmetics.hideOtherPets == true,
		world = worldOf(data),
	}
end

local function setAttribute(player: Player, value: string)
	if typeof(player) == "Instance" and player:IsA("Player") then
		player:SetAttribute(PetService.ATTRIBUTE, value)
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
		ProfileManager.save(player) -- S11: 새 petId를 얻었을 때만
	end,
	setAttribute = setAttribute,
	hasSlotPass = hasSlotPass,
	hasStoragePass = hasStoragePass,
	isSlotPassResolved = function(player: Player)
		return GamepassService.isResolved(player, "petSlots3")
	end,
	luckOptions = function(player: Player)
		return ShopEffects.luckOptions(player, "pet")
	end,
	hasHatchPass = function(player: Player)
		return GamepassService.owns(player, "hatch3x")
	end,
}

local runtime = createRuntime(REAL)

-- PlayerState가 부르는 요약(게임패스 세션 값 포함).
function PetService.summarizeFor(player: Player, data: any): PetSummary
	return PetService.summarize(data, hasSlotPass(player), hasStoragePass(player))
end

function PetService.hatch(player: Player, eggId: any, source: string): (boolean, any)
	local ok, value = runtime.hatch(player, eggId, source)
	if ok then
		print(string.format(
			"[PetService] %s(%d) 알 %d → %s (희귀도 %d) uid=%s%s%s",
			player.Name, player.UserId, value.eggId, value.petId, value.rarity, value.uid,
			if value.isNew then " 새 펫" else " 중복", if value.equipped then " → 빈 슬롯 장착" else ""
		))
	end
	return ok, value
end

-- 3배 부화(S18). 마리 수는 ShopConfig hatch3x의 count. 성공이면 (true, { HatchResult }).
function PetService.hatchMulti(player: Player, eggId: any, source: string): (boolean, any)
	local def = ShopConfig.get("hatch3x") :: ShopConfig.ProductDef
	local ok, value = runtime.hatchMany(player, eggId, def.effect.count, source)
	if ok then
		local names = {}
		for _, r in ipairs(value) do
			table.insert(names, string.format("%s(uid=%s%s)", r.petId, r.uid, if r.isNew then " 새" else ""))
		end
		print(string.format("[PetService] %s(%d) 알 %d × %d → %s", player.Name, player.UserId, eggId, #value, table.concat(names, ", ")))
	end
	return ok, value
end

function PetService.equip(player: Player, uid: any): (boolean, string?)
	return runtime.equip(player, uid)
end

function PetService.unequip(player: Player, uid: any): (boolean, string?)
	return runtime.unequip(player, uid)
end

function PetService.equipBest(player: Player): (boolean, string?)
	return runtime.equipBest(player)
end

function PetService.craft(player: Player, uid: any): (boolean, any)
	local ok, value = runtime.craft(player, uid)
	if ok then
		print(string.format("[PetService] %s(%d) 크래프팅 → %s 단계 %d uid=%s%s", player.Name, player.UserId, value.petId, value.level, value.uid,
			if value.equipped then " (장착 자리 이어받음)" else ""))
	end
	return ok, value
end

function PetService.release(player: Player, uid: any): (boolean, string?)
	local ok, reason = runtime.release(player, uid)
	if ok then
		print(string.format("[PetService] %s(%d) 놓아주기 uid=%s", player.Name, player.UserId, tostring(uid)))
	end
	return ok, reason
end

local initialized = false

function PetService.init()
	if initialized then
		warn("[PetService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local function onLoaded(player: Player, profile: any)
		runtime.onLoaded(player, profile.Data)
	end
	ProfileManager.onLoaded(onLoaded)
	-- 슬롯 게임패스 소유가 확정되면(접속 조회 끝 · 재조회 성공 · 구매) 장착을 슬롯에 맞춘다(E6 · S17)
	GamepassService.onChanged(function(player: Player)
		local removed = runtime.trimToSlots(player)
		if removed > 0 then
			print(string.format("[PetService] %s(%d) 장착이 슬롯보다 많아 %d마리 해제(소유 확인 뒤)", player.Name, player.UserId, removed))
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = ProfileManager.get(player)
		if profile ~= nil then
			onLoaded(player, profile)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)
	print(string.format("[PetService] 준비 완료 (롤 시계 %g초)", PetConfig.HATCH_INTERVAL_SEC))
end

return PetService

--!strict
-- 펫 뽑기(알) · 크래프팅 · 장착 슬롯 (Phase 7 지시서 #12). 규칙 원본은 DESIGN.md "6. 뽑기 3종 > 펫"(E1~E11) · "3. 화폐와 배수"(E3).
-- 알은 WorldConfig.eggPacks 인덱스로 참조된다.
--
--   E1  알 부화 1회 비용 100 / 100K / 100M(확정 — 아우라 팩과 같은 1000배 간격). 해금 = lifetimeBlox ≥ 그 알의 비용(G8)
--   E2  펫 하나에 값 m 하나. 알 1 사다리(LADDER) 시작값은 사람 결정, 알 n = 알 1 × EGG_RATIO^(n-1).
--       종 희귀도 확률은 아우라와 같은 모양(0.3 / 0.09 / 0.01 판정, 맨 아래 등급이 폴백 — baseChance 없음)
--   E3  펫 배수 = 1 + Σ(장착 펫의 실효 증가분), 실효 증가분 = (m − 1) × CRAFT_FACTOR^(강화 단계 − 1). 빈 슬롯은 0
--       StrengthMultiplier.compute 한 자리에서만 곱한다(petMult). 데미지 항은 없다(S9)
--   E4  크래프팅: petId와 강화 단계가 같은 CRAFT_REQUIREMENT마리 → 같은 petId 다음 단계 1마리. 최대 MAX_LEVEL단계
--   G4 같은 규칙  알 N 최저 m > 알 N−1 최고 m (validate)
--
-- ===== 무엇이 사람 결정이고 무엇이 TEMP인가 ==================================================
--
--   확률 모양 · 알 비용 · 해금 = 비용 · 강화 4단계 · 3마리      사람 결정(E1 · E4 · G7 · G8 · G10)
--   LADDER · EGG_RATIO · CRAFT_FACTOR                      TEMP. 지시서 #12 5단계 권한으로만 조정(알 간 규칙 · 단조 · m ≥ 1)
--   HATCH_INTERVAL_SEC                                     남용 방지 값(밸런스 값 아님). 시작값 초당 4회
--   DISPLAY                                                표시 값(클라 전용 대체물의 크기 · 파트 상한 — E9)
--
-- ⚠️ 저장되는 것은 petId와 강화 단계뿐이다(DESIGN.md 10장 — 이름 · 이미지 · m은 저장하지 않는다). m을 바꾸면 이미 가진 펫도 바뀐다.

local BigNum = require(script.Parent.Parent.BigNum)
local WorldConfig = require(script.Parent.WorldConfig)

type BigNumber = BigNum.BigNumber

export type PetDef = {
	id: string, -- 화면 이름은 Strings "pet.name.<id>" (지시서 #L1 K6 — 화면 이름은 Strings 키, Shared/Localization/Names)
	baseChance: number?, -- 일반(폴백)은 nil
	mult: number, -- m (힘 배수 — 장착 시 실효 증가분으로 합산)
}

export type EggDef = {
	eggId: number, -- 화면 이름은 Strings "egg.name.<번호>" (지시서 #L1 K6 — 화면 이름은 Strings 키, Shared/Localization/Names)
	rollCost: BigNumber, -- = 해금 조건(lifetimeBlox ≥ 이 값, G8)
	pets: { PetDef }, -- 희귀도 낮은 순. 인덱스 = 종 희귀도(1 일반 · 2 희귀 · 3 영웅 · 4 전설)
}

-- 보유 펫 한 마리(프로필 pets.owned[uid]). tier = **강화 단계** 1~MAX_LEVEL(DESIGN 10장 스키마 이름 그대로).
export type OwnedPet = { petId: string, tier: number }

local PetConfig = {}

-- ===== TEMP — m 값 · 강화 배율 (지시서 #12 5단계 권한으로만 조정) =====
PetConfig.LADDER = { 1.05, 1.1, 1.2, 1.4 } -- 알 1 일반 → 전설 (E2 시작값, 사람 결정)
PetConfig.EGG_RATIO = 1.4 -- 알 n = 알 1 × EGG_RATIO^(n-1) (E2). 알 간: 1.05 × 1.4 = 1.47 > 1.4
-- 강화 단계 하나마다 실효 증가분 × 이 값 (E3). 시작값 2.5(사람 결정)는 결정 모델(S5' + S7 + A4 + E11)에서 25층 첫 진입 중앙값이
-- 38.4분(B2 43.0분의 −10.7%)으로 지킬 것(−10% 이내 = 38.7분 이상)을 넘었다 → 지시서 #12 5단계 권한으로 2.2(P1 — 39.0분).
-- 후보별 수치는 SuccessRateReport.PET_VARIANTS 주석. 사다리 · 알 간 비율은 시작값 그대로다.
PetConfig.CRAFT_FACTOR = 2.2

-- 종 희귀도 확률(사람 결정 G7 — 아우라와 같은 모양). 일반은 폴백이라 nil.
local CHANCES: { number? } = { nil, 0.3, 0.09, 0.01 }
PetConfig.TIER_COUNT = 4
PetConfig.MODAL_MIN_TIER = 3 -- 결과 모달: 새 펫이거나 이 종 희귀도(영웅) 이상 (E8)

-- 강화 단계 (E4 · G10). 이름(Strings "pet.level.<단계>")은 종 희귀도와 겹치지 않게 다른 낱말을 쓴다 — LocaleTests가 잰다.
PetConfig.MAX_LEVEL = 4
PetConfig.CRAFT_REQUIREMENT = 3 -- 같은 petId · 같은 단계 3마리 → 다음 단계 1마리

PetConfig.HATCH_INTERVAL_SEC = 0.25 -- 남용 방지. 플레이어당 초당 4회

-- 장착 슬롯: 기본 2 + 업그레이드 최대 +1 + 게임패스 +3 = 최대 6
PetConfig.BaseSlots = 2
PetConfig.UpgradeSlotBonus = 1
PetConfig.GamepassSlotBonus = 3
PetConfig.MaxSlots = PetConfig.BaseSlots + PetConfig.UpgradeSlotBonus + PetConfig.GamepassSlotBonus

-- 저장 공간: 기본 50 + 게임패스 +100
PetConfig.BaseStorage = 50
PetConfig.GamepassStorageBonus = 100

-- 표시(E9 — 클라 전용 대체물). 펫 하나 = 종 희귀도 색 구 1개 + 강화 단계 2 이상이면 외곽 껍질 1개(파트 1~2개).
PetConfig.DISPLAY = {
	SIZE_BY_LEVEL = { 1.2, 1.45, 1.7, 2.0 }, -- 구 지름(스터드). 강화 단계가 오를수록 크다
	SHELL_SCALE = 1.25, -- 껍질 지름 = 구 × 이 값 (단계 2 이상)
	SHELL_HEX = { "", "ffd24a", "bff4ff", "ff7bd8" }, -- 단계별 껍질 색(1단계는 껍질 없음). 무지개는 클라가 색상을 돌린다
	MAX_TOTAL_PARTS = 72, -- 한 클라가 그리는 펫 파트 합 상한(넘는 펫은 그리지 않는다 — 내 펫 먼저)
	BEHIND = 4, -- 캐릭터 뒤 거리(스터드)
	SPACING = 2.6, -- 펫 사이 가로 간격
	HEIGHT = 1.2, -- 허리 높이 기준 위로
	FOLLOW_RATE = 8, -- 보간 속도(1/초). 클수록 빨리 따라붙는다
	PUNCH_PERIOD_SEC = 0.5, -- 블록 반경 안일 때 "치는 모습" 주기(데미지 없음 — S9)
}

local TIER_KEYS = { "common", "rare", "epic", "legendary" }
local EGG_COUNT = 3
PetConfig.EGG_COST_EXPONENTS = { 2, 5, 8 } -- 100 · 100K · 100M (E1 확정)

local Eggs: { [number]: EggDef } = {}
PetConfig.Eggs = Eggs

local indexById: { [string]: { eggId: number, tier: number } } = {}

local function rebuildIndex()
	table.clear(indexById)
	for eggId, egg in pairs(Eggs) do
		for tier, def in ipairs(egg.pets) do
			indexById[def.id] = { eggId = eggId, tier = tier }
		end
	end
end

-- LADDER · EGG_RATIO로 표를 (다시) 만든다. 시뮬레이터 후보 스윕이 값을 바꾼 뒤 부르고, 끝나면 되돌린 값으로 다시 부른다.
-- m은 소수 넷째 자리에서 반올림한다(곱셈 잡음으로 알 간 경계가 흔들리지 않게 — AuraConfig와 같다).
function PetConfig.rebuild()
	for eggId = 1, EGG_COUNT do
		local scale = PetConfig.EGG_RATIO ^ (eggId - 1)
		local pets: { PetDef } = {}
		for tier = 1, PetConfig.TIER_COUNT do
			pets[tier] = {
				id = string.format("egg%d_%s", eggId, TIER_KEYS[tier]),
				baseChance = CHANCES[tier],
				mult = math.floor(PetConfig.LADDER[tier] * scale * 10000 + 0.5) / 10000,
			}
		end
		local existing = Eggs[eggId]
		local cost = BigNum.new(1, PetConfig.EGG_COST_EXPONENTS[eggId])
		if existing ~= nil then
			existing.rollCost = cost
			existing.pets = pets
		else
			Eggs[eggId] = { eggId = eggId, rollCost = cost, pets = pets }
		end
	end
	rebuildIndex()
end

-- id → (정의, 알 번호, 종 희귀도). 모르는 id는 nil.
function PetConfig.get(id: any): (PetDef?, number?, number?)
	if type(id) ~= "string" then
		return nil, nil, nil
	end
	local at = indexById[id]
	if at == nil then
		return nil, nil, nil
	end
	return Eggs[at.eggId].pets[at.tier], at.eggId, at.tier
end

function PetConfig.multOf(id: any): number
	local def = PetConfig.get(id)
	return if def ~= nil then def.mult else 1
end

-- 강화 단계가 올바른가(1~MAX_LEVEL 정수).
function PetConfig.isLevel(level: any): boolean
	return type(level) == "number" and level == level and level % 1 == 0 and level >= 1 and level <= PetConfig.MAX_LEVEL
end

-- 실효 증가분 (E3) = (m − 1) × CRAFT_FACTOR^(단계 − 1). 모르는 id · 깨진 단계는 0(기여 없음).
function PetConfig.effectiveGain(petId: any, level: any): number
	local def = PetConfig.get(petId)
	if def == nil or not PetConfig.isLevel(level) then
		return 0
	end
	return (def.mult - 1) * PetConfig.CRAFT_FACTOR ^ (level - 1)
end

-- 펫 배수 (E3) = 1 + Σ 실효 증가분. pets = 장착 펫 목록({petId, tier}). 빈 목록 · nil이면 1.
-- ⚠️ 목록 안의 nil 구멍에서 멈추지 않도록 # 길이가 아니라 pairs로 돈다(지시서 #12 2단계와 같은 종류의 함정).
function PetConfig.totalMult(pets: { OwnedPet }?): number
	local total = 1
	if type(pets) ~= "table" then
		return total
	end
	for _, pet in pairs(pets) do
		if type(pet) == "table" then
			total += PetConfig.effectiveGain(pet.petId, pet.tier)
		end
	end
	return total
end

-- 장착 목록의 Player Attribute 문자열(E9): "petId:단계,petId:단계". 장착 없음은 "". 서버(PetService)가 쓰고 클라 렌더러가 읽는다.
function PetConfig.serializeEquipped(list: { OwnedPet }): string
	local parts = {}
	for _, pet in ipairs(list) do
		table.insert(parts, string.format("%s:%d", pet.petId, pet.tier))
	end
	return table.concat(parts, ",")
end

-- 위의 역. 모르는 petId · 깨진 단계 · 형식이 틀린 조각은 건너뛴다(Attribute는 문자열이라 클라가 다시 읽어 거른다).
function PetConfig.parseEquipped(s: any): { OwnedPet }
	local out: { OwnedPet } = {}
	if type(s) ~= "string" or #s == 0 then
		return out
	end
	for piece in string.gmatch(s, "[^,]+") do
		local id, lv = string.match(piece, "^([%w_]+):(%d+)$")
		local level = tonumber(lv)
		if id ~= nil and level ~= nil and PetConfig.get(id) ~= nil and PetConfig.isLevel(level) then
			table.insert(out, { petId = id, tier = level })
		end
	end
	return out
end

-- 장착 슬롯 수 — 파생값(v5, 지시서 #10 S12). 프로필에 저장하지 않는다.
--   슬롯 = 기본 + petSlots 업그레이드 레벨 × 업그레이드 보너스 + (게임패스면 게임패스 보너스), 상한 MaxSlots
-- hasSlotPass는 세션 값이다(절대 규칙 5 — 매 세션 MarketplaceService 확인). Phase 8 전까지 호출자는 false를 넘긴다.
-- 레벨이 숫자가 아니거나 음수면 0으로 본다(깨진 입력으로 슬롯이 줄거나 늘지 않게).
function PetConfig.getSlots(petSlotsLevel: number, hasSlotPass: boolean): number
	local level = if type(petSlotsLevel) == "number" and petSlotsLevel == petSlotsLevel and petSlotsLevel > 0
		then math.floor(petSlotsLevel)
		else 0
	local slots = PetConfig.BaseSlots + level * PetConfig.UpgradeSlotBonus
	if hasSlotPass then
		slots += PetConfig.GamepassSlotBonus
	end
	return math.min(slots, PetConfig.MaxSlots)
end

-- 저장 공간 — 파생값(v5, S12). hasStoragePass는 세션 값(위와 같다).
function PetConfig.getStorage(hasStoragePass: boolean): number
	return PetConfig.BaseStorage + (if hasStoragePass then PetConfig.GamepassStorageBonus else 0)
end

-- 열린 알 — 파생값(G8). 두 축: 월드가 **어느 알이 있는지**(WorldConfig.eggPacks), lifetimeBlox가 **어디까지 열렸는지**
-- (해금 조건 = 부화 1회 비용). 반환: 열린 알 번호 배열(월드 순서). 월드가 없으면 빈 배열.
function PetConfig.getUnlockedEggs(lifetimeBlox: BigNumber, worldId: number): { number }
	local world = WorldConfig.get(worldId)
	local out: { number } = {}
	if world == nil then
		return out
	end
	for _, eggId in ipairs(world.eggPacks) do
		local egg = Eggs[eggId]
		if egg ~= nil and BigNum.gte(lifetimeBlox, egg.rollCost) then
			table.insert(out, eggId)
		end
	end
	return out
end

-- 그 월드에 있는 알인가(잠김 여부와 무관 — 창이 잠긴 알도 보여 준다).
function PetConfig.isInWorld(eggId: any, worldId: number): boolean
	local world = WorldConfig.get(worldId)
	if world == nil or type(eggId) ~= "number" then
		return false
	end
	for _, id in ipairs(world.eggPacks) do
		if id == eggId then
			return true
		end
	end
	return false
end

function PetConfig.isUnlocked(eggId: any, lifetimeBlox: BigNumber, worldId: number): boolean
	for _, id in ipairs(PetConfig.getUnlockedEggs(lifetimeBlox, worldId)) do
		if id == eggId then
			return true
		end
	end
	return false
end

function PetConfig.validate(): boolean
	assert(PetConfig.CRAFT_REQUIREMENT >= 2 and PetConfig.CRAFT_REQUIREMENT % 1 == 0, "PetConfig: CRAFT_REQUIREMENT는 2 이상 정수")
	assert(PetConfig.MAX_LEVEL >= 1 and PetConfig.MAX_LEVEL <= 4, "PetConfig: 강화 단계는 1~4")
	assert(type(PetConfig.CRAFT_FACTOR) == "number" and PetConfig.CRAFT_FACTOR > 1 and PetConfig.CRAFT_FACTOR < math.huge,
		"PetConfig: CRAFT_FACTOR는 1보다 큰 유한수(강화하면 실효 증가분이 커져야 한다)")
	assert(type(PetConfig.HATCH_INTERVAL_SEC) == "number" and PetConfig.HATCH_INTERVAL_SEC > 0, "PetConfig: HATCH_INTERVAL_SEC는 0보다 커야 함")
	assert(#PetConfig.LADDER == PetConfig.TIER_COUNT, "PetConfig: LADDER는 종 희귀도 수만큼")
	assert(PetConfig.EGG_RATIO > 1, "PetConfig: EGG_RATIO는 1보다 커야 함")
	assert(
		PetConfig.MaxSlots == PetConfig.BaseSlots + PetConfig.UpgradeSlotBonus + PetConfig.GamepassSlotBonus,
		"PetConfig: MaxSlots 계산이 어긋남"
	)

	local ids = {}
	for id in pairs(Eggs) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local prevCost: BigNumber? = nil
	local prevTop: number? = nil
	for _, id in ipairs(ids) do
		local egg = Eggs[id]
		assert(egg.eggId == id, string.format("PetConfig: 알 %d의 eggId 불일치", id))
		assert(BigNum.gt(egg.rollCost, BigNum.new(0, 0)), string.format("PetConfig: 알 %d의 rollCost는 0보다 커야 함", id))
		assert(#egg.pets == PetConfig.TIER_COUNT, string.format("PetConfig: 알 %d의 펫은 %d종", id, PetConfig.TIER_COUNT))
		assert(egg.pets[1].baseChance == nil, string.format("PetConfig: 알 %d 일반은 폴백(확률 없음)", id))

		local chanceSum = 0
		local prevMult = -math.huge
		local prevChance = math.huge
		for tier, pet in ipairs(egg.pets) do
			assert(pet.mult >= 1 and pet.mult < math.huge, "PetConfig: " .. pet.id .. "의 m은 1 이상 유한수")
			assert(pet.mult > prevMult, "PetConfig: " .. pet.id .. " — 알 안 m은 희귀도가 오를수록 커져야 함")
			prevMult = pet.mult
			if tier > 1 then
				local p = pet.baseChance
				assert(type(p) == "number" and p > 0 and p <= 1, "PetConfig: " .. pet.id .. "의 baseChance가 (0,1] 범위를 벗어남")
				assert((p :: number) < prevChance, "PetConfig: " .. pet.id .. " — 확률은 희귀도가 오를수록 작아져야 함")
				prevChance = p :: number
				chanceSum += p :: number
			end
		end
		assert(chanceSum <= 1 + 1e-9, string.format("PetConfig: 알 %d의 baseChance 합이 1을 초과함 (%.4f)", id, chanceSum))

		local low = egg.pets[1].mult
		if prevTop ~= nil then
			assert(low > prevTop, string.format("PetConfig: 알 %d 최저 m(%g)이 알 %d 최고 m(%g)보다 크지 않음 (알 간 규칙)", id, low, id - 1, prevTop))
		end
		prevTop = egg.pets[#egg.pets].mult

		if prevCost ~= nil then
			assert(BigNum.gt(egg.rollCost, prevCost), string.format("PetConfig: 알 %d의 rollCost가 이전 알보다 크지 않음", id))
		end
		prevCost = egg.rollCost
	end

	local d = PetConfig.DISPLAY
	assert(#d.SIZE_BY_LEVEL == PetConfig.MAX_LEVEL and #d.SHELL_HEX == PetConfig.MAX_LEVEL, "PetConfig: DISPLAY 단계 표는 MAX_LEVEL개")
	assert(d.MAX_TOTAL_PARTS >= 2 * PetConfig.MaxSlots, "PetConfig: DISPLAY.MAX_TOTAL_PARTS는 내 펫 전부(최대 슬롯 × 2파트)보다 커야 함")
	return true
end

PetConfig.rebuild()

return PetConfig

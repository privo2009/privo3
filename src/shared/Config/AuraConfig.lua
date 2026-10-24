--!strict
-- 아우라 뽑기 (Phase 7 지시서 #11). 규칙 원본은 DESIGN.md "6. 뽑기 3종 > 아우라"(A1~A11).
--
--   A1  아우라 하나에 값 m 하나 — 힘 배율 = 데미지 배율 = m. 표시는 "힘·데미지 ×m".
--       m은 StrengthMultiplier.compute와 AttackService 1펀치 데미지 결합에 한 번씩 들어간다 → DPS에는 m²(의도)
--   A2  팩 1 사다리(LADDER) 시작값은 사람 결정, 팩 n = 팩 1 × PACK_RATIO^(n-1). 팩 4 · 5(월드 2)도 같은 비율로 정의만 둔다
--   G1  등급 확률 모양 0.6 / 0.3 / 0.09 / 0.01. 판정은 순차(희귀도 높은 순 — 서버 RollLogic)라 common은 **폴백**이다 —
--       위 셋이 빗나간 나머지 전부(행운 1에서 약 63.7%). 그래서 common에는 baseChance를 두지 않는다(TitleConfig 초보자와 같다)
--   G2  롤 비용 팩마다 1000배(1K → 1M → …). 해금 조건 = 롤 1회 비용(G3) — 열린 팩은 getUnlockedPacks로 파생한다
--   G4  팩 N 최저 m > 팩 N−1 최고 m (validate)
--
-- ===== 무엇이 사람 결정이고 무엇이 TEMP인가 ==================================================
--
--   확률 모양 · 롤 비용 · 해금 = 롤 비용                사람 결정(G1 · G2 · G3)
--   LADDER · PACK_RATIO (m 값)                       TEMP. 지시서 #11 6단계 권한으로만 조정(G4 · 단조 · m ≥ 1)
--   ROLL_INTERVAL_SEC                                남용 방지 값(밸런스 값 아님, A9). 시작값 초당 4회
--   PARTICLE                                         표시 값(방출량 상한 — A7)

local BigNum = require(script.Parent.Parent.BigNum)
local WorldConfig = require(script.Parent.WorldConfig)

type BigNumber = BigNum.BigNumber

export type AuraDef = {
	id: string,
	name: string,
	baseChance: number?, -- common(폴백)은 nil
	mult: number, -- m (힘 = 데미지)
}

export type AuraPackDef = {
	packId: number,
	rollCost: BigNumber, -- = 해금 조건(lifetimeBlox ≥ 이 값)
	auras: { AuraDef }, -- 희귀도 낮은 순. 인덱스 = 등급(1 common · 2 rare · 3 epic · 4 legendary)
}

local AuraConfig = {}

-- ===== TEMP — m 값 (지시서 #11 A2 시작값) =====
AuraConfig.LADDER = { 1.1, 1.25, 1.5, 2.0 } -- 팩 1 common → legendary
AuraConfig.PACK_RATIO = 2.2 -- 팩 n = 팩 1 × PACK_RATIO^(n-1)

-- 등급 확률(사람 결정 G1). common은 폴백이라 nil.
local CHANCES: { number? } = { nil, 0.3, 0.09, 0.01 }
AuraConfig.TIER_NAMES = { "일반", "희귀", "영웅", "전설" }
AuraConfig.TIER_COUNT = 4
AuraConfig.MODAL_MIN_TIER = 3 -- 결과 모달: 새 아우라이거나 이 등급(epic) 이상 (A6)

AuraConfig.ROLL_INTERVAL_SEC = 0.25 -- 남용 방지(A9). 플레이어당 초당 4회

-- 파티클 표시(A7 — 클라 전용, 대체물: 기본 ParticleEmitter). 방출량은 등급마다, 화면 전체 합은 상한을 넘지 않는다.
AuraConfig.PARTICLE = {
	RATE_BY_TIER = { 4, 7, 11, 16 }, -- 초당 입자 수(한 캐릭터)
	LIFETIME_SEC = 1.2,
	MAX_TOTAL_RATE = 120, -- 한 클라가 그리는 모든 아우라의 초당 입자 합 상한(넘으면 비율로 줄인다)
}

local NAMES = {
	{ "반짝임", "불꽃", "번개", "오로라" },
	{ "돌풍", "빙하", "용암", "혜성" },
	{ "성운", "일식", "초신성", "블랙홀" },
	{ "차원균열", "시공왜곡", "붕괴", "특이점" },
	{ "태초", "종말", "영원", "절대자" },
}
local TIER_KEYS = { "common", "rare", "epic", "legendary" }
local PACK_COUNT = 5

local Packs: { [number]: AuraPackDef } = {}
AuraConfig.Packs = Packs

-- LADDER · PACK_RATIO로 표를 (다시) 만든다. 시뮬레이터 후보 스윕이 값을 바꾼 뒤 부르고, 끝나면 되돌린 값으로 다시 부른다.
-- m은 소수 넷째 자리에서 반올림한다(곱셈 잡음으로 G4 경계가 흔들리지 않게).
function AuraConfig.rebuild()
	for packId = 1, PACK_COUNT do
		local scale = AuraConfig.PACK_RATIO ^ (packId - 1)
		local auras: { AuraDef } = {}
		for tier = 1, AuraConfig.TIER_COUNT do
			auras[tier] = {
				id = string.format("pack%d_%s", packId, TIER_KEYS[tier]),
				name = NAMES[packId][tier],
				baseChance = CHANCES[tier],
				mult = math.floor(AuraConfig.LADDER[tier] * scale * 10000 + 0.5) / 10000,
			}
		end
		local existing = Packs[packId]
		local def: AuraPackDef = {
			packId = packId,
			rollCost = BigNum.new(1, 3 * packId), -- 1K · 1M · 1B · 1T · 1Qa (G2)
			auras = auras,
		}
		if existing ~= nil then
			-- 같은 표 객체를 유지한다(다른 모듈이 Packs[n]을 들고 있어도 새 값이 보이게)
			existing.rollCost = def.rollCost
			existing.auras = def.auras
		else
			Packs[packId] = def
		end
	end
	AuraConfig._rebuildIndex()
end

local indexById: { [string]: { packId: number, tier: number } } = {}

function AuraConfig._rebuildIndex()
	table.clear(indexById)
	for packId, pack in pairs(Packs) do
		for tier, def in ipairs(pack.auras) do
			indexById[def.id] = { packId = packId, tier = tier }
		end
	end
end

-- id → (정의, 팩 번호, 등급). 모르는 id는 nil.
function AuraConfig.get(id: any): (AuraDef?, number?, number?)
	if type(id) ~= "string" then
		return nil, nil, nil
	end
	local at = indexById[id]
	if at == nil then
		return nil, nil, nil
	end
	return Packs[at.packId].auras[at.tier], at.packId, at.tier
end

-- 장착 아우라 m. 장착 없음 · 모르는 id는 1.
function AuraConfig.multOf(id: any): number
	local def = AuraConfig.get(id)
	return if def ~= nil then def.mult else 1
end

-- a가 b보다 m이 큰가. b가 없으면(false · 모르는 id) a가 알려진 id면 true — 첫 아우라는 무조건 장착된다.
function AuraConfig.isHigher(a: any, b: any): boolean
	local da = AuraConfig.get(a)
	if da == nil then
		return false
	end
	local db = AuraConfig.get(b)
	return db == nil or da.mult > db.mult
end

-- 열린 아우라 팩 — 파생값(v5 S13 · G3/S8). 두 축: 월드가 **어느 팩이 있는지**(WorldConfig.auraPacks),
-- lifetimeBlox가 **어디까지 열렸는지**(해금 조건 = 롤 1회 비용). 반환: 열린 팩 번호 배열(월드 순서). 월드가 없으면 빈 배열.
function AuraConfig.getUnlockedPacks(lifetimeBlox: BigNumber, worldId: number): { number }
	local world = WorldConfig.get(worldId)
	local out: { number } = {}
	if world == nil then
		return out
	end
	for _, packId in ipairs(world.auraPacks) do
		local pack = Packs[packId]
		if pack ~= nil and BigNum.gte(lifetimeBlox, pack.rollCost) then
			table.insert(out, packId)
		end
	end
	return out
end

-- 그 월드에 있는 팩인가(잠김 여부와 무관 — 창이 잠긴 팩도 보여 준다).
function AuraConfig.isInWorld(packId: any, worldId: number): boolean
	local world = WorldConfig.get(worldId)
	if world == nil or type(packId) ~= "number" then
		return false
	end
	for _, id in ipairs(world.auraPacks) do
		if id == packId then
			return true
		end
	end
	return false
end

function AuraConfig.isUnlocked(packId: any, lifetimeBlox: BigNumber, worldId: number): boolean
	for _, id in ipairs(AuraConfig.getUnlockedPacks(lifetimeBlox, worldId)) do
		if id == packId then
			return true
		end
	end
	return false
end

function AuraConfig.validate(): boolean
	assert(type(AuraConfig.ROLL_INTERVAL_SEC) == "number" and AuraConfig.ROLL_INTERVAL_SEC > 0, "AuraConfig: ROLL_INTERVAL_SEC는 0보다 커야 함")
	assert(#AuraConfig.LADDER == AuraConfig.TIER_COUNT, "AuraConfig: LADDER는 등급 수만큼")
	assert(AuraConfig.PACK_RATIO > 1, "AuraConfig: PACK_RATIO는 1보다 커야 함")
	local ids = {}
	for id in pairs(Packs) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local prevCost: BigNumber? = nil
	local prevTop: number? = nil
	for _, id in ipairs(ids) do
		local pack = Packs[id]
		assert(pack.packId == id, string.format("AuraConfig: 팩 %d의 packId 불일치", id))
		assert(#pack.auras == AuraConfig.TIER_COUNT, string.format("AuraConfig: 팩 %d의 아우라는 %d종", id, AuraConfig.TIER_COUNT))
		assert(pack.auras[1].baseChance == nil, string.format("AuraConfig: 팩 %d common은 폴백(확률 없음)", id))

		local chanceSum = 0
		local prevMult = -math.huge
		local prevChance = math.huge
		for tier, aura in ipairs(pack.auras) do
			assert(aura.mult >= 1 and aura.mult < math.huge, "AuraConfig: " .. aura.id .. "의 m은 1 이상 유한수")
			assert(aura.mult > prevMult, "AuraConfig: " .. aura.id .. " — 팩 안 m은 등급이 오를수록 커져야 함")
			prevMult = aura.mult
			if tier > 1 then
				local p = aura.baseChance
				assert(type(p) == "number" and p > 0 and p <= 1, "AuraConfig: " .. aura.id .. "의 baseChance가 (0,1] 범위를 벗어남")
				assert((p :: number) < prevChance, "AuraConfig: " .. aura.id .. " — 확률은 등급이 오를수록 작아져야 함")
				prevChance = p :: number
				chanceSum += p :: number
			end
		end
		assert(chanceSum <= 1 + 1e-9, string.format("AuraConfig: 팩 %d의 baseChance 합이 1을 초과함 (%.4f)", id, chanceSum))

		local low = pack.auras[1].mult
		if prevTop ~= nil then
			assert(low > prevTop, string.format("AuraConfig: 팩 %d 최저 m(%g)이 팩 %d 최고 m(%g)보다 크지 않음 (G4)", id, low, id - 1, prevTop))
		end
		prevTop = pack.auras[#pack.auras].mult

		if prevCost ~= nil then
			assert(BigNum.gt(pack.rollCost, prevCost), string.format("AuraConfig: 팩 %d의 rollCost가 이전 팩보다 크지 않음", id))
		end
		prevCost = pack.rollCost
	end
	local rate = AuraConfig.PARTICLE.RATE_BY_TIER
	assert(#rate == AuraConfig.TIER_COUNT, "AuraConfig: PARTICLE.RATE_BY_TIER는 등급 수만큼")
	for i = 1, #rate do
		assert(rate[i] > 0 and rate[i] <= AuraConfig.PARTICLE.MAX_TOTAL_RATE, "AuraConfig: 파티클 방출량은 0보다 크고 상한 이하")
	end
	return true
end

AuraConfig.rebuild()

return AuraConfig

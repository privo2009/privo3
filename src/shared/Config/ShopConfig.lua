--!strict
-- 로벅스 상품 카탈로그 — 게임패스 · 힘 배수 계단 · 개발자 상품 (Phase 8 지시서 #16, 2026-10-25 사람 결정).
-- 규칙 원본은 DESIGN.md "9. 수익화"(상품 목록 · 폐기 · 미룸 · S1 ~ S18). **가격 · 효과 수치의 원본은 이 파일이다.**
-- 대시보드 등록용 한 장은 docs/DASHBOARD_PRODUCTS.md(이 표를 사람이 대시보드에 옮기고, 받은 ID를 여기 id에 넣는다).
--
-- ===== 대시보드 ID (2026-10-30 등록 — 지시서 #17) ======================================================
--
-- 키 하나에 ID 하나. 게임패스와 개발자 상품은 표를 나눈다 — validate가 섞임(게임패스 키가 상품 표에 있는 것 등) · 같은 ID 두 번 ·
-- 0 이하 ID를 거부한다. 값은 사람이 Creator Dashboard에서 옮겨 준 것(docs/DASHBOARD_PRODUCTS.md — 이름 · 가격도 거기).
-- 가격은 대시보드 가격과 같아야 한다. 서버가 시작할 때 GetProductInfoAsync로 대조해 다르면 WARN만 한다(ShopPriceCheck).
-- id 0("대시보드에 없다")의 처리는 그대로 남아 있다 — 화면 "준비 중" · 서버 not_registered(MarketplaceGateway — 프롬프트를 띄우지 않는다).
-- 지금 표에는 0이 없다. 테스트는 MarketplaceGateway.fakeCatalog로 원하는 상품만 등록된 표를 만든다.
--
-- ===== 행운 상품 (paidRandom) =====================================================================
--
-- 확률을 바꾸는 로벅스 상품은 유료 랜덤 아이템이다(DESIGN 6장 P2 · 9장 S13). 제한 지역 유저(PolicyService)에게는 숨기고 보유해도 효과를 끈다.
-- paidRandom은 효과에서 나오는 값과 같아야 한다 — validate가 잰다(행운 패스 · 롤 충전 · 행운 포션 · 행운 포션이 든 번들).
--
-- ⚠️ 블럭스를 로벅스로 파는 상품은 두지 않는다(P1 — CLAUDE.md 금지 사항). effect.type "blox"는 validate가 거부한다.
--    2배 블럭스 게임패스(버는 양 ×2)는 판다(S14 — 사람 결정, 위험 기록은 docs/PENDING.md).

local ShopConfig = {}

export type Kind = "gamepass" | "product"

export type ProductDef = {
	key: string,
	kind: Kind,
	id: number, -- Roblox GamePassId / ProductId. 0 = 미등록
	-- 이름 · 설명은 여기 없다 — Strings "shop.<키>.name" · ".desc"(영어가 대시보드 이름 · 설명. 지시서 #L1 K6, Shared/Localization/Names)
	priceRobux: number,
	effect: { [string]: any },
	paidRandom: boolean, -- 로벅스 행운 상품(S13)
}

-- 포션(부스트) 정의. 개발자 상품 effect.boost가 이 키를 가리킨다. 엔진은 Server/Systems/BoostService(S7).
-- mult는 켜 있는 동안의 배수, durationSec는 1개를 켤 때 더해지는 시간(같은 종류를 또 켜면 시간만 더해진다 — 배수는 그대로).
-- 이름은 Strings "boost.<키>.name"(지시서 #L1 K6).
export type BoostDef = { mult: number, durationSec: number, paidRandom: boolean }
ShopConfig.BOOSTS = {
	strength = { mult = 2, durationSec = 900, paidRandom = false }, -- 힘 ×2 (StrengthMultiplier)
	damage = { mult = 2, durationSec = 900, paidRandom = false }, -- 1펀치 데미지 ×2
	luck = { mult = 2, durationSec = 900, paidRandom = true }, -- 칭호 · 아우라 · 펫 행운 ×2
} :: { [string]: BoostDef }
ShopConfig.BOOST_ORDER = { "strength", "damage", "luck" }

ShopConfig.GAMEPASS_IDS = {
	strength2x       = 2052216044, -- x2 Power · 3 R$
	strength4x       = 2052702002, -- x4 Power · 9 R$
	strength8x       = 2052210043, -- x8 Power · 29 R$
	strength16x      = 2052438033, -- x16 Power · 79 R$
	strength32x      = 2054039990, -- x32 Power · 149 R$
	strength64x      = 2052954081, -- x64 Power · 249 R$
	strength128x     = 2052480115, -- x128 Power · 399 R$
	strength256x     = 2053890027, -- x256 Power · 499 R$
	strength512x     = 2053164055, -- x512 Power · 599 R$
	strength1024x    = 2052390076, -- x1024 Power · 699 R$
	autoClicker      = 2052132045, -- Auto Clicker · 49 R$
	autoClickerOP    = 2053242108, -- OP Auto Clicker · 89 R$
	rebirth2x        = 2054058093, -- x2 Rebirths · 99 R$
	damage2x         = 2052696040, -- x2 Damage · 149 R$
	blox2x           = 2054262102, -- x2 Blox · 199 R$
	hatch3x          = 2052474059, -- Triple Hatch · 99 R$
	petLuck2x        = 2052954089, -- x2 Pet Luck · 99 R$
	petStorage100    = 2054172019, -- +100 Pet Storage · 49 R$
	petSlots3        = 2053284114, -- +3 Pet Slots · 199 R$
	auraLuck10x      = 2053680063, -- x10 Aura Luck · 299 R$
	titleLuck10x     = 2052546070, -- x10 Title Luck · 299 R$
	voidTrainingZone = 2054052054, -- Void Training Zone · 799 R$
	autoAdvance      = 2053542093, -- Auto Advance · 199 R$
} :: { [string]: number }

ShopConfig.PRODUCT_IDS = {
	luckyRoll5     = 3722238324, -- Lucky Roll x5 · 49 R$
	luckyRoll15    = 3722238413, -- Lucky Roll x15 · 149 R$
	superRoll5     = 3722238507, -- Super Roll x5 · 99 R$
	superRoll15    = 3722238589, -- Super Roll x15 · 249 R$
	strengthPotion = 3722238698, -- Power Potion · 19 R$
	damagePotion   = 3722238762, -- Damage Potion · 19 R$
	luckPotion     = 3722238841, -- Luck Potion · 29 R$
	potionBundle   = 3722238982, -- Potion Bundle · 999 R$
	gymUnlock1     = 3722239093, -- Gym 1 Unlock · 29 R$
	gymUnlock2     = 3722239174, -- Gym 2 Unlock · 49 R$
	gymUnlock3     = 3722239239, -- Gym 3 Unlock · 79 R$
	gymUnlock4     = 3722239675, -- Gym 4 Unlock · 99 R$
	gymUnlock5     = 3722239721, -- Gym 5 Unlock · 149 R$
	gymUnlock6     = 3722239888, -- Gym 6 Unlock · 199 R$
	gymUnlock7     = 3722240101, -- Gym 7 Unlock · 299 R$
	gymUnlock8     = 3722240268, -- Gym 8 Unlock · 449 R$
} :: { [string]: number }

local Products: { [string]: ProductDef } = {}
ShopConfig.Products = Products

local function add(def: ProductDef)
	assert(Products[def.key] == nil, "ShopConfig: 상품 키 중복 - " .. def.key)
	Products[def.key] = def
end

local function pass(key: string, price: number, effect: { [string]: any }, paidRandom: boolean?)
	add({ key = key, kind = "gamepass", id = ShopConfig.GAMEPASS_IDS[key] or 0, priceRobux = price, effect = effect, paidRandom = paidRandom == true })
end

local function product(key: string, price: number, effect: { [string]: any }, paidRandom: boolean?)
	add({ key = key, kind = "product", id = ShopConfig.PRODUCT_IDS[key] or 0, priceRobux = price, effect = effect, paidRandom = paidRandom == true })
end

-- ===== 게임패스 ==================================================================================
pass("autoClicker", 49, { type = "autoClick", clicksPerSec = 15 })
pass("autoClickerOP", 89, { type = "autoClick", clicksPerSec = 30 })
pass("rebirth2x", 99, { type = "rebirthMult", mult = 2 })
pass("hatch3x", 99, { type = "hatchMulti", count = 3 })
pass("petLuck2x", 99, { type = "luckPass", roll = "pet", mult = 2 }, true)
pass("petStorage100", 49, { type = "petStorage" }) -- 보너스 수는 PetConfig.GamepassStorageBonus
pass("damage2x", 149, { type = "damageMult", mult = 2 })
pass("petSlots3", 199, { type = "petSlots" }) -- 보너스 수는 PetConfig.GamepassSlotBonus
pass("blox2x", 199, { type = "bloxMult", mult = 2 })
pass("auraLuck10x", 299, { type = "luckPass", roll = "aura", mult = 10 }, true)
pass("titleLuck10x", 299, { type = "luckPass", roll = "title", mult = 10 }, true)
pass("voidTrainingZone", 799, { type = "gymPass" }) -- 기구는 GymConfig(gamepassKey)가 가리킨다
pass("autoAdvance", 199, { type = "autoAdvance" }) -- 효과는 #18

-- ===== 힘 배수 계단 (게임패스 10단계 — 보유한 단계 중 최고 하나만, S4) ============================
-- 가격 2026-10-30 사람 결정(지시서 #17 — 대시보드 가격): 32x부터 149 · 249 · 399 · 499 · 599 · 699
ShopConfig.STRENGTH_TIERS = {} :: { string }
for _, t in ipairs({ { 2, 3 }, { 4, 9 }, { 8, 29 }, { 16, 79 }, { 32, 149 }, { 64, 249 }, { 128, 399 }, { 256, 499 }, { 512, 599 }, { 1024, 699 } }) do
	local key = string.format("strength%dx", t[1])
	pass(key, t[2], { type = "strengthTier", mult = t[1] })
	table.insert(ShopConfig.STRENGTH_TIERS, key)
end

-- ===== 개발자 상품 ================================================================================
product("luckyRoll5", 49, { type = "rollCredit", credit = "lucky", rolls = 5, luckMult = 5 }, true)
product("luckyRoll15", 149, { type = "rollCredit", credit = "lucky", rolls = 15, luckMult = 5 }, true)
product("superRoll5", 99, { type = "rollCredit", credit = "super", rolls = 5, luckMult = 100 }, true)
product("superRoll15", 249, { type = "rollCredit", credit = "super", rolls = 15, luckMult = 100 }, true)
product("strengthPotion", 19, { type = "potion", boost = "strength", count = 1 })
product("damagePotion", 19, { type = "potion", boost = "damage", count = 1 })
product("luckPotion", 29, { type = "potion", boost = "luck", count = 1 }, true)
product("potionBundle", 999, { type = "potionBundle", counts = { strength = 99, damage = 99, luck = 99 } }, true)

-- 운동기구 선해금 8종. 가격은 2026-10-21 GymConfig 값 그대로(29 ~ 449). GymConfig는 이 키로 참조한다(원본 한 곳).
ShopConfig.GYM_UNLOCKS = {} :: { string }
for i, price in ipairs({ 29, 49, 79, 99, 149, 199, 299, 449 }) do
	local key = "gymUnlock" .. i
	product(key, price, { type = "gymUnlock", gymIndex = i })
	table.insert(ShopConfig.GYM_UNLOCKS, key)
end

-- 상점 창 로벅스 탭 순서(게임패스). 힘 배수 계단은 이 목록 앞에 한 줄로 따로 그린다.
ShopConfig.GAMEPASS_ORDER = {
	"autoClicker", "autoClickerOP", "damage2x", "blox2x", "rebirth2x", "voidTrainingZone", "autoAdvance",
	"petSlots3", "petStorage100", "hatch3x", "petLuck2x", "auraLuck10x", "titleLuck10x",
}

-- 반드시 "최고 단계만". 절대 누적 곱셈 금지 (CLAUDE.md 금지 사항).
ShopConfig.STRENGTH_TIER_NOTE = "highest_only"

-- ===== 조회 ========================================================================================

function ShopConfig.get(key: any): ProductDef?
	if type(key) ~= "string" then
		return nil
	end
	return Products[key]
end

function ShopConfig.isRegistered(key: any): boolean
	local def = ShopConfig.get(key)
	return def ~= nil and def.id ~= 0
end

-- 게임패스 키 전부(계단 포함). 순서는 키 이름순(결정적).
function ShopConfig.gamepassKeys(): { string }
	local out = {}
	for key, def in pairs(Products) do
		if def.kind == "gamepass" then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

-- 대시보드 ID → 키. 영수증(ProductId) · 구매 완료 이벤트(GamePassId)가 이 함수로 키를 찾는다. 0은 찾지 않는다.
function ShopConfig.findById(kind: Kind, id: any): string?
	if type(id) ~= "number" or id == 0 then
		return nil
	end
	for key, def in pairs(Products) do
		if def.kind == kind and def.id == id then
			return key
		end
	end
	return nil
end

-- 힘 배수 계단: 보유한 단계 중 가장 높은 배수 하나(없으면 1). owns(key) → boolean.
function ShopConfig.strengthTierMult(owns: (string) -> boolean): number
	local best = 1
	for _, key in ipairs(ShopConfig.STRENGTH_TIERS) do
		local def = Products[key]
		if def.effect.mult > best and owns(key) then
			best = def.effect.mult
		end
	end
	return best
end

-- 지금 보유한 최고 단계 키(없으면 nil)와 그다음 단계 키(최고면 nil). 상점 "지금 단계" 줄이 쓴다.
function ShopConfig.strengthTierState(owns: (string) -> boolean): (string?, string?)
	local current: string? = nil
	for _, key in ipairs(ShopConfig.STRENGTH_TIERS) do
		if owns(key) then
			current = key
		end
	end
	local nextKey: string? = nil
	for _, key in ipairs(ShopConfig.STRENGTH_TIERS) do
		local def = Products[key]
		local curMult = if current ~= nil then Products[current :: string].effect.mult else 1
		if def.effect.mult > curMult then
			nextKey = key
			break
		end
	end
	return current, nextKey
end

-- 더 높은 단계를 이미 가져서 이 상품을 살 필요가 없는가(지시서 #17 — 2026-10-30 사람 결정). 사유 코드 또는 nil.
--   R1 힘 배수 계단: 보유한 최고 단계 이하 → "ladder_owned_higher"(같은 단계는 이 함수가 아니라 already_owned가 먼저 막는다)
--   R2 자동 클리커: OP를 가졌으면 기본 자동 클리커 → "auto_owned_higher"
-- 서버 PurchaseRequestService(프롬프트 전 거부)와 화면(로벅스 탭 · HUD 구좌 잠금)이 같은 함수를 쓴다.
ShopConfig.REASON_LADDER_OWNED_HIGHER = "ladder_owned_higher"
ShopConfig.REASON_AUTO_OWNED_HIGHER = "auto_owned_higher"
function ShopConfig.ownedHigher(key: string, owns: (string) -> boolean): string?
	local def = Products[key]
	if def == nil then
		return nil
	end
	if def.effect.type == "strengthTier" then
		if ShopConfig.strengthTierMult(owns) > def.effect.mult then
			return ShopConfig.REASON_LADDER_OWNED_HIGHER
		end
	elseif def.effect.type == "autoClick" then
		for otherKey, other in pairs(Products) do
			if other.effect.type == "autoClick" and other.effect.clicksPerSec > def.effect.clicksPerSec and owns(otherKey) then
				return ShopConfig.REASON_AUTO_OWNED_HIGHER
			end
		end
	end
	return nil
end

-- 그 뽑기(title · aura · pet)의 행운 패스 배수. 보유한 패스 중 그 뽑기 것만(지금은 뽑기마다 하나).
function ShopConfig.luckPassMult(roll: string, owns: (string) -> boolean): number
	local m = 1
	for key, def in pairs(Products) do
		if def.effect.type == "luckPass" and def.effect.roll == roll and owns(key) then
			m *= def.effect.mult
		end
	end
	return m
end

-- 키가 주는 효과 배수(type이 맞으면 mult, 아니면 1). damage2x · blox2x · rebirth2x가 쓴다.
function ShopConfig.passMult(key: string, owns: (string) -> boolean): number
	local def = Products[key]
	if def == nil or not owns(key) then
		return 1
	end
	return def.effect.mult or 1
end

-- 자동 클리커 초당 횟수: 보유한 것 중 높은 쪽만(둘 다 있으면 30). 없으면 0.
function ShopConfig.autoClickRate(owns: (string) -> boolean): number
	local best = 0
	for key, def in pairs(Products) do
		if def.effect.type == "autoClick" and def.effect.clicksPerSec > best and owns(key) then
			best = def.effect.clicksPerSec
		end
	end
	return best
end

local function effectIsPaidRandom(def: ProductDef): boolean
	local e = def.effect
	if e.type == "luckPass" or e.type == "rollCredit" then
		return true
	end
	if e.type == "potion" then
		local boost = ShopConfig.BOOSTS[e.boost]
		return boost ~= nil and boost.paidRandom
	end
	if e.type == "potionBundle" then
		for boostKey, n in pairs(e.counts) do
			local boost = ShopConfig.BOOSTS[boostKey]
			if boost ~= nil and boost.paidRandom and n > 0 then
				return true
			end
		end
	end
	return false
end
ShopConfig._effectIsPaidRandom = effectIsPaidRandom

function ShopConfig.validate(): boolean
	local ids: { [number]: string } = {}
	-- ID 표: 섞임 없음(게임패스 표의 키는 게임패스, 상품 표의 키는 개발자 상품) · 표에 없는 상품 키 없음(지시서 #17)
	for key in pairs(ShopConfig.GAMEPASS_IDS) do
		assert(Products[key] ~= nil and Products[key].kind == "gamepass", "ShopConfig: GAMEPASS_IDS에 게임패스가 아닌 키 - " .. key)
	end
	for key in pairs(ShopConfig.PRODUCT_IDS) do
		assert(Products[key] ~= nil and Products[key].kind == "product", "ShopConfig: PRODUCT_IDS에 개발자 상품이 아닌 키 - " .. key)
	end
	for key, def in pairs(Products) do
		assert(def.key == key, "ShopConfig: 키가 표 키와 다름 - " .. key)
		assert(def.kind == "gamepass" or def.kind == "product", "ShopConfig: kind가 이상함 - " .. key)
		assert(type(def.priceRobux) == "number" and def.priceRobux > 0 and def.priceRobux % 1 == 0, "ShopConfig: 가격은 양의 정수 - " .. key)
		assert(type(def.id) == "number" and def.id > 0 and def.id % 1 == 0, "ShopConfig: id는 양의 정수(대시보드 ID) - " .. key)
		local fromTable = if def.kind == "gamepass" then ShopConfig.GAMEPASS_IDS[key] else ShopConfig.PRODUCT_IDS[key]
		assert(fromTable == def.id, "ShopConfig: id가 그 종류의 ID 표와 다름(게임패스 · 상품 섞임) - " .. key)
		assert(type(def.effect) == "table" and type(def.effect.type) == "string", "ShopConfig: effect.type이 없음 - " .. key)
		-- P1: 블럭스를 로벅스로 파는 상품 금지(CLAUDE.md 금지 사항)
		assert(def.effect.type ~= "blox", "ShopConfig: " .. key .. "이 블럭스를 판다 — 금지(P1, 뽑기가 유료 랜덤 아이템이 된다)")
		assert(def.paidRandom == effectIsPaidRandom(def), "ShopConfig: 행운 상품 표시(paidRandom)가 효과와 다름 - " .. key)
		-- 같은 ID 두 번 금지 — 종류가 달라도(게임패스 ID를 개발자 상품에 넣는 실수를 잡는다)
		assert(ids[def.id] == nil, "ShopConfig: 같은 ID를 두 상품이 씀 - " .. key .. " · " .. tostring(ids[def.id]))
		ids[def.id] = key
		if def.effect.type == "potion" then
			assert(ShopConfig.BOOSTS[def.effect.boost] ~= nil, "ShopConfig: 없는 포션 - " .. key)
		end
	end
	-- 계단: 배수 · 가격 순증가
	local prevMult, prevPrice = 1, 0
	for i, key in ipairs(ShopConfig.STRENGTH_TIERS) do
		local def = Products[key]
		assert(def ~= nil and def.kind == "gamepass" and def.effect.type == "strengthTier", "ShopConfig: 계단 " .. i .. "이 계단 게임패스가 아님")
		assert(def.effect.mult > prevMult, string.format("ShopConfig: 힘 배수 계단 %d번째 배수가 이전보다 크지 않음", i))
		assert(def.priceRobux > prevPrice, string.format("ShopConfig: 힘 배수 계단 %d번째 가격이 이전보다 크지 않음", i))
		prevMult, prevPrice = def.effect.mult, def.priceRobux
	end
	-- 상점 순서: 계단이 아닌 게임패스 전부 · 한 번씩
	local listed: { [string]: boolean } = {}
	for _, key in ipairs(ShopConfig.GAMEPASS_ORDER) do
		local def = Products[key]
		assert(def ~= nil and def.kind == "gamepass" and def.effect.type ~= "strengthTier" and not listed[key], "ShopConfig: GAMEPASS_ORDER 이상 - " .. key)
		listed[key] = true
	end
	for key, def in pairs(Products) do
		if def.kind == "gamepass" and def.effect.type ~= "strengthTier" then
			assert(listed[key], "ShopConfig: 게임패스 " .. key .. "이 GAMEPASS_ORDER에 없음")
		end
	end
	for key, boost in pairs(ShopConfig.BOOSTS) do
		assert(boost.mult > 1 and boost.durationSec > 0, "ShopConfig: 포션 값 - " .. key)
	end
	return true
end

return ShopConfig

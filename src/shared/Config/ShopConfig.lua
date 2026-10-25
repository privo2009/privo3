--!strict
-- 로벅스 상품 카탈로그 — 게임패스 · 힘 배수 계단 · 개발자 상품 (Phase 8 지시서 #16, 2026-10-25 사람 결정).
-- 규칙 원본은 DESIGN.md "9. 수익화"(상품 목록 · 폐기 · 미룸 · S1 ~ S18). **가격 · 효과 수치의 원본은 이 파일이다.**
-- 대시보드 등록용 한 장은 docs/DASHBOARD_PRODUCTS.md(이 표를 사람이 대시보드에 옮기고, 받은 ID를 여기 id에 넣는다).
--
-- ===== id = 0 =====================================================================================
--
-- 0은 "아직 대시보드에 없다"이다. 0인 상품은 화면에 "준비 중"으로 보이고 구매 요청은 서버가 not_registered로 막는다
-- (MarketplaceGateway — 프롬프트를 띄우지 않는다). 소유 조회도 하지 않는다(없는 패스는 아무도 갖지 않는다).
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
	name: string, -- 화면 · 대시보드 이름(한국어)
	priceRobux: number,
	description: string, -- 대시보드 설명 · 상점 줄 설명 한 줄(한국어)
	effect: { [string]: any },
	paidRandom: boolean, -- 로벅스 행운 상품(S13)
}

-- 포션(부스트) 정의. 개발자 상품 effect.boost가 이 키를 가리킨다. 엔진은 Server/Systems/BoostService(S7).
-- mult는 켜 있는 동안의 배수, durationSec는 1개를 켤 때 더해지는 시간(같은 종류를 또 켜면 시간만 더해진다 — 배수는 그대로).
export type BoostDef = { name: string, mult: number, durationSec: number, paidRandom: boolean }
ShopConfig.BOOSTS = {
	strength = { name = "힘 포션", mult = 2, durationSec = 900, paidRandom = false }, -- 힘 ×2 (StrengthMultiplier)
	damage = { name = "데미지 포션", mult = 2, durationSec = 900, paidRandom = false }, -- 1펀치 데미지 ×2
	luck = { name = "행운 포션", mult = 2, durationSec = 900, paidRandom = true }, -- 칭호 · 아우라 · 펫 행운 ×2
} :: { [string]: BoostDef }
ShopConfig.BOOST_ORDER = { "strength", "damage", "luck" }

local Products: { [string]: ProductDef } = {}
ShopConfig.Products = Products

local function add(def: ProductDef)
	assert(Products[def.key] == nil, "ShopConfig: 상품 키 중복 - " .. def.key)
	Products[def.key] = def
end

local function pass(key: string, name: string, price: number, description: string, effect: { [string]: any }, paidRandom: boolean?)
	add({ key = key, kind = "gamepass", id = 0, name = name, priceRobux = price, description = description, effect = effect, paidRandom = paidRandom == true })
end

local function product(key: string, name: string, price: number, description: string, effect: { [string]: any }, paidRandom: boolean?)
	add({ key = key, kind = "product", id = 0, name = name, priceRobux = price, description = description, effect = effect, paidRandom = paidRandom == true })
end

-- ===== 게임패스 ==================================================================================
pass("autoClicker", "자동 클리커", 49, "켜 두면 초당 15번 자동으로 클릭해요", { type = "autoClick", clicksPerSec = 15 })
pass("autoClickerOP", "OP 자동 클리커", 89, "켜 두면 초당 30번 자동으로 클릭해요", { type = "autoClick", clicksPerSec = 30 })
pass("rebirth2x", "2배 환생", 99, "환생할 때 얻는 환생 수가 2배예요", { type = "rebirthMult", mult = 2 })
pass("hatch3x", "3배 부화", 99, "알을 한 번에 3개 부화해요(비용 3배)", { type = "hatchMulti", count = 3 })
pass("petLuck2x", "2배 펫 행운", 99, "펫 부화 행운이 2배예요", { type = "luckPass", roll = "pet", mult = 2 }, true)
pass("petStorage100", "+100 펫 저장 공간", 49, "펫을 100마리 더 보관해요", { type = "petStorage" }) -- 보너스 수는 PetConfig.GamepassStorageBonus
pass("damage2x", "2배 데미지", 149, "1펀치 데미지가 2배예요", { type = "damageMult", mult = 2 })
pass("petSlots3", "+3 펫 장착", 199, "펫을 3마리 더 장착해요", { type = "petSlots" }) -- 보너스 수는 PetConfig.GamepassSlotBonus
pass("blox2x", "2배 블럭스", 199, "수령할 때 받는 블럭스가 2배예요", { type = "bloxMult", mult = 2 })
pass("auraLuck10x", "10배 아우라 행운", 299, "아우라 뽑기 행운이 10배예요", { type = "luckPass", roll = "aura", mult = 10 }, true)
pass("titleLuck10x", "10배 칭호 행운", 299, "칭호 뽑기 행운이 10배예요", { type = "luckPass", roll = "title", mult = 10 }, true)
pass("voidTrainingZone", "공허 훈련 구역", 799, "가장 센 운동기구를 열어요", { type = "gymPass" }) -- 기구는 GymConfig(gamepassKey)가 가리킨다
pass("autoAdvance", "자동 진행", 199, "목표층까지 멈추지 않고 진행해요", { type = "autoAdvance" }) -- 효과는 #18

-- ===== 힘 배수 계단 (게임패스 10단계 — 보유한 단계 중 최고 하나만, S4) ============================
ShopConfig.STRENGTH_TIERS = {} :: { string }
for _, t in ipairs({ { 2, 3 }, { 4, 9 }, { 8, 29 }, { 16, 79 }, { 32, 249 }, { 64, 799 }, { 128, 1499 }, { 256, 2499 }, { 512, 3999 }, { 1024, 5999 } }) do
	local key = string.format("strength%dx", t[1])
	pass(key, string.format("%d배 힘", t[1]), t[2], string.format("클릭으로 얻는 힘이 %d배예요(가장 높은 단계 하나만)", t[1]),
		{ type = "strengthTier", mult = t[1] })
	table.insert(ShopConfig.STRENGTH_TIERS, key)
end

-- ===== 개발자 상품 ================================================================================
product("luckyRoll5", "럭키 롤 5회", 49, "아우라 뽑기 5회 · 행운 ×5 · 블럭스 없이", { type = "rollCredit", credit = "lucky", rolls = 5, luckMult = 5 }, true)
product("luckyRoll15", "럭키 롤 15회", 149, "아우라 뽑기 15회 · 행운 ×5 · 블럭스 없이", { type = "rollCredit", credit = "lucky", rolls = 15, luckMult = 5 }, true)
product("superRoll5", "슈퍼 롤 5회", 99, "아우라 뽑기 5회 · 행운 ×100 · 블럭스 없이", { type = "rollCredit", credit = "super", rolls = 5, luckMult = 100 }, true)
product("superRoll15", "슈퍼 롤 15회", 249, "아우라 뽑기 15회 · 행운 ×100 · 블럭스 없이", { type = "rollCredit", credit = "super", rolls = 15, luckMult = 100 }, true)
product("strengthPotion", "힘 포션", 19, "15분 동안 힘 ×2", { type = "potion", boost = "strength", count = 1 })
product("damagePotion", "데미지 포션", 19, "15분 동안 1펀치 데미지 ×2", { type = "potion", boost = "damage", count = 1 })
product("luckPotion", "행운 포션", 29, "15분 동안 칭호 · 아우라 · 펫 행운 ×2", { type = "potion", boost = "luck", count = 1 }, true)
product("potionBundle", "포션 번들", 999, "힘 · 데미지 · 행운 포션 각 99개", { type = "potionBundle", counts = { strength = 99, damage = 99, luck = 99 } }, true)

-- 운동기구 선해금 8종. 가격은 2026-10-21 GymConfig 값 그대로(29 ~ 449). GymConfig는 이 키로 참조한다(원본 한 곳).
ShopConfig.GYM_UNLOCKS = {} :: { string }
for i, price in ipairs({ 29, 49, 79, 99, 149, 199, 299, 449 }) do
	local key = "gymUnlock" .. i
	product(key, string.format("운동기구 %d 열기", i), price, string.format("환생 수와 상관없이 운동기구 %d을 열어요", i), { type = "gymUnlock", gymIndex = i })
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
	local ids: { [string]: string } = {}
	for key, def in pairs(Products) do
		assert(def.key == key, "ShopConfig: 키가 표 키와 다름 - " .. key)
		assert(def.kind == "gamepass" or def.kind == "product", "ShopConfig: kind가 이상함 - " .. key)
		assert(type(def.priceRobux) == "number" and def.priceRobux > 0 and def.priceRobux % 1 == 0, "ShopConfig: 가격은 양의 정수 - " .. key)
		assert(type(def.name) == "string" and #def.name > 0 and type(def.description) == "string" and #def.description > 0, "ShopConfig: 이름 · 설명 - " .. key)
		assert(type(def.id) == "number" and def.id >= 0 and def.id % 1 == 0, "ShopConfig: id는 0 이상 정수 - " .. key)
		assert(type(def.effect) == "table" and type(def.effect.type) == "string", "ShopConfig: effect.type이 없음 - " .. key)
		-- P1: 블럭스를 로벅스로 파는 상품 금지(CLAUDE.md 금지 사항)
		assert(def.effect.type ~= "blox", "ShopConfig: " .. key .. "이 블럭스를 판다 — 금지(P1, 뽑기가 유료 랜덤 아이템이 된다)")
		assert(def.paidRandom == effectIsPaidRandom(def), "ShopConfig: 행운 상품 표시(paidRandom)가 효과와 다름 - " .. key)
		if def.id ~= 0 then
			local slot = def.kind .. ":" .. def.id
			assert(ids[slot] == nil, "ShopConfig: 같은 ID를 두 상품이 씀 - " .. key .. " · " .. tostring(ids[slot]))
			ids[slot] = key
		end
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

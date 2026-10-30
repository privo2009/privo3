--!strict
-- Config id → 화면 이름 (지시서 #L1 K6). Config에는 id만 있고 이름은 Strings에 있다 — 이 파일이 id로 키를 만든다.
-- 키 꼴은 아래 함수마다 한 줄. Strings에 그 키가 다 있는지는 LocaleTests · tools/check_strings.py가 잰다.
-- 시뮬레이터 · 리포트(Server/Tools)는 이 파일을 쓰지 않고 id를 그대로 찍는다(K6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(script.Parent.Locale)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

local Names = {}

-- 희귀도(아우라 등급 · 펫 종 희귀도) 단계 1 ~ 4 → 키 이름. AuraConfig · PetConfig의 TIER_KEYS와 같은 순서다.
Names.RARITY_KEYS = { "common", "rare", "epic", "legendary" }

function Names.aura(id: string): string -- "pack1_common" → aura.name.pack1_common
	return Locale.t("aura.name." .. id)
end

function Names.pet(id: string): string -- "egg1_common" → pet.name.egg1_common
	return Locale.t("pet.name." .. id)
end

function Names.egg(eggId: number): string -- 1 → egg.name.1
	return Locale.t("egg.name." .. tostring(eggId))
end

function Names.title(id: string): string -- "novice" → title.name.novice
	return Locale.t("title.name." .. id)
end

function Names.world(worldId: number): string -- 1 → world.name.1
	return Locale.t("world.name." .. tostring(worldId))
end

-- 희귀도 단계(1 ~ 4) — 아우라 · 펫이 같은 낱말을 쓴다(K8 Common · Rare · Epic · Legendary).
function Names.rarity(tier: number): string
	local key = Names.RARITY_KEYS[math.clamp(math.floor(tier), 1, #Names.RARITY_KEYS)]
	return Locale.t("rarity." .. key)
end

-- 펫 강화 단계(1 ~ 4) — K8 Normal · Gold · Diamond · Rainbow.
function Names.petLevel(level: number): string
	return Locale.t("pet.level." .. tostring(math.floor(level)))
end

-- 업그레이드 항목(UpgradeConfig 키 — punchDamage …).
function Names.upgrade(name: string): string
	return Locale.t("upgrade.name." .. name)
end

-- 부스트(ShopConfig.BOOSTS 키 — strength · damage · luck). short = HUD 남은 시간 줄의 짧은 이름.
function Names.boost(key: string, short: boolean?): string
	return Locale.t("boost." .. key .. (if short then ".short" else ".name"))
end

-- 뽑기 3종의 결과 하나(roll = "title" · "aura" · "pet").
function Names.rollItem(roll: string, id: string): string
	if roll == "title" then
		return Names.title(id)
	elseif roll == "aura" then
		return Names.aura(id)
	end
	return Names.pet(id)
end

-- 상점 상품(ShopConfig 키). 힘 배수 계단 · 운동기구 선해금은 번호만 다른 같은 꼴이라 키 하나에 자리 표시로 쓴다.
local function productKeyAndParams(key: string): (string, { [string]: any }?)
	local def = ShopConfig.get(key)
	if def ~= nil and def.effect.type == "strengthTier" then
		return "shop.strengthTier", { mult = def.effect.mult }
	elseif def ~= nil and def.effect.type == "gymUnlock" then
		return "shop.gymUnlock", { n = def.effect.gymIndex }
	end
	return "shop." .. key, nil
end

function Names.product(key: string): string
	local base, params = productKeyAndParams(key)
	return Locale.t(base .. ".name", params)
end

function Names.productDesc(key: string): string
	local base, params = productKeyAndParams(key)
	return Locale.t(base .. ".desc", params)
end

-- 검사용: 상품 하나가 쓰는 Strings 키(이름 · 설명). LocaleTests가 ShopConfig 전부를 돌며 키가 있는지 본다.
function Names.productKeys(key: string): { string }
	local base = productKeyAndParams(key)
	return { base .. ".name", base .. ".desc" }
end

return Names

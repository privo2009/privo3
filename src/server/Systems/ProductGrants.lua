--!strict
-- 개발자 상품 16개의 지급 함수 (Phase 8 지시서 #17 4단계 — DESIGN.md 9장 "구매 규칙 · 지급 · 사용").
--
-- ProductService가 영수증 순서(S3 · 절대 규칙 6)를 지키고, 이 파일은 "메모리에 무엇을 더하는가"만 정한다.
-- 같은 영수증이 다시 오면 ProductService가 PurchaseId 기록으로 걸러 PurchaseGranted만 돌려준다 — 여기까지 오지 않는다.
--
--   포션 3종        potions[종류] += effect.count(1). 사면 바로 켜지지 않는다(켜기는 PotionRequestService)
--   포션 번들       potions[종류] += effect.counts[종류](각 99)
--   럭키 · 슈퍼 롤   rollCredits[credit] += effect.rolls(5 · 15)
--   운동기구 선해금  gymUnlocks[tostring(번호)] = true. 이미 열려 있어도 true(프롬프트 전 already_unlocked로 막지만,
--                   프롬프트와 영수증 사이에 환생으로 열릴 수 있다 — 결제는 이미 됐으므로 기록하고 지급으로 친다)
--
-- 지급 함수는 yield하지 않는다(메모리만). 저장은 ProductService가 한다. 표가 없으면 false → NotProcessedYet(영수증이 다시 온다).
-- 지급하면 notify(player)로 PlayerState에 알린다 — 다음 틱에 보관 수 · 남은 횟수가 화면에 간다.
--
-- ⚠️ 제한 유저(PolicyGate)도 행운 상품 지급은 받는다(이미 결제됐다). 사용 · 효과는 제한이 막는다(S13 — 롤 쓰기 · 행운 포션 켜기).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)

local ProductGrants = {}

local function addCount(t: any, key: string, n: number): boolean
	if type(t) ~= "table" or type(n) ~= "number" or n <= 0 or n % 1 ~= 0 then
		return false
	end
	local v = t[key]
	if v == nil then
		v = 0
	end
	if type(v) ~= "number" or v ~= v or v < 0 then
		return false
	end
	t[key] = v + n
	return true
end

-- 메모리에 지급(순수 — data만 바꾼다). 지급했으면 true.
function ProductGrants.apply(data: any, def: ShopConfig.ProductDef): boolean
	if type(data) ~= "table" then
		return false
	end
	local e = def.effect
	if e.type == "potion" then
		return ShopConfig.BOOSTS[e.boost] ~= nil and addCount(data.potions, e.boost, e.count)
	elseif e.type == "potionBundle" then
		if type(data.potions) ~= "table" then
			return false
		end
		-- 먼저 전부 검사하고 더한다 — 하나만 들어가고 실패하는 반쪽 지급을 만들지 않는다
		for boostKey, n in pairs(e.counts) do
			local v = data.potions[boostKey] or 0
			if ShopConfig.BOOSTS[boostKey] == nil or type(n) ~= "number" or n <= 0 or type(v) ~= "number" or v < 0 then
				return false
			end
		end
		for boostKey, n in pairs(e.counts) do
			data.potions[boostKey] = (data.potions[boostKey] or 0) + n
		end
		return true
	elseif e.type == "rollCredit" then
		return (e.credit == "lucky" or e.credit == "super") and addCount(data.rollCredits, e.credit, e.rolls)
	elseif e.type == "gymUnlock" then
		local index = e.gymIndex
		if type(data.gymUnlocks) ~= "table" or type(index) ~= "number" or index < 1 or index > GymConfig.getCount() then
			return false
		end
		data.gymUnlocks[tostring(index)] = true
		return true
	end
	return false
end

export type Deps = {
	register: (key: string, grant: (Player?, any, ShopConfig.ProductDef) -> boolean) -> (),
	notify: (Player) -> (),
}

-- 개발자 상품 전부를 등록한다. 등록한 키 목록(이름순)을 돌려준다.
function ProductGrants.registerAll(deps: Deps): { string }
	local keys: { string } = {}
	for key, def in pairs(ShopConfig.Products) do
		if def.kind == "product" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		deps.register(key, function(player: Player?, data: any, def: ShopConfig.ProductDef): boolean
			local ok = ProductGrants.apply(data, def)
			if ok and player ~= nil then
				deps.notify(player)
			end
			return ok
		end)
	end
	return keys
end

return ProductGrants

--!strict
-- 프로필 데이터 스키마. 순수 데이터 정의 + 검증만 담당한다.
-- 다른 모듈을 require하지 않는다 (BigNum 포함) — 이 모듈은 Migrations/테스트 양쪽에서
-- 쓰이는 최하단 레이어라, 뭔가를 require하기 시작하면 순환 의존이 생기기 쉽다.
-- DESIGN.md 10. 데이터 스키마 기준이며, 아래 4가지는 의도적으로 수정했다 (사유는 각 위치에 주석).

local Schema = {}

Schema.VERSION = 2 -- v2: upgrades.radius 필드 제거 (데미지 오버플로우 도입, DESIGN.md 2장/7장)

-- 구조적 상한값. DESIGN.md 5/6/9장 수치와 같지만 Schema는 Config를 몰라야 하므로 별도로 둔다.
-- TODO: Phase 8 전후로 ShopConfig/PetConfig/AuraConfig와 단일 출처로 합칠 것 (지금은 중복 관리).
Schema.LIMITS = {
	MAX_DRONES = 5,
	MAX_PET_SLOTS = 6, -- 기본 2 + 업그레이드 최대 +1 + 게임패스 +3
	MAX_AURA_PACKS = 5,
}

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- {m, e} 형태 검증. inf/nan이 여기서 걸러지지 않으면 프로필이 영구 손상되므로 반드시 막는다.
function Schema.isBigNum(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	if not isFiniteNumber(v.m) or not isFiniteNumber(v.e) then
		return false
	end
	if v.e % 1 ~= 0 then
		return false
	end
	if v.m == 0 then
		return v.e == 0
	end
	local absM = math.abs(v.m)
	return absM >= 1 and absM < 10
end

local function newBigNum(m: number, e: number)
	return { m = m, e = e }
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function buildTemplate()
	return {
		schemaVersion = Schema.VERSION,

		-- BigNum: {m = 가수, e = 지수}
		strength = newBigNum(1, 0),
		blox = newBigNum(0, 0),
		lifetimeBlox = newBigNum(0, 0), -- 환생 진척도
		rebirths = newBigNum(0, 0), -- = 힘 배수

		progress = {
			maxStage = 1, -- 환생 시 초기화. 워프 + 드론 기준
			currentWorld = 1,
			unlockedWorlds = 1,
		},

		upgrades = {
			punchDamage = 0,
			punchSpeed = 0, -- 상한
			moveSpeed = 0, -- 상한
			bloxGain = 0,
			auraLuck = 0,
			titleLuck = 0,
			petLuck = 0, -- 상한
			petSlots = 0, -- 최대 +1
		},

		drones = {
			count = 1,
			-- [수정 3] 템플릿 단계에서는 서버 시각을 알 수 없어 0으로만 둔다.
			-- 실제 초기화(os.time())는 신규 프로필 생성 시 ProfileManager가 담당한다.
			lastCollectAt = 0,
		},

		cosmetics = {
			-- [수정 1] nil 대신 false. DataStore는 nil 값을 가진 필드를 저장하지 못하고
			-- (키 자체가 사라짐), ProfileStore의 Reconcile도 템플릿 값이 nil이면 채워 넣지
			-- 못한다. "장착 없음"을 표현하려면 false처럼 저장 가능한 값이어야 한다.
			equippedAura = false,
			ownedAuras = {}, -- {auraId = true}
			equippedTitle = false,
			ownedTitles = {},
			hideOtherAuras = false,
			hideOtherPets = false,
		},

		pets = {
			owned = {}, -- {[uid] = {petId, tier}} — uid는 반드시 문자열
			equipped = {}, -- uid 문자열 배열
			slots = 2,
			storage = 50,
			-- [수정 2] 다음 발급할 uid 번호. 실제 uid는 tostring(nextUid)로 발급해서
			-- 항상 문자열 키만 쓴다. 숫자 키를 그대로 쓰면 DataStore는 JSON을 거치며
			-- 테이블 키를 문자열로 바꿔버려서, pets.equipped가 들고 있던 숫자 참조와
			-- pets.owned의 (문자열로 바뀐) 키가 서로 어긋나게 된다.
			nextUid = 1,
		},

		rolling = {
			unlockedAuraPacks = 1,
			selectedPack = 1,
			autoRollTitle = false,
		},

		boosts = {}, -- {type, mult, expiresAt} 서버에서만 만료 판정

		daily = {
			streak = 0,
			lastClaimDay = 0, -- UTC 일 단위 정수
			freePotionDay = 0,
		},

		stats = {
			totalRuns = 0,
			totalCashouts = 0,
			bestRunDepth = 0,
			offlineClaims = 0,
			playtimeSec = 0,
			-- [수정 3] drones.lastCollectAt과 동일한 이유로 0. ProfileManager가 os.time()으로 채운다.
			firstJoin = 0,
		},
	}
end

-- 모듈 로드 시 한 번만 생성되는 단일 원본. ProfileStore.New(storeName, Schema.getTemplate())에
-- 그대로 넘기기 위한 것이므로, 호출부에서 반환값을 직접 수정하면 안 된다.
-- 수정이 필요하면 반드시 Schema.new()로 깊은 복사본을 받아서 쓸 것.
local Template = buildTemplate()

function Schema.getTemplate()
	return Template
end

-- 테스트/마이그레이션처럼 자유롭게 수정해도 되는 독립 사본이 필요할 때 사용한다.
function Schema.new()
	return deepCopy(Template)
end

local function addError(errors: { string }, message: string)
	table.insert(errors, message)
end

function Schema.validate(data: any): (boolean, { string })
	local errors: { string } = {}

	if type(data) ~= "table" then
		return false, { "data는 table이어야 함" }
	end

	-- schemaVersion ----------------------------------------------------------

	if data.schemaVersion ~= Schema.VERSION then
		addError(errors, string.format("schemaVersion 불일치 (기대=%d, 실제=%s)", Schema.VERSION, tostring(data.schemaVersion)))
	end

	-- BigNum 필드 4개 -----------------------------------------------------------

	for _, field in ipairs({ "strength", "blox", "lifetimeBlox", "rebirths" }) do
		if not Schema.isBigNum(data[field]) then
			addError(errors, field .. "이 올바른 BigNum({m,e}) 형태가 아님")
		end
	end

	-- progress -------------------------------------------------------------------

	if type(data.progress) == "table" then
		local progress = data.progress
		if type(progress.maxStage) ~= "number" or progress.maxStage < 1 then
			addError(errors, "progress.maxStage는 1 이상이어야 함")
		end
		if type(progress.currentWorld) ~= "number" or type(progress.unlockedWorlds) ~= "number" then
			addError(errors, "progress.currentWorld/unlockedWorlds가 number가 아님")
		elseif progress.unlockedWorlds < progress.currentWorld then
			addError(errors, "progress.unlockedWorlds는 currentWorld 이상이어야 함")
		end
	else
		addError(errors, "progress 테이블이 없음")
	end

	-- upgrades ---------------------------------------------------------------------

	if type(data.upgrades) == "table" then
		for name, value in pairs(data.upgrades) do
			if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
				addError(errors, string.format("upgrades.%s는 0 이상의 정수여야 함", tostring(name)))
			end
		end
	else
		addError(errors, "upgrades 테이블이 없음")
	end

	-- drones ----------------------------------------------------------------------

	if type(data.drones) == "table" then
		local count = data.drones.count
		if type(count) ~= "number" or count % 1 ~= 0 or count < 1 or count > Schema.LIMITS.MAX_DRONES then
			addError(errors, string.format("drones.count는 1~%d 사이의 정수여야 함", Schema.LIMITS.MAX_DRONES))
		end
	else
		addError(errors, "drones 테이블이 없음")
	end

	-- pets --------------------------------------------------------------------------

	if type(data.pets) == "table" then
		local pets = data.pets
		local ownedCount = 0

		if type(pets.owned) == "table" then
			for uid in pairs(pets.owned) do
				ownedCount = ownedCount + 1
				if type(uid) ~= "string" then
					addError(errors, string.format("pets.owned에 문자열이 아닌 키 발견: %s", tostring(uid)))
				end
			end
		else
			addError(errors, "pets.owned 테이블이 없음")
		end

		if type(pets.equipped) == "table" then
			for _, uid in ipairs(pets.equipped) do
				if type(pets.owned) ~= "table" or pets.owned[uid] == nil then
					addError(errors, string.format("pets.equipped의 uid(%s)가 pets.owned에 없음", tostring(uid)))
				end
			end

			if type(pets.slots) ~= "number" then
				addError(errors, "pets.slots가 number가 아님")
			elseif #pets.equipped > pets.slots then
				addError(errors, string.format("pets.equipped 개수(%d)가 slots(%d)를 초과함", #pets.equipped, pets.slots))
			end
		else
			addError(errors, "pets.equipped 테이블이 없음")
		end

		if type(pets.slots) == "number" and pets.slots > Schema.LIMITS.MAX_PET_SLOTS then
			addError(errors, string.format("pets.slots(%d)가 구조적 상한(%d)을 초과함", pets.slots, Schema.LIMITS.MAX_PET_SLOTS))
		end

		if type(pets.storage) ~= "number" then
			addError(errors, "pets.storage가 number가 아님")
		elseif ownedCount > pets.storage then
			addError(errors, string.format("pets.owned 개수(%d)가 storage(%d)를 초과함", ownedCount, pets.storage))
		end
	else
		addError(errors, "pets 테이블이 없음")
	end

	-- cosmetics ----------------------------------------------------------------------

	if type(data.cosmetics) == "table" then
		local cosmetics = data.cosmetics

		local function checkEquipped(equippedField: string, ownedField: string)
			local equipped = cosmetics[equippedField]
			if equipped == false then
				return
			end
			local owned = cosmetics[ownedField]
			if type(equipped) ~= "string" or type(owned) ~= "table" or not owned[equipped] then
				addError(errors, string.format("cosmetics.%s가 false도 아니고 %s에도 없음", equippedField, ownedField))
			end
		end

		checkEquipped("equippedAura", "ownedAuras")
		checkEquipped("equippedTitle", "ownedTitles")
	else
		addError(errors, "cosmetics 테이블이 없음")
	end

	-- rolling ---------------------------------------------------------------------------

	if type(data.rolling) == "table" then
		local rolling = data.rolling
		if type(rolling.unlockedAuraPacks) ~= "number" or rolling.unlockedAuraPacks < 1 or rolling.unlockedAuraPacks > Schema.LIMITS.MAX_AURA_PACKS then
			addError(errors, string.format("rolling.unlockedAuraPacks는 1~%d 사이여야 함", Schema.LIMITS.MAX_AURA_PACKS))
		end

		if type(rolling.selectedPack) ~= "number" or type(rolling.unlockedAuraPacks) ~= "number" then
			addError(errors, "rolling.selectedPack/unlockedAuraPacks가 number가 아님")
		elseif rolling.selectedPack > rolling.unlockedAuraPacks then
			addError(errors, "rolling.selectedPack이 unlockedAuraPacks를 초과함")
		end
	else
		addError(errors, "rolling 테이블이 없음")
	end

	-- boosts -----------------------------------------------------------------------------

	if type(data.boosts) == "table" then
		for i, boost in ipairs(data.boosts) do
			if type(boost) ~= "table" or type(boost.type) ~= "string" or type(boost.mult) ~= "number" or type(boost.expiresAt) ~= "number" then
				addError(errors, string.format("boosts[%d]가 {type,mult,expiresAt} 형태가 아님", i))
			end
		end
	else
		addError(errors, "boosts 테이블이 없음")
	end

	return #errors == 0, errors
end

return Schema

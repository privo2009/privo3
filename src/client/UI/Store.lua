--!strict
-- 서버 플레이어 상태의 클라 쪽 사본. 화면 코드가 구독해서 값 변화에 반응한다.
--
-- 초기값은 더미다. Phase 6(지시서 #5)부터 `Net/PlayerStateClient`가 서버 PlayerState 채널을
-- setSource()로 붙인다 — 첫 스냅샷이 오면 더미는 전부 덮인다(로딩 화면이 그때까지 가린다).
-- 화면 코드는 소스가 더미인지 실데이터인지 구분하지 못해야 한다 — setSource()로 소스만
-- 갈아끼우면 화면은 손대지 않아도 그대로 돈다.
-- AssetRegistry가 미도착 에셋을 다루는 방식과 같은 패턴: "아직 실물이 없다"를
-- 소비자가 알 필요가 없게 만드는 단일 교체점.
--
-- 모든 게임 수치는 BigNum이다 (CLAUDE.md 절대 규칙 1). walkSpeed/maxWalkSpeed/
-- maxStage는 원래 작은 정수라 number로 둔다.
--
-- ⚠️ "level" 필드는 없다 (U3-6에서 제거). 레벨은 strength의 지수에서 파생되는
-- 값이지 독립된 상태가 아니다 — `Shared/Config/LevelConfig.getLevel(strength)`가
-- 유일한 계산처다. 예전에 여기 있던 "level" 필드는 화면(PowerBlock)이 읽지
-- 않게 되면서 죽은 필드가 됐다: 그대로 뒀다면 이 필드와 strength가 서로 다른
-- 시점에 갱신될 때(batch 경계 등) 화면에 잠깐 어긋난 레벨이 뜰 위험이 있었다.
-- 레벨이 필요한 화면은 항상 strength를 구독하고 LevelConfig로 직접 계산할 것.
--
-- ===== U3-9a: 팩토리 + 기본 인스턴스 =======================================================
--
-- 실물 코드(HudBoot·HUD 6종)는 여전히 이 파일 맨 아래의 기본 인스턴스 하나만 쓰고,
-- Store.get(...)/subscribe(...)/unsubscribe(...)/setSource(...) 호출 형태도 바뀌지 않는다.
-- 구독 API 시그니처는 그대로다.
--
-- 바뀐 것은 테스트가 더 이상 그 기본 인스턴스를 공유하지 않아도 된다는 것뿐이다.
-- StoreTests가 setSource로 walkSpeed를 1000으로 바꾸는 동안, 같은 싱글톤을 밟는
-- PowerBlockTests와 실물 HUD 6종이 그 값을 같이 맞았다(→ ScreenController.lua의
-- U3-4 주석과 같은 부류의 사고). 이름 접두어로 가리는 대신 상태 자체를 분리한다 —
-- Store.new()로 만든 인스턴스는 자기만의 state·subscribers를 갖고, 기본 인스턴스와는
-- 어떤 상태도 공유하지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

type BigNumber = BigNum.BigNumber

local Store = {}

-- 키 집합은 서버 PlayerStateView(Shared/GameTypes)와 같다 — PlayerStateClient가 payload의 키를
-- 그대로 setter에 넣는다.
export type State = {
	strength: BigNumber,
	blox: BigNumber,
	lifetimeBlox: BigNumber,
	lifeBlox: BigNumber,
	rebirths: BigNumber,
	walkSpeed: number,
	maxWalkSpeed: number,
	maxStage: number,
	padIndex: number,
	upgrades: { [string]: number }, -- 업그레이드 레벨 (지시서 #7). 키 = UpgradeConfig 이름 8개
	titles: TitleSummary, -- 칭호 요약 (지시서 #10). 서버 TitleService.summarize
	auras: AuraSummary, -- 아우라 요약 (지시서 #11). 서버 AuraService.summarize
	pets: PetSummary, -- 펫 요약 (지시서 #12). 서버 PetService.summarize
	shop: ShopSummary, -- 상점 요약 (지시서 #16). 서버 세션 값 — 보유 게임패스 · 행운 상품 제한 · 활성 부스트 · 자동 클리커
	-- 자동 진행 요약 (지시서 #18). 서버 세션 값 — 켜짐 · 목표층 · 안전층 · 반복 횟수 · 목표층 상한
	autoAdvance: { active: boolean, target: number, safeFloor: number, runs: number, maxTarget: number },
}

-- boosts[i].receivedAt = 클라가 그 값을 받은 os.clock(남은 시간을 받은 뒤로 센다 — PlayerStateClient가 채운다)
export type BoostEntry = { type: string, mult: number, remainingSec: number, receivedAt: number }
-- potions · rollCredits · gymUnlocks = 보관 포션 수 · 남은 럭키 · 슈퍼 롤 · 선해금 기구 번호(오름차순) — 지시서 #17
export type Inventory = { potions: { strength: number, damage: number, luck: number }, rollCredits: { lucky: number, super: number }, gymUnlocks: { number } }
export type ShopSummary = { gamepasses: { string }, paidRandomRestricted: boolean, boosts: { BoostEntry }, autoClick: boolean,
	potions: { strength: number, damage: number, luck: number }, rollCredits: { lucky: number, super: number }, gymUnlocks: { number } }

export type PetEntry = { uid: string, petId: string, level: number }
export type PetSummary = { owned: { PetEntry }, equipped: { string }, slots: number, storage: number, hideOtherPets: boolean, world: number }

export type AuraSummary = { owned: { string }, equipped: string, selectedPack: number, hideOtherAuras: boolean, world: number }

export type TitleSummary = { owned: { string }, equipped: string, autoRoll: boolean }

export type Key =
	"strength"
	| "blox"
	| "lifetimeBlox"
	| "lifeBlox"
	| "rebirths"
	| "walkSpeed"
	| "maxWalkSpeed"
	| "maxStage"
	| "padIndex"
	| "upgrades"
	| "titles"
	| "auras"
	| "pets"
	| "shop"
	| "autoAdvance"

export type Setter = (Key, any) -> ()
export type Source = (Setter) -> ()

export type Handle = { key: Key }

export type StoreInstance = {
	get: (Key) -> any,
	subscribe: (Key, (any) -> ()) -> Handle,
	unsubscribe: (Handle) -> (),
	setSource: (Source) -> (),
}

-- F5로 자릿수 문제가 바로 보이도록 규격 근처의 큰 값을 더미로 넣는다.
-- strength/blox: displayM이 999에 가깝고 tier가 2글자 접미사(Qi/Sx)에 걸리도록
-- e를 잡아 "999.00Qi"류의 8자 근처 표기가 나오게 했다 (Formatter.format 기준).
-- walkSpeed/maxWalkSpeed: 4자리가 꽉 차는 값(U3-5, ValuePanel.MAX_CHARS_SPEED=4가
-- 실측 실제 값인 2자리(docs 예시 "56/최대 80")에 맞춰 칸을 좁히지 않았는지 G4에서
-- 눈으로 볼 수 있게 한다 — docs/UI.md "이동 속도 조절은 편의 기능이 아니다").
local DUMMY_STATE: State = {
	strength = BigNum.new(9.99, 20), -- "999.00Qi" 근처
	blox = BigNum.new(9.99, 23), -- "999.00Sx" 근처
	lifetimeBlox = BigNum.new(5, 25),
	lifeBlox = BigNum.new(5, 24),
	rebirths = BigNum.fromNumber(37),
	walkSpeed = 5678,
	maxWalkSpeed = 9999,
	maxStage = 17,
	padIndex = 24,
	upgrades = {}, -- freshState가 UpgradeConfig 이름마다 0을 채운다(이름을 여기 다시 적지 않는다)
	titles = { owned = {}, equipped = "", autoRoll = false }, -- 첫 PlayerState 전 — 아무 칭호 없음
	auras = { owned = {}, equipped = "", selectedPack = 1, hideOtherAuras = false, world = 1 }, -- 첫 PlayerState 전
	pets = { owned = {}, equipped = {}, slots = 2, storage = 50, hideOtherPets = false, world = 1 }, -- 첫 PlayerState 전(값은 곧 서버 것으로 바뀐다)
	-- 첫 PlayerState 전: 보유 없음 · 제한(행운 상품을 숨긴 채 시작한다 — 서버 확인 전과 같다) · 부스트 없음 · 자동 꺼짐
	shop = { gamepasses = {}, paidRandomRestricted = true, boosts = {}, autoClick = false,
		potions = { strength = 0, damage = 0, luck = 0 }, rollCredits = { lucky = 0, super = 0 }, gymUnlocks = {} },
	autoAdvance = { active = false, target = 0, safeFloor = 0, runs = 0, maxTarget = 25 }, -- 첫 PlayerState 전(지시서 #18)
}

local BIG_NUM_KEYS: { [Key]: boolean } = {
	strength = true,
	blox = true,
	lifetimeBlox = true,
	lifeBlox = true,
	rebirths = true,
}

-- 표 값(업그레이드 레벨)은 얕은 복사로 뜬다 — get으로 받은 표를 고쳐도 내부 상태가 안 바뀐다.
local TABLE_KEYS: { [Key]: boolean } = {
	upgrades = true,
	autoAdvance = true, -- 숫자 · boolean만 든 얕은 표(지시서 #18)
}

-- 칭호 요약은 owned 배열까지 깊게 뜬다(얕은 복사면 get으로 받은 배열을 고쳐 내부 상태가 바뀐다).
local function cloneTitles(v: any): TitleSummary
	local owned: { string } = {}
	if type(v) == "table" and type(v.owned) == "table" then
		for i, id in ipairs(v.owned) do
			owned[i] = id
		end
	end
	return {
		owned = owned,
		equipped = if type(v) == "table" and type(v.equipped) == "string" then v.equipped else "",
		autoRoll = type(v) == "table" and v.autoRoll == true,
	}
end

local function titlesEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.equipped ~= b.equipped or a.autoRoll ~= b.autoRoll or #a.owned ~= #b.owned then
		return false
	end
	for i, id in ipairs(a.owned) do
		if b.owned[i] ~= id then
			return false
		end
	end
	return true
end

-- 아우라 요약 깊은 복사 · 비교(칭호와 같은 이유).
local function cloneAuras(v: any): AuraSummary
	local owned: { string } = {}
	if type(v) == "table" and type(v.owned) == "table" then
		for i, id in ipairs(v.owned) do
			owned[i] = id
		end
	end
	local t = if type(v) == "table" then v else {}
	return {
		owned = owned,
		equipped = if type(t.equipped) == "string" then t.equipped else "",
		selectedPack = if type(t.selectedPack) == "number" then t.selectedPack else 1,
		hideOtherAuras = t.hideOtherAuras == true,
		world = if type(t.world) == "number" then t.world else 1,
	}
end

local function aurasEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.equipped ~= b.equipped or a.selectedPack ~= b.selectedPack or a.hideOtherAuras ~= b.hideOtherAuras or a.world ~= b.world
		or #a.owned ~= #b.owned then
		return false
	end
	for i, id in ipairs(a.owned) do
		if b.owned[i] ~= id then
			return false
		end
	end
	return true
end

-- 펫 요약 깊은 복사 · 비교(칭호와 같은 이유 — 보유 항목 표까지 뜬다).
local function clonePets(v: any): PetSummary
	local t = if type(v) == "table" then v else {}
	local owned: { PetEntry } = {}
	if type(t.owned) == "table" then
		for i, e in ipairs(t.owned) do
			if type(e) == "table" then
				owned[i] = { uid = tostring(e.uid), petId = tostring(e.petId), level = if type(e.level) == "number" then e.level else 1 }
			end
		end
	end
	local equipped: { string } = {}
	if type(t.equipped) == "table" then
		for i, uid in ipairs(t.equipped) do
			equipped[i] = tostring(uid)
		end
	end
	return {
		owned = owned,
		equipped = equipped,
		slots = if type(t.slots) == "number" then t.slots else 2,
		storage = if type(t.storage) == "number" then t.storage else 50,
		hideOtherPets = t.hideOtherPets == true,
		world = if type(t.world) == "number" then t.world else 1,
	}
end

local function petsEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.slots ~= b.slots or a.storage ~= b.storage or a.hideOtherPets ~= b.hideOtherPets or a.world ~= b.world
		or #a.owned ~= #b.owned or #a.equipped ~= #b.equipped then
		return false
	end
	for i, e in ipairs(a.owned) do
		local f = b.owned[i]
		if f == nil or f.uid ~= e.uid or f.petId ~= e.petId or f.level ~= e.level then
			return false
		end
	end
	for i, uid in ipairs(a.equipped) do
		if b.equipped[i] ~= uid then
			return false
		end
	end
	return true
end

-- 상점 요약 깊은 복사 · 비교(칭호와 같은 이유). 비교는 receivedAt을 보지 않는다 — 값이 같으면 받은 시각도 처음 것을 둔다.
local function cloneShop(v: any): ShopSummary
	local t = if type(v) == "table" then v else {}
	local passes: { string } = {}
	if type(t.gamepasses) == "table" then
		for i, key in ipairs(t.gamepasses) do
			passes[i] = tostring(key)
		end
	end
	local boosts: { BoostEntry } = {}
	if type(t.boosts) == "table" then
		for _, b in ipairs(t.boosts) do
			if type(b) == "table" then
				table.insert(boosts, {
					type = tostring(b.type),
					mult = if type(b.mult) == "number" then b.mult else 1,
					remainingSec = if type(b.remainingSec) == "number" then b.remainingSec else 0,
					receivedAt = if type(b.receivedAt) == "number" then b.receivedAt else 0,
				})
			end
		end
	end
	local function count(src: any, k: string): number
		local n = if type(src) == "table" then src[k] else nil
		return if type(n) == "number" and n == n and n >= 0 and n ~= math.huge then math.floor(n) else 0
	end
	local gyms: { number } = {}
	if type(t.gymUnlocks) == "table" then
		for _, n in ipairs(t.gymUnlocks) do
			if type(n) == "number" and n == n and n % 1 == 0 then
				table.insert(gyms, n)
			end
		end
	end
	return {
		gamepasses = passes,
		paidRandomRestricted = t.paidRandomRestricted ~= false,
		boosts = boosts,
		autoClick = t.autoClick == true,
		potions = { strength = count(t.potions, "strength"), damage = count(t.potions, "damage"), luck = count(t.potions, "luck") },
		rollCredits = { lucky = count(t.rollCredits, "lucky"), super = count(t.rollCredits, "super") },
		gymUnlocks = gyms,
	}
end

local function shopEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	if a.paidRandomRestricted ~= b.paidRandomRestricted or a.autoClick ~= b.autoClick or #a.gamepasses ~= #b.gamepasses
		or #a.boosts ~= #b.boosts then
		return false
	end
	for i, key in ipairs(a.gamepasses) do
		if b.gamepasses[i] ~= key then
			return false
		end
	end
	-- 보관함 · 롤 · 선해금(지시서 #17)
	local pa, pb, ra, rb = a.potions or {}, b.potions or {}, a.rollCredits or {}, b.rollCredits or {}
	if pa.strength ~= pb.strength or pa.damage ~= pb.damage or pa.luck ~= pb.luck or ra.lucky ~= rb.lucky or ra.super ~= rb.super then
		return false
	end
	local ga, gb = a.gymUnlocks or {}, b.gymUnlocks or {}
	if #ga ~= #gb then
		return false
	end
	for i, n in ipairs(ga) do
		if gb[i] ~= n then
			return false
		end
	end
	for i, x in ipairs(a.boosts) do
		local y = b.boosts[i]
		if y == nil or x.type ~= y.type or x.mult ~= y.mult or x.remainingSec ~= y.remainingSec then
			return false
		end
	end
	return true
end

local function cloneValue(key: Key, value: any): any
	if key == "shop" then
		return cloneShop(value)
	end
	if key == "titles" then
		return cloneTitles(value)
	end
	if key == "auras" then
		return cloneAuras(value)
	end
	if key == "pets" then
		return clonePets(value)
	end
	if BIG_NUM_KEYS[key] then
		local big = value :: BigNumber
		return { m = big.m, e = big.e }
	end
	if TABLE_KEYS[key] and type(value) == "table" then
		local copy = {}
		for k, v in pairs(value) do
			copy[k] = v
		end
		return copy
	end
	return value
end

local function valuesEqual(key: Key, a: any, b: any): boolean
	if key == "shop" then
		-- 들어온 값은 아직 복사 전이라 빠진 필드가 있을 수 있다(옛 payload의 보관함 — 지시서 #17). 둘 다 정규화한 뒤 비교한다
		return shopEqual(cloneShop(a), cloneShop(b))
	end
	if key == "titles" then
		return titlesEqual(a, b)
	end
	if key == "auras" then
		return aurasEqual(a, b)
	end
	if key == "pets" then
		return petsEqual(a, b)
	end
	if BIG_NUM_KEYS[key] then
		return BigNum.eq(a :: BigNumber, b :: BigNumber)
	end
	if TABLE_KEYS[key] and type(a) == "table" and type(b) == "table" then
		for k, v in pairs(a) do
			if b[k] ~= v then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	return a == b
end

-- DUMMY_STATE는 모듈 수준의 단일 원본이라 인스턴스가 그 안의 BigNum 테이블을
-- 그대로 참조하면 안 된다. cloneValue를 태워 키마다 새 테이블로 뜬다.
local function freshState(): State
	local fresh: { [string]: any } = {}
	for key: string, value: any in pairs(DUMMY_STATE :: any) do
		fresh[key] = cloneValue(key :: any, value)
	end
	local levels: { [string]: number } = {}
	for name in pairs(UpgradeConfig.Upgrades) do
		levels[name] = 0
	end
	fresh.upgrades = levels
	return fresh :: any
end

-- 인스턴스 하나를 만든다. state·subscribers 전부 이 함수 호출마다 새로 생기는
-- 지역 상태라 인스턴스끼리 아무것도 공유하지 않는다.
local function createInstance(): StoreInstance
	local state: State = freshState()
	local subscribers: { [Key]: { [Handle]: (any) -> () } } = {}

	local function get(key: Key): any
		return cloneValue(key, (state :: any)[key])
	end

	local function subscribe(key: Key, callback: (any) -> ()): Handle
		local handle: Handle = { key = key }
		local bucket = subscribers[key]
		if bucket == nil then
			bucket = {}
			subscribers[key] = bucket
		end
		bucket[handle] = callback
		return handle
	end

	local function unsubscribe(handle: Handle)
		local bucket = subscribers[handle.key]
		if bucket ~= nil then
			bucket[handle] = nil
		end
	end

	-- Source에게 넘겨주는 갱신 진입점. 값이 실제로 바뀌었을 때만 저장하고 통지한다.
	local function setValue(key: Key, value: any)
		local current = (state :: any)[key]
		if current ~= nil and valuesEqual(key, current, value) then
			return
		end

		(state :: any)[key] = cloneValue(key, value)

		local bucket = subscribers[key]
		if bucket == nil then
			return
		end
		for _, callback in pairs(bucket) do
			-- 콜백 하나가 에러를 내도 나머지 구독자가 죽지 않게 분리한다
			-- (SpeedInput의 onApplied 콜백 처리와 같은 이유).
			task.spawn(callback, cloneValue(key, value))
		end
	end

	-- 나중에 Remote로 교체할 지점. source는 setValue를 받아 원할 때 아무 때나
	-- (동기든 나중에 이벤트로든) 부를 수 있다 — 실제 Remote 연결부는 OnClientEvent
	-- 안에서 이 setter를 부르는 형태가 된다.
	local function setSource(source: Source)
		source(setValue)
	end

	return {
		get = get,
		subscribe = subscribe,
		unsubscribe = unsubscribe,
		setSource = setSource,
	}
end

-- 실물 코드(HudBoot·HUD 6종)가 쓰는 단 하나의 인스턴스.
local defaultInstance = createInstance()

-- 기존 호출 형태(Store.get(...) 등)를 그대로 유지한다 — 기본 인스턴스의 같은 이름
-- 함수를 그대로 참조만 옮긴 것이라 인자·동작이 완전히 같다. HudBoot과 화면 6종은
-- 이 파일을 고칠 필요가 없다.
Store.get = defaultInstance.get
Store.subscribe = defaultInstance.subscribe
Store.unsubscribe = defaultInstance.unsubscribe
Store.setSource = defaultInstance.setSource

-- 자기만의 state·subscribers를 가진 새 인스턴스를 만든다. 테스트 전용이다 —
-- 실물 코드는 절대 부르지 않는다(기본 인스턴스 하나만 쓴다는 설계를 유지).
-- 초기 상태는 기본 인스턴스와 똑같은 DUMMY_STATE 사본이라, 테스트가 검사하는
-- "초기값이 더미값과 같다"는 이 인스턴스에서도 그대로 참이다.
function Store.new(): StoreInstance
	return createInstance()
end

return Store

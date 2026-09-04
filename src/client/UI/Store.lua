--!strict
-- 서버 플레이어 상태의 클라 쪽 사본. 화면 코드가 구독해서 값 변화에 반응한다.
--
-- ⚠️ 이번 단계(U3-1) 소스는 더미다. 서버 Remote를 아직 연결하지 않는다.
-- 화면 코드는 소스가 더미인지 실데이터인지 구분하지 못해야 한다 — 나중에
-- setSource()로 소스만 갈아끼우면 화면은 손대지 않아도 그대로 돈다.
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

type BigNumber = BigNum.BigNumber

local Store = {}

export type State = {
	strength: BigNumber,
	blox: BigNumber,
	lifetimeBlox: BigNumber,
	rebirths: BigNumber,
	walkSpeed: number,
	maxWalkSpeed: number,
	maxStage: number,
}

export type Key =
	"strength"
	| "blox"
	| "lifetimeBlox"
	| "rebirths"
	| "walkSpeed"
	| "maxWalkSpeed"
	| "maxStage"

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
	rebirths = BigNum.fromNumber(37),
	walkSpeed = 5678,
	maxWalkSpeed = 9999,
	maxStage = 17,
}

local BIG_NUM_KEYS: { [Key]: boolean } = {
	strength = true,
	blox = true,
	lifetimeBlox = true,
	rebirths = true,
}

local function cloneValue(key: Key, value: any): any
	if BIG_NUM_KEYS[key] then
		local big = value :: BigNumber
		return { m = big.m, e = big.e }
	end
	return value
end

local function valuesEqual(key: Key, a: any, b: any): boolean
	if BIG_NUM_KEYS[key] then
		return BigNum.eq(a :: BigNumber, b :: BigNumber)
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

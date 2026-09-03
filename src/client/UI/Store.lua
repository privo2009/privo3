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

local state: State = table.clone(DUMMY_STATE) :: State

local subscribers: { [Key]: { [Handle]: (any) -> () } } = {}

function Store.get(key: Key): any
	return cloneValue(key, (state :: any)[key])
end

function Store.subscribe(key: Key, callback: (any) -> ()): Handle
	local handle: Handle = { key = key }
	local bucket = subscribers[key]
	if bucket == nil then
		bucket = {}
		subscribers[key] = bucket
	end
	bucket[handle] = callback
	return handle
end

function Store.unsubscribe(handle: Handle)
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
function Store.setSource(source: Source)
	source(setValue)
end

return Store

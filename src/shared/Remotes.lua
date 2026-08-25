--!strict
-- RemoteEvent 채널의 정의와 접근 통로. Phase 4-2-a 배선의 1단계.
-- 이 모듈은 "통로를 만들고 이름·타입을 한곳에 모으는 것"까지만 한다.
-- FireClient / OnClientEvent 같은 발신·수신 코드는 여기 넣지 않는다.
--
-- 채널을 나눈 이유:
--   BlockDamaged    서버→클라. 고빈도. 타격마다 발화 (근접 자동 공격이라 초당 여러 번)
--   RunStateChanged 서버→클라. 저빈도. 런 상태가 전이될 때만 발화 (런당 두세 번)
--   ClickInput      클라→서버. 클릭 배치 통지 (4-2-b)
--   ClickRejected   서버→클라. 상한에 걸려 버려진 클릭이 있음 (4-2-b)
-- 나중에 고빈도 쪽에 배치·스로틀링을 넣을 때 한 채널에 섞여 있으면 상태 전이까지
-- 같이 지연된다. 채널이 갈라져 있어야 그 최적화를 한쪽에만 적용할 수 있다.
--
-- ===== 클라 → 서버 방향은 성격이 다르다 (중요) =========================================
--
-- ClickInput이 이 프로젝트 최초의 클라→서버 채널이다. 서버→클라 채널과 지켜야 할 것이
-- 다르므로, 이 방향의 채널을 추가할 때는 아래를 그대로 따를 것:
--
--   1. payload는 전부 검증 대상이다 (CLAUDE.md 3). 클라가 보낸 값은 "요청"이지
--      "사실"이 아니다. 서버가 타입·범위·빈도를 모두 다시 잰다
--   2. 결과값(증가할 힘, 받을 보상 같은 것)을 payload에 담지 말 것. 서버가 자기
--      상태에서 직접 구한다. 클라는 "무슨 일이 있었다"까지만 말한다
--   3. 1회당 1발화 금지. 클라가 주기로 모아 보내고 서버가 그 주기 안의 양을 자른다
--      (CLAUDE.md 금지 사항 "자동 롤 시 롤 1회당 RemoteEvent (배치 처리할 것)"와 같은 이유)
--
-- ===== BigNum 값이 RemoteEvent를 건너는 문제 (중요) =====================================
-- 결론: 변환 지점이 필요 없다. 받은 테이블을 BigNum 함수에 그대로 넘기면 된다.
--
-- 근거: BigNum.BigNumber는 `{ m: number, e: number }` 평범한 테이블이고,
-- BigNum.lua 어디에도 setmetatable이 없다(실측 0건). 연산도 전부
-- BigNum.add(a, b) 형태의 자유 함수라 값 쪽에 메타테이블이 붙어 있을 필요가 없다.
-- 그래서 로블록스 직렬화가 메타테이블을 떨군다는 일반적인 함정에 이 타입은 걸리지 않는다.
--
-- 클라 수신부는 이렇게 쓰면 된다 (BigNum.deserialize를 태울 이유가 없다):
--     local change = payload[1]
--     Formatter.format(change.hp)          -- 바로 통과
--     BigNum.gte(change.hp, someThreshold) -- 바로 통과
--
-- 대신 로블록스 직렬화가 실제로 걸리는 제약은 따로 있고, 아래 payload는 셋 다 만족한다:
--   1. 테이블 키가 전부 문자열이거나 전부 1..n 연속 정수여야 한다
--      → BlockChange 배열은 연속 배열, 각 원소는 문자열 키뿐
--   2. 값이 nil이면 그 키가 통째로 사라진다
--      → 아래 payload 타입 어디에도 선택 필드가 없다. 나중에 `foo: number?` 같은 필드를
--        추가하면 그 순간 이 계약이 깨지므로, 추가할 거면 기본값을 채워 보낼 것
--   3. m/e에 inf나 nan이 들어가면 안 된다
--      → BigNum.normalize를 거친 값은 유한하다. 원본이 프로필/Config에서 온 값이면
--        이미 보장되어 있고, 새로 계산한 값을 싣는 경우만 주의하면 된다

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- payload 타입의 실제 정의처. 이 모듈은 별칭만 다시 export한다.
local GameTypes = require(script.Parent.GameTypes)

local Remotes = {}

-- 이름 문자열은 여기가 유일한 출처다. 서버·클라 어느 파일에도 "BlockDamaged" 같은
-- 문자열 리터럴을 다시 적지 말 것.
Remotes.FOLDER_NAME = "Remotes"
Remotes.BLOCK_DAMAGED = "BlockDamaged"
Remotes.RUN_STATE_CHANGED = "RunStateChanged"
Remotes.CLICK_INPUT = "ClickInput"
Remotes.CLICK_REJECTED = "ClickRejected"

-- ===== payload 타입 ====================================================================
--
-- 실제 정의는 Shared/GameTypes.lua 한 곳에 있고 여기서는 별칭만 만든다.
-- 발신·수신부가 "이 채널로 무엇이 건너가는가"를 채널 이름 옆에서 바로 읽게 하려는 것이다.
-- BlockService / ChallengeService도 같은 GameTypes를 참조하므로 정의는 하나뿐이다.

export type BlockChange = GameTypes.BlockChange
export type RunStateView = GameTypes.RunStateView

-- BlockDamaged: 타격 한 번으로 바뀐 블록들. 큐브 단위 정보는 들어가지 않는다.
export type BlockDamagedPayload = { BlockChange }

-- RunStateChanged: 런 상태 전이 1회.
--
-- getRunState()가 주는 RunStateView를 state에 그대로 싣고, 런의 존재 여부를 active로
-- 따로 표시한다. 이렇게 나눈 이유:
--   - 런이 끝난 전이(수령 성공 / 시간 초과 / 포기)에서 클라에 알릴 것이 있는데,
--     getRunState()는 그 시점에 nil을 반환한다. nil을 RemoteEvent로 보내면 인자 자체가
--     사라져서 수신부가 "안 온 것"과 구별하지 못한다
--   - state를 선택 필드로 만드는 방법도 안 된다. nil인 키는 직렬화에서 통째로 사라진다
--   그래서 종료 전이에서도 state는 항상 채운다 — 끝나는 순간의 스냅샷을 넣는다.
--   클라는 active == false를 보고 "이 state는 마지막 모습"으로 읽으면 된다.
--
-- reason은 어느 전이인지 나타내는 태그다("start" / "cleared" / "advance" /
-- "cashout" / "timeout" / "abandon"). 이번 단계의 검증이 Studio Play 육안 확인이라
-- 클라 print에 사유가 찍혀야 배선이 맞는지 읽을 수 있고, 나중에 HUD가 종료 연출을
-- 갈라 쓸 때도 이 값이 기준이 된다. 선택 필드를 못 만드니 항상 채운다.
-- seeds는 이번 전이로 새로 만들어진 블록 세트의 파괴 순서 시드다 (블록 i의 시드 = seeds[i]).
-- 클라가 블록 모델을 직접 만들기 때문에 필요하다 (4-2-a2). 나머지 재료는 클라가 이미 안다 —
-- 개수는 StageConfig.getBlockCount(state.stage), 좌표는 BlockLayout.computeLayout(개수),
-- maxHp는 StageConfig.getHp(state.stage)로 나온다. 시드만 서버가 진입 때 무작위로 뽑는
-- 값이라 전달이 필요하다.
--
-- 왜 채널을 따로 파지 않고 여기 실었는가: 시드는 stage 없이는 의미가 없다. 클라가 모델을
-- 세우려면 (stage → 개수 → 좌표)와 시드가 동시에 있어야 하는데, 채널이 갈리면 클라가 둘을
-- 조인하며 도착 순서를 보장해야 한다. 한 payload에 있으면 짝이 어긋날 수가 없다. 발화
-- 시점도 완전히 겹친다 — 블록 세트가 새로 생기는 순간이 곧 런 상태가 전이하는 순간이다.
-- 채널을 2개로 가른 기준은 빈도인데(위 참고) 시드는 저빈도 쪽에만 붙으므로 그 기준도 산다.
--
-- ⚠️ 새 블록 세트가 없는 전이(cleared / cashout / timeout / abandon)에서는 **빈 배열**을
--    싣는다. 선택 필드로 만들면 안 된다 — nil인 키는 직렬화에서 통째로 사라져서 수신부가
--    다른 형태를 받는다(위 제약 2번). 클라는 어차피 active이고 stage가 바뀐 전이에서만
--    이 값을 읽으므로, 나머지 전이에서 비어 있는 것이 정상이다.
--
--    직렬화 제약 3가지를 다 만족한다: 1..n 연속 정수 배열이고(1번), 항상 채워 보내며(2번),
--    원소는 Random:NextInteger가 준 정수라 inf/nan이 될 수 없다(3번).
export type RunStateChangedPayload = {
	active: boolean,
	reason: string,
	state: RunStateView,
	seeds: { number },
}

-- ClickInput: 클라가 한 배치 주기 동안 모은 클릭 (클라 → 서버).
--
-- ⚠️ count는 "이만큼 눌렀다는 주장"이지 확정된 사실이 아니다. 서버(ClickService)가
--    타입·범위를 다시 재고, 자기 슬라이딩 윈도우로 초당 상한까지 잘라낸다.
--
-- ⚠️ 여기에 "증가할 힘"을 담지 말 것. 힘은 서버가 PadService.getClickPower(player)로
--    직접 구한다. 클라가 파워를 실어 보내면 그 값이 곧 힘이 되므로 검증이 불가능해진다.
--
-- 왜 그냥 숫자가 아니라 테이블인가: 나중에 필드가 붙어도(예: 입력 종류) 발신·수신부의
--    인자 개수가 안 바뀐다. 선택 필드는 못 만드니 붙일 때 항상 채워 보내면 된다.
--
-- 왜 count를 아예 빼지 않는가: 배치가 성립하려면 "몇 번인지"가 반드시 건너와야 한다.
--    빼면 1클릭당 1발화가 되어 위 3번 금지에 정면으로 걸린다. 대신 이 값은 신뢰되지
--    않는다 — 상한 판정은 전적으로 서버 윈도우가 한다. 클라가 count=9999를 보내도
--    통과하는 건 그 순간 윈도우에 남은 자리(최대 10)뿐이다.
export type ClickInputPayload = {
	count: number,
}

-- ClickRejected: 상한에 걸려 버려진 클릭이 있었다 (서버 → 클라).
--
-- Phase 6에서 "최대 속도! 자동 클리커로 더 빠르게" 안내가 뜨는 자리다. 지금은 채널과
-- payload 형태만 확정하고 클라는 print만 한다 — 나중에 payload를 다시 뜯지 않기 위함이다.
--   limitPerSec  서버가 적용 중인 초당 상한. 안내 문구에 숫자를 박지 않으려면 필요하다
--   dropped      직전 통지 이후 버려진 클릭 수. 얼마나 심하게 막혔는지를 나타낸다
-- 둘 다 항상 채운다 (선택 필드 금지 — nil인 키는 직렬화에서 사라진다).
--
-- ⚠️ 이 통지 자체도 빈도 제한을 받는다. 상한에 걸린 유저는 계속 걸려 있으므로 매번
--    보내면 통지가 곧 부하가 된다. 억제 주기는 ClickService에 있다.
export type ClickRejectedPayload = {
	limitPerSec: number,
	dropped: number,
}

export type Channels = {
	blockDamaged: RemoteEvent,
	runStateChanged: RemoteEvent,
	clickInput: RemoteEvent,
	clickRejected: RemoteEvent,
}

-- ===== 인스턴스 확보 ====================================================================
--
-- 인스턴스는 ReplicatedStorage.Remotes 아래에 서버가 런타임에 만든다.
-- default.project.json에 $className: RemoteEvent로 선언해 Rojo가 미리 만들게 할 수도 있지만
-- 그러면 이름 문자열이 project.json과 이 파일 두 곳에 생긴다. 이름의 출처를 한 곳으로
-- 유지하는 쪽을 택했고, 그래서 default.project.json은 건드리지 않았다.
-- (모듈 자체는 src/shared → ReplicatedStorage.Shared.Remotes에 실린다. 코드와 인스턴스가
--  다른 위치인 건 의도된 것이다 — Shared는 코드 폴더다)

local function ensureFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME)
	if existing ~= nil then
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureEvent(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		return existing :: RemoteEvent
	end

	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end

local cached: Channels? = nil

-- 서버 전용. 없으면 만들고, 있으면 그것을 쓴다. 여러 서버 스크립트가 각자 호출해도
-- 중복 생성되지 않는다 (찾기 → 없을 때만 생성이 이 함수 안에 갇혀 있다).
function Remotes.getServer(): Channels
	assert(RunService:IsServer(), "Remotes.getServer: 서버 전용이다. 클라는 getClient()를 쓴다")

	if cached ~= nil then
		return cached
	end

	local folder = ensureFolder()
	local channels: Channels = {
		blockDamaged = ensureEvent(folder, Remotes.BLOCK_DAMAGED),
		runStateChanged = ensureEvent(folder, Remotes.RUN_STATE_CHANGED),
		clickInput = ensureEvent(folder, Remotes.CLICK_INPUT),
		clickRejected = ensureEvent(folder, Remotes.CLICK_REJECTED),
	}
	cached = channels
	return channels
end

-- 클라가 서버보다 먼저 도달할 수 있으므로 무한 대기가 기본이다. 다만 서버가 getServer()를
-- 아예 호출하지 않는 배선 실수면 조용히 영원히 멈춘 것처럼 보이므로, 일정 시간이 지나면
-- 한 번 경고하고 계속 기다린다.
local WAIT_WARN_SEC = 10

local function waitFor(parent: Instance, name: string): Instance
	local found = parent:WaitForChild(name, WAIT_WARN_SEC)
	if found ~= nil then
		return found
	end

	warn(string.format(
		"[Remotes] %s를 %d초째 기다리는 중이다. 서버가 Remotes.getServer()를 호출했는지 확인할 것.",
		name,
		WAIT_WARN_SEC
	))
	return parent:WaitForChild(name)
end

-- 클라 전용. 인스턴스를 만들지 않는다 — 만드는 쪽은 서버 하나뿐이어야 한다.
function Remotes.getClient(): Channels
	assert(RunService:IsClient(), "Remotes.getClient: 클라 전용이다. 서버는 getServer()를 쓴다")

	if cached ~= nil then
		return cached
	end

	local folder = waitFor(ReplicatedStorage, Remotes.FOLDER_NAME)
	local channels: Channels = {
		blockDamaged = waitFor(folder, Remotes.BLOCK_DAMAGED) :: RemoteEvent,
		runStateChanged = waitFor(folder, Remotes.RUN_STATE_CHANGED) :: RemoteEvent,
		clickInput = waitFor(folder, Remotes.CLICK_INPUT) :: RemoteEvent,
		clickRejected = waitFor(folder, Remotes.CLICK_REJECTED) :: RemoteEvent,
	}
	cached = channels
	return channels
end

return Remotes

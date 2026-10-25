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
--   SpeedRequest    클라→서버. 커스텀 스피드 요청 (4-2-c)
--   SpeedApplied    서버→클라. 실제 적용된 속도 + 현재 최대치 (4-2-c)
--   PlayerState     서버→클라. 플레이어 상태 전체 스냅샷 (Phase 6). 바뀔 때만, 플레이어당 빈도 상한
--   SyncRequest     클라→서버. "지금 상태를 다시 보내 달라" (Phase 6). 접속 직후 동기화용
--   RebirthRequest  클라→서버. 환생 창의 환생 요청 (Phase 6). 서버가 다시 판정한다
--   RebirthResult   서버→클라. 그 요청의 결과(성공 / 거부 사유 코드)
--   WarpRequest     클라→서버. 월드·워프 창의 워프 요청(목표 층) (Phase 6 지시서 #6)
--   WarpResult      서버→클라. 그 요청의 결과
--   UpgradeRequest  클라→서버. 상점 창의 업그레이드 구매 요청(항목 이름) (Phase 6 지시서 #7)
--   UpgradeResult   서버→클라. 그 요청의 결과
--   TitleRequest    클라→서버. 타이틀 창의 요청(roll · equip · setAuto) (Phase 7 지시서 #10)
--   TitleResult     서버→클라. 그 요청의 결과 + 자동 롤로 새 칭호를 얻었을 때의 알림(중복은 보내지 않는다)
--   AuraRequest     클라→서버. 아우라 창의 요청(roll · equip · selectPack) (Phase 7 지시서 #11)
--   AuraResult      서버→클라. 그 요청의 결과 1건(결과 연출용). 브로드캐스트하지 않는다
--   SettingsRequest 클라→서버. 설정 창의 값 변경(허용 키 화이트리스트) (지시서 #11)
--   SettingsResult  서버→클라. 그 요청의 결과
--   PetRequest      클라→서버. 펫 창의 요청(hatch · equip · unequip · equipBest · craft · release) (Phase 7 지시서 #12)
--   PetResult       서버→클라. 그 요청의 결과 1건(결과 연출용). 브로드캐스트하지 않는다
--   PurchaseRequest 클라→서버. 로벅스 상품 구매 요청(상품 키) (Phase 8 지시서 #16). 서버가 검증한 뒤에만 프롬프트를 띄운다
--   PurchaseResult  서버→클라. 그 요청의 판정(프롬프트를 띄웠나 · 거부 사유) + 게임패스 프롬프트가 닫힌 결과
-- 나중에 고빈도 쪽에 배치·스로틀링을 넣을 때 한 채널에 섞여 있으면 상태 전이까지
-- 같이 지연된다. 채널이 갈라져 있어야 그 최적화를 한쪽에만 적용할 수 있다.
--
-- ===== 클라 → 서버 방향은 성격이 다르다 (중요) =========================================
--
-- ClickInput이 이 프로젝트 최초의 클라→서버 채널이고, SpeedRequest가 두 번째다.
-- 서버→클라 채널과 지켜야 할 것이 다르므로, 이 방향의 채널을 추가할 때는 아래를 그대로 따를 것:
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
local BigNum = require(script.Parent.BigNum)

local Remotes = {}

-- 이름 문자열은 여기가 유일한 출처다. 서버·클라 어느 파일에도 "BlockDamaged" 같은
-- 문자열 리터럴을 다시 적지 말 것.
Remotes.FOLDER_NAME = "Remotes"
Remotes.BLOCK_DAMAGED = "BlockDamaged"
Remotes.RUN_STATE_CHANGED = "RunStateChanged"
Remotes.CLICK_INPUT = "ClickInput"
Remotes.CLICK_REJECTED = "ClickRejected"
Remotes.SPEED_REQUEST = "SpeedRequest"
Remotes.SPEED_APPLIED = "SpeedApplied"
Remotes.PLAYER_STATE = "PlayerState"
Remotes.SYNC_REQUEST = "SyncRequest"
Remotes.REBIRTH_REQUEST = "RebirthRequest"
Remotes.REBIRTH_RESULT = "RebirthResult"
Remotes.WARP_REQUEST = "WarpRequest"
Remotes.WARP_RESULT = "WarpResult"
Remotes.UPGRADE_REQUEST = "UpgradeRequest"
Remotes.UPGRADE_RESULT = "UpgradeResult"
Remotes.TITLE_REQUEST = "TitleRequest"
Remotes.TITLE_RESULT = "TitleResult"
Remotes.AURA_REQUEST = "AuraRequest"
Remotes.AURA_RESULT = "AuraResult"
Remotes.SETTINGS_REQUEST = "SettingsRequest"
Remotes.SETTINGS_RESULT = "SettingsResult"
Remotes.PET_REQUEST = "PetRequest"
Remotes.PET_RESULT = "PetResult"
Remotes.PURCHASE_REQUEST = "PurchaseRequest"
Remotes.PURCHASE_RESULT = "PurchaseResult"

-- ===== payload 타입 ====================================================================
--
-- 실제 정의는 Shared/GameTypes.lua 한 곳에 있고 여기서는 별칭만 만든다.
-- 발신·수신부가 "이 채널로 무엇이 건너가는가"를 채널 이름 옆에서 바로 읽게 하려는 것이다.
-- BlockService / ChallengeService도 같은 GameTypes를 참조하므로 정의는 하나뿐이다.

export type BlockChange = GameTypes.BlockChange
export type RunStateView = GameTypes.RunStateView
export type PlayerStateView = GameTypes.PlayerStateView

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

-- SpeedRequest: 유저가 정한 이동속도 요청 (클라 → 서버).
--
-- 값의 성격은 **절대값**이다. 비율도 배수도 아니고 "이 속도로 다니고 싶다"는 studs/s다.
-- 유저는 숫자를 직접 입력한다(프리셋 없음 — 레퍼런스 방식). 그래서 최대치를 모르는 채로
-- 100을 넣는 일이 정상 경로에 포함된다.
--
-- ⚠️ 이 값은 "요청"이지 "적용된 속도"가 아니다. 규약 2번(결과값 금지)이 여기서 특히
--    중요하다 — 클라가 "이 속도로 세팅됨"을 보내는 형태로 바꾸면 그 순간 클라가 자기
--    속도를 스스로 정하게 된다. 실제 적용값은 서버가 min(요청, 최대치)로 정하고
--    SpeedApplied로 되돌려준다.
--
-- ⚠️ 서버는 이 값의 타입·nan·inf·0 이하를 전부 다시 잰다(SpeedService.sanitizeRequest).
--    클라가 자체 검증을 하더라도 그것이 서버 검증을 대체하지 않는다.
--
-- 왜 숫자 하나가 아니라 테이블인가: ClickInputPayload와 같은 이유다. 나중에 필드가 붙어도
-- 발신·수신부의 인자 개수가 안 바뀐다.
--
-- ⚠️ 저장하지 않는다. 커스텀 스피드는 세션 메모리뿐이므로 이 채널이 생겨도
--    schemaVersion을 올릴 일이 없다 (SpeedService.lua "저장하지 않는다" 절).
export type SpeedRequestPayload = {
	speed: number,
}

-- SpeedApplied: 실제로 적용된 속도와 그때의 최대치 (서버 → 클라).
--
-- 왜 필요한가: 유저가 100을 입력해도 최대치가 18이면 18이 적용된다. 이 통지가 없으면
-- 클라 UI는 100을 표시한 채로 남고, 유저는 자기가 100으로 다니는 줄 안다.
-- Phase 6 UI가 이 값을 받아 입력칸을 실제값으로 되돌린다.
--
-- ⚠️ 거부된 요청(숫자 아님 · nan · inf · 0 이하)에도 보낸다. 거부야말로 클라 표시가
--    어긋나 있는 경우이므로, 그때 아무것도 안 보내면 잘못된 값이 화면에 남는다.
--    그 경우 speed에는 **지금 실제로 적용 중인 값**이 실린다(요청값이 아니다).
--
-- maxSpeed를 함께 싣는 이유: 클라가 최대치를 스스로 계산하려면 힘과 LevelConfig가 필요한데
-- 힘은 서버 프로필에 있다. 그리고 최대치는 레벨업으로 오르므로 요청 시점마다 다르다 —
-- 클라가 캐시해 둔 값으로 안내 문구를 만들면 조용히 어긋난다.
--
-- 둘 다 항상 채운다 (선택 필드 금지 — nil인 키는 직렬화에서 통째로 사라진다).
-- 둘 다 유한한 양수다: speed는 sanitizeRequest를 통과한 값이거나 현재 적용값이고,
-- maxSpeed는 LevelConfig가 상한을 씌운 값이라 inf가 될 수 없다(직렬화 제약 3번).
export type SpeedAppliedPayload = {
	speed: number,
	maxSpeed: number,
}

-- PlayerState: 플레이어 상태 전체 스냅샷 (서버 → 클라). 부분 갱신이 아니라 매번 전체다 —
-- 필드가 9개뿐이라 작고, 수신부가 "어느 필드가 왔나"를 조립할 필요가 없다.
-- 보내는 시점·빈도 상한은 Server/Systems/PlayerStateService 상단.
-- 직렬화 제약 3가지를 다 만족한다: 문자열 키뿐이고, 선택 필드가 없으며, BigNum은 프로필 값을
-- 복사한 것이고 숫자는 유한하다(PlayerStateService.buildSnapshot이 보장).
export type PlayerStatePayload = PlayerStateView

-- SyncRequest: "지금 상태를 다시 보내 달라" (클라 → 서버).
--
-- 왜 필요한가: RunStateChanged를 듣는 클라 스크립트가 넷이다(블록 · HUD 챌린지 정보 · 발판 ·
-- 진행 벽). 리스너가 붙기 전에 서버가 보낸 이벤트는 큐에 쌓였다가 **처음 붙은 리스너 하나에만**
-- 전달된다 — 접속 직후 서버가 먼저 밀어 보내면 나머지 셋은 놓친다. 그래서 각 수신부가 리스너를
-- 붙인 뒤 이 요청을 보내고, 서버는 짧은 창 안의 요청을 하나로 모아 한 번만 답한다
-- (PlayerState 전체 + RunStateChanged reason="sync").
--
-- payload에 결과값을 담지 않는다(규약 2) — 비어 있는 테이블이다. 빈도는 서버가 자른다(규약 3).
export type SyncRequestPayload = {}

-- RebirthRequest: 환생해 달라 (클라 → 서버). payload는 비어 있다 — 규약 2(결과값 금지). 얻을 배수를
-- 클라가 실어 보내지 않는다. 서버가 RebirthService.rebirth 안에서 canRebirth로 다시 판정한다.
-- 확인 단계(두 번 누름)는 클라 화면의 일이다 — 서버는 요청 하나를 환생 하나로 본다.
-- 빈도는 서버가 자른다(규약 3, Server/Systems/RebirthRequestService).
export type RebirthRequestPayload = {}

-- RebirthResult: 환생 요청의 결과 (서버 → 클라). 바뀐 값(블럭스 · 배수 · 힘)은 PlayerState가 따로 보낸다.
--   ok      true면 환생됨
--   reason  거부 사유 코드(RebirthService.REASON_* 또는 "rate_limited"). 성공이면 ""
--   gained  얻은 배수. 거부면 0 (선택 필드 금지 — nil인 키는 직렬화에서 사라진다)
--   total   환생 뒤 rebirths 누적값. 거부면 0. 환생 안내(지시서 #8)가 "×이전 → ×이후"를 PlayerState 도착 순서와 무관하게
--           그린다 — 이전 = total − gained
export type RebirthResultPayload = {
	ok: boolean,
	reason: string,
	gained: BigNum.BigNumber,
	total: BigNum.BigNumber,
}

-- WarpRequest: 이 층으로 워프해 달라 (클라 → 서버). stage만 싣는다 — 비용을 싣지 않는다(규약 2).
-- stage는 "요청"이다. 서버가 타입 · 정수 · 범위를 다시 재고(WarpRequestService · WarpConfig.canWarp),
-- 활성 런이 없는지(W1)도 다시 본다. 빈도는 서버가 자른다(규약 3).
export type WarpRequestPayload = {
	stage: number,
}

-- WarpResult: 워프 요청의 결과 (서버 → 클라). 바뀐 블럭스는 PlayerState, 새 런은 RunStateChanged가 보낸다.
--   reason  거부 사유 코드(WarpService.REASON_* · "rate_limited"). 성공이면 ""
--   cost    차감된 비용. 거부면 0 (선택 필드 금지)
export type WarpResultPayload = {
	ok: boolean,
	reason: string,
	stage: number,
	cost: BigNum.BigNumber,
}

-- UpgradeRequest: 이 업그레이드를 한 레벨 사 달라 (클라 → 서버). 항목 이름만 싣는다 — 레벨 · 비용을 싣지 않는다(규약 2).
-- 서버가 이름(노출 항목인가) · 최대 레벨 · 잔액을 다시 재고(UpgradeService · UpgradeConfig.canBuy), 빈도도 자른다(규약 3).
export type UpgradeRequestPayload = {
	name: string,
}

-- UpgradeResult: 구매 요청의 결과 (서버 → 클라). 바뀐 블럭스 · 레벨은 PlayerState가 따로 보낸다.
--   reason  거부 사유 코드(UpgradeConfig.REASON_* · UpgradeService.REASON_* · "rate_limited"). 성공이면 ""
--   level   성공이면 산 뒤의 레벨, 거부면 0 / cost 차감된 비용, 거부면 0 (선택 필드 금지)
export type UpgradeResultPayload = {
	ok: boolean,
	reason: string,
	name: string,
	level: number,
	cost: BigNum.BigNumber,
}

-- TitleRequest: 타이틀 창 요청 (클라 → 서버). 결과 · 비용 · 확률을 싣지 않는다(규약 2) — 서버가 전부 다시 판정한다.
--   action  "roll" | "equip" | "setAuto"
--   titleId equip일 때만 의미가 있다(다른 action이면 무시)
--   on      setAuto일 때만 의미가 있다
export type TitleRequestPayload = {
	action: string,
	titleId: string?,
	on: boolean?,
}

-- TitleResult: 요청 결과 또는 자동 롤 신규 획득 알림 (서버 → 클라). 바뀐 블럭스 · 칭호 목록은 PlayerState가 따로 보낸다.
--   action  요청의 action, 자동 롤 알림이면 "autoRoll"
--   reason  거부 사유 코드(RollService.REASON_* · TitleService.REASON_* · "rate_limited"). 성공이면 ""
--   titleId 롤 결과 · 장착한 칭호. 없으면 "" / isNew 처음 얻은 칭호인가 / equipped 이 요청으로 장착이 바뀌었는가 (선택 필드 금지)
export type TitleResultPayload = {
	action: string,
	ok: boolean,
	reason: string,
	titleId: string,
	isNew: boolean,
	equipped: boolean,
}

-- AuraRequest: 아우라 창 요청 (클라 → 서버). 결과 · 비용 · 확률을 싣지 않는다(규약 2).
--   action  "roll" | "equip" | "selectPack" / pack roll · selectPack일 때 팩 번호 / auraId equip일 때
export type AuraRequestPayload = {
	action: string,
	pack: number?,
	auraId: string?,
}

-- AuraResult: 요청 결과 1건 (서버 → 클라). 바뀐 블럭스 · 보유 목록은 PlayerState가 따로 보낸다. 선택 필드 금지.
--   reason 사유 코드(성공이면 "") / auraId 결과 · 장착한 아우라(없으면 "") / packId · tier 결과의 팩 · 등급(없으면 0)
--   isNew 처음 얻은 아우라인가 / equipped 이 요청으로 장착이 바뀌었는가
export type AuraResultPayload = {
	action: string,
	ok: boolean,
	reason: string,
	auraId: string,
	packId: number,
	tier: number,
	isNew: boolean,
	equipped: boolean,
}

-- SettingsRequest: 설정 값 하나 바꾸기 (클라 → 서버). 허용 키는 서버 화이트리스트(SettingsRequestService)가 정한다.
export type SettingsRequestPayload = {
	key: string,
	value: any,
}

export type SettingsResultPayload = {
	ok: boolean,
	reason: string,
	key: string,
	value: boolean,
}

-- PetRequest: 펫 창 요청 (클라 → 서버). 결과 · 비용 · 확률을 싣지 않는다(규약 2).
--   action  "hatch" | "equip" | "unequip" | "equipBest" | "craft" | "release" / egg hatch일 때 알 번호 / uid 그 밖(equipBest 제외)
export type PetRequestPayload = {
	action: string,
	egg: number?,
	uid: string?,
}

-- PetResult: 요청 결과 1건 (서버 → 클라). 바뀐 블럭스 · 보유 목록은 PlayerState가 따로 보낸다. 선택 필드 금지.
--   reason 사유 코드(성공이면 "") / uid 결과 펫(부화 · 크래프팅) 또는 대상 펫 / petId · eggId · rarity(종 희귀도) · level(강화 단계)
--   결과 펫의 값(없으면 "" · 0) / isNew 지금 보유에 없던 종인가 / equipped 이 요청으로 결과 펫이 장착됐는가
export type PetResultPayload = {
	action: string,
	ok: boolean,
	reason: string,
	uid: string,
	petId: string,
	eggId: number,
	rarity: number,
	level: number,
	isNew: boolean,
	equipped: boolean,
	-- 부화한 펫 전부(지시서 #16 S18 — 3배 부화는 결과 1건에 3마리). 보통 부화는 1마리(앞 필드와 같은 펫), 그 밖의 action은 빈 목록
	pets: { PetResultEntry },
}

export type PetResultEntry = {
	uid: string,
	petId: string,
	rarity: number,
	level: number,
	isNew: boolean,
	equipped: boolean,
}

-- PurchaseRequest: 이 상품을 사고 싶다 (클라 → 서버). 상품 키만 싣는다 — 가격 · ID를 싣지 않는다(규약 2).
-- 서버(PurchaseRequestService)가 키 · 보유 · 제한(S13) · 등록(ID 0) · 지급 함수를 다시 재고 빈도도 자른다(규약 3).
export type PurchaseRequestPayload = {
	key: string,
}

-- PurchaseResult: 구매 요청의 결과 (서버 → 클라). 선택 필드 금지.
--   key    요청한 상품 키(형태가 틀렸으면 "") / kind "gamepass" | "product"(키가 틀렸거나 빈도 초과면 "")
--   phase  "prompt" = 요청 판정(ok면 프롬프트를 띄웠다) · "finished" = 게임패스 프롬프트가 닫혔다(ok면 샀다)
--   reason 사유 코드(PurchaseRequestService.REASON_* — rate_limited · invalid_key · already_owned · restricted ·
--          not_registered · not_available · prompt_failed · cancelled). 성공이면 ""
-- 산 게임패스의 소유는 PlayerState(shop.gamepasses)가 따로 보낸다.
export type PurchaseResultPayload = {
	key: string,
	kind: string,
	phase: string,
	ok: boolean,
	reason: string,
}

export type Channels = {
	blockDamaged: RemoteEvent,
	runStateChanged: RemoteEvent,
	clickInput: RemoteEvent,
	clickRejected: RemoteEvent,
	speedRequest: RemoteEvent,
	speedApplied: RemoteEvent,
	playerState: RemoteEvent,
	syncRequest: RemoteEvent,
	rebirthRequest: RemoteEvent,
	rebirthResult: RemoteEvent,
	warpRequest: RemoteEvent,
	warpResult: RemoteEvent,
	upgradeRequest: RemoteEvent,
	upgradeResult: RemoteEvent,
	titleRequest: RemoteEvent,
	titleResult: RemoteEvent,
	auraRequest: RemoteEvent,
	auraResult: RemoteEvent,
	settingsRequest: RemoteEvent,
	settingsResult: RemoteEvent,
	petRequest: RemoteEvent,
	petResult: RemoteEvent,
	purchaseRequest: RemoteEvent,
	purchaseResult: RemoteEvent,
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
		speedRequest = ensureEvent(folder, Remotes.SPEED_REQUEST),
		speedApplied = ensureEvent(folder, Remotes.SPEED_APPLIED),
		playerState = ensureEvent(folder, Remotes.PLAYER_STATE),
		syncRequest = ensureEvent(folder, Remotes.SYNC_REQUEST),
		rebirthRequest = ensureEvent(folder, Remotes.REBIRTH_REQUEST),
		rebirthResult = ensureEvent(folder, Remotes.REBIRTH_RESULT),
		warpRequest = ensureEvent(folder, Remotes.WARP_REQUEST),
		warpResult = ensureEvent(folder, Remotes.WARP_RESULT),
		upgradeRequest = ensureEvent(folder, Remotes.UPGRADE_REQUEST),
		upgradeResult = ensureEvent(folder, Remotes.UPGRADE_RESULT),
		titleRequest = ensureEvent(folder, Remotes.TITLE_REQUEST),
		titleResult = ensureEvent(folder, Remotes.TITLE_RESULT),
		auraRequest = ensureEvent(folder, Remotes.AURA_REQUEST),
		auraResult = ensureEvent(folder, Remotes.AURA_RESULT),
		settingsRequest = ensureEvent(folder, Remotes.SETTINGS_REQUEST),
		settingsResult = ensureEvent(folder, Remotes.SETTINGS_RESULT),
		petRequest = ensureEvent(folder, Remotes.PET_REQUEST),
		petResult = ensureEvent(folder, Remotes.PET_RESULT),
		purchaseRequest = ensureEvent(folder, Remotes.PURCHASE_REQUEST),
		purchaseResult = ensureEvent(folder, Remotes.PURCHASE_RESULT),
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
		speedRequest = waitFor(folder, Remotes.SPEED_REQUEST) :: RemoteEvent,
		speedApplied = waitFor(folder, Remotes.SPEED_APPLIED) :: RemoteEvent,
		playerState = waitFor(folder, Remotes.PLAYER_STATE) :: RemoteEvent,
		syncRequest = waitFor(folder, Remotes.SYNC_REQUEST) :: RemoteEvent,
		rebirthRequest = waitFor(folder, Remotes.REBIRTH_REQUEST) :: RemoteEvent,
		rebirthResult = waitFor(folder, Remotes.REBIRTH_RESULT) :: RemoteEvent,
		warpRequest = waitFor(folder, Remotes.WARP_REQUEST) :: RemoteEvent,
		warpResult = waitFor(folder, Remotes.WARP_RESULT) :: RemoteEvent,
		upgradeRequest = waitFor(folder, Remotes.UPGRADE_REQUEST) :: RemoteEvent,
		upgradeResult = waitFor(folder, Remotes.UPGRADE_RESULT) :: RemoteEvent,
		titleRequest = waitFor(folder, Remotes.TITLE_REQUEST) :: RemoteEvent,
		titleResult = waitFor(folder, Remotes.TITLE_RESULT) :: RemoteEvent,
		auraRequest = waitFor(folder, Remotes.AURA_REQUEST) :: RemoteEvent,
		auraResult = waitFor(folder, Remotes.AURA_RESULT) :: RemoteEvent,
		settingsRequest = waitFor(folder, Remotes.SETTINGS_REQUEST) :: RemoteEvent,
		settingsResult = waitFor(folder, Remotes.SETTINGS_RESULT) :: RemoteEvent,
		petRequest = waitFor(folder, Remotes.PET_REQUEST) :: RemoteEvent,
		petResult = waitFor(folder, Remotes.PET_RESULT) :: RemoteEvent,
		purchaseRequest = waitFor(folder, Remotes.PURCHASE_REQUEST) :: RemoteEvent,
		purchaseResult = waitFor(folder, Remotes.PURCHASE_RESULT) :: RemoteEvent,
	}
	cached = channels
	return channels
end

return Remotes

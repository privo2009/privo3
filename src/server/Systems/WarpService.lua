--!strict
-- 워프. 블럭스를 지불하고 목표 스테이지에서 런을 새로 시작한다.
-- 규칙과 근거는 DESIGN.md "3. 화폐와 배수 > 블럭스 소비처"가 원본이다 — 여기로 복사하지 말 것.
--
-- 이 파일에는 계산이 없다. 비용과 가능 여부는 전부 WarpConfig가 정하고,
-- 여기가 하는 일은 **순서를 지키는 것**과 **거부를 사유 코드로 접는 것**이다.
--
-- ===== 판정은 WarpConfig가 한다 (⚠️ 여기서 다시 하지 말 것) ===========================
--
-- 검증되지 않은 입력에 WarpConfig.cost를 직접 부르지 않는다. 반드시 canWarp을 먼저
-- 통과시키고, 그 반환값으로 받은 비용을 쓴다 (WarpConfig.lua의 cost 위 주석이 원본 계약).
-- cost는 nil·소수·0·음수에 error를 던지는데, 목표층은 결국 Phase 6 UI에서 오고
-- 클라가 보낸 값은 전부 검증 대상이다(CLAUDE.md 절대 규칙 3).
-- 사유 코드로 접혀야 할 것이 서버 에러가 되면 안 된다.
--
-- ⚠️ "블럭스가 충분한가"를 이 파일에서 다시 계산하지 말 것. CurrencyService.subtract도
-- 잔액 부족을 거부하지만 그건 **불변식**(프로필이 음수가 되지 않는다)이지 정책이 아니다.
-- 정책의 진실은 canWarp 하나다. 둘이 갈리면 어느 쪽이 맞는지 물어야 하는 코드가 된다.
--
-- ===== 왜 yield가 하나도 없어야 하는가 ================================================
--
-- 워프는 "지금 보유한 블럭스"로 판정하고 그 자리에서 차감한다. Luau는 단일 스레드라
-- yield하지 않는 한 그 사이에 다른 핸들러가 끼어들 수 없고, 그래서 canWarp이 본 잔액과
-- subtract가 빼는 잔액이 같다는 보장이 성립한다.
--
-- 한 줄이라도 yield가 끼면 그 틈에 ChallengeService.cashout이 들어와 잔액이 바뀔 수
-- 있다. 그러면 canWarp을 통과한 워프가 subtract에서 잔액 부족으로 거부된다 —
-- 아래 REASON_SUBTRACT_FAILED가 바로 그 상황이고, **정상 경로에는 존재하지 않아야 한다.**
--
-- ⚠️ runWarp 안에 task.wait · task.delay · profile:Save() · WaitForChild ·
--    DataStore 호출을 절대 넣지 말 것. 부르는 함수들도 전부 yield하지 않는 것을 확인해
--    두었다(CurrencyService 전체 / ChallengeService.startRun).
--
-- ===== 동결은 넣지 않았다 ============================================================
--
-- 워프 직후 1초 동결은 **미구현이다.** WalkSpeed를 직접 대입하면 SpeedService의 주기
-- 검사(1.5초)가 조용히 되돌리고 로그도 남기지 않는다 — 0은 최대치 이하라 "반영 지연"으로
-- 분류되기 때문이다. 동결 1초 < 주기 1.5초라 타이밍에 따라 먹히기도 하고 아니기도 해서
-- 재현되지 않는 버그가 된다. setCustomSpeed(player, 0)도 안 된다(value <= 0을 거부한다).
-- 안전하게 넣으려면 SpeedService에 폴링이 스킵할 동결 플래그가 필요하다.
-- → docs/PENDING.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
local CurrencyService = require(script.Parent.CurrencyService)
local ChallengeService = require(script.Parent.ChallengeService)

type BigNumber = BigNum.BigNumber

local WarpService = {}

-- ===== 거부 사유 코드 =================================================================
--
-- ⚠️ 코드만 둔다. 표시 문구를 여기 넣지 말 것 — 매핑은 Phase 6 UI가 한다.
--
-- 아래 셋은 **재공개**다. 정의는 WarpConfig에 있고 여기서는 이름만 다시 건다 —
-- 판정이 그 파일에 있으므로 사유 이름도 그 파일이 가져야 사유를 하나 늘릴 때
-- 두 파일이 갈라지지 않는다. 재공개를 두는 이유는 접근점을 Service로 통일하기
-- 위해서다: 정의는 한 곳(Config), 부르는 곳은 한 곳(Service).
-- ⚠️ 값을 여기에 문자열로 다시 적지 말 것. 그 순간 재공개가 아니라 복사본이 된다.
WarpService.REASON_INVALID_STAGE = WarpConfig.REASON_INVALID_STAGE
WarpService.REASON_STAGE_OUT_OF_RANGE = WarpConfig.REASON_STAGE_OUT_OF_RANGE
WarpService.REASON_INSUFFICIENT_BLOX = WarpConfig.REASON_INSUFFICIENT_BLOX

-- 아래 셋은 이 파일이 정의한다. 순수 계층은 프로필도 서비스 호출 결과도 모른다 —
-- WarpConfig에 두면 그 파일이 알 수 없는 것을 판정하는 모양이 된다.

-- 프로필이 로드되기 전이거나 이미 나간 플레이어.
-- ⚠️ 값을 RebirthService와 같은 "no_profile"로 맞춘 것은 의도다. insufficient_blox를
-- 새로 둔 것과 달라 보이지만 이유가 있다 — "블럭스 부족"은 기능별로 다른 안내가
-- 필요하지만 "프로필 없음"은 유저에게 보여줄 상황이 아니라 시스템 오류다.
-- UI 매핑이 갈릴 이유가 없다.
WarpService.REASON_NO_PROFILE = "no_profile"

-- canWarp을 통과했는데 차감이 거부됐다. **정상 경로에는 존재하지 않는다** —
-- 둘 사이에 yield가 없으면 잔액이 변할 수 없기 때문이다.
--
-- ⚠️ 이것을 INSUFFICIENT_BLOX로 접지 말 것. 유저 화면에는 충분한 값이 보이는데
-- "블럭스가 부족합니다"가 뜨는 거짓 안내가 된다. 이건 유저의 잔액 문제가 아니라
-- 경합이거나 정책 버그다.
--
-- ⚠️ RebirthService.REASON_PARTIAL_FAILURE와도 다르다. 저쪽은 이미 무언가 사라진 뒤의
-- 상태이고 이쪽은 **아무것도 일어나지 않은** 상태다. 같은 이름을 쓰면 로그를 보는
-- 사람이 "복구가 필요한가"를 판단할 수 없다.
WarpService.REASON_SUBTRACT_FAILED = "subtract_failed"

-- 차감은 끝났는데 런이 시작되지 않았다. **여기서만 유저가 손해를 본다.**
-- 되돌리지 않는다 — 아래 reportStartRunFailure 주석 참고.
WarpService.REASON_START_RUN_FAILED = "start_run_failed"

local REASON_NO_PROFILE = WarpService.REASON_NO_PROFILE
local REASON_SUBTRACT_FAILED = WarpService.REASON_SUBTRACT_FAILED
local REASON_START_RUN_FAILED = WarpService.REASON_START_RUN_FAILED

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

-- 호출 경로 식별용. RebirthService.normalizeSource와 같은 규칙이다.
-- 빈 문자열까지 접는 이유도 같다: CurrencyService의 reason은 비어 있으면 안 되는데
-- "warp_"로 끝나는 reason은 assert를 통과하면서 로그만 망가뜨린다.
local function normalizeSource(source: string?): string
	if type(source) == "string" and #source > 0 then
		return source
	end
	return "unknown"
end

-- canWarp을 통과했는데 차감이 거부된 것을 기록한다.
--
-- ⚠️ 사유 코드만 돌려주고 끝내지 않는다. "canWarp을 통과했는데 subtract가 거부했다"는
-- 사실 자체가 로그에 드러나야 한다 — 그냥 거부로만 남기면 나중에 이게 경합인지
-- 정책 버그인지 구분할 수 없다. 정상 경로에 없는 일이므로 print가 아니라 warn이다.
local function reportSubtractFailure(player: Player, targetStage: number, cost: BigNumber, sourceTag: string): (boolean, string)
	warn(string.format(
		"[WarpService][ERROR] canWarp 통과 후 subtract 거부: UserId=%d stage=%d cost=%s source=%s. "
			.. "정상 경로에 없는 상태다 — 경합(중간 yield)이거나 정책 버그다. 부작용은 없다.",
		player.UserId,
		targetStage,
		BigNum.tostring(cost),
		sourceTag
	))
	return false, REASON_SUBTRACT_FAILED
end

-- 차감 뒤 런 시작이 터진 것을 기록한다.
--
-- ⚠️ 되돌리지 않는다. RebirthService.reportPartialFailure와 같은 판단이다 —
-- **사후에 이 줄이 유일한 복구 근거가 된다.** 그래서 무엇이 사라졌는지를 문장으로
-- 남긴다. 되돌리지 않는 이유: 되돌리기(blox 재지급)가 또 실패할 수 있고, 그러면
-- "얼마를 돌려줬는지"조차 불확실해져 복구 근거가 오히려 흐려진다.
--
-- 이건 "유저가 손해 보는 쪽이 게임이 망가지는 쪽보다 낫다"의 손해 쪽이다
-- (RebirthService 5번 단계 주석). 순서를 뒤집어 런을 먼저 시작하면 차감 실패 시
-- 공짜 워프가 되므로, 손해를 감수하되 그 사실이 로그에 남아야 한다.
local function reportStartRunFailure(
	player: Player,
	targetStage: number,
	cost: BigNumber,
	sourceTag: string,
	err: any
): (boolean, string)
	warn(string.format(
		"[WarpService][ERROR] 부분 실패: UserId=%d stage=%d cost=%s source=%s - "
			.. "blox는 차감됐고 런은 시작되지 않았다. 프로필이 일관되지 않은 상태이며 "
			.. "이 줄이 유일한 복구 근거다. startRun 오류: %s",
		player.UserId,
		targetStage,
		BigNum.tostring(cost),
		sourceTag,
		tostring(err)
	))
	return false, REASON_START_RUN_FAILED
end

-- 이 흐름이 바깥 세계에 하는 일 전부. 실제 서비스 대신 기록용 테이블을 넣으면
-- **순서와 부작용을 Player 없이 잴 수 있다** (RebirthService.Deps와 같은 이음매).
--
-- 왜 필요한가: 워프 검증의 핵심은 "거부됐을 때 차감이 일어나지 않았는가"인데, 그건
-- 계산 결과가 아니라 **호출 여부**에 대한 질문이다. 가짜 Player 테이블로는
-- ProfileManager.get이 nil을 주기 때문에 실제 서비스를 태우면 전부 "프로필 없음"
-- 한 갈래로만 끝나서 이것을 볼 수 없다.
export type Deps = {
	getBlox: (Player) -> BigNumber?,
	subtractBlox: (Player, BigNumber, string) -> boolean,
	startRun: (Player, number) -> boolean,
}

-- 워프 결과.
export type WarpResult = BigNumber

-- 워프 한 번. 순서는 아래 주석의 번호가 곧 계약이다.
--
-- ⚠️ 이 함수 안에서 yield하지 말 것 (파일 상단 참고). deps로 들어오는 함수들도 마찬가지다.
local function runWarp(deps: Deps, player: Player, targetStage: number, source: string?): (boolean, any)
	local sourceTag = normalizeSource(source)
	local reason = "warp_" .. sourceTag

	-- 1. 프로필 확인. getBlox가 nil이면 로드 전이거나 이미 나간 플레이어다.
	--
	-- ⚠️ targetStage 검증보다 먼저다. 프로필이 없으면 목표층이 유효하든 아니든 아무것도
	-- 할 수 없고, 순서를 뒤집으면 "프로필이 없는데 INVALID_STAGE"라는 엉뚱한 사유가 나온다.
	local blox = deps.getBlox(player)
	if blox == nil then
		return false, REASON_NO_PROFILE
	end

	-- 2. 가능 판정. 목표층 검증(INVALID_STAGE) · 범위(STAGE_OUT_OF_RANGE) ·
	--    잔액(INSUFFICIENT_BLOX)이 전부 여기서 갈리고, 그 우선순위도 WarpConfig의 계약이다.
	--
	-- ⚠️ 여기까지는 **부작용이 0이어야 한다.** 거부가 런을 없애거나 값을 건드리면
	-- "층을 잘못 눌렀는데 진행 중이던 런이 날아갔다"가 된다.
	-- 아래 3번부터가 되돌릴 수 없는 구간이므로 판정을 전부 그 앞에서 끝낸다.
	local canOk, costOrReason = WarpConfig.canWarp(blox, targetStage)
	if not canOk then
		return false, costOrReason
	end
	local cost = costOrReason :: BigNumber

	-- ===== 여기부터 되돌릴 수 없다 =====================================================

	-- 3. 비용 차감. ⚠️ 런 시작보다 **먼저**다.
	-- 뒤집으면 런이 먼저 시작되고 차감이 실패했을 때 공짜 워프가 된다.
	-- 유저가 손해 보는 쪽이 게임이 망가지는 쪽보다 낫다 (RebirthService 5번 주석과 같은 원칙).
	--
	-- set이 아니라 subtract인 이유: 워프는 전액 소모가 아니라 정해진 비용만 가져간다.
	if not deps.subtractBlox(player, cost, reason) then
		return reportSubtractFailure(player, targetStage, cost, sourceTag)
	end

	-- 4. 목표 층에서 런을 새로 시작한다.
	--
	-- ⚠️ 기존 런이 있으면 startRun이 **조용히 덮어쓴다.** 이것이 정상 동작이다 —
	-- 거부하지 않는다(ChallengeService.startRun 주석). 워프는 "지금 어디에 있든
	-- 목표 층으로 간다"이므로 진행 중인 런을 없애는 것이 곧 기능이다.
	-- abandonRun을 먼저 부르지 않는 이유도 같다: 덮어쓰기가 이미 그 일을 한다.
	--
	-- ⚠️ pcall로 감싼다. startRun은 false를 돌려주는 경로가 없지만 error는 던질 수 있고
	-- (BlockService.enterStage 내부 오류 등), 그 시점엔 이미 blox가 사라져 있다.
	-- 감싸지 않으면 호출자가 error를 받으므로 사유 코드로 접을 수 없고, 유저 입장에선
	-- "블럭스가 사라졌는데 아무 일도 안 일어났다"가 된다.
	local startOk, startErr = pcall(deps.startRun, player, targetStage)
	if not startOk then
		return reportStartRunFailure(player, targetStage, cost, sourceTag, startErr)
	end

	-- 5. 성공. 돌려주는 것은 **차감된 비용**이다.
	--
	-- ⚠️ run 상태를 여기서 돌려주지 않는다. startRun이 RunStateChanged를 이미 발화했으므로
	-- (reason 태그 "start"), 같은 정보를 두 경로로 주면 어느 쪽이 최신인지 물어야 한다.
	-- 비용을 돌려주는 것은 canWarp의 반환 형태(ok=true면 비용)와도 대칭이다.
	return true, cost
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
WarpService._pure = {
	normalizeSource = normalizeSource,
	runWarp = runWarp,
}

-- ===== 공개 API =======================================================================

-- 실제 서비스에 연결한 deps. 모듈 로드 시 한 번 만든다.
-- ⚠️ 여기 있는 함수 중 어느 것도 yield하지 않는다. 새 항목을 붙일 때 그것부터 확인할 것.
local REAL: Deps = {
	getBlox = function(player: Player)
		return CurrencyService.get(player, "blox")
	end,
	subtractBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.subtract(player, "blox", amount, reason))
	end,
	startRun = function(player: Player, stage: number)
		return ChallengeService.startRun(player, stage)
	end,
}

-- 워프를 실행한다.
--
--   성공  true,  비용(BigNum)  — 실제로 차감된 금액
--   거부  false, "사유코드"    (REASON_* 상수 중 하나)
--
-- ⚠️ false를 전부 같은 "실패"로 다루지 말 것. 셋으로 갈린다:
--   INVALID_STAGE / STAGE_OUT_OF_RANGE / INSUFFICIENT_BLOX — 부작용 0인 정상 거부
--   SUBTRACT_FAILED  — 부작용 0이지만 정상 경로에 없는 상태(경합/버그). 로그를 볼 것
--   START_RUN_FAILED — **blox가 이미 사라졌다.** "워프하지 못했습니다"는 거짓 안내다
--
-- source는 호출 경로 태그다. nil이나 빈 문자열이면 "unknown"으로 접힌다
-- (RebirthService.rebirth / ChallengeService.advance·cashout과 같은 규칙).
function WarpService.warp(player: Player, targetStage: number, source: string?): (boolean, any)
	return runWarp(REAL, player, targetStage, source)
end

local initialized = false

-- 워프를 연다.
--
-- ⚠️ 순서: CurrencyService · ChallengeService가 준비된 뒤에 부른다
-- (Bootstrap의 호출 지점 주석 참고). 그 둘을 검사하지는 않는다 — 서로 init 상태를
-- 물어보는 API가 없고, 만들면 서비스끼리 준비 여부를 캐묻는 결합이 새로 생긴다.
--
-- ⚠️ 지금은 진입점이 없다. 워프를 실제로 부르는 경로가 아직 없고, 3D 파트나 Remote는
-- 이번 단계에서 만들지 않았다 — 진입점은 Phase 6 UI(텔레포트 버튼 → 스테이지 선택창)에
-- 붙인다. 그래서 이 함수는 지금 로그 한 줄이 전부다. 그럼에도 두는 이유는 그 진입점이
-- 붙을 자리를 한 곳으로 정해두기 위해서다 — 없으면 호출부가 각자 WarpService를
-- require하게 된다 (RebirthService.init과 같은 판단).
function WarpService.init()
	if initialized then
		warn("[WarpService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	print("[WarpService] 워프 준비 완료 (진입점은 아직 없음)")
end

return WarpService

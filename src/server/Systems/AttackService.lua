--!strict
-- 근접 자동 공격. 블록은 근접하면 자동으로 공격된다 — 클릭 입력이 아니다.
-- 규칙과 근거는 DESIGN.md "2. 블록 > 공격 방식"이 원본이다. ⚠️ 근거를 여기로 복사하지 말 것.
--
-- 이 파일이 채우는 것은 **힘 → 데미지 경로 하나**다. 그 아래(오버플로우·클리어 판정·
-- 통지)는 전부 이미 있었고, 그것을 부르는 실호출자만 없었다.
--
--   클릭 → 힘        ClickService          (이미 있음)
--   힘 → 데미지      **여기**
--   데미지 → 블록    ChallengeService → BlockService  (이미 있음)
--
-- ===== 거리 체크는 펀치 시점에 한다 (⚠️ 별도 폴링 루프를 두지 말 것) ==================
--
-- 발동 조건은 거리 폴링이다. 상시 발동이 아니다 — 반경 밖이면 그 펀치를 **스킵한다.**
-- 그래서 20초 동안 "블록 곁을 지킬 것인가 패드를 밟으러 갈 것인가"라는 판단이 생긴다.
--
-- ⚠️ 거리 판정용 루프를 따로 만들지 말 것. 펀치 주기(0.5초)와 그 루프의 주기가 어긋나면
-- "반경 밖으로 나갔는데 아직 안 꺼진 창"이 생긴다. 4-2-e에서 워프 동결을 포기하게 만든
-- "동결 1초 < SpeedService 폴링 1.5초"와 **정확히 같은 종류의 함정**이다
-- (→ docs/PENDING.md "워프 후 1초 동결"). 판정은 펀치가 나가는 그 자리에서 한 번만 한다.
--
-- ===== 경계 규약은 AttackConfig가 소유한다 ============================================
--
-- ⚠️ 여기서 `distance < radius` 같은 비교를 직접 쓰지 말 것. AttackConfig.isInRange를
-- 부른다. 이하(<=)인지 미만(<)인지가 두 파일에 생기면 경계에서 갈라지고, 그 차이는
-- "가끔 딜이 안 들어간다"로만 나타나서 재현이 안 된다.
--
-- ===== 판정 원점 =====================================================================
--
-- 블록 클러스터의 중심은 **런의 스테이지를 따라간다** — 스테이지 N이면
-- `ArenaConfig.getStageCenterX(N)`이다. AttackConfig의 반경은 그 중심 기준으로
-- 유도되므로 원점이 움직여도 92.8 그대로다.
--
-- ✅ 위 문단은 4-2-a2b(2026-09-05)에서 이렇게 바뀌었다. 그 전에는
-- "월드 원점 (0,0,0), 스테이지·월드와 무관하다"였고, 근거는 BlockService가
-- 오프셋을 더하지 않고 좌표를 그대로 쓴다는 것이었다 — 그리고 그 문단은
-- "BlockLayout이 언젠가 오프셋을 갖게 되면 여기서 고치지 말고 BlockLayout이
-- 원점을 노출하게 한 뒤 그것을 읽으라"고 미리 적어두었다. **그대로 했다.**
-- `BlockLayout.getStageOrigin`이 그 노출이고, 이 파일은 그것을 읽기만 한다.
--
-- ⚠️ 오프셋 식(주기 × (N-1))을 여기 옮겨 적지 말 것. 식은 한 곳에만 있어야 한다 —
-- OUTER_RADIUS를 BlockLayout에 노출시킨 것과 같은 이유다.
--
-- ===== BlockDamaged를 여기서 발신하지 않는다 (⚠️ 중요) ================================
--
-- ChallengeService.applyDamage가 **이미** notifyBlockDamaged를 발신한다.
-- 여기서 또 보내면 클라가 같은 변경을 두 번 받아 파편 연출이 두 배로 돈다.
-- 클리어 판정·maxStage 갱신·RunStateChanged 통지도 전부 그쪽이 한다 —
-- 이 파일은 "언제 얼마의 데미지를 넣을지"만 정한다.
--
-- ===== 서버는 데미지와 HP만 다룬다 ====================================================
--
-- ⚠️ 파편·파티클을 여기서 만들지 말 것 (CLAUDE.md 절대 규칙 4). 서버가 하는 일은
-- 데미지 숫자를 넘기는 것까지이고, 큐브 개수는 클라가 HP 비율로 역산한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
-- 판정 원점을 렌더와 같은 함수에서 받기 위해서다 (getStageOrigin). 좌표식을 여기 쓰지 말 것.
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local CurrencyService = require(script.Parent.CurrencyService)
local ChallengeService = require(script.Parent.ChallengeService)
-- 펀치 데미지 · 펀치 속도 업그레이드 효과(지시서 #7). 효과 식은 UpgradeConfig, 레벨은 UpgradeService가 안다.
local UpgradeService = require(script.Parent.UpgradeService)

type BigNumber = BigNum.BigNumber

local AttackService = {}

-- ===== 펀치 결과 코드 =================================================================
--
-- ⚠️ 코드만 둔다. 표시 문구를 여기 넣지 말 것 — 이건 UI용이 아니라 **관측용**이다.
-- Bootstrap VERIFY print가 이 값을 찍어서 "딜이 안 들어간다"의 원인을 가른다.
-- 후보가 넷(배수 미배선 / 반경 판정 / 펀치 루프 / applyDamage 호출)이라
-- 이 코드가 없으면 로그만 보고는 어느 쪽인지 알 수 없다.
AttackService.RESULT_OK = "ok"
AttackService.RESULT_NO_RUN = "no_run"
AttackService.RESULT_CLEARED = "cleared"
AttackService.RESULT_NO_CHARACTER = "no_character"
AttackService.RESULT_NO_STRENGTH = "no_strength"
AttackService.RESULT_OUT_OF_RANGE = "out_of_range"
AttackService.RESULT_NO_CHANGES = "no_changes"

local RESULT_OK = AttackService.RESULT_OK
local RESULT_NO_RUN = AttackService.RESULT_NO_RUN
local RESULT_CLEARED = AttackService.RESULT_CLEARED
local RESULT_NO_CHARACTER = AttackService.RESULT_NO_CHARACTER
local RESULT_NO_STRENGTH = AttackService.RESULT_NO_STRENGTH
local RESULT_OUT_OF_RANGE = AttackService.RESULT_OUT_OF_RANGE
local RESULT_NO_CHANGES = AttackService.RESULT_NO_CHANGES

-- 블록 클러스터의 중심. 위 "판정 원점" 참고.
--
-- ⚠️ **4-2-a2b에서 상수가 아니게 됐다.** 예전에는 `Vector3.new(0, 0, 0)` 하나였다 —
-- 25개 층의 블록이 전부 X=0에 겹쳐 있었기 때문이고, 그건 버그였다.
-- 이제 층마다 클러스터가 `ArenaConfig.getStageCenterX(stage)`에 선다.
--
-- ⚠️ **여기서 오프셋을 다시 계산하지 말 것.** `BlockLayout.getStageOrigin`은
-- 서버 배치(BlockService)·클라 렌더(RemoteReceiver)가 쓰는 것과 **같은 함수**다.
-- 판정이 자기 식으로 원점을 구하는 순간 "블록이 보이는데 안 맞는" 상태가 되고,
-- 그게 `BlockLayout.lua` 상단이 못박은 "판정 좌표 = 표시 좌표" 계약이 깨지는 방식이다.
--
-- ⚠️ 반경은 그대로다. `AttackConfig.getRadius()`가 쓰는 `OUTER_RADIUS`는 클러스터
-- **중심으로부터의** 거리라 클러스터가 어디로 가든 92.8이다. 원점만 움직인다.
local function clusterOriginFor(stage: number): Vector3
	return BlockLayout.getStageOrigin(stage)
end

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

-- 펀치 1회의 데미지 = **그 시점의 힘 × 펀치 데미지 업그레이드 배수.**
--
-- ⚠️ **힘 계통에서 업그레이드를 곱하는 지점은 여기 하나다**(지시서 #7 S4). 배수는 UpgradeConfig.getEffect("punchDamage", 레벨)
-- = 1 + 증가량 × 레벨(S1 — 더하기)이고, 0레벨이면 1이라 예전과 같다. 다른 곳(힘 획득 · 블록 쪽)에서 또 곱하지 말 것.
--
-- ⚠️ 펀치 속도를 곱하지 않는다. 속도는 **주기를 정할 뿐**이다.
-- 초당 총 데미지가 `힘 × 펀치속도`가 되는 것은 이 함수가 그 횟수만큼 불리는 결과이지,
-- 한 번의 데미지에 속도가 들어가서가 아니다. 여기서 한 번 더 곱하면 **이중 계산**이 되어
-- 실제 DPS가 속도의 제곱에 비례한다 — 4-2-f 성공률 계산이 통째로 틀어진다.
-- (AttackServiceTests가 이 회귀를 잡는다. 그 케이스를 지우지 말 것)
--
-- ⚠️ 새 테이블을 돌려준다. 프로필이 들고 있는 BigNum 테이블을 그대로 넘기면
-- 하류(BlockService)가 그것을 고칠 때 플레이어의 힘이 조용히 바뀐다.
-- (RebirthConfig의 zero() 주석이 경고하는 것과 같은 사고다)
local function computePunchDamage(strength: BigNumber, damageMultiplier: number): BigNumber
	if damageMultiplier == 1 then
		return BigNum.new(strength.m, strength.e)
	end
	return BigNum.mul(strength, BigNum.fromNumber(damageMultiplier))
end

-- 펀치 주기(초). 1 / 초당 횟수. rate를 안 주면 기본 속도(AttackConfig.PUNCH_SPEED_BASE).
-- ⚠️ 수치를 여기 적지 말 것. 기본 · 상한은 AttackConfig, 업그레이드 효과는 UpgradeConfig가 소유한다.
local function punchInterval(rate: number?): number
	return 1 / (rate or AttackConfig.PUNCH_SPEED_BASE)
end

-- ===== 플레이어별 펀치 주기 (지시서 #7) ====================================================
--
-- punchSpeed 업그레이드로 플레이어마다 초당 횟수가 다르다. 그래도 **서버 단일 루프**다(아래 init 주석) —
-- 루프는 짧은 틱(TICK_SEC)으로 돌고, 플레이어마다 "다음 펀치 시각"을 들고 있다가 그 시각이 지난 플레이어만 친다.
-- 거리 판정은 여전히 펀치가 나가는 그 자리(runPunch)에서 한 번만 한다 — 별도 폴링 루프가 아니다.
--
-- 틱은 가장 빠른 주기(1 / PUNCH_SPEED_MAX)보다 충분히 짧아야 한다 — 틱이 주기보다 길면 한 틱에 한 번밖에 못 쳐서
-- 실제 속도가 틱에 묶인다. 상한의 1/4로 잡는다(5회/초면 0.05초).
local TICK_DIVISOR = 4
local function tickSec(): number
	return 1 / (AttackConfig.PUNCH_SPEED_MAX * TICK_DIVISOR)
end

-- 다음 펀치 시각. 예정 시각에 주기를 더한다(평균 속도가 틱 간격과 무관하게 정확하다).
-- 그런데 그 시각도 이미 지났으면(서버가 멈췄다 풀림 · 캐릭터가 없던 동안 등) 지금부터 센다 — 밀린 펀치를 몰아치지 않는다.
local function scheduleNext(due: number, now: number, interval: number): number
	local nextAt = due + interval
	if nextAt <= now then
		return now + interval
	end
	return nextAt
end

-- 플레이어의 지금 초당 펀치 횟수. UpgradeConfig.getEffect("punchSpeed", 레벨) — 0레벨이면 PUNCH_SPEED_BASE, 최대 레벨이면 상한.
local function punchRateFor(player: Player): number
	return UpgradeService.getEffect(player, "punchSpeed")
end

-- 펀치 한 번의 결과. Bootstrap VERIFY가 이 값을 찍는다.
export type PunchOutcome = {
	result: string,
	distance: number?, -- 잴 수 있었을 때만
	damage: BigNumber?, -- 계산까지 갔을 때만
}

-- 이 흐름이 바깥 세계에 하는 일 전부. 실제 서비스 대신 기록용 테이블을 넣으면
-- **호출 여부를 Player 없이 잴 수 있다** (RebirthService.Deps / WarpService.Deps와 같은 이음매).
--
-- 왜 필요한가: 이 파일의 핵심 질문은 "반경 밖일 때 applyDamage를 **부르지 않았는가**"인데,
-- 그건 계산 결과가 아니라 호출 여부다. 가짜 Player 테이블로 실제 서비스를 태우면
-- 전부 "런 없음" 한 갈래로 끝나서 그것을 볼 수 없다.
export type Deps = {
	getRunState: (Player) -> { stage: number, cleared: boolean }?,
	getStrength: (Player) -> BigNumber?,
	getPosition: (Player) -> Vector3?,
	applyDamage: (Player, Vector3, BigNumber) -> any,
	-- 펀치 데미지 업그레이드 배수(1 이상). 0레벨이면 1
	getDamageMultiplier: (Player) -> number,
}

-- 펀치 한 번. 순서는 아래 주석의 번호가 곧 계약이다.
--
-- ⚠️ 판정 순서가 중요하다. 런 검사가 가장 앞인 이유: ChallengeService.applyDamage는
-- 런이 없으면 **warn을 찍는다.** 런 없는 플레이어에게 매 0.5초 부르면 로그가 도배되어
-- 정작 봐야 할 줄이 묻힌다. 여기서 미리 걸러야 한다.
local function runPunch(deps: Deps, player: Player): PunchOutcome
	-- 1. 런이 활성인가.
	local run = deps.getRunState(player)
	if run == nil then
		return { result = RESULT_NO_RUN }
	end

	-- 2. 이미 클리어했으면 때리지 않는다. 수령·진행 결정 대기 중이고, 타이머도 멈춰 있다.
	-- (ChallengeService.applyDamage도 같은 판정을 하지만 그쪽은 조용히 nil을 돌려주므로
	--  여기서 걸러야 "왜 안 들어갔나"가 결과 코드로 남는다)
	if run.cleared then
		return { result = RESULT_CLEARED }
	end

	-- 3. 캐릭터 위치. 사망·리스폰·로드 전에는 없다 — 정상 상태이므로 조용히 스킵한다.
	local position = deps.getPosition(player)
	if position == nil then
		return { result = RESULT_NO_CHARACTER }
	end

	-- 4. 거리 판정. ⚠️ 비교를 직접 쓰지 않는다 — 경계 규약은 AttackConfig가 소유한다.
	-- ⚠️ 원점이 런의 스테이지를 따라간다. run은 1번에서 이미 손에 있으므로
	-- 새로 조회하지 않는다 — 조회를 늘리면 그 사이 층이 바뀌는 창이 생긴다.
	local distance = (position - clusterOriginFor(run.stage)).Magnitude
	if not AttackConfig.isInRange(distance) then
		-- ⚠️ 데미지 0을 넣지 않는다. **호출 자체를 건너뛴다.**
		-- 0을 넣으면 BlockDamaged가 발화해서 클라가 매 0.5초 빈 연출을 돌고,
		-- 서버 로그에도 "때렸다"가 남아 반경 판정이 도는지 보이지 않는다.
		return { result = RESULT_OUT_OF_RANGE, distance = distance }
	end

	-- 5. 힘. ⚠️ CurrencyService를 통해서만 읽는다 — profile.Data를 직접 보지 말 것
	-- (CLAUDE.md 절대 규칙 2). 프로필이 없으면 nil이고 그 틱은 스킵한다.
	local strength = deps.getStrength(player)
	if strength == nil then
		return { result = RESULT_NO_STRENGTH, distance = distance }
	end

	local damage = computePunchDamage(strength, deps.getDamageMultiplier(player))

	-- 6. 데미지 전달. 오버플로우·클리어 판정·BlockDamaged 발신은 전부 하류가 한다.
	-- originPosition은 캐릭터 위치다 — BlockService가 "가까운 블록부터" 정렬에 쓴다.
	local changes = deps.applyDamage(player, position, damage)
	if changes == nil then
		-- 하류가 거부했다. 런이 그 사이 사라졌거나 이미 클리어된 경우다.
		return { result = RESULT_NO_CHANGES, distance = distance, damage = damage }
	end

	return { result = RESULT_OK, distance = distance, damage = damage }
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
AttackService._pure = {
	runPunch = runPunch,
	computePunchDamage = computePunchDamage,
	punchInterval = punchInterval,
	scheduleNext = scheduleNext,
	tickSec = tickSec,
	-- ⚠️ 상수 CLUSTER_ORIGIN을 노출하던 자리다. 층마다 달라지므로 상수로 줄 수 없다.
	-- 테스트는 이 함수를 부르거나 BlockLayout.getStageOrigin을 직접 쓴다 — 어느 쪽이든
	-- 렌더와 같은 유도를 타는 것이 요점이다.
	clusterOriginFor = clusterOriginFor,
}

-- ===== 공개 API =======================================================================

-- 캐릭터의 월드 위치. 없는 순간이 정상적으로 존재한다(사망·리스폰·로드 전).
local function getPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	-- ⚠️ WaitForChild를 쓰지 말 것. 이 함수는 0.5초마다 도는 루프 안에서 불리므로
	-- 기다리면 그 코루틴이 멈추고 다른 플레이어의 펀치까지 밀린다.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- 실제 서비스에 연결한 deps. 모듈 로드 시 한 번 만든다.
local REAL: Deps = {
	getRunState = function(player: Player)
		return ChallengeService.getRunState(player)
	end,
	getStrength = function(player: Player)
		return CurrencyService.get(player, "strength")
	end,
	getPosition = getPosition,
	applyDamage = function(player: Player, position: Vector3, damage: BigNumber)
		return ChallengeService.applyDamage(player, position, damage)
	end,
	getDamageMultiplier = function(player: Player)
		return UpgradeService.getEffect(player, "punchDamage")
	end,
}

-- ===== 관측 =========================================================================
--
-- 마지막 펀치의 결과. Bootstrap VERIFY print가 읽는다 —
-- SpeedRequestService.getStats와 같은 성격이고 같은 이유로 있다:
-- 이 경로에는 UI가 없어서(Phase 6) 배선이 끊겨도 화면에 아무 흔적이 없다.
--
-- ⚠️ 세션 메모리다. 프로필에 저장하지 않는다.
local lastOutcome: { [Player]: PunchOutcome } = {}

-- 플레이어별 다음 펀치 시각(os.clock). 위 "플레이어별 펀치 주기". 세션 메모리다.
local nextPunchAt: { [Player]: number } = {}

-- 마지막 펀치 결과. 아직 한 번도 안 돌았으면 nil.
function AttackService.getLastOutcome(player: Player): PunchOutcome?
	return lastOutcome[player]
end

-- 펀치 한 번을 지금 처리한다. 루프가 부르지만 테스트·검증도 직접 부를 수 있다.
function AttackService.punch(player: Player): PunchOutcome
	local outcome = runPunch(REAL, player)
	lastOutcome[player] = outcome
	return outcome
end

local initialized = false

-- 근접 자동 공격을 연다.
--
-- ⚠️ 순서: CurrencyService · ChallengeService가 준비된 뒤에 부른다.
-- 그 둘을 검사하지는 않는다 — 서로 init 상태를 물어보는 API가 없고, 만들면
-- 서비스끼리 준비 여부를 캐묻는 결합이 새로 생긴다 (WarpService.init과 같은 판단).
function AttackService.init()
	if initialized then
		warn("[AttackService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- ⚠️ 플레이어별 task.spawn이 아니라 **서버 단일 루프**다.
	-- 플레이어마다 루프를 걸면 나갈 때 각각 멈춰야 하고, 한 번 놓치면 코루틴이 남는다.
	-- SpeedService의 주기 검사가 같은 이유로 단일 루프다 — 그 관례를 따른다.
	-- 플레이어마다 주기가 다르므로(펀치 속도 업그레이드) 루프는 짧은 틱으로 돌고 "다음 펀치 시각"이 지난 플레이어만 친다
	-- (위 "플레이어별 펀치 주기"). 처음 본 플레이어는 한 주기 뒤에 첫 펀치 — 예전 루프(대기 후 펀치)와 같다.
	-- 주기는 펀치할 때마다 다시 읽는다 — 업그레이드를 사면 다음 펀치부터 새 주기다.
	task.spawn(function()
		while true do
			task.wait(tickSec())
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local due = nextPunchAt[player]
				if due == nil then
					nextPunchAt[player] = now + punchInterval(punchRateFor(player))
				elseif now >= due then
					AttackService.punch(player)
					nextPunchAt[player] = scheduleNext(due, now, punchInterval(punchRateFor(player)))
				end
			end
		end
	end)

	-- 누수 방지. 관측 테이블 · 펀치 시각은 세션 메모리이므로 퇴장 시 지운다.
	Players.PlayerRemoving:Connect(function(player: Player)
		lastOutcome[player] = nil
		nextPunchAt[player] = nil
	end)

	print(string.format(
		"[AttackService] 근접 자동 공격 시작 (기본 %.1f회/초 · 상한 %.1f회/초, 틱 %.3f초, 판정 반경 %.1f studs)",
		AttackConfig.PUNCH_SPEED_BASE,
		AttackConfig.PUNCH_SPEED_MAX,
		tickSec(),
		AttackConfig.getRadius()
	))
end

return AttackService

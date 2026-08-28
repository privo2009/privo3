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
-- 블록 클러스터의 중심은 **월드 원점 (0,0,0)** 이다. 스테이지·월드와 무관하다.
-- 근거: BlockLayout의 ring()이 원점 중심으로 좌표를 만들고(그 파일 "좌표는 원점 고정이다"),
-- BlockService가 그 좌표에 오프셋을 더하지 않고 그대로 블록 위치로 쓴다.
-- AttackConfig의 반경도 전부 이 중심 기준으로 유도됐다.
--
-- ⚠️ BlockLayout이 언젠가 오프셋을 갖게 되면 이 상수도 함께 움직여야 한다.
-- 그때는 여기서 고치지 말고 BlockLayout이 원점을 노출하게 한 뒤 그것을 읽을 것 —
-- OUTER_RADIUS를 그쪽에 노출시킨 것과 같은 이유다(식은 한 곳에만).
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
local CurrencyService = require(script.Parent.CurrencyService)
local ChallengeService = require(script.Parent.ChallengeService)

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
local CLUSTER_ORIGIN = Vector3.new(0, 0, 0)

-- ===== 순수 로직 (Player/Instance 의존 없음) ===========================================

-- 펀치 1회의 데미지 = **그 시점의 힘.**
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
local function computePunchDamage(strength: BigNumber): BigNumber
	return BigNum.new(strength.m, strength.e)
end

-- 펀치 주기(초). 1 / 초당 횟수.
-- ⚠️ 수치를 여기 적지 말 것. AttackConfig가 소유한다 (CLAUDE.md "작업 방식").
--
-- ⚠️ 지금은 전원이 BASE다. punchSpeed 업그레이드(UpgradeConfig)가 붙으면 플레이어별로
-- 갈리는데, 그때 이 함수를 플레이어별로 부르는 것만으로는 부족하다 — 단일 루프의
-- 주기 자체를 바꿔야 하므로 루프 구조를 함께 봐야 한다. 그 전까지는 상수다.
local function punchInterval(): number
	return 1 / AttackConfig.PUNCH_SPEED_BASE
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
	local distance = (position - CLUSTER_ORIGIN).Magnitude
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

	local damage = computePunchDamage(strength)

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
	CLUSTER_ORIGIN = CLUSTER_ORIGIN,
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
}

-- ===== 관측 =========================================================================
--
-- 마지막 펀치의 결과. Bootstrap VERIFY print가 읽는다 —
-- SpeedRequestService.getStats와 같은 성격이고 같은 이유로 있다:
-- 이 경로에는 UI가 없어서(Phase 6) 배선이 끊겨도 화면에 아무 흔적이 없다.
--
-- ⚠️ 세션 메모리다. 프로필에 저장하지 않는다.
local lastOutcome: { [Player]: PunchOutcome } = {}

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
	task.spawn(function()
		while true do
			task.wait(punchInterval())
			for _, player in ipairs(Players:GetPlayers()) do
				AttackService.punch(player)
			end
		end
	end)

	-- 누수 방지. 관측 테이블은 세션 메모리이므로 퇴장 시 지운다.
	Players.PlayerRemoving:Connect(function(player: Player)
		lastOutcome[player] = nil
	end)

	print(string.format(
		"[AttackService] 근접 자동 공격 시작 (%.1f회/초, 주기 %.2f초, 판정 반경 %.1f studs)",
		AttackConfig.PUNCH_SPEED_BASE,
		punchInterval(),
		AttackConfig.getRadius()
	))
end

return AttackService

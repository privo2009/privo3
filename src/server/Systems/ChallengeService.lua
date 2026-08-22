--!strict
-- 챌린지 루프(스테이지 진입 → 20초 타이머 → 클리어/실패) 오케스트레이션. DESIGN.md "1. 챌린지" 기준.
--
-- 절대 원칙:
--   - 보상은 누적이 아니라 갱신이다. 스테이지를 클리어할 때마다 currentReward를 덮어쓴다.
--     실패하면 런 자체를 버려서(0 지급) 이전 스테이지 보상도 함께 사라진다 (푸시-유어-럭)
--   - 타이머는 서버 os.clock() 기준. 클라가 보낸 시간은 절대 신뢰하지 않는다
--   - run 상태(stage/currentReward/startedAt)는 메모리에만 존재한다. 프로필에 저장하지 않는다
--     (강제 종료로 진행 중이던 런의 보상을 지키는 익스플로잇 방지)
--   - 블럭스 지급은 CurrencyService.add만 통과한다. profile.blox를 직접 건드리지 않는다
--   - 클리어 시 profile.Data.progress.maxStage를 그 스테이지가 더 클 때만 갱신한다
--
-- BlockService와의 관계: ChallengeService가 상위, BlockService가 하위.
--   - 스테이지 진입 → BlockService.enterStage
--   - 데미지 판정 → BlockService.applyDamage로 위임
--   - 클리어 판정 → BlockService.isCleared
--   BlockService는 ChallengeService를 몰라야 한다 (역방향 require 금지).
--
-- 시간 계산/보상 갱신/maxStage 갱신은 Player 없이 동작하는 순수 함수로 분리했고,
-- ChallengeService._pure로 노출해서 ChallengeServiceTests.server.lua가 직접 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.CurrencyService)
local BlockService = require(script.Parent.BlockService)

type BigNumber = BigNum.BigNumber
type BlockChange = BlockService.BlockChange

export type RunState = {
	stage: number,
	currentReward: BigNumber,
	startedAt: number, -- os.clock() 기준
	cleared: boolean, -- true면 타이머 정지, advance/cashout 가능
	frozenTimeLeft: number?, -- cleared된 순간의 남은 시간 스냅샷 (타이머 정지 표시용)
}

export type RunStateView = {
	stage: number,
	reward: BigNumber,
	timeLeft: number,
	cleared: boolean,
	-- 진행 벽을 열어도 되는가. false면 벽을 비활성화하고 수령 발판만 남긴다
	-- (DESIGN.md 8. 월드 > 최종 월드의 마지막 층). 벽 배치 코드는 이 값만 보면 된다.
	canAdvance: boolean,
}

local ChallengeService = {}

-- ===== 순수 로직 (Player 의존 없음) =====================================================

-- 새 스테이지의 런 상태를 만든다. reward는 그대로 대입(덮어쓰기)한다 — 이전 stage의
-- currentReward와 합산하지 않는다. advance()도 이 함수를 재사용해서 "갱신이지 누적이 아님"을
-- 자연스럽게 보장한다.
local function buildRun(stage: number, reward: BigNumber, now: number): RunState
	return {
		stage = stage,
		currentReward = reward,
		startedAt = now,
		cleared = false,
		frozenTimeLeft = nil,
	}
end

local function computeTimeLeft(startedAt: number, now: number, durationSec: number): number
	return math.max(0, durationSec - (now - startedAt))
end

local function isExpired(startedAt: number, now: number, durationSec: number): boolean
	return (now - startedAt) >= durationSec
end

-- clearedStage가 currentMaxStage보다 클 때만 갱신한다 (환생 등으로 되돌아간 스테이지를
-- 다시 클리어해도 maxStage가 내려가지 않도록).
local function computeNewMaxStage(currentMaxStage: number, clearedStage: number): number
	return math.max(currentMaxStage, clearedStage)
end

-- 런이 클리어된 채로 끝났으면 그 보상을, 실패(타임아웃/이탈)로 끝났으면 0을 반환한다.
-- 실제 실패 경로는 이 함수를 호출하지 않고 런을 그냥 버리지만(=0 지급), 그 설계를
-- 하나의 순수 함수로도 확인할 수 있도록 노출해둔다.
local function resolveRunOutcome(run: RunState, cleared: boolean): BigNumber
	if cleared then
		return run.currentReward
	end
	return BigNum.new(0, 0)
end

-- 진행 벽이 열리는 조건. 클리어했고, 갈 다음 층이 실재해야 한다.
-- nextStageExists를 인자로 받는 이유: 이 판정을 StageConfig 조회와 분리해두면
-- "다음 월드가 있는 경우"를 월드 주입 없이도 순수 함수로 검증할 수 있다.
local function canAdvanceFrom(run: RunState, nextStageExists: boolean): boolean
	return run.cleared and nextStageExists
end

-- 수령 발판이 활성화되는 조건. 진행 벽이 막혀도 이쪽은 영향받지 않는다 —
-- 최종 층에서 "수령만 가능"이 성립하는 근거가 이 독립성이다.
local function canCashout(run: RunState): boolean
	return run.cleared
end

-- 호출 경로 식별용. advance/cashout은 지금은 발판·벽만 호출하지만, 자동 수령 게임패스(Phase 8)와
-- 자동 진행 모드가 나중에 같은 함수를 직접 호출한다. 그때 "이 거부가 어디서 났나"를 로그만 보고
-- 알 수 있어야 호출부를 역추적하지 않는다. 선택 인자이므로 안 넘기면 "unknown"이다.
-- 빈 문자열까지 unknown으로 접는 이유: CurrencyService의 reason은 비어 있으면 안 되는데,
-- "challenge_cashout_"로 끝나는 reason은 assert를 통과하면서 로그만 망가뜨린다.
local function normalizeSource(source: string?): string
	if type(source) == "string" and #source > 0 then
		return source
	end
	return "unknown"
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
ChallengeService._pure = {
	buildRun = buildRun,
	computeTimeLeft = computeTimeLeft,
	isExpired = isExpired,
	computeNewMaxStage = computeNewMaxStage,
	resolveRunOutcome = resolveRunOutcome,
	canAdvanceFrom = canAdvanceFrom,
	canCashout = canCashout,
	normalizeSource = normalizeSource,
}

-- ===== 공개 API (Player 상태 보관) ======================================================

local runs: { [Player]: RunState } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	runs[player] = nil
end)

local function failRun(player: Player, run: RunState)
	warn(string.format("[ChallengeService] %s(%d) 챌린지 실패(시간 초과) - stage=%d, reward=%s 소멸", player.Name, player.UserId, run.stage, BigNum.tostring(run.currentReward)))
	runs[player] = nil
end

-- 만료 검사 루프. 20초 타이머라 프레임 단위 정밀도가 필요 없으므로 일정 간격으로만 스캔한다.
local EXPIRY_CHECK_INTERVAL_SEC = 0.5
local timeSinceLastCheck = 0

RunService.Heartbeat:Connect(function(dt: number)
	timeSinceLastCheck += dt
	if timeSinceLastCheck < EXPIRY_CHECK_INTERVAL_SEC then
		return
	end
	timeSinceLastCheck = 0

	local now = os.clock()
	for player, run in pairs(runs) do
		if not run.cleared and isExpired(run.startedAt, now, StageConfig.CHALLENGE_TIMER_SEC) then
			failRun(player, run)
		end
	end
end)

-- 스테이지(기본 1)부터 런을 시작한다. 기존 런이 있었다면 덮어쓴다.
function ChallengeService.startRun(player: Player, stage: number?): boolean
	local targetStage = stage or 1
	assert(type(targetStage) == "number" and targetStage >= 1, "ChallengeService.startRun: stage는 1 이상이어야 함")

	local reward = StageConfig.getBloxReward(targetStage)
	runs[player] = buildRun(targetStage, reward, os.clock())
	BlockService.enterStage(player, targetStage)

	return true
end

-- 데미지를 BlockService에 위임하고, 이번 타격으로 클리어됐으면 타이머를 멈추고 maxStage를 갱신한다.
function ChallengeService.applyDamage(player: Player, originPosition: Vector3, damage: BigNumber): { BlockChange }?
	local run = runs[player]
	if run == nil then
		warn(string.format("[ChallengeService] applyDamage 실패: %s(%d) 활성 런 없음", player.Name, player.UserId))
		return nil
	end

	if run.cleared then
		-- 이미 클리어해서 advance/cashout 결정 대기 중. 추가 타격은 의미 없으니 무시.
		return nil
	end

	local changes = BlockService.applyDamage(player, originPosition, damage)
	if changes == nil then
		return nil
	end

	if BlockService.isCleared(player) then
		run.cleared = true
		run.frozenTimeLeft = computeTimeLeft(run.startedAt, os.clock(), StageConfig.CHALLENGE_TIMER_SEC)

		local profile = ProfileManager.get(player)
		if profile ~= nil then
			profile.Data.progress.maxStage = computeNewMaxStage(profile.Data.progress.maxStage, run.stage)
		end
	end

	return changes
end

-- 클리어 상태에서만 다음 스테이지로 넘어간다. reward는 새 스테이지 값으로 덮어쓴다(누적 아님).
--
-- 현재 정의된 마지막 층에서는 진행 벽이 열리지 않으므로 여기서 정상 거부한다.
-- StageConfig.getWorld는 없는 월드에 assert로 터지는데, 그건 "있어선 안 될 상태"를 잡는
-- 장치지 유저가 25층을 깬 정상 상황을 다룰 자리가 아니다. 터뜨리지 않고 false를 돌려준다.
function ChallengeService.advance(player: Player, source: string?): boolean
	local src = normalizeSource(source)
	local run = runs[player]
	if run == nil then
		warn(string.format("[ChallengeService] advance 실패: %s(%d) 활성 런 없음 (source=%s)", player.Name, player.UserId, src))
		return false
	end

	if not run.cleared then
		warn(string.format("[ChallengeService] advance 거부: %s(%d) 아직 클리어 안 됨 (stage=%d, source=%s)", player.Name, player.UserId, run.stage, src))
		return false
	end

	local nextStage = run.stage + 1

	if not canAdvanceFrom(run, StageConfig.hasStage(nextStage)) then
		-- 에러가 아니라 설계된 종착점이다. WorldConfig에 다음 월드가 추가되면 저절로 풀린다.
		warn(string.format("[ChallengeService] advance 거부: %s(%d) 최종 층 도달 (stage=%d, source=%s) - 스테이지 %d를 담당하는 월드가 WorldConfig에 없음. 진행 벽 비활성, 수령만 가능", player.Name, player.UserId, run.stage, src, nextStage))
		return false
	end

	local nextReward = StageConfig.getBloxReward(nextStage)
	runs[player] = buildRun(nextStage, nextReward, os.clock())
	BlockService.enterStage(player, nextStage)

	-- 성공 로그를 추가한 이유: 거부만 로깅하면 자동 진행 모드가 붙었을 때 "몇 층에서 몇 층으로,
	-- 어느 경로로 넘어갔는가"가 아무 데도 안 남는다. 자동 진행은 벽 통과 없이 서버가 연속으로
	-- 호출하므로 유저 조작이라는 육안 단서조차 없어서, 층이 튀거나 멈춘 버그를 재현 없이는
	-- 못 쫓는다. 층 전환 1회당 한 줄이라 수동 진행(20초에 1회)에서는 부담이 없고, 자동 진행에서
	-- 과하면 이 줄만 지우면 된다 — 판정에는 관여하지 않는다.
	print(string.format("[ChallengeService] advance: %s(%d) stage %d -> %d (source=%s)", player.Name, player.UserId, run.stage, nextStage, src))

	return true
end

-- 클리어 상태에서만 보상을 지급하고 런을 끝낸다.
function ChallengeService.cashout(player: Player, source: string?): (boolean, BigNumber?)
	local src = normalizeSource(source)
	local run = runs[player]
	if run == nil then
		warn(string.format("[ChallengeService] cashout 실패: %s(%d) 활성 런 없음 (source=%s)", player.Name, player.UserId, src))
		return false, nil
	end

	-- 진행 벽이 막힌 최종 층에서도 이 게이트는 그대로 통과한다. 수령은 벽 상태와 무관하다.
	if not canCashout(run) then
		warn(string.format("[ChallengeService] cashout 거부: %s(%d) 아직 클리어 안 됨 (stage=%d, source=%s)", player.Name, player.UserId, run.stage, src))
		return false, nil
	end

	local reward = run.currentReward
	-- reason에 경로를 박아두면 재화 로그(CurrencyService)만 봐도 발판 수령인지 자동 수령인지
	-- 갈라진다. 재화 누수 추적은 CurrencyService 로그 한 곳에서 하기로 했으므로(CLAUDE.md 2번),
	-- 그쪽에 경로가 남아야 한다.
	local ok = CurrencyService.add(player, "blox", reward, "challenge_cashout_" .. src)
	if not ok then
		-- CurrencyService가 이미 거부 사유를 로깅했다. 런은 유지해서(날리지 않고) 재시도 가능하게 둔다.
		warn(string.format("[ChallengeService] cashout 실패: %s(%d) 지급 거부됨 (stage=%d, source=%s) - 런 유지, 재시도 가능", player.Name, player.UserId, run.stage, src))
		return false, nil
	end

	runs[player] = nil
	return true, reward
end

-- 이탈/포기 처리. 실패와 동일하게 런을 그냥 버린다 (보상 0, 패널티 없음).
function ChallengeService.abandonRun(player: Player): boolean
	if runs[player] == nil then
		return false
	end
	runs[player] = nil
	return true
end

function ChallengeService.getRunState(player: Player): RunStateView?
	local run = runs[player]
	if run == nil then
		return nil
	end

	local timeLeft: number
	if run.cleared then
		timeLeft = run.frozenTimeLeft or 0
	else
		timeLeft = computeTimeLeft(run.startedAt, os.clock(), StageConfig.CHALLENGE_TIMER_SEC)
	end

	return {
		stage = run.stage,
		reward = run.currentReward,
		timeLeft = timeLeft,
		cleared = run.cleared,
		canAdvance = canAdvanceFrom(run, StageConfig.hasStage(run.stage + 1)),
	}
end

return ChallengeService

--!strict
-- ChallengeService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 3-3 검증: 보상 갱신(누적 아님) / 실패 시 0 / 타이머 만료 경계값 /
-- 클리어 전 advance·cashout 거부 / maxStage는 더 클 때만 갱신.
--
-- 1~4번은 ChallengeService._pure의 순수 함수만 호출한다 — Player 없이 검증한다.
-- 5번(거부 판정)만 실제 공개 API(startRun/advance/cashout)를 호출하는데, 이 함수들이
-- 내부에서 진짜로 건드리는 건 player.Name/player.UserId 필드뿐이라(Instance 메서드 없음),
-- 그 두 필드만 있는 평범한 테이블을 "가짜 Player"로 넘겨도 동작한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local ChallengeService = require(script.Parent.ChallengeService)

local pure = ChallengeService._pure

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

-- 1. buildRun: 보상이 누적이 아니라 갱신되는지 (DESIGN.md 예시 그대로 1 → 3 → 8) -----------------

do
	local run1 = pure.buildRun(1, BigNum.new(1, 0), 0) -- 스테이지1 클리어: 지금 나가면 1
	check("스테이지1 보상 == 1", BigNum.eq(run1.currentReward, BigNum.new(1, 0)))

	local run2 = pure.buildRun(2, BigNum.new(3, 0), 1) -- 스테이지2 클리어: 지금 나가면 3 (1 대체됨)
	check("스테이지2 보상 == 3 (1과 합산된 4가 아님)", BigNum.eq(run2.currentReward, BigNum.new(3, 0)))

	local run3 = pure.buildRun(3, BigNum.new(8, 0), 2) -- 스테이지3 클리어: 지금 나가면 8
	check("스테이지3 보상 == 8 (1+3+8=12가 아님)", BigNum.eq(run3.currentReward, BigNum.new(8, 0)))
end

-- 2. resolveRunOutcome: 실패 시 0 --------------------------------------------------------

do
	local run = pure.buildRun(5, BigNum.new(199, 1), 0) -- 진행 중 보상이 얼마든
	check("클리어 상태면 보상 그대로 지급", BigNum.eq(pure.resolveRunOutcome(run, true), run.currentReward))
	check("실패(cleared=false)면 보상은 0", BigNum.eq(pure.resolveRunOutcome(run, false), BigNum.new(0, 0)))
end

-- 3. isExpired: 타이머 만료 판정 경계값 ----------------------------------------------------

do
	local startedAt = 100
	local durationSec = 20

	check("정확히 20초 지나면 만료(포함)", pure.isExpired(startedAt, startedAt + 20, durationSec) == true)
	check("19.99초는 아직 안 만료", pure.isExpired(startedAt, startedAt + 19.99, durationSec) == false)
	check("20.01초는 만료", pure.isExpired(startedAt, startedAt + 20.01, durationSec) == true)
	check("0초(막 시작)는 안 만료", pure.isExpired(startedAt, startedAt, durationSec) == false)
end

do
	-- computeTimeLeft도 같은 경계에서 0으로 클램프되는지 (음수로 안 내려가는지)
	check("20초 시점 timeLeft == 0", pure.computeTimeLeft(100, 120, 20) == 0)
	check("25초 시점(초과)도 timeLeft == 0 (음수 아님)", pure.computeTimeLeft(100, 125, 20) == 0)
	check("10초 시점 timeLeft == 10", pure.computeTimeLeft(100, 110, 20) == 10)
end

-- 4. computeNewMaxStage: 기존보다 클 때만 갱신 ------------------------------------------------

do
	check("클리어 스테이지가 더 크면 갱신", pure.computeNewMaxStage(5, 7) == 7)
	check("클리어 스테이지가 더 작으면 유지", pure.computeNewMaxStage(5, 3) == 5)
	check("클리어 스테이지가 같으면 유지", pure.computeNewMaxStage(5, 5) == 5)
end

-- 5. 클리어 전 advance/cashout 거부 (실제 공개 API, 가짜 Player 테이블 사용) --------------------

do
	local fakePlayer = { Name = "ChallengeTestPlayer", UserId = 999999 }

	local startOk = ChallengeService.startRun(fakePlayer :: any, 1)
	check("startRun은 성공", startOk == true)

	local advanceOk = ChallengeService.advance(fakePlayer :: any)
	check("클리어 전 advance는 거부됨", advanceOk == false)

	local cashoutOk, cashoutReward = ChallengeService.cashout(fakePlayer :: any)
	check("클리어 전 cashout은 거부됨", cashoutOk == false and cashoutReward == nil)

	local state = ChallengeService.getRunState(fakePlayer :: any)
	check("거부되어도 런 자체는 그대로 남아있음 (stage=1)", state ~= nil and state.stage == 1 and state.cleared == false)

	ChallengeService.abandonRun(fakePlayer :: any)
end

print(string.format("[ChallengeServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ChallengeServiceTests] %d test(s) failed", failed))
end

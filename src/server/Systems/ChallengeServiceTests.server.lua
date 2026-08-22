--!strict
-- ChallengeService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 3-3 검증: 보상 갱신(누적 아님) / 실패 시 0 / 타이머 만료 경계값 /
-- 클리어 전 advance·cashout 거부 / maxStage는 더 클 때만 갱신 / 최종 층 진행 벽 차단.
--
-- 1~4번은 ChallengeService._pure의 순수 함수만 호출한다 — Player 없이 검증한다.
-- 5~6번은 실제 공개 API(startRun/applyDamage/advance/cashout)를 호출하는데, 이 함수들이
-- 내부에서 진짜로 건드리는 건 player.Name/player.UserId 필드뿐이라(Instance 메서드 없음),
-- 그 두 필드만 있는 평범한 테이블을 "가짜 Player"로 넘겨도 동작한다.
-- maxStage 갱신과 블럭스 지급만 프로필을 요구하는데, 전자는 profile == nil이면 건너뛰고
-- 후자는 CurrencyService가 거부하고 끝난다 — 둘 다 터지지 않으므로 나머지 경로는 검증 가능하다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
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

-- 6. 최종 층에서 진행 벽이 막힌다 (DESIGN.md 8. 월드 > 최종 월드의 마지막 층) -------------------
--
-- 6-1은 순수 함수, 6-2~6-4는 실제 공개 API를 탄다.
-- advance/applyDamage/getRunState는 프로필을 요구하지 않으므로(maxStage 갱신은 profile이
-- nil이면 건너뛴다) 5번과 같은 가짜 Player 테이블로 끝까지 굴릴 수 있다.

do
	local clearedRun = pure.buildRun(25, BigNum.new(1, 0), 0)
	clearedRun.cleared = true
	local runningRun = pure.buildRun(25, BigNum.new(1, 0), 0)

	check("클리어 + 다음 층 있음 → 진행 가능", pure.canAdvanceFrom(clearedRun, true) == true)
	check("클리어 + 다음 층 없음 → 진행 불가 (벽 막힘)", pure.canAdvanceFrom(clearedRun, false) == false)
	check("미클리어 + 다음 층 있음 → 진행 불가", pure.canAdvanceFrom(runningRun, true) == false)
	-- 수령 게이트는 다음 층 존재 여부를 인자로 받지도 않는다 = 구조적으로 벽과 무관하다.
	check("최종 층이어도 수령 게이트는 통과", pure.canCashout(clearedRun) == true)
	check("미클리어면 수령 게이트도 막힘", pure.canCashout(runningRun) == false)
end

do
	local finalStage = 0
	for _, world in pairs(WorldConfig.Worlds) do
		finalStage = math.max(finalStage, world.stageRange[2])
	end
	check("StageConfig가 최종 층을 최종 층으로 안다", StageConfig.isFinalStage(finalStage) == true)
	check("최종 층 다음은 존재하지 않는다", StageConfig.hasStage(finalStage + 1) == false)

	local fakePlayer = { Name = "FinalStageTestPlayer", UserId = 999998 }

	ChallengeService.startRun(fakePlayer :: any, finalStage)
	-- 실제 클리어 경로를 탄다. 데미지 오버플로우로 한 방에 전 블록이 부서진다.
	ChallengeService.applyDamage(fakePlayer :: any, Vector3.new(0, 0, 0), BigNum.new(1, 200))

	local cleared = ChallengeService.getRunState(fakePlayer :: any)
	check("최종 층이 실제로 클리어됨", cleared ~= nil and cleared.cleared == true)
	check("클리어했는데도 canAdvance == false (벽 비활성)", cleared ~= nil and cleared.canAdvance == false)

	local advanceOk = ChallengeService.advance(fakePlayer :: any)
	check("최종 층에서 advance 거부 (assert로 터지지 않고 false 반환)", advanceOk == false)

	local afterReject = ChallengeService.getRunState(fakePlayer :: any)
	check("거부되어도 런은 클리어 상태로 살아있음", afterReject ~= nil and afterReject.stage == finalStage and afterReject.cleared == true)

	-- cashout은 CurrencyService.add까지 내려가고, 가짜 Player에는 프로필이 없어서 거기서 막힌다.
	-- 즉 여기서 확인 가능한 것은 "cleared 게이트를 통과해 재화 계층까지 갔다"까지다.
	-- 실패해도 런을 남기는 것이 cashout의 계약이므로(재시도 가능), 그 계약이 지켜지는지 본다.
	-- 지급 성공 경로 자체는 CurrencyServiceTests가 프로필 없이 별도로 검증한다.
	local cashoutOk = ChallengeService.cashout(fakePlayer :: any)
	check("최종 층 cashout이 cleared 게이트에서 막히지 않음 (재화 계층까지 도달)", cashoutOk == false and ChallengeService.getRunState(fakePlayer :: any) ~= nil)

	ChallengeService.abandonRun(fakePlayer :: any)
end

-- 6-4. 다음 월드가 있으면 같은 층에서 벽이 열린다 — 월드 2 더미를 주입해서 확인한다.
--      WorldConfig.Worlds는 모듈 캐시 하나를 공유하므로 주입이 곧 전역 변경이다.
--      다른 테스트 스크립트가 오염된 상태를 보지 않도록 pcall로 감싸고 반드시 되돌린다.

do
	local finalStage = 0
	for _, world in pairs(WorldConfig.Worlds) do
		finalStage = math.max(finalStage, world.stageRange[2])
	end
	local nextStage = finalStage + 1

	check("주입 전: 다음 층 없음", StageConfig.hasStage(nextStage) == false)

	WorldConfig.Worlds[2] = {
		id = 2,
		name = "테스트더미",
		material = "stone",
		stageRange = { nextStage, nextStage + 24 },
		hpBase = BigNum.new(1, 2),
		hpGrowthSegments = { { from = nextStage, to = nextStage + 24, growth = 3.0 } },
		bloxBase = BigNum.new(1, 0),
		bloxGrowthSegments = { { from = nextStage, to = nextStage + 24, growth = 2.7 } },
		eggPacks = { 1 },
		auraPacks = { 1 },
	} :: any

	local ok, err = pcall(function()
		check("주입 후: 다음 층 생김", StageConfig.hasStage(nextStage) == true)
		check("주입 후: 최종 층이 더 이상 최종이 아님", StageConfig.isFinalStage(finalStage) == false)

		local fakePlayer = { Name = "WorldTwoTestPlayer", UserId = 999997 }
		ChallengeService.startRun(fakePlayer :: any, finalStage)
		ChallengeService.applyDamage(fakePlayer :: any, Vector3.new(0, 0, 0), BigNum.new(1, 200))

		local before = ChallengeService.getRunState(fakePlayer :: any)
		check("월드2가 있으면 canAdvance == true (같은 층인데 벽이 열림)", before ~= nil and before.canAdvance == true)

		local advanceOk = ChallengeService.advance(fakePlayer :: any)
		check("월드2가 있으면 advance 성공 — 코드 수정 없이 벽이 열린다", advanceOk == true)

		local after = ChallengeService.getRunState(fakePlayer :: any)
		check("월드2 첫 층으로 넘어감", after ~= nil and after.stage == nextStage and after.cleared == false)

		ChallengeService.abandonRun(fakePlayer :: any)
	end)

	WorldConfig.Worlds[2] = nil -- 주입 해제. 실패했더라도 반드시 되돌린다

	check("더미 월드 제거됨 (다른 테스트에 새지 않음)", StageConfig.hasStage(nextStage) == false)
	if not ok then
		check("월드2 주입 테스트가 예외 없이 끝남", false, tostring(err))
	end
end

-- 7. source 인자 (Phase 4-2-a 선행) — 로깅·식별 목적이므로 동작은 하나도 안 바뀌어야 한다 ------
--
-- source는 반드시 선택 인자다. 위 1~6번(기존 케이스)이 전부 단일 인자로 호출하고 있고
-- 그대로 통과하는 것 자체가 하위 호환의 1차 증거지만, 여기서 같은 상황을 source 유무로
-- 나란히 굴려서 반환값·런 상태가 동일한지 직접 대조한다.
--
-- reason 문자열("challenge_cashout_" .. source)까지는 여기서 못 본다 — 가짜 Player에는
-- 프로필이 없어 CurrencyService가 그 앞에서 거부하기 때문이다. 그래서 reason에 들어가는
-- 조각인 normalizeSource를 순수 함수로 따로 검증한다.

do
	check("source가 nil이면 unknown", pure.normalizeSource(nil) == "unknown")
	check("source가 빈 문자열이어도 unknown (reason이 _로 끝나는 것 방지)", pure.normalizeSource("") == "unknown")
	check("source를 넘기면 그대로 쓴다", pure.normalizeSource("cashout_pad") == "cashout_pad")
end

do
	-- 7-1. 미클리어 거부 경로: source 유무로 반환값이 갈리지 않는다.
	local noSource = { Name = "SourceCompatPlayer", UserId = 999996 }
	local withSource = { Name = "SourceTaggedPlayer", UserId = 999995 }

	ChallengeService.startRun(noSource :: any, 1)
	ChallengeService.startRun(withSource :: any, 1)

	local advanceNo = ChallengeService.advance(noSource :: any)
	local advanceWith = ChallengeService.advance(withSource :: any, "auto_advance")
	check("미클리어 advance는 source 없이도 거부", advanceNo == false)
	check("미클리어 advance는 source를 넘겨도 똑같이 거부", advanceWith == advanceNo)

	local cashoutNo, rewardNo = ChallengeService.cashout(noSource :: any)
	local cashoutWith, rewardWith = ChallengeService.cashout(withSource :: any, "cashout_pad")
	check("미클리어 cashout은 source 없이도 거부", cashoutNo == false and rewardNo == nil)
	check("미클리어 cashout은 source를 넘겨도 똑같이 거부", cashoutWith == cashoutNo and rewardWith == rewardNo)

	local stateNo = ChallengeService.getRunState(noSource :: any)
	local stateWith = ChallengeService.getRunState(withSource :: any)
	check(
		"거부 후 런 상태가 source 유무와 무관하게 동일",
		stateNo ~= nil and stateWith ~= nil and stateNo.stage == stateWith.stage and stateNo.cleared == stateWith.cleared and stateNo.canAdvance == stateWith.canAdvance
	)

	ChallengeService.abandonRun(noSource :: any)
	ChallengeService.abandonRun(withSource :: any)
end

do
	-- 7-2. 성공 경로: source를 붙여도 층 전환 결과가 같다. 자동 진행 모드가 벽 없이
	--       직접 호출하게 될 경로를 미리 태워보는 것이기도 하다.
	local fakePlayer = { Name = "SourceAdvancePlayer", UserId = 999994 }

	ChallengeService.startRun(fakePlayer :: any, 1)
	ChallengeService.applyDamage(fakePlayer :: any, Vector3.new(0, 0, 0), BigNum.new(1, 200))

	local advanceOk = ChallengeService.advance(fakePlayer :: any, "auto_advance")
	check("클리어 후 advance는 source를 넘겨도 성공", advanceOk == true)

	local after = ChallengeService.getRunState(fakePlayer :: any)
	check("source를 넘겨도 다음 층으로 정상 전환 (stage=2, 미클리어)", after ~= nil and after.stage == 2 and after.cleared == false)
	check("보상은 새 스테이지 값으로 갱신 (source와 무관)", after ~= nil and BigNum.eq(after.reward, StageConfig.getBloxReward(2)))

	ChallengeService.abandonRun(fakePlayer :: any)
end

do
	-- 7-3. cashout의 "실패해도 런을 남긴다" 계약이 source를 붙여도 그대로인지.
	--       가짜 Player는 프로필이 없어 CurrencyService에서 막히므로 실패 경로가 재현된다.
	local fakePlayer = { Name = "SourceCashoutPlayer", UserId = 999993 }

	ChallengeService.startRun(fakePlayer :: any, 1)
	ChallengeService.applyDamage(fakePlayer :: any, Vector3.new(0, 0, 0), BigNum.new(1, 200))

	local cashoutOk, reward = ChallengeService.cashout(fakePlayer :: any, "cashout_pad")
	check("source를 붙인 cashout도 재화 계층에서 막힌다 (프로필 없음)", cashoutOk == false and reward == nil)

	local after = ChallengeService.getRunState(fakePlayer :: any)
	check("지급 실패해도 런은 클리어 상태로 남는다 (재시도 가능 계약 유지)", after ~= nil and after.stage == 1 and after.cleared == true)

	ChallengeService.abandonRun(fakePlayer :: any)
end

print(string.format("[ChallengeServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ChallengeServiceTests] %d test(s) failed", failed))
end

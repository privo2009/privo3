--!strict
-- WarpService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-e 검증: 거부 시 차감 0 / 차감이 런 시작보다 먼저 / 부분 실패 사유가 갈리는가.
--
-- WarpService._pure.runWarp에 **기록용 deps**를 넣어 검증한다. 실제 서비스를 태우지
-- 않는 이유는 Instance를 피하려는 것이 아니라, 실제 서비스로는 **볼 수 없기 때문**이다:
-- 가짜 Player 테이블이면 ProfileManager.get이 nil을 주므로 모든 경로가 "프로필 없음"
-- 한 갈래로 끝나고, 정작 확인해야 할 "거부됐을 때 차감이 일어나지 않았는가"와
-- "차감을 런 시작보다 먼저 했는가"가 전부 가려진다.
-- (RebirthServiceTests가 존재하는 이유와 같은 제약이다)
--
-- ⚠️ 마지막 층 번호를 이 파일에 적지 않는다. WarpConfigTests와 같은 이유다 —
-- 25를 적으면 월드 2가 추가될 때 경계 케이스가 조용히 엉뚱한 층을 보게 된다.
--
-- 여기서 다루지 않는 것: 실제 프로필 왕복과 RunStateChanged 발화. 그쪽은 Play 육안
-- 확인 몫이고 배선(Prompt 3) 이후에 본다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = ReplicatedStorage.Shared.Config
local StageConfig = require(Config.StageConfig)
local WarpConfig = require(Config.WarpConfig)
local WarpService = require(script.Parent.WarpService)

local pure = WarpService._pure

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

local fakePlayer = { Name = "TestPlayer", UserId = 1 } :: any

-- 현재 WorldConfig가 덮는 마지막 층. 숫자를 적지 않고 찾는다.
local LAST_STAGE = 1
while StageConfig.hasStage(LAST_STAGE + 1) do
	LAST_STAGE = LAST_STAGE + 1
end

local TARGET = 3
local TARGET_COST = WarpConfig.cost(TARGET)

-- ===== 기록용 세계 ====================================================================
--
-- 프로필 대신 쓰는 평범한 테이블. deps가 여기에 쓰고, 테스트는 전후를 대조한다.
type World = {
	blox: BigNum.BigNumber?,
	startedStage: number?,
	runActiveStage: number?,
	calls: { string },
	reasons: { string },
	failAt: string?,
}

local function newWorld(blox: BigNum.BigNumber?, runActiveStage: number?): World
	return {
		blox = blox,
		startedStage = nil,
		runActiveStage = runActiveStage,
		calls = {},
		reasons = {},
		failAt = nil,
	}
end

local function depsFor(w: World)
	return {
		getBlox = function(_player: Player)
			table.insert(w.calls, "getBlox")
			return w.blox
		end,

		subtractBlox = function(_player: Player, amount: BigNum.BigNumber, reason: string)
			table.insert(w.calls, "subtractBlox")
			table.insert(w.reasons, reason)
			if w.failAt == "subtractBlox" then
				return false
			end
			-- 실제 CurrencyService처럼 잔액 부족이면 거부하고 값을 건드리지 않는다.
			local current = w.blox
			if current == nil or BigNum.lt(current, amount) then
				return false
			end
			w.blox = BigNum.sub(current, amount)
			return true
		end,

		startRun = function(_player: Player, stage: number)
			table.insert(w.calls, "startRun")
			if w.failAt == "startRun" then
				error("테스트용 강제 오류: startRun")
			end
			-- 실제 ChallengeService.startRun처럼 기존 런을 조용히 덮어쓴다.
			w.startedStage = stage
			w.runActiveStage = stage
			return true
		end,
	}
end

-- 거부 케이스마다 반복되는 검사. 헬퍼로 묶은 이유는 "거부됐는데 차감됐다"가
-- 이 파일에서 가장 심각한 버그라 케이스별로 빠짐없이 확인해야 하기 때문이다.
--
-- ⚠️ 이 헬퍼는 check를 3번 부른다. 정적 세기와 실측이 어긋나는 원인이다
-- (ROADMAP 테스트 표의 RebirthServiceTests 각주와 같은 구조).
local function checkRejectedCleanly(label: string, w: World, before: BigNum.BigNumber?)
	if before == nil then
		check(string.format("%s — blox가 nil 그대로", label), w.blox == nil)
	else
		check(
			string.format("%s — blox가 차감되지 않았다", label),
			w.blox ~= nil and BigNum.eq(w.blox :: any, before),
			w.blox and BigNum.tostring(w.blox :: any) or "nil"
		)
	end

	check(string.format("%s — startRun이 불리지 않았다", label), w.startedStage == nil)
	check(string.format("%s — subtractBlox가 불리지 않았다", label), not table.find(w.calls, "subtractBlox"))
end

-- ===== 사유 코드 재공개 ================================================================

do
	-- ⚠️ 값을 문자열로 다시 적었는지 확인한다. 복사본이 되면 WarpConfig에서 값을 바꿔도
	-- Service가 옛 값을 계속 내보내고, 그때는 UI 매핑만 조용히 어긋난다.
	check("REASON_INVALID_STAGE가 WarpConfig와 같은 값", WarpService.REASON_INVALID_STAGE == WarpConfig.REASON_INVALID_STAGE)
	check("REASON_STAGE_OUT_OF_RANGE가 WarpConfig와 같은 값", WarpService.REASON_STAGE_OUT_OF_RANGE == WarpConfig.REASON_STAGE_OUT_OF_RANGE)
	check("REASON_INSUFFICIENT_BLOX가 WarpConfig와 같은 값", WarpService.REASON_INSUFFICIENT_BLOX == WarpConfig.REASON_INSUFFICIENT_BLOX)

	-- Service가 정의하는 셋은 순수 계층이 알 수 없는 것들이다.
	check("REASON_NO_PROFILE은 Service가 정의", WarpService.REASON_NO_PROFILE == "no_profile")
	check("REASON_SUBTRACT_FAILED는 Service가 정의", WarpService.REASON_SUBTRACT_FAILED == "subtract_failed")
	check("REASON_START_RUN_FAILED는 Service가 정의", WarpService.REASON_START_RUN_FAILED == "start_run_failed")

	-- 6개가 전부 다른 값이어야 UI가 상황을 구분할 수 있다.
	local seen: { [string]: boolean } = {}
	local unique = true
	for _, code in
		ipairs({
			WarpService.REASON_INVALID_STAGE,
			WarpService.REASON_STAGE_OUT_OF_RANGE,
			WarpService.REASON_INSUFFICIENT_BLOX,
			WarpService.REASON_NO_PROFILE,
			WarpService.REASON_SUBTRACT_FAILED,
			WarpService.REASON_START_RUN_FAILED,
		})
	do
		if seen[code] then
			unique = false
		end
		seen[code] = true
	end
	check("사유 코드 6개가 서로 다르다", unique)
end

-- ===== 정상 워프 ======================================================================

do
	local start = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))
	local w = newWorld(start)

	local ok, result = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("정상 워프 — 성공", ok == true, tostring(result))
	check(
		"정상 워프 — 두 번째 반환값이 차감된 비용",
		ok and type(result) == "table" and BigNum.eq(result, TARGET_COST),
		ok and BigNum.tostring(result) or tostring(result)
	)
	check(
		"정상 워프 — blox가 정확히 비용만큼 줄었다",
		BigNum.eq(w.blox :: any, BigNum.sub(start, TARGET_COST)),
		BigNum.tostring(w.blox :: any)
	)
	check("정상 워프 — 런이 목표 stage로 시작됐다", w.startedStage == TARGET, tostring(w.startedStage))
end

do
	-- ⚠️ 순서가 계약이다. 런을 먼저 시작하고 차감이 실패하면 공짜 워프가 된다.
	local w = newWorld(BigNum.mul(TARGET_COST, BigNum.fromNumber(10)))
	pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	local subtractAt = table.find(w.calls, "subtractBlox")
	local startAt = table.find(w.calls, "startRun")
	check(
		"차감이 런 시작보다 먼저다",
		subtractAt ~= nil and startAt ~= nil and (subtractAt :: number) < (startAt :: number),
		table.concat(w.calls, " -> ")
	)
end

do
	-- 경계: 비용과 정확히 같은 잔액이면 통과하고 잔액이 0이 된다.
	local w = newWorld(BigNum.new(TARGET_COST.m, TARGET_COST.e))
	local ok = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("비용과 정확히 같은 blox — 통과", ok == true)
	check("비용과 정확히 같은 blox — 잔액이 0", BigNum.eq(w.blox :: any, BigNum.new(0, 0)), BigNum.tostring(w.blox :: any))
end

do
	-- source 정규화. RebirthService·ChallengeService와 같은 규칙이다.
	check("normalizeSource — 정상 문자열은 그대로", pure.normalizeSource("pad") == "pad")
	check("normalizeSource — nil은 unknown", pure.normalizeSource(nil) == "unknown")
	check("normalizeSource — 빈 문자열도 unknown", pure.normalizeSource("") == "unknown")

	local w = newWorld(BigNum.mul(TARGET_COST, BigNum.fromNumber(10)))
	pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, nil)
	check("차감 reason이 warp_unknown으로 접힌다", w.reasons[1] == "warp_unknown", tostring(w.reasons[1]))
end

-- ===== 거부 — 부작용 0이어야 한다 =====================================================

do
	-- ⚠️ 이 파일에서 가장 중요한 묶음이다. 거부됐는데 차감됐으면 유저 블럭스가
	-- 아무 일 없이 사라진다.
	local rich = BigNum.new(1, 300)

	local invalidCases: { { label: string, stage: any } } = {
		{ label = "0층", stage = 0 },
		{ label = "음수", stage = -5 },
		{ label = "소수", stage = 1.5 },
		{ label = "nil", stage = nil },
		{ label = "문자열", stage = "3" },
	}

	for _, case in ipairs(invalidCases) do
		local w = newWorld(BigNum.new(rich.m, rich.e))
		local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, case.stage :: any, "test")

		check(
			string.format("%s → INVALID_STAGE", case.label),
			ok == false and reason == WarpService.REASON_INVALID_STAGE,
			tostring(reason)
		)
		checkRejectedCleanly(string.format("INVALID_STAGE(%s)", case.label), w, rich)
	end
end

do
	local rich = BigNum.new(1, 300)
	local w = newWorld(BigNum.new(rich.m, rich.e))

	local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, LAST_STAGE + 1, "test")

	check(
		string.format("마지막 층 + 1(%d) → STAGE_OUT_OF_RANGE", LAST_STAGE + 1),
		ok == false and reason == WarpService.REASON_STAGE_OUT_OF_RANGE,
		tostring(reason)
	)
	checkRejectedCleanly("STAGE_OUT_OF_RANGE", w, rich)
end

do
	-- 비용보다 1 적은 잔액. ⚠️ 낮은 층에서만 본다 — 비용이 커지면 sub(cost, 1)이
	-- 유효자리 12에 먹혀 원래 값과 같아지고, 그러면 통과가 정답이 되어 케이스가
	-- 의미를 잃는다 (WarpConfigTests의 같은 케이스와 동일한 이유).
	local cost1 = WarpConfig.cost(1)
	local justBelow = BigNum.sub(cost1, BigNum.fromNumber(1))
	local w = newWorld(BigNum.new(justBelow.m, justBelow.e))

	local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, 1, "test")

	check(
		"비용보다 1 적은 blox → INSUFFICIENT_BLOX",
		ok == false and reason == WarpService.REASON_INSUFFICIENT_BLOX,
		tostring(reason)
	)
	checkRejectedCleanly("INSUFFICIENT_BLOX", w, justBelow)
end

do
	local w = newWorld(BigNum.new(0, 0))
	local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("blox 0 → INSUFFICIENT_BLOX", ok == false and reason == WarpService.REASON_INSUFFICIENT_BLOX, tostring(reason))
	checkRejectedCleanly("blox 0", w, BigNum.new(0, 0))
end

do
	-- 프로필 없음. ⚠️ 목표층 검증보다 먼저 갈려야 한다 — 순서를 뒤집으면
	-- "프로필이 없는데 INVALID_STAGE"라는 엉뚱한 사유가 나온다.
	local w = newWorld(nil)
	local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("프로필 없음 → NO_PROFILE", ok == false and reason == WarpService.REASON_NO_PROFILE, tostring(reason))
	checkRejectedCleanly("NO_PROFILE", w, nil)

	local badStage = newWorld(nil)
	local badOk, badReason = pure.runWarp(depsFor(badStage) :: any, fakePlayer, -1, "test")
	check(
		"프로필 없음이 INVALID_STAGE보다 먼저 갈린다",
		badOk == false and badReason == WarpService.REASON_NO_PROFILE,
		tostring(badReason)
	)
end

-- ===== 부분 실패 — 셋이 갈려야 한다 ===================================================

do
	-- canWarp을 통과했는데 차감이 거부된 경우. 부작용은 없지만 정상 경로에도 없다.
	local start = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))
	local w = newWorld(BigNum.new(start.m, start.e))
	w.failAt = "subtractBlox"

	local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("차감 거부 → SUBTRACT_FAILED", ok == false and reason == WarpService.REASON_SUBTRACT_FAILED, tostring(reason))
	check(
		"차감 거부 — blox가 그대로다 (부작용 0)",
		BigNum.eq(w.blox :: any, start),
		BigNum.tostring(w.blox :: any)
	)
	check("차감 거부 — startRun이 불리지 않았다", w.startedStage == nil)

	-- ⚠️ INSUFFICIENT_BLOX로 접히면 안 된다. 유저 화면엔 충분한 값이 보이는데
	-- "블럭스가 부족합니다"가 뜨는 거짓 안내가 된다.
	check("차감 거부는 INSUFFICIENT_BLOX가 아니다", reason ~= WarpService.REASON_INSUFFICIENT_BLOX)
end

do
	-- ⚠️ 두 번째로 중요한 케이스다. 차감은 끝났는데 런이 안 섰다 —
	-- **되돌리지 않는 것이 기대 동작이다.** blox는 사라진 채로 남는다.
	local start = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))
	local w = newWorld(BigNum.new(start.m, start.e))
	w.failAt = "startRun"

	local ok, reason = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("startRun 오류 → START_RUN_FAILED", ok == false and reason == WarpService.REASON_START_RUN_FAILED, tostring(reason))
	check(
		"startRun 오류 — blox는 차감된 채로 남는다 (되돌리지 않는다)",
		BigNum.eq(w.blox :: any, BigNum.sub(start, TARGET_COST)),
		BigNum.tostring(w.blox :: any)
	)
	check("startRun 오류 — 런은 시작되지 않았다", w.startedStage == nil)
	check("startRun 오류 — error가 밖으로 새지 않는다 (pcall로 접힌다)", type(reason) == "string")
end

do
	-- 세 갈래의 사유가 실제로 다른지 한 자리에서 대조한다. 호출자가 이 셋을 같은
	-- "실패"로 뭉뚱그리면, blox가 사라진 유저에게 "워프하지 못했습니다"를 띄우게 된다.
	--
	-- ⚠️ 잔액을 1e300 같은 큰 값으로 잡지 말 것. 아래에서 "차감된 쪽만 줄었다"를 보는데,
	-- 지수 차가 13을 넘으면 sub 결과가 원래 값과 같아져(유효자리 12 — CLAUDE.md 정밀도
	-- 계약) 줄어든 것을 관측할 수 없다. 비용과 같은 자릿수로 잡는다.
	local rich = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))

	local plain = newWorld(BigNum.new(rich.m, rich.e))
	local _, plainReason = pure.runWarp(depsFor(plain) :: any, fakePlayer, LAST_STAGE + 1, "test")

	local noSub = newWorld(BigNum.new(rich.m, rich.e))
	noSub.failAt = "subtractBlox"
	local _, noSubReason = pure.runWarp(depsFor(noSub) :: any, fakePlayer, TARGET, "test")

	local broken = newWorld(BigNum.new(rich.m, rich.e))
	broken.failAt = "startRun"
	local _, brokenReason = pure.runWarp(depsFor(broken) :: any, fakePlayer, TARGET, "test")

	check(
		"정상 거부 · 차감 거부 · 부분 실패의 사유가 전부 다르다",
		plainReason ~= noSubReason and noSubReason ~= brokenReason and plainReason ~= brokenReason,
		string.format("%s / %s / %s", tostring(plainReason), tostring(noSubReason), tostring(brokenReason))
	)
	check(
		"부작용이 있는 쪽만 blox가 줄었다",
		BigNum.eq(plain.blox :: any, rich)
			and BigNum.eq(noSub.blox :: any, rich)
			and BigNum.lt(broken.blox :: any, rich)
	)
end

-- ===== 이미 런이 진행 중일 때 =========================================================

do
	-- ⚠️ 덮어쓰기가 **정상 동작이다.** 거부되지 않는다 —
	-- ChallengeService.startRun이 기존 런을 조용히 덮어쓰기 때문이고,
	-- 워프는 "지금 어디에 있든 목표 층으로 간다"이므로 그것이 곧 기능이다.
	local start = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))
	local w = newWorld(BigNum.new(start.m, start.e), 7) -- 7층 런이 진행 중

	local ok, result = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("진행 중인 런이 있어도 워프는 거부되지 않는다", ok == true, tostring(result))
	check("진행 중이던 런이 목표 stage로 덮어써졌다", w.runActiveStage == TARGET, tostring(w.runActiveStage))
	check("덮어쓸 때도 비용은 정상 차감된다", BigNum.eq(w.blox :: any, BigNum.sub(start, TARGET_COST)))

	-- abandonRun을 따로 부르지 않는다 — 덮어쓰기가 이미 그 일을 한다.
	check("abandonRun을 따로 부르지 않는다", not table.find(w.calls, "abandonRun"), table.concat(w.calls, " -> "))
end

do
	-- 같은 층으로 워프해도 거부되지 않는다. 비용은 그대로 나간다 (전 구간 유료).
	local start = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))
	local w = newWorld(BigNum.new(start.m, start.e), TARGET)

	local ok = pure.runWarp(depsFor(w) :: any, fakePlayer, TARGET, "test")

	check("현재와 같은 층으로 워프해도 거부되지 않는다", ok == true)
	check("같은 층 워프도 비용을 낸다 (전 구간 유료)", BigNum.eq(w.blox :: any, BigNum.sub(start, TARGET_COST)))
end

-- ===== 진행 상태 비참조 ===============================================================

do
	-- 워프는 진행 상태를 참조하지 않는다 (DESIGN.md "블럭스 소비처").
	-- deps에 maxStage도 현재 층도 없다는 것이 구조적 증거지만, 비용이 실제로
	-- 현재 위치와 무관한지 한 번 더 본다.
	-- ⚠️ 잔액은 비용과 같은 자릿수로 잡는다. 큰 값으로 두면 차감이 정밀도에 먹혀
	-- 양쪽 다 "안 줄어든" 상태로 같아지고, 그러면 이 케이스가 아무것도 확인하지 못한다.
	local start = BigNum.mul(TARGET_COST, BigNum.fromNumber(10))

	local fromLow = newWorld(BigNum.new(start.m, start.e), 1)
	pure.runWarp(depsFor(fromLow) :: any, fakePlayer, TARGET, "test")

	local fromHigh = newWorld(BigNum.new(start.m, start.e), LAST_STAGE)
	pure.runWarp(depsFor(fromHigh) :: any, fakePlayer, TARGET, "test")

	check(
		"비용이 현재 위치와 무관하다 (절대 기준)",
		BigNum.eq(fromLow.blox :: any, fromHigh.blox :: any),
		string.format("%s vs %s", BigNum.tostring(fromLow.blox :: any), BigNum.tostring(fromHigh.blox :: any))
	)
	-- 위 케이스가 "둘 다 안 줄었다"로 통과하는 것을 막는다.
	check(
		"두 경우 모두 실제로 비용이 빠져나갔다",
		BigNum.eq(fromLow.blox :: any, BigNum.sub(start, TARGET_COST)),
		BigNum.tostring(fromLow.blox :: any)
	)
end

print(string.format("[WarpServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[WarpServiceTests] %d test(s) failed", failed))
end

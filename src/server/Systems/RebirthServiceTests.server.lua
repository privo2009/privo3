--!strict
-- RebirthService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-d 검증: 거부 시 부작용 0 / 전액 소모 / 배수 가산 / 순서 / source 정규화.
--
-- RebirthService._pure.runRebirth에 **기록용 deps**를 넣어 검증한다. 실제 서비스를 태우지
-- 않는 이유는 Instance를 피하려는 것이 아니라, 실제 서비스로는 **볼 수 없기 때문**이다:
-- 가짜 Player 테이블이면 ProfileManager.get이 nil을 주므로 모든 경로가 "프로필 없음"
-- 한 갈래로 끝나고, 정작 확인해야 할 "거부됐을 때 아무것도 안 건드렸는가"와
-- "힘을 되돌린 뒤에 속도를 재적용했는가"가 전부 가려진다.
-- (Bootstrap의 VERIFY_CHALLENGE 블록이 존재하는 이유와 같은 제약이다)
--
-- 여기서 다루지 않는 것: 실제 프로필 왕복과 Humanoid 반영. 그쪽은 Play 육안 확인 몫이고
-- Bootstrap 배선(Prompt 3) 이후에 본다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local Schema = require(script.Parent.Parent.Data.Schema)
local RebirthService = require(script.Parent.RebirthService)

local pure = RebirthService._pure

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

local COST = RebirthConfig.BLOX_PER_REBIRTH
local TEMPLATE_STRENGTH = Schema.new().strength
local TEMPLATE_MAX_STAGE = Schema.new().progress.maxStage

-- ===== 기록용 세계 ====================================================================
--
-- 프로필 대신 쓰는 평범한 테이블. deps가 여기에 쓰고, 테스트는 전후를 대조한다.
-- ⚠️ 환생 전 값을 전부 "시작 상태와 다른 값"으로 둔다. 시작값과 같게 두면
-- "되돌렸다"와 "원래 그랬다"가 구분되지 않는다.
type World = {
	blox: BigNum.BigNumber?,
	strength: BigNum.BigNumber,
	rebirths: BigNum.BigNumber,
	lifetimeBlox: BigNum.BigNumber,
	maxStage: number,
	currentWorld: number,
	unlockedWorlds: number,
	runActive: boolean,
	calls: { string },
	strengthSeenBySpeed: BigNum.BigNumber?,
	failAt: string?,
}

local function newWorld(blox: BigNum.BigNumber?): World
	return {
		blox = blox,
		strength = BigNum.new(7, 12), -- 7e12. 시작값(1)과 확실히 다르다
		rebirths = BigNum.new(0, 0),
		lifetimeBlox = BigNum.new(4, 9), -- 4e9. 환생 전후로 변하면 안 된다
		maxStage = 17,
		currentWorld = 2,
		unlockedWorlds = 3,
		runActive = true,
		calls = {},
		strengthSeenBySpeed = nil,
		failAt = nil,
	}
end

local function depsFor(w: World)
	local function record(name: string)
		table.insert(w.calls, name)
	end

	return {
		getBlox = function(_p: any)
			record("getBlox")
			return w.blox
		end,
		abandonRun = function(_p: any)
			record("abandonRun")
			w.runActive = false
			return true
		end,
		setBlox = function(_p: any, amount: BigNum.BigNumber, _reason: string)
			record("setBlox")
			if w.failAt == "setBlox" then
				return false
			end
			w.blox = amount
			return true
		end,
		addRebirths = function(_p: any, amount: BigNum.BigNumber, _reason: string)
			record("addRebirths")
			if w.failAt == "addRebirths" then
				return false, nil
			end
			w.rebirths = BigNum.add(w.rebirths, amount)
			return true, w.rebirths
		end,
		setStrength = function(_p: any, amount: BigNum.BigNumber, _reason: string)
			record("setStrength")
			if w.failAt == "setStrength" then
				return false
			end
			w.strength = amount
			return true
		end,
		resetMaxStage = function(_p: any)
			record("resetMaxStage")
			w.maxStage = TEMPLATE_MAX_STAGE
			return true
		end,
		resetCurrentWorld = function(_p: any)
			record("resetCurrentWorld")
			w.currentWorld = 1
			return true
		end,
		startRun = function(_p: any)
			record("startRun")
			w.runActive = true
			return true
		end,
		-- ⚠️ 이 시점의 힘을 그대로 기록해 둔다. 순서 검증의 핵심이다 —
		-- 실제 SpeedService.onRebirth도 힘을 "그 시점에" 다시 읽어 최대치를 계산한다.
		onRebirth = function(_p: any)
			record("onRebirth")
			w.strengthSeenBySpeed = w.strength
			return 16
		end,
	}
end

-- calls 안에서 name의 위치(1-based). 없으면 0.
local function indexOf(calls: { string }, name: string): number
	for i, v in ipairs(calls) do
		if v == name then
			return i
		end
	end
	return 0
end

-- ===== 1. source 정규화 ===============================================================

check("source nil은 unknown으로 접힌다", pure.normalizeSource(nil) == "unknown")
check("source 빈 문자열도 unknown으로 접힌다", pure.normalizeSource("") == "unknown")
check("정상 source는 그대로", pure.normalizeSource("rebirth_button") == "rebirth_button")

do
	-- reason 문자열이 실제로 CurrencyService까지 전달되는지. 빈 source가 "rebirth_"로
	-- 끝나는 반쪽 reason을 만들면 CurrencyService의 assert는 통과하면서 로그만 망가진다.
	local seen: string? = nil
	local w = newWorld(BigNum.fromNumber(COST))
	local deps = depsFor(w)
	deps.setBlox = function(_p: any, amount: BigNum.BigNumber, reason: string)
		seen = reason
		w.blox = amount
		return true
	end

	pure.runRebirth(deps :: any, fakePlayer, nil)
	check("nil source가 reason에 unknown으로 실린다", seen == "rebirth_unknown", tostring(seen))

	seen = nil
	local w2 = newWorld(BigNum.fromNumber(COST))
	local deps2 = depsFor(w2)
	deps2.setBlox = function(_p: any, amount: BigNum.BigNumber, reason: string)
		seen = reason
		w2.blox = amount
		return true
	end
	pure.runRebirth(deps2 :: any, fakePlayer, "rebirth_pad")
	check("정상 source가 reason에 그대로 실린다", seen == "rebirth_rebirth_pad", tostring(seen))
end

-- ===== 2. 거부 — 부작용이 0이어야 한다 ================================================
--
-- ⚠️ 이 절이 이 파일에서 제일 중요하다. 거부가 런을 없애거나 값을 건드리면
-- "버튼을 잘못 눌렀는데 진행 중이던 런이 날아갔다"가 된다.

local function checkUntouched(label: string, w: World, expectedBlox: BigNum.BigNumber?)
	check(label .. ": 런이 살아 있다", w.runActive == true)
	check(label .. ": blox 그대로", expectedBlox == nil or BigNum.eq(w.blox :: any, expectedBlox))
	check(label .. ": strength 그대로", BigNum.eq(w.strength, BigNum.new(7, 12)))
	check(label .. ": rebirths 그대로", BigNum.eq(w.rebirths, BigNum.new(0, 0)))
	check(label .. ": maxStage 그대로", w.maxStage == 17, tostring(w.maxStage))
	check(label .. ": currentWorld 그대로", w.currentWorld == 2, tostring(w.currentWorld))
	check(
		label .. ": getBlox 말고는 아무것도 부르지 않았다",
		#w.calls == 1 and w.calls[1] == "getBlox",
		table.concat(w.calls, ",")
	)
end

do
	local w = newWorld(BigNum.new(0, 0))
	local ok, reason = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")
	check("blox 0이면 거부", ok == false and reason == RebirthService.REASON_NOT_ENOUGH_BLOX, tostring(reason))
	checkUntouched("blox 0", w, BigNum.new(0, 0))
end

do
	local justBelow = BigNum.fromNumber(COST - 1)
	local w = newWorld(justBelow)
	local ok, reason = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")
	check("비용보다 1 적으면 거부", ok == false and reason == RebirthService.REASON_NOT_ENOUGH_BLOX, tostring(reason))
	checkUntouched("비용-1", w, justBelow)
end

do
	local w = newWorld(nil) -- getBlox가 nil = 프로필 없음
	local ok, reason = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")
	check("프로필이 없으면 no_profile", ok == false and reason == RebirthService.REASON_NO_PROFILE, tostring(reason))
	checkUntouched("프로필 없음", w, nil)
end

-- ===== 3. 성공 =========================================================================

do
	-- 비용의 2배 직전. 나머지는 버려지고 배수는 1이어야 한다.
	local w = newWorld(BigNum.fromNumber(COST * 2 - 1))
	local ok, result = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")

	check("성공하면 true", ok == true)
	check("gained == 1 (나머지는 버림)", ok and BigNum.eq(result.gained, BigNum.fromNumber(1)), ok and BigNum.tostring(result.gained) or tostring(result))
	check("total == 1 (0에서 시작)", ok and BigNum.eq(result.total, BigNum.fromNumber(1)))
	check("blox가 0이 됐다", BigNum.eq(w.blox :: any, BigNum.new(0, 0)), BigNum.tostring(w.blox :: any))
	check("strength가 템플릿 값으로 돌아갔다", BigNum.eq(w.strength, TEMPLATE_STRENGTH), BigNum.tostring(w.strength))
	check("rebirths가 1이 됐다", BigNum.eq(w.rebirths, BigNum.fromNumber(1)))
	check("maxStage가 템플릿 값으로 돌아갔다", w.maxStage == TEMPLATE_MAX_STAGE, tostring(w.maxStage))
	check("currentWorld가 1로 돌아갔다", w.currentWorld == 1, tostring(w.currentWorld))
	check("unlockedWorlds는 유지된다 (영구 진행)", w.unlockedWorlds == 3, tostring(w.unlockedWorlds))
	check("런이 다시 서 있다 (1층 재시작)", w.runActive == true)
end

do
	-- lifetimeBlox 불변. deps에 이걸 건드릴 통로 자체가 없다는 것이 확인 대상이다.
	-- ⚠️ 진짜 보장은 CurrencyService.applyAdd의 `currency == "blox"` 분기에 있고
	-- CurrencyServiceTests가 그쪽을 잰다. 여기서는 환생 흐름이 우회로를 만들지 않았는지 본다.
	local w = newWorld(BigNum.fromNumber(COST * 5))
	local before = w.lifetimeBlox
	pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")
	check("lifetimeBlox가 환생 전후로 불변", BigNum.eq(w.lifetimeBlox, before), BigNum.tostring(w.lifetimeBlox))
end

-- ===== 4. 누적 (덮어쓰기가 아니다) =====================================================

do
	local w = newWorld(BigNum.fromNumber(COST * 3))
	local ok1, r1 = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")
	check("1회차: gained 3", ok1 and BigNum.eq(r1.gained, BigNum.fromNumber(3)))
	check("1회차: total 3", ok1 and BigNum.eq(r1.total, BigNum.fromNumber(3)))

	-- 다시 벌었다고 치고 2회차.
	w.blox = BigNum.fromNumber(COST * 2)
	local ok2, r2 = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")
	check("2회차: gained 2 (이번 회차분만)", ok2 and BigNum.eq(r2.gained, BigNum.fromNumber(2)))
	check("2회차: total 5 (3 + 2, 가산이다)", ok2 and BigNum.eq(r2.total, BigNum.fromNumber(5)), ok2 and BigNum.tostring(r2.total) or "")
	check("2회차 후 rebirths == 5 (덮어쓰기였다면 2)", BigNum.eq(w.rebirths, BigNum.fromNumber(5)), BigNum.tostring(w.rebirths))
end

-- ===== 5. 순서 ========================================================================

do
	local w = newWorld(BigNum.fromNumber(COST))
	pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")

	local iAbandon = indexOf(w.calls, "abandonRun")
	local iSetBlox = indexOf(w.calls, "setBlox")
	local iAddReb = indexOf(w.calls, "addRebirths")
	local iSetStr = indexOf(w.calls, "setStrength")
	local iStart = indexOf(w.calls, "startRun")
	local iSpeed = indexOf(w.calls, "onRebirth")
	local order = table.concat(w.calls, " -> ")

	-- 9개다. 순서 목록의 2번(판정)은 순수 계산이라 바깥 세계를 부르지 않는다.
	check("바깥 세계 호출이 9개 전부 났다", #w.calls == 9, order)
	check("런 소멸이 재화 조작보다 먼저다", iAbandon > 0 and iAbandon < iSetBlox, order)
	check("blox 소모가 배수 가산보다 먼저다", iSetBlox < iAddReb, order)
	check("1층 재시작이 진행도 되돌리기보다 뒤다", iStart > indexOf(w.calls, "resetMaxStage"), order)

	-- ⚠️ 이 두 줄이 4-2-d에서 제일 자주 어긋나는 지점이다.
	check("속도 재적용이 힘 초기화보다 뒤다", iSetStr > 0 and iSpeed > iSetStr, order)
	check(
		"속도 재적용이 **초기화된** 힘을 본다 (먼저 불렸다면 7e12를 봤을 것)",
		w.strengthSeenBySpeed ~= nil and BigNum.eq(w.strengthSeenBySpeed :: any, TEMPLATE_STRENGTH),
		w.strengthSeenBySpeed and BigNum.tostring(w.strengthSeenBySpeed) or "nil"
	)
end

-- ===== 6. 부분 실패 — 정상 거부와 사유 코드가 갈려야 한다 ==============================
--
-- 정상 경로에서는 나오지 않는다(프로필이 손상된 경우뿐). 그래도 재는 이유가 둘 있다:
--
--   1. 실패했을 때 **어느 방향으로 망가지는지**가 설계 결정이다 (유저 손해 < 게임 파괴)
--   2. ⚠️ 사유 코드가 정상 거부와 **갈려야 한다.** 3단계(런 소멸) 이후의 실패는 부작용이
--      이미 났으므로, 이걸 not_enough_blox와 같은 "실패"로 뭉뚱그리면 UI가 블럭스가
--      사라진 유저에게 "환생하지 못했습니다"를 띄운다. 거짓 안내다.
--
-- 아래 마지막 케이스가 그 대조다. 둘이 같은 값이 되는 순간 실패해야 한다.

do
	local w = newWorld(BigNum.fromNumber(COST))
	w.failAt = "setBlox"
	local ok, reason = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")

	check("4단계 실패는 partial_failure", ok == false and reason == RebirthService.REASON_PARTIAL_FAILURE, tostring(reason))
	check("4단계 실패 후 배수는 오르지 않는다", BigNum.eq(w.rebirths, BigNum.new(0, 0)))
	check("4단계 실패 후 힘도 그대로", BigNum.eq(w.strength, BigNum.new(7, 12)))
	check("4단계 실패 시 뒤 단계를 부르지 않는다", indexOf(w.calls, "addRebirths") == 0, table.concat(w.calls, ","))
	-- 부작용이 0이 아니다 — 런은 이미 사라졌다. 이 케이스가 partial인 이유가 그것이다.
	check("4단계 실패여도 런은 이미 사라진 상태다", w.runActive == false)
end

do
	local w = newWorld(BigNum.fromNumber(COST))
	w.failAt = "addRebirths"
	local ok, reason = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")

	check("5단계 실패는 partial_failure", ok == false and reason == RebirthService.REASON_PARTIAL_FAILURE, tostring(reason))
	check("5단계 실패 시 힘 초기화까지 가지 않는다", indexOf(w.calls, "setStrength") == 0, table.concat(w.calls, ","))
	check(
		"5단계 실패 방향: 블럭스만 사라진다 (배수가 먼저 올라 무한 환생이 되지 않는다)",
		BigNum.eq(w.blox :: any, BigNum.new(0, 0)) and BigNum.eq(w.rebirths, BigNum.new(0, 0))
	)
end

do
	local w = newWorld(BigNum.fromNumber(COST))
	w.failAt = "setStrength"
	local ok, reason = pure.runRebirth(depsFor(w) :: any, fakePlayer, "test")

	check("6단계 실패도 partial_failure", ok == false and reason == RebirthService.REASON_PARTIAL_FAILURE, tostring(reason))
	check("6단계 실패 시 진행도 되돌리기까지 가지 않는다", indexOf(w.calls, "resetMaxStage") == 0, table.concat(w.calls, ","))
	check(
		"6단계 실패 상태: 블럭스는 소각됐고 배수는 올랐는데 힘만 안 돌아갔다",
		BigNum.eq(w.blox :: any, BigNum.new(0, 0))
			and BigNum.eq(w.rebirths, BigNum.fromNumber(1))
			and BigNum.eq(w.strength, BigNum.new(7, 12))
	)
end

do
	-- ⚠️ 이 파일에서 두 번째로 중요한 케이스다. 부작용 유무를 호출자가 구분할 수 없으면
	-- UI가 거짓 안내를 한다. 사유 코드가 실제로 갈리는지 한 자리에서 대조한다.
	local rejected = newWorld(BigNum.fromNumber(COST - 1))
	local _, rejectReason = pure.runRebirth(depsFor(rejected) :: any, fakePlayer, "test")

	local broken = newWorld(BigNum.fromNumber(COST))
	broken.failAt = "setBlox"
	local _, brokenReason = pure.runRebirth(depsFor(broken) :: any, fakePlayer, "test")

	check(
		"부작용 0인 거부와 부작용 있는 실패의 사유 코드가 다르다",
		rejectReason ~= brokenReason,
		string.format("%s vs %s", tostring(rejectReason), tostring(brokenReason))
	)
	check("부작용 0인 쪽은 not_enough_blox 그대로", rejectReason == RebirthService.REASON_NOT_ENOUGH_BLOX, tostring(rejectReason))
	check("부작용 있는 쪽만 partial_failure", brokenReason == RebirthService.REASON_PARTIAL_FAILURE, tostring(brokenReason))
	check("부작용 0인 쪽은 런이 살아 있고, 있는 쪽은 사라졌다", rejected.runActive == true and broken.runActive == false)
end

print(string.format("[RebirthServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RebirthServiceTests] %d test(s) failed", failed))
end

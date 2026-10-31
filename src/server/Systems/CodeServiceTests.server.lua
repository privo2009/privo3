--!strict
-- 코드 입력 검증 (지시서 #20 단계 5 — C1 ~ C6). CodesConfig(정리 · 표) · CodeService 런타임(가짜 시계 · 가짜 코드 표) ·
-- RewardService 런타임(가짜 deps)을 이어 붙인다. 실제 프로필을 건드리지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local CodesConfig = require(ReplicatedStorage.Shared.Config.CodesConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local CodeService = require(script.Parent.CodeService)
local RewardService = require(script.Parent.RewardService)
local Schema = require(script.Parent.Parent.Data.Schema)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local A: any = { Name = "A", UserId = 1 }
local NOW = 1_800_000_000

-- 가짜 코드 표: Config의 RELEASE + 만료된 것 · 아직인 것 · 펫 주는 것
local CODES: any = {
	RELEASE = CodesConfig.Codes.RELEASE,
	OLD = { rewards = { { type = "potion", kind = "damage", count = 1 } }, expiresAt = NOW - 1 },
	SOON = { rewards = { { type = "bloxScaled", k = 1 } }, expiresAt = NOW + 100 },
	PETCODE = { rewards = { { type = "pet", petId = PetConfig.Eggs[1].pets[1].id } }, expiresAt = nil },
}

local function world(room: number?)
	local w: any = { sent = {}, adds = {} }
	w.data = Schema.new() :: any
	w.reward = RewardService._pure.createRuntime({
		getData = function()
			return w.data
		end,
		addBlox = function(_, amount)
			table.insert(w.adds, amount)
			return true
		end,
		petRoom = function()
			return room or 10
		end,
		grantPet = function()
			return true
		end,
		notify = function() end,
		log = function() end,
	})
	w.rt = CodeService._pure.createRuntime({
		codes = CODES,
		now = function()
			return NOW
		end,
		getData = function()
			return w.data
		end,
		grant = function(p, rewards, src)
			return w.reward.grant(p, rewards, src)
		end,
		send = function(_, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w
end

-- 1. 정리(C1) ----------------------------------------------------------------------------------------------
check("정리: 앞뒤 공백 지움 · 대문자(대소문자 무시)", CodesConfig.normalize("  release\t") == "RELEASE" and CodesConfig.normalize("ReLeAsE") == "RELEASE"
	and CodesConfig.normalize("\nRELEASE \n") == "RELEASE")
check("정리: 빈 문자열 · 공백만 · 너무 긴 문자열 · 문자열 아님 → nil", CodesConfig.normalize("") == nil and CodesConfig.normalize("   ") == nil
	and CodesConfig.normalize(string.rep("A", CodesConfig.MAX_LENGTH + 1)) == nil and CodesConfig.normalize(string.rep("A", 10000)) == nil
	and CodesConfig.normalize(123) == nil and CodesConfig.normalize({}) == nil and CodesConfig.normalize(nil) == nil)
check("정리: 길이 상한까지는 받는다 · 가운데 공백은 그대로(없는 코드가 된다)", CodesConfig.normalize(string.rep("a", CodesConfig.MAX_LENGTH))
	== string.rep("A", CodesConfig.MAX_LENGTH) and CodesConfig.normalize("RE LEASE") == "RE LEASE")
check("CodesConfig.validate · MAX_LENGTH = Schema.LIMITS.MAX_CODE_LENGTH · RELEASE(TEMP) = 힘 포션 2 + 데미지 포션 2",
	CodesConfig.validate() and CodesConfig.MAX_LENGTH == Schema.LIMITS.MAX_CODE_LENGTH and (function()
		local r = CodesConfig.Codes.RELEASE.rewards
		return #r == 2 and r[1].kind == "strength" and r[1].count == 2 and r[2].kind == "damage" and r[2].count == 2
			and CodesConfig.Codes.RELEASE.expiresAt == nil
	end)())

-- 2. 판정 ---------------------------------------------------------------------------------------------
do
	local w = world()
	local out, code = w.rt.onRequest(A, { code = "  release " }, 1)
	check("성공: 소문자 · 공백 입력도 RELEASE → 포션 2 + 2 · 기록 남음 · 결과 보상 2칸", out.ok and out.reason == "" and code == "RELEASE"
		and w.data.potions.strength == 2 and w.data.potions.damage == 2 and w.data.redeemedCodes.RELEASE == true and #out.rewards == 2
		and out.rewards[1].kind == "strength" and out.rewards[1].count == 2 and out.rewards[1].petId == "" and #w.sent == 1)
	check("결과에 입력 글자를 싣지 않는다(C4 — 필드는 ok · reason · rewards · blox뿐)", (function()
		for key in pairs(out) do
			if key ~= "ok" and key ~= "reason" and key ~= "rewards" and key ~= "blox" then
				return false
			end
		end
		return out.code == nil
	end)())
	local again = w.rt.onRequest(A, { code = "RELEASE" }, 2)
	check("다시 넣으면 already_redeemed · 보관함 그대로", not again.ok and again.reason == CodeService.REASON_ALREADY and w.data.potions.strength == 2)
	local old = w.rt.onRequest(A, { code = "old" }, 3)
	check("만료(expiresAt ≤ 지금) → expired · 기록 안 함", not old.ok and old.reason == CodeService.REASON_EXPIRED and w.data.redeemedCodes.OLD == nil)
	local soon = w.rt.onRequest(A, { code = "SOON" }, 4)
	check("아직 안 끝난 만료 → 성공 · 블럭스 합을 결과에 싣는다", soon.ok and BigNum.gt(soon.blox, BigNum.new(0, 0)) and #w.adds == 1)
	local nope = w.rt.onRequest(A, { code = "NOPE" }, 5)
	check("없는 코드 → not_found · 보상 빈 목록", not nope.ok and nope.reason == CodeService.REASON_NOT_FOUND and #nope.rewards == 0)
end
do
	local w = world(0)
	local out = w.rt.onRequest(A, { code = "PETCODE" }, 1)
	check("펫 주는 코드 · 보관함 가득 → storage_full · 기록 안 함(비우면 다시 받을 수 있다)", not out.ok and out.reason == "storage_full"
		and w.data.redeemedCodes.PETCODE == nil)
	w.data = nil
	check("프로필 없음 → no_profile", w.rt.onRequest(A, { code = "RELEASE" }, 2).reason == CodeService.REASON_NO_PROFILE)
end

-- 3. 틀린 코드 5번/분 → 1분 막힘 → 풀림(C3) · 빈도 · 이상한 payload -------------------------------------------------
do
	local w = world()
	local reasons = {}
	for i = 1, CodesConfig.FAIL_LIMIT do
		table.insert(reasons, w.rt.onRequest(A, { code = "WRONG" .. i }, i).reason)
	end
	check("틀린 5번은 전부 not_found", reasons[1] == "not_found" and reasons[CodesConfig.FAIL_LIMIT] == "not_found")
	local locked = w.rt.onRequest(A, { code = "RELEASE" }, CodesConfig.FAIL_LIMIT + 1)
	check("5번째 뒤에는 맞는 코드도 too_many_attempts(막힘) · 보관함 그대로", not locked.ok and locked.reason == CodeService.REASON_TOO_MANY
		and w.data.potions.strength == 0)
	local stillLocked = w.rt.onRequest(A, { code = "RELEASE" }, CodesConfig.FAIL_LIMIT + CodesConfig.LOCK_SEC - 1)
	local free = w.rt.onRequest(A, { code = "RELEASE" }, CodesConfig.FAIL_LIMIT + CodesConfig.LOCK_SEC + 0.5)
	check("막힘 1분 안은 계속 막힘 · 1분 뒤 풀린다(맞는 코드 성공)", stillLocked.reason == CodeService.REASON_TOO_MANY and free.ok)
	local w2 = world()
	for i = 1, CodesConfig.FAIL_LIMIT - 1 do
		w2.rt.onRequest(A, { code = "X" }, i * 1)
	end
	local later = w2.rt.onRequest(A, { code = "X" }, CodesConfig.FAIL_WINDOW_SEC + 10)
	local stillOpen = w2.rt.onRequest(A, { code = "RELEASE" }, CodesConfig.FAIL_WINDOW_SEC + 11)
	check("1분이 지난 틀린 횟수는 세지 않는다(4번 + 1분 뒤 1번 → 막히지 않음)", later.reason == "not_found" and stillOpen.ok)
	local w3 = world()
	w3.rt.onRequest(A, { code = "RELEASE" }, 1)
	local fast = w3.rt.onRequest(A, { code = "RELEASE" }, 1.1)
	check("빈도 상한 안 두 번째 → rate_limited(틀린 횟수에 세지 않는다)", fast.reason == CodeService.REASON_RATE_LIMITED)
	local w4 = world()
	local empty = w4.rt.onRequest(A, { code = "" }, 1)
	local long = w4.rt.onRequest(A, { code = string.rep("Z", 5000) }, 2)
	local notString = w4.rt.onRequest(A, { code = 42 }, 3)
	local notTable = w4.rt.onRequest(A, "RELEASE", 4)
	check("빈 문자열 · 아주 긴 문자열 · 문자열 아님 · 표 아님 → not_found(지급 없음)", empty.reason == "not_found" and long.reason == "not_found"
		and notString.reason == "not_found" and notTable.reason == "not_found" and w4.data.potions.strength == 0)
	local fifth = w4.rt.onRequest(A, { code = "RELEASE" }, 5)
	check("그 넷도 틀린 횟수에 들어간다(다섯째 틀림 전이라 아직 받는다)", fifth.ok)
end

print(string.format("[CodeServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[CodeServiceTests] %d test(s) failed", failed))
end

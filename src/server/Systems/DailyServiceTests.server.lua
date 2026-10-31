--!strict
-- 일일 보상 검증 (지시서 #20 단계 4 — D1 ~ D5 · T1). DayClock · DailyLogic(순수) · DailyService 런타임(가짜 시계) ·
-- RewardService · PetService 런타임(가짜 deps)을 이어 붙여 7일째 리미티드 펫 · 보관함 가득까지 본다. 실제 프로필을 건드리지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local DayClock = require(ReplicatedStorage.Shared.DayClock)
local DailyLogic = require(ReplicatedStorage.Shared.DailyLogic)
local DailyRewardConfig = require(ReplicatedStorage.Shared.Config.DailyRewardConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local DailyService = require(script.Parent.DailyService)
local RewardService = require(script.Parent.RewardService)
local PetService = require(script.Parent.PetService)
local PlayerStateService = require(script.Parent.PlayerStateService)
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
local DAY = DayClock.SECONDS_PER_DAY
local MIDNIGHT = 20758 * DAY -- 어느 UTC 0시
local LIMITED = PetConfig.LIMITED_IDS[1]

-- 1. UTC 일 번호 경계 ------------------------------------------------------------------------------------
check("DayClock: 0시 정각이 새 날 · 1초 전은 전날", DayClock.dayNumber(MIDNIGHT) == 20758 and DayClock.dayNumber(MIDNIGHT - 1) == 20757
	and DayClock.dayNumber(MIDNIGHT + DAY - 1) == 20758 and DayClock.dayNumber(0) == 0)
check("DayClock: 다음 0시까지 — 정각 86400 · 1초 전 1 · 소수 시각은 내림", DayClock.secondsToNextDay(MIDNIGHT) == DAY
	and DayClock.secondsToNextDay(MIDNIGHT - 1) == 1 and DayClock.secondsToNextDay(MIDNIGHT + 0.5) == DAY)
check("DayClock: HH:MM 올림 · 0 · 23:59", DayClock.hhmm(5 * 3600 + 61) == "05:02" and DayClock.hhmm(0) == "00:00" and DayClock.hhmm(DAY - 60) == "23:59")

-- 2. 판정 (순수) ------------------------------------------------------------------------------------------
do
	local T = 20758
	local first = DailyLogic.status({ streak = 0, lastClaimDay = 0 }, T)
	check("처음: 받을 수 있음 · 1일 칸 · 받음 0칸", first.canClaim and first.day == 1 and first.shownStreak == 0 and not first.claimedToday)
	local cont = DailyLogic.status({ streak = 3, lastClaimDay = T - 1 }, T)
	check("연속(어제 3일째) → 4일 칸 · 받음 3칸", cont.canClaim and cont.day == 4 and cont.shownStreak == 3)
	local gap = DailyLogic.status({ streak = 3, lastClaimDay = T - 2 }, T)
	check("끊김(이틀 전) → 1일 칸 · 받음 0칸(화면에서도 1일부터)", gap.canClaim and gap.day == 1 and gap.shownStreak == 0)
	local today = DailyLogic.status({ streak = 4, lastClaimDay = T }, T)
	check("오늘 받음 → 받을 수 없음 · 오늘 칸 4 · 받음 4칸", not today.canClaim and today.claimedToday and today.day == 4 and today.shownStreak == 4)
	local wrap = DailyLogic.status({ streak = 7, lastClaimDay = T - 1 }, T)
	check("어제 7일째 → 오늘 1일부터(D1)", wrap.canClaim and wrap.day == 1 and wrap.shownStreak == 0)
	local broken = DailyLogic.status({ streak = 99, lastClaimDay = -1 }, T)
	check("깨진 값 → 처음과 같다", broken.canClaim and broken.day == 1)
end

-- 3. 서버 런타임 — 받기 · 연속 · 끊김 · 같은 날 두 번 · 7일째 펫 · 보관함 가득 -----------------------------------------
local function world()
	local w: any = { clock = MIDNIGHT + 3600, sent = {}, notified = 0, adds = {} }
	local data = Schema.new() :: any
	data.progress.maxStage = 9
	w.data = data
	w.pet = PetService._pure.createRuntime({
		now = function()
			return 0
		end,
		getData = function()
			return w.data
		end,
		getBlox = function()
			return BigNum.new(0, 0)
		end,
		subtractBlox = function()
			return false
		end,
		roll = function(tiers)
			return tiers[1], 1
		end,
		save = function() end,
		setAttribute = function() end,
		hasSlotPass = function()
			return false
		end,
		hasStoragePass = function()
			return false
		end,
	})
	w.reward = RewardService._pure.createRuntime({
		getData = function()
			return w.data
		end,
		addBlox = function(_, amount)
			table.insert(w.adds, amount)
			return true
		end,
		petRoom = function(p)
			return w.pet.storageRoom(p)
		end,
		grantPet = function(p, id, src)
			return (w.pet.grant(p, id, src))
		end,
		notify = function() end,
		log = function() end,
	})
	w.rt = DailyService._pure.createRuntime({
		now = function()
			return w.clock
		end,
		dayOffset = 0,
		getData = function()
			return w.data
		end,
		grant = function(p, rewards, src)
			return w.reward.grant(p, rewards, src)
		end,
		notify = function()
			w.notified += 1
		end,
		send = function(_, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w
end

do
	local w = world()
	local ok, reason, day = w.rt.claim(A)
	check("1일째 받기: 성공 · 칸 1 · 힘 포션 1이 보관함 · 기록 {1, 오늘} · 통지", ok and reason == nil and day == 1 and w.data.potions.strength == 1
		and w.data.daily.streak == 1 and w.data.daily.lastClaimDay == DayClock.dayNumber(w.clock) and w.notified == 1)
	local ok2, reason2 = w.rt.claim(A)
	check("같은 날 두 번 → already_claimed · 보관함 · 기록 그대로", not ok2 and reason2 == DailyService.REASON_ALREADY_CLAIMED
		and w.data.potions.strength == 1 and w.data.daily.streak == 1)
	w.clock += DAY
	local ok3, _, day3 = w.rt.claim(A)
	check("다음 날(연속) → 2일째 · 블럭스 ×2(9층 기준) add 1회", ok3 and day3 == 2 and w.data.daily.streak == 2 and #w.adds == 1)
	w.clock += 2 * DAY
	local ok4, _, day4 = w.rt.claim(A)
	check("하루 건너뜀(이틀 뒤) → 1일로 돌아간다", ok4 and day4 == 1 and w.data.daily.streak == 1)
	local s = w.rt.summary(A)
	check("요약: 오늘 받음 · 칸 1 · 받음 1칸 · 오늘 일 번호 · 다음 리셋 1 ~ 86400초", not s.canClaim and s.claimedToday and s.day == 1 and s.streak == 1
		and s.today == DayClock.dayNumber(w.clock) and s.secondsToReset >= 1 and s.secondsToReset <= DAY)
end

do
	local w = world()
	w.data.daily = { streak = 6, lastClaimDay = DayClock.dayNumber(w.clock) - 1 }
	local ok, _, day = w.rt.claim(A)
	local entry = w.data.pets.owned["1"]
	check("7일째 → 리미티드 펫 1마리 지급(펫 보관함 · 빈 슬롯 장착) · 기록 streak 7", ok and day == 7 and entry ~= nil and entry.petId == LIMITED
		and w.data.pets.equipped[1] == "1" and w.data.daily.streak == 7)
	w.clock += DAY
	local s = w.rt.summary(A)
	check("7일째 다음 날 → 1일 칸부터", s.canClaim and s.day == 1 and s.streak == 0)
end

do
	local w = world()
	local yesterday = DayClock.dayNumber(w.clock) - 1
	w.data.daily = { streak = 6, lastClaimDay = yesterday }
	for i = 1, PetConfig.getStorage(false) do
		w.data.pets.owned[tostring(i)] = { petId = PetConfig.Eggs[1].pets[1].id, tier = 1 }
	end
	w.data.pets.nextUid = PetConfig.getStorage(false) + 1
	local ok, reason = w.rt.claim(A)
	check("7일째 · 보관함 가득 → storage_full · 기록 그대로(아직 받을 수 있다)", not ok and reason == "storage_full" and w.data.daily.streak == 6
		and w.data.daily.lastClaimDay == yesterday and w.rt.summary(A).canClaim and w.rt.summary(A).day == 7)
	w.data.pets.owned["1"] = nil -- 그날 안에 한 칸 비운다
	local ok2, _, day2 = w.rt.claim(A)
	check("같은 날 한 칸 비우고 다시 → 성공 · 7일째 · 리미티드 지급", ok2 and day2 == 7 and w.data.daily.streak == 7 and (function()
		for _, e in pairs(w.data.pets.owned) do
			if e.petId == LIMITED then
				return true
			end
		end
		return false
	end)())
	local w2 = world()
	w2.data.daily = { streak = 6, lastClaimDay = DayClock.dayNumber(w2.clock) - 1 }
	for i = 1, PetConfig.getStorage(false) do
		w2.data.pets.owned[tostring(i)] = { petId = PetConfig.Eggs[1].pets[1].id, tier = 1 }
	end
	w2.rt.claim(A)
	w2.clock += DAY
	check("받지 못한 채 날이 바뀌면 → 1일로 돌아간다(D4 · D1)", w2.rt.summary(A).day == 1)
end

-- 4. 요청 채널 -------------------------------------------------------------------------------------------
do
	local w = world()
	local out = w.rt.onRequest(A, { action = "claim" }, 10)
	check("요청 claim → ok · day 1 · 결과 한 번 보냄", out.ok and out.day == 1 and out.reason == "" and #w.sent == 1)
	local fast = w.rt.onRequest(A, { action = "claim" }, 10.1)
	check("빈도 상한 안 두 번째 → rate_limited · day 0", not fast.ok and fast.reason == DailyService.REASON_RATE_LIMITED and fast.day == 0)
	local bad = w.rt.onRequest(A, { action = "steal" }, 20)
	local notTable = w.rt.onRequest(A, "claim", 30)
	check("형태가 틀린 요청 → invalid(문자열 · 모르는 action)", not bad.ok and bad.reason == DailyService.REASON_INVALID and notTable.reason == DailyService.REASON_INVALID)
	local again = w.rt.onRequest(A, { action = "claim" }, 40)
	check("오늘 받은 뒤 요청 → already_claimed", not again.ok and again.reason == DailyService.REASON_ALREADY_CLAIMED)
	w.data = nil
	check("프로필 없음 → no_profile · 요약은 받을 것 없음", w.rt.onRequest(A, { action = "claim" }, 50).reason == DailyService.REASON_NO_PROFILE
		and not w.rt.summary(A).canClaim)
end

-- 5. 리미티드 펫 · 보상표 ---------------------------------------------------------------------------------------
do
	local inEgg = false
	for _, egg in pairs(PetConfig.Eggs) do
		for _, def in ipairs(egg.pets) do
			if PetConfig.isLimited(def.id) then
				inEgg = true
			end
		end
	end
	local def, eggId, rarity = PetConfig.get(LIMITED)
	check("리미티드: 어느 알 확률표에도 없다 · get이 찾는다(알 0 · 희귀도 LIMITED_RARITY) · m = LIMITED_MULT · validate", not inEgg and def ~= nil
		and eggId == PetConfig.LIMITED_EGG_ID and rarity == PetConfig.LIMITED_RARITY and (def :: any).mult == PetConfig.LIMITED_MULT and PetConfig.validate())
	local w = world()
	for i = 1, 3 do
		w.data.pets.owned[tostring(i)] = { petId = LIMITED, tier = 1 }
	end
	w.data.pets.nextUid = 4
	local ok, r = w.pet.craft(A, "1")
	check("리미티드도 크래프팅된다(3마리 → 다음 단계 1마리 · 같은 petId)", ok and r.petId == LIMITED and r.level == 2 and w.data.pets.owned["1"] == nil)
	check("리미티드 실효 증가분 = (m − 1) × CRAFT_FACTOR^(단계 − 1)", math.abs(PetConfig.effectiveGain(LIMITED, 2)
		- (PetConfig.LIMITED_MULT - 1) * PetConfig.CRAFT_FACTOR) < 1e-9)
	check("보상표: validate · 7칸 = Schema.LIMITS.DAILY_CYCLE_DAYS · 7일째는 리미티드 · 행운 포션 없음", DailyRewardConfig.validate()
		and DailyRewardConfig.CYCLE_DAYS == Schema.LIMITS.DAILY_CYCLE_DAYS and DailyRewardConfig.DAYS[7][1].petId == LIMITED and (function()
			for _, list in ipairs(DailyRewardConfig.DAYS) do
				for _, r2 in ipairs(list) do
					if r2.type == "potion" and r2.kind == "luck" then
						return false
					end
				end
			end
			return true
		end)())
end

-- 6. TEST_DAY_OFFSET 관문 (T1) · PlayerState 요약 ----------------------------------------------------------------
do
	local o0, l0 = DailyService.resolveOffset(nil, true, "floor9")
	check("오프셋 nil → 0 · 로그 없음", o0 == 0 and l0 == nil)
	local o1, l1, v1 = DailyService.resolveOffset(3, false, "floor9")
	check("Studio가 아니면 → 0 · ERROR warn", o1 == 0 and l1 ~= nil and string.find(l1 :: string, "ERROR", 1, true) ~= nil and v1 == "warn")
	local o2, _, v2 = DailyService.resolveOffset(2, true, nil)
	check("Mock 프리셋 없으면 → 0 · warn(실제 프로필에 가짜 날짜를 남기지 않는다)", o2 == 0 and v2 == "warn")
	local o3 = DailyService.resolveOffset(1.5, true, "floor9")
	local o4, _, v4 = DailyService.resolveOffset(-2, true, "floor9")
	check("정수 아님 → 0 · 프리셋 + 정수 → 그 값 · print", o3 == 0 and o4 == -2 and v4 == "print")
	local t0 = os.clock()
	while not DailyService.isRegistered() and os.clock() - t0 < 10 do
		task.wait()
	end
	check("커밋 값: Bootstrap의 TEST_DAY_OFFSET은 nil(켠 Play에서는 이 줄이 실패한다 — 그 Play로 개수를 세지 않는다)",
		DailyService.isRegistered() and DailyService.getRequestedOffset() == nil)
	local pure = PlayerStateService._pure
	local data = Schema.new() :: any
	local s1 = pure.buildSnapshot(data, 16, 16, 1, nil, nil, nil, { canClaim = true, claimedToday = false, day = 3, streak = 2, secondsToReset = 5000,
		today = 9 })
	local s2 = pure.buildSnapshot(data, 16, 16, 1, nil, nil, nil, { canClaim = true, claimedToday = false, day = 3, streak = 2, secondsToReset = 4990,
		today = 9 })
	local s3 = pure.buildSnapshot(data, 16, 16, 1, nil, nil, nil, { canClaim = false, claimedToday = true, day = 3, streak = 3, secondsToReset = 4990,
		today = 9 })
	check("PlayerState: daily 요약을 싣는다 · 남은 초 10초 차이는 같다(매초 보내지 않음) · 받으면 다르다", s1.daily.day == 3
		and pure.snapshotsEqual(s1, s2) and not pure.snapshotsEqual(s2, s3))
	check("PlayerState: 요약이 없으면 받을 것 없음(기본값)", pure.buildSnapshot(data, 16, 16, 1).daily.canClaim == false)
end

print(string.format("[DailyServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[DailyServiceTests] %d test(s) failed", failed))
end

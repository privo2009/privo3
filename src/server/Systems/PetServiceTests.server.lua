--!strict
-- PetService 검증 (지시서 #12 3단계). 가짜 deps로 Player 없이 굴린다:
-- 거부 경로 부작용 0(잠긴 알 · 월드 밖 알 · 잔액 부족 · 저장 공간 가득 · 롤 시계 · 잘못된 알 번호 · 없는 uid · 장착 중 놓아주기 ·
-- 재료 부족 크래프팅 · 최대 단계 크래프팅) · 차감 → 판정 순서 · uid 발급(문자열 키) · 새 펫만 저장 · 장착 ≤ 파생 슬롯 ·
-- equipBest · 크래프팅이 장착 자리를 이어받음 · 배수 E3 식 · 한 번만 · 요약 · 프로필 크기. 기대값은 Config에서 읽는다.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local Schema = require(script.Parent.Parent.Data.Schema)
local RollService = require(script.Parent.RollService)
local PetService = require(script.Parent.PetService)
local AttackService = require(script.Parent.AttackService)

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

local E1 = PetConfig.Eggs[1]
local E2 = PetConfig.Eggs[2]
local INTERVAL = PetConfig.HATCH_INTERVAL_SEC
local BASE_SLOTS = PetConfig.getSlots(0, false)
local STORAGE = PetConfig.getStorage(false)

local function world(opts: { blox: BigNum.BigNumber?, lifetime: BigNum.BigNumber? }?)
	local o = opts or {}
	local data = Schema.new()
	data.lifetimeBlox = o.lifetime or E2.rollCost -- 알 1 · 2가 열린 상태
	local w = {
		clock = 50,
		blox = o.blox or BigNum.mul(E2.rollCost, BigNum.fromNumber(1000)),
		data = data,
		log = {} :: { string },
		rolls = {} :: { number },
		lastLuck = nil :: number?,
		saves = 0,
		attr = "unset" :: any,
		attrSets = 0,
		present = true,
		subtractFails = false,
		slotPass = false,
		storagePass = false,
	}
	local deps: PetService.Deps = {
		now = function()
			return w.clock
		end,
		getData = function(_p)
			return if w.present then w.data else nil
		end,
		getBlox = function(_p)
			return w.blox
		end,
		subtractBlox = function(_p, amount, reason)
			table.insert(w.log, "subtract:" .. reason)
			if w.subtractFails or BigNum.lt(w.blox, amount) then
				return false
			end
			w.blox = BigNum.sub(w.blox, amount)
			return true
		end,
		roll = function(tiers, luck)
			table.insert(w.log, "roll")
			w.lastLuck = luck
			local i = table.remove(w.rolls, 1) or 1
			return tiers[i], i
		end,
		save = function(_p)
			w.saves += 1
		end,
		setAttribute = function(_p, s)
			w.attr = s
			w.attrSets += 1
		end,
		hasSlotPass = function(_p)
			return w.slotPass
		end,
		hasStoragePass = function(_p)
			return w.storagePass
		end,
	}
	return w, PetService._pure.createRuntime(deps)
end

local P = ({} :: any) :: Player
local Q = ({} :: any) :: Player

local function count(t: any): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

-- 보유를 직접 채운다(테스트 준비 — 서비스 밖에서 프로필 표를 만든다).
local function give(w: any, petId: string, level: number, n: number): { string }
	local uids = {}
	for _ = 1, n do
		local uid = tostring(w.data.pets.nextUid)
		w.data.pets.nextUid += 1
		w.data.pets.owned[uid] = { petId = petId, tier = level }
		table.insert(uids, uid)
	end
	return uids
end

-- 1. 부화 거부 경로 — 부작용 0 --------------------------------------------------------------------
do
	local w, rt = world()
	w.present = false
	local ok, r = rt.hatch(P, 1, "manual")
	check("프로필 없음 → no_profile · 차감 없음", not ok and r == RollService.REASON_NO_PROFILE and #w.log == 0)
end
do
	local w, rt = world()
	local ok1, r1 = rt.hatch(P, 1.5, "manual")
	local ok2, r2 = rt.hatch(P, "1" :: any, "manual")
	local ok3, r3 = rt.hatch(P, 0 / 0, "manual")
	check("알 번호가 정수가 아니면 invalid_request · 차감 없음", not ok1 and r1 == RollService.REASON_INVALID and not ok2 and r2 == RollService.REASON_INVALID
		and not ok3 and r3 == RollService.REASON_INVALID and #w.log == 0)
end
do
	local w, rt = world({ lifetime = BigNum.sub(E1.rollCost, BigNum.fromNumber(1)) })
	local ok, r = rt.hatch(P, 1, "manual")
	check("잠긴 알(lifetimeBlox < 부화 비용 — G8) → egg_locked · 차감 없음", not ok and r == PetService.REASON_EGG_LOCKED and #w.log == 0)
	local ok3, r3 = rt.hatch(P, 3, "manual")
	check("아직 안 열린 알 3 → egg_locked", not ok3 and r3 == PetService.REASON_EGG_LOCKED and #w.log == 0)
	local w2, rt2 = world({ lifetime = BigNum.new(1, 300) })
	local ok9, r9 = rt2.hatch(P, 99, "manual")
	check("없는 알 번호(월드 밖) → 아무리 벌어도 egg_locked", not ok9 and r9 == PetService.REASON_EGG_LOCKED and #w2.log == 0)
end
do
	local w, rt = world()
	give(w, E1.pets[1].id, 1, STORAGE)
	local blox = w.blox
	local ok, r = rt.hatch(P, 1, "manual")
	check("저장 공간 가득(파생 " .. STORAGE .. ") → storage_full · 차감 없음 · 보유 그대로", not ok and r == PetService.REASON_STORAGE_FULL and #w.log == 0
		and BigNum.eq(w.blox, blox) and count(w.data.pets.owned) == STORAGE)
	w.storagePass = true
	check("저장 공간 게임패스(세션 값)면 파생 저장 공간이 늘어 부화된다", (rt.hatch(P, 1, "manual")))
end
do
	local w, rt = world({ blox = BigNum.sub(E1.rollCost, BigNum.fromNumber(1)) })
	local ok, r = rt.hatch(P, 1, "manual")
	check("잔액 부족 → insufficient_blox · 차감도 부르지 않는다", not ok and r == RollService.REASON_INSUFFICIENT_BLOX and #w.log == 0 and w.saves == 0)
	w.blox = E1.rollCost
	w.subtractFails = true
	local ok2, r2 = rt.hatch(P, 1, "manual")
	check("차감 거부(경합) → insufficient_blox · 판정 없음 · uid 그대로", not ok2 and r2 == RollService.REASON_INSUFFICIENT_BLOX and #w.log == 1
		and w.log[1] == "subtract:pet_hatch_egg1_manual" and w.data.pets.nextUid == 1 and count(w.data.pets.owned) == 0)
	w.subtractFails = false
	check("차감 거부는 롤 시계를 쓰지 않는다", (rt.hatch(P, 1, "manual")))
end

-- 2. 순서 · 비용 · uid · 신규 / 중복 · 자동 장착 · 저장 ------------------------------------------------------
do
	local w, rt = world()
	local before = w.blox
	w.rolls = { 2 }
	local ok, r = rt.hatch(P, 1, "manual")
	check("차감 → 판정 순서", w.log[1] == "subtract:pet_hatch_egg1_manual" and w.log[2] == "roll")
	check("비용 = 알 부화 비용", BigNum.eq(w.blox, BigNum.sub(before, E1.rollCost)))
	check("uid = tostring(nextUid) · 문자열 키 · nextUid + 1", ok and r.uid == "1" and type(next(w.data.pets.owned)) == "string" and w.data.pets.nextUid == 2)
	check("보유: petId · 강화 단계 1 · 이름 · m은 저장하지 않는다", w.data.pets.owned["1"].petId == E1.pets[2].id and w.data.pets.owned["1"].tier == 1
		and w.data.pets.owned["1"].name == nil and w.data.pets.owned["1"].mult == nil)
	check("결과: 알 · 종 희귀도 · 단계 · 새 펫", r.eggId == 1 and r.rarity == 2 and r.level == 1 and r.isNew)
	check("빈 슬롯 → 자동 장착 + Attribute · 새 펫이라 저장 1회", r.equipped and w.data.pets.equipped[1] == "1"
		and w.attr == PetConfig.serializeEquipped({ { petId = E1.pets[2].id, tier = 1 } }) and w.saves == 1)

	w.clock += INTERVAL
	w.rolls = { 2 }
	local okDup, dup = rt.hatch(P, 1, "manual")
	check("중복 petId: 보유에 더한다(크래프팅 재료 — 증발하지 않는다) · 저장 없음", okDup and not dup.isNew and dup.uid == "2"
		and count(w.data.pets.owned) == 2 and w.saves == 1)
	check("중복도 빈 슬롯이면 장착", dup.equipped and #w.data.pets.equipped == 2)

	w.clock += INTERVAL
	w.rolls = { 4 }
	local _, full = rt.hatch(P, 1, "manual")
	check("슬롯이 차면 장착하지 않는다(교체는 equipBest) · 새 종이라 저장", not full.equipped and #w.data.pets.equipped == BASE_SLOTS and full.isNew and w.saves == 2)
end
do
	local w, rt = world()
	w.data.pets.owned["5"] = { petId = E1.pets[1].id, tier = 1 }
	w.data.pets.nextUid = 5 -- 깨진 nextUid(이미 쓰인 번호)
	rt.hatch(P, 1, "manual")
	check("깨진 nextUid라도 기존 펫을 덮어쓰지 않는다", w.data.pets.owned["5"] ~= nil and w.data.pets.owned["6"] ~= nil and w.data.pets.nextUid == 7)
end

-- 3. 롤 시계 · 행운 -------------------------------------------------------------------------------
do
	local w, rt = world()
	rt.hatch(P, 1, "manual")
	local blox = w.blox
	w.clock += INTERVAL * 0.5
	local ok, r = rt.hatch(P, 1, "manual")
	check("롤 시계 안 → rate_limited · 차감 없음", not ok and r == RollService.REASON_RATE_LIMITED and BigNum.eq(w.blox, blox))
	w.clock += INTERVAL * 0.5
	check("시계가 지나면 다시 부화", (rt.hatch(P, 1, "manual")))
	check("시계는 플레이어마다 따로", (rt.hatch(Q, 1, "manual")))
	local w2, rt2 = world()
	w2.data.upgrades.petLuck = 7
	rt2.hatch(P, 2, "manual")
	check("판정에 넘어간 행운 = petLuck 효과", w2.lastLuck ~= nil and math.abs((w2.lastLuck :: number) - UpgradeConfig.getEffect("petLuck", 7)) < 1e-12)
end

-- 4. 장착 · 해제 · 슬롯 (E6) -------------------------------------------------------------------------
do
	local w, rt = world()
	local u = give(w, E1.pets[1].id, 1, 5)
	for i = 1, BASE_SLOTS do
		check("장착 " .. i, (rt.equip(P, u[i])))
	end
	local okFull, rFull = rt.equip(P, u[BASE_SLOTS + 1])
	check("장착 ≤ 파생 슬롯 → slots_full", not okFull and rFull == PetService.REASON_SLOTS_FULL and #w.data.pets.equipped == BASE_SLOTS)
	check("이미 장착한 것을 다시 장착 → 그대로 성공(멱등)", (rt.equip(P, u[1])) and #w.data.pets.equipped == BASE_SLOTS)
	w.data.upgrades.petSlots = 1
	check("petSlots 업그레이드 1 → 슬롯 하나 더 (파생)", (rt.equip(P, u[BASE_SLOTS + 1])) and #w.data.pets.equipped == PetConfig.getSlots(1, false))
	local okG, rG = rt.equip(P, "999")
	check("없는 uid 장착 → not_owned", not okG and rG == PetService.REASON_NOT_OWNED)
	local okN, rN = rt.equip(P, 1 :: any)
	check("uid가 문자열이 아니면 → not_owned", not okN and rN == PetService.REASON_NOT_OWNED)
	check("해제", (rt.unequip(P, u[1])) and #w.data.pets.equipped == PetConfig.getSlots(1, false) - 1)
	local okU, rU = rt.unequip(P, u[1])
	check("장착 안 한 것 해제 → not_equipped", not okU and rU == PetService.REASON_NOT_EQUIPPED)
	check("장착이 바뀔 때마다 Attribute를 다시 세팅한다", w.attr == PetConfig.serializeEquipped(PetService._pure.equippedPets(w.data)))
end

-- 5. equipBest ----------------------------------------------------------------------------------
do
	local w, rt = world()
	local lo = give(w, E1.pets[1].id, 1, 1)[1]
	local mid = give(w, E2.pets[1].id, 1, 1)[1]
	local hi = give(w, E1.pets[1].id, 4, 1)[1] -- 알 1 일반이라도 무지개면 실효 증가분이 크다
	local top = give(w, E2.pets[4].id, 1, 1)[1]
	w.data.pets.equipped = { lo }
	check("equipBest 성공", (rt.equipBest(P)))
	local eq = w.data.pets.equipped
	local gains = {}
	for _, uid in ipairs({ lo, mid, hi, top }) do
		local e = w.data.pets.owned[uid]
		gains[uid] = PetConfig.effectiveGain(e.petId, e.tier)
	end
	local sorted = { lo, mid, hi, top }
	table.sort(sorted, function(a, b)
		return gains[a] > gains[b]
	end)
	check("equipBest: 실효 증가분 큰 순으로 슬롯 수만큼", #eq == BASE_SLOTS and eq[1] == sorted[1] and eq[2] == sorted[2])
	check("equipBest: 크래프팅 단계가 실효 증가분에 들어간다", table.find(eq, hi) ~= nil)
	local w2, rt2 = world()
	check("equipBest: 보유 0 → 성공 · 장착 비움", (rt2.equipBest(P)) and #w2.data.pets.equipped == 0)
end

-- 6. 크래프팅 (E4) ----------------------------------------------------------------------------------
do
	local w, rt = world()
	local u = give(w, E1.pets[3].id, 1, 4)
	local other = give(w, E1.pets[3].id, 2, 1)[1] -- 다른 단계는 재료가 아니다
	w.data.pets.equipped = { u[2] }
	local ok, r = rt.craft(P, u[2])
	check("크래프팅: 같은 petId · 같은 단계 3마리 → 다음 단계 1마리", ok and r.level == 2 and r.petId == E1.pets[3].id
		and w.data.pets.owned[r.uid].tier == 2 and count(w.data.pets.owned) == 4 - 3 + 1 + 1)
	check("크래프팅: 재료는 장착하지 않은 것부터 — 장착한 u2는 남는다", w.data.pets.owned[u[2]] ~= nil and w.data.pets.owned[u[1]] == nil
		and w.data.pets.owned[u[3]] == nil and w.data.pets.owned[u[4]] == nil and w.data.pets.owned[other] ~= nil)
	check("크래프팅: 장착을 안 썼으면 장착 그대로 · 결과는 장착 안 됨", not r.equipped and #w.data.pets.equipped == 1 and w.data.pets.equipped[1] == u[2])
	check("크래프팅: 결과 uid도 새로 발급(문자열)", type(r.uid) == "string" and tonumber(r.uid) ~= nil and w.data.pets.nextUid == tonumber(r.uid) + 1)
end
do
	local w, rt = world()
	local keep = give(w, E2.pets[1].id, 1, 1)[1]
	local u = give(w, E1.pets[2].id, 1, 3)
	w.data.pets.equipped = { keep, u[3], u[1] } -- 슬롯 2 + 업그레이드 상정(구조 검사용)
	local ok, r = rt.craft(P, u[1])
	check("크래프팅: 장착된 것을 써야 하면 결과가 그 장착 자리를 이어받는다", ok and r.equipped and w.data.pets.equipped[1] == keep
		and w.data.pets.equipped[2] == r.uid and #w.data.pets.equipped == 2)
	check("크래프팅: 이어받으면 Attribute도 갱신", w.attr == PetConfig.serializeEquipped(PetService._pure.equippedPets(w.data)))
end
do
	local w, rt = world()
	local u = give(w, E1.pets[1].id, 1, 2)
	local before = count(w.data.pets.owned)
	local ok, r = rt.craft(P, u[1])
	check("재료 부족 크래프팅 → not_enough · 부작용 0", not ok and r == PetService.REASON_NOT_ENOUGH and count(w.data.pets.owned) == before and w.data.pets.nextUid == 3)
	local m = give(w, E1.pets[1].id, PetConfig.MAX_LEVEL, 3)
	local okM, rM = rt.craft(P, m[1])
	check("최대 단계 크래프팅 → max_level · 부작용 0", not okM and rM == PetService.REASON_MAX_LEVEL and w.data.pets.owned[m[1]] ~= nil)
	local okG, rG = rt.craft(P, "777")
	check("없는 uid 크래프팅 → not_owned", not okG and rG == PetService.REASON_NOT_OWNED)
	local w2, rt2 = world()
	local c = give(w2, E1.pets[1].id, 1, 9)
	rt2.craft(P, c[1])
	rt2.craft(P, c[4])
	local okC, rC = rt2.craft(P, c[7])
	local _, top = rt2.craft(P, rC.uid)
	check("크래프팅 사슬: 9마리 → 2단계 3마리 → 3단계 1마리", okC and top ~= nil and type(top) == "table" and top.level == 3 and count(w2.data.pets.owned) == 1)
end

-- 7. 놓아주기 (E5) ----------------------------------------------------------------------------------
do
	local w, rt = world()
	local u = give(w, E1.pets[1].id, 1, 2)
	w.data.pets.equipped = { u[1] }
	local blox = w.blox
	local okE, rE = rt.release(P, u[1])
	check("장착 중 놓아주기 → pet_equipped · 그대로", not okE and rE == PetService.REASON_EQUIPPED and w.data.pets.owned[u[1]] ~= nil)
	check("놓아주기: 하나 지운다 · 환급 없음", (rt.release(P, u[2])) and w.data.pets.owned[u[2]] == nil and BigNum.eq(w.blox, blox))
	local okG, rG = rt.release(P, u[2])
	check("없는 uid 놓아주기 → not_owned", not okG and rG == PetService.REASON_NOT_OWNED)
end

-- 8. 로드 정리 ------------------------------------------------------------------------------------
do
	local w, rt = world()
	local u = give(w, E1.pets[1].id, 1, 1)
	w.data.pets.equipped = { u[1], u[1], "404" }
	rt.onLoaded(P, w.data)
	check("로드: 장착의 중복 · 없는 uid를 거른다 · Attribute 세팅", #w.data.pets.equipped == 1 and w.data.pets.equipped[1] == u[1] and w.attrSets == 1)
	local many = give(w, E1.pets[1].id, 1, PetConfig.MaxSlots)
	w.data.pets.equipped = many
	rt.onLoaded(P, w.data)
	check("로드: 슬롯보다 많은 장착은 자르지 않는다(E6 — Phase 8)", #w.data.pets.equipped == PetConfig.MaxSlots)
end

-- 9. 배수 E3 — 힘 자리 한 번만 · 데미지 항 없음 (S9) -------------------------------------------------------------
do
	local a, b = E2.pets[4], E1.pets[2]
	local list = { { petId = a.id, tier = 2 }, { petId = b.id, tier = 1 } }
	local pm = PetConfig.totalMult(list)
	check("E3: 1 + Σ (m − 1) × CRAFT_FACTOR^(단계 − 1)", math.abs(pm - (1 + (a.mult - 1) * PetConfig.CRAFT_FACTOR + (b.mult - 1))) < 1e-12)
	local rebirths = BigNum.fromNumber(4)
	local s = StrengthMultiplier.compute({ rebirths = rebirths, petMult = pm })
	check("힘: (1 + 환생) × 펫 배수 — 한 번(제곱 아님)", math.abs(BigNum.toRatio(s, BigNum.fromNumber(5 * pm)) - 1) < 1e-9)
	local t = TitleConfig.Titles[3].mult
	local m = AuraConfig.Packs[1].auras[2].mult
	local all = StrengthMultiplier.compute({ rebirths = rebirths, titleMult = t, auraMult = m, petMult = pm })
	check("힘: 칭호 × 아우라 × 펫 (S3)", math.abs(BigNum.toRatio(all, BigNum.fromNumber(5 * t * m * pm)) - 1) < 1e-9)
	local onlyPet = StrengthMultiplier.compute({ rebirths = rebirths, titleMult = nil, auraMult = nil, petMult = pm })
	check("힘: 칭호 · 아우라가 없어도(앞 항 nil) 펫은 곱해진다 — #11 ipairs 구멍 재발 방지", math.abs(BigNum.toRatio(onlyPet, BigNum.fromNumber(5 * pm)) - 1) < 1e-9)
	check("힘: 깨진 펫 배수(0.5 · nan · inf)는 무시", BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, petMult = 0.5 }), BigNum.fromNumber(5))
		and BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, petMult = 0 / 0 }), BigNum.fromNumber(5))
		and BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, petMult = math.huge }), BigNum.fromNumber(5)))
	local dmg = AttackService.combineDamageMultiplier({ punchDamage = 1.2, auraMult = m, petMult = pm } :: any)
	check("데미지: 펫 배수는 1펀치 데미지에 들어가지 않는다(S9 — 힘을 통해서만)", math.abs(dmg - 1.2 * m) < 1e-12)
	check("getMult 원본 = totalMult(장착 펫) · 빈 장착 1", PetConfig.totalMult(PetService._pure.equippedPets(Schema.new())) == 1)
end

-- 10. 요약 (PlayerState) -----------------------------------------------------------------------------
do
	local data = Schema.new()
	data.pets.owned["10"] = { petId = E2.pets[1].id, tier = 2 }
	data.pets.owned["2"] = { petId = E1.pets[4].id, tier = 1 }
	data.pets.owned["3"] = { petId = "ghost", tier = 1 } -- 모르는 petId는 요약에서 빠진다
	data.pets.equipped = { "10", "404" }
	data.cosmetics.hideOtherPets = true
	data.upgrades.petSlots = 1
	local s = PetService.summarize(data)
	check("요약: owned uid 번호 순 { uid · petId · level }", #s.owned == 2 and s.owned[1].uid == "2" and s.owned[2].uid == "10" and s.owned[2].level == 2)
	check("요약: equipped(없는 uid 제외) · 파생 슬롯 · 저장 공간 · 숨기기", #s.equipped == 1 and s.equipped[1] == "10"
		and s.slots == PetConfig.getSlots(1, false) and s.storage == STORAGE and s.hideOtherPets == true)
	local sp = PetService.summarize(data, true, true)
	check("요약: 게임패스(세션 값)를 넣으면 파생값이 따라온다", sp.slots == PetConfig.getSlots(1, true) and sp.storage == PetConfig.getStorage(true))
	local e = PetService.summarize(nil)
	check("요약: 깨진 데이터도 안 죽는다", #e.owned == 0 and #e.equipped == 0 and e.slots == BASE_SLOTS)
end

-- 11. 프로필 크기 — 펫 150 + 칭호 · 아우라 전부 (지시서 #12 — 4MB 대비) ------------------------------------------
do
	local data = Schema.new()
	local storageMax = PetConfig.getStorage(true)
	local longest = ""
	for _, egg in pairs(PetConfig.Eggs) do
		for _, pet in ipairs(egg.pets) do
			if #pet.id > #longest then
				longest = pet.id
			end
		end
	end
	for i = 1, storageMax do
		data.pets.owned[tostring(100000 + i)] = { petId = longest, tier = PetConfig.MAX_LEVEL } -- uid 6자리(넉넉히)
	end
	data.pets.nextUid = 100000 + storageMax + 1
	for i = 1, PetConfig.MaxSlots do
		data.pets.equipped[i] = tostring(100000 + i)
	end
	for _, def in ipairs(TitleConfig.Titles) do
		data.cosmetics.ownedTitles[def.id] = true
	end
	for _, pack in pairs(AuraConfig.Packs) do
		for _, def in ipairs(pack.auras) do
			data.cosmetics.ownedAuras[def.id] = true
		end
	end
	local ok = Schema.validate(data)
	local json = HttpService:JSONEncode(data)
	local limit = 4 * 1024 * 1024
	local ratio = #json / limit
	check("프로필 크기: 최대 보유 템플릿이 Schema를 통과한다", ok)
	check(string.format("프로필 크기: %d바이트 = 4MB의 %.3f%% (절반 미만)", #json, ratio * 100), ratio < 0.5)
	print(string.format("[PetServiceTests] 프로필 크기(펫 %d · 칭호 %d · 아우라 전부): JSON %d바이트 = 4MB의 %.3f%%",
		storageMax, #TitleConfig.Titles, #json, ratio * 100))
	local summary = PetService.summarize(data, true, true)
	local stateJson = HttpService:JSONEncode(summary)
	check(string.format("PlayerState pets 요약(150마리): %d바이트 — 한 번에 보낸다(차분 불필요, 50KB 미만)", #stateJson), #stateJson < 50 * 1024)
	print(string.format("[PetServiceTests] PlayerState pets 요약 %d마리: JSON %d바이트", #summary.owned, #stateJson))
end

print(string.format("[PetServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PetServiceTests] %d test(s) failed", failed))
end

--!strict
-- AuraService 검증 (지시서 #11 4단계). 가짜 deps로 Player 없이 굴린다:
-- 거부 경로 부작용 0(잠긴 팩 · 월드 밖 팩 · 잔액 부족 · 롤 시계 · 잘못된 팩) · 차감 → 판정 순서 · 신규 / 중복 · 자동 장착(더 높은 m만) ·
-- 저장 1회 · 장착 · 팩 선택 · 행운 전달 · 요약 · 배수 두 자리 "한 번만". 기대값은 Config에서 읽는다.
-- 럭키 · 슈퍼 롤 쓰기(지시서 #17): 블럭스 비용 없음 · 남은 횟수 −1 · 행운 ×rollCreditLuck · 제한 유저 restricted(충전 그대로) · 0이면 none_owned

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local Schema = require(script.Parent.Parent.Data.Schema)
local RollService = require(script.Parent.RollService)
local AuraService = require(script.Parent.AuraService)
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

local P1 = AuraConfig.Packs[1]
local P2 = AuraConfig.Packs[2]
local INTERVAL = AuraConfig.ROLL_INTERVAL_SEC
local WORLD = WorldConfig.get(1) :: any

local function packOutsideWorld(): number?
	for id in pairs(AuraConfig.Packs) do
		if not AuraConfig.isInWorld(id, 1) then
			return id
		end
	end
	return nil
end

local function world(opts: { blox: BigNum.BigNumber?, lifetime: BigNum.BigNumber? }?)
	local o = opts or {}
	local data = Schema.new()
	data.lifetimeBlox = o.lifetime or P2.rollCost -- 팩 1 · 2가 열린 상태
	local w = {
		clock = 50,
		blox = o.blox or BigNum.mul(P2.rollCost, BigNum.fromNumber(10)),
		data = data,
		log = {} :: { string },
		rolls = {} :: { number },
		lastLuck = nil :: number?,
		saves = 0,
		attr = "unset" :: any,
		present = true,
		subtractFails = false,
	}
	local deps: AuraService.Deps = {
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
		setAttribute = function(_p, id)
			w.attr = id
		end,
		isRestricted = function(_p)
			return w.restricted == true
		end,
	}
	return w, AuraService._pure.createRuntime(deps)
end

local P = ({} :: any) :: Player
local Q = ({} :: any) :: Player

-- 1. 거부 경로 — 부작용 0 ------------------------------------------------------------------------
do
	local w, rt = world()
	w.present = false
	local ok, r = rt.roll(P, 1, "manual")
	check("프로필 없음 → no_profile · 차감 없음", not ok and r == RollService.REASON_NO_PROFILE and #w.log == 0)
end
do
	local w, rt = world()
	local ok1, r1 = rt.roll(P, 1.5, "manual")
	local ok2, r2 = rt.roll(P, "1" :: any, "manual")
	check("팩 번호가 정수가 아니면 invalid_request · 차감 없음", not ok1 and r1 == RollService.REASON_INVALID and not ok2 and r2 == RollService.REASON_INVALID and #w.log == 0)
end
do
	local w, rt = world({ lifetime = BigNum.div(P1.rollCost, BigNum.fromNumber(2)) })
	local ok, r = rt.roll(P, 1, "manual")
	check("잠긴 팩(lifetimeBlox < 롤 비용) → pack_locked · 차감 없음", not ok and r == AuraService.REASON_PACK_LOCKED and #w.log == 0)
	local ok2, r2 = rt.roll(P, 3, "manual")
	check("아직 안 열린 팩 3 → pack_locked", not ok2 and r2 == AuraService.REASON_PACK_LOCKED and #w.log == 0)
end
do
	local outside = packOutsideWorld()
	local w, rt = world({ lifetime = BigNum.new(1, 300) })
	local ok, r = rt.roll(P, outside :: number, "manual")
	check("월드에 없는 팩(월드 2 팩) → 아무리 벌어도 pack_locked", outside ~= nil and not ok and r == AuraService.REASON_PACK_LOCKED and #w.log == 0)
	local ok9, r9 = rt.roll(P, 99, "manual")
	check("없는 팩 번호 → pack_locked", not ok9 and r9 == AuraService.REASON_PACK_LOCKED)
end
do
	local w, rt = world({ blox = BigNum.sub(P1.rollCost, BigNum.fromNumber(1)) })
	local ok, r = rt.roll(P, 1, "manual")
	check("잔액 부족 → insufficient_blox · 차감도 부르지 않는다", not ok and r == RollService.REASON_INSUFFICIENT_BLOX and #w.log == 0 and w.saves == 0)
	w.blox = P1.rollCost
	w.subtractFails = true
	local ok2, r2 = rt.roll(P, 1, "manual")
	check("차감 거부(경합) → insufficient_blox · 롤 없음", not ok2 and r2 == RollService.REASON_INSUFFICIENT_BLOX and #w.log == 1 and w.log[1] == "subtract:aura_roll_pack1_manual")
	w.subtractFails = false
	check("차감 거부는 롤 시계를 쓰지 않는다", (rt.roll(P, 1, "manual")))
end

-- 2. 순서 · 비용 · 신규 · 자동 장착 · 저장 ------------------------------------------------------------
do
	local w, rt = world()
	local before = w.blox
	w.rolls = { 2 }
	local ok, r = rt.roll(P, 1, "manual")
	check("차감 → 판정 순서", w.log[1] == "subtract:aura_roll_pack1_manual" and w.log[2] == "roll")
	check("비용 = 팩 롤 비용", BigNum.eq(w.blox, BigNum.sub(before, P1.rollCost)))
	check("신규: 보유 추가 · 결과 팩 · 등급", ok and r.isNew and r.packId == 1 and r.tier == 2 and w.data.cosmetics.ownedAuras[P1.auras[2].id] == true)
	check("신규: 장착 없음 → 자동 장착 + Attribute · 저장 1회", r.equipped and w.data.cosmetics.equippedAura == P1.auras[2].id and w.attr == P1.auras[2].id and w.saves == 1)

	w.clock += INTERVAL
	w.rolls = { 1 }
	local _, low = rt.roll(P, 1, "manual")
	check("더 낮은 m 신규: 보유만 늘고 장착 그대로", low.isNew and not low.equipped and w.data.cosmetics.equippedAura == P1.auras[2].id and w.saves == 2)

	w.clock += INTERVAL
	w.rolls = { 1 }
	local _, high = rt.roll(P, 2, "manual")
	check("팩 2 common(m > 팩 1 legendary — G4) → 바로 장착", high.isNew and high.equipped and w.data.cosmetics.equippedAura == P2.auras[1].id)

	w.clock += INTERVAL
	w.rolls = { 2 }
	local savesBefore = w.saves
	local okDup, dup = rt.roll(P, 1, "manual")
	check("중복: 성공 · isNew false · 장착 · 저장 그대로", okDup and not dup.isNew and not dup.equipped and w.saves == savesBefore
		and w.data.cosmetics.equippedAura == P2.auras[1].id)
end

-- 3. 롤 시계 (남용 방지) ---------------------------------------------------------------------------
do
	local w, rt = world()
	rt.roll(P, 1, "manual")
	local blox = w.blox
	w.clock += INTERVAL * 0.5
	local ok, r = rt.roll(P, 1, "manual")
	check("롤 시계 안 → rate_limited · 차감 없음", not ok and r == RollService.REASON_RATE_LIMITED and BigNum.eq(w.blox, blox))
	w.clock += INTERVAL * 0.5
	check("시계가 지나면 다시 굴린다", (rt.roll(P, 1, "manual")))
	check("시계는 플레이어마다 따로", (rt.roll(Q, 1, "manual")))
end

-- 4. 장착 · 팩 선택 -------------------------------------------------------------------------------
do
	local w, rt = world()
	w.data.cosmetics.ownedAuras[P1.auras[1].id] = true
	check("보유한 아우라 장착", (rt.equip(P, P1.auras[1].id)) and w.data.cosmetics.equippedAura == P1.auras[1].id and w.attr == P1.auras[1].id)
	local ok2, r2 = rt.equip(P, P1.auras[4].id)
	check("미보유 장착 → not_owned · 그대로", not ok2 and r2 == AuraService.REASON_NOT_OWNED and w.data.cosmetics.equippedAura == P1.auras[1].id)
	local ok3, r3 = rt.equip(P, "ghost")
	check("모르는 id → invalid_request", not ok3 and r3 == RollService.REASON_INVALID)

	check("팩 선택: 월드 안 · 잠긴 팩도 저장된다(창이 해금 조건을 보여 준다)", (rt.selectPack(P, WORLD.auraPacks[#WORLD.auraPacks])) and w.data.rolling.selectedPack == WORLD.auraPacks[#WORLD.auraPacks])
	local outside = packOutsideWorld()
	local ok4, r4 = rt.selectPack(P, outside :: number)
	check("팩 선택: 월드 밖 팩 → invalid_request · 그대로", not ok4 and r4 == RollService.REASON_INVALID and w.data.rolling.selectedPack == WORLD.auraPacks[#WORLD.auraPacks])
	local ok5 = rt.selectPack(P, 1.5)
	check("팩 선택: 정수가 아니면 거부", not ok5)
end

-- 5. 행운 전달 (auraLuck) · 요약 -------------------------------------------------------------------
do
	local w, rt = world()
	w.data.upgrades.auraLuck = 6
	rt.roll(P, 1, "manual")
	check("판정에 넘어간 행운 = auraLuck 효과", w.lastLuck ~= nil and math.abs((w.lastLuck :: number) - UpgradeConfig.getEffect("auraLuck", 6)) < 1e-12)

	local data = Schema.new()
	data.cosmetics.ownedAuras[P2.auras[1].id] = true
	data.cosmetics.ownedAuras[P1.auras[3].id] = true
	data.cosmetics.equippedAura = P2.auras[1].id
	data.cosmetics.hideOtherAuras = true
	data.rolling.selectedPack = 2
	local s = AuraService.summarize(data)
	check("요약: owned 팩 · 등급 순", #s.owned == 2 and s.owned[1] == P1.auras[3].id and s.owned[2] == P2.auras[1].id)
	check("요약: equipped · selectedPack · hideOtherAuras", s.equipped == P2.auras[1].id and s.selectedPack == 2 and s.hideOtherAuras == true)
	local e = AuraService.summarize(Schema.new())
	check("요약: 빈 프로필 equipped \"\" · 팩 1 · 숨김 끔", e.equipped == "" and e.selectedPack == 1 and e.hideOtherAuras == false and #e.owned == 0)
	check("요약: 깨진 데이터도 안 죽는다", AuraService.summarize(nil).equipped == "")
end

-- 5b. 럭키 · 슈퍼 롤 쓰기 (지시서 #17) -------------------------------------------------------------------
do
	local w, rt = world()
	w.data.rollCredits.lucky = 2
	w.data.rollCredits.super = 1
	local blox = w.blox
	w.rolls = { 3 }
	local ok, r = rt.roll(P, 1, "credit", "lucky")
	local luckyMult = ShopConfig.rollCreditLuck("lucky") :: number
	check("럭키 롤: 성공 · 남은 횟수 −1 · 블럭스 차감 없음(차감 호출도 없음)", ok and r.isNew and w.data.rollCredits.lucky == 1 and BigNum.eq(w.blox, blox)
		and w.log[1] == "roll")
	check("럭키 롤: 행운 = 업그레이드 × rollCreditLuck(럭키 5)", luckyMult == 5 and w.lastLuck ~= nil
		and math.abs((w.lastLuck :: number) - UpgradeConfig.getEffect("auraLuck", 0) * luckyMult) < 1e-9)
	w.clock += INTERVAL
	rt.roll(P, 1, "credit", "super")
	check("슈퍼 롤: 행운 ×100 · 남은 0", ShopConfig.rollCreditLuck("super") == 100 and w.data.rollCredits.super == 0
		and math.abs((w.lastLuck :: number) - UpgradeConfig.getEffect("auraLuck", 0) * 100) < 1e-9)
	w.clock += INTERVAL
	local okNone, none = rt.roll(P, 1, "credit", "super")
	check("남은 횟수 0 → none_owned · 블럭스 그대로", not okNone and none == AuraService.REASON_NONE_OWNED and BigNum.eq(w.blox, blox))
	local okBad, bad = rt.roll(P, 1, "credit", "mega")
	check("모르는 롤 → invalid", not okBad and bad == RollService.REASON_INVALID)
	w.restricted = true
	w.clock += INTERVAL
	local okR, rr = rt.roll(P, 1, "credit", "lucky")
	check("제한 유저 → restricted · 충전 그대로(1)", not okR and rr == AuraService.REASON_RESTRICTED and w.data.rollCredits.lucky == 1)
	w.restricted = false
	local outside = packOutsideWorld() :: number
	local okL, rl = rt.roll(P, outside, "credit", "lucky")
	check("롤 쓰기도 열린 팩만 → pack_locked · 충전 그대로", not okL and rl == AuraService.REASON_PACK_LOCKED and w.data.rollCredits.lucky == 1)
	w.clock += INTERVAL * 0.3
	rt.roll(P, 1, "credit", "lucky")
	local okRate, rate = rt.roll(P, 1, "credit", "lucky")
	check("롤 시계는 롤 쓰기에도 걸린다 → rate_limited", not okRate and rate == RollService.REASON_RATE_LIMITED)
end

-- 6. 배수 두 자리 — 각 자리 한 번만 (A10) ---------------------------------------------------------------
do
	local m = P2.auras[4].mult
	local t = TitleConfig.Titles[#TitleConfig.Titles].mult
	local rebirths = BigNum.fromNumber(4)
	local s = StrengthMultiplier.compute({ rebirths = rebirths, auraMult = m })
	check("힘: (1 + 환생) × m — 한 번 (제곱 아님)", math.abs(BigNum.toRatio(s, BigNum.fromNumber(5 * m)) - 1) < 1e-9)
	local st = StrengthMultiplier.compute({ rebirths = rebirths, titleMult = t, auraMult = m })
	check("힘: 칭호 × 아우라 — 출처끼리 곱한다(S3)", math.abs(BigNum.toRatio(st, BigNum.fromNumber(5 * t * m)) - 1) < 1e-9)
	check("힘: 깨진 아우라 배수(0.5 · nan)는 무시", BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, auraMult = 0.5 }), BigNum.fromNumber(5))
		and BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, auraMult = 0 / 0 }), BigNum.fromNumber(5)))

	local combine = AttackService.combineDamageMultiplier
	local g = UpgradeConfig.getEffect("punchDamage", 3)
	check("데미지: 펀치 데미지 업그레이드 × m — 한 번", math.abs(combine({ punchDamage = g, auraMult = m }) - g * m) < 1e-12)
	check("데미지: 아우라 없음 = 업그레이드 그대로", combine({ punchDamage = g }) == g)
	check("데미지: 깨진 값은 1", combine({ punchDamage = 0 / 0, auraMult = 0.3 }) == 1)
	local strength = BigNum.fromNumber(1000)
	local dmg = AttackService._pure.computePunchDamage(strength, combine({ punchDamage = 1, auraMult = m }))
	check("데미지: 1펀치 = 힘 × m (한 번)", math.abs(BigNum.toRatio(dmg, BigNum.fromNumber(1000 * m)) - 1) < 1e-9)
	check("multOf: 장착 없음 · 모르는 id는 1", AuraConfig.multOf(false) == 1 and AuraConfig.multOf("ghost") == 1 and AuraConfig.multOf(P1.auras[1].id) == P1.auras[1].mult)
end

print(string.format("[AuraServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AuraServiceTests] %d test(s) failed", failed))
end

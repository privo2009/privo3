--!strict
-- PlayerStateClient 검증: payload 형태 판정 · Store 반영 · 틀린 payload는 통째로 버림.
-- 실물 싱글톤이 아니라 Store.new() 인스턴스에 반영한다(싱글톤은 서버 값이 채운다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Store = require(script.Parent.Parent.UI.Store)
local PlayerStateClient = require(script.Parent.Parent.Net.PlayerStateClient)

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

local function samplePayload(): any
	return {
		blox = { m = 1.5, e = 3 },
		strength = { m = 2.25, e = 7 },
		lifetimeBlox = { m = 4, e = 5 },
		lifeBlox = { m = 3, e = 4 },
		rebirths = { m = 2.8, e = 1 },
		walkSpeed = 20,
		maxWalkSpeed = 36,
		maxStage = 6,
		padIndex = 3,
		upgrades = { punchDamage = 2, punchSpeed = 1, bloxGain = 0, auraLuck = 0, titleLuck = 0, petLuck = 0, petSlots = 0 },
		titles = { owned = { "novice", "breaker" }, equipped = "breaker", autoRoll = true },
		auras = { owned = { "pack1_rare" }, equipped = "pack1_rare", selectedPack = 2, hideOtherAuras = true, world = 1 },
		pets = { owned = { { uid = "1", petId = "egg1_rare", level = 1 }, { uid = "4", petId = "egg1_epic", level = 2 } }, equipped = { "4" },
			slots = 2, storage = 50, hideOtherPets = false, world = 1 },
		shop = { gamepasses = { "damage2x", "strength8x" }, paidRandomRestricted = false,
			boosts = { { type = "strength", mult = 2, remainingSec = 600 } }, autoClick = true },
	}
end

-- 1. 형태 판정 ------------------------------------------------------------------------------
check("형태: 정상 payload는 통과", PlayerStateClient.isValidPayload(samplePayload()))
do
	local p = samplePayload()
	p.lifeBlox = nil
	check("형태: BigNum 필드가 빠지면 거부", not PlayerStateClient.isValidPayload(p))
	local q = samplePayload()
	q.walkSpeed = 0 / 0
	check("형태: nan 숫자는 거부", not PlayerStateClient.isValidPayload(q))
	local r = samplePayload()
	r.blox = 5
	check("형태: BigNum 자리에 숫자면 거부", not PlayerStateClient.isValidPayload(r))
	check("형태: 테이블이 아니면 거부", not PlayerStateClient.isValidPayload("x"))
	local u = samplePayload()
	u.upgrades = nil
	check("형태: 업그레이드 표가 없으면 거부(지시서 #7)", not PlayerStateClient.isValidPayload(u))
	local v = samplePayload()
	v.upgrades.bloxGain = nil
	check("형태: 업그레이드 키가 빠지면 거부", not PlayerStateClient.isValidPayload(v))
	local x = samplePayload()
	x.upgrades.punchSpeed = -1
	check("형태: 음수 레벨은 거부", not PlayerStateClient.isValidPayload(x))
	local t1 = samplePayload()
	t1.titles = nil
	check("형태: 칭호 요약이 없으면 거부(지시서 #10)", not PlayerStateClient.isValidPayload(t1))
	local t2 = samplePayload()
	t2.titles.owned = { "novice", 3 }
	check("형태: 칭호 owned에 문자열이 아닌 값이면 거부", not PlayerStateClient.isValidPayload(t2))
	local t3 = samplePayload()
	t3.titles.autoRoll = "yes"
	check("형태: 칭호 autoRoll이 boolean이 아니면 거부", not PlayerStateClient.isValidPayload(t3))
	local t4 = samplePayload()
	t4.titles = { owned = {}, equipped = "", autoRoll = false }
	check("형태: 빈 칭호 요약은 통과", PlayerStateClient.isValidPayload(t4))
	local a1 = samplePayload()
	a1.auras = nil
	check("형태: 아우라 요약이 없으면 거부(지시서 #11)", not PlayerStateClient.isValidPayload(a1))
	local a2 = samplePayload()
	a2.auras.hideOtherAuras = "no"
	check("형태: 아우라 숨기기가 boolean이 아니면 거부", not PlayerStateClient.isValidPayload(a2))
	local a3 = samplePayload()
	a3.auras.selectedPack = 0 / 0
	check("형태: 아우라 팩 번호가 nan이면 거부", not PlayerStateClient.isValidPayload(a3))
	local p1 = samplePayload()
	p1.pets = nil
	check("형태: 펫 요약이 없으면 거부(지시서 #12)", not PlayerStateClient.isValidPayload(p1))
	local p2 = samplePayload()
	p2.pets.owned[2].uid = 4
	check("형태: 펫 uid가 문자열이 아니면 거부", not PlayerStateClient.isValidPayload(p2))
	local p3 = samplePayload()
	p3.pets.slots = 0 / 0
	check("형태: 펫 슬롯이 nan이면 거부", not PlayerStateClient.isValidPayload(p3))
end

-- 2. Store 반영 -----------------------------------------------------------------------------
do
	local store = Store.new()
	local payload = samplePayload()
	local ok = false
	store.setSource(function(setter)
		ok = PlayerStateClient.apply(setter, payload)
	end)
	check("반영: apply가 true", ok)
	check("반영: blox", BigNum.eq(store.get("blox"), BigNum.new(1.5, 3)))
	check("반영: strength", BigNum.eq(store.get("strength"), BigNum.new(2.25, 7)))
	check("반영: lifeBlox", BigNum.eq(store.get("lifeBlox"), BigNum.new(3, 4)))
	check("반영: rebirths", BigNum.eq(store.get("rebirths"), BigNum.new(2.8, 1)))
	check("반영: 숫자 필드", store.get("walkSpeed") == 20 and store.get("maxWalkSpeed") == 36
		and store.get("maxStage") == 6 and store.get("padIndex") == 3)

	payload.blox.m = 9
	check("반영: payload를 고쳐도 Store 값은 안 바뀐다 (복사)", BigNum.eq(store.get("blox"), BigNum.new(1.5, 3)))
	check("반영: 업그레이드 레벨", store.get("upgrades").punchDamage == 2 and store.get("upgrades").punchSpeed == 1)
	payload.upgrades.punchDamage = 7
	local got = store.get("upgrades")
	got.punchSpeed = 99
	check("반영: 업그레이드 표도 복사 (payload · get 반환값을 고쳐도 안 바뀐다)", store.get("upgrades").punchDamage == 2 and store.get("upgrades").punchSpeed == 1)

	local titles = store.get("titles")
	check("반영: 칭호 요약", titles.equipped == "breaker" and titles.autoRoll == true and #titles.owned == 2 and titles.owned[2] == "breaker")
	payload.titles.owned[1] = "mythic"
	titles.owned[2] = "legend"
	check("반영: 칭호 요약도 깊은 복사", store.get("titles").owned[1] == "novice" and store.get("titles").owned[2] == "breaker")
	local auras = store.get("auras")
	check("반영: 아우라 요약", auras.equipped == "pack1_rare" and auras.selectedPack == 2 and auras.hideOtherAuras == true and #auras.owned == 1)
	auras.owned[1] = "pack5_legendary"
	check("반영: 아우라 요약도 깊은 복사", store.get("auras").owned[1] == "pack1_rare")
	local pets = store.get("pets")
	check("반영: 펫 요약", #pets.owned == 2 and pets.owned[2].level == 2 and pets.equipped[1] == "4" and pets.slots == 2 and pets.storage == 50)
	pets.owned[1].level = 4
	payload.pets.equipped[1] = "1"
	check("반영: 펫 요약도 깊은 복사", store.get("pets").owned[1].level == 1 and store.get("pets").equipped[1] == "4")

	local received: any = nil
	store.subscribe("strength", function(value)
		received = value
	end)
	local next_ = samplePayload()
	next_.strength = { m = 3, e = 7 }
	store.setSource(function(setter)
		PlayerStateClient.apply(setter, next_)
	end)
	task.wait()
	check("반영: 바뀐 키의 구독자가 새 값으로 불린다", received ~= nil and BigNum.eq(received, BigNum.new(3, 7)))
end

do
	local store = Store.new()
	local before = store.get("walkSpeed")
	local bad = samplePayload()
	bad.padIndex = nil
	local ok = true
	store.setSource(function(setter)
		ok = PlayerStateClient.apply(setter, bad)
	end)
	check("거부: 틀린 payload는 false", ok == false)
	check("거부: 틀린 payload는 한 키도 반영하지 않는다", store.get("walkSpeed") == before)
end

-- 상점 요약 (지시서 #16) -----------------------------------------------------------------------
do
	check("상점: 정상 요약 통과", PlayerStateClient.isValidShop(samplePayload().shop))
	local noShop = samplePayload()
	noShop.shop = nil
	check("상점: 요약이 없으면 payload 거부", not PlayerStateClient.isValidPayload(noShop))
	local badPass = samplePayload()
	badPass.shop.gamepasses = { 3 }
	local badBoost = samplePayload()
	badBoost.shop.boosts = { { type = "luck", mult = 2, remainingSec = 0 / 0 } }
	local badFlag = samplePayload()
	badFlag.shop.autoClick = "yes"
	check("상점: 게임패스 키가 문자열 아님 · 부스트 남은 초 nan · 토글이 boolean 아님 → 거부", not PlayerStateClient.isValidShop(badPass.shop)
		and not PlayerStateClient.isValidShop(badBoost.shop) and not PlayerStateClient.isValidShop(badFlag.shop))
	local store = Store.new()
	local initial = store.get("shop")
	check("상점: 첫 PlayerState 전에는 보유 없음 · 제한 · 부스트 없음 · 자동 꺼짐", #initial.gamepasses == 0 and initial.paidRandomRestricted == true
		and #initial.boosts == 0 and initial.autoClick == false)
	local payload = samplePayload()
	store.setSource(function(setter)
		PlayerStateClient.apply(setter, payload, 123)
	end)
	local shop = store.get("shop")
	check("상점: 반영 · 받은 시각이 부스트에 붙는다", #shop.gamepasses == 2 and shop.gamepasses[2] == "strength8x" and shop.autoClick == true
		and shop.paidRandomRestricted == false and shop.boosts[1].remainingSec == 600 and shop.boosts[1].receivedAt == 123)
	shop.gamepasses[1] = "blox2x"
	shop.boosts[1].remainingSec = 1
	check("상점: 깊은 복사(받은 표를 고쳐도 안 바뀐다)", store.get("shop").gamepasses[1] == "damage2x" and store.get("shop").boosts[1].remainingSec == 600)
	store.setSource(function(setter)
		PlayerStateClient.apply(setter, samplePayload(), 500)
	end)
	check("상점: 값이 같으면 받은 시각은 처음 것 그대로(같은 값은 통지 안 함)", store.get("shop").boosts[1].receivedAt == 123)
	-- 보관함 · 롤 · 선해금(지시서 #17)
	check("보관함: 옛 payload(필드 없음)도 받는다 → 0 · 빈 목록", store.get("shop").potions.strength == 0 and store.get("shop").rollCredits.super == 0
		and #store.get("shop").gymUnlocks == 0)
	local inv = samplePayload()
	inv.shop.potions = { strength = 2, damage = 0, luck = 7 }
	inv.shop.rollCredits = { lucky = 5, super = 1 }
	inv.shop.gymUnlocks = { 1, 4 }
	local fired = 0
	store.subscribe("shop", function()
		fired += 1
	end)
	store.setSource(function(setter)
		PlayerStateClient.apply(setter, inv, 600)
	end)
	task.wait()
	local s2 = store.get("shop")
	check("보관함: 포션 · 롤 · 선해금이 Store에 실린다 · 바뀌면 통지", s2.potions.strength == 2 and s2.potions.luck == 7 and s2.rollCredits.lucky == 5
		and s2.gymUnlocks[2] == 4 and fired >= 1)
	local bad = samplePayload()
	bad.shop.potions = { strength = 0 / 0, damage = -1 }
	bad.shop.gymUnlocks = { "x", 3.5, 2 }
	store.setSource(function(setter)
		PlayerStateClient.apply(setter, bad, 700)
	end)
	check("보관함: 이상한 값은 0 · 정수 번호만", store.get("shop").potions.strength == 0 and store.get("shop").potions.damage == 0
		and #store.get("shop").gymUnlocks == 1 and store.get("shop").gymUnlocks[1] == 2)
end

print(string.format("[PlayerStateClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PlayerStateClientTests] %d test(s) failed", failed))
end

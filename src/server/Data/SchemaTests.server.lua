--!strict
-- Schema 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 2-1 검증: 정상 템플릿이 자기 자신의 validate를 통과하는지,
-- 그리고 오염된 데이터 각각이 의도한 이유로 정확히 실패하는지 확인한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Schema = require(script.Parent.Schema)
-- LIMITS는 Config와 중복이다(Schema는 Config를 몰라야 한다). 어긋나면 여기서 잡는다.
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)

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

local function errorsContain(errors: { string }, keyword: string): boolean
	for _, err in ipairs(errors) do
		if string.find(err, keyword, 1, true) then
			return true
		end
	end
	return false
end

-- 1. 기본 API ---------------------------------------------------------------

do
	local ok, errors = Schema.validate(Schema.getTemplate())
	check("getTemplate()이 validate를 통과함", ok, table.concat(errors, "; "))
end

do
	local template = Schema.getTemplate()
	local again = Schema.getTemplate()
	check("getTemplate()은 같은 원본 테이블 참조를 반환함", template == again)
end

do
	local a = Schema.new()
	local b = Schema.new()
	a.blox.m = 5
	check("new()는 매번 독립된 깊은 복사본을 반환함", b.blox.m == 0)
end

check("Schema.VERSION == 7 (v7: purchases · potions · rollCredits · gymUnlocks · boosts remainingSec — 지시서 #16)", Schema.VERSION == 7)
do
	local t = Schema.getTemplate() :: any
	check("v7 템플릿: purchases · boosts 빈 표 · potions 3종 0 · rollCredits 2종 0 · gymUnlocks 빈 표 · MAX_PURCHASES 100",
		type(t.purchases) == "table" and next(t.purchases) == nil and type(t.boosts) == "table" and next(t.boosts) == nil
			and t.potions.strength == 0 and t.potions.damage == 0 and t.potions.luck == 0 and t.rollCredits.lucky == 0 and t.rollCredits.super == 0
			and type(t.gymUnlocks) == "table" and next(t.gymUnlocks) == nil and Schema.LIMITS.MAX_PURCHASES == 100)
	local function rejects(mutate: (any) -> ()): boolean
		local d = Schema.new() :: any
		mutate(d)
		return not (Schema.validate(d))
	end
	local okBoost = Schema.new() :: any
	okBoost.boosts = { { type = "strength", mult = 2, remainingSec = 600 } }
	okBoost.purchases = { "abc", "def" }
	okBoost.gymUnlocks = { ["3"] = true }
	okBoost.potions.luck = 5
	check("v7 검증: 정상 boosts · purchases · gymUnlocks · potions 통과", (Schema.validate(okBoost)))
	check("v7 검증 거부: 옛 boosts(expiresAt만) · remainingSec 음수 · mult < 1", rejects(function(d)
		d.boosts = { { type = "strength", mult = 2, expiresAt = 100 } }
	end) and rejects(function(d)
		d.boosts = { { type = "strength", mult = 2, remainingSec = -1 } }
	end) and rejects(function(d)
		d.boosts = { { type = "strength", mult = 0.5, remainingSec = 10 } }
	end))
	check("v7 검증 거부: purchases 101개 · 문자열 아님", rejects(function(d)
		for i = 1, 101 do
			d.purchases[i] = tostring(i)
		end
	end) and rejects(function(d)
		d.purchases = { 123 }
	end))
	check("v7 검증 거부: potions 음수 · 소수 · rollCredits 없음 · gymUnlocks 숫자 키 · 값 true 아님", rejects(function(d)
		d.potions.strength = -1
	end) and rejects(function(d)
		d.potions.damage = 1.5
	end) and rejects(function(d)
		d.rollCredits = nil
	end) and rejects(function(d)
		d.gymUnlocks = { [3] = true }
	end) and rejects(function(d)
		d.gymUnlocks = { ["3"] = 1 }
	end))
end
check("v6 템플릿: upgrades.moveSpeed 없음 · 나머지 7키", (Schema.getTemplate() :: any).upgrades.moveSpeed == nil and (function()
	local n = 0
	for _ in pairs(Schema.getTemplate().upgrades) do
		n += 1
	end
	return n == 7
end)())
check("LIMITS.MAX_PET_SLOTS == PetConfig.MaxSlots", Schema.LIMITS.MAX_PET_SLOTS == PetConfig.MaxSlots)
check("LIMITS.MAX_PET_STORAGE == PetConfig.getStorage(게임패스 있음)", Schema.LIMITS.MAX_PET_STORAGE == PetConfig.getStorage(true))
do
	local packCount = 0
	for _ in pairs(AuraConfig.Packs) do
		packCount += 1
	end
	check("LIMITS.MAX_AURA_PACKS == AuraConfig 팩 수", Schema.LIMITS.MAX_AURA_PACKS == packCount)
end
check("LIMITS에 드론 상한이 없다(v5)", (Schema.LIMITS :: any).MAX_DRONES == nil)

-- v5: 파생값 · 폐기 필드는 템플릿에 없다 (S12 · S13 — 게임패스가 섞인 값을 저장하지 않는다)
do
	local t = Schema.getTemplate() :: any
	check("v5 템플릿: pets.slots 없음", t.pets.slots == nil)
	check("v5 템플릿: pets.storage 없음", t.pets.storage == nil)
	check("v5 템플릿: rolling.unlockedAuraPacks 없음", t.rolling.unlockedAuraPacks == nil)
	check("v5 템플릿: drones 없음", t.drones == nil)
	check("v5 템플릿: rolling.selectedPack · autoRollTitle은 남는다", t.rolling.selectedPack == 1 and t.rolling.autoRollTitle == false)
end

-- 2. isBigNum: 정상 케이스 ------------------------------------------------------

check("isBigNum: {m=1,e=0}", Schema.isBigNum({ m = 1, e = 0 }))
check("isBigNum: {m=9.99,e=5}", Schema.isBigNum({ m = 9.99, e = 5 }))
check("isBigNum: {m=0,e=0}", Schema.isBigNum({ m = 0, e = 0 }))
check("isBigNum: {m=-5,e=3} (구조상으로는 허용)", Schema.isBigNum({ m = -5, e = 3 }))

-- 3. isBigNum: 실패 케이스 ------------------------------------------------------

check("isBigNum 실패: raw number", not Schema.isBigNum(5))
check("isBigNum 실패: inf", not Schema.isBigNum({ m = math.huge, e = 0 }))
check("isBigNum 실패: -inf", not Schema.isBigNum({ m = -math.huge, e = 0 }))
check("isBigNum 실패: nan", not Schema.isBigNum({ m = 0 / 0, e = 0 }))
check("isBigNum 실패: 정규화 안 됨 (m=12)", not Schema.isBigNum({ m = 12, e = 0 }))
check("isBigNum 실패: {m=0,e=5}", not Schema.isBigNum({ m = 0, e = 5 }))
check("isBigNum 실패: e가 정수가 아님", not Schema.isBigNum({ m = 1, e = 0.5 }))

-- 4. validate: 실패 케이스 ----------------------------------------------------------

do
	local data = Schema.new()
	data.blox = 5 -- raw number를 BigNum 필드에
	local ok, errors = Schema.validate(data)
	check("validate 실패: BigNum 필드에 raw number", not ok and errorsContain(errors, "blox"))
end

do
	local data = Schema.new()
	data.strength = { m = math.huge, e = 0 }
	local ok, errors = Schema.validate(data)
	check("validate 실패: BigNum 필드에 inf", not ok and errorsContain(errors, "strength"))
end

do
	local data = Schema.new()
	data.rebirths = { m = 0 / 0, e = 0 }
	local ok, errors = Schema.validate(data)
	check("validate 실패: BigNum 필드에 nan", not ok and errorsContain(errors, "rebirths"))
end

do
	local data = Schema.new()
	data.lifetimeBlox = { m = 12, e = 0 } -- 정규화 안 됨
	local ok, errors = Schema.validate(data)
	check("validate 실패: 정규화 안 된 m=12", not ok and errorsContain(errors, "lifetimeBlox"))
end

do
	local data = Schema.new()
	data.blox = { m = 0, e = 5 }
	local ok, errors = Schema.validate(data)
	check("validate 실패: {m=0,e=5}", not ok and errorsContain(errors, "blox"))
end

do
	local data = Schema.new()
	data.progress.maxStage = 0
	local ok, errors = Schema.validate(data)
	check("validate 실패: maxStage=0", not ok and errorsContain(errors, "maxStage"))
end

do
	local data = Schema.new()
	data.progress.selectedPadIndex = 0
	local ok, errors = Schema.validate(data)
	check("validate 실패: selectedPadIndex=0", not ok and errorsContain(errors, "selectedPadIndex"))
end

do
	-- 상한(clickPadSet.count)은 여기서 검사하지 않는다 — Schema는 Config를 몰라야 한다.
	-- 범위 초과는 PadService가 로드 시 클램프한다 (PadServiceTests 6번 항목).
	local data = Schema.new()
	data.progress.selectedPadIndex = 9999
	local ok = Schema.validate(data)
	check("validate 통과: selectedPadIndex 상한은 Schema의 책임이 아님", ok)
end


do
	local data = Schema.new()
	data.pets.owned[1] = { petId = "test", tier = 1 } -- 숫자 키
	local ok, errors = Schema.validate(data)
	check("validate 실패: pets.owned에 숫자 키", not ok and errorsContain(errors, "pets.owned"))
end

do
	local data = Schema.new()
	table.insert(data.pets.equipped, "not_owned_uid")
	local ok, errors = Schema.validate(data)
	check("validate 실패: owned에 없는 펫 장착", not ok and errorsContain(errors, "pets.equipped"))
end

-- v5: 장착 · 보유 상한은 게임패스 최대 보너스까지 허용한다 — 로드 시점에는 게임패스를 모른다.
-- 패스 보유자를 로드에서 깨뜨리지 않는 것이 목적이다(실제 슬롯 잘라내기는 게임패스 확인 뒤 — PENDING).
local function petsWith(owned: number, equipped: number)
	local data = Schema.new()
	for i = 1, owned do
		data.pets.owned[tostring(i)] = { petId = "x", tier = 1 }
	end
	for i = 1, equipped do
		table.insert(data.pets.equipped, tostring(i))
	end
	return data
end

do
	local base = PetConfig.getSlots(0, false)
	local ok = Schema.validate(petsWith(base + 1, base + 1))
	check("validate 통과: 장착이 기본 슬롯보다 많아도 최대 슬롯 이하면 통과 (패스 보유자)", ok)
	local okMax = Schema.validate(petsWith(Schema.LIMITS.MAX_PET_SLOTS, Schema.LIMITS.MAX_PET_SLOTS))
	check("validate 통과: 장착 = 최대 슬롯", okMax)
	local okOver, errors = Schema.validate(petsWith(Schema.LIMITS.MAX_PET_SLOTS + 1, Schema.LIMITS.MAX_PET_SLOTS + 1))
	check("validate 실패: 장착 > 최대 슬롯", not okOver and errorsContain(errors, "최대 슬롯"))
end

do
	local okBase = Schema.validate(petsWith(PetConfig.getStorage(false) + 1, 0))
	check("validate 통과: 보유가 기본 저장 공간보다 많아도 최대 이하면 통과 (패스 보유자)", okBase)
	local okMax = Schema.validate(petsWith(Schema.LIMITS.MAX_PET_STORAGE, 0))
	check("validate 통과: 보유 = 최대 저장 공간", okMax)
	local okOver, errors = Schema.validate(petsWith(Schema.LIMITS.MAX_PET_STORAGE + 1, 0))
	check("validate 실패: 보유 > 최대 저장 공간", not okOver and errorsContain(errors, "최대 저장 공간"))
end

do
	local data = Schema.new()
	data.rolling.selectedPack = Schema.LIMITS.MAX_AURA_PACKS
	check("validate 통과: selectedPack = 팩 상한 (열렸는지는 Schema 책임 아님 — 파생)", (Schema.validate(data)))
	for _, bad in ipairs({ 0, Schema.LIMITS.MAX_AURA_PACKS + 1, 1.5 }) do
		local d = Schema.new()
		d.rolling.selectedPack = bad
		local ok, errors = Schema.validate(d)
		check("validate 실패: selectedPack=" .. tostring(bad), not ok and errorsContain(errors, "selectedPack"))
	end
end

do
	local data = Schema.new() :: any
	data.rolling.autoRollTitle = "yes"
	local ok, errors = Schema.validate(data)
	check("validate 실패: autoRollTitle이 boolean이 아님", not ok and errorsContain(errors, "autoRollTitle"))
end

do
	-- v4 필드가 남아 있어도(마이그레이션 전 데이터를 검증하는 경우) 검증이 그것을 읽지 않는다
	local data = Schema.new() :: any
	data.pets.slots = 0
	data.pets.storage = 0
	check("validate: 지운 slots · storage 값을 읽지 않는다", (Schema.validate(data)))
end

-- 5. validate: cosmetics 관련 추가 케이스 -----------------------------------------------

do
	local data = Schema.new()
	data.cosmetics.equippedAura = "not_owned_aura" -- ownedAuras에 없음
	local ok, errors = Schema.validate(data)
	check("validate 실패: 소유하지 않은 아우라 장착", not ok and errorsContain(errors, "equippedAura"))
end

do
	local data = Schema.new()
	data.cosmetics.ownedAuras["some_aura"] = true
	data.cosmetics.equippedAura = "some_aura"
	local ok = Schema.validate(data)
	check("validate 성공: 소유한 아우라 장착", ok)
end

print(string.format("[SchemaTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SchemaTests] %d test(s) failed", failed))
end

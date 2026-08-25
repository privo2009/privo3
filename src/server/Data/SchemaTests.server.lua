--!strict
-- Schema 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 2-1 검증: 정상 템플릿이 자기 자신의 validate를 통과하는지,
-- 그리고 오염된 데이터 각각이 의도한 이유로 정확히 실패하는지 확인한다.

local Schema = require(script.Parent.Schema)

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

check("Schema.VERSION == 3 (v3: progress.selectedPadIndex 추가)", Schema.VERSION == 3)
check("LIMITS.MAX_DRONES == 5", Schema.LIMITS.MAX_DRONES == 5)
check("LIMITS.MAX_PET_SLOTS == 6", Schema.LIMITS.MAX_PET_SLOTS == 6)
check("LIMITS.MAX_AURA_PACKS == 5", Schema.LIMITS.MAX_AURA_PACKS == 5)

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
	data.drones.count = 6
	local ok, errors = Schema.validate(data)
	check("validate 실패: drones.count=6", not ok and errorsContain(errors, "drones.count"))
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

do
	local data = Schema.new()
	data.pets.owned["a"] = { petId = "x", tier = 1 }
	data.pets.owned["b"] = { petId = "x", tier = 1 }
	data.pets.owned["c"] = { petId = "x", tier = 1 }
	data.pets.equipped = { "a", "b", "c" } -- 기본 slots=2인데 3개 장착
	local ok, errors = Schema.validate(data)
	check("validate 실패: equipped가 slots 초과", not ok and errorsContain(errors, "slots"))
end

do
	local data = Schema.new()
	data.rolling.selectedPack = 2 -- 기본 unlockedAuraPacks=1
	local ok, errors = Schema.validate(data)
	check("validate 실패: selectedPack이 unlockedAuraPacks 초과", not ok and errorsContain(errors, "selectedPack"))
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

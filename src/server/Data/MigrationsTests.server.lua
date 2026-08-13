--!strict
-- Migrations 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 2-1 검증: 미래 버전 거부 / 동일 버전 통과 / schemaVersion 갱신.
-- Migrations는 순수 함수라 실제 프로필 로드 없이도 단위 테스트 가능하다.

local Migrations = require(script.Parent.Migrations)

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

-- 1. 기본 -----------------------------------------------------------------

check("Migrations.CURRENT == 2 (v1->v2 변환 1개 등록됨: upgrades.radius 제거)", Migrations.CURRENT == 2)

-- 2. v1 -> v2 실제 마이그레이션: upgrades.radius 필드 제거 -------------------------------
-- 데미지 오버플로우 도입으로 파괴 반경 개념이 없어져서 생긴 실제 마이그레이션(Migrations[1]).

do
	local data = {
		schemaVersion = 1,
		upgrades = { punchDamage = 3, punchSpeed = 1, radius = 5, moveSpeed = 0 },
	}
	local ok, err = Migrations.run(data)

	check("v1->v2: 변환 성공", ok, err)
	check("v1->v2: schemaVersion이 2로 갱신됨", data.schemaVersion == 2)
	check("v1->v2: upgrades.radius가 제거됨", data.upgrades.radius == nil)
	check(
		"v1->v2: 다른 upgrades 필드는 그대로 유지됨",
		data.upgrades.punchDamage == 3 and data.upgrades.punchSpeed == 1 and data.upgrades.moveSpeed == 0
	)
end

do
	-- upgrades 테이블 자체가 없는(비정상) 데이터도 에러 없이 통과해야 한다 —
	-- Migrations[1]이 type(data.upgrades) == "table" 가드 없이 짜여있으면 여기서 죽는다.
	local data = { schemaVersion = 1 }
	local ok, err = Migrations.run(data)
	check("v1->v2: upgrades 테이블이 없어도 안 죽고 통과", ok and data.schemaVersion == 2, err)
end

-- 3. 동일 버전 통과 ------------------------------------------------------------

do
	local data = { schemaVersion = Migrations.CURRENT, value = 42 }
	local ok, err = Migrations.run(data)
	check("동일 버전(schemaVersion == CURRENT)은 그대로 통과", ok and data.schemaVersion == Migrations.CURRENT and data.value == 42, err)
end

-- 4. 미래 버전 거부 --------------------------------------------------------------

do
	local data = { schemaVersion = Migrations.CURRENT + 999 }
	local ok, err = Migrations.run(data)
	check("미래 버전(schemaVersion > CURRENT)은 변환하지 않고 실패", not ok and data.schemaVersion == Migrations.CURRENT + 999, err)
	check("미래 버전 실패 시 에러 메시지가 있음", type(err) == "string" and #(err :: string) > 0)
end

-- 5. 잘못된 입력 ------------------------------------------------------------------

do
	local ok = Migrations.run({ schemaVersion = "not a number" })
	check("schemaVersion이 number가 아니면 실패", not ok)
end

do
	local ok = Migrations.run("not a table")
	check("data가 table이 아니면 실패", not ok)
end

-- 6. schemaVersion 갱신 (변환 함수를 임시로 등록해서 구조를 검증) -------------------------

do
	local originalCurrent = Migrations.CURRENT

	-- 최신 버전 -> +1 변환을 임시로 등록. Migrations[1](실제 radius 제거 변환)과는 다른
	-- 슬롯이라 서로 안 건드린다. run()이 등록된 변환을 실제로 적용하고 schemaVersion을
	-- 갱신하는지는 검증해야 한다.
	Migrations.CURRENT = originalCurrent + 1
	Migrations[originalCurrent] = function(data)
		data.migratedMarker = true
		return data
	end

	local data = { schemaVersion = originalCurrent }
	local ok, err = Migrations.run(data)
	check(
		"등록된 변환이 적용되고 schemaVersion이 갱신됨",
		ok and data.schemaVersion == originalCurrent + 1 and data.migratedMarker == true,
		err
	)

	-- 변환 함수가 없는 상태에서 CURRENT만 올라간 경우: "변환 함수가 없음" 실패가 나야 함
	Migrations[originalCurrent] = nil
	local data2 = { schemaVersion = originalCurrent }
	local ok2, err2 = Migrations.run(data2)
	check("중간 버전 변환 함수가 없으면 실패", not ok2, err2)

	-- 다른 테스트에 영향 주지 않도록 원상복구
	Migrations.CURRENT = originalCurrent
end

print(string.format("[MigrationsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[MigrationsTests] %d test(s) failed", failed))
end

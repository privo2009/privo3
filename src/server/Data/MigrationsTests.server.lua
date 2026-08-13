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

check("Migrations.CURRENT == 1 (아직 등록된 변환 함수 없음)", Migrations.CURRENT == 1)

-- 2. 동일 버전 통과 ------------------------------------------------------------

do
	local data = { schemaVersion = Migrations.CURRENT, value = 42 }
	local ok, err = Migrations.run(data)
	check("동일 버전(schemaVersion == CURRENT)은 그대로 통과", ok and data.schemaVersion == Migrations.CURRENT and data.value == 42, err)
end

-- 3. 미래 버전 거부 --------------------------------------------------------------

do
	local data = { schemaVersion = Migrations.CURRENT + 999 }
	local ok, err = Migrations.run(data)
	check("미래 버전(schemaVersion > CURRENT)은 변환하지 않고 실패", not ok and data.schemaVersion == Migrations.CURRENT + 999, err)
	check("미래 버전 실패 시 에러 메시지가 있음", type(err) == "string" and #(err :: string) > 0)
end

-- 4. 잘못된 입력 ------------------------------------------------------------------

do
	local ok = Migrations.run({ schemaVersion = "not a number" })
	check("schemaVersion이 number가 아니면 실패", not ok)
end

do
	local ok = Migrations.run("not a table")
	check("data가 table이 아니면 실패", not ok)
end

-- 5. schemaVersion 갱신 (변환 함수를 임시로 등록해서 구조를 검증) -------------------------

do
	local originalCurrent = Migrations.CURRENT

	-- 버전 1 -> 2 변환을 임시로 등록. 실제 게임에는 아직 이런 변환이 없지만,
	-- run()이 등록된 변환을 실제로 적용하고 schemaVersion을 갱신하는지는 검증해야 한다.
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

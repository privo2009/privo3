--!strict
-- Migrations 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 2-1 검증: 미래 버전 거부 / 동일 버전 통과 / schemaVersion 갱신.
-- Migrations는 순수 함수라 실제 프로필 로드 없이도 단위 테스트 가능하다.

local Migrations = require(script.Parent.Migrations)
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

-- 7. v1 전체 템플릿 -> v2 필드 구성 일치 -------------------------------------------------
-- 2번은 손으로 만든 부분 픽스처라 "radius가 지워졌다"까지만 봤다. 여기서는 v1 시점의
-- 전체 템플릿을 태워서 결과의 키 구성이 현재 Schema.getTemplate()과 완전히 일치하는지 본다.
--
-- [무엇을 검증하는가 - Reconcile 몫과의 경계]
-- 실서버 경로는 Migrations.run() -> profile:Reconcile() 두 단계이고 책임이 갈린다.
--   Reconcile   : 템플릿에 있는데 데이터에 없는 키를 채운다. 지우지는 못한다.
--   마이그레이션 : 템플릿에서 없어진 키를 지운다. Reconcile이 못 하는 유일한 일.
--
-- 그래서 이 테스트는 ProfileStore를 끌어오지 않고 마이그레이션 단독 출력을 본다.
-- Reconcile 스텁을 만들어 태우면 ProfileStore의 실제 동작이 아니라 스텁을 검증하게 되고,
-- 더 나쁘게는 "마이그레이션이 지웠어야 할 키"를 스텁이 채워 가려버릴 수 있다.
--
-- 지금은 v1->v2가 삭제만 있는 마이그레이션이라 단독 출력이 템플릿과 정확히 일치해야 한다.
-- 나중에 "필드 추가" 마이그레이션이 생기면 MISSING 쪽은 Reconcile 몫으로 넘어가므로
-- 그때 판정을 완화한다. EXTRA 쪽은 절대 완화하지 말 것 - 마이그레이션 고유 책임이다.

-- 키 경로만 재귀 수집한다. 값은 보지 않는다 - 마이그레이션이 바꾸는 것은 구성이지 값이 아니다.
-- 빈 테이블({})은 자기 경로만 남기고 하위로 내려가지 않으므로 ownedAuras 같은 필드도 안전하다.
local function collectKeyPaths(value: any, prefix: string, out: { [string]: boolean })
	for k, v in pairs(value) do
		local path = if prefix == "" then tostring(k) else (prefix .. "." .. tostring(k))
		out[path] = true
		if type(v) == "table" then
			collectKeyPaths(v, path, out)
		end
	end
	return out
end

-- v1 시점의 전체 프로필 템플릿.
-- Schema.getTemplate()에서 파생시키지 않고 손으로 박아둔다 - 현재 템플릿에서 만들어내면
-- 템플릿이 바뀔 때 픽스처도 같이 바뀌어서 이 테스트가 아무것도 못 잡는다.
-- 출처: 커밋 d3a490f~1 의 Schema.lua buildTemplate(). v2와의 차이는 upgrades.radius 하나뿐이다.
local function makeV1Profile()
	return {
		schemaVersion = 1,

		strength = { m = 1, e = 0 },
		blox = { m = 0, e = 0 },
		lifetimeBlox = { m = 0, e = 0 },
		rebirths = { m = 0, e = 0 },

		progress = { maxStage = 1, currentWorld = 1, unlockedWorlds = 1 },

		upgrades = {
			punchDamage = 0,
			punchSpeed = 0,
			radius = 0, -- v2에서 제거되는 필드
			moveSpeed = 0,
			bloxGain = 0,
			auraLuck = 0,
			titleLuck = 0,
			petLuck = 0,
			petSlots = 0,
		},

		drones = { count = 1, lastCollectAt = 0 },

		cosmetics = {
			equippedAura = false,
			ownedAuras = {},
			equippedTitle = false,
			ownedTitles = {},
			hideOtherAuras = false,
			hideOtherPets = false,
		},

		pets = { owned = {}, equipped = {}, slots = 2, storage = 50, nextUid = 1 },

		rolling = { unlockedAuraPacks = 1, selectedPack = 1, autoRollTitle = false },

		boosts = {},

		daily = { streak = 0, lastClaimDay = 0, freePotionDay = 0 },

		stats = {
			totalRuns = 0,
			totalCashouts = 0,
			bestRunDepth = 0,
			offlineClaims = 0,
			playtimeSec = 0,
			firstJoin = 0,
		},
	}
end

do
	local data = makeV1Profile()
	local ok, err = Migrations.run(data)
	check("v1 전체 템플릿: 변환 성공", ok, err)

	local got = collectKeyPaths(data, "", {})
	-- getTemplate()은 공용 단일 원본이라 수정하면 안 된다. 여기서는 읽기만 한다.
	local want = collectKeyPaths(Schema.getTemplate(), "", {})

	local extra: { string } = {} -- 템플릿에 없는데 남아있는 키 = 마이그레이션이 못 지운 것
	local missing: { string } = {} -- 템플릿에 있는데 결과에 없는 키

	for path in pairs(got) do
		if not want[path] then
			table.insert(extra, path)
		end
	end
	for path in pairs(want) do
		if not got[path] then
			table.insert(missing, path)
		end
	end
	table.sort(extra)
	table.sort(missing)

	local extraDetail = if #extra > 0 then ("EXTRA: " .. table.concat(extra, ", ")) else nil
	local missingDetail = if #missing > 0 then ("MISSING: " .. table.concat(missing, ", ")) else nil

	check(
		"v1 전체 템플릿: 템플릿에 없는 키가 남아있지 않음 (마이그레이션의 삭제 책임)",
		#extra == 0,
		extraDetail
	)
	check(
		"v1 전체 템플릿: 템플릿의 키가 빠짐없이 존재함",
		#missing == 0,
		missingDetail
	)
end

-- 8. 멱등성 -----------------------------------------------------------------------------
-- run()을 두 번 태워도 결과가 같아야 한다. while version < CURRENT 루프 구조상 2회차는
-- 루프에 진입하지 않으므로 지금은 구조적으로 보장되지만, 변환 함수가 늘어나면서
-- 그 가정이 깨질 수 있다(예: 조건 없이 값을 누적하는 변환). 실측으로 못박아 둔다.
-- 키 구성만이 아니라 값까지 비교한다 - 멱등성이 깨지는 전형적인 형태가 "값이 두 번 더해짐"이라서다.

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- 첫 차이가 난 경로를 돌려준다. 어디서 깨졌는지 모르면 디버깅이 안 된다.
local function deepEqual(a: any, b: any, path: string): (boolean, string?)
	if type(a) ~= type(b) then
		return false, string.format("%s: 타입 불일치 (%s vs %s)", path, type(a), type(b))
	end
	if type(a) ~= "table" then
		if a ~= b then
			return false, string.format("%s: 값 불일치 (%s vs %s)", path, tostring(a), tostring(b))
		end
		return true, nil
	end
	for k, v in pairs(a) do
		local childPath = if path == "" then tostring(k) else (path .. "." .. tostring(k))
		local same, detail = deepEqual(v, b[k], childPath)
		if not same then
			return false, detail
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			local childPath = if path == "" then tostring(k) else (path .. "." .. tostring(k))
			return false, string.format("%s: 2회차에만 존재", childPath)
		end
	end
	return true, nil
end

do
	local data = makeV1Profile()

	local ok1, err1 = Migrations.run(data)
	check("멱등: 1회차 변환 성공", ok1, err1)

	local afterFirst = deepCopy(data)

	local ok2, err2 = Migrations.run(data)
	check("멱등: 2회차도 성공 (이미 최신 버전)", ok2, err2)
	check("멱등: schemaVersion이 CURRENT에서 더 올라가지 않음", data.schemaVersion == Migrations.CURRENT)

	local same, detail = deepEqual(afterFirst, data, "")
	check("멱등: 2회차 결과가 1회차와 완전히 동일 (키+값)", same, detail)
end

print(string.format("[MigrationsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[MigrationsTests] %d test(s) failed", failed))
end

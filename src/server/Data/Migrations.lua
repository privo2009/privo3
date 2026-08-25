--!strict
-- 버전별 프로필 데이터 변환. schemaVersion을 하나씩 올려가며 순차 적용한다.
--
-- 사용법: 스키마가 바뀌면 "버전 N → N+1" 변환 함수를 Migrations[N]에 등록한다.
--   Migrations[1] = function(data)
--       data.someNewField = 0 -- 버전 2에서 새로 생긴 필드 기본값 채우기
--       return data
--   end
--
-- 숫자 키(Migrations[1], [2], ...)와 문자열 키(Migrations.CURRENT, .run)를 같은 테이블에
-- 함께 쓴다 — Lua 테이블은 두 종류의 키가 서로 충돌하지 않으므로 별도 배열이 필요 없다.

local Schema = require(script.Parent.Schema)

local Migrations = {}

Migrations.CURRENT = Schema.VERSION

-- v1 -> v2: 데미지 오버플로우 도입으로 upgrades.radius(파괴 반경) 필드가 없어짐
-- (DESIGN.md 2장 "데미지 오버플로우" / 7장 업그레이드 상점). 기존 프로필에 남아있던
-- 값은 그냥 버린다 — 환불/보상 대상 아님(사용한 만큼 다른 업그레이드에 쓸 수 있었던
-- 재화가 아니라 순수 구조 필드 삭제).
Migrations[1] = function(data)
	if type(data.upgrades) == "table" then
		data.upgrades.radius = nil
	end
	return data
end

-- v2 -> v3: 클릭 파워 패드 도입으로 progress.selectedPadIndex가 생김 (Phase 4-2-b).
-- 기존 프로필은 아무 패드도 밟은 적이 없으므로 패드 1(조건 0, 항상 해금)로 채운다.
--
-- profile:Reconcile()도 템플릿 기준으로 누락 필드를 채우지만 여기에 따로 쓴다:
-- ProfileManager의 로드 순서가 Migrations.run -> Reconcile이라 마이그레이션 시점에는
-- 아직 필드가 없고, 무엇보다 "이 버전에서 무엇이 생겼는가"가 Reconcile에는 안 남는다.
Migrations[2] = function(data)
	if type(data.progress) ~= "table" then
		-- progress 자체가 없는(비정상) 데이터. 여기서 만들지 않는다 — Reconcile이 템플릿
		-- 통째로 채우고, 그래도 안 되면 Schema.validate가 잡아서 킥한다.
		return data
	end
	if data.progress.selectedPadIndex == nil then
		data.progress.selectedPadIndex = 1
	end
	return data
end

-- data.schemaVersion부터 Migrations.CURRENT까지 등록된 변환 함수를 순서대로 적용하고
-- data.schemaVersion을 최종 버전으로 갱신한다. data는 in-place로 수정된다.
--
-- 알 수 없는 미래 버전(data.schemaVersion > CURRENT)은 절대 변환하지 않고 실패로 처리한다.
-- 예: 신버전 서버가 저장한 데이터를, 롤백된 구버전 서버가 잘못 이해하고 덮어써서
-- 데이터를 훼손하는 사고를 막기 위함.
function Migrations.run(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.schemaVersion) ~= "number" then
		return false, "data.schemaVersion이 number가 아님"
	end

	if data.schemaVersion > Migrations.CURRENT then
		return false, string.format("알 수 없는 미래 schemaVersion(%d > 현재 %d) — 변환 거부", data.schemaVersion, Migrations.CURRENT)
	end

	local version = data.schemaVersion
	while version < Migrations.CURRENT do
		local transform = Migrations[version]
		if type(transform) ~= "function" then
			return false, string.format("버전 %d → %d 변환 함수가 없음", version, version + 1)
		end

		data = transform(data)
		version = version + 1
		data.schemaVersion = version
	end

	return true, nil
end

return Migrations

--!strict
-- 버전별 프로필 데이터 변환. schemaVersion을 하나씩 올려가며 순차 적용한다.
-- 지금은 Schema.VERSION이 1(최초 버전)이라 등록된 변환 함수가 하나도 없는 게 정상이다.
--
-- 사용법: 스키마가 바뀌면 "버전 N → N+1" 변환 함수를 Migrations[N]에 등록한다.
-- 예시 (아직 실제로 등록된 것은 없음):
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

--!strict
-- 데이터 환경 (지시서 #23 E1 ~ E6 — DESIGN.md 10장 "데이터 환경"). 저장소 이름 · 환경 값의 원본은 이 파일 한 곳이다.
--
--   studio   PlayerData_v1        RunService:IsStudio()면 무조건(DATA_ENV가 무엇이든) — 지금 이름 그대로(개발 계정 진행 유지)
--   beta     PlayerData_beta_v1   Studio가 아니고 DATA_ENV = "beta"(커밋 값 — 비공개 테스트)
--   live     PlayerData_live_v1   Studio가 아니고 DATA_ENV = "live"(출시 당일 한 줄 커밋 — ROADMAP "출시 체크리스트")
--
-- ⚠️ Studio에서 beta · live 저장소를 열지 않는다(E3). storeNameFor가 거부 사유와 nil을 돌려주고 ProfileManager는 열지 않는다.
--    Studio 밖에서 DATA_ENV가 beta · live가 아니어도 같다 — 틀린 저장소에 섞여 쓰는 것보다 안 열리는 쪽이 고치기 쉽다.
-- ⚠️ 이름 뒤의 "v1"은 schemaVersion과 무관하다(스키마 변경은 Migrations). 데이터를 통째로 리셋하는 비상 상황에만 올린다.
-- beta에서는 개발자 상품을 팔지 않는다(E5 — 출시 때 진행이 초기화되면 산 것이 사라진다). 예외는 BETA_PRODUCT_ALLOWLIST(실서버 구매 확인 H7).
-- 게임패스는 환경과 무관하게 판다(소유가 로블록스 계정에 남는다).

local DataConfig = {}

DataConfig.DATA_ENV = "beta" -- E2 · E6: "beta" | "live"만. 출시 당일 "live"로 바꾸는 한 줄 커밋

DataConfig.STUDIO = "studio"
DataConfig.BETA = "beta"
DataConfig.LIVE = "live"

DataConfig.STORE_NAMES = {
	studio = "PlayerData_v1",
	beta = "PlayerData_beta_v1",
	live = "PlayerData_live_v1",
} :: { [string]: string }

DataConfig.BETA_PRODUCT_ALLOWLIST = { "strengthPotion" } :: { string }

DataConfig.REASON_BETA_DISABLED = "beta_disabled"
DataConfig.ERR_BAD_ENV = "bad_env" -- Studio 밖인데 DATA_ENV가 beta · live가 아니다
DataConfig.ERR_STUDIO_NON_STUDIO_STORE = "studio_refuses_store" -- Studio에서 beta · live 저장소를 요구했다

-- 커밋해도 되는 DATA_ENV 값(E6)
function DataConfig.isDeployEnv(value: any): boolean
	return value == DataConfig.BETA or value == DataConfig.LIVE
end

-- E2: 환경 결정. Studio면 무조건 studio. 아니면 configured가 beta · live일 때 그것, 아니면 (nil, bad_env).
function DataConfig.resolveEnv(isStudio: boolean, configured: any): (string?, string?)
	if isStudio then
		return DataConfig.STUDIO, nil
	end
	if DataConfig.isDeployEnv(configured) then
		return configured :: string, nil
	end
	return nil, DataConfig.ERR_BAD_ENV
end

-- E3: 환경 → 저장소 이름. Studio에서 studio가 아닌 환경을 요구하면 (nil, studio_refuses_store) — 그 경로는 저장소를 열지 않는다.
function DataConfig.storeNameFor(env: any, isStudio: boolean): (string?, string?)
	if isStudio and env ~= DataConfig.STUDIO then
		return nil, DataConfig.ERR_STUDIO_NON_STUDIO_STORE
	end
	local name = if type(env) == "string" then DataConfig.STORE_NAMES[env] else nil
	if name == nil then
		return nil, DataConfig.ERR_BAD_ENV
	end
	return name, nil
end

-- E1 · E4: 이번 서버가 쓸 (환경, 저장소 이름, 거부 사유). 이름이 nil이면 저장소를 열지 않는다.
function DataConfig.resolveStore(isStudio: boolean, configured: any): (string?, string?, string?)
	local env, err = DataConfig.resolveEnv(isStudio, configured)
	if env == nil then
		return nil, nil, err
	end
	local name, nameErr = DataConfig.storeNameFor(env, isStudio)
	return env, name, nameErr
end

-- E4 시작 로그 한 줄. 이름을 열지 못하면 사유를 싣는다(그 줄은 호출자가 ERROR로 찍는다).
function DataConfig.startLine(env: string?, name: string?, err: string?): string
	if name ~= nil then
		return string.format("[Data] env=%s store=%s", tostring(env), name)
	end
	return string.format("[Data][ERROR] env=%s store=(열지 않음) reason=%s", tostring(env), tostring(err))
end

-- E5: 이 환경에서 이 상품을 팔지 않는가. kind는 ShopConfig 상품 종류("gamepass" | "product").
-- beta의 개발자 상품만 막는다(허용 목록 제외). studio · live · 게임패스는 언제나 판다.
function DataConfig.productBlocked(env: any, kind: any, key: any): boolean
	if env ~= DataConfig.BETA or kind ~= "product" then
		return false
	end
	return not table.find(DataConfig.BETA_PRODUCT_ALLOWLIST, key)
end

function DataConfig.validate(): boolean
	assert(DataConfig.isDeployEnv(DataConfig.DATA_ENV), "DataConfig: DATA_ENV는 beta · live만 — " .. tostring(DataConfig.DATA_ENV))
	local seen: { [string]: boolean } = {}
	for _, env in ipairs({ DataConfig.STUDIO, DataConfig.BETA, DataConfig.LIVE }) do
		local name = DataConfig.STORE_NAMES[env]
		assert(type(name) == "string" and #name > 0 and not seen[name], "DataConfig: 환경마다 다른 저장소 이름 — " .. env)
		seen[name] = true
	end
	return true
end

return DataConfig

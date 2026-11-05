--!strict
-- DataConfig 검증 (지시서 #23 E1 ~ E6 — DESIGN.md 10장 "데이터 환경").
--   환경 결정(Studio → 언제나 studio · beta · live · 잘못된 값) · 저장소 이름 · Studio에서 beta · live 거부 ·
--   DATA_ENV 커밋 값 · beta 개발자 상품 거부 · 허용 목록 · 게임패스 허용 · 시작 로그 한 줄

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataConfig = require(ReplicatedStorage.Shared.Config.DataConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

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

local S, B, L = DataConfig.STUDIO, DataConfig.BETA, DataConfig.LIVE

-- 1. 커밋 값 (E6) ---------------------------------------------------------------------------------------
check("커밋 값: DATA_ENV는 beta 또는 live", DataConfig.DATA_ENV == B or DataConfig.DATA_ENV == L, tostring(DataConfig.DATA_ENV))
check("커밋 값: validate 통과", pcall(DataConfig.validate))
check("커밋 값 검사: studio · 빈 값 · 대문자 · 숫자는 커밋 불가", not DataConfig.isDeployEnv(S) and not DataConfig.isDeployEnv(nil)
	and not DataConfig.isDeployEnv("") and not DataConfig.isDeployEnv("Live") and not DataConfig.isDeployEnv(1))

-- 2. 환경 결정 (E2) -------------------------------------------------------------------------------------
for _, configured in ipairs({ B, L, "nope", S }) do
	check("Studio면 무조건 studio — 설정 " .. configured, DataConfig.resolveEnv(true, configured) == S)
end
check("Studio면 설정이 nil이어도 studio", DataConfig.resolveEnv(true, nil) == S)
check("Studio 밖 beta → beta", DataConfig.resolveEnv(false, B) == B)
check("Studio 밖 live → live", DataConfig.resolveEnv(false, L) == L)
do
	local env, err = DataConfig.resolveEnv(false, "Live")
	check("Studio 밖 잘못된 값 → 환경 없음 · bad_env", env == nil and err == DataConfig.ERR_BAD_ENV)
	local env2, err2 = DataConfig.resolveEnv(false, S)
	check("Studio 밖 studio 설정 → 환경 없음(실서버가 개발 저장소를 열지 않는다)", env2 == nil and err2 == DataConfig.ERR_BAD_ENV)
end

-- 3. 저장소 이름 (E1) -----------------------------------------------------------------------------------
check("이름: studio = PlayerData_v1(개발 계정 진행 유지)", DataConfig.STORE_NAMES[S] == "PlayerData_v1")
check("이름: beta = PlayerData_beta_v1", DataConfig.STORE_NAMES[B] == "PlayerData_beta_v1")
check("이름: live = PlayerData_live_v1", DataConfig.STORE_NAMES[L] == "PlayerData_live_v1")
check("이름: Studio 밖 beta · live는 자기 이름", DataConfig.storeNameFor(B, false) == "PlayerData_beta_v1"
	and DataConfig.storeNameFor(L, false) == "PlayerData_live_v1")
check("이름: Studio의 studio는 PlayerData_v1", DataConfig.storeNameFor(S, true) == "PlayerData_v1")

-- 4. Studio에서 beta · live 거부 (E3) -------------------------------------------------------------------
for _, env in ipairs({ B, L }) do
	local name, err = DataConfig.storeNameFor(env, true)
	check("Studio에서 " .. env .. " 저장소 → 열지 않음 · studio_refuses_store", name == nil and err == DataConfig.ERR_STUDIO_NON_STUDIO_STORE)
end
do
	local name, err = DataConfig.storeNameFor("nope", false)
	check("모르는 환경 → 이름 없음 · bad_env", name == nil and err == DataConfig.ERR_BAD_ENV)
end

-- 5. resolveStore · 시작 로그 (E1 · E4) -----------------------------------------------------------------
do
	local env, name, err = DataConfig.resolveStore(true, DataConfig.DATA_ENV)
	check("Studio + 커밋 값 → studio · PlayerData_v1 · 사유 없음", env == S and name == "PlayerData_v1" and err == nil)
	check("시작 로그: [Data] env=studio store=PlayerData_v1", DataConfig.startLine(env, name, err) == "[Data] env=studio store=PlayerData_v1")
	local env2, name2 = DataConfig.resolveStore(false, B)
	check("실서버 + beta → beta · PlayerData_beta_v1", env2 == B and name2 == "PlayerData_beta_v1"
		and DataConfig.startLine(env2, name2, nil) == "[Data] env=beta store=PlayerData_beta_v1")
	local env3, name3, err3 = DataConfig.resolveStore(false, "Live")
	check("실서버 + 잘못된 값 → 열지 않음 · ERROR 줄에 사유", env3 == nil and name3 == nil and err3 == DataConfig.ERR_BAD_ENV
		and string.find(DataConfig.startLine(env3, name3, err3), "[Data][ERROR]", 1, true) == 1
		and string.find(DataConfig.startLine(env3, name3, err3), DataConfig.ERR_BAD_ENV, 1, true) ~= nil)
end

-- 6. beta 상품 판매 (E5) --------------------------------------------------------------------------------
check("beta: 허용 목록은 strengthPotion 하나", #DataConfig.BETA_PRODUCT_ALLOWLIST == 1 and DataConfig.BETA_PRODUCT_ALLOWLIST[1] == "strengthPotion")
do
	local allIn = true
	for _, key in ipairs(DataConfig.BETA_PRODUCT_ALLOWLIST) do
		local def = ShopConfig.get(key)
		if def == nil or def.kind ~= "product" then
			allIn = false
		end
	end
	check("beta: 허용 목록 키는 ShopConfig의 개발자 상품", allIn)
end
check("beta: 허용 목록 개발자 상품은 판다", not DataConfig.productBlocked(B, "product", "strengthPotion"))
check("beta: 그 밖의 개발자 상품은 막는다", DataConfig.productBlocked(B, "product", "luckyRoll5") and DataConfig.productBlocked(B, "product", "damagePotion"))
check("beta: 게임패스는 판다", not DataConfig.productBlocked(B, "gamepass", "damage2x") and not DataConfig.productBlocked(B, "gamepass", "strength2x"))
check("studio · live · 환경 없음: 개발자 상품도 판다", not DataConfig.productBlocked(S, "product", "luckyRoll5")
	and not DataConfig.productBlocked(L, "product", "luckyRoll5") and not DataConfig.productBlocked(nil, "product", "luckyRoll5"))
check("beta: 사유 코드 beta_disabled", DataConfig.REASON_BETA_DISABLED == "beta_disabled")

print(string.format("[DataConfigTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[DataConfigTests] %d test(s) failed", failed))
end

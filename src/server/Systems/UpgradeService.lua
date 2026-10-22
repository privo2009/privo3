--!strict
-- 블럭스 상점 업그레이드 (Phase 6 지시서 #7). 레벨 읽기 · 효과 조회 · 구매.
-- 식(효과 · 비용 · 최대 레벨 · 구매 가능 판정)은 전부 Shared/Config/UpgradeConfig가 원본이다 — 여기서 다시 세우지 않는다.
-- 결정과 근거는 DESIGN.md "7. 업그레이드 상점".
--
-- ===== 레벨은 이 파일만 쓴다 ==========================================================
--
-- profile.Data.upgrades[이름]에 대입하는 곳은 이 파일의 setLevel 하나뿐이다(ChallengeService가 progress.*를
-- 소유하는 것과 같은 규칙). 효과를 쓰는 쪽(AttackService · SpeedService · ChallengeService)은 getEffect만 부른다.
-- 환생(RebirthService.runRebirth)은 upgrades를 건드리지 않는다 — 업그레이드는 환생해도 남는다(S5, DESIGN "환생 > 유지").
--
-- ===== 구매 순서 (S8) =================================================================
--
--   1. 노출 항목인가                 아니면 invalid_upgrade
--   2. 프로필 · 레벨 · 잔액 읽기       없으면 no_profile
--   3. UpgradeConfig.canBuy          max_level · max_speed_reached(이동 속도) · insufficient_blox (클라 판정을 믿지 않고 매번 다시 잰다)
--   ----- 여기까지 부작용 0 -----
--   4. CurrencyService.subtract      단일 게이트(절대 규칙 2). 거부되면 insufficient_blox — 아직 부작용 0
--   5. 레벨 + 1                       실패하면 partial_failure (블럭스는 빠졌는데 레벨이 안 올랐다 — ERROR 로그가 유일한 복구 근거)
--   6. 레벨 변경 통지                 SpeedService가 이동속도 최대치를 다시 적용한다
--
-- 왜 차감이 먼저인가: 레벨을 먼저 올리고 차감이 실패하면 공짜 레벨이 생긴다. 둘 다 정상 경로에서는 실패하지 않지만
-- (같은 프로필을 yield 없이 연달아 쓴다), 굳이 고르면 유저가 손해 보는 쪽이 게임이 망가지는 쪽보다 낫다(RebirthService와 같은 판단).
-- 저장은 ProfileStore가 한다(profile.Data를 고치면 다음 자동 저장에 실린다 — PadService와 같다).
--
-- ⚠️ 이 파일은 SpeedService · AttackService · ChallengeService를 require하지 않는다 — 그쪽들이 이 파일을 읽는다(순환 방지).
--    레벨이 바뀐 뒤의 반응은 onLevelChanged에 등록한 쪽이 한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.CurrencyService)

type BigNumber = BigNum.BigNumber

local UpgradeService = {}

UpgradeService.REASON_NO_PROFILE = "no_profile"
UpgradeService.REASON_PARTIAL_FAILURE = "partial_failure"

-- 저장값을 레벨로 읽는다. 없거나 형태가 틀리면 0(Schema.validate가 로드 때 이미 0 이상의 정수를 보장한다 — 방어선).
local function readLevel(data: any, name: string): number
	local upgrades = if type(data) == "table" then data.upgrades else nil
	local raw = if type(upgrades) == "table" then upgrades[name] else nil
	if type(raw) ~= "number" or raw ~= raw or raw < 0 or raw == math.huge then
		return 0
	end
	return math.floor(raw)
end

export type BuyResult = { name: string, level: number, cost: BigNumber }

-- 구매가 바깥 세계에 하는 일 전부. 실제 서비스 대신 기록용 테이블을 넣으면 순서 · 부분 실패를 Player 없이 잰다
-- (RebirthService.Deps · WarpService.Deps와 같은 이음매).
export type Deps = {
	getLevel: (Player, string) -> number?, -- 프로필이 없으면 nil
	getBlox: (Player) -> BigNumber?,
	-- 힘(이동 속도 상한 판정용 — 지시서 #8). 없으면(테스트 deps 등) 그 판정을 건너뛴다
	getStrength: ((Player) -> BigNumber?)?,
	subtractBlox: (Player, BigNumber, string) -> boolean,
	setLevel: (Player, string, number) -> boolean,
	notify: (Player, string, number) -> (),
}

local function runBuy(deps: Deps, player: Player, name: any): (boolean, any)
	-- 1. 노출 항목인가. 이름이 문자열이 아니거나 비노출(Phase 7)이면 거부 — 프로필도 보지 않는다.
	if not UpgradeConfig.isExposed(name) then
		return false, UpgradeConfig.REASON_INVALID_UPGRADE
	end

	-- 2. 지금 레벨 · 잔액.
	local level = deps.getLevel(player, name)
	local blox = deps.getBlox(player)
	if level == nil or blox == nil then
		return false, UpgradeService.REASON_NO_PROFILE
	end

	-- 3. 서버 재판정. 클라가 "살 수 있다"고 보고 보냈어도 여기서 다시 잰다.
	local strength = if deps.getStrength ~= nil then deps.getStrength(player) else nil
	local ok, reason, cost = UpgradeConfig.canBuy(name, level, blox, { strength = strength })
	if not ok or cost == nil then
		return false, reason
	end

	-- ===== 여기부터 부작용 =====

	-- 4. 차감. 단일 게이트. 거부(잔액 부족 등)면 아직 아무것도 안 바뀌었다.
	if not deps.subtractBlox(player, cost, "upgrade_" .. name) then
		return false, UpgradeConfig.REASON_INSUFFICIENT_BLOX
	end

	-- 5. 레벨 + 1.
	local newLevel = level + 1
	if not deps.setLevel(player, name, newLevel) then
		warn(string.format(
			"[UpgradeService] ERROR 부분 실패: %s(%d) %s 블럭스 %s 차감 뒤 레벨 %d → %d 저장 실패",
			player.Name, player.UserId, name, BigNum.tostring(cost), level, newLevel
		))
		return false, UpgradeService.REASON_PARTIAL_FAILURE
	end

	-- 6. 통지.
	deps.notify(player, name, newLevel)

	local result: BuyResult = { name = name, level = newLevel, cost = cost }
	return true, result
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
UpgradeService._pure = {
	runBuy = runBuy,
	readLevel = readLevel,
}

-- ===== 공개 API =======================================================================

-- 레벨. 프로필이 없으면 0 — 효과 쪽은 0레벨 효과(기본값)로 돈다.
function UpgradeService.getLevel(player: Player, name: string): number
	local profile = ProfileManager.get(player)
	if profile == nil then
		return 0
	end
	return readLevel(profile.Data, name)
end

-- 이 플레이어의 지금 효과(UpgradeConfig.getEffect). 효과를 쓰는 곳은 전부 이 함수 하나를 부른다.
function UpgradeService.getEffect(player: Player, name: string): number
	return UpgradeConfig.getEffect(name, UpgradeService.getLevel(player, name))
end

-- 상태 채널용. 8키 전부(비노출 포함). 프로필 Data를 받는다(PlayerStateService.buildSnapshot이 부른다).
function UpgradeService.readLevels(data: any): { [string]: number }
	local out: { [string]: number } = {}
	for name in pairs(UpgradeConfig.Upgrades) do
		out[name] = readLevel(data, name)
	end
	return out
end

local listeners: { (Player, string, number) -> () } = {}

-- 레벨이 바뀌면 부른다(구매 직후). 반응하는 쪽이 등록한다 — 위 "순환 방지".
function UpgradeService.onLevelChanged(callback: (Player, string, number) -> ())
	table.insert(listeners, callback)
end

local REAL: Deps = {
	getLevel = function(player: Player, name: string)
		local profile = ProfileManager.get(player)
		if profile == nil then
			return nil
		end
		return readLevel(profile.Data, name)
	end,
	getBlox = function(player: Player)
		return CurrencyService.get(player, "blox")
	end,
	getStrength = function(player: Player)
		return CurrencyService.get(player, "strength")
	end,
	subtractBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.subtract(player, "blox", amount, reason))
	end,
	setLevel = function(player: Player, name: string, level: number)
		local profile = ProfileManager.get(player)
		if profile == nil or type(profile.Data.upgrades) ~= "table" then
			return false
		end
		profile.Data.upgrades[name] = level
		return true
	end,
	notify = function(player: Player, name: string, level: number)
		for _, callback in ipairs(listeners) do
			-- 반응 하나가 에러를 내도 구매 결과와 다른 반응은 살아야 한다. yield하지 않는 반응만 등록한다.
			local ok, err = pcall(callback, player, name, level)
			if not ok then
				warn(string.format("[UpgradeService] 레벨 변경 반응 실패 (%s → %d): %s", name, level, tostring(err)))
			end
		end
	end,
}

-- 한 레벨 산다.
--   성공  true,  { name, level = 산 뒤 레벨, cost }
--   거부  false, 사유 코드 (UpgradeConfig.REASON_* · REASON_NO_PROFILE · REASON_PARTIAL_FAILURE)
function UpgradeService.buy(player: Player, name: any): (boolean, any)
	local ok, value = runBuy(REAL, player, name)
	if ok then
		print(string.format(
			"[UpgradeService] %s(%d) %s → 레벨 %d (-%s)",
			player.Name, player.UserId, tostring(name), value.level, BigNum.tostring(value.cost)
		))
	end
	return ok, value
end

return UpgradeService

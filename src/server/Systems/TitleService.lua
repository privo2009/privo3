--!strict
-- 타이틀(칭호) 서버 (Phase 7 지시서 #10). 롤 · 자동 롤 · 장착 · 배수 조회. 규칙 원본은 DESIGN.md "6. 뽑기 3종 > 타이틀".
--
-- ===== 칭호 상태는 이 파일만 쓴다 ======================================================
--
-- profile.Data.cosmetics.ownedTitles · equippedTitle, rolling.autoRollTitle에 대입하는 곳은 이 파일뿐이다
-- (UpgradeService가 upgrades를 소유하는 것과 같은 규칙). 배수를 쓰는 쪽(ClickService · ChallengeService)은 getMult만 부른다.
--
-- ===== 롤 순서 ==========================================================================
--
--   1. 프로필 · 칭호 표 읽기            없으면 no_profile
--   2. 롤 시계(G6)                      ROLL_INTERVAL_SEC 안 두 번째 롤이면 rate_limited (수동 · 자동이 같은 시계)
--   2b. 잔액 미리 보기                  비용보다 적으면 insufficient_blox — 차감을 부르지 않는다. 자동 롤이 돈이 떨어진 채 켜져 있으면
--       매 틱 CurrencyService 거부 warn이 찍혔다(2026-10-24 Play). 판정의 권위는 여전히 3번 차감이다(경합 대비)
--   ----- 여기까지 부작용 0 -----
--   3. CurrencyService.subtract(비용)   단일 게이트(절대 규칙 2). 거부면 insufficient_blox — 아직 부작용 0, 시계도 그대로
--   4. 시계 기록 → 행운(RollService.computeLuck) → 순차 판정(RollService.roll — 서버 RNG)
--   5. 새 id      보유 추가 · 더 높은 등급이면 자동 장착 · 저장 1회(Profile:Save, S11) · 자동 롤이면 알림 1건
--      중복 id    아무것도 하지 않는다(알림 · 저장 없음 — 롤 1회당 RemoteEvent 금지, 매 롤 저장 금지)
--
-- 차감이 먼저인 이유는 UpgradeService와 같다 — 판정을 먼저 하고 차감이 실패하면 공짜 칭호가 생긴다.
--
-- ===== 자동 롤 =========================================================================
--
-- 서버 단일 루프 하나가 ROLL_INTERVAL_SEC마다 autoRollTitle인 플레이어를 1회씩 굴린다. 플레이어마다 task.spawn 하지 않는다
-- (AttackService · SpeedService와 같은 구조). 블럭스가 모자라면 그 틱은 건너뛰고 토글은 그대로 둔다.
-- 수동 롤 응답은 요청 채널(TitleRequestService)이 보낸다. 자동 롤은 응답할 요청이 없으므로 **새 칭호일 때만** 여기서 알린다.
--
-- ===== 머리 위 칭호 =====================================================================
--
-- 장착 칭호 id를 Player Attribute(ATTRIBUTE)로 세팅한다 — 서버가 세팅하면 모든 클라에 복제된다.
-- 각 클라가 모든 캐릭터 머리 위에 BillboardGui를 그린다(World/TitleBillboards — 클라 전용, 풀링).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.CurrencyService)
local RollService = require(script.Parent.RollService)

type BigNumber = BigNum.BigNumber

local TitleService = {}

TitleService.ATTRIBUTE = "EquippedTitle"
TitleService.SOURCE_MANUAL = "manual"
TitleService.SOURCE_AUTO = "auto"
TitleService.REASON_NOT_OWNED = "not_owned"
-- 롤 시계 여유. 단일 루프의 task.wait는 요청한 시간 이상 뒤에 깨어나지만, 같은 틱 안의 기록 시각과 다음 틱 사이가
-- 부동소수점으로 간격보다 아주 조금 짧게 잴 수 있다. 그때 자동 롤이 한 틱 걸러 막히지 않게 둔다(Claude 판단).
local CLOCK_EPSILON_SEC = 0.05

export type RollResult = {
	titleId: string,
	index: number, -- 희귀도 단계(TitleConfig.Titles 인덱스)
	isNew: boolean,
	equipped: boolean, -- 이 롤로 장착이 바뀌었는가
}

-- 바깥 세계에 하는 일 전부. 실물 대신 기록용 테이블을 넣으면 순서 · 부작용을 Player 없이 잰다(UpgradeService.Deps와 같은 이음매).
export type Deps = {
	now: () -> number,
	getData: (Player) -> any?, -- profile.Data. 없으면 nil
	getBlox: (Player) -> BigNumber?, -- 잔액 미리 보기(없으면 부족으로 본다)
	subtractBlox: (Player, BigNumber, string) -> boolean,
	roll: (tiers: { TitleConfig.TitleDef }, luck: number) -> (TitleConfig.TitleDef, number),
	save: (Player) -> (),
	notifyAutoNew: (Player, RollResult) -> (), -- 자동 롤로 새 칭호를 얻었을 때만
	setAttribute: (Player, string?) -> (),
}

-- 칭호 표가 쓸 수 있는 모양인가. Schema.validate가 로드 때 보장하지만 방어선을 둔다.
local function titleTables(data: any): (any?, any?)
	if type(data) ~= "table" or type(data.cosmetics) ~= "table" or type(data.rolling) ~= "table" then
		return nil, nil
	end
	if type(data.cosmetics.ownedTitles) ~= "table" then
		return nil, nil
	end
	return data.cosmetics, data.rolling
end

-- 장착 칭호 id(알려진 것만). 없거나 모르는 id면 nil.
local function equippedId(data: any): string?
	local cosmetics = titleTables(data)
	if cosmetics == nil then
		return nil
	end
	local def = TitleConfig.get(cosmetics.equippedTitle)
	return if def ~= nil then def.id else nil
end

local function createRuntime(deps: Deps)
	local lastRollAt: { [Player]: number } = {}
	local runtime = {}

	function runtime.roll(player: Player, source: string): (boolean, any)
		-- 1. 프로필
		local data = deps.getData(player)
		local cosmetics, _rolling = titleTables(data)
		if cosmetics == nil then
			return false, RollService.REASON_NO_PROFILE
		end

		-- 2. 롤 시계 (수동 · 자동 공용)
		local now = deps.now()
		local last = lastRollAt[player]
		if last ~= nil and now - last < TitleConfig.ROLL_INTERVAL_SEC - CLOCK_EPSILON_SEC then
			return false, RollService.REASON_RATE_LIMITED
		end

		-- 2b. 잔액 미리 보기
		local blox = deps.getBlox(player)
		if blox == nil or BigNum.lt(blox, TitleConfig.ROLL_COST) then
			return false, RollService.REASON_INSUFFICIENT_BLOX
		end

		-- ===== 여기부터 부작용 =====

		-- 3. 차감. 거부면 아직 아무것도 안 바뀌었다(시계도).
		if not deps.subtractBlox(player, TitleConfig.ROLL_COST, "title_roll_" .. source) then
			return false, RollService.REASON_INSUFFICIENT_BLOX
		end

		-- 4. 판정
		lastRollAt[player] = now
		local luck = RollService.computeLuck("title", data)
		local def, index = deps.roll(TitleConfig.Titles, luck)

		-- 5. 반영
		local owned = cosmetics.ownedTitles
		if owned[def.id] then
			local dup: RollResult = { titleId = def.id, index = index, isNew = false, equipped = false }
			return true, dup
		end
		owned[def.id] = true
		local equipped = false
		if TitleConfig.isHigher(def.id, cosmetics.equippedTitle) then
			cosmetics.equippedTitle = def.id
			deps.setAttribute(player, def.id)
			equipped = true
		end
		deps.save(player)
		local result: RollResult = { titleId = def.id, index = index, isNew = true, equipped = equipped }
		if source == TitleService.SOURCE_AUTO then
			deps.notifyAutoNew(player, result)
		end
		return true, result
	end

	-- 보유한 것만 장착된다. 같은 것을 다시 장착해도 성공(아무 일 없음).
	function runtime.equip(player: Player, titleId: any): (boolean, string?)
		local cosmetics = titleTables(deps.getData(player))
		if cosmetics == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		local def = TitleConfig.get(titleId)
		if def == nil then
			return false, RollService.REASON_INVALID
		end
		if not cosmetics.ownedTitles[def.id] then
			return false, TitleService.REASON_NOT_OWNED
		end
		cosmetics.equippedTitle = def.id
		deps.setAttribute(player, def.id)
		return true, nil
	end

	function runtime.setAutoRoll(player: Player, on: any): (boolean, string?)
		local _, rolling = titleTables(deps.getData(player))
		if rolling == nil then
			return false, RollService.REASON_NO_PROFILE
		end
		if type(on) ~= "boolean" then
			return false, RollService.REASON_INVALID
		end
		rolling.autoRollTitle = on
		return true, nil
	end

	-- 자동 롤 한 틱. 켠 플레이어를 1회씩 굴린다. 굴린 수를 돌려준다(테스트용). 거부(잔액 부족 · 시계)는 조용히 건너뛴다.
	function runtime.autoTick(players: { Player }): number
		local rolled = 0
		for _, player in ipairs(players) do
			local _, rolling = titleTables(deps.getData(player))
			if rolling ~= nil and rolling.autoRollTitle == true then
				local ok = runtime.roll(player, TitleService.SOURCE_AUTO)
				if ok then
					rolled += 1
				end
			end
		end
		return rolled
	end

	function runtime.onRemoving(player: Player)
		lastRollAt[player] = nil
	end

	return runtime
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
TitleService._pure = {
	createRuntime = createRuntime,
	equippedId = equippedId,
	CLOCK_EPSILON_SEC = CLOCK_EPSILON_SEC,
}

-- ===== 공개 API =========================================================================

-- 장착 칭호 배수(힘 = 블럭스). 프로필이 없거나 장착이 없으면 1. ClickService · ChallengeService가 부른다.
function TitleService.getMult(player: Player): number
	local profile = ProfileManager.get(player)
	if profile == nil then
		return 1
	end
	return TitleConfig.multOf(equippedId(profile.Data))
end

-- 상태 채널 요약(PlayerStateService.buildSnapshot이 부른다). owned는 희귀도 순, equipped는 없으면 "".
export type TitleSummary = { owned: { string }, equipped: string, autoRoll: boolean }
function TitleService.summarize(data: any): TitleSummary
	local cosmetics, rolling = titleTables(data)
	local owned: { string } = {}
	if cosmetics ~= nil then
		for _, def in ipairs(TitleConfig.Titles) do
			if cosmetics.ownedTitles[def.id] then
				table.insert(owned, def.id)
			end
		end
	end
	return {
		owned = owned,
		equipped = equippedId(data) or "",
		autoRoll = rolling ~= nil and rolling.autoRollTitle == true,
	}
end

local autoNewListeners: { (Player, RollResult) -> () } = {}

-- 자동 롤로 새 칭호를 얻으면 부른다(TitleRequestService가 등록해 클라에 알린다 — 이 파일은 Remotes를 모른다).
function TitleService.onAutoNew(callback: (Player, RollResult) -> ())
	table.insert(autoNewListeners, callback)
end

local function setAttribute(player: Player, id: string?)
	if typeof(player) == "Instance" and player:IsA("Player") then
		player:SetAttribute(TitleService.ATTRIBUTE, id)
	end
end

local REAL: Deps = {
	now = os.clock,
	getData = function(player: Player)
		local profile = ProfileManager.get(player)
		return if profile ~= nil then profile.Data else nil
	end,
	getBlox = function(player: Player)
		return CurrencyService.get(player, "blox")
	end,
	subtractBlox = function(player: Player, amount: BigNumber, reason: string)
		return (CurrencyService.subtract(player, "blox", amount, reason))
	end,
	roll = function(tiers, luck)
		return RollService.roll(tiers, luck)
	end,
	save = function(player: Player)
		-- S11: 새 id를 처음 얻었을 때만. 고정 주기 저장 루프는 없다(ProfileStore 자동 저장).
		ProfileManager.save(player)
	end,
	notifyAutoNew = function(player: Player, result: RollResult)
		print(string.format(
			"[TitleService] %s(%d) 새 칭호 %s (단계 %d, auto)%s",
			player.Name, player.UserId, result.titleId, result.index, if result.equipped then " → 자동 장착" else ""
		))
		for _, callback in ipairs(autoNewListeners) do
			local ok, err = pcall(callback, player, result)
			if not ok then
				warn("[TitleService] 자동 롤 알림 실패: " .. tostring(err))
			end
		end
	end,
	setAttribute = setAttribute,
}

local runtime = createRuntime(REAL)

-- 1회 롤. source = SOURCE_MANUAL | SOURCE_AUTO.
--   성공  true,  RollResult
--   거부  false, 사유 코드 (RollService.REASON_*)
function TitleService.roll(player: Player, source: string): (boolean, any)
	local ok, value = runtime.roll(player, source)
	if ok and value.isNew then
		print(string.format(
			"[TitleService] %s(%d) 새 칭호 %s (단계 %d, %s)%s",
			player.Name, player.UserId, value.titleId, value.index, source, if value.equipped then " → 자동 장착" else ""
		))
	end
	return ok, value
end

function TitleService.equip(player: Player, titleId: any): (boolean, string?)
	return runtime.equip(player, titleId)
end

function TitleService.setAutoRoll(player: Player, on: any): (boolean, string?)
	local ok, reason = runtime.setAutoRoll(player, on)
	if ok then
		print(string.format("[TitleService] %s(%d) 자동 롤 %s", player.Name, player.UserId, if on then "켬" else "끔"))
	end
	return ok, reason
end

local initialized = false

function TitleService.init()
	if initialized then
		warn("[TitleService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	-- 접속 시 머리 위 칭호(Attribute)를 세운다. 모르는 id(옛 프로필)는 세우지 않는다.
	local function onLoaded(player: Player, profile: any)
		setAttribute(player, equippedId(profile.Data))
	end
	ProfileManager.onLoaded(onLoaded)
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = ProfileManager.get(player)
		if profile ~= nil then
			onLoaded(player, profile)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)

	-- 자동 롤 서버 단일 루프.
	task.spawn(function()
		while true do
			task.wait(TitleConfig.ROLL_INTERVAL_SEC)
			local ok, err = pcall(runtime.autoTick, Players:GetPlayers())
			if not ok then
				warn("[TitleService] 자동 롤 틱 실패: " .. tostring(err))
			end
		end
	end)

	print(string.format("[TitleService] 준비 완료 (롤 %s 블럭스, %g초에 1회 · 자동 롤 단일 루프)", BigNum.tostring(TitleConfig.ROLL_COST), TitleConfig.ROLL_INTERVAL_SEC))
end

return TitleService

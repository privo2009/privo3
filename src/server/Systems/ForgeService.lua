--!strict
-- 대장간 서버(지시서 #33 — DESIGN 16장 "제작" · "대장간 화면").
--
-- 서버 권위(CLAUDE.md 절대 규칙 3) — 클라 ForgeRequest는 "요청"일 뿐이다:
--   제작      대장간이 열렸나(forgeOpen) · 조합 모양(광석 번호 × CRAFT_INPUT) · 그만큼 광석이 있나 · 칸 수는 서버가 다시 센다(slotsOf) ·
--             결과는 서버 난수(EconomyV2Logic.rollCraft) · 지급은 InventoryService.craft 한 번(광석 차감 · 곡괭이 +1 · 칸별 토큰 — 전부 아니면 없음)
--   간격      서버가 강제한다(EconomyV2Logic.craftStep): 무료 = 스킵 시점(CRAFT_SKIP_SEC)마다 1회 · 연출 생략 보유 = 최소 간격마다 1회 ·
--             트리플 보유 = 한 번에 TRIPLE_CRAFT_COUNT회(광석 × 3). 상품 ID 자리가 nil이면 보유 없음(= 무료와 같다 — 상품 코드는 #35)
--   자동 제작  무료 토글. 고른 조합(또는 자동 채우기)을 서버 단일 루프가 간격마다 반복한다. **접속 중에만** — 저장하지 않는다(나가면 끝).
--             광석이 모자라면 멈추고 알린다(auto_state reason)
--   교환      토큰 수 확인 → InventoryService.exchange 한 번(토큰 차감 · 곡괭이 지급). ??? 토큰(next)은 교환할 곡괭이가 없다(잠긴 칸)
-- 결과는 EconomyEvent(kind forge_state · craft_result · exchange_result · auto_state)로 요청한 사람에게만 보낸다.
-- 확률표는 클라가 같은 공유 로직(EconomyV2Logic.oddsFor)으로 그린다 — 표의 원본은 Config 하나다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ForgeService = {}

ForgeService.KIND = "pickaxe"
ForgeService.REQUEST_MIN_GAP_SEC = 0.15 -- 같은 사람 요청 연타 상한(판정 전에 버린다)

export type AutoState = { on: boolean, combo: { number }?, fill: boolean, count: number }
export type PlayerForge = { nextAt: number, lastRequestAt: number, auto: AutoState }

export type Deps = {
	isForgeOpen: (Player) -> boolean,
	getOres: (Player) -> { number }?,
	getTokens: (Player) -> { [string]: number }?,
	getOwned: (Player) -> { [string]: number }?,
	craft: (Player, { [number]: number }, string, { string }, { [string]: number }, string) -> boolean,
	exchange: (Player, string, string, { [string]: number }, string) -> boolean,
	ownsSkipPass: (Player) -> boolean,
	ownsTriple: (Player) -> boolean,
	send: (Player, any) -> (),
	rand: () -> number,
	now: () -> number,
	afterGrant: ((Player) -> ())?, -- 곡괭이를 얻은 뒤(#34 — 장비 화면 상태 다시 보내기). 없으면 안 부른다
}

-- ===== 순수 로직 (Player · 프로필 없음 — ForgeServiceTests가 _pure로 부른다) ===============================

local function newPlayerForge(): PlayerForge
	return { nextAt = 0, lastRequestAt = -math.huge, auto = { on = false, combo = nil, fill = true, count = 0 } }
end

-- 이번 제작에 쓸 조합을 정한다. fill이면 가진 광석으로 가장 높은 칸 조합(높은 광석은 아낀다 — bestCombo).
-- 아니면 요청 조합 모양을 검사한다. 사유: "bad_combo" · "not_enough_ore"
local function chooseCombo(inv: { number }, combo: any, fill: boolean): ({ number }?, string?)
	if fill then
		local best = EconomyV2Logic.bestCombo(inv)
		if best == nil then
			return nil, "not_enough_ore"
		end
		return best, nil
	end
	if not EconomyV2Logic.isCombo(combo) then
		return nil, "bad_combo"
	end
	local clean = table.clone(combo :: { number })
	table.sort(clean)
	if EconomyV2Logic.comboTimes(inv, clean) < 1 then
		return nil, "not_enough_ore"
	end
	return clean, nil
end

export type CraftPlan = { combo: { number }, times: number, slots: number, ids: { string }, tokens: { [string]: number }, step: number }

-- 제작 한 번(버튼 한 번 · 자동 1틱)을 계획한다 — 바꾸는 것은 없다. 사유: "forge_closed" · "too_soon" · "bad_combo" · "not_enough_ore"
local function planCraft(open: boolean, pf: PlayerForge, now: number, inv: { number }, combo: any, fill: boolean, skipPass: boolean,
	triple: boolean, rand: () -> number): (CraftPlan?, string?)
	if not open then
		return nil, "forge_closed"
	end
	if now < pf.nextAt - 1e-6 then
		return nil, "too_soon"
	end
	local chosen, why = chooseCombo(inv, combo, fill)
	if chosen == nil then
		return nil, why
	end
	local step, per = EconomyV2Logic.craftStep(skipPass, triple)
	if EconomyV2Logic.comboTimes(inv, chosen) < per then
		return nil, "not_enough_ore" -- 트리플은 광석 CRAFT_INPUT × 3개가 있어야 한다
	end
	local slots = EconomyV2Logic.slotsOf(chosen) -- 칸은 서버가 다시 센다
	local ids = {}
	local tokens: { [string]: number } = {}
	for _ = 1, per do
		table.insert(ids, EconomyV2Logic.rollCraft(slots, rand))
		for r, c in pairs(EconomyV2Logic.tokensFor(slots)) do
			tokens[r] = (tokens[r] or 0) + c
		end
	end
	return { combo = chosen, times = per, slots = slots, ids = ids, tokens = tokens, step = step }, nil
end

-- 교환 검사. 사유: "forge_closed" · "unknown" · "not_exchangeable" · "not_enough_tokens"
local function planExchange(open: boolean, tokens: { [string]: number }, id: any): (Config.PickaxeDef?, string?)
	if not open then
		return nil, "forge_closed"
	end
	if type(id) ~= "string" then
		return nil, "unknown"
	end
	local def = EconomyV2Logic.pickaxe(id)
	if def == nil then
		return nil, "unknown"
	end
	if def.exchangeCost == nil then
		return nil, "not_exchangeable"
	end
	if (tokens[def.rarity] or 0) < (def.exchangeCost :: number) then
		return nil, "not_enough_tokens"
	end
	return def, nil
end

ForgeService._pure = {
	newPlayerForge = newPlayerForge,
	chooseCombo = chooseCombo,
	planCraft = planCraft,
	planExchange = planExchange,
}

-- ===== 바깥 세계 이음매 (테스트가 기록용으로 바꿔 끼운다 — 바꾼 뒤 반드시 되돌릴 것) ======================

local function liveDeps(): Deps
	local InventoryService = require(script.Parent.InventoryService)
	local channels = Remotes.getServer()
	local rng = Random.new()
	return {
		isForgeOpen = InventoryService.isForgeOpen,
		getOres = InventoryService.getOres,
		getTokens = InventoryService.getTokens,
		getOwned = function(player)
			return InventoryService.getOwned(player, ForgeService.KIND)
		end,
		craft = InventoryService.craft,
		exchange = InventoryService.exchange,
		-- 즉시 제작 · 트리플 제작(#35 — ShopConfig 키 · 제한 지역이면 끔). ID가 nil이면 상품 표에 없어 보유 없음 = 무료와 같다
		ownsSkipPass = function(player)
			return require(script.Parent.ShopEffects).v2PassActive(player, "instantCraft")
		end,
		ownsTriple = function(player)
			return require(script.Parent.ShopEffects).v2PassActive(player, "tripleCraft")
		end,
		send = function(player, payload)
			if typeof(player) == "Instance" and player:IsA("Player") then
				channels.economyEvent:FireClient(player, payload)
			end
		end,
		rand = function()
			return rng:NextNumber()
		end,
		now = os.clock,
		afterGrant = function(player)
			require(script.Parent.EquipmentService).sendState(player)
		end,
	}
end

ForgeService._deps = nil :: Deps?

local function deps(): Deps
	if ForgeService._deps == nil then
		ForgeService._deps = liveDeps()
	end
	return ForgeService._deps :: Deps
end

local states: { [Player]: PlayerForge } = {}

local function stateOf(player: Player): PlayerForge
	local s = states[player]
	if s == nil then
		s = newPlayerForge()
		states[player] = s
	end
	return s
end

local function ownsSkip(player: Player): boolean
	return Config.CRAFT_SKIP_PASS_ID ~= nil and deps().ownsSkipPass(player)
end

local function ownsTriple(player: Player): boolean
	return Config.TRIPLE_CRAFT_PASS_ID ~= nil and deps().ownsTriple(player)
end

local function autoView(pf: PlayerForge): any
	return { on = pf.auto.on, count = pf.auto.count }
end

function ForgeService.sendState(player: Player)
	local d = deps()
	d.send(player, {
		kind = "forge_state",
		tokens = d.getTokens(player) or {},
		owned = d.getOwned(player) or {},
		ores = d.getOres(player) or EconomyV2Logic.newInv(),
		auto = autoView(stateOf(player)),
	})
end

-- 제작 한 번. auto = 자동 제작 루프에서 불렀나. 성공이면 (true), 아니면 (false, 사유). 결과 신호를 보낸다(자동의 too_soon은 조용히).
function ForgeService.craft(player: Player, combo: any, fill: boolean, auto: boolean): (boolean, string?)
	local d = deps()
	local pf = stateOf(player)
	local inv = d.getOres(player)
	if inv == nil then
		return false, "no_profile"
	end
	local before = d.getOwned(player) or {}
	local plan, why = planCraft(d.isForgeOpen(player), pf, d.now(), inv, combo, fill, ownsSkip(player), ownsTriple(player), d.rand)
	if plan == nil then
		if not (auto and why == "too_soon") then
			d.send(player, { kind = "craft_result", ok = false, reason = why, auto = auto })
		end
		return false, why
	end
	local reason = if auto then "forge_auto_craft" else "forge_craft"
	if not d.craft(player, EconomyV2Logic.comboCounts(plan.combo, plan.times), ForgeService.KIND, plan.ids, plan.tokens, reason) then
		d.send(player, { kind = "craft_result", ok = false, reason = "grant_failed", auto = auto })
		return false, "grant_failed"
	end
	pf.nextAt = d.now() + plan.step
	if auto then
		pf.auto.count += plan.times
	end
	local isNew = {}
	local seen: { [string]: boolean } = {}
	for i, id in ipairs(plan.ids) do
		isNew[i] = before[id] == nil and not seen[id]
		seen[id] = true
	end
	d.send(player, {
		kind = "craft_result",
		ok = true,
		ids = plan.ids,
		isNew = isNew,
		slots = plan.slots,
		combo = plan.combo,
		tokens = plan.tokens,
		auto = auto,
		autoCount = pf.auto.count,
		nextIn = plan.step,
		ores = d.getOres(player) or EconomyV2Logic.newInv(),
		tokensTotal = d.getTokens(player) or {},
		owned = d.getOwned(player) or {},
	})
	if d.afterGrant ~= nil then
		d.afterGrant(player)
	end
	return true, nil
end

function ForgeService.setAuto(player: Player, on: boolean, combo: any, fill: boolean)
	local d = deps()
	local pf = stateOf(player)
	if on then
		if not d.isForgeOpen(player) then
			d.send(player, { kind = "auto_state", on = false, count = pf.auto.count, reason = "forge_closed" })
			return
		end
		if not fill and not EconomyV2Logic.isCombo(combo) then
			d.send(player, { kind = "auto_state", on = false, count = pf.auto.count, reason = "bad_combo" })
			return
		end
		pf.auto = { on = true, combo = if fill then nil else table.clone(combo), fill = fill, count = 0 }
	else
		pf.auto.on = false
	end
	d.send(player, { kind = "auto_state", on = pf.auto.on, count = pf.auto.count })
end

-- 자동 제작 1틱(루프 · 테스트). 간격이 안 됐으면 아무것도 안 한다. 광석이 모자라거나 닫혔으면 멈추고 알린다.
function ForgeService.autoTick(player: Player)
	local pf = states[player]
	if pf == nil or not pf.auto.on then
		return
	end
	local ok, why = ForgeService.craft(player, pf.auto.combo, pf.auto.fill, true)
	if not ok and why ~= "too_soon" then
		pf.auto.on = false
		deps().send(player, { kind = "auto_state", on = false, count = pf.auto.count, reason = why })
	end
end

function ForgeService.exchange(player: Player, id: any): (boolean, string?)
	local d = deps()
	local tokens = d.getTokens(player)
	if tokens == nil then
		return false, "no_profile"
	end
	local def, why = planExchange(d.isForgeOpen(player), tokens, id)
	if def == nil then
		d.send(player, { kind = "exchange_result", ok = false, reason = why })
		return false, why
	end
	local cost = { [def.rarity] = def.exchangeCost :: number }
	if not d.exchange(player, ForgeService.KIND, def.id, cost, "forge_exchange") then
		d.send(player, { kind = "exchange_result", ok = false, reason = "grant_failed" })
		return false, "grant_failed"
	end
	d.send(player, { kind = "exchange_result", ok = true, id = def.id, tokensTotal = d.getTokens(player) or {}, owned = d.getOwned(player) or {} })
	if d.afterGrant ~= nil then
		d.afterGrant(player)
	end
	return true, nil
end

-- 클라 요청 한 건(검증 · 연타 상한). 모르는 꼴은 조용히 버린다.
function ForgeService.handleRequest(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return
	end
	local d = deps()
	local pf = stateOf(player)
	local now = d.now()
	if now - pf.lastRequestAt < ForgeService.REQUEST_MIN_GAP_SEC then
		return
	end
	pf.lastRequestAt = now
	local fill = payload.fill == true
	if payload.action == "craft" then
		ForgeService.craft(player, payload.combo, fill, false)
	elseif payload.action == "auto" then
		ForgeService.setAuto(player, payload.on == true, payload.combo, fill)
	elseif payload.action == "exchange" then
		ForgeService.exchange(player, payload.id)
	elseif payload.action == "sync" then
		ForgeService.sendState(player)
	end
end

-- 테스트 전용
function ForgeService._state(player: Player): PlayerForge?
	return states[player]
end
function ForgeService._reset(player: Player)
	states[player] = nil
end

local initialized = false

-- 테스트 전용: init이 불렸나(플래그가 꺼져 있으면 Bootstrap이 부르지 않는다)
function ForgeService._initialized(): boolean
	return initialized
end

function ForgeService.init()
	if initialized then
		return
	end
	initialized = true
	local channels = Remotes.getServer()
	channels.forgeRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local ok, err = pcall(ForgeService.handleRequest, player, payload)
		if not ok then
			warn("[ForgeService] 요청 오류: " .. tostring(err))
		end
	end)
	-- 자동 제작: 서버 단일 루프(플레이어별 task.spawn 아님)
	task.spawn(function()
		while true do
			task.wait(Config.AUTO_CRAFT_POLL_SEC)
			for player, pf in pairs(states) do
				if pf.auto.on then
					local ok, err = pcall(ForgeService.autoTick, player)
					if not ok then
						warn("[ForgeService] 자동 제작 오류: " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil -- 자동 제작은 접속 중에만(저장하지 않는다)
	end)
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	ProfileManager.onLoaded(function(player: Player)
		ForgeService.sendState(player)
	end)
	print(string.format("[ForgeService] 대장간 시작 (무료 간격 %.1f초 · 연출 %.1f초 · 생략 상품 %s · 트리플 상품 %s)", Config.CRAFT_SKIP_SEC,
		Config.CRAFT_ANIM_SEC, tostring(Config.CRAFT_SKIP_PASS_ID), tostring(Config.TRIPLE_CRAFT_PASS_ID)))
end

return ForgeService

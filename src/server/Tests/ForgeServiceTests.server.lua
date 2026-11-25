--!strict
-- 대장간 서버 검증(지시서 #33).
-- ForgeService._deps를 기록용 가짜로 바꿔 끼우고(끝나면 되돌린다), 지급은 InventoryService 순수 함수를 Schema.new() 데이터에 그대로 태운다 —
-- 프로필 · RemoteEvent를 쓰지 않는다.
--   점수 표 → 칸 · 자동 채우기 · 제작 검증(닫힘 · 광석 부족 · 개수 · 모양) · 토큰 지급 · 난수 주입 결과 · 간격 강제(무료 · 생략 · 트리플) ·
--   자동 제작 반복 · 멈춤 · 교환(비용 · 부족 · ??? 잠김 · 일반 없음) · 확률 표시(합 · 0% 금지) · 지급 원자성 · 플래그 꺼짐이면 init 없음
-- 숫자는 Config에서 읽는다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Schema = require(ServerScriptService.Server.Data.Schema)
local InventoryService = require(ServerScriptService.Server.Systems.InventoryService)
local ForgeService = require(ServerScriptService.Server.Systems.ForgeService)

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

local N = Config.CRAFT_INPUT
local IP = InventoryService._pure
local FP = ForgeService._pure

-- 1. 점수 표 → 칸 · 자동 채우기 ---------------------------------------------------------------------
do
	local pts = Config.ORE_POINTS
	check("점수 표: 구리 1 · 주석 1 · 철 2 · 은 2 · 금 3 · 비취 4 · 루비 5 · 사파이어 6 · 자수정 8 · 별빛석 10(TEMP)",
		table.concat(pts, ",") == "1,1,2,2,3,4,5,6,8,10" and L.gaugePoints(7) == 5)
	-- 그 층 광석 5개 → 칸 → 토큰 등급(#33 결정: 희귀 6 ~ 8층 · 에픽 14 · 신화 20 · 전설 23 · ??? 25)
	local function slotsAt(stage: number): number
		local k = L.oreOf(stage)
		return L.slotsOf({ k, k, k, k, k })
	end
	check("점수 표: 층 → 토큰 등급(5층 0칸 · 6층 희귀 · 14층 에픽 · 20층 신화 · 23층 전설 · 25층 ???)",
		slotsAt(5) == 0 and L.tokensFor(slotsAt(6)).rare == 1 and L.tokensFor(slotsAt(14)).epic == 1 and L.tokensFor(slotsAt(20)).mythic == 1
			and L.tokensFor(slotsAt(23)).legendary == 1 and L.tokensFor(slotsAt(25)).next == 1 and slotsAt(13) == 1 and slotsAt(19) == 2
			and slotsAt(22) == 3 and slotsAt(24) == 4)
	local inv = L.newInv()
	inv[1], inv[6], inv[7] = 5, 5, 2 -- 구리 1점 · 비취 4점 · 루비 5점
	local combo, slots = L.bestCombo(inv)
	local sum = 0
	for _, k in ipairs(combo or {}) do
		sum += L.gaugePoints(k)
	end
	-- 가장 높은 5개 = 7 · 7 · 6 · 6 · 6 = 22점 → 2칸. 2칸(20점)을 가장 적은 점수로 = 비취 × 5(루비를 아낀다)
	check("자동 채우기: 가장 높은 칸 · 같은 칸이면 점수 합 최소(높은 광석을 아낀다)", combo ~= nil and slots == 2 and sum == 20
		and table.concat(combo :: { number }, ",") == "6,6,6,6,6", table.concat(combo or {}, ","))
	check("자동 채우기: 광석 5개 미만이면 없음", L.bestCombo({ 4, 0, 0, 0, 0, 0, 0, 0, 0, 0 }) == nil)
end

-- 2. 확률 표시: 합 · 0% 금지 ---------------------------------------------------------------------------
do
	local sumOk, zeroOk = true, true
	for s = 0, N do
		local sum = 0
		for _, row in ipairs(L.oddsFor(s)) do
			sum += row.pct
			local t = L.formatPct(row.pct)
			if row.pct > 0 then
				zeroOk = zeroOk and t ~= "0%" and string.match(t, "[1-9]") ~= nil
			else
				zeroOk = zeroOk and t == "0%"
			end
		end
		sumOk = sumOk and math.abs(sum - 100) < 1e-9
	end
	check("확률 표시: 칸마다 15종 합 100%", sumOk)
	check("확률 표시: 0이 아닌 확률은 0%로 보이지 않는다(전설 같은 아주 작은 값도 유효 숫자)", zeroOk)
	check("확률 표시: 꼴(40% · 12.5% · 0.05% · 0.0033%)", L.formatPct(40) == "40%" and L.formatPct(12.5) == "12.5%" and L.formatPct(0.05) == "0.05%"
		and L.formatPct(0.00333) == "0.0033%", L.formatPct(0.00333))
end

-- 3. 가짜 세계 ---------------------------------------------------------------------------------------
type World = { data: any, open: boolean, now: number, sent: { any }, rolls: { number }, skip: boolean, triple: boolean }

local savedDeps = ForgeService._deps
local savedSkip, savedTriple = Config.CRAFT_SKIP_PASS_ID, Config.TRIPLE_CRAFT_PASS_ID

local function newWorld(): (World, any)
	local data = Schema.new()
	local w: World = { data = data, open = true, now = 100, sent = {}, rolls = {}, skip = false, triple = false }
	local p = { Name = "ForgeFake" } :: any
	ForgeService._deps = {
		isForgeOpen = function()
			return w.open
		end,
		getOres = function()
			return table.clone(w.data.ores)
		end,
		getTokens = function()
			return table.clone(w.data.tokens)
		end,
		getOwned = function()
			local out = {}
			for id, o in pairs(w.data.equipment.pickaxe) do
				out[id] = o.count
			end
			return out
		end,
		craft = function(_p, take, kind, ids, tokens, _reason)
			return (IP.applyChecked(w.data, function(d)
				return IP.applyCraft(d, take, kind, ids, tokens)
			end))
		end,
		exchange = function(_p, kind, id, tokens, _reason)
			return (IP.applyChecked(w.data, function(d)
				return IP.applyExchange(d, kind, id, tokens)
			end))
		end,
		ownsSkipPass = function()
			return w.skip
		end,
		ownsTriple = function()
			return w.triple
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
		rand = function()
			local v = table.remove(w.rolls, 1)
			return v or 0
		end,
		now = function()
			return w.now
		end,
	}
	ForgeService._reset(p)
	return w, p
end

local function last(w: World, kind: string): any
	for i = #w.sent, 1, -1 do
		if w.sent[i].kind == kind then
			return w.sent[i]
		end
	end
	return nil
end

local function setOres(w: World, counts: { [number]: number })
	for k = 1, Config.ORE_COUNT do
		w.data.ores[k] = counts[k] or 0
	end
end

local okRun, errRun = pcall(function()
	-- 4. 제작 검증 -----------------------------------------------------------------------------------
	do
		local w, p = newWorld()
		setOres(w, { [10] = 5 })
		w.open = false
		local ok1, why1 = ForgeService.craft(p, { 10, 10, 10, 10, 10 }, false, false)
		check("제작 거부: 대장간이 닫혀 있으면 forge_closed · 광석 그대로", not ok1 and why1 == "forge_closed" and w.data.ores[10] == 5)
		w.open = true
		local ok2, why2 = ForgeService.craft(p, { 10, 10, 10, 10 }, false, false)
		local ok3, why3 = ForgeService.craft(p, { 10, 10, 10, 10, 11 }, false, false)
		local ok4, why4 = ForgeService.craft(p, { 10, 10, 10, 10, 1.5 }, false, false)
		check("제작 거부: 개수 ≠ 5 · 없는 광석 · 정수 아님 → bad_combo", not ok2 and why2 == "bad_combo" and not ok3 and why3 == "bad_combo"
			and not ok4 and why4 == "bad_combo")
		local ok5, why5 = ForgeService.craft(p, { 9, 10, 10, 10, 10 }, false, false)
		check("제작 거부: 가진 광석이 모자라면 not_enough_ore · 그대로", not ok5 and why5 == "not_enough_ore" and w.data.ores[10] == 5)
		local r = last(w, "craft_result")
		check("제작 거부: 결과 신호 ok false · 사유", r ~= nil and r.ok == false and r.reason == "not_enough_ore")
	end

	-- 5. 토큰 지급 · 난수 주입 결과 · 칸은 서버가 다시 센다 ---------------------------------------------------
	do
		local w, p = newWorld()
		setOres(w, { [10] = 5, [1] = 5 })
		w.rolls = { 0.999999999 } -- 5칸 확률표의 마지막 줄(확률이 있는 마지막 곡괭이)
		local ok = ForgeService.craft(p, { 10, 10, 10, 10, 10 }, false, false)
		local lastId
		for _, row in ipairs(L.oddsFor(N)) do
			if row.pct > 0 then
				lastId = row.id
			end
		end
		local r = last(w, "craft_result")
		check("제작: 난수 주입 결과 = 확률표 그대로 · 곡괭이 +1", ok and r ~= nil and r.ids[1] == lastId and w.data.equipment.pickaxe[lastId] ~= nil)
		check("제작: 5칸 토큰(전설 1 · ??? 1) · 광석 5개 차감", w.data.tokens.legendary == 1 and w.data.tokens.next == 1 and w.data.ores[10] == 0
			and r.slots == N and r.isNew[1] == true)
		w.now += Config.CRAFT_SKIP_SEC
		w.rolls = { 0 }
		local ok2 = ForgeService.craft(p, { 1, 1, 1, 1, 1 }, false, false)
		local r2 = last(w, "craft_result")
		check("제작: 0칸 토큰 없음 · 같은 곡괭이면 개수 +1(isNew false)", ok2 and r2.slots == 0 and w.data.tokens.rare == 0
			and (r2.ids[1] ~= Config.START_PICKAXE or (w.data.equipment.pickaxe[Config.START_PICKAXE].count == 2 and r2.isNew[1] == false)))
	end

	-- 6. 간격 강제(무료 · 생략 · 트리플) ----------------------------------------------------------------
	do
		local w, p = newWorld()
		setOres(w, { [1] = 30 })
		local c = { 1, 1, 1, 1, 1 }
		local a = ForgeService.craft(p, c, false, false)
		w.now += Config.CRAFT_SKIP_SEC - 0.1
		local b, whyB = ForgeService.craft(p, c, false, false)
		w.now += 0.1
		local d = ForgeService.craft(p, c, false, false)
		check("간격(무료): 스킵 시점(CRAFT_SKIP_SEC) 전에는 too_soon · 지나면 된다", a and not b and whyB == "too_soon" and d)
		-- 연출 생략: ID 자리가 nil이면 보유해도 무료와 같다
		Config.CRAFT_SKIP_PASS_ID = nil
		w.skip = true
		w.now += Config.CRAFT_MIN_INTERVAL_SEC
		local e = ForgeService.craft(p, c, false, false)
		check("간격(생략): 상품 ID nil이면 무료 간격 그대로", not e)
		Config.CRAFT_SKIP_PASS_ID = 1
		w.now += Config.CRAFT_SKIP_SEC
		local f = ForgeService.craft(p, c, false, false)
		w.now += Config.CRAFT_MIN_INTERVAL_SEC
		local g = ForgeService.craft(p, c, false, false)
		check("간격(생략): 보유자는 최소 간격마다 1회", f and g)
		Config.CRAFT_SKIP_PASS_ID = savedSkip
		w.skip = false
		-- 트리플: 한 번에 3회 · 광석 15개
		Config.TRIPLE_CRAFT_PASS_ID = 1
		w.triple = true
		setOres(w, { [1] = Config.TRIPLE_CRAFT_COUNT * N })
		w.now += Config.CRAFT_SKIP_SEC
		local before = 0
		for _, o in pairs(w.data.equipment.pickaxe) do
			before += o.count
		end
		local t = ForgeService.craft(p, c, false, false)
		local after = 0
		for _, o in pairs(w.data.equipment.pickaxe) do
			after += o.count
		end
		check("트리플: 한 번에 3회 · 광석 15개 · 곡괭이 +3", t and w.data.ores[1] == 0 and after - before == Config.TRIPLE_CRAFT_COUNT
			and #last(w, "craft_result").ids == Config.TRIPLE_CRAFT_COUNT)
		setOres(w, { [1] = Config.TRIPLE_CRAFT_COUNT * N - 1 })
		w.now += Config.CRAFT_SKIP_SEC
		local t2, whyT = ForgeService.craft(p, c, false, false)
		check("트리플: 광석이 15개 미만이면 not_enough_ore · 그대로", not t2 and whyT == "not_enough_ore" and w.data.ores[1] == Config.TRIPLE_CRAFT_COUNT * N - 1)
		Config.TRIPLE_CRAFT_PASS_ID = savedTriple
	end

	-- 7. 자동 제작: 반복 · 멈춤 ---------------------------------------------------------------------------
	do
		local w, p = newWorld()
		setOres(w, { [1] = 12 })
		ForgeService.setAuto(p, true, nil, true)
		local st = ForgeService._state(p)
		check("자동 제작: 켜짐 신호", st ~= nil and st.auto.on and last(w, "auto_state").on == true)
		ForgeService.autoTick(p)
		ForgeService.autoTick(p) -- 간격 전 — 조용히 넘어간다
		w.now += Config.CRAFT_SKIP_SEC
		ForgeService.autoTick(p)
		check("자동 제작: 간격마다 1회 반복(2회 · 광석 10개)", st.auto.count == 2 and w.data.ores[1] == 2 and last(w, "craft_result").auto == true)
		w.now += Config.CRAFT_SKIP_SEC
		ForgeService.autoTick(p)
		local s = last(w, "auto_state")
		check("자동 제작: 광석이 모자라면 멈추고 알린다(not_enough_ore)", not st.auto.on and s.on == false and s.reason == "not_enough_ore" and s.count == 2)
		ForgeService.setAuto(p, true, { 1, 1 }, false)
		check("자동 제작: 조합 모양이 틀리면 켜지 않는다", not st.auto.on and last(w, "auto_state").reason == "bad_combo")
		w.open = false
		ForgeService.setAuto(p, true, nil, true)
		check("자동 제작: 대장간이 닫혀 있으면 켜지 않는다", not st.auto.on and last(w, "auto_state").reason == "forge_closed")
	end

	-- 8. 교환 -----------------------------------------------------------------------------------------
	do
		local w, p = newWorld()
		local def: any = nil
		for _, d in ipairs(Config.PICKAXES) do
			if d.rarity == "epic" and def == nil then
				def = d
			end
		end
		w.data.tokens.epic = def.exchangeCost - 1
		local a, whyA = ForgeService.exchange(p, def.id)
		check("교환: 토큰이 모자라면 not_enough_tokens · 그대로", not a and whyA == "not_enough_tokens" and w.data.tokens.epic == def.exchangeCost - 1
			and w.data.equipment.pickaxe[def.id] == nil)
		w.data.tokens.epic += 1
		local b = ForgeService.exchange(p, def.id)
		local r = last(w, "exchange_result")
		check("교환: 비용만큼 차감 · 곡괭이 지급 · 결과 신호", b and w.data.tokens.epic == 0 and w.data.equipment.pickaxe[def.id].count == 1 and r.ok == true
			and r.owned[def.id] == 1)
		local c, whyC = ForgeService.exchange(p, Config.START_PICKAXE)
		local d, whyD = ForgeService.exchange(p, "next")
		w.data.tokens.next = 99
		local e, whyE = ForgeService.exchange(p, Config.NEXT_RARITY)
		check("교환: 일반은 없음 · ???(next)는 잠김(교환할 곡괭이 없음)", not c and whyC == "not_exchangeable" and not d and whyD == "unknown"
			and not e and whyE == "unknown" and w.data.tokens.next == 99)
		w.open = false
		w.data.tokens.epic = 50
		local f, whyF = ForgeService.exchange(p, def.id)
		check("교환: 대장간이 닫혀 있으면 forge_closed", not f and whyF == "forge_closed" and w.data.tokens.epic == 50)
	end

	-- 9. 지급 원자성 · 요청 검증 ------------------------------------------------------------------------
	do
		local data = Schema.new()
		data.ores[1] = 3
		local ok = IP.applyChecked(data, function(d)
			return IP.applyCraft(d, { [1] = 5 }, "pickaxe", { Config.PICKAXES[2].id }, { rare = 1 })
		end)
		check("지급: 광석이 모자라면 곡괭이 · 토큰도 안 준다(전부 아니면 없음)", not ok and data.ores[1] == 3 and data.tokens.rare == 0
			and data.equipment.pickaxe[Config.PICKAXES[2].id] == nil)
		local ok2 = IP.applyChecked(data, function(d)
			return IP.applyCraft(d, { [1] = 1 }, "pickaxe", { "nope" }, {})
		end)
		check("지급: 모르는 곡괭이면 광석도 그대로", not ok2 and data.ores[1] == 3)
		local w, p = newWorld()
		setOres(w, { [1] = 5 })
		ForgeService.handleRequest(p, { action = "craft", combo = { 1, 1, 1, 1, 1 } })
		ForgeService.handleRequest(p, { action = "sync" }) -- 연타 상한 안 — 버린다
		local nState = 0
		for _, s in ipairs(w.sent) do
			if s.kind == "forge_state" then
				nState += 1
			end
		end
		w.now += 1
		ForgeService.handleRequest(p, "junk")
		ForgeService.handleRequest(p, { action = "sync" })
		check("요청: craft 처리 · 연타 상한 안 요청은 버림 · 모르는 꼴은 무시", w.data.ores[1] == 0 and nState == 0 and last(w, "forge_state") ~= nil)
	end
end)

ForgeService._deps = savedDeps
Config.CRAFT_SKIP_PASS_ID, Config.TRIPLE_CRAFT_PASS_ID = savedSkip, savedTriple
check("가짜 세계: 오류 없이 끝남", okRun, tostring(errRun))

-- 10. 플래그 꺼짐 = 지금과 같다 -----------------------------------------------------------------------------

print(string.format("[ForgeServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ForgeServiceTests] %d test(s) failed", failed))
end

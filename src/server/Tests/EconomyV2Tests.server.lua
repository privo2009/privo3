--!strict
-- 경제(지시서 #30 — #37부터 유일한 경제) 설정 · 순수 로직 · 환생 검증.
-- ⚠️ 설정 숫자를 하드코딩하지 않는다 — 기대값은 EconomyV2Config에서 읽는다(숫자는 TEMP라 바뀐다).
-- 플래그 커밋 값 false도 여기서 잰다(로컬에서 잠깐 true로 켠 Play에서는 1번이 실패한다 — 그 Play는 세지 않는다).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local RebirthService = require(ServerScriptService.Server.Systems.RebirthService)

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

local function seq(values: { number }): () -> number
	local i = 0
	return function()
		i += 1
		return values[((i - 1) % #values) + 1]
	end
end

local N = Config.CRAFT_INPUT
local UNIT = Config.GAUGE_UNIT

-- 1. 플래그 · 검증 -------------------------------------------------------------------------------
check("설정: validate 통과", (pcall(Config.validate)))
check("설정: 곡괭이 15종(일반 3 · 희귀 4 · 에픽 4 · 신화 3 · 전설 1)", (function()
	local c: { [string]: number } = {}
	for _, d in ipairs(Config.PICKAXES) do
		c[d.rarity] = (c[d.rarity] or 0) + 1
	end
	return #Config.PICKAXES == 15 and c.common == 3 and c.rare == 4 and c.epic == 4 and c.mythic == 3 and c.legendary == 1
end)())
check("설정: 교환 비용(희귀 3 · 4 · 5 · 7 / 에픽 2 · 3 · 5 · 9 / 신화 10 · 25 · 50 / 전설 50 — 사람 결정)", (function()
	local got: { [string]: { number } } = {}
	for _, d in ipairs(Config.PICKAXES) do
		if d.exchangeCost ~= nil then
			got[d.rarity] = got[d.rarity] or {}
			table.insert(got[d.rarity], d.exchangeCost :: number)
		end
	end
	return table.concat(got.rare, ",") == "3,4,5,7" and table.concat(got.epic, ",") == "2,3,5,9" and table.concat(got.mythic, ",") == "10,25,50"
		and table.concat(got.legendary, ",") == "50"
end)())
check("설정: 별 소모 1 · 3 · 5 · 7 · 10(누적 26) · 강화 +10", table.concat(Config.STAR_CONSUME, ",") == "1,3,5,7,10" and Config.ENHANCE_MAX == 10)
-- 운동기구 해금 환생 수(TEMP — #37에서 EconomyV2Config.GYM_UNLOCK_REBIRTHS → GymConfig 기구 표로 옮김 · 값 그대로)
local GYM_UNLOCK = { 1, 2, 3, 5, 7, 9, 12, 15 }
check("설정: 운동기구 해금 수 = 환생 기구 수", #GYM_UNLOCK == GymConfig.getRebirthTierCount())

-- 2. 광석 · 게이지(정수) --------------------------------------------------------------------------
do
	local ok = true
	for k, band in ipairs(Config.ORE_BANDS) do
		ok = ok and L.oreOf(band.from) == k and L.oreOf(band.to) == k
	end
	check("광석: 구간 양 끝 층 = 광석 번호", ok)
	local five = {}
	for i = 1, N do
		five[i] = Config.ORE_COUNT
	end
	check("게이지: 마지막 광석 5개만 칸 5(꽉 참)", L.slotsOf(five) == N)
	five[1] = Config.ORE_COUNT - 1
	check("게이지: 하나만 낮아도 칸 4(정수 내림)", L.slotsOf(five) == N - 1)
	-- 0.1 × k 실수 합이면 오차가 나는 조합(예: 광석 3 · 3 · 3 · 3 · 3 + …)을 정수로 센다: 점수 합이 UNIT 배수면 정확히 그 칸
	local okInt = true
	for k = 1, Config.ORE_COUNT do
		local same = {}
		for i = 1, N do
			same[i] = k
		end
		okInt = okInt and L.slotsOf(same) == math.min((L.gaugePoints(k) * N) // UNIT, N) -- #33 N12: 점수 = 점수 표
	end
	check("게이지: 같은 광석 5개 = (k × 5) ÷ 10 내림(모든 k)", okInt)
	check("게이지: 점수는 정수(광석 k = k)", L.gaugePoints(1) == 1 and L.gaugePoints(Config.ORE_COUNT) == Config.ORE_COUNT)
end

-- 3. 확률표 ---------------------------------------------------------------------------------------
do
	local sumOk, rowsOk, capOk = true, true, true
	for s = 0, N do
		local odds = L.oddsFor(s)
		local sum = 0
		for _, row in ipairs(odds) do
			sum += row.pct
			if row.rarity == "legendary" then
				capOk = capOk and row.pct <= Config.LEGENDARY_ODDS_MAX_PCT + 1e-12
			end
		end
		sumOk = sumOk and math.abs(sum - 100) < 1e-9
		rowsOk = rowsOk and #odds == #Config.PICKAXES
	end
	check("확률: 칸마다 합 100%", sumOk)
	check("확률: 칸마다 15종 전체", rowsOk)
	check("확률: 전설 ≤ 설정 상한", capOk)
	local mono = true
	for _, r in ipairs(Config.RARITIES) do
		for s = 1, N do
			mono = mono and L.atLeastPct(s, r) >= L.atLeastPct(s - 1, r) - 1e-12
		end
	end
	check("확률: 칸이 늘수록 '그 등급 이상' 확률이 줄지 않는다(모든 등급)", mono)
	local nextOnlyTop = true
	for s = 0, N do
		local has = (L.tokensFor(s)[Config.NEXT_RARITY] or 0) > 0
		nextOnlyTop = nextOnlyTop and (has == (s == N))
	end
	check("토큰: ??? 토큰은 5칸에서만", nextOnlyTop)
	check("토큰: 0칸 없음 · 1칸 희귀 · 2칸 에픽 · 3칸 신화 · 4칸 전설", next(L.tokensFor(0)) == nil and L.tokensFor(1).rare == 1
		and L.tokensFor(2).epic == 1 and L.tokensFor(3).mythic == 1 and L.tokensFor(4).legendary == 1 and L.tokensFor(N).legendary == 1)
	-- 뽑기: rand 0 → 확률이 있는 첫 줄 · 1에 가까우면 확률이 있는 마지막 줄
	local first, last
	for _, row in ipairs(L.oddsFor(0)) do
		if row.pct > 0 then
			first = first or row.id
			last = row.id
		end
	end
	check("뽑기: rand 0 → 첫 줄 · 0.999999999 → 마지막 줄", L.rollCraft(0, seq({ 0 })) == first and L.rollCraft(0, seq({ 0.999999999 })) == last)
end

-- 4. 조합 · 제작 ----------------------------------------------------------------------------------
do
	local inv = L.newInv()
	inv[1], inv[Config.ORE_COUNT] = 3, 1
	check("조합: 광석 5개 미만이면 nil", L.bestCombo(inv) == nil)
	inv = L.newInv()
	inv[2], inv[9], inv[Config.ORE_COUNT] = 10, 5, 4 -- #33 N12: 점수 표(광석 9 = 8점 · 10 = 10점)
	local combo, slots = L.bestCombo(inv)
	local top = { Config.ORE_COUNT, Config.ORE_COUNT, Config.ORE_COUNT, Config.ORE_COUNT, 9 }
	check("조합: 칸은 가장 높은 5개와 같다", combo ~= nil and slots == L.slotsOf(top) and L.slotsOf(combo :: { number }) == slots)
	local sum = 0
	for _, k in ipairs(combo or {}) do
		sum += L.gaugePoints(k)
	end
	check("조합: 같은 칸이면 점수 합이 가장 작다(높은 광석을 아낀다 — 여기서는 광석 9 × 5 = 칸 × 10 딱)", sum == slots * UNIT
		and combo ~= nil and (combo :: { number })[1] == 9 and (combo :: { number })[N] == 9, table.concat(combo or {}, ","))
	local picks = L.newPicks()
	local before = table.clone(inv)
	local res = L.craft(picks, inv, combo :: { number }, seq({ 0 }))
	local used = 0
	for k = 1, Config.ORE_COUNT do
		used += before[k] - inv[k]
	end
	local tokOk = true
	for r, c in pairs(L.tokensFor(slots)) do
		tokOk = tokOk and picks.tokens[r] == c
	end
	check("제작: 광석 5개를 뺀다 · 칸 · 토큰 = tokensFor(칸)", res ~= nil and used == N and res.slots == slots and tokOk)
	check("제작: 결과 곡괭이를 얻는다(시작 곡괭이 + 1종)", res ~= nil and picks.owned[res.id] ~= nil)
	local empty = L.newInv()
	check("제작: 광석이 모자라면 nil · 그대로", L.craft(picks, empty, { 1, 1, 1, 1, 1 }, seq({ 0 })) == nil and empty[1] == 0)
	-- 같은 곡괭이를 또 얻으면 여벌
	local p2 = L.newPicks()
	L.addPickaxe(p2, Config.START_PICKAXE)
	check("얻기: 이미 있으면 여벌 +1", p2.owned[Config.START_PICKAXE].copies == 1)
end

-- 5. 교환 · 별 · 강화 ----------------------------------------------------------------------------
do
	local picks = L.newPicks()
	local target: Config.PickaxeDef? = nil
	for _, d in ipairs(Config.PICKAXES) do
		if d.rarity == "legendary" then
			target = d
		end
	end
	local t = target :: Config.PickaxeDef
	picks.tokens[t.rarity] = (t.exchangeCost :: number) - 1
	local okA, reasonA = L.exchange(picks, t.id)
	check("교환: 토큰이 1 모자라면 거부 · 그대로", not okA and reasonA == "not_enough_tokens" and picks.owned[t.id] == nil)
	picks.tokens[t.rarity] += 1
	local okB = L.exchange(picks, t.id)
	check("교환: 정확히 비용이면 확정으로 얻고 토큰 0", okB and picks.owned[t.id] ~= nil and picks.tokens[t.rarity] == 0)
	check("교환: 일반은 교환 없음", select(2, L.canExchange(picks, Config.START_PICKAXE)) == "not_exchangeable")

	local o = picks.owned[Config.START_PICKAXE]
	o.copies = Config.STAR_CONSUME[1] - 1
	check("별: 여벌이 모자라면 거부", select(2, L.starUp(picks, Config.START_PICKAXE)) == "not_enough_copies" and o.stars == 0)
	local total = 0
	for _, c in ipairs(Config.STAR_CONSUME) do
		total += c
	end
	o.copies = total
	local ups = 0
	while L.starUp(picks, Config.START_PICKAXE) do
		ups += 1
	end
	check("별: 누적 소모로 5성 · 여벌 0 · 더는 max", ups == #Config.STAR_CONSUME and o.stars == #Config.STAR_CONSUME and o.copies == 0
		and select(2, L.starUp(picks, Config.START_PICKAXE)) == "max")

	local inv = L.newInv()
	local cost0 = L.enhanceCost(0) :: number
	inv[1] = cost0 -- 광석 1 = 1점
	inv[Config.ORE_COUNT] = 1
	local okE = L.enhance(picks, Config.START_PICKAXE, inv)
	check("강화: 낮은 광석부터 낸다(광석 1로 비용 전부)", okE and o.enh == 1 and inv[1] == 0 and inv[Config.ORE_COUNT] == 1)
	local inv2 = L.newInv()
	check("강화: 광석이 모자라면 거부 · 그대로", select(2, L.enhance(picks, Config.START_PICKAXE, inv2)) == "not_enough_ore" and o.enh == 1)
	o.enh = Config.ENHANCE_MAX
	check("강화: +10이면 max · 비용 nil", L.enhanceCost(Config.ENHANCE_MAX) == nil and select(2, L.enhance(picks, Config.START_PICKAXE, inv)) == "max")
	check("강화: 비용은 정수 · 늘어난다", L.enhanceCost(1) ~= nil and (L.enhanceCost(1) :: number) % 1 == 0 and (L.enhanceCost(1) :: number) >= cost0)

	local id = Config.PICKAXES[3].id
	local m = L.pickaxeMult(id, 4, 2)
	check("배수: 곡괭이 × 강화 × 별(곱)", math.abs(m - L.baseMult(id) * L.enhanceMult(4) * L.starMult(2)) < 1e-9
		and math.abs(L.baseMult(id) - Config.PICK_RATIO ^ 2) < 1e-9)
	check("배수: 시작 곡괭이 0강 0성 = 1", L.pickaxeMult(Config.START_PICKAXE, 0, 0) == 1)
	local pb = L.newPicks()
	L.addPickaxe(pb, Config.PICKAXES[5].id)
	check("장착: 가진 것 중 배수가 가장 큰 것", L.bestOwned(pb) == Config.PICKAXES[5].id)
	check("가방: 용량은 장착 곡괭이 rank를 따른다 · 패스 배수", L.bagCapacity(Config.PICKAXES[1].id) == Config.BAG_BASE
		and L.bagCapacity(Config.PICKAXES[5].id) == Config.BAG_BASE + 4 * Config.BAG_PER_RANK
		and L.bagCapacity(Config.PICKAXES[1].id, 2) == Config.BAG_BASE * 2)
end

-- 6. 가방 바꿔 줍기 --------------------------------------------------------------------------------
do
	local bag = L.newInv()
	local a = L.addToBag(bag, 3, 2, 3)
	local b = L.addToBag(bag, 3, 5, 2)
	local mid2, mid5 = bag[2], bag[5]
	local c = L.addToBag(bag, 3, 1, 1)
	local d = L.addToBag(bag, 3, 5, 1)
	check("가방: 가득 차면 더 낮은 광석과 바꾼다 · 낮거나 같으면 못 줍는다", a == 3 and b == 2 and mid2 == 1 and mid5 == 2 and c == 0
		and d == 1 and bag[2] == 0 and bag[5] == 3)
end

-- 7. 환생 v2 · 배수 · 운동기구 ---------------------------------------------------------------------
do
	local c0 = L.rebirthCost(0)
	local c3 = L.rebirthCost(BigNum.fromNumber(3))
	check("환생: 비용 = 시작 × 성장^n", BigNum.eq(c0, Config.REBIRTH_COST_BASE)
		and math.abs(BigNum.toRatio(c3, Config.REBIRTH_COST_BASE) - Config.REBIRTH_COST_GROWTH ^ 3) < 1e-6)
	check("환생: 배수 항 = b^n · n 0이면 1", BigNum.eq(L.rebirthFactor(0), BigNum.new(1, 0))
		and math.abs(BigNum.toRatio(L.rebirthFactor(BigNum.fromNumber(5)), BigNum.new(1, 0)) - Config.REBIRTH_MULT_BASE ^ 5) < 1e-6)
	local blox = BigNum.mul(c3, BigNum.fromNumber(1.5))
	check("환생: 비용 이상이면 가능 · 1 모자라면 불가", L.canRebirth(c3, 3) and not L.canRebirth(BigNum.sub(c3, BigNum.new(1, 0)), 3))
	local left = L.rebirthRemainder(blox, 3)
	check("환생: 남는 블럭스 = 비용만 뺀 나머지(기본)", Config.REBIRTH_KEEP_REMAINDER and math.abs(BigNum.toRatio(left, c3) - 0.5) < 1e-6)
	check("환생: 유지 목록(곡괭이 · 광석 · 토큰 · 코인)", table.concat(L.REBIRTH_KEEPS, ",") == "pickaxes,ores,tokens,coins")

	local r = BigNum.fromNumber(4)
	local v2 = StrengthMultiplier.compute({ rebirths = r })
	check("배수: 새 경제 = b^n(다른 출처는 그대로 곱)", BigNum.eq(v2, L.rebirthFactor(r))
		and math.abs(BigNum.toRatio(StrengthMultiplier.compute({ rebirths = r, titleMult = 2 }), v2) - 2) < 1e-9)

	local okGym = true
	for i = 1, GymConfig.getRebirthTierCount() do
		local need = GYM_UNLOCK[i]
		okGym = okGym and GymConfig.isUnlockedByRebirths(i, BigNum.fromNumber(need))
			and not GymConfig.isUnlockedByRebirths(i, BigNum.fromNumber(need - 1))
			and BigNum.eq(GymConfig.getUnlockRebirths(i), BigNum.fromNumber(need))
	end
	check("운동기구: 새 경제 해금 = 설정 값(경계)", okGym)
end

-- 8. RebirthService 새 경제 경로(가짜 deps — 프로필 없음) -----------------------------------------
do
	local runRebirth = RebirthService._pure.runRebirth
	local function world(blox: BigNum.BigNumber, rebirths: number)
		local w: any = { blox = blox, rebirths = BigNum.fromNumber(rebirths), strength = BigNum.new(7, 12), calls = {}, subtracted = nil, set = nil }
		local deps: any = {
			getBlox = function()
				return w.blox
			end,
			abandonRun = function()
				table.insert(w.calls, "abandonRun")
				return true
			end,
			setBlox = function(_p, amount)
				table.insert(w.calls, "setBlox")
				w.set = amount
				w.blox = amount
				return true
			end,
			addRebirths = function(_p, amount)
				table.insert(w.calls, "addRebirths")
				w.rebirths = BigNum.add(w.rebirths, amount)
				return true, w.rebirths
			end,
			setStrength = function(_p, amount)
				w.strength = amount
				return true
			end,
			resetMaxStage = function()
				return true
			end,
			resetCurrentWorld = function()
				return true
			end,
			onRebirth = function()
				return 16
			end,
			resetLifeBlox = function()
				return true
			end,
			resetPad = function()
				table.insert(w.calls, "resetPad")
				return true
			end,
			getRebirthMult = function()
				return 2 -- x2 Rebirths를 가졌어도 새 경제는 +1(PENDING G14)
			end,
			getRebirths = function()
				return w.rebirths
			end,
			subtractBlox = function(_p, amount)
				table.insert(w.calls, "subtractBlox")
				w.subtracted = amount
				w.blox = BigNum.sub(w.blox, amount)
				return true
			end,
		}
		return w, deps
	end
	local n = 2
	local cost = L.rebirthCost(n)
	local wLow, dLow = world(BigNum.sub(cost, BigNum.new(1, 0)), n)
	local okLow, reasonLow = runRebirth(dLow, {} :: any, "test")
	check("환생 v2: 비용 미만이면 거부 · 아무것도 안 바뀜", not okLow and reasonLow == RebirthService.REASON_NOT_ENOUGH_BLOX and #wLow.calls == 0)
	local have = BigNum.mul(cost, BigNum.fromNumber(1.25))
	local w, d = world(have, n)
	local ok, result = runRebirth(d, {} :: any, "test")
	check("환생 v2: 비용만 CurrencyService 통로(subtract)로 뺀다 · 나머지 남음", ok and w.subtracted ~= nil and BigNum.eq(w.subtracted, cost)
		and math.abs(BigNum.toRatio(w.blox, cost) - 0.25) < 1e-6 and table.find(w.calls, "setBlox") == nil)
	check("환생 v2: 환생 수 +1(x2 패스여도) · 결과 gained 1 · total n+1", ok and BigNum.eq(result.gained, BigNum.new(1, 0))
		and BigNum.eq(result.total, BigNum.fromNumber(n + 1)))
	check("환생 v2: 나머지 초기화는 지금과 같다(힘 · 패드)", ok and BigNum.eq(w.strength, require(ServerScriptService.Server.Data.Schema).new().strength)
		and table.find(w.calls, "resetPad") ~= nil)
	local wExact, dExact = world(cost, n)
	local okExact = runRebirth(dExact, {} :: any, "test")
	check("환생 v2: 딱 비용이면 0으로(set) — 나머지 없음", okExact and wExact.set ~= nil and wExact.set.m == 0)
end

print(string.format("[EconomyV2Tests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EconomyV2Tests] %d test(s) failed", failed))
end

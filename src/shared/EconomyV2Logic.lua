--!strict
-- 새 경제 순수 로직 (지시서 #30 — 원본 결정 DESIGN.md "16. 경제 재설계" · 숫자 Shared/Config/EconomyV2Config).
--
-- 서비스 연결이 없다(드롭 · 줍기 · 대장간 화면은 다음 지시서). 난수는 주입한다(rand: () -> number, [0, 1)).
-- 게임(다음 지시서의 서비스) · 환생 v2 · 시뮬레이터(Tools/EconomyV2Report)가 **같은 함수**를 부른다 — 식을 두 곳에 쓰지 않는다.
--
-- 상태 꼴(저장 필드는 아직 없다 — 스키마는 다음 지시서. 여기 꼴이 그때의 출발점이다):
--   inv     { [광석 k]: 개수 }                          1 ~ ORE_COUNT, 정수
--   picks   { owned = { [id]: { copies, stars, enh } },  copies = 별 올리기에 쓸 수 있는 같은 곡괭이 여벌
--             tokens = { [등급]: 개수 },                 rare · epic · mythic · legendary · next(???)
--             equipped = id }
--   bag     { [광석 k]: 개수 }                          런 동안만(수령하면 inv로, 실패하면 잃는다)
-- 곡괭이 · 광석 · 토큰 · 코인은 환생으로 초기화하지 않는다(EconomyV2Logic.REBIRTH_KEEPS — 환생 v2가 건드리지 않는 목록).

local BigNum = require(script.Parent.BigNum)
local Config = require(script.Parent.Config.EconomyV2Config)

type BigNumber = BigNum.BigNumber

export type Owned = { copies: number, stars: number, enh: number }
export type Picks = { owned: { [string]: Owned }, tokens: { [string]: number }, equipped: string }
export type OddsRow = { id: string, rarity: string, pct: number }

local EconomyV2Logic = {}

-- 환생 v2가 초기화하지 않는 것(규칙 — 저장 필드가 생기면 RebirthService 테스트가 이 목록을 대조한다)
EconomyV2Logic.REBIRTH_KEEPS = { "pickaxes", "ores", "tokens", "coins" }

function EconomyV2Logic.isOn(): boolean
	return Config.ECONOMY_V2 == true
end

-- ===== 곡괭이 표 ===========================================================================================

local byId: { [string]: Config.PickaxeDef } = {}
for _, def in ipairs(Config.PICKAXES) do
	byId[def.id] = def
end

function EconomyV2Logic.pickaxe(id: string): Config.PickaxeDef?
	return byId[id]
end

function EconomyV2Logic.newPicks(): Picks
	local start = Config.START_PICKAXE
	return { owned = { [start] = { copies = 0, stars = 0, enh = 0 } }, tokens = {}, equipped = start }
end

function EconomyV2Logic.newInv(): { number }
	local inv = {}
	for k = 1, Config.ORE_COUNT do
		inv[k] = 0
	end
	return inv
end

-- ===== 광석 · 게이지 ======================================================================================

-- 층 → 광석 종류(1 ~ ORE_COUNT). 구간 밖(25층 위)은 마지막 광석.
function EconomyV2Logic.oreOf(stage: number): number
	for k, band in ipairs(Config.ORE_BANDS) do
		if stage >= band.from and stage <= band.to then
			return k
		end
	end
	return Config.ORE_COUNT
end

-- 광석 k의 블록 하나 드롭 기대값(지시서 #31 — 상위 광석은 UPPER_ORE_DROP_MULT를 곱한다)
function EconomyV2Logic.dropsPerBlock(k: number): number
	local base = Config.ORE_PER_BLOCK
	return if k >= Config.UPPER_ORE_FROM then base * Config.UPPER_ORE_DROP_MULT else base
end

-- 층 stage의 블록 blocks개가 떨어뜨리는 광석 수(정수). 기대값의 소수 부분은 블록마다 확률로 하나 더(rand: [0, 1)).
-- rand가 nil이면 기대값을 반올림한다(시뮬레이터 — 같은 기대값).
function EconomyV2Logic.rollDrops(stage: number, blocks: number, rand: (() -> number)?): number
	local d = EconomyV2Logic.dropsPerBlock(EconomyV2Logic.oreOf(stage))
	if rand == nil then
		return math.floor(d * blocks + 0.5)
	end
	local whole = math.floor(d)
	local frac = d - whole
	local n = 0
	for _ = 1, blocks do
		n += whole
		if frac > 0 and rand() < frac then
			n += 1
		end
	end
	return n
end

-- 광석 k의 게이지 점수(정수). 0.1 × k칸을 10배로 둔 값이다.
function EconomyV2Logic.gaugePoints(k: number): number
	assert(k % 1 == 0 and k >= 1 and k <= Config.ORE_COUNT, "EconomyV2Logic.gaugePoints: 광석 번호는 1 ~ ORE_COUNT 정수")
	return k
end

-- 광석 목록 → 칸 수. 정수 점수 합 ÷ GAUGE_UNIT 내림(실수로 더하지 않는다 — 3.9999 오차로 칸이 줄지 않게).
function EconomyV2Logic.slotsOf(ores: { number }): number
	local sum = 0
	for _, k in ipairs(ores) do
		sum += EconomyV2Logic.gaugePoints(k)
	end
	return math.min(sum // Config.GAUGE_UNIT, Config.CRAFT_INPUT)
end

-- 가진 광석으로 만들 수 있는 조합 중 칸 수가 가장 높은 것. 같은 칸이면 점수 합이 가장 작은 것,
-- 그것도 같으면 높은 광석을 덜 쓰는 것(내림차순으로 늘어놓아 사전순으로 작은 것 — 8 · 8 · 8 · 8 · 8이 10 · 10 · 10 · 8 · 2보다 낫다).
-- 광석이 CRAFT_INPUT개 미만이면 nil.
-- 오름차순 조합만 본다(같은 조합을 두 번 세지 않는다).
function EconomyV2Logic.bestCombo(inv: { number }): ({ number }?, number)
	local n = Config.CRAFT_INPUT
	local total = 0
	for k = 1, Config.ORE_COUNT do
		total += inv[k] or 0
	end
	if total < n then
		return nil, 0
	end
	-- 칸 상한 = 가장 높은 n개
	local top = {}
	for k = Config.ORE_COUNT, 1, -1 do
		for _ = 1, math.min(inv[k] or 0, n - #top) do
			table.insert(top, k)
		end
		if #top == n then
			break
		end
	end
	local maxSlots = EconomyV2Logic.slotsOf(top)
	local need = maxSlots * Config.GAUGE_UNIT
	local best: { number }? = nil
	local bestSum = math.huge
	local pick = {}
	local used: { [number]: number } = {}
	-- 오름차순 두 조합을 뒤(높은 쪽)부터 비교: a가 높은 광석을 덜 쓰면 true
	local function fewerHigh(a: { number }, b: { number }): boolean
		for i = #a, 1, -1 do
			if a[i] ~= b[i] then
				return a[i] < b[i]
			end
		end
		return false
	end
	local function walk(from: number, sum: number)
		if sum > bestSum then
			return -- 이미 더 큰 합(오름차순이라 뒤는 더 크다)
		end
		if #pick == n then
			if sum >= need and (sum < bestSum or best == nil or fewerHigh(pick, best :: { number })) then
				best = table.clone(pick)
				bestSum = sum
			end
			return
		end
		-- 남은 칸을 전부 최고 광석으로 채워도 need에 못 닿으면 자른다
		if sum + (n - #pick) * Config.ORE_COUNT < need then
			return
		end
		for k = from, Config.ORE_COUNT do
			if (used[k] or 0) < (inv[k] or 0) then
				used[k] = (used[k] or 0) + 1
				table.insert(pick, k)
				walk(k, sum + k)
				table.remove(pick)
				used[k] -= 1
			end
		end
	end
	walk(1, 0)
	return best, maxSlots
end

-- 조합을 몇 번 더 만들 수 있는가(인벤토리만 본다)
function EconomyV2Logic.comboTimes(inv: { number }, combo: { number }): number
	local need: { [number]: number } = {}
	for _, k in ipairs(combo) do
		need[k] = (need[k] or 0) + 1
	end
	local times = math.huge
	for k, c in pairs(need) do
		times = math.min(times, (inv[k] or 0) // c)
	end
	return if times == math.huge then 0 else times
end

-- ===== 제작 확률 · 토큰 ===================================================================================

-- 칸 수 → 15종 전체 확률표(rank 순서 · pct 합 100). 제작 전에 이 표를 그대로 보여 준다(DESIGN 16장 — 확률 공개).
function EconomyV2Logic.oddsFor(slots: number): { OddsRow }
	local row = Config.RARITY_ODDS[slots]
	assert(row ~= nil, "EconomyV2Logic.oddsFor: 칸 수는 0 ~ CRAFT_INPUT")
	local out: { OddsRow } = {}
	local idx: { [string]: number } = {}
	for _, def in ipairs(Config.PICKAXES) do
		local split = Config.RARITY_SPLIT[def.rarity]
		local sum = 0
		for _, w in ipairs(split) do
			sum += w
		end
		idx[def.rarity] = (idx[def.rarity] or 0) + 1
		local share = split[idx[def.rarity]] / sum
		table.insert(out, { id = def.id, rarity = def.rarity, pct = (row[def.rarity] or 0) * share })
	end
	return out
end

-- 칸 수에서 등급 r 이상이 나올 확률(%)
function EconomyV2Logic.atLeastPct(slots: number, rarity: string): number
	local row = Config.RARITY_ODDS[slots]
	local on = false
	local sum = 0
	for _, r in ipairs(Config.RARITIES) do
		if r == rarity then
			on = true
		end
		if on then
			sum += row[r] or 0
		end
	end
	return sum
end

-- 확률표로 하나 뽑는다. rand()는 [0, 1).
function EconomyV2Logic.rollCraft(slots: number, rand: () -> number): string
	local odds = EconomyV2Logic.oddsFor(slots)
	local x = rand() * 100
	local acc = 0
	local last = odds[1].id
	for _, row in ipairs(odds) do
		if row.pct > 0 then
			acc += row.pct
			last = row.id
			if x < acc then
				return row.id
			end
		end
	end
	return last -- 부동소수 끝자리(합 100에서 아주 조금 모자람)
end

function EconomyV2Logic.tokensFor(slots: number): { [string]: number }
	return table.clone(Config.TOKENS_BY_GAUGE[slots] or {})
end

-- 곡괭이 하나를 얻는다(제작 · 교환). 이미 있으면 여벌(copies)이 된다.
function EconomyV2Logic.addPickaxe(picks: Picks, id: string)
	assert(byId[id] ~= nil, "EconomyV2Logic.addPickaxe: 모르는 곡괭이 " .. id)
	local o = picks.owned[id]
	if o == nil then
		picks.owned[id] = { copies = 0, stars = 0, enh = 0 }
	else
		o.copies += 1
	end
end

export type CraftResult = { id: string, slots: number, tokens: { [string]: number }, isNew: boolean }

-- 제작 1회: 조합만큼 광석을 빼고 · 뽑고 · 곡괭이와 토큰을 더한다. 광석이 모자라면 nil(아무것도 안 바뀐다).
function EconomyV2Logic.craft(picks: Picks, inv: { number }, combo: { number }, rand: () -> number): CraftResult?
	if #combo ~= Config.CRAFT_INPUT or EconomyV2Logic.comboTimes(inv, combo) < 1 then
		return nil
	end
	for _, k in ipairs(combo) do
		inv[k] -= 1
	end
	local slots = EconomyV2Logic.slotsOf(combo)
	local id = EconomyV2Logic.rollCraft(slots, rand)
	local isNew = picks.owned[id] == nil
	EconomyV2Logic.addPickaxe(picks, id)
	local tokens = EconomyV2Logic.tokensFor(slots)
	for r, c in pairs(tokens) do
		picks.tokens[r] = (picks.tokens[r] or 0) + c
	end
	return { id = id, slots = slots, tokens = tokens, isNew = isNew }
end

-- 제작 · 부화 시간(지시서 #31 — 연출 + 스킵). 한 번(버튼 한 번 · 자동 1틱)에 걸리는 초와 그 한 번에 몇 회인가.
--   skipPass = 연출 생략 상품 보유 · triple = 트리플 상품 보유. 무료는 스킵 시점마다 1회.
function EconomyV2Logic.craftStep(skipPass: boolean?, triple: boolean?): (number, number)
	return (if skipPass then Config.CRAFT_MIN_INTERVAL_SEC else Config.CRAFT_SKIP_SEC), (if triple then Config.TRIPLE_CRAFT_COUNT else 1)
end

function EconomyV2Logic.hatchStep(skipPass: boolean?, triple: boolean?): (number, number)
	return (if skipPass then Config.HATCH_MIN_INTERVAL_SEC else Config.HATCH_SKIP_SEC), (if triple then Config.TRIPLE_HATCH_COUNT else 1)
end

-- 대장간이 열렸는가(⚠️ FORGE_UNLOCK_REBIRTHS · FORGE_UNLOCK_STAGE — Claude 제안 · 사람 결정 전). 설정한 조건을 전부 채워야 한다.
-- bestStageEver = 평생 최고층(환생으로 줄지 않는다) · rebirths = 환생 수(BigNum 또는 number)
function EconomyV2Logic.forgeOpen(bestStageEver: number, rebirths: (BigNumber | number)?): boolean
	local needStage = Config.FORGE_UNLOCK_STAGE
	local needRebirths = Config.FORGE_UNLOCK_REBIRTHS
	if needStage ~= nil and bestStageEver < needStage then
		return false
	end
	if needRebirths ~= nil and EconomyV2Logic.rebirthCount(rebirths or 0) < needRebirths then
		return false
	end
	return true
end

-- 자동 제작이 sec초 동안 할 수 있는 회수(재료 제한은 따로 — craft가 nil을 돌려준다)
function EconomyV2Logic.autoCraftCount(sec: number, skipPass: boolean?, triple: boolean?): number
	local step, per = EconomyV2Logic.craftStep(skipPass, triple)
	if sec <= 0 then
		return 0
	end
	return math.floor(sec / step) * per
end

-- ===== 교환 ==============================================================================================

-- 토큰으로 그 등급 곡괭이를 확정으로 얻는다. 사유: "unknown" · "not_exchangeable"(일반) · "not_enough_tokens"
function EconomyV2Logic.canExchange(picks: Picks, id: string): (boolean, string?)
	local def = byId[id]
	if def == nil then
		return false, "unknown"
	end
	if def.exchangeCost == nil then
		return false, "not_exchangeable"
	end
	if (picks.tokens[def.rarity] or 0) < (def.exchangeCost :: number) then
		return false, "not_enough_tokens"
	end
	return true, nil
end

function EconomyV2Logic.exchange(picks: Picks, id: string): (boolean, string?)
	local ok, reason = EconomyV2Logic.canExchange(picks, id)
	if not ok then
		return false, reason
	end
	local def = byId[id] :: Config.PickaxeDef
	picks.tokens[def.rarity] -= def.exchangeCost :: number
	EconomyV2Logic.addPickaxe(picks, id)
	return true, nil
end

-- ===== 별 · 강화 =========================================================================================

-- 지금 별 수에서 한 단계 올릴 때 소모하는 같은 곡괭이 수. 5성이면 nil.
function EconomyV2Logic.starCost(stars: number): number?
	return Config.STAR_CONSUME[stars + 1]
end

function EconomyV2Logic.starUp(picks: Picks, id: string): (boolean, string?)
	local o = picks.owned[id]
	if o == nil then
		return false, "not_owned"
	end
	local cost = EconomyV2Logic.starCost(o.stars)
	if cost == nil then
		return false, "max"
	end
	if o.copies < cost then
		return false, "not_enough_copies"
	end
	o.copies -= cost
	o.stars += 1
	return true, nil
end

-- 지금 강화 수준에서 +1 하는 데 드는 광석 점수(정수). +10이면 nil.
function EconomyV2Logic.enhanceCost(level: number): number?
	if level >= Config.ENHANCE_MAX then
		return nil
	end
	return math.ceil(Config.ENHANCE_COST_BASE * Config.ENHANCE_COST_GROWTH ^ level)
end

-- 강화 블럭스 비용(PENDING N5 — ENHANCE_BLOX_COST_BASE가 nil이면 nil = 블럭스 안 씀). 측정 변형용.
function EconomyV2Logic.enhanceBloxCost(level: number): BigNumber?
	local base = Config.ENHANCE_BLOX_COST_BASE
	if base == nil or level >= Config.ENHANCE_MAX then
		return nil
	end
	return BigNum.mul(base, BigNum.pow(BigNum.fromNumber(Config.ENHANCE_BLOX_COST_GROWTH), level))
end

-- 광석 점수 points만큼 낸다 — 낮은 광석부터(maxOre 이하만 — nil이면 전부). 모자라면 아무것도 안 빼고 false.
-- 광석은 쪼갤 수 없어 마지막 하나는 넘칠 수 있다(넘친 점수는 돌려주지 않는다).
function EconomyV2Logic.payOrePoints(inv: { number }, points: number, maxOre: number?): boolean
	local top = maxOre or Config.ORE_COUNT
	local have = 0
	for k = 1, top do
		have += (inv[k] or 0) * k
	end
	if have < points then
		return false
	end
	local left = points
	for k = 1, top do
		while left > 0 and (inv[k] or 0) > 0 do
			inv[k] -= 1
			left -= k
		end
		if left <= 0 then
			break
		end
	end
	return true
end

-- 장착 곡괭이(또는 id)를 +1 강화한다. 사유: "not_owned" · "max" · "not_enough_ore"
function EconomyV2Logic.enhance(picks: Picks, id: string, inv: { number }, maxOre: number?): (boolean, string?)
	local o = picks.owned[id]
	if o == nil then
		return false, "not_owned"
	end
	local cost = EconomyV2Logic.enhanceCost(o.enh)
	if cost == nil then
		return false, "max"
	end
	if not EconomyV2Logic.payOrePoints(inv, cost, maxOre) then
		return false, "not_enough_ore"
	end
	o.enh += 1
	return true, nil
end

-- ===== 채굴 데미지 배수 · 가방 ============================================================================

-- 곡괭이 배수(등급 · 순위만)
function EconomyV2Logic.baseMult(id: string): number
	local def = byId[id]
	assert(def ~= nil, "EconomyV2Logic.baseMult: 모르는 곡괭이 " .. id)
	return Config.PICK_RATIO ^ (def.rank - 1)
end

function EconomyV2Logic.enhanceMult(level: number): number
	return 1 + Config.ENHANCE_STEP * level
end

function EconomyV2Logic.starMult(stars: number): number
	return 1 + Config.STAR_STEP * stars
end

-- 최종 채굴 데미지 배수 = 곡괭이 × 강화 × 별(출처끼리 곱한다 — DESIGN 3장 S3 · S5와 같은 꼴).
-- AttackService.combineDamageMultiplier의 펀치 데미지 항 자리에 한 번만 들어간다.
function EconomyV2Logic.pickaxeMult(id: string, enh: number, stars: number): number
	return EconomyV2Logic.baseMult(id) * EconomyV2Logic.enhanceMult(enh) * EconomyV2Logic.starMult(stars)
end

function EconomyV2Logic.ownedMult(picks: Picks, id: string): number
	local o = picks.owned[id]
	if o == nil then
		return 0
	end
	return EconomyV2Logic.pickaxeMult(id, o.enh, o.stars)
end

function EconomyV2Logic.equippedMult(picks: Picks): number
	return EconomyV2Logic.ownedMult(picks, picks.equipped)
end

-- 가진 것 중 배수가 가장 큰 곡괭이(같으면 rank가 높은 것)
function EconomyV2Logic.bestOwned(picks: Picks): string
	local best, bestM, bestRank = picks.equipped, -1, -1
	for id in pairs(picks.owned) do
		local m = EconomyV2Logic.ownedMult(picks, id)
		local rank = (byId[id] :: Config.PickaxeDef).rank
		if m > bestM or (m == bestM and rank > bestRank) then
			best, bestM, bestRank = id, m, rank
		end
	end
	return best
end

-- 장착 곡괭이의 가방 용량(큰 가방 게임패스 배수는 상품이 생길 때 — passMult)
function EconomyV2Logic.bagCapacity(id: string, passMult: number?): number
	local def = byId[id]
	assert(def ~= nil, "EconomyV2Logic.bagCapacity: 모르는 곡괭이 " .. id)
	return math.floor((Config.BAG_BASE + Config.BAG_PER_RANK * (def.rank - 1)) * (passMult or 1))
end

-- 가방에 광석 k를 count개 넣는다. 가득 차면 가방 안의 더 낮은 광석과 바꿔 줍는다(사람 결정). 넣은 수를 돌려준다.
function EconomyV2Logic.addToBag(bag: { number }, cap: number, k: number, count: number): number
	local used = 0
	for i = 1, Config.ORE_COUNT do
		used += bag[i] or 0
	end
	local added = 0
	for _ = 1, count do
		if used < cap then
			bag[k] = (bag[k] or 0) + 1
			used += 1
			added += 1
		else
			local lowest: number? = nil
			for i = 1, k - 1 do
				if (bag[i] or 0) > 0 then
					lowest = i
					break
				end
			end
			if lowest == nil then
				break
			end
			bag[lowest :: number] -= 1
			bag[k] = (bag[k] or 0) + 1
			added += 1
		end
	end
	return added
end

-- ===== 코인 ===============================================================================================

function EconomyV2Logic.coinPerBlock(stage: number): BigNumber
	return BigNum.mul(BigNum.fromNumber(Config.COIN_BASE), BigNum.pow(BigNum.fromNumber(Config.COIN_GROWTH), stage - 1))
end

function EconomyV2Logic.eggCoinCost(eggId: number): BigNumber?
	local c = Config.EGG_COIN_COST[eggId]
	return if c ~= nil then BigNum.new(c.m, c.e) else nil
end

-- ===== 환생 v2 ============================================================================================

-- BigNum 환생 수 → number(정수 · 아주 크면 큰 number 그대로 — 새 경제 범위는 수십 회)
function EconomyV2Logic.rebirthCount(rebirths: BigNumber | number): number
	if type(rebirths) == "number" then
		return rebirths
	end
	local r = rebirths :: BigNumber
	if r.m <= 0 then
		return 0
	end
	return math.floor(r.m * 10 ^ r.e + 1e-6)
end

-- 다음 환생 비용 = REBIRTH_COST_BASE × REBIRTH_COST_GROWTH^n (n = 지금 환생 수)
function EconomyV2Logic.rebirthCost(rebirths: BigNumber | number): BigNumber
	local n = EconomyV2Logic.rebirthCount(rebirths)
	return BigNum.mul(Config.REBIRTH_COST_BASE, BigNum.pow(BigNum.fromNumber(Config.REBIRTH_COST_GROWTH), n))
end

-- 힘 배수의 환생 항 = REBIRTH_MULT_BASE^n (n = 0이면 1)
function EconomyV2Logic.rebirthFactor(rebirths: BigNumber | number): BigNumber
	local n = EconomyV2Logic.rebirthCount(rebirths)
	return BigNum.pow(BigNum.fromNumber(Config.REBIRTH_MULT_BASE), n)
end

function EconomyV2Logic.canRebirth(blox: BigNumber, rebirths: BigNumber | number): boolean
	return BigNum.gte(blox, EconomyV2Logic.rebirthCost(rebirths))
end

-- 환생 뒤 남는 블럭스. 기본(REBIRTH_KEEP_REMAINDER) = 비용만 뺀 나머지, 아니면 0. 음수 잡음은 0으로 접는다.
function EconomyV2Logic.rebirthRemainder(blox: BigNumber, rebirths: BigNumber | number): BigNumber
	if not Config.REBIRTH_KEEP_REMAINDER then
		return BigNum.new(0, 0)
	end
	local left = BigNum.sub(blox, EconomyV2Logic.rebirthCost(rebirths))
	if left.m < 0 then
		return BigNum.new(0, 0)
	end
	return left
end

-- 새 경제에서 빠진 로벅스 상품인가(지시서 #31 G14 — x2 Rebirths). economyV2 = nil이면 플래그.
function EconomyV2Logic.isRemovedProduct(key: string, economyV2: boolean?): boolean
	local v2 = if economyV2 ~= nil then economyV2 else EconomyV2Logic.isOn()
	return v2 and Config.REMOVED_PRODUCTS[key] == true
end

-- 이름 Strings 키(⚠️ 임시 이름 — 지시서 #31). 화면은 Locale.t(키)로 꺼낸다(Shared/Localization/Names).
function EconomyV2Logic.oreNameKey(k: number): string
	local key = Config.ORE_NAME_KEYS[k]
	assert(key ~= nil, "EconomyV2Logic.oreNameKey: 광석 번호는 1 ~ ORE_COUNT")
	return key
end

function EconomyV2Logic.pickaxeNameKey(id: string): string
	local def = byId[id]
	assert(def ~= nil, "EconomyV2Logic.pickaxeNameKey: 모르는 곡괭이 " .. id)
	return def.nameKey
end

-- 새 경제 운동기구 해금 환생 수(기구 번호 — 로벅스 전용 기구는 nil)
function EconomyV2Logic.gymUnlockRebirths(index: number): number?
	return Config.GYM_UNLOCK_REBIRTHS[index]
end

return EconomyV2Logic

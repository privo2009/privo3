--!strict
-- 새 경제 2차 측정 (지시서 #30 6번). ⚠️ 측정 도구다 — 숫자를 정하지 않는다(D2: 고르는 것은 희준). 추천까지만 한다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다.
--    새 경제의 식은 여기 다시 쓰지 않는다 — Shared/EconomyV2Logic(게이지 · 조합 · 제작 · 토큰 · 교환 · 별 · 강화 · 가방 · 코인 · 환생 v2)과
--    Shared/Config/EconomyV2Config를 그대로 부르고, 묶음(후보)마다 Config 값을 메모리에서 잠깐 바꾸고 끝나면 되돌린다
--    (EconomyCandidateReport · HpCandidateReport와 같은 패턴). 플래그(ECONOMY_V2)는 건드리지 않는다 — 배수 · 운동기구는 economyV2 인자로 부른다.
--    엔진은 SuccessRateReport(HP 곡선 · 런 · 수령 · 실패 · 칭호 S7 · 아우라 A4 · 업그레이드 S5' · 운동기구)다. 고리 ECON으로 붙는다.
-- 켜는 곳: SuccessRateReport.SIM.ECONOMY_V2_ONLY + Bootstrap SUCCESS_RATE_REPORT_ENABLED(둘 다 커밋 값 false).
--
-- ===== 표준 무과금 플레이어(지시서 #30 6번 — 괄호는 Claude 해석) ===============================================
--   진행 · 클릭 · 진행 판단 · 칭호 · 아우라 · 운동기구   SuccessRateReport 결정 모델 그대로(수동 진행 · 클릭률 6 ~ 10)
--   환생      살 수 있으면 바로(#29 결론 — eager). 비용 EconomyV2Logic.rebirthCost · 나머지는 아우라 A4 → 업그레이드 S5'(펀치 속도 · 블럭스 획득 ·
--             펫 슬롯)에 쓰고, 남은 것은 남긴다(REBIRTH_KEEP_REMAINDER — 비교 줄 "0으로")
--   광석      층을 깰 때마다 그 층 블록 수 × ORE_PER_BLOCK(EconomyV2Logic.oreOf). 줍기 = #29 표준 모델(타이머 중 드롭은 공격하며 줍고, 클리어 뒤
--             마지막 블록 드롭만 걸어간다 — EconomyCandidateReport.pickDistance · 반경 PICKUP_RADIUS). 가방 = 장착 곡괭이 용량 · 가득 차면 바꿔 줍기
--   코인      깬 층의 블록 수 × coinPerBlock(층)(실패한 층의 부서진 블록은 세지 않는다 — 과소). 펫: 런 직전 코인으로 해금된 가장 높은 알을 닿는 만큼
--             부화(E11과 같은 "가장 높은 것만" · 크래프팅 · 놓아주기). 펫 슬롯은 S5'가 블럭스로 산다
--   제작      자동 제작 켬 · 간격 AUTO_CRAFT_INTERVAL_SEC마다 1회(쉬지 않고 — 광석이 떨어지면 그동안은 안 쌓인다). 조합 = 가진 광석으로 칸이
--             가장 높은 조합(EconomyV2Logic.bestCombo — 같은 칸이면 합이 작고 높은 광석을 덜 쓰는 것). 런 직전(로비)에 몰아서 계산한다
--   교환      가진 토큰으로 살 수 있는 가장 좋은(rank 높은) 미보유 곡괭이 — 살 수 있는 동안 되풀이
--   별        여벌이 닿으면 올린다(어느 곡괭이든)
--   강화      장착한 곡괭이 · (지금 최선 조합의 가장 낮은 광석보다 낮은 광석만 낸다 — 제작에 안 쓰일 광석. 비교 줄 "아무 광석")
--   장착      가진 것 중 배수가 가장 큰 것(EconomyV2Logic.bestOwned)
--   워프      없음(결정 모델과 같다 — 비교 줄 greedy)
-- 끝: 25층 첫 진입 뒤에도 15종을 다 모을 때까지(또는 SIM.MAX_SIM_SEC_PER_PLAYER) 돈다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)

local SuccessRateReport = require(script.Parent.SuccessRateReport)
local EconomyCandidateReport = require(script.Parent.EconomyCandidateReport)
local AttackService = require(script.Parent.Parent.Systems.AttackService)
local RollService = require(script.Parent.Parent.Systems.RollService)
local RollLogic = require(script.Parent.Parent.Systems.RollLogic)

type BigNumber = BigNum.BigNumber

local EconomyV2Report = {}

-- 관측 해상도(게임 수치가 아니다)
EconomyV2Report.PLAYERS = 100
EconomyV2Report.TUNE_PLAYERS = 30
EconomyV2Report.TUNE_STEPS = 6
EconomyV2Report.CRAFT_SEED = 20261124
EconomyV2Report.PET_COIN_SEED = 20261125
-- 합격 기준(지시서 #30 6번 — 게임 수치가 아니다)
EconomyV2Report.GOAL = {
	t25 = { 105, 135 }, -- 분
	t15 = { 160, 200 },
	rebirths = { 10, 20 },
	early = 0.10, -- 1 ~ 9층 첫 도달 ±10%
	legendChance = 0.1, -- 3시간 안 확률 전설 기대 횟수
	horizonMin = 180,
}
-- run() 모드: "full"(재현 + 후보 묶음 + 정책 비교 + 참고 측정) · "explore"(재현 + EXPLORE 목록만)
EconomyV2Report.MODE = "full"

export type Policy = {
	rebirthKeep: boolean?, -- nil = Config.REBIRTH_KEEP_REMAINDER
	enhance: string?, -- "fodder"(기본) · "any" · "none"
	pickup: string?, -- "hand"(기본) · "auto"(자동 진행 — 전부 자동 · 시간 0)
	warp: string?, -- "none"(기본) · "greedy"
	bagPass: number?, -- 큰 가방 배수(구매자)
	fastCraft: boolean?,
	tripleCraft: boolean?,
	exchange: string?, -- "best"(기본) · "none"
}
export type Bundle = { label: string, set: { [string]: any }?, policy: Policy? }

-- ===== 묶음 깔기(언제나 되돌린다) =====================================================================================

local function median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	local c = table.clone(xs)
	table.sort(c)
	return c[math.floor((#c + 1) / 2)]
end

local function mean(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	local s = 0
	for _, x in ipairs(xs) do
		s += x
	end
	return s / #xs
end

local function log10Big(v: BigNumber): number
	return if v.m > 0 then math.log10(v.m) + v.e else 0
end

local function lastStage(): number
	local s = 1
	while StageConfig.hasStage(s + 1) do
		s += 1
	end
	return s
end

local LEGEND_PCT: { [number]: number } = {}

local function withBundle(b: Bundle, fn: () -> ())
	local SRR = SuccessRateReport :: any
	local MODEL = SuccessRateReport.MODEL :: any
	local saved: { [string]: any } = {}
	for k, v in pairs(b.set or {}) do
		saved[k] = (Config :: any)[k]
		;(Config :: any)[k] = v
	end
	local savedSRR = {
		econ = SRR.ECON,
		click = SRR.clickMultiplier,
		damage = SRR.damageMultiplier,
		gym = SRR.gymUnlockedCount,
		targets = SRR.S5_TARGETS,
		warp = MODEL.WARP_POLICY,
	}
	for s = 0, Config.CRAFT_INPUT do
		local pct = 0
		for _, row in ipairs(EconomyV2Logic.oddsFor(s)) do
			if row.rarity == "legendary" then
				pct += row.pct
			end
		end
		LEGEND_PCT[s] = pct
	end
	local ok, err = pcall(function()
		assert(Config.validate(), "묶음 설정이 validate를 통과하지 못했다")
		fn()
	end)
	for k, v in pairs(saved) do
		(Config :: any)[k] = v
	end
	SRR.ECON = savedSRR.econ
	SRR.clickMultiplier = savedSRR.click
	SRR.damageMultiplier = savedSRR.damage
	SRR.gymUnlockedCount = savedSRR.gym
	SRR.S5_TARGETS = savedSRR.targets
	MODEL.WARP_POLICY = savedSRR.warp
	if not ok then
		error(err)
	end
end

-- ===== 한 묶음 돌리기 ================================================================================================

local function measureV2(b: Bundle, players: number): any
	local out: any = nil
	withBundle(b, function()
		local SRR = SuccessRateReport :: any
		local MODEL = SuccessRateReport.MODEL :: any
		local SIM = SuccessRateReport.SIM
		local pol: Policy = b.policy or {}
		local keep = if pol.rebirthKeep ~= nil then pol.rebirthKeep else Config.REBIRTH_KEEP_REMAINDER
		local enhanceRule = pol.enhance or "fodder"
		local auto = pol.pickup == "auto"
		local interval = Config.AUTO_CRAFT_INTERVAL_SEC * (if pol.fastCraft then Config.FAST_CRAFT_FACTOR else 1)
		local perTick = if pol.tripleCraft then Config.TRIPLE_CRAFT_COUNT else 1
		local craftRandom = RollService.seededRandom(EconomyV2Report.CRAFT_SEED)
		local petCoinRandom = RollService.seededRandom(EconomyV2Report.PET_COIN_SEED)
		local maxStage = lastStage()
		local states: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
		local function st(p: any): any
			local s = states[p]
			if s == nil then
				s = {
					n = 0, picks = EconomyV2Logic.newPicks(), inv = EconomyV2Logic.newInv(), bag = EconomyV2Logic.newInv(),
					coins = BigNum.new(0, 0), coinsTotal = BigNum.new(0, 0), craftClock = 0, crafts = {}, tokensEarned = {},
					kthAt = { 0 }, expLegend = 0, legendByChance = 0, legendByToken = false, bagFullStage = nil, rebirthAt = {},
					rebirthSpent = BigNum.new(0, 0), lostOre = 0, collected = 0, pickSec = 0, hatches = 0, combo = nil,
				}
				for i = 0, Config.CRAFT_INPUT do
					s.crafts[i] = 0
				end
				states[p] = s
			end
			return s
		end
		local function ownedCount(s: any): number
			local c = 0
			for _ in pairs(s.picks.owned) do
				c += 1
			end
			return c
		end
		local function noteOwned(p: any, s: any)
			local c = ownedCount(s)
			while #s.kthAt < c do
				table.insert(s.kthAt, p.elapsedSec)
			end
		end
		local function bagCap(s: any): number
			return EconomyV2Logic.bagCapacity(s.picks.equipped, pol.bagPass)
		end
		local function doCrafts(p: any, s: any)
			local ticks = math.floor((p.elapsedSec - s.craftClock) / interval)
			if ticks <= 0 then
				return
			end
			local budget = ticks * perTick
			local done = 0
			local ranOut = false
			while done < budget do
				local combo, slots = EconomyV2Logic.bestCombo(s.inv)
				if combo == nil then
					ranOut = true
					break
				end
				local times = math.min(EconomyV2Logic.comboTimes(s.inv, combo :: { number }), budget - done)
				for _ = 1, times do
					local before = s.picks.owned[Config.PICKAXES[#Config.PICKAXES].id] ~= nil
					local r = EconomyV2Logic.craft(s.picks, s.inv, combo :: { number }, craftRandom)
					if r == nil then
						break
					end
					done += 1
					s.crafts[slots] += 1
					for rr, c in pairs(r.tokens) do
						s.tokensEarned[rr] = (s.tokensEarned[rr] or 0) + c
					end
					local craftSec = s.craftClock + math.ceil(done / perTick) * interval
					if craftSec <= EconomyV2Report.GOAL.horizonMin * 60 then
						s.expLegend += LEGEND_PCT[slots] / 100
					end
					local def = EconomyV2Logic.pickaxe(r.id) :: any
					if def.rarity == "legendary" and not before then
						s.legendByChance += 1
					end
				end
			end
			if ranOut then
				s.craftClock = p.elapsedSec
			else
				s.craftClock += math.ceil(done / perTick) * interval
			end
		end
		local function doExchanges(s: any)
			if pol.exchange == "none" then
				return
			end
			while true do
				local bestId: string? = nil
				for i = #Config.PICKAXES, 1, -1 do
					local def = Config.PICKAXES[i]
					if s.picks.owned[def.id] == nil and EconomyV2Logic.canExchange(s.picks, def.id) then
						bestId = def.id
						break
					end
				end
				if bestId == nil then
					return
				end
				if (EconomyV2Logic.pickaxe(bestId) :: any).rarity == "legendary" then
					s.legendByToken = true
				end
				EconomyV2Logic.exchange(s.picks, bestId)
			end
		end
		local function doUpgrades(s: any)
			for _, def in ipairs(Config.PICKAXES) do
				if s.picks.owned[def.id] ~= nil then
					while EconomyV2Logic.starUp(s.picks, def.id) do
					end
				end
			end
			s.picks.equipped = EconomyV2Logic.bestOwned(s.picks)
			if enhanceRule ~= "none" then
				local maxOre: number? = nil
				if enhanceRule == "fodder" then
					local combo = EconomyV2Logic.bestCombo(s.inv)
					maxOre = if combo ~= nil then (combo :: { number })[1] - 1 else 0
				end
				if maxOre == nil or (maxOre :: number) > 0 then
					while EconomyV2Logic.enhance(s.picks, s.picks.equipped, s.inv, maxOre) do
					end
				end
			end
			s.picks.equipped = EconomyV2Logic.bestOwned(s.picks)
		end
		local function hatchWithCoins(p: any, s: any)
			local unlocked = PetConfig.getUnlockedEggs(p.lifetimeBlox, SIM.WORLD_ID)
			local eggId = unlocked[#unlocked]
			if eggId == nil then
				return
			end
			local cost = EconomyV2Logic.eggCoinCost(eggId)
			if cost == nil then
				return
			end
			local n = math.floor(BigNum.toRatio(s.coins, cost :: BigNumber))
			if n <= 0 then
				return
			end
			local egg = PetConfig.Eggs[eggId]
			local luck = RollService.computeLuck("pet", { upgrades = p.upgrades })
			local storage = PetConfig.getStorage(false)
			for _ = 1, n do
				if SuccessRateReport.petCount(p) >= storage and not SuccessRateReport.releaseWeakest(p) then
					break
				end
				s.coins = BigNum.sub(s.coins, cost :: BigNumber)
				local def = RollLogic.roll(egg.pets, luck, petCoinRandom)
				local key = def.id .. ":1"
				p.pets[key] = (p.pets[key] or 0) + 1
				s.hatches += 1
				SuccessRateReport.craftAll(p)
			end
		end

		SRR.ECON = {
			eager = true,
			keepBlox = keep,
			canRebirth = function(p)
				return EconomyV2Logic.canRebirth(p.blox, st(p).n)
			end,
			rebirthCost = function(p)
				return EconomyV2Logic.rebirthCost(st(p).n)
			end,
			applyRebirth = function(p)
				local s = st(p)
				s.rebirthSpent = BigNum.add(s.rebirthSpent, EconomyV2Logic.rebirthCost(s.n))
				s.n += 1
				p.rebirths = BigNum.fromNumber(s.n)
				table.insert(s.rebirthAt, p.elapsedSec)
			end,
			onRunStart = function(p)
				local s = st(p)
				doCrafts(p, s)
				doExchanges(s)
				doUpgrades(s)
				noteOwned(p, s)
				hatchWithCoins(p, s)
				for k = 1, Config.ORE_COUNT do
					s.bag[k] = 0
				end
			end,
			onStageClear = function(p, stage)
				local s = st(p)
				local blocks = StageConfig.getBlockCount(stage)
				local coins = BigNum.mul(EconomyV2Logic.coinPerBlock(stage), BigNum.fromNumber(blocks))
				s.coins = BigNum.add(s.coins, coins)
				s.coinsTotal = BigNum.add(s.coinsTotal, coins)
				local sec = 0
				if not auto then
					sec = EconomyCandidateReport.pickDistance(stage, "last", Config.PICKUP_RADIUS) / LevelConfig.getMaxSpeed(p.strength)
				end
				local cap = bagCap(s)
				local drops = blocks * Config.ORE_PER_BLOCK
				EconomyV2Logic.addToBag(s.bag, cap, EconomyV2Logic.oreOf(stage), drops)
				local used = 0
				for k = 1, Config.ORE_COUNT do
					used += s.bag[k]
				end
				-- 가방이 처음 상한에 닿은 층(그 뒤로는 바꿔 줍기만 — 오르는 층은 언제나 더 높은 광석이라 바꿔 줍기는 늘 된다)
				if used >= cap and s.bagFullStage == nil then
					s.bagFullStage = stage
				end
				s.pickSec += sec
				return sec
			end,
			onRunEnd = function(p, _best, cashed)
				local s = st(p)
				for k = 1, Config.ORE_COUNT do
					if cashed then
						s.inv[k] += s.bag[k]
						s.collected += s.bag[k]
					else
						s.lostOre += s.bag[k]
					end
					s.bag[k] = 0
				end
			end,
		}
		SRR.clickMultiplier = function(p: any): BigNumber
			return StrengthMultiplier.compute({
				rebirths = p.rebirths,
				economyV2 = true,
				titleMult = SuccessRateReport.titleMult(p),
				auraMult = SuccessRateReport.auraMult(p),
				petMult = SuccessRateReport.petMult(p),
			})
		end
		SRR.damageMultiplier = function(p: any): number
			return AttackService.combineDamageMultiplier({
				punchDamage = EconomyV2Logic.equippedMult(st(p).picks),
				auraMult = SuccessRateReport.auraMult(p),
			})
		end
		SRR.gymUnlockedCount = function(p: any): number
			return GymConfig.getUnlockedCount(p.rebirths, true)
		end
		SRR.S5_TARGETS = { "punchSpeed", "bloxGain", "petSlots" }
		MODEL.WARP_POLICY = pol.warp or "none"

		out = EconomyV2Report.collect(players, maxStage, st, function(p: any)
			return ownedCount(st(p)) >= #Config.PICKAXES
		end)
	end)
	return out
end

-- 플레이어 players명을 돌려 층 첫 도달 · 지표를 모은다. st = nil이면 지금 경제(재현).
function EconomyV2Report.collect(players: number, maxStage: number, st: ((any) -> any)?, untilFn: ((any) -> boolean)?): any
	local SIM = SuccessRateReport.SIM
	local rng = Random.new(SIM.SEED)
	local titleRandom = RollService.seededRandom(SIM.TITLE_SEED)
	local auraRandom = RollService.seededRandom(SIM.AURA_SEED)
	local petRandom = if st == nil then RollService.seededRandom(SIM.PET_SEED) else nil -- 새 경제: 펫은 코인(블럭스 E11 끔)
	local firstTry = {}
	local results = {}
	local rows: { any } = {}
	local cur: any = nil
	local runStart = 0
	local observer = function(event: string, p: any, seen: { [number]: boolean }, _reached: number?)
		if event == "run_start" then
			runStart = p.elapsedSec
		elseif event == "run_end" then
			for stage in pairs(seen) do
				if cur.first[stage] == nil then
					cur.first[stage] = runStart
					if stage == maxStage and st ~= nil then
						local s = st(p)
						cur.at25 = { n = s.n, blox = log10Big(p.blox), rebirthAt = table.clone(s.rebirthAt), pet = SuccessRateReport.petMult(p),
							owned = #s.kthAt, pick = EconomyV2Logic.equippedMult(s.picks) }
					end
				end
			end
			cur.p = p
		end
	end
	for _ = 1, players do
		cur = { first = {} }
		table.insert(results, SuccessRateReport.simulatePlayer(rng, maxStage, firstTry, titleRandom, auraRandom, petRandom,
			{ observer = observer, untilFn = untilFn }))
		if st ~= nil and cur.p ~= nil then
			local p = cur.p
			local s = st(p)
			cur.end_ = {
				sec = p.elapsedSec, kthAt = table.clone(s.kthAt), crafts = table.clone(s.crafts), tokens = table.clone(s.tokensEarned),
				expLegend = s.expLegend, legendByChance = s.legendByChance, legendByToken = s.legendByToken, bagFullStage = s.bagFullStage,
				coins = log10Big(s.coinsTotal), hatches = s.hatches, rebirthSpent = log10Big(s.rebirthSpent), aura = log10Big(p.auraSpent),
				title = log10Big(p.titleSpent), upgrade = log10Big(p.upgradeSpent), lifetime = log10Big(p.lifetimeBlox), blox = log10Big(p.blox),
				lostOre = s.lostOre, collected = s.collected, pickSec = s.pickSec, n = s.n, picks = s.picks,
			}
		end
		cur.p = nil
		table.insert(rows, cur)
		task.wait()
	end
	return { rows = rows, metrics = SuccessRateReport.metrics(firstTry, results), players = players, maxStage = maxStage }
end

-- 층 s 첫 도달 중앙값(분)
local function firstMin(r: any, stage: number): number?
	local xs = {}
	for _, row in ipairs(r.rows) do
		if row.first[stage] ~= nil then
			table.insert(xs, row.first[stage] / 60)
		end
	end
	return if #xs * 2 >= #r.rows then median(xs) else nil
end

local function fmt(x: number?, f: string?): string
	return if x ~= nil then string.format(f or "%.1f", x) else "-"
end

local function endMed(r: any, fn: (any) -> number?): number?
	local xs = {}
	for _, row in ipairs(r.rows) do
		if row.end_ ~= nil then
			local v = fn(row.end_)
			if v ~= nil then
				table.insert(xs, v)
			end
		end
	end
	return median(xs)
end

local function at25Med(r: any, fn: (any) -> number?): number?
	local xs = {}
	for _, row in ipairs(r.rows) do
		if row.at25 ~= nil then
			local v = fn(row.at25)
			if v ~= nil then
				table.insert(xs, v)
			end
		end
	end
	return median(xs)
end

-- 지금 경제(플래그 끔) 재현 — #29 B4 25층 38.7분 · 층별 첫 도달 기준선
EconomyV2Report.V1 = nil :: any
function EconomyV2Report.reproduceV1(players: number): any
	local r = EconomyV2Report.collect(players, lastStage(), nil, nil)
	local m = r.metrics
	local seg = m.segments
	local early = {}
	for stage = 1, 9 do
		table.insert(early, string.format("%d:%s", stage, fmt(firstMin(r, stage), "%.2f")))
	end
	print(string.format("[ECON2] v1 재현(ECON 없음 · %d명) · 25층 %d명 · 중앙 %s분(#29 B4 38.7) · 구간 %.1f / %.1f / %.1f · 환생(이벤트) 평균 %.1f",
		players, m.reached, fmt(m.medianFinalMin), (seg[1].rate or 0) * 100, (seg[2].rate or 0) * 100, (seg[3].rate or 0) * 100, m.meanRebirths))
	print("[ECON2]   v1 층 첫 도달(분) " .. table.concat(early, " ") .. string.format(" · 17:%s · 25:%s", fmt(firstMin(r, 17)), fmt(firstMin(r, 25))))
	EconomyV2Report.V1 = r
	return r
end

-- 묶음 측정 결과 요약(표가 아니라 줄)
function EconomyV2Report.summarize(r: any): any
	local G = EconomyV2Report.GOAL
	local t25 = firstMin(r, r.maxStage)
	local k15 = endMed(r, function(e)
		return if #e.kthAt >= #Config.PICKAXES then e.kthAt[#Config.PICKAXES] / 60 else nil
	end)
	local got15 = 0
	for _, row in ipairs(r.rows) do
		if row.end_ ~= nil and #row.end_.kthAt >= #Config.PICKAXES then
			got15 += 1
		end
	end
	if got15 * 2 < #r.rows then
		k15 = nil
	end
	local n25 = at25Med(r, function(a)
		return a.n
	end)
	local legendMean = mean((function()
		local xs = {}
		for _, row in ipairs(r.rows) do
			if row.end_ ~= nil then
				table.insert(xs, row.end_.expLegend)
			end
		end
		return xs
	end)())
	local worstEarly = 0
	local v1 = EconomyV2Report.V1
	if v1 ~= nil then
		-- v1 첫 도달이 1분 미만인 층(1 ~ 3층)은 분모가 작아 비율이 흔들린다 — 그 층은 빼고 잰다(보고에 층별 값을 따로 적는다)
		for stage = 2, 9 do
			local a, b = firstMin(r, stage), firstMin(v1, stage)
			if a ~= nil and b ~= nil and b >= 1 then
				worstEarly = math.max(worstEarly, math.abs(a / b - 1))
			end
		end
	end
	local pass = {
		t25 = t25 ~= nil and t25 >= G.t25[1] and t25 <= G.t25[2],
		t15 = k15 ~= nil and k15 >= G.t15[1] and k15 <= G.t15[2],
		rebirths = n25 ~= nil and n25 >= G.rebirths[1] and n25 <= G.rebirths[2],
		early = v1 ~= nil and worstEarly <= G.early,
		legend = legendMean ~= nil and legendMean < G.legendChance,
	}
	return { t25 = t25, k15 = k15, got15 = got15, n25 = n25, legendMean = legendMean, worstEarly = worstEarly, pass = pass }
end

function EconomyV2Report.report(b: Bundle, players: number): any
	local r = measureV2(b, players)
	local sm = EconomyV2Report.summarize(r)
	local m = r.metrics
	local seg = m.segments
	local p = sm.pass
	local function mark(ok: boolean): string
		return if ok then "O" else "X"
	end
	print(string.format("[ECON2] %s · %d명 · 25층 %d명 %s분[%s] · 15종 %d명 %s분[%s] · 25층까지 환생 %s회[%s] · 1~9층 최대 차 %.0f%%[%s] · 확률 전설 기대 %s[%s]",
		b.label, players, m.reached, fmt(sm.t25), mark(p.t25), sm.got15, fmt(sm.k15), mark(p.t15), fmt(sm.n25, "%.0f"), mark(p.rebirths),
		sm.worstEarly * 100, mark(p.early), fmt(sm.legendMean, "%.3f"), mark(p.legend)))
	local floors = {}
	for _, stage in ipairs({ 5, 9, 13, 17, 20, 23, 25 }) do
		table.insert(floors, string.format("%d:%s", stage, fmt(firstMin(r, stage))))
	end
	local gaps = {}
	for stage = 1, r.maxStage - 1 do
		local a, b2 = firstMin(r, stage), firstMin(r, stage + 1)
		if a ~= nil and b2 ~= nil then
			table.insert(gaps, { stage = stage, d = b2 - a })
		end
	end
	table.sort(gaps, function(x, y)
		return x.d > y.d
	end)
	local cliff = {}
	for i = 1, math.min(3, #gaps) do
		table.insert(cliff, string.format("%d→%d %.1f", gaps[i].stage, gaps[i].stage + 1, gaps[i].d))
	end
	local early = {}
	for stage = 3, 9 do
		table.insert(early, string.format("%d:%s", stage, fmt(firstMin(r, stage), "%.2f")))
	end
	print("[ECON2]   1 ~ 9층 첫 도달(분) " .. table.concat(early, " "))
	print(string.format("[ECON2]   층 첫 도달(분) %s · 성공률 %.1f / %.1f / %.1f · 체류 절벽 %s", table.concat(floors, " "), (seg[1].rate or 0) * 100,
		(seg[2].rate or 0) * 100, (seg[3].rate or 0) * 100, table.concat(cliff, " · ")))
	local intervals = {}
	for _, row in ipairs(r.rows) do
		if row.at25 ~= nil then
			local ra = row.at25.rebirthAt
			for i = 2, #ra do
				table.insert(intervals, (ra[i] - ra[i - 1]) / 60)
			end
		end
	end
	local kth = {}
	for k = 2, #Config.PICKAXES do
		local v = endMed(r, function(e)
			return if e.kthAt[k] ~= nil then e.kthAt[k] / 60 else nil
		end)
		table.insert(kth, string.format("%d:%s", k, fmt(v, "%.0f")))
	end
	print(string.format("[ECON2]   환생 첫 %s분 · 간격 %s분 · k종째(분) %s", fmt(at25Med(r, function(a)
		return if a.rebirthAt[1] ~= nil then a.rebirthAt[1] / 60 else nil
	end), "%.1f"), fmt(median(intervals), "%.2f"), table.concat(kth, " ")))
	local crafts = {}
	for s = 0, Config.CRAFT_INPUT do
		table.insert(crafts, string.format("%d칸 %s", s, fmt(endMed(r, function(e)
			return e.crafts[s]
		end), "%.0f")))
	end
	local toks = {}
	for _, rr in ipairs({ "rare", "epic", "mythic", "legendary", "next" }) do
		table.insert(toks, string.format("%s %s", rr, fmt(endMed(r, function(e)
			return e.tokens[rr] or 0
		end), "%.0f")))
	end
	local byToken = 0
	for _, row in ipairs(r.rows) do
		if row.end_ ~= nil and row.end_.legendByToken then
			byToken += 1
		end
	end
	print(string.format("[ECON2]   제작(끝까지) %s · 토큰 %s · 전설 토큰 교환 %d명 · 가방 가득 첫 층 %s · 모은 광석 %s · 잃은 광석 %s · 줍기 %s분",
		table.concat(crafts, " "), table.concat(toks, " "), byToken, fmt(endMed(r, function(e)
			return e.bagFullStage
		end), "%.0f"), fmt(endMed(r, function(e)
			return e.collected
		end), "%.0f"), fmt(endMed(r, function(e)
			return e.lostOre
		end), "%.0f"), fmt(endMed(r, function(e)
			return e.pickSec / 60
		end), "%.1f")))
	print(string.format("[ECON2]   블럭스(log10) 25층 잔고 %s · 끝 평생 %s · 씀 환생 %s · 아우라 %s · 칭호 %s · 업그레이드 %s · 끝 잔고 %s · 코인 %s · 부화 %s · 펫 배수 25층 %s · 곡괭이 배수 25층 %s",
		fmt(at25Med(r, function(a)
			return a.blox
		end)), fmt(endMed(r, function(e)
			return e.lifetime
		end)), fmt(endMed(r, function(e)
			return e.rebirthSpent
		end)), fmt(endMed(r, function(e)
			return e.aura
		end)), fmt(endMed(r, function(e)
			return e.title
		end)), fmt(endMed(r, function(e)
			return e.upgrade
		end)), fmt(endMed(r, function(e)
			return e.blox
		end)), fmt(endMed(r, function(e)
			return e.coins
		end)), fmt(endMed(r, function(e)
			return e.hatches
		end), "%.0f"), fmt(at25Med(r, function(a)
			return a.pet
		end), "%.2f"), fmt(at25Med(r, function(a)
			return a.pick
		end), "%.1f")))
	return sm
end

-- 손잡이 하나(key — Config 이름)를 log 공간 이분 탐색해 지표(metric: 요약 → 분)를 target에 맞춘다. 키우면 빨라지는 손잡이면 faster = true.
function EconomyV2Report.tune(b: Bundle, key: string, range: { number }, metric: string, target: number, faster: boolean): number
	local lo, hi = math.log(range[1]), math.log(range[2])
	for _ = 1, EconomyV2Report.TUNE_STEPS do
		local mid = (lo + hi) / 2
		local set = table.clone(b.set or {})
		set[key] = math.exp(mid)
		local r = measureV2({ label = b.label, set = set, policy = b.policy }, EconomyV2Report.TUNE_PLAYERS)
		local sm = EconomyV2Report.summarize(r)
		local v = sm[metric]
		local slow = v == nil or v > target
		if slow == faster then
			lo = mid
		else
			hi = mid
		end
	end
	return math.exp((lo + hi) / 2)
end

-- ===== 후보 묶음 · 비교 줄 ==========================================================================================

-- 묶음은 성격이 다르다(곡괭이 무게 · 환생 무게 · 제작 무게). 손잡이 하나씩을 25층 · 15종 목표에 맞춘다(run의 tune 단계).
EconomyV2Report.BUNDLES = {
	-- 2026-11-24 탐색 6회(EXPLORE)로 출발점을 고르고 run()이 PICK_RATIO(25층 120분) · AUTO_CRAFT_INTERVAL_SEC(15종 180분)를 다시 맞춘다
	{ label = "A 곡괭이 무게", set = { ORE_PER_BLOCK = 1, REBIRTH_COST_BASE = BigNum.new(1, 3), REBIRTH_COST_GROWTH = 3, REBIRTH_MULT_BASE = 1.15,
		PICK_RATIO = 1.32, AUTO_CRAFT_INTERVAL_SEC = 120 } },
	{ label = "B 환생 무게", set = { ORE_PER_BLOCK = 1, REBIRTH_COST_BASE = BigNum.new(1, 3), REBIRTH_COST_GROWTH = 4, REBIRTH_MULT_BASE = 1.36,
		PICK_RATIO = 1.15, AUTO_CRAFT_INTERVAL_SEC = 120 } },
	{ label = "C 균형", set = { ORE_PER_BLOCK = 1, REBIRTH_COST_BASE = BigNum.new(1, 3), REBIRTH_COST_GROWTH = 4, REBIRTH_MULT_BASE = 1.25,
		PICK_RATIO = 1.25, AUTO_CRAFT_INTERVAL_SEC = 150 } },
} :: { Bundle }

EconomyV2Report.EXPLORE = {
	{ label = "TEMP 지금 설정(= 추천 1순위 C 균형)" },
} :: { Bundle }

local function withPolicy(b: Bundle, label: string, pol: Policy): Bundle
	local p2 = table.clone(b.policy or {}) :: any
	for k, v in pairs(pol :: any) do
		p2[k] = v
	end
	return { label = b.label .. " · " .. label, set = b.set, policy = p2 }
end

function EconomyV2Report.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	task.wait(5) -- 시작 직후 테스트들이 MODEL · Config를 잠깐 흔드는 동안 기다린다
	local E = EconomyV2Report
	local t0 = os.clock()
	print(string.format("[ECON2] ===== 새 경제 2차 측정 (지시서 #30 — 추천까지만 · 숫자는 사람이 정한다) · 모드 %s =====", E.MODE))
	E.reproduceV1(200)
	if E.MODE == "explore" then
		for _, b in ipairs(E.EXPLORE) do
			E.report(b, E.PLAYERS)
			print(string.format("[ECON2]   · %.0f초", os.clock() - t0))
		end
		print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
		return
	end
	local tuned: { Bundle } = {}
	for _, b in ipairs(E.BUNDLES) do
		local set = table.clone(b.set or {})
		-- 1) 25층 ≈ 2시간: 곡괭이 배수 PICK_RATIO(키우면 빨라진다)
		set.PICK_RATIO = E.tune({ label = b.label, set = set, policy = b.policy }, "PICK_RATIO", { 1.08, 1.6 }, "t25", 120, true)
		-- 2) 15종 ≈ 3시간: 자동 제작 간격(키우면 느려진다)
		set.AUTO_CRAFT_INTERVAL_SEC = E.tune({ label = b.label, set = set, policy = b.policy }, "AUTO_CRAFT_INTERVAL_SEC", { 60, 300 }, "k15", 180, false)
		local tb = { label = b.label, set = set, policy = b.policy }
		table.insert(tuned, tb)
		local keys = {}
		for k, v in pairs(set) do
			table.insert(keys, string.format("%s=%s", k, if type(v) == "number" then string.format("%.4g", v) else tostring(v)))
		end
		table.sort(keys)
		print(string.format("[ECON2] 묶음 %s 맞춘 값: %s · %.0f초", b.label, table.concat(keys, " "), os.clock() - t0))
		E.report(tb, E.PLAYERS)
	end
	local ref = tuned[1]
	print(string.format("[ECON2] ----- 정책 비교 (%s 고정) · %.0f초 -----", ref.label, os.clock() - t0))
	E.report(withPolicy(ref, "환생 뒤 블럭스 0(#29 R4 정의)", { rebirthKeep = false }), E.PLAYERS)
	E.report(withPolicy(ref, "강화 아무 광석(낮은 것부터)", { enhance = "any" }), E.PLAYERS)
	E.report(withPolicy(ref, "강화 안 함", { enhance = "none" }), E.PLAYERS)
	E.report(withPolicy(ref, "교환 안 함", { exchange = "none" }), E.PLAYERS)
	E.report(withPolicy(ref, "워프 greedy(상한)", { warp = "greedy" }), E.PLAYERS)
	print(string.format("[ECON2] ----- 참고 측정 · 유료 상품 효과 (%s) · %.0f초 -----", ref.label, os.clock() - t0))
	E.report(withPolicy(ref, "자동 진행(전부 자동 줍기 · 시간 0)", { pickup = "auto" }), E.PLAYERS)
	E.report(withPolicy(ref, "큰 가방 ×2", { bagPass = 2 }), E.PLAYERS)
	E.report(withPolicy(ref, "빠른 제작(간격 ×" .. Config.FAST_CRAFT_FACTOR .. ")", { fastCraft = true }), E.PLAYERS)
	E.report(withPolicy(ref, "트리플 제작", { tripleCraft = true }), E.PLAYERS)
	print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
end

return EconomyV2Report

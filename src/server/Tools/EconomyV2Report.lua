--!strict
-- 새 경제 2차 · 3차 측정 (지시서 #30 6번 · #31 5번). ⚠️ 측정 도구다 — 숫자를 정하지 않는다(D2: 고르는 것은 희준). 추천까지만 한다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다.
--    새 경제의 식은 여기 다시 쓰지 않는다 — Shared/EconomyV2Logic(게이지 · 조합 · 제작 · 토큰 · 교환 · 별 · 강화 · 가방 · 코인 · 환생 v2)과
--    Shared/Config/EconomyV2Config를 그대로 부르고, 묶음(후보)마다 Config 값을 메모리에서 잠깐 바꾸고 끝나면 되돌린다
--    (EconomyCandidateReport · HpCandidateReport와 같은 패턴). 플래그(ECONOMY_V2)는 건드리지 않는다 — 배수 · 운동기구는 economyV2 인자로 부른다.
--    엔진은 SuccessRateReport(HP 곡선 · 런 · 수령 · 실패 · 칭호 S7 · 아우라 A4 · 업그레이드 S5' · 운동기구)다. 고리 ECON으로 붙는다.
-- 켜는 곳: SuccessRateReport.SIM.ECONOMY_V2_ONLY + Bootstrap SUCCESS_RATE_REPORT_ENABLED(둘 다 커밋 값 false).
--
-- ===== 표준 무과금 플레이어(지시서 #30 6번 · #31 5번 — 괄호는 Claude 해석) ===============================================
--   진행 · 클릭 · 진행 판단 · 칭호 · 아우라 · 운동기구   SuccessRateReport 결정 모델 그대로(수동 진행 · 클릭률 6 ~ 10)
--   환생      살 수 있으면 바로(#29 결론 — eager). 비용 EconomyV2Logic.rebirthCost · 나머지는 아우라 A4 → 업그레이드 S5'(펀치 속도 · 블럭스 획득 ·
--             펫 슬롯)에 쓰고, 남은 것은 남긴다(REBIRTH_KEEP_REMAINDER — 비교 줄 "0으로")
--   광석      층을 깰 때마다 EconomyV2Logic.rollDrops(층 · 블록 수 — 상위 광석은 × UPPER_ORE_DROP_MULT · 소수는 seed 난수). 줍기 = #29 표준 모델(타이머 중 드롭은 공격하며 줍고, 클리어 뒤
--             마지막 블록 드롭만 걸어간다 — EconomyCandidateReport.pickDistance · 반경 PICKUP_RADIUS). 가방 = 장착 곡괭이 용량 · 가득 차면 바꿔 줍기
--   코인      깬 층의 블록 수 × coinPerBlock(층)(실패한 층의 부서진 블록은 세지 않는다 — 과소). 펫: 런 직전 코인으로 해금된 가장 높은 알을 닿는 만큼
--             부화(E11과 같은 "가장 높은 것만" · 크래프팅 · 놓아주기). 펫 슬롯은 S5'가 블럭스로 산다
--   제작      자동 제작 켬 · 연출 + 스킵(#31 — EconomyV2Logic.craftStep: 무료는 CRAFT_SKIP_SEC마다 1회 · 쉬지 않고 — 광석이 떨어지면 그동안은
--             안 쌓인다). 대장간은 FORGE_UNLOCK_STAGE(Claude 제안 — nil이면 처음부터). 조합 = 가진 광석으로 칸이
--             가장 높은 조합(EconomyV2Logic.bestCombo — 같은 칸이면 합이 작고 높은 광석을 덜 쓰는 것) · #31부터 높은 광석 아껴 두기(standardCombo).
--             런 직전 · 런 끝에 몰아서 계산한다
--   교환      가진 토큰으로 살 수 있는 가장 좋은(rank 높은) 미보유 곡괭이 — 살 수 있는 동안 되풀이
--   별        여벌이 닿으면 올린다(어느 곡괭이든)
--   강화      장착한 곡괭이 · (지금 최선 조합의 가장 낮은 광석보다 낮은 광석만 낸다 — 제작에 안 쓰일 광석. 비교 줄 "아무 광석") · 수령 직후 먼저
--   부화      연출 + 스킵(#31 — EconomyV2Logic.hatchStep: 무료는 HATCH_SKIP_SEC마다 1회)
--   자동 진행 구매자(#31 참고 줄) AutoAdvanceLogic.safeFloor · defaultTarget과 지난 런 최고층 + 1(실패면 + 0) 중 큰 쪽을 목표층으로 — 진행 판정은 ECON.advance
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
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local SuccessRateReport = require(script.Parent.SuccessRateReport)
local EconomyCandidateReport = require(script.Parent.EconomyCandidateReport)
local AttackService = require(script.Parent.Parent.Systems.AttackService)
local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
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
EconomyV2Report.DROP_SEED = 20261126
-- 합격 기준(지시서 #31 5번 — 게임 수치가 아니다). 초반은 1 ~ 7층만(8 · 9층은 빨라져도 된다 — N6 해소)
EconomyV2Report.GOAL = {
	t25 = { 105, 135 }, -- 분
	t15 = { 160, 200 },
	rebirths = { 10, 20 },
	early = 0.10, -- 1 ~ 7층 첫 도달 ±10%
	earlyTo = 7,
	robust = 0.10, -- 1회 제작 0 · 5 · 10초 · 트리플이 15종을 바꾸는 폭
	legendChance = 0.1, -- 3시간 안 확률 전설 기대 횟수
	horizonMin = 180,
}
-- run() 모드: "full"(재현 + 후보 묶음 + 정책 비교 + 참고 측정) · "explore"(재현 + EXPLORE 목록만)
EconomyV2Report.MODE = "full"

export type Policy = {
	rebirthKeep: boolean?, -- nil = Config.REBIRTH_KEEP_REMAINDER
	enhance: string?, -- "fodder"(기본) · "any" · "none"
	pickup: string?, -- "hand"(기본) · "auto"(자동 진행 구매자 — AutoAdvanceLogic 목표층 진행 · 드롭 전부 자동 · 줍기 시간 0)
	warp: string?, -- "none"(기본) · "greedy"
	bagPass: number?, -- 큰 가방 배수(구매자)
	craftSkip: boolean?, -- 제작 연출 생략(구매자 — 서버 최소 간격)
	tripleCraft: boolean?,
	craftSec: number?, -- 견고함: 1회 제작 시간을 이 값으로(0 = 즉시)
	hatchSkip: boolean?, -- 부화 연출 생략(구매자)
	tripleHatch: boolean?, -- 트리플 부화(기존 Triple Hatch)
	bloxPass: number?, -- 비교용 2배 블럭스
	damagePass: number?, -- 비교용 2배 데미지
	exchange: string?, -- "best"(기본) · "none"
}
export type Bundle = { label: string, set: { [string]: any }?, policy: Policy?, hpSegments: { any }? }

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
-- 묶음 set에서 "이 키를 nil로" 표시(표에 nil을 못 넣는다)
EconomyV2Report.NONE = table.freeze({})

-- 표준 플레이어의 조합(지시서 #31 — Claude 해석). 가진 광석으로 닿는 가장 높은 칸 s를 고르고, 그 칸을 광석 2s + 1 이하만으로 채울 수 있으면
-- 그렇게 한다(높은 광석은 더 높은 칸에 아껴 둔다). 못 채우면 EconomyV2Logic.bestCombo 그대로.
-- 이유: 5초 제작이면 제작이 공급보다 빨라 bestCombo만으로는 20층 이상 광석이 3칸 제작에 섞여 녹는다(4칸이 안 생긴다 — 3차 측정 첫 실행).
function EconomyV2Report.standardCombo(inv: { number }): ({ number }?, number)
	local combo, slots = EconomyV2Logic.bestCombo(inv)
	if combo == nil then
		return nil, 0
	end
	local cap = 2 * slots + 1
	if cap >= Config.ORE_COUNT then
		return combo, slots
	end
	local filtered = table.clone(inv)
	for k = cap + 1, Config.ORE_COUNT do
		filtered[k] = 0
	end
	local c2, s2 = EconomyV2Logic.bestCombo(filtered)
	if c2 ~= nil and s2 == slots then
		return c2, s2
	end
	return combo, slots
end

local function withBundle(b: Bundle, fn: () -> ())
	local SRR = SuccessRateReport :: any
	local MODEL = SuccessRateReport.MODEL :: any
	local saved: { [string]: any } = {}
	local touched: { string } = {} -- 원래 값이 nil인 키도 되돌린다(FORGE_UNLOCK_STAGE · ENHANCE_BLOX_COST_BASE)
	for k, v in pairs(b.set or {}) do
		saved[k] = (Config :: any)[k]
		table.insert(touched, k)
		;(Config :: any)[k] = if v == EconomyV2Report.NONE then nil else v
	end
	-- HP 곡선 변형(⚠️ 희준 결정 영역 — 비교 줄에만 쓴다. 기본안 아님)
	local world = WorldConfig.get(SuccessRateReport.SIM.WORLD_ID) :: any
	local savedHp = world.hpGrowthSegments
	local savedBloxSeg = world.bloxGrowthSegments
	if b.hpSegments ~= nil then
		world.hpGrowthSegments = b.hpSegments
	end
	-- 보상 곡선 변형(비교 줄 — 24 → 25층 막힘 방법). HP는 그대로
	if (b :: any).bloxSegments ~= nil then
		world.bloxGrowthSegments = (b :: any).bloxSegments
	end
	local savedSRR = {
		econ = SRR.ECON,
		click = SRR.clickMultiplier,
		damage = SRR.damageMultiplier,
		gym = SRR.gymUnlockedCount,
		blox = SRR.bloxMultiplier,
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
	for _, k in ipairs(touched) do
		(Config :: any)[k] = saved[k]
	end
	world.hpGrowthSegments = savedHp
	world.bloxGrowthSegments = savedBloxSeg
	SRR.bloxMultiplier = savedSRR.blox
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
		-- 제작 · 부화 시간(지시서 #31 — 연출 + 스킵). 표준 무과금은 스킵 시점마다 1회. 견고함 줄은 craftSec으로 1회 시간을 바꾼다
		local interval, perTick = EconomyV2Logic.craftStep(pol.craftSkip, pol.tripleCraft)
		if pol.craftSec ~= nil then
			interval = pol.craftSec
		end
		local hatchSec, hatchPer = EconomyV2Logic.hatchStep(pol.hatchSkip, pol.tripleHatch)
		local origBlox = SuccessRateReport.bloxMultiplier
		local craftRandom = RollService.seededRandom(EconomyV2Report.CRAFT_SEED)
		local petCoinRandom = RollService.seededRandom(EconomyV2Report.PET_COIN_SEED)
		local dropRandom = RollService.seededRandom(EconomyV2Report.DROP_SEED)
		local maxStage = lastStage()
		local states: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
		local function st(p: any): any
			local s = states[p]
			if s == nil then
				s = {
					n = 0, picks = EconomyV2Logic.newPicks(), inv = EconomyV2Logic.newInv(), bag = EconomyV2Logic.newInv(),
					coins = BigNum.new(0, 0), coinsTotal = BigNum.new(0, 0), craftClock = 0, hatchClock = 0, crafts = {}, tokensEarned = {},
					backlogMax = 0, backlogSum = 0, backlogN = 0, star180 = nil, enhanceBlox = BigNum.new(0, 0), autoTarget = 1,
					first24 = nil, at25 = nil, stop24 = 0, fail24 = 0, clear24 = 0, maxEver = 0,
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
		local function forgeOpen(s: any): boolean
			return EconomyV2Logic.forgeOpen(s.maxEver, s.n) -- FORGE_UNLOCK_REBIRTHS · FORGE_UNLOCK_STAGE(Claude 제안)
		end
		local function doCrafts(p: any, s: any)
			if not forgeOpen(s) then
				s.craftClock = p.elapsedSec
				return
			end
			local ticks = if interval > 0 then math.floor((p.elapsedSec - s.craftClock) / interval) else math.huge
			if ticks <= 0 then
				return
			end
			local budget = if ticks == math.huge then math.huge else ticks * perTick
			local done = 0
			local ranOut = false
			while done < budget do
				local combo, slots = EconomyV2Report.standardCombo(s.inv)
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
					local craftSec = s.craftClock + (if interval > 0 then math.ceil(done / perTick) * interval else 0)
					if craftSec <= EconomyV2Report.GOAL.horizonMin * 60 then
						s.expLegend += LEGEND_PCT[slots] / 100
					end
					local def = EconomyV2Logic.pickaxe(r.id) :: any
					if def.rarity == "legendary" and not before then
						s.legendByChance += 1
					end
				end
			end
			if ranOut or interval <= 0 then
				s.craftClock = p.elapsedSec
			else
				s.craftClock += math.ceil(done / perTick) * interval
			end
		end
		-- 쌓인 광석을 자동 제작으로 다 쓰는 데 걸리는 초(런을 마칠 때 — 잠수 제작의 의미)
		local function backlogSec(s: any): number
			local total = 0
			for k = 1, Config.ORE_COUNT do
				total += s.inv[k]
			end
			local sets = total // Config.CRAFT_INPUT
			return if interval > 0 then math.ceil(sets / perTick) * interval else 0
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
		local function doUpgrades(p: any, s: any)
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
					local combo = EconomyV2Report.standardCombo(s.inv)
					maxOre = if combo ~= nil then (combo :: { number })[1] - 1 else 0
				end
				if maxOre == nil or (maxOre :: number) > 0 then
					while true do
						local o = s.picks.owned[s.picks.equipped]
						-- N5 변형: 강화에 블럭스도 든다(ENHANCE_BLOX_COST_BASE — 기본 nil)
						local bc = EconomyV2Logic.enhanceBloxCost(o.enh)
						if bc ~= nil and not BigNum.gte(p.blox, bc :: BigNumber) then
							break
						end
						if not EconomyV2Logic.enhance(s.picks, s.picks.equipped, s.inv, maxOre) then
							break
						end
						if bc ~= nil then
							p.blox = BigNum.sub(p.blox, bc :: BigNumber)
							s.enhanceBlox = BigNum.add(s.enhanceBlox, bc :: BigNumber)
						end
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
			-- 부화 시간(지시서 #31 — 연출 + 스킵): 지난번부터 흐른 시간에 할 수 있는 회수까지만
			local actions = if hatchSec > 0 then math.floor((p.elapsedSec - s.hatchClock) / hatchSec) else math.huge
			local cap = if actions == math.huge then math.huge else actions * hatchPer
			local timeBound = n >= cap
			n = math.min(n, cap)
			if timeBound and hatchSec > 0 then
				s.hatchClock += actions * hatchSec
			else
				s.hatchClock = p.elapsedSec
			end
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
			advance = if auto then function(p, stage, _timeLeft)
				return stage < st(p).autoTarget
			end else nil,
			onRunStart = function(p)
				local s = st(p)
				doCrafts(p, s)
				if forgeOpen(s) then
					doExchanges(s)
					doUpgrades(p, s)
				end
				noteOwned(p, s)
				hatchWithCoins(p, s)
				if s.star180 == nil and p.elapsedSec >= EconomyV2Report.GOAL.horizonMin * 60 then
					local hist = { [0] = 0, 0, 0, 0, 0, 0 }
					for _, o in pairs(s.picks.owned) do
						hist[o.stars] += 1
					end
					s.star180 = { hist = hist, owned = ownedCount(s) }
				end
				if auto then
					-- 자동 진행 구매자(Claude 해석): 목표층 = 안전층(AutoAdvanceLogic.safeFloor · defaultTarget)과 지난 런 최고층 + 1 중 큰 쪽 —
					-- 지난 런이 실패였으면 + 1 없이 지난 최고층(그 층에서 수령). 진행 판정은 게임과 같다(AutoAdvanceService: 목표층이면 수령, 아니면 진행)
					local punch = BigNum.mul(p.strength, BigNum.fromNumber(SuccessRateReport.damageMultiplier(p)))
					local safe = AutoAdvanceLogic.safeFloor(punch, SuccessRateReport.effect(p.upgrades, "punchSpeed"))
					local push = if p.lastRunReward ~= nil and p.lastRunReward.m > 0 then p.lastBest + 1 else p.lastBest
					local target = math.max(AutoAdvanceLogic.defaultTarget(safe), push)
					s.autoTarget = math.clamp(target, AutoAdvanceLogic.FIRST_STAGE, AutoAdvanceLogic.maxTarget())
				end
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
				local drops = EconomyV2Logic.rollDrops(stage, blocks, dropRandom) -- 소수 기대값은 블록마다 확률(게임과 같은 함수)
				if stage == 24 then
					s.clear24 += 1
				end
				s.maxEver = math.max(s.maxEver, stage)
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
			onRunEnd = function(p, best, cashed)
				local s = st(p)
				doCrafts(p, s)
				if s.first24 ~= nil and s.at25 == nil then
					if cashed and best == 24 then
						s.stop24 += 1
					elseif not cashed and best == 23 then
						s.fail24 += 1
					end
				end
				for k = 1, Config.ORE_COUNT do
					if cashed then
						s.inv[k] += s.bag[k]
						s.collected += s.bag[k]
					else
						s.lostOre += s.bag[k]
					end
					s.bag[k] = 0
				end
				if cashed and forgeOpen(s) then
					-- 수령 직후 강화가 먼저 고른다(제작이 낮은 광석을 먼저 녹이면 1회 제작 시간에 따라 강화 몫이 달라진다 — 견고함)
					doUpgrades(p, s)
				end
				if cashed then
					local bl = backlogSec(s)
					s.backlogMax = math.max(s.backlogMax, bl)
					s.backlogSum += bl
					s.backlogN += 1
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
				passMult = pol.damagePass,
			})
		end
		if pol.bloxPass ~= nil then
			SRR.bloxMultiplier = function(p: any): number
				return origBlox(p) * (pol.bloxPass :: number)
			end
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
					if st ~= nil and stage == 24 then
						local s = st(p)
						s.first24 = runStart
						s.n24 = s.n
						cur.pick24 = EconomyV2Logic.equippedMult(s.picks)
					end
					if stage == maxStage and st ~= nil then
						local s = st(p)
						s.at25 = true
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
				backlogMax = s.backlogMax, backlogMean = if s.backlogN > 0 then s.backlogSum / s.backlogN else 0, star180 = s.star180,
				enhanceBlox = log10Big(s.enhanceBlox), stop24 = s.stop24, fail24 = s.fail24, n24 = s.n24,
			}
		end
		cur.p = nil
		table.insert(rows, cur)
		task.wait()
	end
	return { rows = rows, metrics = SuccessRateReport.metrics(firstTry, results), players = players, maxStage = maxStage, firstTry = firstTry }
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
		for stage = 2, G.earlyTo do
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
	print(string.format("[ECON2] %s · %d명 · 25층 %d명 %s분[%s] · 15종 %d명 %s분[%s] · 25층까지 환생 %s회[%s] · 1~7층 최대 차 %.0f%%[%s] · 확률 전설 기대 %s[%s]",
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
		local v1 = EconomyV2Report.V1
		local a, b = firstMin(r, stage), if v1 ~= nil then firstMin(v1, stage) else nil
		table.insert(early, string.format("%d:%s(%s)", stage, fmt(a, "%.2f"), if a ~= nil and b ~= nil and b > 0 then string.format("%+.0f%%", (a / b - 1) * 100) else "-"))
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
-- 지시서 #31: 쌓이는 광석 · 별(3시간) · 강화 블럭스 · 24 → 25층
local hist = { [0] = 0, 0, 0, 0, 0, 0 }
local nStar = 0
local fives = {}
local owned180 = {}
for _, row in ipairs(r.rows) do
	local e = row.end_
	if e ~= nil and e.star180 ~= nil then
		nStar += 1
		for k = 0, 5 do
			hist[k] += e.star180.hist[k]
		end
		table.insert(fives, e.star180.hist[5])
		table.insert(owned180, e.star180.owned)
	end
end
local histTxt = {}
for k = 0, 5 do
	table.insert(histTxt, string.format("%d성 %.1f", k, if nStar > 0 then hist[k] / nStar else 0))
end
print(string.format("[ECON2]   쌓인 광석 다 쓰는 시간(런 끝 · 분) 평균 %s · 최대 %s · 별(3시간 · %d명 평균 곡괭이 수) %s · 5성 곡괭이 %s개 · 보유 %s종 · 강화 블럭스 %s",
	fmt(endMed(r, function(e)
		return e.backlogMean / 60
	end), "%.2f"), fmt(endMed(r, function(e)
		return e.backlogMax / 60
	end), "%.1f"), nStar, table.concat(histTxt, " "), fmt(median(fives), "%.0f"), fmt(median(owned180), "%.0f"), fmt(endMed(r, function(e)
		return e.enhanceBlox
	end))))
local gap2425 = {}
local reb = {}
local pickGain = {}
for _, row in ipairs(r.rows) do
	if row.first[24] ~= nil and row.first[25] ~= nil then
		table.insert(gap2425, (row.first[25] - row.first[24]) / 60)
		if row.at25 ~= nil and row.end_ ~= nil and row.end_.n24 ~= nil then
			table.insert(reb, row.at25.n - row.end_.n24)
		end
		if row.pick24 ~= nil and row.at25 ~= nil then
			table.insert(pickGain, row.at25.pick / row.pick24)
		end
	end
end
local rates = {}
for stage = 21, r.maxStage do
	local t = r.firstTry[stage]
	table.insert(rates, string.format("%d:%s", stage, if t ~= nil and t.attempts > 0 then string.format("%.0f%%", t.successes / t.attempts * 100) else "-"))
end
print(string.format("[ECON2]   24→25층 간격 %s분 · 그동안 환생 %s회 · 24층에서 멈춘(수령) 런 %s · 24층 실패 런 %s · 곡괭이 배수 늘어남 ×%s · 첫 시도 성공률 %s",
	fmt(median(gap2425)), fmt(median(reb), "%.0f"), fmt(endMed(r, function(e)
		return e.stop24
	end), "%.0f"), fmt(endMed(r, function(e)
		return e.fail24
	end), "%.0f"), fmt(median(pickGain), "%.2f"), table.concat(rates, " ")))
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

-- 지시서 #31 3차 측정: 묶음 C(환생 1000 · ×4 · 1.25^n) 바탕. 25층 ≈ 2시간 = 곡괭이 배수(PICK_RATIO) · 15종 ≈ 3시간 = 상위 광석 공급(k15Key).
-- 제작 간격은 손잡이가 아니다(연출 + 스킵 — 1회 5초 무료). run()이 묶음마다 손잡이 둘을 이분 탐색으로 맞춘다.
-- 묶음마다 대장간 조건 두 키를 늘 적는다(표에 nil을 못 넣으므로 NONE — withBundle이 그 동안 nil로 둔다 = 조건 없음. 커밋 TEMP 값과 상관없이 같은 측정)
local NONE = EconomyV2Report.NONE
local C_BASE = { ORE_PER_BLOCK = 1, REBIRTH_COST_BASE = BigNum.new(1, 3), REBIRTH_COST_GROWTH = 4, REBIRTH_MULT_BASE = 1.25, PICK_RATIO = 1.255,
	UPPER_ORE_DROP_MULT = 1, FORGE_UNLOCK_REBIRTHS = NONE, FORGE_UNLOCK_STAGE = NONE }
local function withSet(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in pairs(extra) do
		t[k] = v
	end
	return t
end
EconomyV2Report.C_BASE = C_BASE

EconomyV2Report.BUNDLES = {
	-- 2026-11-24 탐색 2회: 설정만으로는 1 ~ 7층 ±10%가 안 된다(곡괭이 1.10이어도 7층 −20% — 5초 제작이면 3분 안에 7종).
	-- 대장간을 8층에서 열면(Claude 제안) 1 ~ 7층 5% 안. 셋 다 15종은 상위 드롭(UPPER_ORE_DROP_MULT)으로 맞춘다
	{ label = "R1 대장간 8층", set = withSet(C_BASE, { FORGE_UNLOCK_STAGE = 8, PICK_RATIO = 1.21, UPPER_ORE_DROP_MULT = 0.10 }), k15Key = "UPPER_ORE_DROP_MULT", k15Range = { 0.03, 1 } },
	{ label = "R2 대장간 첫 환생 뒤", set = withSet(C_BASE, { FORGE_UNLOCK_REBIRTHS = 1, PICK_RATIO = 1.21, UPPER_ORE_DROP_MULT = 0.10 }),
		k15Key = "UPPER_ORE_DROP_MULT", k15Range = { 0.03, 1 } },
	{ label = "R3 설정만(대장간 처음부터)", set = withSet(C_BASE, { PICK_RATIO = 1.15, UPPER_ORE_DROP_MULT = 0.12 }), k15Key = "UPPER_ORE_DROP_MULT", k15Range = { 0.03, 1 } },
} :: { any }

EconomyV2Report.EXPLORE = {
	-- 커밋한 TEMP 값(추천 1순위 R2 반올림) 확인 + 견고함
	{ label = "TEMP 지금 값(R2 반올림)" },
	{ label = "TEMP · 1회 0초", policy = { craftSec = 0 } },
	{ label = "TEMP · 1회 10초", policy = { craftSec = 10 } },
	{ label = "TEMP · 트리플", policy = { tripleCraft = true } },
} :: { any }

-- 24 → 25층 막힘 줄이는 방법(run 끝에서 측정). hpSegments가 있는 줄은 ⚠️ HP 곡선 변형 — 희준 결정 영역, 기본안 아님
EconomyV2Report.CLIFF = {
	{ label = "M1 보상 17~25층 ×3.0(HP 그대로)", bloxSegments = { { from = 1, to = 16, growth = 2.7 }, { from = 17, to = 25, growth = 3.0 } } },
	{ label = "M2 환생 비용 ×3.5", set = { REBIRTH_COST_GROWTH = 3.5 } },
	{ label = "M3 ⚠️HP 변형(희준 결정 영역 · 기본안 아님) 24~25층 ×4.5",
		hpSegments = { { from = 1, to = 8, growth = 2.8 }, { from = 9, to = 16, growth = 3.8 }, { from = 17, to = 23, growth = 6.0 }, { from = 24, to = 25, growth = 4.5 } } },
} :: { any }

local function withPolicy(b: any, label: string, pol: Policy): any
	local p2 = table.clone(b.policy or {}) :: any
	for k, v in pairs(pol :: any) do
		p2[k] = v
	end
	return { label = b.label .. " · " .. label, set = b.set, policy = p2, hpSegments = b.hpSegments, bloxSegments = b.bloxSegments }
end

local function withExtra(b: any, label: string, extra: { [string]: any }): any
	return { label = b.label .. " · " .. label, set = withSet(b.set or {}, extra), policy = b.policy, hpSegments = b.hpSegments }
end

local function setText(set: { [string]: any }): string
	local keys = {}
	for k, v in pairs(set) do
		local txt
		if type(v) == "number" then
			txt = string.format("%.4g", v)
		elseif v == EconomyV2Report.NONE then
			txt = "nil"
		elseif type(v) == "table" and v.m ~= nil then
			txt = string.format("%ge%d", v.m, v.e)
		else
			txt = tostring(v)
		end
		table.insert(keys, string.format("%s=%s", k, txt))
	end
	table.sort(keys)
	return table.concat(keys, " ")
end

function EconomyV2Report.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	task.wait(5) -- 시작 직후 테스트들이 MODEL · Config를 잠깐 흔드는 동안 기다린다
	local E = EconomyV2Report
	local t0 = os.clock()
	print(string.format("[ECON2] ===== 새 경제 3차 측정 (지시서 #31 — 추천까지만 · 숫자는 사람이 정한다) · 모드 %s =====", E.MODE))
	E.reproduceV1(200)
	if E.MODE == "explore" then
		for _, b in ipairs(E.EXPLORE) do
			E.report(b, E.PLAYERS)
			print(string.format("[ECON2]   · %.0f초", os.clock() - t0))
		end
		print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
		return
	end
	local tuned: { any } = {}
	local summaries: { any } = {}
	for _, b in ipairs(E.BUNDLES) do
		local set = table.clone(b.set or {})
		-- 1) 25층 ≈ 2시간: 곡괭이 배수 PICK_RATIO(키우면 빨라진다)
		set.PICK_RATIO = E.tune({ label = b.label, set = set, policy = b.policy }, "PICK_RATIO", { 1.05, 1.5 }, "t25", 120, true)
		-- 2) 15종 ≈ 3시간: 상위 광석 공급(키우면 빨라진다)
		set[b.k15Key] = E.tune({ label = b.label, set = set, policy = b.policy }, b.k15Key, b.k15Range, "k15", 180, true)
		-- 3) 15종을 바꾸면 25층이 조금 움직인다 — 곡괭이 배수를 한 번 더 맞춘다
		set.PICK_RATIO = E.tune({ label = b.label, set = set, policy = b.policy }, "PICK_RATIO", { set.PICK_RATIO / 1.06, set.PICK_RATIO * 1.06 }, "t25", 120, true)
		local tb = { label = b.label, set = set, policy = b.policy }
		table.insert(tuned, tb)
		print(string.format("[ECON2] 묶음 %s 맞춘 값: %s · %.0f초", b.label, setText(set), os.clock() - t0))
		table.insert(summaries, E.report(tb, E.PLAYERS))
	end
	local ref = tuned[1]
	local refSm = summaries[1]
	print(string.format("[ECON2] ----- 견고함 (%s 고정 — 1회 제작 시간 · 트리플이 15종을 바꾸는 폭, 기준 ±%.0f%%) · %.0f초 -----", ref.label, E.GOAL.robust * 100, os.clock() - t0))
	for i, b in ipairs(tuned) do
		local base = summaries[i]
		local deltas = {}
		for _, row in ipairs({ { "0초(연출 생략)", { craftSec = 0 } }, { "10초", { craftSec = 10 } }, { "트리플", { tripleCraft = true } } }) do
			local sm = E.report(withPolicy(b, "1회 제작 " .. row[1], row[2]), E.PLAYERS)
			local d = if sm.k15 ~= nil and base.k15 ~= nil then (sm.k15 / base.k15 - 1) * 100 else nil
			table.insert(deltas, string.format("%s %s%%", row[1], if d ~= nil then string.format("%+.1f", d) else "-"))
		end
		print(string.format("[ECON2] 견고함 %s: 15종 %s분 대비 %s", b.label, fmt(base.k15), table.concat(deltas, " · ")))
	end
	print(string.format("[ECON2] ----- N5 강화에 블럭스 변형 (%s) · %.0f초 -----", ref.label, os.clock() - t0))
	E.report(withExtra(ref, "강화 블럭스 1e4 × 10^수준", { ENHANCE_BLOX_COST_BASE = BigNum.new(1, 4), ENHANCE_BLOX_COST_GROWTH = 10 }), E.PLAYERS)
	E.report(withExtra(ref, "강화 블럭스 1e7 × 10^수준", { ENHANCE_BLOX_COST_BASE = BigNum.new(1, 7), ENHANCE_BLOX_COST_GROWTH = 10 }), E.PLAYERS)
	print(string.format("[ECON2] ----- 24 → 25층 막힘 방법 (%s) · %.0f초 -----", ref.label, os.clock() - t0))
	for _, c in ipairs(E.CLIFF) do
		local b = { label = ref.label .. " · " .. c.label, set = withSet(ref.set, c.set or {}), policy = ref.policy, hpSegments = c.hpSegments,
			bloxSegments = c.bloxSegments }
		E.report(b, E.PLAYERS)
	end
	print(string.format("[ECON2] ----- 참고 측정 · 유료 상품 효과 (%s) · %.0f초 -----", ref.label, os.clock() - t0))
	E.report(withPolicy(ref, "자동 진행(AutoAdvanceLogic 목표층 · 전부 자동 줍기)", { pickup = "auto" }), E.PLAYERS)
	E.report(withPolicy(ref, "큰 가방 ×2", { bagPass = 2 }), E.PLAYERS)
	E.report(withPolicy(ref, "제작 연출 생략", { craftSkip = true }), E.PLAYERS)
	E.report(withPolicy(ref, "트리플 제작", { tripleCraft = true }), E.PLAYERS)
	E.report(withPolicy(ref, "부화 연출 생략", { hatchSkip = true }), E.PLAYERS)
	E.report(withPolicy(ref, "트리플 부화", { tripleHatch = true }), E.PLAYERS)
	E.report(withPolicy(ref, "비교 2배 블럭스", { bloxPass = 2 }), E.PLAYERS)
	E.report(withPolicy(ref, "비교 2배 데미지", { damagePass = 2 }), E.PLAYERS)
	print(string.format("[ECON2] 기준 %s 25층 %s · 15종 %s", ref.label, fmt(refSm.t25), fmt(refSm.k15)))
	print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
end

return EconomyV2Report

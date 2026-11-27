--!strict
-- 새 경제 2차 ~ 5차 측정 (지시서 #30 6번 · #31 5번 · #32 6번 · #33 6번 — 5차 결과 docs/TUNING.md 10절 · TEMP = V4). ⚠️ 측정 도구다 — 숫자를 정하지 않는다(D2: 고르는 것은 희준). 추천까지만 한다.
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다.
--    새 경제의 식은 여기 다시 쓰지 않는다 — Shared/EconomyV2Logic(게이지 · 조합 · 제작 · 토큰 · 교환 · 별 · 강화 · 가방 · 코인 · 환생 v2)과
--    Shared/Config/EconomyV2Config를 그대로 부르고, 묶음(후보)마다 Config 값을 메모리에서 잠깐 바꾸고 끝나면 되돌린다
--    (#37 — 플래그 ECONOMY_V2는 지웠다. 이름도 EconomyV2Report → EconomyReport).
--    엔진은 SuccessRateReport(HP 곡선 · 런 · 수령 · 실패 · 칭호 S7 · 아우라 A4 · 업그레이드 S5' · 운동기구)다. 고리 ECON으로 붙는다.
-- 켜는 곳: SuccessRateReport.SIM.ECONOMY_ONLY + Bootstrap SUCCESS_RATE_REPORT_ENABLED(둘 다 커밋 값 false).
--
-- ===== 표준 무과금 플레이어(지시서 #30 6번 · #31 5번 — 괄호는 Claude 해석) ===============================================
--   진행 · 클릭 · 진행 판단 · 칭호 · 아우라 · 운동기구   SuccessRateReport 결정 모델 그대로(수동 진행 · 클릭률 6 ~ 10)
--   환생      살 수 있으면 바로(#29 결론 — eager). 비용 EconomyV2Logic.rebirthCost · 나머지는 아우라 A4 → 업그레이드 S5'(펀치 속도 · 블럭스 획득 ·
--             펫 슬롯)에 쓰고, 남은 것은 남긴다(REBIRTH_KEEP_REMAINDER — 비교 줄 "0으로")
--   광석      층을 깰 때마다 EconomyV2Logic.rollDrops(층 · 블록 수 — 상위 광석은 × UPPER_ORE_DROP_MULT · 소수는 seed 난수). 줍기 = #29 표준 모델(타이머 중 드롭은 공격하며 줍고, 클리어 뒤
--             마지막 블록 드롭만 걸어간다 — EconomyReport.pickDistance · 반경 PICKUP_RADIUS). 가방 = 장착 곡괭이 용량 · 가득 차면 바꿔 줍기
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
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local AttackService = require(script.Parent.Parent.Systems.AttackService)
local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
local RollService = require(script.Parent.Parent.Systems.RollService)
local RollLogic = require(script.Parent.Parent.Systems.RollLogic)

type BigNumber = BigNum.BigNumber

local EconomyReport = {}

-- 클리어 뒤 줍기 걷는 거리(#29 표준 모델 — #37에서 EconomyCandidateReport가 지워지며 여기로 옮겼다. 식 그대로)
-- 블록 자리(층 중심 기준) 거리 목록
local distCache: { [number]: { Vector3 } } = {}
local function offsets(stage: number): { Vector3 }
	local cached = distCache[stage]
	if cached ~= nil then
		return cached
	end
	local origin = BlockLayout.getStageOrigin(stage)
	local out = {}
	for i, pos in ipairs(BlockLayout.computeLayout(StageConfig.getBlockCount(stage), stage)) do
		local d = pos - origin
		out[i] = Vector3.new(d.X, 0, d.Z)
	end
	distCache[stage] = out
	return out
end

-- 클리어 뒤 걷는 거리(스터드). "last" = 마지막 블록(평균 거리) 왕복, "all" = 가까운 순 순회 + 복귀. 반경 r 안은 걷지 않는다.
function EconomyReport.pickDistance(stage: number, kind: string, r: number): number
	local pts = offsets(stage)
	if kind == "last" then
		local sum = 0
		for _, v in ipairs(pts) do
			sum += v.Magnitude
		end
		return 2 * math.max(0, sum / #pts - r)
	end
	local pos = Vector3.zero
	local left = table.clone(pts)
	local total = 0
	while #left > 0 do
		-- r 안은 이미 끌려왔다
		for i = #left, 1, -1 do
			if (left[i] - pos).Magnitude <= r then
				table.remove(left, i)
			end
		end
		if #left == 0 then
			break
		end
		local bi, bd = 1, math.huge
		for i, v in ipairs(left) do
			local d = (v - pos).Magnitude
			if d < bd then
				bi, bd = i, d
			end
		end
		local target = left[bi]
		local step = math.max(0, bd - r)
		pos = pos + (target - pos).Unit * step
		total += step
		table.remove(left, bi) -- 부동소수 오차로 r 경계에서 남지 않게 직접 뺀다
	end
	return total + pos.Magnitude
end


-- 관측 해상도(게임 수치가 아니다)
EconomyReport.PLAYERS = 100
EconomyReport.TUNE_PLAYERS = 30
EconomyReport.TUNE_STEPS = 6
EconomyReport.CRAFT_SEED = 20261124
EconomyReport.PET_COIN_SEED = 20261125
EconomyReport.DROP_SEED = 20261126
-- 합격 기준(지시서 #31 5번 — 게임 수치가 아니다). 초반은 1 ~ 7층만(8 · 9층은 빨라져도 된다 — N6 해소)
EconomyReport.GOAL = {
	t25 = { 105, 135 }, -- 분
	t15 = { 160, 200 },
	rebirths = { 10, 20 },
	early = 0.10, -- 1 ~ 7층 첫 도달 ±10%
	earlyTo = 7,
	robust = 0.10, -- 1회 제작 0 · 5 · 10초 · 트리플이 15종을 바꾸는 폭
	k5 = 25, -- #32 획득 퍼짐: 5종째 25분 이내
	k10 = { 50, 90 }, -- 10종째
	k14 = { 120, 160 }, -- 14종째
	gap2425 = 10, -- 24 → 25층 체류 중앙값(분) 이하
	-- #33 강화 목표(Claude 해석 — 측정 기준): 새 곡괭이 +0 ≥ 이전 곡괭이 +10(따라잡는 강 0) · 장착이 바뀔 때 나가는 곡괭이 강화 중앙값 ≥ 3
	-- (강화가 공백을 채웠다) · +10에 닿고 노는 시간 중앙값 ≤ 5분(공백보다 일찍 끝나지 않았다)
	enhOut = 3,
	enhIdle = 5,
	legendChance = 0.1, -- 3시간 안 확률 전설 기대 횟수
	horizonMin = 180,
}
-- run() 모드: "full"(재현 + 후보 묶음 + 정책 비교 + 참고 측정) · "explore"(재현 + EXPLORE 목록만) · "gym"(운동기구 선택지 GYM_OPTIONS만 — #41 · docs/GYM_OPTIONS.md) ·
-- "types"(플레이어 유형 TYPE_OPTIONS만 — #43 4부 · docs/TUNING.md 12절) · "botcompare"(봇 vs 시뮬 — #44 3부 · TUNING 14절)
-- "retune"(#45 — 걷기 · 로비 넣은 모델에서 GOAL 가운데에 맞는 후보 값만 찾는다 · 커밋 값은 그대로 · TUNING 15절)
EconomyReport.MODE = "full"

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
export type Bundle = { label: string, set: { [string]: any }?, policy: Policy?, hpSegments: { any }?,
	-- 운동기구 개편 선택지 측정(지시서 #41 4부 — 측정만. GymConfig · 게임 코드는 바꾸지 않는다 — 묶음 동안 메모리에서만 갈아 끼운다)
	gymTiers: { any }?, -- GymConfig.TIERS 자리에 잠깐 깔 표(로벅스 전용은 맨 끝)
	gymUnlock: ((any) -> number)?, -- 열린 기구 수 고르는 식(nil이면 게임과 같은 GymConfig.getUnlockedCount(환생 수))
	gymTrainSec: number?, -- MODEL.GYM_TRAIN_SEC(막힌 런 뒤 기구에서 클릭하는 초 — 0 = 기구 안 씀)
	ownsVoid: boolean?, -- MODEL.OWNS_VOID_ZONE(공허 구매자 비교 줄)
	-- 플레이어 유형(지시서 #43 4부 — 측정만. Config는 그대로 · 결정 모델 값만 묶음 동안 바꾼다): SuccessRateReport.MODEL 키 → 값
	model: { [string]: any }?,
}

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
EconomyReport.NONE = table.freeze({})

-- 표준 플레이어의 조합(지시서 #31 — Claude 해석). 가진 광석으로 닿는 가장 높은 칸 s를 고르고, 그 칸을 광석 2s + 1 이하만으로 채울 수 있으면
-- 그렇게 한다(높은 광석은 더 높은 칸에 아껴 둔다). 못 채우면 EconomyV2Logic.bestCombo 그대로.
-- 이유: 5초 제작이면 제작이 공급보다 빨라 bestCombo만으로는 20층 이상 광석이 3칸 제작에 섞여 녹는다(4칸이 안 생긴다 — 3차 측정 첫 실행).
function EconomyReport.standardCombo(inv: { number }): ({ number }?, number)
	local combo, slots = EconomyV2Logic.bestCombo(inv)
	if combo == nil then
		return nil, 0
	end
	-- #33: 점수 표 — "광석 2s + 1 이하"를 점수로 본다(점수가 2s + 1 이하인 가장 높은 광석까지)
	local cap = 0
	for k = 1, Config.ORE_COUNT do
		if Config.ORE_POINTS[k] <= 2 * slots + 1 then
			cap = k
		end
	end
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
		;(Config :: any)[k] = if v == EconomyReport.NONE then nil else v
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
	-- 운동기구 선택지(#41): 표 · 훈련 시간 · 공허 구매자 — 끝나면 되돌린다
	local savedTiers = table.clone(GymConfig.TIERS)
	local savedTrain, savedVoid = MODEL.GYM_TRAIN_SEC, MODEL.OWNS_VOID_ZONE
	if b.gymTiers ~= nil then
		table.clear(GymConfig.TIERS)
		for _, t in ipairs(b.gymTiers :: { any }) do
			table.insert(GymConfig.TIERS, t)
		end
	end
	if b.gymTrainSec ~= nil then
		MODEL.GYM_TRAIN_SEC = b.gymTrainSec
	end
	if b.ownsVoid ~= nil then
		MODEL.OWNS_VOID_ZONE = b.ownsVoid
	end
	-- 원래 값이 nil인 키(WALK_ACROSS_STUDS 등)도 되돌리도록 키 목록을 따로 둔다(표에 nil을 넣으면 사라진다 — #31 Config와 같은 함정)
	local savedModel: { [string]: any } = {}
	local modelKeys: { string } = {}
	for k, v in pairs(b.model or {}) do
		savedModel[k] = MODEL[k]
		table.insert(modelKeys, k)
		MODEL[k] = v
	end
	local savedSRR = {
		train = SRR.trainAtGym,
		econ = SRR.ECON,
		click = SRR.clickMultiplier,
		damage = SRR.damageMultiplier,
		gym = SRR.gymUnlockedCount,
		gymMult = SRR.gymMultiplier,
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
	table.clear(GymConfig.TIERS)
	for _, t in ipairs(savedTiers) do
		table.insert(GymConfig.TIERS, t)
	end
	MODEL.GYM_TRAIN_SEC, MODEL.OWNS_VOID_ZONE = savedTrain, savedVoid
	for _, k in ipairs(modelKeys) do
		MODEL[k] = savedModel[k]
	end
	SRR.trainAtGym = savedSRR.train
	world.hpGrowthSegments = savedHp
	world.bloxGrowthSegments = savedBloxSeg
	SRR.bloxMultiplier = savedSRR.blox
	SRR.ECON = savedSRR.econ
	SRR.clickMultiplier = savedSRR.click
	SRR.damageMultiplier = savedSRR.damage
	SRR.gymUnlockedCount = savedSRR.gym
	SRR.gymMultiplier = savedSRR.gymMult
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
		local craftRandom = RollService.seededRandom(EconomyReport.CRAFT_SEED)
		local petCoinRandom = RollService.seededRandom(EconomyReport.PET_COIN_SEED)
		local dropRandom = RollService.seededRandom(EconomyReport.DROP_SEED)
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
					maxedAt = {}, switches = {}, lastEquipped = Config.START_PICKAXE,
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
				local combo, slots = EconomyReport.standardCombo(s.inv)
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
					if craftSec <= EconomyReport.GOAL.horizonMin * 60 then
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
					local combo = EconomyReport.standardCombo(s.inv)
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
						if o.enh >= Config.ENHANCE_MAX and s.maxedAt[s.picks.equipped] == nil then
							s.maxedAt[s.picks.equipped] = p.elapsedSec
						end
					end
				end
			end
			s.picks.equipped = EconomyV2Logic.bestOwned(s.picks)
			-- #33 강화 목표: 장착이 바뀔 때 나가는 곡괭이의 강화 단계 · +10에 닿고 놀던 시간(분)
			if s.picks.equipped ~= s.lastEquipped then
				local old = s.picks.owned[s.lastEquipped]
				local maxed = s.maxedAt[s.lastEquipped]
				table.insert(s.switches, { enh = if old ~= nil then old.enh else 0, idle = if maxed ~= nil then (p.elapsedSec - maxed) / 60 else 0 })
				s.lastEquipped = s.picks.equipped
			end
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
			-- 자동 진행(유료)은 서버가 다음 층 입구 · 스폰으로 옮긴다 — 진행 벽 · 수령 발판까지 걷지 않는다(#45)
			teleports = auto,
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
				if EconomyReport._snapHook ~= nil then
					-- 테스트 프리셋 뽑기(#38 PresetExport): 런 시작마다 그 플레이어 상태를 넘긴다(바꾸지 않는다)
					EconomyReport._snapHook(p, s, forgeOpen(s))
				end
				if s.enh60 == nil and p.elapsedSec >= 3600 then
					s.enh60 = s.picks.owned[s.picks.equipped].enh
				end
				if s.enh120 == nil and p.elapsedSec >= 7200 then
					s.enh120 = s.picks.owned[s.picks.equipped].enh
				end
				if s.star180 == nil and p.elapsedSec >= EconomyReport.GOAL.horizonMin * 60 then
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
					sec = EconomyReport.pickDistance(stage, "last", Config.PICKUP_RADIUS) / LevelConfig.getMaxSpeed(p.strength)
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
				-- 3시간 시점 별 분포: 런 시작에서 못 잡고 끝나는 플레이어(마지막 런이 3시간을 넘김)도 여기서 잡는다
				if s.star180 == nil and p.elapsedSec >= EconomyReport.GOAL.horizonMin * 60 then
					local hist = { [0] = 0, 0, 0, 0, 0, 0 }
					for _, o in pairs(s.picks.owned) do
						hist[o.stars] += 1
					end
					s.star180 = { hist = hist, owned = ownedCount(s) }
				end
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
			return GymConfig.getUnlockedCount(p.rebirths)
		end
		SRR.gymMultiplier = GymConfig.getMultiplier -- 배수도 게임과 같은 표(#42 — 기본은 옛 모델 표)
		if b.gymUnlock ~= nil then
			SRR.gymUnlockedCount = b.gymUnlock
		end
		-- 운동기구 몫 관측(#41): 기구에서 보낸 시간 · 한 번(막힌 런 뒤)에 힘이 몇 % 늘었나. 측정만 — 결과는 바꾸지 않는다
		local gymStats = { sec = 0, gains = {} :: { number }, uses = 0 }
		EconomyReport._gymStats = gymStats
		local origTrain = SRR.trainAtGym -- withBundle이 이미 저장해 두고 끝나면 되돌린다
		SRR.trainAtGym = function(p: any, sec: number): number
			p._gymBest = math.max(p._gymBest or 0, p.bestThisLife or 0)
			local before = log10Big(p.strength)
			local index = origTrain(p, sec)
			if index > 0 then
				gymStats.sec += sec
				gymStats.uses += 1
				table.insert(gymStats.gains, (10 ^ (log10Big(p.strength) - before) - 1) * 100)
			end
			return index
		end
		SRR.S5_TARGETS = { "punchSpeed", "bloxGain", "petSlots" }
		MODEL.WARP_POLICY = pol.warp or "none"

		local catch = {}
		for i = 1, #Config.PICKAXES - 1 do
			catch[i] = EconomyV2Logic.catchUpLevel(Config.PICKAXES[i].id, Config.PICKAXES[i + 1].id) or 99 -- 99 = +10까지 못 따라잡음
		end
		local vis = {}
		for _, stage in ipairs({ 1, 6, 11, 14, 17, 20, 23, 25 }) do
			local d = EconomyV2Logic.dropsPerBlock(EconomyV2Logic.oreOf(stage))
			table.insert(vis, string.format("%d층 %.2f(%.0f개)", stage, d, d * StageConfig.getBlockCount(stage)))
		end
		out = EconomyReport.collect(players, maxStage, st, function(p: any)
			-- #32: 15종을 다 모아도 3시간 시점까지 돈다(별 분포를 3시간 시점 전원으로 잰다 — #31 해석 4줄 다시 잼)
			return ownedCount(st(p)) >= #Config.PICKAXES and p.elapsedSec >= EconomyReport.GOAL.horizonMin * 60
		end)
		out.catch = catch
		out.visible = table.concat(vis, " · ")
	end)
	return out
end

-- 테스트 프리셋 뽑기(#38): 지금 TEMP(V4 — set = {}) 표준 플레이어를 players명 돌리며 런 시작마다 hook(p, s, forgeOpen)을 부른다
EconomyReport._snapHook = nil :: ((any, any, boolean) -> ())?
function EconomyReport.snapshots(players: number, hook: (any, any, boolean) -> ())
	EconomyReport._snapHook = hook
	local ok, err = pcall(measureV2, { label = "V4", set = {} }, players)
	EconomyReport._snapHook = nil
	if not ok then
		error(err)
	end
end

-- 플레이어 players명을 돌려 층 첫 도달 · 지표를 모은다. st = nil이면 지금 경제(재현).
function EconomyReport.collect(players: number, maxStage: number, st: ((any) -> any)?, untilFn: ((any) -> boolean)?): any
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
						cur.at25 = { n = s.n, blox = log10Big(p.blox), coins = log10Big(s.coins), rebirthAt = table.clone(s.rebirthAt), pet = SuccessRateReport.petMult(p),
							owned = #s.kthAt, pick = EconomyV2Logic.equippedMult(s.picks), enh = s.picks.owned[s.picks.equipped].enh }
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
				enh = s.picks.owned[s.picks.equipped].enh, enh60 = s.enh60, enh120 = s.enh120, switches = s.switches,
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
EconomyReport.V1 = nil :: any
function EconomyReport.reproduceV1(players: number): any
	local r = EconomyReport.collect(players, lastStage(), nil, nil)
	local m = r.metrics
	local seg = m.segments
	local early = {}
	for stage = 1, 9 do
		table.insert(early, string.format("%d:%s", stage, fmt(firstMin(r, stage), "%.2f")))
	end
	print(string.format("[ECON2] v1 재현(ECON 없음 · %d명) · 25층 %d명 · 중앙 %s분(#29 B4 38.7) · 구간 %.1f / %.1f / %.1f · 환생(이벤트) 평균 %.1f",
		players, m.reached, fmt(m.medianFinalMin), (seg[1].rate or 0) * 100, (seg[2].rate or 0) * 100, (seg[3].rate or 0) * 100, m.meanRebirths))
	print("[ECON2]   v1 층 첫 도달(분) " .. table.concat(early, " ") .. string.format(" · 17:%s · 25:%s", fmt(firstMin(r, 17)), fmt(firstMin(r, 25))))
	EconomyReport.V1 = r
	return r
end

-- 묶음 측정 결과 요약(표가 아니라 줄)
function EconomyReport.summarize(r: any): any
	local G = EconomyReport.GOAL
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
	local v1 = EconomyReport.V1
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
	local function kth(k: number): number?
		return endMed(r, function(e)
			return if e.kthAt[k] ~= nil then e.kthAt[k] / 60 else nil
		end)
	end
	local gaps = {}
	for _, row in ipairs(r.rows) do
		if row.first[24] ~= nil and row.first[25] ~= nil then
			table.insert(gaps, (row.first[25] - row.first[24]) / 60)
		end
	end
	local k5, k10, k14, gap = kth(5), kth(10), kth(14), median(gaps)
	pass.k5 = k5 ~= nil and k5 <= G.k5
	pass.k10 = k10 ~= nil and k10 >= G.k10[1] and k10 <= G.k10[2]
	pass.k14 = k14 ~= nil and k14 >= G.k14[1] and k14 <= G.k14[2]
	pass.gap = gap ~= nil and gap <= G.gap2425
	local outs, idles = {}, {}
	for _, row in ipairs(r.rows) do
		if row.end_ ~= nil then
			for _, sw in ipairs(row.end_.switches or {}) do
				table.insert(outs, sw.enh)
				table.insert(idles, sw.idle)
			end
		end
	end
	local enhOut, enhIdle = median(outs), median(idles)
	local catchMax = 0
	for _, c in ipairs(r.catch or {}) do
		catchMax = math.max(catchMax, c)
	end
	pass.enh = catchMax == 0 and enhOut ~= nil and enhOut >= G.enhOut and enhIdle ~= nil and enhIdle <= G.enhIdle
	return { t25 = t25, k15 = k15, got15 = got15, n25 = n25, legendMean = legendMean, worstEarly = worstEarly, pass = pass, k5 = k5, k10 = k10,
		k14 = k14, gap = gap, enhOut = enhOut, enhIdle = enhIdle, catchMax = catchMax, nSwitch = #outs }
end

function EconomyReport.report(b: Bundle, players: number): any
	local r = measureV2(b, players)
	EconomyReport._lastResult = r -- 유형 비교(#43 4부)가 같은 결과로 한 줄 더 뽑는다
	local sm = EconomyReport.summarize(r)
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
		local v1 = EconomyReport.V1
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
	for k = 1, #Config.PICKAXES do
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
print(string.format("[ECON2]   획득 퍼짐(#32): 5종 %s분[%s] · 10종 %s분[%s] · 14종 %s분[%s] · 24→25 체류 %s분[%s] · 강화(장착) 25층 %s · 1시간 %s · 2시간 %s · 끝 %s",
	fmt(sm.k5), mark(p.k5), fmt(sm.k10), mark(p.k10), fmt(sm.k14), mark(p.k14), fmt(sm.gap), mark(p.gap), fmt(at25Med(r, function(a)
		return a.enh
	end), "%.0f"), fmt(endMed(r, function(e)
		return e.enh60
	end), "%.0f"), fmt(endMed(r, function(e)
		return e.enh120
	end), "%.0f"), fmt(endMed(r, function(e)
		return e.enh
	end), "%.0f")))
-- 지시서 #33: 강화 목표 · 보이는 양
local catchTxt = {}
for i, c in ipairs(r.catch or {}) do
	table.insert(catchTxt, string.format("%d→%d:%s", i, i + 1, if c < 99 then tostring(c) else ">10"))
end
print(string.format("[ECON2]   강화(#33): 따라잡는 강 %s · 최대 %s[%s] · 장착 바뀔 때 나가는 곡괭이 강화 중앙 %s · +10 뒤 논 시간 중앙 %s분 · 바뀐 횟수 %d",
	table.concat(catchTxt, " "), fmt(sm.catchMax, "%.0f"), mark(p.enh), fmt(sm.enhOut, "%.0f"), fmt(sm.enhIdle, "%.1f"), sm.nSwitch))
print("[ECON2]   보이는 양(#33 — 층마다 블록당 광석 · 층 광석 합) " .. (r.visible or "-"))
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

-- 손잡이 하나를 setter(set, 값)로 넣으며 log 공간 이분 탐색한다(#32 — 광석별 드롭 표처럼 Config 이름 하나가 아닌 손잡이)
function EconomyReport.tuneWith(b: any, setter: ({ [string]: any }, number) -> (), range: { number }, metric: string, target: number, faster: boolean): number
	local lo, hi = math.log(range[1]), math.log(range[2])
	for _ = 1, EconomyReport.TUNE_STEPS do
		local mid = (lo + hi) / 2
		local set = table.clone(b.set or {})
		setter(set, math.exp(mid))
		local r = measureV2({ label = b.label, set = set, policy = b.policy }, EconomyReport.TUNE_PLAYERS)
		local sm = EconomyReport.summarize(r)
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

-- 손잡이 하나(key — Config 이름)를 log 공간 이분 탐색해 지표(metric: 요약 → 분)를 target에 맞춘다. 키우면 빨라지는 손잡이면 faster = true.
function EconomyReport.tune(b: Bundle, key: string, range: { number }, metric: string, target: number, faster: boolean): number
	local lo, hi = math.log(range[1]), math.log(range[2])
	for _ = 1, EconomyReport.TUNE_STEPS do
		local mid = (lo + hi) / 2
		local set = table.clone(b.set or {})
		set[key] = math.exp(mid)
		local r = measureV2({ label = b.label, set = set, policy = b.policy }, EconomyReport.TUNE_PLAYERS)
		local sm = EconomyReport.summarize(r)
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
local NONE = EconomyReport.NONE
local C_BASE = { ORE_PER_BLOCK = 1, REBIRTH_COST_BASE = BigNum.new(1, 3), REBIRTH_COST_GROWTH = 4, REBIRTH_MULT_BASE = 1.25, PICK_RATIO = 1.255,
	UPPER_ORE_DROP_MULT = 1, FORGE_UNLOCK_REBIRTHS = NONE, FORGE_UNLOCK_STAGE = NONE }
local function withSet(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in pairs(extra) do
		t[k] = v
	end
	return t
end
EconomyReport.C_BASE = C_BASE

-- #32 4차 결과(docs/TUNING.md 9절): 추천 S2 — #33 결정으로 모델이 바뀌어 다시 잰다(점수 표 · 모든 광석 드롭 0.5 이상 · 등급별 강화).
-- #33 5차 측정: 점수 표(Config.ORE_POINTS) · 광석 1 ~ 7 드롭 넉넉하게(1 · 0.8) · 광석 8 x · 9 ~ 10 y(둘 다 ORE_DROP_MIN 이상 — N13) ·
-- 강화 = 등급 × 단계 비용(ENHANCE_COST_BY_RARITY) · 효과 ENHANCE_STEP(곡괭이 비율보다 작게 — 새 곡괭이 +0 ≥ 이전 +10).
-- 손잡이: x(신화 토큰 — 14종째) · y(전설 토큰 — 15종째) · PICK_RATIO(25층). 드롭이 바닥(0.5)에 닿으면 가방(T2)으로 늦춘다
local function oreDrops(x: number, y: number): { number }
	local m = Config.ORE_DROP_MIN
	return { 1, 1, 1, 1, 1, 0.8, 0.8, math.max(m, x), math.max(m, y), math.max(m, y) }
end
EconomyReport.oreDrops = oreDrops
local ENH_COST = { common = 1, rare = 3, epic = 9, mythic = 27, legendary = 81 }
local T_BASE = withSet(C_BASE, { FORGE_UNLOCK_STAGE = 8, PICK_RATIO = 1.23, ENHANCE_STEP = 0.02, ENHANCE_COST_BY_RARITY = ENH_COST,
	ENHANCE_STEP_BY_RARITY = NONE, ORE_DROP_BY_ORE = oreDrops(0.6, 0.5) })
-- 1 ~ 3칸 신화 확률 낮춤(5차 탐색: 2칸 제작이 수백 번이라 2칸 신화 1.5%만으로 신화가 확률로 10개 넘게 나와 14종째가 90분대)
local ODDS33 = table.clone(Config.RARITY_ODDS)
ODDS33[1] = { common = 70, rare = 26, epic = 3.9, mythic = 0.1, legendary = 0 }
ODDS33[2] = { common = 45, rare = 40, epic = 14.7, mythic = 0.3, legendary = 0 }
ODDS33[3] = { common = 30, rare = 40, epic = 28.5, mythic = 1.5, legendary = 0 }
EconomyReport.ODDS33 = ODDS33
EconomyReport.BUNDLES = {
	{ label = "T1 점수 표 · 드롭 0.5 이상 · 강화 등급 비용 · 1~3칸 신화 낮춤", set = withSet(T_BASE, { RARITY_ODDS = ODDS33 }), x0 = 0.6, y0 = 0.5 },
	{ label = "T2 T1 + 작은 가방(12 + 2/등급)", set = withSet(T_BASE, { RARITY_ODDS = ODDS33, BAG_BASE = 12, BAG_PER_RANK = 2 }), x0 = 0.6, y0 = 0.5 },
} :: { any }

EconomyReport.EXPLORE = {
	-- #33 5차: T1 맞춘 값을 깔끔한 값으로(0.5 · 2.2) 옮길 때 곡괭이 배수만 조금 낮춰 15종을 기준 안 가운데로(반올림 민감 — 같은 값도 ±5분)
	{ label = "V0 TEMP(커밋 값 = V4)", set = {} },
	{ label = "V1 드롭 0.5 · 강화 2.2 · PICK 1.25", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 2.2, PICK_RATIO = 1.25 } },
	{ label = "V2 드롭 0.5 · 강화 2.2 · PICK 1.24", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 2.2, PICK_RATIO = 1.24 } },
	{ label = "V3 V1 + 9~10 드롭 0.5 · 강화 3", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 3, PICK_RATIO = 1.25 } },
	{ label = "V4 드롭 0.5 · 강화 2.2 · PICK 1.245", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 2.2, PICK_RATIO = 1.245 } },
	{ label = "V4 · 1회 제작 0초", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 2.2, PICK_RATIO = 1.245 }, policy = { craftSec = 0 } },
	{ label = "V4 · 1회 제작 10초", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 2.2, PICK_RATIO = 1.245 }, policy = { craftSec = 10 } },
	{ label = "V4 · 트리플", set = { ORE_DROP_BY_ORE = oreDrops(0.5, 0.5), ENHANCE_COST_BASE = 2.2, PICK_RATIO = 1.245 }, policy = { tripleCraft = true } },
} :: { any }

-- 24 → 25층 막힘 줄이는 방법(run 끝에서 측정). hpSegments가 있는 줄은 ⚠️ HP 곡선 변형 — 희준 결정 영역, 기본안 아님
EconomyReport.CLIFF = {
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
		elseif v == EconomyReport.NONE then
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

-- ===== 운동기구 개편 선택지 (지시서 #41 4부 — docs/GYM_OPTIONS.md · 결정은 희준) ==========================================
-- 측정만 한다. 표는 묶음 동안만 GymConfig.TIERS 자리에 깔고 되돌린다(게임 값 · 상품은 그대로).
local VOID = { unlockRebirths = nil, multiplier = 100, gamepassKey = "voidTrainingZone" }
local function rebirthTiers(rows: { { number } }): { any }
	local out = {}
	for _, r in ipairs(rows) do
		table.insert(out, { unlockRebirths = BigNum.fromNumber(r[1]), multiplier = r[2] })
	end
	table.insert(out, VOID)
	return out
end
-- 층 도달 해금: 이 플레이어가 지금까지 닿은 가장 높은 층(생애를 넘어 — 환생해도 안 잠긴다)으로 연다
local function byStage(stages: { number }): (any) -> number
	return function(p: any): number
		local best = math.max(p._gymBest or 0, p.bestThisLife or 0)
		local n = 0
		for i, need in ipairs(stages) do
			if best >= need then
				n = i
			end
		end
		return n
	end
end
local NOW8 = { { 1, 1.2 }, { 2, 1.5 }, { 3, 2 }, { 5, 2.5 }, { 7, 3 }, { 9, 4 }, { 12, 5 }, { 15, 8 } }
-- ===== 플레이어 유형(지시서 #43 4부 — 측정만 · Config는 그대로. 2월 밸런스 참고 — docs/TUNING.md 12절) ======================
-- 무과금 행동 유형은 결정 모델(SuccessRateReport.MODEL) 값만 바꾼다. 유료는 이미 있는 정책(policy) 칸 · 기구 해금 식으로 흉내 낸다.
-- "매일 30분"은 따로 돌리지 않는다 — 접속 중에만 도는 것(자동 제작 · 런)뿐이라 표준 줄의 노는 시간과 같고, 날짜만 나눈다(일일 보상은 시뮬레이터에 없다)
local function allGyms(_p: any): number
	return GymConfig.getRebirthTierCount()
end
EconomyReport.TYPE_OPTIONS = {
	{ label = "표준(클릭 6~10 · 무과금)", set = {} },
	{ label = "클릭 빠름(9~10 — 수동 상한)", set = {}, model = { CLICK_RATE_MIN = 9, CLICK_RATE_MAX = 10 } },
	{ label = "클릭 느림(2~4)", set = {}, model = { CLICK_RATE_MIN = 2, CLICK_RATE_MAX = 4 } },
	{ label = "잠수 많음(노는 시간 50% 가만히 · 자동 제작은 돈다)", set = {}, model = { IDLE_SHARE = 0.5 } },
	{ label = "유료 자동 진행", set = {}, policy = { pickup = "auto" } },
	{ label = "유료 2배 데미지", set = {}, policy = { damagePass = 2 } },
	{ label = "유료 2배 블럭스", set = {}, policy = { bloxPass = 2 } },
	{ label = "유료 큰 가방", set = {}, policy = { bagPass = Config.BIG_BAG_MULT } },
	{ label = "유료 즉시 제작(연출 생략)", set = {}, policy = { craftSkip = true } },
	{ label = "유료 선해금 기구(환생 기구 전부)", set = {}, gymUnlock = allGyms },
	{ label = "유료 전부(위 6개)", set = {}, gymUnlock = allGyms,
		policy = { pickup = "auto", damagePass = 2, bloxPass = 2, bagPass = Config.BIG_BAG_MULT, craftSkip = true } },
}
-- 유형 한 줄: 25층 · 15종 · 25층까지 환생 · 막히는 층(첫 도달 간격이 가장 긴 두 곳) · 25층 때 남은 블럭스 · 코인(중앙 — 10의 지수)
function EconomyReport.typeLine(label: string, sm: any): string
	local r = EconomyReport._lastResult
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
	for i = 1, math.min(2, #gaps) do
		table.insert(cliff, string.format("%d→%d %.0f분", gaps[i].stage, gaps[i].stage + 1, gaps[i].d))
	end
	local blox = at25Med(r, function(a)
		return a.blox
	end)
	local coins = at25Med(r, function(a)
		return a.coins
	end)
	return string.format("[ECON2] 유형 %s | 25층 %s분 · 15종 %s분 · 환생 %s회 · 막힘 %s · 25층 때 블럭스 10^%s · 코인 10^%s", label, fmt(sm.t25),
		fmt(sm.k15), fmt(sm.n25, "%.0f"), table.concat(cliff, " · "), fmt(blox, "%.1f"), fmt(coins, "%.1f"))
end

EconomyReport.GYM_OPTIONS = {
	-- #42: A2 채택 — "지금"이 A2다(게임 GymConfig). 예전 8기구(G0)는 비교 줄로 남긴다. 지금 = 아래 A2 줄과 같은 값이어야 한다
	{ label = "지금 A2(GymConfig · 12기구 · 환생 1~15 · ×1.2~×8)", set = {} },
	{ label = "지금 · 기구 안 씀(비교)", set = {}, gymTrainSec = 0 },
	{ label = "지금 · 공허 구매자(비교)", set = {}, ownsVoid = true },
	{ label = "G0 예전 8기구(환생 1~15 · ×1.2~×8 — #41 측정 기준)", set = {}, gymTiers = rebirthTiers(NOW8) },
	{ label = "A 12기구(환생 1~30 · ×1.2~×20)", set = {}, gymTiers = rebirthTiers({ { 1, 1.2 }, { 2, 1.5 }, { 3, 2 }, { 5, 2.5 }, { 7, 3 },
		{ 9, 4 }, { 12, 5 }, { 15, 8 }, { 18, 10 }, { 21, 12 }, { 25, 15 }, { 30, 20 } }) },
	-- A는 25층까지 환생 15회 안팎이라 환생 18 ~ 30 기구는 3시간 안에 거의 안 열린다(측정값이 G0와 같다) — 같은 범위에 촘촘히 늘린 A2를 같이 잰다
	{ label = "A2 12기구(환생 1~15 촘촘히 · ×1.2~×8)", set = {}, gymTiers = rebirthTiers({ { 1, 1.2 }, { 2, 1.4 }, { 3, 1.6 }, { 4, 2 }, { 5, 2.3 },
		{ 6, 2.6 }, { 7, 3 }, { 8, 3.5 }, { 9, 4 }, { 11, 5 }, { 13, 6 }, { 15, 8 } }) },
	{ label = "B 8기구 층 도달(3~22층 · ×1.2~×8)", set = {}, gymTiers = rebirthTiers(NOW8), gymUnlock = byStage({ 3, 5, 8, 10, 13, 16, 19, 22 }) },
	{ label = "C 등급 4기구(환생 1 · 4 · 8 · 14 · ×1.5 · ×3 · ×6 · ×12)", set = {}, gymTiers = rebirthTiers({ { 1, 1.5 }, { 4, 3 }, { 8, 6 }, { 14, 12 } }) },
	{ label = "C · 공허 구매자(비교)", set = {}, gymTiers = rebirthTiers({ { 1, 1.5 }, { 4, 3 }, { 8, 6 }, { 14, 12 } }), ownsVoid = true },
} :: { any }

function EconomyReport.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	task.wait(5) -- 시작 직후 테스트들이 MODEL · Config를 잠깐 흔드는 동안 기다린다
	local E = EconomyReport
	local t0 = os.clock()
	print(string.format("[ECON2] ===== 새 경제 5차 측정 (지시서 #33 — 점수 표 · 드롭 0.5 이상 · 등급별 강화 · 추천까지만) · 모드 %s =====", E.MODE))
	if E.MODE == "botcompare" then -- 봇 vs 시뮬(#44 3부): 표준 플레이어(fresh 시작)의 층 첫 도달 · 8분 · 10분 때 상태 · 시간 나눔(중앙)
		local sm = E.report({ label = "표준(봇 비교 — 걷기 · 로비 넣은 지금 모델)", set = {} }, E.PLAYERS)
		local r = E._lastResult
		local reach = {}
		for stage = 1, 10 do
			table.insert(reach, string.format("%d:%s", stage, fmt(firstMin(r, stage), "%.1f")))
		end
		print("[ECON2] 봇비교 층 첫 도달(분 · 중앙) " .. table.concat(reach, " "))
		local at: { [number]: { any } } = { [480] = {}, [600] = {}, [3600] = {}, [7572] = {} }
		local seen: { [any]: { [number]: boolean } } = {}
		E.snapshots(E.PLAYERS, function(pl: any, st: any, _open: boolean)
			local mark = seen[pl] or {}
			seen[pl] = mark
			for T, list in pairs(at) do
				if not mark[T] and pl.elapsedSec >= T then
					mark[T] = true
					table.insert(list, { best = math.max(st.maxEver or 0, pl.bestThisLife or 0), n = st.n, runs = pl.runCount,
						split = table.clone(pl.split or {}), t = pl.elapsedSec, pet = SuccessRateReport.petMult(pl), title = pl.titleIndex or 0,
						punch = (pl.upgrades or {}).punchSpeed or 0, coins = log10Big(st.coins) })
				end
			end
		end)
		for _, T in ipairs({ 480, 600, 3600, 7572 }) do
			local list = at[T]
			local function med(fn: (any) -> number): number?
				local xs = {}
				for _, x in ipairs(list) do
					table.insert(xs, fn(x))
				end
				return median(xs)
			end
			local parts = {}
			for _, k in ipairs({ "gate", "attack", "attack_fail", "pickup", "walk_advance", "walk_cashout", "lobby", "gym", "idle", "clears" }) do
				table.insert(parts, string.format("%s %s", k, fmt(med(function(x)
					return x.split[k] or 0
				end), "%.0f")))
			end
			print(string.format("[ECON2] 봇비교 %d분 배수: 펫 ×%s · 칭호 번호 %s · 펀치 속도 업그레이드 %s · 코인 10^%s", T // 60,
				fmt(med(function(x)
					return x.pet
				end), "%.2f"), fmt(med(function(x)
					return x.title
				end), "%.0f"), fmt(med(function(x)
					return x.punch
				end), "%.0f"), fmt(med(function(x)
					return x.coins
				end), "%.1f")))
			print(string.format("[ECON2] 봇비교 %d분(다음 런 시작 %s초) · 최고 층 %s · 환생 %s · 런 %s · 시간 나눔(초) %s · %d명", T // 60,
				fmt(med(function(x)
					return x.t
				end), "%.0f"), fmt(med(function(x)
					return x.best
				end), "%.0f"), fmt(med(function(x)
					return x.n
				end), "%.0f"), fmt(med(function(x)
					return x.runs
				end), "%.0f"), table.concat(parts, " · "), #list))
		end
		-- 옛 모델과 비교(#45): 걷기 · 로비 없는 옛 표준(#44까지)으로 같은 seed를 돌리면
		local old = E.report({ label = "옛 모델(걷기 · 로비 없음 — #44까지)", set = {}, model = { WALK_ACROSS_STUDS = 0, LOBBY_SEC_PER_RUN = 0 } }, E.PLAYERS)
		local walkOnly = E.report({ label = "걷기만(로비 0)", set = {}, model = { LOBBY_SEC_PER_RUN = 0 } }, E.PLAYERS)
		local lobbyHi = E.report({ label = "로비 8.5초/런(봇 실측 위 끝)", set = {}, model = { LOBBY_SEC_PER_RUN = 8.5 } }, E.PLAYERS)
		print(string.format("[ECON2] 봇비교 옛 모델: 25층 %s분 · 15종 %s분 · 환생 %s회 | 걷기만 %s · %s | 로비 8.5초 %s · %s | 지금 표준 %s · %s · 환생 %s",
			fmt(old.t25), fmt(old.k15), fmt(old.n25, "%.0f"), fmt(walkOnly.t25), fmt(walkOnly.k15), fmt(lobbyHi.t25), fmt(lobbyHi.k15),
			fmt(sm.t25), fmt(sm.k15), fmt(sm.n25, "%.0f")))
		print(string.format("[ECON2] 봇비교 25층 %s분 · 15종 %s분 · ===== 끝 · %.0f초 =====", fmt(sm.t25), fmt(sm.k15), os.clock() - t0))
		return
	end
	if E.MODE == "retune" then
		-- #45: 지금 커밋 값에서 시작해 PICK_RATIO(25층) · 광석 8 드롭(14종) · 광석 9 ~ 10 드롭(15종) · PICK_RATIO(다시)를 GOAL 가운데로.
		-- 찾기만 한다(커밋 값을 바꾸지 않는다 — 목표 시간은 사람 결정). 순서는 full 모드와 같다(강화 비용 바탕은 빼고)
		local G = E.GOAL
		local t25Target, k15Target = (G.t25[1] + G.t25[2]) / 2, (G.t15[1] + G.t15[2]) / 2
		local k14Target = (G.k14[1] + G.k14[2]) / 2
		local base = E.report({ label = "지금 값(걷기 · 로비 넣은 새 기준)", set = {} }, E.PLAYERS)
		local drops = Config.ORE_DROP_BY_ORE or {}
		local x, y = drops[8] or Config.ORE_DROP_MIN, drops[9] or Config.ORE_DROP_MIN
		local set: { [string]: any } = { PICK_RATIO = Config.PICK_RATIO }
		local function b(): any
			return { label = "다시 맞춤", set = set }
		end
		set.PICK_RATIO = E.tune(b(), "PICK_RATIO", { 1.1, 1.6 }, "t25", t25Target, true)
		print(string.format("[ECON2]   다시맞춤 1 PICK_RATIO %.4g · %.0f초", set.PICK_RATIO, os.clock() - t0))
		x = E.tuneWith(b(), function(st: { [string]: any }, v: number)
			st.ORE_DROP_BY_ORE = oreDrops(v, y)
		end, { Config.ORE_DROP_MIN, 3 }, "k14", k14Target, true)
		set.ORE_DROP_BY_ORE = oreDrops(x, y)
		print(string.format("[ECON2]   다시맞춤 2 광석 8 드롭 %.4g · %.0f초", math.max(Config.ORE_DROP_MIN, x), os.clock() - t0))
		y = E.tuneWith(b(), function(st: { [string]: any }, v: number)
			st.ORE_DROP_BY_ORE = oreDrops(x, v)
		end, { Config.ORE_DROP_MIN, 3 }, "k15", k15Target, true)
		set.ORE_DROP_BY_ORE = oreDrops(x, y)
		print(string.format("[ECON2]   다시맞춤 3 광석 9~10 드롭 %.4g · %.0f초", math.max(Config.ORE_DROP_MIN, y), os.clock() - t0))
		set.PICK_RATIO = E.tune(b(), "PICK_RATIO", { 1.1, 1.6 }, "t25", t25Target, true)
		local cand = E.report({ label = "후보(25층 · 14종 · 15종 GOAL 가운데)", set = set }, E.PLAYERS)
		local function passes(sm: any): string
			local bad = {}
			for _, k in ipairs({ "t25", "t15", "rebirths", "k5", "k10", "k14", "gap", "legend" }) do
				if sm.pass[k] ~= true then
					table.insert(bad, k)
				end
			end
			return if #bad == 0 then "기준 안" else "벗어남 " .. table.concat(bad, ",")
		end
		print(string.format("[ECON2] 다시맞춤 요약" .. string.char(10)
			.. "[ECON2] 지금 값 PICK_RATIO %.4g · 드롭 8 %.3g · 9~10 %.3g | 25층 %s · 14종 %s · 15종 %s · 환생 %s · 24→25 %s분 · %s" .. string.char(10)
			.. "[ECON2] 후보   PICK_RATIO %.4g · 드롭 8 %.3g · 9~10 %.3g | 25층 %s · 14종 %s · 15종 %s · 환생 %s · 24→25 %s분 · %s · %.0f초",
			Config.PICK_RATIO, drops[8] or Config.ORE_DROP_MIN, drops[9] or Config.ORE_DROP_MIN, fmt(base.t25), fmt(base.k14), fmt(base.k15),
			fmt(base.n25, "%.0f"), fmt(base.gap), passes(base),
			set.PICK_RATIO, math.max(Config.ORE_DROP_MIN, x), math.max(Config.ORE_DROP_MIN, y), fmt(cand.t25), fmt(cand.k14), fmt(cand.k15),
			fmt(cand.n25, "%.0f"), fmt(cand.gap), passes(cand), os.clock() - t0))
		print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
		return
	end
	if E.MODE == "types" then -- 플레이어 유형(#43 4부) — 재현 없이 유형만 · 끝에 요약 줄을 한 번 더 모아 찍는다
		local lines = {}
		local std: any = nil
		for _, b in ipairs(E.TYPE_OPTIONS) do
			local sm = E.report(b, E.PLAYERS)
			std = std or sm
			table.insert(lines, E.typeLine(b.label, sm))
			print(lines[#lines])
			print(string.format("[ECON2]   · %.0f초", os.clock() - t0))
		end
		if std ~= nil then
			table.insert(lines, string.format("[ECON2] 유형 매일 30분(표준 줄을 날짜로) | 25층 %s일 · 15종 %s일 — 일일 보상은 시뮬레이터에 없다(실제는 조금 빠르다)",
				fmt(if std.t25 ~= nil then std.t25 / 30 else nil, "%.1f"), fmt(if std.k15 ~= nil then std.k15 / 30 else nil, "%.1f")))
		end
		print("[ECON2] 유형 요약" .. string.char(10) .. table.concat(lines, string.char(10))) -- 한 줄로(로그 보관 상한에 앞줄이 밀려도 남는다)
		print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
		return
	end
	if E.MODE == "gym" then -- 운동기구 개편 선택지(#41 4부) — 재현 없이 선택지만
		for _, b in ipairs(E.GYM_OPTIONS) do
			E.report(b, E.PLAYERS)
			local g = E._gymStats
			if g ~= nil then
				print(string.format("[ECON2]   기구 몫 %s: 기구 시간 %.1f분/명 · %.1f회/명 · 1회 힘 증가 중앙 %s%%", b.label, g.sec / 60 / E.PLAYERS,
					g.uses / E.PLAYERS, fmt(median(g.gains), "%.1f")))
			end
			print(string.format("[ECON2]   · %.0f초", os.clock() - t0))
		end
		print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
		return
	end
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
		local x, y = b.x0, b.y0
		local function setX(st: { [string]: any }, v: number)
			st.ORE_DROP_BY_ORE = oreDrops(v, y)
		end
		local function setY(st: { [string]: any }, v: number)
			st.ORE_DROP_BY_ORE = oreDrops(x, v)
		end
		-- 0) #33 강화가 공백을 채우게: 장착이 바뀔 때 나가는 곡괭이 강화 중앙 ≈ 6(강화 비용 바탕 — 키우면 강화가 줄어든다)
		set.ENHANCE_COST_BASE = E.tune({ label = b.label, set = set, policy = b.policy }, "ENHANCE_COST_BASE", { 0.3, 30 }, "enhOut", 6, true)
		-- 1) 14종째 ≈ 140분: 광석 8 드롭(키우면 빨라진다 · 바닥 ORE_DROP_MIN)
		x = E.tuneWith({ label = b.label, set = set, policy = b.policy }, setX, { Config.ORE_DROP_MIN, 2 }, "k14", 140, true)
		set.ORE_DROP_BY_ORE = oreDrops(x, y)
		-- 2) 15종째 ≈ 180분: 광석 9 ~ 10 드롭
		y = E.tuneWith({ label = b.label, set = set, policy = b.policy }, setY, { Config.ORE_DROP_MIN, 2 }, "k15", 180, true)
		set.ORE_DROP_BY_ORE = oreDrops(x, y)
		-- 3) 25층 ≈ 2시간: 곡괭이 배수
		set.PICK_RATIO = E.tune({ label = b.label, set = set, policy = b.policy }, "PICK_RATIO", { 1.05, 1.6 }, "t25", 120, true)
		-- 4) 곡괭이가 바뀌면 14종이 조금 움직인다 — 광석 8을 한 번 더
		x = E.tuneWith({ label = b.label, set = set, policy = b.policy }, setX, { math.max(Config.ORE_DROP_MIN, x / 1.6), math.max(Config.ORE_DROP_MIN * 1.01, x * 1.6) }, "k14", 140, true)
		set.ORE_DROP_BY_ORE = oreDrops(x, y)
		local tb = { label = b.label, set = set, policy = b.policy }
		table.insert(tuned, tb)
		print(string.format("[ECON2] 묶음 %s 맞춘 값: 강화 비용 바탕 %.4g · 광석 8 드롭 %.4g · 9~10 드롭 %.4g · PICK_RATIO %.4g · %.0f초", b.label,
			set.ENHANCE_COST_BASE, math.max(Config.ORE_DROP_MIN, x), math.max(Config.ORE_DROP_MIN, y), set.PICK_RATIO, os.clock() - t0))
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
	print(string.format("[ECON2] 기준 %s 25층 %s · 15종 %s", ref.label, fmt(refSm.t25), fmt(refSm.k15)))
	print(string.format("[ECON2] ===== 끝 · %.0f초 =====", os.clock() - t0))
end

return EconomyReport

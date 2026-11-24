--!strict
-- 경제 재설계 후보 측정 (지시서 #29 단계 2). ⚠️ 측정 도구다 — 채택하지 않는다(D2: 고르는 것은 사람이다).
--
-- ⚠️ 개발 도구다. 게임 경로에 붙지 않는다. 프로필을 읽지도 쓰지도 않는다. 게임 코드 · Config 파일을 고치지 않는다 —
--    후보마다 SuccessRateReport의 고리(ECON)와 배수 함수 두 자리(clickMultiplier · damageMultiplier) · S5_TARGETS ·
--    UpgradeConfig.Upgrades.bagCap(가방 업그레이드 — 펀치 데미지 자리)을 메모리에서 잠깐 갈아끼우고 끝나면 되돌린다
--    (HpCandidateReport · withUpgradeOverride와 같은 패턴). 켜는 곳: SuccessRateReport.SIM.ECONOMY_SWEEP_ONLY + Bootstrap SUCCESS_RATE_REPORT_ENABLED.
--
-- ===== 후보 모델 (지시서 #29 방향 — 게임에는 아직 없다) ===================================================
--
--   환생      1번에 +1(x2 Rebirths 패스 = +2 — 무과금 측정은 끔). 비용 = 1000 × g^n(n = 지금 환생 수). 조건 = 보유 ≥ 비용.
--             환생하면 보유 블럭스는 0(지금과 같다) — 비용을 먼저 떼고 나머지(버려질 양)로 A4 · E11 · S5'를 한다.
--             힘 배수의 환생 항 = (1 + a·n) 또는 b^n. 나머지 항(칭호 · 아우라 · 펫)은 StrengthMultiplier.compute 그대로.
--   곡괭이    펀치 데미지 업그레이드 자리. 등급 t 배수 = N^(t−1) × 강화(더하기 1 + v·k 또는 곱하기 v^k). 환생해도 남는다.
--             1펀치 배수 = AttackService.combineDamageMultiplier(곡괭이 배수 × 아우라 m) — 게임과 같은 결합 함수.
--   광석      층 구간(HP 구간 1~8 · 9~16 · 17~25)마다 한 종류(A · B · C). 블록 하나가 부서지면 그 구간 광석 ORE_PER_BLOCK개 —
--             층마다 종류 · 양이 고정(블록 수 StageConfig.getBlockCount).
--   표준 제작  런 직전(스폰)에: 다음 등급을 만들 수 있으면 만든다. 못 만들면 지금 등급 강화 — 다만 다음 등급이 같은 광석이면
--             아껴 둔다(다음 등급이 다른 광석일 때만 강화). Claude 해석이다(사람 결정 모델 값이 아니다).
--   줍기      블록 자리(BlockLayout.computeLayout)에 떨어진다. 플레이어는 층 중심에 서 있다고 본다. 끌어당기는 반경 r 안은 자동.
--             손 플레이 "last": 타이머 중에 부서진 블록의 드롭은 공격하면서 줍는다(판정 반경이 층 전체 — 공격이 끊기지 않는다).
--               클리어 뒤에는 마지막 블록 드롭만 — 블록까지 평균 거리 d에서 2 × max(0, d − r) ÷ 걷기 속도(LevelConfig.getMaxSpeed).
--             손 플레이 "all": 클리어 뒤 전부 — 중심에서 가까운 블록부터 r 안까지 걸어가는 순회 + 중심 복귀 ÷ 걷기 속도(비교 줄).
--             자동 진행 "autoAll"(전부 자동 · 시간 0) · "autoNone"(줍지 않음) · "autoRadius"(r 안 블록 드롭만).
--             남은 드롭 "vanish"(다음 층에서 사라짐) · "stay"(런 끝까지 — 자동 진행은 수령 직전에 한 번 순회해서 줍는다).
--   가방      런 동안만. 기본 용량 + 가방 업그레이드(S5' 대상에 들어간다 — 펀치 데미지 자리). 수령하면 가방 → 인벤토리,
--             실패하면 가방을 잃는다. 가득 차면 "leave"(못 줍고 남김) · "swap"(더 높은 구간 광석이면 낮은 것과 바꿔 줍기).
--
-- 후보마다 손잡이 하나를 25층 첫 진입 중앙값이 TARGET_MIN(38.7분)에 가깝도록 이분 탐색한다(TUNE_PLAYERS명) — 그 값으로 PLAYERS명을 다시 돈다.
--   선형 환생(1 + a·n): 손잡이 = 곡괭이 등급 배수 N(환생이 약하니 곡괭이가 성장을 맡는다)
--   지수 환생(b^n): 곡괭이 N은 후보에 적힌 값으로 고정 · 손잡이 = 환생 배수 b(환생이 성장을 맡는다)
-- "손잡이를 맞춘 뒤" 성공률 · 환생 수 · 등급 시각이 후보마다 어떻게 다른가가 비교 대상이다.
-- 1차 측정(2026-11-24): 지수 환생도 N을 손잡이로 두면 곡괭이가 성장을 다 가져가 25층까지 환생 2 ~ 4회였다 — 그래서 손잡이를 나눴다.
-- 2차 측정: b를 손잡이로 둬도 "막히면 환생"(지금 결정 모델)이면 환생은 약 11분마다 3회 — 환생 수는 비용이 아니라 막힘이 정한다.
--   그래서 지수 후보는 "살 수 있으면 바로 환생"(eager — Claude 해석, 사람 결정 모델 값이 아니다)으로 두고 막히면 환생은 비교 줄로 남긴다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local SuccessRateReport = require(script.Parent.SuccessRateReport)
local AttackService = require(script.Parent.Parent.Systems.AttackService)
local RollService = require(script.Parent.Parent.Systems.RollService)

type BigNumber = BigNum.BigNumber

local EconomyCandidateReport = {}

-- 관측 해상도(게임 수치가 아니다)
EconomyCandidateReport.PLAYERS = 200
EconomyCandidateReport.STUDY_PLAYERS = 100 -- 줍기 · 가방 · 자동 진행 비교 줄
EconomyCandidateReport.TUNE_PLAYERS = 50
EconomyCandidateReport.TUNE_STEPS = 6
EconomyCandidateReport.TARGET_MIN = 38.7 -- 지금(B4) 25층 첫 진입 중앙값 — 지시서 #29 기준(± 25%)
EconomyCandidateReport.N_RANGE = { 1.5, 400 }
EconomyCandidateReport.B_RANGE = { 1.05, 8 }
EconomyCandidateReport.ORE_PER_BLOCK = 1

-- ===== 후보 정의 ========================================================================================

-- ratio = 지수 후보의 고정 곡괭이 N · rule = 표준 플레이어 환생 시점("stuck" 막히면 — 지금 결정 모델 · "eager" 살 수 있으면 바로)
export type RebirthDef = { key: string, g: number, kind: string, a: number, gain: number, ratio: number?, rule: string? }
export type TierDef = { ore: number, cost: number }
export type PickDef = { key: string, tiers: { TierDef }, steps: number, stepKind: string, stepValue: number, stepCost: number }
export type PickupDef = {
	time: string, -- "last" · "all" · "off"(시간 0 — 넣기 전)
	pull: number, -- 끌어당기는 반경(스터드)
	mode: string, -- "hand" · "autoAll" · "autoNone" · "autoRadius"
	leftover: string, -- "vanish" · "stay"
	bagBase: number?, -- nil = 상한 없음(넣기 전)
	bagFull: string, -- "leave" · "swap"
	bagUpgrade: boolean, -- 가방 업그레이드(펀치 데미지 자리)를 S5'로 사는가
	bagPerLevel: number,
	bagPassMult: number, -- 가방 게임패스(구매자 비교 줄만 2)
}

EconomyCandidateReport.REBIRTHS = {
	R1 = { key = "R1", g = 1.6, kind = "linear", a = 2, gain = 1 },
	R2 = { key = "R2", g = 2.0, kind = "exp", a = 2, gain = 1, ratio = 2, rule = "eager" },
	R3 = { key = "R3", g = 2.7, kind = "exp", a = 2, gain = 1, ratio = 2, rule = "eager" },
	R4 = { key = "R4", g = 4.0, kind = "exp", a = 2, gain = 1, ratio = 2, rule = "eager" },
} :: { [string]: RebirthDef }
-- 곡괭이 후보를 R3에 얹을 때의 고정 N(등급 끝 배수가 비슷하게 — P1 2.5^4 = 39 · P2 2^5 × 1.75 = 56 · P3 1.8^6 × 2.01 = 69)
EconomyCandidateReport.PICK_RATIO = { P1 = 2.5, P2 = 2, P3 = 1.8 } :: { [string]: number }

EconomyCandidateReport.PICKAXES = {
	P1 = { key = "P1", steps = 0, stepKind = "add", stepValue = 0, stepCost = 0, tiers = {
		{ ore = 1, cost = 0 }, { ore = 1, cost = 15 }, { ore = 1, cost = 40 }, { ore = 2, cost = 30 }, { ore = 3, cost = 25 } } },
	P2 = { key = "P2", steps = 3, stepKind = "add", stepValue = 0.25, stepCost = 4, tiers = {
		{ ore = 1, cost = 0 }, { ore = 1, cost = 10 }, { ore = 1, cost = 30 }, { ore = 2, cost = 20 }, { ore = 2, cost = 50 }, { ore = 3, cost = 30 } } },
	P3 = { key = "P3", steps = 5, stepKind = "mul", stepValue = 1.15, stepCost = 3, tiers = {
		{ ore = 1, cost = 0 }, { ore = 1, cost = 8 }, { ore = 1, cost = 20 }, { ore = 1, cost = 45 }, { ore = 2, cost = 20 }, { ore = 2, cost = 50 },
		{ ore = 3, cost = 40 } } },
} :: { [string]: PickDef }

-- 줍기 · 가방 표준(손 플레이). 비교 줄은 이것을 덮어쓴다.
EconomyCandidateReport.PICKUP_STANDARD = {
	time = "last", pull = 12, mode = "hand", leftover = "vanish", bagBase = 30, bagFull = "leave",
	bagUpgrade = true, bagPerLevel = 5, bagPassMult = 1,
} :: PickupDef

-- ===== 순수 식 (EconomyCandidateReportTests가 잰다) =======================================================

function EconomyCandidateReport.rebirthCost(def: RebirthDef, n: number): BigNumber
	return BigNum.mul(BigNum.fromNumber(1000), BigNum.pow(BigNum.fromNumber(def.g), n))
end

-- 힘 배수의 환생 항(1 이상)
function EconomyCandidateReport.rebirthFactor(def: RebirthDef, n: number): number
	if def.kind == "exp" then
		return def.a ^ n
	end
	return 1 + def.a * n
end

function EconomyCandidateReport.pickMult(def: PickDef, ratio: number, tier: number, step: number): number
	local m = ratio ^ (tier - 1)
	if def.stepKind == "mul" then
		return m * def.stepValue ^ step
	end
	return m * (1 + def.stepValue * step)
end

-- 층 → 광석 종류(HP 구간 번호)
function EconomyCandidateReport.oreOf(stage: number): number
	local world = WorldConfig.get(SuccessRateReport.SIM.WORLD_ID) :: WorldConfig.WorldDef
	for i, seg in ipairs(world.hpGrowthSegments) do
		if stage >= seg.from and stage <= seg.to then
			return i
		end
	end
	return #world.hpGrowthSegments
end

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
function EconomyCandidateReport.pickDistance(stage: number, kind: string, r: number): number
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

-- 반경 r 안(층 중심에서) 블록 수
function EconomyCandidateReport.blocksWithin(stage: number, r: number): number
	local n = 0
	for _, v in ipairs(offsets(stage)) do
		if v.Magnitude <= r then
			n += 1
		end
	end
	return n
end

-- 가방에 넣기. 넣은 수를 돌려준다(가득 차면 leave / swap).
function EconomyCandidateReport.addToBag(bag: { number }, cap: number?, ore: number, count: number, full: string): number
	local added = 0
	for _ = 1, count do
		local used = 0
		for _, c in ipairs(bag) do
			used += c
		end
		if cap == nil or used < cap then
			bag[ore] = (bag[ore] or 0) + 1
			added += 1
		elseif full == "swap" then
			local lowest: number? = nil
			for i = 1, ore - 1 do
				if (bag[i] or 0) > 0 then
					lowest = i
					break
				end
			end
			if lowest == nil then
				break
			end
			bag[lowest :: number] -= 1
			bag[ore] = (bag[ore] or 0) + 1
			added += 1
		else
			break
		end
	end
	return added
end

-- 표준 제작 규칙(파일 상단). st.tier · st.step · st.inv를 제자리에서 바꾼다. 만든 등급 목록을 돌려준다.
function EconomyCandidateReport.craft(def: PickDef, st: any): { number }
	local made = {}
	while true do
		local nextDef = def.tiers[st.tier + 1]
		if nextDef ~= nil and (st.inv[nextDef.ore] or 0) >= nextDef.cost then
			st.inv[nextDef.ore] -= nextDef.cost
			st.tier += 1
			st.step = 0
			table.insert(made, st.tier)
			continue
		end
		if st.step < def.steps then
			local ore = def.tiers[st.tier].ore
			local cost = def.stepCost * (st.step + 1)
			local reserve = if nextDef ~= nil and nextDef.ore == ore then nextDef.cost else 0
			if (st.inv[ore] or 0) - cost >= reserve then
				st.inv[ore] -= cost
				st.step += 1
				continue
			end
		end
		break
	end
	return made
end

-- ===== 한 후보 돌리기 ======================================================================================

export type Candidate = {
	label: string,
	rebirth: RebirthDef,
	pick: PickDef,
	ratio: number?, -- nil이면 이분 탐색
	pickup: PickupDef,
	hpGrowths: { number }?, -- HP 성장률 세 값(비교 줄)
	bloxGainPerLevel: number?, -- 블럭스 획득 효과(비교 줄)
	noUpgrades: boolean?, -- 남는 업그레이드 2종(펀치 속도 · 블럭스 획득)을 안 사는 비교 줄
}

local function log10Big(v: BigNumber): number
	return if v.m > 0 then math.log10(v.m) + v.e else 0
end

local function median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	local c = table.clone(xs)
	table.sort(c)
	return c[math.floor((#c + 1) / 2)]
end

-- 후보 상태를 깔고 fn을 부른다. 언제나 되돌린다.
local function withCandidate(c: Candidate, ratio: number, stats: any, fn: () -> ())
	local SRR = SuccessRateReport :: any
	local saved = {
		econ = SRR.ECON,
		click = SRR.clickMultiplier,
		damage = SRR.damageMultiplier,
		targets = SRR.S5_TARGETS,
		bag = (UpgradeConfig.Upgrades :: any).bagCap,
		bloxGain = (UpgradeConfig.Upgrades :: any).bloxGain.effectPerLevel,
	}
	local world = WorldConfig.get(SuccessRateReport.SIM.WORLD_ID) :: WorldConfig.WorldDef
	local savedSegs = world.hpGrowthSegments
	local rb, pk, pu = c.rebirth, c.pick, c.pickup
	local states: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
	stats.states = states

	local function st(p: any): any
		local s = states[p]
		if s == nil then
			s = { n = 0, tier = 1, step = 0, inv = { 0, 0, 0 }, bag = { 0, 0, 0 }, left = { 0, 0, 0 }, tierAt = {}, rebirthAt = {},
				collected = 0, pickSec = 0, lostBag = 0 }
			states[p] = s
		end
		return s
	end
	local function bagCap(p: any): number?
		if pu.bagBase == nil then
			return nil
		end
		local extra = if pu.bagUpgrade then UpgradeConfig.getEffect("bagCap", p.upgrades.bagCap or 0) else 0
		return math.floor((pu.bagBase :: number + extra) * pu.bagPassMult)
	end
	local function speed(p: any): number
		return LevelConfig.getMaxSpeed(p.strength)
	end

	SRR.ECON = {
		eager = rb.rule == "eager",
		canRebirth = function(p)
			return BigNum.gte(p.blox, EconomyCandidateReport.rebirthCost(rb, st(p).n))
		end,
		rebirthCost = function(p)
			return EconomyCandidateReport.rebirthCost(rb, st(p).n)
		end,
		applyRebirth = function(p)
			local s = st(p)
			s.n += rb.gain
			p.rebirths = BigNum.fromNumber(s.n)
			table.insert(s.rebirthAt, p.elapsedSec)
		end,
		onRunStart = function(p)
			local s = st(p)
			for _, t in ipairs(EconomyCandidateReport.craft(pk, s)) do
				if s.tierAt[t] == nil then
					s.tierAt[t] = p.elapsedSec
				end
			end
			table.clear(s.bag)
			s.bag[1], s.bag[2], s.bag[3] = 0, 0, 0
			s.left[1], s.left[2], s.left[3] = 0, 0, 0
		end,
		onStageClear = function(p, stage)
			local s = st(p)
			local ore = EconomyCandidateReport.oreOf(stage)
			local count = StageConfig.getBlockCount(stage)
			local drops = count * EconomyCandidateReport.ORE_PER_BLOCK
			local sec = 0
			local got = drops
			if pu.mode == "autoNone" then
				got = 0
			elseif pu.mode == "autoRadius" then
				got = EconomyCandidateReport.blocksWithin(stage, pu.pull) * EconomyCandidateReport.ORE_PER_BLOCK
			elseif pu.mode == "hand" and pu.time ~= "off" then
				sec = EconomyCandidateReport.pickDistance(stage, pu.time, pu.pull) / speed(p)
			end
			local added = EconomyCandidateReport.addToBag(s.bag, bagCap(p), ore, got, pu.bagFull)
			if pu.leftover == "stay" then
				s.left[ore] += drops - got
			end
			s.pickSec += sec
			return sec
		end,
		onRunEnd = function(p, best, cashed)
			local s = st(p)
			if cashed then
				if pu.leftover == "stay" and (s.left[1] + s.left[2] + s.left[3]) > 0 then
					-- 수령 직전 한 번 순회해서 남은 드롭을 줍는다(마지막 층 배치로 근사)
					local sec = EconomyCandidateReport.pickDistance(math.max(best, 1), "all", pu.pull) / speed(p)
					p.elapsedSec += sec
					s.pickSec += sec
					for ore = 3, 1, -1 do
						EconomyCandidateReport.addToBag(s.bag, bagCap(p), ore, s.left[ore], pu.bagFull)
					end
				end
				for i = 1, 3 do
					s.inv[i] += s.bag[i]
					s.collected += s.bag[i]
				end
			else
				s.lostBag += s.bag[1] + s.bag[2] + s.bag[3]
			end
			s.bag[1], s.bag[2], s.bag[3] = 0, 0, 0
		end,
	}
	SRR.clickMultiplier = function(p: any): BigNumber
		return StrengthMultiplier.compute({
			rebirths = BigNum.fromNumber(EconomyCandidateReport.rebirthFactor(rb, st(p).n) - 1),
			titleMult = SuccessRateReport.titleMult(p),
			auraMult = SuccessRateReport.auraMult(p),
			petMult = SuccessRateReport.petMult(p),
		})
	end
	SRR.damageMultiplier = function(p: any): number
		local s = st(p)
		return AttackService.combineDamageMultiplier({
			punchDamage = EconomyCandidateReport.pickMult(pk, ratio, s.tier, s.step),
			auraMult = SuccessRateReport.auraMult(p),
		})
	end
	local targets = if c.noUpgrades then {} else { "punchSpeed", "bloxGain" }
	if pu.bagUpgrade and pu.bagBase ~= nil then
		table.insert(targets, "bagCap")
	end
	SRR.S5_TARGETS = targets
	-- 가방 업그레이드: 100 × 1.6^L(1차 측정에서 1.15는 너무 싸 S5'가 용량을 수십 레벨 사서 상한이 안 걸렸다)
	;(UpgradeConfig.Upgrades :: any).bagCap = { exposed = true, maxLevel = nil, baseCost = BigNum.new(1, 2), costGrowth = 1.6,
		effectBase = 0, effectPerLevel = pu.bagPerLevel }
	if c.bloxGainPerLevel ~= nil then
		(UpgradeConfig.Upgrades :: any).bloxGain.effectPerLevel = c.bloxGainPerLevel
	end
	if c.hpGrowths ~= nil then
		local swapped = {}
		for i, seg in ipairs(savedSegs) do
			swapped[i] = { from = seg.from, to = seg.to, growth = (c.hpGrowths :: { number })[i] }
		end
		world.hpGrowthSegments = swapped
	end

	local ok, err = pcall(fn)

	SRR.ECON = saved.econ
	SRR.clickMultiplier = saved.click
	SRR.damageMultiplier = saved.damage
	SRR.S5_TARGETS = saved.targets
	;(UpgradeConfig.Upgrades :: any).bagCap = saved.bag
	;(UpgradeConfig.Upgrades :: any).bloxGain.effectPerLevel = saved.bloxGain
	world.hpGrowthSegments = savedSegs
	if not ok then
		error(err)
	end
end

local function lastStage(): number
	local s = 1
	while StageConfig.hasStage(s + 1) do
		s += 1
	end
	return s
end

-- 후보 한 벌을 players명 돌려 지표를 돌려준다.
function EconomyCandidateReport.measure(c: Candidate, ratio: number, players: number): any
	local stats: any = {}
	local out: any = nil
	withCandidate(c, ratio, stats, function()
		local SIM = SuccessRateReport.SIM
		local maxStage = lastStage()
		local rng = Random.new(SIM.SEED)
		local titleRandom = RollService.seededRandom(SIM.TITLE_SEED)
		local auraRandom = RollService.seededRandom(SIM.AURA_SEED)
		local petRandom = RollService.seededRandom(SIM.PET_SEED)
		local firstTry = {}
		local results = {}
		local finals: { any } = {}
		local cur: any = nil
		local observer = function(event: string, p: any, seen: { [number]: boolean }, _reached: number?)
			if event == "run_end" and seen[maxStage] and cur.final == nil then
				local s = stats.states[p]
				local pickM = EconomyCandidateReport.pickMult(c.pick, ratio, s.tier, s.step)
				local aura = SuccessRateReport.auraMult(p)
				cur.final = {
					sec = p.elapsedSec,
					n = s.n,
					tier = s.tier,
					step = s.step,
					strength = log10Big(p.strength),
					damage = log10Big(p.strength) + math.log10(SuccessRateReport.damageMultiplier(p)),
					rebirthLog = math.log10(EconomyCandidateReport.rebirthFactor(c.rebirth, s.n)),
					pickLog = math.log10(pickM),
					auraLog = 2 * math.log10(aura), -- 힘 항 + 데미지 항(A10)
					petLog = math.log10(SuccessRateReport.petMult(p)),
					titleLog = math.log10(SuccessRateReport.titleMult(p)),
					bloxPerMin = 10 ^ log10Big(p.lifetimeBlox) / math.max(p.elapsedSec / 60, 1e-9),
					orePerMin = s.collected / math.max(p.elapsedSec / 60, 1e-9),
					pickSec = s.pickSec,
					lostBag = s.lostBag,
					collected = s.collected,
				}
				local intervals = {}
				for i = 2, #s.rebirthAt do
					table.insert(intervals, (s.rebirthAt[i] - s.rebirthAt[i - 1]) / 60)
				end
				cur.final.firstRebirthMin = if s.rebirthAt[1] ~= nil then s.rebirthAt[1] / 60 else nil
				cur.final.intervalMin = median(intervals)
				cur.final.tierAt = table.clone(s.tierAt)
			end
		end
		for _ = 1, players do
			cur = {}
			table.insert(results, SuccessRateReport.simulatePlayer(rng, maxStage, firstTry, titleRandom, auraRandom, petRandom, { observer = observer }))
			if cur.final ~= nil then
				table.insert(finals, cur.final)
			end
			task.wait()
		end
		out = { metrics = SuccessRateReport.metrics(firstTry, results), finals = finals, players = players }
	end)
	return out
end

local function pct(x: number?): string
	return if x ~= nil then string.format("%.1f", x * 100) else "-"
end

local function fmt(x: number?, f: string?): string
	return if x ~= nil then string.format(f or "%.1f", x) else "-"
end

local function medOf(finals: { any }, key: string): number?
	local xs = {}
	for _, f in ipairs(finals) do
		if f[key] ~= nil then
			table.insert(xs, f[key])
		end
	end
	return median(xs)
end

-- 목표 ±10%p 밖 층
local function outOfBand(m: any): { string }
	local out = {}
	for stage = 1, m.maxStage do
		local r = m.floorRates[stage]
		local t = SuccessRateReport.targetFor(stage)
		if r ~= nil and t ~= nil then
			local tol = SuccessRateReport.TARGET_TOLERANCE
			if r < t.min - tol or r > t.max + tol then
				table.insert(out, string.format("%d:%s", stage, pct(r)))
			end
		end
	end
	return out
end

-- 손잡이 값을 넣은 후보(지수 환생이면 b를 바꾼 사본)와 곡괭이 N
local function apply(c: Candidate, knob: number): (Candidate, number)
	if c.rebirth.kind == "exp" then
		local rb = table.clone(c.rebirth)
		rb.a = knob
		local c2 = table.clone(c)
		c2.rebirth = rb
		return c2, c.ratio or rb.ratio or 2
	end
	return c, knob
end

-- 손잡이 이분 탐색(log 공간). 중앙값이 없으면(최고층 못 감) 느린 것으로 본다. 키우면 빨라진다(N · b 둘 다).
function EconomyCandidateReport.tune(c: Candidate): number
	local range = if c.rebirth.kind == "exp" then EconomyCandidateReport.B_RANGE else EconomyCandidateReport.N_RANGE
	local lo, hi = math.log(range[1]), math.log(range[2])
	for _ = 1, EconomyCandidateReport.TUNE_STEPS do
		local mid = (lo + hi) / 2
		local cc, ratio = apply(c, math.exp(mid))
		local r = EconomyCandidateReport.measure(cc, ratio, EconomyCandidateReport.TUNE_PLAYERS)
		local m = r.metrics.medianFinalMin
		if m == nil or r.metrics.reached * 2 < r.players or m > EconomyCandidateReport.TARGET_MIN then
			lo = mid -- 느리다 → N을 키운다
		else
			hi = mid
		end
	end
	return math.exp((lo + hi) / 2)
end

function EconomyCandidateReport.report(c0: Candidate, players: number, knob: number?): number
	local k = knob or EconomyCandidateReport.tune(c0)
	local c, ratio = apply(c0, k)
	local r = EconomyCandidateReport.measure(c, ratio, players)
	local m, f = r.metrics, r.finals
	local seg = m.segments
	local tierText = {}
	for t = 2, #c.pick.tiers do
		local xs = {}
		for _, x in ipairs(f) do
			if x.tierAt[t] ~= nil then
				table.insert(xs, x.tierAt[t] / 60)
			end
		end
		table.insert(tierText, string.format("T%d %s(%d)", t, fmt(median(xs)), #xs))
	end
	local function share(key: string): string
		local xs = {}
		for _, x in ipairs(f) do
			local total = x.rebirthLog + x.pickLog + x.auraLog + x.petLog + x.titleLog
			if total > 0 then
				table.insert(xs, x[key] / total)
			end
		end
		return pct(median(xs))
	end
	print(string.format("[ECON] %s · N=%.2f · 환생 %s · 비용 g %.1f · %s · %d명 · 25층 %d명 · 중앙 %s분 · 구간 %s / %s / %s · 목표 밖 %s",
		c.label, ratio, if c.rebirth.kind == "exp" then string.format("%.2f^n", c.rebirth.a) else string.format("1+%g·n", c.rebirth.a), c.rebirth.g, c.rebirth.rule or "stuck", players, m.reached, fmt(m.medianFinalMin), pct(seg[1] and seg[1].rate), pct(seg[2] and seg[2].rate),
		pct(seg[3] and seg[3].rate), table.concat(outOfBand(m), " ")))
	print(string.format("[ECON]   환생 첫 %s분 · 25층까지 %s회 · 간격 %s분 · 등급 %s",
		fmt(medOf(f, "firstRebirthMin")), fmt(medOf(f, "n"), "%.0f"), fmt(medOf(f, "intervalMin"), "%.2f"), table.concat(tierText, " ")))
	print(string.format("[ECON]   25층 힘 10^%s · 데미지 10^%s · 몫(log) 환생 %s · 곡괭이 %s · 아우라 %s · 펫 %s · 칭호 %s",
		fmt(medOf(f, "strength")), fmt(medOf(f, "damage")), share("rebirthLog"), share("pickLog"), share("auraLog"), share("petLog"), share("titleLog")))
	print(string.format("[ECON]   블럭스/분 10^%s · 광석/분 %s · 줍기 %s분 · 실패로 잃은 광석 %s · 모은 광석 %s",
		fmt((function()
			local v = medOf(f, "bloxPerMin")
			return if v ~= nil and v > 0 then math.log10(v) else nil
		end)(), "%.2f"), fmt(medOf(f, "orePerMin"), "%.2f"), fmt((function()
			local v = medOf(f, "pickSec")
			return if v ~= nil then v / 60 else nil
		end)(), "%.2f"), fmt(medOf(f, "lostBag"), "%.0f"), fmt(medOf(f, "collected"), "%.0f")))
	return k
end

local function pickup(over: { [string]: any }): PickupDef
	local p = table.clone(EconomyCandidateReport.PICKUP_STANDARD) :: any
	for k, v in pairs(over) do
		p[k] = v
	end
	return p
end

function EconomyCandidateReport.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	task.wait(5) -- 시작 직후 테스트들이 MODEL · Config를 잠깐 흔드는 동안 기다린다
	local E = EconomyCandidateReport
	local R, P = E.REBIRTHS, E.PICKAXES
	local std = E.PICKUP_STANDARD
	local t0 = os.clock()
	print(string.format("[ECON] ===== 경제 후보 (지시서 #29 — 채택하지 않는다) · 결정 모델 S5'(펀치 데미지 → 곡괭이 · 가방) + S7 + A4 + E11 · 목표 %.1f분 =====",
		E.TARGET_MIN))
	-- 1. 환생 후보(곡괭이 P2 · 줍기 표준). R1 손잡이 = N, R2 ~ R4 손잡이 = b(N 고정)
	local refKnob = 0
	for _, key in ipairs({ "R1", "R2", "R3", "R4" }) do
		local k = E.report({ label = key .. "+P2", rebirth = R[key], pick = P.P2, pickup = std }, E.PLAYERS)
		if key == "R3" then
			refKnob = k
		end
	end
	-- 2. 곡괭이 후보(환생 R3 · 고정 N은 PICK_RATIO)
	for _, key in ipairs({ "P1", "P3" }) do
		E.report({ label = "R3+" .. key, rebirth = R.R3, pick = P[key], ratio = E.PICK_RATIO[key], pickup = std }, E.PLAYERS)
	end
	-- 3. HP 곡선 후보(R3+P2 · b 다시 맞춤) — 살 수 있으면 바로 환생이면 9 ~ 25층 첫 진입 성공률이 목표보다 높다(2차 측정)
	for _, g in ipairs({ { 2.8, 4.3, 9.0 }, { 2.8, 4.5, 12.0 } }) do
		E.report({ label = string.format("R3+P2 · HP %g / %g / %g", g[1], g[2], g[3]), rebirth = R.R3, pick = P.P2, pickup = std, hpGrowths = g },
			E.PLAYERS)
	end
	print(string.format("[ECON] ----- 비교 줄 (R3+P2 · b=%.2f 고정) · %.0f초 -----", refKnob, os.clock() - t0))
	local function row(label: string, over: { [string]: any }, extra: { [string]: any }?)
		local c: any = { label = label, rebirth = R.R3, pick = P.P2, pickup = pickup(over) }
		for k, v in pairs(extra or {}) do
			c[k] = v
		end
		E.report(c, E.STUDY_PLAYERS, refKnob)
	end
	row("x2 Rebirths(+2)", {}, { rebirth = { key = "R3x2", g = R.R3.g, kind = R.R3.kind, a = R.R3.a, gain = 2, ratio = R.R3.ratio, rule = R.R3.rule } })
	row("막히면 환생(stuck — 지금 규칙)", {}, { rebirth = { key = "R3s", g = R.R3.g, kind = R.R3.kind, a = R.R3.a, gain = 1, ratio = R.R3.ratio, rule = "stuck" } })
	row("넣기 전(줍기 0초 · 가방 무한)", { time = "off", bagBase = nil })
	row("표준(last · r12 · 가방 30 + 5/레벨 · 남김)", {})
	row("반경 r6", { pull = 6 })
	row("반경 r20", { pull = 20 })
	row("클리어 뒤 전부 줍기(all)", { time = "all" })
	row("가방 20", { bagBase = 20 })
	row("가방 무한(줍기 시간 있음)", { bagBase = nil })
	row("가방 바꿔 줍기(swap)", { bagFull = "swap" })
	row("가방 업그레이드 안 삼", { bagUpgrade = false })
	row("가방 업그레이드 안 삼 · swap", { bagUpgrade = false, bagFull = "swap" })
	row("가방 패스 ×2(구매자)", { bagPassMult = 2 })
	row("자동 진행 전부 줍기", { mode = "autoAll" })
	row("자동 진행 안 줍기", { mode = "autoNone" })
	row("자동 진행 반경 r12 · 사라짐", { mode = "autoRadius", leftover = "vanish" })
	row("자동 진행 반경 r35 · 사라짐", { mode = "autoRadius", leftover = "vanish", pull = 35 })
	row("자동 진행 반경 r12 · 런 끝까지", { mode = "autoRadius", leftover = "stay" })
	row("블럭스 획득 0.10/레벨", {}, { bloxGainPerLevel = 0.10 })
	row("펀치 속도 · 블럭스 획득 안 삼(가방만)", {}, { noUpgrades = true })
	print(string.format("[ECON] ===== 끝 · %.0f초 =====", os.clock() - t0))
end

return EconomyCandidateReport

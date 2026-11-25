--!strict
-- 경제 #31 결정 검증(#37부터 유일한 경제 — 플래그는 지웠다).
--   제작 · 부화 시간 = 연출 + 스킵(무료 스킵 · 연출 생략 최소 간격 · 트리플) · 상위 광석 드롭 기대값 · 강화 블럭스 비용 변형(N5 — 기본 nil) ·
--   임시 이름 Strings 25개(광석 10 · 곡괭이 15) · x2 Rebirths 새 경제에서 빠짐(효과 1 · 구매 not_available · 끔이면 그대로) ·
--   분석 이벤트 rebirth v2 값(환생 수 · 비용 자릿수) · 환생 v2 결과에 낸 비용.
-- 숫자는 Config에서 읽는다(하드코딩하지 않는다).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local AnalyticsConfig = require(ReplicatedStorage.Shared.Config.AnalyticsConfig)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local MarketplaceGateway = require(ServerScriptService.Server.Systems.MarketplaceGateway)
local PurchaseRequestService = require(ServerScriptService.Server.Systems.PurchaseRequestService)
local Analytics = require(ServerScriptService.Server.Systems.Analytics)
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

-- 1. 제작 · 부화 시간 모델 ------------------------------------------------------------------------
do
	check("설정: 옛 자동 제작 간격 손잡이는 없다(연출 + 스킵 모델로 바뀜)", (Config :: any).AUTO_CRAFT_INTERVAL_SEC == nil and (Config :: any).FAST_CRAFT_FACTOR == nil)
	local s0, n0 = L.craftStep(false, false)
	local s1, n1 = L.craftStep(true, false)
	local s3, n3 = L.craftStep(false, true)
	check("제작: 무료 = 스킵 시점마다 1회", s0 == Config.CRAFT_SKIP_SEC and n0 == 1)
	check("제작: 연출 생략 = 서버 최소 간격마다 1회", s1 == Config.CRAFT_MIN_INTERVAL_SEC and n1 == 1 and s1 <= s0)
	check("제작: 트리플 = 한 번에 TRIPLE_CRAFT_COUNT회", s3 == Config.CRAFT_SKIP_SEC and n3 == Config.TRIPLE_CRAFT_COUNT)
	local h0, hn0 = L.hatchStep(false, false)
	local h1, hn1 = L.hatchStep(true, true)
	check("부화: 같은 모델(무료 스킵 · 연출 생략 · 트리플)", h0 == Config.HATCH_SKIP_SEC and hn0 == 1 and h1 == Config.HATCH_MIN_INTERVAL_SEC
		and hn1 == Config.TRIPLE_HATCH_COUNT)
	local sec = Config.CRAFT_SKIP_SEC * 7 + Config.CRAFT_SKIP_SEC / 2
	check("자동 제작 회수 = 내림(초 ÷ 간격) × 한 번 회수", L.autoCraftCount(sec, false, false) == 7 and L.autoCraftCount(sec, false, true) == 7 * Config.TRIPLE_CRAFT_COUNT
		and L.autoCraftCount(0, true, true) == 0)
end

-- 1b. 대장간 여는 층(Claude 제안 — 설정 nil이면 처음부터) ---------------------------------------------
do
	local savedStage, savedReb = Config.FORGE_UNLOCK_STAGE, Config.FORGE_UNLOCK_REBIRTHS
	Config.FORGE_UNLOCK_STAGE, Config.FORGE_UNLOCK_REBIRTHS = nil, nil
	local openNil = L.forgeOpen(0, 0)
	Config.FORGE_UNLOCK_STAGE = 8
	local below, at, above = L.forgeOpen(7, 0), L.forgeOpen(8, 0), L.forgeOpen(25, 0)
	Config.FORGE_UNLOCK_STAGE, Config.FORGE_UNLOCK_REBIRTHS = nil, 1
	local r0, r1, rBig = L.forgeOpen(25, 0), L.forgeOpen(1, 1), L.forgeOpen(1, BigNum.fromNumber(3))
	Config.FORGE_UNLOCK_STAGE, Config.FORGE_UNLOCK_REBIRTHS = savedStage, savedReb
	check("대장간: 둘 다 nil이면 처음부터 · 층 조건은 평생 최고층", openNil and not below and at and above)
	check("대장간: 환생 조건은 환생 수(BigNum도)", not r0 and r1 and rBig)
end

-- 2. 상위 광석 드롭 -------------------------------------------------------------------------------
do
	local low = L.dropsPerBlock(Config.UPPER_ORE_FROM - 1)
	local high = L.dropsPerBlock(Config.UPPER_ORE_FROM)
	-- #33 N12: 광석별 드롭 표(ORE_DROP_BY_ORE)가 있으면 그 표 · 모든 광석 ORE_DROP_MIN 이상(N13). 없으면 예전 규칙(하위 ORE_PER_BLOCK · 상위 × MULT)
	local byOre = Config.ORE_DROP_BY_ORE
	local tableOk = true
	if byOre ~= nil then
		for k = 1, Config.ORE_COUNT do
			tableOk = tableOk and L.dropsPerBlock(k) == byOre[k] and L.dropsPerBlock(k) >= Config.ORE_DROP_MIN
		end
	end
	check("드롭: 광석별 표가 있으면 그 표(모두 ORE_DROP_MIN 이상) · 없으면 하위 ORE_PER_BLOCK · 상위는 × UPPER_ORE_DROP_MULT", if byOre ~= nil
		then tableOk else (low == Config.ORE_PER_BLOCK and math.abs(high - Config.ORE_PER_BLOCK * Config.UPPER_ORE_DROP_MULT) < 1e-12))
	local saved = Config.UPPER_ORE_DROP_MULT
	Config.UPPER_ORE_DROP_MULT = 1.5
	local upperStage = Config.ORE_BANDS[Config.UPPER_ORE_FROM].from
	local exact = L.rollDrops(upperStage, 10, nil)
	local r = Random.new(31)
	local total = 0
	local trials = 2000
	for _ = 1, trials do
		total += L.rollDrops(upperStage, 10, function()
			return r:NextNumber()
		end)
	end
	local expect = 10 * L.dropsPerBlock(Config.UPPER_ORE_FROM)
	Config.UPPER_ORE_DROP_MULT = saved
	check("드롭: 난수 없으면 기대값 반올림", exact == math.floor(expect + 0.5))
	check("드롭: 확률 드롭 평균 = 기대값(±3%)", math.abs(total / trials / expect - 1) < 0.03, string.format("%.3f / %.3f", total / trials, expect))
end

-- 3. 강화 블럭스 비용(N5 변형 — 기본은 안 씀) ---------------------------------------------------------
do
	check("강화 블럭스: 기본 nil(사람 결정 전)", Config.ENHANCE_BLOX_COST_BASE == nil and L.enhanceBloxCost(0) == nil)
	local saved = Config.ENHANCE_BLOX_COST_BASE
	Config.ENHANCE_BLOX_COST_BASE = BigNum.new(1, 4)
	local c0, c2 = L.enhanceBloxCost(0), L.enhanceBloxCost(2)
	local cMax = L.enhanceBloxCost(Config.ENHANCE_MAX)
	Config.ENHANCE_BLOX_COST_BASE = saved
	check("강화 블럭스: BASE × GROWTH^수준 · 최대면 nil", c0 ~= nil and c2 ~= nil and BigNum.eq(c0 :: any, BigNum.new(1, 4))
		and math.abs(BigNum.toRatio(c2 :: any, c0 :: any) - Config.ENHANCE_BLOX_COST_GROWTH ^ 2) < 1e-6 and cMax == nil)
end

-- 4. 임시 이름 25개 -------------------------------------------------------------------------------
do
	local ok = true
	local seen: { [string]: boolean } = {}
	for k = 1, Config.ORE_COUNT do
		local key = L.oreNameKey(k)
		ok = ok and Locale.tFor("en", key) ~= key and Locale.tFor("ko", key) ~= key and Names.ore(k) == Locale.t(key)
		seen[Locale.tFor("en", key)] = true
	end
	check("이름: 광석 10개 en · ko 키 · Names.ore", ok)
	local okP = true
	local nP = 0
	for _, def in ipairs(Config.PICKAXES) do
		local key = L.pickaxeNameKey(def.id)
		local en = Locale.tFor("en", key)
		local ko = Locale.tFor("ko", key)
		okP = okP and en ~= key and ko ~= key and Names.pickaxe(def.id) == Locale.t(key)
			and string.sub(en, -#" Pickaxe") == " Pickaxe" and string.sub(ko, -#" 곡괭이") == " 곡괭이"
		nP += 1
	end
	check("이름: 곡괭이 15개 en · ko 키 · 뒤에 Pickaxe / 곡괭이 · Names.pickaxe", okP and nP == #Config.PICKAXES)
	local dupe = false
	local enSet: { [string]: boolean } = {}
	for _, def in ipairs(Config.PICKAXES) do
		local en = Locale.tFor("en", def.nameKey)
		dupe = dupe or enSet[en] == true
		enSet[en] = true
	end
	check("이름: 곡괭이 이름 겹침 없음 · 광석 이름 10종 서로 다름", not dupe and (function()
		local n = 0
		for _ in pairs(seen) do
			n += 1
		end
		return n == Config.ORE_COUNT
	end)())
end

-- 5. x2 Rebirths(#37에서 지웠다 — 상품 줄 · 효과 · 구매 처리) -------------------------------------------------
do
	check("빠진 상품: x2 Rebirths는 ShopConfig에 없다(#37 다)", ShopConfig.get("rebirth2x") == nil and table.find(ShopConfig.GAMEPASS_ORDER, "rebirth2x") == nil)
	local catalog = MarketplaceGateway.fakeCatalog({ damage2x = 9402 })
	local w: any = { gateway = MarketplaceGateway.fake(), sent = {} }
	w.handler = PurchaseRequestService._pure.createHandler({
		gateway = w.gateway,
		owns = function()
			return false
		end,
		isRestricted = function()
			return false
		end,
		hasGrant = function()
			return false
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
		catalog = catalog,
	})
	local player: any = { Name = "EconV2Purchase", UserId = 831 }
	local rOn = w.handler.onRequest(player, { key = "rebirth2x" }, 10)
	local rOther = w.handler.onRequest(player, { key = "damage2x" }, 20)
	check("구매: x2 Rebirths 요청 → invalid_key(없는 상품 — #37 다) · 다른 패스는 그대로", not rOn.ok and rOn.reason == PurchaseRequestService.REASON_INVALID_KEY
		and rOther.ok)
end

-- 6. 분석 이벤트 rebirth v2 -----------------------------------------------------------------------
do
	local custom = {}
	local a = Analytics.new({
		sink = {
			economy = function() end,
			custom = function(_p, name, value, fields)
				table.insert(custom, { name = name, value = value, fields = fields })
			end,
			funnel = function() end,
		},
		clock = function()
			return 0
		end,
		log = function() end,
		isPlayer = function()
			return true
		end,
		spawn = function(fn)
			fn()
		end,
		verbose = false,
	} :: any)
	local player: any = { Name = "EconV2Analytics", UserId = 832 }
	local cost = L.rebirthCost(5)
	local ok = a.rebirth(player, BigNum.fromNumber(6), cost)
	local c = custom[1]
	local digits = math.floor(math.log10(cost.m) + cost.e + 1e-9)
	check("분석: v2 값 = 환생 뒤 환생 수 · 필드 1 = 비용 자릿수", ok and c ~= nil and c.name == AnalyticsConfig.EVENTS.rebirth and c.value == 6
		and c.fields ~= nil and c.fields[1] == tostring(digits))
	local bad = a.rebirth(player, BigNum.new(0, 0), cost)
	check("분석: 환생 수 0 · 깨진 값은 거부", not bad and #custom == 1)
end

-- 7. 환생 v2 결과에 낸 비용 -----------------------------------------------------------------------
do
	local runRebirth = RebirthService._pure.runRebirth
	local function deps(blox: BigNum.BigNumber, rebirths: number): any
		local w = { blox = blox, rebirths = BigNum.fromNumber(rebirths) }
		return {
			getBlox = function()
				return w.blox
			end,
			getRebirths = function()
				return w.rebirths
			end,
			abandonRun = function() end,
			setBlox = function(_p, v)
				w.blox = v
				return true
			end,
			subtractBlox = function(_p, v)
				w.blox = BigNum.sub(w.blox, v)
				return true
			end,
			addRebirths = function(_p, v)
				w.rebirths = BigNum.add(w.rebirths, v)
				return true, w.rebirths
			end,
			setStrength = function()
				return true
			end,
			resetMaxStage = function() end,
			resetCurrentWorld = function() end,
			onRebirth = function() end,
			resetLifeBlox = function()
				return true
			end,
			resetPad = function() end,
		}
	end
	local n = 3
	local cost = L.rebirthCost(n)
	local ok, res = runRebirth(deps(BigNum.mul(cost, BigNum.fromNumber(2)), n), {} :: any, "test")
	check("환생 v2: 결과에 낸 비용(분석 값)", ok and res.cost ~= nil and BigNum.eq(res.cost, cost))
end

print(string.format("[EconomyV2DecisionTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EconomyV2DecisionTests] %d test(s) failed", failed))
end

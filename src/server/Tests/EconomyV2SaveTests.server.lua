--!strict
-- 새 경제 저장 v10 · 단일 관문 검증(지시서 #32). 프로필을 로드하지 않는다 — Schema · Migrations 순수 함수 · InventoryService._pure ·
-- 가짜 데이터 표(InventoryService._deps 바꿔 끼움 — 끝나면 되돌린다) · CurrencyService._pure(coins).
--   v9 → v10 이주(기본값 · 멱등 · 기존 값 그대로 · 결과가 v10 검증 통과) · 검증 거부 · Schema 상한 = EconomyV2Config ·
--   InventoryService(광석 · 토큰 · 장비 종류별 · 장착 · 대장간 — 검증 · 사유 · 실패면 그대로) · 코인 = CurrencyService 재화
-- 숫자는 Config · Schema에서 읽는다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local Schema = require(ServerScriptService.Server.Data.Schema)
local Migrations = require(ServerScriptService.Server.Data.Migrations)
local InventoryService = require(ServerScriptService.Server.Systems.InventoryService)
local CurrencyService = require(ServerScriptService.Server.Systems.CurrencyService)

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

local L = Schema.LIMITS

-- 1. Schema 상한 = Config ----------------------------------------------------------------------------
do
	local kindsOk = #L.EQUIPMENT_KINDS == #Config.EQUIPMENT_KINDS
	for i, kind in ipairs(Config.EQUIPMENT_KINDS) do
		kindsOk = kindsOk and L.EQUIPMENT_KINDS[i] == kind and L.START_EQUIPMENT[kind] == Config.EQUIPMENT[kind].start
	end
	check("상한: 광석 수 · 장비 종류 · 시작 장비 = EconomyV2Config", L.ORE_COUNT == Config.ORE_COUNT and kindsOk)
	check("상한: 별 · 강화 = EconomyV2Config", L.MAX_STARS == #Config.STAR_CONSUME and L.MAX_ENHANCE == Config.ENHANCE_MAX)
	local tokenOk = #L.TOKEN_KEYS == #Config.RARITIES
	for i, r in ipairs(Config.RARITIES) do
		if i > 1 then
			tokenOk = tokenOk and L.TOKEN_KEYS[i - 1] == r
		end
	end
	check("상한: 토큰 = 희귀 이상 등급 + ???(NEXT_RARITY)", tokenOk and L.TOKEN_KEYS[#L.TOKEN_KEYS] == Config.NEXT_RARITY)
end

-- 2. 템플릿 기본값 ------------------------------------------------------------------------------------
do
	local d = Schema.new()
	local oresZero = #d.ores == Config.ORE_COUNT
	for k = 1, Config.ORE_COUNT do
		oresZero = oresZero and d.ores[k] == 0
	end
	check("기본값: 광석 10종 0", oresZero)
	local start = Config.START_PICKAXE
	local o = d.equipment.pickaxe[start]
	check("기본값: 일반 1번 곡괭이 1개 보유 · 장착", o ~= nil and o.count == 1 and o.stars == 0 and o.enh == 0 and d.equipped.pickaxe == start)
	local only = 0
	for _ in pairs(d.equipment.pickaxe) do
		only += 1
	end
	check("기본값: 장비는 시작 곡괭이 하나뿐", only == 1)
	local tokensZero = true
	for _, key in ipairs(L.TOKEN_KEYS) do
		tokensZero = tokensZero and d.tokens[key] == 0
	end
	check("기본값: 토큰 0 · 코인 0 · 대장간 닫힘", tokensZero and d.coins.m == 0 and d.coins.e == 0 and d.forgeOpen == false)
	check("기본값: 새 템플릿이 v10 검증을 통과", (Schema.validate(d)))
end

-- 3. 이주 v9 → v10 -----------------------------------------------------------------------------------
do
	local v9 = Schema.new()
	v9.schemaVersion = 9
	for _, field in ipairs({ "coins", "ores", "equipment", "equipped", "tokens", "forgeOpen" }) do
		v9[field] = nil
	end
	v9.blox = { m = 3.5, e = 9 }
	v9.rebirths = { m = 4, e = 0 }
	local ok, err = Migrations.run(v9)
	check("이주: v9 → v10 성공 · schemaVersion 10", ok and v9.schemaVersion == 10 and Schema.VERSION == 10, err)
	check("이주: 새 필드 기본값(광석 0 · 시작 곡괭이 보유 · 장착 · 토큰 0 · 코인 0 · 닫힘)", v9.ores[1] == 0 and v9.ores[Config.ORE_COUNT] == 0
		and v9.equipment.pickaxe[Config.START_PICKAXE].count == 1 and v9.equipped.pickaxe == Config.START_PICKAXE and v9.tokens.legendary == 0
		and v9.coins.m == 0 and v9.forgeOpen == false)
	check("이주: 기존 값 그대로(블럭스 · 환생)", v9.blox.m == 3.5 and v9.blox.e == 9 and v9.rebirths.m == 4)
	check("이주: 결과가 v10 검증을 통과", (Schema.validate(v9)))
	-- 멱등: v10 변환을 한 번 더 불러도 같다(이미 있는 값은 덮지 않는다)
	v9.ores[3] = 7
	v9.forgeOpen = true
	v9.coins = { m = 1.5, e = 2 }
	v9.equipment.pickaxe.pick_r1 = { count = 2, stars = 1, enh = 3 }
	v9.equipped.pickaxe = "pick_r1"
	Migrations[9](v9)
	check("이주: 두 번 불러도 같다(광석 · 대장간 · 코인 · 장비 · 장착 그대로)", v9.ores[3] == 7 and v9.forgeOpen == true and v9.coins.m == 1.5
		and v9.equipment.pickaxe.pick_r1.count == 2 and v9.equipped.pickaxe == "pick_r1")
	local broken: any = { schemaVersion = 9, ores = "x", equipment = { pickaxe = 5 }, equipped = { pickaxe = 3 }, tokens = 0, forgeOpen = "yes", coins = 7 }
	Migrations[9](broken)
	check("이주: 꼴이 틀린 필드만 기본값으로", type(broken.ores) == "table" and type(broken.equipment.pickaxe) == "table"
		and broken.equipped.pickaxe == Config.START_PICKAXE and type(broken.tokens) == "table" and broken.forgeOpen == false and broken.coins.m == 0)
end

-- 4. 검증 거부 ---------------------------------------------------------------------------------------
do
	local function rejects(mutate: (any) -> ()): boolean
		local d = Schema.new()
		mutate(d)
		local errors = {}
		Schema.validateEconomy(d, errors)
		return #errors > 0
	end
	check("검증 거부: 광석 음수 · 소수 · 칸 수 틀림", rejects(function(d)
		d.ores[2] = -1
	end) and rejects(function(d)
		d.ores[2] = 1.5
	end) and rejects(function(d)
		d.ores[Config.ORE_COUNT + 1] = 0
	end))
	check("검증 거부: 장착이 보유에 없음 · 별 6 · 강화 11 · 개수 0", rejects(function(d)
		d.equipped.pickaxe = "pick_l1"
	end) and rejects(function(d)
		d.equipment.pickaxe[Config.START_PICKAXE].stars = L.MAX_STARS + 1
	end) and rejects(function(d)
		d.equipment.pickaxe[Config.START_PICKAXE].enh = L.MAX_ENHANCE + 1
	end) and rejects(function(d)
		d.equipment.pickaxe[Config.START_PICKAXE].count = 0
	end))
	check("검증 거부: 토큰 음수 · 코인 깨짐 · 대장간 문자열", rejects(function(d)
		d.tokens.rare = -2
	end) and rejects(function(d)
		d.coins = { m = 0 / 0, e = 0 }
	end) and rejects(function(d)
		d.forgeOpen = "yes"
	end))
end

-- 5. InventoryService 관문 ----------------------------------------------------------------------------
do
	local P = InventoryService._pure
	local d = Schema.new()
	check("광석: 더하기", P.applyChecked(d, function(x)
		return P.applyAddOres(x, { [1] = 5, [8] = 2 })
	end) and d.ores[1] == 5 and d.ores[8] == 2)
	local okTake = P.applyChecked(d, function(x)
		return P.applyTakeOres(x, { [1] = 3 })
	end)
	local okOver = P.applyChecked(d, function(x)
		return P.applyTakeOres(x, { [1] = 3, [8] = 1 })
	end)
	check("광석: 빼기 · 모자라면 거부하고 아무것도 안 바뀜", okTake and d.ores[1] == 2 and not okOver and d.ores[8] == 2)
	check("광석: 모르는 번호 · 음수 · 소수 거부", not P.applyChecked(d, function(x)
		return P.applyAddOres(x, { [Config.ORE_COUNT + 1] = 1 })
	end) and not P.applyChecked(d, function(x)
		return P.applyAddOres(x, { [2] = -1 })
	end) and not P.applyChecked(d, function(x)
		return P.applyAddOres(x, { [2] = 0.5 })
	end) and d.ores[2] == 0)
	check("토큰: 더하기 · 빼기 · 모르는 종류 거부", P.applyChecked(d, function(x)
		return P.applyAddTokens(x, { legendary = 3, next = 1 })
	end) and P.applyChecked(d, function(x)
		return P.applyTakeTokens(x, { legendary = 2 })
	end) and d.tokens.legendary == 1 and d.tokens.next == 1 and not P.applyChecked(d, function(x)
		return P.applyAddTokens(x, { gold = 1 })
	end))
	local id = Config.PICKAXES[4].id
	check("장비: 종류별로 얻기(새것 1 · 같은 것 개수 +1) · 장착", P.applyChecked(d, function(x)
		return P.applyGrantEquipment(x, "pickaxe", id)
	end) and P.applyChecked(d, function(x)
		return P.applyGrantEquipment(x, "pickaxe", id)
	end) and d.equipment.pickaxe[id].count == 2 and P.applyChecked(d, function(x)
		return P.applyEquip(x, "pickaxe", id)
	end) and d.equipped.pickaxe == id)
	check("장비: 모르는 종류 · 모르는 id · 안 가진 것 장착 거부", not P.applyChecked(d, function(x)
		return P.applyGrantEquipment(x, "sword", id)
	end) and not P.applyChecked(d, function(x)
		return P.applyGrantEquipment(x, "pickaxe", "nope")
	end) and not P.applyChecked(d, function(x)
		return P.applyEquip(x, "pickaxe", Config.PICKAXES[#Config.PICKAXES].id)
	end) and d.equipped.pickaxe == id)
	local okOpen, info1 = P.applyChecked(d, P.applyOpenForge)
	local okAgain, info2 = P.applyChecked(d, P.applyOpenForge)
	check("대장간: 열기 · 이미 열려 있으면 그대로(닫는 함수 없음)", okOpen and info1 == nil and okAgain and info2 == "already" and d.forgeOpen == true
		and (InventoryService :: any).closeForge == nil)
	-- 공개 API: 가짜 데이터로(사유 필수 · 프로필 없으면 false)
	local saved = InventoryService._deps
	local fake = Schema.new()
	local logs = {}
	InventoryService._deps = {
		getData = function(p: any)
			return if p.UserId == 1 then fake else nil
		end,
		log = function(line: string)
			table.insert(logs, line)
		end,
	}
	local p1: any = { Name = "InvTest", UserId = 1 }
	local p2: any = { Name = "NoProfile", UserId = 2 }
	local okAdd = InventoryService.addOres(p1, { [3] = 4 }, "test_add")
	local okNone = InventoryService.addOres(p2, { [3] = 4 }, "test_add")
	local okZero = InventoryService.addOres(p1, { [3] = 0 }, "test_zero")
	local readCopy = InventoryService.getOres(p1)
	if readCopy ~= nil then
		readCopy[3] = 999
	end
	local reasonErr = not pcall(InventoryService.addOres, p1, { [3] = 1 }, "")
	InventoryService._deps = saved
	check("공개: 더하면 로그 1(사유) · 프로필 없으면 false · 0개는 그대로 · 읽기는 사본 · 사유 필수", okAdd and not okNone and okZero
		and fake.ores[3] == 4 and #logs == 1 and string.find(logs[1], "test_add", 1, true) ~= nil and reasonErr)
end

-- 6. 코인 = CurrencyService 재화 ---------------------------------------------------------------------
do
	check("코인: CurrencyService 재화 목록에 있다", CurrencyService.CURRENCIES.coins == true)
	local d = Schema.new()
	local ok, updates = CurrencyService._pure.applyAdd("coins", d, { m = 2.5, e = 3 })
	check("코인: 더하면 coins만 바뀐다(블럭스 누적 · 생애 누적은 그대로)", ok and updates ~= nil and (updates :: any).coins.m == 2.5
		and (updates :: any).lifetimeBlox == nil and (updates :: any).lifeBlox == nil)
	local okSub = CurrencyService._pure.applySubtract("coins", d, { m = 1, e = 0 })
	check("코인: 잔액보다 많이 빼면 거부", not okSub)
end

print(string.format("[EconomyV2SaveTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EconomyV2SaveTests] %d test(s) failed", failed))
end

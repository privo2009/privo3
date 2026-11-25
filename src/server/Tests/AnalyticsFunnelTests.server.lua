--!strict
-- 분석 #38: 온보딩 퍼널 9단계 · 코인 경제 이벤트 · 곡괭이 종 수 · 나가면 지움 · 공식 한도. 가짜 전송(sink)으로만 — 실제로 보내지 않는다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AnalyticsConfig = require(ReplicatedStorage.Shared.Config.AnalyticsConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local Schema = require(ServerScriptService.Server.Data.Schema)
local Analytics = require(ServerScriptService.Server.Systems.Analytics)

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

local STEPS = AnalyticsConfig.ONBOARDING_STEPS

local function newWorld()
	local w: any = { clock = 1000, economy = {}, custom = {}, onboarding = {}, funnel = {} }
	w.a = Analytics.new({
		sink = {
			economy = function(player, flow, currency, amount, balance, transaction, sku, fields)
				table.insert(w.economy, { flow = flow, currency = currency, amount = amount, balance = balance, transaction = transaction, sku = sku })
			end,
			custom = function(player, name, value, fields)
				table.insert(w.custom, { name = name, value = value, fields = fields })
			end,
			funnel = function(player, step, name)
				table.insert(w.funnel, { step = step, name = name })
			end,
			onboarding = function(player, step, name)
				table.insert(w.onboarding, { step = step, name = name })
			end,
		},
		clock = function()
			return w.clock
		end,
		log = function() end,
		isPlayer = function()
			return true
		end,
		spawn = function(fn)
			fn()
		end,
		verbose = false,
	})
	return w
end

local function stepsOf(w: any): string
	local out = {}
	for _, e in ipairs(w.onboarding) do
		table.insert(out, tostring(e.step))
	end
	return table.concat(out, ",")
end

-- 1. 공식 한도 · 표 -----------------------------------------------------------------------------------
do
	local n = 0
	for _ in pairs(AnalyticsConfig.EVENTS) do
		n += 1
	end
	check("한도: 커스텀 이벤트 이름 ≤ 100 · 온보딩 9단계 ≤ 100 · 자원 2종 ≤ 5", n <= 100 and #STEPS == 9 and AnalyticsConfig.CURRENCY ~= AnalyticsConfig.CURRENCY_COINS)
	check("한도: 플레이어당 분당 상한이 120 + 20 × CCU 안(20)", AnalyticsConfig.PER_PLAYER_PER_MINUTE <= 20)
	check("이름: 단계 이름 순서(접속 → 첫 수령 → 첫 코인 → 첫 광석 → 첫 알 → 첫 환생 → 8층 대장간 → 첫 제작 → 첫 장착)",
		STEPS[1] == "Joined" and STEPS[2] == "FirstCashout" and STEPS[3] == "FirstCoin" and STEPS[4] == "FirstOre" and STEPS[5] == "FirstEgg"
			and STEPS[6] == "FirstRebirth" and STEPS[7] == "ForgeFloor8" and STEPS[8] == "FirstCraft" and STEPS[9] == "FirstEquip")
end

-- 2. 지난 단계 계산(줄지 않는 값) ---------------------------------------------------------------------------
do
	local r = Analytics._pure.funnelReached
	local d = Schema.new()
	check("계산: 새 프로필 = 1(접속)", r(d) == 1)
	d.lifetimeBlox = BigNum.new(5, 1)
	check("계산: 첫 수령 = 2", r(d) == 2)
	d.coins = BigNum.new(3, 0)
	d.ores[1] = 2
	check("계산: 코인 · 광석 = 4", r(d) == 4)
	d.forgeOpen = true
	check("계산: 대장간이 먼저 열려도 알 · 환생 전이면 4에서 멈춘다(차례 지킴)", r(d) == 4)
	d.pets.nextUid = 2
	d.coins = BigNum.new(0, 0)
	d.ores[1] = 0
	d.equipment.pickaxe.pick_c2 = { count = 1, stars = 0, enh = 0 }
	check("계산: 코인 · 광석을 다 써도 흔적(부화 · 제작)으로 지난 것으로 = 5", r(d) == 5)
	d.rebirths = BigNum.new(1, 0)
	check("계산: 환생 · 대장간 · 제작 = 8", r(d) == 8)
	d.equipped.pickaxe = "pick_c2"
	check("계산: 다른 곡괭이 장착 = 9", r(d) == 9)
	check("계산: 표가 아니면 0", r(nil) == 0)
end

-- 3. 보내기: 처음 온 사람 · 돌아온 사람 · 차례대로 · 중복 없음 --------------------------------------------------------
do
	local w = newWorld()
	local P = {}
	local d = Schema.new()
	w.a.onProfileLoaded(P, d)
	check("처음 온 사람: 접속하면 1단계 한 번", stepsOf(w) == "1")
	w.a.progressCheck(P, d)
	check("다시 확인해도 그대로(같은 단계 두 번 안 보냄)", stepsOf(w) == "1")
	d.lifetimeBlox = BigNum.new(1, 1)
	d.coins = BigNum.new(1, 0)
	d.ores[2] = 1
	d.pets.nextUid = 3
	w.a.progressCheck(P, d)
	check("여러 단계를 한꺼번에 지나면 차례대로(2 · 3 · 4 · 5)", stepsOf(w) == "1,2,3,4,5")
	check("단계 이름 그대로", w.onboarding[5].name == "FirstEgg")

	local w2 = newWorld()
	local back = Schema.new()
	back.lifetimeBlox = BigNum.new(1, 3)
	back.coins = BigNum.new(1, 0)
	back.ores[1] = 3
	w2.a.onProfileLoaded(P, back)
	check("돌아온 사람: 이미 지난 단계는 다시 안 보냄", #w2.onboarding == 0 and w2.a.progressOf(P).logged == 4)
	back.pets.nextUid = 2
	w2.a.progressCheck(P, back)
	check("돌아온 사람: 새로 지난 단계만(5)", stepsOf(w2) == "5")
end

-- 4. 곡괭이 종 수 ---------------------------------------------------------------------------------------
do
	local w = newWorld()
	local P = {}
	local d = Schema.new()
	w.a.onProfileLoaded(P, d)
	w.a.progressCheck(P, d)
	local before = #w.custom
	d.equipment.pickaxe.pick_c3 = { count = 1, stars = 0, enh = 0 }
	w.a.progressCheck(P, d)
	w.a.progressCheck(P, d)
	local sent = w.custom[before + 1]
	check("곡괭이 종 수: 늘 때 한 번(값 = 종 수)", #w.custom == before + 1 and sent ~= nil and sent.name == AnalyticsConfig.EVENTS.pickaxeKinds and sent.value == 2)
	d.equipment.pickaxe[EconomyV2Config.START_PICKAXE].count = 3
	w.a.progressCheck(P, d)
	check("곡괭이 종 수: 같은 종 사본은 안 셈", #w.custom == before + 1)
end

-- 5. 코인 경제 이벤트 -------------------------------------------------------------------------------------
do
	local w = newWorld()
	local P = {}
	for _ = 1, 50 do
		w.a.coinFlow(P, "block_break", BigNum.new(2, 0), BigNum.new(1, 2))
	end
	w.a.coinFlow(P, "pet_hatch_egg1_manual", BigNum.new(5, 1), BigNum.new(5, 1))
	w.a.bloxFlow(P, "challenge_cashout_pad", BigNum.new(3, 1), BigNum.new(3, 1))
	w.a.flush(P)
	local byKey = {}
	for _, e in ipairs(w.economy) do
		byKey[e.currency .. "/" .. e.flow .. "/" .. e.sku] = e
	end
	local src = byKey["Coins/Source/block"]
	local sink = byKey["Coins/Sink/egg"]
	local blox = byKey["Blox/Source/cashout_manual"]
	check("코인: 블록 50번은 모아서 한 번(Source · Gameplay · 합 100)", src ~= nil and src.amount == 100 and src.transaction == "Gameplay")
	check("코인: 부화는 Sink · Shop · 양수 금액", sink ~= nil and sink.amount == 50 and sink.transaction == "Shop")
	check("코인 · 블럭스는 자원 이름이 따로(묶이지 않는다)", blox ~= nil and #w.economy == 3)
	check("코인: 표에 없는 reason은 안 보냄", w.a.coinFlow(P, "mystery", BigNum.new(1, 0), BigNum.new(1, 0)) == "unclassified")
end

-- 6. 나가면 지움 -----------------------------------------------------------------------------------------
do
	local w = newWorld()
	local P = {}
	w.a.onProfileLoaded(P, Schema.new())
	w.a.coinFlow(P, "block_break", BigNum.new(1, 0), BigNum.new(1, 0))
	check("나가기 전: 플레이어별 표에 있다", w.a.trackedCount(P) >= 2)
	w.a.onRemoving(P)
	check("나가기: 플레이어별 표 전부 지움(남은 흐름은 보냄)", w.a.trackedCount(P) == 0 and #w.economy == 1)
end

print(string.format("[AnalyticsFunnelTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AnalyticsFunnelTests] %d test(s) failed", failed))
end

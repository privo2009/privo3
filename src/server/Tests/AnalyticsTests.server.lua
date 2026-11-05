--!strict
-- 분석 이벤트 래퍼 검증 (지시서 #23 A1 ~ A5 — DESIGN.md 14장). 가짜 sink · 가짜 시계로 굴린다 — 실제 AnalyticsService를 부르지 않는다.
--   흐름표(reason → 흐름 · 종류 · sku) · 흐름별 호출 1회 · 모아 보내기 · 큰 수 → blox_flow_large 분기 · 경계 ·
--   inf · NaN · 음수 거부 · 상한(창 · 플레이어별) · pcall 실패 무해 · Player 아님 건너뜀 · 처음 깬 층 중복 없음 · 도우미(환생 · 구매 · 퍼널)
--
-- ⚠️ 수치를 리터럴로 적지 않는다 — AnalyticsConfig에서 읽는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AnalyticsConfig = require(ReplicatedStorage.Shared.Config.AnalyticsConfig)
local Analytics = require(ServerScriptService.Server.Systems.Analytics)
local ChallengeService = require(ServerScriptService.Server.Systems.ChallengeService)

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

local CAP = AnalyticsConfig.PER_PLAYER_PER_MINUTE
local SAFE = AnalyticsConfig.ECONOMY_SAFE_MAX
local E = AnalyticsConfig.EVENTS

local function newWorld(opts: { failing: boolean?, notPlayer: boolean? }?)
	local o = opts or {}
	local w: any = { clock = 1000, economy = {}, custom = {}, funnel = {}, logs = {} }
	w.a = Analytics.new({
		sink = {
			economy = function(player, flow, currency, amount, balance, transaction, sku, fields)
				if o.failing then
					error("가짜 실패")
				end
				table.insert(w.economy, { player = player, flow = flow, currency = currency, amount = amount, balance = balance,
					transaction = transaction, sku = sku, fields = fields })
			end,
			custom = function(player, name, value, fields)
				if o.failing then
					error("가짜 실패")
				end
				table.insert(w.custom, { player = player, name = name, value = value, fields = fields })
			end,
			funnel = function(player, step, name)
				table.insert(w.funnel, { player = player, step = step, name = name })
			end,
		},
		clock = function()
			return w.clock
		end,
		log = function(line: string)
			table.insert(w.logs, line)
		end,
		isPlayer = function(_p)
			return not o.notPlayer
		end,
		spawn = function(fn)
			fn()
		end,
		verbose = false,
	})
	return w
end

local P1: any = { Name = "AnalyticsP1", UserId = 9201 }
local P2: any = { Name = "AnalyticsP2", UserId = 9202 }
local function big(n: number): any
	return BigNum.fromNumber(n)
end

-- 1. 설정 · 흐름표 -----------------------------------------------------------------------------------------
check("validate 통과", pcall(AnalyticsConfig.validate))
check("상한: 공식 120 + 20 × CCU 안(인원 N명 모두 상한이어도 N × 상한 ≤ 120 + 20N)", CAP * 100 <= 120 + 20 * 100 and CAP <= 20)
check("경제 이벤트 상한 < 2^53(정수 정밀도)", SAFE < 2 ^ 53)
do
	local cases = {
		{ "challenge_cashout_auto", "Source", "Gameplay", "cashout_auto" },
		{ "challenge_cashout_cashout_pad_stage_3", "Source", "Gameplay", "cashout_manual" },
		{ "reward_daily_day3", "Source", "TimedReward", "daily" },
		{ "reward_code_RELEASE", "Source", "Gameplay", "code" },
		{ "reward_onboarding_complete", "Source", "Onboarding", "onboarding" },
		{ "upgrade_punchDamage", "Sink", "Shop", "upgrade_punchDamage" },
		{ "title_roll_auto", "Sink", "Shop", "title_roll" },
		{ "aura_roll_pack1_ui", "Sink", "Shop", "aura_roll" },
		{ "pet_hatch_egg1_ui", "Sink", "Shop", "pet_hatch" },
		{ "warp_ui", "Sink", "ContextualPurchase", "warp" },
		{ "rebirth_ui", "Sink", "Gameplay", "rebirth" },
	}
	for _, c in ipairs(cases) do
		local row, sku = AnalyticsConfig.classify(c[1])
		check("흐름표: " .. c[1], row ~= nil and row.flow == c[2] and row.transaction == c[3] and sku == c[4],
			row and (row.flow .. "/" .. row.transaction .. "/" .. tostring(sku)) or "nil")
	end
	check("흐름표: 모르는 reason · 문자열 아님 → nil", AnalyticsConfig.classify("click_manual") == nil and AnalyticsConfig.classify(nil) == nil)
	local okNames = true
	for _, row in ipairs(AnalyticsConfig.BLOX_FLOWS) do
		local okEnum = pcall(function()
			return (Enum.AnalyticsEconomyTransactionType :: any)[row.transaction].Name
		end)
		local okFlow = pcall(function()
			return (Enum.AnalyticsEconomyFlowType :: any)[row.flow].Name
		end)
		okNames = okNames and okEnum and okFlow
	end
	check("흐름표의 거래 종류 · 흐름 이름은 엔진 Enum에 있다", okNames)
end

-- 2. 흐름별 호출 1회 · 모아 보내기 ---------------------------------------------------------------------------
do
	local w = newWorld()
	check("흐름 한 건 → 대기", w.a.bloxFlow(P1, "challenge_cashout_auto", big(27), big(1640)) == "queued" and #w.economy == 0)
	check("보내기 → 경제 이벤트 1회", w.a.flush(P1) == 1 and #w.economy == 1)
	local e = w.economy[1]
	check("인자: Source · Blox · 금액 · 잔액 · Gameplay · cashout_auto", e ~= nil and e.flow == "Source" and e.currency == AnalyticsConfig.CURRENCY
		and math.abs(e.amount - 27) < 1e-9 and math.abs(e.balance - 1640) < 1e-9 and e.transaction == "Gameplay" and e.sku == "cashout_auto")
	check("다시 보내기 → 더 없음", w.a.flush(P1) == 0 and #w.economy == 1)
	for _ = 1, 3 do
		w.a.bloxFlow(P1, "title_roll_auto", big(100), big(500))
	end
	w.a.bloxFlow(P1, "upgrade_punchDamage", big(50), big(450))
	check("같은 흐름 3건 + 다른 흐름 1건 → 대기 2묶음", w.a.pendingCount(P1) == 2)
	w.a.flush(P1)
	local roll
	for _, x in ipairs(w.economy) do
		if x.sku == "title_roll" then
			roll = x
		end
	end
	check("모아 보내기: 칭호 뽑기 3건 = 이벤트 1개 · 금액 합 300 · 잔액은 마지막 값", #w.economy == 3 and roll ~= nil
		and math.abs(roll.amount - 300) < 1e-9 and math.abs(roll.balance - 500) < 1e-9 and roll.flow == "Sink")
	check("금액 0 → 보내지 않음", w.a.bloxFlow(P1, "warp_ui", big(0), big(10)) == "zero" and w.a.pendingCount(P1) == 0)
	check("모르는 reason → unclassified · 대기 없음", w.a.bloxFlow(P1, "mystery_reason", big(1), big(1)) == "unclassified"
		and w.a.pendingCount(P1) == 0 and w.a.stats.unclassified == 1)
end

-- 3. tick · 나감 --------------------------------------------------------------------------------------------
do
	local w = newWorld()
	w.a.bloxFlow(P1, "warp_ui", big(5), big(10))
	w.clock += AnalyticsConfig.FLUSH_SEC - 1
	w.a.tick()
	check("tick: FLUSH_SEC 전에는 보내지 않는다", #w.economy == 0)
	w.clock += 1
	w.a.tick()
	check("tick: FLUSH_SEC가 지나면 보낸다", #w.economy == 1)
	w.a.bloxFlow(P2, "warp_ui", big(5), big(10))
	w.a.onRemoving(P2)
	check("나갈 때 남은 것을 보낸다", #w.economy == 2 and w.a.pendingCount(P2) == 0)
end

-- 4. 큰 수 → blox_flow_large -------------------------------------------------------------------------------------
do
	local w = newWorld()
	w.a.bloxFlow(P1, "challenge_cashout_auto", BigNum.new(2, 15), BigNum.new(3, 15))
	w.a.flush(P1)
	local c = w.custom[1]
	check("금액 ≥ 1e15 → 경제 이벤트 대신 blox_flow_large", #w.economy == 0 and c ~= nil and c.name == E.bloxFlowLarge)
	check("큰 수: 값 = log10 금액", c ~= nil and math.abs(c.value - (15 + math.log10(2))) < 1e-9, c and tostring(c.value))
	check("큰 수: 필드 흐름 · sku · log10 잔액 문자열", c ~= nil and c.fields ~= nil and c.fields[1] == "Source" and c.fields[2] == "cashout_auto"
		and c.fields[3] == string.format("%.3f", 15 + math.log10(3)))
	w.a.bloxFlow(P1, "upgrade_punchDamage", big(10), BigNum.new(5, 2000))
	w.a.flush(P1)
	check("금액은 작아도 잔액이 10^2000이면 큰 수 쪽 · 값 유한", #w.economy == 0 and #w.custom == 2 and w.custom[2].value == w.custom[2].value
		and math.abs(w.custom[2].value - 1) < 1e-9 and w.custom[2].fields[3] == string.format("%.3f", 2000 + math.log10(5)))
	w.a.bloxFlow(P1, "warp_ui", BigNum.new(9.99, 14), BigNum.new(9.99, 14))
	w.a.flush(P1)
	check("경계: 9.99e14 → 경제 이벤트", #w.economy == 1)
	w.a.bloxFlow(P1, "warp_ui", BigNum.new(1, 15), big(1))
	w.a.flush(P1)
	check("경계: 정확히 1e15 → 큰 수 쪽", #w.economy == 1 and #w.custom == 3)
	check("log10Big: 0은 nil · 1e2000 유한", Analytics._pure.log10Big(BigNum.new(0, 0)) == nil and Analytics._pure.log10Big(BigNum.new(1, 2000)) == 2000)
end

-- 5. inf · NaN · 음수 거부 ------------------------------------------------------------------------------------
do
	local w = newWorld()
	local nan = 0 / 0
	local bad = { { m = math.huge, e = 0 }, { m = nan, e = 0 }, { m = 1, e = math.huge }, { m = -1, e = 0 }, "12", nil }
	local allRejected = true
	for i = 1, 6 do
		if w.a.bloxFlow(P1, "warp_ui", bad[i], big(1)) ~= "rejected" then
			allRejected = false
		end
	end
	check("inf · NaN · 지수 inf · 음수 · 문자열 · nil 금액 → 거부", allRejected and w.a.pendingCount(P1) == 0)
	check("잔액이 NaN이어도 거부", w.a.bloxFlow(P1, "warp_ui", big(1), { m = nan, e = 0 }) == "rejected")
	check("커스텀 값 NaN · inf → 보내지 않음", not w.a.custom(P1, "x", nan) and not w.a.custom(P1, "x", math.huge) and #w.custom == 0)
	check("거부 수 집계 · 로그", w.a.stats.rejected == 9 and #w.logs >= 1)
end

-- 6. 상한 -------------------------------------------------------------------------------------------------
do
	local w = newWorld()
	local sent = 0
	for i = 1, CAP + 5 do
		if w.a.custom(P1, "cap_test", i) then
			sent += 1
		end
	end
	check("상한: 창 안에서 " .. CAP .. "개만 보낸다 · 넘친 5개는 버림", sent == CAP and #w.custom == CAP and w.a.stats.dropped == 5)
	check("상한: 버림은 로그로 남는다(접음)", (function()
		for _, l in ipairs(w.logs) do
			if string.find(l, "[Analytics]", 1, true) and string.find(l, "user=9201", 1, true) then
				return true
			end
		end
		return false
	end)())
	check("상한: 플레이어마다 따로", w.a.custom(P2, "cap_test", 1))
	w.clock += AnalyticsConfig.WINDOW_SEC
	check("상한: 창이 지나면 다시 보낸다", w.a.custom(P1, "cap_test", 1) and #w.custom == CAP + 2)
end

-- 7. pcall 실패 무해 · Player 아님 ------------------------------------------------------------------------------
do
	local w = newWorld({ failing = true })
	local ok = pcall(function()
		w.a.custom(P1, "fail_test", 1)
		w.a.bloxFlow(P1, "warp_ui", big(3), big(3))
		w.a.flush(P1)
	end)
	check("sink가 오류를 내도 호출자는 멀쩡하다", ok and w.a.stats.failed == 2)
	check("실패는 로그 한 줄(접음)", #w.logs >= 1 and string.find(w.logs[1], "[Analytics]", 1, true) ~= nil)
	local w2 = newWorld({ notPlayer = true })
	check("Player가 아니면 건너뛴다(테스트 가짜 플레이어 — 실제 호출 없음)", not w2.a.custom(P1, "x", 1)
		and w2.a.bloxFlow(P1, "warp_ui", big(1), big(1)) == "skipped" and #w2.custom == 0 and w2.a.stats.skipped == 2)
end

-- 8. 도우미 — 환생 · 처음 깬 층 · 자동 진행 · 구매 · 퍼널 -------------------------------------------------------
do
	local w = newWorld()
	check("환생: 값 = log10 얻은 환생 수", w.a.rebirth(P1, BigNum.new(1.4, 1)) and w.custom[1].name == E.rebirth
		and math.abs(w.custom[1].value - math.log10(14)) < 1e-9)
	check("환생: 0 · 형태 이상은 거부", not w.a.rebirth(P1, BigNum.new(0, 0)) and not w.a.rebirth(P1, nil) and #w.custom == 1)
	check("처음 깬 층: 값 = 층 번호", w.a.floorFirstClear(P1, 3) and w.custom[2].name == E.floorFirstClear and w.custom[2].value == 3)
	check("자동 진행 시작: 값 = 목표 − 안전", w.a.autoAdvanceStart(P1, 2 - 8) and w.custom[3].name == E.autoAdvanceStart and w.custom[3].value == -6)
	check("로벅스 구매: 값 1 · 필드 키 · 종류", w.a.robuxPurchase(P1, "strengthPotion", "product") and w.custom[4].name == E.robuxPurchase
		and w.custom[4].value == 1 and w.custom[4].fields[1] == "strengthPotion" and w.custom[4].fields[2] == "product")
	check("퍼널: 1회", w.a.funnel(P1, 2, "pass_gate") and #w.funnel == 1 and w.funnel[1].step == 2)
	local names = {}
	for _, n in pairs(E) do
		names[n] = true
	end
	local count = 0
	for _ in pairs(names) do
		count += 1
	end
	check("커스텀 이벤트 이름 5개 · 서로 다름(공식 한도 100)", count == 5)
end

-- 9. 처음 깬 층 중복 없음 (ChallengeService.firstClear — 환생에도 줄지 않는 bestRunDepth) ------------------------------
do
	local fc = ChallengeService._pure.firstClear
	local best = 0
	local fired = {}
	-- 1 · 2 · 3층 → 환생(maxStage는 1로) → 1 · 2층 다시 → 4층
	for _, stage in ipairs({ 1, 2, 3, 1, 2, 3, 4, 4 }) do
		local first, nextBest = fc(best, stage)
		if first then
			table.insert(fired, stage)
		end
		best = nextBest
	end
	check("처음 깬 층: 1 · 2 · 3 · 4만 한 번씩(환생 뒤 다시 깬 층은 안 보냄)", table.concat(fired, ",") == "1,2,3,4", table.concat(fired, ","))
	check("처음 깬 층: bestRunDepth가 없거나 NaN이면 0으로 본다", (fc(nil, 1)) and (fc(0 / 0, 1)))
	check("처음 깬 층: 더 깊은 기록이 있으면 낮은 층은 아님", not (fc(10, 3)) and select(2, fc(10, 3)) == 10)
end

print(string.format("[AnalyticsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AnalyticsTests] %d test(s) failed", failed))
end

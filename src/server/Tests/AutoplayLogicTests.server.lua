--!strict
-- 자동 플레이 봇 순수 로직 검증(지시서 #43 1부). Shared/AutoplayLogic · Shared/Config/AutoplayConfig.
-- 봇이 실제로 도는 것은 TEST_AUTOPLAY를 켠 Play다(HANDOFF/43/autoplay.txt) — 여기는 켜는 판정 · 정책 · 검사 함수 · 설정 관계만 잰다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AutoplayConfig = require(ReplicatedStorage.Shared.Config.AutoplayConfig)
local AutoplayLogic = require(ReplicatedStorage.Shared.AutoplayLogic)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local TestGate = require(ReplicatedStorage.Shared.TestGate)
local TestPresets = require(ReplicatedStorage.Shared.Config.TestPresets)

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

local ORES = EconomyV2Config.ORE_COUNT

-- 1. 커밋 값 · 켜는 판정 ------------------------------------------------------------------------------------
do
	local deadline = os.clock() + 15
	while not AutoplayLogic.isRegistered() and os.clock() < deadline do
		task.wait(0.1)
	end
	check("Bootstrap TEST_AUTOPLAY 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)", AutoplayLogic.isRegistered() and AutoplayLogic.getRequested() == nil,
		tostring(AutoplayLogic.getRequested()))
	check("커밋 검사 도구 목록에 TEST_AUTOPLAY(TestGate.STUDIO_FLAGS)", table.find(TestGate.STUDIO_FLAGS, "TEST_AUTOPLAY") ~= nil)

	local a, b, l, lv = AutoplayLogic.resolve(nil, nil, true)
	check("resolve: 꺼짐(nil) → 아무것도 없음", a == nil and b == nil and l == nil and lv == nil)
	a, b, _, lv = AutoplayLogic.resolve("fresh", nil, false)
	check("resolve: Studio가 아니면 무시 · warn", a == nil and b == nil and lv == "warn")
	a, b, _, lv = AutoplayLogic.resolve("nope", nil, true)
	check("resolve: 모르는 구간 → 무시 · warn", a == nil and b == nil and lv == "warn")
	a, b, _, lv = AutoplayLogic.resolve(3, nil, true)
	check("resolve: 글이 아닌 값 → 무시 · warn", a == nil and lv == "warn")
	a, b, _, lv = AutoplayLogic.resolve("min30", "hour1", true)
	check("resolve: TEST_PRESET이 구간 프리셋과 다르면 봇을 끈다", a == nil and b == nil and lv == "warn")
	local okAll = true
	for _, name in ipairs(AutoplayConfig.ORDER) do
		local sa, sb, _, slv = AutoplayLogic.resolve(name, nil, true)
		local sa2, sb2 = AutoplayLogic.resolve(name, AutoplayConfig.SEGMENTS[name].preset, true)
		okAll = okAll and sa == name and sb == AutoplayConfig.SEGMENTS[name].preset and slv == "print" and sa2 == name and sb2 == sb
	end
	check("resolve: 구간 전부(4개 — #44 pre_rebirth) → 그 구간의 프리셋(TEST_PRESET이 nil이거나 같으면)", okAll and #AutoplayConfig.ORDER == 4)
end

-- 2. 설정 관계 -------------------------------------------------------------------------------------------
do
	local ok, why = true, ""
	for _, name in ipairs(AutoplayConfig.ORDER) do
		local seg = AutoplayConfig.SEGMENTS[name]
		if seg == nil or TestPresets.Presets[seg.preset] == nil or not StageConfig.hasStage(seg.targetFloor) or seg.limitSec <= 0 then
			ok, why = false, name
		end
	end
	check("구간마다 프리셋이 있고 목표 층이 실재한다", ok, why)
	-- 서 있는 자리: 층 입구 안쪽(중심에서 STAGE_WIDTH/2 − 6)은 공격 반경 안 · 실패 줄(Z = FAIL_STAND_Z)은 반경 밖이고 챌린지 구역 안
	local inner = ArenaConfig.STAGE_WIDTH / 2 - 6
	check("봇 자리: 층 입구 안쪽은 공격 반경 안", AttackConfig.isInRange(inner))
	check("봇 자리: 실패 줄은 공격 반경 밖 · 구역 안",
		not AttackConfig.isInRange(math.sqrt(inner * inner + AutoplayConfig.FAIL_STAND_Z ^ 2))
			and AutoplayConfig.FAIL_STAND_Z < ArenaConfig.CHALLENGE_ZONE_Z_HALF - 1)
	local ClickService = require(ServerScriptService.Server.Systems.ClickService) :: any
	local limit = ClickService._pure.MANUAL_CLICK_LIMIT
	check("봇 클릭 = 초당 수동 상한 이하(ClickService)",
		AutoplayConfig.CLICKS_PER_BATCH / AutoplayConfig.CLICK_PERIOD_SEC <= limit + 1e-6, tostring(limit))
	check("봇 요청 간격 > RemoteGuard 기본 · 대장간 연타 상한(0.15초)", AutoplayConfig.REQUEST_GAP_SEC > 0.15)
	check("구간 끝: 최소 런 수 ≥ 실패 섞기 주기(실패 런이 한 번은 들어간다)", AutoplayConfig.MIN_RUNS >= AutoplayConfig.FAIL_EVERY_RUNS)
end

-- 3. 정책 ----------------------------------------------------------------------------------------------
do
	local T = StageConfig.CHALLENGE_TIMER_SEC
	check("afterClear: 진행 벽이 닫혔으면 수령", AutoplayLogic.afterClear({ canAdvance = false, timeLeft = T, stage = 1 }, T, 10) == "cashout")
	check("afterClear: 시간이 넉넉하면 진행", AutoplayLogic.afterClear({ canAdvance = true, timeLeft = T * 0.6, stage = 3 }, T, 10) == "advance")
	check("afterClear: 시간이 모자라면 수령", AutoplayLogic.afterClear({ canAdvance = true, timeLeft = T * 0.4, stage = 3 }, T, 10) == "cashout")
	check("afterClear: 목표 층을 깼으면 수령", AutoplayLogic.afterClear({ canAdvance = true, timeLeft = T, stage = 10 }, T, 10) == "cashout")
	local every = AutoplayConfig.FAIL_EVERY_RUNS
	check("실패 섞기: 런 번호가 배수일 때만", AutoplayLogic.isFailRun(every) and AutoplayLogic.isFailRun(every * 2)
		and not AutoplayLogic.isFailRun(1) and not AutoplayLogic.isFailRun(every - 1) and not AutoplayLogic.isFailRun(0))
	check("실패 섞기: 한 층을 깬 뒤에 손을 놓는다", not AutoplayLogic.failHere(0) and AutoplayLogic.failHere(1))
	local p = AutoplayConfig.REBIRTH_PATIENCE_RUNS
	check("환생: 막힌 런 수 · 비용 둘 다", AutoplayLogic.shouldRebirth(p, true) and not AutoplayLogic.shouldRebirth(p - 1, true)
		and not AutoplayLogic.shouldRebirth(p, false))
	local back = AutoplayConfig.WARP_BACK
	check("워프: 최고 층 − WARP_BACK이 2층 미만이면 안 한다", AutoplayLogic.warpTarget(back + 1, function()
		return 0
	end) == nil)
	check("워프: 싸면 최고 층 − WARP_BACK", AutoplayLogic.warpTarget(back + 10, function()
		return 0
	end) == 10)
	check("워프: 비싸면 안 한다", AutoplayLogic.warpTarget(back + 10, function()
		return AutoplayConfig.WARP_BUDGET_SHARE + 0.01
	end) == nil)
end

-- 4. 검사 함수 -------------------------------------------------------------------------------------------
do
	local function inv(t: { [number]: number }): { number }
		local out = {}
		for k = 1, ORES do
			out[k] = t[k] or 0
		end
		return out
	end
	local clean = { blox = BigNum.new(1, 3), coins = BigNum.new(0, 0), strength = BigNum.new(5, 0), lifeBlox = BigNum.new(1, 3),
		lifetimeBlox = BigNum.new(1, 3), rebirths = BigNum.new(0, 0), ores = inv({ [1] = 3 }), tokens = { rare = 2, epic = 0 } }
	check("음수: 깨끗한 데이터 → 문제 0", #AutoplayLogic.negativeProblems(clean, ORES) == 0)
	local bad = table.clone(clean)
	bad.blox = { m = -1, e = 2 }
	bad.ores = inv({ [2] = -1 })
	bad.tokens = { rare = 1.5 }
	check("음수: 블럭스 · 광석 · 토큰(소수) 셋 다 잡는다", #AutoplayLogic.negativeProblems(bad, ORES) == 3)
	check("음수: 데이터가 없으면 문제", #AutoplayLogic.negativeProblems(nil, ORES) == 1)
	check("가방: 상한 이하 통과 · 넘치면 문제", #AutoplayLogic.bagProblems(10, 10, 9) == 0 and #AutoplayLogic.bagProblems(11, 10, 10) == 1)
	check("가방: 낮은 곡괭이로 바꿔 넘친 채 그대로면 통과 · 넘친 채 늘면 문제(#34 규칙)",
		#AutoplayLogic.bagProblems(15, 10, 15) == 0 and #AutoplayLogic.bagProblems(14, 10, 15) == 0 and #AutoplayLogic.bagProblems(16, 10, 15) == 1)

	local bag = inv({ [1] = 2, [3] = 1 })
	local before = inv({ [1] = 5 })
	check("수령: 인벤토리 = 앞 + 가방이면 통과", #AutoplayLogic.runEndProblems("cashout", bag, before, inv({ [1] = 7, [3] = 1 }), 0, ORES) == 0)
	check("수령: 하나라도 어긋나면 문제", #AutoplayLogic.runEndProblems("cashout", bag, before, inv({ [1] = 7 }), 0, ORES) == 1)
	check("실패: 인벤토리 그대로 · 가방 0이면 통과", #AutoplayLogic.runEndProblems("timeout", bag, before, before, 0, ORES) == 0)
	check("실패: 가방 광석이 인벤토리로 들어갔으면 문제", #AutoplayLogic.runEndProblems("timeout", bag, before, inv({ [1] = 7, [3] = 1 }), 0, ORES) == 2)
	check("런 끝: 가방이 남으면 문제", #AutoplayLogic.runEndProblems("abandon", bag, before, before, 3, ORES) == 1)

	local IN = EconomyV2Config.CRAFT_INPUT
	local combo = { 1, 1, 2, 2, 3 }
	local o0 = inv({ [1] = 10, [2] = 4, [3] = 1 })
	local o1 = inv({ [1] = 8, [2] = 2, [3] = 0 })
	check("제작: 조합만큼 줄고 토큰이 계획대로면 통과",
		#AutoplayLogic.craftProblems(o0, o1, combo, 1, IN, { rare = 1 }, { rare = 2 }, { rare = 1 }, ORES) == 0)
	check("제작: 광석이 더 줄면 문제(종류 · 합 둘 다)",
		#AutoplayLogic.craftProblems(o0, inv({ [1] = 7, [2] = 2 }), combo, 1, IN, {}, {}, {}, ORES) == 2)
	check("제작: 토큰이 계획과 다르면 문제", #AutoplayLogic.craftProblems(o0, o1, combo, 1, IN, {}, { epic = 1 }, { rare = 1 }, ORES) == 2)
	check("제작: 조합이 CRAFT_INPUT개가 아니면 문제", #AutoplayLogic.craftProblems(o0, o0, {}, 1, IN, {}, {}, {}, ORES) >= 1)
	check("제작: 세 번(트리플) = 조합 × 3",
		#AutoplayLogic.craftProblems(inv({ [1] = 15 }), inv({}), { 1, 1, 1, 1, 1 }, 3, IN, {}, {}, {}, ORES) == 0)

	-- 환생 앞뒤(#44 pre_rebirth)
	local function snapOf(r: number, bloxM: number, bloxE: number): any
		return { rebirths = r, blox = BigNum.new(bloxM, bloxE), coins = BigNum.new(4, 5), strength = BigNum.new(5, 9),
			lifeBlox = BigNum.new(1, 10), ores = inv({ [4] = 9 }), tokens = { rare = 3 }, pickaxes = { pick_m1 = { count = 1, stars = 0, enh = 5 } },
			equipped = "pick_m1", pets = { "1:egg1_common", "2:egg2_rare" }, gyms = 10, maxStage = 19 }
	end
	local b0 = snapOf(12, 1.845494, 10)
	local cost = BigNum.new(1.6777216, 10)
	local a0 = snapOf(13, 1.6777216 * 0.1, 10)
	a0.blox = BigNum.sub(b0.blox, cost)
	a0.gyms, a0.maxStage, a0.strength, a0.lifeBlox = 11, 1, BigNum.new(0, 0), BigNum.new(0, 0)
	local ctx = { cost = cost, multRatio = 1.25, multBase = 1.25, gymsExpected = 11, strengthStart = BigNum.new(0, 0), analytics = 1 }
	check("환생 검사: 정상 환생(+1 · 블럭스 = 앞 − 비용 · 나머지 그대로 · 기구 · ×1.25 · 초기화 · 분석 1)은 문제 0",
		#AutoplayLogic.rebirthProblems(b0, a0, ctx) == 0, table.concat(AutoplayLogic.rebirthProblems(b0, a0, ctx), " / "))
	local a1 = table.clone(a0)
	a1.blox = BigNum.new(0, 0)
	a1.pets = { "1:egg1_common" }
	check("환생 검사: 나머지 블럭스를 잃거나 펫이 사라지면 잡는다", #AutoplayLogic.rebirthProblems(b0, a1, ctx) == 2)
	local ctx2 = table.clone(ctx)
	ctx2.multRatio, ctx2.analytics, ctx2.gymsExpected = 1.0, 0, 12
	check("환생 검사: 배수 · 분석 이벤트 · 기구 갱신이 틀리면 잡는다", #AutoplayLogic.rebirthProblems(b0, a0, ctx2) == 3)
	local seg = AutoplayConfig.SEGMENTS.pre_rebirth
	check("pre_rebirth 구간: 환생 먼저 · 런 1번 · 목표 층 실재 · 프리셋이 환생 비용에 닿는다", seg ~= nil and seg.rebirthFirst == true
		and seg.minRuns == 1 and StageConfig.hasStage(seg.targetFloor) and TestPresets.Presets[seg.preset] ~= nil
		and require(ReplicatedStorage.Shared.EconomyV2Logic).canRebirth(TestPresets.Presets[seg.preset].blox, TestPresets.Presets[seg.preset].rebirths))

	check("서버 루프 상한: 5%(50 ms/초)", AutoplayLogic.loopBudgetOk(49) and not AutoplayLogic.loopBudgetOk(51))
	local t = AutoplayLogic.newTally()
	check("모음: 비면 0", AutoplayLogic.tallyLine(t, 40) == "0")
	for i = 1, 30 do
		AutoplayLogic.add(t, "kind" .. (i % 3), string.rep("가", 10))
	end
	local s = AutoplayLogic.tallyLine(t, 40)
	check("모음: 개수 · 종류 · 길이 상한(utf8)", t.count == 30 and #t.order == 3 and utf8.len(s) ~= nil and (utf8.len(s) :: number) <= 40, s)
	check("봇 자신의 줄은 경고 집계에서 뺀다", AutoplayLogic.isOwnLine(AutoplayConfig.TAG .. " 서버 x") and not AutoplayLogic.isOwnLine("[ChallengeService] x"))
end

print(string.format("[AutoplayLogicTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AutoplayLogicTests] %d test(s) failed", failed))
end

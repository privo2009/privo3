--!strict
-- EconomyCandidateReport(경제 재설계 후보 측정 — 지시서 #29 단계 2)의 순수 식 검증.
-- 후보 모델(환생 비용 · 배수 · 곡괭이 · 광석 · 가방 · 제작 규칙 · 줍기 거리)이 파일 상단 설명대로 계산되는지만 본다.
-- 측정 결과(성공률 · 시간)는 보지 않는다 — 그건 리포트 Play의 [ECON] 줄이다. 게임 코드 · Config는 그대로여야 한다(고리는 비어 있다).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local SuccessRateReport = require(ServerScriptService.Server.Tools.SuccessRateReport)
local E = require(ServerScriptService.Server.Tools.EconomyCandidateReport)

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

local R, P = E.REBIRTHS, E.PICKAXES

-- 1. 고리는 비어 있고 단독 모드는 꺼져 있다(커밋 값) — 결정 모델 숫자가 그대로다
check("고리 ECON = nil · 경제 단독 모드 false · S5' 대상 그대로 · 가방 업그레이드 없음", SuccessRateReport.ECON == nil
	and SuccessRateReport.SIM.ECONOMY_SWEEP_ONLY == false and table.concat(SuccessRateReport.S5_TARGETS, ",") == "punchDamage,punchSpeed,bloxGain"
	and (UpgradeConfig.Upgrades :: any).bagCap == nil)

-- 2. 환생 비용 1000 × g^n · 배수 1 + a·n / b^n
local c0, c3 = E.rebirthCost(R.R2, 0), E.rebirthCost(R.R2, 3)
local r3 = BigNum.toRatio(c3, BigNum.fromNumber(1))
check("환생 비용: n=0 → 1000 · R2(g 2) n=3 → 8000", BigNum.eq(c0, BigNum.fromNumber(1000)) and math.abs(r3 - 8000) < 1e-6, tostring(r3))
check("환생 배수: R1(1 + 2n) n=5 → 11 · 지수(b 1.5) n=4 → 5.0625 · n=0 → 1", E.rebirthFactor(R.R1, 5) == 11
	and math.abs(E.rebirthFactor({ key = "t", g = 2, kind = "exp", a = 1.5, gain = 1 }, 4) - 5.0625) < 1e-9 and E.rebirthFactor(R.R2, 0) == 1 and E.rebirthFactor(R.R1, 0) == 1)

-- 3. 곡괭이 배수 N^(t−1) × 강화
check("곡괭이: P2(더하기 0.25) T3 · 2단계 · N 4 → 16 × 1.5 = 24 · P3(곱하기 1.15) T1 · 2단계 → 1.3225", math.abs(E.pickMult(P.P2, 4, 3, 2) - 24) < 1e-9
	and math.abs(E.pickMult(P.P3, 4, 1, 2) - 1.3225) < 1e-9)

-- 4. 광석 = HP 구간 번호
local world = WorldConfig.get(SuccessRateReport.SIM.WORLD_ID) :: WorldConfig.WorldDef
local okOre = true
for i, seg in ipairs(world.hpGrowthSegments) do
	okOre = okOre and E.oreOf(seg.from) == i and E.oreOf(seg.to) == i
end
check("광석 종류 = HP 구간(경계 양 끝 층)", okOre)

-- 5. 가방: 가득 차면 남김(leave) · 더 높은 구간이면 바꿔 줍기(swap) · 상한 없음
local bag = { 0, 0, 0 }
local a1 = E.addToBag(bag, 5, 1, 4, "leave")
local a2 = E.addToBag(bag, 5, 2, 3, "leave")
local bagS = { 4, 1, 0 }
local s1 = E.addToBag(bagS, 5, 3, 3, "swap")
local s2 = E.addToBag(bagS, 5, 1, 2, "swap")
local bagN = { 0, 0, 0 }
check("가방: leave 4 + 1(가득) · swap은 낮은 것부터 바꾼다 · 같은 구간끼리는 안 바꾼다 · 상한 없음", a1 == 4 and a2 == 1 and bag[1] == 4 and bag[2] == 1
	and s1 == 3 and bagS[1] == 1 and bagS[3] == 3 and s2 == 0 and E.addToBag(bagN, nil, 2, 50, "leave") == 50)

-- 6. 표준 제작: 다음 등급 먼저 · 같은 광석이면 아껴 두고 다른 광석이면 강화
local st = { tier = 1, step = 0, inv = { 45, 0, 0 } }
local made = E.craft(P.P2, st)
check("제작(P2 · A 45): T2(10) → T3(30) → 다음(T4)은 B라 A로 강화 1단계(4) · A 1 남음", #made == 2 and st.tier == 3 and st.step == 1 and st.inv[1] == 1,
	string.format("tier %d step %d A %d", st.tier, st.step, st.inv[1]))
local st2 = { tier = 1, step = 0, inv = { 9, 0, 0 } }
E.craft(P.P2, st2)
check("제작: 다음 등급이 같은 광석(A)이면 강화하지 않고 아껴 둔다", st2.tier == 1 and st2.step == 0 and st2.inv[1] == 9)

-- 7. 줍기 거리: 반경이 넓으면 0 · 전부 순회 ≥ 0 · 반경이 클수록 짧다
local far = E.pickDistance(10, "all", 6)
local near = E.pickDistance(10, "all", 20)
check("줍기 거리: 반경 1000 → 0 · 전부 순회는 반경 6이 20보다 길다 · 마지막 블록 ≥ 0", E.pickDistance(10, "all", 1000) == 0
	and E.pickDistance(10, "last", 1000) == 0 and far > near and near >= 0 and E.pickDistance(10, "last", 6) > 0,
	string.format("r6 %.1f · r20 %.1f", far, near))

print(string.format("[EconomyCandidateReportTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EconomyCandidateReportTests] %d test(s) failed", failed))
end

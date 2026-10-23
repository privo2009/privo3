--!strict
-- RollLogic 검증 (지시서 #10 3단계): 순차 판정의 경계(p 바로 아래 / 위) · p ≥ 1 확정 · 폴백 · 높은 등급 우선 ·
-- 확률 합이 1을 넘어도 동작 · 분포 · 깨진 입력. 난수 열을 주입해 굴린다 — 게임 RNG는 건드리지 않는다.
-- 등급 표는 테스트용 가짜 표다(Config 값이 아니다 — Config가 바뀌어도 이 성질은 같아야 한다).

local RollLogic = require(script.Parent.RollLogic)

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

-- 주어진 수를 차례로 돌려주는 난수 함수. 다 쓰면 error — 판정이 몇 번 굴렸는지까지 잰다.
local function sequence(values: { number }): (() -> number, () -> number)
	local i = 0
	return function()
		i += 1
		assert(values[i] ~= nil, "난수 열을 다 썼다")
		return values[i]
	end, function()
		return i
	end
end

local TIERS = {
	{ id = "fallback" }, -- 폴백: 확률 없음
	{ id = "a", baseChance = 0.2 },
	{ id = "b", baseChance = 0.02 },
	{ id = "c", baseChance = 0.002 },
}

-- 1. 높은 등급부터 판정한다 -----------------------------------------------------------
do
	local rnd, used = sequence({ 0.001 })
	local tier, index = RollLogic.roll(TIERS, 1, rnd)
	check("가장 높은 등급(c)이 먼저 판정된다", tier.id == "c" and index == 4 and used() == 1)
end

do
	-- c는 빗나가고(0.5 ≥ 0.002) b에서 걸린다(0.01 < 0.02). a는 보지도 않는다.
	local rnd, used = sequence({ 0.5, 0.01 })
	local tier = RollLogic.roll(TIERS, 1, rnd)
	check("빗나가면 한 단계 아래로 내려간다", tier.id == "b" and used() == 2)
end

-- 2. 경계: p 바로 아래 / p 정확히 / 위 ---------------------------------------------------
do
	local p = TIERS[4].baseChance :: number
	local below = RollLogic.roll(TIERS, 1, (sequence({ p - 1e-12 })))
	check("p 바로 아래 → 그 등급", below.id == "c")
	local at = RollLogic.roll(TIERS, 1, (sequence({ p, 0.9, 0.9, 0.9 })))
	check("p 정확히 → 빗나감 (random() < p)", at.id == "fallback")
	local above = RollLogic.roll(TIERS, 1, (sequence({ p + 1e-12, 0.9, 0.9 })))
	check("p 바로 위 → 빗나감", above.id == "fallback")
end

-- 3. 행운이 p를 키운다 · p ≥ 1이면 확정 -------------------------------------------------------
do
	local luck = 3
	local p = (TIERS[4].baseChance :: number) * luck
	local hit = RollLogic.roll(TIERS, luck, (sequence({ p - 1e-9 })))
	check("행운 ×3: 기본 확률로는 빗나갈 값이 걸린다", hit.id == "c" and p - 1e-9 > (TIERS[4].baseChance :: number))
	check("chance = 기본 × 행운", math.abs(RollLogic.chance(TIERS[4], luck) - p) < 1e-15)

	local sure = 1 / (TIERS[4].baseChance :: number)
	local tier = RollLogic.roll(TIERS, sure, (sequence({ 0.999999 })))
	check("p ≥ 1이면 그 등급 확정 (난수 0.999999도 걸린다)", tier.id == "c")
end

-- 4. 폴백 ----------------------------------------------------------------------------------
do
	local rnd, used = sequence({ 0.99, 0.99, 0.99 })
	local tier, index = RollLogic.roll(TIERS, 1, rnd)
	check("전부 빗나가면 폴백(tiers[1])", tier.id == "fallback" and index == 1)
	check("폴백은 난수를 쓰지 않는다 (등급 수 - 1번만 굴림)", used() == #TIERS - 1)
end

do
	local only = { { id = "solo" } }
	local tier = RollLogic.roll(only, 1, function(): number
		error("굴리면 안 된다")
	end)
	check("등급이 폴백 하나뿐이면 굴리지 않고 폴백", tier.id == "solo")
end

do
	local ok = pcall(RollLogic.roll, {}, 1, function(): number
		return 0
	end)
	check("빈 등급 표는 error (호출자 버그)", not ok)
end

-- 5. 확률 합이 1을 넘어도 동작한다 (DESIGN 6장) ----------------------------------------------------
do
	local fat = { { id = "f" }, { id = "x", baseChance = 0.8 }, { id = "y", baseChance = 0.8 } }
	local hitY = RollLogic.roll(fat, 1, (sequence({ 0.1 })))
	local hitX = RollLogic.roll(fat, 1, (sequence({ 0.9, 0.1 })))
	local miss = RollLogic.roll(fat, 1, (sequence({ 0.9, 0.9 })))
	check("합 1.6: 높은 등급 우선", hitY.id == "y")
	check("합 1.6: 빗나가면 다음", hitX.id == "x")
	check("합 1.6: 다 빗나가면 폴백", miss.id == "f")
end

-- 6. 깨진 행운 · 확률 ------------------------------------------------------------------------
do
	for _, bad in ipairs({ 0 / 0, -1, 0 }) do
		local rnd, used = sequence({ 0 })
		local tier = RollLogic.roll(TIERS, bad, rnd)
		check("행운 " .. tostring(bad) .. " → 폴백, 굴리지 않는다", tier.id == "fallback" and used() == 0)
	end
	local tier = RollLogic.roll(TIERS, (("3" :: any) :: number), (sequence({})))
	check("행운이 숫자가 아니면 폴백", tier.id == "fallback")
	check("확률이 0 이하인 등급은 굴리지 않는다", RollLogic.chance({ baseChance = -0.5 }, 1) == 0 and RollLogic.chance({}, 1) == 0)
end

-- 7. 분포 --------------------------------------------------------------------------------
do
	local d = RollLogic.distribution(TIERS, 1)
	local sum = 0
	for i = 1, #TIERS do
		sum += d[i]
	end
	local pc = TIERS[4].baseChance :: number
	local pb = TIERS[3].baseChance :: number
	check("분포 합 = 1", math.abs(sum - 1) < 1e-12)
	check("분포: 가장 높은 등급 = 기본 확률", math.abs(d[4] - pc) < 1e-15)
	check("분포: 다음 등급 = (1 - 위) × 기본", math.abs(d[3] - (1 - pc) * pb) < 1e-15)
	local sure = RollLogic.distribution(TIERS, 1 / pc)
	check("분포: p ≥ 1인 등급이 1, 아래는 0", math.abs(sure[4] - 1) < 1e-12 and sure[1] == 0 and sure[2] == 0)
end

-- 8. 결정성 · 표본 (같은 seed → 같은 결과, 많이 굴리면 분포에 가깝다) ---------------------------------------
do
	local function run(seed: number): { number }
		local r = Random.new(seed)
		local counts = { 0, 0, 0, 0 }
		for _ = 1, 20000 do
			local _, i = RollLogic.roll(TIERS, 1, function()
				return r:NextNumber()
			end)
			counts[i] += 1
		end
		return counts
	end
	local a, b = run(7), run(7)
	check("같은 seed → 같은 결과", a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4])
	local d = RollLogic.distribution(TIERS, 1)
	local ratioA = a[2] / 20000
	check("표본 20000회: 등급 a 비율이 분포 ±1%p 안", math.abs(ratioA - d[2]) < 0.01, string.format("%.4f vs %.4f", ratioA, d[2]))
end

print(string.format("[RollLogicTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RollLogicTests] %d test(s) failed", failed))
end

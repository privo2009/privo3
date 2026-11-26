--!strict
-- 이동 익스플로잇 대비 검증(지시서 #43 2부 — Server/Systems/MovementGuard · Shared/Config/MovementGuardConfig).
-- 정상 걷기 · 점프 · 낙하 통과 / 순간이동 · 3배 속도 무시 / 게임 순간이동 직후 통과 / 의심 동안 줍기 · 공격 건너뜀 / 설정에서 읽음.
-- 실물 오탐 0은 자동 플레이 봇(TEST_AUTOPLAY) Play로 본다 — HANDOFF/43/autoplay.txt.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.MovementGuardConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local Systems = ServerScriptService.Server.Systems
local MovementGuard = require(Systems.MovementGuard) :: any
local AttackService = require(Systems.AttackService) :: any
local OreDropService = require(Systems.OreDropService) :: any

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

local P = MovementGuard._pure
local DT = Config.SAMPLE_SEC
local WALK = 16 -- 레벨 0 이동 속도(로블록스 기본 · SpeedService 레벨 0 상한)
local GRAV = 196.2 -- 로블록스 기본 중력

-- 표본 열을 하나씩 먹여 의심이 몇 번 났는지 센다
local function feed(positions: { Vector3 }, maxSpeed: number, state: any?): (number, any)
	local s = state or P.newState()
	local hits = 0
	for i, pos in ipairs(positions) do
		local hit = P.observe(s, { pos = pos, t = i * DT }, maxSpeed)
		if hit then
			hits += 1
		end
	end
	return hits, s
end

-- 1. 정상 움직임은 통과 ------------------------------------------------------------------------------------
do
	local walk = {}
	for i = 1, 40 do
		table.insert(walk, Vector3.new(i * WALK * DT, 3, 0))
	end
	check("정상: 레벨 이동 속도로 10초 걷기 → 의심 0", (feed(walk, WALK)) == 0)

	local fast = {}
	for i = 1, 40 do
		table.insert(fast, Vector3.new(i * 60 * DT, 3, 0))
	end
	check("정상: 높은 레벨(상한 60)로 달리기 → 의심 0", (feed(fast, 60)) == 0)

	-- 걸으며 점프(초속 50 — 기본 JumpPower) · 내려오기
	local jump = {}
	for i = 1, 16 do
		local t = i * DT
		local y = 3 + math.max(0, 50 * t - 0.5 * GRAV * t * t)
		table.insert(jump, Vector3.new(i * WALK * DT, y, 0))
	end
	check("정상: 걸으며 점프 · 착지 → 의심 0", (feed(jump, WALK)) == 0)

	-- 높은 곳(20 studs)에서 자유 낙하
	local fall = {}
	for i = 1, 8 do
		local t = i * DT
		table.insert(fall, Vector3.new(0, math.max(3, 23 - 0.5 * GRAV * t * t), 0))
	end
	check("정상: 20 studs 자유 낙하 → 의심 0", (feed(fall, WALK)) == 0)

	-- 복제 흔들림: 한 주기에 두 주기 몫이 몰려 들어오고 다음 주기는 0
	local jitter = { Vector3.new(0, 3, 0), Vector3.new(2 * WALK * DT, 3, 0), Vector3.new(2 * WALK * DT, 3, 0), Vector3.new(4 * WALK * DT, 3, 0) }
	check("정상: 복제가 몰려 오는 흔들림(한 주기 2배) → 의심 0", (feed(jitter, WALK)) == 0)
end

-- 2. 순간이동 · 3배 속도는 걸린다 --------------------------------------------------------------------------------
do
	local tp = { Vector3.new(0, 3, 0), Vector3.new(1, 3, 0), Vector3.new(150, 3, 0) }
	local hits, s = feed(tp, WALK)
	check("순간이동 150 studs → 의심 1 · 그 뒤 HOLD 동안 믿지 않음", hits == 1 and not P.trusted(s, 3 * DT + Config.HOLD_SEC * 0.5)
		and P.trusted(s, 3 * DT + Config.HOLD_SEC + 0.01))
	local speedy = {}
	for i = 1, 12 do
		table.insert(speedy, Vector3.new(i * WALK * 3 * DT, 3, 0))
	end
	check("3배 속도(레벨 0) → 걸린다", (feed(speedy, WALK)) >= 1)
	local speedyHigh = {}
	for i = 1, 12 do
		table.insert(speedyHigh, Vector3.new(i * 60 * 3 * DT, 3, 0))
	end
	check("3배 속도(상한 60) → 걸린다", (feed(speedyHigh, 60)) >= 1)
	local up = { Vector3.new(0, 3, 0), Vector3.new(0, 40, 0) }
	local _, why = P.evaluate({ pos = up[1], t = 0 }, { pos = up[2], t = DT }, WALK)
	check("위로 순간이동(37 studs/주기) → 사유 up", why == "up", tostring(why))
	local ok2, why2 = P.evaluate({ pos = Vector3.new(0, 3, 0), t = 0 }, { pos = Vector3.new(0, 3, 0), t = 0 }, WALK)
	check("같은 시각 표본(dt 0)은 판정하지 않는다", ok2 and why2 == nil)
end

-- 3. 게임 순간이동 직후는 통과 -----------------------------------------------------------------------------------
do
	local s = P.newState()
	P.observe(s, { pos = Vector3.new(500, 3, 0), t = 1 }, WALK)
	P.markTeleportState(s, 1.1) -- 서버가 스폰으로 옮겼다
	local hit1 = P.observe(s, { pos = Vector3.new(-200, 3, 0), t = 1.25 }, WALK) -- 새 자리
	local hit2 = P.observe(s, { pos = Vector3.new(500, 3, 0), t = 1.5 }, WALK) -- 오는 중이던 옛 자리 복제
	local hit3 = P.observe(s, { pos = Vector3.new(-200, 3, 0), t = 1.75 }, WALK)
	local hit4 = P.observe(s, { pos = Vector3.new(-200 + WALK * DT, 3, 0), t = 1.1 + Config.TELEPORT_GRACE_SEC + 0.1 }, WALK)
	check("게임 순간이동: 유예 동안 옛 자리 · 새 자리가 섞여도 통과", not hit1 and not hit2 and not hit3)
	check("게임 순간이동: 유예가 끝나면 다시 걷기로 잰다(통과)", not hit4 and P.trusted(s, 2))
	local hit5 = P.observe(s, { pos = Vector3.new(400, 3, 0), t = 1.1 + Config.TELEPORT_GRACE_SEC + 0.35 }, WALK)
	check("게임 순간이동: 유예가 끝난 뒤의 순간이동은 걸린다", hit5)
	local s2 = P.newState()
	P.observe(s2, { pos = Vector3.new(0, 3, 0), t = 1 }, WALK)
	P.observe(s2, nil, WALK) -- 캐릭터 없음(죽음)
	check("캐릭터가 없어졌다 생기면 기준점을 다시 잡는다(리스폰 통과)", not P.observe(s2, { pos = Vector3.new(-200, 3, 0), t = 1.5 }, WALK))
	-- 공개 함수(가짜 Player): markTeleport → sample 순간이동 통과 · isTrusted
	local fp: any = { Name = "MoveGuardTest", UserId = 4301 }
	MovementGuard._reset(fp)
	local before = MovementGuard.suspectCount()
	MovementGuard.sample(fp, Vector3.new(0, 3, 0), 100, WALK)
	MovementGuard.sample(fp, Vector3.new(300, 3, 0), 100 + DT, WALK)
	check("공개 sample: 순간이동이면 의심 수 +1", MovementGuard.suspectCount() == before + 1)
	MovementGuard._reset(fp)
	check("공개 isTrusted: 기록이 없으면 믿는다", MovementGuard.isTrusted(fp))
end

-- 4. 의심 동안 공격 · 줍기를 건너뛴다 ----------------------------------------------------------------------------
do
	local origin = BlockLayout.getStageOrigin(1)
	local calls = 0
	local deps = {
		getRunState = function()
			return { stage = 1, cleared = false }
		end,
		getStrength = function()
			return BigNum.new(1, 3)
		end,
		getPosition = function()
			return origin
		end,
		applyDamage = function()
			calls += 1
			return {}
		end,
		getDamageMultiplier = function()
			return 1
		end,
		isMoveTrusted = function()
			return false
		end,
	}
	local fp: any = { Name = "MoveGuardAttack", UserId = 4302 }
	local out = AttackService._pure.runPunch(deps, fp)
	check("공격: 이동 의심이면 move_suspect · applyDamage 0번", out.result == AttackService.RESULT_MOVE_SUSPECT and calls == 0, out.result)
	deps.isMoveTrusted = function()
		return true
	end
	out = AttackService._pure.runPunch(deps, fp)
	check("공격: 믿으면 그대로 친다", out.result == AttackService.RESULT_OK and calls == 1, out.result)

	local trustedNow = false
	local sent = {}
	local w = {
		addCoins = function()
			return true, BigNum.new(0, 0)
		end,
		getCoins = function()
			return BigNum.new(0, 0)
		end,
		addOres = function()
			return true
		end,
		getOres = function()
			return EconomyV2Logic.newInv()
		end,
		isForgeOpen = function()
			return true
		end,
		openForge = function()
			return true
		end,
		getEquipped = function()
			return EconomyV2Config.START_PICKAXE
		end,
		ownsAutoAdvance = function()
			return false
		end,
		ownsBigBag = function()
			return false
		end,
		rootPosition = function()
			return Vector3.new(0, 3, 0)
		end,
		isMoveTrusted = function()
			return trustedNow
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
		rand = function()
			return 0 -- 소수 몫도 언제나 하나 더 — 블록마다 드롭이 있다
		end,
	}
	local saved = OreDropService._deps
	OreDropService._deps = w
	local p: any = { Name = "MoveGuardPickup", UserId = 4303 }
	OreDropService._reset(p)
	OreDropService.onStageEnter(p, 1, "start")
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) })
	OreDropService.pickupTick(p)
	local held = OreDropService.bagUsed(p)
	trustedNow = true
	OreDropService.pickupTick(p)
	local after = OreDropService.bagUsed(p)
	check("줍기: 이동 의심 동안은 줍지 않고 · 믿으면 줍는다", held == 0 and after > 0, string.format("%d → %d", held, after))
	OreDropService._reset(p)
	OreDropService._deps = saved
end

-- 5. 설정에서 읽는다(숫자를 코드에 박지 않는다) ---------------------------------------------------------------
do
	local ok = true
	for _, key in ipairs({ "SAMPLE_SEC", "SPEED_MARGIN", "SLACK_STUDS", "UP_SPEED_MAX", "FALL_SPEED_MAX", "HOLD_SEC", "TELEPORT_GRACE_SEC" }) do
		if type((Config :: any)[key]) ~= "number" or (Config :: any)[key] <= 0 then
			ok = false
		end
	end
	check("설정: 숫자 7개가 MovementGuardConfig에 있고 양수", ok)
	-- 여유를 크게 바꾸면 판정이 따라 바뀐다(코드에 상수가 없다는 증거)
	local saved = Config.SPEED_MARGIN
	Config.SPEED_MARGIN = 1000
	local okBig = P.evaluate({ pos = Vector3.zero, t = 0 }, { pos = Vector3.new(150, 0, 0), t = DT }, WALK)
	Config.SPEED_MARGIN = saved
	check("설정: 여유를 키우면 150 studs/주기도 통과 — 판정이 설정을 읽는다", okBig)
end

print(string.format("[MovementGuardTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[MovementGuardTests] %d test(s) failed", failed))
end

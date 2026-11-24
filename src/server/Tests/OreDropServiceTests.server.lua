--!strict
-- 새 경제 드롭 · 줍기 · 가방 · 코인 · 대장간 열림 검증(지시서 #32 — 플래그 ECONOMY_V2 뒤). 전역 플래그는 건드리지 않는다.
-- OreDropService._deps를 기록용 가짜로 바꿔 끼우고(끝나면 되돌린다) 가짜 플레이어 표로 굴린다 — 프로필 · RemoteEvent를 쓰지 않는다.
--   줍기 판정(반경 · 가방 자리 · 바꿔 줍기 · 바닥에 남기) · 층 이동 시 드롭 사라짐(가방 그대로) · 수령 때 옮기기 · 실패 · 이탈 때 비우기 ·
--   자동 진행 줍기(거리 무관 · 상한 그대로) · 코인(블록마다 · 실패해도 유지) · 대장간(그 층에서 열림 · 한 번 · 환생 뒤 1층에서도 유지) ·
--   첫 광석 안내 한 번 · ChallengeService 고리(nil이면 아무것도 안 부름 · 걸면 시작 · 깨짐 · 진행 · 끝을 부름)
-- 숫자는 Config에서 읽는다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local OreDropService = require(ServerScriptService.Server.Systems.OreDropService)
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

local P = OreDropService._pure
local R = Config.PICKUP_RADIUS

-- 1. 순수: 줍기 판정 ----------------------------------------------------------------------------------
do
	local s = P.newRunEcon(1)
	local cap = 3
	local function put(id: number, ore: number, x: number)
		s.drops[id] = { id = id, ore = ore, position = Vector3.new(x, 0, 0) }
	end
	put(1, 1, R - 0.5)
	put(2, 1, R + 0.5)
	local picked = P.pickupPass(s, cap, Vector3.new(0, 3, 0), R, false)
	check("줍기: 반경 안만 줍는다(높이는 보지 않는다 — 수평 거리)", #picked == 1 and picked[1] == 1 and s.drops[2] ~= nil and s.bag[1] == 1)
	put(3, 1, 0)
	put(4, 1, 0)
	put(5, 1, 0)
	P.pickupPass(s, cap, Vector3.new(0, 0, 0), R, false)
	check("줍기: 가방 자리만큼만 · 넘친 것은 바닥에 남는다", P.bagUsed(s.bag) == cap and s.drops[5] ~= nil)
	put(6, 4, 0)
	local swap = P.pickupPass(s, cap, Vector3.new(0, 0, 0), R, false)
	check("가득 찼을 때: 더 좋은 광석이면 바꿔 줍고 낮은 것은 사라진다", table.find(swap, 6) ~= nil and s.bag[4] == 1 and s.bag[1] == cap - 1
		and P.bagUsed(s.bag) == cap)
	put(7, 1, 0)
	local none = P.pickupPass(s, cap, Vector3.new(0, 0, 0), R, false)
	check("가득 찼을 때: 가장 낮은 것보다 좋지 않으면 바닥에 남는다", #none == 0 and s.drops[7] ~= nil)
	local all = P.newRunEcon(1)
	all.drops[1] = { id = 1, ore = 2, position = Vector3.new(500, 0, 0) }
	all.drops[2] = { id = 2, ore = 2, position = Vector3.new(-500, 0, 0) }
	local got = P.pickupPass(all, 1, nil, R, true)
	check("자동 진행: 거리와 상관없이 줍되 가방 상한은 그대로", #got == 1 and P.bagUsed(all.bag) == 1)
	local order = P.newRunEcon(1)
	order.drops[1] = { id = 1, ore = 1, position = Vector3.zero }
	order.drops[2] = { id = 2, ore = 3, position = Vector3.zero }
	local first = P.pickupPass(order, 1, Vector3.zero, R, false)
	check("줍기: 한 번에 여럿이면 높은 광석부터", first[1] == 2 and order.bag[3] == 1)
end

-- 2. 순수: 드롭 · 층 · 수령 · 실패 · 코인 · 대장간 ------------------------------------------------------
do
	local s = P.newRunEcon(1)
	local r = Random.new(32)
	local stage = Config.ORE_BANDS[2].from
	local made = P.spawnDrops(s, stage, { Vector3.new(10, 5, 0), Vector3.new(20, 5, 0) }, function()
		return r:NextNumber()
	end)
	local inRange = #made > 0
	for _, d in ipairs(made) do
		inRange = inRange and d.ore == L.oreOf(stage) and d.position.Y == 0
			and math.min((d.position - Vector3.new(10, 0, 0)).Magnitude, (d.position - Vector3.new(20, 0, 0)).Magnitude) <= Config.DROP_SCATTER + 1e-6
	end
	check("드롭: 그 층 광석 · 깨진 블록 근처 바닥(Y 0) · 블록당 기대값(하위 1 이상)", inRange and #made >= 2 * math.floor(L.dropsPerBlock(L.oreOf(stage))))
	s.bag[2] = 3
	P.enterStage(s, stage + 1)
	check("층 이동: 바닥 드롭은 사라지고 가방은 그대로", next(s.drops) == nil and s.bag[2] == 3 and s.stage == stage + 1)
	local counts = P.takeBag(s)
	check("수령: 가방 → 개수표(0 빼고) · 가방 비움", counts[2] == 3 and counts[1] == nil and P.bagUsed(s.bag) == 0)
	s.bag[5] = 4
	s.drops[1] = { id = 1, ore = 5, position = Vector3.zero }
	check("실패 · 이탈: 가방 · 바닥 비움 · 잃은 수", P.discard(s) == 4 and P.bagUsed(s.bag) == 0 and next(s.drops) == nil)
	local c = P.coinsFor(7, 3)
	check("코인: 블록 수 × 층 코인(EconomyV2Logic.coinPerBlock)", BigNum.eq(c, BigNum.mul(L.coinPerBlock(7), BigNum.fromNumber(3))))
	local need = Config.FORGE_UNLOCK_STAGE :: number
	check("대장간: 그 층 미만은 안 열림 · 그 층 이상이면 열림 · 이미 열렸으면 다시 열지 않음", not P.opensForge(false, need - 1)
		and P.opensForge(false, need) and P.opensForge(false, need + 5) and not P.opensForge(true, need) and not P.opensForge(true, 1))
end

-- 3. 서비스 흐름(가짜 deps) --------------------------------------------------------------------------
local function fakeWorld(opts: { auto: boolean?, inv: { number }? }?)
	local o = opts or {}
	local w: any = { sent = {}, coins = BigNum.new(0, 0), ores = o.inv or L.newInv(), forgeOpen = false, opened = 0, root = Vector3.zero, added = {} }
	w.deps = {
		addCoins = function(_p, amount, _reason)
			w.coins = BigNum.add(w.coins, amount)
			return true, w.coins
		end,
		getCoins = function()
			return w.coins
		end,
		addOres = function(_p, counts, reason)
			table.insert(w.added, { counts = counts, reason = reason })
			for k, n in pairs(counts) do
				w.ores[k] += n
			end
			return true
		end,
		getOres = function()
			return table.clone(w.ores)
		end,
		isForgeOpen = function()
			return w.forgeOpen
		end,
		openForge = function()
			w.forgeOpen = true
			w.opened += 1
			return true
		end,
		getEquipped = function()
			return Config.START_PICKAXE
		end,
		ownsAutoAdvance = function()
			return o.auto == true
		end,
		ownsBigBag = function()
			return false
		end,
		rootPosition = function()
			return w.root
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
		rand = function()
			return 0.5
		end,
	}
	function w.kinds(kind: string): number
		local n = 0
		for _, p in ipairs(w.sent) do
			if p.kind == kind then
				n += 1
			end
		end
		return n
	end
	return w
end

local savedDeps = OreDropService._deps
do
	local w = fakeWorld()
	OreDropService._deps = w.deps
	local p: any = { Name = "OreTestA", UserId = 3201 }
	OreDropService._reset(p)
	OreDropService.onStageEnter(p, 1, "start")
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0), Vector3.new(1, 0, 0) })
	check("흐름: 블록이 깨지면 드롭 신호 · 코인이 바로 들어온다", w.kinds("drops") == 1 and w.kinds("coins") == 1
		and BigNum.eq(w.coins, P.coinsFor(1, 2)))
	OreDropService.pickupTick(p)
	local st = OreDropService._state(p) :: any
	local bagNow = P.bagUsed(st.bag)
	check("흐름: 가까우면 서버 폴링이 줍는다 · 가방 신호 · 첫 광석이면 대장간 안내 한 번", bagNow > 0 and w.kinds("picked") == 1
		and w.kinds("forge_hint") == 1)
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0) })
	OreDropService.pickupTick(p)
	check("흐름: 안내는 한 번만", w.kinds("forge_hint") == 1)
	-- 실패: 가방을 잃고 코인은 그대로
	local coinsBefore = w.coins
	OreDropService.onRunEnded(p, "timeout")
	check("실패: 가방을 비운다(인벤토리로 안 감) · 코인은 그대로", #w.added == 0 and OreDropService._state(p) == nil and BigNum.eq(w.coins, coinsBefore)
		and w.kinds("bag") == 1)
	-- 수령: 가방 → 인벤토리
	OreDropService.onStageEnter(p, 1, "start")
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0) })
	OreDropService.pickupTick(p)
	local inBag = P.bagUsed((OreDropService._state(p) :: any).bag)
	OreDropService.onRunEnded(p, "cashout")
	check("수령: 가방 광석이 인벤토리로(InventoryService 경로 · 사유)", inBag > 0 and #w.added == 1 and w.added[1].reason == "cashout_bag"
		and w.ores[L.oreOf(1)] == inBag)
	-- 이탈(환생 · 사망)도 실패와 같다
	OreDropService.onStageEnter(p, 1, "start")
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0) })
	OreDropService.pickupTick(p)
	OreDropService.onRunEnded(p, "abandon")
	check("이탈(환생 · 사망): 가방을 비운다", #w.added == 1)
	-- 멀면 안 줍는다 · 층 이동 시 바닥 드롭 사라짐
	OreDropService.onStageEnter(p, 1, "start")
	w.root = Vector3.new(R * 3, 0, 0)
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0) })
	OreDropService.pickupTick(p)
	local s2 = OreDropService._state(p) :: any
	local onFloor = next(s2.drops) ~= nil and P.bagUsed(s2.bag) == 0
	OreDropService.onStageEnter(p, 2, "advance")
	check("흐름: 멀면 안 줍는다 · 다음 층으로 가면 바닥 드롭 사라짐(clear 신호)", onFloor and next(s2.drops) == nil and w.kinds("clear") >= 1)
	OreDropService._reset(p)
end
do
	local w = fakeWorld({ auto = true })
	OreDropService._deps = w.deps
	local p: any = { Name = "OreTestAuto", UserId = 3202 }
	OreDropService._reset(p)
	OreDropService.onStageEnter(p, 1, "start")
	w.root = Vector3.new(9999, 0, 0)
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0) })
	OreDropService.pickupTick(p)
	check("자동 진행 보유자: 멀어도 전부 줍는다", P.bagUsed((OreDropService._state(p) :: any).bag) > 0)
	OreDropService._reset(p)
end
do
	local w = fakeWorld({ inv = (function()
		local t = L.newInv()
		t[1] = 3
		return t
	end)() })
	OreDropService._deps = w.deps
	local p: any = { Name = "OreTestForge", UserId = 3203 }
	OreDropService._reset(p)
	OreDropService.onStageEnter(p, 1, "start")
	OreDropService.onBlocksDestroyed(p, 1, { Vector3.new(0, 0, 0) })
	OreDropService.pickupTick(p)
	check("안내: 인벤토리에 광석이 이미 있으면 띄우지 않는다", w.kinds("forge_hint") == 0)
	local need = Config.FORGE_UNLOCK_STAGE :: number
	OreDropService.onStageEnter(p, need - 1, "advance")
	local before = w.opened
	OreDropService.onStageEnter(p, need, "advance")
	check("대장간: 그 층에 처음 도달하면 열림 저장 · 알림", before == 0 and w.opened == 1 and w.forgeOpen and w.kinds("forge_open") == 1)
	OreDropService.onStageEnter(p, need + 1, "advance")
	OreDropService.onRunEnded(p, "abandon") -- 환생(이탈)
	OreDropService.onStageEnter(p, 1, "start") -- 환생 뒤 1층부터
	OreDropService.onStageEnter(p, need, "advance")
	check("대장간: 영구 — 환생 뒤 1층에서도 열려 있고 다시 열지 않는다", w.forgeOpen and w.opened == 1 and w.kinds("forge_open") == 1)
	OreDropService._reset(p)
end
OreDropService._deps = savedDeps

-- 4. ChallengeService 고리 ---------------------------------------------------------------------------
do
	check("고리: 커밋 상태(플래그 꺼짐)에서는 걸려 있지 않다", ChallengeService.economyHooks == nil or Config.ECONOMY_V2)
	local savedHooks = ChallengeService.economyHooks
	local savedReturn = ChallengeService._deps.returnToSpawn
	ChallengeService._deps.returnToSpawn = function() end
	local p: any = { Name = "OreHookTest", UserId = 3204 }
	local calls = {}
	ChallengeService.economyHooks = {
		onStageEnter = function(pl, stage, reason)
			if pl == p then
				table.insert(calls, "enter:" .. stage .. ":" .. reason)
			end
		end,
		onBlocksDestroyed = function(pl, stage, positions)
			if pl == p then
				table.insert(calls, "broken:" .. stage .. ":" .. #positions)
			end
		end,
		onRunEnded = function(pl, reason)
			if pl == p then
				table.insert(calls, "end:" .. reason)
			end
		end,
	}
	ChallengeService.startRun(p, 1)
	ChallengeService.applyDamage(p, Vector3.zero, BigNum.new(1, 200))
	ChallengeService.advance(p, "test")
	ChallengeService.abandonRun(p)
	ChallengeService.economyHooks = function() end :: any -- 던지는 고리 — 런은 그대로 가야 한다
	local okThrow = pcall(function()
		ChallengeService.startRun(p, 1)
		ChallengeService.abandonRun(p)
	end)
	ChallengeService.economyHooks = savedHooks
	ChallengeService._deps.returnToSpawn = savedReturn
	local blocks = StageConfig.getBlockCount(1)
	check("고리: 시작 · 깨짐(깨진 블록 자리 전부) · 진행 · 끝 순서로 부른다", calls[1] == "enter:1:start" and calls[2] == "broken:1:" .. blocks
		and calls[3] == "enter:2:advance" and calls[4] == "end:abandon", table.concat(calls, ","))
	check("고리: 고리가 던져도 런은 그대로(pcall)", okThrow)
end

print(string.format("[OreDropServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[OreDropServiceTests] %d test(s) failed", failed))
end

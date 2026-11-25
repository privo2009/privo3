--!strict
-- 서버 루프 12명 측정 도구(지시서 #38 4단계 — Studio 전용 · TestGate). MCP로 12명 서버를 띄울 수 없어서
-- 가짜 플레이어 12명(가짜 프로필 — ProfileManager._attachTestProfile · 실제 저장소에 닿지 않는다)으로 실물 서비스 함수를 돌려
-- 틱 하나(12명 전부)에 드는 시간을 잰다. 켜는 곳: Bootstrap PERF_REPORT_ENABLED(커밋 값 false).
-- 결과 줄 "[PERF] …" · 끝 줄 "[PERF] ===== 끝". 읽는 법 · 정한 상한 → docs/TUNING.md "서버 성능(#38)".
--
-- 재는 것(줄마다 ms/틱 = 12명 한 바퀴 · ms/초 = 그 루프 주기로 1초 동안):
--   줍기 폴링 0.25초(바닥 드롭 16개 · 반경 밖 — 전부 훑는 최악) · 안내 폴링 0.5초 · 자동 제작 0.25초(매 틱 제작 — 최악) ·
--   자동 부화 0.25초 · 공격(펀치 1회 · 블록 데미지 — 12명이 초당 5번씩) · 블록 깨짐 1회(드롭 · 코인) ·
--   분석 진행 확인 2초 · 입구 문(RemoteGuard) 메시지 1개

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)

local PerfReport = {}

PerfReport.PLAYERS = 12
PerfReport.ITERS = 200

local function noop() end

function PerfReport.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	local Systems = script.Parent.Parent.Systems
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	local Schema = require(script.Parent.Parent.Data.Schema)
	local CurrencyService = require(Systems.CurrencyService)
	local InventoryService = require(Systems.InventoryService)
	local OreDropService = require(Systems.OreDropService)
	local OnboardingTipsService = require(Systems.OnboardingTipsService)
	local ForgeService = require(Systems.ForgeService)
	local PetAutoHatchService = require(Systems.PetAutoHatchService)
	local ChallengeService = require(Systems.ChallengeService)
	local AttackService = require(Systems.AttackService)
	local Analytics = require(Systems.Analytics)
	local RemoteGuard = require(Systems.RemoteGuard)

	task.wait(15) -- 테스트가 같은 서비스의 _deps를 바꿔 끼우는 동안은 피한다
	print(string.format("[PERF] ===== 서버 루프 측정 시작 (가짜 플레이어 %d명 · 반복 %d)", PerfReport.PLAYERS, PerfReport.ITERS))

	local players: { any } = {}
	local datas: { any } = {}
	for i = 1, PerfReport.PLAYERS do
		local p = { Name = "PerfPlayer" .. i, UserId = -38000 - i }
		local d = Schema.new()
		d.forgeOpen = true
		d.ores[1] = 1e6
		d.coins = BigNum.new(1, 12)
		d.lifetimeBlox = BigNum.new(1, 6)
		ProfileManager._attachTestProfile(p, d)
		table.insert(players, p)
		table.insert(datas, d)
	end

	local clock = 1e6
	local saved = {
		ore = OreDropService._deps,
		tips = OnboardingTipsService._deps,
		forge = ForgeService._deps,
		hatch = PetAutoHatchService._deps,
	}
	OreDropService._deps = {
		addCoins = function(p, amount, reason)
			return CurrencyService.add(p, "coins", amount, reason)
		end,
		getCoins = function(p)
			return CurrencyService.get(p, "coins")
		end,
		addOres = InventoryService.addOres,
		getOres = InventoryService.getOres,
		isForgeOpen = InventoryService.isForgeOpen,
		openForge = InventoryService.openForge,
		getEquipped = function(p)
			return InventoryService.getEquipped(p, "pickaxe")
		end,
		ownsAutoAdvance = function()
			return false
		end,
		ownsBigBag = function()
			return false
		end,
		rootPosition = function()
			return Vector3.new(0, 0, 0)
		end,
		send = noop,
		rand = function()
			return 0.5
		end,
	} :: any
	OnboardingTipsService._deps = {
		getData = function(p)
			local prof = ProfileManager.get(p)
			return if prof ~= nil then prof.Data else nil
		end,
		bagUsed = OreDropService.bagUsed,
		send = noop,
		log = noop,
	} :: any
	ForgeService._deps = {
		isForgeOpen = InventoryService.isForgeOpen,
		getOres = InventoryService.getOres,
		getTokens = InventoryService.getTokens,
		getOwned = function(p)
			return InventoryService.getOwned(p, "pickaxe")
		end,
		craft = InventoryService.craft,
		exchange = InventoryService.exchange,
		ownsSkipPass = function()
			return true -- 가장 짧은 간격(연출 생략) — 최악
		end,
		ownsTriple = function()
			return false
		end,
		send = noop,
		rand = function()
			return 0.5
		end,
		now = function()
			return clock
		end,
	} :: any
	PetAutoHatchService._deps = {
		hatch = function()
			return true, { petId = "p", rarity = 1, isNew = false }
		end,
		hatchMulti = function()
			return true, {}
		end,
		ownsTriple = function()
			return false
		end,
		send = noop,
		notify = noop,
		now = function()
			return clock
		end,
	} :: any

	local results: { string } = {}
	-- 인벤토리 변경 줄(print)은 재는 동안 끈다 — Studio 출력 창 print가 로직보다 훨씬 비싸 숫자를 흐린다(실서버 로그 비용은 따로)
	local savedInvLog = InventoryService._deps.log
	InventoryService._deps.log = noop
	local function measure(label: string, perSec: number, fn: () -> ())
		local t0 = os.clock()
		for _ = 1, PerfReport.ITERS do
			fn()
		end
		local ms = (os.clock() - t0) / PerfReport.ITERS * 1000
		local line = string.format("[PERF] %s: %.3f ms/틱(%d명) · %.2f ms/초(초당 %g틱)", label, ms, PerfReport.PLAYERS, ms * perSec, perSec)
		print(line)
		table.insert(results, line)
		task.wait()
		return ms * perSec
	end

	local ok, err = pcall(function()
		local total = 0
		-- 바닥 드롭 16개(반경 밖 — 다 훑고 하나도 못 줍는 최악)
		local far = {}
		for b = 1, 16 do
			table.insert(far, Vector3.new(100 + b, 0, 100))
		end
		for _, p in ipairs(players) do
			OreDropService.onStageEnter(p, 1, "start")
			OreDropService.onBlocksDestroyed(p, 1, far)
		end
		total += measure("줍기 폴링(드롭 16개씩)", 1 / Config.PICKUP_POLL_SEC, function()
			for _, p in ipairs(players) do
				OreDropService.pickupTick(p)
			end
		end)
		total += measure("안내 폴링", 1 / OnboardingConfig.TIP_POLL_SEC, function()
			for _, p in ipairs(players) do
				OnboardingTipsService.tick(p)
			end
		end)
		for _, p in ipairs(players) do
			ForgeService._reset(p)
			ForgeService.setAuto(p, true, { 1, 1, 1, 1, 1 }, false)
		end
		total += measure("자동 제작(매 틱 1회 제작 — 최악)", 1 / Config.AUTO_CRAFT_POLL_SEC, function()
			clock += 10
			for _, p in ipairs(players) do
				ForgeService.autoTick(p)
			end
		end)
		for _, p in ipairs(players) do
			PetAutoHatchService.setAuto(p, true, 1)
		end
		total += measure("자동 부화", 1 / Config.AUTO_HATCH_POLL_SEC, function()
			clock += 10
			for _, p in ipairs(players) do
				PetAutoHatchService.tick(p)
			end
		end)
		-- 공격: 5층 런 · 블록 앞 · 약한 힘(블록이 안 깨지게 — 데미지 경로만)
		local stage = 5
		for _, p in ipairs(players) do
			ChallengeService.startRun(p, stage)
		end
		local attackDeps = {
			getRunState = function(p)
				return ChallengeService.getRunState(p) :: any
			end,
			getStrength = function()
				return BigNum.new(1, 0)
			end,
			getPosition = function()
				return BlockLayout.getStageOrigin(stage)
			end,
			applyDamage = ChallengeService.applyDamage,
			getDamageMultiplier = function()
				return 1
			end,
		}
		total += measure("공격(펀치 1회씩 · 블록 데미지)", AttackConfig.PUNCH_SPEED_MAX, function()
			for _, p in ipairs(players) do
				AttackService._pure.runPunch(attackDeps :: any, p)
			end
		end)
		local near = {}
		for b = 1, 1 do
			table.insert(near, Vector3.new(b, 0, 0))
		end
		local breakMs = measure("블록 깨짐 1개(드롭 · 코인 지급)", 2, function()
			for _, p in ipairs(players) do
				OreDropService.onBlocksDestroyed(p, 1, near)
				OreDropService.pickupTick(p)
			end
		end)
		total += breakMs
		total += measure("분석 진행 확인", 1 / 2, function()
			for i, p in ipairs(players) do
				Analytics._pure.funnelReached(datas[i])
				Analytics._pure.pickaxeKinds(datas[i])
			end
		end)
		local gate = RemoteGuard._pure.newGate()
		local t = 0
		total += measure("입구 문(메시지 1개씩 · 대장간 표)", 5, function()
			t += 1
			for _, p in ipairs(players) do
				gate.check(p, "ForgeRequest", { action = "craft", combo = { 1, 1, 1, 1, 1 } }, t)
			end
		end)
		local sumLine = string.format("[PERF] 합계(위 루프를 그 주기로 1초 돌림): %.2f ms/초 = 서버 1초의 %.2f%%", total, total / 10)
		print(sumLine)
		table.insert(results, sumLine)
	end)
	if not ok then
		warn("[PERF] 측정 오류: " .. tostring(err))
	end

	InventoryService._deps.log = savedInvLog
	for _, p in ipairs(players) do
		ForgeService.setAuto(p, false, nil, false)
		PetAutoHatchService.setAuto(p, false, nil)
		ChallengeService.abandonRun(p)
		OreDropService._reset(p)
		ForgeService._reset(p)
		PetAutoHatchService._reset(p)
		ProfileManager._detachTestProfile(p)
	end
	OreDropService._deps = saved.ore
	OnboardingTipsService._deps = saved.tips
	ForgeService._deps = saved.forge
	PetAutoHatchService._deps = saved.hatch
	print("[PERF] 요약\n" .. table.concat(results, "\n")) -- 한 줄로(로그 보관 상한에 앞줄이 밀려도 이 줄은 남는다)
	print("[PERF] ===== 끝")
end

return PerfReport

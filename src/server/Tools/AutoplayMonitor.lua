--!strict
-- 자동 플레이 봇 — 서버 검사(지시서 #43 1부 · Studio 전용 · TestGate · **Mock 프로필에서만**).
-- 켜는 곳: Bootstrap TEST_AUTOPLAY = "fresh" | "min30" | "hour2"(커밋 값 nil). 구간이 Mock 프리셋을 연다(AutoplayLogic.resolve).
-- 이 파일은 조작하지 않는다 — 클라 봇(Client/Tools/AutoplayBot)이 실제 리모트 · 캐릭터 이동으로 논다. 여기는 지켜보고 센다:
--   출력 창 경고 · 오류(서버) · 재화 · 광석 · 토큰 음수 · 가방 상한 · 수령 때 가방 → 인벤토리 · 실패 때 가방 비움 ·
--   제작 1회당 광석 CRAFT_INPUT개 · 토큰 계획대로(ForgeService 이음매 _deps.craft를 감싸 앞뒤를 잰다 — 끝나면 되돌린다) ·
--   서버 루프 시간(줍기 · 자동 제작 · 자동 부화 · 안내 · 펀치 · 블록 깨짐 고리를 감싸 잰다 — TUNING 11 상한)
-- 시작 신호: ReplicatedStorage 속성 AutoplaySegment(클라 봇이 이것을 보고 움직인다) · 끝 신호: AutoplayDone = true.
-- 결과: "[AUTOPLAY] 서버 …" 줄들 + 끝 줄 "[AUTOPLAY] ===== 서버 끝". 프로필은 읽기만 한다(바꾸는 것은 봇의 요청을 받은 서비스뿐).

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AutoplayConfig = require(ReplicatedStorage.Shared.Config.AutoplayConfig)
local AutoplayLogic = require(ReplicatedStorage.Shared.AutoplayLogic)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)

local AutoplayMonitor = {}

AutoplayMonitor.ATTR_SEGMENT = "AutoplaySegment"
AutoplayMonitor.ATTR_DONE = "AutoplayDone"

local TAG = AutoplayConfig.TAG

local function line(fmt: string, ...)
	print(TAG .. " 서버 " .. string.format(fmt, ...))
end

-- 서버 테스트 끝 줄을 기다린다(테스트가 서비스 이음매를 바꿔 끼우는 동안 감싸지 않는다)
local function waitTestsDone(): boolean
	local t0 = os.clock()
	while os.clock() - t0 < AutoplayConfig.TEST_WAIT_MAX_SEC do
		for _, e in ipairs(LogService:GetLogHistory()) do
			if string.find(e.message, "[TestRunDone] server", 1, true) ~= nil then
				return true
			end
		end
		task.wait(1)
	end
	return false
end

local function firstPlayerWithProfile(ProfileManager: any): (Player?, any)
	for _ = 1, 120 do
		for _, p in ipairs(Players:GetPlayers()) do
			local profile = ProfileManager.get(p)
			if profile ~= nil then
				return p, profile
			end
		end
		task.wait(0.5)
	end
	return nil, nil
end

-- 함수 감싸기(시간 재기). 되돌릴 함수를 돌려준다
local function wrapTimed(tbl: any, key: string, acc: { ms: number, calls: number }): () -> ()
	local orig = tbl[key]
	if type(orig) ~= "function" then
		return function() end
	end
	tbl[key] = function(...)
		local t = os.clock()
		local r = table.pack(orig(...))
		acc.ms += (os.clock() - t) * 1000
		acc.calls += 1
		return table.unpack(r, 1, r.n)
	end
	return function()
		tbl[key] = orig
	end
end

function AutoplayMonitor.run(segmentName: string)
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	local Systems = script.Parent.Parent.Systems
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	local seg = AutoplayConfig.SEGMENTS[segmentName]
	if seg == nil then
		warn(TAG .. " 서버 ERROR 알 수 없는 구간 " .. tostring(segmentName))
		return
	end
	if ProfileManager.mockPreset() ~= seg.preset then
		-- Mock이 아니면 돌지 않는다(실제 저장소 프로필로 봇이 놀면 안 된다 — CLAUDE.md 절대 규칙 8의 이유와 같다)
		warn(string.format("%s 서버 ERROR Mock 프리셋이 %s가 아니다(%s) — 봇을 시작하지 않는다", TAG, seg.preset, tostring(ProfileManager.mockPreset())))
		return
	end
	local testsDone = waitTestsDone()
	task.wait(AutoplayConfig.START_DELAY_SEC)
	local player, profile = firstPlayerWithProfile(ProfileManager)
	if player == nil or profile == nil then
		warn(TAG .. " 서버 ERROR 프로필이 열린 플레이어가 없다 — 봇을 시작하지 않는다")
		return
	end
	local ChallengeService = require(Systems.ChallengeService)
	local OreDropService = require(Systems.OreDropService)
	local ForgeService = require(Systems.ForgeService)
	local AttackService = require(Systems.AttackService)
	local PetAutoHatchService = require(Systems.PetAutoHatchService)
	local OnboardingTipsService = require(Systems.OnboardingTipsService)
	local data = profile.Data

	local warnings = AutoplayLogic.newTally()
	local negatives = AutoplayLogic.newTally()
	local bags = AutoplayLogic.newTally()
	local runEnds = AutoplayLogic.newTally()
	local crafts = AutoplayLogic.newTally()
	local rebirthChecks = AutoplayLogic.newTally()
	local rebirthDone = 0
	local counts = { start = 0, advance = 0, cleared = 0, cashout = 0, timeout = 0, abandon = 0, crafts = 0, craftOres = 0 }
	local startFloorMax = data.progress.maxStage
	local bestFloor = 0
	local rebirthsBefore = BigNum.new(data.rebirths.m, data.rebirths.e)
	local strengthBefore = BigNum.new(data.strength.m, data.strength.e)
	local maxBag = 0
	local runActive = false
	local prevBag = 0

	-- 1. 경고 · 오류(이 구간 동안 · 봇 자신의 줄은 뺀다)
	local logConn = LogService.MessageOut:Connect(function(message: string, kind: Enum.MessageType)
		if kind ~= Enum.MessageType.MessageWarning and kind ~= Enum.MessageType.MessageError then
			return
		end
		if AutoplayLogic.isOwnLine(message) then
			return
		end
		local head = string.match(message, "^%[([%w_]+)%]") or "?"
		AutoplayLogic.add(warnings, (if kind == Enum.MessageType.MessageError then "E:" else "W:") .. head, string.sub(message, 1, 60))
	end)

	-- 2. 서버 루프 시간(감싸서 잰다 — 끝나면 되돌린다)
	local acc = { ms = 0, calls = 0 }
	local unwraps = {
		wrapTimed(OreDropService, "pickupTick", acc),
		wrapTimed(ForgeService, "autoTick", acc),
		wrapTimed(PetAutoHatchService, "tick", acc),
		wrapTimed(OnboardingTipsService, "tick", acc),
		wrapTimed(AttackService, "punch", acc),
	}
	local hooks = ChallengeService.economyHooks :: any
	if hooks ~= nil then
		table.insert(unwraps, wrapTimed(hooks, "onBlocksDestroyed", acc))
		table.insert(unwraps, wrapTimed(hooks, "onStageEnter", acc))
		table.insert(unwraps, wrapTimed(hooks, "onRunEnded", acc))
	end
	local maxFrame = 0
	local slowFrames = 0
	local frameConn = RunService.Heartbeat:Connect(function(dt: number)
		maxFrame = math.max(maxFrame, dt)
		if dt > 0.1 then
			slowFrames += 1
		end
	end)

	-- 3. 제작: ForgeService 이음매(_deps.craft)를 감싸 광석 · 토큰 앞뒤를 잰다(수동 · 자동 제작 둘 다 이 한 곳을 지난다)
	ForgeService.sendState(player) -- 이음매가 아직 없으면 만든다(읽기 + 통지만)
	local fdeps = (ForgeService :: any)._deps
	local craftOrig = if fdeps ~= nil then fdeps.craft else nil
	if fdeps ~= nil and type(craftOrig) == "function" then
		fdeps.craft = function(p: Player, take: { [number]: number }, kind: string, ids: { string }, tokens: { [string]: number }, reason: string)
			if p ~= player then
				return craftOrig(p, take, kind, ids, tokens, reason)
			end
			local oresBefore = table.clone(data.ores)
			local tokBefore = table.clone(data.tokens)
			local ok = craftOrig(p, take, kind, ids, tokens, reason)
			if ok then
				counts.crafts += #ids
				local combo = {}
				for k, n in pairs(take) do
					counts.craftOres += n
					for _ = 1, n // math.max(1, #ids) do
						table.insert(combo, k)
					end
				end
				for _, prob in ipairs(AutoplayLogic.craftProblems(oresBefore, data.ores, combo, #ids, EconomyV2Config.CRAFT_INPUT,
					tokBefore, data.tokens, tokens, EconomyV2Config.ORE_COUNT)) do
					AutoplayLogic.add(crafts, "craft", prob)
				end
			end
			return ok
		end
	else
		AutoplayLogic.add(crafts, "no_seam", "ForgeService._deps.craft")
	end

	-- 3b. 환생(#44 pre_rebirth): 실제 경로(RebirthRequest → RebirthRequestService → RebirthService.rebirth)를 감싸 앞뒤를 잰다 —
	--     환생 +1 · 블럭스 = 앞 − 비용 · 곡괭이 · 광석 · 토큰 · 코인 · 펫 그대로 · 열린 기구 갱신 · 힘 배수 ×1.25 · 초기화 · 분석 이벤트 1번
	local RebirthService = require(Systems.RebirthService)
	local Analytics = require(Systems.Analytics)
	local ClickService = require(Systems.ClickService)
	local Schema = require(script.Parent.Parent.Data.Schema)
	local analyticsRebirths = 0
	local analyticsOrig = Analytics.rebirth
	Analytics.rebirth = function(...)
		analyticsRebirths += 1
		return analyticsOrig(...)
	end
	local function snapshot(): any
		local d = profile.Data
		local picks = {}
		for id, o in pairs(d.equipment.pickaxe) do
			picks[id] = { count = o.count, stars = o.stars, enh = o.enh }
		end
		local pets = {}
		for uid, pet in pairs(d.pets.owned) do
			table.insert(pets, uid .. ":" .. tostring(pet.petId))
		end
		table.sort(pets)
		return {
			rebirths = EconomyV2Logic.rebirthCount(d.rebirths),
			blox = BigNum.new(d.blox.m, d.blox.e),
			coins = BigNum.new(d.coins.m, d.coins.e),
			strength = BigNum.new(d.strength.m, d.strength.e),
			lifeBlox = BigNum.new(d.lifeBlox.m, d.lifeBlox.e),
			ores = table.clone(d.ores),
			tokens = table.clone(d.tokens),
			pickaxes = picks,
			equipped = d.equipped.pickaxe,
			pets = pets,
			gyms = GymConfig.getUnlockedCount(d.rebirths),
			maxStage = d.progress.maxStage,
			mult = ClickService.strengthMultiplierOf(player),
		}
	end
	local rebirthOrig = RebirthService.rebirth
	RebirthService.rebirth = function(p: Player, source: string?)
		if p ~= player then
			return rebirthOrig(p, source)
		end
		local before = snapshot()
		local cost = EconomyV2Logic.rebirthCost(profile.Data.rebirths)
		local calls0 = analyticsRebirths
		local ok, value = rebirthOrig(p, source)
		if ok then
			rebirthDone += 1
			local after = snapshot()
			for _, prob in ipairs(AutoplayLogic.rebirthProblems(before, after, {
				cost = cost,
				multRatio = BigNum.toRatio(after.mult, before.mult),
				multBase = EconomyV2Config.REBIRTH_MULT_BASE,
				gymsExpected = GymConfig.getUnlockedCount(BigNum.fromNumber(before.rebirths + 1)),
				strengthStart = Schema.new().strength,
				analytics = analyticsRebirths - calls0,
			})) do
				AutoplayLogic.add(rebirthChecks, "rebirth", prob)
			end
			line("환생 %d → %d · 비용 %s · 블럭스 %s → %s · 열린 기구 %d → %d · 힘 배수 ×%.4f", before.rebirths, after.rebirths,
				BigNum.tostring(cost), BigNum.tostring(before.blox), BigNum.tostring(after.blox), before.gyms, after.gyms,
				BigNum.toRatio(after.mult, before.mult))
		end
		return ok, value
	end

	-- 4. 런 끝: 수령이면 가방 → 인벤토리 · 아니면 가방 비움. 듣는 쪽은 endRun의 통지에서 **고리(onRunEnded)보다 먼저** 동기로 불린다 —
	--    그때 가방 · 인벤토리를 찍고, task.defer로 고리가 끝난 뒤를 잰다
	ChallengeService.onRunEvent(function(p: Player, reason: string, stage: number)
		if p ~= player or ReplicatedStorage:GetAttribute(AutoplayMonitor.ATTR_DONE) == true then
			return
		end
		if counts[reason] ~= nil then
			counts[reason] += 1
		end
		if reason == "start" or reason == "advance" or reason == "cleared" then
			runActive = true
		elseif reason == "cashout" or reason == "timeout" or reason == "abandon" then
			runActive = false
		end
		if reason == "cleared" then
			bestFloor = math.max(bestFloor, stage)
		end
		if reason ~= "cashout" and reason ~= "timeout" and reason ~= "abandon" then
			return
		end
		local st = OreDropService._state(player)
		local bag = if st ~= nil then table.clone(st.bag) else {}
		local invBefore = table.clone(data.ores)
		task.defer(function()
			for _, prob in ipairs(AutoplayLogic.runEndProblems(reason, bag, invBefore, data.ores, OreDropService.bagUsed(player),
				EconomyV2Config.ORE_COUNT)) do
				AutoplayLogic.add(runEnds, reason, prob)
			end
		end)
	end)

	-- 시작 신호
	local t0 = os.clock()
	line("===== 시작 %s(%s) · 목표 %d층 · 상한 %d초 · 시작 최고 층 %d · 테스트 끝 줄 %s", segmentName, seg.label, seg.targetFloor, seg.limitSec,
		startFloorMax, if testsDone then "봄" else "못 봄(90초)")
	ReplicatedStorage:SetAttribute(AutoplayMonitor.ATTR_SEGMENT, segmentName)

	-- 5. 주기 검사(음수 · 가방 상한) + 끝 판정
	local reason = "limit"
	while true do
		task.wait(AutoplayConfig.CHECK_PERIOD_SEC)
		if player.Parent == nil then
			reason = "left"
			break
		end
		for _, prob in ipairs(AutoplayLogic.negativeProblems(data, EconomyV2Config.ORE_COUNT)) do
			AutoplayLogic.add(negatives, "neg", prob)
		end
		local used = OreDropService.bagUsed(player)
		maxBag = math.max(maxBag, used)
		for _, prob in ipairs(AutoplayLogic.bagProblems(used, OreDropService.capacityOf(player), prevBag)) do
			AutoplayLogic.add(bags, "cap", prob)
		end
		prevBag = used
		if bestFloor >= seg.targetFloor and counts.start >= (seg.minRuns or AutoplayConfig.MIN_RUNS) and not runActive
			and (not seg.rebirthFirst or rebirthDone > 0) then
			reason = "target"
			break
		end
		if os.clock() - t0 >= seg.limitSec then
			break
		end
	end
	local elapsed = os.clock() - t0
	ReplicatedStorage:SetAttribute(AutoplayMonitor.ATTR_DONE, true)
	task.wait(1) -- 마지막 런 끝(defer 검사)이 들어오게

	logConn:Disconnect()
	frameConn:Disconnect()
	for _, undo in ipairs(unwraps) do
		undo()
	end
	if fdeps ~= nil and craftOrig ~= nil then
		fdeps.craft = craftOrig
	end
	RebirthService.rebirth = rebirthOrig
	Analytics.rebirth = analyticsOrig
	if seg.rebirthFirst and rebirthDone == 0 then
		AutoplayLogic.add(rebirthChecks, "no_rebirth", "환생 구간인데 환생이 없었다")
	end

	local msPerSec = acc.ms / math.max(elapsed, 1e-6)
	local failed = warnings.count + negatives.count + bags.count + runEnds.count + crafts.count + rebirthChecks.count
	if not AutoplayLogic.loopBudgetOk(msPerSec) then
		failed += 1
	end
	line("구간 %s · 끝 사유 %s · %.0f초 · 최고 층 이번 %d (시작 %d → 지금 %d) · 목표 %d층 %s", segmentName, reason, elapsed, bestFloor, startFloorMax,
		data.progress.maxStage, seg.targetFloor, if bestFloor >= seg.targetFloor then "닿음" else "못 닿음")
	line("런 시작 %d · 진행 %d · 클리어 %d · 수령 %d · 시간 초과 %d · 포기(환생 등) %d", counts.start, counts.advance, counts.cleared, counts.cashout,
		counts.timeout, counts.abandon)
	line("환생 %s → %s · 힘 %s → %s · 블럭스 %s · 코인 %s", BigNum.tostring(rebirthsBefore), BigNum.tostring(data.rebirths),
		BigNum.tostring(strengthBefore), BigNum.tostring(data.strength), BigNum.tostring(data.blox), BigNum.tostring(data.coins))
	line("제작 %d회 · 광석 %d개 쓰임 · 가방 최대 %d · 곡괭이 장착 %s", counts.crafts, counts.craftOres, maxBag, tostring(data.equipped.pickaxe))
	line("검사 경고·오류 %s", AutoplayLogic.tallyLine(warnings, 80))
	line("검사 음수 %s · 가방 상한 %s", AutoplayLogic.tallyLine(negatives, 40), AutoplayLogic.tallyLine(bags, 40))
	line("검사 런 끝 가방 %s · 제작 %s", AutoplayLogic.tallyLine(runEnds, 40), AutoplayLogic.tallyLine(crafts, 40))
	line("검사 환생 %d번 %s", rebirthDone, AutoplayLogic.tallyLine(rebirthChecks, 70))
	line("검사 서버 루프 %.3f ms/초(상한 %.0f) · 호출 %d · Heartbeat 최대 %.0f ms · 0.1초 넘는 프레임 %d", msPerSec,
		1000 * AutoplayConfig.SERVER_LOOP_BUDGET_SHARE, acc.calls, maxFrame * 1000, slowFrames)
	line("===== 끝 %s · 서버 검사 %s", segmentName, if failed == 0 then "통과" else string.format("실패 %d", failed))
end

return AutoplayMonitor

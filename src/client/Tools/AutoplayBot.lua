--!strict
-- 자동 플레이 봇 — 클라 조작(지시서 #43 1부 · Studio 전용 · TestGate). 서버가 Mock 프로필을 확인하고 ReplicatedStorage 속성
-- AutoplaySegment를 세워야만 움직인다(Server/Tools/AutoplayMonitor — Bootstrap TEST_AUTOPLAY). 속성이 없으면 아무것도 하지 않는다.
--
-- **실제 게임 경로로만 논다** — 서비스를 건너뛰지 않는다:
--   이동     Humanoid:MoveTo(캐릭터 물리는 클라 소유 — 사람이 걷는 것과 같은 길). 게이트 · 진행 벽 · 수령 발판은 걸어서 밟는다
--   요청     UI가 쓰는 것과 같은 리모트 · 같은 payload(ClickInput · ForgeRequest · EquipmentRequest · PetRequest · PetAutoRequest ·
--            UpgradeRequest · RebirthRequest · WarpRequest · DailyRequest) — 서버 RemoteGuard · 서비스 검사를 그대로 지난다
--   창       ScreenController.open/close(메뉴 버튼이 부르는 것과 같은 함수)
-- 봇이 재는 것(클라): 창 열기 · 닫기 · 클라 출력 창 경고 · 오류 · 이동 막힘 · 줍기. 서버 검사는 AutoplayMonitor.
-- 결과 "[AUTOPLAY] 클라 …" · 끝 줄 "[AUTOPLAY] ===== 클라 끝". 정책 · 수치는 Shared/Config/AutoplayConfig · Shared/AutoplayLogic.

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoplayConfig = require(ReplicatedStorage.Shared.Config.AutoplayConfig)
local AutoplayLogic = require(ReplicatedStorage.Shared.AutoplayLogic)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)

local AutoplayBot = {}

local TAG = AutoplayConfig.TAG
local ATTR_SEGMENT = "AutoplaySegment" -- AutoplayMonitor.ATTR_SEGMENT과 같은 이름(서버 모듈은 클라에서 못 읽는다)
local ATTR_DONE = "AutoplayDone"

local function line(fmt: string, ...)
	print(TAG .. " 클라 " .. string.format(fmt, ...))
end

local function done(): boolean
	return ReplicatedStorage:GetAttribute(ATTR_DONE) == true
end

function AutoplayBot.run()
	if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)
	-- 서버가 Mock을 확인하고 신호를 줄 때까지 기다린다(없으면 이 함수는 여기서 영영 멈춰 있다 — 보통 Play)
	while type(ReplicatedStorage:GetAttribute(ATTR_SEGMENT)) ~= "string" do
		ReplicatedStorage:GetAttributeChangedSignal(ATTR_SEGMENT):Wait()
	end
	local segmentName = ReplicatedStorage:GetAttribute(ATTR_SEGMENT) :: string
	local seg = AutoplayConfig.SEGMENTS[segmentName]
	if seg == nil then
		return
	end
	local Client = script.Parent.Parent
	local Store = require(Client.UI.Store) :: any
	local ScreenController = require(Client.UI.ScreenController) :: any
	local EconomyV2State = require(Client.Economy.EconomyV2State) :: any
	local econ = EconomyV2State.shared()
	-- Store.get(키) 꼴을 표처럼 읽는다(읽을 때마다 지금 값)
	local function snap(): any
		return setmetatable({}, {
			__index = function(_, key)
				return Store.get(key)
			end,
		})
	end
	local channels = Remotes.getClient()
	local player = Players.LocalPlayer
	local t0 = os.clock()

	-- ===== 기록 =========================================================================================
	local warnings = AutoplayLogic.newTally()
	local windows = AutoplayLogic.newTally()
	local moves = AutoplayLogic.newTally()
	local flow = AutoplayLogic.newTally() -- 요청 · 런 흐름 이상(게이트가 런을 안 세움 등)
	-- 끝 신호 뒤에 끊긴 걸음은 흐름 이상이 아니다
	local function addFlow(kind: string, example: string)
		if not done() then
			AutoplayLogic.add(flow, kind, example)
		end
	end
	local stats = { runs = 0, floors = 0, advances = 0, cashouts = 0, fails = 0, failRuns = 0, warps = 0, rebirths = 0, crafts = 0,
		exchanges = 0, equips = 0, enhances = 0, stars = 0, hatches = 0, upgrades = 0, picked = 0, clicks = 0, daily = 0 }
	local phase = "start"
	-- 시간 나눔(#44 3부 — 봇 vs 시뮬): 단계마다 쓴 초 · 층 첫 도달(봇 시작부터 초)
	local phaseSec: { [string]: number } = {}
	local phaseAt = os.clock()
	local function setPhase(name: string)
		local now = os.clock()
		phaseSec[phase] = (phaseSec[phase] or 0) + (now - phaseAt)
		phaseAt = now
		phase = name
	end
	local firstReach: { [number]: number } = {}
	local cashoutFloors: { number } = {}

	local logConn = LogService.MessageOut:Connect(function(message: string, kind: Enum.MessageType)
		if kind ~= Enum.MessageType.MessageWarning and kind ~= Enum.MessageType.MessageError then
			return
		end
		if AutoplayLogic.isOwnLine(message) then
			return
		end
		local head = string.match(message, "^%[([%w_]+)%]") or "?"
		AutoplayLogic.add(warnings, (if kind == Enum.MessageType.MessageError then "E:" else "W:") .. head .. "@" .. phase,
			AutoplayLogic.clip(message, 50))
	end)

	-- ===== 서버 신호 받기 ==================================================================================
	local run: any = nil -- 지금 런 상태 노출본(없으면 nil)
	local runSeq = 0 -- 런 상태가 바뀔 때마다 +1
	channels.runStateChanged.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		run = if payload.active == true then payload.state else nil
		runSeq += 1
		if run ~= nil and (payload.reason == "start" or payload.reason == "advance") and type(run.stage) == "number"
			and firstReach[run.stage] == nil then
			firstReach[run.stage] = os.clock() - t0
		end
	end)
	local drops: { [number]: Vector3 } = {}
	local results: { [string]: any } = {}
	channels.economyEvent.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "drops" and type(payload.drops) == "table" then
			for _, d in ipairs(payload.drops) do
				if type(d) == "table" and typeof(d.position) == "Vector3" then
					drops[d.id] = d.position
				end
			end
		elseif payload.kind == "picked" and type(payload.ids) == "table" then
			for _, id in ipairs(payload.ids) do
				drops[id] = nil
				stats.picked += 1
			end
		elseif payload.kind == "clear" then
			table.clear(drops)
		end
		results[payload.kind] = payload
	end)
	for _, name in ipairs({ "rebirthResult", "warpResult", "upgradeResult", "petResult", "dailyResult" }) do
		(channels :: any)[name].OnClientEvent:Connect(function(payload: any)
			results[name] = payload
		end)
	end

	-- ===== 몸 · 이동 =====================================================================================
	local function body(): (Humanoid?, BasePart?)
		local character = player.Character
		if character == nil then
			return nil, nil
		end
		local h = character:FindFirstChildOfClass("Humanoid")
		local r = character:FindFirstChild("HumanoidRootPart")
		if h == nil or r == nil or not r:IsA("BasePart") or h.Health <= 0 then
			return nil, nil
		end
		return h, r :: BasePart
	end

	-- 수평으로 target 근처(within)까지 걷는다. cancel()이 참이면 멈춘다. (닿았나, 막혔나)
	local function walkTo(target: Vector3, maxSec: number, within: number?, cancel: (() -> boolean)?): (boolean, boolean)
		local reach = within or 2.5
		local start = os.clock()
		local lastPos: Vector3? = nil
		local lastMove = os.clock()
		local jumped = false
		while os.clock() - start < maxSec do
			if done() or (cancel ~= nil and cancel()) then
				return false, false
			end
			local h, r = body()
			if h == nil or r == nil then
				task.wait(0.25)
				continue
			end
			local here = r.Position
			local flat = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
			if flat.Magnitude <= reach then
				h:MoveTo(here)
				return true, false
			end
			h:MoveTo(Vector3.new(target.X, here.Y - 2, target.Z))
			task.wait(0.2)
			if lastPos == nil or (r.Position - (lastPos :: Vector3)).Magnitude > AutoplayConfig.STUCK_STUDS then
				lastPos = r.Position
				lastMove = os.clock()
			elseif os.clock() - lastMove > AutoplayConfig.STUCK_SEC then
				if not jumped then
					h.Jump = true
					jumped = true
					lastMove = os.clock()
				else
					return false, true
				end
			end
		end
		return false, false
	end

	local function rootPos(): Vector3?
		local _, r = body()
		return if r ~= nil then r.Position else nil
	end

	local function waitUntil(pred: () -> boolean, maxSec: number): boolean
		local start = os.clock()
		while os.clock() - start < maxSec do
			if pred() then
				return true
			end
			if done() then
				return false
			end
			task.wait(0.1)
		end
		return pred()
	end

	-- 요청 한 번 + 그 결과(종류 key)를 기다린다. 결과 표를 돌려준다(없으면 nil)
	local function request(remote: RemoteEvent, payload: any, resultKey: string?): any
		if resultKey ~= nil then
			results[resultKey] = nil
		end
		remote:FireServer(payload)
		local got = nil
		if resultKey ~= nil then
			waitUntil(function()
				return results[resultKey] ~= nil
			end, AutoplayConfig.RESULT_WAIT_SEC)
			got = results[resultKey]
		end
		task.wait(AutoplayConfig.REQUEST_GAP_SEC)
		return got
	end

	-- ===== 창 열기 · 닫기 ====================================================================================
	local function checkWindows(label: string)
		setPhase("windows_" .. label)
		for _, name in ipairs(AutoplayConfig.WINDOWS) do
			local ok, err = pcall(ScreenController.open, name)
			task.wait(AutoplayConfig.WINDOW_WAIT_SEC)
			if not ok then
				AutoplayLogic.add(windows, "open_error", name .. ":" .. AutoplayLogic.clip(tostring(err), 40))
			elseif not ScreenController.isOpen(name) then
				AutoplayLogic.add(windows, "not_open", name)
			end
			local ok2, err2 = pcall(ScreenController.close, name)
			task.wait(AutoplayConfig.WINDOW_WAIT_SEC)
			if not ok2 then
				AutoplayLogic.add(windows, "close_error", name .. ":" .. AutoplayLogic.clip(tostring(err2), 40))
			elseif ScreenController.isOpen(name) then
				AutoplayLogic.add(windows, "not_closed", name)
			end
		end
	end

	-- ===== 로비 =========================================================================================
	local function closeDaily()
		local ok, isOpen = pcall(ScreenController.isOpen, "DailyRewardWindow")
		if ok and isOpen then
			pcall(ScreenController.close, "DailyRewardWindow")
		end
	end

	local function bestGym(): (number?, Vector3?)
		local s = snap()
		local centers = GymLayout.computeLayout(GymConfig.getCount())
		local owns = function(key: string): boolean
			return table.find(s.shop.gamepasses, key) ~= nil
		end
		local shop = GymLayout.shopUnlocked(s.shop.gymUnlocks, owns)
		local best, bestMult = nil, 0
		for i = 1, GymConfig.getCount() do
			local open = shop(i) or (not GymConfig.isRobuxOnly(i) and GymConfig.isUnlockedByRebirths(i, s.rebirths))
			if open and GymConfig.getMultiplier(i) > bestMult then
				best, bestMult = i, GymConfig.getMultiplier(i)
			end
		end
		if best == nil then
			return nil, nil
		end
		return best, centers[best]
	end

	local function train(sec: number)
		setPhase("gym_walk") -- #45: 기구까지 걷기(로비 시간)와 기구 위 클릭(운동 시간 — 시뮬 GYM_TRAIN_SEC)을 나눠 잰다
		local _, center = bestGym()
		if center ~= nil then
			local reached, stuck = walkTo(Vector3.new(center.X, 0, center.Z), 15, 2)
			if not reached then
				AutoplayLogic.add(moves, if stuck then "gym_stuck" else "gym_far", tostring(center))
			end
		end
		-- 클릭은 뒤의 클릭 루프가 줄곧 보낸다(기구 위에 서 있으면 기구 배수 — 서버가 클릭 순간의 위치로 판정)
		setPhase("gym")
		local start = os.clock()
		while os.clock() - start < sec and not done() do
			task.wait(0.25)
		end
	end

	-- 클릭 루프: 구간 내내 초당 상한만큼(런 중 · 걷는 중에도 — 빠른 클릭 플레이어). 보내는 꼴은 Input/ClickInput과 같다
	task.spawn(function()
		while not done() do
			channels.clickInput:FireServer({ count = AutoplayConfig.CLICKS_PER_BATCH })
			stats.clicks += AutoplayConfig.CLICKS_PER_BATCH
			task.wait(AutoplayConfig.CLICK_PERIOD_SEC)
		end
	end)

	local function forgeVisit()
		local v = econ.get()
		if not v.forgeOpen then
			return
		end
		setPhase("forge")
		for _ = 1, AutoplayConfig.CRAFTS_PER_VISIT do
			if EconomyV2Logic.bestCombo(econ.get().ores) == nil then
				break
			end
			local r = request(channels.forgeRequest, { action = "craft", fill = true }, "craft_result")
			if r == nil then
				addFlow("craft_no_result", "fill")
				break
			elseif r.ok == true then
				stats.crafts += 1
				task.wait(math.max(0, (tonumber(r.nextIn) or 0) - AutoplayConfig.REQUEST_GAP_SEC))
			elseif r.reason == "too_soon" then
				task.wait(0.5)
			else
				break
			end
		end
		-- 교환: 토큰이 닿는 가장 좋은 곡괭이 하나
		local tokens = econ.get().tokens
		local bestDef: any = nil
		for _, def in ipairs(EconomyV2Config.PICKAXES) do
			if def.exchangeCost ~= nil and (tokens[def.rarity] or 0) >= def.exchangeCost then
				if bestDef == nil or def.rank > bestDef.rank then
					bestDef = def
				end
			end
		end
		if bestDef ~= nil then
			local r = request(channels.forgeRequest, { action = "exchange", id = bestDef.id }, "exchange_result")
			if r ~= nil and r.ok == true then
				stats.exchanges += 1
			end
		end
		-- 장비: 가장 좋은 곡괭이 장착 · 별 · 강화(되는 만큼 한 번씩)
		setPhase("equipment")
		v = econ.get()
		local picks = EconomyV2Logic.picksFromSave(v.equipment, v.equipped)
		local best = EconomyV2Logic.bestOwned(picks)
		if best ~= nil and best ~= v.equipped then
			local r = request(channels.equipmentRequest, { action = "equip", id = best }, "equipment_result")
			if r ~= nil and r.ok == true then
				stats.equips += 1
			end
		end
		v = econ.get()
		local o = v.equipment[v.equipped]
		if o ~= nil then
			local need = EconomyV2Logic.starCost(o.stars)
			if need ~= nil and EconomyV2Logic.spareOf(o.count) >= need then
				local r = request(channels.equipmentRequest, { action = "star", id = v.equipped }, "equipment_result")
				if r ~= nil and r.ok == true then
					stats.stars += 1
				end
			end
			local cost = EconomyV2Logic.enhanceCost(o.enh, v.equipped)
			if cost ~= nil and EconomyV2Logic.orePayment(econ.get().ores, cost) ~= nil then
				local r = request(channels.equipmentRequest, { action = "enhance", id = v.equipped }, "equipment_result")
				if r ~= nil and r.ok == true then
					stats.enhances += 1
				end
			end
		end
	end

	-- 펫(#45): 자동 부화가 꺼져 있고 코인이 닿으면 손으로 한 번 깐다(손 부화 경로 점검) · 그 뒤 자동 부화가 코인이 닿는 만큼 깐다(keepAutoOn)
	local function petVisit()
		setPhase("pet")
		local s = snap()
		local eggs = PetConfig.getUnlockedEggs(s.lifetimeBlox, s.pets.world, s.pets.bestDepth)
		local egg = eggs[#eggs]
		if egg == nil or econ.get().autoHatchOn then
			return
		end
		local cost = EconomyV2Logic.eggCoinCost(egg)
		if cost == nil or BigNum.lt(econ.get().coins, cost) then
			return
		end
		local r = request(channels.petRequest, { action = "hatch", egg = egg }, "petResult")
		if r ~= nil and r.ok == true then
			stats.hatches += 1
			request(channels.petRequest, { action = "equipBest" }, "petResult")
		end
	end

	-- 자동 제작 · 자동 부화는 켜 둔다(#45 — 시뮬 표준은 제작 · 부화를 시계로 센다: 사람은 켜 놓고 논다). 꺼져 있으면 켠다
	-- (광석 · 코인이 모자라 서버가 껐으면 다시 닿을 때). 부화 알 = 열린 알 중 가장 높은 것
	local function keepAutoOn()
		local v = econ.get()
		if v.forgeOpen and not v.autoOn and EconomyV2Logic.bestCombo(v.ores) ~= nil then
			setPhase("forge")
			request(channels.forgeRequest, { action = "auto", on = true, fill = true }, "auto_state")
		end
		local s = snap()
		local eggs = PetConfig.getUnlockedEggs(s.lifetimeBlox, s.pets.world, s.pets.bestDepth)
		local egg = eggs[#eggs]
		if egg ~= nil and not econ.get().autoHatchOn then
			local cost = EconomyV2Logic.eggCoinCost(egg)
			if cost ~= nil and BigNum.gte(econ.get().coins, cost) then
				setPhase("pet")
				request(channels.petAutoRequest, { on = true, egg = egg }, "auto_hatch_state")
				request(channels.petRequest, { action = "equipBest" }, "petResult")
			end
		end
	end

	local function upgradeVisit()
		setPhase("upgrade")
		-- 살 수 있는 만큼(한 바퀴에 대상마다 1레벨씩 · 더 못 사면 끝 · 상한 30번)
		for _ = 1, 30 do
			local bought = false
			for _, name in ipairs(AutoplayConfig.UPGRADE_TARGETS) do
				local s = snap()
				local level = s.upgrades[name] or 0
				if UpgradeConfig.isExposed(name) and UpgradeConfig.canBuy(name, level, s.blox) then
					local r = request(channels.upgradeRequest, { name = name }, "upgradeResult")
					if r ~= nil and r.ok == true then
						stats.upgrades += 1
						bought = true
					end
				end
			end
			if not bought or done() then
				break
			end
		end
	end

	-- ===== 런 =========================================================================================
	local timer = StageConfig.CHALLENGE_TIMER_SEC
	local function stagePoint(stage: number, z: number): Vector3
		return Vector3.new(ArenaConfig.getStageCenterX(stage) - ArenaConfig.STAGE_WIDTH / 2 + 6, 0, z)
	end

	local function nearestDrop(): Vector3?
		local here = rootPos()
		if here == nil then
			return nil
		end
		local best, bestD = nil, math.huge
		for _, pos in pairs(drops) do
			local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude
			if d < bestD then
				best, bestD = pos, d
			end
		end
		return best
	end

	local function bagFull(): boolean
		local v = econ.get()
		return v.bagCap > 0 and v.bagUsed >= v.bagCap
	end

	-- 한 층: 클리어 될 때까지 블록 곁에서 드롭을 줍는다. 클리어면 true(런이 끝났으면 false)
	local function fightFloor(stage: number): boolean
		setPhase("approach")
		walkTo(stagePoint(stage, 0), 8, 3, function()
			return run == nil or run.cleared == true
		end)
		setPhase("attack")
		while run ~= nil and run.stage == stage and run.cleared ~= true and not done() do
			local target = if not bagFull() then nearestDrop() else nil
			if target ~= nil then
				local _, stuck = walkTo(target, 3, EconomyV2Config.PICKUP_RADIUS * 0.5, function()
					return run == nil or run.cleared == true or run.stage ~= stage
				end)
				if stuck then
					AutoplayLogic.add(moves, "drop_stuck", string.format("%d층", stage))
					walkTo(stagePoint(stage, 0), 4, 3)
				end
				task.wait(0.1) -- 닿아 있으면 walkTo가 바로 돌아온다 — 줍기 폴링(0.25초)을 기다린다
			else
				task.wait(0.2)
			end
		end
		if run == nil or run.stage ~= stage or run.cleared ~= true then
			return false
		end
		-- 클리어 뒤 남은 드롭(가방이 차거나 없거나 상한 시간까지)
		setPhase("pickup")
		local start = os.clock()
		while os.clock() - start < AutoplayConfig.PICKUP_CHASE_SEC and not bagFull() and not done() do
			local target = nearestDrop()
			if target == nil then
				break
			end
			local _, stuck = walkTo(target, 3, EconomyV2Config.PICKUP_RADIUS * 0.5)
			if stuck then
				AutoplayLogic.add(moves, "drop_stuck_after", string.format("%d층", stage))
				break
			end
			task.wait(0.1)
		end
		return true
	end

	local function playRun(viaWarp: number?)
		stats.runs += 1
		local runIndex = stats.runs
		local failRun = AutoplayLogic.isFailRun(runIndex)
		if failRun then
			stats.failRuns += 1
		end
		setPhase("enter")
		if viaWarp ~= nil then
			local r = request(channels.warpRequest, { stage = viaWarp }, "warpResult")
			if r == nil or r.ok ~= true then
				addFlow("warp_failed", tostring(r and r.reason))
			else
				stats.warps += 1
			end
		end
		if run == nil then
			-- 게이트: 스폰 쪽에서 게이트 너머(1층 입구 안쪽)로 걸어서 지난다
			local gateX = ArenaConfig.getEntranceGateCenter()
			walkTo(Vector3.new(gateX - 12, 0, 0), 20, 3)
			walkTo(Vector3.new(gateX + 8, 0, 0), 6, 2, function()
				return run ~= nil
			end)
			if not waitUntil(function()
				return run ~= nil
			end, 5) then
				addFlow("gate_no_run", string.format("런 %d", runIndex))
				return
			end
		end
		local cleared = 0
		while run ~= nil and not done() do
			local stage = run.stage
			if not fightFloor(stage) then
				stats.fails += 1 -- 못 깼다(시간 초과 — 서버가 스폰으로 돌려보낸다)
				waitUntil(function()
					return run == nil
				end, timer + 2)
				break
			end
			stats.floors += 1
			cleared += 1
			local view = run
			if view == nil then
				break
			end
			setPhase("decide")
			local wallX = ArenaConfig.getAdvanceX(stage)
			if failRun and AutoplayLogic.failHere(cleared) and view.canAdvance == true then
				-- 실패 섞기: 반경 밖 줄(Z = FAIL_STAND_Z)로 벽을 지나 다음 층에 들어가 가만히 서서 시간 초과로 진다(가방을 잃는 길)
				walkTo(Vector3.new(wallX - 8, 0, AutoplayConfig.FAIL_STAND_Z), 10, 2)
				walkTo(Vector3.new(wallX + 10, 0, AutoplayConfig.FAIL_STAND_Z), 6, 2, function()
					return run ~= nil and run.stage ~= stage
				end)
				if not waitUntil(function()
					return run ~= nil and run.stage == stage + 1
				end, 3) then
					addFlow("fail_advance_no", string.format("%d층", stage))
				end
				setPhase("fail_wait")
				waitUntil(function()
					return run == nil
				end, timer + 3)
				stats.advances += 1
				break
			end
			local choice = AutoplayLogic.afterClear(view, timer, seg.targetFloor)
			if choice == "advance" then
				setPhase("to_wall")
				walkTo(Vector3.new(wallX + 10, 0, 0), 12, 2, function()
					return run ~= nil and run.stage ~= stage
				end)
				if not waitUntil(function()
					return run ~= nil and run.stage == stage + 1
				end, 3) then
					addFlow("advance_no", string.format("%d층", stage))
					break
				end
				stats.advances += 1
			else
				setPhase("to_pad")
				table.insert(cashoutFloors, stage)
				walkTo(Vector3.new(ArenaConfig.getCashoutX(stage), 0, ArenaConfig.CASHOUT_LATERAL_OFFSET), 12, 1.5, function()
					return run == nil
				end)
				if not waitUntil(function()
					return run == nil
				end, 3) then
					addFlow("cashout_no", string.format("%d층", stage))
				else
					stats.cashouts += 1
				end
				break
			end
		end
		-- 서버가 스폰으로 돌려보낼 때까지(런 끝 → returnToSpawn)
		setPhase("return")
		waitUntil(function()
			return run == nil
		end, timer + 3)
		task.wait(0.5)
	end

	-- ===== 본 흐름 ======================================================================================
	line("===== 시작 %s(%s)", segmentName, seg.label)
	checkWindows("start")
	closeDaily()
	local s0 = snap()
	if s0.daily.canClaim then
		setPhase("daily")
		local r = request(channels.dailyRequest, { action = "claim" }, "dailyResult") -- OverlayBoot와 같은 꼴
		if r ~= nil and r.ok == true then
			stats.daily += 1
		else
			addFlow("daily_failed", tostring(r and r.reason))
		end
		closeDaily()
	end
	-- 환생 길(#44 pre_rebirth): 환생 창 열기 · 다음 비용이 창에 보이나 → 환생(실제 리모트 · 서버가 Mock 확인 뒤에만 이 봇이 돈다) →
	-- 환생 안내(RebirthNotice)가 뜨나 · 클라 상태(환생 +1 · 최고 층 1 · 가장 좋은 열린 기구가 바뀌나). 서버 앞뒤 검사는 AutoplayMonitor
	if seg.rebirthFirst then
		setPhase("rebirth_first")
		-- snap()은 읽을 때마다 지금 값이다 — 앞 값은 요청 전에 꺼내 둔다(#44 첫 돌림에서 "13 → 14"로 잘못 찍혔다)
		local beforeRebirths: any = snap().rebirths
		local beforeBlox: any = snap().blox
		local cost = EconomyV2Logic.rebirthCost(beforeRebirths)
		local gymBefore = bestGym()
		pcall(ScreenController.open, "Rebirth")
		task.wait(AutoplayConfig.WINDOW_WAIT_SEC)
		local shown = false
		local want = Formatter.format(cost)
		for _, d in ipairs(player.PlayerGui:GetDescendants()) do
			if d:IsA("TextLabel") and d.Visible and d.Text == want then
				shown = true
				break
			end
		end
		if not shown then
			addFlow("rebirth_cost_not_shown", want)
		end
		if not EconomyV2Logic.canRebirth(beforeBlox, beforeRebirths) then
			addFlow("rebirth_cannot", BigNum.tostring(beforeBlox) .. "<" .. want)
		end
		local r = request(channels.rebirthRequest, {}, "rebirthResult")
		pcall(ScreenController.close, "Rebirth")
		if r == nil or r.ok ~= true then
			addFlow("rebirth_failed", tostring(r and r.reason))
		else
			stats.rebirths += 1
			local wantRebirths = EconomyV2Logic.rebirthCount(beforeRebirths) + 1
			if not waitUntil(function()
				return EconomyV2Logic.rebirthCount(snap().rebirths) == wantRebirths and snap().maxStage == 1
			end, AutoplayConfig.REBIRTH_WAIT_SEC) then
				addFlow("rebirth_state", string.format("환생 %d · 최고 층 %d", EconomyV2Logic.rebirthCount(snap().rebirths), snap().maxStage))
			end
			local notice = false
			waitUntil(function()
				local n = player.PlayerGui:FindFirstChild("RebirthNotice", true)
				notice = n ~= nil and n:IsA("GuiObject") and n.Visible
				return notice
			end, AutoplayConfig.REBIRTH_WAIT_SEC)
			if not notice then
				addFlow("rebirth_notice", "안내가 안 보임")
			end
			local gymAfter = bestGym()
			local opensMore = GymConfig.getUnlockedCount(BigNum.fromNumber(wantRebirths)) > GymConfig.getUnlockedCount(beforeRebirths)
			if opensMore and (gymAfter or 0) <= (gymBefore or 0) then
				addFlow("rebirth_gym", string.format("기구 %s → %s", tostring(gymBefore), tostring(gymAfter)))
			end
			line("환생 %d → %d · 비용 %s(창에 %s) · 안내 %s · 가장 좋은 기구 %s → %s", wantRebirths - 1, wantRebirths, want,
				if shown then "보임" else "안 보임", if notice then "뜸" else "안 뜸", tostring(gymBefore), tostring(gymAfter))
		end
	end
	local bestSeen = snap().maxStage
	local staleRuns = 0
	-- 업그레이드는 환생 뒤 남는 블럭스로만(시뮬 S5' — #45. 첫 환생 전에 사면 환생 비용을 못 모은다 — #44 봇 vs 시뮬)
	local upgradeNext = stats.rebirths > 0
	while not done() do
		-- 로비 한 바퀴(#45 — 시뮬 표준 플레이어처럼): 대장간(제작 1번 · 교환 · 장비) · 펫 · 자동 제작 · 부화 켜 두기 ·
		-- 살 수 있으면 바로 환생(시뮬 eager) → 그 뒤 업그레이드 · 막힌 런 뒤에만 운동기구 → 런
		forgeVisit()
		petVisit()
		keepAutoOn()
		local s = snap()
		if AutoplayLogic.shouldRebirth(staleRuns, EconomyV2Logic.canRebirth(s.blox, s.rebirths)) then
			setPhase("rebirth")
			local r = request(channels.rebirthRequest, {}, "rebirthResult")
			if r ~= nil and r.ok == true then
				stats.rebirths += 1
				staleRuns = 0
				bestSeen = 0
				upgradeNext = true
			else
				addFlow("rebirth_failed", tostring(r and r.reason))
			end
		end
		if upgradeNext then
			upgradeVisit()
			upgradeNext = false
		end
		if done() then
			break
		end
		local trainSec = if staleRuns > 0 then AutoplayConfig.STALL_TRAIN_SEC else AutoplayConfig.GYM_TRAIN_SEC
		if trainSec > 0 then
			train(trainSec)
		end
		if done() then
			break
		end
		s = snap()
		local warpTo = AutoplayLogic.warpTarget(s.maxStage, function(stage: number): number
			if s.blox.m <= 0 then
				return math.huge
			end
			return BigNum.toRatio(WarpConfig.cost(stage), s.blox)
		end)
		local failMix = AutoplayLogic.isFailRun(stats.runs + 1) -- 이번 런이 일부러 실패 섞는 런인가(playRun이 stats.runs를 올린다)
		playRun(warpTo)
		local now = snap().maxStage
		if now > bestSeen then
			bestSeen = now
			staleRuns = 0
		elseif not failMix then
			-- 일부러 실패한 런은 막힌 런으로 세지 않는다(#45 — 점검용 실패가 운동 30초 · 환생 판단을 끌어오면 시뮬과 비교가 어긋난다)
			staleRuns += 1
		end
	end
	setPhase("end")
	local h, r = body()
	if h ~= nil and r ~= nil then
		h:MoveTo(r.Position)
	end
	checkWindows("end")
	logConn:Disconnect()
	local failed = warnings.count + windows.count + flow.count
	line("구간 %s · %.0f초 · 런 %d(실패 섞기 %d) · 깬 층 %d · 진행 %d · 수령 %d · 못 깸 %d · 워프 %d · 환생 %d", segmentName, os.clock() - t0,
		stats.runs, stats.failRuns, stats.floors, stats.advances, stats.cashouts, stats.fails, stats.warps, stats.rebirths)
	line("제작 %d · 교환 %d · 장착 %d · 강화 %d · 별 %d · 부화 %d · 업그레이드 %d · 줍기 %d · 클릭 %d · 일일 %d", stats.crafts, stats.exchanges,
		stats.equips, stats.enhances, stats.stars, stats.hatches, stats.upgrades, stats.picked, stats.clicks, stats.daily)
	line("검사 경고·오류 %s", AutoplayLogic.tallyLine(warnings, 80))
	line("검사 창 %d개 × 2번 %s · 흐름 %s", #AutoplayConfig.WINDOWS, AutoplayLogic.tallyLine(windows, 40), AutoplayLogic.tallyLine(flow, 40))
	line("관찰 이동 막힘 %s", AutoplayLogic.tallyLine(moves, 80))
	-- #44 3부(봇 vs 시뮬): 층 첫 도달(분 — 봇 시작부터) · 단계마다 쓴 초 · 수령한 층
	setPhase("end")
	local reach = {}
	for k = 1, 30 do
		if firstReach[k] ~= nil then
			table.insert(reach, string.format("%d:%.1f", k, firstReach[k] / 60))
		end
	end
	line("관찰 층 첫 도달(분) %s", table.concat(reach, " "))
	local order = { "windows_start", "daily", "forge", "equipment", "pet", "upgrade", "rebirth_first", "rebirth", "gym_walk", "gym", "enter",
		"approach", "attack", "pickup", "decide", "to_wall", "to_pad", "fail_wait", "return", "windows_end" }
	local parts = {}
	for _, k in ipairs(order) do
		if phaseSec[k] ~= nil and phaseSec[k] >= 0.5 then
			table.insert(parts, string.format("%s %.0f", k, phaseSec[k]))
		end
	end
	line("관찰 시간 나눔(초) %s", table.concat(parts, " · "))
	line("관찰 런 사이 로비 %.1f초/런(%s · 런 %d — 시뮬 MODEL.LOBBY_SEC_PER_RUN)", AutoplayLogic.lobbySecPerRun(phaseSec, stats.runs),
		table.concat(AutoplayConfig.LOBBY_PHASES, "+"), stats.runs)
	local cf = {}
	for _, f in ipairs(cashoutFloors) do
		table.insert(cf, tostring(f))
	end
	line("관찰 수령한 층 %s", table.concat(cf, " · "))
	line("===== 끝 %s · 클라 검사 %s", segmentName, if failed == 0 then "통과" else string.format("실패 %d", failed))
end

return AutoplayBot

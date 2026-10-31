--!strict
-- 자동 진행 모드 (Phase 8 지시서 #18 — DESIGN.md "1. 챌린지 > 자동 진행 모드" AA0 ~ AA13).
--
-- 목표층까지 서버가 진행시키고, 목표층에서 자동으로 수령하고, 중지할 때까지 반복한다. 진행 벽 · 수령 발판을 쓰지 않는다 —
-- 판정은 여전히 ChallengeService(advance · cashout이 서버 런 상태로 정한다 — 절대 규칙 3). 이 파일은 "언제 부를지"만 정한다.
--
-- ===== 한 플레이어의 흐름 (서버 단일 루프 tick이 돈다 — 플레이어마다 task.spawn 없음, AA12) =====================
--   시작(AA1)   start 요청 → 보유 · 목표층 · 런 없음 · 캐릭터 확인 → 안전층 계산(고정, AA5) → startRun(1) → 1층 입구로 이동
--   클리어      목표층(이상)이면 바로 cashout("auto")(AA3). 아니면 ADVANCE_DELAY_SEC 뒤 advance("auto") → 다음 층 입구로 이동(AA2)
--              ⚠️ 순서 advance → 이동. 다음 층 입구는 직전 층 진행 벽 트리거 자리라, 층이 먼저 바뀌어 있어야 트리거가 걸러진다
--   런 끝       수령 · 실패 · 사람의 직접 수령 모두 "런이 없어졌다"로 보고 REPEAT_DELAY_SEC 뒤 다시 1층부터(AA0 · AA4 · AA8)
--   꺼짐        중지 요청(stopped — 런은 그대로, AA8) · 캐릭터 없음(character_lost) · 퇴장. 꺼지면 알린다(결과 채널)
--
-- 상태는 세션 메모리뿐이다(AA10 — 켜짐 · 목표층 · 고정 안전층 · 반복 횟수). 프로필 스키마를 바꾸지 않는다.
-- 반복 횟수 = 이번 자동 세션에서 세운 런 수(첫 런 포함).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AutoAdvanceConfig = require(ReplicatedStorage.Shared.Config.AutoAdvanceConfig)
local AutoAdvanceLogic = require(ReplicatedStorage.Shared.AutoAdvanceLogic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AutoAdvanceService = {}

AutoAdvanceService.REASON_RATE_LIMITED = "rate_limited"
AutoAdvanceService.REASON_INVALID = "invalid"
AutoAdvanceService.REASON_NOT_OWNED = "not_owned"
AutoAdvanceService.REASON_INVALID_TARGET = "invalid_target"
AutoAdvanceService.REASON_RUN_ACTIVE = "run_active"
AutoAdvanceService.REASON_NO_CHARACTER = "no_character"
AutoAdvanceService.REASON_ALREADY_ACTIVE = "already_active"
AutoAdvanceService.REASON_NOT_ACTIVE = "not_active"
AutoAdvanceService.REASON_STOPPED = "stopped" -- 꺼짐 알림: 사람이 중지
AutoAdvanceService.REASON_CHARACTER_LOST = "character_lost" -- 꺼짐 알림: 캐릭터 없어짐(AA8)
AutoAdvanceService.REASON_AUTO_ACTIVE = "auto_active" -- 워프 · 환생 거부(AA9 — 그 채널들이 쓴다)
AutoAdvanceService.SOURCE = "auto"

export type RunView = { stage: number, cleared: boolean, canAdvance: boolean }

export type Deps = {
	owns: (Player) -> boolean,
	getRunState: (Player) -> RunView?,
	startRun: (Player, number) -> boolean,
	advance: (Player, string) -> boolean,
	cashout: (Player, string) -> boolean,
	moveToEntrance: (Player, number) -> boolean,
	hasCharacter: (Player) -> boolean,
	safeFloorOf: (Player) -> number,
	notify: (Player) -> (), -- PlayerState(요약이 바뀌었다)
	send: (Player, Remotes.AutoAdvanceResultPayload) -> (),
	log: (string) -> (),
}

type Entry = {
	target: number,
	safeFloor: number,
	runs: number,
	clearedStage: number?, -- 지금 클리어 대기 중인 층(진행 간격을 재는 기준)
	clearedAt: number?,
	repeatAt: number?, -- 런이 없어진 뒤 다음 런 시각
}

export type Summary = { active: boolean, target: number, safeFloor: number, runs: number, maxTarget: number }

local function readRequest(payload: any): (string?, number?)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return nil, nil
	end
	if payload.action == "stop" then
		return "stop", nil
	end
	if payload.action == "start" then
		return "start", if type(payload.target) == "number" then payload.target else nil
	end
	return nil, nil
end

local function createRuntime(deps: Deps)
	local entries: { [Player]: Entry } = {}
	local lastAt: { [Player]: number } = {}
	local runtime = {}

	local function result(action: string, ok: boolean, reason: string, e: Entry?): Remotes.AutoAdvanceResultPayload
		return { action = action, ok = ok, reason = reason, target = if e ~= nil then e.target else 0,
			safeFloor = if e ~= nil then e.safeFloor else 0 }
	end

	-- notice = 서버가 끈 것(character_lost)이면 꺼짐 알림을 보낸다. 사람이 중지했으면 그 요청의 응답 하나로 충분하다
	local function turnOff(player: Player, reason: string, notice: boolean)
		local e = entries[player]
		if e == nil then
			return
		end
		entries[player] = nil
		deps.log(string.format("[AutoAdvance] %s 꺼짐(%s) — 반복 %d회", player.Name, reason, e.runs))
		if notice then
			deps.send(player, result("stopped", true, reason, e))
		end
		deps.notify(player)
	end

	-- 1층 런을 세우고 입구로 옮긴다(시작 · 반복 공용). 런 세우기를 먼저 — 입구는 입장 게이트 자리라 런이 있어야 게이트가 무시한다.
	local function beginRun(player: Player, e: Entry): boolean
		if not deps.startRun(player, AutoAdvanceLogic.FIRST_STAGE) then
			return false
		end
		deps.moveToEntrance(player, AutoAdvanceLogic.FIRST_STAGE)
		e.runs += 1
		e.clearedStage, e.clearedAt, e.repeatAt = nil, nil, nil
		deps.log(string.format("[AutoAdvance] %s 런 시작 #%d(목표 %d층 · 안전 %d층)", player.Name, e.runs, e.target, e.safeFloor))
		return true
	end

	function runtime.isActive(player: Player): boolean
		return entries[player] ~= nil
	end

	function runtime.summary(player: Player): Summary
		local e = entries[player]
		if e ~= nil then
			return { active = true, target = e.target, safeFloor = e.safeFloor, runs = e.runs, maxTarget = AutoAdvanceLogic.maxTarget() }
		end
		-- 꺼져 있으면 지금 힘으로 잰 안전층(설정 창이 보인다 — 시작하면 그 순간 값으로 다시 재서 고정한다)
		return { active = false, target = 0, safeFloor = deps.safeFloorOf(player), runs = 0, maxTarget = AutoAdvanceLogic.maxTarget() }
	end

	function runtime.onRequest(player: Player, payload: any, now: number): Remotes.AutoAdvanceResultPayload
		local action, target = readRequest(payload)
		local shown = action or ""
		local out: Remotes.AutoAdvanceResultPayload
		local last = lastAt[player]
		if last ~= nil and now - last < AutoAdvanceConfig.REQUEST_MIN_INTERVAL_SEC then
			out = result(shown, false, AutoAdvanceService.REASON_RATE_LIMITED, entries[player])
		elseif action == nil then
			lastAt[player] = now
			out = result("", false, AutoAdvanceService.REASON_INVALID, nil)
		elseif action == "stop" then
			lastAt[player] = now
			local e = entries[player]
			if e == nil then
				out = result("stop", false, AutoAdvanceService.REASON_NOT_ACTIVE, nil)
			else
				out = result("stop", true, "", e)
				turnOff(player, AutoAdvanceService.REASON_STOPPED, false) -- 자동만 끈다 — 런은 그대로(AA8)
			end
		else
			lastAt[player] = now
			if entries[player] ~= nil then
				out = result("start", false, AutoAdvanceService.REASON_ALREADY_ACTIVE, entries[player])
			elseif not deps.owns(player) then
				out = result("start", false, AutoAdvanceService.REASON_NOT_OWNED, nil)
			elseif not AutoAdvanceLogic.isValidTarget(target) then
				out = result("start", false, AutoAdvanceService.REASON_INVALID_TARGET, nil)
			elseif deps.getRunState(player) ~= nil then
				out = result("start", false, AutoAdvanceService.REASON_RUN_ACTIVE, nil)
			elseif not deps.hasCharacter(player) then
				out = result("start", false, AutoAdvanceService.REASON_NO_CHARACTER, nil)
			else
				local e: Entry = { target = target :: number, safeFloor = deps.safeFloorOf(player), runs = 0 }
				entries[player] = e
				if beginRun(player, e) then
					out = result("start", true, "", e)
					deps.notify(player)
				else
					entries[player] = nil
					out = result("start", false, AutoAdvanceService.REASON_INVALID, nil)
				end
			end
		end
		deps.send(player, out)
		return out
	end

	-- 단일 루프 한 틱(모든 자동 플레이어).
	function runtime.tick(now: number)
		for player, e in pairs(entries) do
			if not deps.hasCharacter(player) then
				turnOff(player, AutoAdvanceService.REASON_CHARACTER_LOST, true)
				continue
			end
			local run = deps.getRunState(player)
			if run == nil then
				-- 런이 없어졌다(자동 수령 · 실패 · 사람의 직접 수령) → 간격 뒤 다시 1층부터
				e.clearedStage, e.clearedAt = nil, nil
				if e.repeatAt == nil then
					e.repeatAt = now + AutoAdvanceConfig.REPEAT_DELAY_SEC
				elseif now >= e.repeatAt then
					e.repeatAt = nil
					if beginRun(player, e) then
						deps.notify(player)
					end
				end
				continue
			end
			e.repeatAt = nil
			if not run.cleared then
				e.clearedStage, e.clearedAt = nil, nil
				continue
			end
			-- 클리어 대기
			if run.stage >= e.target or not run.canAdvance then
				-- 목표층(사람이 직접 진행해 넘었어도 판정은 그대로) 또는 더 갈 층이 없음 → 자동 수령(AA3)
				deps.cashout(player, AutoAdvanceService.SOURCE)
				continue
			end
			if e.clearedStage ~= run.stage then
				e.clearedStage, e.clearedAt = run.stage, now
			elseif now - (e.clearedAt :: number) >= AutoAdvanceConfig.ADVANCE_DELAY_SEC then
				e.clearedStage, e.clearedAt = nil, nil
				if deps.advance(player, AutoAdvanceService.SOURCE) then
					deps.moveToEntrance(player, run.stage + 1) -- ⚠️ advance 뒤(위 흐름 주석)
				end
			end
		end
	end

	function runtime.onRemoving(player: Player)
		entries[player] = nil
		lastAt[player] = nil
	end

	return runtime
end

AutoAdvanceService._pure = { createRuntime = createRuntime, readRequest = readRequest }

-- ===== 실물 =========================================================================================

local live: any = nil

function AutoAdvanceService.isActive(player: Player): boolean
	return live ~= nil and live.isActive(player)
end

function AutoAdvanceService.summary(player: Player): Summary
	if live == nil then
		return { active = false, target = 0, safeFloor = 0, runs = 0, maxTarget = AutoAdvanceLogic.maxTarget() }
	end
	return live.summary(player)
end

export type InitDeps = {
	owns: (Player) -> boolean,
	getRunState: (Player) -> RunView?,
	startRun: (Player, number) -> boolean,
	advance: (Player, string) -> boolean,
	cashout: (Player, string) -> boolean,
	moveToEntrance: (Player, number) -> boolean,
	hasCharacter: (Player) -> boolean,
	safeFloorOf: (Player) -> number,
	notify: (Player) -> (),
}

-- 서비스들을 Bootstrap이 넘긴다(ChallengeService · ArenaService · AttackService · PlayerStateService — 순환 require를 피한다).
function AutoAdvanceService.init(services: InitDeps)
	if live ~= nil then
		warn("[AutoAdvanceService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	AutoAdvanceConfig.validate()
	local channels = Remotes.getServer()
	live = createRuntime({
		owns = services.owns,
		getRunState = services.getRunState,
		startRun = services.startRun,
		advance = services.advance,
		cashout = services.cashout,
		moveToEntrance = services.moveToEntrance,
		hasCharacter = services.hasCharacter,
		safeFloorOf = services.safeFloorOf,
		notify = services.notify,
		send = function(player: Player, payload: Remotes.AutoAdvanceResultPayload)
			channels.autoAdvanceResult:FireClient(player, payload)
		end,
		log = print,
	})
	channels.autoAdvanceRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out = live.onRequest(player, payload, os.clock())
		print(string.format("[AutoAdvance] %s(%d) 요청 %s → ok=%s reason=%s 목표 %d · 안전 %d", player.Name, player.UserId, out.action,
			tostring(out.ok), out.reason, out.target, out.safeFloor))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		live.onRemoving(player)
	end)
	local accum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum < AutoAdvanceConfig.LOOP_SEC then
			return
		end
		accum = 0
		live.tick(os.clock())
	end)
	print(string.format("[AutoAdvance] 준비 완료(단일 루프 %.1f초 · 진행 간격 %.1f초 · 반복 간격 %d초)", AutoAdvanceConfig.LOOP_SEC,
		AutoAdvanceConfig.ADVANCE_DELAY_SEC, AutoAdvanceConfig.REPEAT_DELAY_SEC))
end

return AutoAdvanceService

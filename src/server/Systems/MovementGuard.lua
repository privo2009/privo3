--!strict
-- 이동 익스플로잇 대비(지시서 #43 2부 — DESIGN "보안" · docs/REMOTES.md "이동 검사"). 설정은 Shared/Config/MovementGuardConfig(전부 TEMP).
--
-- 왜: 캐릭터 물리는 클라 소유다. 서버가 읽는 HumanoidRootPart 위치는 클라가 보낸 값이고, 줍기(OreDropService 거리 폴링) ·
-- 근접 자동 공격(AttackService)이 그 위치를 믿는다. 순간이동 · 스피드핵이면 블록 곁을 지키지 않고 드롭을 쓸어 담을 수 있다.
--
-- 하는 일(서버 단일 루프 — SAMPLE_SEC마다):
--   위치를 적고 앞 표본과 비교한다. 수평 이동이 (레벨 이동 속도 상한 + SPEED_MARGIN) × dt + SLACK_STUDS를 넘거나, 오르기 · 떨어지기가
--   상한을 넘으면 "의심" — HOLD_SEC 동안 isTrusted가 false다. 줍기 · 공격은 그 틱을 건너뛴다(값은 아무것도 바꾸지 않는다).
--   경고 로그 한 줄(같은 플레이어 반복은 LogFold로 접는다). **킥하지 않는다** — 오탐으로 정상 유저가 피해 보면 안 된다.
-- 예외: 게임이 옮긴 순간(markTeleport — ArenaService 스폰 복귀 · 층 입구 이동(워프 · 자동 진행) · 리스폰)은 TELEPORT_GRACE_SEC 동안 재지 않고
--   기준점만 다시 잡는다(서버가 옮긴 자리와 오는 중인 옛 자리 복제가 섞여 보인다).
-- ⚠️ yield하지 않는다(markTeleport는 ArenaService의 무-yield 구간 — 환생 · 워프 — 안에서 불린다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.MovementGuardConfig)
local LogFold = require(script.Parent.LogFold)

local MovementGuard = {}

export type Sample = { pos: Vector3, t: number }
export type State = { last: Sample?, graceUntil: number, suspectUntil: number, suspects: number }

-- ===== 순수 판정 (Player 없음 — MovementGuardTests) ================================================================

-- 앞 표본 → 지금 표본이 허용 안인가. (ok, 사유 "fast" | "up" | "down" | nil, 수평 속도 studs/초)
local function evaluate(prev: Sample, cur: Sample, maxSpeed: number): (boolean, string?, number)
	local dt = cur.t - prev.t
	if dt <= 0 then
		return true, nil, 0
	end
	local d = cur.pos - prev.pos
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	local speed = flat / dt
	if flat > (maxSpeed + Config.SPEED_MARGIN) * dt + Config.SLACK_STUDS then
		return false, "fast", speed
	end
	if d.Y > Config.UP_SPEED_MAX * dt + Config.SLACK_STUDS then
		return false, "up", speed
	end
	if -d.Y > Config.FALL_SPEED_MAX * dt + Config.SLACK_STUDS then
		return false, "down", speed
	end
	return true, nil, speed
end

local function newState(): State
	return { last = nil, graceUntil = -math.huge, suspectUntil = -math.huge, suspects = 0 }
end

-- 표본 하나를 받는다. (상태는 제자리에서 바뀐다) 이번에 의심이 새로 났으면 (true, 사유, 속도)
local function observe(state: State, cur: Sample?, maxSpeed: number): (boolean, string?, number)
	if cur == nil then
		state.last = nil -- 캐릭터 없음(죽음 · 리스폰 중) — 다음 표본부터 다시
		return false, nil, 0
	end
	local prev = state.last
	state.last = cur
	if prev == nil or cur.t < state.graceUntil then
		return false, nil, 0
	end
	local ok, why, speed = evaluate(prev, cur, maxSpeed)
	if ok then
		return false, nil, speed
	end
	state.suspectUntil = cur.t + Config.HOLD_SEC
	state.suspects += 1
	return true, why, speed
end

local function markTeleportState(state: State, now: number)
	state.last = nil
	state.graceUntil = now + Config.TELEPORT_GRACE_SEC
end

local function trusted(state: State?, now: number): boolean
	return state == nil or now >= state.suspectUntil
end

MovementGuard._pure = {
	evaluate = evaluate,
	newState = newState,
	observe = observe,
	markTeleportState = markTeleportState,
	trusted = trusted,
}

-- ===== 바깥 세계 =================================================================================================

local states: { [Player]: State } = {}
local totalSuspects = 0
local warnFold = LogFold.new(LogFold.WINDOW_SEC, os.clock, function(message: string)
	warn(message)
end)

local function stateOf(player: Player): State
	local s = states[player]
	if s == nil then
		s = newState()
		states[player] = s
	end
	return s
end

-- 게임이 캐릭터를 옮겼다(스폰 복귀 · 층 입구 · 리스폰). 가짜 Player 테이블(테스트)도 받는다. yield 없음
-- 나간 플레이어(Parent 없음 — 나가는 중 사망 · 포기 경로)는 표를 다시 만들지 않는다(PlayerRemoving이 지운 뒤 새로 생겨 남는 것을 막는다 — #43 3부)
function MovementGuard.markTeleport(player: Player)
	if typeof(player) == "Instance" and player.Parent == nil then
		return
	end
	markTeleportState(stateOf(player), os.clock())
end

-- 지금 이 플레이어의 위치를 믿어도 되는가(줍기 · 공격이 부른다). 의심 HOLD_SEC 동안 false
function MovementGuard.isTrusted(player: Player): boolean
	return trusted(states[player], os.clock())
end

-- 이번 서버에서 의심한 수(봇 · Play 확인용 — 읽기만)
function MovementGuard.suspectCount(): number
	return totalSuspects
end

-- 표본 한 번(루프 · 테스트). pos가 nil이면 캐릭터 없음
function MovementGuard.sample(player: Player, pos: Vector3?, now: number, maxSpeed: number)
	local state = stateOf(player)
	local cur = if pos ~= nil then { pos = pos, t = now } else nil
	local hit, why, speed = observe(state, cur, maxSpeed)
	if hit then
		totalSuspects += 1
		warnFold.log(tostring(player.UserId) .. "|" .. tostring(why), string.format(
			"%s 이동 의심 user=%s 사유=%s 수평 %.1f studs/초(상한 %.1f) — %.1f초 동안 줍기 · 공격 무시(킥 없음)",
			Config.LOG_TAG, tostring(player.UserId), tostring(why), speed, maxSpeed + Config.SPEED_MARGIN, Config.HOLD_SEC))
	end
end

-- 테스트 전용
function MovementGuard._state(player: Player): State?
	return states[player]
end
function MovementGuard._reset(player: Player)
	states[player] = nil
end

local initialized = false

function MovementGuard.init()
	if initialized then
		return
	end
	initialized = true
	local SpeedService = require(script.Parent.SpeedService)
	local Proximity = require(script.Parent.Proximity)
	local function hook(player: Player)
		MovementGuard.markTeleport(player)
		player.CharacterAdded:Connect(function()
			MovementGuard.markTeleport(player) -- 리스폰 = 게임이 옮긴 것
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	-- 서버 단일 루프(플레이어별 task.spawn 아님 — AttackService · SpeedService와 같은 관례)
	task.spawn(function()
		while true do
			task.wait(Config.SAMPLE_SEC)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(function()
					MovementGuard.sample(player, (Proximity.rootPosition(player)), now, SpeedService.getMaxSpeed(player))
				end)
				if not ok then
					warn("[MovementGuard] 표본 오류: " .. tostring(err))
				end
			end
		end
	end)
	print(string.format("[MovementGuard] 이동 검사 시작 (주기 %.2f초 · 여유 +%g studs/초 · 순간이동 유예 %.1f초 · 걸리면 %.1f초 무시 · 킥 없음)",
		Config.SAMPLE_SEC, Config.SPEED_MARGIN, Config.TELEPORT_GRACE_SEC, Config.HOLD_SEC))
end

return MovementGuard

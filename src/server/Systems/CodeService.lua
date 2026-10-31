--!strict
-- 코드 입력 서버 (지시서 #20 C1 ~ C6 — DESIGN.md 9장 "코드 입력"). 코드 원본은 Shared/Config/CodesConfig, 지급은 RewardService.
--
-- ===== 판정 순서 (CodeRequest) — 앞에서 걸리면 거기서 끝 ====================================================
--
--   1. 빈도        플레이어당 REQUEST_MIN_INTERVAL_SEC에 1회 → rate_limited(틀린 횟수에 세지 않는다)
--   2. 막힘        틀린 코드 막힘 중이면 → too_many_attempts
--   3. 찾기        CodesConfig.normalize(앞뒤 공백 · 대문자) → Codes에 없으면 not_found. 빈 문자열 · 너무 긴 문자열 · 문자열 아님도 not_found.
--                  틀린 횟수 +1 — FAIL_WINDOW_SEC 안에 FAIL_LIMIT번이 되면 그 순간부터 LOCK_SEC 막힘(C3 — 세션 메모리)
--   4. 프로필      없으면 no_profile
--   5. 이미 받음    redeemedCodes[코드] → already_redeemed
--   6. 만료        expiresAt ≤ 지금(os.time — 서버 시계) → expired
--   7. 지급        RewardService.grant(보상, "code_<코드>") — 거부면 그 사유(storage_full 등) · 기록하지 않는다
--   8. 기록        redeemedCodes[코드] = true — 지급과 같은 프로필 표
--
-- ⚠️ 입력 글자(원문)는 저장하지도 · 다른 사람에게 보내지도 · 로그에 찍지도 않는다(C4). 결과에도 싣지 않는다 — 기록 · 로그는 Config 키뿐.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local CodesConfig = require(ReplicatedStorage.Shared.Config.CodesConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CodeService = {}

CodeService.REASON_RATE_LIMITED = "rate_limited"
CodeService.REASON_TOO_MANY = "too_many_attempts"
CodeService.REASON_NOT_FOUND = "not_found"
CodeService.REASON_NO_PROFILE = "no_profile"
CodeService.REASON_ALREADY = "already_redeemed"
CodeService.REASON_EXPIRED = "expired"

export type Deps = {
	codes: { [string]: CodesConfig.CodeDef },
	now: () -> number, -- os.time(만료 판정)
	getData: (Player) -> any?,
	grant: (Player, any, string) -> (boolean, any),
	send: (Player, Remotes.CodeResultPayload) -> (),
}

local function rewardViews(list: any): { Remotes.CodeRewardView }
	local out: { Remotes.CodeRewardView } = {}
	for _, r in ipairs(list) do
		table.insert(out, {
			type = tostring(r.type),
			kind = if type(r.kind) == "string" then r.kind else "",
			count = if type(r.count) == "number" then r.count else 0,
			k = if type(r.k) == "number" then r.k else 0,
			petId = if type(r.petId) == "string" then r.petId else "",
		})
	end
	return out
end

local function createRuntime(deps: Deps)
	local lastAt: { [Player]: number } = {}
	local fails: { [Player]: { number } } = {}
	local lockedUntil: { [Player]: number } = {}
	local runtime = {}

	local function fail(player: Player, reason: string): Remotes.CodeResultPayload
		return { ok = false, reason = reason, rewards = {}, blox = BigNum.new(0, 0) }
	end

	local function countFail(player: Player, clock: number)
		local list = fails[player] or {}
		local kept: { number } = {}
		for _, t in ipairs(list) do
			if clock - t < CodesConfig.FAIL_WINDOW_SEC then
				table.insert(kept, t)
			end
		end
		table.insert(kept, clock)
		fails[player] = kept
		if #kept >= CodesConfig.FAIL_LIMIT then
			lockedUntil[player] = clock + CodesConfig.LOCK_SEC
			fails[player] = {}
		end
	end

	-- 판정 + 지급. 기록할 Config 키도 돌려준다(로그용 — 입력 원문이 아니다).
	function runtime.redeem(player: Player, raw: any, clock: number): (Remotes.CodeResultPayload, string?)
		local until_ = lockedUntil[player]
		if until_ ~= nil then
			if clock < until_ then
				return fail(player, CodeService.REASON_TOO_MANY), nil
			end
			lockedUntil[player] = nil
		end
		local code = CodesConfig.normalize(raw)
		local def = if code ~= nil then deps.codes[code] else nil
		if code == nil or def == nil then
			countFail(player, clock)
			return fail(player, CodeService.REASON_NOT_FOUND), nil
		end
		local data = deps.getData(player)
		if type(data) ~= "table" or type(data.redeemedCodes) ~= "table" then
			return fail(player, CodeService.REASON_NO_PROFILE), code
		end
		if data.redeemedCodes[code] == true then
			return fail(player, CodeService.REASON_ALREADY), code
		end
		if def.expiresAt ~= nil and deps.now() >= def.expiresAt then
			return fail(player, CodeService.REASON_EXPIRED), code
		end
		local ok, value = deps.grant(player, def.rewards, "code_" .. code)
		if not ok then
			return fail(player, tostring(value)), code
		end
		data.redeemedCodes[code] = true
		return { ok = true, reason = "", rewards = rewardViews(def.rewards), blox = value.blox }, code
	end

	function runtime.onRequest(player: Player, payload: any, clock: number): (Remotes.CodeResultPayload, string?)
		local last = lastAt[player]
		local out: Remotes.CodeResultPayload
		local code: string? = nil
		if last ~= nil and clock - last < CodesConfig.REQUEST_MIN_INTERVAL_SEC then
			out = fail(player, CodeService.REASON_RATE_LIMITED)
		else
			lastAt[player] = clock
			out, code = runtime.redeem(player, if type(payload) == "table" then payload.code else nil, clock)
		end
		deps.send(player, out)
		return out, code
	end

	function runtime.onRemoving(player: Player)
		lastAt[player] = nil
		fails[player] = nil
		lockedUntil[player] = nil
	end

	return runtime
end

CodeService._pure = {
	createRuntime = createRuntime,
}

local live: any = nil

export type InitDeps = {
	getData: (Player) -> any?,
	grant: (Player, any, string) -> (boolean, any),
}

function CodeService.init(services: InitDeps)
	if live ~= nil then
		warn("[CodeService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	local channels = Remotes.getServer()
	live = createRuntime({
		codes = CodesConfig.Codes,
		now = os.time,
		getData = services.getData,
		grant = services.grant,
		send = function(player: Player, payload: Remotes.CodeResultPayload)
			channels.codeResult:FireClient(player, payload)
		end,
	})
	channels.codeRequest.OnServerEvent:Connect(function(player: Player, payload: any)
		local out, code = live.onRequest(player, payload, os.clock())
		-- 입력 원문은 찍지 않는다(C4) — 맞은 Config 키만
		print(string.format("[CodeService] %s(%d) 코드 → ok=%s reason=%s code=%s", player.Name, player.UserId, tostring(out.ok), out.reason,
			code or "-"))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		live.onRemoving(player)
	end)
	local n = 0
	for _ in pairs(CodesConfig.Codes) do
		n += 1
	end
	print(string.format("[CodeService] 코드 입력 준비 완료 (코드 %d개 · 틀린 %d번/%d초 → %d초 막힘)", n, CodesConfig.FAIL_LIMIT,
		CodesConfig.FAIL_WINDOW_SEC, CodesConfig.LOCK_SEC))
end

return CodeService

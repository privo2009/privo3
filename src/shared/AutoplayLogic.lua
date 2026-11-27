--!strict
-- 자동 플레이 봇 순수 로직(지시서 #43 1부 — Player · 프로필 · 인스턴스 없음 → AutoplayLogicTests).
-- 켜도 되는가(resolve) · 봇 정책(진행 · 실패 섞기 · 환생 · 워프) · 검사(음수 · 가방 · 수령 · 제작) · 결과 줄 꼴.
-- 설정은 Shared/Config/AutoplayConfig. 서버 검사 = Server/Tools/AutoplayMonitor · 조작 = Client/Tools/AutoplayBot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoplayConfig = require(ReplicatedStorage.Shared.Config.AutoplayConfig)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local AutoplayLogic = {}

-- ===== 켜도 되는가 ==========================================================================================

local requested: any = nil
local registered = false

-- Bootstrap의 TEST_AUTOPLAY 값을 기록한다(AutoplayLogicTests가 커밋 값 nil을 본다 — 켠 Play에서는 그 줄이 실패한다)
function AutoplayLogic.register(flag: any)
	requested = flag
	registered = true
end

function AutoplayLogic.isRegistered(): boolean
	return registered
end

function AutoplayLogic.getRequested(): any
	return requested
end

-- (구간 이름 또는 nil, 열 Mock 프리셋 또는 nil, 로그 한 줄 또는 nil, "warn" | "print" | nil)
-- 구간이 프리셋을 정한다(명령 하나). TEST_PRESET이 따로 켜져 있고 다르면 봇을 끈다 — 어느 상태로 도는지 헷갈리지 않게.
function AutoplayLogic.resolve(flag: any, preset: any, isStudio: boolean): (string?, string?, string?, string?)
	if flag == nil then
		return nil, nil, nil, nil
	end
	if not isStudio then
		return nil, nil, string.format("%s ERROR Studio가 아닌데 TEST_AUTOPLAY(%s)가 켜져 있다 — 무시한다. Bootstrap의 TEST_AUTOPLAY를 nil로",
			AutoplayConfig.TAG, tostring(flag)), "warn"
	end
	local seg = if type(flag) == "string" then AutoplayConfig.SEGMENTS[flag] else nil
	if seg == nil then
		return nil, nil, string.format("%s ERROR 알 수 없는 구간 %s — 무시한다(목록: %s)", AutoplayConfig.TAG, tostring(flag),
			table.concat(AutoplayConfig.ORDER, ", ")), "warn"
	end
	if preset ~= nil and preset ~= seg.preset then
		return nil, nil, string.format("%s ERROR TEST_PRESET(%s)이 구간 %s의 프리셋(%s)과 다르다 — 봇을 끈다. TEST_PRESET을 nil로(구간이 프리셋을 연다)",
			AutoplayConfig.TAG, tostring(preset), flag, seg.preset), "warn"
	end
	return flag, seg.preset, string.format("%s ⚠️ 구간 %s(%s) — Mock 프로필 %s로 시작한다. 저장하지 않는다. 커밋 전에 TEST_AUTOPLAY = nil",
		AutoplayConfig.TAG, flag, seg.label, seg.preset), "print"
end

-- ===== 봇 정책 ============================================================================================

-- 클리어한 뒤: "advance" | "cashout". view = 런 상태 노출본(timeLeft · canAdvance · stage), timer = 층 타이머(초)
function AutoplayLogic.afterClear(view: any, timer: number, targetFloor: number): string
	if type(view) ~= "table" or view.canAdvance ~= true then
		return "cashout"
	end
	if type(view.stage) == "number" and view.stage >= targetFloor then
		return "cashout" -- 목표 층을 깼다 — 가방을 챙겨 끝낸다
	end
	local left = if type(view.timeLeft) == "number" then view.timeLeft else 0
	return if left >= timer * AutoplayConfig.ADVANCE_TIME_SHARE then "advance" else "cashout"
end

-- 이번 런이 실패 섞기 런인가(1부터 센 런 번호)
function AutoplayLogic.isFailRun(runIndex: number): boolean
	local every = AutoplayConfig.FAIL_EVERY_RUNS
	return every > 0 and runIndex > 0 and runIndex % every == 0
end

-- 실패 런에서 어느 층에서 손을 놓나: 둘째 층(첫 층을 깨고 진행했으면) — 가방에 광석이 든 채로 지는 길
function AutoplayLogic.failHere(runFloorsCleared: number): boolean
	return runFloorsCleared >= 1
end

-- 환생할까: 최고 층이 patience 런 동안 안 올랐고 비용이 닿으면
function AutoplayLogic.shouldRebirth(staleRuns: number, canAfford: boolean): boolean
	return canAfford and staleRuns >= AutoplayConfig.REBIRTH_PATIENCE_RUNS
end

-- 워프할 층(없으면 nil): 최고 층 − WARP_BACK(2 이상), 비용 ≤ 보유 × 몫. costShare = 비용 / 보유(보유 0이면 math.huge)
function AutoplayLogic.warpTarget(maxStage: number, costShareOf: (number) -> number): number?
	local target = maxStage - AutoplayConfig.WARP_BACK
	if target < 2 then
		return nil
	end
	if costShareOf(target) <= AutoplayConfig.WARP_BUDGET_SHARE then
		return target
	end
	return nil
end

-- ===== 검사 (문제 목록 — 비면 통과) ===========================================================================

local function bigNegative(v: any): boolean
	return type(v) == "table" and type(v.m) == "number" and v.m < 0
end

local function badCount(n: any): boolean
	return type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0
end

-- 재화(BigNum) · 광석 · 토큰이 음수(또는 깨진 수)가 아닌가. data = 프로필 Data 꼴(읽기만)
function AutoplayLogic.negativeProblems(data: any, oreCount: number): { string }
	local out = {}
	if type(data) ~= "table" then
		return { "no_data" }
	end
	for _, key in ipairs({ "blox", "coins", "strength", "lifeBlox", "lifetimeBlox", "rebirths" }) do
		if bigNegative(data[key]) then
			table.insert(out, key .. "<0")
		end
	end
	if type(data.ores) == "table" then
		for k = 1, oreCount do
			if data.ores[k] ~= nil and badCount(data.ores[k]) then
				table.insert(out, string.format("ore%d=%s", k, tostring(data.ores[k])))
			end
		end
	end
	if type(data.tokens) == "table" then
		for key, n in pairs(data.tokens) do
			if badCount(n) then
				table.insert(out, string.format("token_%s=%s", tostring(key), tostring(n)))
			end
		end
	end
	return out
end

-- 가방 상한. 런 중 낮은 곡괭이로 바꾸면 든 광석은 그대로 두고 용량만 줄어 넘칠 수 있다(#34 — EconomyV2Logic.addToBag) —
-- 그래서 "넘친 채로 더 늘었나"만 문제다(prevUsed = 앞 검사 때 수 · 처음이면 0). #43 3부에서 고침(처음엔 넘치기만 해도 문제로 셌다)
function AutoplayLogic.bagProblems(used: number, cap: number, prevUsed: number?): { string }
	if used > cap and used > (prevUsed or 0) then
		return { string.format("bag %d>%d", used, cap) }
	end
	return {}
end

-- 런 끝: 수령이면 인벤토리 뒤 = 앞 + 가방, 아니면 인벤토리 그대로(가방을 잃는다). bagLeft = 끝난 뒤 가방에 남은 수(0이어야)
function AutoplayLogic.runEndProblems(reason: string, bag: { number }, invBefore: { number }, invAfter: { number }, bagLeft: number,
	oreCount: number): { string }
	local out = {}
	for k = 1, oreCount do
		local want = (invBefore[k] or 0) + (if reason == "cashout" then (bag[k] or 0) else 0)
		if (invAfter[k] or 0) ~= want then
			table.insert(out, string.format("%s ore%d %d≠%d", reason, k, invAfter[k] or 0, want))
		end
	end
	if bagLeft ~= 0 then
		table.insert(out, string.format("%s bagLeft=%d", reason, bagLeft))
	end
	return out
end

-- 제작 한 번: 광석이 조합 × 횟수만큼(한 번에 inputPer개) 줄고 토큰이 계획만큼 늘었나
function AutoplayLogic.craftProblems(oresBefore: { number }, oresAfter: { number }, combo: { number }, times: number, inputPer: number,
	tokensBefore: { [string]: number }, tokensAfter: { [string]: number }, planned: { [string]: number }, oreCount: number): { string }
	local out = {}
	if #combo ~= inputPer then
		table.insert(out, string.format("combo %d≠%d", #combo, inputPer))
	end
	local used: { [number]: number } = {}
	for _, k in ipairs(combo) do
		used[k] = (used[k] or 0) + times
	end
	local spent = 0
	for k = 1, oreCount do
		local d = (oresBefore[k] or 0) - (oresAfter[k] or 0)
		spent += d
		if d ~= (used[k] or 0) then
			table.insert(out, string.format("ore%d -%d≠-%d", k, d, used[k] or 0))
		end
	end
	if spent ~= inputPer * times then
		table.insert(out, string.format("ores -%d≠-%d", spent, inputPer * times))
	end
	local keys: { [string]: boolean } = {}
	for key in pairs(tokensBefore) do
		keys[key] = true
	end
	for key in pairs(tokensAfter) do
		keys[key] = true
	end
	for key in pairs(planned) do
		keys[key] = true
	end
	for key in pairs(keys) do
		local d = (tokensAfter[key] or 0) - (tokensBefore[key] or 0)
		if d ~= (planned[key] or 0) then
			table.insert(out, string.format("token_%s +%d≠+%d", key, d, planned[key] or 0))
		end
	end
	return out
end

-- 환생 한 번 앞뒤(#44 pre_rebirth). 스냅숏 꼴 = AutoplayMonitor.snapshot(환생 수 number · 블럭스 · 코인 · 힘 · lifeBlox BigNum ·
-- 광석 · 토큰 · 곡괭이 표 · 장착 · 펫 "uid:petId" 정렬 목록 · 열린 기구 수 · 최고 층). ctx = { cost · multRatio(뒤 / 앞 힘 배수) · multBase ·
-- gymsExpected · strengthStart · analytics(환생 분석 호출 수) }
local function sameCounts(a: { [any]: any }, b: { [any]: any }): boolean
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

local function bigClose(a: any, b: any): boolean
	if a.m == 0 or b.m == 0 then
		return a.m == b.m
	end
	local ra = math.log10(math.abs(a.m)) + a.e
	local rb = math.log10(math.abs(b.m)) + b.e
	return math.abs(ra - rb) < 1e-9 and (a.m > 0) == (b.m > 0)
end

function AutoplayLogic.rebirthProblems(before: any, after: any, ctx: any): { string }
	local out = {}
	if after.rebirths ~= before.rebirths + 1 then
		table.insert(out, string.format("rebirths %d→%d", before.rebirths, after.rebirths))
	end
	-- 블럭스 = 앞 − 비용(나머지는 남는다 — REBIRTH_KEEP_REMAINDER)
	local want = if BigNum.gt(before.blox, ctx.cost) then BigNum.sub(before.blox, ctx.cost) else BigNum.new(0, 0)
	if not bigClose(after.blox, want) then
		table.insert(out, "blox≠before−cost")
	end
	if not bigClose(after.coins, before.coins) then
		table.insert(out, "coins")
	end
	if not sameCounts(after.ores, before.ores) then
		table.insert(out, "ores")
	end
	if not sameCounts(after.tokens, before.tokens) then
		table.insert(out, "tokens")
	end
	local picksSame = true
	for id, o in pairs(before.pickaxes) do
		local p = after.pickaxes[id]
		if p == nil or p.count ~= o.count or p.stars ~= o.stars or p.enh ~= o.enh then
			picksSame = false
		end
	end
	for id in pairs(after.pickaxes) do
		if before.pickaxes[id] == nil then
			picksSame = false
		end
	end
	if not picksSame or after.equipped ~= before.equipped then
		table.insert(out, "pickaxes")
	end
	if table.concat(after.pets, ",") ~= table.concat(before.pets, ",") then
		table.insert(out, "pets")
	end
	if after.gyms ~= ctx.gymsExpected or after.gyms < before.gyms then
		table.insert(out, string.format("gyms %d→%d(want %d)", before.gyms, after.gyms, ctx.gymsExpected))
	end
	if math.abs(ctx.multRatio - ctx.multBase) > 1e-6 then
		table.insert(out, string.format("mult ×%.6f≠×%g", ctx.multRatio, ctx.multBase))
	end
	if not bigClose(after.strength, ctx.strengthStart) or after.maxStage ~= 1 or after.lifeBlox.m ~= 0 then
		table.insert(out, "reset(strength · maxStage · lifeBlox)")
	end
	if ctx.analytics ~= 1 then
		table.insert(out, string.format("analytics %d", ctx.analytics))
	end
	return out
end

-- 서버 루프 합(ms/초)이 상한 안인가
function AutoplayLogic.loopBudgetOk(msPerSec: number): boolean
	return msPerSec <= 1000 * AutoplayConfig.SERVER_LOOP_BUDGET_SHARE
end

-- ===== 결과 꼴 ============================================================================================

-- 문제 모음: 종류마다 개수 + 첫 예시 하나(줄이 넘치지 않게)
export type Tally = { count: number, kinds: { [string]: { n: number, example: string } }, order: { string } }

function AutoplayLogic.newTally(): Tally
	return { count = 0, kinds = {}, order = {} }
end

function AutoplayLogic.add(t: Tally, kind: string, example: string)
	t.count += 1
	local k = t.kinds[kind]
	if k == nil then
		t.kinds[kind] = { n = 1, example = example }
		table.insert(t.order, kind)
	else
		k.n += 1
	end
end

-- 한 줄로(최대 maxLen자 — 넘치면 자른다 · utf8 안전)
function AutoplayLogic.tallyLine(t: Tally, maxLen: number): string
	if t.count == 0 then
		return "0"
	end
	local parts = {}
	for _, kind in ipairs(t.order) do
		local k = t.kinds[kind]
		table.insert(parts, string.format("%s×%d(%s)", kind, k.n, k.example))
	end
	local s = string.format("%d — %s", t.count, table.concat(parts, " · "))
	if utf8.len(s) == nil then
		s = (string.gsub(s, "[\128-\255]", "?")) -- 깨진 예시가 섞였으면(바깥에서 바이트로 자른 문장) 깨진 바이트를 ?로 — 줄 전체가 깨지지 않게
	end
	if (utf8.len(s) :: number) > maxLen then
		local cut = utf8.offset(s, maxLen - 1)
		if cut ~= nil then
			s = string.sub(s, 1, cut - 1) .. "…"
		end
	end
	return s
end

-- 런 하나당 로비 초(#45): LOBBY_PHASES 단계 초 합 ÷ 런 수(런 0이면 0)
function AutoplayLogic.lobbySecPerRun(phaseSec: { [string]: number }, runs: number): number
	if runs <= 0 then
		return 0
	end
	local sum = 0
	for _, k in ipairs(AutoplayConfig.LOBBY_PHASES) do
		sum += phaseSec[k] or 0
	end
	return sum / runs
end

-- 앞에서 n자만(글자 단위 — utf8 안전). 바이트로 자르면 한글 한가운데가 잘려 깨진 줄이 되고, 깨진 줄은 MCP 읽기를 멈춰 세운다(#45 실측).
-- 깨진 문자열이 들어오면 바이트 128 이상을 "?"로 바꿔 돌려준다
function AutoplayLogic.clip(s: string, n: number): string
	local len = utf8.len(s)
	if len == nil then
		return (string.gsub(string.sub(s, 1, n), "[\128-\255]", "?"))
	end
	if len <= n then
		return s
	end
	local cut = utf8.offset(s, n + 1) :: number
	return string.sub(s, 1, cut - 1)
end

-- 줄 앞 머리로 봇 자신의 줄인가(경고 · 오류 집계에서 뺀다)
function AutoplayLogic.isOwnLine(message: string): boolean
	return string.sub(message, 1, #AutoplayConfig.TAG) == AutoplayConfig.TAG
end

return AutoplayLogic

--!strict
-- 분석 이벤트 래퍼 (지시서 #23 A1 ~ A5 — DESIGN.md 14장). AnalyticsService를 부르는 곳은 이 파일 하나다.
--
--   블럭스 흐름(A1)   CurrencyService가 blox add · subtract · set 성공 뒤 bloxFlow(player, reason, 금액, 잔액)를 부른다(Bootstrap이 건다).
--                     reason → AnalyticsConfig.BLOX_FLOWS. 같은 (흐름 · 종류 · sku)는 FLUSH_SEC 동안 금액을 더해 한 번에 보낸다
--   큰 수(A2)          금액 · 잔액 둘 다 ECONOMY_SAFE_MAX 미만이면 LogEconomyEvent, 아니면 LogCustomEvent(blox_flow_large, log10 금액).
--                     inf · NaN · 음수 · BigNum이 아닌 값은 보내지 않는다(거부 로그)
--   커스텀(A3)         rebirth · floor_first_clear · auto_advance_start · robux_purchase
--   상한 · pcall(A4)   플레이어당 WINDOW_SEC에 PER_PLAYER_PER_MINUTE개. 넘치면 버리고 개수만 로그(접음). 모든 호출은 pcall —
--                     실패해도 게임 동작에 영향이 없다. AnalyticsService 메서드는 yield하므로 task.spawn 안에서 부른다
--   퍼널(A5)           첫 접속 안내 LogOnboardingFunnelStepEvent(#20 O5)
--
-- Studio에서도 부른다(공식: Studio · 클라에서는 보내지지 않는다 — 결과 로그 줄만 본다). 결과 줄은 Studio에서만 찍는다(실패 줄은 언제나).
-- 공식 문서(2026-11-06): create.roblox.com/docs/reference/engine/classes/AnalyticsService · production/analytics/economy-events ·
-- custom-events · custom-fields(키는 Enum.AnalyticsCustomFieldKeys.CustomField01 ~ 03 .Name, 값은 문자열) · event-types(한도)
--
-- ⚠️ Player가 아닌 값(테스트의 가짜 플레이어 표)은 조용히 건너뛴다 — 서비스 테스트가 실제 이벤트 · 로그를 만들지 않게.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AnalyticsConfig = require(ReplicatedStorage.Shared.Config.AnalyticsConfig)
local LogFold = require(script.Parent.LogFold)

type BigNumber = BigNum.BigNumber

local Analytics = {}

-- 실제로 내보내는 곳. 테스트는 기록만 하는 가짜로 바꿔 끼운다. fields는 최대 3개 문자열 배열(CustomField01 ~ 03 순서)
export type Sink = {
	economy: (player: any, flow: string, currency: string, amount: number, balance: number, transaction: string, sku: string, fields: { string }?) -> (),
	custom: (player: any, name: string, value: number, fields: { string }?) -> (),
	funnel: (player: any, step: number, name: string) -> (),
}

export type Deps = {
	sink: Sink,
	clock: () -> number,
	log: (string) -> (),
	isPlayer: (any) -> boolean,
	spawn: ((() -> ()) -> ())?, -- 기본 task.spawn. 테스트는 바로 부른다
	verbose: boolean?, -- 성공 결과 줄을 찍는가(Studio)
	foldSec: number?,
}

-- BigNum 꼴이고 유한하고 음수가 아닌가(A2)
local function isSafeBig(v: any): boolean
	if type(v) ~= "table" or type(v.m) ~= "number" or type(v.e) ~= "number" then
		return false
	end
	local m, e = v.m, v.e
	if m ~= m or e ~= e or m == math.huge or m == -math.huge or e == math.huge or e == -math.huge then
		return false
	end
	return m >= 0
end

-- log10(BigNum). 0이면 nil. 10^2000에서도 유한하다(지수 + log10(가수))
local function log10Big(v: BigNumber): number?
	if v.m <= 0 then
		return nil
	end
	return v.e + math.log10(v.m)
end

-- ECONOMY_SAFE_MAX 미만이면 그 숫자, 아니면 nil
local function smallNumber(v: BigNumber): number?
	if v.m == 0 then
		return 0
	end
	if v.e >= 16 then
		return nil
	end
	local n = v.m * 10 ^ v.e
	if n ~= n or n >= AnalyticsConfig.ECONOMY_SAFE_MAX then
		return nil
	end
	return n
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

type Pending = { flow: string, transaction: string, sku: string, amount: BigNumber, balance: BigNumber, count: number }

function Analytics.new(deps: Deps)
	local spawn = deps.spawn or function(fn: () -> ())
		task.spawn(fn)
	end
	local folder = LogFold.new(deps.foldSec or AnalyticsConfig.WINDOW_SEC, deps.clock, deps.log)
	local windows: { [any]: { start: number, count: number, dropped: number } } = {}
	local pending: { [any]: { [string]: Pending } } = {}
	local lastFlush: { [any]: number } = {}
	local stats = { sent = 0, dropped = 0, failed = 0, rejected = 0, skipped = 0, unclassified = 0 }
	local self: any = { stats = stats }

	local function idOf(player: any): string
		return tostring(if type(player) == "table" or typeof(player) == "Instance" then player.UserId else player)
	end

	-- 상한(A4). 고정 창 — 창이 지나면 새로 센다
	local function allow(player: any): boolean
		local now = deps.clock()
		local w = windows[player]
		if w == nil or now - w.start >= AnalyticsConfig.WINDOW_SEC then
			w = { start = now, count = 0, dropped = 0 }
			windows[player] = w
		end
		if w.count >= AnalyticsConfig.PER_PLAYER_PER_MINUTE then
			w.dropped += 1
			stats.dropped += 1
			folder.log("drop:" .. idOf(player), string.format("[Analytics] 상한 초과 — 버림 user=%s 이번 창 %d개(상한 %d/%gs)",
				idOf(player), w.dropped, AnalyticsConfig.PER_PLAYER_PER_MINUTE, AnalyticsConfig.WINDOW_SEC))
			return false
		end
		w.count += 1
		return true
	end

	-- 보낸다(상한 · pcall). 보냈으면 true
	local function send(player: any, label: string, call: () -> ()): boolean
		if not deps.isPlayer(player) then
			stats.skipped += 1
			return false
		end
		if not allow(player) then
			return false
		end
		stats.sent += 1
		spawn(function()
			local ok, err = pcall(call)
			if not ok then
				stats.failed += 1
				folder.log("fail:" .. label, string.format("[Analytics] %s user=%s → 실패(%s)", label, idOf(player), tostring(err)))
			elseif deps.verbose then
				deps.log(string.format("[Analytics] %s user=%s → ok", label, idOf(player)))
			end
		end)
		return true
	end

	local function reject(label: string, detail: string)
		stats.rejected += 1
		folder.log("reject:" .. label, string.format("[Analytics] 거부 %s — %s", label, detail))
	end

	-- 커스텀 이벤트(A3). value는 유한한 숫자만
	function self.custom(player: any, name: string, value: any, fields: { string }?): boolean
		if not finite(value) then
			reject(name, "값이 유한한 숫자가 아님 " .. tostring(value))
			return false
		end
		return send(player, string.format("custom %s value=%s%s", name, tostring(value),
			if fields ~= nil then " fields=" .. table.concat(fields, "/") else ""), function()
			deps.sink.custom(player, name, value, fields)
		end)
	end

	function self.funnel(player: any, step: number, name: string): boolean
		return send(player, string.format("funnel %d %s", step, name), function()
			deps.sink.funnel(player, step, name)
		end)
	end

	-- 블럭스 흐름 한 건(A1). 결과: "queued" · "zero" · "rejected" · "unclassified" · "skipped"
	function self.bloxFlow(player: any, reason: string, amount: any, balance: any): string
		if not isSafeBig(amount) or not isSafeBig(balance) then
			reject("blox " .. tostring(reason), string.format("금액 · 잔액이 유한한 BigNum이 아님 (%s · %s)", tostring(amount and amount.m), tostring(balance and balance.m)))
			return "rejected"
		end
		local row, sku = AnalyticsConfig.classify(reason)
		if row == nil then
			stats.unclassified += 1
			folder.log("unclassified:" .. tostring(reason), string.format("[Analytics] 흐름표에 없는 reason=%s — 보내지 않음(AnalyticsConfig.BLOX_FLOWS)", tostring(reason)))
			return "unclassified"
		end
		if amount.m == 0 then
			return "zero"
		end
		if not deps.isPlayer(player) then
			stats.skipped += 1
			return "skipped"
		end
		local r = row :: AnalyticsConfig.Flow
		local key = r.flow .. "|" .. r.transaction .. "|" .. (sku :: string)
		local byPlayer = pending[player]
		if byPlayer == nil then
			byPlayer = {}
			pending[player] = byPlayer
			if lastFlush[player] == nil then
				lastFlush[player] = deps.clock()
			end
		end
		local p = byPlayer[key]
		if p == nil then
			byPlayer[key] = { flow = r.flow, transaction = r.transaction, sku = sku :: string, amount = amount, balance = balance, count = 1 }
		else
			p.amount = BigNum.add(p.amount, amount)
			p.balance = balance
			p.count += 1
		end
		return "queued"
	end

	-- 모아 둔 흐름을 보낸다(A1 · A2). 보낸(시도한) 이벤트 수를 돌려준다
	function self.flush(player: any): number
		local byPlayer = pending[player]
		pending[player] = nil
		lastFlush[player] = deps.clock()
		if byPlayer == nil then
			return 0
		end
		local n = 0
		for _, p in pairs(byPlayer) do
			local amountN = smallNumber(p.amount)
			local balanceN = smallNumber(p.balance)
			if amountN ~= nil and balanceN ~= nil then
				send(player, string.format("economy %s %s %s amount=%s balance=%s n=%d", p.flow, p.transaction, p.sku,
					tostring(amountN), tostring(balanceN), p.count), function()
					deps.sink.economy(player, p.flow, AnalyticsConfig.CURRENCY, amountN :: number, balanceN :: number, p.transaction, p.sku, nil)
				end)
			else
				local lb = log10Big(p.balance)
				self.custom(player, AnalyticsConfig.EVENTS.bloxFlowLarge, log10Big(p.amount) :: number,
					{ p.flow, p.sku, if lb ~= nil then string.format("%.3f", lb) else "0" })
			end
			n += 1
		end
		return n
	end

	-- 주기 호출(런타임 루프). FLUSH_SEC가 지난 플레이어만 보낸다
	function self.tick()
		local now = deps.clock()
		for player, at in pairs(lastFlush) do
			if pending[player] ~= nil and now - at >= AnalyticsConfig.FLUSH_SEC then
				self.flush(player)
			end
		end
	end

	function self.flushAll()
		local list = {}
		for player in pairs(pending) do
			table.insert(list, player)
		end
		for _, player in ipairs(list) do
			self.flush(player)
		end
	end

	function self.onRemoving(player: any)
		self.flush(player)
		pending[player] = nil
		lastFlush[player] = nil
		windows[player] = nil
	end

	-- 커스텀 이벤트 도우미(A3)
	function self.rebirth(player: any, gained: any): boolean
		if not isSafeBig(gained) or gained.m <= 0 then
			reject(AnalyticsConfig.EVENTS.rebirth, "얻은 환생 수가 양의 BigNum이 아님")
			return false
		end
		return self.custom(player, AnalyticsConfig.EVENTS.rebirth, log10Big(gained) :: number)
	end

	function self.floorFirstClear(player: any, floor: number): boolean
		return self.custom(player, AnalyticsConfig.EVENTS.floorFirstClear, floor)
	end

	function self.autoAdvanceStart(player: any, gap: number): boolean
		return self.custom(player, AnalyticsConfig.EVENTS.autoAdvanceStart, gap)
	end

	function self.robuxPurchase(player: any, key: string, kind: string): boolean
		return self.custom(player, AnalyticsConfig.EVENTS.robuxPurchase, 1, { key, kind })
	end

	function self.pendingCount(player: any): number
		local n = 0
		for _ in pairs(pending[player] or {}) do
			n += 1
		end
		return n
	end

	return self
end

-- 테스트 전용 통로
Analytics._pure = { isSafeBig = isSafeBig, log10Big = log10Big, smallNumber = smallNumber }

-- ===== 런타임 =====================================================================================

local function fieldsDict(fields: { string }?): { [string]: string }?
	if fields == nil then
		return nil
	end
	local keys = { Enum.AnalyticsCustomFieldKeys.CustomField01.Name, Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField03.Name }
	local out = {}
	for i = 1, math.min(#fields, 3) do
		out[keys[i]] = tostring(fields[i])
	end
	return out
end

local function realSink(): Sink
	local service = game:GetService("AnalyticsService")
	return {
		economy = function(player, flow, currency, amount, balance, transaction, sku, fields)
			service:LogEconomyEvent(player, (Enum.AnalyticsEconomyFlowType :: any)[flow], currency, amount, balance,
				(Enum.AnalyticsEconomyTransactionType :: any)[transaction].Name, sku, fieldsDict(fields))
		end,
		custom = function(player, name, value, fields)
			service:LogCustomEvent(player, name, value, fieldsDict(fields))
		end,
		funnel = function(player, step, name)
			service:LogOnboardingFunnelStepEvent(player, step, name)
		end,
	}
end

local live: any = nil

function Analytics.init()
	if live ~= nil then
		return
	end
	AnalyticsConfig.validate()
	live = Analytics.new({
		sink = realSink(),
		clock = os.clock,
		log = print,
		isPlayer = function(p: any): boolean
			return typeof(p) == "Instance" and p:IsA("Player")
		end,
		verbose = RunService:IsStudio(),
	})
	task.spawn(function()
		while true do
			task.wait(1)
			live.tick()
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		live.onRemoving(player)
	end)
	game:BindToClose(function()
		live.flushAll()
	end)
	print(string.format("[Analytics] 준비 완료(플레이어당 %d개/%gs · 모아 보내기 %gs · 경제 이벤트 < %g)", AnalyticsConfig.PER_PLAYER_PER_MINUTE,
		AnalyticsConfig.WINDOW_SEC, AnalyticsConfig.FLUSH_SEC, AnalyticsConfig.ECONOMY_SAFE_MAX))
end

-- 서비스가 부르는 진입점. init 전(서비스 테스트 등)이면 아무것도 하지 않는다
function Analytics.bloxFlow(player: any, reason: string, amount: any, balance: any)
	if live ~= nil then
		live.bloxFlow(player, reason, amount, balance)
	end
end
function Analytics.funnel(player: any, step: number, name: string)
	if live ~= nil then
		live.funnel(player, step, name)
	end
end
function Analytics.rebirth(player: any, gained: any)
	if live ~= nil then
		live.rebirth(player, gained)
	end
end
function Analytics.floorFirstClear(player: any, floor: number)
	if live ~= nil then
		live.floorFirstClear(player, floor)
	end
end
function Analytics.autoAdvanceStart(player: any, gap: number)
	if live ~= nil then
		live.autoAdvanceStart(player, gap)
	end
end
function Analytics.robuxPurchase(player: any, key: string, kind: string)
	if live ~= nil then
		live.robuxPurchase(player, key, kind)
	end
end

return Analytics

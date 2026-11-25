--!strict
-- 새 경제 클라 상태(지시서 #32). 서버 EconomyEvent를 받아 HUD가 읽을 값만 들고 있다.
-- 판정하지 않는다(서버 권위) — 받은 값을 그대로 둔다. 인스턴스마다 따로(테스트는 new()로 자기 것을 만든다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)

type BigNumber = BigNum.BigNumber

local EconomyV2State = {}

export type Values = {
	coins: BigNumber,
	bagUsed: number,
	bagCap: number,
	bag: { number },
	ores: { number },
	forgeOpen: boolean,
	-- 대장간(#33 — ForgeService 신호)
	tokens: { [string]: number },
	owned: { [string]: number },
	autoOn: boolean,
	autoCount: number,
	-- 장비(#34 — EquipmentService 신호)
	equipment: { [string]: { count: number, stars: number, enh: number } },
	equipped: string,
	-- 자동 부화(#35 — PetAutoHatchService 신호)
	autoHatchOn: boolean,
	autoHatchCount: number,
	-- 새 경제 안내(#36 — OnboardingTipsService 신호). 지난 안내 키 · 안내 끔. HUD 칸이 이것을 보고 나타난다
	tipsSeen: { [string]: boolean },
	tipsOff: boolean,
}
export type State = {
	get: () -> Values,
	apply: (payload: any) -> boolean, -- 값이 바뀌었으면 true
	subscribe: (fn: (Values) -> ()) -> (),
}

local function bigOf(v: any): BigNumber?
	if type(v) == "table" and type(v.m) == "number" and type(v.e) == "number" then
		return BigNum.new(v.m, v.e)
	end
	return nil
end

local function countsOf(v: any): { [string]: number }?
	if type(v) ~= "table" then
		return nil
	end
	local out: { [string]: number } = {}
	for key, n in pairs(v) do
		if type(key) == "string" and type(n) == "number" then
			out[key] = n
		end
	end
	return out
end

local function intsOf(v: any): { number }?
	if type(v) ~= "table" then
		return nil
	end
	local out = {}
	for k = 1, #EconomyV2Logic.newInv() do
		local n = v[k]
		out[k] = if type(n) == "number" then n else 0
	end
	return out
end

function EconomyV2State.new(): State
	local values: Values = {
		coins = BigNum.new(0, 0),
		bagUsed = 0,
		bagCap = 0,
		bag = EconomyV2Logic.newInv(),
		ores = EconomyV2Logic.newInv(),
		forgeOpen = false,
		tokens = {},
		owned = {},
		autoOn = false,
		autoCount = 0,
		equipment = {},
		equipped = "",
		autoHatchOn = false,
		autoHatchCount = 0,
		tipsSeen = {},
		tipsOff = false,
	}
	local listeners: { (Values) -> () } = {}
	local self = {} :: State

	function self.get(): Values
		return values
	end

	function self.apply(payload: any): boolean
		if type(payload) ~= "table" or type(payload.kind) ~= "string" then
			return false
		end
		local changed = false
		if type(payload.used) == "number" and type(payload.cap) == "number" then
			values.bagUsed, values.bagCap = payload.used, payload.cap
			values.bag = intsOf(payload.bag) or values.bag
			changed = true
		end
		local total = bigOf(payload.total) or (if payload.kind == "snapshot" then bigOf(payload.coins) else nil)
		if total ~= nil then
			values.coins = total
			changed = true
		end
		local ores = intsOf(payload.ores)
		if ores ~= nil then
			values.ores = ores
			changed = true
		end
		if payload.kind == "forge_open" or (payload.kind == "snapshot" and payload.forgeOpen == true) then
			values.forgeOpen = true
			changed = true
		end
		-- 대장간(#33): 토큰 · 보유 · 자동 제작
		local tokens = countsOf(if payload.kind == "forge_state" then payload.tokens else payload.tokensTotal)
		if tokens ~= nil then
			values.tokens = tokens
			changed = true
		end
		local owned = countsOf(payload.owned)
		if owned ~= nil then
			values.owned = owned
			changed = true
		end
		if payload.kind == "forge_state" and type(payload.auto) == "table" then
			values.autoOn, values.autoCount = payload.auto.on == true, tonumber(payload.auto.count) or 0
			changed = true
		elseif payload.kind == "auto_state" then
			values.autoOn, values.autoCount = payload.on == true, tonumber(payload.count) or 0
			changed = true
		elseif payload.kind == "craft_result" and payload.ok == true and payload.auto == true then
			values.autoCount = tonumber(payload.autoCount) or values.autoCount
			changed = true
		end
		if payload.kind == "auto_hatch_state" then
			values.autoHatchOn, values.autoHatchCount = payload.on == true, tonumber(payload.count) or 0
			changed = true
		elseif payload.kind == "auto_hatch_result" then
			values.autoHatchCount = tonumber(payload.count) or values.autoHatchCount
			changed = true
		end
		if payload.kind == "tips" and type(payload.seen) == "table" then
			local seen = {}
			for _, key in ipairs(payload.seen) do
				if type(key) == "string" then
					seen[key] = true
				end
			end
			values.tipsSeen, values.tipsOff = seen, payload.off == true
			changed = true
		elseif payload.kind == "tip" and type(payload.key) == "string" then
			values.tipsSeen[payload.key] = true
			changed = true
		end
		if payload.kind == "equipment_state" and type(payload.equipment) == "table" then
			local eq = {}
			for id, o in pairs(payload.equipment) do
				if type(id) == "string" and type(o) == "table" then
					eq[id] = { count = tonumber(o.count) or 0, stars = tonumber(o.stars) or 0, enh = tonumber(o.enh) or 0 }
				end
			end
			values.equipment = eq
			values.equipped = if type(payload.equipped) == "string" then payload.equipped else values.equipped
			changed = true
		end
		if changed then
			for _, fn in ipairs(listeners) do
				fn(values)
			end
		end
		return changed
	end

	function self.subscribe(fn: (Values) -> ())
		table.insert(listeners, fn)
	end

	return self
end

-- 클라에서 하나만 쓰는 상태(#35 — EconomyV2Boot가 채우고 펫 창(WindowBoot 쪽)이 코인 · 자동 부화를 읽는다). 테스트는 new()를 쓴다
local sharedState: State? = nil
function EconomyV2State.shared(): State
	if sharedState == nil then
		sharedState = EconomyV2State.new()
	end
	return sharedState :: State
end

return EconomyV2State

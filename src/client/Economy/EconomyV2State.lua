--!strict
-- 새 경제 클라 상태(지시서 #32 — 플래그 ECONOMY_V2 뒤). 서버 EconomyEvent를 받아 HUD가 읽을 값만 들고 있다.
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

return EconomyV2State

--!strict
-- 부스트(포션) 엔진 (Phase 8 지시서 #16 4단계 · DESIGN 9장 S7).
--
--   profile.Data.boosts = { { type, mult, remainingSec } } (스키마 v7). type은 ShopConfig.BOOSTS의 키(strength · damage · luck).
--   **접속 중에만** 시간이 흐른다 — 서버 단일 루프가 TICK_SEC마다 접속한 플레이어의 remainingSec를 깎는다(플레이어마다 task.spawn 금지).
--   나가 있는 동안은 루프가 그 프로필을 보지 않으므로 줄지 않는다. 0 이하가 되면 지운다(만료).
--   같은 종류를 또 켜면 시간이 더해진다(배수는 그대로 — ShopConfig.BOOSTS의 mult).
--
--   결합: 힘 포션 → StrengthMultiplier · 데미지 포션 → 1펀치 데미지 결합 · 행운 포션 → computeLuck 부스트 항.
--   값은 ShopEffects를 거쳐 나간다(행운 포션은 제한 유저면 1 — S13). 이 파일은 시간과 배수만 안다.
--
--   켜기(보관함 → 활성)는 #17이다. 여기서는 add(엔진 API)만 둔다.
--   ⚠️ 저장을 부르지 않는다. 남은 시간은 메모리에서 줄고 ProfileStore 자동 저장 · 퇴장 저장이 가져간다
--   (매 초 저장 금지 — 쓰기 한도).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)

local BoostService = {}

BoostService.TICK_SEC = 1
BoostService.MAX_TICK_DT = 5 -- 서버가 멈췄다 풀려도 한 틱에 이보다 많이 깎지 않는다

export type BoostView = { type: string, mult: number, remainingSec: number }

local function isEntry(e: any): boolean
	return type(e) == "table" and type(e.type) == "string" and type(e.mult) == "number" and type(e.remainingSec) == "number"
		and e.remainingSec == e.remainingSec
end

-- 그 종류의 지금 배수. 살아 있는 항목 중 가장 큰 배수(없으면 1). 같은 종류가 여럿이어도 곱하지 않는다(한 번만).
local function activeMult(boosts: any, boostType: string): number
	local best = 1
	if type(boosts) ~= "table" then
		return best
	end
	for _, e in ipairs(boosts) do
		if isEntry(e) and e.type == boostType and e.remainingSec > 0 and e.mult > best and e.mult < math.huge then
			best = e.mult
		end
	end
	return best
end

-- dt초 흐르게 한다. 끝난 것 · 깨진 것은 지운다. 바뀌었으면 true.
local function tickBoosts(boosts: any, dt: number): boolean
	if type(boosts) ~= "table" or #boosts == 0 or not (dt > 0) then
		return false
	end
	local kept = {}
	for _, e in ipairs(boosts) do
		if isEntry(e) then
			e.remainingSec -= dt
			if e.remainingSec > 0 then
				table.insert(kept, e)
			end
		end
	end
	table.clear(boosts)
	for i, e in ipairs(kept) do
		boosts[i] = e
	end
	return true
end

-- 하나 켠다. 같은 종류가 있으면 남은 시간에 더한다. 모르는 종류면 false.
local function addBoost(boosts: any, boostType: string): boolean
	local def = ShopConfig.BOOSTS[boostType]
	if def == nil or type(boosts) ~= "table" then
		return false
	end
	for _, e in ipairs(boosts) do
		if isEntry(e) and e.type == boostType and e.remainingSec > 0 then
			e.remainingSec += def.durationSec
			return true
		end
	end
	table.insert(boosts, { type = boostType, mult = def.mult, remainingSec = def.durationSec })
	return true
end

-- 상태 채널용. BOOST_ORDER 순서, 살아 있는 것만, 남은 초는 올림 정수. hide(type)가 true인 종류는 뺀다(제한 유저의 행운 포션).
local function summarize(boosts: any, hide: ((string) -> boolean)?): { BoostView }
	local out: { BoostView } = {}
	for _, boostType in ipairs(ShopConfig.BOOST_ORDER) do
		local remaining = 0
		local mult = activeMult(boosts, boostType)
		if type(boosts) == "table" then
			for _, e in ipairs(boosts) do
				if isEntry(e) and e.type == boostType and e.remainingSec > remaining then
					remaining = e.remainingSec
				end
			end
		end
		if remaining > 0 and not (hide ~= nil and hide(boostType)) then
			table.insert(out, { type = boostType, mult = mult, remainingSec = math.ceil(remaining) })
		end
	end
	return out
end

BoostService._pure = {
	activeMult = activeMult,
	tickBoosts = tickBoosts,
	addBoost = addBoost,
	summarize = summarize,
}

-- ===== 런타임 ======================================================================================

local function boostsOf(player: Player): any?
	local profile = ProfileManager.get(player)
	local data = if profile ~= nil then profile.Data else nil
	return if type(data) == "table" then data.boosts else nil
end

-- 지금 배수(없으면 1). ShopEffects가 부른다 — 결합 자리에서 직접 부르지 말 것(제한 판정이 빠진다).
function BoostService.getMult(player: Player, boostType: string): number
	return activeMult(boostsOf(player), boostType)
end

function BoostService.summarize(player: Player, hide: ((string) -> boolean)?): { BoostView }
	return summarize(boostsOf(player), hide)
end

-- 하나 켠다(#17 보관함이 부른다). 프로필이 없거나 모르는 종류면 false.
function BoostService.add(player: Player, boostType: string): boolean
	local boosts = boostsOf(player)
	return boosts ~= nil and addBoost(boosts, boostType)
end

local initialized = false

function BoostService.init()
	if initialized then
		warn("[BoostService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true
	local accum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum < BoostService.TICK_SEC then
			return
		end
		local step = math.min(accum, BoostService.MAX_TICK_DT)
		accum = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local boosts = boostsOf(player)
			if boosts ~= nil then
				tickBoosts(boosts, step)
			end
		end
	end)
	print(string.format("[BoostService] 부스트 엔진 준비 완료 (접속 중에만 · %d초 단일 루프)", BoostService.TICK_SEC))
end

return BoostService

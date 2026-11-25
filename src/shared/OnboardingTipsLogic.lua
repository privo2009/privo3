--!strict
-- 새 경제 안내 판정(지시서 #36 — DESIGN 16장 "해금 순서 · 첫 접속 안내"). 순수 모듈 — 서버 OnboardingTipsService · 클라 HUD가 같은 식을 쓴다.
--
--   facts(data, bagUsed)   안내 키마다 { trigger = 지금 보여 줄 때인가, past = 이미 지났나 } — 프로필 꼴 그대로 읽는다(없는 필드는 0 · 빈 것)
--   pick(o, facts)         저장 상태(onboarding)와 facts로 이번에 적을 키 하나와 silent(글 없이 적기)를 돌려준다. 없으면 nil
--                          지난 것(past) · 안내를 끈 유저(tipsOff)는 silent — 칸은 나타나고 글은 없다
--   backfill(o, facts)     프로필을 불러올 때: 이미 참인 것(past 또는 trigger)을 전부 글 없이 적은 키 목록(이미 지난 유저에게 지난 안내를 띄우지 않는다)
--   hudShown(seen, hud)    그 HUD 칸이 보이는가 — 그 칸을 여는 안내 키를 지났으면(한 번 보이면 계속)
-- 저장 꼴: onboarding.tips{[키] = true} · onboarding.tipsOff(boolean) — 템플릿에 없다(없으면 빈 것). 스키마 버전 그대로

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)

local OnboardingTipsLogic = {}

export type Fact = { trigger: boolean, past: boolean }
export type Facts = { [string]: Fact }

local function big(v: any): BigNum.BigNumber
	if type(v) == "table" and type(v.m) == "number" and type(v.e) == "number" then
		return v :: any
	end
	return BigNum.new(0, 0)
end

local function positive(v: any): boolean
	return BigNum.gt(big(v), BigNum.new(0, 0))
end

local function anyPositive(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	for _, n in pairs(t) do
		if type(n) == "number" and n > 0 then
			return true
		end
	end
	return false
end

-- 저장 상태 읽기(없으면 빈 것)
function OnboardingTipsLogic.seenSet(o: any): { [string]: boolean }
	if type(o) == "table" and type(o.tips) == "table" then
		return o.tips
	end
	return {}
end

function OnboardingTipsLogic.isOff(o: any): boolean
	return type(o) == "table" and o.tipsOff == true
end

function OnboardingTipsLogic.facts(data: any, bagUsed: number?): Facts
	local d = if type(data) == "table" then data else {}
	local rebirths = big(d.rebirths)
	local hasRebirth = positive(d.rebirths)
	local forgeOpen = d.forgeOpen == true
	local picks = if type(d.equipment) == "table" and type(d.equipment.pickaxe) == "table" then d.equipment.pickaxe else {}
	local equippedId = if type(d.equipped) == "table" and type(d.equipped.pickaxe) == "string" then d.equipped.pickaxe else EconomyV2Config.START_PICKAXE
	local equippedMult = EconomyV2Logic.multFromSave(picks, equippedId)
	local better, owned = false, 0
	for id, o in pairs(picks) do
		if type(o) == "table" and type(o.count) == "number" and o.count > 0 and EconomyV2Logic.pickaxe(id) ~= nil then
			owned += o.count
			if id ~= equippedId and EconomyV2Logic.multFromSave(picks, id) > equippedMult then
				better = true
			end
		end
	end
	local pets = if type(d.pets) == "table" and type(d.pets.owned) == "table" then d.pets.owned else {}
	local hasPet = next(pets) ~= nil
	local egg1 = PetConfig.Eggs[1]
	local eggOpen = egg1 ~= nil and BigNum.gte(big(d.lifetimeBlox), egg1.rollCost)
	return {
		blox = { trigger = positive(d.lifetimeBlox) or positive(d.blox), past = hasRebirth },
		coins = { trigger = positive(d.coins), past = false },
		bag = { trigger = (bagUsed or 0) > 0 or anyPositive(d.ores), past = forgeOpen },
		rebirth = { trigger = BigNum.gte(big(d.blox), EconomyV2Logic.rebirthCost(rebirths)), past = hasRebirth },
		craft = { trigger = forgeOpen, past = anyPositive(d.tokens) or owned > 1 },
		equip = { trigger = better, past = equippedId ~= EconomyV2Config.START_PICKAXE },
		egg = { trigger = eggOpen, past = hasPet },
	}
end

function OnboardingTipsLogic.pick(o: any, facts: Facts): (string?, boolean)
	local seen = OnboardingTipsLogic.seenSet(o)
	local off = OnboardingTipsLogic.isOff(o)
	for _, tip in ipairs(OnboardingConfig.V2_TIPS) do
		local f = facts[tip.key]
		if not seen[tip.key] and f ~= nil then
			if f.past then
				return tip.key, true
			elseif f.trigger then
				return tip.key, off
			end
		end
	end
	return nil, false
end

function OnboardingTipsLogic.backfill(o: any, facts: Facts): { string }
	local seen = OnboardingTipsLogic.seenSet(o)
	local out = {}
	for _, tip in ipairs(OnboardingConfig.V2_TIPS) do
		local f = facts[tip.key]
		if not seen[tip.key] and f ~= nil and (f.past or f.trigger) then
			table.insert(out, tip.key)
		end
	end
	return out
end

-- 프로필 onboarding에 키를 적는다(tips 표가 없으면 만든다 — 기존 필드 안)
function OnboardingTipsLogic.mark(o: any, key: string)
	if type(o) ~= "table" then
		return
	end
	if type(o.tips) ~= "table" then
		o.tips = {}
	end
	o.tips[key] = true
end

function OnboardingTipsLogic.tipOf(key: string): OnboardingConfig.Tip?
	for _, tip in ipairs(OnboardingConfig.V2_TIPS) do
		if tip.key == key then
			return tip
		end
	end
	return nil
end

function OnboardingTipsLogic.hudShown(seen: { [string]: boolean }?, hud: string): boolean
	for _, tip in ipairs(OnboardingConfig.V2_TIPS) do
		if tip.hud == hud then
			return seen ~= nil and seen[tip.key] == true
		end
	end
	return true -- 안내로 여는 칸이 아니면 언제나 보인다
end

return OnboardingTipsLogic

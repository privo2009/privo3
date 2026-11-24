--!strict
-- 새 경제 상점 검증(지시서 #31 G14 — 플래그 ECONOMY_V2 뒤). 전역 플래그는 건드리지 않는다 — 문맥에 economyV2를 넣어 굴린다.
--   켜면 로벅스 탭에서 x2 Rebirths 줄이 빠진다(다른 줄은 그대로) · 끄면 지금 목록 그대로 · 임시 이름(Names.ore · Names.pickaxe)이 클라에서도 나온다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local RobuxShopLogic = require(script.Parent.Parent.UI.Logic.RobuxShopLogic)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function shop(passes: { string }?): any
	return { gamepasses = passes or {}, paidRandomRestricted = false, boosts = {}, autoClick = false }
end

local function keys(rows: { RobuxShopLogic.Row }): { [string]: boolean }
	local out = {}
	for _, r in ipairs(rows) do
		out[r.key] = true
	end
	return out
end

do
	local off = RobuxShopLogic.rows(shop(), { economyV2 = false })
	local on = RobuxShopLogic.rows(shop(), { economyV2 = true })
	local offKeys, onKeys = keys(off), keys(on)
	local removed = 0
	for key in pairs(Config.REMOVED_PRODUCTS) do
		if offKeys[key] then
			removed += 1
		end
	end
	check("상점: 끄면 x2 Rebirths 줄이 있다(지금 그대로)", offKeys.rebirth2x == true)
	check("상점: 켜면 x2 Rebirths 줄이 빠진다", onKeys.rebirth2x == nil)
	check("상점: 빠진 줄 말고는 같다", #off - #on == removed and (function()
		for key in pairs(offKeys) do
			if not onKeys[key] and not Config.REMOVED_PRODUCTS[key] then
				return false
			end
		end
		return true
	end)())
	local owned = RobuxShopLogic.rows(shop({ "rebirth2x" }), { economyV2 = true })
	check("상점: 이미 가진 사람도 켜면 안 보인다", keys(owned).rebirth2x == nil)
	local default = RobuxShopLogic.rows(shop(), nil)
	check("상점: 문맥 없음 = 커밋 플래그 값", (keys(default).rebirth2x == true) == not Config.ECONOMY_V2 and #ShopConfig.GAMEPASS_ORDER > 0)
end

do
	local ok = true
	for k = 1, Config.ORE_COUNT do
		ok = ok and Names.ore(k) ~= Config.ORE_NAME_KEYS[k] and Names.ore(k) == Locale.t(Config.ORE_NAME_KEYS[k])
	end
	for _, def in ipairs(Config.PICKAXES) do
		ok = ok and Names.pickaxe(def.id) ~= def.nameKey and Names.pickaxe(def.id) == Locale.t(def.nameKey)
	end
	check("이름: 클라에서 광석 10 · 곡괭이 15 임시 이름이 나온다", ok)
end

print(string.format("[EconomyV2ShopTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EconomyV2ShopTests] %d test(s) failed", failed))
end

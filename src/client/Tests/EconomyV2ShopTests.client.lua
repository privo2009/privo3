--!strict
-- 상점 검증(지시서 #31 G14 · #37 — x2 Rebirths는 ShopConfig에서 지웠다).
--   로벅스 탭에 x2 Rebirths 줄이 없다(가졌어도) · 임시 이름(Names.ore · Names.pickaxe)이 클라에서도 나온다.

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
	local rows = RobuxShopLogic.rows(shop(), nil)
	check("상점: x2 Rebirths 줄이 없다(#37 다 — 상품을 지웠다)", keys(rows).rebirth2x == nil and #ShopConfig.GAMEPASS_ORDER > 0)
	local owned = RobuxShopLogic.rows(shop({ "rebirth2x" }), nil)
	check("상점: 이미 가진 사람도 안 보인다", keys(owned).rebirth2x == nil)
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

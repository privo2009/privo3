--!strict
-- UiTheme 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- U3 착수 준비: 8개 색 역할이 전부 존재하고 밝은/기본/어두운 3단계를 갖는지 확인.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)

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

-- docs/UI.md "3. 색" 표와 대조하는 이름 목록. 개수를 하드코딩하지 않고 이 목록과 맞춘다.
local EXPECTED_ROLES = { "power", "blox", "advance", "cashout", "robux", "danger", "premium", "neutral" }

for _, role in ipairs(EXPECTED_ROLES) do
	local entry = UiTheme.Colors[role]
	check(string.format("UiTheme: 역할 '%s'가 존재한다", role), entry ~= nil)

	if entry then
		check(string.format("UiTheme: '%s'.light가 Color3다", role), typeof(entry.light) == "Color3")
		check(string.format("UiTheme: '%s'.base가 Color3다", role), typeof(entry.base) == "Color3")
		check(string.format("UiTheme: '%s'.dark가 Color3다", role), typeof(entry.dark) == "Color3")
	end
end

local count = 0
for _ in pairs(UiTheme.Colors) do
	count += 1
end
check("UiTheme: 정확히 8개 역할만 등록돼 있다", count == #EXPECTED_ROLES, tostring(count))

-- 희귀도 색 (지시서 #10 S14) — 역할색과 별도 묶음 · hex 재사용 금지 · 단계가 오를수록 눈에 띈다 -----------------
do
	local tiers = UiTheme.RARITY_TIERS
	check("희귀도: 6단계", #tiers == 6)
	local roleHex: { [string]: string } = {}
	for role, entry in pairs(UiTheme.Colors) do
		for _, step in ipairs({ "light", "base", "dark" }) do
			roleHex[(entry :: any)[step]:ToHex():upper()] = role .. "." .. step
		end
	end
	local seen: { [string]: boolean } = {}
	local prevS, prevV = -1, -1
	for i, key in ipairs(tiers) do
		local color = UiTheme.Rarity[key]
		check("희귀도: " .. key .. "가 Color3다", typeof(color) == "Color3")
		if typeof(color) == "Color3" then
			local hex = color:ToHex():upper()
			check("희귀도: " .. key .. "는 역할색 hex를 재사용하지 않는다", roleHex[hex] == nil, roleHex[hex])
			check("희귀도: " .. key .. "는 다른 단계와 다르다", not seen[hex])
			seen[hex] = true
			local _, s, v = color:ToHSV()
			check("희귀도: " .. key .. " 채도가 아래 단계보다 높다", s > prevS, string.format("%.3f vs %.3f", s, prevS))
			check("희귀도: " .. key .. " 밝기가 아래 단계보다 낮지 않다", v >= prevV - 1e-9, string.format("%.3f vs %.3f", v, prevV))
			prevS, prevV = s, v
			check("희귀도: rarityColor(" .. i .. ") = " .. key, UiTheme.rarityColor(i) == color)
		end
	end
	check("희귀도: 범위 밖 단계는 끝 단계로 접는다", UiTheme.rarityColor(0) == UiTheme.Rarity.tier1 and UiTheme.rarityColor(99) == UiTheme.Rarity.tier6)
	check("희귀도: 역할 표(Colors)에 섞이지 않았다", (UiTheme.Colors :: any).tier1 == nil)
end

print(string.format("[UiThemeTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UiThemeTests] %d test(s) failed", failed))
end

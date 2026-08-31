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

print(string.format("[UiThemeTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UiThemeTests] %d test(s) failed", failed))
end

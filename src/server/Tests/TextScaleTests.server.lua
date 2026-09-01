--!strict
-- TextScale 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- U3-1 착수 준비: 글자 크기 5단계가 전부 존재하고 docs/UI.md "4. 글자 > 크기 5단계"
-- 표와 일치하는지 확인한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)

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

-- docs/UI.md "4. 글자 > 크기 5단계" 표 그대로.
local EXPECTED: { { level: TextScale.Level, heightFraction: number, maxTextSize: number } } = {
	{ level = "huge", heightFraction = 0.07, maxTextSize = 76 },
	{ level = "large", heightFraction = 0.05, maxTextSize = 54 },
	{ level = "medium", heightFraction = 0.035, maxTextSize = 38 },
	{ level = "small", heightFraction = 0.025, maxTextSize = 27 },
	{ level = "tiny", heightFraction = 0.02, maxTextSize = 22 },
}

for _, expected in ipairs(EXPECTED) do
	local spec = TextScale.Levels[expected.level]
	check(string.format("TextScale: '%s'가 존재한다", expected.level), spec ~= nil)
	if spec then
		check(
			string.format("TextScale: '%s'.heightFraction == %.3f", expected.level, expected.heightFraction),
			math.abs(spec.heightFraction - expected.heightFraction) < 1e-9,
			tostring(spec.heightFraction)
		)
		check(
			string.format("TextScale: '%s'.maxTextSize == %d", expected.level, expected.maxTextSize),
			spec.maxTextSize == expected.maxTextSize,
			tostring(spec.maxTextSize)
		)
	end
end

local count = 0
for _ in pairs(TextScale.Levels) do
	count += 1
end
check("TextScale: 정확히 5단계만 등록돼 있다", count == #EXPECTED, tostring(count))

print(string.format("[TextScaleTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TextScaleTests] %d test(s) failed", failed))
end

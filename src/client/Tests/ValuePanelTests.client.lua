--!strict
-- ValuePanel 컴포넌트 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동
-- 실행된다. U3-1 착수 준비.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local ValuePanel = require(script.Parent.Parent.UI.Components.ValuePanel)
local TestHelpers = require(script.Parent.TestHelpers)
local checkClose = TestHelpers.checkClose

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

-- 1. 8자 규격에서 999.99AB(류)가 안 잘린다 --------------------------------------------
-- "안 잘린다"는 TextScaled(항상 프레임에 맞춰 줄어들 뿐 넘치지 않는다)로 보장되고,
-- 8자 폭 자체는 AspectRatioConstraint가 맡는다 — 둘 다 구조적으로 확인한다.

do
	local handle = ValuePanel.create("huge") -- maxChars 생략 -> 기본값 8
	check("TextScaled가 켜져 있다", handle.label.TextScaled == true)

	local sizeConstraint = handle.label:FindFirstChildOfClass("UITextSizeConstraint")
	check("UITextSizeConstraint가 있다", sizeConstraint ~= nil)
	if sizeConstraint then
		check(
			"'huge' 단계의 MaxTextSize == 76",
			(sizeConstraint :: UITextSizeConstraint).MaxTextSize == 76
		)
	end

	local aspect = handle.label:FindFirstChildOfClass("UIAspectRatioConstraint")
	check("UIAspectRatioConstraint가 있다", aspect ~= nil)
	if aspect then
		-- AspectRatio는 Instance에서 읽은 float32 값이라 checkClose를 쓴다(TestHelpers.lua 참고).
		check(
			"기본 8자 폭의 AspectRatio == 8 * 0.55",
			checkClose((aspect :: UIAspectRatioConstraint).AspectRatio, 8 * 0.55)
		)
		check(
			"DominantAxis가 Height다 (실제 렌더 픽셀 기준으로 폭이 따라오게)",
			(aspect :: UIAspectRatioConstraint).DominantAxis == Enum.DominantAxis.Height
		)
	end

	local stroke = handle.label:FindFirstChildOfClass("UIStroke")
	check("UIStroke(외곽선)가 있다", stroke ~= nil)

	-- 8자 규격의 경계값. BigNum.new(9.99, 20) -> tier=6(Qi), displayM=999 -> "999.00Qi" (8자).
	local boundaryValue = BigNum.new(9.99, 20)
	handle.setValue(boundaryValue)
	local expected = Formatter.format(boundaryValue)
	check(
		string.format("8자 경계값 '%s'가 그대로 Text에 들어간다(안 잘림)", expected),
		handle.label.Text == expected,
		handle.label.Text
	)
	check("경계값 포맷 길이가 8자다(전제 확인)", #expected == 8, expected)
end

-- 2. 폭을 4자리로 주면 그만큼만 잡는다 (이동 속도, docs/UI.md "4. 글자" 같은 절) -----------

do
	local eight = ValuePanel.create("small", 8)
	local four = ValuePanel.create("small", 4)

	local eightAspect = eight.label:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint?
	local fourAspect = four.label:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint?

	check("8자 AspectRatioConstraint가 있다", eightAspect ~= nil)
	check("4자 AspectRatioConstraint가 있다", fourAspect ~= nil)

	if eightAspect and fourAspect then
		check("4자 폭이 8자 폭보다 좁다", fourAspect.AspectRatio < eightAspect.AspectRatio)
		check(
			"4자 AspectRatio == 4 * 0.55",
			checkClose(fourAspect.AspectRatio, 4 * 0.55)
		)
	end

	-- ValuePanel.MAX_CHARS_SPEED가 바로 이 4자리 상수다 (이동 속도 전용).
	check("ValuePanel.MAX_CHARS_SPEED == 4", ValuePanel.MAX_CHARS_SPEED == 4)

	four.setNumber(24)
	check("setNumber(24) -> Text == '24'", four.label.Text == "24")
end

print(string.format("[ValuePanelTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ValuePanelTests] %d test(s) failed", failed))
end

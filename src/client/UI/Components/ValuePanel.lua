--!strict
-- docs/UI.md "4. 글자 > 숫자가 UI 최대 제약"의 숫자 칸.
--
-- TextScaled + UITextSizeConstraint로 자릿수가 늘어도 특대가 중처럼 보이는 구간을
-- 막고, UIAspectRatioConstraint로 자릿수만큼의 폭을 실제 렌더 픽셀 기준으로
-- 확보한다 — 부모가 화면 전체든 Panel 본문처럼 중첩된 곳이든, 실측 픽셀 기준이라
-- 중첩 깊이와 무관하게 항상 같은 비율로 나온다 (Panel.lua가 X 버튼 정사각형에
-- 쓴 것과 같은 장치).
--
-- 크기·위치는 이 컴포넌트가 정하지 않는다(AssetImage와 같은 원칙) — 호출자가
-- Size.Y.Scale(글자 5단계 중 하나, TextScale.Levels 참고)을 세팅하면 폭은 아래
-- maxChars 비율로 자동으로 따라온다.
--
-- 숫자 포맷은 Shared/Formatter.lua를 그대로 쓴다. 새로 만들지 않는다
-- (FormatterTests가 이미 그 계약을 검증한다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)

type BigNumber = BigNum.BigNumber

local ValuePanel = {}

-- 최대 폭 기준 999.99AB = 8자 (docs/UI.md "4. 글자 > 숫자가 UI 최대 제약").
-- 모든 숫자 칸은 이 폭으로 설계한다 — 딱 맞게 만들면 나중에 잘린다.
ValuePanel.MAX_CHARS_DEFAULT = 8

-- 이동 속도는 8자 규격을 따르지 않는다. 실제 값은 2자리지만 칸은 4자리다 —
-- 좁히지 말 것 (docs/UI.md 같은 절).
ValuePanel.MAX_CHARS_SPEED = 4

-- 자릿수 1개당 대략적인 폭:높이 비율. docs에 폰트 실측 수치가 없어(4. 글자 > 폰트
-- 미해결) SourceSansBold 숫자/영문 대문자 글리프의 통상적인 폭 비율(약 0.55~0.6em)로
-- 임의로 정했다 — 게임 수치가 아니라 시각 튜닝값이고, 실제 폰트가 정해지면
-- (docs/UI.md "폰트 (미해결)") 재실측해서 바꿀 수 있다.
local CHAR_WIDTH_RATIO = 0.55

export type ValuePanelHandle = {
	label: TextLabel,
	setValue: (BigNumber) -> (),
	setNumber: (number) -> (),
}

function ValuePanel.create(level: TextScale.Level, maxChars: number?): ValuePanelHandle
	local chars = maxChars or ValuePanel.MAX_CHARS_DEFAULT
	local spec = TextScale.Levels[level]
	assert(spec ~= nil, "ValuePanel.create: 알 수 없는 글자 크기 단계: " .. tostring(level))

	local label = Instance.new("TextLabel")
	label.Name = "ValuePanel"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.SourceSansBold
	label.Text = ""

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = spec.maxTextSize
	sizeConstraint.Parent = label

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = chars * CHAR_WIDTH_RATIO
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = label

	-- 외곽선: 흰 글자 + 검은 스트로크 (docs/UI.md "4. 글자 > 외곽선")
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	local function setValue(value: BigNumber)
		label.Text = Formatter.format(value)
	end

	local function setNumber(value: number)
		label.Text = string.format("%d", value)
	end

	return {
		label = label,
		setValue = setValue,
		setNumber = setNumber,
	}
end

return ValuePanel

--!strict
-- ⚠️ 검증 관문 G1 전용 임시 파일. **G1 통과 후 삭제한다.**
--    (`docs/UI_HANDOFF.md` "5. 검증 관문 G1 ~ G4 > G1 — 버튼 9-slice")
--
-- 무엇을 보는가
--   btn_yellow(192x64, 9-slice 사방 24px)를 세 가지 크기로 동시에 띄우고 육안 확인한다.
--     통과 : 세 크기 모두 테두리 굵기가 같다 / 모서리가 안 뭉개진다
--     실패 : 9-slice 24px 값을 재조정한다 → 나머지 버튼 5종 착수 금지
--
-- ⚠️ Offset 예외
--   CLAUDE.md 금지 사항의 "UI 크기·위치에 Offset 사용 금지"를 이 파일은 의도적으로 어긴다.
--   목적이 픽셀 단위 슬라이스 검증이라 Scale로는 잴 수 없다 — Scale은 실제 픽셀 크기가
--   뷰포트에 따라 달라지므로 "높이 48" 같은 경계값을 맞출 방법이 없다.
--   (이 파일의 이전 판은 Scale + UIAspectRatioConstraint 방식이었고, 그래서 아래 세 번째
--    표본을 아예 만들 수 없었다. 검증용 예외이므로 본 UI 코드로 이 방식을 옮기지 말 것.)
--   예외는 검증 표본 3개의 Size에만 적용한다. 라벨은 기존대로 Scale이다.
--
-- 에셋 ID는 `Shared/Config/AssetConfig.lua`가 원본이다. 여기에 ID를 다시 적지 말 것.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetConfig = require(ReplicatedStorage.Shared.Config.AssetConfig)

local BUTTON = AssetConfig.Buttons.yellow

-- 검증 크기 3종. 원본 192x64 / 사방 24px 여백 기준으로 고른 값이다.
--   원본 1:1      늘어남이 없는 기준점. 여기서 이상하면 PNG 자체나 slice 값이 틀린 것이다
--   가로 2배      좌우 stretch 확인. 중앙 열만 늘어나고 모서리는 그대로여야 한다
--   세로 최소 경계 높이 48 = 상하 마진 합(24+24)과 정확히 같다. ← 핵심 판정
--
-- ⚠️ 세 번째가 핵심이다. 중앙 행의 높이가 0이 되는 지점이라, 여기서 테두리가 두꺼워지거나
--    상단 하이라이트가 뭉개지면 최소 크기 제약이 실재한다는 뜻이다(= 버튼을 이보다
--    납작하게 쓸 수 없다). 그 경우 G1은 통과여도 최소 높이를 규격에 적어야 한다.
local SAMPLES = {
	{ name = "Original", width = 192, height = 64, label = "192 x 64   원본 1:1" },
	{ name = "WideX2", width = 384, height = 64, label = "384 x 64   가로 2배" },
	{ name = "MinHeight", width = 192, height = 48, label = "192 x 48   세로 최소 경계" },
}

-- 세로 배치 위치 (앵커 중심 기준). 화면 세로를 4등분해 셋을 벌려둔다.
local ROW_Y = { 0.25, 0.5, 0.75 }

local BUTTON_X = 0.55 -- 버튼 중심. 왼쪽에 라벨 자리를 비워둔다
local LABEL_X = 0.05 -- 라벨 좌측 시작
local LABEL_WIDTH = 0.28
local LABEL_HEIGHT = 0.05

-- 노란 버튼의 경계가 배경에 묻히면 테두리 굵기를 못 본다. 어두운 회색을 깔아 대비를 만든다.
local BACKGROUND_COLOR = Color3.fromRGB(40, 40, 40)
local LABEL_COLOR = Color3.fromRGB(255, 255, 255)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "SliceCheck"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Position = UDim2.fromScale(0, 0)
backdrop.BackgroundColor3 = BACKGROUND_COLOR
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

for index, sample in ipairs(SAMPLES) do
	local centerY = ROW_Y[index]

	local image = Instance.new("ImageLabel")
	image.Name = sample.name
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(BUTTON_X, centerY)
	image.Size = UDim2.fromOffset(sample.width, sample.height) -- 상단 주석의 Offset 예외
	image.BackgroundTransparency = 1
	image.Image = BUTTON.id
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = BUTTON.slice
	image.Parent = backdrop

	local label = Instance.new("TextLabel")
	label.Name = sample.name .. "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(LABEL_X, centerY)
	label.Size = UDim2.fromScale(LABEL_WIDTH, LABEL_HEIGHT)
	label.BackgroundTransparency = 1
	label.Text = sample.label
	label.TextColor3 = LABEL_COLOR
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.Parent = backdrop
end

print(string.format("[SliceCheck] btn_yellow v%d (%s) 표본 3종 표시. G1 육안 확인 후 이 파일을 삭제할 것.", BUTTON.version, BUTTON.id))

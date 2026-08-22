--!strict
-- ⚠️ 검증 관문 G1 전용 임시 파일. Phase 6 착수 조건 확인용이며 통과 후 삭제한다.
--    (`docs/UI_HANDOFF.md` "5. 검증 관문 G1 ~ G4 > G1 — 버튼 9-slice")
--
-- 무엇을 보는가
--   btn_yellow(192x64, 9-slice 24px)를 세 가지 크기로 동시에 띄우고 육안 확인한다.
--     통과 : 세 크기 모두 테두리 굵기가 같다 / 모서리가 안 뭉개진다
--     실패 : 9-slice 24px 값을 재조정한다 → 나머지 버튼 5종 착수 금지
--
-- 임시 검증값이므로 Config로 분리하지 않고 아래 상수에 모아둔다.

local Players = game:GetService("Players")

-- 업로드 후 교체. 디자인 담당이 올린 btn_yellow.png의 에셋 ID를 여기에 넣는다.
local ASSET_ID = "rbxassetid://0"

-- 원본 192x64, 사방 24px 여백 (`docs/UI_ASSET_SPEC.md` "1. 9-slice", "2. 버튼 6종")
local SLICE_CENTER = Rect.new(24, 24, 168, 40)
local BUTTON_ASPECT = 192 / 64 -- = 3. 가로:세로 비율

-- 세 검증 크기. 높이는 화면 세로 대비 Scale, 가로는 위 비율에서 파생된다.
local SMALL_HEIGHT = 0.06
local LARGE_HEIGHT = 0.09
local LONG_HEIGHT = 0.09
local LONG_WIDTH_MULTIPLIER = 3 -- "가로로 긴" 것만 큰 버튼의 3배 폭

-- 세로 배치 위치 (앵커 중심 기준). 세 개가 서로 안 겹치도록 벌려둔다.
local SMALL_Y = 0.25
local LARGE_Y = 0.45
local LONG_Y = 0.70

local BUTTON_X = 0.55 -- 버튼 중심. 왼쪽에 라벨 자리를 비워둔다
local LABEL_X = 0.04 -- 라벨 좌측 시작
local LABEL_WIDTH = 0.20
local LABEL_HEIGHT = 0.05

local BACKGROUND_COLOR = Color3.fromRGB(40, 40, 40)
local LABEL_COLOR = Color3.fromRGB(255, 255, 255)

if ASSET_ID == "rbxassetid://0" then
	warn("[SliceCheck] ASSET_ID가 아직 rbxassetid://0 이다. btn_yellow 업로드 후 상단 상수를 교체할 것.")
end

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

-- 비율 보정 방식: UIAspectRatioConstraint를 골랐다.
-- Size는 Scale만 쓰는데(Offset 금지), 가로 Scale은 뷰포트 가로, 세로 Scale은 뷰포트 세로를
-- 기준으로 계산되므로 (0.09, 0.27) 같은 값을 그대로 넣으면 화면 가로세로비가 바뀔 때마다
-- 버튼 비율이 같이 틀어진다. 9-slice 검증은 "늘어난 방향과 정도"를 보는 것이므로
-- 비율이 화면마다 달라지면 판정 자체가 흔들린다.
-- 카메라 뷰포트 비율로 매번 가로 Scale을 역산하는 방법도 되지만, Studio 창 크기 변경과
-- 기기 회전마다 재계산 연결을 유지해야 한다. 반면 제약은 엔진이 매 프레임 유지해주고
-- 실제 UI 코드에서도 같은 방식을 쓸 것이므로 검증 조건이 본 구현과 어긋나지 않는다.
-- AspectType = ScaleWithParentSize + DominantAxis = Height 조합이라 높이 Scale만 기준이 되고
-- 가로는 AspectRatio에서 파생된다. (그래서 아래 Size의 가로 Scale 값은 0으로 두고 제약이 채운다.
-- FitWithinMaxSize는 Size를 최대치로 보므로 가로 0이면 아예 안 보인다 — 쓰면 안 된다)
-- 세로로 좁은 세로 화면에서는 '긴 9% x3' 표본이 화면 가로를 넘을 수 있다. G1 확인은
-- Studio Play(가로 화면) 기준이다.
local function createSample(name: string, heightScale: number, centerY: number, aspect: number, labelText: string)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(BUTTON_X, centerY)
	image.Size = UDim2.fromScale(0, heightScale) -- 가로는 아래 제약이 채운다
	image.BackgroundTransparency = 1
	image.Image = ASSET_ID
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = SLICE_CENTER
	image.Parent = backdrop

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspect
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.AspectType = Enum.AspectType.ScaleWithParentSize
	ratio.Parent = image

	local label = Instance.new("TextLabel")
	label.Name = name .. "Label"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(LABEL_X, centerY)
	label.Size = UDim2.fromScale(LABEL_WIDTH, LABEL_HEIGHT)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = LABEL_COLOR
	label.TextScaled = true -- 글자 크기도 Offset을 안 쓰기 위해 박스에 맞춘다
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.Parent = backdrop
end

createSample("Small", SMALL_HEIGHT, SMALL_Y, BUTTON_ASPECT, "작은 6%")
createSample("Large", LARGE_HEIGHT, LARGE_Y, BUTTON_ASPECT, "큰 9%")
createSample("Long", LONG_HEIGHT, LONG_Y, BUTTON_ASPECT * LONG_WIDTH_MULTIPLIER, "긴 9% x3")

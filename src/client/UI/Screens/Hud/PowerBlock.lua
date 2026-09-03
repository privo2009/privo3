--!strict
-- HUD: 힘 · 레벨 · 속도 블록 (하단 중앙). docs/UI.md "1. 화면 목록 > 힘 · 레벨 · 속도 블록",
-- "2. 세이프존 > 구역 비율", DESIGN.md "레벨" · "레벨 > 커스텀 스피드".
--
-- U3-5 확정값 (임의로 바꾸지 말 것). 세 행 높이(7.0/1.5/3.0/1.5/3.5%, 합 16.5%)는
-- 숫자를 직접 박지 않고 아래 상수에서 유도한다 — 예산을 조정할 때 한 곳만 고치면
-- 되게 하려는 것이다. 하단 여백 5.33%는 화면 폭 3%(Layout.EDGE_MARGIN)의 16:9 환산.
--
-- ⚠️ 레벨은 Store의 "level" 필드를 읽지 않는다. DESIGN.md "레벨"이 "레벨 = 힘의
-- 지수(N=1)"로 정의하므로, 이 파일은 그 정의를 직접 구현해 strength(BigNum)에서
-- 레벨을 유도한다 — 별도 필드(Store.level)에 기대면 두 값이 각자 다른 시점에
-- 갱신될 때(네트워크 갱신 순서 등) 화면에 잠깐 어긋난 레벨이 뜰 수 있다. 진행률
-- 계산도 어차피 strength의 가수가 필요해 같은 값을 두 번 구독할 이유가 없다.
--
-- ⚠️ 이번 범위는 표시뿐이다. 이동 속도 편집 입력(SpeedInput.request() 왕복)은 넣지
-- 않는다 — 서버가 실제 적용값과 최대치를 되돌려주는 계약(DESIGN "커스텀 스피드")이
-- 걸려 있어 Play 없이는 검증이 불가능하다. 연필 아이콘은 자리만 잡는다(클릭 배선 없음).
--
-- ⚠️ UIListLayout/UIGridLayout을 쓰지 않는다. 세 행을 각각 명시적 Position/Size로
-- 배치한다 — 레이아웃 오브젝트는 자식의 Position을 수정하지 않아 Position 기반
-- 검증이 전부 (0,0)으로 걸린다(docs/PENDING.md "함정", U3-4C에서 MenuRailTests가
-- 실제로 이렇게 죽었다).
--
-- ⚠️ 이 세션은 Studio Play를 돌릴 수 없다(RC 환경) — 코드·테스트만 쌓고 실측 검증은
-- 다음 세션으로 미룬다(docs/PENDING.md "미결" 참고).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local ValuePanel = require(script.Parent.Parent.Parent.Components.ValuePanel)
local Store = require(script.Parent.Parent.Parent.Store)

type BigNumber = BigNum.BigNumber

local PowerBlock = {}

-- ===== 세로 배분 (화면 높이 기준) ============================================

local POWER_ROW_HEIGHT = TextScale.Levels.huge.heightFraction -- 7.0% — 특대, 힘 수치와 같은 단계
local ROW_GAP = 0.015 -- 화면 기준 1.5%. 행 사이 간격 (이 세션 확정값)
local LEVEL_ROW_HEIGHT = 0.03 -- 화면 기준 3.0% — 레벨 진행 바
local SPEED_ROW_HEIGHT = TextScale.Levels.medium.heightFraction -- 3.5% — medium과 정확히 일치
-- 파생값(16.5%). 표에 그대로 박지 않는다 — 위 네 상수를 고치면 이것도 같이 움직인다.
local BLOCK_HEIGHT = POWER_ROW_HEIGHT + ROW_GAP + LEVEL_ROW_HEIGHT + ROW_GAP + SPEED_ROW_HEIGHT

local BLOCK_WIDTH = 0.40 -- 화면 기준 40%, 중앙 (좌우 레일 20%씩을 피한 중앙 60% 안)

-- 하단 여백: 화면 폭 3%(Layout.EDGE_MARGIN)의 16:9 환산 (docs/UI.md "2. 세이프존 > 규칙").
-- Panel.lua의 widthFractionToRootScaleY와 같은 공식이지만 그 함수는 local이라 가져다
-- 쓸 수 없다 — 공식만 그대로 재현한다 (REFERENCE_ASPECT = 1920/1080, Panel.lua와 동일 상수).
local REFERENCE_ASPECT = 1920 / 1080
local BOTTOM_MARGIN_HEIGHT = Layout.EDGE_MARGIN * REFERENCE_ASPECT -- 5.33%

-- 블록은 아래쪽 여백 바로 위에 바닥을 고정하고 위로 연다("상단 여유"는 비워둔
-- 공간이지 블록의 일부가 아니다 — docs "확정된 값" 절 참고).
local BLOCK_BOTTOM_Y = 1 - BOTTOM_MARGIN_HEIGHT -- 화면 기준, ~0.9467
local BLOCK_TOP_Y = BLOCK_BOTTOM_Y - BLOCK_HEIGHT -- 화면 기준, ~0.7817

-- 테스트 전용 참조 (MenuRail.Columns/Items와 같은 성격) — HudLayoutTests가 렌더
-- 결과(AbsolutePosition/AbsoluteSize)를 예산과 대조할 때 매직넘버를 다시 옮겨적지
-- 않기 위해 노출한다.
PowerBlock.BlockWidth = BLOCK_WIDTH
PowerBlock.BlockHeight = BLOCK_HEIGHT
PowerBlock.BlockTopY = BLOCK_TOP_Y
PowerBlock.BlockBottomY = BLOCK_BOTTOM_Y

-- 세 행의 부모(root) 상대 Y 범위. BLOCK_HEIGHT로 나눠서 유도한다 — 표의 파생값
-- (0.424242 등)을 직접 박지 않는다.
local POWER_Y0 = 0
local POWER_Y1 = POWER_ROW_HEIGHT / BLOCK_HEIGHT
local LEVEL_Y0 = (POWER_ROW_HEIGHT + ROW_GAP) / BLOCK_HEIGHT
local LEVEL_Y1 = (POWER_ROW_HEIGHT + ROW_GAP + LEVEL_ROW_HEIGHT) / BLOCK_HEIGHT
local SPEED_Y0 = (POWER_ROW_HEIGHT + ROW_GAP + LEVEL_ROW_HEIGHT + ROW_GAP) / BLOCK_HEIGHT
local SPEED_Y1 = 1

-- ===== 레벨 진행 바 내부 =====================================================

local LEVEL_LABEL_LEVEL: TextScale.Level = "small" -- 소(2.5%), docs "레벨 진행 바 > 라벨"
-- 화면 기준(소, 2.5%)을 LevelRow 기준(3.0%)으로 환산 — ChallengeInfo.lua의 같은 환산과
-- 동일 패턴(자식 Size.Y.Scale은 root 기준이라, 화면 기준 값을 root 기준으로 나눠야 한다).
local LEVEL_LABEL_HEIGHT_ROW_REL = TextScale.Levels[LEVEL_LABEL_LEVEL].heightFraction / LEVEL_ROW_HEIGHT
local LEVEL_LABEL_WIDTH = 0.15 -- LevelRow 기준. 시각 튜닝값(게임 수치 아님) — 좌우 라벨 폭
local LEVEL_BAR_HEIGHT_REL = 0.6 -- LevelRow 기준. 시각 튜닝값 — 바 자체는 행 높이의 60%만 쓰고 세로 중앙 정렬

-- ===== 이동 속도 행 내부 =====================================================

local SPEED_LEVEL: TextScale.Level = "medium" -- 3.5% — SPEED_ROW_HEIGHT와 정확히 일치(환산 불필요)
local SPEED_VALUE_WIDTH = 0.30 -- SpeedRow 기준. 시각 튜닝값 — 현재값 칸 폭
local SPEED_ICON_RESERVED_WIDTH = 0.10 -- SpeedRow 기준. 시각 튜닝값 — 연필 아이콘이 쓸 오른쪽 여유

export type PowerBlockHandle = {
	root: Frame,
	-- 테스트 전용: 실제 Store 왕복(task.spawn 비동기) 없이도 표시 로직을 검증할 수
	-- 있게 노출한다 (ChallengeInfo._debug.apply와 같은 성격).
	_debug: {
		applyPower: (BigNumber) -> (),
		applySpeed: (number, number) -> (),
	},
}

-- 레벨 = 힘의 지수 (DESIGN.md "레벨", N=1). 힘이 0이면(BigNum 불변식상 m=0일 때 e도
-- 항상 0) 레벨도 0이다 — 별도 분기 없이 자연히 성립한다.
local function computeLevel(power: BigNumber): number
	return power.e
end

-- 진행률 = log10(가수). 가수는 BigNum 불변식상 [1,10)이므로 결과는 자연히 [0,1)
-- 안에 들지만, math.clamp로 한 번 더 방어한다(문서 요구사항 — 경계에서 소실되거나
-- 예측 불가능한 값을 절대 화면에 보내지 않기 위해). m<=0(힘이 정확히 0)이면 log10이
-- 정의되지 않으므로 별도로 0을 반환한다.
local function computeProgress(power: BigNumber): number
	if power.m <= 0 then
		return 0
	end
	return math.clamp(math.log(power.m, 10), 0, 1)
end

function PowerBlock.create(): PowerBlockHandle
	local root = Instance.new("Frame")
	root.Name = "PowerBlock"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, BLOCK_BOTTOM_Y)
	root.Size = UDim2.fromScale(BLOCK_WIDTH, BLOCK_HEIGHT)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	-- 행 1: 힘 수치 (특대, 8자) --------------------------------------------------------

	local powerValue = ValuePanel.create("huge", ValuePanel.MAX_CHARS_DEFAULT)
	powerValue.label.Name = "PowerValue"
	powerValue.label.AnchorPoint = Vector2.new(0.5, 0)
	powerValue.label.Position = UDim2.fromScale(0.5, POWER_Y0)
	-- X=1 (0이 아니다): ValuePanel의 UIAspectRatioConstraint는 AspectType 기본값
	-- FitWithinMaxSize라 Size가 상자다 — X=0이면 상자 폭 0으로 결과가 0x0이 된다
	-- (BloxDisplay/Value 등에 이미 반복된 관례, U3-2 관측).
	powerValue.label.Size = UDim2.fromScale(1, POWER_Y1 - POWER_Y0)
	powerValue.label.Parent = root

	-- 행 2: 레벨 진행 바 ----------------------------------------------------------------

	local levelRow = Instance.new("Frame")
	levelRow.Name = "LevelRow"
	levelRow.AnchorPoint = Vector2.new(0, 0)
	levelRow.Position = UDim2.fromScale(0, LEVEL_Y0)
	levelRow.Size = UDim2.fromScale(1, LEVEL_Y1 - LEVEL_Y0)
	levelRow.BackgroundTransparency = 1
	levelRow.BorderSizePixel = 0
	levelRow.Parent = root

	local currentLabel = Instance.new("TextLabel")
	currentLabel.Name = "CurrentLabel"
	currentLabel.AnchorPoint = Vector2.new(0, 0.5)
	currentLabel.Position = UDim2.fromScale(0, 0.5)
	currentLabel.Size = UDim2.fromScale(LEVEL_LABEL_WIDTH, LEVEL_LABEL_HEIGHT_ROW_REL)
	currentLabel.BackgroundTransparency = 1
	currentLabel.BorderSizePixel = 0
	currentLabel.Text = "0"
	currentLabel.TextScaled = true
	currentLabel.TextColor3 = Color3.new(1, 1, 1)
	currentLabel.Font = Enum.Font.SourceSansBold
	currentLabel.Parent = levelRow

	local currentSizeConstraint = Instance.new("UITextSizeConstraint")
	currentSizeConstraint.MaxTextSize = TextScale.Levels[LEVEL_LABEL_LEVEL].maxTextSize
	currentSizeConstraint.Parent = currentLabel

	local currentStroke = Instance.new("UIStroke")
	currentStroke.Color = Color3.new(0, 0, 0)
	currentStroke.Parent = currentLabel

	local nextLabel = Instance.new("TextLabel")
	nextLabel.Name = "NextLabel"
	nextLabel.AnchorPoint = Vector2.new(1, 0.5)
	nextLabel.Position = UDim2.fromScale(1, 0.5)
	nextLabel.Size = UDim2.fromScale(LEVEL_LABEL_WIDTH, LEVEL_LABEL_HEIGHT_ROW_REL)
	nextLabel.BackgroundTransparency = 1
	nextLabel.BorderSizePixel = 0
	nextLabel.Text = "1"
	nextLabel.TextScaled = true
	nextLabel.TextColor3 = Color3.new(1, 1, 1)
	nextLabel.Font = Enum.Font.SourceSansBold
	nextLabel.Parent = levelRow

	local nextSizeConstraint = Instance.new("UITextSizeConstraint")
	nextSizeConstraint.MaxTextSize = TextScale.Levels[LEVEL_LABEL_LEVEL].maxTextSize
	nextSizeConstraint.Parent = nextLabel

	local nextStroke = Instance.new("UIStroke")
	nextStroke.Color = Color3.new(0, 0, 0)
	nextStroke.Parent = nextLabel

	-- 배경 + 채움 두 층 (docs "레벨 진행 바"). AssetRegistry에 진행 바용 엔트리가 없어
	-- UiTheme 역할색 Frame으로 그린다 — 새 엔트리를 추가하지 않는다(디자인 담당의
	-- 제작 목록을 늘리는 별개의 결정이라 U3-5 범위 밖. 막히면 멈추라는 지시에 따라
	-- 여기서는 막히지 않고 이 대안으로 진행한다).
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.AnchorPoint = Vector2.new(0, 0.5)
	barBg.Position = UDim2.fromScale(LEVEL_LABEL_WIDTH, 0.5)
	barBg.Size = UDim2.fromScale(1 - LEVEL_LABEL_WIDTH * 2, LEVEL_BAR_HEIGHT_REL)
	barBg.BackgroundColor3 = UiTheme.Colors.neutral.dark
	barBg.BorderSizePixel = 0
	barBg.Parent = levelRow

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.AnchorPoint = Vector2.new(0, 0)
	barFill.Position = UDim2.fromScale(0, 0)
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = UiTheme.Colors.power.base
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	-- 행 3: 이동 속도 ---------------------------------------------------------------------

	local speedRow = Instance.new("Frame")
	speedRow.Name = "SpeedRow"
	speedRow.AnchorPoint = Vector2.new(0, 0)
	speedRow.Position = UDim2.fromScale(0, SPEED_Y0)
	speedRow.Size = UDim2.fromScale(1, SPEED_Y1 - SPEED_Y0)
	speedRow.BackgroundTransparency = 1
	speedRow.BorderSizePixel = 0
	speedRow.Parent = root

	-- 속도는 재화 8자 규격(999.99AB)을 따르지 않는다 — 4자 규격을 따로 쓴다
	-- (docs/UI.md "이동 속도 조절은 편의 기능이 아니다"). 실제 값(2자리)에 칸을
	-- 맞춰 좁히지 않는다 — 상한이 발판 깊이에서 유도되고 깊이가 커지면 같이 오른다.
	local speedValue = ValuePanel.create(SPEED_LEVEL, ValuePanel.MAX_CHARS_SPEED)
	speedValue.label.Name = "SpeedValue"
	speedValue.label.AnchorPoint = Vector2.new(0, 0)
	speedValue.label.Position = UDim2.fromScale(0, 0)
	speedValue.label.Size = UDim2.fromScale(SPEED_VALUE_WIDTH, 1)
	speedValue.label.Parent = speedRow

	local maxLabel = Instance.new("TextLabel")
	maxLabel.Name = "MaxLabel"
	maxLabel.AnchorPoint = Vector2.new(0, 0)
	maxLabel.Position = UDim2.fromScale(SPEED_VALUE_WIDTH, 0)
	maxLabel.Size = UDim2.fromScale(1 - SPEED_VALUE_WIDTH - SPEED_ICON_RESERVED_WIDTH, 1)
	maxLabel.BackgroundTransparency = 1
	maxLabel.BorderSizePixel = 0
	maxLabel.Text = "/ 최대 0"
	maxLabel.TextScaled = true
	maxLabel.TextColor3 = Color3.new(1, 1, 1)
	maxLabel.Font = Enum.Font.SourceSansBold
	maxLabel.Parent = speedRow

	local maxSizeConstraint = Instance.new("UITextSizeConstraint")
	maxSizeConstraint.MaxTextSize = TextScale.Levels[SPEED_LEVEL].maxTextSize
	maxSizeConstraint.Parent = maxLabel

	local maxStroke = Instance.new("UIStroke")
	maxStroke.Color = Color3.new(0, 0, 0)
	maxStroke.Parent = maxLabel

	-- 연필 아이콘: 자리만 잡는다. 클릭 배선은 이번 범위가 아니다(위 파일 상단 참고) —
	-- 실제 탭 타겟은 값 패널 전체가 될 예정이지만 그 배선도 이번엔 넣지 않는다.
	local editIcon = AssetImage.create(AssetRegistry.resolve("icon_edit"))
	editIcon.Name = "EditIcon"
	editIcon.AnchorPoint = Vector2.new(1, 0)
	editIcon.Position = UDim2.fromScale(1, 0)
	-- X=1 (0이 아니다): 아래 AspectRatioConstraint가 AspectType 기본값 FitWithinMaxSize라
	-- Size가 상자다 (MenuRail/Tile 등과 같은 관례).
	editIcon.Size = UDim2.fromScale(1, 1)
	local editAspect = Instance.new("UIAspectRatioConstraint")
	editAspect.AspectRatio = 1
	editAspect.DominantAxis = Enum.DominantAxis.Height
	editAspect.Parent = editIcon
	editIcon.Parent = speedRow

	-- ===== 표시 갱신 ================================================================

	local function applyPower(power: BigNumber)
		powerValue.setValue(power)

		local level = computeLevel(power)
		local progress = computeProgress(power)

		currentLabel.Text = tostring(level)
		nextLabel.Text = tostring(level + 1)
		barFill.Size = UDim2.fromScale(progress, 1)
	end

	local function applySpeed(speed: number, maxSpeed: number)
		speedValue.setNumber(speed)
		maxLabel.Text = string.format("/ 최대 %d", maxSpeed)
	end

	applyPower(Store.get("strength"))
	applySpeed(Store.get("walkSpeed"), Store.get("maxWalkSpeed"))

	-- walkSpeed/maxWalkSpeed는 서로 다른 Store 키라 독립적으로 갱신될 수 있다 —
	-- 표시 문자열은 항상 둘 다 필요하므로, 어느 쪽이 바뀌든 Store.get으로 나머지
	-- 한쪽을 다시 읽어 함께 적용한다(둘 다 구독하되 반쪽 값으로 렌더하지 않는다).
	Store.subscribe("strength", function(value: BigNumber)
		applyPower(value)
	end)
	Store.subscribe("walkSpeed", function(value: number)
		applySpeed(value, Store.get("maxWalkSpeed"))
	end)
	Store.subscribe("maxWalkSpeed", function(value: number)
		applySpeed(Store.get("walkSpeed"), value)
	end)

	return {
		root = root,
		_debug = {
			applyPower = applyPower,
			applySpeed = applySpeed,
		},
	}
end

return PowerBlock

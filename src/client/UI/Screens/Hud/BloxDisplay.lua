--!strict
-- HUD: 블럭스 보유 총량 (좌상단). docs/UI.md "1. 화면 목록" · "2. 세이프존".
--
-- ⚠️ docs/UI.md는 좌상단을 "건드릴 수 없음 — 로블록스 기본 UI가 차지"로 적으면서
-- 동시에 블럭스를 좌상단에 두라고 한다. 실제로는 로블록스 기본 UI "바로 아래·옆"
-- 이라는 뜻이다 — HudGui가 IgnoreGuiInset = true라서 (0,0)이 기본 UI와 겹치므로,
-- Layout.getTopInset()만큼 아래로 내린다 (Layout.lua 상단 참고, 근거는 그쪽에 있다).
--
-- 크기: "쌓아두는 값"이라 작게 둔다 (docs/UI.md "왜 힘이 하단이고 블럭스가
-- 좌상단인가" — 힘은 특대로 계속 보고, 블럭스는 작게 가끔 본다). docs의 5단계
-- 표에 "블럭스 보유량"이 명시돼 있지 않아, "항목 이름·가격"과 같은 급인 중(3.5%)을
-- 골랐다 — 각주 수준(극소)은 아니지만 힘(특대)과는 확실히 대비돼야 한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local ValuePanel = require(script.Parent.Parent.Parent.Components.ValuePanel)
local Store = require(script.Parent.Parent.Parent.Store)

local BloxDisplay = {}

local LEVEL: TextScale.Level = "medium"

export type BloxDisplayHandle = {
	root: Frame,
}

function BloxDisplay.create(): BloxDisplayHandle
	local height = TextScale.Levels[LEVEL].heightFraction

	local root = Instance.new("Frame")
	root.Name = "BloxDisplay"
	root.AnchorPoint = Vector2.new(0, 0)
	-- X: 화면 폭 3% 여백(Layout.EDGE_MARGIN, Scale). Y: 기본 UI 인셋만큼만 내린다(Offset).
	root.Position = UDim2.new(Layout.EDGE_MARGIN, 0, 0, Layout.getTopInset())
	-- 폭은 아이콘+숫자칸이 여유 있게 들어가되 좌측 레일(20%) 안에 머무르도록,
	-- 레일 폭에서 양쪽 여백을 뺀 값으로 잡는다(임의 상수가 아니라 Layout 값에서 유도).
	root.Size = UDim2.fromScale(Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2, height)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0.15, 0) -- 아이콘-숫자 사이 여백. 부모 폭 대비 15% — 시각 튜닝값
	listLayout.Parent = root

	local icon = AssetImage.create(AssetRegistry.resolve("icon_blox"))
	icon.Name = "Icon"
	icon.LayoutOrder = 1
	-- X=1 (0이 아니다): AspectType 기본값 FitWithinMaxSize에서는 Size가 "이 상자 안에
	-- 비율 유지하며 넣어라"의 그 상자다. X=0이면 상자 폭이 0이라 결과가 0x0이 된다
	-- (U3-2 관측으로 확정 — DominantAxis는 ScaleWithParentSize에서만 동작해서 여기선
	-- 안 쓰인다). 상자를 넉넉히(1) 주고 실제 폭은 AspectRatioConstraint가 높이 기준으로 깎는다.
	icon.Size = UDim2.fromScale(1, 1)
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = icon
	icon.Parent = root

	local valuePanel = ValuePanel.create(LEVEL, ValuePanel.MAX_CHARS_DEFAULT)
	valuePanel.label.Name = "Value"
	valuePanel.label.LayoutOrder = 2
	-- X=1 (0이 아니다): ValuePanel의 UIAspectRatioConstraint도 AspectType 기본값
	-- FitWithinMaxSize라 Size가 상자다 — X=0이면 상자 폭 0으로 결과가 0x0이 된다
	-- (같은 관례가 Icon·ChallengeInfo/Timer·MenuRail/Tile에도 손으로 반복돼 있다, U3-2 관측).
	valuePanel.label.Size = UDim2.fromScale(1, 1)
	valuePanel.label.Parent = root

	valuePanel.setValue(Store.get("blox"))
	Store.subscribe("blox", function(value)
		valuePanel.setValue(value)
	end)

	return {
		root = root,
	}
end

return BloxDisplay

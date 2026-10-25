--!strict
-- HUD: 활성 부스트(포션) 남은 시간 (우측 레일 맨 위 — 상단 정보 띠 바로 아래). Phase 8 지시서 #16 5단계.
-- docs/UI.md "지시서 #16 > 부스트 남은 시간" · "2. 세이프존". 활성 포션이 있을 때만 작게 보이고, 없으면 숨긴다.
--
-- 자리: 우측 레일(중앙 금지 구역 밖)의 Y = Layout.TOP_HEIGHT부터 아래로 줄을 쌓는다. 우측 레일 위쪽은 비어 있다 —
--   아래쪽은 자동 도구(하단 띠 경계 위)와 로벅스 구좌(하단 띠)다. TouchSafeLayout이 올리는 우하단 묶음과도 멀다.
-- 글자: 소(2.5%) · 오른쪽 정렬 · 흰 글자 + 검은 테두리(8. 비주얼 스타일). 폰 하한 11px는 TextMinimum이 붙인다.
-- 줄 문구 · 남은 시간 계산은 UI/Logic/BoostTimersLogic(순수). 1초마다 다시 그린다(인스턴스를 새로 만들지 않는다 — 줄 3개를 미리 둔다).
-- "숨김" = 줄 라벨이 전부 Visible false(root는 투명한 틀로 열려 있다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local Layout = require(script.Parent.Parent.Parent.Layout)
local Store = require(script.Parent.Parent.Parent.Store)
local BoostTimersLogic = require(script.Parent.Parent.Parent.Logic.BoostTimersLogic)

local BoostTimers = {}

local LEVEL: TextScale.Level = "small"
local LINE_H = TextScale.Levels[LEVEL].heightFraction -- 화면 기준 줄 높이(2.5%)
local LINE_GAP = 0.005
local LINES = BoostTimersLogic.MAX_LINES
local TOTAL_H = LINES * LINE_H + (LINES - 1) * LINE_GAP
BoostTimers.TotalHeight = TOTAL_H
BoostTimers.TOP = Layout.TOP_HEIGHT -- 우측 레일 맨 위(상단 정보 띠 바로 아래)

export type Deps = {
	store: any?,
	now: (() -> number)?,
	autoTick: boolean?, -- 기본 true(1초마다 다시 그림). 테스트는 false로 두고 refresh를 직접 부른다
}

export type Handle = {
	root: Frame,
	refresh: () -> (),
	_debug: { labels: { TextLabel } },
}

function BoostTimers.create(deps: Deps?): Handle
	local d: Deps = deps or {}
	local source: any = d.store or Store
	local now = d.now or os.clock
	local rootWidth = Layout.RAIL_WIDTH - Layout.EDGE_MARGIN * 2 -- 우측 레일, ShopSlots · AutoTools와 같은 여백 관례

	local root = Instance.new("Frame")
	root.Name = "BoostTimers"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.fromScale(1 - Layout.EDGE_MARGIN, BoostTimers.TOP)
	root.Size = UDim2.fromScale(rootWidth, TOTAL_H)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	-- root는 늘 보인다(ScreenController.open이 Visible을 켠다 — 투명한 틀이다). 줄 라벨만 켜고 끈다(없으면 아무것도 안 보인다)

	local labels: { TextLabel } = {}
	for i = 1, LINES do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.Position = UDim2.fromScale(0, (i - 1) * (LINE_H + LINE_GAP) / TOTAL_H)
		label.Size = UDim2.fromScale(1, LINE_H / TOTAL_H)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Text = ""
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.SourceSansBold
		label.Visible = false
		label.Parent = root
		local size = Instance.new("UITextSizeConstraint")
		size.MaxTextSize = TextScale.Levels[LEVEL].maxTextSize
		size.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = label
		labels[i] = label
	end

	local function refresh()
		local lines = BoostTimersLogic.lines(source.get("shop"), now())
		for i, label in ipairs(labels) do
			local text = lines[i]
			label.Visible = text ~= nil
			label.Text = text or ""
		end
	end

	-- 폰 맞춤: 줄 높이 기본 2.5%가 글자 하한(TextScale.MIN_TEXT_PX)보다 작으면(Galaxy A06 높이 338px → 8.5px) 하한 + 1px로 키운다.
	-- Scale로 다시 쓴다(Offset 금지 — ShopSlots 가격 줄과 같은 방식). 부모(화면) 높이를 보고 정한다.
	local function fit()
		local parent = root.Parent
		local screenH = if parent ~= nil and parent:IsA("GuiBase2d") then (parent :: GuiBase2d).AbsoluteSize.Y else 0
		if screenH <= 0 then
			return
		end
		local lineH = math.max(LINE_H, (TextScale.MIN_TEXT_PX + 1) / screenH)
		local total = LINES * lineH + (LINES - 1) * LINE_GAP
		root.Size = UDim2.fromScale(rootWidth, total)
		for i, label in ipairs(labels) do
			label.Position = UDim2.fromScale(0, (i - 1) * (lineH + LINE_GAP) / total)
			label.Size = UDim2.fromScale(1, lineH / total)
		end
	end
	local parentConn: RBXScriptConnection? = nil
	root.AncestryChanged:Connect(function()
		if parentConn ~= nil then
			parentConn:Disconnect()
			parentConn = nil
		end
		local parent = root.Parent
		if parent ~= nil and parent:IsA("GuiBase2d") then
			parentConn = (parent :: GuiBase2d):GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		end
		fit()
	end)

	source.subscribe("shop", refresh)
	refresh()
	if d.autoTick ~= false then
		task.spawn(function()
			while true do
				task.wait(1)
				refresh()
			end
		end)
	end

	return { root = root, refresh = refresh, _debug = { labels = labels } }
end

return BoostTimers

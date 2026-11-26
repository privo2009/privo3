--!strict
-- 토스트 (OverlayGui 알림층 — 비차단). Phase 7 지시서 #10. 지금 쓰는 곳은 새 칭호 하나다(S15).
-- 큐 규칙(최대 3개 · 넘치면 큐 · 오래된 것부터 사라진다)은 UI/Logic/ToastLogic, 문구는 TitleWindowLogic.toastFor.
--
-- 자리: 상단 정보 띠(위 15%)의 오른쪽 — 챌린지 정보(가운데 0.35~0.65) · 환생 안내(0.28~0.72) 오른쪽, 위에서 아래로 쌓인다.
-- 중앙 금지 구역(위 15% 아래) 밖이다. 오른쪽 레일(오류 · 런 안내)을 쓰지 않은 이유: 폰에서는 자동 도구 · 구좌가
-- 그 자리로 올라오고(TouchSafeLayout, 2026-10-24 실측 y 0.357~0.659), 왼쪽 아래는 이동 조이스틱 영역이다.
-- 한 줄 = 소 단계 글자. **희귀도 색 글자 + 중립 어두운 바탕** — 희귀도 색 바탕에 흰 글자보다 등급이 먼저 읽힌다.
-- 배치값은 Claude가 정했다(docs/UI.md "지시서 #10" 절).
--
-- 폰 예외 (#L2, 2026-10-29 사람 결정): 한 줄 칸에 글자 하한(11px) 두 줄이 안 들어가는 낮은 화면(Galaxy A06 338px → 14.9px)에서는
-- 영어 토스트가 칸 폭(169px)을 넘친다. 그때만 **동시 2개 · 각 두 줄(글자 감싸기)**로 바꾼다 — 같은 띠 높이를 2줄로 나눠 쓴다.
-- 넘치는 토스트는 큐로 돌아가 차례를 기다린다(ToastLogic.setLimit — 잃지 않는다). 화면 높이가 바뀌면 다시 고른다.
--
-- 첫 접속 안내 띠와 자리 나누기 (지시서 #26 — #20 "알려진 것"): 안내 띠(OnboardingBand)가 이 칸(x 0.73 ~ · 위 0.005 ~ 0.145)을 같이 써서
-- 안내 중 토스트가 띠를 덮었다. 띠가 보이는 동안(setBelowBand(true))은 토스트를 **띠 바로 아래 오른쪽 레일 칸**으로 내린다 —
-- x 0.80 ~ 0.97 · y 0.15 ~ 0.225(오류 칸 ErrorNotice와 같은 자리 · 소 단계 3줄 높이). 중앙 금지 구역(x 0.2 ~ 0.8) 밖이고
-- 런 안내(오른쪽 레일 0.235 ~)와 겹치지 않는다. 칸이 좁아(폭 17%) **한 번에 1개 · 글자 감싸기**로 보이고 나머지는 큐에서 기다린다.
-- 오류 칸은 로딩 시간 초과에만 열린다 — 그때는 내리지 않는다(OverlayBoot가 정한다). 띠가 사라지면 원래 자리로 돌아간다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Layout = require(script.Parent.Parent.Parent.Layout)
local OverlayParts = require(script.Parent.OverlayParts)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local ToastLogic = require(script.Parent.Parent.Parent.Logic.ToastLogic)
local Kit = require(script.Parent.Parent.Parent.Components.Kit) -- UI 키트(#39 — 모양 숫자 · 색은 UiTheme.Skin)

local ToastStack = {}

local X0 = 0.73
local WIDTH = 1 - Layout.EDGE_MARGIN - X0 -- 0.24
local TOP = 0.005
local ROW_H = 0.044 -- 3줄 + 간격이 띠(0.15) 안에 들도록(부동소수 여유)
local GAP = 0.005
ToastStack.COMPACT_VISIBLE = 2 -- 폰 예외에서 동시에 보이는 수
ToastStack.Bounds = { x0 = X0, y0 = TOP, x1 = X0 + WIDTH, y1 = TOP + ToastLogic.MAX_VISIBLE * ROW_H + (ToastLogic.MAX_VISIBLE - 1) * GAP }
-- 띠 아래 칸(지시서 #26) — 오류 칸(ErrorNotice.Bounds)과 같은 사각형
ToastStack.BELOW_VISIBLE = 1
ToastStack.BelowBounds = {
	x0 = OverlayParts.RIGHT_RAIL_LEFT,
	y0 = Layout.TOP_HEIGHT,
	x1 = OverlayParts.RIGHT_RAIL_LEFT + OverlayParts.RIGHT_RAIL_WIDTH,
	y1 = Layout.TOP_HEIGHT + TextScale.Levels.small.heightFraction * 3,
}

export type Entry = { text: string, tier: number }

export type Handle = {
	root: Frame,
	push: (Entry) -> (),
	setBelowBand: (boolean) -> (),
	_rows: { TextLabel },
	_queue: ToastLogic.Queue<Entry>,
	_render: () -> (),
	_isCompact: () -> boolean,
	_isBelowBand: () -> boolean,
}

function ToastStack.create(now: (() -> number)?): Handle
	assert(ToastStack.Bounds.y1 <= Layout.TOP_HEIGHT, "ToastStack: 상단 정보 띠(15%)를 넘는다")
	local clock = now or os.clock
	local root = Instance.new("Frame")
	root.Name = "ToastStack"
	root.Position = UDim2.fromScale(X0, TOP)
	root.Size = UDim2.fromScale(WIDTH, ToastStack.Bounds.y1 - TOP)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = OverlayParts.Z.notice
	-- root는 늘 보이는 투명 틀이다(ScreenController.open이 root를 보이게 한다 — RebirthNotice와 같은 이유). 줄마다 Visible을 켠다.

	local height = ToastStack.Bounds.y1 - TOP
	local rows: { TextLabel } = {}
	for i = 1, ToastLogic.MAX_VISIBLE do
		local label = Kit.toastRow("Toast" .. i, "small") -- 키트(#39 — 어두운 바탕 · 오른쪽 정렬)
		label.Position = UDim2.fromScale(0, (i - 1) * (ROW_H + GAP) / height)
		label.Size = UDim2.fromScale(1, ROW_H / height)
		label.ZIndex = OverlayParts.Z.notice
		label.Visible = false
		label.Parent = root
		rows[i] = label
	end

	local queue = ToastLogic.new() :: ToastLogic.Queue<Entry>
	local compact = false
	local below = false
	local shownRows = #rows

	local function render()
		local list = queue.visible()
		for i, label in ipairs(rows) do
			local item = list[i]
			if item ~= nil and i <= shownRows then
				label.Text = item.text .. " "
				label.TextColor3 = UiTheme.rarityColor(item.tier)
				label.Visible = true
			else
				label.Visible = false
			end
		end
	end

	-- 줄 배치. 띠 아래 칸이면 한 줄이 칸 전체(감싸기). 아니면 원래 칸 — 폰 예외는 부모(화면) 높이로 한 줄 칸의 픽셀을 보고,
	-- 두 줄(하한 + 1px씩)이 안 들어가면 2개 · 두 줄로.
	local function layout()
		if below then
			root.Position = UDim2.fromScale(ToastStack.BelowBounds.x0, ToastStack.BelowBounds.y0)
			root.Size = UDim2.fromScale(ToastStack.BelowBounds.x1 - ToastStack.BelowBounds.x0, ToastStack.BelowBounds.y1 - ToastStack.BelowBounds.y0)
			shownRows = ToastStack.BELOW_VISIBLE
			for _, label in ipairs(rows) do
				label.Position = UDim2.fromScale(0, 0)
				label.Size = UDim2.fromScale(1, 1)
				label.TextWrapped = true
			end
		else
			root.Position = UDim2.fromScale(X0, TOP)
			root.Size = UDim2.fromScale(WIDTH, height)
			shownRows = if compact then ToastStack.COMPACT_VISIBLE else #rows
			local rowH = if compact then (height - (shownRows - 1) * GAP) / shownRows else ROW_H
			for i, label in ipairs(rows) do
				label.Position = UDim2.fromScale(0, (i - 1) * (rowH + GAP) / height)
				label.Size = UDim2.fromScale(1, rowH / height)
				label.TextWrapped = compact
			end
		end
		queue.setLimit(shownRows, clock())
		render()
	end

	local function fit()
		local parent = root.Parent
		local screenH = if parent ~= nil and parent:IsA("GuiBase2d") then (parent :: GuiBase2d).AbsoluteSize.Y else 0
		if screenH <= 0 then
			return
		end
		local want = ROW_H * screenH < 2 * (TextScale.MIN_TEXT_PX + 1)
		if want == compact then
			return
		end
		compact = want
		layout()
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

	-- 가장 오래된 것이 사라질 시각에 한 번만 깨운다(Heartbeat 루프를 두지 않는다 · 예약은 늘 하나).
	-- 깨어나면 지운 뒤 큐 맨 앞을 올리고, 아직 보이는 것이 있으면 다음 시각을 다시 예약한다.
	local scheduled = false
	local function schedule()
		if scheduled then
			return
		end
		local wait = queue.nextExpiryIn(clock())
		if wait == nil then
			return
		end
		scheduled = true
		task.delay(wait + 0.02, function()
			scheduled = false
			if queue.tick(clock()) then
				render()
			end
			schedule()
		end)
	end

	local function push(entry: Entry)
		queue.push(entry, clock())
		render()
		schedule()
	end

	-- 안내 띠가 보이는 동안 띠 아래 칸으로(지시서 #26). 같은 값이면 아무것도 하지 않는다.
	local function setBelowBand(on: boolean)
		if on == below then
			return
		end
		below = on
		layout()
		schedule()
	end

	return {
		root = root,
		push = push,
		setBelowBand = setBelowBand,
		_rows = rows,
		_queue = queue,
		_render = render,
		_isCompact = function()
			return compact
		end,
		_isBelowBand = function()
			return below
		end,
	}
end

return ToastStack

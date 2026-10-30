--!strict
-- 로벅스 상품 줄 목록 — 상점 로벅스 탭 · 아우라 · 펫 · 칭호 창이 같이 쓴다 (Phase 8 지시서 #16 · #17 — docs/UI.md "지시서 #17").
--
-- 줄 값(이름 · 설명 · 상태 · 가격 · 켜기)은 UI/Logic/RobuxShopLogic이 만든 Row다. 이 파일은 그리기 · 누르기 배선뿐이다.
--   줄 = 이름(중) · 설명 또는 확률(소) | [켜기(하늘) — 포션 줄만] | 구매(초록 btn_green) · 가격(소)
--   구매는 PurchaseClient(같은 키는 결과까지 한 번만), 켜기는 PotionClient(같은 종류는 결과까지 한 번만)
--   줄은 maxRows개를 만들고 그리는 순간의 줄 수만큼 보인다(제한 유저는 줄이 적다). 캔버스도 그 줄 수에서 유도한다.
-- 배치값은 지시서 #16 상점 로벅스 탭 값을 그대로 옮겼다(폰 줄 안 두 칸 11px — docs/UI.md "지시서 #16" 실측).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Button = require(script.Parent.Button)
local WindowParts = require(script.Parent.WindowParts)

local RobuxList = {}

local SCROLLBAR_PX = 6 -- ScrollBarThickness는 픽셀 정수 속성이라 Scale로 줄 수 없다(docs/UI.md "지시서 #12")
-- 줄 안(줄 기준 비율). 켜기 버튼은 윗칸(이름 옆)에만 둔다 — 이름 칸만 USE 폭만큼 줄고, 아랫줄 설명은 원래 폭 그대로
-- (폰 705×338에서 행운 포션 설명이 좁은 칸에 넘쳐서 — K12 레이아웃 먼저, 2026-10-31).
local LEFT_X = 0.02
local LEFT_W = 0.64
local LEFT_W_WITH_USE = 0.42
local USE_X = 0.46
local USE_W = 0.2
local BUTTON_X = 0.68
local BUTTON_W = 0.32
local BUTTON_H = 0.5
local FOOT_Y = 0.5
local FOOT_H = 0.5
RobuxList.Layout = { LEFT_W = LEFT_W, LEFT_W_WITH_USE = LEFT_W_WITH_USE, USE_X = USE_X, USE_W = USE_W, BUTTON_X = BUTTON_X, BUTTON_W = BUTTON_W }

export type RowParts = {
	frame: Frame,
	title: TextLabel,
	effect: TextLabel,
	foot: TextLabel,
	button: Button.ButtonHandle,
	buttonLabel: TextLabel,
	hit: TextButton,
	use: Button.ButtonHandle,
	useLabel: TextLabel,
	useHit: TextButton,
}

-- Row는 RobuxShopLogic.Row(순환 require를 피해 any로 받는다)
export type Options = {
	name: string,
	parent: Instance,
	position: UDim2,
	size: UDim2,
	rowH: number, -- 목록(보이는 높이) 기준 줄 높이
	rowGap: number, -- 목록 기준 줄 사이
	maxRows: number,
	raise: { Instance }, -- 버튼 루트를 모은다(창이 WindowParts.raiseButtons로 올린다)
	purchase: any, -- PurchaseClient.Client
	potion: any?, -- PotionClient(켜기). 없으면 켜기 버튼은 늘 잠김
	onPressed: (() -> ())?, -- 요청을 보낸 직후(창이 상태 문구를 지운다)
}

export type Handle = {
	list: ScrollingFrame,
	rows: { RowParts },
	render: (rows: { any }) -> (),
	pressBuy: (index: number) -> (),
	pressUse: (index: number) -> (),
	scrollTo: (index: number) -> (),
	view: () -> { any },
}

function RobuxList.create(o: Options): Handle
	local list = Instance.new("ScrollingFrame")
	list.Name = o.name
	list.Position = o.position
	list.Size = o.size
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR_PX
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ZIndex = 3
	list.Parent = o.parent

	local function canvasK(n: number): number
		return math.max(1, (o.rowH + o.rowGap) * n)
	end

	local rows: { RowParts } = {}
	for i = 1, o.maxRows do
		local frame = Instance.new("Frame")
		frame.Name = "RobuxRow_" .. i
		frame.BackgroundColor3 = UiTheme.Colors.neutral.dark -- 줄 바탕: 패널 자리표시(중립 기본)와 구분(워프 창 행 경계와 같은 이유)
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = list
		local title = WindowParts.makeText("Title", frame, "medium", LEFT_X, 0, LEFT_W, 0.5)
		local effect = WindowParts.makeText("Effect", frame, "small", LEFT_X, 0.5, LEFT_W, 0.5)
		local button = Button.create({ size = "Small", color = "green", widthScale = BUTTON_W, heightScale = BUTTON_H })
		button.root.Name = "BuyButton"
		button.root.Position = UDim2.fromScale(BUTTON_X, 0)
		button.root.ZIndex = WindowParts.Z_BUTTON
		button.root.Parent = frame
		local buttonLabel, hit = WindowParts.decorateButton(button, "")
		table.insert(o.raise, button.root)
		local use = Button.create({ size = "Small", color = "blue", widthScale = USE_W, heightScale = BUTTON_H })
		use.root.Name = "UseButton"
		use.root.Position = UDim2.fromScale(USE_X, 0)
		use.root.ZIndex = WindowParts.Z_BUTTON
		use.root.Visible = false
		use.root.Parent = frame
		local useLabel, useHit = WindowParts.decorateButton(use, "")
		table.insert(o.raise, use.root)
		local foot = WindowParts.makeText("Foot", frame, "small", BUTTON_X, FOOT_Y, BUTTON_W, FOOT_H, Enum.TextXAlignment.Center)
		rows[i] = { frame = frame, title = title, effect = effect, foot = foot, button = button, buttonLabel = buttonLabel, hit = hit,
			use = use, useLabel = useLabel, useHit = useHit }
	end

	local view: { any } = {}

	local function render(newRows: { any })
		view = newRows
		local k = canvasK(#view)
		list.CanvasSize = UDim2.fromScale(0, k)
		for i, parts in ipairs(rows) do
			local r = view[i]
			parts.frame.Visible = r ~= nil
			parts.frame.Position = UDim2.fromScale(0, (i - 1) * (o.rowH + o.rowGap) / k)
			parts.frame.Size = UDim2.fromScale(1, o.rowH / k)
			if r ~= nil then
				local hasUse = r.useKey ~= nil
				parts.title.Size = UDim2.fromScale(if hasUse then LEFT_W_WITH_USE else LEFT_W, 0.5)
				parts.title.Text = r.title
				parts.effect.Text = r.detail
				parts.foot.Text = r.footText
				parts.buttonLabel.Text = r.buttonText
				parts.button.setDisabled(not r.canBuy or (r.buyKey ~= nil and o.purchase.isPending(r.buyKey)))
				parts.use.root.Visible = hasUse
				if hasUse then
					parts.useLabel.Text = r.useText
					parts.use.setDisabled(not r.canUse or o.potion == nil or o.potion.isPending(r.useKey))
				end
			end
		end
	end

	local function pressBuy(index: number)
		local r = view[index]
		if r == nil or not r.canBuy or r.buyKey == nil then
			return
		end
		if o.purchase.request(r.buyKey) and o.onPressed ~= nil then
			o.onPressed()
		end
	end

	local function pressUse(index: number)
		local r = view[index]
		if r == nil or not r.canUse or r.useKey == nil or o.potion == nil then
			return
		end
		if o.potion.request(r.useKey) and o.onPressed ~= nil then
			o.onPressed()
		end
	end

	-- 그 줄이 보이게 목록을 내린다(HUD 부스트 표시 → 포션 묶음)
	local function scrollTo(index: number)
		local k = canvasK(#view)
		local y = (index - 1) * (o.rowH + o.rowGap) / k
		list.CanvasPosition = Vector2.new(0, y * list.AbsoluteCanvasSize.Y)
	end

	for i, parts in ipairs(rows) do
		parts.hit.Activated:Connect(function()
			pressBuy(i)
		end)
		parts.useHit.Activated:Connect(function()
			pressUse(i)
		end)
	end

	return {
		list = list,
		rows = rows,
		render = render,
		pressBuy = pressBuy,
		pressUse = pressUse,
		scrollTo = scrollTo,
		view = function()
			return view
		end,
	}
end

return RobuxList

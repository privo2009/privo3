--!strict
-- 코인 이펙트(지시서 #32 — 클라 전용): 블록이 깨진 자리에서 작은 코인이 튀어 HUD 코인 칸으로 날아간다.
-- 화면(2D) 위에 그린다 — 3D 자리를 화면 좌표로 바꿔 출발점으로 쓴다. 풀링(Frame 재사용) · 한 번에 MAX_PER_BURST개까지.
-- 에셋 자리: EconomyV2Config.COIN_VISUAL.effectId — nil이면 임시 도형(코인 색 원).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots) -- 에셋 자리(#36 — 값이 있으면 그 그림 · 없으면 임시 도형)
local Kit = require(script.Parent.Parent.UI.Components.Kit) -- UI 키트(#39 — 모양 숫자 · 색은 UiTheme.Skin)

local CoinFx = {}

CoinFx.MAX_PER_BURST = 6
CoinFx.FLY_SEC = 0.6
CoinFx.SIZE = 0.025 -- 화면 높이 대비(Scale — 폭은 비율 제약이 높이를 따라간다)

export type Options = {
	parent: Instance, -- ScreenGui
	toScreen: ((Vector3) -> Vector2?)?, -- 3D → 화면 픽셀(기본 현재 카메라)
	target: () -> Vector2, -- 날아갈 곳(HUD 코인 아이콘)
	clock: (() -> number)?,
	autoStep: boolean?,
}

export type Handle = {
	burst: (positions: { Vector3 }) -> number, -- 띄운 개수
	step: (now: number) -> (),
	flying: () -> number,
	poolSize: () -> number,
	destroy: () -> (),
}

local function defaultToScreen(pos: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local v, onScreen = camera:WorldToViewportPoint(pos)
	if not onScreen then
		return nil
	end
	return Vector2.new(v.X, v.Y)
end

function CoinFx.create(o: Options): Handle
	local clock = o.clock or os.clock
	local toScreen = o.toScreen or defaultToScreen
	local pool: { Frame } = {}
	local live: { { frame: Frame, from: Vector2, startAt: number } } = {}

	local function take(): Frame
		local f = table.remove(pool)
		if f == nil then
			local nf = Instance.new("Frame")
			nf.Name = "Coin"
			nf.AnchorPoint = Vector2.new(0.5, 0.5)
			nf.BackgroundColor3 = Config.COIN_VISUAL.color
			nf.BorderSizePixel = 0
			nf.Size = UDim2.fromScale(CoinFx.SIZE, CoinFx.SIZE)
			local a = Instance.new("UIAspectRatioConstraint")
			a.AspectRatio = 1
			a.DominantAxis = Enum.DominantAxis.Height
			a.Parent = nf
			Kit.corner(nf, "round") -- 키트(#39)
			if AssetSlots.applyImage(nf, Config.COIN_VISUAL.effectId) ~= nil then
				nf.BackgroundTransparency = 1 -- 그림이 있으면 임시 노란 원 대신(#36)
			end
			f = nf
		end
		local ff = f :: Frame
		ff.Visible = true
		ff.Parent = o.parent
		return ff
	end

	-- 화면 픽셀 → 부모 기준 Scale(UI는 Scale만 — CLAUDE.md 금지 사항). 부모 크기가 0이면(테스트 · 로드 전) 픽셀 그대로 1로 나눈다
	local function scaleAt(px: Vector2): UDim2
		local size = if o.parent:IsA("GuiBase2d") then (o.parent :: GuiBase2d).AbsoluteSize else Vector2.new(1, 1)
		local w, h = math.max(size.X, 1), math.max(size.Y, 1)
		return UDim2.fromScale(px.X / w, px.Y / h)
	end

	local self = {} :: Handle

	function self.burst(positions: { Vector3 }): number
		local n = 0
		local now = clock()
		for _, pos in ipairs(positions) do
			if n >= CoinFx.MAX_PER_BURST then
				break
			end
			local screen = toScreen(pos)
			if screen ~= nil then
				local f = take()
				f.Position = scaleAt(screen :: Vector2)
				table.insert(live, { frame = f, from = screen :: Vector2, startAt = now + n * 0.04 })
				n += 1
			end
		end
		return n
	end

	function self.step(now: number)
		if #live == 0 then
			return
		end
		local target = o.target()
		for i = #live, 1, -1 do
			local c = live[i]
			local t = math.clamp((now - c.startAt) / CoinFx.FLY_SEC, 0, 1)
			if t >= 1 then
				table.remove(live, i)
				c.frame.Visible = false
				c.frame.Parent = nil
				table.insert(pool, c.frame)
			else
				-- 처음에 위로 살짝 튀고(포물선) 아이콘으로 빨려 든다
				local p = c.from:Lerp(target, t * t)
				local hop = math.sin(t * math.pi) * 40 * (1 - t)
				c.frame.Position = scaleAt(Vector2.new(p.X, p.Y - hop))
			end
		end
	end

	function self.flying(): number
		return #live
	end

	function self.poolSize(): number
		return #pool
	end

	local conn: RBXScriptConnection? = nil
	if o.autoStep ~= false then
		conn = RunService.RenderStepped:Connect(function()
			self.step(clock())
		end)
	end

	function self.destroy()
		if conn ~= nil then
			conn:Disconnect()
		end
		for _, c in ipairs(live) do
			c.frame:Destroy()
		end
		table.clear(live)
		for _, f in ipairs(pool) do
			f:Destroy()
		end
		table.clear(pool)
	end

	return self
end

return CoinFx

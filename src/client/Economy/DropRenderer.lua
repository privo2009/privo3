--!strict
-- 광석 드롭 표시(지시서 #32 — 클라 전용). 서버가 "어디에 무엇이 떨어졌다"를 알리면 그린다 — 판정은 서버.
-- 절대 규칙 4: 물리 없음(Anchored · CanCollide false) · 반복 생성 없음(풀링 — Part를 다시 쓴다).
-- 모습(임시 도형): 광석 재질 색의 작은 정육면체를 45도 돌려 세운 것 · 바닥 위에 떠서 천천히 오르내리며 돈다.
-- 에셋 자리(#36 — DESIGN 16장 "에셋 교체 방식"): ORE_VISUALS[k].modelId가 있고 서버 AssetLoader가 불러 둔 틀(AssetSlots "ore_k" — MeshPart 하나,
--           Model이면 PrimaryPart)이 있으면 그것을 복제해 쓴다(색은 모델 그대로 · 크기도 모델 그대로). 없으면 임시 도형.
--           effectId가 있으면 드롭에 반짝이 파티클(ParticleEmitter.Texture — 클라 전용 · 절대 규칙 4). 풀은 모습(틀 키)마다 따로다
-- 줍기: 서버가 "주웠다"를 알리면 플레이어 쪽으로 날아가며 작아지고 사라진다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)

local DropRenderer = {}

DropRenderer.SIZE = 0.9 -- 스터드(시각 튜닝값)
DropRenderer.HOVER = 1.2 -- 바닥 위 높이
DropRenderer.BOB = 0.25 -- 오르내림 폭
DropRenderer.SPIN = 1.2 -- 초당 회전(라디안)
DropRenderer.FLY_SEC = 0.35 -- 주웠을 때 날아가는 시간

export type Options = {
	parent: Instance?, -- 드롭 Part를 담을 곳(기본 workspace 아래 폴더)
	getTarget: (() -> Vector3?)?, -- 주운 드롭이 날아갈 곳(기본 내 캐릭터 루트)
	clock: (() -> number)?,
	autoStep: boolean?, -- 기본 true — RenderStepped로 움직인다(테스트는 false · step을 직접)
	template: ((key: string) -> Instance?)?, -- 모델 틀 찾기(기본 AssetSlots.template — 테스트는 가짜 틀)
}

export type Handle = {
	spawn: (drops: { any }) -> (),
	pick: (ids: { number }) -> (),
	clear: () -> (),
	step: (now: number) -> (),
	activeCount: () -> number,
	poolSize: () -> number,
	partOf: (id: number) -> BasePart?,
	destroy: () -> (),
}

local function defaultTarget(): Vector3?
	local player = game:GetService("Players").LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function DropRenderer.create(options: Options?): Handle
	local o = options or {}
	local clock = o.clock or os.clock
	local folder: Instance
	if o.parent ~= nil then
		folder = o.parent :: Instance
	else
		local f = Instance.new("Folder")
		f.Name = "EconomyDrops"
		f.Parent = workspace
		folder = f
	end
	local getTarget = o.getTarget or defaultTarget

	local findTemplate = o.template or function(key: string): Instance?
		return AssetSlots.template(key)
	end
	local pools: { [string]: { BasePart } } = {}
	local active: { [number]: { part: BasePart, base: Vector3, phase: number } } = {}
	local flying: { { part: BasePart, from: Vector3, startAt: number, size: Vector3 } } = {}
	local created = 0
	local TEMP_KEY = "temp"

	-- 광석 k의 모델 틀(BasePart) — 없으면 nil(임시 도형)
	local function templateOf(k: number): BasePart?
		local t = findTemplate("ore_" .. k)
		if t == nil then
			return nil
		end
		if t:IsA("BasePart") then
			return t
		end
		if t:IsA("Model") then
			return t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart", true)
		end
		return nil
	end

	local function take(k: number): BasePart
		local tpl = templateOf(k)
		local key = if tpl ~= nil then "ore_" .. k else TEMP_KEY
		local pool = pools[key]
		local part = if pool ~= nil then table.remove(pool) else nil
		if part == nil then
			local p: BasePart
			if tpl ~= nil then
				p = (tpl :: BasePart):Clone()
				p:ClearAllChildren()
			else
				local np = Instance.new("Part")
				np.Material = Enum.Material.SmoothPlastic
				np.Size = Vector3.new(DropRenderer.SIZE, DropRenderer.SIZE, DropRenderer.SIZE)
				p = np
			end
			p.Name = "OreDrop"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p:SetAttribute("PoolKey", key)
			p:SetAttribute("BaseSize", p.Size)
			created += 1
			part = p
		end
		local pp = part :: BasePart
		pp.Size = pp:GetAttribute("BaseSize") :: Vector3
		pp.Transparency = 0
		-- 반짝이(effectId — 없으면 끔)
		local texture = AssetSlots.contentId((Config.ORE_VISUALS[k] or Config.ORE_VISUALS[1]).effectId)
		local fx = pp:FindFirstChild("OreFx") :: ParticleEmitter?
		if texture ~= nil and fx == nil then
			local e = Instance.new("ParticleEmitter")
			e.Name = "OreFx"
			e.Rate = 4
			e.Lifetime = NumberRange.new(0.4, 0.8)
			e.Speed = NumberRange.new(0.5, 1)
			e.Size = NumberSequence.new(0.4)
			e.Parent = pp
			fx = e
		end
		if fx ~= nil then
			fx.Enabled = texture ~= nil
			if texture ~= nil then
				fx.Texture = texture
			end
		end
		pp.Parent = folder
		return pp
	end

	local function give(part: BasePart)
		part.Parent = nil
		local key = part:GetAttribute("PoolKey") :: string? or TEMP_KEY
		local pool = pools[key]
		if pool == nil then
			pool = {}
			pools[key] = pool
		end
		table.insert(pool :: { BasePart }, part)
	end

	local self = {} :: Handle

	function self.spawn(drops: { any })
		for _, d in ipairs(drops) do
			if type(d) == "table" and type(d.id) == "number" and active[d.id] == nil and typeof(d.position) == "Vector3" then
				local ore = if Config.ORE_VISUALS[d.ore] ~= nil then d.ore else 1
				local part = take(ore)
				if part:GetAttribute("PoolKey") == TEMP_KEY then
					part.Color = Config.ORE_VISUALS[ore].color -- 임시 도형만 칠한다(모델은 제 색)
				end
				local base = (d.position :: Vector3) + Vector3.new(0, DropRenderer.HOVER, 0)
				part.CFrame = CFrame.new(base) * CFrame.Angles(math.rad(45), 0, math.rad(45))
				active[d.id] = { part = part, base = base, phase = (d.id % 7) / 7 * math.pi * 2 }
			end
		end
	end

	function self.pick(ids: { number })
		local now = clock()
		for _, id in ipairs(ids) do
			local a = active[id]
			if a ~= nil then
				active[id] = nil
				table.insert(flying, { part = a.part, from = a.part.Position, startAt = now, size = a.part.Size })
			end
		end
	end

	function self.clear()
		for id, a in pairs(active) do
			active[id] = nil
			give(a.part)
		end
	end

	function self.step(now: number)
		for _, a in pairs(active) do
			local y = math.sin(now * 2 + a.phase) * DropRenderer.BOB
			a.part.CFrame = CFrame.new(a.base + Vector3.new(0, y, 0)) * CFrame.Angles(math.rad(45), now * DropRenderer.SPIN + a.phase, math.rad(45))
		end
		if #flying > 0 then
			local target = getTarget()
			for i = #flying, 1, -1 do
				local f = flying[i]
				local t = math.clamp((now - f.startAt) / DropRenderer.FLY_SEC, 0, 1)
				if t >= 1 or target == nil then
					table.remove(flying, i)
					give(f.part)
				else
					f.part.Size = f.size * (1 - t * 0.8)
					f.part.CFrame = CFrame.new(f.from:Lerp(target :: Vector3, t))
					f.part.Transparency = t * 0.6
				end
			end
		end
	end

	function self.activeCount(): number
		local n = 0
		for _ in pairs(active) do
			n += 1
		end
		return n
	end

	function self.poolSize(): number
		local n = 0
		for _, pool in pairs(pools) do
			n += #pool
		end
		return n
	end

	function self.partOf(id: number): BasePart?
		local a = active[id]
		return if a ~= nil then a.part else nil
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
		self.clear()
		for _, f in ipairs(flying) do
			give(f.part)
		end
		table.clear(flying)
		for _, pool in pairs(pools) do
			for _, p in ipairs(pool) do
				p:Destroy()
			end
		end
		table.clear(pools)
		if o.parent == nil then
			folder:Destroy()
		end
	end

	return self
end

return DropRenderer

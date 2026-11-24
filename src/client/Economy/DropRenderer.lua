--!strict
-- 광석 드롭 표시(지시서 #32 — 클라 전용 · 플래그 ECONOMY_V2 뒤). 서버가 "어디에 무엇이 떨어졌다"를 알리면 그린다 — 판정은 서버.
-- 절대 규칙 4: 물리 없음(Anchored · CanCollide false) · 반복 생성 없음(풀링 — Part를 다시 쓴다).
-- 모습(임시 도형): 광석 재질 색의 작은 정육면체를 45도 돌려 세운 것 · 바닥 위에 떠서 천천히 오르내리며 돈다.
-- 에셋 자리: EconomyV2Config.ORE_VISUALS[k].modelId — 지금은 nil(임시 도형). 값을 넣는 방식은 #36 에셋 주문서에서 정한다
--           (⚠️ 런타임 메시 교체 방식은 공식 문서로 확인하지 않았다 — 기억으로 쓰지 않는다).
-- 줍기: 서버가 "주웠다"를 알리면 플레이어 쪽으로 날아가며 작아지고 사라진다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)

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

	local pool: { BasePart } = {}
	local active: { [number]: { part: BasePart, base: Vector3, phase: number } } = {}
	local flying: { { part: BasePart, from: Vector3, startAt: number } } = {}
	local created = 0

	local function take(): BasePart
		local part = table.remove(pool)
		if part == nil then
			local p = Instance.new("Part")
			p.Name = "OreDrop"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Size = Vector3.new(DropRenderer.SIZE, DropRenderer.SIZE, DropRenderer.SIZE)
			created += 1
			part = p
		end
		local pp = part :: BasePart
		pp.Size = Vector3.new(DropRenderer.SIZE, DropRenderer.SIZE, DropRenderer.SIZE)
		pp.Transparency = 0
		pp.Parent = folder
		return pp
	end

	local function give(part: BasePart)
		part.Parent = nil
		table.insert(pool, part)
	end

	local self = {} :: Handle

	function self.spawn(drops: { any })
		for _, d in ipairs(drops) do
			if type(d) == "table" and type(d.id) == "number" and active[d.id] == nil and typeof(d.position) == "Vector3" then
				local visual = Config.ORE_VISUALS[d.ore] or Config.ORE_VISUALS[1]
				local part = take()
				part.Color = visual.color
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
				table.insert(flying, { part = a.part, from = a.part.Position, startAt = now })
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
					local s = DropRenderer.SIZE * (1 - t * 0.8)
					f.part.Size = Vector3.new(s, s, s)
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
		return #pool
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
		for _, p in ipairs(pool) do
			p:Destroy()
		end
		table.clear(pool)
		if o.parent == nil then
			folder:Destroy()
		end
	end

	return self
end

return DropRenderer

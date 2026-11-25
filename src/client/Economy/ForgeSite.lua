--!strict
-- 로비 임시 대장간(지시서 #33 — 에셋 자리 EconomyV2Config.FORGE_SITE · modelId가 nil이면 임시 도형).
-- 클라 전용 파트다(내 화면에만 — 대장간이 열린 사람에게만 보여야 하므로 서버가 만들지 않는다). 근접 프롬프트(ProximityPrompt)가 창을 연다.
-- 프롬프트는 "창을 열어라" 신호일 뿐 권한이 아니다 — 제작 · 교환 판정은 전부 서버(ForgeService)다.
-- 대장간이 닫혀 있으면 만들지 않는다(setOpen(false)면 지운다).
-- 에셋 자리(#36): 서버 AssetLoader가 불러 둔 틀(AssetSlots "forge_site" — Model)이 있으면 복제해 같은 자리(바닥 가운데 = FORGE_SITE.position)에 둔다 ·
-- 프롬프트는 그 모델의 PrimaryPart(없으면 첫 파트)에 · 전부 고정(Anchored). effectId가 있으면 화로에 불꽃 파티클(ParticleEmitter.Texture).
-- 속성 이름은 공식 문서 ProximityPrompt(ActionText · ObjectText · MaxActivationDistance · HoldDuration · RequiresLineOfSight · Triggered)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local ProximityConfig = require(ReplicatedStorage.Shared.Config.ProximityConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local ForgeSite = {}

export type Handle = {
	setOpen: (open: boolean) -> (),
	model: () -> Model?,
	prompt: () -> ProximityPrompt?,
	destroy: () -> (),
}

function ForgeSite.create(options: { parent: Instance?, onOpen: () -> (), template: ((string) -> Instance?)? }): Handle
	local parent = options.parent or workspace
	local model: Model? = nil
	local prompt: ProximityPrompt? = nil

	local findTemplate = options.template or function(key: string): Instance?
		return AssetSlots.template(key)
	end

	-- 모델 틀이 있으면 복제(같은 자리 · 고정). 프롬프트를 붙일 파트를 돌려준다
	local function buildFromTemplate(tpl: Model): (Model, BasePart?)
		local site = Config.FORGE_SITE
		local m = tpl:Clone()
		m.Name = "ForgeSite"
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local _, size = m:GetBoundingBox()
		m:PivotTo(CFrame.new(site.position + Vector3.new(0, size.Y / 2, 0)))
		return m, m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	end

	local function build()
		local site = Config.FORGE_SITE
		local tpl = findTemplate("forge_site")
		if tpl ~= nil and tpl:IsA("Model") then
			local m, anchor = buildFromTemplate(tpl)
			if anchor ~= nil then
				local p = Instance.new("ProximityPrompt")
				p.Name = "ForgePrompt"
				p.AutoLocalize = false
				p.ActionText = Locale.t("forge.prompt.action")
				p.ObjectText = Locale.t("forge.title")
				p.MaxActivationDistance = ProximityConfig.FORGE_PROMPT_DISTANCE
				p.HoldDuration = 0
				p.RequiresLineOfSight = false
				p.Triggered:Connect(function()
					options.onOpen()
				end)
				p.Parent = anchor
				m.Parent = parent
				model, prompt = m, p
				return
			end
			m:Destroy()
		end
		local m = Instance.new("Model")
		m.Name = "ForgeSite"
		-- 임시 도형: 몸통(블록) + 지붕 + 화로(주황 칸)
		local base = Instance.new("Part")
		base.Name = "Base"
		base.Anchored = true
		base.Size = site.size
		base.Position = site.position + Vector3.new(0, site.size.Y / 2, 0)
		base.Color = site.color
		base.Material = Enum.Material.Brick
		base.Parent = m
		local roof = Instance.new("WedgePart")
		roof.Name = "Roof"
		roof.Anchored = true
		roof.CanCollide = false
		roof.Size = Vector3.new(site.size.X + 1, 2, site.size.Z / 2 + 0.5)
		roof.CFrame = CFrame.new(site.position + Vector3.new(0, site.size.Y + 1, site.size.Z / 4))
		roof.Color = Color3.fromRGB(70, 50, 40)
		roof.Parent = m
		local fire = Instance.new("Part")
		fire.Name = "Fire"
		fire.Anchored = true
		fire.CanCollide = false
		fire.Size = Vector3.new(site.size.X * 0.4, site.size.Y * 0.3, 0.4)
		fire.Position = site.position + Vector3.new(0, site.size.Y * 0.35, site.size.Z / 2 + 0.2) -- 스폰 쪽(+Z) 면(Play #33 — -Z 면은 벽에 가렸다)
		fire.Color = Color3.fromRGB(255, 120, 30)
		fire.Material = Enum.Material.Neon
		fire.Parent = m
		local fireTexture = AssetSlots.contentId(site.effectId)
		if fireTexture ~= nil then
			local e = Instance.new("ParticleEmitter")
			e.Name = "ForgeFx"
			e.Texture = fireTexture
			e.Rate = 8
			e.Parent = fire
		end
		m.PrimaryPart = base
		local p = Instance.new("ProximityPrompt")
		p.Name = "ForgePrompt"
		p.AutoLocalize = false
		p.ActionText = Locale.t("forge.prompt.action")
		p.ObjectText = Locale.t("forge.title")
		p.MaxActivationDistance = ProximityConfig.FORGE_PROMPT_DISTANCE
		p.HoldDuration = 0
		p.RequiresLineOfSight = false
		p.Triggered:Connect(function()
			options.onOpen()
		end)
		p.Parent = base
		m.Parent = parent
		model, prompt = m, p
	end

	local self = {} :: Handle
	function self.setOpen(open: boolean)
		if open and model == nil then
			build()
		elseif not open and model ~= nil then
			(model :: Model):Destroy()
			model, prompt = nil, nil
		end
	end
	function self.model(): Model?
		return model
	end
	function self.prompt(): ProximityPrompt?
		return prompt
	end
	function self.destroy()
		self.setOpen(false)
	end
	return self
end

return ForgeSite

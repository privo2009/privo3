--!strict
-- 부화 연출(지시서 #35 — 제작 연출과 같은 모델). 임시 도형: 알 모양 칸이 흔들린 뒤 결과 이름(희귀도 색).
-- 스킵 버튼은 HATCH_SKIP_SEC에 나타나고 HATCH_ANIM_SEC가 지나면 닫힌다(서버가 같은 간격을 강제한다 — PetService).
-- 에셋 자리: EconomyV2Config.HATCH_FX_VISUAL(nil이면 임시 도형 — 런타임 교체 방식은 #36). 문장은 Strings 키 · AutoLocalize false · UiTheme.FONT · Scale만.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots) -- 에셋 자리(#36 — 값이 있으면 그 그림 · 없으면 임시 도형)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Button = require(script.Parent.Parent.UI.Components.Button)
local WindowParts = require(script.Parent.Parent.UI.Components.WindowParts)
local PetWindowLogic = require(script.Parent.Parent.UI.Logic.PetWindowLogic)

local HatchFx = {}

HatchFx.REVEAL_SEC = 1 -- 알이 흔들리다 결과가 보이는 시점(임시)
local Z = 30

export type Handle = {
	root: Frame,
	show: (pets: { any }) -> (),
	step: (now: number) -> (),
	isOpen: () -> boolean,
	_debug: any,
}

function HatchFx.create(options: { parent: Instance, clock: (() -> number)?, autoStep: boolean? }): Handle
	local clock = options.clock or os.clock
	local root = Instance.new("Frame")
	root.Name = "HatchFx"
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0.35
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = Z
	root.Visible = false
	root.Parent = options.parent

	local egg = Instance.new("Frame") -- 임시 도형(알)
	egg.Name = "Egg"
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	egg.Position = UDim2.fromScale(0.5, 0.42)
	egg.Size = UDim2.fromScale(0.12, 0.3)
	egg.BackgroundColor3 = Color3.fromRGB(245, 235, 210)
	egg.ZIndex = Z + 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = egg
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.75
	aspect.Parent = egg
	egg.Parent = root
	-- 에셋 자리(#36): 알 그림이 있으면 임시 알 칸 대신 · 결과 빛 그림은 이름 뒤(드러난 뒤에만)
	if AssetSlots.applyImage(egg, Config.HATCH_FX_VISUAL.eggImageId) ~= nil then
		egg.BackgroundTransparency = 1
	end
	local burst = AssetSlots.applyImage(root, Config.HATCH_FX_VISUAL.effectId, { position = UDim2.fromScale(0.5, 0.42), size = UDim2.fromScale(0.5, 0.6) })
	if burst ~= nil then
		burst.ZIndex = Z + 1
		burst.Visible = false
	end

	local title = WindowParts.makeText("Title", root, "large", 0.2, 0.12, 0.6, 0.08, Enum.TextXAlignment.Center)
	title.AutoLocalize = false
	title.ZIndex = Z + 2
	local names: { TextLabel } = {}
	for i = 1, 3 do
		local l = WindowParts.makeText("Name" .. i, root, "large", 0.15, 0.3 + (i - 1) * 0.1, 0.7, 0.09, Enum.TextXAlignment.Center)
		l.AutoLocalize = false
		l.ZIndex = Z + 2
		l.Visible = false
		names[i] = l
	end
	local skip = Button.create({ size = "Small", color = "gray", widthScale = 0.16, heightScale = 0.08 })
	skip.root.Name = "Skip"
	skip.root.AnchorPoint = Vector2.new(0.5, 0)
	skip.root.Position = UDim2.fromScale(0.5, 0.72)
	skip.root.Parent = root
	local skipLabel, skipHit = WindowParts.decorateButton(skip, Locale.t("forge.skip"))
	skipLabel.AutoLocalize = false
	for _, o in ipairs(skip.root:GetDescendants()) do
		if o:IsA("GuiObject") then
			o.ZIndex = Z + 3
		end
	end
	skip.root.ZIndex = Z + 3
	skip.root.Visible = false

	local startAt: number? = nil
	local shown: { any } = {}

	local function close()
		root.Visible = false
		startAt = nil
	end

	local function step(now: number)
		if startAt == nil then
			return
		end
		local t = now - (startAt :: number)
		local revealed = t >= HatchFx.REVEAL_SEC
		egg.Visible = not revealed
		if burst ~= nil then
			burst.Visible = revealed
		end
		-- 흔들기(임시 — 회전만)
		egg.Rotation = if revealed then 0 else math.sin(t * 20) * 12
		for i, l in ipairs(names) do
			l.Visible = revealed and shown[i] ~= nil
		end
		skip.root.Visible = t >= Config.HATCH_SKIP_SEC
		if t >= Config.HATCH_ANIM_SEC then
			close()
		end
	end

	local function show(pets: { any })
		shown = pets
		title.Text = Locale.t("pet.hatching")
		for i, l in ipairs(names) do
			local p = pets[i]
			if p ~= nil then
				local def, _, rarity = PetConfig.get(p.petId)
				l.Text = if def ~= nil then Names.pet(p.petId) else tostring(p.petId)
				l.TextColor3 = UiTheme.rarityColor(PetWindowLogic.rarityTier(rarity or 1))
			end
		end
		root.Visible = true
		startAt = clock()
		step(clock())
	end

	skipHit.Activated:Connect(close)
	if options.autoStep ~= false then
		local conn = RunService.Heartbeat:Connect(function()
			step(clock())
		end)
		root.Destroying:Connect(function()
			conn:Disconnect()
		end)
	end

	return {
		root = root,
		show = show,
		step = step,
		isOpen = function()
			return root.Visible
		end,
		_debug = { skip = skip.root, names = names, egg = egg, burst = burst },
	}
end

return HatchFx

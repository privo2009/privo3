--!strict
-- ⚠️ 개발 도구다. 게임 런타임에 실행되지 않는다 (Bootstrap 등 어디서도 require하지 않음).
-- Studio 커맨드 바에서 한 번 실행해서 모델을 만들고, 그 결과(ServerStorage.BlockModels 밑에
-- 생성된 Model)를 저장(파일 → 저장, 혹은 원하는 위치로 드래그)해서 실제 게임에 쓴다.
--
-- Phase 3-4: 블록 모델 생성. 격자 크기는 4x4x4(64개/블록)로 확정 —
-- 근거: 파편 동시 상한 200개(CLAUDE.md) 안에서 블록 3개가 동시에 완전파괴돼도
-- (3×64=192) 풀 한계를 안 넘는 선. 5x5x5(125개)는 블록 2개만 동시파괴돼도 넘는다.
-- ⚠️ 실제 격자/큐브 크기 값은 여기 하드코딩하지 않는다. src/shared/Config/BlockLayoutConfig.lua
-- 가 유일한 출처다 — BlockService.lua의 배치 반지름도 같은 Config에서 파생되므로, 크기를
-- 바꾸려면 이 파일이 아니라 그쪽을 고쳐야 두 모듈이 계속 맞물린다.
--
-- 사용 예 (커맨드 바):
--   local Gen = require(game.ServerScriptService.Server.Tools.BlockModelGenerator)
--   Gen.generateAndSave({ gridSize = 4, materialPreset = "wood" })
--   Gen.generateAllPresets(4) -- 재질 6종 전부 한 번에 생성
--   Gen.previewLayout(8, "stone") -- 8개 배치를 Workspace에서 눈으로 확인 (개발용, 게임에 안 씀)

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockService = require(script.Parent.Parent.Systems.BlockService)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)

export type MaterialPreset = {
	name: string,
	color: Color3,
	material: Enum.Material,
}

local BlockModelGenerator = {}

-- 재질 프리셋. DESIGN.md "재질 진행": 나무 → 돌 → 철 → 크리스탈 → 용암 → 우주.
-- ⚠️ 색상/머티리얼 값은 전부 임시(placeholder)다. 디자인 담당이 실제 텍스처/머티리얼로
-- 교체할 자리 — 이 테이블만 바꾸면 되도록 색상값을 여기 한 곳에 모아뒀다.
local MATERIAL_PRESETS: { [string]: MaterialPreset } = {
	wood = { name = "wood", color = Color3.fromRGB(133, 94, 66), material = Enum.Material.Wood },
	stone = { name = "stone", color = Color3.fromRGB(150, 150, 150), material = Enum.Material.Slate },
	iron = { name = "iron", color = Color3.fromRGB(180, 180, 190), material = Enum.Material.Metal },
	crystal = { name = "crystal", color = Color3.fromRGB(120, 200, 255), material = Enum.Material.Glass },
	lava = { name = "lava", color = Color3.fromRGB(255, 90, 20), material = Enum.Material.Neon },
	space = { name = "space", color = Color3.fromRGB(20, 20, 40), material = Enum.Material.ForceField },
}

BlockModelGenerator.MATERIAL_PRESETS = MATERIAL_PRESETS

-- previewLayout이 쓰는 Workspace 폴더 이름. 항상 이 폴더 하나만 유지한다.
local PREVIEW_FOLDER_NAME = "BlockLayoutPreview"

export type GenerateOptions = {
	gridSize: number, -- 한 변당 큐브 개수. 4면 4x4x4=64개.
	cubeSize: number?, -- 큐브 한 변 길이(studs). 기본 BlockLayoutConfig.CUBE_SIZE.
	materialPreset: string?, -- MATERIAL_PRESETS 키. 기본 "wood".
	canCollide: boolean?, -- 기본 true. 파괴된 뒤 파편은 Phase 3-2 클라 코드가 별도로 다룸.
	modelName: string?,
}

-- 격자 좌표(x,y,z, 0부터 시작) -> 1부터 시작하는 순차 인덱스.
-- BlockShuffle.computeDestructionOrder(seed, count)가 반환하는 순열이 가리키는 인덱스가
-- 바로 이 GridIndex와 대응된다 — 클라가 그 순서대로 GridIndex를 찾아 큐브를 지운다.
local function gridIndex(x: number, y: number, z: number, gridSize: number): number
	return x * gridSize * gridSize + y * gridSize + z + 1
end

-- 정육면체 격자를 큐브로 채운 Model을 만든다. Parent는 아직 안 붙인다 (generateAndSave가 붙임).
function BlockModelGenerator.generate(options: GenerateOptions): Model
	local gridSize = options.gridSize
	assert(type(gridSize) == "number" and gridSize >= 1 and gridSize == math.floor(gridSize), "gridSize는 1 이상의 정수여야 함")

	local cubeSize = options.cubeSize or BlockLayoutConfig.CUBE_SIZE
	assert(cubeSize > 0, "cubeSize는 0보다 커야 함")

	local presetKey = options.materialPreset or "wood"
	local preset = MATERIAL_PRESETS[presetKey]
	assert(preset ~= nil, "알 수 없는 재질 프리셋: " .. tostring(presetKey))

	local canCollide = options.canCollide
	if canCollide == nil then
		canCollide = true
	end

	local model = Instance.new("Model")
	model.Name = options.modelName or string.format("Block_%dx%dx%d_%s", gridSize, gridSize, gridSize, preset.name)

	-- 격자를 모델 중심(원점) 기준으로 배치.
	local offset = (gridSize - 1) * cubeSize / 2

	local firstCube: Part? = nil

	for x = 0, gridSize - 1 do
		for y = 0, gridSize - 1 do
			for z = 0, gridSize - 1 do
				local index = gridIndex(x, y, z, gridSize)

				local cube = Instance.new("Part")
				cube.Name = string.format("Cube_%d", index)
				cube.Size = Vector3.new(cubeSize, cubeSize, cubeSize)
				cube.CFrame = CFrame.new(x * cubeSize - offset, y * cubeSize - offset, z * cubeSize - offset)
				cube.Anchored = true -- DESIGN.md: 물리 시뮬레이션 금지, 수동 낙하 애니메이션만
				cube.CanCollide = canCollide :: boolean
				cube.Color = preset.color
				cube.Material = preset.material
				cube.TopSurface = Enum.SurfaceType.Smooth
				cube.BottomSurface = Enum.SurfaceType.Smooth

				-- 클라가 파괴 순서를 매핑할 때 쓰는 격자 인덱스/좌표.
				cube:SetAttribute("GridIndex", index)
				cube:SetAttribute("GridX", x)
				cube:SetAttribute("GridY", y)
				cube:SetAttribute("GridZ", z)

				cube.Parent = model

				if firstCube == nil then
					firstCube = cube
				end
			end
		end
	end

	if firstCube ~= nil then
		model.PrimaryPart = firstCube
	end

	model:SetAttribute("GridSize", gridSize)
	model:SetAttribute("CubeCount", gridSize ^ 3)
	model:SetAttribute("MaterialPreset", preset.name)

	return model
end

-- generate()로 만든 모델을 ServerStorage.BlockModels 밑에 배치하고 반환한다.
function BlockModelGenerator.generateAndSave(options: GenerateOptions): Model
	local model = BlockModelGenerator.generate(options)

	local folder = ServerStorage:FindFirstChild("BlockModels") :: Folder?
	if folder == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "BlockModels"
		newFolder.Parent = ServerStorage
		folder = newFolder
	end

	model.Parent = folder

	print(string.format(
		"[BlockModelGenerator] %s 생성 완료 (%d개 큐브) -> ServerStorage.BlockModels",
		model.Name,
		model:GetAttribute("CubeCount") :: number
	))

	return model
end

-- MATERIAL_PRESETS에 있는 재질 6종 전부를 같은 gridSize/cubeSize로 한 번에 생성한다.
function BlockModelGenerator.generateAllPresets(gridSize: number, cubeSize: number?, canCollide: boolean?): { Model }
	local models = {}
	for presetKey in pairs(MATERIAL_PRESETS) do
		table.insert(
			models,
			BlockModelGenerator.generateAndSave({
				gridSize = gridSize,
				cubeSize = cubeSize,
				materialPreset = presetKey,
				canCollide = canCollide,
			})
		)
	end
	return models
end

-- materialName에 해당하는 블록 템플릿을 구한다. ServerStorage.BlockModels에 이미 저장된
-- 게 있으면 그걸 쓰고(디자인 담당이 손댄 버전을 그대로 미리보기에 반영하기 위함), 없으면
-- 미리보기 전용으로 즉석에서 하나 만든다 (ServerStorage에 저장하지 않음).
local function getOrCreateTemplate(materialName: string, cubeSize: number?): Model
	local folder = ServerStorage:FindFirstChild("BlockModels")
	if folder ~= nil then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("MaterialPreset") == materialName then
				return child :: Model
			end
		end
	end

	return BlockModelGenerator.generate({
		gridSize = BlockLayoutConfig.GRID_SIZE,
		materialPreset = materialName,
		cubeSize = cubeSize,
	})
end

-- model을 강체 이동시켜 "모델 전체의 기하학적 중심"이 targetPosition에 오도록 한다.
-- generate()가 만드는 모델은 PrimaryPart(Cube_1)가 격자 모서리에 있어서, PrimaryPart
-- 기준으로 단순히 PivotTo(CFrame.new(targetPosition))을 하면 블록이 모서리만큼 밀려나
-- BlockService의 레이아웃 좌표(블록 "중심" 기준)와 어긋난다. 그래서 실제 바운딩박스
-- 중심을 기준으로 델타를 계산해서 옮긴다.
local function moveModelCenterTo(model: Model, targetPosition: Vector3)
	local currentCenter = model:GetBoundingBox().Position
	local delta = targetPosition - currentCenter
	model:PivotTo(model:GetPivot() + delta)
end

-- ⚠️ 개발용 미리보기 함수. 게임 런타임에 호출되지 않는다. count/재질 조합으로 실제 배치
-- 좌표(BlockService._pure.computeLayout)를 Workspace에 눈으로 확인하기 위한 것 —
-- 블록 크기·간격을 정할 때 커맨드 바에서 여러 번 호출해보고 끝나면 지우고 쓴다.
--
-- yOffset: 블록 "중심"을 지면(Y=0) 기준 얼마나 띄울지. BlockService의 레이아웃 좌표는
-- 전부 Y=0(수평면)이라, 오프셋 없이 그대로 쓰면 블록 절반이 바닥 밑에 묻힌다.
-- 생략하면 기본 격자(4x4x4) × cubeSize 기준으로 블록 바닥이 Y=0에 오도록 자동 계산한다.
function BlockModelGenerator.previewLayout(count: number, materialName: string, cubeSize: number?, yOffset: number?): Folder
	assert(type(count) == "number" and count >= 1 and count <= 16 and count == math.floor(count), "count는 1~16 사이의 정수여야 함")
	assert(MATERIAL_PRESETS[materialName] ~= nil, "알 수 없는 재질 프리셋: " .. tostring(materialName))

	local positions = BlockService._pure.computeLayout(count)

	-- 기존 미리보기가 있으면 지우고 새로 만든다.
	local existing = Workspace:FindFirstChild(PREVIEW_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_FOLDER_NAME
	folder.Parent = Workspace

	local resolvedCubeSize = cubeSize or BlockLayoutConfig.CUBE_SIZE
	local resolvedYOffset = yOffset or (BlockLayoutConfig.GRID_SIZE * resolvedCubeSize) / 2

	local template = getOrCreateTemplate(materialName, cubeSize)
	local isTemporaryTemplate = template.Parent == nil

	for i, position in ipairs(positions) do
		local clone = template:Clone()
		clone.Name = string.format("Preview_%d", i)
		moveModelCenterTo(clone, Vector3.new(position.X, position.Y + resolvedYOffset, position.Z))
		clone.Parent = folder
	end

	if isTemporaryTemplate then
		template:Destroy() -- ServerStorage에 없던 즉석 템플릿이면 정리
	end

	print(string.format(
		"[BlockModelGenerator] previewLayout(%d, %s) -> Workspace.%s에 %d개 배치",
		count,
		materialName,
		PREVIEW_FOLDER_NAME,
		count
	))

	return folder
end

return BlockModelGenerator

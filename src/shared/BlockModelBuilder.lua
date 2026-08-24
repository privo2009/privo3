--!strict
-- 블록 모델(4x4x4 큐브 격자)을 실제로 만드는 순수 생성 로직. 서버·클라 양쪽이 쓴다.
--
-- 왜 shared인가: 4-2-a2에서 블록 렌더링이 클라로 넘어갔다. 이제 모델을 만드는 쪽은
-- 각 클라(Net/RemoteReceiver)이고, 서버는 개발 도구(Tools/BlockModelGenerator)에서만
-- 쓴다. 두 곳이 같은 격자·같은 GridIndex를 만들어야 ChunkBreaker가 올바른 큐브를 찾는다.
--
-- 여기 없는 것: generateAndSave / generateAllPresets / previewLayout은 Studio 커맨드 바
-- 전용 개발 도구라 Tools/BlockModelGenerator에 남아 있다. previewLayout이 BlockService를
-- 쓰기 때문이기도 하다 — 그것까지 옮기면 shared가 server를 require하게 되어 의존 방향이
-- 거꾸로 뒤집힌다.
--
-- Phase 3-4: 격자 크기는 4x4x4(64개/블록)로 확정 — 근거: 파편 동시 상한 200개(CLAUDE.md)
-- 안에서 블록 3개가 동시에 완전파괴돼도(3×64=192) 풀 한계를 안 넘는 선. 5x5x5(125개)는
-- 블록 2개만 동시파괴돼도 넘는다.
-- ⚠️ 실제 격자/큐브 크기 값은 여기 하드코딩하지 않는다. Shared/Config/BlockLayoutConfig.lua
-- 가 유일한 출처다 — BlockLayout의 배치 반지름도 같은 Config에서 파생되므로, 크기를
-- 바꾸려면 이 파일이 아니라 그쪽을 고쳐야 두 모듈이 계속 맞물린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)

export type MaterialPreset = {
	name: string,
	color: Color3,
	material: Enum.Material,
}

local BlockModelBuilder = {}

-- ===== 템플릿 보관 위치 ================================================================
--
-- ReplicatedStorage.BlockModels. 예전에는 ServerStorage였는데 클라가 볼 수 없어서 옮겼다.
--
-- 이 폴더는 **디자인 담당이 나중에 실제 블록 모델을 넣을 자리**다. 지금은 비어 있고
-- (지환은 아직 모델을 넣지 않았고 임시 프리셋만 돌고 있다) 그래서 이전 작업이 없었다.
-- 넣어둔 모델이 있으면 getOrCreateTemplate이 그것을 그대로 쓴다 — 이 경로가 살아 있는
-- 것이 이 함수의 존재 이유다. 즉석 생성본은 모델이 없을 때의 대체물일 뿐이다.
--
-- ⚠️ 복제 비용: ReplicatedStorage에 있으면 템플릿이 전원에게 복제된다.
--    재질 6종 × 64큐브 = 384파트. **접속자 수와 무관한 고정값**이라 감당 가능하다고 봤다.
--    비교 대상은 예전 방식이다 — 서버가 플레이어마다 블록을 만들면 30명 × 7블록 × 64큐브
--    = 13,440파트가 서버에 서고 그게 전부 복제됐다. 384는 그 2.9%이고 접속자가 늘어도
--    안 늘어난다. 반대로 템플릿을 클라가 매번 생성하면 층 전환마다 64파트 생성이 반복된다.
local TEMPLATE_FOLDER_NAME = "BlockModels"

BlockModelBuilder.TEMPLATE_FOLDER_NAME = TEMPLATE_FOLDER_NAME

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

BlockModelBuilder.MATERIAL_PRESETS = MATERIAL_PRESETS

export type GenerateOptions = {
	gridSize: number, -- 한 변당 큐브 개수. 4면 4x4x4=64개.
	cubeSize: number?, -- 큐브 한 변 길이(studs). 기본 BlockLayoutConfig.CUBE_SIZE.
	materialPreset: string?, -- MATERIAL_PRESETS 키. 기본 "wood".
	canCollide: boolean?, -- 기본 true.
	modelName: string?,
}

-- 격자 좌표(x,y,z, 0부터 시작) -> 1부터 시작하는 순차 인덱스.
-- BlockShuffle.computeDestructionOrder(seed, count)가 반환하는 순열이 가리키는 인덱스가
-- 바로 이 GridIndex와 대응된다 — 클라가 그 순서대로 GridIndex를 찾아 큐브를 지운다.
local function gridIndex(x: number, y: number, z: number, gridSize: number): number
	return x * gridSize * gridSize + y * gridSize + z + 1
end

BlockModelBuilder.gridIndex = gridIndex

-- 정육면체 격자를 큐브로 채운 Model을 만든다. Parent는 아직 안 붙인다.
function BlockModelBuilder.generate(options: GenerateOptions): Model
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

-- materialName에 해당하는 블록 템플릿을 구한다. ReplicatedStorage.BlockModels에 이미
-- 저장된 게 있으면 그걸 쓰고(디자인 담당이 손댄 버전이 그대로 게임에 반영된다), 없으면
-- 즉석에서 하나 만든다 (폴더에 저장하지 않음 — 부르는 쪽이 수명을 관리한다).
function BlockModelBuilder.getOrCreateTemplate(materialName: string, cubeSize: number?): Model
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER_NAME)
	if folder ~= nil then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("MaterialPreset") == materialName then
				return child :: Model
			end
		end
	end

	return BlockModelBuilder.generate({
		gridSize = BlockLayoutConfig.GRID_SIZE,
		materialPreset = materialName,
		cubeSize = cubeSize,
	})
end

-- model을 강체 이동시켜 "모델 전체의 기하학적 중심"이 targetPosition에 오도록 한다.
-- generate()가 만드는 모델은 PrimaryPart(Cube_1)가 격자 모서리에 있어서, PrimaryPart
-- 기준으로 단순히 PivotTo(CFrame.new(targetPosition))을 하면 블록이 모서리만큼 밀려나
-- 레이아웃 좌표(블록 "중심" 기준)와 어긋난다. 그래서 실제 바운딩박스 중심을 기준으로
-- 델타를 계산해서 옮긴다.
function BlockModelBuilder.moveModelCenterTo(model: Model, targetPosition: Vector3)
	local currentCenter = model:GetBoundingBox().Position
	local delta = targetPosition - currentCenter
	model:PivotTo(model:GetPivot() + delta)
end

return BlockModelBuilder

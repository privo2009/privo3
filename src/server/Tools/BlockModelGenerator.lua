--!strict
-- ⚠️ 전부 개발 도구다. Studio 커맨드 바 전용이며 게임 런타임에 실행되지 않는다.
--
-- 생성 로직 자체는 여기 없다 — Shared/BlockModelBuilder.lua에 있다. 4-2-a2에서 블록
-- 렌더링이 클라로 넘어가면서, 클라도 같은 격자를 만들어야 해서 순수 생성부만 shared로
-- 나갔다. 이 파일에는 그 위에 얹힌 개발 편의 기능만 남는다.
--
-- 왜 이 세 개는 server에 남는가: previewLayout이 BlockService(server/Systems)를 쓴다.
-- 모듈을 통째로 shared로 옮기면 shared가 server를 require하게 되어 의존 방향이 거꾸로
-- 뒤집힌다. 커맨드 바 전용 도구이므로 server가 제자리다.
--
-- 사용 예 (커맨드 바):
--   local Gen = require(game.ServerScriptService.Server.Tools.BlockModelGenerator)
--   Gen.generateAndSave({ gridSize = 4, materialPreset = "wood" })
--   Gen.generateAllPresets(4) -- 재질 6종 전부 한 번에 생성
--   Gen.previewLayout(8, "stone") -- 8개 배치를 Workspace에서 눈으로 확인
--
-- generateAndSave가 만든 모델은 ReplicatedStorage.BlockModels 밑에 생긴다. 그것을 저장해
-- 두면(파일 → 저장, 혹은 원하는 위치로 드래그) 실제 게임에서 그대로 쓰인다 —
-- 클라의 getOrCreateTemplate이 그 폴더를 먼저 뒤진다. ServerStorage가 아닌 이유는
-- 클라가 ServerStorage를 볼 수 없기 때문이다 (BlockModelBuilder 상단 참고).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockService = require(script.Parent.Parent.Systems.BlockService)
local BlockLayout = require(ReplicatedStorage.Shared.BlockLayout)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local BlockModelBuilder = require(ReplicatedStorage.Shared.BlockModelBuilder)

export type MaterialPreset = BlockModelBuilder.MaterialPreset
export type GenerateOptions = BlockModelBuilder.GenerateOptions

local BlockModelGenerator = {}

-- 재정의하지 않는다. 정의는 BlockModelBuilder 한 곳이고 여기서는 다시 노출만 한다 —
-- 커맨드 바에서 Gen.MATERIAL_PRESETS로 재질 목록을 확인하던 습관을 깨지 않기 위해서다.
BlockModelGenerator.MATERIAL_PRESETS = BlockModelBuilder.MATERIAL_PRESETS
BlockModelGenerator.generate = BlockModelBuilder.generate
BlockModelGenerator.getOrCreateTemplate = BlockModelBuilder.getOrCreateTemplate
BlockModelGenerator.moveModelCenterTo = BlockModelBuilder.moveModelCenterTo

local TEMPLATE_FOLDER_NAME = BlockModelBuilder.TEMPLATE_FOLDER_NAME

-- previewLayout이 쓰는 Workspace 폴더 이름. 항상 이 폴더 하나만 유지한다.
local PREVIEW_FOLDER_NAME = "BlockLayoutPreview"

-- generate()로 만든 모델을 ReplicatedStorage.BlockModels 밑에 배치하고 반환한다.
function BlockModelGenerator.generateAndSave(options: GenerateOptions): Model
	local model = BlockModelBuilder.generate(options)

	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER_NAME) :: Folder?
	if folder == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = TEMPLATE_FOLDER_NAME
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end

	model.Parent = folder

	print(string.format(
		"[BlockModelGenerator] %s 생성 완료 (%d개 큐브) -> ReplicatedStorage.%s",
		model.Name,
		model:GetAttribute("CubeCount") :: number,
		TEMPLATE_FOLDER_NAME
	))

	return model
end

-- MATERIAL_PRESETS에 있는 재질 6종 전부를 같은 gridSize/cubeSize로 한 번에 생성한다.
function BlockModelGenerator.generateAllPresets(gridSize: number, cubeSize: number?, canCollide: boolean?): { Model }
	local models = {}
	for presetKey in pairs(BlockModelBuilder.MATERIAL_PRESETS) do
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

-- ⚠️ 개발용 미리보기 함수. 게임 런타임에 호출되지 않는다. count/재질 조합으로 실제 배치
-- 좌표(BlockLayout.computeLayout)를 Workspace에 눈으로 확인하기 위한 것 —
-- 블록 크기·간격을 정할 때 커맨드 바에서 여러 번 호출해보고 끝나면 지우고 쓴다.
--
-- BlockService를 거치지 않고 BlockLayout을 직접 부른다. 좌표 계산이 shared로 나갔으므로
-- 원본을 보는 것이 맞다 (BlockService._pure.computeLayout도 같은 함수를 가리킨다).
--
-- yOffset: 블록 "중심"을 지면(Y=0) 기준 얼마나 띄울지. 레이아웃 좌표는 전부 Y=0(수평면)이라
-- 오프셋 없이 그대로 쓰면 블록 절반이 바닥 밑에 묻힌다. 생략하면 클라 렌더링과 같은 값
-- (BlockLayout.GROUND_Y_OFFSET)을 쓴다 — cubeSize를 따로 준 경우만 그 값으로 다시 계산한다.
function BlockModelGenerator.previewLayout(count: number, materialName: string, cubeSize: number?, yOffset: number?): Folder
	assert(type(count) == "number" and count >= 1 and count <= 16 and count == math.floor(count), "count는 1~16 사이의 정수여야 함")
	assert(BlockModelBuilder.MATERIAL_PRESETS[materialName] ~= nil, "알 수 없는 재질 프리셋: " .. tostring(materialName))

	local positions = BlockLayout.computeLayout(count)

	-- 기존 미리보기가 있으면 지우고 새로 만든다.
	local existing = Workspace:FindFirstChild(PREVIEW_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_FOLDER_NAME
	folder.Parent = Workspace

	local resolvedYOffset: number
	if yOffset ~= nil then
		resolvedYOffset = yOffset
	elseif cubeSize ~= nil then
		resolvedYOffset = (BlockLayoutConfig.GRID_SIZE * cubeSize) / 2
	else
		resolvedYOffset = BlockLayout.GROUND_Y_OFFSET
	end

	local template = BlockModelBuilder.getOrCreateTemplate(materialName, cubeSize)
	local isTemporaryTemplate = template.Parent == nil

	for i, position in ipairs(positions) do
		local clone = template:Clone()
		clone.Name = string.format("Preview_%d", i)
		BlockModelBuilder.moveModelCenterTo(clone, Vector3.new(position.X, position.Y + resolvedYOffset, position.Z))
		clone.Parent = folder
	end

	if isTemporaryTemplate then
		template:Destroy() -- 폴더에 없던 즉석 템플릿이면 정리
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

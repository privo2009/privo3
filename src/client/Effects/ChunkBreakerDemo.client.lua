--!strict
-- ⚠️ Phase 3-2 임시 데모. 실제 서버 연동(RemoteEvent) 없이 클라 혼자서 ChunkBreaker를
-- 호출해 블록 하나가 HP 100% → 0%로 단계적으로 부서지는 과정을 Studio Play 상태에서 눈으로
-- 확인하기 위한 것. RemoteEvent가 붙어서 서버가 실제로 HP를 보내주는 단계가 되면 이 파일
-- 전체를 삭제할 것.

local DEMO_MODE = true

if not DEMO_MODE then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local ChunkBreaker = require(script.Parent.ChunkBreaker)

-- 데모 전용 큐브 그리드 생성. 실제 게임에서는 서버의 BlockModelGenerator.lua(개발 도구)가
-- 만든 모델을 저장해서 쓰는데, 이 데모는 서버 연동 없이 클라 단독 실행이 목적이라 여기서
-- 직접 만든다. GridIndex를 매기는 방식(x*gridSize² + y*gridSize + z + 1)은
-- BlockModelGenerator와 반드시 똑같이 맞춰야 ChunkBreaker가 올바른 큐브를 찾는다.
local function buildDemoBlockModel(): (Model, number)
	local gridSize = BlockLayoutConfig.GRID_SIZE
	local cubeSize = BlockLayoutConfig.CUBE_SIZE
	local totalCubes = gridSize ^ 3

	local model = Instance.new("Model")
	model.Name = "ChunkBreakerDemoBlock"

	local offset = (gridSize - 1) * cubeSize / 2
	local firstCube: BasePart? = nil

	for x = 0, gridSize - 1 do
		for y = 0, gridSize - 1 do
			for z = 0, gridSize - 1 do
				local gridIndex = x * gridSize * gridSize + y * gridSize + z + 1

				local cube = Instance.new("Part")
				cube.Name = string.format("Cube_%d", gridIndex)
				cube.Size = Vector3.new(cubeSize, cubeSize, cubeSize)
				cube.CFrame = CFrame.new(x * cubeSize - offset, y * cubeSize - offset, z * cubeSize - offset)
				cube.Anchored = true
				cube.CanCollide = true
				cube.Color = Color3.fromRGB(133, 94, 66) -- 임시 나무색 (디자인 담당 교체 자리)
				cube.Material = Enum.Material.Wood
				cube:SetAttribute("GridIndex", gridIndex)
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

	return model, totalCubes
end

local DEMO_POSITION = Vector3.new(0, 20, 0)
local DEMO_SEED = 12345
local MAX_HP = 100
local STEPS = 10
local STEP_INTERVAL_SEC = 1

local demoModel, totalCubes = buildDemoBlockModel()
demoModel:PivotTo(CFrame.new(DEMO_POSITION))
demoModel.Parent = Workspace

local breaker = ChunkBreaker.new(demoModel, totalCubes, DEMO_SEED)

task.spawn(function()
	print(string.format(
		"[ChunkBreakerDemo] 데모 블록 생성 (%d개 큐브, 위치 %s). %d초마다 HP %.0f%%씩 감소.",
		totalCubes,
		tostring(DEMO_POSITION),
		STEP_INTERVAL_SEC,
		100 / STEPS
	))

	for step = 1, STEPS do
		task.wait(STEP_INTERVAL_SEC)
		local hp = MAX_HP - (MAX_HP / STEPS) * step
		breaker:setHp(hp, MAX_HP)
		print(string.format("[ChunkBreakerDemo] step %d/%d: hp=%.1f/%d", step, STEPS, hp, MAX_HP))
	end

	print("[ChunkBreakerDemo] 완료 — HP 0, 큐브 전부 숨겨짐")
end)

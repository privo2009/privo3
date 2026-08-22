--!strict
-- ⚠️ Phase 3-2 임시 데모. 실제 서버 연동(RemoteEvent) 없이 클라 혼자서 ChunkBreaker를
-- 호출해 블록이 부서지는 과정을 Studio Play 상태에서 눈으로 확인하기 위한 것.
-- 서버 신호가 붙은 지금은 아래 DEMO_ENABLED로 꺼둔 상태다. 수신부와 대조할 일이 없어지면
-- 이 파일 전체를 삭제할 것.

-- 실제 서버 신호(Net/RemoteReceiver.client.lua)가 붙은 뒤로는 꺼둔다. 켜면 이 데모가
-- 자체 타이머로 만든 블록을 따로 부수므로, 수신부가 만든 연출과 화면에서 섞인다.
-- 수신부가 이상할 때 true로 바꿔서 "연출 자체는 멀쩡한가"를 대조하는 용도로 남겨둔다.
-- (원래 이 자리에 있던 DEMO_MODE 플래그를 이름만 바꾼 것이다. 같은 뜻의 플래그를 둘로
--  늘리면 어느 쪽이 진짜인지 헷갈린다)
local DEMO_ENABLED = false

if not DEMO_ENABLED then
	return
end

-- 데모 패턴 3종. 이 상수 하나만 바꿔서 전환한다 (Play 중에는 바꿔도 다음 실행부터 반영되니,
-- 바꾼 뒤 다시 Play해야 함 — 파일 상단 상수라 런타임 중 실시간 전환은 아님).
--   gradual : 1초마다 10%씩 (초반 느낌, 지금까지의 기본 동작)
--   oneshot : 3초 대기 후 100% -> 0% 한 번에 (중반 한 방 느낌)
--   instant : staggerDuration=0으로 만든 ChunkBreaker로 한 번에 (자동 진행 느낌)
local DEMO_PATTERN: "gradual" | "oneshot" | "instant" = "oneshot"

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

local GRADUAL_STEPS = 10
local GRADUAL_STEP_INTERVAL_SEC = 1
local ONESHOT_WAIT_SEC = 3
local RESET_DELAY_SEC = 3 -- 한 사이클 끝나고 다음 사이클 시작 전 대기 시간

local function runGradual(breaker: ChunkBreaker.ChunkBreakerHandle)
	print(string.format("[ChunkBreakerDemo] gradual: %d초마다 HP %.0f%%씩 감소", GRADUAL_STEP_INTERVAL_SEC, 100 / GRADUAL_STEPS))
	for step = 1, GRADUAL_STEPS do
		task.wait(GRADUAL_STEP_INTERVAL_SEC)
		local hp = MAX_HP - (MAX_HP / GRADUAL_STEPS) * step
		breaker:setHp(hp, MAX_HP)
		print(string.format("[ChunkBreakerDemo] gradual step %d/%d: hp=%.1f/%d", step, GRADUAL_STEPS, hp, MAX_HP))
	end
end

local function runOneshot(breaker: ChunkBreaker.ChunkBreakerHandle)
	print(string.format("[ChunkBreakerDemo] oneshot: %d초 대기 후 100%%->0%% 한 번에", ONESHOT_WAIT_SEC))
	task.wait(ONESHOT_WAIT_SEC)
	breaker:setHp(0, MAX_HP)
	print("[ChunkBreakerDemo] oneshot: 처리 완료")
end

local function runInstant(breaker: ChunkBreaker.ChunkBreakerHandle)
	print("[ChunkBreakerDemo] instant: staggerDuration=0, 한 번에 처리")
	breaker:setHp(0, MAX_HP)
	print("[ChunkBreakerDemo] instant: 처리 완료")
end

-- Play를 다시 누르지 않아도 되도록, 한 사이클(패턴 실행 -> 대기 -> 리셋)을 무한 반복한다.
task.spawn(function()
	while true do
		local demoModel, totalCubes = buildDemoBlockModel()
		demoModel:PivotTo(CFrame.new(DEMO_POSITION))
		demoModel.Parent = Workspace

		-- instant만 staggerDuration=0으로 만든다. gradual/oneshot은 기본값(ChunkBreaker의
		-- DEFAULT_STAGGER_DURATION_SEC)을 그대로 쓴다.
		local staggerOverride: number? = if DEMO_PATTERN == "instant" then 0 else nil
		local breaker = ChunkBreaker.new(demoModel, totalCubes, DEMO_SEED, staggerOverride)

		print(string.format("[ChunkBreakerDemo] === 새 사이클 시작 (pattern=%s, %d개 큐브) ===", DEMO_PATTERN, totalCubes))

		if DEMO_PATTERN == "gradual" then
			runGradual(breaker)
		elseif DEMO_PATTERN == "oneshot" then
			runOneshot(breaker)
		elseif DEMO_PATTERN == "instant" then
			runInstant(breaker)
		else
			warn("[ChunkBreakerDemo] 알 수 없는 DEMO_PATTERN: " .. tostring(DEMO_PATTERN))
		end

		print(string.format("[ChunkBreakerDemo] 사이클 종료 — %d초 뒤 블록 리셋", RESET_DELAY_SEC))
		task.wait(RESET_DELAY_SEC)

		demoModel:Destroy()
	end
end)

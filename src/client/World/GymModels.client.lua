--!strict
-- 운동기구 모델 자리 연결 (지시서 #42 — 얹는 규칙은 GymModelLogic). 틀은 서버 AssetLoader가 비동기로 늦게 불러 두므로
-- 기구 발판(Workspace.Gyms)과 틀 폴더(ReplicatedStorage.AssetTemplates)를 둘 다 지켜본다 — 들어오는 순서와 상관없다.
-- 지금은 모델 ID가 전부 nil이라 아무것도 얹지 않는다(임시 발판 그대로).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local GymModelLogic = require(script.Parent.GymModelLogic)

local gymFolder: Instance? = nil

local function attachAll()
	if gymFolder == nil then
		return
	end
	for _, part in ipairs((gymFolder :: Instance):GetChildren()) do
		GymModelLogic.attach(part)
	end
end

task.spawn(function()
	local folder = Workspace:WaitForChild("Gyms")
	gymFolder = folder
	folder.ChildAdded:Connect(function(part: Instance)
		GymModelLogic.attach(part)
	end)
	attachAll()
end)

task.spawn(function()
	local templates = ReplicatedStorage:WaitForChild(AssetSlots.FOLDER)
	templates.ChildAdded:Connect(function(child: Instance)
		if string.sub(child.Name, 1, 4) == "gym_" then
			attachAll()
		end
	end)
	attachAll()
end)

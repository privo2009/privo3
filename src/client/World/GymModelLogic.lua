--!strict
-- 운동기구 모델 얹기 (지시서 #42 — AssetSlots "gym_<번호>" 13칸 · 값 원본 GymConfig.VISUALS · 주문 docs/ASSET_ORDER.md).
-- 서버 AssetLoader가 불러 둔 틀(ReplicatedStorage.AssetTemplates.gym_<번호> — Model)이 있으면 그 기구 발판 위에 복제해 얹는다.
-- 없으면 아무것도 안 한다 — 지금 임시 발판(GymService가 만든 Part) 그대로("값이 없으면 지금 모양" — DESIGN 16장 에셋 교체 방식).
-- 모델은 보이기만 한다: 판정 · 색(LobbyRenderer) · 프롬프트(GymPrompts) · 안내(WorldLabels)는 전부 발판 Part와 GymLayout 좌표 그대로.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)

local GymModelLogic = {}

GymModelLogic.MODEL_NAME = "GymModel"

-- 발판 하나에 모델을 얹는다. 얹었으면 그 모델, 아니면 nil(틀 없음 · 이미 있음 · 기구 발판 아님).
-- findTemplate: 테스트가 가짜 틀을 넘긴다(기본 AssetSlots.template).
function GymModelLogic.attach(part: Instance, findTemplate: ((string) -> Instance?)?): Model?
	if not part:IsA("BasePart") then
		return nil
	end
	local index = part:GetAttribute("GymIndex")
	if type(index) ~= "number" or part:FindFirstChild(GymModelLogic.MODEL_NAME) ~= nil then
		return nil
	end
	local find = findTemplate or function(key: string): Instance?
		return AssetSlots.template(key)
	end
	local tpl = find(AssetSlots.gymKey(index))
	if tpl == nil or not tpl:IsA("Model") then
		return nil
	end
	local m = (tpl :: Model):Clone()
	m.Name = GymModelLogic.MODEL_NAME
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	-- 경계 상자 가운데를 발판 위 자리에 맞춘다(모델 기준점이 어디든 같은 자리)
	local box, size = m:GetBoundingBox()
	local pivotFromBox = box:ToObjectSpace(m:GetPivot())
	m:PivotTo(GymLayout.modelCenter((part :: BasePart).Position, size.Y) * pivotFromBox)
	m.Parent = part
	return m
end

return GymModelLogic

--!strict
-- 글자 높이 하한 적용 (Phase 6 지시서 #6). ScreenGui 아래 모든 UITextSizeConstraint에
-- MinTextSize = TextScale.MIN_TEXT_PX를 건다(이미 있는 것 + 나중에 생기는 것).
-- 근거와 값은 Shared/Config/TextScale.MIN_TEXT_PX 주석이 원본이다.
--
-- 화면 코드마다 따로 넣지 않고 ScreenGui 단위로 한 번에 건다 — 화면이 늘어도 빠지는 곳이 없다.
-- MaxTextSize가 하한보다 작은 제약은 없지만(가장 작은 단계 극소 22), 있으면 MaxTextSize로 맞춘다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)

local TextMinimum = {}

local function applyOne(obj: Instance)
	if obj:IsA("UITextSizeConstraint") then
		local c = obj :: UITextSizeConstraint
		local target = math.min(TextScale.MIN_TEXT_PX, c.MaxTextSize)
		if c.MinTextSize < target then
			c.MinTextSize = target
		end
	end
end

function TextMinimum.attach(gui: Instance)
	for _, obj in ipairs(gui:GetDescendants()) do
		applyOne(obj)
	end
	gui.DescendantAdded:Connect(applyOne)
end

return TextMinimum

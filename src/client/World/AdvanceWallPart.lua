--!strict
-- 진행 벽 파트 하나에 AdvanceWallView의 계산 결과를 꽂는다. 3c 커밋 2.
--
-- 판정은 서버(ChallengeService.advance), 모습 계산은 Shared/AdvanceWallView다.
-- 이 모듈은 그 결과를 파트 속성으로 옮기기만 한다 — 여기서 상태를 보고 분기하지 말 것.
--
-- ⚠️ 위치를 여기서 계산하지 않는다. view.x/y/z는 ArenaConfig.getAdvanceWallCenter에서 왔고,
-- 서버 트리거(AdvanceWallService)도 같은 함수를 쓴다. 보이는 벽과 판정하는 벽이 한 자리다.
-- ⚠️ 색은 view.colorRole → UiTheme.Colors[역할].base다. hex를 여기 적지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdvanceWallView = require(ReplicatedStorage.Shared.AdvanceWallView)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)

local AdvanceWallPart = {}

local PART_NAME = "AdvanceWall"

-- 벽 파트를 만든다(부모는 붙이지 않는다). 렌더러가 한 번만 부르고 계속 재사용한다 —
-- 이벤트마다 만들면 반복 루프의 Instance.new다 (CLAUDE.md 금지 사항).
--   Anchored = true  물리 시뮬레이션 금지 (절대 규칙 4)
--   CanTouch = false 클라 쪽 Touched는 쓰지 않는다. 진행 판정은 서버 트리거 몫이다
function AdvanceWallPart.create(): Part
	local part = Instance.new("Part")
	part.Name = PART_NAME
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	AdvanceWallPart.applyView(part, AdvanceWallView.compute(nil))
	return part
end

-- view를 파트에 그대로 적용한다.
--
-- ⚠️ x가 nil이면(stage 없음·잘못됨) 위치는 그대로 둔다. 그때 view는 보이지 않음 값
-- (투명 1 · 충돌 X)이라 옛 자리에 남아도 안 보이고 안 막는다.
-- size도 그때는 nil이라 크기 역시 그대로 둔다.
function AdvanceWallPart.applyView(part: BasePart, view: AdvanceWallView.View)
	part.Transparency = view.transparency
	part.CanCollide = view.canCollide
	part.Color = UiTheme.Colors[view.colorRole].base

	if view.size ~= nil then
		part.Size = view.size
	end

	if view.x ~= nil and view.y ~= nil and view.z ~= nil then
		part.Position = Vector3.new(view.x, view.y, view.z)
	end
end

return AdvanceWallPart

--!strict
-- 빛 띠(Shine) 순수 계산 (지시서 #21 B — docs/UI.md "UI 효과"). 화면은 Components/Shine.
--
--   keypoints(half, peak)   UIGradient.Transparency 키포인트 — 0 · 0.5 − half · 0.5 · 0.5 + half · 1. 가장자리 1, 가운데 peak.
--                           시간 0 ~ 1 안 · 오름차순 · 첫 0 · 끝 1(NumberSequence 조건)
--   offsetAt(t)             지나가기 시작한 뒤 t초의 Offset.X(−1 → 1). 지나가는 동안만 값이 있고 밖이면 −1(띠가 대상 밖)
--   isVisible(node, ...)    대상과 조상이 전부 보이는가(Visible · ScreenGui.Enabled). 노드 접근은 함수로 받아 테스트가 가짜 나무를 쓴다
--   pickActive(entries, n)  보이는 것 중 우선순위 높은 순 · 붙인 순으로 n개(한 화면 상한 — 남용 방지)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)

local ShineLogic = {}

export type Keypoint = { time: number, value: number }

function ShineLogic.keypoints(half: number, peak: number): { Keypoint }
	local h = math.clamp(half, 1e-3, 0.5 - 1e-3)
	local p = math.clamp(peak, 0, 1)
	return {
		{ time = 0, value = 1 },
		{ time = 0.5 - h, value = 1 },
		{ time = 0.5, value = p },
		{ time = 0.5 + h, value = 1 },
		{ time = 1, value = 1 },
	}
end

-- ease(alpha) = TweenService:GetValue(alpha, 스타일, 방향). 테스트는 직선 ease를 넘길 수 있다.
function ShineLogic.offsetAt(t: number, ease: (number) -> number): number
	local sweep = UIFxConfig.SHINE_SWEEP_TIME
	if t < 0 or t > sweep then
		return -1
	end
	return -1 + 2 * ease(t / sweep)
end

export type NodeAccess = {
	parentOf: (any) -> any?,
	isGui: (any) -> boolean, -- GuiObject인가(Visible을 본다)
	visibleOf: (any) -> boolean,
	isScreenGui: (any) -> boolean,
	enabledOf: (any) -> boolean,
	isRoot: (any) -> boolean, -- PlayerGui 등 — 여기까지 오면 보인다
}

-- 대상부터 위로 올라가며 하나라도 숨어 있으면 false. ScreenGui에 닿지 못하고 나무가 끊기면(붙지 않음) false.
function ShineLogic.isVisible(node: any, access: NodeAccess): boolean
	local cur = node
	while cur ~= nil do
		if access.isGui(cur) and not access.visibleOf(cur) then
			return false
		end
		if access.isScreenGui(cur) then
			return access.enabledOf(cur)
		end
		if access.isRoot(cur) then
			return true
		end
		cur = access.parentOf(cur)
	end
	return false
end

export type Entry = { visible: boolean, priority: number, order: number }

-- 돌릴 것의 순번 목록(입력 배열의 인덱스). 보이는 것 중 우선순위 높은 순 · 같으면 붙인 순(order 작은 것)으로 limit개.
function ShineLogic.pickActive(entries: { Entry }, limit: number): { number }
	local idx: { number } = {}
	for i, e in ipairs(entries) do
		if e.visible then
			table.insert(idx, i)
		end
	end
	table.sort(idx, function(a, b)
		local ea, eb = entries[a], entries[b]
		if ea.priority ~= eb.priority then
			return ea.priority > eb.priority
		end
		return ea.order < eb.order
	end)
	local out: { number } = {}
	for i = 1, math.min(limit, #idx) do
		out[i] = idx[i]
	end
	return out
end

-- 프리셋 → 색. 모르는 이름은 기본(흰색). 보라(진행 전용)는 어떤 프리셋에도 없다.
function ShineLogic.colorOf(preset: string?): Color3
	if preset == "premium" then
		return UIFxConfig.SHINE_COLOR_PREMIUM
	end
	return UIFxConfig.SHINE_COLOR_DEFAULT
end

return ShineLogic

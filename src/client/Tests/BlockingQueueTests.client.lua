--!strict
-- 차단층 범용 큐 · 결과 모달 검증 (지시서 #11 5단계 A6): 한 번에 하나 · 닫으면 다음 · 우선순위(작을수록 먼저) ·
-- 보이는 것을 가로채지 않음 · 같은 우선순위는 들어온 순서 · 모달 표시 · 차단층.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local BlockingQueueLogic = require(script.Parent.Parent.UI.Logic.BlockingQueueLogic)
local ResultModal = require(script.Parent.Parent.UI.Screens.Overlay.ResultModal)
local OverlayParts = require(script.Parent.Parent.UI.Screens.Overlay.OverlayParts)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local PR = BlockingQueueLogic.PRIORITY

do
	check("우선순위: 로딩 < 첫 접속 < 일일 보상 < 뽑기 결과 (UI.md)", PR.loading < PR.firstJoin and PR.firstJoin < PR.dailyReward and PR.dailyReward < PR.rollResult)
	local q = BlockingQueueLogic.new() :: BlockingQueueLogic.Queue<string>
	check("빈 큐: 보이는 것 없음", q.current() == nil and q.size() == 0)
	check("첫 항목은 바로 보인다", q.push(PR.rollResult, "a1") == true and q.current() == "a1")
	check("두 번째는 기다린다(한 번에 하나)", q.push(PR.rollResult, "a2") == false and q.current() == "a1" and q.size() == 2)
	q.push(PR.dailyReward, "daily")
	check("더 높은 우선순위도 지금 것을 가로채지 않는다", q.current() == "a1")
	check("닫으면 우선순위 높은 것이 먼저", q.dismiss() == "daily")
	check("그다음 같은 우선순위는 들어온 순서", q.dismiss() == "a2")
	check("다 닫으면 빈다", q.dismiss() == nil and q.size() == 0)
	q.push(PR.rollResult, "b1")
	q.push(PR.rollResult, "b2")
	q.push(PR.rollResult, "b3")
	q.dismiss()
	check("같은 우선순위 셋: 순서 그대로", q.current() == "b2" and q.dismiss() == "b3")
end

do
	local m = ResultModal.create()
	local confirmed = 0
	m.onConfirm(function()
		confirmed += 1
	end)
	check("모달: 처음엔 숨김(틀만 보인다)", not m._debug.panel.Visible and m.root.BackgroundTransparency == 1)
	m.show({ heading = "새 아우라!", name = "오로라", rarityTier = 5, detail = "전설" })
	check("모달: 보이면 내용 · 희귀도 색", m._debug.panel.Visible and m._debug.name.Text == "오로라" and m._debug.name.TextColor3 == UiTheme.rarityColor(5))
	check("모달: 차단층", m.root.ZIndex == OverlayParts.Z.blocking and m._debug.panel.ZIndex > OverlayParts.Z.blocking)
	m.hide()
	check("모달: 닫으면 숨김", not m._debug.panel.Visible)
	check("모달: 크기 Scale만", m._debug.panel.Size.X.Offset == 0 and m._debug.panel.Size.Y.Offset == 0)
	m.root:Destroy()
end

print(string.format("[BlockingQueueTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BlockingQueueTests] %d test(s) failed", failed))
end

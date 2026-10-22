--!strict
-- 월드·워프 창 검증 (Phase 6 지시서 #6): 표시 값(WarpConfig 원본) · 잠김(블럭스 부족 · 런 중 W1) · 사유 문구 ·
-- 확인 단계 없이는 요청이 안 나감 · 쪽 넘김 · 창 규격. 실물 싱글톤이 아니라 Store.new()로 굴린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Store = require(script.Parent.Parent.UI.Store)
local WarpWindowLogic = require(script.Parent.Parent.UI.Logic.WarpWindowLogic)
local WarpWindow = require(script.Parent.Parent.UI.Screens.Window.WarpWindow)

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

local LAST = WarpWindowLogic.lastStage()

-- 1. 표시 값 ---------------------------------------------------------------------------------
do
	local blox = WarpConfig.cost(3) -- 3층까지 딱 살 수 있다
	local r3 = WarpWindowLogic.row(3, blox, false)
	check("값: 비용은 WarpConfig.cost 원본", BigNum.eq(r3.cost, WarpConfig.cost(3)))
	check("값: 비용만큼 있으면 갈 수 있다", r3.canWarp and r3.reason == nil)
	local r4 = WarpWindowLogic.row(4, blox, false)
	check("값: 모자라면 insufficient_blox", not r4.canWarp and r4.reason == WarpConfig.REASON_INSUFFICIENT_BLOX)
	local running = WarpWindowLogic.row(1, BigNum.new(1, 100), true)
	check("W1: 런 중이면 블럭스가 많아도 run_active", not running.canWarp and running.reason == WarpWindowLogic.REASON_RUN_ACTIVE)
	check("값: 기본 선택은 갈 수 있는 가장 높은 층", WarpWindowLogic.defaultStage(blox) == 3)
	check("값: 아무 데도 못 가면 1층", WarpWindowLogic.defaultStage(BigNum.new(0, 0)) == 1)
	check("쪽: 쪽 수 = 층 수 / 쪽 크기 올림", WarpWindowLogic.pageCount() == math.ceil(LAST / WarpWindowLogic.PAGE_SIZE))
	check("쪽: 마지막 쪽 행 수", #WarpWindowLogic.rows(WarpWindowLogic.pageCount(), blox, false) == LAST - (WarpWindowLogic.pageCount() - 1) * WarpWindowLogic.PAGE_SIZE)
	check("쪽: 층 → 쪽", WarpWindowLogic.pageOf(1) == 1 and WarpWindowLogic.pageOf(WarpWindowLogic.PAGE_SIZE + 1) == 2)
end

-- 2. 사유 문구 ---------------------------------------------------------------------------------
do
	local generic = WarpWindowLogic.reasonText("???")
	check("문구: 런 중", WarpWindowLogic.reasonText("run_active") ~= generic)
	check("문구: 블럭스 부족", WarpWindowLogic.reasonText(WarpConfig.REASON_INSUFFICIENT_BLOX) ~= generic)
	check("문구: 캐릭터 없음", WarpWindowLogic.reasonText("no_character") ~= generic)
	check("문구: 차감 뒤 사고는 '문제 발생'", WarpWindowLogic.reasonText("start_run_failed") ~= generic)
end

-- 3. 창 --------------------------------------------------------------------------------------
local function makeWindow(bloxValue: BigNum.BigNumber)
	local store = Store.new()
	store.setSource(function(setter)
		setter("blox", bloxValue)
	end)
	local clock = 0
	local w = { sends = {} :: { number }, closes = 0 }
	local handle = WarpWindow.create({
		store = store,
		sendRequest = function(stage: number)
			table.insert(w.sends, stage)
		end,
		onClose = function()
			w.closes += 1
		end,
		now = function()
			return clock
		end,
	})
	local function advance(sec: number)
		clock += sec
	end
	return handle, w, advance
end

do
	local handle, w, advance = makeWindow(WarpConfig.cost(3))
	check("창: 작은 창 60% × 70%", math.abs(handle.root.Size.X.Scale - 0.6) < 1e-6 and math.abs(handle.root.Size.Y.Scale - 0.7) < 1e-6)
	check("창: 월드 표시", handle._debug.labels.world.Text == WarpWindow.WORLD_TEXT)
	check("창: 처음 선택은 3층", handle._debug.state().selected == 3)
	check("창: 3층 행에 비용", string.find(handle._debug.rowLabels[3].Text, Formatter.format(WarpConfig.cost(3)), 1, true) ~= nil, handle._debug.rowLabels[3].Text)
	check("창: 선택 행은 보라", handle._debug.rowLabels[3].BackgroundColor3 == UiTheme.Colors.advance.base)
	check("창: 갈 수 있는 행은 중립 밝음 — 패널 바탕(중립 기본)과 구분된다", handle._debug.rowLabels[1].BackgroundColor3 == UiTheme.Colors.neutral.light
		and handle._debug.rowLabels[1].BackgroundColor3 ~= UiTheme.Colors.neutral.base)
	check("창: 못 가는 행은 중립 어두움", handle._debug.rowLabels[4].BackgroundColor3 == UiTheme.Colors.neutral.dark)
	check("창: 워프 버튼 켜짐", not handle._debug.button.isDisabled())

	handle._debug.press()
	check("창: 한 번 누름으로는 요청이 나가지 않는다", #w.sends == 0)
	check("창: 확인 중 문구 + 취소 버튼", handle._debug.labels.button.Text == WarpWindow.CONFIRM_TEXT and handle._debug.cancelButton.root.Visible)
	advance(1)
	handle._debug.press()
	check("창: 두 번째 누름에 선택 층으로 요청 1회", #w.sends == 1 and w.sends[1] == 3)

	handle._debug.press()
	handle._debug.select(2)
	advance(0.5)
	handle._debug.press()
	check("창: 확인 중 층을 바꾸면 처음부터 다시 확인", #w.sends == 1)

	handle._debug.select(4)
	check("잠김: 모자란 층은 버튼 회색", handle._debug.button.isDisabled())
	check("잠김: 이유 문구", handle._debug.labels.status.Text == WarpWindowLogic.reasonText(WarpConfig.REASON_INSUFFICIENT_BLOX))
	handle._debug.press()
	advance(0.5)
	handle._debug.press()
	check("잠김: 두 번 눌러도 요청이 안 나간다", #w.sends == 1)

	handle._debug.select(3)
	handle.setRunActive(true)
	check("W1: 런 중이면 잠김 + 이유", handle._debug.button.isDisabled()
		and handle._debug.labels.status.Text == WarpWindowLogic.reasonText(WarpWindowLogic.REASON_RUN_ACTIVE))
	handle._debug.press()
	advance(0.5)
	handle._debug.press()
	check("W1: 런 중에는 두 번 눌러도 요청이 안 나간다", #w.sends == 1)
	handle.setRunActive(false)
	check("W1: 런이 끝나면 다시 켜진다", not handle._debug.button.isDisabled())

	handle._debug.nextPage()
	check("쪽: 다음 쪽", handle._debug.state().page == 2)
	handle._debug.prevPage()
	handle._debug.prevPage()
	check("쪽: 1쪽 밑으로 안 내려간다", handle._debug.state().page == 1)

	handle.onResult({ ok = true, reason = "", stage = 3, cost = WarpConfig.cost(3) })
	check("결과: 성공 문구", handle._debug.labels.status.Text == string.format(WarpWindow.SUCCESS_TEXT, 3, Formatter.format(WarpConfig.cost(3))))
	handle.onResult({ ok = false, reason = "run_active", stage = 3, cost = { m = 0, e = 0 } })
	check("결과: 거부 사유 문구", handle._debug.labels.status.Text == WarpWindowLogic.reasonText("run_active"))

	handle._debug.close()
	check("창: X는 onClose를 부른다", w.closes == 1)
	handle.root:Destroy()
end

print(string.format("[WarpWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[WarpWindowTests] %d test(s) failed", failed))
end

--!strict
-- 화면 연출 검증 (지시서 #25 U1 ~ U7 — docs/UI.md "UI 효과 > 화면 연출"). 수치는 Shared/Config/UIFxConfig에서 읽는다(여기 다시 적지 않는다).
--   순수 계산(FxLogic): 구간 표본 · 사양 · log10 보간(0 · 같은 값 · 줄어듦 · 아주 큰 지수) · 튀기 · 스로틀 · 가운데 기준 · 크래프팅 순서
--   구동기(Fx): 가짜 시계로 표본 · 끝값 · onDone · 교체 · finish · cancel · 연출 줄이기 · 멈춤값 · 트윈 정리(루프 끊김) · UIScale 하나 규칙
--   연결: 창 열기 · 닫기(단일 오픈 · 닫는 중 다른 창 · 같은 창 다시) · 결과 모달(영웅 이상 · 빛 띠 1회) · 블럭스 올라가기 · 레벨 · 환생 배수 ·
--         크래프팅(결과 · PlayerState 어느 쪽이 먼저 와도) · 연출 줄이기(버튼 반응 · 빛 띠)
-- 실제 요청을 보내지 않는다. 가짜 GUI는 끝나면 지운다. 시계 · 설정은 끝나면 되돌린다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local UI = script.Parent.Parent.UI
local FxLogic = require(UI.Logic.FxLogic)
local Fx = require(UI.Components.Fx)
local FxPrefs = require(UI.FxPrefs)
local Shine = require(UI.Components.Shine)
local ButtonFx = require(UI.Components.ButtonFx)
local ScreenController = require(UI.ScreenController)
local ResultModal = require(UI.Screens.Overlay.ResultModal)
local BloxDisplay = require(UI.Screens.Hud.BloxDisplay)
local PowerBlock = require(UI.Screens.Hud.PowerBlock)
local PetWindow = require(UI.Screens.Window.PetWindow)
local Store = require(UI.Store)

type BigNumber = BigNum.BigNumber

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

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local function ease(a: number, s: Enum.EasingStyle, d: Enum.EasingDirection): number
	return TweenService:GetValue(a, s, d)
end

local B = BigNum.new
local savedReduce, savedSfx = FxPrefs.reduceMotion(), FxPrefs.sfxEnabled()

-- 가짜 시계(Fx 구동기). 실물 Heartbeat도 같은 시계를 읽는다 — 아래 UiFxTests를 기다린 뒤부터 테스트 동안만
local T = 1000

-- 테스트 GUI 틀
local gui = Instance.new("ScreenGui")
gui.Name = "FxTestsGui"
gui.ResetOnSpawn = false
gui.AutoLocalize = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- 1. 설정 ------------------------------------------------------------------------------------------------
check("UIFxConfig.validate · 스크린샷 멈춤 DEBUG_FREEZE_PROGRESS nil(커밋 값)", UIFxConfig.validate() and UIFxConfig.DEBUG_FREEZE_PROGRESS == nil)

-- 2. 구간 표본 ----------------------------------------------------------------------------------------------
do
	local spec = FxLogic.popSpec(1.2, 0.2)
	local v0, d0 = FxLogic.sample(spec.from, spec.segments, 0, ease)
	local vp = FxLogic.sample(spec.from, spec.segments, 0.2 * UIFxConfig.POP_PEAK_AT, ease)
	local v1, d1 = FxLogic.sample(spec.from, spec.segments, 0.2 + 0.01, ease)
	check("튀기: 시작 1 · 꼭대기 시점에 peak · 끝 정확히 1(끝남)", near(v0, 1) and not d0 and near(vp, 1.2, 1e-4) and v1 == 1 and d1)
	check("총 시간 · 진행률 → 시각 · 끝값", near(FxLogic.totalTime(spec.segments), 0.2) and near(FxLogic.timeAtProgress(spec.segments, 0.5), 0.1)
		and FxLogic.finalValue(spec) == 1 and FxLogic.finalValue({ from = 3, segments = {} }) == 3)
	local mid = FxLogic.sample(0, FxLogic.progressSpec(1).segments, 0.5, ease)
	check("진행률 사양(직선): 반 시간 = 0.5", near(mid, 0.5))
end

-- 3. 사양 = Config ------------------------------------------------------------------------------------------
do
	local open = FxLogic.windowOpenSpec()
	local close = FxLogic.windowCloseSpec(1)
	check("창 열기: WINDOW_OPEN_SCALE_FROM → 1 · WINDOW_OPEN_TIME · Back Out", open.from == UIFxConfig.WINDOW_OPEN_SCALE_FROM
		and open.segments[1].to == 1 and open.segments[1].time == UIFxConfig.WINDOW_OPEN_TIME and open.segments[1].style == Enum.EasingStyle.Back)
	check("창 닫기: 지금 크기 → WINDOW_CLOSE_SCALE_TO · WINDOW_CLOSE_TIME · Quad In", close.from == 1 and close.segments[1].to == UIFxConfig.WINDOW_CLOSE_SCALE_TO
		and close.segments[1].time == UIFxConfig.WINDOW_CLOSE_TIME and close.segments[1].direction == Enum.EasingDirection.In)
	local dimIn, dimOut = FxLogic.dimSpec(1, true, 0.5), FxLogic.dimSpec(0.5, false, 0.5)
	check("막: 보이기 1 → 원래 값(WINDOW_DIM_TIME) · 숨기기 → 1(WINDOW_CLOSE_TIME)", dimIn.from == 1 and dimIn.segments[1].to == 0.5
		and dimIn.segments[1].time == UIFxConfig.WINDOW_DIM_TIME and dimOut.segments[1].to == 1 and dimOut.segments[1].time == UIFxConfig.WINDOW_CLOSE_TIME)
	local normal, rare = FxLogic.modalSpec(UIFxConfig.MODAL_RARE_MIN_TIER - 1), FxLogic.modalSpec(UIFxConfig.MODAL_RARE_MIN_TIER)
	local peak = FxLogic.sample(rare.from, rare.segments, UIFxConfig.MODAL_RARE_TIME * UIFxConfig.POP_PEAK_AT, ease)
	check("모달: 보통 MODAL_SCALE_FROM → 1 · 영웅 이상 MODAL_RARE_SCALE_FROM → MODAL_RARE_PEAK → 1", normal.from == UIFxConfig.MODAL_SCALE_FROM
		and #normal.segments == 1 and rare.from == UIFxConfig.MODAL_RARE_SCALE_FROM and near(peak, UIFxConfig.MODAL_RARE_PEAK, 1e-4)
		and FxLogic.finalValue(rare) == 1 and near(FxLogic.totalTime(rare.segments), UIFxConfig.MODAL_RARE_TIME))
	check("희귀 판정: MODAL_RARE_MIN_TIER 이상만 · nil은 보통", FxLogic.isRare(UIFxConfig.MODAL_RARE_MIN_TIER) and FxLogic.isRare(6)
		and not FxLogic.isRare(UIFxConfig.MODAL_RARE_MIN_TIER - 1) and not FxLogic.isRare(nil))
	local pin = FxLogic.popInSpec(UIFxConfig.CRAFT_POP_FROM, UIFxConfig.CRAFT_POP_TIME)
	check("크래프팅 결과 칸: CRAFT_POP_FROM → 1", pin.from == UIFxConfig.CRAFT_POP_FROM and FxLogic.finalValue(pin) == 1)
end

-- 4. log10 보간 (U3) -------------------------------------------------------------------------------------------
do
	local a, b = B(1, 2), B(1, 4)
	local m = FxLogic.lerpLog(a, b, 0.5)
	check("보간: 100 → 10000의 반 = 1000(log 공간)", m.e == 3 and near(m.m, 1, 1e-9))
	local z0, z1 = FxLogic.lerpLog(a, b, 0), FxLogic.lerpLog(a, b, 1)
	check("보간: 0 = from 그대로 · 1 = to 그대로(같은 값의 사본)", BigNum.eq(z0, a) and BigNum.eq(z1, b) and z1 ~= b)
	local prev = a
	local mono = true
	for i = 1, 20 do
		local v = FxLogic.lerpLog(B(3.7, 5), B(2.2, 9), i / 20)
		if BigNum.lt(v, prev) or v.m < 1 or v.m >= 10 then
			mono = false
		end
		prev = v
	end
	check("보간: 늘기만 한다 · 가수 1 이상 10 미만", mono)
	local fromZero = FxLogic.lerpLog(B(0, 0), B(5, 3), 0.5)
	local zeroStart = FxLogic.lerpLog(B(0, 0), B(5, 3), 0)
	check("보간: 0에서 시작 — 0은 그대로, 사이는 1(log 0)부터", BigNum.eq(zeroStart, B(0, 0)) and fromZero.e == 1 and BigNum.gt(fromZero, B(1, 0)))
	check("보간: 같은 값 · 줄어듦 → 목표 그대로", BigNum.eq(FxLogic.lerpLog(b, b, 0.3), b) and BigNum.eq(FxLogic.lerpLog(b, a, 0.3), a))
	local huge = FxLogic.lerpLog(B(1, 2000), B(1, 2010), 0.5)
	check("보간: 10^2000 → 10^2010의 반 = 10^2005(정밀도 · inf 없음)", huge.e == 2005 and near(huge.m, 1, 1e-6) and huge.m == huge.m)
	local hugeEdge = FxLogic.lerpLog(B(9.99, 1999), B(1.01, 2000), 0.5)
	check("보간: 지수 경계 넘김도 사이 값", BigNum.gt(hugeEdge, B(9.99, 1999)) and BigNum.lt(hugeEdge, B(1.01, 2000)))
	check("계획: 늘면 animate · 줄면 instant · 같으면 none", FxLogic.countUpPlan(a, b) == "animate" and FxLogic.countUpPlan(b, a) == "instant"
		and FxLogic.countUpPlan(a, B(1, 2)) == "none")
	check("log10: 0 이하는 nil · 1e2000은 2000", FxLogic.log10Of(B(0, 0)) == nil and near(FxLogic.log10Of(B(1, 2000)) :: number, 2000))
end

-- 5. 스로틀 · 가운데 기준 --------------------------------------------------------------------------------------
do
	check("스로틀: 처음 · 간격 지남은 참 · 간격 안은 거짓", FxLogic.throttle(nil, 5, 0.5) and FxLogic.throttle(1, 1.5, 0.5) and not FxLogic.throttle(1, 1.49, 0.5))
	local p = FxLogic.centerPosition(Vector2.new(0, 0.5), UDim2.fromScale(0.1, 0.5), Vector2.new(40, 20), Vector2.new(400, 100))
	local same = FxLogic.centerPosition(Vector2.new(0.5, 0.5), UDim2.fromScale(0.3, 0.3), Vector2.new(40, 20), Vector2.new(400, 100))
	check("가운데 기준: (0, 0.5) 기준 → x만 칸 반폭만큼 · (0.5, 0.5)는 그대로 · Offset 0", near(p.X.Scale, 0.15) and near(p.Y.Scale, 0.5)
		and p.X.Offset == 0 and same == UDim2.fromScale(0.3, 0.3))
end

-- 6. 크래프팅 순서 (U6 — #12 결과 · PlayerState 순서) ---------------------------------------------------------------
do
	local R = { x = 0, y = 0, w = 0.1, h = 0.1 }
	local seq = FxLogic.newCraftSeq()
	local inGrid = false
	local function find(uid: string)
		return if inGrid and uid == "9" then R else nil
	end
	seq.begin({ R }, 0)
	check("크래프팅: 누름만으로는 재생 안 함", (seq.poll(find, 0.1)) == "wait")
	seq.result(true, "9", 0.2)
	check("크래프팅: 결과가 먼저 와도 격자에 없으면 기다린다", (seq.poll(find, 0.3)) == "wait")
	inGrid = true
	local v, rect, mats, uid = seq.poll(find, 0.4)
	check("크래프팅: 결과 + 격자 → 한 번 재생(자리 · 재료 · uid)", v == "play" and rect == R and mats ~= nil and #(mats :: any) == 1 and uid == "9"
		and (seq.poll(find, 0.5)) == "idle")
	local seq2 = FxLogic.newCraftSeq()
	seq2.begin({}, 0)
	inGrid = true
	check("크래프팅: PlayerState가 먼저 와도(격자에 있음) 결과 전엔 재생 안 함", (seq2.poll(find, 0.1)) == "wait")
	seq2.result(true, "9", 0.2)
	check("크래프팅: 그 뒤 결과가 오면 재생", (seq2.poll(find, 0.25)) == "play")
	local seq3 = FxLogic.newCraftSeq()
	seq3.begin({}, 0)
	seq3.result(false, "", 0.1)
	check("크래프팅: 거부 결과면 버린다", (seq3.poll(find, 0.2)) == "idle")
	local seq4 = FxLogic.newCraftSeq()
	seq4.begin({}, 0)
	seq4.result(true, "77", 0.1)
	check("크래프팅: CRAFT_WAIT_SEC 안에 격자에 안 들어오면 버린다", (seq4.poll(find, 0.1 + UIFxConfig.CRAFT_WAIT_SEC + 0.01)) == "idle")
end

-- ⚠️ 여기부터는 모든 화면이 같이 쓰는 값을 잠깐 바꾼다(Fx 시계 · FxPrefs 연출 줄이기 — 켜는 순간 붙은 버튼 전부가 1로 돌아간다).
-- 버튼 반응 · 빛 띠를 재는 UiFxTests가 끝난 뒤에 시작한다(2026-11-12 단계 3 실측: 같이 돌면 UiFxTests "올림" 검사 2개가 1을 읽었다).
-- 기다리는 방법은 그 파일의 요약 줄(LogService) — 30초가 지나면 그냥 시작한다
do
	local LogService = game:GetService("LogService")
	local deadline = os.clock() + 30
	local done = false
	while not done and os.clock() < deadline do
		for _, e in LogService:GetLogHistory() do
			if string.find(e.message, "[UiFxTests] ", 1, true) and string.find(e.message, " passed, ", 1, true) then
				done = true
				break
			end
		end
		if not done then
			task.wait(0.2)
		end
	end
end
-- 시계는 기다린 뒤에 바꾼다
T = 1000
Fx._debug.setClock(function()
	return T
end)

-- 7. 구동기 (가짜 시계) -------------------------------------------------------------------------------------------
do
	FxPrefs.set(false, true)
	local key = Instance.new("Folder")
	local got, done = -1, 0
	local spec = FxLogic.popInSpec(0.5, 0.2)
	local base = Fx._debug.activeCount()
	Fx.play(key, "a", spec, function(v)
		got = v
	end, function()
		done += 1
	end)
	check("구동기: 걸자마자 시작값 · 돌고 있음 · 루프 연결", got == 0.5 and Fx.isPlaying(key, "a") and Fx._debug.isLooping())
	T += 0.1
	Fx._debug.step()
	check("구동기: 중간 값(이징)", got > 0.5 and got ~= 1 and done == 0)
	T += 0.2
	Fx._debug.step()
	check("구동기: 끝 = 정확히 끝값 · onDone 한 번 · 목록에서 빠짐(트윈 정리)", got == 1 and done == 1 and not Fx.isPlaying(key, "a")
		and Fx._debug.activeCount() == base)
	local firstDone = 0
	Fx.play(key, "b", spec, function() end, function()
		firstDone += 1
	end)
	Fx.play(key, "b", spec, function(v)
		got = v
	end)
	check("구동기: 같은 자리에 새로 걸면 앞 것은 onDone 없이 버린다", firstDone == 0 and Fx._debug.activeCount() == base + 1)
	Fx.finish(key, "b")
	check("구동기: finish = 끝값 · 목록에서 빠짐", got == 1 and not Fx.isPlaying(key, "b"))
	local cancelDone = 0
	Fx.play(key, "c", spec, function(v)
		got = v
	end, function()
		cancelDone += 1
	end)
	Fx.cancel(key, "c")
	check("구동기: cancel = 그 자리(시작값) · onDone 없음", got == 0.5 and cancelDone == 0 and not Fx.isPlaying(key, "c"))
	-- 연출 줄이기
	FxPrefs.set(true, true)
	local reducedDone = 0
	Fx.play(key, "d", spec, function(v)
		got = v
	end, function()
		reducedDone += 1
	end)
	check("연출 줄이기: 걸자마자 끝값 + onDone(움직임 없음)", got == 1 and reducedDone == 1 and not Fx.isPlaying(key, "d"))
	FxPrefs.set(false, true)
	Fx.play(key, "e", spec, function(v)
		got = v
	end)
	FxPrefs.set(true, true)
	check("연출 줄이기를 켠 순간 돌던 것도 끝값", got == 1 and not Fx.isPlaying(key, "e"))
	FxPrefs.set(false, true)
	-- 스크린샷 멈춤
	UIFxConfig.DEBUG_FREEZE_PROGRESS = 0.5
	Fx.play(key, "f", FxLogic.progressSpec(0.2), function(v)
		got = v
	end)
	T += 5
	Fx._debug.step()
	local frozen = got
	local still = Fx.isPlaying(key, "f")
	UIFxConfig.DEBUG_FREEZE_PROGRESS = nil
	Fx._debug.step()
	check("멈춤값: 시간이 지나도 그 진행률(0.5)에 머문다 · 끄면 끝난다", near(frozen, 0.5) and still and got == 1 and not Fx.isPlaying(key, "f"))
	key:Destroy()
end

-- 8. UIScale 하나 규칙 · 가운데 기준 튀기 ------------------------------------------------------------------------------
do
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(0.5, 0.5)
	holder.Parent = gui
	local btn = Instance.new("Frame")
	btn.Size = UDim2.fromScale(0.2, 0.2)
	btn.Parent = holder
	local hit = Instance.new("TextButton")
	hit.Name = "HitArea"
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = btn
	ButtonFx.attach(hit)
	local skippedBefore = #Fx.skipped
	check("UIScale 하나: 버튼 반응(ButtonFxScale)이 달린 그림에는 연출 UIScale을 달지 않는다", Fx.scaleOf(btn) == nil and #Fx.skipped == skippedBefore + 1
		and #btn:GetChildren() == 2)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0.1, 0.5)
	label.Size = UDim2.fromScale(0.2, 0.3)
	label.Parent = holder
	task.wait()
	local restPos = label.Position
	Fx.pop(label, UIFxConfig.LEVEL_POP_PEAK, UIFxConfig.LEVEL_POP_TIME)
	local s = label:FindFirstChild(Fx.SCALE_NAME) :: UIScale
	local pivoted = Fx.isPivoted(label) and label.AnchorPoint == Vector2.new(0.5, 0.5)
	T += UIFxConfig.LEVEL_POP_TIME * UIFxConfig.POP_PEAK_AT
	Fx._debug.step()
	local peakScale = s.Scale
	T += UIFxConfig.LEVEL_POP_TIME
	Fx._debug.step()
	check("튀기: 가운데 기준으로 바꿨다가 · 꼭대기 LEVEL_POP_PEAK · 끝나면 1과 원래 AnchorPoint · Position", pivoted
		and near(peakScale, UIFxConfig.LEVEL_POP_PEAK, 1e-3) and s.Scale == 1 and label.AnchorPoint == Vector2.new(0, 0.5) and label.Position == restPos
		and not Fx.isPivoted(label))
	check("튀기: 연출 UIScale 이름 FxScale 하나", #label:GetChildren() == 1 and s.Name == "FxScale")
	holder:Destroy()
end

-- 9. 창 열기 · 닫기 (U1) ------------------------------------------------------------------------------------------
do
	local sc = ScreenController.new("FxTests_", { animate = true })
	local dbg = sc._debug
	local function panel(): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(0.6, 0.7)
		return f
	end
	sc.register("A", "Window", panel)
	sc.register("B", "Window", panel)
	local changes: { boolean } = {}
	sc.onWindowChanged(function(v)
		table.insert(changes, v)
	end)
	sc.open("A")
	local a = dbg.entries.A.instance :: GuiObject
	local aScale = a:FindFirstChild(ScreenController.WINDOW_SCALE_NAME) :: UIScale
	local blur = dbg.getBlur() :: Frame
	check("열기: 창 UIScale WINDOW_OPEN_SCALE_FROM에서 시작 · 막은 투명도 1에서", aScale ~= nil and near(aScale.Scale, UIFxConfig.WINDOW_OPEN_SCALE_FROM)
		and blur.Visible and near(blur.BackgroundTransparency, 1))
	T += UIFxConfig.WINDOW_OPEN_TIME + 0.01
	Fx._debug.step()
	check("열기 끝: 창 1 · 막 원래 투명도", aScale.Scale == 1 and near(blur.BackgroundTransparency, 0.5))
	sc.close("A")
	check("닫기: isOpen은 바로 false · 모양은 닫는 중(보임 · isClosing)", not sc.isOpen("A") and a.Visible and sc.isClosing("A"))
	T += UIFxConfig.WINDOW_CLOSE_TIME * 0.5
	Fx._debug.step()
	local mid = aScale.Scale
	T += UIFxConfig.WINDOW_CLOSE_TIME
	Fx._debug.step()
	check("닫기 끝: 1 → WINDOW_CLOSE_SCALE_TO 사이를 지나 · 끝나면 숨김 · 크기 1로 · 막 숨김", mid < 1 and mid > UIFxConfig.WINDOW_CLOSE_SCALE_TO
		and not a.Visible and aScale.Scale == 1 and not sc.isClosing("A") and not blur.Visible)
	-- 닫는 중에 다른 창을 연다
	sc.open("A")
	T += 1
	Fx._debug.step()
	sc.close("A")
	sc.open("B")
	local b = dbg.entries.B.instance :: GuiObject
	check("닫는 중 다른 창: 닫히던 창은 즉시 숨김(겹치지 않음) · 새 창만 보임 · 단일 오픈", not a.Visible and not sc.isClosing("A") and b.Visible
		and sc.isOpen("B") and not sc.isOpen("A"))
	-- 열린 창에서 다른 창 열기(연출 없이 즉시 닫힘)
	T += 1
	Fx._debug.step()
	sc.open("A")
	check("열린 창에서 다른 창: 앞 창은 즉시 닫힘(닫는 연출 없음)", not b.Visible and not sc.isClosing("B") and a.Visible)
	-- 같은 창을 닫는 중에 다시 연다
	T += 1
	Fx._debug.step()
	sc.close("A")
	sc.open("A")
	check("같은 창 다시 열기: 닫힘을 끝내고 다시 연다(보임 · 열기 시작 크기)", a.Visible and sc.isOpen("A") and not sc.isClosing("A")
		and near(aScale.Scale, UIFxConfig.WINDOW_OPEN_SCALE_FROM))
	T += 1
	Fx._debug.step()
	check("창 변화 알림: 연출과 무관하게 열림 · 닫힘 순서대로", changes[1] == true and changes[2] == false)
	-- 연출 줄이기: 닫기가 바로 끝난다
	FxPrefs.set(true, true)
	sc.close("A")
	check("연출 줄이기: 닫기 즉시 숨김(움직임 없음)", not a.Visible and not sc.isClosing("A") and aScale.Scale == 1)
	FxPrefs.set(false, true)
	-- 연출 없는 인스턴스(기존 테스트 전제)
	local plain = ScreenController.new("FxTestsPlain_")
	plain.register("P", "Window", panel)
	plain.open("P")
	plain.close("P")
	local p = plain._debug.entries.P.instance :: GuiObject
	check("연출 없는 인스턴스: 닫으면 바로 숨김 · UIScale 없음", not p.Visible and p:FindFirstChildOfClass("UIScale") == nil)
	sc.destroy()
	plain.destroy()
end

-- 10. 결과 모달 (U2) · 빛 띠 1회 ----------------------------------------------------------------------------------
do
	local m = ResultModal.create()
	m.root.Parent = gui
	local panelF = m._debug.panel
	m.show({ heading = "h", name = "n", rarityTier = UIFxConfig.MODAL_RARE_MIN_TIER - 1, detail = "d" })
	local s = panelF:FindFirstChild(Fx.SCALE_NAME) :: UIScale
	check("모달 보통: MODAL_SCALE_FROM에서 시작 · 빛 띠 없음", s ~= nil and near(s.Scale, UIFxConfig.MODAL_SCALE_FROM) and not Shine.isAttached(panelF))
	T += 1
	Fx._debug.step()
	check("모달 보통: 끝나면 1", s.Scale == 1)
	m.hide()
	m.show({ heading = "h", name = "n", rarityTier = 5, detail = "d" })
	check("모달 영웅 이상: MODAL_RARE_SCALE_FROM에서 시작 · 빛 띠 1회 붙음", near(s.Scale, UIFxConfig.MODAL_RARE_SCALE_FROM) and Shine.isAttached(panelF))
	T += UIFxConfig.MODAL_RARE_TIME * UIFxConfig.POP_PEAK_AT
	Fx._debug.step()
	local peak = s.Scale
	T += UIFxConfig.MODAL_RARE_TIME
	Fx._debug.step()
	check("모달 영웅 이상: 꼭대기 MODAL_RARE_PEAK → 끝 1", near(peak, UIFxConfig.MODAL_RARE_PEAK, 1e-3) and s.Scale == 1)
	m.hide()
	check("모달 숨김: 빛 띠를 뗀다", not Shine.isAttached(panelF))
	m.root:Destroy()
end

-- 11. 빛 띠 1회 모드 · 연출 줄이기 -----------------------------------------------------------------------------------
do
	local clockT = 0
	Shine._debug.setClock(function()
		return clockT
	end)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0.2, 0.1)
	f.Parent = gui
	Shine.attach(f, { once = true, delay = 0.1, priority = UIFxConfig.SHINE_ONCE_PRIORITY })
	Shine._debug.step()
	local started = Shine._debug.isRunning(f)
	clockT = 0.1 + UIFxConfig.SHINE_SWEEP_TIME * 0.5
	Shine._debug.step()
	local midOffset = (Shine._debug.gradientOf(f) :: UIGradient).Offset.X
	clockT = 0.1 + UIFxConfig.SHINE_SWEEP_TIME + 0.05
	Shine._debug.step()
	check("빛 띠 1회: delay 뒤 한 번 지나가고(가운데 근처) · 끝나면 스스로 떨어진다(반복 없음)", started and midOffset > -1 and midOffset < 1
		and not Shine.isAttached(f))
	local g = Instance.new("Frame")
	g.Size = UDim2.fromScale(0.2, 0.1)
	g.Parent = gui
	Shine.attach(g, { once = true })
	g.Visible = false
	Shine._debug.step()
	check("빛 띠 1회: 숨으면 바로 뗀다", not Shine.isAttached(g))
	local r = Instance.new("Frame")
	r.Size = UDim2.fromScale(0.2, 0.1)
	r.Parent = gui
	Shine.attach(r, { priority = 50 })
	Shine._debug.step()
	local runningBefore = Shine._debug.isRunning(r)
	FxPrefs.set(true, true)
	Shine._debug.step()
	local overlay = Shine._debug.overlayOf(r) :: GuiObject
	check("연출 줄이기: 붙은 빛 띠가 바로 멈추고 덮개를 숨긴다", runningBefore and not Shine._debug.isRunning(r) and overlay ~= nil and not overlay.Visible)
	local o = Instance.new("Frame")
	o.Size = UDim2.fromScale(0.2, 0.1)
	o.Parent = gui
	Shine.attach(o, { once = true })
	Shine._debug.step()
	check("연출 줄이기: 1회 모드는 바로 뗀다", not Shine.isAttached(o))
	FxPrefs.set(false, true)
	Shine._debug.step()
	check("연출 줄이기 끔: 다시 돈다", Shine._debug.isRunning(r))
	Shine.detach(r)
	Shine._debug.setClock(nil)
	f:Destroy()
	g:Destroy()
	r:Destroy()
	o:Destroy()
end

-- 12. 버튼 반응 · 연출 줄이기 -----------------------------------------------------------------------------------------
do
	local pic = Instance.new("Frame")
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position = UDim2.fromScale(0.5, 0.5)
	pic.Size = UDim2.fromScale(0.2, 0.1)
	pic.Parent = gui
	local hit = Instance.new("TextButton")
	hit.Name = "HitArea"
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = pic
	local h = ButtonFx.attach(hit) :: any
	h._debug.fire("enter", false, true)
	h._debug.settle()
	local hovered = h.scale.Scale
	FxPrefs.set(true, true)
	check("연출 줄이기를 켠 순간: 커져 있던 버튼이 바로 1", near(hovered, UIFxConfig.HOVER_SCALE, 1e-4) and h.scale.Scale == 1)
	h._debug.fire("down", false, true)
	h._debug.settle()
	check("연출 줄이기: 눌러도 크기 1(트윈 없음)", h.scale.Scale == 1 and h._debug.goal() == 1)
	FxPrefs.set(false, true)
	h._debug.fire("up", false, true)
	h._debug.fire("leave", false, false)
	h._debug.fire("enter", false, true)
	h._debug.settle()
	check("연출 줄이기 끔: 다음 입력부터 다시 반응", near(h.scale.Scale, UIFxConfig.HOVER_SCALE, 1e-4))
	pic:Destroy()
end

-- 13. 블럭스 올라가기 (U3) ------------------------------------------------------------------------------------------
do
	local store = Store.new()
	local setter: any = nil
	store.setSource(function(s)
		setter = s
		s("blox", B(1, 2))
	end)
	local live = false
	local d = BloxDisplay.create(store, { live = function()
		return live
	end })
	d.root.Parent = gui
	task.wait()
	setter("blox", B(5, 2))
	task.wait()
	check("올라가기: 첫 상태(live 아님)는 즉시", BigNum.eq(d._debug.shown(), B(5, 2)) and not Fx.isPlaying(d.root, "countUp"))
	live = true
	setter("blox", B(5, 6))
	task.wait()
	check("올라가기: 늘면 연출 시작(지금 표시값에서)", Fx.isPlaying(d.root, "countUp") and BigNum.eq(d._debug.shown(), B(5, 2)))
	T += UIFxConfig.COUNT_UP_TIME * 0.5
	Fx._debug.step()
	local mid = d._debug.shown()
	check("올라가기: 중간 표시값은 이전 < 값 < 새 값 · 표시는 Formatter", BigNum.gt(mid, B(5, 2)) and BigNum.lt(mid, B(5, 6))
		and d._debug.label.Text ~= "")
	setter("blox", B(1, 8))
	task.wait()
	check("올라가기: 진행 중에 또 늘면 지금 표시값에서 다시", Fx.isPlaying(d.root, "countUp") and BigNum.eq(d._debug.shown(), mid))
	T += UIFxConfig.COUNT_UP_TIME + 0.01
	Fx._debug.step()
	check("올라가기: 끝 = 정확히 새 값", BigNum.eq(d._debug.shown(), B(1, 8)) and not Fx.isPlaying(d.root, "countUp"))
	setter("blox", B(2, 3))
	task.wait()
	check("올라가기: 줄면 즉시", BigNum.eq(d._debug.shown(), B(2, 3)) and not Fx.isPlaying(d.root, "countUp"))
	d.root:Destroy()
end

-- 14. 레벨 · 환생 배수 튀기 (U4 · U5) ---------------------------------------------------------------------------------
do
	local store = Store.new()
	local setter: any = nil
	store.setSource(function(s)
		setter = s
		s("strength", B(1, 0))
		s("rebirths", B(0, 0))
	end)
	local live = false
	local clockNow = 0
	local pb = PowerBlock.create(store, { live = function()
		return live
	end, now = function()
		return clockNow
	end })
	pb.root.Parent = gui
	task.wait()
	setter("strength", B(1, 3))
	setter("rebirths", B(2, 0))
	task.wait()
	check("튀기: 첫 상태(live 아님)는 연출 없음", pb._debug.pops().level == 0 and pb._debug.pops().rebirth == 0)
	live = true
	local lv = LevelConfig.getLevel(B(1, 3))
	setter("strength", B(1, 6))
	task.wait()
	check("레벨: 오르면 튀기 1회(레벨 숫자)", LevelConfig.getLevel(B(1, 6)) > lv and pb._debug.pops().level == 1
		and Fx.isPlaying(pb._debug.levelLabel, "pop"))
	clockNow += UIFxConfig.LEVEL_POP_MIN_INTERVAL * 0.5
	setter("strength", B(1, 9))
	task.wait()
	check("레벨: LEVEL_POP_MIN_INTERVAL 안에 또 오르면 튀지 않는다", pb._debug.pops().level == 1)
	clockNow += UIFxConfig.LEVEL_POP_MIN_INTERVAL
	setter("strength", B(1, 12))
	task.wait()
	check("레벨: 간격이 지나면 다시 튄다", pb._debug.pops().level == 2)
	setter("rebirths", B(3, 0))
	task.wait()
	check("환생 배수: 환생 수가 늘면 튀기(REBIRTH_POP)", pb._debug.pops().rebirth == 1 and Fx.isPlaying(pb._debug.multiplierLabel, "pop"))
	setter("rebirths", B(0, 0))
	task.wait()
	check("환생 배수: 줄면(초기화 등) 튀지 않는다", pb._debug.pops().rebirth == 1)
	Fx.finishAll()
	pb.root:Destroy()
end

-- 15. 크래프팅 연결 (U6) — 결과 뒤 재생 --------------------------------------------------------------------------------
do
	local pid = PetConfig.Eggs[1].pets[1].id
	local function pets(owned: { any })
		return { owned = owned, equipped = {}, slots = PetConfig.getSlots(0, false), storage = PetConfig.getStorage(false), hideOtherPets = false, world = 1 }
	end
	local three = { { uid = "1", petId = pid, level = 1 }, { uid = "2", petId = pid, level = 1 }, { uid = "3", petId = pid, level = 1 } }
	local function run(resultFirst: boolean): (number, string?, number)
		local store = Store.new()
		local setter: any = nil
		store.setSource(function(s)
			setter = s
			s("pets", pets(three))
			s("blox", B(1, 9))
			s("lifetimeBlox", B(1, 9))
		end)
		local clock = 0
		local w = PetWindow.create({ store = store, sendRequest = function() end, onClose = function() end, now = function()
			return clock
		end })
		w.root.Parent = gui
		task.wait()
		w._debug.select("1")
		w._debug.pressCraft()
		local after = pets({ { uid = "9", petId = pid, level = 2 } })
		local result = { action = "craft", ok = true, reason = "", uid = "9", petId = pid, eggId = 1, rarity = 1, level = 2, isNew = false, equipped = false, pets = {} }
		local beforeBoth: number
		if resultFirst then
			w.onResult(result)
			task.wait()
			beforeBoth = w._debug.craftPlays()
			setter("pets", after)
		else
			setter("pets", after)
			task.wait()
			beforeBoth = w._debug.craftPlays()
			w.onResult(result)
		end
		task.wait()
		local hidden = w._debug.hiddenUid()
		local plays = w._debug.craftPlays()
		Fx.finishAll()
		task.wait()
		local cleared = if w._debug.hiddenUid() == nil and not w._debug.ghosts[4].Visible then 1 else 0
		w.root:Destroy()
		return beforeBoth * 10 + plays, hidden, cleared
	end
	local a, hiddenA, clearedA = run(true)
	check("크래프팅: 결과가 먼저 와도 PlayerState 뒤에 한 번 재생 · 그동안 결과 칸 숨김 · 끝나면 되돌림", a == 1 and hiddenA == "9" and clearedA == 1)
	local b, hiddenB, clearedB = run(false)
	check("크래프팅: PlayerState가 먼저 와도 결과 뒤에 한 번 재생", b == 1 and hiddenB == "9" and clearedB == 1)
end

-- 정리 ------------------------------------------------------------------------------------------------------------
Fx.finishAll()
Fx._debug.setClock(nil)
FxPrefs.set(savedReduce, savedSfx)
gui:Destroy()

print(string.format("[FxTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[FxTests] %d test(s) failed", failed))
end

--!strict
-- 피드백 표시 검증 (Phase 6 지시서 #8 2단계): 클릭 팝업 증가분 · 문구 · 진행, HUD 환생 배수(서버와 같은 함수),
-- 환생 안내 문구(×이전 → ×이후), 운동기구 3D 표시 역할 · 문구(GymConfig 원본). 실물 싱글톤이 아니라 Store.new()로 굴린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local Layout = require(script.Parent.Parent.UI.Layout)
local Store = require(script.Parent.Parent.UI.Store)
local FeedbackLogic = require(script.Parent.Parent.UI.Logic.FeedbackLogic)
local WorldLabelLogic = require(script.Parent.Parent.World.WorldLabelLogic)
local PowerBlock = require(script.Parent.Parent.UI.Screens.Hud.PowerBlock)
local RebirthNotice = require(script.Parent.Parent.UI.Screens.Overlay.RebirthNotice)

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

-- 1. 클릭 팝업 ---------------------------------------------------------------------------------
do
	local a, b = BigNum.new(1, 3), BigNum.new(1.25, 3)
	local g = FeedbackLogic.gainOf(a, b)
	check("팝업: 증가분 = 지금 − 이전", g ~= nil and BigNum.eq(g :: any, BigNum.new(2.5, 2)))
	check("팝업: 줄면(환생 초기화) 안 띄운다", FeedbackLogic.gainOf(b, a) == nil)
	check("팝업: 같으면 안 띄운다", FeedbackLogic.gainOf(a, a) == nil)
	check("팝업: 이전 값이 없으면 안 띄운다", FeedbackLogic.gainOf(nil, a) == nil)
	check("팝업: 문구 +값", FeedbackLogic.popupText(BigNum.new(2.5, 2), 1) == "+" .. Formatter.format(BigNum.new(2.5, 2)))
	local gymText = FeedbackLogic.popupText(BigNum.new(2.5, 2), 1.2)
	check("팝업: 기구 위면 배수를 같이 적는다", string.find(gymText, "기구 ×1.2", 1, true) ~= nil, gymText)
	check("팝업: 배수 짧게 적기", FeedbackLogic.formatMultiplier(2) == "2" and FeedbackLogic.formatMultiplier(1.5) == "1.5" and FeedbackLogic.formatMultiplier(100) == "100")
	local r0, t0 = FeedbackLogic.popupFrame(0)
	local r1, t1 = FeedbackLogic.popupFrame(1)
	local rm, tm = FeedbackLogic.popupFrame(0.5)
	check("팝업: 시작은 제자리 · 불투명", r0 == 0 and t0 == 0)
	check("팝업: 끝은 다 오르고 투명", math.abs(r1 - FeedbackLogic.POPUP_RISE_STUDS) < 1e-9 and math.abs(t1 - 1) < 1e-9)
	check("팝업: 중간은 아직 진하다", rm > 0 and rm < r1 and tm == 0)
	check("팝업: 풀은 배치 주기 × 수명을 넉넉히 덮는다", FeedbackLogic.POPUP_POOL_SIZE >= math.ceil(FeedbackLogic.POPUP_LIFETIME_SEC / 0.2))
end

-- 2. HUD 환생 배수 -------------------------------------------------------------------------------
do
	local rebirths = BigNum.fromNumber(28)
	check("배수: StrengthMultiplier.compute와 같다", BigNum.eq(FeedbackLogic.multiplierOf(rebirths), StrengthMultiplier.compute({ rebirths = rebirths })))
	local store = Store.new()
	store.setSource(function(setter)
		setter("rebirths", rebirths)
	end)
	local handle = PowerBlock.create(store)
	local label = handle._debug.multiplierLabel
	check("HUD: 환생 배수 칸이 힘 행에 있다", label ~= nil and label.Parent ~= nil and label.Parent.Name == "Multiplier")
	check("HUD: 환생 배수 값", label.Text == Formatter.format(StrengthMultiplier.compute({ rebirths = rebirths })), label.Text)
	handle._debug.applyMultiplier(BigNum.fromNumber(30))
	check("HUD: 배수 갱신", label.Text == Formatter.format(StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(30) })), label.Text)
	check("HUD: 환생 배수 칸은 힘 수치 오른쪽(가운데 칸과 안 겹치게)", PowerBlock.MultiplierX >= 0.7)
	handle.root:Destroy()
end

-- 3. 환생 안내 -----------------------------------------------------------------------------------
do
	local n = FeedbackLogic.rebirthNotice(BigNum.fromNumber(31), BigNum.fromNumber(3))
	local before = StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(28) })
	local after = StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(31) })
	check("안내: 이전 배수 = (total − gained)의 배수", BigNum.eq(n.before, before))
	check("안내: 이후 배수 = total의 배수", BigNum.eq(n.after, after))
	check("안내: ×이전 → ×이후 문구", n.change == string.format("힘 배수 ×%s → ×%s", Formatter.format(before), Formatter.format(after)), n.change)
	check("안내: 초기화 사실", n.reset == FeedbackLogic.REBIRTH_RESET_TEXT and n.title == FeedbackLogic.REBIRTH_TITLE)
	local first = FeedbackLogic.rebirthNotice(BigNum.fromNumber(2), BigNum.fromNumber(2))
	check("안내: 첫 환생(이전 0)", BigNum.eq(first.before, StrengthMultiplier.compute({ rebirths = BigNum.new(0, 0) })))

	local notice = RebirthNotice.create()
	check("안내: 처음엔 숨김 (root가 보여도 판은 숨김)", not notice.panel.Visible and notice.root.BackgroundTransparency == 1)
	notice.show(n)
	check("안내: 보이면 세 줄이 채워진다", notice.panel.Visible and notice._rows.change.Text == n.change and notice._rows.reset.Text == n.reset)
	local b = RebirthNotice.Bounds
	check("안내: 상단 정보 띠 안(중앙 금지 구역 밖)", b.y1 <= Layout.TOP_HEIGHT and not Layout.overlapsCenterForbidden(b.x0, b.y0, b.x1, b.y1))
	check("안내: 알림층", notice.root.ZIndex >= 30)
	notice.root:Destroy()
end

-- 4. 운동기구 3D 표시 -----------------------------------------------------------------------------
do
	local count = GymConfig.getCount()
	local zero = BigNum.new(0, 0)
	local rebirths = GymConfig.getUnlockRebirths(3) -- 기구 1~3 열림
	local unlocked = GymConfig.getUnlockedCount(rebirths)
	check("기구 역할: 공허(로벅스 전용)는 항상", WorldLabelLogic.gymRole(count, nil, unlocked) == "void")
	check("기구 역할: 열린 것 중 최고", WorldLabelLogic.gymRole(unlocked, nil, unlocked) == "best")
	check("기구 역할: 다음 해금", WorldLabelLogic.gymRole(unlocked + 1, nil, unlocked) == "next")
	check("기구 역할: 서 있는 기구는 사용 중", WorldLabelLogic.gymRole(1, 1, unlocked) == "current")
	check("기구 역할: 사이 기구는 숨김", WorldLabelLogic.gymRole(2, nil, unlocked) == nil)
	check("기구 역할: 하나도 안 열렸으면 다음 = 1", WorldLabelLogic.gymRole(1, nil, 0) == "next")

	local on = WorldLabelLogic.gym(1, rebirths, true)
	check("기구 표시: 열린 기구 위면 사용 중 · 주황", on.detail == "사용 중" and on.role == "power" and string.find(on.title, "×1.2", 1, true) ~= nil, on.title)
	local off = WorldLabelLogic.gym(1, rebirths, false)
	check("기구 표시: 열렸지만 안 서 있으면 한 줄", off.detail == "" and off.role == "power")
	local locked = WorldLabelLogic.gym(4, zero, false)
	check("기구 표시: 잠김은 필요 환생 수 · 회색", locked.role == "neutral"
		and string.find(locked.detail, Formatter.format(GymConfig.getUnlockRebirths(4)), 1, true) ~= nil, locked.detail)
	check("기구 표시: 잠긴 기구 위면 잠김", string.find(WorldLabelLogic.gym(4, zero, true).detail, "잠김", 1, true) ~= nil)
	local void = WorldLabelLogic.gym(count, BigNum.new(1, 30), true)
	check("기구 표시: 공허는 로벅스 전용(준비 중) · 프리미엄", void.role == "premium" and void.detail == "로벅스 전용(준비 중)")

	-- 서 있는 기구 판정은 서버와 같은 함수(GymLayout.resolve)
	local c = GymLayout.computeLayout(count)[1]
	local r = GymLayout.resolve(Vector3.new(c.X, c.Y + 3, c.Z), rebirths)
	check("기구 판정: 기구 1 위 · 열림 · 배수", r.index == 1 and r.unlocked and r.multiplier == GymConfig.getMultiplier(1))
	check("기구 판정: 통로는 기구 위 아님", GymLayout.resolve(Vector3.new(c.X, 3, 0), rebirths).index == nil)
end

-- 5. 패드 · 운동기구 본체 색 (지시서 #8 M4) ---------------------------------------------------------
do
	local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
	local zero = BigNum.new(0, 0)
	check("패드 색: 패드 1은 처음부터 해금 → 주황", WorldLabelLogic.padBodyRole(1, zero) == "power")
	check("패드 색: 미해금 → 회색", WorldLabelLogic.padBodyRole(2, zero) == "neutral")
	check("패드 색: 해금 조건을 채우면 → 주황", WorldLabelLogic.padBodyRole(2, ClickPadConfig.getPadUnlock(1, 2)) == "power")
	local count = GymConfig.getCount()
	check("기구 색: 환생 0이면 기구 1 회색", WorldLabelLogic.gymBodyRole(1, zero) == "neutral")
	check("기구 색: 조건을 채우면 주황", WorldLabelLogic.gymBodyRole(1, GymConfig.getUnlockRebirths(1)) == "power")
	check("기구 색: 공허는 환생과 무관하게 프리미엄", WorldLabelLogic.gymBodyRole(count, zero) == "premium" and WorldLabelLogic.gymBodyRole(count, BigNum.new(1, 30)) == "premium")
end

print(string.format("[FeedbackTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[FeedbackTests] %d test(s) failed", failed))
end

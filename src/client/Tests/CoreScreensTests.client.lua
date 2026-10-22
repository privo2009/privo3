--!strict
-- U4 코어 화면 검증 (지시서 #5): 로딩 · 클리어 선택 안내 · 실패 · 3D 안내의 표시 조건(순수 로직)과
-- 화면 규칙(Offset 0 · 중앙 금지 구역 밖 · 층 순서 · 역할 색).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Layout = require(script.Parent.Parent.UI.Layout)
local RunNoticeLogic = require(script.Parent.Parent.UI.Logic.RunNoticeLogic)
local LoadingScreen = require(script.Parent.Parent.UI.Screens.Overlay.LoadingScreen)
local RunNotice = require(script.Parent.Parent.UI.Screens.Overlay.RunNotice)
local ErrorNotice = require(script.Parent.Parent.UI.Screens.Overlay.ErrorNotice)
local OverlayParts = require(script.Parent.Parent.UI.Screens.Overlay.OverlayParts)
local WorldLabelLogic = require(script.Parent.Parent.World.WorldLabelLogic)

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

-- 1. 런 안내 판정 ---------------------------------------------------------------------------
local function decide(active: boolean, reason: string, cleared: boolean, canAdvance: boolean)
	return RunNoticeLogic.decide({ active = active, reason = reason, cleared = cleared, canAdvance = canAdvance })
end
check("안내: 클리어(다음 층 있음) → clear", decide(true, "cleared", true, true) == "clear")
check("안내: 클리어(최종층) → clearFinal", decide(true, "cleared", true, false) == "clearFinal")
check("안내: 접속 sync에서 이미 클리어된 런 → clear", decide(true, "sync", true, true) == "clear")
check("안내: 시간 초과 → fail", decide(false, "timeout", false, false) == "fail")
check("안내: 수령 → hide", decide(false, "cashout", true, true) == "hide")
check("안내: 포기 → hide", decide(false, "abandon", false, false) == "hide")
check("안내: 새 층 진입 → hide", decide(true, "advance", false, true) == "hide")
check("안내: 런 시작 → hide", decide(true, "start", false, false) == "hide")
check("안내: 런 없음 sync → hide", decide(false, "sync", false, false) == "hide")
for kind, sec in pairs(RunNoticeLogic.DURATION_SEC) do
	check(string.format("안내: %s 표시 시간이 양수", kind), type(sec) == "number" and sec > 0)
end

-- 2. 로딩 판정 -----------------------------------------------------------------------------
check("로딩: 받으면 done", LoadingScreen.decide(true, 0) == "done")
check("로딩: 시간 초과 뒤에 받아도 done", LoadingScreen.decide(true, LoadingScreen.TIMEOUT_SEC + 5) == "done")
check("로딩: 못 받고 시간 안이면 loading", LoadingScreen.decide(false, LoadingScreen.TIMEOUT_SEC - 0.1) == "loading")
check("로딩: 못 받고 시간을 넘기면 timeout", LoadingScreen.decide(false, LoadingScreen.TIMEOUT_SEC) == "timeout")

-- 3. 3D 안내 내용 --------------------------------------------------------------------------
do
	local cleared = { active = true, stage = 3, cleared = true, canAdvance = true, reward = BigNum.new(7.29, 0) }
	local c = WorldLabelLogic.cashout(cleared, 3)
	check("발판: 켜진 발판에 수령액(서버 값)", c.visible and c.role == "cashout" and c.detail == "+" .. Formatter.format(cleared.reward), c.detail)
	check("발판: 다른 층 발판에는 안 뜸", not WorldLabelLogic.cashout(cleared, 2).visible)
	local notCleared = { active = true, stage = 3, cleared = false, canAdvance = true, reward = BigNum.new(7.29, 0) }
	check("발판: 클리어 전에는 안 뜸", not WorldLabelLogic.cashout(notCleared, 3).visible)
	check("발판: 런 없음이면 안 뜸", not WorldLabelLogic.cashout(nil, 3).visible)

	local w = WorldLabelLogic.wall(cleared)
	check("벽: 클리어 뒤 다음 층 보상(StageConfig 원본)", w.visible and w.role == "advance"
		and w.detail == "다음 층 +" .. Formatter.format(StageConfig.getBloxReward(4)), w.detail)
	local boosted = { active = true, stage = 3, cleared = true, canAdvance = true, reward = BigNum.new(7.29, 0), nextReward = BigNum.new(3.3, 2) }
	check("벽: 서버가 nextReward를 주면 그 값(업그레이드 배수는 서버가 곱한다 — 지시서 #7)",
		WorldLabelLogic.wall(boosted).detail == "다음 층 +" .. Formatter.format(BigNum.new(3.3, 2)), WorldLabelLogic.wall(boosted).detail)
	check("벽: 클리어 전에는 안 뜸", not WorldLabelLogic.wall(notCleared).visible)
	local final = { active = true, stage = 25, cleared = true, canAdvance = false, reward = BigNum.new(1, 0) }
	local wf = WorldLabelLogic.wall(final)
	check("벽: 최종층은 중립 회색 안내", wf.visible and wf.role == "neutral")

	local zero = BigNum.new(0, 0)
	local p1 = WorldLabelLogic.pad(1, zero)
	check("패드: 패드 1은 처음부터 해금(주황)", p1.visible and p1.role == "power" and p1.detail == "")
	check("패드: 파워 문구는 ClickPadConfig 원본", p1.title == "클릭 " .. Formatter.format(ClickPadConfig.getPadPower(1, 1)), p1.title)
	local p2 = WorldLabelLogic.pad(2, zero)
	check("패드: 미해금은 회색 + 필요량(원본)", p2.role == "neutral"
		and p2.detail == "필요 " .. Formatter.format(ClickPadConfig.getPadUnlock(1, 2)), p2.detail)
	local p2open = WorldLabelLogic.pad(2, ClickPadConfig.getPadUnlock(1, 2))
	check("패드: 조건을 채우면 주황", p2open.role == "power")

	-- 패드 표시는 셋만 (지시서 #6): 지금 패드 · 열린 것 중 최고 · 다음 해금 대상
	local function shownCount(selected: number, unlocked: number): number
		local n = 0
		for i = 1, ClickPadConfig.getSet(1).count do
			if WorldLabelLogic.isPadShown(i, selected, unlocked) then
				n += 1
			end
		end
		return n
	end
	check("패드 표시: 지금 · 최고 · 다음 셋", shownCount(2, 5) == 3)
	check("패드 표시: 지금 패드가 최고면 둘", shownCount(5, 5) == 2)
	check("패드 표시: 전부 열렸으면 다음이 없다", shownCount(ClickPadConfig.getSet(1).count, ClickPadConfig.getSet(1).count) == 1)
	check("패드 표시: 다음 해금 대상이 포함", WorldLabelLogic.isPadShown(6, 2, 5))
	check("패드 표시: 사이 패드는 숨김", not WorldLabelLogic.isPadShown(3, 2, 5) and not WorldLabelLogic.isPadShown(7, 2, 5))
	check("패드 표시: 역할 — 지금 · 최고 · 다음", WorldLabelLogic.padRole(2, 2, 5) == "current"
		and WorldLabelLogic.padRole(5, 2, 5) == "best" and WorldLabelLogic.padRole(6, 2, 5) == "next")
	local H = WorldLabelLogic.PAD_HEIGHT
	local S = WorldLabelLogic.PAD_SIZE
	check("패드 표시: 역할마다 높이가 달라 위아래로 벌어진다(아래 표시의 높이보다 크게)",
		H.best - H.current > S.current.Y and H["next"] - H.best > S.best.Y)
	check("패드 표시: 다음 해금 표시가 다른 둘보다 크다(멀리서 읽히게 — 지시서 #7)",
		S["next"].X > S.best.X and S["next"].Y > S.best.Y and S["next"].Y > S.current.Y)

	check("게이트: 런 없으면 보임", WorldLabelLogic.gate(false).visible)
	check("게이트: 런 중에는 숨김", not WorldLabelLogic.gate(true).visible)

	local roles = { c.role, w.role, wf.role, p1.role, p2.role, WorldLabelLogic.gate(false).role }
	local allKnown = true
	for _, role in ipairs(roles) do
		if UiTheme.Colors[role] == nil then
			allKnown = false
		end
	end
	check("3D 안내: 색은 UiTheme 역할 키만", allKnown)
end

-- 4. 화면 규칙 -----------------------------------------------------------------------------
local function scaleRect(frame: GuiObject): (number, number, number, number)
	local x0 = frame.Position.X.Scale - frame.AnchorPoint.X * frame.Size.X.Scale
	local y0 = frame.Position.Y.Scale - frame.AnchorPoint.Y * frame.Size.Y.Scale
	return x0, y0, x0 + frame.Size.X.Scale, y0 + frame.Size.Y.Scale
end

local function noOffset(root: GuiObject): boolean
	for _, obj in ipairs({ root, table.unpack(root:GetDescendants()) }) do
		if obj:IsA("GuiObject") then
			local g = obj :: GuiObject
			if g.Size.X.Offset ~= 0 or g.Size.Y.Offset ~= 0 or g.Position.X.Offset ~= 0 or g.Position.Y.Offset ~= 0 then
				return false
			end
		end
	end
	return true
end

do
	local loading = LoadingScreen.create()
	check("로딩: 화면 전체를 덮는다", loading.root.Size.X.Scale == 1 and loading.root.Size.Y.Scale == 1)
	check("로딩: 차단층 ZIndex", loading.root.ZIndex == OverlayParts.Z.blocking)
	check("로딩: 입력을 막는다(Active)", loading.root.Active == true)
	check("로딩: Offset 없음", noOffset(loading.root))
	loading.root:Destroy()

	local notice = RunNotice.create()
	local x0, y0, x1, y1 = scaleRect(notice.root)
	check("런 안내: 중앙 금지 구역 밖", not Layout.overlapsCenterForbidden(x0, y0, x1, y1), string.format("%.2f,%.2f,%.2f,%.2f", x0, y0, x1, y1))
	check("런 안내: 가장자리 3% 안쪽", x1 <= 1 - Layout.EDGE_MARGIN + 1e-6)
	check("런 안내: 하단 띠 위", y1 <= 1 - Layout.BOTTOM_HEIGHT)
	check("런 안내: 런 표시층 ZIndex", notice.root.ZIndex == OverlayParts.Z.runDisplay)
	check("런 안내: Offset 없음", noOffset(notice.root))
	check("런 안내: 처음엔 숨김", notice.root.Visible == false)

	notice.show("clear")
	check("런 안내: clear는 두 줄 · 노랑/보라", notice.root.Visible and notice._rows.first.Text == RunNotice.TEXT.cashout
		and notice._rows.second.Visible and notice._rows.second.Text == RunNotice.TEXT.advance
		and notice._rows.first.BackgroundColor3 == UiTheme.Colors.cashout.base
		and notice._rows.second.BackgroundColor3 == UiTheme.Colors.advance.base)
	notice.show("clearFinal")
	check("런 안내: 최종층은 '수령만 가능' 한 줄", notice._rows.first.Text == RunNotice.TEXT.final and not notice._rows.second.Visible)
	notice.show("fail")
	check("런 안내: 실패는 빨강 한 줄", notice._rows.first.Text == RunNotice.TEXT.fail
		and notice._rows.first.BackgroundColor3 == UiTheme.Colors.danger.base)
	notice.show("hide")
	check("런 안내: hide면 숨김", notice.root.Visible == false)
	notice.root:Destroy()

	local err = ErrorNotice.create()
	local ex0, ey0, ex1, ey1 = scaleRect(err.root)
	check("오류: 중앙 금지 구역 밖", not Layout.overlapsCenterForbidden(ex0, ey0, ex1, ey1))
	check("오류: 알림층이 가장 위", err.root.ZIndex > OverlayParts.Z.blocking and OverlayParts.Z.blocking > OverlayParts.Z.runDisplay)
	check("오류: 런 안내 칸과 세로로 겹치지 않는다", ey1 <= y0 + 1e-6, string.format("err bottom %.3f / notice top %.3f", ey1, y0))
	err.root:Destroy()
end

print(string.format("[CoreScreensTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[CoreScreensTests] %d test(s) failed", failed))
end

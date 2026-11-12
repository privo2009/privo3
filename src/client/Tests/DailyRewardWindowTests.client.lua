--!strict
-- 일일 보상 창 · HUD 아이콘 · 자동 등장 검증 (지시서 #20 단계 7 — D1 ~ D5). 실제 요청을 보내지 않는다 — 가짜 sendClaim · Store.new().
--   표시 값(서버 원본) · 칸 상태 · 리미티드 칸 · 배지 · 자동 등장(안내 끝난 뒤 · 런 중 아님 · 그날 한 번) · 요청 한 번만 · 사유 문구 ·
--   새 문장 en · ko · 폰 틀(705×338) 넘침 0 · 11px(그 Play의 언어)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local DailyRewardConfig = require(ReplicatedStorage.Shared.Config.DailyRewardConfig)
local RewardLogic = require(ReplicatedStorage.Shared.RewardLogic)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local UI = script.Parent.Parent.UI
local Store = require(UI.Store)
local TextMinimum = require(UI.TextMinimum)
local BlockingQueueLogic = require(UI.Logic.BlockingQueueLogic)
local L = require(UI.Logic.DailyRewardWindowLogic)
local PetWindowLogic = require(UI.Logic.PetWindowLogic)
local DailyRewardWindow = require(UI.Screens.Overlay.DailyRewardWindow)
local DailyIcon = require(UI.Screens.Hud.DailyIcon)

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

local function daily(canClaim: boolean, claimedToday: boolean, day: number, streak: number, secs: number?, today: number?, at: number?): any
	return { canClaim = canClaim, claimedToday = claimedToday, day = day, streak = streak, secondsToReset = secs or 3600, today = today or 20758,
		receivedAt = at or 0 }
end

-- 1. 칸 · 표시 값(서버 원본) ----------------------------------------------------------------------------------
do
	local c = L.cells(daily(true, false, 1, 0), 9)
	check("처음: 7칸 · 1일 오늘 · 나머지 future · 받은 칸 0", #c == 7 and c[1].state == "today" and c[2].state == "future" and c[7].state == "future")
	check("칸 글자: '1일' · 힘 포션 이름 · 개수(Config 값)", c[1].dayText == Locale.t("daily.day", { n = 1 }) and c[1].name == Names.boost("strength")
		and c[1].amount == Locale.t("daily.reward.count", { count = DailyRewardConfig.DAYS[1][1].count }))
	check("블럭스 칸 = 최고층(PlayerState maxStage 9) 1회 보상 × k — 서버가 주는 식과 같다", c[2].name == Locale.t("daily.reward.blox")
		and c[2].amount == Formatter.format(RewardLogic.bloxAmount(9, DailyRewardConfig.DAYS[2][1].k :: number)))
	local lim = c[7]
	check("7일째: 리미티드 펫 이름 · 희귀도 '리미티드' · 색 tier6", lim.isPet and lim.name == Names.pet(PetConfig.LIMITED_IDS[1])
		and lim.amount == Locale.t("rarity.limited") and lim.rarityTier == 6 and PetWindowLogic.rarityTier(PetConfig.LIMITED_RARITY) == 6)
	local mid = L.cells(daily(true, false, 4, 3), 9)
	check("연속 3일 뒤: 1 ~ 3 받음('받음') · 4 오늘", mid[1].state == "claimed" and mid[3].state == "claimed" and mid[4].state == "today"
		and mid[1].amount == Locale.t("daily.claimed"))
	local done = L.cells(daily(false, true, 4, 4), 9)
	check("오늘 받음: 1 ~ 4 받음 · 오늘 칸 없음 · 버튼 '내일 또' 꺼짐", done[4].state == "claimed" and done[5].state == "future"
		and not L.button(daily(false, true, 4, 4), false).enabled and L.button(daily(false, true, 4, 4), false).text == Locale.t("daily.comeBack"))
	check("받을 수 있으면 버튼 켜짐 · 대기 중이면 꺼짐", L.button(daily(true, false, 1, 0), false).enabled and not L.button(daily(true, false, 1, 0), true).enabled)
	check("다음 보상까지: 서버 남은 초 − 받은 뒤 지난 초 → HH:MM", L.timerText(daily(true, false, 1, 0, 3 * 3600 + 120, 0, 10), 70)
		== Locale.t("daily.next", { time = "03:01" }) and L.secondsLeft(daily(true, false, 1, 0, 5, 0, 0), 100) == 0)
	check("사유: storage_full → '펫 보관함을 한 칸 비우세요' · already_claimed · 모르는 것", L.reasonText("storage_full") == Locale.t("daily.reason.storage_full")
		and L.reasonText("already_claimed") == Locale.t("daily.reason.already_claimed") and L.reasonText("zzz") == Locale.t("daily.reason.failed")
		and L.resultText({ ok = true, reason = "", day = 3 }) == Locale.t("daily.result.ok", { n = 3 }))
end

-- 2. 자동 등장 · 배지 · 큐 순서 -----------------------------------------------------------------------------------
do
	local d = daily(true, false, 2, 1)
	check("자동 등장: 안내 진행 중이면 안 뜬다(안내가 끝난 뒤 — D5)", not L.shouldAutoShow(d, { step = 2, done = false }, false, nil))
	check("자동 등장: 안내 끝 · 런 아님 · 아직 안 띄움 → 뜬다", L.shouldAutoShow(d, { step = 5, done = true }, false, nil))
	check("자동 등장: 런 중이면 미룬다 · 같은 일 번호로 이미 띄웠으면 안 뜬다 · 새 날이면 다시", not L.shouldAutoShow(d, { done = true }, true, nil)
		and not L.shouldAutoShow(d, { done = true }, false, 20758) and L.shouldAutoShow(daily(true, false, 1, 0, 3600, 20759), { done = true }, false, 20758))
	check("자동 등장: 받을 게 없거나 첫 상태 전(today 0)이면 안 뜬다", not L.shouldAutoShow(daily(false, true, 2, 2), { done = true }, false, nil)
		and not L.shouldAutoShow(daily(true, false, 1, 0, 0, 0), { done = true }, false, nil))
	check("큐 우선순위: 일일 보상(3)이 뽑기 결과(4)보다 먼저 · 2번(첫 접속 안내)은 띠로 바뀌었다", BlockingQueueLogic.PRIORITY.dailyReward
		< BlockingQueueLogic.PRIORITY.rollResult)
	local store = Store.new()
	store.setSource(function(setter)
		setter("daily", daily(true, false, 1, 0))
	end)
	local pressed = 0
	local icon = DailyIcon.create({ store = store, top = 0.1, onPress = function()
		pressed += 1
	end })
	check("배지: 받을 게 있으면 보인다 · 수령 노랑 · '!'", icon._debug.badge.Visible and icon._debug.badge.BackgroundColor3 == UiTheme.Colors.cashout.base
		and icon._debug.badgeLabel.Text == Locale.t("hud.daily.badge"))
	store.setSource(function(setter)
		setter("daily", daily(false, true, 1, 1))
	end)
	icon._debug.press()
	check("배지: 받은 뒤 사라진다 · 누르면 창 열기 한 번", not icon._debug.badge.Visible and pressed == 1)
	check("아이콘: 좌측 레일 안 · Scale만", icon.root.Position.X.Offset == 0 and icon.root.Size.Y.Offset == 0
		and icon.root.Position.X.Scale + icon.root.Size.X.Scale <= 0.2 + 1e-6)
	icon.root:Destroy()
end

-- 3. 창 — 요청 한 번만 · 결과 문구 · 칸 표시 ---------------------------------------------------------------------
do
	local store = Store.new()
	store.setSource(function(setter)
		setter("maxStage", 9)
		setter("daily", daily(true, false, 7, 6))
	end)
	local clock = 100
	local sent = 0
	local w = DailyRewardWindow.create({ store = store, sendClaim = function()
		sent += 1
	end, now = function()
		return clock
	end })
	w.show()
	check("창: 7일째 칸 이름 = 리미티드 펫 · 희귀도 색 · 오늘 칸 노랑 테두리", w._debug.cells[7].name.Text == Names.pet(PetConfig.LIMITED_IDS[1])
		and w._debug.cells[7].name.TextColor3 == UiTheme.rarityColor(6) and w._debug.cells[7].stroke.Color == UiTheme.Colors.cashout.base)
	w._debug.press()
	w._debug.press()
	check("받기 두 번 눌러도 요청 1건(대기 중)", sent == 1)
	w.onResult({ ok = false, reason = "storage_full", day = 0 })
	check("보관함 가득 → '펫 보관함을 한 칸 비우세요' · 버튼 다시 켜짐", w._debug.status.Text == Locale.t("daily.reason.storage_full")
		and w._debug.claimLabel.Text == Locale.t("daily.claim"))
	w._debug.press()
	check("결과 뒤 다시 누르면 요청 2건", sent == 2)
	w.onResult({ ok = true, reason = "", day = 7 })
	store.setSource(function(setter)
		setter("daily", daily(false, true, 7, 7))
	end)
	check("받은 뒤: 상태 문구 '7일째' · 7칸 다 받음 · 버튼 '내일 또'", w._debug.status.Text == Locale.t("daily.result.ok", { n = 7 })
		and w._debug.cells[7].amount.Text == Locale.t("daily.claimed") and w._debug.claimLabel.Text == Locale.t("daily.comeBack"))
	w.hide()
	check("닫으면 막 · 판이 숨는다", not w._debug.panel.Visible and not w.isShown())
	w.root:Destroy()
end

-- 4. 새 문장 en · ko ------------------------------------------------------------------------------------------
do
	local keys = { "daily.title", "daily.day", "daily.claim", "daily.claimed", "daily.comeBack", "daily.close", "daily.next", "daily.reward.blox",
		"daily.reward.count", "daily.result.ok", "daily.reason.storage_full", "daily.reason.already_claimed", "daily.reason.failed", "hud.daily",
		"hud.daily.badge", "rarity.limited", "pet.name.limited_dawn" }
	local missing = {}
	for _, key in ipairs(keys) do
		local e = (Strings.Entries :: any)[key]
		if type(e) ~= "table" or type(e.en) ~= "string" or e.en == "" or type(e.ko) ~= "string" or e.ko == "" then
			table.insert(missing, key)
		end
	end
	check("새 문장(일일 보상 · 아이콘 · 리미티드) en · ko 둘 다", #missing == 0, table.concat(missing, ", "))
end

-- 5. 폰 틀 705×338 — 창 · 아이콘 넘침 0 · 11px(그 Play의 언어) --------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "DailyPhoneFit"
	gui.ResetOnSpawn = false
	gui.AutoLocalize = false -- K10
	local phone = Instance.new("Frame")
	phone.Size = UDim2.fromOffset(705, 338) -- 테스트 틀만 Offset
	phone.BackgroundTransparency = 1
	phone.Parent = gui
	TextMinimum.attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local function measure(root: Instance): (number, number, string)
		local minH, bad, badText = math.huge, 0, ""
		for _, obj in ipairs(root:GetDescendants()) do
			if obj:IsA("TextLabel") and obj.Text ~= "" then
				local visible = true
				local node: Instance? = obj
				while node ~= nil and node ~= gui do
					if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
						visible = false
						break
					end
					node = node.Parent
				end
				if visible then
					minH = math.min(minH, obj.AbsoluteSize.Y)
					if not obj.TextFits or obj.AbsoluteSize.Y < TextScale.MIN_TEXT_PX - 0.5 then
						bad += 1
						badText = obj.Name .. "(" .. obj.Text .. ")"
					end
				end
			end
		end
		return minH, bad, badText
	end

	local store = Store.new()
	store.setSource(function(setter)
		setter("maxStage", 25) -- 가장 큰 블럭스 글자
		setter("daily", daily(true, false, 4, 3, 86399))
	end)
	local w = DailyRewardWindow.create({ store = store, sendClaim = function() end })
	w.root.Parent = phone
	w.show()
	require(script.Parent.Parent.UI.Components.Fx).finishAll() -- 등장 연출(지시서 #25 U2)을 끝 상태로 보내고 잰다
	w.onResult({ ok = false, reason = "storage_full", day = 0 }) -- 가장 긴 사유 문구
	task.wait()
	task.wait()
	local h1, b1, t1 = measure(w.root)
	check(string.format("폰: 일일 보상 창 넘침 0 · 최소 %.1fpx ≥ 11", h1), b1 == 0 and h1 >= TextScale.MIN_TEXT_PX - 0.5, t1)
	local icon = DailyIcon.create({ store = store, top = 0.15 })
	icon.root.Parent = phone
	task.wait()
	task.wait()
	local h2, b2, t2 = measure(icon.root)
	check(string.format("폰: 아이콘 라벨 · 배지 넘침 0 · 최소 %.1fpx ≥ 11", h2), b2 == 0 and h2 >= TextScale.MIN_TEXT_PX - 0.5, t2)
	print(string.format("[DailyRewardWindowTests] 폰 705×338(%s): 창 최소 %.1fpx · 아이콘 최소 %.1fpx · 칸 %.0fx%.0f", Locale.current(), h1, h2,
		w._debug.cells[1].frame.AbsoluteSize.X, w._debug.cells[1].frame.AbsoluteSize.Y))
	gui:Destroy()
end

print(string.format("[DailyRewardWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[DailyRewardWindowTests] %d test(s) failed", failed))
end

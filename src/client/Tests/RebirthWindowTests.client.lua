--!strict
-- 환생 창 검증 (Phase 6 지시서 #5): 표시 값(서버와 같은 함수) · 사유 문구 · 확인 단계 없이는
-- 요청이 나가지 않음 · 잠김 · 창 규격. 실물 싱글톤이 아니라 Store.new()로 굴린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Store = require(script.Parent.Parent.UI.Store)
local RebirthWindowLogic = require(script.Parent.Parent.UI.Logic.RebirthWindowLogic)
local RebirthWindow = require(script.Parent.Parent.UI.Screens.Window.RebirthWindow)

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

local COST = RebirthConfig.BLOX_PER_REBIRTH

-- 1. 표시 값 ---------------------------------------------------------------------------------
do
	local blox = BigNum.fromNumber(COST * 2 + 345)
	local v = RebirthWindowLogic.compute(blox, BigNum.fromNumber(4))
	check("값: 얻는 배수 = 서버 함수(getGainedRebirths)", BigNum.eq(v.gained, RebirthConfig.getGainedRebirths(blox)))
	check("값: 얻는 배수 2", BigNum.eq(v.gained, BigNum.fromNumber(2)))
	check("값: 버려지는 양 = 나머지", BigNum.eq(v.wasted, BigNum.fromNumber(345)), BigNum.tostring(v.wasted))
	check("값: 가능", v.canRebirth and v.lockReason == nil)
	check("값: 지금 배수 = StrengthMultiplier", BigNum.eq(v.multiplierNow, StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(4) })))
	check("값: 환생 후 배수 = 배수 + 얻는 배수", BigNum.eq(v.multiplierAfter, StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(6) })))

	local low = RebirthWindowLogic.compute(BigNum.fromNumber(COST - 1), BigNum.new(0, 0))
	check("값: 1000 미만이면 잠김 + 사유 코드", not low.canRebirth and low.lockReason == "not_enough_blox")
	check("값: 잠겨도 버려지는 양은 전액", BigNum.eq(low.wasted, BigNum.fromNumber(COST - 1)))

	local huge = RebirthWindowLogic.compute(BigNum.new(7, 40), BigNum.new(0, 0))
	check("값: 아주 큰 블럭스에서도 버려지는 양이 음수가 아니다", huge.wasted.m >= 0)
end

-- 2. 사유 문구 ---------------------------------------------------------------------------------
do
	local generic = RebirthWindowLogic.reasonText("???")
	check("문구: 블럭스 부족은 비용을 Config에서", string.find(RebirthWindowLogic.reasonText("not_enough_blox"), Formatter.format(BigNum.fromNumber(COST)), 1, true) ~= nil)
	check("문구: 부분 실패는 일반 실패와 다르다", RebirthWindowLogic.reasonText("partial_failure") ~= generic)
	check("문구: 빈도 상한 문구가 있다", RebirthWindowLogic.reasonText("rate_limited") ~= generic)
	check("문구: 모르는 코드는 일반 문구", generic ~= "")
end

-- 3. 확인 단계 ---------------------------------------------------------------------------------
do
	local c = RebirthWindowLogic.newConfirm()
	check("확인: 첫 누름은 확인 요청일 뿐", c.press(0, true) == "askConfirm")
	check("확인: 창 안 두 번째 누름에만 send", c.press(1, true) == "send")
	check("확인: send 뒤에는 다시 처음부터", c.press(2, true) == "askConfirm")
	check("확인: 시간이 지나면 다시 확인 요청", c.press(2 + RebirthWindowLogic.CONFIRM_WINDOW_SEC + 0.1, true) == "askConfirm")
	c.cancel()
	check("확인: 취소하면 다음 누름은 확인 요청", c.press(20, true) == "askConfirm")
	check("확인: 잠겨 있으면 locked", c.press(20.5, false) == "locked")
	check("확인: locked 뒤에도 바로 send 되지 않는다", c.press(21, true) == "askConfirm")
end

check("목록: 초기화 목록에 패드가 있다", table.find(RebirthWindowLogic.RESETS, Locale.t("rebirth.reset.pad")) ~= nil
	and string.find(Locale.tFor("ko", "rebirth.reset.pad"), "패드", 1, true) ~= nil and string.find(Locale.tFor("en", "rebirth.reset.pad"), "Pad", 1, true) ~= nil)

-- 4. 창 --------------------------------------------------------------------------------------
check("목록: 남는 것에 상점 업그레이드가 있다(환생은 업그레이드를 건드리지 않는다 — 지시서 #7)", RebirthWindowLogic.KEEPS == Locale.t("rebirth.keeps") and string.find(Locale.tFor("ko", "rebirth.keeps"), "업그레이드", 1, true) ~= nil and string.find(Locale.tFor("en", "rebirth.keeps"), "Upgrade", 1, true) ~= nil)
check("값: 버려지는 양 = RebirthConfig.getLeftover(시뮬레이터 S5 예산과 같은 원본)", BigNum.eq(RebirthWindowLogic.compute(BigNum.fromNumber(2345), BigNum.new(0, 0)).wasted,
	RebirthConfig.getLeftover(BigNum.fromNumber(2345))))

local function makeWindow(bloxValue: number)
	local store = Store.new()
	local set: (any, any) -> () = function() end
	store.setSource(function(setter)
		set = setter
		setter("blox", BigNum.fromNumber(bloxValue))
		setter("rebirths", BigNum.fromNumber(2))
	end)
	local clock = 0
	local w = { sends = 0, closes = 0, shops = 0 }
	local handle = RebirthWindow.create({
		store = store,
		sendRequest = function()
			w.sends += 1
		end,
		onClose = function()
			w.closes += 1
		end,
		openShop = function()
			w.shops += 1
		end,
		now = function()
			return clock
		end,
	})
	local function advance(sec: number)
		clock += sec
	end
	return handle, w, advance, set
end

do
	local handle, w, advance, set = makeWindow(COST * 3 + 10)
	check("창: 작은 창 60% × 70%", math.abs(handle.root.Size.X.Scale - 0.6) < 1e-6 and math.abs(handle.root.Size.Y.Scale - 0.7) < 1e-6)
	check("창: 보유 블럭스 표시", handle._debug.labels.bloxValue.Text == Formatter.format(BigNum.fromNumber(COST * 3 + 10)))
	check("창: 버려지는 양 표시", handle._debug.labels.wastedValue.Text == Formatter.format(BigNum.fromNumber(10)))
	check("창: 버튼이 켜져 있다", not handle._debug.button.isDisabled())
	-- 버튼 그림이 패널 배경층 밑에 깔리면 안 보인다(2026-10-22 Play에서 X 버튼이 사라졌다).
	local function minZ(root: Instance): number
		local m = math.huge
		for _, obj in ipairs(root:GetDescendants()) do
			if obj:IsA("GuiObject") then
				m = math.min(m, (obj :: GuiObject).ZIndex)
			end
		end
		return m
	end
	local panelBgMax = 0
	for _, child in ipairs(handle.root:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Body" and child.Name ~= "Close" then
			for _, obj in ipairs({ child, table.unpack(child:GetDescendants()) }) do
				if obj:IsA("GuiObject") then
					panelBgMax = math.max(panelBgMax, (obj :: GuiObject).ZIndex)
				end
			end
		end
	end
	local closeRoot = handle.root:FindFirstChild("Close")
	check("창: X 버튼 그림이 패널 배경보다 위", closeRoot ~= nil and minZ(closeRoot :: Instance) > panelBgMax,
		string.format("close min %s / bg max %s", tostring(closeRoot and minZ(closeRoot)), tostring(panelBgMax)))
	check("창: 환생 버튼 그림이 패널 배경보다 위", minZ(handle._debug.button.root) > panelBgMax)

	handle._debug.press()
	check("창: 한 번 누름으로는 요청이 나가지 않는다", w.sends == 0)
	check("창: 확인 중 문구 + 취소 버튼", handle._debug.labels.button.Text == RebirthWindow.CONFIRM_TEXT and handle._debug.cancelButton.root.Visible)
	advance(1)
	handle._debug.press()
	check("창: 확인 뒤 두 번째 누름에 요청 1회", w.sends == 1)

	handle._debug.press()
	advance(1)
	handle._debug.cancel()
	advance(0.5)
	handle._debug.press()
	check("창: 취소하면 다시 두 번 눌러야 한다", w.sends == 1)
	advance(RebirthWindowLogic.CONFIRM_WINDOW_SEC + 1)
	handle._debug.press()
	check("창: 확인 시간이 지나면 다시 두 번 눌러야 한다", w.sends == 1)

	handle.onResult({ ok = true, reason = "", gained = { m = 3, e = 0 } })
	check("창: 성공 결과 문구", handle._debug.labels.status.Text == RebirthWindow.successText(BigNum.new(3, 0)))
	handle.onResult({ ok = false, reason = "rate_limited", gained = { m = 0, e = 0 } })
	check("창: 거부 결과는 사유 문구", handle._debug.labels.status.Text == RebirthWindowLogic.reasonText("rate_limited"))
	-- 지시서 #18 AA9: "자동 진행 중" 거부 문구는 자동이 꺼지면 지워진다(다른 거부 문구는 그대로)
	set("autoAdvance", { active = true, target = 8, safeFloor = 8, runs = 1, maxTarget = 25 })
	handle.onResult({ ok = false, reason = "auto_active", gained = { m = 0, e = 0 } })
	local shownOn = handle._debug.labels.status.Text == RebirthWindowLogic.reasonText("auto_active")
	set("autoAdvance", { active = false, target = 0, safeFloor = 8, runs = 0, maxTarget = 25 })
	check("AA9: 자동 중 거부 문구 → 자동이 꺼지면 지워진다", shownOn and handle._debug.labels.status.Text ~= RebirthWindowLogic.reasonText("auto_active"))

	handle._debug.close()
	check("창: X는 onClose를 부른다", w.closes == 1)

	-- 상점 안내 + 상점 버튼 (지시서 #7)
	check("상점: 안내 문구", handle._debug.labels.shopHint.Text == RebirthWindowLogic.SHOP_HINT)
	check("상점: 버튼은 회색(중립)이고 켜져 있다", handle._debug.shopButton.root.Name == "ShopButton" and not handle._debug.shopButton.isDisabled())
	local hintBottom = handle._debug.labels.shopHint.Position.Y.Scale + handle._debug.labels.shopHint.Size.Y.Scale
	check("상점: 안내 줄이 버려지는 양 아래 · 초기화 목록 위", handle._debug.labels.shopHint.Position.Y.Scale >= handle._debug.labels.wastedValue.Position.Y.Scale + handle._debug.labels.wastedValue.Size.Y.Scale - 1e-6
		and hintBottom <= handle._debug.labels.resetsHeader.Position.Y.Scale + 1e-6)
	check("상점: 남는 것 줄이 상태 줄과 겹치지 않는다", handle._debug.labels.keeps.Position.Y.Scale + handle._debug.labels.keeps.Size.Y.Scale <= handle._debug.labels.status.Position.Y.Scale + 1e-6)
	check("상점: 상태 줄이 버튼과 겹치지 않는다", handle._debug.labels.status.Position.Y.Scale + handle._debug.labels.status.Size.Y.Scale <= handle._debug.button.root.Position.Y.Scale + 1e-6)
	handle._debug.press() -- 확인 중으로 만든 뒤
	handle._debug.openShop()
	check("상점: 버튼을 누르면 상점을 연다(1회) · 환생 요청은 안 나간다", w.shops == 1 and w.sends == 1)
	check("상점: 확인 중이던 환생은 취소된다", handle._debug.labels.button.Text == RebirthWindow.BUTTON_TEXT)
	handle.root:Destroy()
end

do
	local handle, w, advance = makeWindow(COST - 1)
	check("잠김: 버튼이 회색 잠김", handle._debug.button.isDisabled())
	check("잠김: 이유 문구", handle._debug.labels.status.Text == RebirthWindowLogic.reasonText("not_enough_blox"))
	handle._debug.press()
	advance(0.5)
	handle._debug.press()
	check("잠김: 두 번 눌러도 요청이 나가지 않는다", w.sends == 0)
	handle.root:Destroy()
end

-- 5. 화면 정리 (지시서 #8) -------------------------------------------------------------------------
do
	local lines = RebirthWindowLogic.resetLines()
	check("목록: 초기화 목록을 두 개씩 묶어 줄 수가 절반(올림)", #lines == math.ceil(#RebirthWindowLogic.RESETS / 2), tostring(#lines))
	check("목록: 묶은 줄에 항목이 다 들어 있다", (function()
		local all = table.concat(lines, " ")
		for _, item in ipairs(RebirthWindowLogic.RESETS) do
			if string.find(all, item, 1, true) == nil then
				return false
			end
		end
		return true
	end)())

	local withWaste = makeWindow(COST * 3 + 10)
	check("버려지는 양 > 0 이면 빨간 강조", withWaste._debug.labels.wastedValue.BackgroundTransparency == 0)
	local line = withWaste._debug.labels.reset1
	check("목록 줄 높이가 예전(본문의 4.5%)보다 크다", line ~= nil and line.Size.Y.Scale > 0.045, line and tostring(line.Size.Y.Scale) or "nil")
	withWaste.root:Destroy()
	local noWaste = makeWindow(COST * 3)
	check("버려지는 양 0 이면 빨간 강조를 끈다", noWaste._debug.labels.wastedValue.BackgroundTransparency == 1
		and noWaste._debug.labels.wastedValue.Text == Formatter.format(BigNum.new(0, 0)))
	noWaste.root:Destroy()
end

print(string.format("[RebirthWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RebirthWindowTests] %d test(s) failed", failed))
end

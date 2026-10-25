--!strict
-- 타이틀 창 · 토스트 검증 (Phase 7 지시서 #10 5단계): 표시 값(TitleConfig · 서버 원본) · 잠김 사유 · 요청이 한 번만 나가는가 ·
-- 토스트 큐(3개 상한 · 순서) · 희귀도 색이 쓰인다. 실물 싱글톤이 아니라 Store.new()로 굴린다. 기대값은 Config에서 읽는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Store = require(script.Parent.Parent.UI.Store)
local Layout = require(script.Parent.Parent.UI.Layout)
local TitleWindowLogic = require(script.Parent.Parent.UI.Logic.TitleWindowLogic)
local ToastLogic = require(script.Parent.Parent.UI.Logic.ToastLogic)
local TitleWindow = require(script.Parent.Parent.UI.Screens.Window.TitleWindow)
local ToastStack = require(script.Parent.Parent.UI.Screens.Overlay.ToastStack)
local RebirthNotice = require(script.Parent.Parent.UI.Screens.Overlay.RebirthNotice)
local RollOdds = require(ReplicatedStorage.Shared.RollOdds)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

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

local T = TitleConfig.Titles
local N = #T

-- 1. 표시 값 ------------------------------------------------------------------------------------------
do
	local rows = TitleWindowLogic.rows({ owned = {}, equipped = "", autoRoll = false }, {})
	check("값: 줄 수 = 칭호 수", #rows == N)
	check("값: 위가 가장 귀한 등급 (희귀도 높은 순)", rows[1].id == T[N].id and rows[1].tier == N and rows[N].id == T[1].id and rows[N].tier == 1)
	check("값: 배수 문구 = TitleConfig mult", rows[1].multText == TitleWindowLogic.multText(T[N].mult)
		and string.find(rows[1].multText, string.format("%.2f", T[N].mult), 1, true) ~= nil, rows[1].multText)
	local texts, dec = RollOdds.percentages(RollOdds.distribution(T, 1))
	check("값: 확률 칸 = 실제 등장 확률(RollOdds 분포 · 표시) — 폴백도 %", rows[N].chanceText == texts[1] and rows[1].chanceText == texts[N],
		rows[N].chanceText .. " / " .. rows[1].chanceText)
	local units = 0
	for _, r in ipairs(rows) do
		units += math.floor((tonumber((string.gsub(r.chanceText, "%%", ""))) :: number) * 10 ^ dec + 0.5)
	end
	check("값: 6줄 확률 합 = 정확히 100% (P3)", units == 100 * 10 ^ dec)

	local L = 9
	local luck = UpgradeConfig.getEffect("titleLuck", L)
	local lucky = TitleWindowLogic.rows({ owned = {}, equipped = "", autoRoll = false }, { titleLuck = L })
	local luckyTexts = RollOdds.percentages(RollOdds.distribution(T, luck))
	check("값: 현재 확률 = titleLuck 효과가 반영된 실제 확률", lucky[1].chanceText == luckyTexts[N], lucky[1].chanceText)
	check("값: 행운 문구 = '행운 ×N 적용'", TitleWindowLogic.luckText({ titleLuck = L }) == RollOdds.luckText(luck))
	check("값: 행운 표가 깨져도 0레벨", TitleWindowLogic.luckOf(nil) == UpgradeConfig.getEffect("titleLuck", 0) and TitleWindowLogic.luckOf({ titleLuck = -2 }) == UpgradeConfig.getEffect("titleLuck", 0))

	check("버튼 문구: 비용 = TitleConfig.ROLL_COST", string.find(TitleWindowLogic.rollButtonText(), Formatter.format(TitleConfig.ROLL_COST), 1, true) ~= nil)
	local perSec = BigNum.div(TitleConfig.ROLL_COST, BigNum.fromNumber(TitleConfig.ROLL_INTERVAL_SEC))
	check("안내: 초당 비용 = 비용 ÷ 간격", string.find(TitleWindowLogic.autoNoteText(), Formatter.format(perSec), 1, true) ~= nil, TitleWindowLogic.autoNoteText())
end

-- 2. 보유 · 장착 · 잠김 ------------------------------------------------------------------------------------
do
	local rows = TitleWindowLogic.rows({ owned = { T[2].id, T[4].id }, equipped = T[4].id, autoRoll = false }, {})
	local function rowOf(id: string)
		for _, r in ipairs(rows) do
			if r.id == id then
				return r
			end
		end
		return nil
	end
	local eq, own, none = rowOf(T[4].id) :: any, rowOf(T[2].id) :: any, rowOf(T[N].id) :: any
	check("장착 중: 버튼 '장착 중' · 못 누름", eq.equipped and eq.buttonText == TitleWindowLogic.EQUIPPED_TEXT and not eq.canEquip)
	check("보유: 버튼 '장착' · 누를 수 있음", own.owned and not own.equipped and own.buttonText == TitleWindowLogic.EQUIP_TEXT and own.canEquip)
	check("미보유: 잠김 · 문구", not none.owned and not none.canEquip and none.statusText == TitleWindowLogic.NOT_OWNED_TEXT)
	local ghost = TitleWindowLogic.rows({ owned = { "ghost" }, equipped = "ghost", autoRoll = false }, {})
	local anyEquipped = false
	for _, r in ipairs(ghost) do
		anyEquipped = anyEquipped or r.equipped
	end
	check("모르는 id는 무시", not anyEquipped)

	local cost = TitleConfig.ROLL_COST
	local poor = TitleWindowLogic.rollState(BigNum.sub(cost, BigNum.fromNumber(1)))
	check("잠김: 블럭스 < 비용 → 못 굴림 + 사유", not poor.canRoll and poor.footText == TitleWindowLogic.reasonText("insufficient_blox"))
	check("잠김: 딱 맞으면 굴림 (서버와 같은 경계)", TitleWindowLogic.rollState(cost).canRoll)
	check("잠김: 블럭스가 깨지면 못 굴림", not TitleWindowLogic.rollState(nil).canRoll)

	local generic = TitleWindowLogic.reasonText("???")
	for code in pairs(TitleWindowLogic.REASONS) do
		check("문구: " .. code, TitleWindowLogic.reasonText(code) ~= generic)
	end
end

-- 3. 결과 문구 · 토스트 판정 ----------------------------------------------------------------------------------
do
	local id = T[3].id
	check("결과: 새 칭호", TitleWindowLogic.resultText({ action = "roll", ok = true, reason = "", titleId = id, isNew = true, equipped = true }) == Locale.t("title.result.new", { name = Names.title(T[3].id) }))
	check("결과: 중복", string.find(TitleWindowLogic.resultText({ action = "roll", ok = true, reason = "", titleId = id, isNew = false, equipped = false }) or "", Locale.t("title.result.dup", { name = "" }), 1, true) ~= nil)
	check("결과: 장착", TitleWindowLogic.resultText({ action = "equip", ok = true, reason = "", titleId = id, isNew = false, equipped = true }) == Locale.t("common.result.equip", { name = Names.title(T[3].id) }))
	check("결과: 거부는 사유 문구", TitleWindowLogic.resultText({ action = "roll", ok = false, reason = "rate_limited", titleId = "", isNew = false, equipped = false }) == TitleWindowLogic.reasonText("rate_limited"))
	check("결과: 자동 롤 토글 성공은 문구 없음", TitleWindowLogic.resultText({ action = "setAuto", ok = true, reason = "", titleId = "", isNew = false, equipped = false }) == nil)

	local toast = TitleWindowLogic.toastFor(T[N].id)
	check("토스트: '새 칭호! 이름 (힘·블럭스 ×N)' · 희귀도 단계", toast ~= nil and (toast :: any).tier == N
		and (toast :: any).text == Locale.t("title.toast", { name = Names.title(T[N].id), mult = TitleWindowLogic.multText(T[N].mult) }))
	check("토스트: 모르는 id는 없음", TitleWindowLogic.toastFor("ghost") == nil)
	check("토스트 판정: 수동 롤 신규 · 자동 롤 신규만", TitleWindowLogic.shouldToast({ action = "roll", ok = true, isNew = true })
		and TitleWindowLogic.shouldToast({ action = "autoRoll", ok = true, isNew = true })
		and not TitleWindowLogic.shouldToast({ action = "roll", ok = true, isNew = false })
		and not TitleWindowLogic.shouldToast({ action = "roll", ok = false, isNew = true })
		and not TitleWindowLogic.shouldToast({ action = "equip", ok = true, isNew = true }))
end

-- 4. 창 — 요청 한 번만 · 잠김 · 토글 두 채널 · 희귀도 색 --------------------------------------------------------
local function makeWindow(blox: BigNum.BigNumber, titles: any, levels: { [string]: number }?)
	local store = Store.new()
	local setter: any = nil
	store.setSource(function(s)
		setter = s
		s("blox", blox)
		s("titles", titles)
		if levels ~= nil then
			s("upgrades", levels)
		end
	end)
	local clock = 0
	local w = { sends = {} :: { any }, closes = 0 }
	local handle = TitleWindow.create({
		store = store,
		sendRequest = function(payload)
			table.insert(w.sends, payload)
		end,
		onClose = function()
			w.closes += 1
		end,
		now = function()
			return clock
		end,
	})
	return handle, w, function(sec: number)
		clock += sec
	end, function(key: string, value: any)
		setter(key, value)
	end
end

do
	local rich = BigNum.new(1, 6)
	local handle, w, advance, set = makeWindow(rich, { owned = { T[2].id }, equipped = "", autoRoll = false })
	local d = handle._debug
	d.pressRoll()
	d.pressRoll()
	check("롤: 결과 대기 중 두 번째 누름은 안 나간다", #w.sends == 1 and w.sends[1].action == "roll")
	check("롤: 대기 중 버튼 잠김", d.rollButton.isDisabled())
	handle.onResult({ action = "roll", ok = true, reason = "", titleId = T[2].id, isNew = false, equipped = false })
	check("롤: 결과가 와도 롤 간격 동안은 잠김 · 상태 문구", d.rollButton.isDisabled() and d.status.Text ~= "")
	d.pressRoll()
	check("롤: 롤 간격 안에 누르면 안 나간다 (서버 rate_limited를 미리 막는다)", #w.sends == 1)
	advance(TitleConfig.ROLL_INTERVAL_SEC + 0.01)
	handle.refresh()
	check("롤: 롤 간격이 지나면 풀린다", not d.rollButton.isDisabled())
	d.pressRoll()
	check("롤: 풀린 뒤 다시 누르면 나간다", #w.sends == 2)
	advance(TitleWindowLogic.PENDING_TIMEOUT_SEC + 0.1)
	d.pressRoll()
	check("롤: 결과가 안 와도 시간이 지나면 다시 나간다", #w.sends == 3)

	handle.onResult({ action = "autoRoll", ok = true, reason = "", titleId = T[3].id, isNew = true, equipped = false })
	check("자동 롤 알림은 창 상태 문구를 바꾸지 않는다 (토스트 몫)", string.find(d.status.Text, Names.title(T[3].id), 1, true) == nil)

	-- 장착
	d.pressEquip(T[N].id)
	check("장착: 미보유는 안 나간다", #w.sends == 3)
	d.pressEquip(T[2].id)
	check("장착: 보유는 equip 요청 1건", #w.sends == 4 and w.sends[4].action == "equip" and w.sends[4].titleId == T[2].id)

	-- 토글
	check("토글 꺼짐: 테두리 검정 · 글자 중립 기본", d.autoStroke.Color == Color3.new(0, 0, 0) and d.autoLabel.TextColor3 == UiTheme.Colors.neutral.base
		and d.autoLabel.Text == TitleWindowLogic.AUTO_OFF_TEXT)
	d.pressAuto()
	check("토글: 지금의 반대 값으로 setAuto 1건", #w.sends == 5 and w.sends[5].action == "setAuto" and w.sends[5].on == true)
	set("titles", { owned = { T[2].id }, equipped = "", autoRoll = true })
	task.wait() -- Store 구독 통지가 한 프레임 뒤일 수 있다(PlayerStateClientTests와 같다)
	handle.refresh()
	check("토글 켜짐: 테두리 노랑 · 글자 중립 밝음 (두 채널)", d.autoStroke.Color == UiTheme.Colors.cashout.base
		and d.autoLabel.TextColor3 == UiTheme.Colors.neutral.light and d.autoLabel.Text == TitleWindowLogic.AUTO_ON_TEXT)

	-- 희귀도 색
	local colorsOk = true
	for i, parts in ipairs(d.rows) do
		local r = d.view()[i]
		if parts.name.TextColor3 ~= UiTheme.rarityColor(r.tier) then
			colorsOk = false
		end
	end
	check("이름 글자 = 희귀도 색", colorsOk)
	check("확률 표 위 '행운 ×N 적용' 줄", d.luckLine.Text == TitleWindowLogic.luckText(nil))
	check("창 크기 Offset 0 (Scale만)", handle.root.Size.X.Offset == 0 and handle.root.Size.Y.Offset == 0)
	handle.root:Destroy()
end

do
	local poor = BigNum.sub(TitleConfig.ROLL_COST, BigNum.fromNumber(1))
	local handle, w = makeWindow(poor, { owned = {}, equipped = "", autoRoll = false })
	handle._debug.pressRoll()
	check("잠김: 블럭스가 모자라면 회색 · 요청 없음 · 사유 문구", handle._debug.rollButton.isDisabled() and #w.sends == 0
		and handle._debug.rollFoot.Text == TitleWindowLogic.reasonText("insufficient_blox"))
	handle.root:Destroy()
end

-- 5. 토스트 큐 -------------------------------------------------------------------------------------------
do
	local q = ToastLogic.new() :: ToastLogic.Queue<string>
	for i = 1, ToastLogic.MAX_VISIBLE + 1 do
		q.push("t" .. i, 0)
	end
	local v = q.visible()
	check("큐: 최대 MAX_VISIBLE개만 보인다 · 넘친 것은 기다린다", #v == ToastLogic.MAX_VISIBLE and q.waiting() == 1)
	check("큐: 위에서부터 먼저 뜬 순서", v[1] == "t1" and v[#v] == "t" .. ToastLogic.MAX_VISIBLE)
	check("큐: 시간이 안 지나면 그대로", q.tick(ToastLogic.HOLD_SEC * 0.5) == false and #q.visible() == ToastLogic.MAX_VISIBLE)
	check("큐: 남은 시간 = 보유 시간 − 지난 시간", math.abs((q.nextExpiryIn(1) :: number) - (ToastLogic.HOLD_SEC - 1)) < 1e-9)
	check("큐: 시간이 지나면 바뀐다", q.tick(ToastLogic.HOLD_SEC) == true)
	local after = q.visible()
	check("큐: 같이 뜬 것은 같이 지고 기다리던 것이 올라온다", #after == 1 and after[1] == "t" .. (ToastLogic.MAX_VISIBLE + 1) and q.waiting() == 0)
	q.tick(ToastLogic.HOLD_SEC * 3)
	check("큐: 다 지면 빈다 · 남은 시간 없음", #q.visible() == 0 and q.nextExpiryIn(0) == nil)

	local q2 = ToastLogic.new() :: ToastLogic.Queue<string>
	q2.push("a", 0)
	q2.push("b", 1)
	q2.tick(ToastLogic.HOLD_SEC + 0.5)
	local left = q2.visible()
	check("큐: 오래된 것부터 사라진다", #left == 1 and left[1] == "b")
end

do
	local clock = 0
	local stack = ToastStack.create(function()
		return clock
	end)
	stack.push({ text = "x", tier = N })
	check("토스트 줄: 글자 = 희귀도 색 · 보임", stack._rows[1].Visible and stack._rows[1].TextColor3 == UiTheme.rarityColor(N))
	check("토스트 줄: 나머지 줄은 숨김", not stack._rows[2].Visible)
	local b = ToastStack.Bounds
	check("토스트 자리: 상단 정보 띠 안 · 중앙 금지 구역 밖", b.y1 <= Layout.TOP_HEIGHT and not Layout.overlapsCenterForbidden(b.x0, b.y0, b.x1, b.y1))
	check("토스트 자리: 오른쪽 가장자리 여백 안", b.x1 <= 1 - Layout.EDGE_MARGIN + 1e-9)
	local r = RebirthNotice.Bounds
	check("토스트 자리: 환생 안내와 겹치지 않는다", b.x0 >= r.x1)
	check("토스트: 알림층", stack.root.ZIndex >= 30)
	stack.root:Destroy()
end

print(string.format("[TitleWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TitleWindowTests] %d test(s) failed", failed))
end

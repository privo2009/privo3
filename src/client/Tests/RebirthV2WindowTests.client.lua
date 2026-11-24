--!strict
-- 새 경제 환생 창 검증(지시서 #30 — 플래그 ECONOMY_V2 뒤). 창에 economyV2 = true를 넣어 굴린다(전역 플래그는 건드리지 않는다).
-- 다음 환생 비용 · 지금 블럭스 · 부족하면 잠김 · ×이전 → ×이후(b^n) · 문구는 Strings 키 · 플래그 끔이면 지금 창 그대로.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
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

local REBIRTHS = 3
local COST = EconomyV2Logic.rebirthCost(REBIRTHS)

-- 1. 값(순수) -------------------------------------------------------------------------------------
do
	local low = RebirthWindowLogic.compute(BigNum.sub(COST, BigNum.new(1, 0)), BigNum.fromNumber(REBIRTHS), nil, true)
	check("값: 비용 미만이면 잠김 · 사유 코드", low.v2 and not low.canRebirth and low.lockReason == "not_enough_blox")
	check("값: 다음 비용 = EconomyV2Logic.rebirthCost(서버와 같은 함수)", low.cost ~= nil and BigNum.eq(low.cost :: any, COST))
	local ok = RebirthWindowLogic.compute(COST, BigNum.fromNumber(REBIRTHS), nil, true)
	check("값: 비용 이상이면 가능 · 버려지는 양 0", ok.canRebirth and ok.lockReason == nil and ok.wasted.m == 0)
	check("값: ×이전 → ×이후 = b^n → b^(n+1)", BigNum.eq(ok.multiplierNow, EconomyV2Logic.rebirthFactor(REBIRTHS))
		and BigNum.eq(ok.multiplierAfter, EconomyV2Logic.rebirthFactor(REBIRTHS + 1)))
	local off = RebirthWindowLogic.compute(COST, BigNum.fromNumber(REBIRTHS), nil, false)
	check("값: 끔이면 지금 규칙(1 + n · 비용 없음)", not off.v2 and off.cost == nil
		and BigNum.eq(off.multiplierNow, StrengthMultiplier.compute({ rebirths = BigNum.fromNumber(REBIRTHS), economyV2 = false })))
	check("문구: 부족 사유에 다음 비용", string.find(RebirthWindowLogic.reasonText("not_enough_blox", COST), Formatter.format(COST), 1, true) ~= nil)
	check("목록: 새 경제 첫 줄(블럭스)은 비용만 빠진다 · 나머지 줄은 같다", RebirthWindowLogic.RESETS_V2[1] == Locale.t("rebirth.v2.reset.blox")
		and RebirthWindowLogic.RESETS_V2[2] == RebirthWindowLogic.RESETS[2] and #RebirthWindowLogic.RESETS_V2 == #RebirthWindowLogic.RESETS)
	local keysOk = true
	for _, key in ipairs({ "rebirth.v2.cost", "rebirth.v2.gain", "rebirth.v2.gainValue", "rebirth.v2.success", "rebirth.v2.reason.not_enough_blox",
		"rebirth.v2.reset.blox", "rebirth.v2.keeps" }) do
		keysOk = keysOk and Locale.tFor("en", key) ~= key and Locale.tFor("ko", key) ~= key
	end
	check("문구: 새 키 7개 en · ko 둘 다 있다", keysOk)
end

-- 2. 창 -------------------------------------------------------------------------------------------
local function makeWindow(blox: BigNum.BigNumber, v2: boolean)
	local store = Store.new()
	store.setSource(function(setter)
		setter("blox", blox)
		setter("rebirths", BigNum.fromNumber(REBIRTHS))
	end)
	local sends = 0
	local handle = RebirthWindow.create({
		store = store,
		sendRequest = function()
			sends += 1
		end,
		onClose = function() end,
		now = function()
			return 0
		end,
		economyV2 = v2,
	})
	return handle, function()
		return sends
	end
end

do
	local have = BigNum.sub(COST, BigNum.new(1, 0))
	local h = makeWindow(have, true)
	local labels = h._debug.labels
	check("창: 지금 블럭스 · 다음 환생 비용 줄", labels.bloxValue.Text == Formatter.format(have) and labels.wastedName.Text == Locale.t("rebirth.v2.cost")
		and labels.wastedValue.Text == Formatter.format(COST))
	check("창: 부족하면 버튼 잠김 · 이유 문구(비용)", h._debug.button.isDisabled() and labels.status.Text == RebirthWindowLogic.reasonText("not_enough_blox", COST))
	check("창: 힘 배수 줄 ×이전 → ×이후", labels.gainName.Text == Locale.t("rebirth.v2.gain") and labels.gainValue.Text == Locale.t("rebirth.v2.gainValue", {
		before = Formatter.format(EconomyV2Logic.rebirthFactor(REBIRTHS)), after = Formatter.format(EconomyV2Logic.rebirthFactor(REBIRTHS + 1)) }))
	check("창: 남는 것 · 초기화 첫 줄이 새 경제 문구", labels.keeps.Text == RebirthWindowLogic.KEEPS_V2 and labels.reset1.Text == RebirthWindowLogic.resetLines(true)[1])
	check("창: 경고색 없음(비용 줄)", labels.wastedValue.BackgroundTransparency == 1)
	h.root:Destroy()

	local h2, sends = makeWindow(COST, true)
	check("창: 비용 이상이면 버튼 켜짐", not h2._debug.button.isDisabled())
	h2._debug.press()
	h2._debug.press()
	check("창: 확인 두 번에 요청 하나(지금 창과 같은 확인 단계)", sends() == 1)
	h2.onResult({ ok = true, reason = "", gained = BigNum.new(1, 0), total = BigNum.fromNumber(REBIRTHS + 1) })
	check("창: 성공 문구는 환생 수", h2._debug.labels.status.Text == Locale.t("rebirth.v2.success", { total = Formatter.format(BigNum.fromNumber(REBIRTHS + 1)) }))
	h2.root:Destroy()

	local h3 = makeWindow(COST, false)
	check("창: 끔이면 지금 창(얻는 배수 · 버려지는 양 줄)", h3._debug.labels.wastedName.Text == Locale.t("rebirth.wasted")
		and h3._debug.labels.gainName.Text == Locale.t("rebirth.gain") and h3._debug.labels.keeps.Text == RebirthWindowLogic.KEEPS)
	h3.root:Destroy()
end

print(string.format("[RebirthV2WindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RebirthV2WindowTests] %d test(s) failed", failed))
end

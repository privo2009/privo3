--!strict
-- 설정 창 · 아우라 파티클 방출량 검증 (지시서 #11 5단계 A7 · A8): 토글 요청 한 번만 · 지금의 반대 값 · 두 채널(테두리 · 밝기) ·
-- 거부 문구 · 방출량(등급별 · 숨기기 반영 · 내 아우라는 언제나 · 전체 합 상한).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Store = require(script.Parent.Parent.UI.Store)
local SettingsWindow = require(script.Parent.Parent.UI.Screens.Window.SettingsWindow)
local AuraRenderLogic = require(script.Parent.Parent.World.AuraRenderLogic)

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

-- 1. 설정 창 ---------------------------------------------------------------------------------------
do
	local store = Store.new()
	local setter: any = nil
	store.setSource(function(s)
		setter = s
		s("auras", { owned = {}, equipped = "", selectedPack = 1, hideOtherAuras = false, world = 1 })
	end)
	local clock = 0
	local sends: { any } = {}
	local h = SettingsWindow.create({
		store = store,
		sendRequest = function(p)
			table.insert(sends, p)
		end,
		onClose = function() end,
		now = function()
			return clock
		end,
	})
	local row = h._debug.rows[1]
	check("첫 항목: 다른 사람 아우라 숨기기", row.label.Text == Locale.t("settings.hideOtherAuras") and SettingsWindow.ROWS[1].key == "hideOtherAuras")
	check("꺼짐: 테두리 검정 · 글자 중립 기본", #row.strokes > 0 and row.strokes[1].Color == Color3.new(0, 0, 0)
		and row.buttonLabel.TextColor3 == UiTheme.Colors.neutral.base and row.buttonLabel.Text == SettingsWindow.OFF_TEXT)
	h._debug.press(1)
	h._debug.press(1)
	check("누르면 지금의 반대 값 1건 · 대기 중 두 번째는 안 나간다", #sends == 1 and sends[1].key == "hideOtherAuras" and sends[1].value == true)
	h.onResult({ ok = true, reason = "", key = "hideOtherAuras", value = true })
	setter("auras", { owned = {}, equipped = "", selectedPack = 1, hideOtherAuras = true, world = 1 })
	task.wait()
	h.refresh()
	check("켜짐: 테두리 노랑 · 글자 중립 밝음 (두 채널)", row.strokes[1].Color == UiTheme.Colors.cashout.base
		and row.buttonLabel.TextColor3 == UiTheme.Colors.neutral.light and row.buttonLabel.Text == SettingsWindow.ON_TEXT)
	h._debug.press(1)
	check("켜진 뒤 누르면 false", #sends == 2 and sends[2].value == false)
	h.onResult({ ok = false, reason = "rate_limited", key = "hideOtherAuras", value = false })
	check("거부 → 상태 문구", h._debug.status.Text ~= "")

	-- 둘째 줄: 다른 사람 펫 숨기기 (지시서 #12 E10)
	local pets = h._debug.rows[2]
	check("둘째 항목: 다른 사람 펫 숨기기 · 키 hideOtherPets", #SettingsWindow.ROWS == 2 and pets ~= nil and pets.label.Text == Locale.t("settings.hideOtherPets")
		and SettingsWindow.ROWS[2].key == "hideOtherPets" and pets.buttonLabel.Text == SettingsWindow.OFF_TEXT)
	h._debug.press(2)
	check("펫 숨기기: 지금의 반대 값 1건 · 아우라 줄 대기와 따로", #sends == 3 and sends[3].key == "hideOtherPets" and sends[3].value == true)
	h.onResult({ ok = true, reason = "", key = "hideOtherPets", value = true })
	setter("pets", { owned = {}, equipped = {}, slots = 2, storage = 50, hideOtherPets = true, world = 1 })
	task.wait()
	h.refresh()
	check("펫 숨기기 켜짐: 두 채널(테두리 노랑 · 글자 밝음) · 아우라 줄은 그대로", pets.strokes[1].Color == UiTheme.Colors.cashout.base
		and pets.buttonLabel.Text == SettingsWindow.ON_TEXT and row.buttonLabel.Text == SettingsWindow.ON_TEXT)
	check("줄 크기 Scale만(Offset 0)", pets.button.root.Size.Y.Offset == 0 and pets.label.Size.Y.Offset == 0)
	h.root:Destroy()
end

-- 2. 파티클 방출량 ------------------------------------------------------------------------------------
do
	local P = AuraConfig.Packs[1].auras
	local RATE = AuraConfig.PARTICLE.RATE_BY_TIER
	local r = AuraRenderLogic.rates({ { auraId = P[4].id, isLocal = true }, { auraId = P[1].id, isLocal = false }, { auraId = false, isLocal = false } }, false)
	check("방출량: 등급별 값 · 장착 없음은 0", r[1] == RATE[4] and r[2] == RATE[1] and r[3] == 0)
	local hidden = AuraRenderLogic.rates({ { auraId = P[4].id, isLocal = true }, { auraId = P[4].id, isLocal = false } }, true)
	check("숨기기: 다른 사람은 0 · 내 아우라는 보인다", hidden[1] == RATE[4] and hidden[2] == 0)
	local crowd = {}
	for i = 1, 40 do
		crowd[i] = { auraId = P[4].id, isLocal = i == 1 }
	end
	local many = AuraRenderLogic.rates(crowd, false)
	local total = 0
	for _, x in ipairs(many) do
		total += x
	end
	check("상한: 사람이 많아도 전체 합 ≤ MAX_TOTAL_RATE · 같은 비율", math.abs(total - AuraConfig.PARTICLE.MAX_TOTAL_RATE) < 1e-6 and math.abs(many[1] - many[40]) < 1e-9)
	check("모르는 아우라 id는 0", AuraRenderLogic.rates({ { auraId = "ghost", isLocal = true } }, false)[1] == 0)
end

print(string.format("[SettingsWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SettingsWindowTests] %d test(s) failed", failed))
end

--!strict
-- 장비 클라 검증(지시서 #34 — 플래그 ECONOMY_V2 뒤에서만 쓰는 모듈). 전역 플래그는 건드리지 않는다 — 모듈을 직접 만들어 굴린다.
--   창 로직(15칸 등급순 · 배수 · 장착 · 실루엣 · 강화 미리보기 = 서버와 같은 낮은 광석부터 · 별 미리보기 = 여벌 · 1개 남김 · 상한) ·
--   창(실루엣 · 등급 색 테두리 · 이름 · 버튼 상태 · 결과 글자 · AutoLocalize false · UiTheme.FONT) · 상태(equipment_state) ·
--   HUD 장비 버튼(대장간이 열렸을 때만) · 상점 줄(새 경제면 펀치 데미지 빠짐 · 끄면 그대로)

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Logic = require(script.Parent.Parent.UI.Logic.EquipmentWindowLogic)
local EquipmentWindow = require(script.Parent.Parent.UI.Screens.Window.EquipmentWindow)
local EconomyHud = require(script.Parent.Parent.UI.Screens.Hud.EconomyHud)
local EconomyV2State = require(script.Parent.Parent.Economy.EconomyV2State)
local UpgradeShopLogic = require(script.Parent.Parent.UI.Logic.UpgradeShopLogic)

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

local START = Config.START_PICKAXE
local P5 = Config.PICKAXES[5].id

-- 1. 창 로직 ------------------------------------------------------------------------------------------
do
	local eq = { [START] = { count = 1, stars = 0, enh = 0 }, [P5] = { count = 3, stars = 2, enh = 4 } }
	local cells = Logic.cells(eq, P5)
	local orderOk = #cells == #Config.PICKAXES
	for i, c in ipairs(cells) do
		orderOk = orderOk and c.id == Config.PICKAXES[i].id
	end
	check("칸: 15칸 등급순(rank)", orderOk)
	local c5 = cells[5]
	check("칸: 보유 · 별 · 강화 · 배수(= 곡괭이 × 강화 × 별) · 장착", c5.owned and c5.count == 3 and c5.stars == 2 and c5.enh == 4 and c5.equipped
		and math.abs(c5.mult - L.pickaxeMult(P5, 4, 2)) < 1e-9 and not cells[1].equipped)
	check("칸: 없는 곡괭이는 실루엣(이름 ???)", not cells[15].owned and Logic.nameOf(cells[15]) == Locale.t("equip.unknown"))
	local ores = L.newInv()
	ores[1], ores[3] = 5, 5
	local ep = Logic.enhancePreview(cells[1], ores)
	local cost = L.enhanceCost(0, START) :: number
	check("강화 미리보기: 다음 비용 · 쓰일 광석(낮은 광석부터 — 서버와 같은 orePayment) · 배수 바뀜", ep.cost == cost and ep.take ~= nil
		and (ep.take :: any)[1] == cost and (ep.take :: any)[3] == nil and ep.after > ep.before)
	local poor = Logic.enhancePreview(cells[1], L.newInv())
	check("강화 미리보기: 광석이 모자라면 쓰일 광석 없음", poor.take == nil and string.find(poor.text, Locale.t("equip.reason.not_enough_ore"), 1, true) ~= nil)
	local maxed = Logic.enhancePreview({ id = START, rarity = "common", owned = true, count = 1, stars = 0, enh = Config.ENHANCE_MAX, mult = 1, equipped = false }, ores)
	check("강화 미리보기: +10이면 최대", maxed.canMax and maxed.text == Locale.t("equip.enh.max"))
	local sp1 = Logic.starPreview(cells[1])
	local sp5 = Logic.starPreview(c5)
	check("별 미리보기: 보유 1개 = 여벌 0(1개 남김) · 필요 1 · 못 올림", sp1.spare == 0 and sp1.need == Config.STAR_CONSUME[1] and not sp1.can)
	check("별 미리보기: 보유 3 · 2성 → 여벌 2 · 필요 5 · 못 올림 · 배수 바뀜 표시", sp5.spare == 2 and sp5.need == Config.STAR_CONSUME[3] and not sp5.can
		and sp5.after > c5.mult)
	local sMax = Logic.starPreview({ id = START, rarity = "common", owned = true, count = 9, stars = 5, enh = 0, mult = 1, equipped = false })
	check("별 미리보기: 5성이면 최대", sMax.isMax and not sMax.can)
end

-- 2. 창 -----------------------------------------------------------------------------------------------
do
	local gui = Instance.new("ScreenGui")
	local sent = {}
	local w = EquipmentWindow.create({
		send = function(p)
			table.insert(sent, p)
		end,
		onClose = function() end,
	})
	w.root.Parent = gui
	local ores = L.newInv()
	ores[1] = 20
	w.set({ equipment = { [START] = { count = 2, stars = 0, enh = 0 }, [P5] = { count = 1, stars = 0, enh = 0 } }, equipped = START, ores = ores })
	local d = w._debug
	local c1, c15 = d.cells[1], d.cells[15]
	check("창: 가진 칸 = 등급 색 테두리 · 이름 / 없는 칸 = 실루엣(??? · 숫자 없음)", c1.stroke.Color == UiTheme.equipGradeColor("common")
		and c1.name.TextColor3 == UiTheme.equipGradeColor("common") and c15.name.Text == Locale.t("equip.unknown") and c15.info.Text == "")
	check("창: 장착한 곡괭이 고름 — 장착 버튼 잠김 · 강화 가능 · 별 가능(여벌 1)", d.equipB.isDisabled() and not d.enhB.isDisabled() and not d.starB.isDisabled())
	w.select(P5)
	check("창: 다른 곡괭이 고름 — 장착 가능 · 이름은 등급 색", not d.equipB.isDisabled() and d.dName.TextColor3 == UiTheme.equipGradeColor("rare"))
	w.onEvent({ kind = "equipment_result", action = "enhance", ok = false, reason = "not_enough_ore", id = P5 })
	check("창: 거부 사유 글자", d.msg.Text == Locale.t("equip.reason.not_enough_ore"))
	local autoOk, fontOk = true, true
	for _, obj in ipairs(w.root:GetDescendants()) do
		if obj:IsA("TextLabel") then
			autoOk = autoOk and (obj.AutoLocalize == false or obj.Text == "")
			fontOk = fontOk and obj.Font == UiTheme.FONT
		end
	end
	check("창: 글자 AutoLocalize false · UiTheme.FONT", autoOk and fontOk)
	gui:Destroy()
end

-- 3. 상태 · HUD · 상점 ---------------------------------------------------------------------------------------
do
	local s = EconomyV2State.new()
	s.apply({ kind = "equipment_state", equipment = { [P5] = { count = 2, stars = 1, enh = 3 } }, equipped = P5, ores = L.newInv() })
	local v = s.get()
	check("상태: equipment_state → 장비 · 장착", v.equipped == P5 and v.equipment[P5].stars == 1 and v.equipment[P5].enh == 3)
	local gui = Instance.new("ScreenGui")
	local hud = EconomyHud.create(gui)
	hud.set({ coins = BigNum.new(0, 0), bagUsed = 0, bagCap = 20, forgeOpen = false })
	local closed = not hud.forgeRow.Visible
	hud.set({ coins = BigNum.new(0, 0), bagUsed = 0, bagCap = 20, forgeOpen = true })
	check("HUD: 장비 버튼은 대장간이 열렸을 때만(대장간 줄)", closed and hud.forgeRow.Visible and hud.equipHit ~= nil and hud.equipHit:IsDescendantOf(hud.forgeRow))
	gui:Destroy()
	local on, off = UpgradeShopLogic.order(true), UpgradeShopLogic.order(false)
	check("상점: 새 경제면 펀치 데미지 줄 없음 · 끄면 SHOP_ORDER 그대로", table.find(on, "punchDamage") == nil and #on == #UpgradeConfig.SHOP_ORDER - 1
		and table.concat(off, ",") == table.concat(UpgradeConfig.SHOP_ORDER, ","))
end

print(string.format("[EquipmentClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EquipmentClientTests] %d test(s) failed", failed))
end

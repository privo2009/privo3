--!strict
-- 장비 서버 검증(지시서 #34 — 플래그 ECONOMY_V2 뒤). 전역 플래그는 건드리지 않는다.
-- InventoryService 순수 함수(Schema.new 데이터) · EquipmentService(가짜 deps) · 데미지 배수 일치(게임 = 시뮬) · 가방 넘침 · 손 모델 · 플래그 꺼짐.
-- 숫자는 Config에서 읽는다.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Schema = require(ServerScriptService.Server.Data.Schema)
local InventoryService = require(ServerScriptService.Server.Systems.InventoryService)
local EquipmentService = require(ServerScriptService.Server.Systems.EquipmentService)
local HeldPickaxeService = require(ServerScriptService.Server.Systems.HeldPickaxeService)
local OreDropService = require(ServerScriptService.Server.Systems.OreDropService)
local AttackService = require(ServerScriptService.Server.Systems.AttackService)
local UpgradeService = require(ServerScriptService.Server.Systems.UpgradeService)

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

local IP = InventoryService._pure
local START = Config.START_PICKAXE
local P2 = Config.PICKAXES[2].id

local function enhance(data: any, id: string): (boolean, any)
	return IP.applyChecked(data, function(d)
		local ok, info = IP.applyEnhance(d, "pickaxe", id)
		return ok, if ok then nil else info
	end)
end
local function star(data: any, id: string): (boolean, any)
	return IP.applyChecked(data, function(d)
		return IP.applyStarUp(d, "pickaxe", id)
	end)
end

-- 1. 장착 검증(순수 판정) -------------------------------------------------------------------------
do
	local C = EquipmentService._pure.check
	local eq = { [START] = { count = 1, stars = 0, enh = 0 } }
	local inv = L.newInv()
	check("장착: 없는 곡괭이는 not_owned · 모르는 id는 unknown", C("equip", P2, true, eq, START, inv) == "not_owned"
		and C("equip", "nope", true, eq, START, inv) == "unknown" and C("equip", 5, true, eq, START, inv) == "unknown")
	check("장착: 같은 것 다시는 already_equipped", C("equip", START, true, eq, START, inv) == "already_equipped")
	eq[P2] = { count = 1, stars = 0, enh = 0 }
	check("장착: 가진 다른 곡괭이는 된다 · 대장간이 닫혀도 장착은 된다", C("equip", P2, false, eq, START, inv) == nil)
	check("강화 · 별: 대장간이 닫혀 있으면 forge_closed", C("enhance", START, false, eq, START, inv) == "forge_closed"
		and C("star", START, false, eq, START, inv) == "forge_closed")
end

-- 2. 강화: 비용 · 낮은 광석부터 · 부족 · +10 상한 ---------------------------------------------------------
do
	local data = Schema.new()
	data.ores[1], data.ores[3], data.ores[10] = 5, 4, 2
	local cost = L.enhanceCost(0, START) :: number
	local ok = enhance(data, START)
	check("강화: 비용 = 등급 × 단계(시작 곡괭이 +0 → 바탕 × 일반 배수)", cost == math.ceil(Config.ENHANCE_COST_BASE * Config.ENHANCE_COST_BY_RARITY.common - 1e-9))
	check("강화: 낮은 광석부터 낸다(구리 1점 × 비용 · 위 광석 그대로) · +1", ok and data.ores[1] == 5 - cost and data.ores[3] == 4 and data.ores[10] == 2
		and data.equipment.pickaxe[START].enh == 1, string.format("ores %d %d %d", data.ores[1], data.ores[3], data.ores[10]))
	local mixed = L.newInv()
	mixed[1], mixed[3] = 1, 5 -- 1점 하나 + 2점 다섯
	local take = L.orePayment(mixed, 4)
	check("강화: 낮은 광석이 모자라면 다음 광석(구리 1 + 철 2 — 마지막 하나는 넘칠 수 있다)", take ~= nil and take[1] == 1 and take[3] == 2)
	local poor = Schema.new()
	local okP, why = enhance(poor, START)
	check("강화: 광석이 모자라면 not_enough_ore · 그대로", not okP and why == "not_enough_ore" and poor.equipment.pickaxe[START].enh == 0)
	data.equipment.pickaxe[START].enh = Config.ENHANCE_MAX
	local before = data.ores[1]
	local okM, whyM = enhance(data, START)
	check("강화: +10이면 max · 광석 그대로", not okM and whyM == "max" and data.ores[1] == before)
	local okN, whyN = enhance(data, P2)
	check("강화: 없는 곡괭이는 not_owned", not okN and whyN == "not_owned")
	local epic: string = ""
	for _, d in ipairs(Config.PICKAXES) do
		if d.rarity == "epic" and epic == "" then
			epic = d.id
		end
	end
	check("강화: 등급이 높을수록 비싸다(에픽 > 일반) · 단계가 오를수록 비싸다", (L.enhanceCost(0, epic) :: number) > (L.enhanceCost(0, START) :: number)
		and (L.enhanceCost(5, START) :: number) > (L.enhanceCost(0, START) :: number))
end

-- 3. 별: 여벌 소모 · 1개 남김 · 5성 상한 ------------------------------------------------------------------
do
	local data = Schema.new()
	local o = data.equipment.pickaxe[START]
	local ok1, why1 = star(data, START)
	check("별: 보유 1개뿐이면 여벌 0 — not_enough_copies", not ok1 and why1 == "not_enough_copies" and o.stars == 0)
	data.equipment.pickaxe[START].count = 2
	local ok2 = star(data, START)
	o = data.equipment.pickaxe[START]
	check("별: 여벌 1 → 1성 · 보유 1개 남김", ok2 and o.stars == 1 and o.count == 1)
	local total = 1
	for _, c in ipairs(Config.STAR_CONSUME) do
		total += c
	end
	data.equipment.pickaxe[START] = { count = total - 1, stars = 1, enh = 0 } -- 1성까지 쓴 뒤 남은 수(보유 1 + 여벌 25)
	local ups = 0
	while (star(data, START)) do
		ups += 1
	end
	o = data.equipment.pickaxe[START]
	check("별: 누적 26 여벌로 5성 · 보유 1개는 언제나 남는다", ups == 4 and o.stars == 5 and o.count == 1)
	data.equipment.pickaxe[START].count = 50
	local okM, whyM = star(data, START)
	check("별: 5성이면 max · 개수 그대로", not okM and whyM == "max" and data.equipment.pickaxe[START].count == 50)
end

-- 4. EquipmentService 요청(가짜 deps) ----------------------------------------------------------------------
local savedEq = EquipmentService._deps
local okRun, errRun = pcall(function()
	local data = Schema.new()
	data.equipment.pickaxe[P2] = { count = 1, stars = 0, enh = 0 }
	local open = true
	local sent, equippedCalls = {}, 0
	local p = { Name = "EquipFake" } :: any
	EquipmentService._deps = {
		isForgeOpen = function()
			return open
		end,
		getEquipment = function()
			return table.clone(data.equipment.pickaxe)
		end,
		getEquipped = function()
			return data.equipped.pickaxe
		end,
		getOres = function()
			return table.clone(data.ores)
		end,
		equip = function(_p, kind, id, _r)
			return (IP.applyChecked(data, function(d)
				return IP.applyEquip(d, kind, id)
			end))
		end,
		enhance = function(_p, _k, id, _r)
			return (enhance(data, id))
		end,
		starUp = function(_p, _k, id, _r)
			return (star(data, id))
		end,
		onEquipped = function()
			equippedCalls += 1
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
		now = function()
			return 0
		end,
	}
	local a = EquipmentService.handle(p, "equip", P2)
	local b, whyB = EquipmentService.handle(p, "equip", P2)
	check("요청 장착: 바뀌고 가방 · 손 모델 다시(1번) · 같은 것 다시는 already_equipped(쓰지 않음)", a and data.equipped.pickaxe == P2 and equippedCalls == 1
		and not b and whyB == "already_equipped" and equippedCalls == 1)
	open = false
	data.ores[1] = 50
	local c, whyC = EquipmentService.handle(p, "enhance", P2)
	open = true
	local d = EquipmentService.handle(p, "enhance", P2)
	local last = sent[#sent - 1]
	check("요청 강화: 닫히면 forge_closed · 열리면 +1 · 결과 신호 · 상태 다시 보냄", not c and whyC == "forge_closed" and d
		and data.equipment.pickaxe[P2].enh == 1 and last.kind == "equipment_result" and last.ok == true and sent[#sent].kind == "equipment_state")
	EquipmentService._reset(p)
	EquipmentService.handleRequest(p, { action = "star", id = P2 })
	EquipmentService.handleRequest(p, { action = "sync" }) -- 같은 시각 — 연타 상한 안이라 버린다
	local n = #sent
	check("요청: 별(여벌 없음) 거부 신호 · 연타 상한 안 요청은 버림", sent[n - 1].kind == "equipment_result" and sent[n - 1].reason == "not_enough_copies")
end)
EquipmentService._deps = savedEq
check("가짜 세계: 오류 없이 끝남", okRun, tostring(errRun))

-- 5. 채굴 데미지 배수 일치(게임 = 시뮬) -------------------------------------------------------------------------
do
	local matchOk = true
	local cases = 0
	for i, def in ipairs(Config.PICKAXES) do
		local eq = { [START] = { count = 1, stars = 0, enh = 0 }, [def.id] = { count = 1 + i, stars = i % 6, enh = (i * 3) % 11 } }
		local game = L.multFromSave(eq, def.id)
		local sim = L.equippedMult(L.picksFromSave(eq, def.id))
		local direct = L.baseMult(def.id) * L.enhanceMult(eq[def.id].enh, def.id) * L.starMult(eq[def.id].stars)
		matchOk = matchOk and math.abs(game - sim) < 1e-9 and math.abs(game - direct) < 1e-9
		cases += 1
	end
	check("배수 일치: 15종 × (강화 · 별) — 게임(multFromSave) = 시뮬(equippedMult) = 곡괭이 × 강화 × 별", matchOk and cases == #Config.PICKAXES)
	-- 실제 데미지 경로(AttackService.punchDamageFactor)도 같은 값
	local data = Schema.new()
	local id = Config.PICKAXES[9].id
	data.equipment.pickaxe[id] = { count = 4, stars = 2, enh = 7 }
	data.equipped.pickaxe = id
	local fake = { Name = "DamageFake" } :: any
	local savedGet = InventoryService._deps.getData
	InventoryService._deps.getData = function(pl: any)
		return if pl == fake then data else savedGet(pl)
	end
	local okV2, v2 = pcall(AttackService.punchDamageFactor, fake, true)
	local okV1, v1 = pcall(AttackService.punchDamageFactor, fake, false)
	InventoryService._deps.getData = savedGet
	check("데미지 경로: 새 경제면 장착 곡괭이 배수(= 시뮬 equippedMult) · 끄면 상점 업그레이드 효과 그대로", okV2 and okV1
		and math.abs(v2 - L.equippedMult(L.picksFromSave(data.equipment.pickaxe, id))) < 1e-9 and v2 > 1
		and v1 == UpgradeService.getEffect(fake, "punchDamage"), tostring(v2) .. " / " .. tostring(v1))
	check("상점: 펀치 데미지 업그레이드는 새 경제에서만 빠진다", L.isRemovedUpgrade("punchDamage", true) and not L.isRemovedUpgrade("punchDamage", false)
		and not L.isRemovedUpgrade("punchSpeed", true) and not L.isRemovedUpgrade("bloxGain", true))
end

-- 6. 가방: 장착을 바꾸면 용량 · 넘침 규칙 -------------------------------------------------------------------------
do
	local bag = L.newInv()
	bag[2] = Config.BAG_BASE + 5 -- 큰 가방 곡괭이에서 시작 곡괭이로 바꿔 넘친 가방
	local added = L.addToBag(bag, Config.BAG_BASE, 5, 3)
	check("넘친 가방: 든 광석은 그대로 · 새로 줍기(바꿔 줍기 포함) 0", added == 0 and bag[2] == Config.BAG_BASE + 5 and bag[5] == 0)
	local full = L.newInv()
	full[1] = Config.BAG_BASE
	check("딱 찬 가방: 더 좋은 광석은 바꿔 줍는다(#32 그대로)", L.addToBag(full, Config.BAG_BASE, 5, 1) == 1 and full[5] == 1)
	local savedOre = OreDropService._deps
	local sent = {}
	local equipped = Config.PICKAXES[6].id
	OreDropService._deps = {
		getEquipped = function()
			return equipped
		end,
		ownsBigBag = function()
			return false
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
	} :: any
	local p = { Name = "BagFake" } :: any
	local okB, errB = pcall(function()
		OreDropService.refreshBag(p)
		equipped = START
		OreDropService.refreshBag(p)
	end)
	OreDropService._deps = savedOre
	check("장착 바꿈: 가방 용량을 바로 다시 보낸다(장착 등급 용량)", okB and #sent == 2 and sent[1].kind == "bag"
		and sent[1].cap == L.bagCapacity(Config.PICKAXES[6].id) and sent[2].cap == L.bagCapacity(START), tostring(errB))
end

-- 7. 손 모델(서버) --------------------------------------------------------------------------------------------
do
	local character = Instance.new("Model")
	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Parent = character
	local id = Config.PICKAXES[12].id
	local m = HeldPickaxeService.attach(character, id)
	local head = if m ~= nil then m:FindFirstChild("Head") :: BasePart? else nil
	local handle = if m ~= nil then m:FindFirstChild("Handle") :: BasePart? else nil
	local weld = if handle ~= nil then handle:FindFirstChildOfClass("WeldConstraint") else nil
	check("손 모델: 캐릭터에 붙는다 · 머리 = 등급 색 · 손에 묶음 · 물리 없음(충돌 · 터치 · 질의 끔 · Massless)", m ~= nil and m.Parent == character
		and head ~= nil and head.Color == UiTheme.equipGradeColor("mythic") and weld ~= nil and weld.Part0 == hand and weld.Part1 == handle
		and handle ~= nil and not handle.CanCollide and not handle.CanTouch and not handle.CanQuery and handle.Massless and not handle.Anchored)
	HeldPickaxeService.attach(character, START)
	local n = 0
	for _, c in ipairs(character:GetChildren()) do
		if c.Name == HeldPickaxeService.MODEL_NAME then
			n += 1
		end
	end
	local now = character:FindFirstChild(HeldPickaxeService.MODEL_NAME)
	check("손 모델: 장착을 바꾸면 하나만(새 곡괭이)", n == 1 and now ~= nil and now:GetAttribute("PickaxeId") == START)
	HeldPickaxeService.attach(character, nil)
	check("손 모델: 장착 없음 · 모르는 곡괭이면 지운다", character:FindFirstChild(HeldPickaxeService.MODEL_NAME) == nil
		and HeldPickaxeService.attach(character, "nope") == nil)
	local noHand = Instance.new("Model")
	check("손 모델: 손이 없으면 붙이지 않는다", HeldPickaxeService.attach(noHand, START) == nil)
	character:Destroy()
	noHand:Destroy()
end

-- 8. 플래그 꺼짐 = 지금과 같다 ------------------------------------------------------------------------------
check("플래그 꺼짐: 장비 · 손 모델 서비스 init 없음(켜져 있으면 init됨)", EquipmentService._initialized() == L.isOn()
	and HeldPickaxeService._initialized() == L.isOn())

print(string.format("[EquipmentServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[EquipmentServiceTests] %d test(s) failed", failed))
end

--!strict
-- 장비 서버(지시서 #34 — DESIGN 16장 "곡괭이" · "별 · 강화 규칙" · "장비 화면").
--
-- 서버 권위(CLAUDE.md 절대 규칙 3) — 클라 EquipmentRequest는 "요청"일 뿐이다:
--   장착   가진 장비인가 · 이미 장착한 것이면 거부(already_equipped — 쓰지 않는다) → InventoryService.equip →
--          가방 용량을 바로 다시 보낸다(OreDropService.refreshBag — 줄어 넘치면 든 광석은 두고 새로 줍기만 막는다) · 손 모델 갱신
--   강화   대장간이 열렸나 · 가진 장비인가 · +10 미만 · 비용(등급 × 단계)을 가진 광석에서 낮은 광석부터 → InventoryService.enhance 한 번
--   별     대장간이 열렸나 · 여벌(보유 − 1)이 다음 별 재료 이상 · 5성 미만 → InventoryService.starUp 한 번(보유 1개는 언제나 남는다)
-- 결과는 EconomyEvent(kind equipment_state · equipment_result)로 요청한 사람에게만. 요청 연타 상한은 대장간과 같은 방식(0.15초).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyV2Logic = require(ReplicatedStorage.Shared.EconomyV2Logic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteGuard = require(script.Parent.RemoteGuard) -- 입구 공통 문(모양 · 연타 · 오류 격리 — #38)

local EquipmentService = {}

EquipmentService.KIND = "pickaxe"
EquipmentService.REQUEST_MIN_GAP_SEC = 0.15

export type Deps = {
	isForgeOpen: (Player) -> boolean,
	getEquipment: (Player) -> { [string]: any }?,
	getEquipped: (Player) -> string?,
	getOres: (Player) -> { number }?,
	equip: (Player, string, string, string) -> boolean,
	enhance: (Player, string, string, string) -> boolean,
	starUp: (Player, string, string, string) -> boolean,
	onEquipped: (Player) -> (), -- 가방 용량 · 손 모델 다시
	send: (Player, any) -> (),
	now: () -> number,
}

-- ===== 순수 판정 (Player 없음 — EquipmentServiceTests) ===========================================================

-- 요청 검사. 사유: "unknown" · "forge_closed" · "not_owned" · "already_equipped" · "max" · "not_enough_ore" · "not_enough_copies"
local function check(action: string, id: any, open: boolean, equipment: { [string]: any }, equipped: string?, ores: { number }): string?
	if type(id) ~= "string" or EconomyV2Logic.pickaxe(id) == nil then
		return "unknown"
	end
	local o = equipment[id]
	if o == nil then
		return "not_owned"
	end
	if action == "equip" then
		return if equipped == id then "already_equipped" else nil
	end
	if not open then
		return "forge_closed"
	end
	if action == "enhance" then
		local cost = EconomyV2Logic.enhanceCost(o.enh, id)
		if cost == nil then
			return "max"
		end
		return if EconomyV2Logic.orePayment(ores, cost) == nil then "not_enough_ore" else nil
	elseif action == "star" then
		local need = EconomyV2Logic.starCost(o.stars)
		if need == nil then
			return "max"
		end
		return if EconomyV2Logic.spareOf(o.count) < need then "not_enough_copies" else nil
	end
	return "unknown"
end

EquipmentService._pure = { check = check }

-- ===== 바깥 세계 이음매 =====================================================================================

local function liveDeps(): Deps
	local InventoryService = require(script.Parent.InventoryService)
	local channels = Remotes.getServer()
	return {
		isForgeOpen = InventoryService.isForgeOpen,
		getEquipment = function(player)
			return InventoryService.getEquipment(player, EquipmentService.KIND)
		end,
		getEquipped = function(player)
			return InventoryService.getEquipped(player, EquipmentService.KIND)
		end,
		getOres = InventoryService.getOres,
		equip = InventoryService.equip,
		enhance = InventoryService.enhance,
		starUp = InventoryService.starUp,
		onEquipped = function(player)
			require(script.Parent.OreDropService).refreshBag(player)
			require(script.Parent.HeldPickaxeService).refresh(player)
		end,
		send = function(player, payload)
			if typeof(player) == "Instance" and player:IsA("Player") then
				channels.economyEvent:FireClient(player, payload)
			end
		end,
		now = os.clock,
	}
end

EquipmentService._deps = nil :: Deps?

local function deps(): Deps
	if EquipmentService._deps == nil then
		EquipmentService._deps = liveDeps()
	end
	return EquipmentService._deps :: Deps
end

local lastAt: { [Player]: number } = {}

function EquipmentService.sendState(player: Player)
	local d = deps()
	d.send(player, {
		kind = "equipment_state",
		equipment = d.getEquipment(player) or {},
		equipped = d.getEquipped(player) or "",
		ores = d.getOres(player) or EconomyV2Logic.newInv(),
	})
end

-- 요청 한 건 처리(검증 · 실행 · 결과). 성공이면 (true), 아니면 (false, 사유)
function EquipmentService.handle(player: Player, action: string, id: any): (boolean, string?)
	local d = deps()
	local equipment = d.getEquipment(player)
	local ores = d.getOres(player)
	if equipment == nil or ores == nil then
		return false, "no_profile"
	end
	local why = check(action, id, d.isForgeOpen(player), equipment, d.getEquipped(player), ores)
	local ok = why == nil
	if ok then
		local reason = "equipment_" .. action
		if action == "equip" then
			ok = d.equip(player, EquipmentService.KIND, id, reason)
		elseif action == "enhance" then
			ok = d.enhance(player, EquipmentService.KIND, id, reason)
		else
			ok = d.starUp(player, EquipmentService.KIND, id, reason)
		end
		if not ok then
			why = "grant_failed"
		elseif action == "equip" then
			d.onEquipped(player)
		end
	end
	d.send(player, { kind = "equipment_result", action = action, ok = ok, reason = why, id = if type(id) == "string" then id else "" })
	EquipmentService.sendState(player)
	return ok, why
end

function EquipmentService.handleRequest(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return
	end
	local d = deps()
	local now = d.now()
	if now - (lastAt[player] or -math.huge) < EquipmentService.REQUEST_MIN_GAP_SEC then
		return
	end
	lastAt[player] = now
	local action = payload.action
	if action == "equip" or action == "enhance" or action == "star" then
		EquipmentService.handle(player, action, payload.id)
	elseif action == "sync" then
		EquipmentService.sendState(player)
	end
end

function EquipmentService._reset(player: Player)
	lastAt[player] = nil
end

local initialized = false

function EquipmentService._initialized(): boolean
	return initialized
end

function EquipmentService.init()
	if initialized then
		return
	end
	initialized = true
	RemoteGuard.connect(Remotes.getServer().equipmentRequest, function(player: Player, payload: any)
		local ok, err = pcall(EquipmentService.handleRequest, player, payload)
		if not ok then
			warn("[EquipmentService] 요청 오류: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAt[player] = nil
	end)
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	ProfileManager.onLoaded(function(player: Player)
		EquipmentService.sendState(player)
	end)
	print("[EquipmentService] 장비(장착 · 강화 · 별) 시작")
end

return EquipmentService

--!strict
-- 개발자 전용 관리 도구(지시서 #48 4부). 값 · 누가 쓰나 → Shared/Config/AdminConfig. 규칙 → DESIGN.md "17. 운영 > 관리 도구" · REMOTES.md.
--
-- 입구 AdminRequest(RemoteGuard.connect — 모양 · 연타 · 오류 격리) → 이 모듈:
--   1. 관리자가 아니면 조용히 버린다(답 없음 — 관리 도구가 있다는 것도 알리지 않는다). 판정은 서버(게임 주인 · 그룹 주인 · 지정 목록)
--   2. payload { action, target(UserId), kind, id(문자열), amount, text } — 빠진 필드 없이(Remotes "nil이면 키가 사라진다")
--      grant · revoke  같은 서버 유저 · 종류(blox · coins · ore · token · pickaxe · pet) · 개수 1 ~ 상한 · id 검사 → 관문으로
--                      재화 CurrencyService · 광석 · 토큰 · 곡괭이 InventoryService · 펫 PetService(지급 grant · 회수 release(uid)). 사유 "admin"
--      inspect         그 유저 상태 몇 줄(읽기만)
--      announce        글 1 ~ ANNOUNCE_MAX_CHARS자 → TextService로 거른 글만 모두에게(ServerNotice kind = "announce"). 거르기 실패면 안 보낸다
--   3. 쓸 때마다 서버 로그 한 줄 + 분석 이벤트(admin_action) · 결과는 AdminResult로 그 관리자에게만
-- 접속 때 관리자에게만 AdminResult{ action = "hello" } 한 번 — 클라는 그때만 관리 창을 만든다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local AdminService = {}

export type Deps = {
	isAdmin: (player: any) -> boolean,
	findTarget: (userId: number) -> any?,
	addCurrency: (target: any, currency: string, amount: any, reason: string) -> boolean,
	subCurrency: (target: any, currency: string, amount: any, reason: string) -> boolean,
	addOres: (target: any, counts: { [number]: number }, reason: string) -> boolean,
	takeOres: (target: any, counts: { [number]: number }, reason: string) -> boolean,
	addTokens: (target: any, counts: { [string]: number }, reason: string) -> boolean,
	takeTokens: (target: any, counts: { [string]: number }, reason: string) -> boolean,
	grantPickaxe: (target: any, id: string, reason: string) -> boolean,
	revokePickaxe: (target: any, id: string, reason: string) -> boolean,
	grantPet: (target: any, petId: string, reason: string) -> boolean,
	releasePet: (target: any, uid: string) -> boolean,
	filterText: (admin: any, text: string) -> (boolean, string?),
	broadcast: (text: string) -> (),
	inspect: (target: any) -> { string },
	refresh: (target: any) -> (),
	send: (admin: any, payload: any) -> (),
	log: (line: string) -> (),
	analytics: (admin: any, action: string, kind: string) -> (),
}

local function isCount(v: any, max: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= 1 and v <= max
end

local PICKAXE_SET: { [string]: boolean } = {}
for _, def in ipairs(EconomyV2Config.PICKAXES) do
	PICKAXE_SET[def.id] = true
end
local TOKEN_SET: { [string]: boolean } = { rare = true, epic = true, mythic = true, legendary = true, next = true }

-- 종류마다 개수 상한
local function maxFor(kind: string): number
	if kind == "blox" or kind == "coins" then
		return AdminConfig.MAX_CURRENCY
	elseif kind == "ore" or kind == "token" then
		return AdminConfig.MAX_COUNT
	end
	return AdminConfig.MAX_ITEMS
end

-- grant · revoke 한 번. 돌려주는 값: (성공, 사유)
local function applyItem(deps: Deps, target: any, action: string, kind: string, id: string, amount: number): (boolean, string)
	local R = AdminConfig.REASON
	local grant = action == "grant"
	if kind == "blox" or kind == "coins" then
		local big = BigNum.fromNumber(amount)
		local ok = if grant then deps.addCurrency(target, kind, big, R) else deps.subCurrency(target, kind, big, R)
		return ok, if ok then "" else "gate_refused"
	elseif kind == "ore" then
		local k = tonumber(id)
		if k == nil or k % 1 ~= 0 or k < 1 or k > EconomyV2Config.ORE_COUNT then
			return false, "bad_id"
		end
		local counts = { [k :: number] = amount }
		local ok = if grant then deps.addOres(target, counts, R) else deps.takeOres(target, counts, R)
		return ok, if ok then "" else "gate_refused"
	elseif kind == "token" then
		if not TOKEN_SET[id] then
			return false, "bad_id"
		end
		local counts = { [id] = amount }
		local ok = if grant then deps.addTokens(target, counts, R) else deps.takeTokens(target, counts, R)
		return ok, if ok then "" else "gate_refused"
	elseif kind == "pickaxe" then
		if not PICKAXE_SET[id] then
			return false, "bad_id"
		end
		for _ = 1, amount do
			local ok = if grant then deps.grantPickaxe(target, id, R) else deps.revokePickaxe(target, id, R)
			if not ok then
				return false, "gate_refused"
			end
		end
		return true, ""
	elseif kind == "pet" then
		if grant then
			if PetConfig.get(id) == nil then
				return false, "bad_id"
			end
			for _ = 1, amount do
				if not deps.grantPet(target, id, R) then
					return false, "gate_refused"
				end
			end
			return true, ""
		end
		-- 회수는 uid 하나씩(같은 펫이 여러 마리일 수 있다 — inspect가 uid를 보여 준다)
		if amount ~= 1 or string.match(id, "^%d+$") == nil then
			return false, "bad_id"
		end
		local ok = deps.releasePet(target, id)
		return ok, if ok then "" else "gate_refused"
	end
	return false, "bad_kind"
end

-- 입구 하나(테스트 · RemoteGuardTests 흔들기가 가짜 deps로 만든다)
function AdminService.createHandler(deps: Deps)
	local self = {}

	local function reply(admin: any, action: string, ok: boolean, reason: string, lines: { string }?)
		deps.send(admin, { action = action, ok = ok, reason = reason, lines = lines or {} })
	end

	function self.onRequest(admin: any, payload: any, _now: number?): (boolean, string)
		if not deps.isAdmin(admin) then
			return false, "not_admin" -- 조용히 버린다(답 없음)
		end
		if type(payload) ~= "table" or type(payload.action) ~= "string" or not AdminConfig.ACTIONS[payload.action] then
			reply(admin, "?", false, "bad_action")
			return false, "bad_action"
		end
		local action = payload.action
		if action == "announce" then
			local text = payload.text
			local len = if type(text) == "string" then utf8.len(text) else nil
			if len == nil or len < 1 or len > AdminConfig.ANNOUNCE_MAX_CHARS or string.match(text, "^%s*$") ~= nil or string.find(text, "%c") ~= nil then
				reply(admin, action, false, "bad_text")
				return false, "bad_text"
			end
			local ok, filtered = deps.filterText(admin, text)
			if not ok or type(filtered) ~= "string" or filtered == "" then
				reply(admin, action, false, "filter_failed")
				return false, "filter_failed"
			end
			deps.broadcast(filtered :: string)
			deps.log(string.format("[Admin] %s(%d) 공지 %d자", tostring(admin.Name), tonumber(admin.UserId) or 0, len))
			deps.analytics(admin, action, "text")
			reply(admin, action, true, "")
			return true, ""
		end
		if type(payload.target) ~= "number" or payload.target ~= payload.target then
			reply(admin, action, false, "bad_target")
			return false, "bad_target"
		end
		local target = deps.findTarget(payload.target)
		if target == nil then
			reply(admin, action, false, "no_target")
			return false, "no_target"
		end
		if action == "inspect" then
			local lines = deps.inspect(target)
			deps.log(string.format("[Admin] %s(%d) 상태 읽기 → %s(%d)", tostring(admin.Name), tonumber(admin.UserId) or 0, tostring(target.Name),
				tonumber(target.UserId) or 0))
			deps.analytics(admin, action, "state")
			reply(admin, action, true, "", lines)
			return true, ""
		end
		local kind = payload.kind
		if not AdminConfig.isKind(kind) then
			reply(admin, action, false, "bad_kind")
			return false, "bad_kind"
		end
		if not isCount(payload.amount, maxFor(kind)) then
			reply(admin, action, false, "bad_amount")
			return false, "bad_amount"
		end
		local id = if type(payload.id) == "string" then payload.id else ""
		if #id > 40 then
			reply(admin, action, false, "bad_id")
			return false, "bad_id"
		end
		local ok, reason = applyItem(deps, target, action, kind, id, payload.amount)
		deps.log(string.format("[Admin] %s(%d) %s %s %s ×%s → %s(%d) %s%s", tostring(admin.Name), tonumber(admin.UserId) or 0, action, kind, id,
			tostring(payload.amount), tostring(target.Name), tonumber(target.UserId) or 0, if ok then "성공" else "거부 ", reason))
		deps.analytics(admin, action, kind)
		if ok then
			deps.refresh(target)
		end
		reply(admin, action, ok, reason)
		return ok, reason
	end

	return self
end

AdminService._pure = { createHandler = AdminService.createHandler, applyItem = applyItem }

-- ===== 실물 배선 =================================================================================

local groupOwnerId: number? = nil
local groupOwnerRead = false

-- 그룹 소유면 그룹 주인 UserId(한 번 읽어 둔다 — 실패하면 nil · 다음에 다시)
local function readGroupOwner(): number?
	if groupOwnerRead then
		return groupOwnerId
	end
	if game.CreatorType ~= Enum.CreatorType.Group then
		groupOwnerRead = true
		return nil
	end
	local ok, info = pcall(function()
		return game:GetService("GroupService"):GetGroupInfoAsync(game.CreatorId)
	end)
	if ok and type(info) == "table" and type(info.Owner) == "table" and type(info.Owner.Id) == "number" then
		groupOwnerId = info.Owner.Id
		groupOwnerRead = true
	end
	return groupOwnerId
end

function AdminService.isAdmin(player: Player): boolean
	if typeof(player) ~= "Instance" then
		return false
	end
	local creatorType = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User"
	return AdminConfig.isAdmin(player.UserId, creatorType, game.CreatorId, if creatorType == "Group" then readGroupOwner() else nil)
end

local function bigText(v: any): string
	if type(v) ~= "table" then
		return "-"
	end
	return string.format("%.3fe%d", v.m, v.e)
end

local function inspectOf(target: Player): { string }
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	local profile = ProfileManager.get(target)
	if profile == nil then
		return { "no profile" }
	end
	local d = profile.Data
	local lines = {}
	table.insert(lines, string.format("%s(%d) blox=%s coins=%s strength=%s rebirths=%s maxStage=%s", target.Name, target.UserId, bigText(d.blox),
		bigText(d.coins), bigText(d.strength), bigText(d.rebirths), tostring(d.progress and d.progress.maxStage)))
	local ores = {}
	for k = 1, EconomyV2Config.ORE_COUNT do
		ores[k] = tostring(type(d.ores) == "table" and d.ores[k] or 0)
	end
	table.insert(lines, "ores=" .. table.concat(ores, ","))
	local toks = {}
	for _, key in ipairs({ "rare", "epic", "mythic", "legendary", "next" }) do
		table.insert(toks, key .. ":" .. tostring(type(d.tokens) == "table" and d.tokens[key] or 0))
	end
	table.insert(lines, "tokens=" .. table.concat(toks, " "))
	local picks = {}
	local eq = if type(d.equipment) == "table" then d.equipment.pickaxe else nil
	if type(eq) == "table" then
		for id, o in pairs(eq) do
			table.insert(picks, string.format("%s×%d", id, o.count))
		end
	end
	table.sort(picks)
	table.insert(lines, string.format("pickaxes=%s equipped=%s", table.concat(picks, " "), tostring(type(d.equipped) == "table" and d.equipped.pickaxe)))
	local pets = {}
	if type(d.pets) == "table" and type(d.pets.owned) == "table" then
		for uid, p in pairs(d.pets.owned) do
			table.insert(pets, string.format("%s:%s", uid, tostring(type(p) == "table" and p.petId or p)))
		end
	end
	table.sort(pets)
	table.insert(lines, string.format("pets(%d)=%s", #pets, table.concat(pets, " ", 1, math.min(#pets, 20))))
	return lines
end

local initialized = false

function AdminService.init()
	if initialized then
		return
	end
	initialized = true
	AdminConfig.validate()
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	local RemoteGuard = require(script.Parent.RemoteGuard)
	local CurrencyService = require(script.Parent.CurrencyService)
	local InventoryService = require(script.Parent.InventoryService)
	local PetService = require(script.Parent.PetService)
	local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
	local Analytics = require(script.Parent.Analytics)
	local TextService = game:GetService("TextService")
	local channels = Remotes.getServer()

	local deps: Deps = {
		isAdmin = AdminService.isAdmin,
		findTarget = function(userId: number): any?
			local p = Players:GetPlayerByUserId(userId)
			return if p ~= nil and ProfileManager.get(p) ~= nil then p else nil
		end,
		addCurrency = function(t, c, a, r)
			return (CurrencyService.add(t, c, a, r))
		end,
		subCurrency = function(t, c, a, r)
			return (CurrencyService.subtract(t, c, a, r))
		end,
		addOres = InventoryService.addOres,
		takeOres = InventoryService.takeOres,
		addTokens = InventoryService.addTokens,
		takeTokens = InventoryService.takeTokens,
		grantPickaxe = function(t, id, r)
			return InventoryService.grantEquipment(t, "pickaxe", id, r)
		end,
		revokePickaxe = function(t, id, r)
			return InventoryService.revokeEquipment(t, "pickaxe", id, r)
		end,
		grantPet = function(t, petId, r)
			return (PetService.grant(t, petId, r))
		end,
		releasePet = function(t, uid)
			return (PetService.release(t, uid))
		end,
		filterText = function(admin: any, text: string): (boolean, string?)
			-- 공식 text-filtering: 모두에게 보이는 글은 FilterStringAsync → GetNonChatStringForBroadcastAsync
			local ok, out = pcall(function()
				local result = TextService:FilterStringAsync(text, admin.UserId)
				return result:GetNonChatStringForBroadcastAsync()
			end)
			return ok, if ok then out else nil
		end,
		broadcast = function(text: string)
			channels.serverNotice:FireAllClients({ kind = "announce", text = text, sec = 0 })
		end,
		inspect = inspectOf,
		refresh = function(t: any)
			-- 받은 쪽 화면을 바로 맞춘다(HUD · 대장간 · 장비 · 광석)
			pcall(function()
				require(script.Parent.PlayerStateService).notify(t)
			end)
			pcall(function()
				require(script.Parent.ForgeService).sendState(t)
			end)
			pcall(function()
				require(script.Parent.EquipmentService).sendState(t)
			end)
			pcall(function()
				require(script.Parent.OreDropService).sendSnapshot(t)
			end)
		end,
		send = function(admin: any, payload: any)
			channels.adminResult:FireClient(admin, payload)
		end,
		log = function(line: string)
			print(line)
		end,
		analytics = function(admin: any, action: string, kind: string)
			Analytics.adminAction(admin, action, kind)
		end,
	}
	local handler = AdminService.createHandler(deps)
	RemoteGuard.connect(channels.adminRequest, function(player: Player, payload: any)
		handler.onRequest(player, payload, os.clock())
	end)
	-- 관리자에게만 "관리자다" 한 번(그때만 클라가 창을 만든다)
	ProfileManager.onLoaded(function(player: Player)
		if AdminService.isAdmin(player) then
			print(string.format("[Admin] %s(%d) 관리자 — 관리 창 알림", player.Name, player.UserId))
			channels.adminResult:FireClient(player, { action = "hello", ok = true, reason = "", lines = {} })
		end
	end)
end

return AdminService

--!strict
-- 관리 도구 검증(지시서 #48 4부). 가짜 deps로 입구를 돌린다(실제 프로필 · 재화를 건드리지 않는다).
--   관리자 판정(주인 · 그룹 주인 · 지정 목록) · 관리자 아님 거부(답도 없음) · 잘못된 값 거부 · 관문 경유(사유 "admin") · 로그 · 분석 이벤트 ·
--   공지는 거른 글만 · 곡괭이 회수 순수 계산 · 분석 흐름에서 빠짐

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminService = require(ServerScriptService.Server.Systems.AdminService)
local InventoryService = require(ServerScriptService.Server.Systems.InventoryService)
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local AnalyticsConfig = require(ReplicatedStorage.Shared.Config.AnalyticsConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

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

local ADMIN = { Name = "admin", UserId = 100 }
local OTHER = { Name = "other", UserId = 200 }
local TARGET = { Name = "target", UserId = 7 }

-- 가짜 deps: 바꾸는 호출(관문)을 순서대로 적는다
local function makeDeps(opts: { admin: boolean?, gateOk: boolean?, filterOk: boolean? }?)
	local o = opts or {}
	local calls: { { name: string, args: { any } } } = {}
	local sent: { any } = {}
	local logs: { string } = {}
	local events: { { string } } = {}
	local refreshed = 0
	local broadcasts: { string } = {}
	local gateOk = o.gateOk ~= false
	local function mut(name: string)
		return function(...)
			table.insert(calls, { name = name, args = { ... } })
			return gateOk
		end
	end
	local deps: AdminService.Deps = {
		isAdmin = function(p: any)
			return o.admin ~= false and p == ADMIN
		end,
		findTarget = function(id: number): any?
			return if id == TARGET.UserId then TARGET else nil
		end,
		addCurrency = mut("addCurrency"),
		subCurrency = mut("subCurrency"),
		addOres = mut("addOres"),
		takeOres = mut("takeOres"),
		addTokens = mut("addTokens"),
		takeTokens = mut("takeTokens"),
		grantPickaxe = mut("grantPickaxe"),
		revokePickaxe = mut("revokePickaxe"),
		grantPet = mut("grantPet"),
		releasePet = mut("releasePet"),
		filterText = function(_a: any, text: string): (boolean, string?)
			if o.filterOk == false then
				return false, nil
			end
			return true, "[f]" .. text
		end,
		broadcast = function(text: string)
			table.insert(broadcasts, text)
		end,
		inspect = function(_t: any)
			return { "line1", "line2" }
		end,
		refresh = function()
			refreshed += 1
		end,
		send = function(_a: any, payload: any)
			table.insert(sent, payload)
		end,
		log = function(line: string)
			table.insert(logs, line)
		end,
		analytics = function(_a: any, action: string, kind: string)
			table.insert(events, { action, kind })
		end,
	}
	return AdminService.createHandler(deps), {
		calls = calls,
		sent = sent,
		logs = logs,
		events = events,
		broadcasts = broadcasts,
		refreshed = function()
			return refreshed
		end,
	}
end

local function req(action: string, kind: string, id: string, amount: number, text: string?): any
	return { action = action, target = TARGET.UserId, kind = kind, id = id, amount = amount, text = text or "" }
end

-- 1. 관리자 판정(순수) ------------------------------------------------------------------------------------
do
	local isAdmin = AdminConfig.isAdmin
	check("판정: 사용자 소유 = 그 사용자만 · 그룹 소유 = 그룹 주인 · 지정 목록 · 0 · 음수 · 글 아님",
		isAdmin(5, "User", 5, nil, {}) and not isAdmin(6, "User", 5, nil, {}) and isAdmin(9, "Group", 123, 9, {})
			and not isAdmin(123, "Group", 123, 9, {}) and not isAdmin(9, "Group", 123, nil, {}) and isAdmin(42, "User", 5, nil, { 42 })
			and not isAdmin(0, "User", 0, nil, {}) and not isAdmin(-5, "User", -5, nil, {}) and not isAdmin("5" :: any, "User", 5, nil, {}))
	check("판정: 커밋 목록은 사람이 정한 값만(지금 비어 있다 — 게임 주인만) · 실물 판정은 Player만", #AdminConfig.ADMIN_USER_IDS == 0
		and AdminConfig.validate() and not AdminService.isAdmin(ADMIN :: any))
end

-- 2. 관리자 아님: 어떤 요청이든 관문 · 답 · 로그 · 이벤트 0 -------------------------------------------------------
do
	local h, rec = makeDeps()
	local reqs = { req("grant", "coins", "", 100), req("revoke", "ore", "1", 1), req("inspect", "", "", 0), req("announce", "", "", 0, "hi") }
	for _, r in ipairs(reqs) do
		h.onRequest(OTHER, r)
	end
	check("관리자 아님: 4종 요청 → 관문 0 · 답 0(조용히 버림) · 로그 0 · 이벤트 0", #rec.calls == 0 and #rec.sent == 0 and #rec.logs == 0
		and #rec.events == 0 and #rec.broadcasts == 0)
end

-- 3. 관문 경유: 재화 · 광석 · 토큰 · 곡괭이 · 펫 — 사유 "admin" · 로그 · 이벤트 · 화면 갱신 ----------------------------------
do
	local h, rec = makeDeps()
	local petId = PetConfig.Eggs[1].pets[1].id
	local pick = EconomyV2Config.PICKAXES[2].id
	h.onRequest(ADMIN, req("grant", "coins", "", 100))
	h.onRequest(ADMIN, req("revoke", "blox", "", 5))
	h.onRequest(ADMIN, req("grant", "ore", "3", 5))
	h.onRequest(ADMIN, req("revoke", "token", "rare", 2))
	h.onRequest(ADMIN, req("grant", "pickaxe", pick, 3))
	h.onRequest(ADMIN, req("grant", "pet", petId, 2))
	h.onRequest(ADMIN, req("revoke", "pet", "12", 1))
	local names = {}
	local reasonsOk = true
	for _, c in ipairs(rec.calls) do
		table.insert(names, c.name)
		local reason = c.args[#c.args]
		if c.name ~= "releasePet" then
			reasonsOk = reasonsOk and reason == AdminConfig.REASON
		end
	end
	local want = { "addCurrency", "subCurrency", "addOres", "takeTokens", "grantPickaxe", "grantPickaxe", "grantPickaxe", "grantPet", "grantPet", "releasePet" }
	check("관문: 재화 CurrencyService · 광석 · 토큰 · 곡괭이 InventoryService · 펫 PetService(하나씩) — 순서 그대로",
		table.concat(names, ",") == table.concat(want, ","), table.concat(names, ","))
	local coin = rec.calls[1].args
	local ore = rec.calls[3].args
	check("관문 인자: 사유 admin · 코인 BigNum 100 · 광석 {3 = 5} · 대상 = 같은 서버 유저", reasonsOk and coin[1] == TARGET and coin[2] == "coins"
		and BigNum.eq(coin[3], BigNum.fromNumber(100)) and ore[2][3] == 5 and rec.calls[10].args[2] == "12")
	local allOk = true
	for _, p in ipairs(rec.sent) do
		allOk = allOk and p.ok == true
	end
	check("결과 · 기록: 7번 모두 성공 답 · 서버 로그 7줄([Admin]) · 분석 이벤트 7 · 받은 쪽 화면 갱신 7", allOk and #rec.sent == 7 and #rec.logs == 7
		and string.find(rec.logs[1], "[Admin]", 1, true) ~= nil and #rec.events == 7 and rec.events[1][1] == "grant" and rec.events[1][2] == "coins"
		and rec.refreshed() == 7)
end

-- 4. 잘못된 값: 관문까지 가지 않는다(답은 사유와 함께) ------------------------------------------------------------
do
	local h, rec = makeDeps()
	local bad = {
		req("grant", "coins", "", 0),
		req("grant", "coins", "", 1.5),
		req("grant", "coins", "", AdminConfig.MAX_CURRENCY * 10),
		req("grant", "ore", "3", AdminConfig.MAX_COUNT + 1),
		req("grant", "ore", "11", 1),
		req("grant", "ore", "x", 1),
		req("grant", "token", "gold", 1),
		req("grant", "pickaxe", "pick_nope", 1),
		req("grant", "pet", "nope_pet", 1),
		req("revoke", "pet", "12", 2),
		req("revoke", "pet", "abc", 1),
		req("grant", "nope", "", 1),
		{ action = "grant", target = 999, kind = "coins", id = "", amount = 1, text = "" },
		{ action = "grant", target = "7", kind = "coins", id = "", amount = 1, text = "" },
		{ action = "fly", target = 7, kind = "coins", id = "", amount = 1, text = "" },
		req("grant", "pet", PetConfig.Eggs[1].pets[1].id, AdminConfig.MAX_ITEMS + 1),
	}
	for _, r in ipairs(bad) do
		h.onRequest(ADMIN, r :: any)
	end
	local reasons = {}
	for _, p in ipairs(rec.sent) do
		table.insert(reasons, p.reason)
	end
	check("잘못된 값 16종: 관문 0 · 화면 갱신 0 · 답은 전부 실패", #rec.calls == 0 and rec.refreshed() == 0 and #rec.sent == #bad, table.concat(reasons, ","))
	local okAll = true
	for _, p in ipairs(rec.sent) do
		okAll = okAll and p.ok == false and type(p.reason) == "string" and p.reason ~= ""
	end
	check("잘못된 값: 답에 사유 코드(bad_amount · bad_id · bad_kind · no_target · bad_target · bad_action)", okAll)
end

-- 5. 관문이 거부하면(잔액 부족 등) 실패 답 · 갱신 없음 -----------------------------------------------------------
do
	local h, rec = makeDeps({ gateOk = false })
	h.onRequest(ADMIN, req("revoke", "coins", "", 10))
	check("관문 거부: 실패 답(gate_refused) · 화면 갱신 0 · 로그 · 이벤트는 남는다", #rec.sent == 1 and rec.sent[1].ok == false
		and rec.sent[1].reason == "gate_refused" and rec.refreshed() == 0 and #rec.logs == 1 and #rec.events == 1)
end

-- 6. 공지: 거른 글만 모두에게 · 거르기 실패 · 빈 글 · 긴 글 · 제어 문자는 안 보낸다 -------------------------------------
do
	local h, rec = makeDeps()
	h.onRequest(ADMIN, req("announce", "", "", 0, "server restarts soon"))
	check("공지: TextService로 거른 글을 그대로(원문이 아니라) 모두에게", #rec.broadcasts == 1 and rec.broadcasts[1] == "[f]server restarts soon"
		and rec.sent[1].ok == true and #rec.events == 1 and rec.events[1][1] == "announce")
	local h2, rec2 = makeDeps({ filterOk = false })
	h2.onRequest(ADMIN, req("announce", "", "", 0, "hello"))
	local h3, rec3 = makeDeps()
	for _, t in ipairs({ "", "   ", string.rep("가", AdminConfig.ANNOUNCE_MAX_CHARS + 1), "a\0b", "line\nbreak" }) do
		h3.onRequest(ADMIN, req("announce", "", "", 0, t))
	end
	check("공지: 거르기 실패면 안 보냄(filter_failed) · 빈 글 · 공백 · 긴 글 · 제어 문자 5종 안 보냄", #rec2.broadcasts == 0 and rec2.sent[1].reason == "filter_failed"
		and #rec3.broadcasts == 0 and #rec3.sent == 5)
	local hn, recn = makeDeps()
	hn.onRequest(OTHER, req("announce", "", "", 0, "hi"))
	check("공지: 관리자 아니면 거르기 · 방송 0", #recn.broadcasts == 0 and #recn.sent == 0)
end

-- 7. 상태 읽기: 바꾸지 않고 줄만 돌려준다 -----------------------------------------------------------------------
do
	local h, rec = makeDeps()
	h.onRequest(ADMIN, req("inspect", "", "", 0))
	check("상태 읽기: 관문 0 · 줄 2 · 로그 · 이벤트", #rec.calls == 0 and rec.sent[1].ok == true and #rec.sent[1].lines == 2 and #rec.logs == 1
		and rec.events[1][1] == "inspect")
end

-- 8. 곡괭이 회수(InventoryService 순수 계산) — 개수 −1 · 0이면 지움 · 장착 중인 마지막 하나는 거부 ------------------------
do
	local revoke = InventoryService._pure.applyRevokeEquipment
	local id = EconomyV2Config.PICKAXES[3].id
	local data = { equipment = { pickaxe = { [id] = { count = 2, stars = 0, enh = 0 } } }, equipped = { pickaxe = id } }
	local ok1 = revoke(data, "pickaxe", id)
	local afterOne = data.equipment.pickaxe[id] ~= nil and data.equipment.pickaxe[id].count == 1
	local ok2 = revoke(data, "pickaxe", id)
	data.equipped.pickaxe = "other"
	local ok3 = revoke(data, "pickaxe", id)
	local ok4 = revoke(data, "pickaxe", id)
	local ok5 = revoke(data, "pickaxe", "nope")
	check("곡괭이 회수: 2 → 1 · 장착 중 마지막은 거부 · 장착 아니면 지움 · 없는 것 · 모르는 것 거부", ok1 and afterOne and not ok2 and ok3
		and data.equipment.pickaxe[id] == nil and not ok4 and not ok5)
end

-- 9. 분석: 관리 도구 지급은 경제 흐름이 아니다(빠짐) · 커스텀 이벤트 admin_action ---------------------------------------
do
	check("분석: reason admin은 경제 흐름에서 빠지고(경고 없이) · admin_action 이벤트 이름 · 흐름표에 없음",
		AnalyticsConfig.SILENT_REASONS[AdminConfig.REASON] == true and AnalyticsConfig.EVENTS.adminAction == "admin_action"
			and AnalyticsConfig.classify(AdminConfig.REASON, "Blox") == nil)
end

print(string.format("[AdminServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AdminServiceTests] %d test(s) failed", failed))
end

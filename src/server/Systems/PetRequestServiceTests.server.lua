--!strict
-- PetRequestService 검증 (지시서 #12 3단계): payload 위생 · 빈도 상한 · 사유 코드 그대로 · 응답 필드 전부(선택 필드 금지) ·
-- 설정 hideOtherPets 저장(E10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local RollService = require(script.Parent.RollService)
local PetService = require(script.Parent.PetService)
local PetRequestService = require(script.Parent.PetRequestService)
local SettingsRequestService = require(script.Parent.SettingsRequestService)

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

local pure = PetRequestService._pure
local PET = PetConfig.Eggs[1].pets[3]
local P = ({} :: any) :: Player
local STEP = pure.MIN_INTERVAL_SEC + 0.01 -- 간격보다 조금 길게(10.2 − 10 < 0.2 같은 부동소수 오차)

local function complete(p: any): boolean
	return type(p.action) == "string" and type(p.ok) == "boolean" and type(p.reason) == "string" and type(p.uid) == "string"
		and type(p.petId) == "string" and type(p.eggId) == "number" and type(p.rarity) == "number" and type(p.level) == "number"
		and type(p.isNew) == "boolean" and type(p.equipped) == "boolean" and type(p.pets) == "table"
end

-- 1. readRequest -----------------------------------------------------------------------------------
do
	local r = pure.readRequest
	check("hatch: 알 번호", (r({ action = "hatch", egg = 2 }) :: any).egg == 2)
	check("hatch: 알 번호가 정수 · 1 이상이 아니면 nil", r({ action = "hatch", egg = 0 }) == nil and r({ action = "hatch", egg = 1.5 }) == nil
		and r({ action = "hatch", egg = "1" }) == nil and r({ action = "hatch" }) == nil and r({ action = "hatch", egg = 0 / 0 }) == nil)
	check("hatch: 다른 필드(비용 · 결과)는 버린다", (r({ action = "hatch", egg = 1, cost = 0, petId = PET.id }) :: any).petId == nil)
	for _, a in ipairs({ "equip", "unequip", "craft", "release" }) do
		check(a .. ": uid 숫자 문자열", (r({ action = a, uid = "12" }) :: any).uid == "12")
	end
	check("uid: 빈 문자열 · 숫자 아님 · 너무 김 · 숫자 타입은 nil", r({ action = "equip", uid = "" }) == nil and r({ action = "equip", uid = "a1" }) == nil
		and r({ action = "release", uid = string.rep("9", 13) }) == nil and r({ action = "craft", uid = 3 }) == nil)
	check("equipBest: 필드 없이", (r({ action = "equipBest" }) :: any).action == "equipBest")
	check("모르는 action · 표가 아님은 nil", r({ action = "buy", egg = 1 }) == nil and r("hatch") == nil and r(nil) == nil)
end

-- 2. 핸들러 ---------------------------------------------------------------------------------------
local function harness()
	local h = {
		sent = {} :: { any },
		calls = {} :: { string },
		hatchResult = { true, { uid = "7", petId = PET.id, eggId = 1, rarity = 3, level = 1, isNew = true, equipped = true } } :: { any },
	}
	local function simple(name: string)
		return function(_p, uid)
			table.insert(h.calls, name .. ":" .. tostring(uid))
			return uid == "7", if uid == "7" then nil else PetService.REASON_NOT_OWNED
		end
	end
	h.handler = pure.createHandler({
		hatch = function(_p, egg)
			table.insert(h.calls, "hatch:" .. egg)
			return h.hatchResult[1], h.hatchResult[2]
		end,
		equip = simple("equip"),
		unequip = simple("unequip"),
		release = simple("release"),
		equipBest = function(_p)
			table.insert(h.calls, "best")
			return true, nil
		end,
		craft = function(_p, uid)
			table.insert(h.calls, "craft:" .. uid)
			return false, PetService.REASON_NOT_ENOUGH
		end,
		send = function(_p, payload)
			table.insert(h.sent, payload)
		end,
	})
	return h
end

do
	local h = harness()
	local t = 10
	local out = h.handler.onRequest(P, { action = "hatch", egg = 1 }, t)
	check("hatch 성공 → 결과 그대로 · 응답 1건", out.ok and out.uid == "7" and out.petId == PET.id and out.rarity == 3 and out.isNew and out.equipped and #h.sent == 1)
	check("응답 필드 전부(선택 필드 금지)", complete(out))
	t += STEP
	h.hatchResult = { false, PetService.REASON_STORAGE_FULL }
	local full = h.handler.onRequest(P, { action = "hatch", egg = 1 }, t)
	check("hatch 거부 → 사유 코드 그대로(storage_full)", not full.ok and full.reason == PetService.REASON_STORAGE_FULL and complete(full) and full.uid == "")
	t += STEP
	local craft = h.handler.onRequest(P, { action = "craft", uid = "3" }, t)
	check("craft 거부 → not_enough 그대로", not craft.ok and craft.reason == PetService.REASON_NOT_ENOUGH and h.calls[#h.calls] == "craft:3")
	t += STEP
	local rel = h.handler.onRequest(P, { action = "release", uid = "8" }, t)
	check("release 거부 → not_owned 그대로", not rel.ok and rel.reason == PetService.REASON_NOT_OWNED)
	t += STEP
	local eq = h.handler.onRequest(P, { action = "equip", uid = "7" }, t)
	check("equip 성공 → uid 실어 보낸다", eq.ok and eq.uid == "7" and complete(eq))
	t += STEP
	local best = h.handler.onRequest(P, { action = "equipBest" }, t)
	check("equipBest → 서비스로", best.ok and h.calls[#h.calls] == "best")

	local calls = #h.calls
	local fast = h.handler.onRequest(P, { action = "hatch", egg = 1 }, t + pure.MIN_INTERVAL_SEC * 0.5)
	check("빈도 상한 → rate_limited · 서비스를 부르지 않는다 · 응답은 1건", not fast.ok and fast.reason == PetRequestService.REASON_RATE_LIMITED
		and #h.calls == calls and fast.action == "hatch")
	local bad = h.handler.onRequest(P, { action = "hatch", egg = "x" }, t + 5)
	check("잘못된 payload → invalid_request · 서비스를 부르지 않는다", not bad.ok and bad.reason == RollService.REASON_INVALID and #h.calls == calls
		and bad.action == "hatch" and complete(bad))
	local junk = h.handler.onRequest(P, "x", t + 10)
	check("payload가 표가 아니면 action \"\"", not junk.ok and junk.action == "")
	h.handler.onRemoving(P)
	check("나가면 빈도 기록을 지운다", h.handler.onRequest(P, { action = "equipBest" }, t + 10.05).ok)
end

-- 3. 설정 hideOtherPets (E10) ------------------------------------------------------------------------
do
	local cosmetics = { hideOtherAuras = false, hideOtherPets = false }
	local handler = SettingsRequestService._pure.createHandler({
		getCosmetics = function(_p)
			return cosmetics
		end,
		send = function() end,
	})
	local on = handler.onRequest(P, { key = "hideOtherPets", value = true }, 1)
	check("설정: hideOtherPets 저장 · 아우라 숨기기는 그대로", on.ok and cosmetics.hideOtherPets == true and cosmetics.hideOtherAuras == false)
	local bad = handler.onRequest(P, { key = "hideOtherPets", value = 1 }, 2)
	check("설정: hideOtherPets도 boolean만", not bad.ok and bad.reason == SettingsRequestService.REASON_BAD_VALUE and cosmetics.hideOtherPets == true)
end

-- 3. 3배 부화(지시서 #16 S18) — 결과 1건에 3마리 ---------------------------------------------------------------------
do
	check("hatch3: 알 번호를 받는다", (pure.readRequest({ action = "hatch3", egg = 2 }) :: any).egg == 2 and pure.readRequest({ action = "hatch3" }) == nil)
	local sent = {}
	local three = {
		{ uid = "7", petId = PET.id, eggId = 1, rarity = 3, level = 1, isNew = true, equipped = true },
		{ uid = "8", petId = PET.id, eggId = 1, rarity = 3, level = 1, isNew = false, equipped = false },
		{ uid = "9", petId = PET.id, eggId = 1, rarity = 3, level = 1, isNew = false, equipped = false },
	}
	local answer: { any } = { true, three }
	local handler = pure.createHandler({
		hatch = function(_p, _egg)
			return true, three[1]
		end,
		hatchMulti = function(_p, _egg)
			return answer[1], answer[2]
		end,
		equip = function()
			return true, nil
		end,
		unequip = function()
			return true, nil
		end,
		release = function()
			return true, nil
		end,
		equipBest = function()
			return true, nil
		end,
		craft = function()
			return false, PetService.REASON_NOT_ENOUGH
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
	})
	local out = handler.onRequest(P, { action = "hatch3", egg = 1 }, 10)
	check("hatch3 성공: 결과 1건 · pets 3마리 · 앞 필드는 첫 펫", out.ok and #sent == 1 and #out.pets == 3 and out.uid == "7"
		and out.pets[3].uid == "9" and out.pets[2].isNew == false and complete(out))
	answer = { false, PetService.REASON_HATCH_PASS_REQUIRED }
	local denied = handler.onRequest(P, { action = "hatch3", egg = 1 }, 10 + STEP)
	check("hatch3 거부: 사유 그대로(hatch_pass_required) · pets 빈 목록", not denied.ok and denied.reason == PetService.REASON_HATCH_PASS_REQUIRED
		and #denied.pets == 0 and complete(denied))
	local one = handler.onRequest(P, { action = "hatch", egg = 1 }, 10 + STEP * 2)
	check("보통 hatch: pets에 1마리(앞 필드와 같은 펫)", one.ok and #one.pets == 1 and one.pets[1].uid == one.uid)
	local eq = handler.onRequest(P, { action = "equip", uid = "7" }, 10 + STEP * 3)
	check("hatch 아닌 action: pets 빈 목록", eq.ok and #eq.pets == 0)
end

print(string.format("[PetRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PetRequestServiceTests] %d test(s) failed", failed))
end

--!strict
-- AuraRequestService · SettingsRequestService 검증 (지시서 #11 4단계): payload 위생 · 빈도 상한 · 사유 코드 그대로 ·
-- 응답 필드 전부(선택 필드 금지) · 설정 화이트리스트(허용 키 · 타입).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local RollService = require(script.Parent.RollService)
local AuraRequestService = require(script.Parent.AuraRequestService)
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

local pure = AuraRequestService._pure
local ID = AuraConfig.Packs[1].auras[2].id
local P = ({} :: any) :: Player

local function complete(p: any): boolean
	return type(p.action) == "string" and type(p.ok) == "boolean" and type(p.reason) == "string" and type(p.auraId) == "string"
		and type(p.packId) == "number" and type(p.tier) == "number" and type(p.isNew) == "boolean" and type(p.equipped) == "boolean"
end

-- 1. readRequest -----------------------------------------------------------------------------------
do
	local r = pure.readRequest
	check("roll: 팩 번호", (r({ action = "roll", pack = 2 }) :: any).pack == 2)
	check("roll: 팩 번호가 정수 · 1 이상이 아니면 nil", r({ action = "roll", pack = 0 }) == nil and r({ action = "roll", pack = 1.5 }) == nil
		and r({ action = "roll", pack = "1" }) == nil and r({ action = "roll" }) == nil and r({ action = "roll", pack = 0 / 0 }) == nil)
	check("roll: 다른 필드(비용 · 결과)는 버린다", (r({ action = "roll", pack = 1, cost = 0, auraId = ID }) :: any).auraId == nil)
	check("equip: auraId 문자열", (r({ action = "equip", auraId = ID }) :: any).auraId == ID)
	check("equip: 빈 문자열 · 너무 김 · 숫자는 nil", r({ action = "equip", auraId = "" }) == nil and r({ action = "equip", auraId = string.rep("a", 65) }) == nil
		and r({ action = "equip", auraId = 3 }) == nil)
	check("selectPack: 팩 번호", (r({ action = "selectPack", pack = 3 }) :: any).pack == 3)
	check("모르는 action · 표가 아님은 nil", r({ action = "buy", pack = 1 }) == nil and r("roll") == nil and r(nil) == nil)
end

-- 2. 핸들러 ---------------------------------------------------------------------------------------
local function harness()
	local h = { sent = {} :: { any }, calls = {} :: { string }, rollResult = { true, { auraId = ID, packId = 1, tier = 2, isNew = true, equipped = true } } :: { any } }
	h.handler = pure.createHandler({
		roll = function(_p, pack)
			table.insert(h.calls, "roll:" .. pack)
			return h.rollResult[1], h.rollResult[2]
		end,
		equip = function(_p, id)
			table.insert(h.calls, "equip:" .. id)
			return id == ID, if id == ID then nil else "not_owned"
		end,
		selectPack = function(_p, pack)
			table.insert(h.calls, "select:" .. pack)
			return true, nil
		end,
		send = function(_p, payload)
			table.insert(h.sent, payload)
		end,
	})
	return h
end

do
	local h = harness()
	local out = h.handler.onRequest(P, { action = "roll", pack = 1 }, 10)
	check("roll 성공: 결과를 그대로 · 응답 1건 · 필드 전부", out.ok and out.auraId == ID and out.packId == 1 and out.tier == 2 and out.isNew and out.equipped
		and #h.sent == 1 and complete(out))
	local fast = h.handler.onRequest(P, { action = "roll", pack = 1 }, 10 + pure.MIN_INTERVAL_SEC * 0.5)
	check("빈도 상한 → rate_limited · 서비스 안 부름 · 필드 전부", not fast.ok and fast.reason == AuraRequestService.REASON_RATE_LIMITED and #h.calls == 1 and complete(fast))
	h.rollResult = { false, "pack_locked" }
	local locked = h.handler.onRequest(P, { action = "roll", pack = 3 }, 11)
	check("서비스 거부 사유를 그대로", not locked.ok and locked.reason == "pack_locked" and locked.auraId == "" and locked.packId == 0 and complete(locked))
	local bad = h.handler.onRequest(P, { action = "roll", pack = -1 }, 12)
	check("형태가 틀린 요청 → invalid_request · 서비스 안 부름", not bad.ok and bad.reason == RollService.REASON_INVALID and bad.action == "roll" and #h.calls == 2)
	local eq = h.handler.onRequest(P, { action = "equip", auraId = ID }, 13)
	check("equip 성공: auraId · equipped", eq.ok and eq.auraId == ID and eq.equipped)
	local no = h.handler.onRequest(P, { action = "equip", auraId = "other" }, 14)
	check("equip 거부: 사유 그대로 · equipped false", not no.ok and no.reason == "not_owned" and not no.equipped and complete(no))
	local sel = h.handler.onRequest(P, { action = "selectPack", pack = 2 }, 15)
	check("selectPack 성공: packId", sel.ok and sel.packId == 2 and h.calls[#h.calls] == "select:2")
	h.handler.onRemoving(P)
	check("퇴장하면 빈도 기록을 지운다", (h.handler.onRequest(P, { action = "selectPack", pack = 1 }, 15)).ok)
end

-- 3. 설정 화이트리스트 -------------------------------------------------------------------------------
do
	local cosmetics = { hideOtherAuras = false, equippedAura = false }
	local sent = {}
	local handler = SettingsRequestService._pure.createHandler({
		getCosmetics = function(_p)
			return cosmetics
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
	})
	local t = 0
	local function req(payload: any)
		t += 1
		return handler.onRequest(P, payload, t)
	end
	local ok = req({ key = "hideOtherAuras", value = true })
	check("설정: 허용 키 · bool → 저장", ok.ok and cosmetics.hideOtherAuras == true and ok.value == true and #sent == 1)
	local other = req({ key = "equippedAura", value = "pack5_legendary" })
	check("설정: 허용 밖 키(장착 아우라 등) → not_allowed · 그대로", not other.ok and other.reason == SettingsRequestService.REASON_NOT_ALLOWED and cosmetics.equippedAura == false)
	local badType = req({ key = "hideOtherAuras", value = "false" })
	check("설정: 타입이 틀리면 bad_value · 그대로", not badType.ok and badType.reason == SettingsRequestService.REASON_BAD_VALUE and cosmetics.hideOtherAuras == true)
	local junk = req("x")
	check("설정: payload가 표가 아니면 not_allowed", not junk.ok and junk.reason == SettingsRequestService.REASON_NOT_ALLOWED and junk.key == "")
	local fast = handler.onRequest(P, { key = "hideOtherAuras", value = false }, t + SettingsRequestService._pure.MIN_INTERVAL_SEC * 0.5)
	check("설정: 빈도 상한 → rate_limited · 그대로", not fast.ok and fast.reason == SettingsRequestService.REASON_RATE_LIMITED and cosmetics.hideOtherAuras == true)
	check("설정: 허용 키는 hideOtherAuras 하나 (펫은 #12)", SettingsRequestService.ALLOWED.hideOtherAuras == "boolean" and SettingsRequestService.ALLOWED.hideOtherPets == nil)
	local handler2 = SettingsRequestService._pure.createHandler({
		getCosmetics = function(_p)
			return nil
		end,
		send = function() end,
	})
	check("설정: 프로필 없음 → no_profile", handler2.onRequest(P, { key = "hideOtherAuras", value = true }, 1).reason == SettingsRequestService.REASON_NO_PROFILE)
end

print(string.format("[AuraRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AuraRequestServiceTests] %d test(s) failed", failed))
end

--!strict
-- TitleRequestService 검증 (지시서 #10 4단계): payload 위생 · 빈도 상한 · 사유 코드를 그대로 돌려준다 ·
-- 응답 필드가 전부 채워진다(선택 필드 금지) · 자동 롤 신규 알림 모양. 서비스는 가짜 deps다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local RollService = require(script.Parent.RollService)
local TitleRequestService = require(script.Parent.TitleRequestService)

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

local pure = TitleRequestService._pure
local ID = TitleConfig.Titles[2].id

-- 1. readRequest ------------------------------------------------------------------------------------
do
	local r = pure.readRequest
	check("roll", r({ action = "roll" }) ~= nil and (r({ action = "roll" }) :: any).action == "roll")
	check("roll: 다른 필드는 버린다", (r({ action = "roll", titleId = "x", cost = 0 }) :: any).titleId == nil)
	check("equip: titleId 문자열", (r({ action = "equip", titleId = ID }) :: any).titleId == ID)
	check("equip: titleId 없음 · 빈 문자열 · 너무 김 · 숫자는 nil",
		r({ action = "equip" }) == nil and r({ action = "equip", titleId = "" }) == nil
			and r({ action = "equip", titleId = string.rep("a", 65) }) == nil and r({ action = "equip", titleId = 3 }) == nil)
	check("setAuto: on boolean", (r({ action = "setAuto", on = true }) :: any).on == true and (r({ action = "setAuto", on = false }) :: any).on == false)
	check("setAuto: on이 boolean이 아니면 nil", r({ action = "setAuto", on = "true" }) == nil and r({ action = "setAuto" }) == nil)
	check("모르는 action · payload가 표가 아님은 nil", r({ action = "autoRoll" }) == nil and r({ action = "buy" }) == nil and r("roll") == nil and r(nil) == nil)
end

-- 2. 핸들러 ------------------------------------------------------------------------------------------
local function harness()
	local h = {
		sent = {} :: { any },
		calls = {} :: { string },
		rollResult = { true, { titleId = ID, index = 2, isNew = true, equipped = true } } :: { any },
	}
	h.handler = pure.createHandler({
		roll = function(_p)
			table.insert(h.calls, "roll")
			return h.rollResult[1], h.rollResult[2]
		end,
		equip = function(_p, id)
			table.insert(h.calls, "equip:" .. id)
			if id == ID then
				return true, nil
			end
			return false, "not_owned"
		end,
		setAutoRoll = function(_p, on)
			table.insert(h.calls, "auto:" .. tostring(on))
			return true, nil
		end,
		send = function(_p, payload)
			table.insert(h.sent, payload)
		end,
	})
	return h
end

local function complete(p: any): boolean
	return type(p.action) == "string" and type(p.ok) == "boolean" and type(p.reason) == "string"
		and type(p.titleId) == "string" and type(p.isNew) == "boolean" and type(p.equipped) == "boolean"
end

local P = ({} :: any) :: Player

do
	local h = harness()
	local out = h.handler.onRequest(P, { action = "roll" }, 10)
	check("roll 성공: 결과를 그대로 싣는다", out.ok and out.titleId == ID and out.isNew and out.equipped and out.reason == "" and out.action == "roll")
	check("roll 성공: 응답 1건 · 필드 전부", #h.sent == 1 and complete(h.sent[1]))

	local out2 = h.handler.onRequest(P, { action = "roll" }, 10 + pure.MIN_INTERVAL_SEC * 0.5)
	check("빈도 상한 안 → rate_limited, 서비스 안 부름", not out2.ok and out2.reason == TitleRequestService.REASON_RATE_LIMITED and #h.calls == 1)
	check("rate_limited 응답도 필드 전부", complete(out2) and out2.action == "roll")

	h.rollResult = { false, RollService.REASON_INSUFFICIENT_BLOX }
	local out3 = h.handler.onRequest(P, { action = "roll" }, 11)
	check("서비스 거부 사유를 그대로", not out3.ok and out3.reason == RollService.REASON_INSUFFICIENT_BLOX and out3.titleId == "" and complete(out3))
end

do
	local h = harness()
	local bad = h.handler.onRequest(P, { action = "equip", titleId = 5 }, 1)
	check("형태가 틀린 equip → invalid_request, 서비스 안 부름", not bad.ok and bad.reason == RollService.REASON_INVALID and bad.action == "equip" and #h.calls == 0)
	local junk = h.handler.onRequest(P, "hello", 2)
	check("payload가 표가 아님 → invalid_request · action \"\"", not junk.ok and junk.reason == RollService.REASON_INVALID and junk.action == "" and complete(junk))
	local ok = h.handler.onRequest(P, { action = "equip", titleId = ID }, 3)
	check("equip 성공: titleId · equipped", ok.ok and ok.titleId == ID and ok.equipped and h.calls[1] == "equip:" .. ID)
	local no = h.handler.onRequest(P, { action = "equip", titleId = "other" }, 4)
	check("equip 거부: 사유 그대로 · equipped false", not no.ok and no.reason == "not_owned" and not no.equipped)
	local auto = h.handler.onRequest(P, { action = "setAuto", on = true }, 5)
	check("setAuto: 서비스에 boolean 전달 · 성공", auto.ok and auto.action == "setAuto" and h.calls[#h.calls] == "auto:true" and complete(auto))
end

do
	local h = harness()
	h.handler.onRequest(P, { action = "roll" }, 1)
	h.handler.onRemoving(P)
	local again = h.handler.onRequest(P, { action = "roll" }, 1)
	check("퇴장하면 빈도 기록을 지운다", again.ok)
end

-- 3. 자동 롤 신규 알림 -------------------------------------------------------------------------------
do
	local p = pure.autoNewPayload({ titleId = ID, index = 2, isNew = true, equipped = false })
	check("자동 롤 알림: action autoRoll · ok · 필드 전부", p.action == TitleRequestService.ACTION_AUTO_ROLL and p.ok and p.isNew and not p.equipped and complete(p))
end

print(string.format("[TitleRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TitleRequestServiceTests] %d test(s) failed", failed))
end

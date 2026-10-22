--!strict
-- RebirthRequestService 검증: 거부 경로(블럭스 부족 · 빈도 상한 · 부분 실패) · 성공 결과 형태.
-- 실제 RebirthService 대신 기록용 deps로 굴린다 — 프로필을 건드리지 않는다.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local RebirthService = require(ServerScriptService.Server.Systems.RebirthService)
local RebirthRequestService = require(ServerScriptService.Server.Systems.RebirthRequestService)

local pure = RebirthRequestService._pure

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

local fakePlayer: any = { Name = "RebirthRequestTest", UserId = 1 }

local function newWorld(answer: () -> (boolean, any))
	local w = { calls = 0, sent = {} :: { any } }
	local handler = pure.createHandler({
		rebirth = function(_player)
			w.calls += 1
			return answer()
		end,
		send = function(_player, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w, handler
end

do
	local w, handler = newWorld(function()
		return false, RebirthService.REASON_NOT_ENOUGH_BLOX
	end)
	local r = handler.onRequest(fakePlayer, 10)
	check("거부: 블럭스 부족은 서버 판정 사유 그대로", r.ok == false and r.reason == RebirthService.REASON_NOT_ENOUGH_BLOX)
	check("거부: 결과를 클라에 보낸다", #w.sent == 1 and w.sent[1] == r)
	check("거부: gained는 0으로 채운다(선택 필드 없음)", BigNum.eq(r.gained, BigNum.new(0, 0)))
end

do
	local w, handler = newWorld(function()
		return true, { gained = BigNum.new(3, 0), total = BigNum.new(31, 0) }
	end)
	local r1 = handler.onRequest(fakePlayer, 100)
	check("성공: ok와 얻은 배수", r1.ok == true and r1.reason == "" and BigNum.eq(r1.gained, BigNum.new(3, 0)))
	local r2 = handler.onRequest(fakePlayer, 100 + pure.MIN_INTERVAL_SEC / 2)
	check("빈도: 간격 안의 두 번째 요청은 rate_limited", r2.ok == false and r2.reason == RebirthRequestService.REASON_RATE_LIMITED)
	check("빈도: 상한에 걸린 요청은 환생을 부르지 않는다", w.calls == 1, tostring(w.calls))
	local r3 = handler.onRequest(fakePlayer, 100 + pure.MIN_INTERVAL_SEC + 0.01)
	check("빈도: 간격이 지나면 다시 받는다", r3.ok == true and w.calls == 2)
	handler.onRemoving(fakePlayer)
	local r4 = handler.onRequest(fakePlayer, 100 + pure.MIN_INTERVAL_SEC + 0.02)
	check("퇴장: 기록을 지워 다음 접속 첫 요청은 바로 받는다", r4.ok == true and w.calls == 3)
end

do
	local _w, handler = newWorld(function()
		return false, RebirthService.REASON_PARTIAL_FAILURE
	end)
	local r = handler.onRequest(fakePlayer, 0)
	check("부분 실패: 사유를 그대로 전달 (UI가 '문제 발생'으로 매핑)", r.ok == false and r.reason == RebirthService.REASON_PARTIAL_FAILURE)
end

do
	local _w, handler = newWorld(function()
		return false, nil
	end)
	local r = handler.onRequest(fakePlayer, 0)
	check("이상한 반환: 사유가 없으면 unknown", r.ok == false and r.reason == "unknown")
end

print(string.format("[RebirthRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RebirthRequestServiceTests] %d test(s) failed", failed))
end

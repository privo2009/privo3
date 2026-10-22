--!strict
-- WarpRequestService 검증: payload 거르기(잘못된 층) · 빈도 상한 · 서버 판정 사유 전달(런 중 · 블럭스 부족) ·
-- 성공 결과 형태. 실제 WarpService 대신 기록용 deps로 굴린다 — 프로필을 건드리지 않는다.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local WarpService = require(ServerScriptService.Server.Systems.WarpService)
local WarpRequestService = require(ServerScriptService.Server.Systems.WarpRequestService)

local pure = WarpRequestService._pure

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

local fakePlayer: any = { Name = "WarpRequestTest", UserId = 1 }

local function newWorld(answer: (number) -> (boolean, any))
	local w = { calls = {} :: { number }, sent = {} :: { any } }
	local handler = pure.createHandler({
		warp = function(_player, stage)
			table.insert(w.calls, stage)
			return answer(stage)
		end,
		send = function(_player, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w, handler
end

check("payload: 숫자 층은 통과", pure.readStage({ stage = 3 }) == 3)
check("payload: 문자열은 nil", pure.readStage({ stage = "3" }) == nil)
check("payload: nan은 nil", pure.readStage({ stage = 0 / 0 }) == nil)
check("payload: 테이블이 아니면 nil", pure.readStage(3) == nil)

do
	local w, handler = newWorld(function()
		return true, BigNum.new(9, 1)
	end)
	local r = handler.onRequest(fakePlayer, { stage = "abc" }, 0)
	check("거부: 잘못된 층은 invalid_stage, 워프를 부르지 않는다", r.ok == false and r.reason == WarpService.REASON_INVALID_STAGE and #w.calls == 0)
end

do
	local _w, handler = newWorld(function()
		return false, WarpService.REASON_RUN_ACTIVE
	end)
	local r = handler.onRequest(fakePlayer, { stage = 3 }, 0)
	check("거부: 런 중(W1)은 서버 판정 사유 그대로", r.ok == false and r.reason == WarpService.REASON_RUN_ACTIVE and r.stage == 3)
	check("거부: cost는 0으로 채운다", BigNum.eq(r.cost, BigNum.new(0, 0)))
end

do
	local _w, handler = newWorld(function()
		return false, WarpService.REASON_INSUFFICIENT_BLOX
	end)
	local r = handler.onRequest(fakePlayer, { stage = 5 }, 0)
	check("거부: 블럭스 부족 사유 그대로", r.ok == false and r.reason == WarpService.REASON_INSUFFICIENT_BLOX)
end

do
	local w, handler = newWorld(function()
		return true, BigNum.new(9, 1)
	end)
	local r1 = handler.onRequest(fakePlayer, { stage = 3 }, 10)
	check("성공: ok · 층 · 비용", r1.ok == true and r1.reason == "" and r1.stage == 3 and BigNum.eq(r1.cost, BigNum.new(9, 1)))
	local r2 = handler.onRequest(fakePlayer, { stage = 3 }, 10 + pure.MIN_INTERVAL_SEC / 2)
	check("빈도: 간격 안의 두 번째는 rate_limited, 워프를 부르지 않는다", r2.ok == false and r2.reason == WarpRequestService.REASON_RATE_LIMITED and #w.calls == 1)
	local r3 = handler.onRequest(fakePlayer, { stage = 4 }, 10 + pure.MIN_INTERVAL_SEC + 0.01)
	check("빈도: 간격이 지나면 다시 받는다", r3.ok == true and #w.calls == 2)
	check("결과는 매번 클라에 보낸다", #w.sent == 3)
end

print(string.format("[WarpRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[WarpRequestServiceTests] %d test(s) failed", failed))
end

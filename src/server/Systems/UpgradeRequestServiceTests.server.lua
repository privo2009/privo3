--!strict
-- UpgradeRequestService 검증 (지시서 #7): payload 거르기(잘못된 이름) · 빈도 상한(중복 요청) · 서버 판정 사유 전달 ·
-- 성공 결과 형태. 실제 UpgradeService 대신 기록용 deps로 굴린다 — 프로필을 건드리지 않는다.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local UpgradeRequestService = require(ServerScriptService.Server.Systems.UpgradeRequestService)

local pure = UpgradeRequestService._pure

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

local fakePlayer: any = { Name = "UpgradeRequestTest", UserId = 1 }

local function newWorld(answer: (string) -> (boolean, any))
	local w = { calls = {} :: { string }, sent = {} :: { any } }
	local handler = pure.createHandler({
		buy = function(_player, name)
			table.insert(w.calls, name)
			return answer(name)
		end,
		send = function(_player, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w, handler
end

check("payload: 문자열 이름은 통과", pure.readName({ name = "punchDamage" }) == "punchDamage")
check("payload: 숫자 · 빈 문자열 · 너무 긴 이름은 nil", pure.readName({ name = 3 }) == nil and pure.readName({ name = "" }) == nil
	and pure.readName({ name = string.rep("a", 65) }) == nil)
check("payload: 테이블이 아니면 nil", pure.readName("punchDamage") == nil)

do
	local w, handler = newWorld(function()
		return true, { name = "x", level = 1, cost = BigNum.new(1, 1) }
	end)
	local r = handler.onRequest(fakePlayer, { name = 42 }, 0)
	check("거부: 잘못된 이름 형태는 invalid_upgrade, 구매를 부르지 않는다", r.ok == false and r.reason == UpgradeConfig.REASON_INVALID_UPGRADE and #w.calls == 0)
	check("거부: 결과가 클라로 한 번 나간다", #w.sent == 1)
end

for _, reason in ipairs({ UpgradeConfig.REASON_MAX_LEVEL, UpgradeConfig.REASON_INSUFFICIENT_BLOX, UpgradeConfig.REASON_INVALID_UPGRADE }) do
	local _w, handler = newWorld(function()
		return false, reason
	end)
	local r = handler.onRequest(fakePlayer, { name = "punchSpeed" }, 0)
	check("거부: 서버 판정 사유 그대로 — " .. reason, r.ok == false and r.reason == reason and r.name == "punchSpeed"
		and r.level == 0 and BigNum.eq(r.cost, BigNum.new(0, 0)))
end

do
	local w, handler = newWorld(function(name)
		return true, { name = name, level = 3, cost = BigNum.new(1.44, 1) }
	end)
	local r1 = handler.onRequest(fakePlayer, { name = "punchSpeed" }, 10)
	check("성공: ok · 이름 · 레벨 · 비용", r1.ok == true and r1.reason == "" and r1.name == "punchSpeed" and r1.level == 3
		and BigNum.eq(r1.cost, BigNum.new(1.44, 1)))
	local r2 = handler.onRequest(fakePlayer, { name = "punchSpeed" }, 10 + pure.MIN_INTERVAL_SEC / 2)
	check("빈도: 간격 안의 두 번째(중복 요청)는 rate_limited, 구매를 부르지 않는다", r2.ok == false
		and r2.reason == UpgradeRequestService.REASON_RATE_LIMITED and #w.calls == 1)
	local r3 = handler.onRequest(fakePlayer, { name = "moveSpeed" }, 10 + pure.MIN_INTERVAL_SEC + 0.01)
	check("빈도: 간격이 지나면 다시 받는다", r3.ok == true and #w.calls == 2)
	check("빈도: 정상 유저의 빠른 반복 구매는 막지 않을 만큼 짧다(1초 미만)", pure.MIN_INTERVAL_SEC < 1)
	handler.onRemoving(fakePlayer)
	local r4 = handler.onRequest(fakePlayer, { name = "moveSpeed" }, 10 + pure.MIN_INTERVAL_SEC + 0.02)
	check("퇴장 뒤 기록이 지워진다", r4.ok == true)
end

print(string.format("[UpgradeRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UpgradeRequestServiceTests] %d test(s) failed", failed))
end

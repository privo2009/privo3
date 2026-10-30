--!strict
-- PotionRequestService 검증 (지시서 #17 4단계 — DESIGN 9장 "포션 켜기"). 가짜 프로필 · 가짜 부스트로 굴린다(실제 프로필 무변경).
--   payload 거르기 · 빈도 · 판정 순서(invalid · restricted · none_owned) · 켜기(보관 −1 · 부스트 더하기 · 알림) ·
--   부스트 실패면 보관 되돌림 · 같은 종류 두 번 = 시간 연장(BoostService 순수 함수로)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Schema = require(ServerScriptService.Server.Data.Schema)
local BoostService = require(ServerScriptService.Server.Systems.BoostService)
local PotionRequestService = require(ServerScriptService.Server.Systems.PotionRequestService)

local pure = PotionRequestService._pure
local R = PotionRequestService

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

local player: any = { Name = "PotionTest", UserId = 821 }
local STEP = pure.MIN_INTERVAL_SEC

local function newWorld(opts: { restricted: boolean?, boostFails: boolean? }?)
	local o = opts or {}
	local w: any = { data = Schema.new(), sent = {}, notified = 0 }
	w.handler = pure.createHandler({
		getData = function()
			return w.data
		end,
		isRestricted = function()
			return o.restricted == true
		end,
		addBoost = function(_p, boostType: string)
			if o.boostFails then
				return false
			end
			return BoostService._pure.addBoost(w.data.boosts, boostType)
		end,
		notify = function()
			w.notified += 1
		end,
		send = function(_p, payload)
			table.insert(w.sent, payload)
		end,
	})
	return w
end

-- 1. payload ---------------------------------------------------------------------------------------
check("payload: 아는 종류만", pure.readBoost({ boost = "strength" }) == "strength" and pure.readBoost({ boost = "luck" }) == "luck"
	and pure.readBoost({ boost = "victory" }) == nil and pure.readBoost({ boost = 1 }) == nil and pure.readBoost("strength") == nil)

-- 2. 판정 순서 · 켜기 ----------------------------------------------------------------------------------
do
	local w = newWorld()
	local t = 0
	local function ask(boost: any)
		t += STEP
		return w.handler.onRequest(player, { boost = boost }, t)
	end
	local r1 = ask("nope")
	check("없는 종류 → invalid · boost \"\"", not r1.ok and r1.reason == R.REASON_INVALID and r1.boost == "")
	local r2 = ask("strength")
	check("보관 0 → none_owned · 부스트 없음 · 알림 없음", not r2.ok and r2.reason == R.REASON_NONE_OWNED and #w.data.boosts == 0 and w.notified == 0)
	w.data.potions.strength = 2
	local r3 = ask("strength")
	local dur = ShopConfig.BOOSTS.strength.durationSec
	check("켜기 → 보관 −1 · 부스트(힘 ×2 · durationSec) · 알림 1", r3.ok and r3.reason == "" and w.data.potions.strength == 1
		and #w.data.boosts == 1 and w.data.boosts[1].type == "strength" and w.data.boosts[1].mult == ShopConfig.BOOSTS.strength.mult
		and w.data.boosts[1].remainingSec == dur and w.notified == 1)
	local r4 = ask("strength")
	check("같은 종류 또 켜기 → 시간 연장(2 × durationSec) · 줄은 하나 · 보관 0", r4.ok and w.data.potions.strength == 0 and #w.data.boosts == 1
		and w.data.boosts[1].remainingSec == dur * 2)
	check("요청마다 결과 1건", #w.sent == 4)
	local ok, errs = Schema.validate(w.data)
	check("켠 뒤 프로필이 스키마를 통과한다", ok, table.concat(errs or {}, "; "))
end

-- 3. 제한 유저 · 부스트 실패 --------------------------------------------------------------------------
do
	local w = newWorld({ restricted = true })
	w.data.potions.luck = 3
	w.data.potions.damage = 1
	local r1 = w.handler.onRequest(player, { boost = "luck" }, 0)
	check("제한 유저 + 행운 포션 → restricted · 보관 그대로(3)", not r1.ok and r1.reason == R.REASON_RESTRICTED and w.data.potions.luck == 3
		and #w.data.boosts == 0)
	local r2 = w.handler.onRequest(player, { boost = "damage" }, STEP)
	check("제한 유저라도 행운이 아닌 포션은 켠다", r2.ok and w.data.potions.damage == 0)
	local wf = newWorld({ boostFails = true })
	wf.data.potions.damage = 1
	local r3 = wf.handler.onRequest(player, { boost = "damage" }, 0)
	check("부스트 더하기 실패 → invalid · 보관을 되돌린다(1)", not r3.ok and r3.reason == R.REASON_INVALID and wf.data.potions.damage == 1 and wf.notified == 0)
end

-- 4. 빈도 --------------------------------------------------------------------------------------------
do
	local w = newWorld()
	w.data.potions.strength = 5
	w.handler.onRequest(player, { boost = "strength" }, 10)
	local r = w.handler.onRequest(player, { boost = "strength" }, 10 + STEP * 0.5)
	check("빈도: MIN_INTERVAL_SEC 안 두 번째 → rate_limited · 보관 한 번만 줄었다", not r.ok and r.reason == R.REASON_RATE_LIMITED
		and w.data.potions.strength == 4)
	w.handler.onRemoving(player)
	check("빈도: 나가면 지운다", w.handler.onRequest(player, { boost = "strength" }, 10 + STEP * 0.6).ok)
end

print(string.format("[PotionRequestServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PotionRequestServiceTests] %d test(s) failed", failed))
end

--!strict
-- HUD 활성 부스트 남은 시간 문구 (Phase 8 지시서 #16 5단계 — docs/UI.md "지시서 #16"). 순수 모듈 — 화면은 Screens/Hud/BoostTimers.
--
-- 값은 서버 PlayerState shop.boosts(Store "shop")다. 서버는 남은 초를 매초 보내지 않는다(BOOST_RESYNC_SEC) —
-- 클라가 받은 시각(receivedAt) 뒤로 센다: 남은 = remainingSec − (지금 − receivedAt). 0 이하면 그 줄은 빠진다(곧 서버도 지운다).
-- 줄 = "힘 ×2 14:32"(1시간 이상이면 "1:02:03" — 꼴은 Strings "hud.boost.line"). 순서는 서버가 보낸 순서(ShopConfig.BOOST_ORDER).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)

local BoostTimersLogic = {}

BoostTimersLogic.MAX_LINES = 3 -- 부스트 종류 수(ShopConfig.BOOST_ORDER) — 화면이 이만큼 줄을 만든다

function BoostTimersLogic.clockText(sec: number): string
	local s = math.max(0, math.ceil(sec))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

local function multText(mult: number): string
	if mult == math.floor(mult) then
		return string.format("×%d", mult)
	end
	return string.format("×%.1f", mult)
end

-- 지금 보일 줄들. 활성이 없으면 빈 목록(화면은 숨긴다).
function BoostTimersLogic.lines(shop: any, now: number): { string }
	local out: { string } = {}
	if type(shop) ~= "table" or type(shop.boosts) ~= "table" then
		return out
	end
	for _, b in ipairs(shop.boosts) do
		if type(b) == "table" and type(b.remainingSec) == "number" then
			local receivedAt = if type(b.receivedAt) == "number" then b.receivedAt else now
			local left = b.remainingSec - math.max(0, now - receivedAt)
			if left > 0 and #out < BoostTimersLogic.MAX_LINES then
				local name = if type(b.type) == "string" and Locale.has("boost." .. b.type .. ".short") then Names.boost(b.type, true) else tostring(b.type)
				table.insert(out, Locale.t("hud.boost.line", { name = name, mult = multText(if type(b.mult) == "number" then b.mult else 1),
					time = BoostTimersLogic.clockText(left) }))
			end
		end
	end
	return out
end

return BoostTimersLogic

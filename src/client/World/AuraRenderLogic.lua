--!strict
-- 아우라 파티클 방출량 결정 (Phase 7 지시서 #11 A7). 순수 모듈 — 렌더러는 World/AuraRenderer.
--
--   한 캐릭터 방출량 = AuraConfig.PARTICLE.RATE_BY_TIER[등급]. 장착이 없거나 모르는 id면 0.
--   다른 사람 아우라는 내 hideOtherAuras가 켜져 있으면 0(내 아우라는 언제나 보인다).
--   이 클라가 그리는 전체 합이 MAX_TOTAL_RATE를 넘으면 전부 같은 비율로 줄인다(사람이 많아도 상한을 지킨다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)

local AuraRenderLogic = {}

export type Entry = { auraId: any, isLocal: boolean }

-- entries와 같은 순서의 방출량 배열.
function AuraRenderLogic.rates(entries: { Entry }, hideOthers: boolean): { number }
	local out: { number } = {}
	local total = 0
	for i, e in ipairs(entries) do
		local _, _, tier = AuraConfig.get(e.auraId)
		local rate = 0
		if tier ~= nil and (e.isLocal or not hideOthers) then
			rate = AuraConfig.PARTICLE.RATE_BY_TIER[tier]
		end
		out[i] = rate
		total += rate
	end
	local cap = AuraConfig.PARTICLE.MAX_TOTAL_RATE
	if total > cap then
		local scale = cap / total
		for i, r in ipairs(out) do
			out[i] = r * scale
		end
	end
	return out
end

return AuraRenderLogic

--!strict
-- 일일 보상 7일 출석표 (지시서 #20 D3 — DESIGN.md 9장 "일일 보상"). 수치의 원본은 이 파일이다.
--
--   DAYS[n]  n일째 칸의 보상 목록(RewardLogic 보상 형식). 7일째를 받으면 다음 날 1일부터(D1) · 하루를 건너뛰면 1일로(D1)
--   ⚠️ 값은 TEMP — 사람이 튜닝한다(docs/TUNING.md "일일 보상"). 행운 포션은 무료로 주지 않는다(#17 — RewardLogic이 막는다).
--      보상은 전부 정해진 것만(랜덤 없음). 포션은 보관함으로 간다(바로 켜지지 않는다). 블럭스 칸 = 최고층 1회 기본 보상 × k
--   칸 수는 Schema.LIMITS.DAILY_CYCLE_DAYS와 같아야 한다(SchemaTests가 대조한다 — Schema는 Config를 모른다)

local RewardLogic = require(script.Parent.Parent.RewardLogic)
local PetConfig = require(script.Parent.PetConfig)

local DailyRewardConfig = {}

-- ===== TEMP — 보상표 (2026-11-01 사람 결정 D3 시작값) =====
DailyRewardConfig.DAYS = {
	{ { type = "potion", kind = "strength", count = 1 } }, -- 1일 힘 포션 1
	{ { type = "bloxScaled", k = 2 } }, -- 2일 블럭스 ×2
	{ { type = "potion", kind = "damage", count = 1 } }, -- 3일 데미지 포션 1
	{ { type = "bloxScaled", k = 3 } }, -- 4일 블럭스 ×3
	{ { type = "potion", kind = "strength", count = 2 } }, -- 5일 힘 포션 2
	{ { type = "bloxScaled", k = 5 } }, -- 6일 블럭스 ×5
	{ { type = "pet", petId = PetConfig.LIMITED_IDS[1] } }, -- 7일 리미티드 펫 1마리(D4)
} :: { { RewardLogic.Reward } }

DailyRewardConfig.CYCLE_DAYS = #DailyRewardConfig.DAYS

-- 요청 빈도 상한(플레이어당 — 다른 Request 서비스와 같은 꼴)
DailyRewardConfig.REQUEST_MIN_INTERVAL_SEC = 0.5

function DailyRewardConfig.validate(): boolean
	assert(DailyRewardConfig.CYCLE_DAYS == 7, "DailyRewardConfig: 출석표는 7칸(D1)")
	for i, rewards in ipairs(DailyRewardConfig.DAYS) do
		assert(RewardLogic.isValidList(rewards), string.format("DailyRewardConfig: %d일째 보상 형식이 틀림", i))
	end
	local last = DailyRewardConfig.DAYS[DailyRewardConfig.CYCLE_DAYS]
	assert(#last == 1 and last[1].type == "pet" and PetConfig.isLimited(last[1].petId), "DailyRewardConfig: 7일째는 리미티드 펫 1마리(D4)")
	assert(DailyRewardConfig.REQUEST_MIN_INTERVAL_SEC > 0, "DailyRewardConfig: REQUEST_MIN_INTERVAL_SEC는 0 초과")
	return true
end

return DailyRewardConfig

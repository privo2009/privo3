--!strict
-- 분석 이벤트 (지시서 #23 A1 ~ A5 — DESIGN.md 14장). 수치 · 이벤트 이름 · 블럭스 흐름표의 원본은 이 파일이다. 테스트도 이 값을 읽는다.
--
--   PER_PLAYER_PER_MINUTE  플레이어당 분당 보내는 수 상한(A4). 공식 한도는 분당 120 + 20 × CCU(event-types) —
--                          N명이 모두 이 값까지 보내도 20N ≤ 120 + 20N. 넘치면 버리고 버린 개수만 로그한다
--   ECONOMY_SAFE_MAX       금액 · 잔액이 둘 다 이 값 미만이면 경제 이벤트(A2). 경제 이벤트 인자는 Luau number이고 2^53(≈ 9e15)
--                          위에서는 정수 정밀도가 깨진다(CLAUDE.md 절대 규칙 1) — 한 자릿수 여유를 둔 1e15. 넘으면 blox_flow_large
--   FLUSH_SEC              같은 (흐름 · 거래 종류 · sku)를 이 시간 동안 모아 한 번에 보낸다(A1). 자동 칭호 뽑기는 초당 1회 Sink라
--                          바로 보내면 상한을 혼자 다 쓴다 — 공식 custom-events "send events in batches ... rate limits"
--   CURRENCY               경제 이벤트 자원 이름(하나만 쓴다)
--   BLOX_FLOWS             CurrencyService reason 접두어 → 흐름. 위에서부터 첫 일치. sku가 "*"이면 reason 전체를 sku로 쓴다
--                          (upgrade_<이름>). 표에 없는 reason은 보내지 않고 접힌 경고(새 흐름을 빠뜨린 것을 찾게)
--   EVENTS                 커스텀 이벤트 이름(공식 한도 100개)

local AnalyticsConfig = {}

AnalyticsConfig.PER_PLAYER_PER_MINUTE = 20
AnalyticsConfig.WINDOW_SEC = 60
AnalyticsConfig.ECONOMY_SAFE_MAX = 1e15
AnalyticsConfig.FLUSH_SEC = 30
AnalyticsConfig.CURRENCY = "Blox"

AnalyticsConfig.EVENTS = {
	bloxFlowLarge = "blox_flow_large",
	rebirth = "rebirth",
	floorFirstClear = "floor_first_clear",
	autoAdvanceStart = "auto_advance_start",
	robuxPurchase = "robux_purchase",
}

export type Flow = { prefix: string, flow: "Source" | "Sink", transaction: string, sku: string }

-- transaction은 Enum.AnalyticsEconomyTransactionType 항목 이름(공식 economy-events — IAP · TimedReward · Onboarding · Shop ·
-- Gameplay · ContextualPurchase). 문자열로 두고 래퍼가 Enum에서 .Name으로 다시 찾는다(없는 이름이면 보내지 않는다)
AnalyticsConfig.BLOX_FLOWS = {
	{ prefix = "challenge_cashout_auto", flow = "Source", transaction = "Gameplay", sku = "cashout_auto" },
	{ prefix = "challenge_cashout_", flow = "Source", transaction = "Gameplay", sku = "cashout_manual" },
	{ prefix = "reward_daily_", flow = "Source", transaction = "TimedReward", sku = "daily" },
	{ prefix = "reward_code_", flow = "Source", transaction = "Gameplay", sku = "code" },
	{ prefix = "reward_onboarding_", flow = "Source", transaction = "Onboarding", sku = "onboarding" },
	{ prefix = "upgrade_", flow = "Sink", transaction = "Shop", sku = "*" },
	{ prefix = "title_roll_", flow = "Sink", transaction = "Shop", sku = "title_roll" },
	{ prefix = "aura_roll_", flow = "Sink", transaction = "Shop", sku = "aura_roll" },
	{ prefix = "pet_hatch_", flow = "Sink", transaction = "Shop", sku = "pet_hatch" },
	{ prefix = "warp_", flow = "Sink", transaction = "ContextualPurchase", sku = "warp" },
	{ prefix = "rebirth_", flow = "Sink", transaction = "Gameplay", sku = "rebirth" },
} :: { Flow }

-- reason → (흐름표 줄, sku). 표에 없으면 nil
function AnalyticsConfig.classify(reason: any): (Flow?, string?)
	if type(reason) ~= "string" then
		return nil, nil
	end
	for _, row in ipairs(AnalyticsConfig.BLOX_FLOWS) do
		if string.sub(reason, 1, #row.prefix) == row.prefix then
			return row, if row.sku == "*" then reason else row.sku
		end
	end
	return nil, nil
end

function AnalyticsConfig.validate(): boolean
	assert(AnalyticsConfig.PER_PLAYER_PER_MINUTE >= 1 and AnalyticsConfig.PER_PLAYER_PER_MINUTE <= 20,
		"AnalyticsConfig: 플레이어당 분당 상한은 1 ~ 20(공식 120 + 20 × CCU 안)")
	assert(AnalyticsConfig.ECONOMY_SAFE_MAX > 0 and AnalyticsConfig.ECONOMY_SAFE_MAX <= 2 ^ 53, "AnalyticsConfig: 경제 이벤트 상한 ≤ 2^53")
	assert(AnalyticsConfig.FLUSH_SEC > 0 and AnalyticsConfig.WINDOW_SEC > 0, "AnalyticsConfig: 시간은 0 초과")
	for _, row in ipairs(AnalyticsConfig.BLOX_FLOWS) do
		assert(row.flow == "Source" or row.flow == "Sink", "AnalyticsConfig: 흐름은 Source · Sink — " .. row.prefix)
	end
	return true
end

return AnalyticsConfig

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
--   COIN_FLOWS             코인 흐름(지시서 #38 — 두 번째 자원 "Coins". 공식 자원 한도 5 · 10 중 작은 쪽 안)
--   ONBOARDING_STEPS       온보딩 퍼널(#38) 단계 이름 — 번호는 1부터 차례(공식 funnel-events: 뒤 단계를 먼저 보내면 앞 단계도 지난 것으로 친다 ·
--                          같은 단계는 첫 번만 센다 · 단계 100개까지). 그래서 앞 단계를 다 지났을 때만 다음 단계를 보낸다(Analytics.funnelReached)
--   GUIDE_FUNNEL           옛 첫 접속 안내 5단계(#20 O5)의 퍼널 이름 — 온보딩 퍼널은 게임에 하나라 새 단계와 섞이지 않게 따로(LogFunnelStepEvent)
--   PROGRESS_POLL_SEC      퍼널 · 곡괭이 종 수를 다시 보는 주기(서버 루프 하나)

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
	pickaxeKinds = "pickaxe_kinds", -- #38 진행: 값 = 가진 곡괭이 종 수(늘 때만) · 필드 1 = 새로 얻은 등급
}

AnalyticsConfig.CURRENCY_COINS = "Coins"
AnalyticsConfig.GUIDE_FUNNEL = "FirstGuide"
AnalyticsConfig.PROGRESS_POLL_SEC = 2

-- 온보딩 퍼널(#38 — 출시 첫 주 이탈 지점). 순서 = 번호
AnalyticsConfig.ONBOARDING_STEPS = {
	"Joined", -- 1 접속
	"FirstCashout", -- 2 첫 수령
	"FirstCoin", -- 3 첫 코인
	"FirstOre", -- 4 첫 광석(인벤토리)
	"FirstEgg", -- 5 첫 알
	"FirstRebirth", -- 6 첫 환생
	"ForgeFloor8", -- 7 8층 대장간 열림
	"FirstCraft", -- 8 첫 제작
	"FirstEquip", -- 9 첫 장착(시작 곡괭이가 아닌 것)
} :: { string }

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

-- 코인 흐름(#38). 블록이 깨질 때마다 들어오므로 FLUSH_SEC로 모아 보낸다
AnalyticsConfig.COIN_FLOWS = {
	{ prefix = "block_break", flow = "Source", transaction = "Gameplay", sku = "block" },
	{ prefix = "pet_hatch_", flow = "Sink", transaction = "Shop", sku = "egg" },
} :: { Flow }

-- reason → (흐름표 줄, sku). 표에 없으면 nil
function AnalyticsConfig.classify(reason: any, currency: string?): (Flow?, string?)
	if type(reason) ~= "string" then
		return nil, nil
	end
	local rows = if currency == AnalyticsConfig.CURRENCY_COINS then AnalyticsConfig.COIN_FLOWS else AnalyticsConfig.BLOX_FLOWS
	for _, row in ipairs(rows) do
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
	for _, rows in ipairs({ AnalyticsConfig.BLOX_FLOWS, AnalyticsConfig.COIN_FLOWS }) do
		for _, row in ipairs(rows) do
			assert(row.flow == "Source" or row.flow == "Sink", "AnalyticsConfig: 흐름은 Source · Sink — " .. row.prefix)
		end
	end
	local n = 0
	for _ in pairs(AnalyticsConfig.EVENTS) do
		n += 1
	end
	assert(n <= 100, "AnalyticsConfig: 커스텀 이벤트 이름 100개 이하(공식)")
	assert(#AnalyticsConfig.ONBOARDING_STEPS >= 1 and #AnalyticsConfig.ONBOARDING_STEPS <= 100, "AnalyticsConfig: 퍼널 단계 1 ~ 100(공식)")
	return true
end

return AnalyticsConfig

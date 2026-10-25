--!strict
-- 운동기구 설정. 메인 로비 운동기구 구역 위에서 클릭하면 클릭 힘에 배수가 붙는다.
-- (2026-10-21 사람 결정 — DESIGN.md "운동기구"가 규칙의 원본이다. 여기로 복사하지 말 것.)
--
--   해금   환생 수(rebirths) ≥ 그 기구의 조건. 환생 수는 줄지 않으므로 한 번 열리면 계속 열려 있다
--          (패드와 반대 — 패드는 lifeBlox 기준이라 환생하면 다시 잠긴다)
--          로벅스 선해금은 개발자 상품 8종(ShopConfig "gymUnlock1" ~ "gymUnlock8" — 지시서 #16). 가격의 원본은 ShopConfig다.
--          지급(선해금 기록 gymUnlocks)은 #17. 판정은 GymService가 환생 수 OR 선해금 기록 OR 공허 게임패스로 한다
--   유료   맨 끝 기구는 "공허 훈련 구역"이다 — 환생으로는 열리지 않고 로벅스로만 산다. 배수와 가격이
--          모든 기구 중 가장 높다(2026-10-21 사람 결정). 가격의 원본은 ShopConfig(게임패스 voidTrainingZone)다
--   효과   그 기구 위에 서 있는 동안의 클릭 1회 힘 = 패드 파워 × 기구 배수 × 환생 배수 × 클릭 수
--          런 안(챌린지 구역)에는 기구가 없으므로 런 중 클릭에는 붙지 않는다 —
--          docs/PENDING.md "지켜야 할 조건"(운동기구 효율 > 런 중 클릭 효율)이 이 구조로 지켜진다
--
-- 이 모듈은 순수하다. Player·프로필을 보지 않는다. 같은 입력이면 항상 같은 값이다.

local BigNum = require(script.Parent.Parent.BigNum)
local ShopConfig = require(script.Parent.ShopConfig)

type BigNumber = BigNum.BigNumber

local GymConfig = {}

-- ===== 기구 목록 =====================================================================
--
-- ⚠️ TEMP — 4-2-f 시뮬레이션으로 정한 자리값이다(사람이 "적정양으로 대충" 위임). 근거는 아래.
--
--   unlockRebirths  그 기구를 여는 환생 수. 첫 환생에 바로 첫 기구가 열리고, 뒤로 갈수록 기구 사이 간격이
--                   길어진다(아래 근거). nil이면 로벅스 전용 기구다(환생으로 안 열림)
--   multiplier      클릭 힘 배수
--   productKey      환생 기구의 선해금 개발자 상품 키(ShopConfig). 가격은 그 상품에서 읽는다(숫자를 두 곳에 두지 않는다 — 지시서 #16)
--   gamepassKey     로벅스 전용 기구의 ShopConfig 게임패스 키. 환생 기구는 nil
export type Tier = {
	unlockRebirths: BigNumber?,
	multiplier: number,
	productKey: string?,
	gamepassKey: string?,
}

--
-- 근거 (2026-10-21 SuccessRateReport, 결정 모델 + "막힌 런 뒤 기구에서 30초" — 그 해석은 시뮬레이터 MODEL 주석):
--
--   해금 시점 — 사람 결정(2026-10-21): "로그 모양 — 처음엔 빠르게 열리다가 뒤로 갈수록 무뎌진다.
--   첫 기구가 늦으면 이탈한다." 첫 안(환생 10, 100, … 10의 거듭제곱)은 첫 기구가 20.9분에 열렸다
--   (환생 10 = 블럭스 1만). 환생 수는 시간에 대해 지수로 늘어서 10배 사다리는 거의 같은 간격으로 열린다.
--   그래서 조건을 "열리는 시각"에서 거꾸로 골랐다. 첫 환생 = 첫 기구.
--   기구 2 · 3은 사람 결정으로 환생 3 · 5다(2026-10-21, 처음 고른 값은 2 · 3).
--     기구                1     2     3     4     5     6     7     8
--     환생 수              1     3     5    10    50   500   10K    1M
--     열리는 시각 (지금)  11.9  13.6  14.1  18.5  27.8  33.9  41.8  58.5분 (200명 중앙값, 패드 가격 1/3 뒤)
--     패드 가격 1/3 전     9.6  20.2  22.2  24.5  34.1  43.1  48.7  70.6분
--   ⚠️ 열리는 시각은 환생 리듬을 따라가서 패드 가격에 민감하다(환생 수는 정수로 뛴다). 패드 가격을
--      바꾸면 이 줄을 다시 잴 것.
--
--   배수 — 기구가 일찍 열리면 같은 배수로도 후반 성공률이 오른다(첫 안 배수 ×1.5 … ×25 그대로면
--   17~25층 67.6%). 목표 성공률(1~8층 95% / 9~16층 65~85% / 17~25층 40~55%) 안으로 다시 맞췄다.
--                                   1~8층  9~16층  17~25층   25층 첫 진입 중앙값
--     기구 없음                      95.8   70.9    44.9     81.1분
--     첫 안 (환생 10의 거듭제곱)      95.1   73.1    52.0     74.9분
--     이 표 (×1.2 … ×8)              95.2   72.8    51.3     75.5분   ← 채택 (기구 2·3 = 환생 2·3일 때)
--       기구 2·3 = 환생 3·5로 바꾼 뒤    95.2   73.4    51.6     75.0분
--       + 패드 가격 1/3 (지금)          95.8   73.2    47.8     61.9분   배수는 그대로 두었다
--     이 조건 + ×1.2 … ×10           94.8   71.9    55.2     74.5분   17~25층이 목표 끝
--     이 조건 + ×1.5 … ×25           94.8   77.3    67.6     67.0분   17~25층이 목표 위
--   seed가 같아도 후보 사이 차이 ±3%p 안은 잡음 수준이다. 기구 배수 × 훈련 시간이 효과를 정하므로
--   실제 유저가 기구에서 더 오래 있으면 배수를 낮춰야 한다 — 실플레이로 재확인.
--   ⚠️ 패드 리셋 전(패드 유지)에는 46.7분이었다. 기구로는 이 속도를 되찾지 못한다(docs/PENDING.md).
--
--   선해금 가격은 29 → 449 R$ 자리값이다(지금 원본은 ShopConfig gymUnlock1 ~ 8 — 지시서 #16). 공허 훈련 구역(799 R$, DESIGN.md "수익화" 표의 기존 값)이
--   가장 비싸야 하므로 그 아래에 펼쳤다. 기존 게임패스 가격 단위(29·49·79·99·149·199·299·449)를 따른다.
--   Phase 8 수익화 때 다시 본다.
--
--   공허 훈련 구역 ×100 — "배수가 매우 높다"(사람 결정). Claude 판단으로 정했다. 구매자 비교(×50 48.3분 /
--   ×100 40.9분 / ×200 36.5분, 패드 가격 1/3 전)에서 ×100 위로는 빨라지는 폭이 작다. 구매자는 처음부터
--   공허만 쓰므로 환생 기구 표를 바꿔도 구매자 숫자는 그대로다. 패드 가격 1/3 뒤 ×100은 35.9분.
--   구매자 비교는 SuccessRateReport "공허 훈련 구역 구매자 (비교)" 줄. 성공률 목표는 무과금 기준이라
--   구매자는 목표 밖이다.
local TIERS: { Tier } = {
	{ unlockRebirths = BigNum.new(1, 0), multiplier = 1.2, productKey = "gymUnlock1" },
	{ unlockRebirths = BigNum.new(3, 0), multiplier = 1.5, productKey = "gymUnlock2" },
	{ unlockRebirths = BigNum.new(5, 0), multiplier = 2, productKey = "gymUnlock3" },
	{ unlockRebirths = BigNum.new(1, 1), multiplier = 2.5, productKey = "gymUnlock4" },
	{ unlockRebirths = BigNum.new(5, 1), multiplier = 3, productKey = "gymUnlock5" },
	{ unlockRebirths = BigNum.new(5, 2), multiplier = 4, productKey = "gymUnlock6" },
	{ unlockRebirths = BigNum.new(1, 4), multiplier = 5, productKey = "gymUnlock7" },
	{ unlockRebirths = BigNum.new(1, 6), multiplier = 8, productKey = "gymUnlock8" },
	{
		unlockRebirths = nil,
		multiplier = 100,
		gamepassKey = "voidTrainingZone",
	},
}
GymConfig.TIERS = TIERS

local function assertIndex(index: number)
	assert(
		type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #TIERS,
		string.format("GymConfig: 기구 인덱스(%s)가 범위(1..%d)를 벗어남", tostring(index), #TIERS)
	)
end

function GymConfig.getCount(): number
	return #TIERS
end

-- 로벅스 전용 기구인가(환생으로 안 열림).
function GymConfig.isRobuxOnly(index: number): boolean
	assertIndex(index)
	return TIERS[index].unlockRebirths == nil
end

-- 환생으로 열리는 기구 수. 로벅스 전용 기구는 맨 끝에만 온다(validate가 보장) — 1..이 값이 환생 기구다.
function GymConfig.getRebirthTierCount(): number
	local count = 0
	for _, tier in ipairs(TIERS) do
		if tier.unlockRebirths == nil then
			break
		end
		count += 1
	end
	return count
end

-- 그 게임패스 키로 사는 기구 번호. 없으면 nil.
function GymConfig.findByGamepass(key: string): number?
	for index, tier in ipairs(TIERS) do
		if tier.gamepassKey == key then
			return index
		end
	end
	return nil
end

-- ⚠️ 새 BigNum을 돌려준다. 호출자가 고쳐도 TIERS가 오염되지 않는다.
-- 로벅스 전용 기구는 조건이 없으므로 에러다 — 먼저 isRobuxOnly로 거를 것.
function GymConfig.getUnlockRebirths(index: number): BigNumber
	assertIndex(index)
	local v = TIERS[index].unlockRebirths
	assert(v ~= nil, string.format("GymConfig: 기구 %d은 로벅스 전용이라 환생 조건이 없음", index))
	return BigNum.new(v.m, v.e)
end

function GymConfig.getMultiplier(index: number): number
	assertIndex(index)
	return TIERS[index].multiplier
end

-- 그 기구를 로벅스로 여는 상품 키(환생 기구 = 선해금 개발자 상품, 로벅스 전용 = 게임패스).
function GymConfig.getShopKey(index: number): string
	assertIndex(index)
	local tier = TIERS[index]
	return (tier.productKey or tier.gamepassKey) :: string
end

-- 로벅스 가격 — ShopConfig 원본(지시서 #16).
function GymConfig.getRobuxPrice(index: number): number
	local def = ShopConfig.get(GymConfig.getShopKey(index))
	assert(def ~= nil, string.format("GymConfig: 기구 %d의 상품이 ShopConfig에 없음", index))
	return def.priceRobux
end

-- 환생 수로 열렸는가. 로벅스 선해금(Phase 8)은 여기서 보지 않는다 — 소유 확인은 서버가
-- 매 세션 MarketplaceService로 하고(CLAUDE.md 절대 규칙 5) 그 결과를 호출자가 합친다.
-- 로벅스 전용 기구는 환생 수가 얼마든 false다.
function GymConfig.isUnlockedByRebirths(index: number, rebirths: BigNumber): boolean
	assertIndex(index)
	local need = TIERS[index].unlockRebirths
	return need ~= nil and BigNum.gte(rebirths, need)
end

-- 환생 수로 열린 기구 수(0 = 하나도 없음). 조건이 순증가하는 것은 validate가 보장한다.
-- 로벅스 전용 기구는 세지 않는다 — 최대값은 getRebirthTierCount()다.
function GymConfig.getUnlockedCount(rebirths: BigNumber): number
	local unlocked = 0
	for index = 1, GymConfig.getRebirthTierCount() do
		if not GymConfig.isUnlockedByRebirths(index, rebirths) then
			break
		end
		unlocked = index
	end
	return unlocked
end

function GymConfig.validate(): boolean
	assert(#TIERS >= 1, "GymConfig: 기구가 하나도 없음")
	local rebirthTiers = GymConfig.getRebirthTierCount()
	assert(rebirthTiers >= 1, "GymConfig: 환생으로 열리는 기구가 하나도 없음")
	local prev: Tier? = nil
	for index, tier in ipairs(TIERS) do
		local need = tier.unlockRebirths
		if need == nil then
			-- 로벅스 전용: 게임패스가 ShopConfig에 있어야 한다(가격은 그 게임패스 값).
			local key = tier.gamepassKey
			assert(key ~= nil, string.format("GymConfig: 기구 %d은 환생 조건도 gamepassKey도 없음", index))
			local def = ShopConfig.get(key)
			assert(def ~= nil and def.kind == "gamepass" and def.effect.type == "gymPass",
				string.format("GymConfig: 기구 %d의 gamepassKey(%s)가 ShopConfig 게임패스(gymPass)가 아님", index, key))
			assert(tier.productKey == nil, string.format("GymConfig: 기구 %d은 로벅스 전용인데 productKey가 있음", index))
		else
			assert(tier.gamepassKey == nil, string.format("GymConfig: 기구 %d은 환생 기구인데 gamepassKey가 있음", index))
			local def = ShopConfig.get(tier.productKey)
			assert(def ~= nil and def.kind == "product" and def.effect.type == "gymUnlock" and def.effect.gymIndex == index,
				string.format("GymConfig: 기구 %d의 productKey(%s)가 그 기구의 선해금 상품이 아님", index, tostring(tier.productKey)))
			assert(BigNum.gt(need, BigNum.new(0, 0)), string.format("GymConfig: 기구 %d의 조건이 0 이하", index))
			assert(index <= rebirthTiers, string.format("GymConfig: 환생 기구 %d이 로벅스 전용 기구 뒤에 있음", index))
		end
		assert(tier.multiplier > 1, string.format("GymConfig: 기구 %d의 배수(%s)는 1보다 커야 함", index, tostring(tier.multiplier)))
		if prev ~= nil then
			local prevNeed = prev.unlockRebirths
			if need ~= nil and prevNeed ~= nil then
				assert(BigNum.gt(need, prevNeed), string.format("GymConfig: 기구 %d의 조건이 앞 기구보다 크지 않음", index))
			end
			-- 배수·가격은 로벅스 전용까지 이어서 순증가 — 로벅스 전용이 가장 비싸고 가장 세다.
			assert(tier.multiplier > prev.multiplier, string.format("GymConfig: 기구 %d의 배수가 앞 기구보다 크지 않음", index))
			assert(GymConfig.getRobuxPrice(index) > GymConfig.getRobuxPrice(index - 1), string.format("GymConfig: 기구 %d의 가격이 앞 기구보다 크지 않음", index))
		end
		prev = tier
	end
	return true
end

return GymConfig

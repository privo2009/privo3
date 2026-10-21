--!strict
-- 운동기구 설정. 메인 로비 운동기구 구역 위에서 클릭하면 클릭 힘에 배수가 붙는다.
-- (2026-10-21 사람 결정 — DESIGN.md "운동기구"가 규칙의 원본이다. 여기로 복사하지 말 것.)
--
--   해금   환생 수(rebirths) ≥ 그 기구의 조건. 환생 수는 줄지 않으므로 한 번 열리면 계속 열려 있다
--          (패드와 반대 — 패드는 lifeBlox 기준이라 환생하면 다시 잠긴다)
--          로벅스 선해금은 가격만 여기 둔다. 실제 구매(게임패스 소유 확인)는 Phase 8이다
--   유료   맨 끝 기구는 "공허 훈련 구역"이다 — 환생으로는 열리지 않고 로벅스로만 산다. 배수와 가격이
--          모든 기구 중 가장 높다(2026-10-21 사람 결정). 가격의 원본은 ShopConfig.Gamepasses다
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
--   unlockRebirths  그 기구를 여는 환생 수. 10의 거듭제곱 사다리 — 환생 수는 지수로 크므로
--                   (환생 배수 = 1 + rebirths, 후반엔 수백만) 선형 사다리는 앞쪽에 몰린다.
--                   nil이면 로벅스 전용 기구다(환생으로 안 열림)
--   multiplier      클릭 힘 배수
--   robuxPrice      선해금 가격(R$). Phase 8에서 게임패스로 판다. 지금은 숫자만.
--                   로벅스 전용 기구는 ShopConfig.Gamepasses[gamepassKey]에서 읽는다(숫자를 두 곳에 두지 않는다)
--   gamepassKey     로벅스 전용 기구의 ShopConfig.Gamepasses 키. 환생 기구는 nil
export type Tier = {
	unlockRebirths: BigNumber?,
	multiplier: number,
	robuxPrice: number,
	gamepassKey: string?,
}

--
-- 근거 (2026-10-21 SuccessRateReport, 결정 모델 + "막힌 런 뒤 기구에서 30초" — 그 해석은 시뮬레이터 MODEL 주석):
--   기준은 "HP 곡선은 그대로 두고 목표 성공률(1~8층 95% / 9~16층 65~85% / 17~25층 40~55%) 안에서
--   패드 리셋으로 늦어진 속도를 되찾는다"이다.
--                          1~8층  9~16층  17~25층   25층 첫 진입 중앙값
--     기구 없음             95.8   70.9    44.9     81.1분
--     이 표 (×1.5 … ×25)    95.1   73.1    52.0     74.9분   ← 채택
--     배수 2배 (×2 … ×50)   95.1   73.0    60.1     71.0분   17~25층이 목표 위
--   기구는 막혔을 때 힘을 더 주므로 처음 도달할 때의 여유가 커져 후반 성공률이 오른다. 그래서
--   배수를 더 키우면 속도보다 성공률이 먼저 목표를 넘는다. 기구 배수 × 훈련 시간이 효과를 정하므로
--   실제 유저가 기구에서 더 오래 있으면(60초: 17~25층 62.7%) 배수를 낮춰야 한다 — 실플레이로 재확인.
--   25층 첫 진입 때 환생 수 중앙값은 약 10^7 — 기구 8(10^8)은 월드 1 안에서는 열리지 않는 후반 목표다.
--   ⚠️ 패드 리셋 전(패드 유지)에는 46.7분이었다. 기구로는 이 속도를 되찾지 못한다(docs/PENDING.md).
--
--   robuxPrice는 29 → 449 R$ 자리값이다. 공허 훈련 구역(799 R$, DESIGN.md "수익화" 표의 기존 값)이
--   가장 비싸야 하므로 그 아래에 펼쳤다. 기존 게임패스 가격 단위(29·49·79·99·149·199·299·449)를 따른다.
--   Phase 8 수익화 때 다시 본다.
--
--   공허 훈련 구역 배수 — "배수가 매우 높다"(사람 결정)를 최상위 환생 기구(×25)의 4배로 옮겼다(Claude 판단).
--   구매자 비교는 SuccessRateReport "공허 훈련 구역 구매자 (비교)" 줄. 성공률 목표는 무과금 기준이라
--   구매자는 목표 밖이다.
local TIERS: { Tier } = {
	{ unlockRebirths = BigNum.new(1, 1), multiplier = 1.5, robuxPrice = 29 },
	{ unlockRebirths = BigNum.new(1, 2), multiplier = 2, robuxPrice = 49 },
	{ unlockRebirths = BigNum.new(1, 3), multiplier = 3, robuxPrice = 79 },
	{ unlockRebirths = BigNum.new(1, 4), multiplier = 4, robuxPrice = 99 },
	{ unlockRebirths = BigNum.new(1, 5), multiplier = 6, robuxPrice = 149 },
	{ unlockRebirths = BigNum.new(1, 6), multiplier = 10, robuxPrice = 199 },
	{ unlockRebirths = BigNum.new(1, 7), multiplier = 15, robuxPrice = 299 },
	{ unlockRebirths = BigNum.new(1, 8), multiplier = 25, robuxPrice = 449 },
	{
		unlockRebirths = nil,
		multiplier = 100,
		robuxPrice = ShopConfig.Gamepasses.voidTrainingZone.priceRobux,
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

function GymConfig.getRobuxPrice(index: number): number
	assertIndex(index)
	return TIERS[index].robuxPrice
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
			-- 로벅스 전용: 게임패스가 ShopConfig에 있고 가격이 그 값과 같아야 한다.
			local key = tier.gamepassKey
			assert(key ~= nil, string.format("GymConfig: 기구 %d은 환생 조건도 gamepassKey도 없음", index))
			local pass = ShopConfig.Gamepasses[key]
			assert(pass ~= nil, string.format("GymConfig: 기구 %d의 gamepassKey(%s)가 ShopConfig.Gamepasses에 없음", index, key))
			assert(tier.robuxPrice == pass.priceRobux, string.format("GymConfig: 기구 %d의 가격이 ShopConfig와 다름", index))
		else
			assert(tier.gamepassKey == nil, string.format("GymConfig: 기구 %d은 환생 기구인데 gamepassKey가 있음", index))
			assert(BigNum.gt(need, BigNum.new(0, 0)), string.format("GymConfig: 기구 %d의 조건이 0 이하", index))
			assert(index <= rebirthTiers, string.format("GymConfig: 환생 기구 %d이 로벅스 전용 기구 뒤에 있음", index))
		end
		assert(tier.multiplier > 1, string.format("GymConfig: 기구 %d의 배수(%s)는 1보다 커야 함", index, tostring(tier.multiplier)))
		assert(
			type(tier.robuxPrice) == "number" and tier.robuxPrice > 0 and tier.robuxPrice % 1 == 0,
			string.format("GymConfig: 기구 %d의 로벅스 가격(%s)은 양의 정수여야 함", index, tostring(tier.robuxPrice))
		)
		if prev ~= nil then
			local prevNeed = prev.unlockRebirths
			if need ~= nil and prevNeed ~= nil then
				assert(BigNum.gt(need, prevNeed), string.format("GymConfig: 기구 %d의 조건이 앞 기구보다 크지 않음", index))
			end
			-- 배수·가격은 로벅스 전용까지 이어서 순증가 — 로벅스 전용이 가장 비싸고 가장 세다.
			assert(tier.multiplier > prev.multiplier, string.format("GymConfig: 기구 %d의 배수가 앞 기구보다 크지 않음", index))
			assert(tier.robuxPrice > prev.robuxPrice, string.format("GymConfig: 기구 %d의 가격이 앞 기구보다 크지 않음", index))
		end
		prev = tier
	end
	return true
end

return GymConfig

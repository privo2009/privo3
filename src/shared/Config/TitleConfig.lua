--!strict
-- 타이틀(칭호) 뽑기 (Phase 7 지시서 #10). 규칙 원본은 DESIGN.md "6. 뽑기 3종 > 타이틀".
--
--   비용         블럭스 ROLL_COST 고정(지수 아님 — DESIGN)
--   판정         순차 확률(G5). 높은 등급부터 기본 확률 × 행운, 어느 것에도 안 걸리면 폴백(초보자, 확률 없음).
--                판정 코드는 서버 RollLogic이다 — 이 파일은 데이터만 둔다. 클라는 확률을 **표시만** 한다
--   배수         힘 배수 = 블럭스 배수(같은 값 하나 — mult). 폴백 1.0, 등급이 오를수록 단조 증가
--                힘은 StrengthMultiplier.compute, 블럭스는 ChallengeService 블럭스 배수 결합 한 곳에서 곱한다(S3 · S4)
--   롤 빈도      수동 · 자동 합쳐 플레이어당 ROLL_INTERVAL_SEC에 1회(G6) — 서버 TitleService가 잰다
--
-- 배열은 희귀도 낮은 순이다. Titles[1]이 폴백이다(baseChance 없음). 인덱스가 곧 희귀도 단계(UiTheme.Rarity tier1~6)다.
--
-- ===== 무엇이 사람 결정이고 무엇이 TEMP인가 ==================================================
--
--   확률 · 비용 · 폴백 1.0          사람 결정(2026-10-24 지시서 #10 G5) — 시뮬레이터 조정 대상이 아니다
--   mult(폴백 외)                   TEMP. 시작값은 사람 결정, 지시서 #10 6단계 권한으로만 조정(폴백 1.0 고정 · 단조 · 최고 ×3.0 이하)
--   ROLL_INTERVAL_SEC              TEMP(G6)

local BigNum = require(script.Parent.Parent.BigNum)

type BigNumber = BigNum.BigNumber

export type TitleDef = {
	id: string,
	name: string,
	baseChance: number?, -- 폴백(Titles[1])은 nil. 나머지는 (0, 1]
	mult: number, -- 힘 배수 = 블럭스 배수 (TEMP)
}

local TitleConfig = {}

TitleConfig.ROLL_COST = BigNum.new(1, 1) :: BigNumber -- 10, 고정 (지수 아님)
TitleConfig.ROLL_INTERVAL_SEC = 1 -- TEMP(G6). 수동 · 자동 합쳐 플레이어당 1회

local Titles: { TitleDef } = {
	{ id = "novice", name = "초보자", baseChance = nil, mult = 1.0 }, -- 폴백
	{ id = "apprentice", name = "견습생", baseChance = 1 / 5, mult = 1.05 }, -- TEMP mult
	{ id = "breaker", name = "파괴자", baseChance = 1 / 50, mult = 1.1 }, -- TEMP mult
	{ id = "champion", name = "챔피언", baseChance = 1 / 500, mult = 1.2 }, -- TEMP mult
	{ id = "legend", name = "레전드", baseChance = 1 / 5000, mult = 1.4 }, -- TEMP mult
	{ id = "mythic", name = "신화", baseChance = 1 / 50000, mult = 1.8 }, -- TEMP mult
}
TitleConfig.Titles = Titles

local indexById: { [string]: number } = {}
for i, def in ipairs(Titles) do
	indexById[def.id] = i
end

-- id → (정의, 희귀도 단계 인덱스). 모르는 id(옛 프로필 · 깨진 값)는 nil.
function TitleConfig.get(id: any): (TitleDef?, number?)
	if type(id) ~= "string" then
		return nil, nil
	end
	local i = indexById[id]
	if i == nil then
		return nil, nil
	end
	return Titles[i], i
end

-- 장착 칭호의 배수. 장착 없음(false) · 모르는 id는 1.
function TitleConfig.multOf(id: any): number
	local def = TitleConfig.get(id)
	return if def ~= nil then def.mult else 1
end

-- a가 b보다 높은 등급인가. b가 없거나(false · 모르는 id) a가 알려진 id면 true — 첫 칭호는 무조건 장착된다.
function TitleConfig.isHigher(a: any, b: any): boolean
	local _, ia = TitleConfig.get(a)
	if ia == nil then
		return false
	end
	local _, ib = TitleConfig.get(b)
	return ib == nil or ia > ib
end

function TitleConfig.validate(): boolean
	assert(BigNum.gt(TitleConfig.ROLL_COST, BigNum.new(0, 0)), "TitleConfig: ROLL_COST는 0보다 커야 함")
	assert(type(TitleConfig.ROLL_INTERVAL_SEC) == "number" and TitleConfig.ROLL_INTERVAL_SEC > 0, "TitleConfig: ROLL_INTERVAL_SEC는 0보다 커야 함")
	assert(#Titles >= 2, "TitleConfig: 폴백 외에 등급이 하나 이상 있어야 함")

	local fallback = Titles[1]
	assert(fallback.baseChance == nil, "TitleConfig: 폴백(Titles[1])은 확률이 없어야 함")
	assert(fallback.mult == 1, "TitleConfig: 폴백 배수는 1.0이어야 함")

	local seen: { [string]: boolean } = {}
	local chanceSum = 0
	local prevChance = math.huge
	local prevMult = -math.huge
	for i, def in ipairs(Titles) do
		assert(not seen[def.id], "TitleConfig: id 중복 - " .. def.id)
		seen[def.id] = true
		assert(type(def.mult) == "number" and def.mult >= 1 and def.mult < math.huge, "TitleConfig: " .. def.id .. "의 배수는 1 이상 유한수")
		assert(def.mult > prevMult, "TitleConfig: 배수는 등급이 오를수록 커져야 함 - " .. def.id)
		prevMult = def.mult
		if i > 1 then
			local p = def.baseChance
			assert(type(p) == "number" and p > 0 and p <= 1, "TitleConfig: " .. def.id .. "의 baseChance가 (0,1] 범위를 벗어남")
			assert((p :: number) < prevChance, "TitleConfig: 확률은 등급이 오를수록 작아져야 함 - " .. def.id)
			prevChance = p :: number
			chanceSum += p :: number
		end
	end
	assert(chanceSum <= 1 + 1e-9, string.format("TitleConfig: 폴백 제외 baseChance 합이 1을 초과함 (%.4f)", chanceSum))
	return true
end

return TitleConfig

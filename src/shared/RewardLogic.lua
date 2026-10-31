--!strict
-- 무료 보상(일일 보상 · 코드 · 첫 접속 완료)의 보상 형식과 블럭스 양 계산 (지시서 #20 R1 — DESIGN.md 9장 "무료 요소 > 보상 지급 공용").
-- 순수 모듈 — 서버 RewardService가 지급 전에, 클라 창이 표시할 때 같은 함수를 쓴다(화면 값 = 지급 값).
--
--   보상 형식  { type = "potion", kind, count }   kind = POTION_KINDS(힘 · 데미지 — 행운 포션은 무료로 주지 않는다 #17) · count 1 ~ MAX_COUNT 정수
--              { type = "bloxScaled", k }        블럭스 = 최고층 1회 기본 보상 × k (k > 0 유한수)
--              { type = "pet", petId }           PetConfig.get이 아는 id(리미티드 포함)
--   최고층 1회 기본 보상 = maxStage 층의 StageConfig.getBloxReward(WorldConfig 보상). 블럭스 배수(x2 Blox · 칭호 · 업그레이드)는 곱하지 않는다.
--              maxStage가 1 미만 · 숫자 아님이면 1층 기준, 정의된 마지막 층을 넘으면 마지막 층 기준

local BigNum = require(script.Parent.BigNum)
local StageConfig = require(script.Parent.Config.StageConfig)
local PetConfig = require(script.Parent.Config.PetConfig)

type BigNumber = BigNum.BigNumber

export type Reward = {
	type: string,
	kind: string?,
	count: number?,
	k: number?,
	petId: string?,
}

local RewardLogic = {}

RewardLogic.POTION_KINDS = { "strength", "damage" }
RewardLogic.MAX_COUNT = 99
RewardLogic.MAX_REWARDS = 8 -- 보상 하나가 담는 항목 수 상한(Config 실수 방지)

local function isPotionKind(kind: any): boolean
	for _, k in ipairs(RewardLogic.POTION_KINDS) do
		if kind == k then
			return true
		end
	end
	return false
end

local function isWhole(n: any, lo: number, hi: number): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi
end

-- 항목 하나가 올바른 형식인가.
function RewardLogic.isValid(r: any): boolean
	if type(r) ~= "table" then
		return false
	end
	if r.type == "potion" then
		return isPotionKind(r.kind) and isWhole(r.count, 1, RewardLogic.MAX_COUNT)
	elseif r.type == "bloxScaled" then
		return type(r.k) == "number" and r.k == r.k and r.k > 0 and r.k < math.huge
	elseif r.type == "pet" then
		return PetConfig.get(r.petId) ~= nil
	end
	return false
end

-- 목록 전체가 올바른가(1 ~ MAX_REWARDS개, 전부 isValid).
function RewardLogic.isValidList(list: any): boolean
	if type(list) ~= "table" or #list < 1 or #list > RewardLogic.MAX_REWARDS then
		return false
	end
	for _, r in ipairs(list) do
		if not RewardLogic.isValid(r) then
			return false
		end
	end
	return true
end

-- bloxScaled의 기준 층(위 규칙).
function RewardLogic.baseStage(maxStage: any): number
	local stage = if type(maxStage) == "number" and maxStage == maxStage and maxStage >= 1 then math.floor(maxStage) else 1
	while stage > 1 and not StageConfig.hasStage(stage) do
		stage -= 1
	end
	return stage
end

-- bloxScaled 한 항목의 블럭스 양.
function RewardLogic.bloxAmount(maxStage: any, k: number): BigNumber
	return BigNum.mul(StageConfig.getBloxReward(RewardLogic.baseStage(maxStage)), BigNum.fromNumber(k))
end

-- 목록의 펫 수(저장 공간 검사용).
function RewardLogic.petCount(list: { Reward }): number
	local n = 0
	for _, r in ipairs(list) do
		if r.type == "pet" then
			n += 1
		end
	end
	return n
end

return RewardLogic

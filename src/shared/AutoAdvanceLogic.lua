--!strict
-- 자동 진행 모드의 순수 계산 (Phase 8 지시서 #18 — DESIGN.md "1. 챌린지 > 자동 진행 모드 > 안전층"). 서버와 설정 창이 같은 함수를 본다
-- (창은 서버가 보낸 안전층을 표시만 한다 — 목표층 범위 · 버튼 색 판정만 여기서 같이 쓴다).
--
--   safeFloor  안전층 = 1층부터 연속으로 총HP(N) ≤ D 를 만족하는 최고 N(없으면 0)
--              D = 1펀치 데미지 × 초당 펀치 × 타이머 초(DESIGN "펀치와 딜 총량 > 20초 딜 총량 D" — 이론 상한)
--              이동 시간 0(순간 이동). 1펀치 데미지는 AttackService가 실제로 쓰는 값(힘 × 결합 배수)을 서버가 넘긴다
--   maxTarget  목표층 상한 = 1층이 속한 월드의 마지막 층(AA6 — 지금 25)
--   startKind  목표층 ≤ 안전층이면 "safe"(수령 · 안전 노랑), 넘으면 "risky"(진행 · 도박 보라) — AA7

local BigNum = require(script.Parent.BigNum)
local StageConfig = require(script.Parent.Config.StageConfig)
local WorldConfig = require(script.Parent.Config.WorldConfig)

type BigNumber = BigNum.BigNumber

local AutoAdvanceLogic = {}

AutoAdvanceLogic.FIRST_STAGE = 1

function AutoAdvanceLogic.maxTarget(): number
	local world = WorldConfig.getByStage(AutoAdvanceLogic.FIRST_STAGE)
	return if world ~= nil then world.stageRange[2] else AutoAdvanceLogic.FIRST_STAGE
end

-- 목표층으로 받을 수 있는 값인가(정수 · 1 ~ maxTarget).
function AutoAdvanceLogic.isValidTarget(target: any): boolean
	return type(target) == "number" and target == target and target % 1 == 0 and target >= AutoAdvanceLogic.FIRST_STAGE
		and target <= AutoAdvanceLogic.maxTarget()
end

-- 20초 딜 총량 D. punchDamage는 BigNum, punchRate는 초당 횟수.
function AutoAdvanceLogic.dealTotal(punchDamage: BigNumber, punchRate: number, timerSec: number): BigNumber
	local perSec = if type(punchRate) == "number" and punchRate == punchRate and punchRate > 0 and punchRate ~= math.huge then punchRate else 0
	return BigNum.mul(punchDamage, BigNum.fromNumber(perSec * timerSec))
end

-- 안전층. totalHpOf(stage)를 생략하면 StageConfig.getTotalHp(실물), lastStage를 생략하면 maxTarget.
function AutoAdvanceLogic.safeFloor(punchDamage: BigNumber, punchRate: number, timerSec: number?,
	totalHpOf: ((number) -> BigNumber)?, lastStage: number?): number
	local d = AutoAdvanceLogic.dealTotal(punchDamage, punchRate, timerSec or StageConfig.CHALLENGE_TIMER_SEC)
	local hpOf = totalHpOf or StageConfig.getTotalHp
	local last = lastStage or AutoAdvanceLogic.maxTarget()
	local safe = 0
	for stage = AutoAdvanceLogic.FIRST_STAGE, last do
		if BigNum.lte(hpOf(stage), d) then
			safe = stage
		else
			break -- 연속 조건 — 한 층이라도 못 깨면 그 뒤는 보지 않는다
		end
	end
	return safe
end

function AutoAdvanceLogic.startKind(target: number, safeFloor: number): string
	return if target <= safeFloor then "safe" else "risky"
end

-- 설정 창 기본 목표층(AA6): 안전층. 안전층이 0이면 1층.
function AutoAdvanceLogic.defaultTarget(safeFloor: number): number
	return math.clamp(if safeFloor >= AutoAdvanceLogic.FIRST_STAGE then safeFloor else AutoAdvanceLogic.FIRST_STAGE,
		AutoAdvanceLogic.FIRST_STAGE, AutoAdvanceLogic.maxTarget())
end

return AutoAdvanceLogic

--!strict
-- CashoutPadView(수령 발판 켜짐/꺼짐 계산) 검증. Studio에서 Rojo 연결 후 Play 하면
-- 서버 시작 시 자동 실행된다.
--
-- 핵심 계약: 켜짐 조건은 서버 수령 판정(run.cleared + 밟은 발판 층 == 런 층)과 같다.
-- 넓으면 "켜진 발판인데 수령 안 됨"(거짓 신호), 좁으면 "꺼진 발판인데 수령됨"이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local CashoutPadView = require(Shared.CashoutPadView)
local StageConfig = require(Shared.Config.StageConfig)
local UiTheme = require(Shared.Config.UiTheme)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function findLastStage(): number
	local stage = 1
	while StageConfig.hasStage(stage + 1) do
		stage += 1
	end
	return stage
end

local LAST_STAGE = findLastStage()

local function expectLit(label: string, view: CashoutPadView.View)
	check(label .. ": lit=true", view.lit == true)
	check(label .. ": colorRole=cashout", view.colorRole == "cashout", tostring(view.colorRole))
end

local function expectUnlit(label: string, view: CashoutPadView.View)
	check(label .. ": lit=false", view.lit == false)
	check(label .. ": colorRole=neutral", view.colorRole == "neutral", tostring(view.colorRole))
end

-- 1. 켜짐 — 클리어한 런의 그 층 발판 하나 ---------------------------------------------
expectLit("1층 클리어 → 1층 발판", CashoutPadView.compute({ active = true, stage = 1, cleared = true }, 1))
expectLit(
	"최종층 클리어 → 최종층 발판",
	CashoutPadView.compute({ active = true, stage = LAST_STAGE, cleared = true }, LAST_STAGE)
)

-- 2. 꺼짐 — 같은 층이어도 미클리어 ---------------------------------------------------
expectUnlit("1층 미클리어 → 1층 발판", CashoutPadView.compute({ active = true, stage = 1, cleared = false }, 1))
expectUnlit("cleared 없음 → 꺼짐", CashoutPadView.compute({ active = true, stage = 1 }, 1))

-- 3. 꺼짐 — 클리어했어도 다른 층 발판 (서버 층 대조와 같다) ----------------------------
expectUnlit("2층 클리어 → 1층 발판", CashoutPadView.compute({ active = true, stage = 2, cleared = true }, 1))
expectUnlit("1층 클리어 → 2층 발판", CashoutPadView.compute({ active = true, stage = 1, cleared = true }, 2))

-- 4. 꺼짐 — 런 없음 ------------------------------------------------------------------
expectUnlit("입력 nil", CashoutPadView.compute(nil, 1))
expectUnlit("active=false (cleared가 남아 있어도)", CashoutPadView.compute({ active = false, stage = 1, cleared = true }, 1))
expectUnlit("stage 없음", CashoutPadView.compute({ active = true, cleared = true }, 1))

-- 5. 발판 전체를 훑으면 켜지는 것은 정확히 하나 -------------------------------------
do
	local state = { active = true, stage = math.min(3, LAST_STAGE), cleared = true }
	local litCount = 0
	for padStage = 1, LAST_STAGE do
		if CashoutPadView.compute(state, padStage).lit then
			litCount += 1
		end
	end
	check("클리어 런 하나에 켜진 발판은 1개", litCount == 1, tostring(litCount))
end

-- 6. 역할 키가 UiTheme에 실제로 있고, 서버 처음 색이 꺼짐 역할이다 -------------------
check("UNLIT_ROLE = neutral", CashoutPadView.UNLIT_ROLE == "neutral", tostring(CashoutPadView.UNLIT_ROLE))
check("UiTheme.Colors.cashout 존재", UiTheme.Colors.cashout ~= nil)
check("UiTheme.Colors.neutral 존재", UiTheme.Colors.neutral ~= nil)
check("켜짐·꺼짐 색이 다르다", UiTheme.Colors.cashout.base ~= UiTheme.Colors.neutral.base)

print(string.format("[CashoutPadViewTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[CashoutPadViewTests] %d test(s) failed", failed))
end

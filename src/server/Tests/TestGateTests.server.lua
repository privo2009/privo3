--!strict
-- TestGate 검증 (지시서 #27 T3). Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- 게이트 판정을 isStudio 주입으로 잰다 — true면 실행 · false면 건너뜀. 게시 서버에서 실제로 안 도는지는 Studio에서 볼 수 없다
-- (비공개 테스트 첫날 서버 로그로 확인 — ROADMAP 출시 체크리스트). 스크립트마다 첫 줄에 있는지는 tools/check_test_gate.py(T2).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TestGate = require(ReplicatedStorage.Shared.TestGate)
local TestRunLogic = require(ReplicatedStorage.Shared.TestRunLogic)

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

-- 스크립트 첫 줄과 같은 꼴로 몸통을 부른다 — 게이트가 false면 몸통이 한 번도 안 돈다
local function runScript(isStudio: boolean?): number
	local ran = 0
	local function body()
		if not TestGate.shouldRun(isStudio) then
			return
		end
		ran += 1
	end
	body()
	return ran
end

check("Studio(true 주입)면 실행한다", TestGate.shouldRun(true) == true and runScript(true) == 1)
check("Studio가 아니면(false 주입) 건너뛴다 — 몸통 0번", TestGate.shouldRun(false) == false and runScript(false) == 0)
check("주입이 없으면 RunService:IsStudio()를 따른다", TestGate.shouldRun() == RunService:IsStudio())
check("이 Play는 Studio다(여기까지 왔으면 첫 줄 게이트를 지났다)", RunService:IsStudio() and TestGate.shouldRun())
check("boolean이 아닌 값을 넘겨도 true로 치지 않는다", TestGate.shouldRun((("yes" :: any) :: boolean)) == false)
check("끝 표시의 기대 목록에 이 파일이 들어 있다(게이트를 지난 테스트는 그대로 센다 — T4)",
	table.find(TestRunLogic.expected(script.Parent.Parent), "TestGateTests") ~= nil)

print(string.format("[TestGateTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TestGateTests] %d test(s) failed", failed))
end

--!strict
-- 테스트 · 리포트 게이트 (지시서 #27 T1) — 테스트 스크립트(*Tests) · 리포트(*Report) · 끝 표시(TestRunDone) · 프리셋 내보내기는
-- **Studio에서만** 돈다. 게시된 서버 · 클라에서는 첫 실행 줄에서 아무것도 하지 않고 끝난다(#26에서 찾음 — 그전엔 게시 빌드에서도 돌았다).
--
-- 쓰는 법(스크립트 첫 실행 줄 — 머리 주석 바로 다음, 어떤 require보다 앞):
--   if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end
-- 도구 모듈의 run()은 함수 첫 줄에 같은 판정을 둔다. 빠짐은 tools/check_test_gate.py가 잡는다(T2).
--
-- 판정은 RunService:IsStudio() 하나. isStudio를 넘기면 그 값으로 판정한다(TestGateTests가 true · false를 주입한다 — T3).
-- TestHelpers(Shared)는 게이트를 두지 않는다 — 테스트 전용 모듈이지만 부르는 쪽(테스트)이 게이트 뒤에 있으니 게시 빌드에 남아도 불리지 않는다.

local TestGate = {}

function TestGate.shouldRun(isStudio: boolean?): boolean
	if isStudio == nil then
		return game:GetService("RunService"):IsStudio()
	end
	return isStudio == true
end

-- Studio 전용 개발 플래그(지시서 #39 — TEST_UI_PREVIEW 등): 값이 켜져 있고(nil · false가 아님) Studio일 때만 true.
-- 게시된 클라 · 서버에서는 플래그를 잘못 커밋해도 꺼진 것으로 본다. 커밋 값은 tools/check_test_gate.py가 nil · false인지 본다
function TestGate.flagOn(value: any, isStudio: boolean?): boolean
	if value == nil or value == false then
		return false
	end
	return TestGate.shouldRun(isStudio)
end

-- 커밋 값이 꺼져 있어야 하는 Studio 전용 플래그 이름(check_test_gate.py가 같은 목록으로 파일을 본다 — 빠지면 실패)
TestGate.STUDIO_FLAGS = { "TEST_UI_PREVIEW", "TEST_AUTOPLAY" }

return TestGate

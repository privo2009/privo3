--!strict
-- 서버 테스트 끝 표시 (지시서 #26 단계 1 — Studio 전용). 테스트 파일이 아니다(행이 아니다).
-- Server 아래 *Tests 스크립트의 요약 줄이 다 찍히면(또는 상한 90초) "[TestRunDone] server n/n files · N passed, M failed"를 찍는다.
-- 읽는 법 · 판정은 CLAUDE.md "테스트 개수 실측". 로직 · 근거는 Shared/TestRunLogic 상단.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestRunLogic = require(ReplicatedStorage.Shared.TestRunLogic)

task.defer(TestRunLogic.run, "server", script.Parent.Parent)

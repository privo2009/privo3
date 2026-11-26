--!strict
-- 자동 플레이 봇 시작(지시서 #43 1부 — Studio 전용). 서버가 Mock 프로필을 확인하고 ReplicatedStorage 속성 AutoplaySegment를 세울 때까지
-- 기다리기만 한다(보통 Play에서는 그 속성이 없어 아무것도 하지 않는다). 켜는 곳: Bootstrap TEST_AUTOPLAY. 조작 = AutoplayBot
if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

task.defer(require(script.Parent.AutoplayBot).run)

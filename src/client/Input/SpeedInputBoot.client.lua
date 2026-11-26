--!strict
-- SpeedInput 모듈을 살아 있게 하는 부트 스크립트.
--
-- 왜 따로 있는가: SpeedInput은 ModuleScript다. 모듈은 아무도 require하지 않으면 실행되지 않고, 그러면 서버의 SpeedApplied를
-- 받는 연결도 걸리지 않는다(받는 쪽이 없으면 클라에 이벤트가 쌓인다). 커스텀 이동 속도 입력 UI는 아직 없다(PowerBlock은 표시만) —
-- 그 UI가 SpeedInput을 require하게 되면 이 파일은 지워도 된다.
-- (지시서 #44: 왕복 확인용 VERIFY_ENABLED 블록과 적용값 · 준비 print를 지웠다 — 관측은 자동 플레이 봇 · Bootstrap [VERIFY] WalkSpeed 줄)

require(script.Parent.SpeedInput)

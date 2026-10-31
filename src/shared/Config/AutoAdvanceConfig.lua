--!strict
-- 자동 진행 모드 수치 (Phase 8 지시서 #18 — DESIGN.md "1. 챌린지 > 자동 진행 모드" AA2 · AA4 · AA12). 수치의 원본은 이 파일이다.
--
--   ADVANCE_DELAY_SEC   층을 클리어한 뒤 다음 층으로 넘기기까지(AA2). 사람이 "클리어"를 알아볼 만큼 · 1초 이하(지시서 #18 —
--                       Claude 결정 0.6). 이 동안 런 타이머는 이미 멈춰 있다(cleared) — 성공률에 영향이 없다
--   REPEAT_DELAY_SEC    수령 · 실패 뒤 다음 런까지(AA4 — 3초). 결과 안내가 보이고 캐릭터가 스폰으로 옮겨질 시간
--   LOOP_SEC            서버 단일 루프 주기(AA12). 진행 간격(0.6초)보다 충분히 짧게
--   REQUEST_MIN_INTERVAL_SEC  시작 · 중지 요청 빈도 상한(플레이어당)
--   SAFE_TIME_RATIO     안전층 여유(S15 — 2026-11-01 사람 결정, 지시서 #20). 안전층 비교에 쓰는 딜 총량의 시간 항(20초)에 곱한다.
--                       펀치는 예정 뒤 첫 루프 틱에 나가고 시간 초과는 Heartbeat가 따로 봐서 마지막 펀치 1회가 밀릴 수 있다(#19 조사 4).
--                       20초 펀치는 최소 40회라 10% 여유가 그 1회 누락을 덮는다. D 자체(AutoAdvanceLogic.dealTotal)에는 곱하지 않는다
--   (입구 들여 놓기는 두지 않는다 — 다음 층 입구 = 워프와 같은 ArenaService.moveToStageEntrance. 벽 트리거 이중 진행은 층 번호 비교로
--    막혀 들여 놓을 필요가 없었다 — DESIGN "진행 방식" · AutoAdvanceServiceTests · #18 실물 확인)

local AutoAdvanceConfig = {}

AutoAdvanceConfig.ADVANCE_DELAY_SEC = 0.6
AutoAdvanceConfig.REPEAT_DELAY_SEC = 3
AutoAdvanceConfig.LOOP_SEC = 0.1
AutoAdvanceConfig.REQUEST_MIN_INTERVAL_SEC = 0.5
AutoAdvanceConfig.SAFE_TIME_RATIO = 0.9

-- 자동 진행 게임패스 키(ShopConfig)
AutoAdvanceConfig.GAMEPASS_KEY = "autoAdvance"

function AutoAdvanceConfig.validate(): boolean
	assert(AutoAdvanceConfig.ADVANCE_DELAY_SEC > 0 and AutoAdvanceConfig.ADVANCE_DELAY_SEC <= 1,
		"AutoAdvanceConfig: ADVANCE_DELAY_SEC는 0 초과 1 이하(AA2)")
	assert(AutoAdvanceConfig.REPEAT_DELAY_SEC > 0, "AutoAdvanceConfig: REPEAT_DELAY_SEC는 0 초과")
	assert(AutoAdvanceConfig.LOOP_SEC > 0 and AutoAdvanceConfig.LOOP_SEC < AutoAdvanceConfig.ADVANCE_DELAY_SEC,
		"AutoAdvanceConfig: LOOP_SEC는 진행 간격보다 짧아야 함")
	assert(AutoAdvanceConfig.REQUEST_MIN_INTERVAL_SEC > 0, "AutoAdvanceConfig: REQUEST_MIN_INTERVAL_SEC는 0 초과")
	assert(type(AutoAdvanceConfig.SAFE_TIME_RATIO) == "number" and AutoAdvanceConfig.SAFE_TIME_RATIO > 0
		and AutoAdvanceConfig.SAFE_TIME_RATIO <= 1, "AutoAdvanceConfig: SAFE_TIME_RATIO는 0 초과 1 이하(S15 — 여유는 줄이는 쪽만)")
	return true
end

return AutoAdvanceConfig

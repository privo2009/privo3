--!strict
-- 자동 플레이 봇 설정(지시서 #43 1부 — Studio 전용 · Mock 프로필만). **게임 수치가 아니다** — 봇의 구간 · 행동 · 검사 상한뿐이다.
-- 켜는 곳: Bootstrap TEST_AUTOPLAY(커밋 값 nil). 돌리는 법 · 읽는 법 → CLAUDE.md "자동 플레이 봇" · HANDOFF restart.
-- 판정 · 보고 꼴은 Shared/AutoplayLogic(순수 — AutoplayLogicTests), 서버 검사는 Server/Tools/AutoplayMonitor, 조작은 Client/Tools/AutoplayBot.

local AutoplayConfig = {}

export type Segment = { preset: string, targetFloor: number, limitSec: number, label: string }

-- 구간 이름 = TEST_AUTOPLAY 값. preset = 그 구간이 여는 Mock 프로필(Shared/Config/TestPresets 이름).
-- 목표 층을 깨고 런이 MIN_RUNS 이상 · 지금 런이 없으면(마지막 가방까지 검사) 또는 limitSec이 지나면 끝난다
-- (못 닿아도 검사가 전부 통과면 통과 — 닿은 층은 지표로 적는다).
AutoplayConfig.SEGMENTS = {
	fresh = { preset = "fresh", targetFloor = 10, limitSec = 480, label = "fresh → 10층" },
	min30 = { preset = "min30", targetFloor = 17, limitSec = 360, label = "min30 → 17층 근처" },
	hour2 = { preset = "hour2", targetFloor = 25, limitSec = 420, label = "hour2 → 24 · 25층 도전" },
} :: { [string]: Segment }
AutoplayConfig.ORDER = { "fresh", "min30", "hour2" }
-- 목표 층에 닿아도 런이 이만큼은 돌아야 끝난다 — 실패 섞기(FAIL_EVERY_RUNS) 런이 한 번은 들어가게
AutoplayConfig.MIN_RUNS = 4

-- 시작: 서버 테스트 끝 줄([TestRunDone] server)을 본 뒤 이만큼 더 기다린다(클라 테스트 · 접속 안내가 가라앉게). 끝 줄 대기 상한
AutoplayConfig.START_DELAY_SEC = 8
AutoplayConfig.TEST_WAIT_MAX_SEC = 90

-- ===== 봇 행동(정책) — SuccessRateReport MODEL의 "보통 플레이어"를 흉내 낸다 ==================================
-- 진행: 클리어했을 때 남은 시간이 타이머의 이 몫 이상이면 다음 층(MODEL.ADVANCE_THRESHOLD_MIN과 같은 0.5) · 아니면 수령
AutoplayConfig.ADVANCE_TIME_SHARE = 0.5
-- 실패 섞기: 런 번호가 이 수의 배수면 둘째 층(못 가면 첫 층)에서 반경 밖에 서서 시간 초과로 진다 — 가방을 잃는 길을 지난다
AutoplayConfig.FAIL_EVERY_RUNS = 4
-- 환생: 최고 층이 이만큼 런 동안 안 오르고 블럭스가 비용 이상이면(SRR SIM.REBIRTH_PATIENCE_RUNS와 같은 3)
AutoplayConfig.REBIRTH_PATIENCE_RUNS = 3
-- 로비 운동: 런 사이에 가장 좋은 열린 기구에서 이만큼 클릭한다. 지난 런이 새 층을 못 열었으면 STALL_TRAIN_SEC
AutoplayConfig.GYM_TRAIN_SEC = 12
AutoplayConfig.STALL_TRAIN_SEC = 30
-- 클릭: 0.2초마다 이만큼 = 초당 10번(ClickService 수동 상한과 같다 — 넘기면 서버가 자른다)
AutoplayConfig.CLICK_PERIOD_SEC = 0.2
AutoplayConfig.CLICKS_PER_BATCH = 2
-- 요청 간격: RemoteGuard 기본 통(0.15초) · ForgeService 연타 상한(0.15초)보다 넉넉히
AutoplayConfig.REQUEST_GAP_SEC = 0.35
-- 대장간 한 번 들를 때 제작 상한 · 결과 기다림 상한
AutoplayConfig.CRAFTS_PER_VISIT = 4
AutoplayConfig.RESULT_WAIT_SEC = 3
-- 워프: 최고 층 − WARP_BACK 층으로, 비용이 보유 블럭스의 WARP_BUDGET_SHARE 이하일 때만(아니면 게이트로 1층부터)
AutoplayConfig.WARP_BACK = 3
AutoplayConfig.WARP_BUDGET_SHARE = 0.3
-- 이동: MoveTo 한 번의 상한(로블록스 MoveTo는 8초면 스스로 끝난다) · 이만큼 못 움직이면 막힌 것(점프 한 번 뒤 포기)
AutoplayConfig.MOVE_STEP_SEC = 6
AutoplayConfig.STUCK_SEC = 1.5
AutoplayConfig.STUCK_STUDS = 1
-- 실패 런: 층 중심에서 Z로 이만큼 떨어진 곳(공격 반경 밖 · 챌린지 구역 안)에 서서 기다린다 — AttackConfig 반경보다 커야 한다(AutoplayLogicTests)
AutoplayConfig.FAIL_STAND_Z = 97
-- 줍기: 층마다 드롭을 따라가는 상한(초) — 클리어 뒤에는 가방이 차거나 드롭이 없거나 이 시간이 지나면 결정한다
AutoplayConfig.PICKUP_CHASE_SEC = 6

-- ===== 검사 상한 ===========================================================================================
-- 서버 루프 합 = 서버 1초의 이 몫 이하(docs/TUNING.md 11 "서버 성능(#38)" — 12명 기준 5%. 봇은 1명이라 넉넉해야 정상)
AutoplayConfig.SERVER_LOOP_BUDGET_SHARE = 0.05
AutoplayConfig.CHECK_PERIOD_SEC = 0.5
-- 창 열기 · 닫기 확인: 미리보기 목록(Client/Tools/UiPreview.WINDOWS) 중 ScreenController에 등록된 창
AutoplayConfig.WINDOWS = { "Forge", "Equipment", "Pet", "Title", "Aura", "Shop", "Rebirth", "Warp", "AutoAdvance", "Settings", "Code" }
AutoplayConfig.WINDOW_WAIT_SEC = 0.6

-- 결과 줄 머리(이 머리로 시작하는 줄은 경고 · 오류 집계에서 뺀다 — 봇 자신의 줄)
AutoplayConfig.TAG = "[AUTOPLAY]"

return AutoplayConfig

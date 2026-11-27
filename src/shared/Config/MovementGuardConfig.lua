--!strict
-- 이동 익스플로잇 대비 설정(지시서 #43 2부 — Server/Systems/MovementGuard). 캐릭터 물리는 클라 소유라 서버가 보는 위치는 클라가 보낸 것이다 —
-- 줍기(거리 폴링) · 근접 자동 공격이 그 위치를 믿는다. 서버가 위치를 주기마다 적어 두고, 허용 속도를 넘는 이동이면 잠깐(HOLD_SEC)
-- 그 플레이어의 줍기 · 공격 틱을 무시하고 경고 로그를 남긴다. **킥하지 않는다**(오탐으로 정상 유저가 피해 보면 안 된다).
--
-- ⚠️ 전부 TEMP — 정상 플레이 오탐 0(자동 플레이 봇 #43 · MovementGuardTests)을 지키는 쪽으로 넉넉히 잡은 값이다.
-- 실제 서버(지연 · 끊김)에서 오탐이 보이면 여유부터 늘린다. 순간이동 · 3배 속도는 이 여유로도 잡혀야 한다(MovementGuardTests가 잰다).

local MovementGuardConfig = {}

-- 위치를 적는 주기(초). 서버 단일 루프
MovementGuardConfig.SAMPLE_SEC = 0.25

-- 수평 허용 속도 = 그 플레이어의 레벨 이동 속도 상한(SpeedService.getMaxSpeed) + SPEED_MARGIN(studs/초). TEMP
MovementGuardConfig.SPEED_MARGIN = 8
-- 한 주기 거리 여유(studs) — 복제가 몰려 오는 흔들림(한 주기에 두 주기 몫이 들어오는 등). TEMP
-- 지시서 #46 4부(Claude 결정 4 → 8): #45 봇이 진행 벽 통과 직후 정상 걷기(속도 43)를 69 studs/초로 걸렸다 — 위치 복제가 약 0.15초 늦게 와서
-- 0.25초 표본 하나에 17.3 studs(허용 (43 + 8) × 0.25 + 4 = 16.75). 여유 8이면 속도 여유 몫(8 × 0.25 = 2)과 합쳐 10 studs —
-- 복제 늦음을 속도 43에서 0.23초 · 상한 80(LevelConfig)에서 0.125초까지 받는다. 순간이동(한 번에 수십 studs) · 3배 속도는 그대로 잡힌다
-- (MovementGuardTests — "복제 0.15초 늦음(속도 43) → 통과" 줄이 #45 오탐을 재현한다).
-- "두 표본 연속일 때만" 방식은 쓰지 않는다 — 한 번에 뛰는 순간이동을 놓친다
MovementGuardConfig.SLACK_STUDS = 8

-- 수직: 오르는 속도 상한(점프 — 기본 JumpPower 50) · 떨어지는 속도 상한(studs/초). TEMP
MovementGuardConfig.UP_SPEED_MAX = 60
MovementGuardConfig.FALL_SPEED_MAX = 250

-- 걸리면 이만큼 그 플레이어의 줍기 · 공격 틱을 무시한다(초). TEMP
MovementGuardConfig.HOLD_SEC = 1.5

-- 게임이 옮긴 직후(워프 · 수령 뒤 스폰 · 게이트 · 리스폰 · 환생): 이만큼은 재지 않고 기준점만 다시 잡는다(초).
-- 서버가 옮긴 자리와 아직 오는 중인 옛 자리 복제가 섞여 보이는 창이다. TEMP
MovementGuardConfig.TELEPORT_GRACE_SEC = 1.0

-- 경고 로그 접기(같은 플레이어 반복 — LogFold 창)
MovementGuardConfig.LOG_TAG = "[MovementGuard]"

return MovementGuardConfig

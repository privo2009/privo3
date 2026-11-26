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
MovementGuardConfig.SLACK_STUDS = 4

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

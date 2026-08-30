--!strict
-- 드론 설정. DESIGN.md "5. 드론" 기준.
--
--   드론 스테이지 = maxStage - STAGE_OFFSET
--   드론 1대 = INTERVAL_SEC초당 해당 스테이지 보상 1회
--   드론 N대 = INTERVAL_SEC초당 N회 (선형, 상한 MAX_COUNT)
--   접속 중 / 오프라인 동일 효율. 오프라인은 OFFLINE_CAP_SEC까지만 쌓인다
--
-- ⚠️ 이 넷 말고 다른 규칙(챌린지 개입 없음, 로벅스 전용 등)은 DESIGN.md가 원본이다.
--    여기로 복사하지 말 것.
--
-- ===== STAGE_OFFSET = 4 확정 근거 (Phase 5 착수 조건, 4-2-f 연장) =====================
--
-- DroneRateReport 실측(src/server/Tools/DroneRateReport.lua "[1] 오프셋 스윕", 기준
-- 클릭률 8) — 능동/드론 비율(그 층 능동 벌이 속도 ÷ 드론 1대 수입)의 전 층 중앙값이
-- DESIGN.md "5. 드론"의 "능동 플레이가 분당 20~60배 효율이어야 한다" 규약 안에 드는
-- 오프셋을 찾는다.
--
--   오프셋 2 (기존 명세) — 중앙값 5.89배. 하한(20배)의 1/3에도 못 미친다.
--                          오프라인 8시간이 능동 플레이 70~250분어치가 되어
--                          "드론이 더 좋으면 능동 콘텐츠가 죽는다"가 우려하는
--                          상황 그 자체가 된다. 기각.
--   오프셋 4            — 중앙값 42.29배. 20~60배 규약 안. 채택.
--   오프셋 5            — 중앙값 113.96배. 상한(60배) 초과 — 드론이 지나치게 약하다. 기각.
--
-- ⚠️ 이 값을 다시 바꾸려면 DroneRateReport를 다시 돌려 확인할 것. 감으로 바꾸지 않는다
--    (그 리포트가 정확히 이 판단을 위해 만들어졌다).
local DroneConfig = {}

DroneConfig.STAGE_OFFSET = 4

-- 1대가 1회 수입을 내는 주기(초). DESIGN.md "5. 드론": "드론 1대 = 60초당 해당
-- 스테이지 보상 1회".
DroneConfig.INTERVAL_SEC = 60

-- 오프라인 누적 상한(초). DESIGN.md "5. 드론": "오프라인 상한 8시간(게임패스로 24시간)".
-- ⚠️ 24시간 게임패스는 이번 범위가 아니다(DroneService.collect가 상한을 인자로 받는
-- 형태로만 열어둔다) — 여기 있는 값은 게임패스 없는 기본 상한이다.
DroneConfig.OFFLINE_CAP_SEC = 8 * 60 * 60

-- 드론 최대 보유 대수. DESIGN.md "5. 드론": "로벅스 전용, 상한 5대".
DroneConfig.MAX_COUNT = 5

function DroneConfig.validate(): boolean
	assert(
		type(DroneConfig.STAGE_OFFSET) == "number" and DroneConfig.STAGE_OFFSET >= 0 and DroneConfig.STAGE_OFFSET % 1 == 0,
		string.format("DroneConfig: STAGE_OFFSET(%s)는 0 이상의 정수여야 함", tostring(DroneConfig.STAGE_OFFSET))
	)

	assert(
		type(DroneConfig.INTERVAL_SEC) == "number" and DroneConfig.INTERVAL_SEC > 0,
		string.format("DroneConfig: INTERVAL_SEC(%s)는 0보다 커야 함", tostring(DroneConfig.INTERVAL_SEC))
	)

	assert(
		type(DroneConfig.OFFLINE_CAP_SEC) == "number" and DroneConfig.OFFLINE_CAP_SEC > 0,
		string.format("DroneConfig: OFFLINE_CAP_SEC(%s)는 0보다 커야 함", tostring(DroneConfig.OFFLINE_CAP_SEC))
	)

	-- 상한이 주기의 배수가 아니어도 DroneService.collect는 동작한다(상한에 걸리면
	-- 나머지를 버리고 lastCollectAt = now로 밀 뿐이다) — 하지만 배수가 아니면
	-- "오프라인 8시간 = 정확히 480사이클"이라는, DroneRateReport [2]가 전제하는 환산이
	-- 어긋난다. 그 리포트를 다시 참조할 값이므로 여기서 막아둔다.
	assert(
		DroneConfig.OFFLINE_CAP_SEC % DroneConfig.INTERVAL_SEC == 0,
		string.format(
			"DroneConfig: OFFLINE_CAP_SEC(%d)는 INTERVAL_SEC(%d)의 배수여야 함",
			DroneConfig.OFFLINE_CAP_SEC,
			DroneConfig.INTERVAL_SEC
		)
	)

	assert(
		type(DroneConfig.MAX_COUNT) == "number" and DroneConfig.MAX_COUNT >= 1 and DroneConfig.MAX_COUNT % 1 == 0,
		string.format("DroneConfig: MAX_COUNT(%s)는 1 이상의 정수여야 함", tostring(DroneConfig.MAX_COUNT))
	)

	-- Schema.LIMITS.MAX_DRONES와의 일치는 여기서 보지 않는다. 이 파일은 Schema를
	-- 몰라야 한다(다른 어떤 Config도 Schema를 require하지 않는다 — 상호 참조를 만들지
	-- 않는 것이 이 코드베이스의 관례다). 그 대조는 ConfigTests가 한다.
	return true
end

return DroneConfig

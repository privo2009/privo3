--!strict
-- 근처 확인 여유 (지시서 #23 N1 — DESIGN.md 13장 "서버 권위 — 근처 확인"). 수치의 원본은 이 파일이다. 테스트도 이 값을 읽는다.
--
-- Touched로 동작하는 곳(입장 게이트 · 수령 발판 · 진행 벽 트리거 · 클릭 파워 패드)은 처리 전에 서버가 HumanoidRootPart가
-- 그 파트 근처인지 본다(Server/Systems/Proximity). 근처 = 파트 로컬 좌표에서 축마다 |d| ≤ 크기/2 + PROXIMITY_MARGIN.
--
--   PROXIMITY_MARGIN = REACH_STUDS + 최고 속도 × LAG_SEC  (지금 6 + 80 × 0.25 = 26 studs)
--     REACH_STUDS  Touched를 일으킨 것은 팔다리 · 발이고 루트는 몸통 가운데다. R15 발바닥까지 HipHeight 2 + 루트 반 높이 1 ≈ 3 —
--                  아바타 크기 · 팔 뻗음을 넉넉히 덮어 6
--     LAG_SEC      서버가 읽는 루트 위치는 접촉 신호와 같은 순간이 아닐 수 있다(클라 물리 복제 지연 · 프레임 드랍).
--                  30fps(LevelConfig.REFERENCE_FPS) 기준 7.5프레임 — 최고 속도로 달린 거리 20 studs를 덮는다
--     최고 속도     숫자로 적지 않는다 — LevelConfig.getMaxWalkSpeed()(발판 깊이 유도). 발판이 바뀌면 여유도 따라간다
--
-- ⚠️ 정상 플레이(빠른 이동 · 최고 속도 · 프레임 드랍)를 거부하면 안 된다. 거부 로그가 보이면 줄이기 전에 원인부터 본다.
--    막는 것은 그 파트에서 여유보다 먼 접촉(스폰에서 아레나로 · 다른 층 발판으로)이다. 여유 안의 순간 이동은 막지 못한다.

local LevelConfig = require(script.Parent.LevelConfig)

local ProximityConfig = {}

ProximityConfig.REACH_STUDS = 6
ProximityConfig.LAG_SEC = 0.25

-- 유도값. 테스트가 이 식을 다시 계산해 대조한다
ProximityConfig.PROXIMITY_MARGIN = ProximityConfig.REACH_STUDS + LevelConfig.getMaxWalkSpeed() * ProximityConfig.LAG_SEC

function ProximityConfig.validate(): boolean
	assert(ProximityConfig.REACH_STUDS > 0 and ProximityConfig.LAG_SEC > 0, "ProximityConfig: 여유 재료는 0 초과")
	local m = ProximityConfig.PROXIMITY_MARGIN
	assert(m == m and m > 0 and m < math.huge, "ProximityConfig: 여유는 유한한 양수")
	return true
end

return ProximityConfig

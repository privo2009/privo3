--!strict
-- 블록 배치 기하 상수. DESIGN.md 2장(배치: 1~4 중앙 사각 / 5~8 원형 / 9~16 이중 원) 기준.
-- ⚠️ 밸런싱/구조 수치는 CLAUDE.md 규칙대로 여기 한 곳에서만 정의한다.
-- BlockService.lua(배치 반지름 계산)와 BlockModelGenerator.lua(실제 큐브 모델 크기)가
-- 둘 다 이 모듈을 통해서만 블록 크기를 알아야 한다 — 전에는 두 값이 서로 몰라서
-- 블록끼리 최대 62%까지 겹쳐 보이는 문제가 있었다 (BlockService는 반지름 6~14를
-- 하드코딩, BlockModelGenerator는 격자 4×cubeSize 4=16 studs를 따로 하드코딩 — 서로 무관).

local BlockLayoutConfig = {}

-- 블록 모델 크기. BlockModelGenerator가 실제로 만드는 격자와 반드시 같아야 한다.
-- 근거(Phase 3-4 결정): 파편 동시 상한 200개(CLAUDE.md) 안에서 블록 3개가 동시에
-- 완전파괴돼도(3×64=192) 풀 한계를 안 넘는 선 — BlockModelGenerator.lua 상단 참고.
BlockLayoutConfig.GRID_SIZE = 4 -- 한 변당 큐브 개수 (4x4x4 = 64개)
BlockLayoutConfig.CUBE_SIZE = 4 -- 큐브 한 변 길이 (studs)
BlockLayoutConfig.BLOCK_SPAN = BlockLayoutConfig.GRID_SIZE * BlockLayoutConfig.CUBE_SIZE -- 블록 한 변 길이 = 16

-- ===== 배치 반지름 배율 ================================================================
-- 전부 "BLOCK_SPAN × 배율" 형태로만 쓴다. BlockService.lua에 절대 studs 값을 직접 넣지 않는다.
--
-- 배율 산출 근거: 정N각형으로 균등 배치된 점들의 인접 간격 = 2 × R × sin(π/N).
-- 블록끼리 안 겹치려면 이 간격이 BLOCK_SPAN 이상이어야 하므로, 이론상 최소 배율은
-- 1 / (2 × sin(π/N))이다. 실제 값은 여기서 더 올려서(previewLayout으로 실측 확인하며
-- 튜닝) 쓰는 경우가 많다 — 정확한 최소 대비 여유는 각 상수 옆 주석 참고. 현재 값 기준
-- 최소 간격은 항상 BLOCK_SPAN 이상(최소 여유 1.15배 이상)임을 매번 계산으로 확인했다.
--
-- 이중 원(안쪽↔바깥쪽)은 같은 링 안의 간격뿐 아니라, 각도가 22.5도 어긋난 안쪽-바깥쪽
-- 최근접 쌍의 거리도 BLOCK_SPAN 이상이어야 해서 코사인 법칙으로 따로 계산했다 — 이쪽이
-- 실제로 더 빡빡한 제약이라 OUTER_RING_MULT의 하한을 결정한다.
--
-- 이 값들을 바꾸면 BlockService의 반지름도 자동으로 같이 바뀐다 — 튜닝은 여기서만 한다.
-- (previewLayout(count, material)로 눈으로 재확인 권장)

-- 사각(4개, N=4): 최소 배율 1/(2·sin45°) ≈ 0.7071, ×1.15 여유 → 0.82
BlockLayoutConfig.SQUARE_RADIUS_MULT = 0.82

-- 원(8개, N=8): 이론상 최소 1.3066(×1.15 여유면 1.5)이지만, 실측 후 2.0으로 상향.
-- 8개 배치와 이중 원 안쪽이 같은 8각형 배치라 INNER_RING_MULT와 항상 같이 움직인다.
BlockLayoutConfig.CIRCLE_RADIUS_MULT = 2.0

-- 이중 원 안쪽(8개, N=8): 원(8개)과 같은 배치라 CIRCLE_RADIUS_MULT와 항상 동일하게 둔다.
BlockLayoutConfig.INNER_RING_MULT = 2.0

-- 이중 원 바깥쪽(8개): 안↔바깥 최근접 거리(각도차 22.5도, 코사인 법칙)가 실제 하한을 정한다.
-- INNER_RING_MULT를 올릴 때마다 안쪽이 바깥쪽에 다시 가까워지므로 같이 올려야 한다.
-- 2.0/3.2 기준으로 안↔바깥 거리가 너무 좁아져서 3.8로 상향.
-- 2.0/3.8 기준 안↔바깥 최근접 거리 = BLOCK_SPAN × 2.10, 바깥 링끼리 간격 = BLOCK_SPAN × 2.91,
-- 안쪽 링끼리 간격 = BLOCK_SPAN × 1.53 — 전부 최소 여유(1.15배)보다 넉넉하다.
BlockLayoutConfig.OUTER_RING_MULT = 3.8

return BlockLayoutConfig

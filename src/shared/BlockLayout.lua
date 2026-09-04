--!strict
-- 블록 배치 좌표 계산 (순수). 서버·클라가 **같은 좌표**를 각자 계산해야 해서 shared에 있다.
--
-- 왜 공유해야 하는가: 서버는 이 좌표로 "가까운 블록부터" 데미지 판정을 하고, 클라는 같은
-- 좌표에 모델을 세운다. 좌표를 전송하지 않고 양쪽이 count 하나로 각자 계산한다 —
-- 같은 입력에 같은 출력을 주는 순수 함수라 전송할 이유가 없다.
-- (원래 BlockService 안에 있었고, 4-2-a2에서 블록 렌더링이 클라로 넘어오며 여기로 나왔다)
--
-- DESIGN.md "2. 블록": 1~4 중앙 사각 / 5~8 원형 / 9~16 이중 원(안8+바깥8),
-- 16칸을 미리 배치해두고 앞에서부터 잘라 쓴다.
--
-- 반지름은 BlockLayoutConfig.BLOCK_SPAN(블록 실제 크기) × 배율로만 계산한다 — 여기에
-- studs 절대값을 직접 하드코딩하지 않는다 (CLAUDE.md: 밸런싱 수치는 Config로).
-- 배율 산출 근거는 BlockLayoutConfig.lua에 있다.
--
-- ===== 좌표는 원점 고정이다 (중요) ======================================================
--
-- 여기서 나오는 좌표는 플레이어와 무관한 절대 좌표다. 플레이어별 오프셋을 붙이지 않는다.
--
-- 예전에는 이것이 문제였다. 서버가 블록 모델을 만들어 전원에게 복제했으므로, 2인 이상이면
-- 모두의 블록이 같은 자리에 겹쳐 섰다. 그때 "배치하는 쪽에서 오프셋을 붙이자"는 안이 있었고,
-- 그건 틀린 해법이었다 — 서버의 거리 판정이 쓰는 좌표와 화면에 보이는 위치가 어긋나서
-- "가까운 블록부터"가 통째로 틀어진다. 판정 좌표와 표시 좌표는 반드시 같아야 한다.
--
-- 4-2-a2에서 그 문제 자체가 사라졌다. 블록 모델을 각 클라가 자기 것만 만들기 때문에
-- 내 화면에는 내 블록만 있고, 겹칠 대상이 없다. 그래서 오프셋도 개인 구역도 필요 없고
-- 좌표는 원점 고정으로 둔다. 판정 좌표 = 표시 좌표가 공짜로 성립한다.
--
-- ⚠️ 그러므로 이 함수에 player 인자를 추가하지 말 것. 추가하는 순간 위 등식이 깨진다.
--
-- ===== 4-2-a2b: stage 오프셋은 player 오프셋이 아니다 ===================================
--
-- 위 경고는 **여전히 유효하다.** 그런데 `computeLayout`이 이제 `stage`를 받는다.
-- 둘은 성격이 정반대이므로 섞어 읽지 말 것:
--
--   player 오프셋   같은 순간에 사람마다 다른 좌표를 준다 → 판정 좌표 ≠ 표시 좌표
--   stage 오프셋    같은 층이면 누구에게나 같은 좌표를 준다 → 등식이 유지된다
--
-- 스테이지는 런 상태값이지 사람 속성이 아니다. 2인이 같은 3층에 있으면 둘 다
-- 같은 X를 얻는다(각자 자기 블록만 보는 것은 4-2-a2의 렌더링 결정이고 좌표와 무관하다).
--
-- 왜 필요했는가: 4-2-a에서 아레나가 +X로 늘어섰는데 이 함수가 오프셋을 안 받아서
-- **25개 층의 블록이 전부 X=0에 겹쳐 있었다.** 진행 벽을 세워도 통과한 자리에
-- 다음 블록이 없고 뒤에 있다 — 코어 루프의 절반이 그것 때문에 비어 있었다.
--
-- ⚠️ **오프셋을 부르는 쪽에서 더하지 말 것.** 서버 판정(AttackService)·서버 배치
-- (BlockService)·클라 렌더(RemoteReceiver) 셋이 각자 더하면 언젠가 한 곳이 빠지고,
-- 그때 증상은 "블록이 보이는데 안 맞는다"이다. `getStageOrigin` 하나만 통과한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)

local BlockLayout = {}

local SQUARE_RADIUS = BlockLayoutConfig.BLOCK_SPAN * BlockLayoutConfig.SQUARE_RADIUS_MULT
local CIRCLE_RADIUS = BlockLayoutConfig.BLOCK_SPAN * BlockLayoutConfig.CIRCLE_RADIUS_MULT
local INNER_RING_RADIUS = BlockLayoutConfig.BLOCK_SPAN * BlockLayoutConfig.INNER_RING_MULT
local OUTER_RING_RADIUS = BlockLayoutConfig.BLOCK_SPAN * BlockLayoutConfig.OUTER_RING_MULT

-- count개 점을 반지름 radius인 원 위에 angleOffsetDeg부터 균등 배치한다.
local function ring(count: number, radius: number, angleOffsetDeg: number): { Vector3 }
	local positions = {}
	for i = 1, count do
		local angle = math.rad(angleOffsetDeg + (i - 1) * (360 / count))
		positions[i] = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	return positions
end

-- 모듈 로드 시 한 번만 계산되는 고정 슬롯 풀. 스테이지 진입마다 다시 만들지 않는다.
local SQUARE_SLOTS = ring(4, SQUARE_RADIUS, 45) -- 사각형 = 4점 균등 원 배치와 동일
local CIRCLE_SLOTS = ring(8, CIRCLE_RADIUS, 0)
local DOUBLE_RING_SLOTS = (function()
	local inner = ring(8, INNER_RING_RADIUS, 0)
	local outer = ring(8, OUTER_RING_RADIUS, 22.5) -- 안쪽 점 사이사이에 오도록 오프셋
	local combined = {}
	for i, pos in ipairs(inner) do
		combined[i] = pos
	end
	for i, pos in ipairs(outer) do
		combined[8 + i] = pos
	end
	return combined
end)()

-- 스테이지 N의 블록 클러스터가 통째로 놓이는 자리.
--
-- ⚠️ **판정 좌표 = 표시 좌표 계약의 이음매다.** 블록 위치를 알아야 하는 쪽은 전부
-- 이 함수를 통과한다 — 서버 배치(BlockService)·클라 렌더(RemoteReceiver)·거리 판정
-- (AttackService). 셋이 각자 200×(N-1)을 계산하면 언젠가 한 곳이 갈린다.
--
-- ⚠️ 200을 여기 적지 않는다. 주기는 ArenaConfig가 STAGE_WIDTH+GAP_WIDTH에서 유도한다.
--
-- stage가 nil이면 원점이다. 4-2-a2b 이전 동작과 같다 — 스테이지를 모르는 호출자
-- (개발용 미리보기 BlockModelGenerator 등)가 예전 그대로 돌게 하기 위한 것이지,
-- 실물 경로가 생략해도 되는 인자라는 뜻이 아니다.
function BlockLayout.getStageOrigin(stage: number?): Vector3
	if stage == nil then
		return Vector3.zero
	end
	return Vector3.new(ArenaConfig.getStageCenterX(stage), 0, 0)
end

-- count(1~16)에 맞는 고정 슬롯 풀에서 앞 count개만 잘라 반환한다.
-- stage를 주면 그 층의 클러스터 자리로 통째로 옮겨진다(슬롯 사이의 상대 배치는 그대로).
function BlockLayout.computeLayout(count: number, stage: number?): { Vector3 }
	assert(count >= 1 and count <= 16, "computeLayout: count는 1~16 사이여야 함")

	local slots: { Vector3 }
	if count <= 4 then
		slots = SQUARE_SLOTS
	elseif count <= 8 then
		slots = CIRCLE_SLOTS
	else
		slots = DOUBLE_RING_SLOTS
	end

	-- ⚠️ 슬롯 풀은 모듈 로드 시 한 번 만들어지는 **공유 테이블**이다. 여기서
	-- slots[i]를 그대로 넘기지 않고 더한 새 Vector3를 넣는 이유가 그것이다 —
	-- Vector3는 불변이라 덧셈이 새 값을 만들고, 풀은 오염되지 않는다.
	local origin = BlockLayout.getStageOrigin(stage)
	local positions = {}
	for i = 1, count do
		positions[i] = slots[i] + origin
	end
	return positions
end

-- 가장 바깥 링의 반지름(블록 **중심**까지). 최대 배치(이중 원)의 최외곽이며 count와
-- 무관하다 — 바깥 링은 로드 시 고정 슬롯 풀로 미리 서고 computeLayout은 앞에서부터
-- 자를 뿐이다. 그래서 "최대 배치의 최외곽"을 알려고 개수 16을 알 필요가 없다.
--
-- 여기 둔 이유: GROUND_Y_OFFSET과 같다. 이 값을 필요로 하는 쪽(근접 판정 반경 —
-- Config/AttackConfig)이 BLOCK_SPAN × OUTER_RING_MULT를 자기 파일에서 다시 계산하면,
-- 여기서 최외곽 계산 방식을 바꿨을 때 그쪽만 옛 식으로 남는다. 식은 한 곳에만 있어야 한다.
--
-- ⚠️ 블록 **바깥면**이 아니라 중심까지의 거리다. 표면까지 필요하면 BLOCK_SPAN/2를 더한다.
BlockLayout.OUTER_RADIUS = OUTER_RING_RADIUS

-- 레이아웃 좌표는 전부 Y=0(수평면)이라 그대로 쓰면 블록 절반이 바닥에 묻힌다.
-- 블록 바닥이 Y=0에 오도록 중심을 반 칸 띄우는 값 — 모델을 세우는 쪽이 더해서 쓴다.
-- 여기 둔 이유: 클라 렌더링(RemoteReceiver)과 개발용 미리보기(previewLayout)가 같은 값을
-- 써야 하는데, 한쪽에만 있으면 두 화면이 다른 높이로 보인다.
BlockLayout.GROUND_Y_OFFSET = BlockLayoutConfig.BLOCK_SPAN / 2

return BlockLayout

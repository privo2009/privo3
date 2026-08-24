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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- count(1~16)에 맞는 고정 슬롯 풀에서 앞 count개만 잘라 반환한다.
function BlockLayout.computeLayout(count: number): { Vector3 }
	assert(count >= 1 and count <= 16, "computeLayout: count는 1~16 사이여야 함")

	local slots: { Vector3 }
	if count <= 4 then
		slots = SQUARE_SLOTS
	elseif count <= 8 then
		slots = CIRCLE_SLOTS
	else
		slots = DOUBLE_RING_SLOTS
	end

	local positions = {}
	for i = 1, count do
		positions[i] = slots[i]
	end
	return positions
end

-- 레이아웃 좌표는 전부 Y=0(수평면)이라 그대로 쓰면 블록 절반이 바닥에 묻힌다.
-- 블록 바닥이 Y=0에 오도록 중심을 반 칸 띄우는 값 — 모델을 세우는 쪽이 더해서 쓴다.
-- 여기 둔 이유: 클라 렌더링(RemoteReceiver)과 개발용 미리보기(previewLayout)가 같은 값을
-- 써야 하는데, 한쪽에만 있으면 두 화면이 다른 높이로 보인다.
BlockLayout.GROUND_Y_OFFSET = BlockLayoutConfig.BLOCK_SPAN / 2

return BlockLayout

--!strict
-- 운동기구 배치 좌표와 "이 위치가 어느 기구 위인가" 판정 (순수). PadLayout과 같은 성격이다 —
-- 좌표만 만들고 Instance는 만들지 않는다. 파트 생성은 Server/Systems/GymService가 한다.
--
-- ===== 어디에 서는가 =====================================================================
--
-- 스폰 구역 안, 패드 줄(Z = 0) 옆에 한 줄로 선다. 기구 i번은 좌표 i번이다 — 스폰에서 멀어질수록
-- 강한 기구라 패드와 같은 방향으로 읽힌다(PadLayout "왜 일렬인가"와 같은 이유).
--
--   Z = 0        패드 1 … 24
--   Z = LANE_Z   기구 1 … 8      (스폰 구역 반폭의 절반 — 패드 줄과 경계 벽 사이 가운데)
--
-- 챌린지 구간(입장 게이트 너머)에는 기구가 없다. 그래서 런 중 클릭에는 기구 배수가 붙지 않는다.
--
-- ⚠️ 배치 상수는 초안값이다. 지환 파트와 맵이 들어오면 SIZE · PITCH는 조정 대상이다
--    (PadLayout "배치 상수는 초안값이다"와 같다). 경계·축은 ArenaConfig가 원본이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)

local GymLayout = {}

-- 기구 하나의 발판 크기 (studs). 캐릭터가 올라서서 클릭하는 자리라 패드(8)보다 넓게 잡았다.
GymLayout.SIZE = Vector3.new(16, 1, 16)

-- 기구 중심 간 거리 (studs). SIZE.X의 2배 — 기구 사이로 걸어 다닐 틈을 둔다.
GymLayout.PITCH = 32

-- 첫 기구 중심이 스폰 구역 시작(SPAWN_ZONE_X_MIN)에서 떨어진 거리. 경계 벽에 붙지 않게.
GymLayout.START_GAP = 30

-- 기구 줄의 Z. 스폰 구역 반폭의 절반 — 패드 줄(Z = 0)과 경계 벽 사이 가운데다.
-- 음수 쪽인 이유는 없다(대칭). 한쪽으로 정해 둘 뿐이다.
GymLayout.LANE_Z = -ArenaConfig.SPAWN_ZONE_Z_HALF / 2

-- 발판 윗면이 지면 위에 오게 중심을 반 칸 띄운다 (PadLayout.GROUND_Y_OFFSET과 같은 이유).
GymLayout.GROUND_Y_OFFSET = GymLayout.SIZE.Y / 2

-- 발판 위 판정 높이(studs). 서 있는 캐릭터의 HumanoidRootPart는 지면에서 약 3 위에 있다 —
-- 점프 중에도 놓치지 않게 넉넉히 잡는다.
GymLayout.STAND_HEIGHT = 12

-- 기구 count개의 중심 좌표. i번째가 기구 i번이다.
function GymLayout.computeLayout(count: number): { Vector3 }
	assert(type(count) == "number" and count >= 0 and count % 1 == 0, "GymLayout.computeLayout: count는 0 이상의 정수")
	local positions: { Vector3 } = {}
	local firstX = ArenaConfig.SPAWN_ZONE_X_MIN + GymLayout.START_GAP
	for i = 1, count do
		table.insert(positions, Vector3.new(firstX + (i - 1) * GymLayout.PITCH, GymLayout.GROUND_Y_OFFSET, GymLayout.LANE_Z))
	end
	return positions
end

-- position이 center 기구의 발판 위(위쪽 STAND_HEIGHT 안)인가.
function GymLayout.isOn(center: Vector3, position: Vector3): boolean
	local half = GymLayout.SIZE / 2
	local bottom = center.Y - half.Y
	return math.abs(position.X - center.X) <= half.X
		and math.abs(position.Z - center.Z) <= half.Z
		and position.Y >= bottom
		and position.Y <= bottom + GymLayout.STAND_HEIGHT
end

-- position이 올라서 있는 기구 번호. 어느 기구 위도 아니면 nil.
function GymLayout.findAt(position: Vector3, count: number): number?
	for i, center in ipairs(GymLayout.computeLayout(count)) do
		if GymLayout.isOn(center, position) then
			return i
		end
	end
	return nil
end

return GymLayout

--!strict
-- 운동기구 배치 좌표와 "이 위치가 어느 기구 위인가" 판정 (순수). PadLayout과 같은 성격이다 —
-- 좌표만 만들고 Instance는 만들지 않는다. 파트 생성은 Server/Systems/GymService가 한다.
--
-- ===== 어디에 서는가 (지시서 #8 M1 — 2026-10-23 사람 결정) ================================
--
--   -Z 옆   패드 24개 (PadLayout)
--   Z = 0   스폰 ──── 가운데 통로 ──── 입장 게이트     (통로에는 아무것도 없다)
--   +Z 옆   운동기구 9개, 2줄 격자            ← 여기
--
-- 기구 i번은 좌표 i번이다. 열 c(= ceil(i / 2))가 게이트 쪽으로 갈수록 커지고, 한 열 안에서는 통로 쪽(안쪽 줄)이 앞 번호다 —
-- 패드와 같은 방향으로 "게이트 쪽일수록 세다"가 읽힌다. 기구가 홀수(9)라 맨 끝 열에는 9번 하나만 선다 —
-- 9번이 로벅스 전용 공허 훈련 구역(가장 비싸고 가장 센 것)이고 맨 끝이다.
--
-- 챌린지 구간(입장 게이트 너머)에는 기구가 없다. 그래서 런 중 클릭에는 기구 배수가 붙지 않는다.
--
-- ⚠️ 배치 상수는 초안값이다. 파트와 맵이 들어오면 SIZE · 간격은 조정 대상이다
--    (PadLayout "배치 상수는 초안값이다"와 같다). 경계·축은 ArenaConfig가 원본이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local BigNum = require(ReplicatedStorage.Shared.BigNum)

type BigNumber = BigNum.BigNumber

local GymLayout = {}

-- 기구 하나의 발판 크기 (studs). 캐릭터가 올라서서 클릭하는 자리라 패드(8)보다 넓게 잡았다.
GymLayout.SIZE = Vector3.new(16, 1, 16)

-- 열 간격(진행축) · 줄 간격(Z). SIZE + 8 — 기구 사이로 걸어 다닐 틈.
GymLayout.PITCH = 24
GymLayout.ROWS = 2
GymLayout.ROW_PITCH = 24

-- 첫 열이 스폰 지점보다 앞(+X)에 선 거리. 5열이면 마지막 열이 -192 + 4 × 24 = -96 — 게이트(-74) 앞에서 끝난다.
GymLayout.START_AHEAD_OF_SPAWN = 8

-- 안쪽 줄의 Z. 통로(Z = 0)에서 기구 가장자리까지 32 studs — 패드 안쪽 줄(PadLayout.LANE_Z = -36)과 대칭인 여유.
-- 바깥쪽 줄은 +Z로 ROW_PITCH만큼 더 간다.
GymLayout.LANE_Z = 40

-- 발판 윗면이 지면 위에 오게 중심을 반 칸 띄운다 (PadLayout.GROUND_Y_OFFSET과 같은 이유).
GymLayout.GROUND_Y_OFFSET = GymLayout.SIZE.Y / 2

-- 발판 위 판정 높이(studs). 서 있는 캐릭터의 HumanoidRootPart는 지면에서 약 3 위에 있다 —
-- 점프 중에도 놓치지 않게 넉넉히 잡는다.
GymLayout.STAND_HEIGHT = 12

-- 기구 i번의 열(1부터)과 줄(0 = 안쪽, 1 = 바깥쪽).
function GymLayout.cellOf(index: number): (number, number)
	return math.ceil(index / GymLayout.ROWS), (index - 1) % GymLayout.ROWS
end

-- 기구 count개의 중심 좌표. i번째가 기구 i번이다.
function GymLayout.computeLayout(count: number): { Vector3 }
	assert(type(count) == "number" and count >= 0 and count % 1 == 0, "GymLayout.computeLayout: count는 0 이상의 정수")
	local positions: { Vector3 } = {}
	local firstX = ArenaConfig.SPAWN_X + GymLayout.START_AHEAD_OF_SPAWN
	for i = 1, count do
		local column, row = GymLayout.cellOf(i)
		table.insert(positions, Vector3.new(
			firstX + (column - 1) * GymLayout.PITCH,
			GymLayout.GROUND_Y_OFFSET,
			GymLayout.LANE_Z + row * GymLayout.ROW_PITCH
		))
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

export type Resolution = {
	multiplier: number, -- 클릭에 곱할 배수. 기구 위가 아니거나 잠겼으면 1
	index: number?, -- 올라선 기구 번호 (기구 위가 아니면 nil)
	unlocked: boolean,
}

-- 위치와 환생 수로 배수를 정한다. position이 nil이면(캐릭터 없음) 기구 위가 아니다.
-- 서버(GymService — 실제 클릭 배수)와 클라(클릭 팝업 · 기구 3D 표시 — 보이기만)가 같은 이 함수를 부른다(지시서 #8).
-- shopUnlocked(index) — 로벅스로 열렸는가(선해금 기록 · 공허 게임패스 소유 — 지시서 #16). 없으면 환생 수로만 본다.
-- 열림 = 환생 해금 **OR** shopUnlocked. 서버는 GymService가, 클라 표시는 Store 값으로 같은 판정을 넘긴다.
-- 로벅스로 열렸는가(지시서 #16): 선해금 기록(gymUnlocks["번호"] == true — 개발자 상품, 기록은 #17) 또는 그 기구의 게임패스 소유
-- (공허 훈련 구역). 서버 GymService(프로필 · GamepassService)와 클라 표시(Store shop — 기록은 아직 요약에 없다)가 이 함수를 쓴다.
-- ⚠️ 개발자 상품 키를 owns로 "가졌다"고 해도 열지 않는다 — 선해금은 기록만 본다.
function GymLayout.shopUnlocked(gymUnlocks: any, owns: (string) -> boolean): (number) -> boolean
	return function(index: number): boolean
		if type(gymUnlocks) == "table" and gymUnlocks[tostring(index)] == true then
			return true
		end
		local key = GymConfig.getShopKey(index)
		local def = ShopConfig.get(key)
		return def ~= nil and def.kind == "gamepass" and owns(key)
	end
end

function GymLayout.resolve(position: Vector3?, rebirths: BigNumber?, shopUnlocked: ((number) -> boolean)?): Resolution
	if position == nil then
		return { multiplier = 1, index = nil, unlocked = false }
	end
	local index = GymLayout.findAt(position, GymConfig.getCount())
	if index == nil then
		return { multiplier = 1, index = nil, unlocked = false }
	end
	local r = rebirths or BigNum.new(0, 0)
	if not GymConfig.isUnlockedByRebirths(index, r) and not (shopUnlocked ~= nil and shopUnlocked(index)) then
		return { multiplier = 1, index = index, unlocked = false }
	end
	return { multiplier = GymConfig.getMultiplier(index), index = index, unlocked = true }
end

return GymLayout

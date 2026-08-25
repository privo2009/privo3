--!strict
-- PadService / PadLayout 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-b 검증: 패드 좌표 / Touched 디바운스 / 해금 판정 / 선택 세팅 / 로드 클램프.
--
-- PadService._pure의 순수 함수만 호출한다 — Player/Instance 없이 검증한다
-- (BlockServiceTests와 같은 방식). 파트 생성과 Touched 연결은 여기서 다루지 않는다:
-- 그쪽은 Instance가 필요해서 Studio Play 육안 확인 몫이다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local PadService = require(script.Parent.PadService)

local pure = PadService._pure

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local WORLD_ID = 1
local PAD_COUNT = ClickPadConfig.getSet(WORLD_ID).count

-- lifetimeBlox 픽스처.
--   POOR = 0     → 패드 1만 열린다 (패드1 조건이 0이므로)
--   RICH = 1000  → 패드 5까지 열린다 (조건: 패드5 = 36×3^3 = 972, 패드6 = 2916)
-- 절대값을 여기 박지 않고 아래에서 getUnlockedPadCount로 실제 경계를 함께 확인한다 —
-- Config를 튜닝하면 이 주석의 숫자는 틀려지지만 테스트는 그 사실을 스스로 잡아낸다.
local POOR = BigNum.new(0, 0)
local RICH = BigNum.new(1, 3)

-- 1. PadLayout.computeLayout ------------------------------------------------------------

-- 패드는 축 하나를 따라 일렬로 선다. "겹치지 않는다"는 두 좌표가 다르다는 뜻이 아니라
-- 패드 한 변 이상 떨어져 있다는 뜻이다 — 실제 파트 크기(PAD_SIZE) 기준으로 잰다.
local PAD_MAX_SPAN = math.max(PadLayout.PAD_SIZE.X, PadLayout.PAD_SIZE.Y, PadLayout.PAD_SIZE.Z)

local function allSeparatedByAtLeast(positions: { Vector3 }, minDistance: number): boolean
	for i = 1, #positions do
		for j = i + 1, #positions do
			if (positions[i] - positions[j]).Magnitude < minDistance then
				return false
			end
		end
	end
	return true
end

for _, count in ipairs({ 1, 2, PAD_COUNT }) do
	local positions = PadLayout.computeLayout(count)
	check(string.format("computeLayout(%d): 개수만큼 좌표가 나옴", count), #positions == count)
	check(
		string.format("computeLayout(%d): 패드끼리 겹치지 않음 (%.1f studs 이상 간격)", count, PAD_MAX_SPAN),
		allSeparatedByAtLeast(positions, PAD_MAX_SPAN)
	)
end

do
	-- 인덱스 순서 = 공간 순서. 이게 깨지면 "앞으로 갈수록 강해진다"가 성립하지 않는다.
	local positions = PadLayout.computeLayout(PAD_COUNT)
	local monotonic = true
	local prev = 0
	for i = 1, PAD_COUNT do
		local along = positions[i]:Dot(PadLayout.AXIS)
		if i > 1 and along <= prev then
			monotonic = false
		end
		prev = along
	end
	check("computeLayout: 인덱스가 커질수록 AXIS 방향으로 멀어짐 (순서 = 강함)", monotonic)
end

do
	-- AXIS가 단위 벡터가 아니면 PITCH를 곱한 간격이 통째로 틀어진다.
	check("PadLayout.AXIS는 단위 벡터", math.abs(PadLayout.AXIS.Magnitude - 1) < 1e-6)
end

do
	-- 패드 1이 블록 아레나 밖에서 시작하는가. START_GAP을 줄이면 여기서 걸린다.
	local arenaRadius = BlockLayoutConfig.BLOCK_SPAN * BlockLayoutConfig.OUTER_RING_MULT
		+ BlockLayoutConfig.BLOCK_SPAN / 2
	local first = PadLayout.computeLayout(1)[1]
	local horizontal = Vector3.new(first.X, 0, first.Z).Magnitude
	local nearestEdge = horizontal - PAD_MAX_SPAN / 2
	check(
		string.format("패드1이 블록 아레나 밖에 있음 (가장자리 %.1f >= 아레나 %.1f)", nearestEdge, arenaRadius),
		nearestEdge >= arenaRadius
	)
end

-- 2. 해금 경계 픽스처 확인 ---------------------------------------------------------------
-- 아래 디바운스/선택 테스트가 이 경계를 전제로 하므로 먼저 못박는다.

check("lifetimeBlox 0이면 패드 1만 해금", ClickPadConfig.getUnlockedPadCount(WORLD_ID, POOR) == 1)

local richUnlocked = ClickPadConfig.getUnlockedPadCount(WORLD_ID, RICH)
check(
	string.format("lifetimeBlox 1000이면 패드 2개 이상 해금 (실제 %d개)", richUnlocked),
	richUnlocked >= 3 and richUnlocked < PAD_COUNT,
	string.format("해금=%d, 전체=%d", richUnlocked, PAD_COUNT)
)

-- 3. 디바운스: 같은 패드 연속 Touched는 1회만 처리 --------------------------------------
-- Touched는 캐릭터가 패드 위에 서 있기만 해도 팔다리 파트마다 반복 발화한다 (CLAUDE.md 3).

do
	local state = pure.newPadState(1)

	local s1, r1 = pure.applyTouch(state, WORLD_ID, 3, RICH, 100.0)
	check("디바운스: 첫 접촉은 처리됨", r1 == "ok" and s1.selectedIndex == 3, tostring(r1))

	local s2, r2 = pure.applyTouch(s1, WORLD_ID, 3, RICH, 100.0 + pure.TOUCH_DEBOUNCE_SEC / 2)
	check("디바운스: 같은 패드 재접촉은 무시됨", r2 == "debounced", tostring(r2))
	check("디바운스: 무시된 접촉은 상태를 바꾸지 않음", s2 == s1)

	local _, r3 = pure.applyTouch(s2, WORLD_ID, 3, RICH, 100.0 + pure.TOUCH_DEBOUNCE_SEC + 0.01)
	check("디바운스: 창이 지나면 다시 처리됨", r3 == "ok", tostring(r3))

	-- 다른 패드는 같은 프레임이라도 디바운스에 걸리지 않는다 (연타가 아니라 이동이다).
	local _, r4 = pure.applyTouch(s1, WORLD_ID, 2, RICH, 100.0)
	check("디바운스: 다른 패드는 즉시 처리됨", r4 == "ok", tostring(r4))
end

-- 4. 해금 미달 패드를 밟으면 선택이 바뀌지 않는다 ----------------------------------------
-- Touched는 신호일 뿐 권한이 아니다 — 서버가 lifetimeBlox로 판정한다.

do
	local state = pure.newPadState(1)
	local after, result = pure.applyTouch(state, WORLD_ID, PAD_COUNT, POOR, 200.0)

	check("잠긴 패드: 결과가 locked", result == "locked", tostring(result))
	check("잠긴 패드: 선택 인덱스가 그대로 1", after.selectedIndex == 1)

	-- 잠긴 패드도 디바운스 타임스탬프는 갱신되어야 한다. 안 그러면 잠긴 패드 위에 서 있는
	-- 동안 warn이 초당 수십 줄 쏟아진다.
	local _, second = pure.applyTouch(after, WORLD_ID, PAD_COUNT, POOR, 200.0 + pure.TOUCH_DEBOUNCE_SEC / 2)
	check("잠긴 패드: 재접촉은 디바운스에 걸림 (warn 폭주 방지)", second == "debounced", tostring(second))
end

-- 5. 선택은 세팅이지 누적이 아니다 (낮은 패드를 밟으면 내려간다) --------------------------

do
	local state = pure.newPadState(1)

	local up, upResult = pure.applyTouch(state, WORLD_ID, 3, RICH, 300.0)
	check("세팅: 높은 패드로 올라감", upResult == "ok" and up.selectedIndex == 3, tostring(upResult))

	local down, downResult = pure.applyTouch(up, WORLD_ID, 2, RICH, 301.0)
	check("세팅: 낮은 패드를 밟으면 내려감 (누적이 아님)", downResult == "ok" and down.selectedIndex == 2, tostring(downResult))

	local back, backResult = pure.applyTouch(down, WORLD_ID, 1, RICH, 302.0)
	check("세팅: 패드 1까지 내려갈 수 있음", backResult == "ok" and back.selectedIndex == 1, tostring(backResult))
end

-- 6. 로드 시 클램프 ----------------------------------------------------------------------
-- 저장된 인덱스를 지금의 Config + lifetimeBlox로 다시 잰다. Config 튜닝으로 조건이
-- 올라가면 이미 저장된 인덱스가 조건 미달이 될 수 있다.

check("클램프: lifetimeBlox 0인데 저장값 5면 1로 내려감", pure.clampSelectedIndex(WORLD_ID, 5, POOR) == 1)
check("클램프: 조건을 만족하면 저장값 그대로", pure.clampSelectedIndex(WORLD_ID, richUnlocked, RICH) == richUnlocked)
check(
	"클램프: 해금 개수를 넘는 저장값은 해금 최고치로 내려감",
	pure.clampSelectedIndex(WORLD_ID, richUnlocked + 1, RICH) == richUnlocked
)
check("클램프: count를 넘는 저장값도 접힘", pure.clampSelectedIndex(WORLD_ID, PAD_COUNT + 999, RICH) == richUnlocked)
check("클램프: nil은 1", pure.clampSelectedIndex(WORLD_ID, nil, RICH) == 1)
check("클램프: 0 이하는 1", pure.clampSelectedIndex(WORLD_ID, 0, RICH) == 1)
check("클램프: 정수가 아니면 1", pure.clampSelectedIndex(WORLD_ID, 2.5, RICH) == 1)

-- 7. getClickPower: 선택 상태가 없으면 패드 1 값 -------------------------------------------
-- 실제 Player 없이 호출한다 — 상태 테이블에 없는 키이므로 "미선택" 경로를 그대로 탄다.

do
	local fakePlayer = {} :: any
	local power = PadService.getClickPower(fakePlayer)
	check(
		"getClickPower: 미선택이면 패드 1 파워",
		BigNum.eq(power, ClickPadConfig.getPadPower(WORLD_ID, 1)),
		BigNum.tostring(power)
	)
	check("getSelectedIndex: 미선택이면 1", PadService.getSelectedIndex(fakePlayer) == 1)
end

print(string.format("[PadServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PadServiceTests] %d test(s) failed", failed))
end

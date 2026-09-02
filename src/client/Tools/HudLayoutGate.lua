--!strict
-- 뷰포트 확정 게이트. HudLayoutReport(관측 리포트)와 HudLayoutTests(레이아웃
-- 테스트)가 공유한다 — 복사해서 두 벌로 두면 한쪽만 고쳤을 때 조용히 어긋난다
-- (U3-3 지시: "복사해서 두 벌로 만들지 말 것").
--
-- 뷰포트가 확정되기 전에는 AbsolutePosition/AbsoluteSize를 재도 의미가 없다.
-- ViewportSize의 미확정 초기값은 (1,1)이고, 그 사이 로블록스가 물리는 중간값도
-- 있다(U3-2 2차 관측에서 실측한 800x600 유령값) — 그래서 "0보다 크다"가 아니라
-- "1보다 크다"로 게이트를 잡고, HudGui.AbsoluteSize가 "기대 크기"와 실제로
-- 같아질 때까지 기다린다.
--
-- ⚠️ U3-4B 후속: "기대 크기"는 더 이상 ViewportSize 그 자체가 아니다.
-- IgnoreGuiInset=true면 HudGui가 뷰포트 전체를 덮어야 정상(기대 크기=ViewportSize)
-- 이지만, U3-4B에서 IgnoreGuiInset=false로 바꾼 뒤로는 GetGuiInset()만큼 줄어든
-- 크기가 정상이다(실측: ViewportSize=(1914,830) 때 HudGui=(1914,772), 인셋 58만큼
-- 정확히 줄어듦). 이전 버전은 "== ViewportSize"로 고정돼 있어서 IgnoreGuiInset=false
-- 전환 직후 이 조건이 영원히 거짓이 되어 게이트가 600프레임을 다 돌고
-- size_mismatch로 실패했다 — HudLayoutTests가 검사 1/2/3을 아예 못 돌았다.
-- hudGui.IgnoreGuiInset을 매번 직접 읽어 기대 크기를 계산하므로, 나중에 다시
-- true로 되돌려도(혹은 레이어별로 값이 갈려도) 이 식이 그대로 맞는다.
--
-- ⚠️ 폭(X) 비교는 반드시 남긴다. 유령 캡처(예: 800x600)를 걸러내는 것이 이
-- 조건의 존재 이유다 — U3-2 1차 관측이 정확히 여기 속아 관측 전체가
-- 버려졌었다. 인셋은 보통 세로(topbar)만 깎으므로 기대 크기의 X는 사실상
-- ViewportSize.X와 같지만, 식을 GetGuiInset()에서 그대로 유도해 X도 함께
-- 검증되게 한다 — "Y만 보면 통과"로 느슨해지지 않는다.
--
-- ⚠️ 이 모듈은 판정 방식을 정하지 않는다. 게이트를 못 벗어났을 때 "그래도 진행"할지
-- "명시적으로 fail"시킬지는 호출자 몫이다 — 리포트는 관측이 목적이라 진행하고,
-- 테스트는 "측정할 수 없었다"를 green으로 처리하면 안 되므로 fail시킨다
-- (HudLayoutTests.client.lua 참고). 이 모듈은 상한(FRAME_CAP)과 실패 사유만 돌려준다.

local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local HudLayoutGate = {}

-- 게이트가 만족되기를 기다리는 프레임 상한. 60fps 기준 약 10초.
HudLayoutGate.FRAME_CAP = 600

export type FailureReason = "camera_nil" | "viewport_ghost" | "size_mismatch"

export type GateResult = {
	satisfied: boolean,
	frames: number,
	failureReason: FailureReason?,
	viewportSize: Vector2, -- camera가 nil이면 (0,0)
	hudGuiAbsoluteSize: Vector2,
	expectedHudGuiSize: Vector2, -- IgnoreGuiInset 값에 따라 달라지는 기대 크기 (camera가 nil이거나 유령이면 (0,0))
}

-- hudGui.IgnoreGuiInset을 직접 읽어 기대 크기를 계산한다 (위 파일 상단 설명 참고).
local function computeExpectedSize(hudGui: ScreenGui, viewportSize: Vector2): Vector2
	if hudGui.IgnoreGuiInset then
		return viewportSize
	end
	local topLeftInset, bottomRightInset = GuiService:GetGuiInset()
	return viewportSize - topLeftInset - bottomRightInset
end

export type UsableBounds = {
	left: number,
	top: number,
	right: number,
	bottom: number,
}

-- HudLayoutTests(검사 2)가 쓰는 "사용 가능 영역" 경계. AbsolutePosition은 GUI 인셋을
-- 포함하지 않는다 — IgnoreGuiInset=false인 ScreenGui의 좌표계는 이미 topbar 아래에서
-- 시작하므로(엔진이 원점을 인셋만큼 대신 내려준다) AbsPos.Y=0은 "화면 맨 위"가 아니라
-- "사용 가능 영역 맨 위"다. 거기서 GetGuiInset().topLeft.Y를 다시 빼면 인셋을 두 번
-- 빼는 것이 된다(U3-4B에서 실제로 이 버그를 밟았다 — BloxDisplay AbsPos.Y=0(정상)인데
-- 옛 기준선 58을 대면 "0 < 58"로 fail이 났다).
--
-- IgnoreGuiInset=true면 좌표계 원점이 진짜 화면 맨 위(0,0)라 인셋만큼 안쪽이 기준선이고,
-- IgnoreGuiInset=false면 엔진이 이미 원점을 옮겨줬으므로 0이 기준선이다. computeExpectedSize
-- 와 같은 판단(IgnoreGuiInset 분기)을 쓰지만 반환 형태가 달라(크기 대 경계) 별도 함수로 둔다 —
-- 판단 자체는 이 모듈 한 곳에만 있고 HudLayoutReport/HudLayoutTests는 이 함수를 가져다 쓴다.
--
-- ⚠️ bottomRight 인셋은 지금 (0,0)이지만 식에서 빠뜨리지 않는다 — 나중에 값이 생겨도
-- (예: 노치가 있는 기기의 하단 제스처 바) 이 함수만 맞으면 호출부는 안 고쳐도 된다.
function HudLayoutGate.computeUsableBounds(hudGui: ScreenGui, viewportSize: Vector2): UsableBounds
	local topLeftInset, bottomRightInset = GuiService:GetGuiInset()

	if hudGui.IgnoreGuiInset then
		return {
			left = topLeftInset.X,
			top = topLeftInset.Y,
			right = viewportSize.X - bottomRightInset.X,
			bottom = viewportSize.Y - bottomRightInset.Y,
		}
	end

	return {
		left = 0,
		top = 0,
		right = viewportSize.X - topLeftInset.X - bottomRightInset.X,
		bottom = viewportSize.Y - topLeftInset.Y - bottomRightInset.Y,
	}
end

-- hudGui의 AbsoluteSize가 기대 크기와 실제로 일치할 때까지 기다린다. 매 프레임
-- Workspace.CurrentCamera를 다시 조회한다 - 클라 부트 시점엔 nil일 수 있고,
-- 나중에 생기거나 교체될 수 있어 최초 1회 캡처로는 부족하다.
function HudLayoutGate.wait(hudGui: ScreenGui): GateResult
	local frames = 0

	local function satisfied(): boolean
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return false
		end
		local vp = camera.ViewportSize
		if vp.X <= 1 or vp.Y <= 1 then
			return false
		end
		return hudGui.AbsoluteSize == computeExpectedSize(hudGui, vp)
	end

	while not satisfied() and frames < HudLayoutGate.FRAME_CAP do
		RunService.Heartbeat:Wait()
		frames += 1
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return {
			satisfied = false,
			frames = frames,
			failureReason = "camera_nil",
			viewportSize = Vector2.new(0, 0),
			hudGuiAbsoluteSize = hudGui.AbsoluteSize,
			expectedHudGuiSize = Vector2.new(0, 0),
		}
	end

	local vp = camera.ViewportSize
	if vp.X <= 1 or vp.Y <= 1 then
		return {
			satisfied = false,
			frames = frames,
			failureReason = "viewport_ghost",
			viewportSize = vp,
			hudGuiAbsoluteSize = hudGui.AbsoluteSize,
			expectedHudGuiSize = Vector2.new(0, 0),
		}
	end

	local expected = computeExpectedSize(hudGui, vp)
	if hudGui.AbsoluteSize ~= expected then
		return {
			satisfied = false,
			frames = frames,
			failureReason = "size_mismatch",
			viewportSize = vp,
			hudGuiAbsoluteSize = hudGui.AbsoluteSize,
			expectedHudGuiSize = expected,
		}
	end

	return {
		satisfied = true,
		frames = frames,
		failureReason = nil,
		viewportSize = vp,
		hudGuiAbsoluteSize = hudGui.AbsoluteSize,
		expectedHudGuiSize = expected,
	}
end

return HudLayoutGate

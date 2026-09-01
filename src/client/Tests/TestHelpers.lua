--!strict
-- UI 테스트 공용 비교 헬퍼.
--
-- Roblox의 UDim.Scale · UIAspectRatioConstraint.AspectRatio · AbsoluteSize 등은
-- float32로 저장된다. Lua number(double)로 값을 세팅해도 읽으면 이미 float32로
-- 반올림된 값이 돌아온다 — 예: Position.X.Scale=0.5, AnchorPoint.X=0.5, Size.X.Scale=0.2로
-- 계산한 x0(=0.5-0.5*0.2, 수학적으로는 정확히 0.4)를 실제로 읽으면 0.3999999985098839가
-- 나온다. 코드는 정상이고 ==(또는 지나치게 빡빡한 오차) 비교가 틀린 것이다.
--
-- U3-3에서 Play 실측(1180 passed / 19 failed) 19건 전부가 이 문제였다. 그중 9건
-- (PanelTests)은 실패 메시지에 실제값이 안 찍혀 있어서 "중첩 Scale 미보정"이라는
-- 잘못된 가설로 한 턴을 낭비했다 — 재계산해보니 두 패널 크기(0.60x0.70 vs 0.85x0.85)
-- 간 실제 오차는 1e-10~2e-8 수준으로, 보정이 빠졌을 때 나와야 할 1e-3~1e-2 수준과
-- 5~8자리 차이가 나 float32로 확정됐다. 그래서 checkClose는 실패 시 기대값·실제값·
-- 오차를 항상 함께 돌려준다 — 다음에 같은 조사를 반복하지 않기 위해서다.
--
-- ⚠️ 엔진 속성을 "읽어온" 값에만 쓴다. 순수 Lua 계산 결과(개수·불리언·문자열 등)는
-- ==를 그대로 쓸 것 — 전부 오차 비교로 바꾸면 진짜 버그를 가리게 된다.
-- ⚠️ BigNum 값 비교에는 쓰지 말 것. 그쪽은 별도의 정밀도 계약이 있다
-- (CLAUDE.md "정밀도 계약", src/shared/BigNum.lua 상단 — 여기 오차와 성격이 다르다).
--
-- ===== 상대오차를 쓰는 이유 =============================================================
--
-- float32의 정밀도는 절대값이 아니라 유효자리(가수 24bit) 기준이다 — 값이 크든 작든
-- 상대오차는 항상 2^-24(약 5.96e-8) 근처다. 이 프로젝트의 UI 값은 지금 0.01~1.0
-- 범위지만(Scale) 나중에 더 작은 값(예: 깊이 중첩된 컴포넌트의 root-상대 Scale)이
-- 들어올 수 있고, 그때 절대오차 상수 하나로는 안 맞는다 — 작은 값엔 너무 헐렁하고
-- 큰 값엔 너무 빡빡해진다. 상대오차는 값의 크기와 무관하게 같은 기준으로 통한다.
--
-- ===== 오차값(RELATIVE_TOLERANCE) 근거 ==================================================
--
-- 이번 재확인(U3-3)에서 실측한 상대오차 분포:
--   제목 높이     작은 창 2.77e-08 / 큰 창  3.18e-08
--   X 버튼 높이   작은 창 1.03e-08 / 큰 창  7.40e-08
--   위쪽 여백     작은 창 3.29e-09 / 큰 창  5.75e-08
--   오른쪽 여백   작은 창 8.74e-07 / 큰 창  3.16e-08   ← 최대
-- 최대 실측 상대오차는 8.74e-07(오른쪽 여백, 절대오차 1.81e-8 / 0.02)이다. float32
-- 연산 하나의 상대오차(5.96e-8)보다 한 자릿수 크지만, 이 값은 나눗셈 → 뺄셈(1-x) →
-- 곱셈을 거치며 float32 반올림이 여러 번 겹친 결과라 그 정도 배율은 정상 범위다.
-- 1e-6은 이 실측 최댓값(8.74e-07)보다 조금 더 여유를 두되(약 14%), 이 프로젝트가
-- 실제로 구분해야 하는 값 차이(예: HEIGHT_BIG 0.09 vs HEIGHT_SMALL 0.06, 상대차
-- 약 33%)보다는 5자리 이상 작아 진짜 버그를 가리지 않는다.
local RELATIVE_TOLERANCE = 1e-6

local TestHelpers = {}

-- actual이 expected와 상대오차 tol(기본 RELATIVE_TOLERANCE) 안에서 같은지 판정한다.
-- (boolean, detail) 를 돌려준다 — detail은 통과 여부와 무관하게 항상 만들어지므로
-- check(name, checkClose(actual, expected))처럼 그대로 이어 쓰면 실패 시 기대값·
-- 실제값·오차가 자동으로 찍힌다.
--
-- expected가 0이면 상대오차가 정의되지 않으므로(0으로 나누기) 그때만 절대오차로
-- 대체한다 — 지금 호출부 중 expected가 0인 경우는 없지만 방어적으로 둔다.
function TestHelpers.checkClose(actual: number, expected: number, tol: number?): (boolean, string)
	local tolerance = tol or RELATIVE_TOLERANCE
	local diff = actual - expected
	local relativeDiff = if expected ~= 0 then diff / expected else diff

	local ok = math.abs(relativeDiff) < tolerance
	local detail = string.format(
		"기대값=%.17g 실제값=%.17g 차이=%.3e (상대 %.3e)",
		expected,
		actual,
		diff,
		relativeDiff
	)

	return ok, detail
end

return TestHelpers

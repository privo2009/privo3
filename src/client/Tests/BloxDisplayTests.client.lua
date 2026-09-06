--!strict
-- BloxDisplay 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-2 착수 준비.
--
-- ⚠️ Store는 전역 싱글턴이라(StoreTests.client.lua와 공유) "blox" 키를 이 파일도
-- 건드린다. 끝나고 원래 더미값으로 복구하지만, 다른 테스트 파일과 값을 주고받는
-- task.wait() 구간에서 이론적으로 겹칠 수 있다 — 지금은 파일 수가 적어 실전에서
-- 문제가 된 적은 없다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local Layout = require(script.Parent.Parent.UI.Layout)
local Store = require(script.Parent.Parent.UI.Store)
local BloxDisplay = require(script.Parent.Parent.UI.Screens.Hud.BloxDisplay)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
local checkClose = TestHelpers.checkClose

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local handle = BloxDisplay.create()

-- ⚠️ **create() 바로 다음 줄이어야 한다. 사이에 yield를 넣지 말 것.**
--
-- create()가 root.Position.Y.Offset에 박는 값은 그 순간의 Layout.getTopInset()이다
-- (BloxDisplay.lua "X: 화면 폭 3% 여백... Y: 기본 UI 인셋만큼만 내린다" 줄).
-- 아래 4절이 그 Offset을 검사하는데, 예전에는 검사 시점에 getTopInset()을 **다시
-- 읽어서** 비교했다. 그 사이에 task.wait()이 든 절이 둘 있고, GetGuiInset()은
-- 뷰포트에 따라 값이 바뀐다 — Studio에서 Output 창을 여는 것만으로 뷰포트가
-- 830 → 593이 되고 인셋이 58 → 57로 갈린다. 프로덕션은 멀쩡한데 검사만 깨졌다
-- (2026-09-04 Play, fail 1건).
--
-- ⚠️ 허용 오차를 두는 것이 답이 아니다. 1px은 그날 나온 값일 뿐이고 로딩이 느리면
-- 더 벌어진다. 두 번 재는 것을 한 번으로 줄이는 것이 고칠 지점이다.
-- 여기서 잡으면 create()와 같은 프레임이라 create()가 본 값과 반드시 같고,
-- 검사는 정확 비교(==)를 그대로 유지한다.
local CREATED_TOP_INSET = Layout.getTopInset()

-- 1. 중앙 금지 구역을 침범하지 않는다 ------------------------------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	check(
		"BloxDisplay가 중앙 금지 구역을 침범하지 않는다",
		not Layout.overlapsCenterForbidden(x0, y0, x1, y1),
		string.format("x0=%.4f y0=%.4f x1=%.4f y1=%.4f", x0, y0, x1, y1)
	)
	check("BloxDisplay가 좌측 레일(20%) 안에 있다", x1 <= Layout.RAIL_WIDTH, tostring(x1))
end

-- 2. Store의 blox 변경이 표시에 반영된다 ----------------------------------------------

do
	local valueLabel = handle.root:FindFirstChild("Value") :: TextLabel
	check("Value 라벨이 있다", valueLabel ~= nil)

	local newBlox = BigNum.new(4.2, 10)
	Store.setSource(function(setter)
		setter("blox", newBlox)
	end)
	task.wait()

	check(
		"Store.blox 변경이 라벨 텍스트에 반영된다",
		valueLabel.Text == Formatter.format(newBlox),
		valueLabel.Text
	)
end

-- 3. 8자 값(999.99AB류)이 잘리지 않는다 (TextScaled + 자릿수 폭 보장) -------------------

do
	local valueLabel = handle.root:FindFirstChild("Value") :: TextLabel
	check("Value 라벨의 TextScaled가 켜져 있다", valueLabel.TextScaled == true)

	local aspect = valueLabel:FindFirstChildOfClass("UIAspectRatioConstraint")
	check("Value 라벨에 AspectRatioConstraint가 있다", aspect ~= nil)
	if aspect then
		-- AspectRatio는 Instance에서 읽은 float32 값이라 checkClose를 쓴다(TestHelpers.lua 참고).
		check(
			"8자 규격 AspectRatio == 8 * 0.55",
			checkClose((aspect :: UIAspectRatioConstraint).AspectRatio, 8 * 0.55)
		)
	end

	-- 8자 경계값: BigNum.new(9.99, 20) -> tier=6(Qi), displayM=999 -> "999.00Qi" (8자).
	local boundaryValue = BigNum.new(9.99, 20)
	Store.setSource(function(setter)
		setter("blox", boundaryValue)
	end)
	task.wait()

	local expected = Formatter.format(boundaryValue)
	check("8자 경계값이 그대로 들어간다(안 잘림)", valueLabel.Text == expected, valueLabel.Text)
	check("경계값 포맷 길이가 8자다(전제 확인)", #expected == 8, expected)
end

-- 4. Offset을 쓰지 않는다 (허용 예외: Position.Y.Offset의 기본 UI 인셋만) -----------------

do
	check("root Size.X.Offset == 0", handle.root.Size.X.Offset == 0)
	check("root Size.Y.Offset == 0", handle.root.Size.Y.Offset == 0)
	check("root Position.X.Offset == 0", handle.root.Position.X.Offset == 0)
	-- Y.Offset은 예외다 — Layout.getTopInset()(기본 UI 인셋 보정)만 들어간다.
	-- ⚠️ getTopInset()을 여기서 다시 부르지 말 것. create() 시점에 잡아둔 값과 비교한다
	--    (이유는 CREATED_TOP_INSET 선언부). 정확 비교는 그대로다.
	check(
		"root Position.Y.Offset == Layout.getTopInset() (허용된 픽셀 예외)",
		handle.root.Position.Y.Offset == CREATED_TOP_INSET,
		string.format("Offset=%d 캡처=%d 현재=%d", handle.root.Position.Y.Offset, CREATED_TOP_INSET, Layout.getTopInset())
	)
end

-- 원상 복구 (다른 테스트가 이 테스트의 잔여값을 보지 않게 한다).
Store.setSource(function(setter)
	setter("blox", BigNum.new(9.99, 23))
end)

print(string.format("[BloxDisplayTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BloxDisplayTests] %d test(s) failed", failed))
end

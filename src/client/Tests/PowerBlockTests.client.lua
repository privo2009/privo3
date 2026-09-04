--!strict
-- PowerBlock(힘 · 레벨 · 속도 블록) 검증. Studio에서 Rojo 연결 후 Play 하면 클라
-- 시작 시 자동 실행된다. U3-5 착수 준비.
--
-- ⚠️ 이 세션은 Studio Play를 돌릴 수 없다(RC 환경) — 이 파일은 작성만 하고
-- red->green 확인은 다음 세션으로 미룬다(docs/PENDING.md "미결" 참고).
--
-- 실제 Store 왕복(task.spawn 비동기) 없이도 진행률·레벨 경계를 검증할 수 있도록
-- handle._debug.applyPower/applySpeed를 직접 부른다(ChallengeInfoTests의
-- handle._debug.apply와 같은 패턴). Store 구독 자체가 반영되는지는 별도 절에서
-- Store.setSource + task.wait()로 확인한다(BloxDisplayTests와 같은 패턴).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local Layout = require(script.Parent.Parent.UI.Layout)
local Store = require(script.Parent.Parent.UI.Store)
local ValuePanel = require(script.Parent.Parent.UI.Components.ValuePanel)
local PowerBlock = require(script.Parent.Parent.UI.Screens.Hud.PowerBlock)
local TestHelpers = require(script.Parent.TestHelpers)
local checkClose = TestHelpers.checkClose

type BigNumber = BigNum.BigNumber

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

-- 원래 더미값 (Store.lua DUMMY_STATE와 동일 — 복원용).
local ORIGINAL_STRENGTH = BigNum.new(9.99, 20)
local ORIGINAL_WALK_SPEED = 5678
local ORIGINAL_MAX_WALK_SPEED = 9999

local handle = PowerBlock.create()

-- 1. 세 행의 부모 상대 Y 범위가 확정값과 일치한다 -------------------------------------
--
-- 표(U3-5 확정값)를 정확한 분수로 재현한다 — 파생 상수(14/33 == 7/16.5)를 다시
-- 옮겨적지 않고 분수 그대로 써서 반올림 오차를 피한다.

do
	local powerRow = handle.root:FindFirstChild("PowerValue") :: TextLabel
	local levelRow = handle.root:FindFirstChild("LevelRow") :: Frame
	local speedRow = handle.root:FindFirstChild("SpeedRow") :: Frame

	check("PowerValue 행이 있다", powerRow ~= nil)
	check("LevelRow가 있다", levelRow ~= nil)
	check("SpeedRow가 있다", speedRow ~= nil)

	if powerRow and levelRow and speedRow then
		local _, powerY0, _, powerY1 = Layout.getBounds(powerRow)
		local _, levelY0, _, levelY1 = Layout.getBounds(levelRow)
		local _, speedY0, _, speedY1 = Layout.getBounds(speedRow)

		local expectedPowerY0, expectedPowerY1 = 0, 7 / 16.5
		local expectedLevelY0, expectedLevelY1 = 8.5 / 16.5, 11.5 / 16.5
		local expectedSpeedY0, expectedSpeedY1 = 13 / 16.5, 1

		check("힘 수치 행 Y0 == 0", checkClose(powerY0, expectedPowerY0))
		check("힘 수치 행 Y1 == 7/16.5(0.424242)", checkClose(powerY1, expectedPowerY1))
		check("레벨 바 행 Y0 == 8.5/16.5(0.515152)", checkClose(levelY0, expectedLevelY0))
		check("레벨 바 행 Y1 == 11.5/16.5(0.696970)", checkClose(levelY1, expectedLevelY1))
		check("이동 속도 행 Y0 == 13/16.5(0.787879)", checkClose(speedY0, expectedSpeedY0))
		check("이동 속도 행 Y1 == 1", checkClose(speedY1, expectedSpeedY1))
	end
end

-- 2. 블록 전체가 하단 띠(Y 0.75~1.00) 안, 하단 여백 침범 없음 -------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)

	check(
		"블록 상단이 하단 띠(75%) 안쪽이다",
		y0 >= (1 - Layout.BOTTOM_HEIGHT),
		string.format("y0=%.6f 하단띠상단=%.6f", y0, 1 - Layout.BOTTOM_HEIGHT)
	)
	check(
		"블록 하단이 하단 여백을 침범하지 않는다(정확히 그 경계까지 채운다)",
		checkClose(y1, PowerBlock.BlockBottomY)
	)
	check("x0/x1 전제 확인(폭 40%, 중앙)", checkClose(x1 - x0, 0.40), string.format("x0=%.4f x1=%.4f", x0, x1))
end

-- 3. 블록이 중앙 금지 구역을 침범하지 않는다 -------------------------------------------

do
	local x0, y0, x1, y1 = Layout.getBounds(handle.root)
	check(
		"PowerBlock이 중앙 금지 구역을 침범하지 않는다",
		not Layout.overlapsCenterForbidden(x0, y0, x1, y1),
		string.format("x0=%.4f y0=%.4f x1=%.4f y1=%.4f", x0, y0, x1, y1)
	)
end

-- 4. 힘 8자 / 속도 4자 규격이 ValuePanel을 통해 걸려 있다 ------------------------------

do
	local powerLabel = handle.root:FindFirstChild("PowerValue") :: TextLabel
	local speedRow = handle.root:FindFirstChild("SpeedRow") :: Frame
	local speedLabel = if speedRow then speedRow:FindFirstChild("SpeedValue") :: TextLabel else nil

	check("PowerValue 라벨이 있다", powerLabel ~= nil)
	check("SpeedValue 라벨이 있다", speedLabel ~= nil)

	if powerLabel then
		local aspect = powerLabel:FindFirstChildOfClass("UIAspectRatioConstraint")
		check("PowerValue에 AspectRatioConstraint가 있다", aspect ~= nil)
		if aspect then
			check(
				"힘 8자 규격 AspectRatio == 8 * 0.55",
				checkClose((aspect :: UIAspectRatioConstraint).AspectRatio, ValuePanel.MAX_CHARS_DEFAULT * 0.55)
			)
		end
	end

	if speedLabel then
		local aspect = speedLabel:FindFirstChildOfClass("UIAspectRatioConstraint")
		check("SpeedValue에 AspectRatioConstraint가 있다", aspect ~= nil)
		if aspect then
			check(
				"속도 4자 규격 AspectRatio == 4 * 0.55",
				checkClose((aspect :: UIAspectRatioConstraint).AspectRatio, ValuePanel.MAX_CHARS_SPEED * 0.55)
			)
			check(
				"속도 규격이 재화 8자 규격과 다르다(같은 칸으로 묶이지 않는다)",
				(aspect :: UIAspectRatioConstraint).AspectRatio ~= ValuePanel.MAX_CHARS_DEFAULT * 0.55
			)
		end
	end
end

-- 5. 진행률 경계값 --------------------------------------------------------------------

do
	local levelRow = handle.root:FindFirstChild("LevelRow") :: Frame
	local currentLabel = levelRow:FindFirstChild("CurrentLabel") :: TextLabel
	local nextLabel = levelRow:FindFirstChild("NextLabel") :: TextLabel
	local barBg = levelRow:FindFirstChild("BarBackground") :: Frame
	local fill = barBg:FindFirstChild("Fill") :: Frame

	check("CurrentLabel/NextLabel/BarBackground/Fill이 모두 있다", currentLabel ~= nil and nextLabel ~= nil and barBg ~= nil and fill ~= nil)

	if currentLabel and nextLabel and fill then
		-- 힘이 0이면 레벨 0, 진행률 0 (BigNum 불변식상 m=0일 때 e도 0).
		handle._debug.applyPower(BigNum.new(0))
		check("힘 0 -> 레벨 0", currentLabel.Text == "0", currentLabel.Text)
		check("힘 0 -> 다음 레벨 1", nextLabel.Text == "1", nextLabel.Text)
		check("힘 0 -> 진행률 0", checkClose(fill.Size.X.Scale, 0))

		-- 가수가 정확히 1이면 진행률 0. 레벨은 지수와 일치해야 한다(임의로 5로 골랐다).
		handle._debug.applyPower(BigNum.new(1, 5))
		check("가수 1 -> 레벨이 힘의 지수(5)와 일치", currentLabel.Text == "5", currentLabel.Text)
		check("가수 1 -> 다음 레벨 6", nextLabel.Text == "6", nextLabel.Text)
		check("가수 1 -> 진행률 0", checkClose(fill.Size.X.Scale, 0))

		-- 가수가 10 근처면 진행률이 1 미만이다.
		handle._debug.applyPower(BigNum.new(9.99, 12))
		check("가수 9.99 -> 레벨이 힘의 지수(12)와 일치", currentLabel.Text == "12", currentLabel.Text)
		check(
			"가수 9.99 -> 진행률이 1 미만이다",
			fill.Size.X.Scale < 1,
			string.format("progress=%.6f", fill.Size.X.Scale)
		)
		check(
			"가수 9.99 -> 진행률이 log10(9.99)에 가깝다",
			checkClose(fill.Size.X.Scale, math.log(9.99, 10))
		)

		-- 클램프: 정규화를 거치지 않은(비정상) BigNum이 들어와도 [0,1] 밖으로 나가지 않는다.
		handle._debug.applyPower({ m = 15, e = 3 } :: BigNumber)
		check(
			"가수가 10을 넘는 비정상 입력도 진행률이 1로 클램프된다",
			checkClose(fill.Size.X.Scale, 1),
			string.format("progress=%.6f", fill.Size.X.Scale)
		)
	end
end

-- 6. Store 구독이 반영된다 -------------------------------------------------------------
--
-- ⚠️ 이 절은 싱글톤을 쓴다. 바꿀 수 없어서가 아니라 그것이 검사 대상이기 때문이다 —
-- PowerBlock.create()가 싱글톤을 직접 구독하므로(PowerBlock.lua "표시 갱신" 절),
-- 여기서 자기 인스턴스를 쓰면 실물 HUD 경로를 하나도 안 재고 통과하게 된다.
-- create()에 store를 주입하도록 고치는 길도 있으나 그러면 통과한 화면 6종이 전부
-- 미검증으로 돌아간다(U3-9 범위 밖).
--
-- 이 절이 U3-9에서 "- 1000"으로 깨졌던 것은 여기 잘못이 아니라 StoreTests가
-- 같은 싱글톤에 walkSpeed=1000을 걸었기 때문이다. 그쪽이 자기 인스턴스로 옮겼으므로
-- 이제 싱글톤의 walkSpeed/strength/maxWalkSpeed를 쓰는 것은 이 파일뿐이다
-- (BloxDisplayTests는 blox만 건드린다 — 키가 겹치지 않는다).

do
	local powerLabel = handle.root:FindFirstChild("PowerValue") :: TextLabel
	local speedRow = handle.root:FindFirstChild("SpeedRow") :: Frame
	local speedLabel = if speedRow then speedRow:FindFirstChild("SpeedValue") :: TextLabel else nil
	local maxLabel = if speedRow then speedRow:FindFirstChild("MaxLabel") :: TextLabel else nil

	if powerLabel and speedLabel and maxLabel then
		local newStrength = BigNum.new(4.2, 9)
		Store.setSource(function(setter)
			setter("strength", newStrength)
		end)
		task.wait()

		check(
			"Store.strength 변경이 PowerValue 텍스트에 반영된다",
			powerLabel.Text == Formatter.format(newStrength),
			powerLabel.Text
		)

		Store.setSource(function(setter)
			setter("walkSpeed", 33)
			setter("maxWalkSpeed", 77)
		end)
		task.wait()

		check("Store.walkSpeed 변경이 SpeedValue 텍스트에 반영된다", speedLabel.Text == "33", speedLabel.Text)
		check("Store.maxWalkSpeed 변경이 MaxLabel 텍스트에 반영된다", maxLabel.Text == "/ 최대 77", maxLabel.Text)

		-- 6b. 다른 Store 인스턴스는 실물 PowerBlock에 닿지 않는다 ----------------------
		--
		-- U3-9 사고의 재발 방지선이다. StoreTests가 자기 인스턴스에 걸던 값을 그대로
		-- 재현한다 — walkSpeed=1000은 실측 실패 메시지 "- 1000"의 그 값이다. 격리가
		-- 무너지면(예: 누가 Store.new()를 지우고 이름 접두어로 되돌리면) 라벨이
		-- 다시 "1000"이 되어 여기서 잡힌다.
		local privateStore = Store.new()
		privateStore.setSource(function(setter)
			setter("walkSpeed", 1000)
			setter("strength", BigNum.new(1, 2))
		end)
		task.wait()

		check(
			"다른 Store 인스턴스의 walkSpeed 변경이 SpeedValue로 새지 않는다",
			speedLabel.Text == "33",
			speedLabel.Text
		)
		check(
			"다른 Store 인스턴스의 strength 변경이 PowerValue로 새지 않는다",
			powerLabel.Text == Formatter.format(newStrength),
			powerLabel.Text
		)
		check(
			"다른 Store 인스턴스는 싱글톤 상태 자체도 바꾸지 않는다",
			checkClose(Store.get("walkSpeed"), 33)
		)
	else
		check("Store 구독 반영 검사 전제(라벨 존재)", false, "PowerValue/SpeedValue/MaxLabel 중 일부가 없다")
	end
end

-- 7. Offset을 쓰지 않는다 (허용 예외 없음 — PowerBlock은 상단 인셋과 무관하다) -------------

do
	check("root Size.X.Offset == 0", handle.root.Size.X.Offset == 0)
	check("root Size.Y.Offset == 0", handle.root.Size.Y.Offset == 0)
	check("root Position.X.Offset == 0", handle.root.Position.X.Offset == 0)
	check("root Position.Y.Offset == 0", handle.root.Position.Y.Offset == 0)

	local levelRow = handle.root:FindFirstChild("LevelRow") :: Frame
	local speedRow = handle.root:FindFirstChild("SpeedRow") :: Frame
	for _, frame in ipairs({ levelRow, speedRow }) do
		if frame then
			check(
				string.format("'%s' Size.X.Offset == 0", frame.Name),
				(frame :: Frame).Size.X.Offset == 0
			)
			check(
				string.format("'%s' Size.Y.Offset == 0", frame.Name),
				(frame :: Frame).Size.Y.Offset == 0
			)
			check(
				string.format("'%s' Position.X.Offset == 0", frame.Name),
				(frame :: Frame).Position.X.Offset == 0
			)
			check(
				string.format("'%s' Position.Y.Offset == 0", frame.Name),
				(frame :: Frame).Position.Y.Offset == 0
			)
		end
	end
end

-- 원상 복구 (다른 테스트·향후 HUD가 이 테스트의 잔여값을 보지 않게 한다).
Store.setSource(function(setter)
	setter("strength", ORIGINAL_STRENGTH)
	setter("walkSpeed", ORIGINAL_WALK_SPEED)
	setter("maxWalkSpeed", ORIGINAL_MAX_WALK_SPEED)
end)

print(string.format("[PowerBlockTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PowerBlockTests] %d test(s) failed", failed))
end

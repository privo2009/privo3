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
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local TestHelpers = require(ReplicatedStorage.Shared.TestHelpers)
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

-- 자기 Store 인스턴스로 만든다(BloxDisplayTests와 같은 이유 — 싱글톤은 서버 PlayerState가 채운다).
local testStore = Store.new()
local handle = PowerBlock.create(testStore)

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

		-- 2026-10-23 지시서 #8: 레벨 바 행 3.0 → 3.5%라 블록 16.5 → 17%.
		local expectedPowerY0, expectedPowerY1 = 0, 7 / 17
		local expectedLevelY0, expectedLevelY1 = 8.5 / 17, 12 / 17
		local expectedSpeedY0, expectedSpeedY1 = 13.5 / 17, 1

		check("힘 수치 행 Y0 == 0", checkClose(powerY0, expectedPowerY0))
		check("힘 수치 행 Y1 == 7/17", checkClose(powerY1, expectedPowerY1))
		check("레벨 바 행 Y0 == 8.5/17", checkClose(levelY0, expectedLevelY0))
		check("레벨 바 행 Y1 == 12/17", checkClose(levelY1, expectedLevelY1))
		check("이동 속도 행 Y0 == 13.5/17", checkClose(speedY0, expectedSpeedY0))
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

		-- L1(지시서 #13): 레벨 = floor(log₂(힘)). 힘이 정확히 2^20이면 레벨 20 · 진행률 0.
		-- 값은 LevelConfig에서 만든다 — 서버 최대 속도와 같은 모듈이다.
		handle._debug.applyPower(LevelConfig.powerOfLevel(20))
		check("힘 2^20 -> 레벨 20 (L1)", currentLabel.Text == "20", currentLabel.Text)
		check("힘 2^20 -> 다음 레벨 21", nextLabel.Text == "21", nextLabel.Text)
		check("힘 2^20 -> 진행률 0", checkClose(fill.Size.X.Scale, 0))

		-- 그 레벨 안에서의 위치 (힘 − 2^L) ÷ 2^L: 1.5 × 2^20이면 0.5
		handle._debug.applyPower(BigNum.mul(LevelConfig.powerOfLevel(20), BigNum.new(1.5, 0)))
		check("힘 1.5×2^20 -> 레벨 20 그대로", currentLabel.Text == "20", currentLabel.Text)
		check("힘 1.5×2^20 -> 진행률 0.5 (그 레벨 안의 위치)", checkClose(fill.Size.X.Scale, 0.5), string.format("progress=%.6f", fill.Size.X.Scale))
		check("진행률 = LevelConfig.getLevelProgress 그대로(클라가 다시 계산하지 않는다)",
			checkClose(fill.Size.X.Scale, LevelConfig.getLevelProgress(BigNum.mul(LevelConfig.powerOfLevel(20), BigNum.new(1.5, 0)))))

		-- 4M → 21 (DESIGN "레벨" 예시) · 진행률 1 미만
		handle._debug.applyPower(BigNum.new(4, 6))
		check("힘 4M -> 레벨 21 · 진행률 0 이상 1 미만", currentLabel.Text == "21" and fill.Size.X.Scale >= 0 and fill.Size.X.Scale < 1,
			string.format("%s / %.6f", currentLabel.Text, fill.Size.X.Scale))

		-- 클램프: 정규화를 거치지 않은(비정상) BigNum이 들어와도 [0,1] 밖으로 나가지 않는다.
		handle._debug.applyPower({ m = 15, e = 3 } :: BigNumber)
		check(
			"가수가 10을 넘는 비정상 입력도 진행률이 [0,1] 안",
			fill.Size.X.Scale >= 0 and fill.Size.X.Scale <= 1,
			string.format("progress=%.6f", fill.Size.X.Scale)
		)
	end
end

-- 6. Store 구독이 반영된다 -------------------------------------------------------------
--
-- ⚠️ 이 절은 예전에 싱글톤을 썼다(실물 HUD 경로를 재려고). Phase 6(지시서 #5)부터 싱글톤은 서버
-- PlayerState가 채우므로, 테스트 값을 거기 쓰면 실값을 덮는다. 그래서 create(store)로 자기
-- 인스턴스를 주입한다 — 구독 코드는 싱글톤일 때와 같은 줄이다(PowerBlock.lua "표시 갱신").
-- 실물 HUD가 서버 값을 그리는지는 Play 스크린샷으로 본다.

do
	local powerLabel = handle.root:FindFirstChild("PowerValue") :: TextLabel
	local speedRow = handle.root:FindFirstChild("SpeedRow") :: Frame
	local speedLabel = if speedRow then speedRow:FindFirstChild("SpeedValue") :: TextLabel else nil
	local maxLabel = if speedRow then speedRow:FindFirstChild("MaxLabel") :: TextLabel else nil

	if powerLabel and speedLabel and maxLabel then
		local newStrength = BigNum.new(4.2, 9)
		testStore.setSource(function(setter)
			setter("strength", newStrength)
		end)
		task.wait()

		check(
			"Store.strength 변경이 PowerValue 텍스트에 반영된다",
			powerLabel.Text == Formatter.format(newStrength),
			powerLabel.Text
		)

		testStore.setSource(function(setter)
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
			"다른 Store 인스턴스는 이 테스트 인스턴스의 상태도 바꾸지 않는다",
			checkClose(testStore.get("walkSpeed"), 33)
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


print(string.format("[PowerBlockTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PowerBlockTests] %d test(s) failed", failed))
end

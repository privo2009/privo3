--!strict
-- ScreenController 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-1 착수 준비.
--
-- ⚠️ ScreenController는 전역 싱글턴이다(설계 자체가 "지금 무엇이 열려 있나"를 단독
-- 소유). 이 테스트가 등록하는 이름은 전부 __Test_ 접두어를 붙여 앞으로 나올 진짜
-- 화면 이름과 절대 겹치지 않게 하고, 끝나면 closeAll()로 정리한다. register()된
-- 항목 자체는 프로세스가 끝날 때까지 남지만, 이름 충돌만 피하면 무해하다.

local ScreenController = require(script.Parent.Parent.UI.ScreenController)

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

local dbg = ScreenController._debug

-- 1. ScreenGui 3개, DisplayOrder 1/2/3, ResetOnSpawn false --------------------------

check("HudGui가 존재한다", dbg.guis.Hud ~= nil)
check("WindowGui가 존재한다", dbg.guis.Window ~= nil)
check("OverlayGui가 존재한다", dbg.guis.Overlay ~= nil)

if dbg.guis.Hud and dbg.guis.Window and dbg.guis.Overlay then
	check("Hud DisplayOrder == 1", dbg.guis.Hud.DisplayOrder == 1)
	check("Window DisplayOrder == 2", dbg.guis.Window.DisplayOrder == 2)
	check("Overlay DisplayOrder == 3", dbg.guis.Overlay.DisplayOrder == 3)

	check("Hud ResetOnSpawn == false", dbg.guis.Hud.ResetOnSpawn == false)
	check("Window ResetOnSpawn == false", dbg.guis.Window.ResetOnSpawn == false)
	check("Overlay ResetOnSpawn == false", dbg.guis.Overlay.ResetOnSpawn == false)
end

-- 2. register 시점에는 Instance가 없고 첫 open에서 생긴다 --------------------------

do
	local built = 0
	ScreenController.register("__Test_Lazy", "Window", function()
		built += 1
		return Instance.new("Frame")
	end)

	check("register 직후에는 instance가 nil이다", dbg.entries["__Test_Lazy"].instance == nil)
	check("register만으로는 builder가 안 불린다", built == 0)

	ScreenController.open("__Test_Lazy")
	check("첫 open 후 instance가 생긴다", dbg.entries["__Test_Lazy"].instance ~= nil)
	check("첫 open에서 builder가 정확히 1번 불린다", built == 1)

	ScreenController.close("__Test_Lazy")
	ScreenController.open("__Test_Lazy")
	check("재open해도 builder가 다시 불리지 않는다(재사용)", built == 1)

	ScreenController.close("__Test_Lazy")
end

-- 3. Window: 한 번에 하나만 열린다 -------------------------------------------------

do
	ScreenController.register("__Test_WindowA", "Window", function()
		return Instance.new("Frame")
	end)
	ScreenController.register("__Test_WindowB", "Window", function()
		return Instance.new("Frame")
	end)

	ScreenController.open("__Test_WindowA")
	check("WindowA를 열면 열려 있다", ScreenController.isOpen("__Test_WindowA"))

	ScreenController.open("__Test_WindowB")
	check("WindowB를 열면 WindowA는 자동으로 닫힌다", not ScreenController.isOpen("__Test_WindowA"))
	check("WindowB는 열려 있다", ScreenController.isOpen("__Test_WindowB"))

	ScreenController.close("__Test_WindowB")
end

-- 4. Overlay: 여러 개가 동시에 열린 채로 남는다 -----------------------------------

do
	ScreenController.register("__Test_OverlayA", "Overlay", function()
		return Instance.new("Frame")
	end)
	ScreenController.register("__Test_OverlayB", "Overlay", function()
		return Instance.new("Frame")
	end)

	ScreenController.open("__Test_OverlayA")
	ScreenController.open("__Test_OverlayB")

	check("Overlay A, B 둘 다 열린 채로 남는다 (A)", ScreenController.isOpen("__Test_OverlayA"))
	check("Overlay A, B 둘 다 열린 채로 남는다 (B)", ScreenController.isOpen("__Test_OverlayB"))

	ScreenController.close("__Test_OverlayA")
	ScreenController.close("__Test_OverlayB")
end

-- 5. 배경 흐리게: 창이 하나라도 열리면 보이고 전부 닫히면 숨는다 --------------------

do
	ScreenController.register("__Test_BlurWindow", "Window", function()
		return Instance.new("Frame")
	end)

	local blur = dbg.getBlur()
	check("blur Frame이 존재한다", blur ~= nil)

	if blur then
		ScreenController.open("__Test_BlurWindow")
		check("창을 열면 blur가 보인다", blur.Visible == true)

		ScreenController.close("__Test_BlurWindow")
		check("창을 닫으면 blur가 숨는다", blur.Visible == false)
	end
end

-- 6. 없는 이름은 error (오타와 정상 상태를 구분 — AssetRegistry.resolve와 같은 판단) --

do
	local ok = pcall(ScreenController.open, "__Test_Does_Not_Exist")
	check("등록되지 않은 이름으로 open하면 error", ok == false)
end

do
	local ok = pcall(ScreenController.close, "__Test_Does_Not_Exist")
	check("등록되지 않은 이름으로 close하면 error", ok == false)
end

do
	local ok = pcall(ScreenController.isOpen, "__Test_Does_Not_Exist")
	check("등록되지 않은 이름으로 isOpen하면 error", ok == false)
end

do
	ScreenController.register("__Test_DupCheck", "Hud", function()
		return Instance.new("Frame")
	end)
	local ok = pcall(ScreenController.register, "__Test_DupCheck", "Hud", function()
		return Instance.new("Frame")
	end)
	check("같은 이름으로 두 번 register하면 error", ok == false)
end

ScreenController.closeAll()

print(string.format("[ScreenControllerTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ScreenControllerTests] %d test(s) failed", failed))
end

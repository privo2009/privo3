--!strict
-- ScreenController 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-1 착수 준비. U3-4에서 자기 인스턴스로 옮김.
--
-- ⚠️ 예전엔 기본 인스턴스(실물 코드가 쓰는 그 하나)를 같이 쓰면서 이름에만
-- __Test_ 접두어를 붙여 충돌을 피했다. 그런데 이 파일 끝의 closeAll()은 이름을
-- 가리지 않고 "그 순간 열려 있는 것 전부"를 닫는다 — 그래서 HudBoot이 이미
-- 띄운 진짜 HUD 3종(BloxDisplay/ChallengeInfo/MenuRail)까지 같이 꺼진 사고가
-- 났다(→ docs/PENDING.md 해소 기록, U3-4). 이름 접두어는 register() 충돌만
-- 막았지 동작 범위는 못 막은 것이다. 그래서 이번엔 ScreenController.new()로
-- 완전히 별도인 인스턴스(자기만의 entries·ScreenGui 3장)를 만들어 쓴다 —
-- 상태 자체가 갈렸으므로 이름을 가릴 필요가 없다.

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

local sc = ScreenController.new("ScreenControllerTests_")
local dbg = sc._debug

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
	sc.register("Lazy", "Window", function()
		built += 1
		return Instance.new("Frame")
	end)

	check("register 직후에는 instance가 nil이다", dbg.entries["Lazy"].instance == nil)
	check("register만으로는 builder가 안 불린다", built == 0)

	sc.open("Lazy")
	check("첫 open 후 instance가 생긴다", dbg.entries["Lazy"].instance ~= nil)
	check("첫 open에서 builder가 정확히 1번 불린다", built == 1)

	sc.close("Lazy")
	sc.open("Lazy")
	check("재open해도 builder가 다시 불리지 않는다(재사용)", built == 1)

	sc.close("Lazy")
end

-- 3. Window: 한 번에 하나만 열린다 -------------------------------------------------

do
	sc.register("WindowA", "Window", function()
		return Instance.new("Frame")
	end)
	sc.register("WindowB", "Window", function()
		return Instance.new("Frame")
	end)

	sc.open("WindowA")
	check("WindowA를 열면 열려 있다", sc.isOpen("WindowA"))

	sc.open("WindowB")
	check("WindowB를 열면 WindowA는 자동으로 닫힌다", not sc.isOpen("WindowA"))
	check("WindowB는 열려 있다", sc.isOpen("WindowB"))

	sc.close("WindowB")
end

-- 4. Overlay: 여러 개가 동시에 열린 채로 남는다 -----------------------------------

do
	sc.register("OverlayA", "Overlay", function()
		return Instance.new("Frame")
	end)
	sc.register("OverlayB", "Overlay", function()
		return Instance.new("Frame")
	end)

	sc.open("OverlayA")
	sc.open("OverlayB")

	check("Overlay A, B 둘 다 열린 채로 남는다 (A)", sc.isOpen("OverlayA"))
	check("Overlay A, B 둘 다 열린 채로 남는다 (B)", sc.isOpen("OverlayB"))

	sc.close("OverlayA")
	sc.close("OverlayB")
end

-- 5. 배경 흐리게: 창이 하나라도 열리면 보이고 전부 닫히면 숨는다 --------------------

do
	sc.register("BlurWindow", "Window", function()
		return Instance.new("Frame")
	end)

	local blur = dbg.getBlur()
	check("blur Frame이 존재한다", blur ~= nil)

	if blur then
		sc.open("BlurWindow")
		check("창을 열면 blur가 보인다", blur.Visible == true)

		sc.close("BlurWindow")
		check("창을 닫으면 blur가 숨는다", blur.Visible == false)
	end
end

-- 6. 없는 이름은 error (오타와 정상 상태를 구분 — AssetRegistry.resolve와 같은 판단) --

do
	local ok = pcall(sc.open, "Does_Not_Exist")
	check("등록되지 않은 이름으로 open하면 error", ok == false)
end

do
	local ok = pcall(sc.close, "Does_Not_Exist")
	check("등록되지 않은 이름으로 close하면 error", ok == false)
end

do
	local ok = pcall(sc.isOpen, "Does_Not_Exist")
	check("등록되지 않은 이름으로 isOpen하면 error", ok == false)
end

do
	sc.register("DupCheck", "Hud", function()
		return Instance.new("Frame")
	end)
	local ok = pcall(sc.register, "DupCheck", "Hud", function()
		return Instance.new("Frame")
	end)
	check("같은 이름으로 두 번 register하면 error", ok == false)
end

-- 7. closeAll: 이 인스턴스에서 열린 것만 닫는다 (실물에는 닿지 않는다) -----------------
-- ⚠️ 이 검사가 이번 사고의 본체다. 예전엔 기본 인스턴스를 같이 써서 closeAll()이
-- 실물 HUD까지 닫았다. 지금은 sc가 완전히 별도 인스턴스라 sc.closeAll()이 아무리
-- 전부를 닫아도 sc 밖(기본 인스턴스, 곧 실물 화면)에는 영향이 없다 — 그 사실
-- 자체를 검사한다.

do
	sc.register("CloseAllCheck", "Hud", function()
		return Instance.new("Frame")
	end)
	sc.open("CloseAllCheck")
	check("closeAll 전에는 열려 있다", sc.isOpen("CloseAllCheck"))

	sc.closeAll()
	check("closeAll 후에는 이 인스턴스의 항목이 닫힌다", not sc.isOpen("CloseAllCheck"))

	-- 기본 인스턴스(ScreenController.isOpen)는 sc와 별개의 entries를 쓰므로,
	-- sc에 등록된 적 없는 이름을 물으면 당연히 error다 — sc.closeAll()이 그쪽
	-- entries에 아예 손을 못 댄다는 것의 방증이다.
	local ok = pcall(ScreenController.isOpen, "CloseAllCheck")
	check("sc에 등록한 이름은 기본 인스턴스에 존재하지 않는다(별개 entries)", ok == false)
end

-- 정리: 이 인스턴스의 ScreenGui 3장을 통째로 버린다. 기본 인스턴스는 건드리지 않는다.
sc.destroy()

print(string.format("[ScreenControllerTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ScreenControllerTests] %d test(s) failed", failed))
end

--!strict
-- HUD 실노출 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-4 신설 — "테스트 1199개가 전부 통과했는데 화면엔 HUD가 하나도 안 보인다"는
-- 사고(ScreenControllerTests의 closeAll()이 실물 HUD까지 같이 닫음 — 원인은
-- docs/PENDING.md 해소 기록·U3-4 참고)를 다시 잡기 위한 것이다. 다른 테스트는
-- 전부 분리된 Instance 트리에서 Size·Position·AspectRatio만 검사하므로
-- "PlayerGui에 실제로 붙어서 보이는가"는 지금까지 아무도 검사하지 않았다 —
-- 이 파일이 그 구멍을 메운다. ScreenController의 **기본 인스턴스**(실물 코드가
-- 쓰는 그 하나)만 본다.
--
-- ===== 실행 시점을 어떻게 보장하는가 (이 파일의 핵심) =================================
--
-- 이 테스트가 의미 있으려면 HudBoot.client.lua가 이미 실행을 마친 뒤에 돌아야
-- 한다. 문제는 형제 LocalScript 사이에 실행 순서 보장이 아예 없다는 것이다 —
-- 이번 사고의 원인이기도 하다. "N초 기다리면 되겠지" 식의 고정 시간 대기는
-- 그 실행 순서 미보장을 다른 형태로 반복하는 것이라 쓰지 않는다.
--
-- 대신 엔진이 실제로 보장하는 두 가지만 쓴다:
--   1. task.defer로 이 검사를 미룬다. task.defer는 "이번 프레임에서 동기적으로
--      실행 중이던 스크립트들이 전부 끝난 뒤"에 실행되도록 엔진이 보장하는
--      스케줄링 규칙이다(시간이 아니라 실행 큐 순서 기준) — 같은 프레임에서
--      yield 없이 도는 HudBoot보다 이 검사가 반드시 늦게 돈다.
--   2. 그 뒤 RunService.Heartbeat를 여러 프레임 이어서 기다리며, 그동안 계속
--      Visible이 유지되는지 본다. task.defer는 "이번 프레임 동기 코드 다음"만
--      보장하고, task.wait로 다음 프레임 이후까지 이어지는 다른 스크립트의
--      뒷정리 코드까지는 못 잡는다 — 그런 코드가 나중에 생겨서 뭔가를 되돌리면
--      이 관찰 창 안에서 상태가 뒤집히는 것으로 잡힌다. 정확한 프레임 수를
--      맞추는 게 목적이 아니라 "여러 프레임에 걸쳐 계속 참이었다"를 근거로 삼는
--      것이다.
--
-- ⚠️ 이것도 절대적인 보장은 아니다 — 관찰 창보다 한참 뒤에 상태를 뒤집는 코드가
-- 생기면 못 잡는다. 다만 지금 코드베이스에서 기본 인스턴스를 건드리는 곳은
-- HudBoot(연다) 하나뿐이다 — U3-4에서 ScreenControllerTests를 별도 인스턴스로
-- 옮겼으므로, 이 관찰 창 안에서 뒤집을 대상 자체가 없다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local SCREENS = { "BloxDisplay", "ChallengeInfo", "MenuRail" }
local STABILITY_FRAMES = 10 -- 프레임 수(시간이 아니다) — 근거는 파일 상단 참고

task.defer(function()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, name in ipairs(SCREENS) do
		local ok = pcall(ScreenController.isOpen, name)
		check(string.format("'%s'가 기본 인스턴스에 등록돼 있다(HudBoot 실행됨)", name), ok)
	end

	local roots: { [string]: GuiObject } = {}
	for _, name in ipairs(SCREENS) do
		local entry = ScreenController._debug.entries[name]
		if entry ~= nil and entry.instance ~= nil then
			roots[name] = entry.instance :: GuiObject
		end
	end

	-- AbsoluteSize·AbsolutePosition은 렌더 후에 채워진다. 최소 한 프레임은
	-- 지나야 한다 — "몇 초"가 아니라 "렌더 갱신이 최소 한 번 있었다"는 조건이다.
	RunService.Heartbeat:Wait()

	local stableVisible: { [string]: boolean } = {}
	for name in pairs(roots) do
		stableVisible[name] = true
	end

	for _ = 1, STABILITY_FRAMES do
		for name, root in pairs(roots) do
			if not (root.Visible and root:IsDescendantOf(playerGui)) then
				stableVisible[name] = false
			end
		end
		RunService.Heartbeat:Wait()
	end

	for _, name in ipairs(SCREENS) do
		local root = roots[name]
		if root ~= nil then
			check(string.format("'%s' root가 PlayerGui 아래 붙어 있다", name), root:IsDescendantOf(playerGui))
			check(string.format("'%s' root.Visible == true", name), root.Visible == true)
			check(
				string.format("'%s' AbsoluteSize가 0이 아니다", name),
				root.AbsoluteSize.X > 0 and root.AbsoluteSize.Y > 0,
				tostring(root.AbsoluteSize)
			)
			check(
				string.format("'%s'가 %d프레임 동안 계속 보였다(뒤늦게 닫히지 않는다)", name, STABILITY_FRAMES),
				stableVisible[name] == true
			)
		end
	end

	local hud = ScreenController._debug.guis.Hud
	check("HudGui.Enabled == true", hud.Enabled == true)

	print(string.format("[HudVisibilityTests] %d passed, %d failed", passed, failed))
	if failed > 0 then
		error(string.format("[HudVisibilityTests] %d test(s) failed", failed))
	end
end)

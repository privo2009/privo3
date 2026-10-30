--!strict
-- 클라 언어 처리 검증 (지시서 #L2 K10 · K11).
--   K10  우리 코드가 만드는 GUI 루트(ScreenGui · BillboardGui · SurfaceGui)는 전부 AutoLocalize = false
--        — 번역은 Strings(Locale.t)가 한다. 로블록스 자동 번역이 그 위에 한 번 더 덮이지 않게 한다.
--        PlayerGui · Workspace 아래 LayerCollector를 전부 훑는다. 예외는 우리 코드 밖 두 가지뿐:
--        Studio 카메라 도구 Freecam(로블록스가 넣는다) · 플레이스 파일 StarterGui에 있는 것의 복사본(코드가 만든 것이 아니다)
--   K11  Studio에서 클라는 서버 언어 신호(LocaleReady)를 받은 뒤에 첫 언어를 고른다 — TEST_LOCALE이 계정 언어와 달라도
--        첫 화면부터 그 언어다. 고른 언어 = TEST_LOCALE(켰으면) 또는 계정 언어
-- 이 파일은 읽기만 한다(인스턴스 · 프로필을 바꾸지 않는다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- K10 ----------------------------------------------------------------------------------------------
do
	-- 화면이 다 세워질 때까지 기다린다(HUD 3층 · 3D 안내 라벨). 상한 15초.
	local deadline = os.clock() + 15
	while os.clock() < deadline do
		if playerGui:FindFirstChild("HudGui") ~= nil and playerGui:FindFirstChild("PadLabel_01") ~= nil then
			break
		end
		task.wait(0.2)
	end
	task.wait(0.5)

	local ours, outside, bad = 0, {}, {}
	local function scan(root: Instance)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("LayerCollector") then
				if d.Name == "Freecam" or StarterGui:FindFirstChild(d.Name) ~= nil then
					table.insert(outside, d.Name)
				else
					ours += 1
					if (d :: any).AutoLocalize ~= false then
						table.insert(bad, d:GetFullName())
					end
				end
			end
		end
	end
	scan(playerGui)
	scan(Workspace)
	check(string.format("K10: 우리 GUI 루트 %d개 전부 AutoLocalize = false", ours), ours > 0 and #bad == 0, table.concat(bad, ", "))
	check("K10: 화면 3층(HudGui · WindowGui · OverlayGui)이 검사 대상에 들어 있다",
		playerGui:FindFirstChild("HudGui") ~= nil and playerGui:FindFirstChild("WindowGui") ~= nil and playerGui:FindFirstChild("OverlayGui") ~= nil)
	print(string.format("[LocaleClientTests] K10 우리 코드 밖 GUI 루트(검사 제외): %s", if #outside > 0 then table.concat(outside, ", ") else "없음"))
end

-- K11 ----------------------------------------------------------------------------------------------
do
	local test = ReplicatedStorage:GetAttribute(Locale.TEST_LOCALE_ATTRIBUTE)
	local expected = if test ~= nil and Locale.isSupported(test) then test else Locale.fromLocaleId(player.LocaleId)
	check("K11: 지금 언어 = TEST_LOCALE(켰으면) 또는 계정 언어", Locale.current() == expected,
		string.format("current=%s expected=%s test=%s localeId=%s", Locale.current(), tostring(expected), tostring(test), player.LocaleId))
	local first, early = Locale._firstPick()
	if RunService:IsStudio() then
		check("K11: 처음 기억한 언어는 서버 신호를 받은 뒤에 골랐다(Studio)", first ~= nil and first.ready == true and first.code == expected,
			if first ~= nil then string.format("code=%s ready=%s", first.code, tostring(first.ready)) else "nil")
		check("K11: 신호 전에 기억 없이 고른 호출 0(기다릴 수 없는 자리에서 먼저 불린 적 없음)", early == 0, tostring(early))
	end
	print(string.format("[LocaleClientTests] K11 언어=%s (TEST_LOCALE=%s · 계정 %s)", Locale.current(), tostring(test), player.LocaleId))
end

print(string.format("[LocaleClientTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LocaleClientTests] %d test(s) failed", failed))
end

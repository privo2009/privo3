--!strict
-- HUD 3종(블럭스 · 챌린지 정보 · 메뉴 진입)을 ScreenController에 등록하고
-- HudGui 층에 띄우는 진입점. ClickInput.client.lua / SpeedInputBoot.client.lua와
-- 같은 자리 — 화면 모듈은 ModuleScript라 누군가 require해서 살려야 한다.
--
-- HUD는 "항상 떠 있음"(docs/UI.md "1. 화면 목록")이라 register 직후 바로 open한다.
-- 다른 화면처럼 유저 조작으로 열고 닫는 대상이 아니다.
--
-- ⚠️ Store는 여전히 더미 소스다(U3-1 Store.lua 상단 참고). 이번 작업도 실데이터를
-- 붙이지 않는다 — setSource로 Remote 연결부를 붙이는 것은 이후 단계다.

local ScreenController = require(script.Parent.ScreenController)
local Layout = require(script.Parent.Layout)
local BloxDisplay = require(script.Parent.Screens.Hud.BloxDisplay)
local ChallengeInfo = require(script.Parent.Screens.Hud.ChallengeInfo)
local MenuRail = require(script.Parent.Screens.Hud.MenuRail)

-- MenuRail은 BloxDisplay 바로 아래부터 시작한다(docs/UI.md 메뉴 진입 절 — 같은
-- 좌측 레일을 위아래로 나눠 쓴다). 시작 위치를 새로 계산해 박지 않고 BloxDisplay가
-- 실제로 차지한 영역(Layout.getBounds)에서 그대로 읽는다 — BloxDisplay의 크기가
-- 나중에 바뀌어도 이 계산이 따라간다.
local MENU_RAIL_TOP_GAP = 0.02 -- BloxDisplay와 메뉴 사이 여백. Panel.lua 여백(2%)과 같은 급의 시각 튜닝값

local bloxDisplay = BloxDisplay.create()
local _, _, _, bloxDisplayBottom = Layout.getBounds(bloxDisplay.root)

local challengeInfo = ChallengeInfo.create()
local menuRail = MenuRail.create(bloxDisplayBottom + MENU_RAIL_TOP_GAP)

-- 셋 다 register 이전에 이미 만들어져 있다. ScreenController의 지연 생성은 나중에
-- 열릴 수도 있는 창·오버레이의 로딩 비용을 아끼려는 것이고, HUD는 register 직후
-- 바로 open하므로 그 이점이 없다 — builder는 단지 이미 있는 root를 돌려준다.
ScreenController.register("BloxDisplay", "Hud", function()
	return bloxDisplay.root
end)
ScreenController.register("ChallengeInfo", "Hud", function()
	return challengeInfo.root
end)
ScreenController.register("MenuRail", "Hud", function()
	return menuRail.root
end)

ScreenController.open("BloxDisplay")
ScreenController.open("ChallengeInfo")
ScreenController.open("MenuRail")

print("[HudBoot] HUD 3종(BloxDisplay/ChallengeInfo/MenuRail) 등록·표시 완료")

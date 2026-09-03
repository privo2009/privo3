--!strict
-- HUD 6종(블럭스 · 챌린지 정보 · 메뉴 진입 · 힘/레벨/속도 블록 · 로벅스 구좌 4개 ·
-- 자동 클리커 토글/자동 진행 버튼)을 ScreenController에 등록하고 HudGui 층에
-- 띄우는 진입점. ClickInput.client.lua / SpeedInputBoot.client.lua와 같은 자리 —
-- 화면 모듈은 ModuleScript라 누군가 require해서 살려야 한다.
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
local PowerBlock = require(script.Parent.Screens.Hud.PowerBlock)
local ShopSlots = require(script.Parent.Screens.Hud.ShopSlots)
local AutoTools = require(script.Parent.Screens.Hud.AutoTools)

-- MenuRail은 BloxDisplay 바로 아래부터 시작한다(docs/UI.md 메뉴 진입 절 — 같은
-- 좌측 레일을 위아래로 나눠 쓴다). 시작 위치를 새로 계산해 박지 않고 BloxDisplay가
-- 실제로 차지한 영역(Layout.getBounds)에서 그대로 읽는다 — BloxDisplay의 크기가
-- 나중에 바뀌어도 이 계산이 따라간다.
local MENU_RAIL_TOP_GAP = 0.02 -- BloxDisplay와 메뉴 사이 여백. Panel.lua 여백(2%)과 같은 급의 시각 튜닝값

local bloxDisplay = BloxDisplay.create()
local _, _, _, bloxDisplayBottom = Layout.getBounds(bloxDisplay.root)

local challengeInfo = ChallengeInfo.create()
local menuRail = MenuRail.create(bloxDisplayBottom + MENU_RAIL_TOP_GAP)
-- PowerBlock은 하단 중앙에 스스로 자리를 잡는다(바닥을 하단 여백 위에 고정하고 위로
-- 연다) — BloxDisplay/MenuRail처럼 다른 HUD 요소의 경계에서 위치를 유도할 필요가
-- 없다(PowerBlock.lua 상단 참고).
local powerBlock = PowerBlock.create()
-- ShopSlots/AutoTools도 우측 레일에 스스로 자리를 잡는다(각 파일 상단 참고) —
-- 서로의 경계에서 위치를 유도하지 않는다.
local shopSlots = ShopSlots.create()
local autoTools = AutoTools.create()

-- 여섯 다 register 이전에 이미 만들어져 있다. ScreenController의 지연 생성은 나중에
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
ScreenController.register("PowerBlock", "Hud", function()
	return powerBlock.root
end)
ScreenController.register("ShopSlots", "Hud", function()
	return shopSlots.root
end)
ScreenController.register("AutoTools", "Hud", function()
	return autoTools.root
end)

ScreenController.open("BloxDisplay")
ScreenController.open("ChallengeInfo")
ScreenController.open("MenuRail")
ScreenController.open("PowerBlock")
ScreenController.open("ShopSlots")
ScreenController.open("AutoTools")

-- ⚠️ 이 로그는 "register+open을 불렀다"는 뜻이지 "지금 화면에 떠 있다"는 보장이
-- 아니다. 이후 다른 스크립트가 같은 이름을 close()하면(예전엔 ScreenControllerTests의
-- closeAll()이 그랬다 — U3-4 사고, docs/PENDING.md 해소 기록 참고) 이 줄이 찍힌
-- 뒤에도 화면이 꺼질 수 있다. "Rojo 연결 성공!"(Hello.server.lua)이 미연결 상태에서도
-- 찍히는 것과 같은 종류의 함정이다 — 이 로그만 보고 표시가 끝났다고 믿지 말 것.
-- 실제로 떠 있는지는 HudVisibilityTests.client.lua가 확인한다.
print(
	"[HudBoot] HUD 6종(BloxDisplay/ChallengeInfo/MenuRail/PowerBlock/ShopSlots/AutoTools) "
		.. "register+open 호출함 (실노출 보장 아님 — HudVisibilityTests 참고)"
)

-- ── 개발용 플래그: HUD_LAYOUT_REPORT_ENABLED ────────────────────────────────────
-- 위치: 이 파일 맨 끝, 위 register+open 호출 *뒤*. 아직 열리지도 않은 화면을
-- 관측하려 든다는 오해를 피하려고 앞이 아니라 여기 둔다.
-- Studio에서 켜고 끄는 값이 아니다. 코드에서 고치고 Rojo sync 해야 반영된다
-- (Bootstrap의 DRONE_VERIFY_ENABLED와 같은 패턴).
--
-- 왜 필요한가: HUD 표시 상태에서 육안으로 3건이 깨져 있다(docs/PENDING.md "HUD
-- 표시 상태에서 육안으로 3건이 보였다" 참고) — 좌측 레일 라벨이 타일에 겹치고,
-- 좌상단 블럭스가 안 보이고, 상단 중앙 "대기중"이 잘린다. 셋 다
-- HudVisibilityTests(IsDescendantOf + Visible + AbsoluteSize)는 통과한다. 이
-- 플래그를 켜면 실제 좌표를 Play 로그로 찍어, 다음 단계에서 만들 레이아웃
-- 테스트의 기준선을 정할 수 있게 한다 (자세한 내용은 HudLayoutReport.lua 상단).
--
-- 기본값은 켜짐이다 — 관측 단계이고, HUD 인스턴스를 읽기만 할 뿐 배치를
-- 바꾸지도 프로필도 건드리지 않으므로(HudLayoutReport 상단 참고) 켠 채로
-- 커밋해도 안전하다.
local HUD_LAYOUT_REPORT_ENABLED = true

if HUD_LAYOUT_REPORT_ENABLED then
	require(script.Parent.Parent.Tools.HudLayoutReport).run()
end

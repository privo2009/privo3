--!strict
-- UI 효과 2종의 수치 (지시서 #21 — docs/UI.md "UI 효과"). 수치의 원본은 이 파일이다. 테스트도 이 값을 읽는다.
--
--   ENABLED            UI_FX_ENABLED — 끄면 버튼 반응 · 빛 띠를 하나도 붙이지 않는다(격리 스위치. 커밋 값 true)
--   버튼 반응           HitArea(TextButton)를 덮은 그림(부모)에 UIScale을 붙여 Scale만 트윈한다(Size · Position은 그대로)
--     HOVER_*          마우스를 올렸을 때(터치에는 없다)
--     PRESS_*          눌렀을 때
--     RELEASE_*        뗐을 때 — 아직 위에 있으면 HOVER_SCALE, 아니면 1로 돌아간다
--   빛 띠(Shine)        대상 배경 위 · 글씨 아래 덮개 + UIGradient로 좁은 밝은 띠를 Offset.X −1 → 1로 지나가게 한다
--     SHINE_SWEEP_*     한 번 지나가는 시간 · 이징
--     SHINE_INTERVAL    지나가기 시작하는 간격(초)
--     SHINE_ANGLE       UIGradient.Rotation(도)
--     SHINE_BAND_HALF_WIDTH  띠 반폭(그라디언트 0 ~ 1 기준)
--     SHINE_PEAK_TRANSPARENCY 띠 가운데 투명도(가장자리 1)
--     SHINE_COLOR_*     기본 = 중립 흰색 · 프리미엄 = 금테 색(수령 · 안전 노랑 기본 — docs/UI.md "3D 오브젝트 색 배정"의 금테와 같은 키).
--                       보라(진행 전용)는 쓰지 않는다
--     SHINE_START_JITTER_MAX 시작 지연 0 ~ 이 값(초) 랜덤 — 여러 개가 동시에 번쩍이지 않게
--     SHINE_MAX_ACTIVE  한 화면에 동시에 도는 빛 띠 상한(남용 방지). 넘는 것은 멈춰 둔다(우선순위 낮은 것부터)
--     SHINE_TARGETS     어느 상품 화면 키에 붙이나 → 프리셋. 키 = RobuxShopLogic 화면 키(계단은 "strengthLadder") · HUD 구좌 키
--     SHINE_ONCE_PRIORITY  1회 모드(결과 모달 — 지시서 #25 U2)의 우선순위. 상한 3개 안에서 다른 띠보다 먼저 자리를 받는다
--
--   화면 연출(지시서 #25 U1 ~ U7 — docs/UI.md "UI 효과 > 화면 연출"). 시작값이다 — 사람이 직접 플레이하며 조정한다
--     WINDOW_*          Window 층 창 열기 · 닫기(창 UIScale + 배경 막 투명도)
--     MODAL_*           차단층 결과 모달 · 일일 보상 판 등장. MODAL_RARE_*는 영웅(표시 단계 MODAL_RARE_MIN_TIER) 이상 — 더 크게 튄다
--     COUNT_UP_*        HUD 블럭스 숫자 올라가기(log10 보간)
--     LEVEL_POP_*       레벨 숫자 튀기 · 최소 간격
--     REBIRTH_*         환생 흰 막 번쩍임 · 환생 배수 숫자 튀기
--     CRAFT_*           크래프팅 재료 모이기 · 결과 칸 튀기 · 결과 펫이 격자에 들어오기를 기다리는 한도
--     POP_PEAK_AT       "1 → 꼭대기 → 1" 튀기에서 꼭대기에 닿는 시점(전체 시간 비율). 올라갈 때 Quad Out · 내려올 때 Quad In
--     SFX_MIN_INTERVAL  같은 효과음은 이 초 안에 한 번만(지시서 #25 S2 — 클릭 소리가 너무 잦지 않게)

local UiTheme = require(script.Parent.UiTheme)

local UIFxConfig = {}

UIFxConfig.ENABLED = true -- UI_FX_ENABLED
-- 스크린샷 전용(지시서 #21 D): 숫자(−1 ~ 1)를 넣으면 도는 빛 띠가 그 Offset에 멈춘다 — MCP 캡처는 게임 시계와 맞출 수 없어서다.
-- ⚠️ 커밋 값은 언제나 nil(UiFxTests). 켠 Play로 테스트 개수를 세지 않는다
UIFxConfig.DEBUG_FREEZE_OFFSET = nil :: number?
-- 스크린샷 전용(지시서 #25 단계 5): 0 ~ 1을 넣으면 모든 화면 연출(Fx)이 그 진행률에 멈춘다(끝나지 않는다). ⚠️ 커밋 값은 언제나 nil(FxTests)
UIFxConfig.DEBUG_FREEZE_PROGRESS = nil :: number?

UIFxConfig.HOVER_SCALE = 1.06
UIFxConfig.HOVER_TIME = 0.12
UIFxConfig.HOVER_STYLE = Enum.EasingStyle.Quad
UIFxConfig.HOVER_DIRECTION = Enum.EasingDirection.Out

UIFxConfig.PRESS_SCALE = 0.92
UIFxConfig.PRESS_TIME = 0.06
UIFxConfig.PRESS_STYLE = Enum.EasingStyle.Quad
UIFxConfig.PRESS_DIRECTION = Enum.EasingDirection.Out

UIFxConfig.RELEASE_TIME = 0.18
UIFxConfig.RELEASE_STYLE = Enum.EasingStyle.Back
UIFxConfig.RELEASE_DIRECTION = Enum.EasingDirection.Out

UIFxConfig.SHINE_SWEEP_TIME = 0.7
UIFxConfig.SHINE_SWEEP_STYLE = Enum.EasingStyle.Sine
UIFxConfig.SHINE_SWEEP_DIRECTION = Enum.EasingDirection.InOut
UIFxConfig.SHINE_INTERVAL = 2.8
UIFxConfig.SHINE_ANGLE = 20
UIFxConfig.SHINE_BAND_HALF_WIDTH = 0.12
UIFxConfig.SHINE_PEAK_TRANSPARENCY = 0.55
UIFxConfig.SHINE_COLOR_DEFAULT = Color3.new(1, 1, 1)
UIFxConfig.SHINE_COLOR_PREMIUM = UiTheme.Colors.cashout.base
UIFxConfig.SHINE_START_JITTER_MAX = 0.8
UIFxConfig.SHINE_MAX_ACTIVE = 3

UIFxConfig.SHINE_ONCE_PRIORITY = 100

-- ===== 화면 연출 (지시서 #25) =====
UIFxConfig.WINDOW_OPEN_SCALE_FROM = 0.9
UIFxConfig.WINDOW_OPEN_TIME = 0.15
UIFxConfig.WINDOW_OPEN_STYLE = Enum.EasingStyle.Back
UIFxConfig.WINDOW_OPEN_DIRECTION = Enum.EasingDirection.Out
UIFxConfig.WINDOW_DIM_TIME = 0.15 -- 배경 막 페이드 인(투명도 1 → ScreenController 막의 원래 값)
UIFxConfig.WINDOW_CLOSE_SCALE_TO = 0.92
UIFxConfig.WINDOW_CLOSE_TIME = 0.1 -- 창 줄어들기 + 막 페이드 아웃
UIFxConfig.WINDOW_CLOSE_STYLE = Enum.EasingStyle.Quad
UIFxConfig.WINDOW_CLOSE_DIRECTION = Enum.EasingDirection.In

UIFxConfig.MODAL_SCALE_FROM = 0.6
UIFxConfig.MODAL_TIME = 0.25
UIFxConfig.MODAL_STYLE = Enum.EasingStyle.Back
UIFxConfig.MODAL_DIRECTION = Enum.EasingDirection.Out
UIFxConfig.MODAL_RARE_MIN_TIER = 4 -- UiTheme.Rarity 표시 단계(tier4 = 아우라 · 펫 epic · 칭호 champion)
UIFxConfig.MODAL_RARE_SCALE_FROM = 0.5
UIFxConfig.MODAL_RARE_PEAK = 1.08
UIFxConfig.MODAL_RARE_TIME = 0.3

UIFxConfig.COUNT_UP_TIME = 0.3
UIFxConfig.COUNT_UP_STYLE = Enum.EasingStyle.Quad
UIFxConfig.COUNT_UP_DIRECTION = Enum.EasingDirection.Out

UIFxConfig.POP_PEAK_AT = 0.5
UIFxConfig.LEVEL_POP_PEAK = 1.2
UIFxConfig.LEVEL_POP_TIME = 0.2
UIFxConfig.LEVEL_POP_MIN_INTERVAL = 0.5

UIFxConfig.REBIRTH_FLASH_FROM = 0.5 -- 흰 막 투명도 시작(→ 1)
UIFxConfig.REBIRTH_FLASH_TIME = 0.3
UIFxConfig.REBIRTH_POP_PEAK = 1.3
UIFxConfig.REBIRTH_POP_TIME = 0.35

UIFxConfig.CRAFT_GATHER_TIME = 0.25
UIFxConfig.CRAFT_POP_FROM = 0.6
UIFxConfig.CRAFT_POP_TIME = 0.2
UIFxConfig.CRAFT_WAIT_SEC = 2

UIFxConfig.SFX_MIN_INTERVAL = 0.05

-- 상품 화면 키 → 프리셋. 프리미엄(남색 + 금테) 역할의 슬롯이면 "premium" — 지금 대상 둘은 로벅스(초록) 역할이라 default다
UIFxConfig.SHINE_TARGETS = {
	strengthLadder = "default", -- 상점 로벅스 탭 힘 배수 계단 줄(다음 단계)
	strength2x = "default", -- HUD 구좌 — 2배 힘 자리(다음 계단 단계를 보인다)
	blox2x = "default", -- 2배 블럭스(상점 줄 · HUD 구좌)
} :: { [string]: string }

function UIFxConfig.validate(): boolean
	assert(UIFxConfig.HOVER_SCALE > 1 and UIFxConfig.PRESS_SCALE > 0 and UIFxConfig.PRESS_SCALE < 1, "UIFxConfig: 올림 > 1 > 누름 > 0")
	assert(UIFxConfig.HOVER_TIME > 0 and UIFxConfig.PRESS_TIME > 0 and UIFxConfig.RELEASE_TIME > 0, "UIFxConfig: 시간은 0 초과")
	assert(UIFxConfig.SHINE_SWEEP_TIME > 0 and UIFxConfig.SHINE_INTERVAL > UIFxConfig.SHINE_SWEEP_TIME,
		"UIFxConfig: 간격은 지나가는 시간보다 길어야 함")
	assert(UIFxConfig.SHINE_BAND_HALF_WIDTH > 0 and UIFxConfig.SHINE_BAND_HALF_WIDTH < 0.5, "UIFxConfig: 띠 반폭 0 ~ 0.5")
	assert(UIFxConfig.SHINE_PEAK_TRANSPARENCY >= 0 and UIFxConfig.SHINE_PEAK_TRANSPARENCY < 1, "UIFxConfig: 띠 가운데 투명도 0 이상 1 미만")
	assert(UIFxConfig.SHINE_START_JITTER_MAX >= 0 and UIFxConfig.SHINE_MAX_ACTIVE >= 1, "UIFxConfig: 지연 · 상한")
	-- 화면 연출(지시서 #25): 시간 0 초과 · 시작 크기 0 초과 1 미만 · 꼭대기 1 초과 · 투명도 0 ~ 1 · 간격 ≥ 0
	for _, t in ipairs({ UIFxConfig.WINDOW_OPEN_TIME, UIFxConfig.WINDOW_DIM_TIME, UIFxConfig.WINDOW_CLOSE_TIME, UIFxConfig.MODAL_TIME,
		UIFxConfig.MODAL_RARE_TIME, UIFxConfig.COUNT_UP_TIME, UIFxConfig.LEVEL_POP_TIME, UIFxConfig.REBIRTH_FLASH_TIME,
		UIFxConfig.REBIRTH_POP_TIME, UIFxConfig.CRAFT_GATHER_TIME, UIFxConfig.CRAFT_POP_TIME }) do
		assert(t > 0 and t < 2, "UIFxConfig: 연출 시간은 0 초과 2초 미만")
	end
	for _, f in ipairs({ UIFxConfig.WINDOW_OPEN_SCALE_FROM, UIFxConfig.WINDOW_CLOSE_SCALE_TO, UIFxConfig.MODAL_SCALE_FROM,
		UIFxConfig.MODAL_RARE_SCALE_FROM, UIFxConfig.CRAFT_POP_FROM }) do
		assert(f > 0 and f < 1, "UIFxConfig: 시작 · 끝 크기는 0 초과 1 미만")
	end
	assert(UIFxConfig.MODAL_RARE_PEAK > 1 and UIFxConfig.LEVEL_POP_PEAK > 1 and UIFxConfig.REBIRTH_POP_PEAK > 1, "UIFxConfig: 꼭대기 > 1")
	assert(UIFxConfig.POP_PEAK_AT > 0 and UIFxConfig.POP_PEAK_AT < 1, "UIFxConfig: 꼭대기 시점 0 ~ 1")
	assert(UIFxConfig.REBIRTH_FLASH_FROM >= 0 and UIFxConfig.REBIRTH_FLASH_FROM < 1, "UIFxConfig: 번쩍임 시작 투명도 0 이상 1 미만")
	assert(UIFxConfig.MODAL_RARE_MIN_TIER >= 1 and UIFxConfig.MODAL_RARE_MIN_TIER <= 6, "UIFxConfig: 희귀 단계 1 ~ 6")
	assert(UIFxConfig.LEVEL_POP_MIN_INTERVAL >= 0 and UIFxConfig.SFX_MIN_INTERVAL >= 0 and UIFxConfig.CRAFT_WAIT_SEC > 0, "UIFxConfig: 간격 · 대기")
	for key, preset in pairs(UIFxConfig.SHINE_TARGETS) do
		assert(preset == "default" or preset == "premium", "UIFxConfig: 프리셋은 default · premium만 — " .. key)
	end
	return true
end

return UIFxConfig

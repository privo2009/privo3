--!strict
-- 화면 글자 원본 (지시서 #L1 K1). 키 → { en = 영어, ko = 한국어 }. **화면에 보이는 문장은 전부 여기 있다.**
-- 코드는 키로만 부른다: Locale.t(키, 자리 표시). 언어 고르기 · 없는 번역 처리는 Locale, 구조 · 절차는 docs/LOCALIZATION.md.
--
-- ===== 쓰는 법 ======================================================================================
--
--   한 줄에 항목 하나:  ["화면.항목"] = { en = "...", ko = "..." },
--   자리 표시 {name}:   영어 · 한국어가 같은 집합이어야 한다(LocaleTests · tools/check_strings.py가 잰다)
--   숫자:               Formatter로 만든 문자열을 자리 표시로 넣는다 — 이 표에 숫자 꼴을 두지 않는다
--   영어(K9):           짧게. 버튼은 명령형(Hatch · Equip · Claim). 문장 끝 마침표 없음(안내문만 마침표)
--   한국어:             지금 화면 문장 그대로(#L1에서 새로 쓰지 않았다)
--   ⚠️ 이 파일은 tools/check_strings.py · tools/export_localization_csv.py가 줄 단위로 읽는다. 한 항목을 여러 줄로 나누지 않는다.
--
-- ===== 용어집 (K8 — docs/LOCALIZATION.md "4. 용어집"과 같은 표. 바꿀 때 둘 다) ==========================
--
--   힘 Power · 블럭스 Blox · 환생 Rebirth · 환생 배수 Rebirth Multiplier · 층 Floor · 런 Run
--   수령 Claim · 수령 발판 Claim Pad · 진행 Advance · 진행 벽 Advance Wall · 입장 게이트 Entry Gate
--   클릭 파워 패드 Power Pad · 운동기구 Gym · 공허 훈련 구역 Void Training Zone · 워프 Warp
--   레벨 Level · 이동 속도 Speed · 업그레이드 Upgrade · 상점 Shop · 설정 Settings
--   칭호 Title · 아우라 Aura · 펫 Pet · 알 Egg · 부화 Hatch · 크래프팅 Craft · 놓아주기 Release · 장착 Equip
--   희귀도 Common · Rare · Epic · Legendary (아우라 · 펫)
--   칭호 6종 Novice · Apprentice · Destroyer · Champion · Legend · Mythic
--   강화 단계 Normal · Gold · Diamond · Rainbow
--   포션 Potion · 행운 Luck · 부스트 Boost · 자동 클리커 Auto Clicker · 자동 진행 Auto Advance
--   상품 이름은 대시보드 이름과 같은 꼴: x2 Power · Auto Clicker · Lucky Roll x5 (배수가 앞, 횟수가 뒤)

local Strings = {}

export type Entry = { en: string, ko: string? }

Strings.Entries = {
	-- ===== 공통 ==========================================================================================
	["common.reason.rate_limited"] = { en = "Please wait a moment and try again", ko = "잠시 뒤에 다시 눌러 주세요" },
	["common.reason.no_profile"] = { en = "Loading your data", ko = "데이터를 불러오는 중이에요" },
	["common.reason.insufficient_blox"] = { en = "Not enough Blox", ko = "블럭스가 모자라요" },
	["common.reason.invalid_request"] = { en = "Can't do that", ko = "할 수 없는 요청이에요" },
	["common.reason.partial_failure"] = { en = "Something went wrong. Please tell an admin.", ko = "문제가 생겼어요. 관리자에게 알려 주세요" },
	["common.reason.failed"] = { en = "Couldn't do that", ko = "하지 못했어요" },
} :: { [string]: Entry }

return Strings

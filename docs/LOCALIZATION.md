# 다국어 (사람용 한 장)

문서 갱신: 2026-10-25 (지시서 #L1)

게임 언어 결정은 `DESIGN.md` "12. 언어"가 원본이다. 이 문서는 **어떻게 돌아가고, 무엇을 어떻게 고치는지**만 둔다.

---

## 1. 구조

```
src/shared/Localization/Strings.lua      원본. 키 → { en = 영어, ko = 한국어 }
        │
        ├─ 게임 안   Locale.t(키, 자리 표시)  →  화면 글자
        │            (src/shared/Localization/Locale.lua — 언어 고르기 · 없는 번역 처리 · 자리 표시 채우기)
        │
        └─ 내보내기  python3 tools/export_localization_csv.py  →  로블록스 현지화 표 CSV
                     → Creator Hub에 올린다(클라우드 현지화 표) → 유럽 · 아시아 언어 자동 번역의 재료
```

- **원본은 저장소의 Strings 하나다.** 클라우드 표는 내보내기다. 클라우드 표에서 직접 고친 번역은 다음 내보내기 때
  덮일 수 있으니, 고칠 것은 Strings에 고치고 다시 올린다
- 언어 고르기: 로블록스 계정 언어(`Player.LocaleId`)가 `ko`로 시작하면 한국어, 그 밖은 전부 영어
- 번역이 없거나 빈 키는 영어로 보인다. 영어도 없으면 `?`가 보이고 출력 창에 WARN이 찍힌다(키 이름은 화면에 안 나간다)

### 화면 이름 (칭호 · 아우라 · 펫 · 알 · 업그레이드 · 상품)

Config 파일에는 id만 있다. 화면 이름은 id로 키를 만들어 Strings에서 찾는다
(`src/shared/Localization/Names.lua` — 예: 아우라 `pack1_common` → 키 `aura.name.pack1_common`).
시뮬레이터 · 리포트는 이름 대신 id를 찍는다.

### 서버가 보내는 것

서버는 화면 문장을 보내지 않는다. 거부 사유는 코드(`insufficient_blox` 등)로 보내고, 클라가 Strings로 문장을 고른다.
예외 하나: 접속을 끊을 때(`Player:Kick`)의 안내문은 클라가 이미 없으므로 서버가 그 플레이어 언어로 Strings에서 골라 넣는다
(`Server/Systems/LocaleGate`). 서버 로그(print · warn)는 번역하지 않는다.

### Studio에서 언어 바꿔 보기 — TEST_LOCALE

`src/server/Bootstrap.server.lua`의 `TEST_LOCALE`에 `"en"` 또는 `"ko"`를 적고 Play하면 그 언어로 보인다(Studio 전용).
⚠️ 커밋할 때는 반드시 `nil`로 되돌린다. `LocaleTests`가 커밋 값이 nil인지 잰다 — 켠 Play에서는 그 줄이 실패하니 그 Play로 테스트 개수를 세지 않는다.

---

## 2. 새 문장을 추가하는 법

1. `Strings.lua`에 한 줄 추가한다. 화면(구역)별로 묶어 둔 자리에 넣는다
   ```
   ["shop.tab.robux"] = { en = "Robux", ko = "로벅스" },
   ```
   - 키: `화면.항목` 소문자 · 점 구분. 이미 있는 키 이름 짓기를 따른다
   - 영어: 짧게. 버튼은 명령형(`Hatch` · `Equip` · `Claim`). 문장 끝 마침표 없음(안내문만 마침표)
   - 한국어: 지금 화면 말투(해요체) 그대로
   - 용어는 아래 "4. 용어집"을 따른다
2. 바뀌는 값은 자리 표시 `{이름}`으로 둔다. 영어 · 한국어 둘 다 **같은 자리 표시 집합**이어야 한다(검사가 잰다)
   ```
   ["aura.pack.info"] = { en = "Pack {pack} · {cost} Blox per roll", ko = "팩 {pack} · 1회 {cost} 블럭스" },
   ```
   숫자는 코드에서 `Formatter.format(...)` · `string.format("%.2f", ...)`로 문자열을 만든 뒤 넣는다
3. 코드에서는 키로만 부른다: `Locale.t("aura.pack.info", { pack = 1, cost = Formatter.format(c) })`.
   **화면 문장을 코드에 직접 쓰지 않는다**(CLAUDE.md 금지 사항)
4. 검사를 돌린다 (Python 3만 있으면 된다)
   ```
   python3 -I tools/check_strings.py      Strings 표 검사(영어 있음 · 자리 표시 일치 · 코드가 부르는 키가 표에 있음)
   python3 -I tools/l10n_scan.py --check   화면 코드에 한글 문장이 남았는지
   ```
5. 영어 · 한국어 둘 다 그 칸에서 읽히는지 Studio에서 본다(`TEST_LOCALE` en · ko 두 번 Play). 길이 규칙은 `docs/UI.md` "4. 글자 > 글자 길이"

---

## 3. 새 언어를 추가하는 순서

순서: **유럽 언어 먼저 → 그다음 나머지 아시아 언어** (2026-10-25 사람 결정).

언어마다 둘 중 하나를 고른다:

```
가. 로블록스 자동 번역  Strings는 en · ko 그대로. 클라우드 표에 CSV를 올리고 그 언어 자동 번역을 켠다
                       → 런타임이 클라우드 표를 읽어야 보인다(아래 "5. 런타임 연결" 나중 방식)
나. 직접 번역           Strings에 그 언어 열을 추가한다(예: es = "..."). Locale.SUPPORTED에 언어 코드를 넣는다
```

가.의 절차(처음 한 번):
1. Creator Hub → 게임 → **Audience → Localization**에서 원본 언어(Source Language)를 **English**로 둔다
2. **Supported Languages**에 그 언어를 추가한다
3. `python3 tools/export_localization_csv.py`로 CSV를 만들고, 같은 Localization 페이지에서 **Upload CSV**로 올린다
   (Studio는 Localization Tools 창 → Cloud Localization Table → Update)
4. **Settings → Use Translated Content**를 켜고, **Languages** 탭에서 그 언어의 자동 번역(Experience Strings & Products)을 켠다
5. 런타임 연결 플래그를 켠다(아래 5절 — Studio에서 확인한 뒤에만)

⚠️ **자동 텍스트 캡처(Automatic Text Capture)는 켜지 않는다.** 캡처는 화면에 뜬 글자를 원본(영어)으로 가정하고 표에 넣는다.
한국어 플레이어 화면의 한국어 문장까지 "영어 원본"으로 들어가 표가 더러워진다. 표는 CSV로만 채운다.

CSV 한계(공식 문서): 파일 2MB · 항목 1만 · 한 번에 추가 · 수정 1,000개. 지금 표는 그 아래다.

### 대시보드 상품 이름의 번역 (게임패스 · 개발자 상품)

상품 이름 · 설명은 클라우드 표가 아니라 **대시보드 상품 정보**다. 대시보드에는 영어 이름 · 설명을 넣는다(원본 `Strings`의
`shop.<키>.name` · `.desc` 영어). 한국어는 사람이 대시보드에서 넣는다:

```
Localization 페이지 → 오른쪽 위 Translate → 왼쪽 Target Languages에서 한국어 → 위 Products 탭 → 번역 입력 → Save
```
(공식 문서 add-translations "Add game product translations" — 2026-10-25 확인. 화면에서 실제로 같은지는 확인 필요)

게임 안 상점 창 이름은 대시보드가 아니라 Strings에서 나온다 — 둘이 어긋나지 않게 대시보드에도 Strings의 문장을 그대로 넣는다.

---

## 4. 용어집 (영어 표기 통일)

Strings 상단 주석에 같은 표가 있다. 바꿀 때는 둘 다 바꾼다(이 표는 사람이 읽는 쪽, Strings 주석은 코드 쪽).

```
힘 Power              블럭스 Blox            환생 Rebirth           환생 배수 Rebirth Multiplier
층 Floor              런 Run                 수령 Claim             수령 발판 Claim Pad
진행 Advance          진행 벽 Advance Wall   입장 게이트 Entry Gate
클릭 파워 패드 Power Pad                     운동기구 Gym           공허 훈련 구역 Void Training Zone
워프 Warp             레벨 Level             이동 속도 Speed        업그레이드 Upgrade
상점 Shop             설정 Settings
칭호 Title            아우라 Aura            펫 Pet                 알 Egg
부화 Hatch            크래프팅 Craft         놓아주기 Release       장착 Equip
희귀도(아우라 · 펫)    Common · Rare · Epic · Legendary
칭호 6종              Novice · Apprentice · Destroyer · Champion · Legend · Mythic
강화 단계             Normal · Gold · Diamond · Rainbow
포션 Potion           행운 Luck              부스트 Boost           자동 클리커 Auto Clicker
자동 진행 Auto Advance
```

- 상품 이름은 대시보드 이름과 같은 표기를 쓴다: `x2 Power` · `Auto Clicker` · `Lucky Roll x5` 꼴(배수가 앞, 횟수가 뒤)
- 아우라 · 펫 · 알 개별 영어 이름은 #L1에서 Claude가 한국어 뜻을 살려 지었다 — 바꾸려면 Strings에서 바꾼다

---

## 5. 런타임 연결 — 지금 방식 / 나중 방식

```
지금    Strings만 쓴다. en · ko는 게임 안 표에서 바로 고른다. 클라우드 표를 읽지 않는다
        Locale.CLOUD_TRANSLATOR_ENABLED = false (커밋 값)

나중    en · ko 밖의 언어 플레이어에게만 클라우드 표의 번역을 쓴다
        LocalizationService:GetTranslatorForPlayerAsync(플레이어)로 Translator를 한 번 받고,
        Locale.t가 Translator:FormatByKey(키, 자리 표시)를 먼저 해 본다. 실패 · 없음이면 영어(Strings)
        Translator를 받기 전(비동기)에는 영어로 보인다
```

왜 이렇게 나눴나:
- 클라우드 표에 키(Key 열)와 자리 표시 `{name}`(이름 붙은 자리 표시)를 그대로 올릴 수 있다 — FormatByKey가 같은 꼴을 받는다.
  그래서 Strings가 원본 · 클라우드가 내보내기라는 원칙이 공식 방식과 부딪히지 않는다
- 로블록스 자동 번역(AutoLocalize)은 화면 글자를 표의 Source와 **통째로 맞춰** 바꾼다. 우리 문장은 숫자가 섞여 조합되므로
  ("Floor 5" 등) 통째 맞추기로는 대부분 안 바뀐다. 키로 찾는 FormatByKey가 맞다
- en · ko는 지금처럼 게임 안 표가 빠르고 확실하다(비동기 · 네트워크 실패가 없다)

켜는 조건(나중 — 사람이 정한다):
1. 3절 가.의 1 ~ 4를 마쳤다(클라우드 표에 CSV · 그 언어 자동 번역 켜짐)
2. Studio에서 그 언어 계정(또는 Studio의 언어 테스트)으로 Play해 Translator가 번역을 돌려주는지 본다
3. 그 뒤 `Locale.CLOUD_TRANSLATOR_ENABLED = true`로 커밋한다

근거(공식 문서 — 2026-10-25 확인. create.roblox.com이 이 세션 네트워크에서 막혀 같은 문서의 원본 저장소
`github.com/Roblox/creator-docs`에서 읽었다):
- 현지화 표 열(Key · Context · Example · Source · 언어 코드) · Source 필수 · Key 중복 금지 · Source + Context 중복 금지 —
  https://create.roblox.com/docs/production/localization/manual-translations
- CSV 올리기 · 한계 · 상품 번역 자리 — https://create.roblox.com/docs/production/localization/add-translations
- 자리 표시(`{Player_Name}` 꼴) — https://create.roblox.com/docs/production/localization/translate-dynamic-content
- Translator · FormatByKey · GetTranslatorForPlayerAsync — https://create.roblox.com/docs/production/localization/localize-with-scripting
  · https://create.roblox.com/docs/reference/engine/classes/Translator
- 자동 번역 · 자동 텍스트 캡처 · 원본 언어 가정 — https://create.roblox.com/docs/production/localization/automatic-translations
- `Player.LocaleId`(게임 콘텐츠 현지화에 쓰는 계정 언어) — https://create.roblox.com/docs/reference/engine/classes/Player#LocaleId
- 언어 코드(한국어 `ko` · `ko-kr`) — https://create.roblox.com/docs/production/localization/language-codes

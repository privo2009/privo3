# 대시보드 상품 등록표

Creator Dashboard에 만들 로벅스 상품 전부와, 만든 뒤 ID를 적을 자리. 지시서 #16(2026-10-25)에서 만들었다.

⚠️ **이 문서는 목록과 절차만 둔다. 가격 · 효과의 원본은 `src/shared/Config/ShopConfig.lua`, 이름 · 설명의 원본은
`src/shared/Localization/Strings.lua`(`shop.<키>.name` · `.desc`)다** (지시서 #L1 K6 — 2026-10-25부터 Config에는 이름이 없다).
아래 값은 그 파일들을 옮겨 적은 것이라, 어긋나면 원본이 맞다(CLAUDE.md "문서 > 복사본은 반드시 어긋난다").
등록할 때는 ShopConfig(가격)와 Strings(이름 · 설명)를 열어 놓고 그 값을 넣는다.

⚠️ **대시보드 이름 · 설명은 영어(Strings의 en)로 넣는다** — 게임 기본 언어가 영어다(`DESIGN.md` "12. 언어").
한국어(Strings의 ko — 아래 표의 이름 · 설명)는 대시보드 번역 자리(Localization → Translate → 한국어 → Products 탭)에 사람이 넣는다
(`docs/LOCALIZATION.md` 3절 "대시보드 상품 이름의 번역"). 영어 목록은 `python3 -I tools/export_localization_csv.py`의 `shop.` 줄로도 뽑을 수 있다.

문서 갱신: 2026-10-25 (지시서 #L1 — 이름 · 설명 원본이 Strings로 옮겨 감)

---

## 1. 지금 상태

- ShopConfig의 상품 **39개 전부 `id = 0`(미등록)이다.** 게임에서는 "준비 중"으로 보이고 구매가 막힌다.
  서버 MarketplaceGateway가 ID 0이면 프롬프트를 띄우지 않고 `not_registered`를 돌려준다.
- 게임패스 23(일반 13 · 힘 배수 계단 10) · 개발자 상품 16(롤 4 · 포션 3 · 포션 번들 1 · 운동기구 선해금 8).
- 개발자 상품은 **ID를 넣어도 아직 팔리지 않는다.** 지급 함수가 없는 상품은 서버가 `not_available`로 거부한다
  (ProductService — 결제는 됐는데 지급은 안 되는 상태를 만들지 않는다). 지급 함수는 지시서 #17이 채운다.

## 2. 대시보드 절차 (공식 문서 — 2026-10-25 확인)

게임패스 — https://create.roblox.com/docs/production/monetization/passes
```
만들기    Creations에서 게임 선택 → Monetization ⟩ Passes → Create pass
          아이콘(512×512 이하 · 원 밖에 중요한 내용 없음 · jpg/png/bmp) · 이름 · 설명 · 분류 → Create pass
ID 복사   Monetization ⟩ Passes → 패스 썸네일에 마우스 → ⋯ → Copy Asset ID
가격      확인 못 함 — 위 페이지에 가격을 정하는 단계가 적혀 있지 않다(판매 상태 "Listed" 언급만 있다)
```

개발자 상품 — https://create.roblox.com/docs/production/monetization/developer-products
```
만들기    Creations에서 게임 선택 → Monetization ⟩ Developer Products → Create developer product
          아이콘(512×512 이하 · jpg/png/bmp) · 이름 · 설명 · 분류 · 가격(1 ~ 10억 로벅스) → Save Changes
ID 복사   Monetization ⟩ Developer Products → 썸네일에 마우스 → ⋯ → Copy Asset ID
주의      "팔기 전에 영수증을 제대로 처리하고 지급할 것 — ProcessReceipt API" (같은 페이지)
```

Studio에서 테스트 구매가 되는지는 위 두 페이지와 player-data-purchasing 페이지에서 **확인 못 함**(지시서 #15 · #16 조사).
그래서 구매 경로는 테스트용 가짜 게이트웨이(`MarketplaceGateway.fake`)로만 잰다 — 실제 프롬프트를 MCP로 누르지 않는다.

## 3. ID를 넣는 자리

`src/shared/Config/ShopConfig.lua`에서 그 키의 `id = 0`을 복사한 Asset ID로 바꾼다.
```
pass("damage2x", 149, ...)   →  add({ key = "damage2x", kind = "gamepass", id = 0, ... })
```
지금은 `pass(...)` · `product(...)` 함수가 `id = 0`을 넣는다. ID를 넣을 때 키별 ID 표를 ShopConfig에 두는 방식으로 바꾼다
(코드 담당 — Rojo · Git 작업이라 디자인 담당이 하지 않는다). `ShopConfig.validate`가 같은 ID 두 번 · 음수 · 소수 ID를 거부한다.

넣은 뒤 확인:
- Play 서버 로그 `[Bootstrap][VERIFY][SHOP]` 줄 — 그 패스를 가진 계정이면 `owned=`에 키가 보인다
- 상점 창 로벅스 탭에서 "준비 중"이 초록 구매 버튼 + 가격으로 바뀐다
- 가격은 대시보드 값과 ShopConfig `priceRobux`가 같아야 한다(화면은 ShopConfig 값을 보인다)

## 4. 게임패스 (23)

로벅스 행운 상품(★)은 제한 지역 유저에게 숨기고 보유해도 효과를 끈다(DESIGN 9장 S13).
```
키                 이름               가격   설명
autoClicker        자동 클리커          49   켜 두면 초당 15번 자동으로 클릭해요
autoClickerOP      OP 자동 클리커       89   켜 두면 초당 30번 자동으로 클릭해요
damage2x           2배 데미지          149   1펀치 데미지가 2배예요
blox2x             2배 블럭스          199   수령할 때 받는 블럭스가 2배예요
rebirth2x          2배 환생             99   환생할 때 얻는 환생 수가 2배예요
voidTrainingZone   공허 훈련 구역      799   가장 센 운동기구를 열어요
autoAdvance        자동 진행           199   목표층까지 멈추지 않고 진행해요        (효과는 #18)
petSlots3          +3 펫 장착          199   펫을 3마리 더 장착해요
petStorage100      +100 펫 저장 공간    49   펫을 100마리 더 보관해요
hatch3x            3배 부화             99   알을 한 번에 3개 부화해요(비용 3배)    (창 버튼은 #17)
petLuck2x        ★ 2배 펫 행운          99   펫 부화 행운이 2배예요
auraLuck10x      ★ 10배 아우라 행운    299   아우라 뽑기 행운이 10배예요
titleLuck10x     ★ 10배 칭호 행운      299   칭호 뽑기 행운이 10배예요
```
힘 배수 계단 — 보유한 단계 중 **가장 높은 하나만** 적용된다(곱하지 않는다).
설명은 전부 "클릭으로 얻는 힘이 N배예요(가장 높은 단계 하나만)".
```
strength2x    2배 힘       3      strength64x    64배 힘     799
strength4x    4배 힘       9      strength128x   128배 힘  1,499
strength8x    8배 힘      29      strength256x   256배 힘  2,499
strength16x   16배 힘     79      strength512x   512배 힘  3,999
strength32x   32배 힘    249      strength1024x  1024배 힘 5,999
```

## 5. 개발자 상품 (16)

```
키              이름              가격   설명
luckyRoll5    ★ 럭키 롤 5회         49   아우라 뽑기 5회 · 행운 ×5 · 블럭스 없이
luckyRoll15   ★ 럭키 롤 15회       149   아우라 뽑기 15회 · 행운 ×5 · 블럭스 없이
superRoll5    ★ 슈퍼 롤 5회         99   아우라 뽑기 5회 · 행운 ×100 · 블럭스 없이
superRoll15   ★ 슈퍼 롤 15회       249   아우라 뽑기 15회 · 행운 ×100 · 블럭스 없이
strengthPotion  힘 포션             19   15분 동안 힘 ×2
damagePotion    데미지 포션         19   15분 동안 1펀치 데미지 ×2
luckPotion    ★ 행운 포션           29   15분 동안 칭호 · 아우라 · 펫 행운 ×2
potionBundle  ★ 포션 번들          999   힘 · 데미지 · 행운 포션 각 99개
gymUnlock1      운동기구 1 열기     29   환생 수와 상관없이 운동기구 1을 열어요
gymUnlock2      운동기구 2 열기     49   (같은 꼴 — 번호만 다르다)
gymUnlock3      운동기구 3 열기     79
gymUnlock4      운동기구 4 열기     99
gymUnlock5      운동기구 5 열기    149
gymUnlock6      운동기구 6 열기    199
gymUnlock7      운동기구 7 열기    299
gymUnlock8      운동기구 8 열기    449
```
지급 함수(#17 전까지 없음): 롤 → `rollCredits` · 포션 → `potions` 보관함 · 선해금 → `gymUnlocks` 기록(전부 스키마 v7).

## 6. 아이콘

상품 아이콘 이미지는 아직 없다(디자인 담당 제작 목록에 없다 — HUD 구좌도 초록 역할색 칸으로 그린다).
공식 절차에 아이콘 업로드 단계가 있다(반드시 올려야 하는지는 확인 못 함). 등록 전에 사람이 정한다: 임시 아이콘으로 먼저 등록할지, 아이콘을 기다릴지.

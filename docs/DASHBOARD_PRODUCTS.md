# 대시보드 상품 등록표

Creator Dashboard에 만들 로벅스 상품 전부와, 만든 뒤 ID를 적을 자리. 지시서 #16(2026-10-25)에서 만들었다.

⚠️ **이 문서는 목록과 절차만 둔다. 가격 · 효과의 원본은 `src/shared/Config/ShopConfig.lua`, 이름 · 설명의 원본은
`src/shared/Localization/Strings.lua`(`shop.<키>.name` · `.desc`)다** (지시서 #L1 K6 — 2026-10-25부터 Config에는 이름이 없다).
아래 값은 그 파일들을 옮겨 적은 것이라, 어긋나면 원본이 맞다(CLAUDE.md "문서 > 복사본은 반드시 어긋난다").
등록할 때는 ShopConfig(가격)와 Strings(이름 · 설명)를 열어 놓고 그 값을 넣는다.

⚠️ **대시보드 이름 · 설명은 영어(Strings의 en)로 넣는다** — 게임 기본 언어가 영어다(`DESIGN.md` "12. 언어").
한국어(Strings의 ko — 아래 표의 이름 · 설명)는 대시보드 번역 자리(Localization → Translate → 한국어 → Products 탭)에 사람이 넣는다
(`docs/LOCALIZATION.md` 3절 "대시보드 상품 이름의 번역"). 영어 목록은 `python3 -I tools/export_localization_csv.py`의 `shop.` 줄로도 뽑을 수 있다.

문서 갱신: 2026-10-30 (지시서 #17 — 대시보드 등록 완료 · 39개 ID · 가격 · 대시보드 이름)

---

## 1. 지금 상태 (2026-10-30)

- **39개 전부 대시보드에 등록됐다(사람).** 게임패스 23(일반 13 · 힘 배수 계단 10) · 개발자 상품 16(롤 4 · 포션 3 · 포션 번들 1 · 운동기구 선해금 8).
- 아래 ID · 가격은 사람이 대시보드에서 옮겨 준 값이다(지시서 #17). 지시서 #17 3단계가 ShopConfig에 넣는다 — 넣기 전에는 게임에서 여전히 "준비 중"이다.
- ShopConfig 가격은 대시보드 가격과 같아야 한다. 서버가 시작할 때 GetProductInfoAsync로 읽어 다르면 WARN만 한다(자동으로 고치지 않는다 — `DESIGN.md` 9장).
- 개발자 상품 지급 함수는 지시서 #17 4단계가 넣는다. 그 전에는 ID가 있어도 서버가 `not_available`로 거부한다(결제되고 지급 안 되는 상태를 만들지 않는다).

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

Studio 구매 — MarketplaceService 레퍼런스(2026-10-30 확인,
https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#PromptProductPurchase)에
"In Studio, mocked purchases don't check that the product belongs to the current game"(게임패스도 같은 문장)가 있다 — **Studio 구매는 모의다.**
로벅스가 빠지는지 · 영수증이 어떻게 오는지는 서술이 없다(확인 못 함) → 지시서 #17 7단계에서 사람이 한 번 사 보고 관측했다(2026-10-31):
구매 창에 테스트(모의) 표시 · 로벅스 잔액 그대로 · 영수증은 실제 ProcessReceipt로 온다(Power Potion — `docs/PENDING.md` "#17 단계 7").
MCP로는 실제 프롬프트를 누르지 않는다 — 구매 경로는 테스트용 가짜 게이트웨이(`MarketplaceGateway.fake`)로 잰다.

## 3. ID를 넣는 자리

`src/shared/Config/ShopConfig.lua`의 키별 ID 표. 키 하나에 ID 하나 — `ShopConfig.validate`가 ID 0 이하 · 같은 ID 두 번 ·
게임패스 ID와 개발자 상품 ID가 섞이는 것을 거부한다(지시서 #17).

넣은 뒤 확인:
- Play 서버 로그 `[Bootstrap][VERIFY][SHOP]` 줄 — 그 패스를 가진 계정이면 `owned=`에 키가 보인다
- 상점 창 로벅스 탭에서 "준비 중"이 초록 구매 버튼 + 가격으로 바뀐다
- 가격 WARN 줄이 없어야 한다(서버 시작 때 GetProductInfoAsync 대조)

## 4. 게임패스 (23)

대시보드 이름은 영어 그대로 적는다. 로벅스 행운 상품(★)은 제한 지역 유저에게 숨기고 보유해도 효과를 끈다(DESIGN 9장 S13).
```
키                 대시보드 이름          ID            R$
autoClicker        Auto Clicker           2052132045     49
autoClickerOP      OP Auto Clicker        2053242108     89
rebirth2x          x2 Rebirths            2054058093     99
damage2x           x2 Damage              2052696040    149
blox2x             x2 Blox                2054262102    199
hatch3x            Triple Hatch           2052474059     99
petLuck2x        ★ x2 Pet Luck            2052954089     99
petStorage100      +100 Pet Storage       2054172019     49
petSlots3          +3 Pet Slots           2053284114    199
auraLuck10x      ★ x10 Aura Luck          2053680063    299
titleLuck10x     ★ x10 Title Luck         2052546070    299
voidTrainingZone   Void Training Zone     2054052054    799
autoAdvance        Auto Advance           2053542093    199   (효과는 #18)
```
힘 배수 계단 — 보유한 단계 중 **가장 높은 하나만** 적용된다(곱하지 않는다). 가진 단계 이하는 살 수 없다(R1).
```
strength2x     x2 Power      2052216044      3
strength4x     x4 Power      2052702002      9
strength8x     x8 Power      2052210043     29
strength16x    x16 Power     2052438033     79
strength32x    x32 Power     2054039990    149
strength64x    x64 Power     2052954081    249
strength128x   x128 Power    2052480115    399
strength256x   x256 Power    2053890027    499
strength512x   x512 Power    2053164055    599
strength1024x  x1024 Power   2052390076    699
```

## 5. 개발자 상품 (16)

```
키              대시보드 이름       ID            R$
luckyRoll5    ★ Lucky Roll x5      3722238324     49
luckyRoll15   ★ Lucky Roll x15     3722238413    149
superRoll5    ★ Super Roll x5      3722238507     99
superRoll15   ★ Super Roll x15     3722238589    249
strengthPotion  Power Potion       3722238698     19
damagePotion    Damage Potion      3722238762     19
luckPotion    ★ Luck Potion        3722238841     29
potionBundle  ★ Potion Bundle      3722238982    999
gymUnlock1      Gym 1 Unlock       3722239093     29
gymUnlock2      Gym 2 Unlock       3722239174     49
gymUnlock3      Gym 3 Unlock       3722239239     79
gymUnlock4      Gym 4 Unlock       3722239675     99
gymUnlock5      Gym 5 Unlock       3722239721    149
gymUnlock6      Gym 6 Unlock       3722239888    199
gymUnlock7      Gym 7 Unlock       3722240101    299
gymUnlock8      Gym 8 Unlock       3722240268    449
```
지급(지시서 #17): 롤 → `rollCredits` · 포션 → `potions` 보관함(번들은 종류마다 +99) · 선해금 → `gymUnlocks` 기록. 규칙은 `DESIGN.md` 9장 "구매 규칙 · 지급 · 사용".

✅ 게임 화면 영어 이름 = 대시보드 이름(39개 전부). #17에서 운동기구 선해금("Gym {n} Unlock"), #18 N1에서 나머지 3개
(x2 Rebirths · Triple Hatch · +3 Pet Slots — `a77fadb`)를 맞췄다. 한국어 이름은 그대로.

## 6. 아이콘

**임시 아이콘으로 등록했다(2026-10-30 사람).** 단색 원 + 글자. 나중에 정식 아이콘으로 바꾼다(디자인 담당 제작 목록에 올릴 것 — `docs/PENDING.md`).

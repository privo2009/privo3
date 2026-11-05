# 튜닝 안내 — 혼자 값을 바꾸고 결과를 보는 법

문서 갱신: 2026-11-01 (지시서 #20 — 일일 보상표 · 리미티드 m · 코드 목록 · 안전층 여유 · 날짜 넘겨 보기)

이 문서는 **사람(희준)용 한 장**이다. 값을 하나 바꾸고, Play 한 번으로 결과를 읽고, 되돌리는 순서를 적는다.
⚠️ 여기에는 **수치를 적지 않는다.** 지금 값은 언제나 Config 파일이 원본이다(복사본은 반드시 어긋난다 — CLAUDE.md "문서").
"무엇이 무엇을 움직이는가"의 원본은 `DESIGN.md` "4-2-f 튜닝 지도"다. 이 문서는 그 지도를 손으로 따라가는 순서다.

---

## 1. 값을 바꾸는 순서 (매번 이대로)

```
1  어느 손잡이인지 고른다          아래 "2. 손잡이 목록"에서 파일 · 값 이름을 찾는다
2  VS Code에서 그 값만 바꾸고 저장  한 번에 하나만. 둘을 같이 바꾸면 무엇이 움직였는지 모른다
3  Rojo 반영 확인                  Studio에서 그 스크립트를 열어(또는 검색해) 바꾼 숫자가 보이는지 본다. 몇 초 늦을 수 있다
4  플래그 켜고 Play                Server/Bootstrap.server.lua의 BALANCE_SUMMARY_ENABLED = true → 저장 → Rojo 확인 → Play
5  요약 읽기                       출력 창에서 [BALANCE] 줄(30줄 안팎, Play 시작 10~20초 뒤). 아래 "3. 요약 읽는 법"
6  플래그 끄기                     BALANCE_SUMMARY_ENABLED = false로 되돌리고 저장. 켠 채로 두면 매 Play가 느려진다
7  마음에 안 들면 값을 되돌린다     원래 값은 git이 기억한다(VS Code 소스 제어 → 그 파일 → 변경 취소)
```

- 요약은 **시뮬레이터**다(200명 가상 플레이어 · 같은 seed). 실제 계정 데이터를 읽지도 쓰지도 않는다
- 같은 값이면 언제나 같은 숫자가 나온다(seed 고정). 값이 바뀌지 않았는데 숫자가 바뀌면 Claude에게 알린다
- 성공률은 몇 %p씩 출렁인다(같은 seed라도 한 사람의 경로가 갈라지면 뒤가 다 바뀐다). **3%p 안쪽 차이는 소음으로 본다**
- 더 자세히 보고 싶으면 같은 자리의 다른 플래그: `SUCCESS_RATE_REPORT_ENABLED`(성공률 전부) ·
  `STANDARD_PATH_REPORT_ENABLED`(시간 축 · 층별 체류) · `HP_CANDIDATE_REPORT_ENABLED`(HP 후보 여러 개 — 수 분 걸린다)

## 2. 손잡이 목록

표기: **파일 · 값** / 움직이는 것 / 같이 볼 것 / 건드리면 안 되는 관계(어기면 Play 시작 때 validate가 에러로 막는다)

**HP 성장률 3값** — `Shared/Config/WorldConfig` 월드 1 `hpGrowthSegments`의 `growth` 세 개(1~8 · 9~16 · 17~25층)
- 움직이는 것: 그 구간 성공률(가장 크게) · 25층 도착 시간 · 환생 횟수
- 같이 볼 것: 구간 성공률 3개 · 목표 밖 층 · 절벽 판정 · 아우라 / 펫 한도 여유(HP 후보 도구)
- 관계: 각 값 > 보상 성장률(곡선 규약 1 — validate가 층마다 검사) · 1 < 2 < 3 순서 유지 · 구간 경계(층 번호)는 바꾸지 않는다

**아우라 m** — `Shared/Config/AuraConfig` `LADDER`(팩 1의 일반 → 전설) · `PACK_RATIO`(팩 사이 배율)
- 움직이는 것: 클릭 힘과 1펀치 데미지 둘 다(데미지에는 제곱으로 듣는다) → 전 구간 성공률 · 25층 시간
- 같이 볼 것: 1~8층 성공률 · 25층 중앙값 · 아우라 분포 줄
- 관계: 사다리는 오름차순 · **팩 N 최저 m > 팩 N−1 최고 m**(G4 — validate)

**펫 m** — `Shared/Config/PetConfig` `LADDER`(알 1의 일반 → 전설) · `EGG_RATIO`(알 사이 배율)
- 움직이는 것: 클릭 힘 한 자리(데미지에는 안 들어간다) → 25층 시간 · 환생 횟수
- 같이 볼 것: 펫 배수 중앙값 · 25층 중앙값 · 환생 횟수(펫이 강하면 환생을 덜 한다)
- 관계: 사다리 오름차순 · **알 N 최저 m > 알 N−1 최고 m**(validate)

**강화 배율 CRAFT_FACTOR** — `PetConfig.CRAFT_FACTOR` (황금 · 다이아 · 무지개가 기본의 몇 배씩인가)
- 움직이는 것: 강화한 펫의 힘(단계마다 곱해진다) → 후반 25층 시간
- 같이 볼 것: 펫 배수 중앙값 · 장착 펫 단계 분포
- 관계: 1보다 커야 한다

**칭호 배수** — `Shared/Config/TitleConfig` `Titles`의 `mult`(초보자 → 신화)
- 움직이는 것: 클릭 힘과 수령 블럭스 둘 다
- 같이 볼 것: 칭호 분포 줄 · 전 구간 성공률
- 관계: 초보자(폴백)는 언제나 1.0 · 등급이 오를수록 커져야 한다(validate)

**업그레이드 3종** — `Shared/Config/UpgradeConfig` `punchDamage` · `punchSpeed` · `bloxGain`의
`maxLevel` · `baseCost` · `costGrowth` · `effectPerLevel`
- 움직이는 것: 펀치 데미지 → 후반 성공률(가장 크다) / 펀치 속도 → 딜 총량 / 블럭스 획득 → 환생 · 뽑기 예산
- 같이 볼 것: 17~25층 성공률 · 25층 시간
- 관계: 효과는 레벨에 **더하기**만(곱하기 금지 — S1) · 노출 항목의 `costGrowth` > 1 · 펀치 속도 레벨당 증가량은 적지 않는다(자동 계산 — S2)

**패드 시작 파워** — `WorldConfig` 월드 1 `clickPadSet.basePower`
- 움직이는 것: 모든 패드의 클릭 힘이 같은 비율로 → 초반 속도 · 1층 걸리는 시간
- 같이 볼 것: 1~8층 성공률 · 표준 경로 25층 도달 분
- 관계: 0보다 커야 한다

**운동기구 배수** — `Shared/Config/GymConfig` `TIERS`의 `multiplier`
- 움직이는 것: 막혔을 때 기구에서 올리는 힘 → 환생 사이 정체 시간
- 같이 볼 것: 환생 횟수 · 25층 시간
- 관계: 각 배수 > 1 · 뒤 기구가 앞 기구보다 커야 한다 · 공허(로벅스)가 가장 크다(validate)

**워프 가격** — `Shared/Config/WarpConfig` 상단 `TEMP_COST_BASE` · `TEMP_COST_RATIO`
- 움직이는 것: 워프를 쓰는 사람의 시간. 표준 플레이어는 워프를 안 쓰므로 요약 숫자는 거의 안 움직인다
- 같이 볼 것: `SUCCESS_RATE_REPORT_ENABLED`의 "워프 비교" 줄
- 관계: 비용과 정확히 같은 블럭스로 워프할 수 있어야 한다(validate)

**뽑기 비용** — 칭호 `TitleConfig.ROLL_COST` · 아우라 팩 `AuraConfig`의 `rollCost`(팩마다) · 펫 알 `PetConfig.EGG_COST_EXPONENTS`
- 움직이는 것: 같은 예산으로 굴리는 횟수 · 팩 / 알이 열리는 시점(해금 = 누적 블럭스 ≥ 1회 비용)
- 같이 볼 것: 뽑기 분포 줄 · 25층 시간
- 관계: 뒤 팩 / 알이 앞보다 비싸야 한다(validate) · 블럭스를 로벅스로 파는 상품은 만들지 않는다(CLAUDE.md 금지 사항)

**일일 보상표(TEMP)** — `Shared/Config/DailyRewardConfig` `DAYS`(1 ~ 7일, 지시서 #20 D3)
- 움직이는 것: 매일 들어오는 사람의 포션 · 블럭스 · 7일째 리미티드 펫. 블럭스 칸은 `bloxScaled{k}` = 그 사람 최고층 1회 기본 보상 × k(블럭스 배수는 안 곱한다)
- 같이 볼 것: 창 칸 글자(Play에서 그대로 보인다) · 포션 보관함 수(상점 로벅스 탭 "포션")
- 관계: 7칸 · 7일째는 리미티드 펫 1마리 · 행운 포션 금지 · 포션 개수 1 ~ 99 · k > 0(validate). 랜덤 보상은 넣지 않는다(D3)

**리미티드 펫 m(TEMP)** — `Shared/Config/PetConfig` `LIMITED_MULT`(시작값 1.96 = 알 2 전설, D4)
- 움직이는 것: 7일을 채운 사람의 펫 힘(장착하면 실효 증가분 m − 1 · 강화하면 CRAFT_FACTOR배)
- 같이 볼 것: 펫 창 상세 "Power +…" · 알 사다리와의 차이
- 관계: m ≥ 1 · 리미티드 id는 어느 알 확률표에도 없다(validate). 알 간 규칙의 대상이 아니다

**코드 목록(TEMP)** — `Shared/Config/CodesConfig` `Codes`(지시서 #20 C1 · C5)
- 추가: 키 = 대문자 · 공백 없는 코드(예 `SUMMER2027`), `rewards` = 위 보상표와 같은 꼴, `expiresAt` = UTC 초(없으면 무기한)
- 관계: 키가 정리된 꼴이 아니면 · 보상 형식이 틀리면 validate가 막는다. 받은 기록은 계정당 1회(프로필) — 코드를 지워도 기록은 남는다
- RELEASE(힘 포션 2 + 데미지 포션 2)는 임시다. 실제 목록 · 알릴 곳은 Phase 9(docs/PENDING.md)

**자동 진행 안전층 여유** — `Shared/Config/AutoAdvanceConfig` `SAFE_TIME_RATIO`(0.9, 지시서 #20 S15)
- 움직이는 것: 자동 진행 창의 "안전층"(20초 딜 총량의 시간 항에 곱한다). 1에 가까울수록 안전층이 높고 경계 층 실패가 잦다
- 같이 볼 것: 튜닝 요약 자동 진행 줄(D는 이 값을 넣은 딜 총량) · 프리셋 안전층(여유 전 → 후: before_first_rebirth 8 → 7, 나머지 그대로)
- 관계: 0 초과 1 이하(validate)

**근처 확인 여유** — `Shared/Config/ProximityConfig` `REACH_STUDS`(6) · `LAG_SEC`(0.25) → `PROXIMITY_MARGIN` = 6 + 최고 속도 × 0.25(지금 26, 지시서 #23 N1)
- 움직이는 것: 게이트 · 수령 발판 · 진행 벽 · 클릭 패드의 Touched를 받아 주는 거리(파트 크기/2 + 여유). 넓히면 순간 이동 이득이 커지고 좁히면 정상 플레이 거부가 생긴다
- 같이 볼 것: Play 로그 `[Proximity] 거부 site=… reason=far dist=…`(정상 플레이에서 0이어야 한다). 최고 속도는 `LevelConfig.getMaxWalkSpeed()`가 발판 깊이에서 정한다 — 숫자로 적지 않는다
- 관계: 0 초과 유한(validate) · 여유 − REACH ≥ 최고 속도 한 프레임(30fps) × 6 · 10fps 한 프레임 이동 + REACH ≤ 여유(ProximityTests가 잰다)

**분석 이벤트 상한 · 모아 보내기** — `Shared/Config/AnalyticsConfig` `PER_PLAYER_PER_MINUTE`(20) · `WINDOW_SEC`(60) · `FLUSH_SEC`(30) · `ECONOMY_SAFE_MAX`(1e15)(지시서 #23 A1 · A2 · A4)
- 움직이는 것: 플레이어 한 명이 분당 보내는 분석 이벤트 수(넘치면 버리고 `[Analytics] 상한 초과` 로그) · 블럭스 흐름을 모아 보내는 간격 · 경제 이벤트 대신 `blox_flow_large`로 가는 기준
- 같이 볼 것: Play 로그 `[Analytics] economy … → ok` · `[Analytics] custom … → ok`(Studio에서만 성공 줄). 대시보드 차트는 보통 24시간 뒤(공식 event-types)
- 관계: 상한 1 ~ 20(공식 분당 120 + 20 × CCU 안 — validate) · ECONOMY_SAFE_MAX ≤ 2^53. 블럭스 흐름표(`BLOX_FLOWS`)에 없는 reason은 보내지 않는다 — 새 재화 사용처를 만들면 표에 한 줄 더한다

## 3. 요약 읽는 법 ([BALANCE] 줄)

```
조건 · 모델 · HP 성장률     어떤 값으로 잰 숫자인지. 값을 바꿨는데 여기가 옛 값이면 Rojo 반영이 안 된 것이다
성공률 3줄 + 목표 밖 층     목표: 1~8층 95% 이상 · 9~16층 65~85% · 17~25층 40~55%(±10%p까지 허용). "⚠️ 밖"이면 그 구간 손잡이를 본다
층별%                       25층 각각의 첫 도달 성공률. 한 층만 튀면 그 층 앞뒤 경계를 본다
25층 첫 진입 중앙값 · 환생   가운데 사람이 25층에 처음 들어간 시각(분)과 그때까지 환생 횟수
레벨 상한                    이동 속도가 최대(80)에 처음 닿는 시각 · 층. 그 뒤로는 레벨 숫자만 오른다
표준 경로                    클릭 6 · 8 · 10회/초 결정론 플레이어의 25층 도달 분(이론 상한 — 실제는 더 늦다)
뽑기 분포                    25층에 처음 들어갈 때 장착한 칭호 · 아우라 · 펫 단계
절벽 판정                    16→17층(본 경계)과 8→9층(대조군)에서 머문 시간이 이웃의 2배 이상이면 "절벽 실재"
자동 진행(안전층 반복)        #18 AA14 — 프리셋 floor9 · floor17 · floor25(그 시각 중앙값 플레이어)마다 두 줄
                             "자동": D(20초 딜 총량) · 안전층(= 목표) · 런당 수령 · 런 길이 · 분당 — 클릭하지 않는다
                             "손": 같은 상태에서 손 플레이 모델 200런 평균 수령 · 런 길이 · 분당 · 최고층 중앙 · 실패 % → 자동/손 분당 비율
                             비율이 1보다 크면 자동이 손 모델보다 빨리 번다(손 모델은 위험층에 들어가 실패 0을 받는다)
```

자동 진행 줄의 손잡이 — `Shared/Config/AutoAdvanceConfig`(게임 수치가 아니라 진행 간격 · 서버 루프 값)
```
ADVANCE_DELAY_SEC 0.6       층을 깬 뒤 다음 층으로 넘기기까지(AA2 — 1초 이하). 런 길이에 (안전층 − 1)번 들어간다
REPEAT_DELAY_SEC  3         수령 · 실패 뒤 다음 런까지(AA4). 런 길이에 한 번 들어간다
LOOP_SEC 0.1 · REQUEST_MIN_INTERVAL_SEC 0.5   서버 루프 주기 · 요청 간격(튜닝 줄에는 안 나온다)
```
안전층 식(AA5)은 `Shared/AutoAdvanceLogic.safeFloor` — D = 1펀치 데미지 × 초당 펀치 × 20초, 1층부터 연속으로 총HP(N) ≤ D인 최고 N.
1펀치 데미지 · 초당 펀치는 업그레이드 · 아우라(위 손잡이)가 움직인다 — 그 손잡이를 바꾸면 안전층도 따라 움직인다.

## 4. 테스트 프리셋 — 그 시점 상태로 바로 시작하기 (Studio 전용)

25층을 직접 보려고 40분을 다시 할 필요가 없다. 가상의 프로필로 그 시점에서 시작한다.

```
1  Server/Bootstrap.server.lua 위쪽 TEST_PRESET = nil 을 이름 하나로 바꾼다   예) local TEST_PRESET: string? = "floor17"
2  저장 → Rojo 반영 확인 → Play
3  출력에 "[TestPreset] ⚠️ 프리셋 ... Mock 프로필로 시작한다"가 보이면 성공
4  끝나면 반드시 nil 로 되돌린다(켠 채로 커밋하면 테스트 한 줄이 실패해서 알려 준다)
```

| 이름 | 시점 | 이럴 때 |
|---|---|---|
| `fresh` | 시작 직후 | 첫 몇 분의 템포 |
| `before_first_rebirth` | 첫 환생 직전 | 환생 창 · 버려지는 양 · 상점에 먼저 쓰기 |
| `floor9` | 9층 첫 도달(그 런을 시작할 때) | 9~16층 구간 체감 |
| `floor17` | 17층 첫 도달 | 17층 경계 · 후반 구간 체감 |
| `floor25` | 25층 첫 도달 | 25층 도전 |
| `floor25_cleared` | 25층을 처음 깬 뒤 | 최종층 벽(열리지 않는다) · 수령 |

- **실제 개발 계정 데이터에는 읽기도 쓰기도 하지 않는다.** Play를 멈추면 프리셋 상태는 사라진다(ProfileStore Mock)
- Studio에서만 켜진다. 라이브 서버에서는 무시되고 경고가 찍힌다
- 값은 시뮬레이터의 가운데 플레이어 상태다. **게임 수치를 바꾼 뒤에는 프리셋도 옛 값**이 된다 — 다시 뽑기:
  `TEST_PRESET_EXPORT_ENABLED = true`로 Play → 출력의 `[PRESET]` 줄을 `Shared/Config/TestPresets.lua`에 붙여 넣는다 → 플래그를 끈다
  (붙여 넣기가 어려우면 Claude에게 "프리셋 다시 뽑아 줘"라고 한다)

### 화면 언어 바꿔 보기 — TEST_LOCALE (Studio 전용, 지시서 #L1)

프리셋과 같은 자리(Bootstrap 위쪽)의 `TEST_LOCALE = nil`을 `"en"` 또는 `"ko"`로 바꾸고 Play하면 그 언어로 보인다.
끝나면 반드시 nil로 되돌린다(LocaleTests 한 줄이 실패해서 알려 준다). 자세히는 `docs/LOCALIZATION.md`.

### 날짜 넘겨 보기 — TEST_DAY_OFFSET · TEST_DAILY_SEED (Studio · 프리셋 전용, 지시서 #20)

일일 보상을 날짜를 기다리지 않고 본다. **TEST_PRESET과 함께일 때만** 켜진다(실제 프로필에 가짜 날짜를 남기지 않는다).
```
TEST_DAY_OFFSET = n        서버 "오늘"(UTC 일 번호)에 n일을 더한다
TEST_DAILY_SEED = { streak = k, daysAgo = d }
                           Mock 프로필이 "d일 전에 k일째까지 받은" 상태로 시작한다(Mock은 Play를 멈추면 사라져 어제 기록이 안 이어지므로)
예) 4일째 보기: OFFSET 3 · SEED { streak = 3, daysAgo = 1 } / 하루 건너뛴 날: SEED { streak = 3, daysAgo = 2 } → 1일로 돌아간다
```
끝나면 둘 다 nil로 되돌린다(DailyServiceTests · TestPresetGateTests 한 줄이 실패해서 알려 준다).

## 5. 바꾼 뒤 깨질 수 있는 곳과 대처

- **Play 시작하자마자 빨간 에러 "…Config: …"** — validate가 위 "관계"를 막은 것이다. 메시지에 어느 값 · 어느 규칙인지 나온다.
  값을 관계 안으로 되돌린다(예: 아우라 팩 2 최저 m이 팩 1 최고 m 이하가 됐다)
- **테스트 줄 "[XxxTests] N passed, M failed"에서 M > 0** — 대부분 테스트는 Config 값을 읽어 비교하므로 값만 바꿔서는 깨지지 않는다.
  깨지면 그 테스트가 숫자를 따로 들고 있는 것이다. 어느 줄이 깨졌는지(출력의 `[FAIL]` 줄)를 Claude에게 넘긴다 — 혼자 테스트를 고치지 않는다
- **TestPresetGateTests의 "TEST_PRESET 커밋 값 = nil" 실패** — 프리셋을 켠 Play에서는 정상이다. 끄면 사라진다
- **요약이 안 나온다** — 30초 기다린다. 1분이 넘으면 출력 창의 빨간 줄을 본다(플래그를 켠 줄이 저장 · Rojo 반영됐는지도 본다)
- 바꾼 값을 채택하려면(커밋): Claude에게 "이 값으로 정했다"고 알린다 — 문서(DESIGN · PENDING) · 프리셋 다시 뽑기 · 테스트 개수 실측을 같이 한다

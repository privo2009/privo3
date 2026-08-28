# 개발 로드맵

문서 갱신: 2026-08-29

## 원칙
- 아래에서 위로 쌓는다. BigNum이 흔들리면 전부 무너진다
- 각 단계마다 검증하고 커밋한다
- 한 단계가 끝나기 전에 다음으로 넘어가지 않는다

---

## 테스트 현황

**테스트 개수는 여기에만 적는다.** Phase 절에는 어떤 파일이 생겼는지만 쓰고
개수는 쓰지 않는다 — 두 군데 적으면 반드시 어긋난다.

전부 Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.

| 파일 | 개수 | 대상 |
|---|---:|---|
| `Tests/BigNumTests.server.lua` | 96 | BigNum 사칙연산·비교·직렬화·정밀도·비율 변환 |
| `Tests/FormatterTests.server.lua` | 33 | 숫자 표기 (접미사, 자릿수) |
| `Tests/ConfigTests.server.lua` | 59 | 모든 Config의 validate + 스모크 |
| `Tests/BlockShuffleTests.server.lua` | 3 | 파괴 순서 결정론적 셔플 |
| `Tests/WarpConfigTests.server.lua` | 31 | 워프 비용 곡선(지수·단조)·순수성·거부 사유 3종 |
| `Tests/AttackConfigTests.server.lua` | 38 | 펀치 속도·판정 반경 파생·경계(이하) ※※ |
| `Data/SchemaTests.server.lua` | 33 | 프로필 스키마 검증 |
| `Data/MigrationsTests.server.lua` | 20 | schemaVersion 마이그레이션·멱등성 |
| `Systems/CurrencyServiceTests.server.lua` | 51 | 재화 단일 게이트·롤백·rebirths |
| `Systems/BlockServiceTests.server.lua` | 30 | 배치·데미지 오버플로우·클리어 |
| `Systems/ChallengeServiceTests.server.lua` | 51 | 타이머·보상 갱신·진입점 거부·source 식별 |
| `Systems/ClickServiceTests.server.lua` | 38 | 입력 위생·초당 상한 윈도우·통지 억제·자동 경로 |
| `Systems/PadServiceTests.server.lua` | 31 | 패드 배치·해금 경계·디바운스·세팅/클램프 |
| `Systems/SpeedServiceTests.server.lua` | 21 | 요청값 클램프·입력 위생·환생 하향·최대치 상승 불변 |
| `Systems/SpeedRequestServiceTests.server.lua` | 32 | 요청 빈도 상한·폐기·로그 억제·응답 payload |
| `Systems/RebirthServiceTests.server.lua` | 66 | 거부 시 부작용 0·순서·누적·부분 실패 ※ |
| `Systems/WarpServiceTests.server.lua` | 73 | 거부 시 차감 0·차감이 런 시작보다 먼저·부분 실패 3종 ※ |
| `Systems/AttackServiceTests.server.lua` | 41 | 반경 밖 미호출·이중 계산 방지·경계(float32 이웃)·방향 독립 |
| **합계** | **747** | |

※ 두 행 다 **헬퍼가 check를 여러 번 부른다.** `RebirthServiceTests`는 7개 check를 묶은
`checkUntouched`를 3번 호출하고(정적 53, 실측 66), `WarpServiceTests`는 3개 check를 묶은
`checkRejectedCleanly`를 거부 케이스마다 부른다. 정적 세기에는 헬퍼 안의 check가 한 번만
잡히고 런타임에는 호출 횟수만큼 돈다 — 어긋나는 것이 **정상**이다.
파라미터화 루프와 같은 구조이므로 이 두 행은 실측만 믿을 것.

※※ **`AttackConfigTests`(38)만 합계에서 역산한 값이다.** 실측으로 받은 것은 총계
747 / 18개 파일 / 0 failed와 `AttackServiceTests` 41이고, 나머지는 직전 실측(667)에
`ConfigTests` +1(`AttackConfig.validate`가 그 파일에 들어갔다 — 아래 ⚠️ 참고)을 더해
남는 값을 이 행에 넣었다. **다음 Play 때 이 파일이 찍는 자기 줄로 38을 확인할 것.**
합계와 행 수는 실측이므로 표 전체가 틀어지지는 않지만, 이 한 행은 아직 눈으로 본 값이 아니다.

최근 갱신: **2026-08-28 Studio Play 런타임 실측.** 747 passed / 0 failed (18개 행).
4-2-e2로 `AttackConfigTests`(38) · `AttackServiceTests`(41) 두 행 추가, `ConfigTests` 58 → 59.

⚠️ `AttackServiceTests`가 32 → 41로 오른 것은 케이스를 늘린 게 아니라 **나눈 것**이다.
경계 검사를 float32 이웃 두 점(반경 바로 아래 = 안 / 바로 위 = 밖)으로 쪼개고 그 파생을
검증하는 3건을 붙였으며, "방향이 아니라 거리만 본다"에 섞여 있던 경계 검사를 떼어내
방향 독립성을 세 축 비교로 따로 세웠다 (→ 4-2-e2 "**[확정됨]** float32 경계").

⚠️ 합계 747은 18개 행을 더한 값이다. **총합을 찍는 스크립트는 없다** —
각 테스트 파일이 자기 줄만 찍는다. 한 행이 통째로 빠져도 로그에는 아무 흔적이 없으므로,
갱신할 때는 반드시 행 수(18)와 합계를 함께 대조할 것.

직전 갱신: 2026-08-28 실측 667 (16개 행).
4-2-e Prompt 2로 `WarpServiceTests`(73) 행 추가.

직전 갱신: 2026-08-28 실측 594 (15개 행).
4-2-e Prompt 1로 `WarpConfigTests`(31) 행 추가, `ConfigTests` 57 → 58.

⚠️ `ConfigTests`가 1 오른 것은 새 케이스를 쓴 게 아니라 `WarpConfig.validate` 한 줄이
그 파일에 들어갔기 때문이다. Config가 늘 때마다 이 행이 같이 오르는 것이 정상이다 —
새 Config를 만들고 이 행이 그대로면 `validate()`가 아무데서도 안 도는 것이다.

직전 갱신: 2026-08-27 실측 562 (14개 행).
4-2-d로 `RebirthServiceTests`(66) 행 추가, `CurrencyServiceTests` 38 → 51.

직전 갱신: 2026-08-26 실측 483 (13개 행). 4-2-d Prompt 1로 `ConfigTests` 30 → 57.

⚠️ 그때 "정적 카운트와 실측이 일치했다"고 적었는데, 그 규칙을 그대로 적용하면 안 된다.
소스의 `check(` 줄 수는 **함수 정의 줄 1개를 포함**하고 **헬퍼 호출 배수를 반영하지 않는다.**
이번에 두 행 다 그 이유로 어긋났다 — `RebirthServiceTests` 53→66(헬퍼 3회 호출),
`CurrencyServiceTests` 52→51(정의 줄). 규칙은 여전히 **실측만 표에 올린다**이다.

직전 갱신: 4-2-c Prompt 3 완료분으로 `SpeedRequestServiceTests`(32) 행을 추가해 424 → 456.

⚠️ 이 행도 정적 카운트가 어긋났다 — 소스의 `check(` 호출은 30이었고 실측은 32다.
**세 번째다.** 정적 추정값을 표에 올리지 말고, 올렸으면 다음 Play에서 반드시 갈아끼울 것.

직전 갱신: 2026-08-26 Play 실측으로 표의 전 행을 갈아끼움 (393 → 424).

이번 실측으로 드러난 어긋남:

```
ConfigTests    22 → 30   4-2-c LevelConfig 케이스 8개 (정적 카운트와 일치)
SchemaTests    31 → 33   ⚠️ 이번 작업과 무관하게 표가 2 뒤처져 있었다
SpeedServiceTests   21   신규 행 (정적 카운트와 일치)
합계          393 → 424
```

⚠️ 직전 갱신에서 예상한 합계는 422였고 실측은 424였다. 어긋난 2는
`SchemaTests`에서 나왔다 — 그때 세지 않고 08-22 값을 그대로 둔 6개 파일 중 하나다.
**세지 않은 행이 곧 어긋나는 행이다.** 다음에도 일부만 세고 나머지를 물려받지 말 것.

직전 갱신: 4-2-b 완료분 반영으로 `ClickServiceTests`(38) · `PadServiceTests`(31)
두 행을 추가해 317 → 393 (당시 정적 카운트).
그 직전: source 인자 추가 작업으로 ChallengeService 38 → 51.

자동 테스트가 없는 것:
- `Effects/ChunkBreaker` 등 클라 시각 연출 — `ChunkBreakerDemo.client.lua`로 육안 확인
- `Tests/CurveReport.server.lua` — pass/fail을 세지 않는 **리포트**다.
  커브 수치를 눈으로 검산하는 용도이고, 커브의 계약 검증은
  `WorldConfig.validate()` / `StageConfig.validate()`가 맡는다 (→ ConfigTests에 포함)

---

## Phase 0 — 환경 ✅ 완료
```
Aftman / Rojo 7.7.0 / Wally 0.3.2 / Git / VS Code
Studio 플러그인 + 동기화 검증
ProfileStore (서버 전용)
프로젝트 구조 + .gitignore
```

### 작업 시작 루틴
```
1. cd C:\privo\privo3 → rojo serve
2. Studio → Plugins → Rojo → Connect
3. code .
```

---

## Phase 1 — 기반 (코드) ✅ 완료

### 1-1. BigNum
`src/shared/BigNum.lua`

```
new / fromNumber / normalize
add / sub / mul / div / pow
compare (lt, lte, eq, gt, gte)
serialize / deserialize  ({m,e} ↔ 저장 형태)
```

**검증**: 테스트 케이스 필수
- 10^2000 곱셈 후 정밀도 유지
- 정규화 (m은 항상 1.0 ≤ m < 10)
- 0과 음수 처리
- 직렬화 왕복 일치

**결과**: `BigNumTests.server.lua` (개수 → "테스트 현황")

### 1-2. Formatter
`src/shared/Formatter.lua`

```
format(bignum) → "1.23Qa" / "4.56ab" / "7.89AB"
tier = floor(e/3)
tier 0~10  → 고정 테이블 (K M B T Qa Qi Sx Sp Oc No)
tier 11~   → 알파벳 계산
```

**검증**: 경계값 (10^32/10^33, 10^2058/10^2061)

**결과**: `FormatterTests.server.lua` (개수 → "테스트 현황")

### 1-3. Config 골격
`src/shared/Config/`
```
StageConfig / UpgradeConfig / ShopConfig
AuraConfig / TitleConfig / PetConfig / WorldConfig
```
값은 임시. 구조만 확정.

**결과**: `ConfigTests.server.lua` (개수 → "테스트 현황")

**다음**: Phase 2 — 데이터 계층

---

## Phase 2 — 데이터 계층 (코드) ✅ 완료

### 2-1. Schema + ProfileManager
```
src/server/Data/Schema.lua
src/server/Data/ProfileManager.lua
src/server/Data/Migrations.lua
```

**검증**:
- 접속 → 데이터 생성 → 나가기 → 재접속 시 복원
- BigNum 필드 왕복
- 강제 종료 시 데이터 무손실

**결과**: `SchemaTests.server.lua`, `MigrationsTests.server.lua` (개수 → "테스트 현황")

### 2-2. CurrencyService
`src/server/Systems/CurrencyService.lua`

모든 재화 증감의 단일 통로. 여기서 검증과 로깅.

**결과**: `CurrencyServiceTests.server.lua` (개수 → "테스트 현황")

---

## Phase 3 — 코어 루프 (코드 + 에셋) ✅ 완료

### 3-1. 블록 (서버) ✅ 완료
```
src/server/Systems/BlockService.lua
src/shared/BlockShuffle.lua (서버/클라 공유 파괴 순서 셔플)
```
HP 관리, 데미지 오버플로우(블록 하나를 부수고 남은 데미지가 다음 블록으로 흘러감,
DESIGN.md "2. 블록 → 데미지 오버플로우" 참고), 클리어 판정, 시드 생성

**결과**: `BlockServiceTests.server.lua`, `BlockShuffleTests.server.lua` (개수 → "테스트 현황")

### 3-2. 블록 (클라) ✅ 완료
```
src/client/Effects/ChunkBreaker.lua
src/client/Effects/ParticlePool.lua
src/client/Effects/ChunkBreakerDemo.client.lua (임시 데모, RemoteEvent 붙으면 삭제)
```
파편 상한 200, 풀링 필수, 물리 금지 — 전부 반영됨.

**결과**: 자동 테스트 없음(클라 시각 연출). `ChunkBreakerDemo.client.lua`로 Studio Play에서 육안 확인.

### 3-3. 챌린지 ✅ 완료
`src/server/Systems/ChallengeService.lua`
20초 타이머(서버 권위), 스테이지 진행, 보상 갱신, 실패 처리

**결과**: `ChallengeServiceTests.server.lua` (개수 → "테스트 현황")

### 3-4. 블록 모델 ✅ 완료 (도구)
`src/server/Tools/BlockModelGenerator.lua` — 격자 큐브 블록 모델 생성기(개발 도구).
재질 프리셋(나무/돌/철/크리스탈/용암/우주)은 임시 색상, 디자인 담당이 교체.

**검증**: 블록을 부수고 다음 스테이지로 갈 수 있다

### 3-5. 밸런싱 튜닝 — Phase 3에서 하지 않았다 (Phase 4 이후로 이월)

Phase 3 계획에는 "실제 성공률 데이터를 보고 튜닝"이 있었지만 **실제로는 안 됐다.**
현재 들어간 25층 곡선(`WorldConfig`)은 레퍼런스 실측 기반 **후보값**이다.

튜닝이 Phase 3에서 불가능했던 이유:

```
HP 곡선만으로는 "20초 안에 깰 수 있는가"를 판단할 수 없다.
성공률 p = f(플레이어 힘, 스테이지 총HP, 20초)
        └─ 이 항이 아직 없다
```

힘 성장(클릭 파워 패드 + 환생 배수)이 없으면 분자가 비어 있어서
성공률을 잴 수 없고, 성공률이 없으면 정지선(37%)이 어느 층에
걸리는지도 모른다. 곡선 규약(→ `DESIGN.md` 1. 챌린지)은 이미 만족하므로
구조는 맞지만, 수치가 맞는지는 아직 아무도 모른다.

**실측 튜닝은 Phase 4-2-f**에서 한다. 그때 볼 것:
- 층별 실제 성공률 — 정지선 37%가 몇 층에서 걸리는가
- 유저가 실제로 멈추는 층 vs 기댓값상 멈춰야 하는 층
- 25층 도달까지 걸리는 시간

**다음**: Phase 4 — 성장

---

## Phase 4 — 성장

설계(4-1)와 구현(4-2)을 나눈다. 설계가 끝나고 코드로 넘어가는 경계다.

### Phase 4-1 — 성장 설계 ✅ 완료

```
환생        전액 소모 + 버림. floor(blox/1000)만큼 rebirths 가산.
            블럭스 → 0. 힘 → 초기화. maxStage → 초기화
rebirths    저장한다. 파생값 아님 (소모라 역산 불가)
maxStage    환생 시 리셋. 드론 전용. 워프는 참조하지 않음
워프        전 구간 유료. 진행 상태 무관한 순수 함수
레벨        힘의 지수 기반. 레벨당 최대 이동속도 +1
커스텀스피드  저장 안 함. 접속·환생 시 최대로 리셋. 서버 검증 필수
클릭패드     월드별 세트 + 세트 내 lifetimeBlox 순차 해금.
            파워 2배씩 / 조건 3배씩. 월드 첫 패드는 조건 0
월드 1       25층. 클리어 시 자동 전환.
            다음 월드 없으면 진행 벽 막힘 (정식 동작)
커브         HP 세그먼트 3.0/4.0/7.0, 보상 고정 2.7. 정지선 37%
목표 성공률   구간별 95% / 65~85% / 40~55%
```

⚠️ 이 목록은 "무엇이 결정됐는지"의 색인이다.
   수치와 근거의 원본은 `DESIGN.md` — 여기로 복사하지 말 것.

### Phase 4-2 — 성장 구현 (코드)

착수 순서대로. 앞이 뒤의 선행 조건이다.

```
a  진입점 배선          ◐  서비스 쪽만. 3D 파트 배선 미착수
a2 블록 렌더링 클라 이관 ✅
b  클릭 파워 패드        ✅
c  레벨 + 커스텀 스피드  ✅
d  RebirthService       ✅  2026-08-27 Play 검증 (잔여 1건 — 아래 참조)
e  WarpService          ✅  2026-08-28 Play 검증
e2 근접 자동 공격        ✅  2026-08-28 Play 검증 (747 passed / 0 failed)
f  실측 튜닝            ✗  미착수 ← 다음. **선행 조건 해소됨**
```

⚠️ `a`가 ◐인 이유: `cashout()` · `advance()`는 완성됐지만 그것을 **부르는 3D 파트가
없다.** `Touched → cashout/advance` 연결이 코드 어디에도 없고, `PadService`의 `Touched`는
클릭 파워 패드 전용이다. 수령 발판·진행 벽 파트는 디자인 담당 에셋 대기 중이다
(→ `docs/UI_ASSET_SPEC.md` "5-1. 수령 발판 · 진행 벽 — 최소 깊이").
d·e의 "진입점 없음"과 같은 상태이며, 셋 다 Phase 6 UI 또는 파트 작업에서 함께 붙는다.

각 항목의 **[착수 전 확정]** 은 설계가 덜 끝난 부분이다. 지금은 근거가 없어
정할 수 없고, 해당 모듈 구현 직전에 정한다. 미리 찍어두면 근거 없는 수치가
코드에 박힌다.

#### 4-2-a. 진입점 배선 [선행 조건]

수령·진행이 화면 UI 버튼이 아니라 3D 오브젝트이므로
(`DESIGN.md` "1. 챌린지 > 선택 방식"), 진입점이 서버 측 Touched/판정이 된다.

```
발판 Touched → ChallengeService.cashout(player, source)
벽 통과      → ChallengeService.advance(player)
```

- 서버 런 상태(`run.cleared`)로 판정. Touched는 신호일 뿐 권한이 아니다
- 런당 1회 처리 보장 (`run.settled` 플래그, 발판·벽 공유)
- ~~`ChunkBreakerDemo`를 대체할 서버→클라 RemoteEvent 배선~~ ✅ **완료**
  — `src/client/Net/RemoteReceiver.client.lua`가 존재하고 동작한다.
  2026-08-28 Play 로그에 `RunStateChanged` 수신이 찍혔다.
  ⚠️ 배선이 끝났다고 `ChunkBreakerDemo`가 지워지는 것은 아니다 —
  3-2에 자동 테스트가 없어 그 파일이 **클라 연출의 유일한 육안 확인 수단**이다
  (→ `docs/PENDING.md` 잔재)

⚠️ `cashout()`은 Touched 없이도 호출 가능해야 한다.
   자동 수령 게임패스와 자동 진행 모드가 나중에 직접 호출한다.

**[확정됨]** 자동 진행은 캐릭터를 이동시키지 않는다. 서버가 `advance()`를
직접 호출한다. 목표층은 유저가 지정하고 시스템은 안전선만 제시한다.
근거와 상세 → `DESIGN.md` "1. 챌린지 > 자동 진행 모드"

#### 4-2-a2. 블록 렌더링 클라 이관 ✅ 완료

블록이 전원 같은 좌표에 서서 2인 이상이면 겹치는 문제를 푼다.

**원래 "개인 구역(플레이어별 월드 공간)"으로 잡혀 있었다. 그 방향을 폐기했다.**

레퍼런스 실측에서 다른 해법이 나왔다 — 스테이지는 전원이 공유하고, 다른 플레이어의
캐릭터는 보이지만 **그가 부수는 블록은 아예 보이지 않는다.** 각자 자기 블록만 본다
(→ `DESIGN.md` "11. 레퍼런스 출처 > 측정 범위").

그래서 서버가 블록 모델을 만들지 않고 각 클라가 자기 것만 만든다. 얻은 것:

```
서버 블록 파트   30명 × 7블록 × 64큐브 = 13,440 → 0
구역 배정·칸막이·좌표 오프셋   전부 불필요
블록 좌표        원점 고정 그대로 (겹칠 대상이 없다)
4-2-a 배선       안 뜯음 (패드·수령 발판·진행 벽은 공용)
```

패드 해금 상태는 `lifetimeBlox` 기반 개인값이므로 서버가 Touched 시점에 판정한다.
파트는 한 세트뿐이라 개인 구역이 필요 없다.

- `Shared/BlockLayout.lua` 신설 — `computeLayout`이 서버에 있으면 클라가 좌표를 못 구한다.
  좌표를 전송하지 않고 양쪽이 `count` 하나로 각자 계산한다
- `Shared/BlockModelBuilder.lua` 신설 — 순수 생성 로직. 템플릿 위치가
  `ServerStorage` → `ReplicatedStorage.BlockModels`로 이동(클라는 ServerStorage를 못 본다)
- `Server/Systems/BlockSpawner.lua` 삭제 — 서버가 모델을 안 만든다
- 시드 전달은 `RunStateChanged` payload에 `seeds` 추가 (채널을 늘리지 않았다.
  근거는 `Shared/Remotes.lua`의 payload 주석)

번호를 a와 b 사이에 끼운 이유: 4-2-a에서 드러났고 4-2-b의 선행 조건이라 그 사이가
제자리인데, b~f를 밀면 다른 절의 참조(`Phase 4-2-f` 등)가 같이 어긋난다.

#### 4-2-b. 클릭 파워 패드 ✅ 완료

힘 성장의 주 수단. 이것이 없으면 `RebirthService` 검증이 불가능하다.
`WorldConfig`에 패드 세트 필드(`clickPadSet`)를 추가했다.

**[확정됨]** 파워는 세팅 방식(누적 아님).
수치는 `ClickPadConfig.lua` / `WorldConfig.clickPadSet`,
근거는 `DESIGN.md` "클릭 파워 패드"

⚠️ 시작 파워는 근거가 약한 임시값이다. 4-2-f 튜닝 대상.
⚠️ 선행 조건 4-2-a2는 완료됐다. 블록이 클라 렌더링이 되면서 개인 구역이 불필요해졌고,
   패드도 공용 파트 한 세트로 두고 서버가 Touched 시점에 개인 해금 여부를 판정한다.

**[확정됨]** 선택 패드 저장 방식, 자동 클릭 주기
→ `DESIGN.md` "클릭 파워 패드"

**[확정됨]** 펀치 속도 → **`Shared/Config/AttackConfig.lua`** (정본이 옮겨졌다, `d153228`)

⚠️ 여기서 `DESIGN.md` "클릭 파워 패드"를 가리키지 않는다. 그 절이 펀치 속도를
수동 클릭 상한과 나란히 담고 있는 것은 **문서상의 사고이고 트랙이 다르다:**

```
수동 클릭 상한 10/sec   힘 트랙        오토마우스 방어선 (수익 모델 상수)
펀치 속도      2/sec    블록 공격 트랙  밸런스 값
```

전자는 올리면 자동 클리커 게임패스의 가치가 깎이고, 후자는 20초 안에 총HP를
깎을 수 있는지를 정한다. 성격이 정반대다.
`DESIGN.md` 본문 분리는 `4819ec8`에서 완료됐다 → `DESIGN.md` "펀치와 딜 총량"

#### 4-2-c. 레벨 + 커스텀 스피드 ✅ 완료

`WalkSpeed` 서버 권위 검증.

**[확정됨]** 레벨 = 힘의 지수 (N=1). 최대속도는 상한 클램프.
수치와 근거 → `DESIGN.md` "레벨"

**진행 상태** — 완료 (2026-08-26 Play 검증). `LevelConfig` · `SpeedService` · Remotes 배선.

커스텀 스피드 채널 2개(`SpeedRequest` / `SpeedApplied`)와 수신부
`SpeedRequestService`, 클라 송신부 `SpeedInput`까지 붙었다.
값은 **절대값**이고 **세션 메모리뿐**이다 — 프로필에 저장하지 않으므로
schemaVersion을 올릴 일이 없다 (→ `DESIGN.md` "커스텀 스피드").

⚠️ UI는 없다. Phase 6에서 `SpeedInput.request()`를 부르는 입력칸이 붙는다.
그때까지 요청 경로의 관측 지점은 Bootstrap VERIFY print의 `req=` 필드다.

#### 4-2-d. RebirthService ✅ 완료

**검증**: 환생 후 배수가 정확히 적용된다.

**[확정됨]** 1000 미만 환생은 거부한다(`RebirthConfig.canRebirth`).
거부는 사유 코드 문자열을 반환하고 표시 문구는 UI가 매핑한다 —
이 규약은 4-2-e 워프의 블럭스 부족 거부에도 그대로 쓴다.

**[확정됨]** 환생 배수는 **획득량**에 곱한다(보유 힘 아님).
곱셈은 힘 지급 게이트 한 곳에서만 하고 결합은 `StrengthMultiplier.compute`가 맡는다.
근거 → `DESIGN.md` "3. 화폐와 배수"

**진행 상태** — ✅ 완료 (2026-08-27 Play 검증).
Prompt 1(순수 계층) · Prompt 2(RebirthService 본체) · Prompt 3(Bootstrap 배선).

검증 근거: **REBIRTH_VERIFY 1회 점등 — WalkSpeed 36.0 → 16.0, max와 일치. 배선 정상.**

진입점(3D 파트 · Remote)은 아직 없다. 환생을 부르는 경로는 Bootstrap의
`REBIRTH_VERIFY_ENABLED` 블록 하나뿐이고, 진입점은 Phase 6 UI 또는 별도 파트
작업에서 붙인다 — 지금 만들면 디자인 담당 에셋 명세가 없어 임시 파트가 굳는다.

✅ **`StrengthMultiplier` 배선 — 해소됨.** 2026-08-28 조사에서 발견돼 같은 날
`4fceb7e`에서 배선됐다. 검증 상태의 원본은 `docs/PENDING.md`다 — 여기에 상태를 적지 않는다.

위 **[확정됨]** 계약은 그대로 유효하다 — 배수 적용 지점은 **힘 지급 게이트 한 곳**이고
결합은 `StrengthMultiplier.compute`가 맡는다.

⚠️ **교훈 — 문서가 [확정됨]으로 적은 것과 호출자가 존재하는 것은 다르다.**
`compute`는 계약대로 만들어져 있었으나 호출자가 코드 전체에 0이었다.
`SpeedService.onRebirth`가 호출자 없이 남아 있던 것과 **같은 종류의 사고**이고,
배수가 안 붙어도 힘은 멀쩡히 오르므로 **플레이로는 발견되지 않는다.**
[확정됨]을 근거로 삼을 때는 호출자가 있는지를 함께 확인할 것.

#### 4-2-e. WarpService ✅ 완료

**[확정됨]** 절대 기준 `cost(목표층)`. 현재 위치를 참조하지 않는 순수 함수다.
비용은 지수.

거리 기준을 버린 이유: 거리 기준은 "현재 위치"를 알아야 성립하는데,
워프가 진행 상태를 참조하는 순간 `maxStage`와 얽힌다. `maxStage`는 환생 시
리셋되므로(→ `DESIGN.md` "3. 화폐와 배수 > 환생"), 환생 직후에는 이미 지나온
구간이 "안 가본 구간"으로 보여 워프 비용이 헐값이 된다. 힘은 환생 배수로
세진 상태이므로 진행이 순간적으로 뚫린다.
근거 → `DESIGN.md` "3. 화폐와 배수 > 블럭스 소비처"의
"워프는 진행 상태를 참조하지 않는다" 문단

⚠️ 남은 것은 지수의 밑과 기준값이다. 이건 4-2-f 실측 튜닝 대상이라
지금 정하지 않는다 — 근거 없는 수치가 코드에 박힌다.

**진행 상태** — ✅ 3단계 전부 완료 (2026-08-28 Play 검증).

```
Prompt 1  순수 계층   8f243e2   Shared/Config/WarpConfig.lua + WarpConfigTests
Prompt 2  서비스      76223f6   Server/Systems/WarpService.lua + WarpServiceTests
Prompt 3  배선        04c9dfd   Bootstrap의 WARP_VERIFY 블록 (검증 전용)
```

검증 근거: **차감분 900 = `cost(3)` 일치, 런이 3층에 섬(`cleared=false timeLeft=20.0`).**
클라 `RunStateChanged`가 `stage=3 reward=7.29`로 따라붙었고 이 값이 `CurveReport`의
3층 보상과 일치한다 — **stage 숫자만 바꾼 것이 아니라 목표층의 진짜 런이 섰다는 증거다.**
전체 667 passed / 0 failed 유지(Bootstrap 수정이 다른 VERIFY 블록에 영향 없음).

진입점은 **아직 없다.** 워프를 부르는 경로는 Bootstrap의 `WARP_VERIFY_ENABLED` 블록
하나뿐이고, 목표층은 그 안에 하드코딩(3층)돼 있다. 3D 파트나 Remote는 만들지 않았다 —
진입점은 Phase 6 UI(텔레포트 버튼 → 스테이지 선택창)에 붙인다
(4-2-d 환생과 같은 판단이다).

`cost(목표층)`은 수식이고 `canWarp(보유블럭스, 목표층)`이 정책이다. 범위 밖 층은
`cost`에서 값이 나오고 `canWarp`이 거부한다 — 상한은 숫자가 아니라
`StageConfig.hasStage`를 통해 `WorldConfig`에서 파생되므로 월드 2가 추가되면
코드 수정 없이 상한이 따라 올라간다.

거부 사유 3종(`invalid_stage` · `stage_out_of_range` · `insufficient_blox`)은
`WarpConfig`에 정의한다. 4-2-d와 달리 Config가 사유를 갖는 이유: 워프는 셋 중 둘이
블럭스와 무관하게 stage만 보고 판정되므로, 판정 주체와 사유 이름이 갈라지면
사유를 하나 늘릴 때 두 파일을 고쳐야 한다. Prompt 2의 `WarpService`는 재공개만 한다.

⚠️ **호출자 계약 (Prompt 2에서 지켰다).** `WarpService`는 검증되지 않은 입력에 `cost`를 직접
부르지 않는다. 반드시 `canWarp`을 먼저 통과시키고 그 반환값으로 받은 비용을 쓴다.
목표층은 Phase 6 UI에서 오고 클라가 보낸 값은 전부 검증 대상이다
(CLAUDE.md 절대 규칙 3). `cost`는 nil·소수·0·음수에 `error`를 던지지만
`canWarp`은 같은 입력을 `invalid_stage`로 접는다 —
사유 코드로 접혀야 할 것이 서버 에러가 되면 안 된다.

#### 4-2-e2. 근접 자동 공격 (AttackService) ✅ 완료

**2026-08-28 RC Play 검증 완료. 747 passed / 0 failed (18개 파일).**

검증된 것:

```
힘 → 데미지 경로    실물에서 돈다. dmg = str (5.513000e+3)
                    펀치 속도가 1회 데미지에 곱해지지 않았다 — 이중 계산 없음
timeLeft 동결       처음 관측됐다. 20.0이 아니라 17.9 / 19.9 / 19.8
                    HUGE_DAMAGE 제거로 중간 클리어가 실제로 발생했다
환생 배수           클릭 획득량에 붙는다. mult=1.000000e+1 (rebirths=9)
                    클릭 1회 배치 +80 / 2회 배치 +160 — 배치당 통과 횟수에 비례
판정 반경           동작한다. dist=4.3~6.0 (in), result=ok
배선                초기화 로그와 result 전이(ok → cleared → no_run) 확인
cashout             증가분 = 보상액 일치, 런 종료 확인
```

⚠️ **아직 관측되지 않은 것 — `result=out_of_range`를 실물에서 보지 못했다.**
테스트로는 덮여 있으나 Play에서 캐릭터를 반경 밖으로 걸어나가게 한 적이 없다.
**거리 폴링을 택한 근거 자체**이므로 한 번은 실물 확인이 필요하다 —
반경이 아레나를 덮어버리면 "이름만 거리 폴링인 상시 발동"이 되고, 그것을 가르는 것은
이 로그 한 줄뿐이다. Phase 6 UI 진입 시 또는 다음 Play 기회에 확인한다
(→ `docs/PENDING.md`).

⚠️ **이 작업은 지금까지 어느 Phase에도 배정된 적이 없다.**
4-2-b가 펀치 속도 수치만 **[확정됨]** 으로 정하고 구현 절을 만들지 않았고,
성격상 Phase 3-3(챌린지) 소관이었으나 그때 누락됐다.
2026-08-28 조사에서 4-2-f 착수 불가의 원인으로 드러나 여기에 세운다.

번호가 `e2`인 이유: 4-2-f 앞에 와야 하는데, b~f를 밀면 다른 절의 참조가
같이 어긋난다. 4-2-a2를 a와 b 사이에 끼웠던 것과 같은 처리다.

**힘 → 데미지 경로가 통째로 없다.** `ChallengeService.applyDamage`의 실호출자는
Bootstrap `VERIFY_CHALLENGE` 한 곳뿐이고 넘기는 값은 힘과 무관한 상수다.
하류(`BlockService`의 오버플로우 처리)는 완성돼 있고 **상류만 비어 있다.**

내용:

- 펀치 주기 루프 → **그 시점에 거리 판정** → `힘 × 펀치` → `ChallengeService.applyDamage`
  (순서가 뒤집힌 것은 의도다. 아래 **[확정됨]** 참고)
- `PUNCH_SPEED_BASE = 2` / `PUNCH_SPEED_MAX = 5`를 새 Config로 분리한다.
  현재 `DESIGN.md` 산문에만 있어 하드코딩 금지 규칙(CLAUDE.md "작업 방식")에 걸린다

##### [확정됨] BlockDamaged를 AttackService가 발신하지 않는다 (2026-08-28)

`ChallengeService.applyDamage`가 **이미** `notifyBlockDamaged`를 발신한다(`:284`).
클리어 판정 · `maxStage` 갱신 · `RunStateChanged` 통지도 전부 하류가 이미 한다.
`AttackService`는 "언제 얼마의 데미지를 넣을지"만 정하고 `Remotes`를 require하지도 않는다.

⚠️ **중복 발신은 파편 연출이 두 배로 도는 것으로 끝나지 않는다.**
파편 상한 200개와 오브젝트 풀링이 **실제 파괴량 기준으로** 설계돼 있어서
(CLAUDE.md 절대 규칙 4), 발신이 두 배면 풀이 예상의 절반 지점에서 마른다.
증상은 **"고층에서만 파편이 안 보인다"** 로 나타나고,
원인이 발신 중복이라는 것을 파편 코드에서는 찾을 수 없다.

⚠️ **이 절에는 2026-08-28까지 정반대의 서술이 있었다** —
"`BlockDamaged` 발신도 여기가 맡는다. 수신부와 채널 정의는 이미 있다 —
**발신자만 없는 상태다**". 사실이 아니었다. 발신자는 처음부터 있었고,
없던 것은 `applyDamage`의 **실호출자**였다.
그 문장을 근거로 작업하면 위의 이중 발신을 만들게 되므로 지웠다.
(같은 서술이 다른 절에 복제돼 있지는 않았다 — 문서 전체 검색으로 확인했다)

근거 → `DESIGN.md` "2. 블록 > 공격 방식" — 블록은 근접 시 자동으로 공격되며
클릭 입력이 아니다. **클릭은 힘 트랙 전용이다.** 두 트랙이 원래 별개라는 것이
이 절이 따로 필요한 이유다.

##### [확정됨] 발동 조건 — 거리 폴링 (2026-08-28)

**상시 발동이 아니다.** 캐릭터가 판정 반경 안에 있을 때만 데미지가 들어간다.

⚠️ **거리 체크는 펀치 시점에 수행한다. 별도 폴링 루프를 두지 않는다.**
펀치 속도 2회/초면 0.5초마다 한 번 거리를 재고, 반경 밖이면 **그 펀치를 스킵한다.**

루프를 따로 두면 `SpeedService` 폴링(1.5초)과 주기가 어긋나
**"동결 1초 < 주기 1.5초"와 같은 종류의 타이밍 함정이 다시 생긴다** —
그 함정은 4-2-e에서 워프 동결을 포기하게 만든 바로 그 문제다
(→ `docs/PENDING.md` "워프 후 1초 동결").

##### [확정됨] 판정 반경 — BlockLayout 파생, 층 무관 고정 (2026-08-28)

**층별로 변하지 않는다. 항상 고정이다.** 기준은 최대 배치(블록 16개 이중 원)의
최외곽이며, 여기에 마진을 더한다.

⚠️ **반경 값을 상수로 하드코딩하지 말 것.** `BlockLayout`에서 파생시킨다.
배치가 바뀌면 반경이 따라 움직여야 한다 — 워프 상한을 `WorldConfig`에서
파생시킨 것과 같은 원리다.

마진은 **"표준"** 수준으로 확정했다. 블록 둘레를 한 바퀴 돌아다녀도 유지되고
아레나를 벗어나면 끊기는 정도다.

⚠️ **발판·벽 최소 깊이 8 studs와 숫자가 비슷하더라도 근거가 다르다.**
그쪽은 고속 이동 시 `Touched` 관통을 막으려고 나온 값이고 근접 판정과 아무 관계가 없다.
**두 값은 별개 Config에 두고 서로 참조하지 않는다.**
발판 깊이를 바꿀 때 반경이 따라 움직이면 안 된다.

⚠️ 마진은 파워 1 · `bloxBase = 1`과 **같은 성격의 임시값**이다.
4-2-f 실측 튜닝 대상이다 — 확정값으로 취급하지 말 것.

##### [확정됨] float32 경계 — 정확히 반경인 점은 런타임에 존재하지 않는다 (2026-08-28)

RC Play에서 `AttackServiceTests` 경계 케이스 2건이 실패했고, 임시 프로브로 원인을 확정했다.

```
getRadius() 원본 double   92.799999999999997
Vector3에 넣었다 뺀 값     92.800003051757812
차이                      3.05e-06
isInRange(잰 거리)        false
isInRange(반경 double)    true      ← 판정 함수에는 결함이 없다
```

**Roblox `Vector3` 성분은 float32이고 `AttackConfig.getRadius()`는 float64다.**
반경을 `Vector3`에 넣으면 float32 격자로 올림되어 반경보다 커진다.
즉 **테스트가 런타임에서 표현 불가능한 점을 찍고 있었다** — 코드 결함이 아니었다.
해법은 경계를 **float32 이웃 두 점**(반경 바로 아래 = 안 / 바로 위 = 밖)으로 재정의하는 것.
런타임이 도달 가능한 가장 가까운 두 점이라 "경계는 이하" 계약은 그대로 검증된다.

⚠️ **4-2-f에서 걸릴 함정 — 범인은 마진이 아니라 `OUTER_RING_MULT`다.**
`BLOCK_SPAN × 3.8 = 60.8`의 `.8`이 이진수로 떨어지지 않아 **마진 배율을 무엇으로 바꿔도
반경에 `.8`이 남는다.** 이웃값을 상수로 적었다면 마진을 튜닝할 때마다 이 테스트가
이유 없이 색을 바꿨을 것이다. `getRadius()`에서 파생시켰으므로 **이제 그런 일은 없다.**

⚠️ 검토했으나 택하지 않은 것 — 다시 제안하지 말 것:
제곱 비교(순서를 보존하므로 이 실패를 못 고친다) · 경계를 피하고 안/밖만 재기(검증 축소) ·
`isInRange`에 ε 허용치(`AttackConfig` 상단이 경계하는 "부동소수가 판정을 정하는 자리"를
코드로 들이는 것) · `OUTER_RING_MULT` 조정(테스트를 위해 게임 밸런스를 바꾸는 것).

##### [확정됨] Config 위치 — AttackConfig 신설 (2026-08-28)

펀치 속도와 반경 마진은 **`Shared/Config/AttackConfig.lua`를 신설해** 그곳에 둔다.

⚠️ **`ClickPadConfig`에 얹지 않는다. 두 값은 트랙이 다르다:**

```
수동 클릭 상한 10/sec   힘 트랙       오토마우스 방어선 (밸런스 값이 아니다)
펀치 속도      2/sec    블록 공격 트랙  밸런스 값
```

`DESIGN.md`에서 둘이 나란히 적혀 있는 것은 **문서상의 사고다.**
그 배치를 코드가 따라가면 트랙 구분이 코드에서도 흐려진다.

##### [확정됨] 기존 파일 경계 (2026-08-28)

**`ChallengeService`는 열지 않는다.** `AttackService`가 런 시작·종료를 통지받는 대신
**자기가 런 상태를 읽는다.** `applyDamage` 때문에 어차피 `ChallengeService`를
require하므로 의존이 늘지 않고, Play 검증이 끝난 파일을 건드리지 않아도 된다.

**Bootstrap `VERIFY_CHALLENGE`는 `HUGE_DAMAGE`만 제거하고 런은 유지한다.**
블록을 세우는 것까지만 하고 데미지는 `AttackService`에 맡긴다.

```
통째로 끄면   기존 진입점 검증이 관측 밖으로 나간다
그대로 두면   한 프레임에 전 블록이 사라져 새 공격 경로가 도는지 보이지 않는다
```

이 변경이 `docs/PENDING.md`의 **`timeLeft` 동결 확인**을 비로소 검증 가능하게 만든다.

##### 구현 결과 (2026-08-28)

```
4fceb7e  StrengthMultiplier 배선 (4-2-d 잔여)
d153228  AttackConfig 순수 계층 + BlockLayout.OUTER_RADIUS 노출
0c389d0  AttackService + Bootstrap 배선
```

**판정 반경 92.8 studs (층 무관 고정).** 전부 파생이며 상수로 적힌 곳이 없다:

```
최외곽 링 중심   60.8 = BLOCK_SPAN(16) × OUTER_RING_MULT(3.8)
블록 바깥면      68.8 = 60.8 + BLOCK_SPAN/2      ← 반경 기준점
마진             24.0 = BLOCK_SPAN × 1.5
판정 반경        92.8 = 68.8 + 24.0
```

기준점이 중심이 아니라 **바깥면**인 이유: 마진 값이 "블록 표면에서 걸어나갈 수 있는
거리"로 곧이곧대로 읽혀야 한다. 중심 기준이면 Config에 적힌 24와 실제 여유 16이
`BLOCK_SPAN/2` 만큼 어긋나고, 이 값은 4-2-f에서 손으로 만질 값이라 만질 때마다 암산이 낀다.

⚠️ **마진 배율을 1.0으로 내리지 말 것.** 반경이 84.8이 되어 패드 1 근접 모서리(84.8)와
**정확히 같아진다** — 부동소수 비교가 게임 판정을 정하는 자리가 된다.

**실측 거리** (원점 = 블록 클러스터 중심):

```
패드 1   중심  88.8   근접 모서리  84.8   ← 반경 안. 24개 중 유일
패드 2   중심 100.8   근접 모서리  96.8   ← 여기부터 밖
패드 24  중심 364.8   근접 모서리 360.8
```

패드 24개 중 **23개가 반경 밖이다.** 이것이 마진 1.5를 고른 근거다 — 반경이 아레나를
통째로 덮으면 나갈 일이 없어서 **이름만 거리 폴링인 상시 발동**이 된다.
패드 1만 안인 것은 자연스럽다: `basePower`이고 해금 조건이 0이라
"아무것도 고르지 않은 상태"이므로 거기 서 있는 동안 딜이 유지되는 쪽이 맞다.

⚠️ 수령 발판 · 진행 벽 · 스폰 지점 · 물리적 아레나 경계는 **전부 미배치다.**
그것들이 배치되면 위 실측의 전제가 함께 무너진다 — 배율만 만지지 말고 실측부터 다시 낼 것.

**구조:**

- **클러스터 원점은 월드 원점 `(0,0,0)`이며 스테이지·월드와 무관하다.**
  `BlockLayout`의 `ring()`이 원점 중심으로 좌표를 만들고, `BlockService`가 그 좌표에
  오프셋을 더하지 않고 그대로 블록 위치로 쓴다.
- **루프는 서버 단일 루프다.** `SpeedService`의 주기 검사와 같은 구조를 따랐다 —
  플레이어마다 `task.spawn`을 걸면 나갈 때 각각 멈춰야 하고 한 번 놓치면 코루틴이 남는다.
- **런 상태는 `ChallengeService.getRunState(player)`로 읽는다.** 이미 있던 공개
  함수라 **`ChallengeService`를 열지 않았다** (Play 검증이 끝난 파일이다).
- **`BlockLayout.OUTER_RADIUS`를 노출했다.** `GROUND_Y_OFFSET`과 같은 이유다 —
  쓰는 쪽이 `BLOCK_SPAN × OUTER_RING_MULT`를 자기 파일에서 다시 계산하면
  최외곽 계산 방식을 바꿨을 때 그쪽만 옛 식으로 남는다.
- **`AttackConfig`의 값은 전부 raw number다.** 반경은 `Vector3`가 float이라 BigNum을
  넣을 수 없고, 펀치 속도는 상한 5가 못박혀 커질 수 없다. BigNum이 되는 지점은
  `힘 × 펀치 데미지`이고 그건 `AttackService`의 몫이다.

**데미지 정의 — 1펀치당 `힘 × 1회분`이다. 초당 환산이 아니다.**

⚠️ **펀치 속도는 주기를 정할 뿐 1회 데미지에 곱해지지 않는다.** 초당 총 데미지가
`힘 × 펀치속도`가 되는 것은 그 횟수만큼 불리는 결과다. 여기서 한 번 더 곱하면
**이중 계산**이 되어 실제 DPS가 속도의 **제곱**에 비례하고, 4-2-f 성공률 계산이
통째로 틀어진다. `AttackServiceTests`가 이 회귀를 잡는다 — 그 케이스를 지우지 말 것.

**`HUGE_DAMAGE` 제거.** 선언·사용 각 1곳뿐이었고 둘 다 없앴다.
`VERIFY_CHALLENGE`는 런을 세우고 블록 개수를 찍은 뒤 3초 기다렸다가 클리어 여부를 본다.
통째로 끄지 않은 이유는 `startRun`·`getSnapshot`·`cashout` 검증이 관측 밖으로 나가기
때문이고, 그대로 두지 않은 이유는 한 프레임에 전 블록이 사라져 새 공격 경로가 도는지
보이지 않기 때문이다. ⚠️ 캐릭터가 반경 밖이면 **클리어 실패로 빠지는 것이 정상이다.**

**Bootstrap `[ATTACK]` 관측 print** (상시 유지. `req=`·`last=`와 같은 성격):

```
[Bootstrap][ATTACK] <이름> result=ok dist=12.3/92.8 (in) dmg=5.00e3 mult=5 str=5.00e3
```

결과 코드가 바뀔 때만 찍는다 — 초당 2회를 그대로 찍으면 다른 로그가 묻힌다.
RC에서 "딜이 안 들어간다"의 후보 넷을 이 한 줄이 가른다:

```
mult= 이 1인데 환생을 했다   → StrengthMultiplier 경로
result=out_of_range          → 캐릭터가 멀리 있다 (정상일 수 있다)
줄 자체가 안 찍힌다          → AttackService.init 배선
result=no_changes            → 하류가 거부했다
```

서비스와 배선이 한 커밋에 있어 **되돌릴 단위가 없었기 때문에** 당시 배선 전체를
`ATTACK_WIRING_ENABLED`(기본 `true`)로 감쌌다. RC 검증으로 존재 이유가 사라져
`d276e95`에서 **플래그와 분기만** 제거했고 배선 자체는 남아 있다.
(왜 감쌌는가는 다음 미검증 레이어를 어떻게 다룰지의 근거가 된다)

#### 4-2-f. 실측 튜닝

✅ **착수 가능 (2026-08-28).** 성공률 `p = f(힘, 총HP, 20초)`의 `f`가 채워졌고
**실물에서 도는 것까지 확인됐다.**

```
클릭 → 힘        ✅ ClickService
힘 → 데미지      ✅ AttackService (4-2-e2. Play 검증 완료)
데미지 → 블록    ✅ BlockService (오버플로우 포함)
```

⚠️ Phase 3-5가 여기로 이월된 이유는 "힘 항이 비어 있다"였고, 그 뒤 4-2-e2 조사에서
"힘을 데미지로 바꾸는 함수가 없다"로 한 번 바뀌었다. **두 조건 모두 해소됐다** —
`dmg = str`이 Play 로그에 찍혔고 중간 클리어(`timeLeft` 동결)가 실제로 발생했다.

⚠️ 남아 있는 것은 **[착수 전 확정]** 의 `bloxBase = 1` 하나이며, 선행 조건과는 별개다.
값을 정하는 문제이지 경로가 없는 문제가 아니다.

⚠️ **측정 전에 힘을 초기화할 것.** 힘이 프로필에 누적돼 있으면 1층이 0.1초에 끝난다
(2026-08-28 관측: `str=5513`, `timeLeft=19.8`). 이전 세션의 클릭이 측정값을 오염시킨다
(→ `docs/PENDING.md`).

성공률 데이터를 보고 HP/보상 커브를 조정한다.
Phase 4-1의 수치는 레퍼런스 기반 후보값이다 (→ Phase 3-5에서 이월된 작업).

**[착수 전 확정]** `bloxBase = 1` 이 확정값인지 임시값인지
— 현재 커브 계산은 이 값을 전제로 했다.

사전 검토 완료 (2026-08-26). 세그먼트 후보와 17층 절벽 → `DESIGN.md`
"목표 성공률 > 4-2-f 사전 검토" 참조. 수치는 여기로 복사하지 말 것.

**착수 전에 읽을 것 → `DESIGN.md` "4-2-f 튜닝 지도".**
조정 대상이 서로 어떻게 물려 있는지(한쪽만 만지면 무엇이 조용히 어긋나는지)와
**Play에서 무엇을 재야 하는지**가 거기 있다. 측정의 선후 관계도 그 절에 있다 —
4-2-e2 Play 검증 전의 성공률은 측정값이 아니다.

---

## Phase 5 — 드론 (코드)
```
DroneService   — maxStage-2, 60초당 1회
OfflineService — 상한 8h, 서버 시각 기준
```

⚠️ 지급 → lastCollectAt 갱신 → 저장 순서. 실패 시 롤백

**검증**: 나갔다 1시간 뒤 접속 시 정확한 보상. 시계 조작 무효

---

## Phase 6 — UI (코드 + 에셋)
```
[코드]   프레임 구조, 버튼 로직, 데이터 바인딩
[수동]   이미지, 색상, 아이콘
```

화면 목록과 각 화면의 구성은 `docs/UI.md` "1. 화면 목록" 참조.

개수를 여기에 적지 않는다. 원본이 늘거나 줄 때마다 어긋난다
(실제로 8 → 26 → 29로 두 번 어긋났고, 레벨·커스텀 스피드 추가로 또 바뀔 예정).
CLAUDE.md "문서" 절의 수치 복사 금지 규칙과 같은 이유다.

에셋 제작 규격은 `docs/UI_ASSET_SPEC.md`, 인계 절차와 검증 관문은
`docs/UI_HANDOFF.md` 참조. 검증 관문 G1은 **Phase 6 착수 조건**이다.

UI 작업은 자체 단계(U0~U8)로 코드 Phase와 독립 진행한다 — `docs/UI.md` "UI Phase" 참조.

⚠️ 이 단계가 전체에서 가장 오래 걸린다

---

## Phase 7 — 뽑기 (코드 + 에셋)
```
RollService  — 서버 판정, 순차 확률
AuraService  — 팩별 테이블
TitleService — 자동 롤 배치 처리
PetService   — 크래프팅, 장착, 저장 공간
```

⚠️ 자동 롤: 1초 단위 배치. 롤당 RemoteEvent 금지.
   저장은 30초 주기 또는 신규 획득 시에만

---

## Phase 8 — 수익화 (코드 + 대시보드)
```
[코드]      GamepassService / ProductService / AdService / PlusService
[대시보드]  게임패스·개발자 상품 생성 및 가격 설정
```

⚠️ ProcessReceipt 멱등성. 가장 버그가 잦은 지점.
⚠️ 힘 배수 계단은 최고 단계만 적용

**검증**: 테스트 구매 → 지급 확인 → 재접속 후 유지 확인

---

## Phase 9 — 출시 준비 [대부분 수동]
```
[수동]  게임 아이콘, 썸네일  ← CTR 결정. 절대 대충 금지
[수동]  게임 설명, 태그
[코드]  RateLimiter, Validator (익스플로잇 방어)
[코드]  Analytics (D1/D7/D30 리텐션 측정)
[수동]  비공개 테스트 → 밸런싱 조정
```

---

# 자동/수동 구분

## Claude Code가 하는 것
모든 `.lua` 파일, 모듈 구조, Config, 리팩토링, Git

## 코드 담당이 하는 것
```
모든 .lua (Claude Code로 처리)
Rojo / Wally 관리
Git
Roblox 대시보드 설정
밸런싱 수치 조정
```

## 디자인 담당이 하는 것
```
3D 모델링 (블록, 펫, 운동기구, 맵)
UI 이미지 / 색상 / 아이콘
이펙트 감각 튜닝
게임 아이콘 · 썸네일
사운드
```

## 공동
```
플레이 테스트 ("재미있나?" 판단)
밸런싱 판단
```

비중: **코드 30~40% / 에셋·UI 60~70%**

## 에셋 조달 방법
```
Creator Store 무료 에셋  — 펫, 이펙트, 운동기구
블록                     — Studio에서 직접 (정육면체라 쉬움)
아이콘                   — AI 생성
고품질 모델              — Discord 커미션 (로벅스)
```

---

# 출시 후

목표는 "3만 로벅스 출금"이 아니라 **"출시하고 리텐션 데이터 읽기"**.

```
Analytics에서 D1 / D7 / D30 확인
→ 어느 지점에서 이탈하는지 파악
→ 가설 세우고 설계 변경
→ 데이터로 검증
```

이 사이클 자체가 두 번째 게임을 다르게 만든다.

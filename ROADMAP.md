# 개발 로드맵

문서 갱신: 2026-08-22

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
| `Tests/ConfigTests.server.lua` | 13 | 모든 Config의 validate + 스모크 |
| `Tests/BlockShuffleTests.server.lua` | 3 | 파괴 순서 결정론적 셔플 |
| `Data/SchemaTests.server.lua` | 31 | 프로필 스키마 검증 |
| `Data/MigrationsTests.server.lua` | 20 | schemaVersion 마이그레이션·멱등성 |
| `Systems/CurrencyServiceTests.server.lua` | 38 | 재화 단일 게이트·롤백 |
| `Systems/BlockServiceTests.server.lua` | 30 | 배치·데미지 오버플로우·클리어 |
| `Systems/ChallengeServiceTests.server.lua` | 51 | 타이머·보상 갱신·진입점 거부·source 식별 |
| **합계** | **315** | |

최근 갱신: RemoteEvent 배선(Phase 4-2-a)으로 BigNum 88 → 96 (toRatio 8케이스 추가).
직전 갱신: source 인자 추가 작업으로 ChallengeService 38 → 51.
표에 적혀 있던 35는 실측 38과 어긋난 값이었다. 25층 벽 막기 작업 때 3개가 추가됐는데
표를 갱신하지 않은 것으로 보인다. 2026-08-22 Studio Play 실측으로 전 항목을 대조해 확정했다
— 어긋난 것은 이 한 줄뿐이고 나머지 8개 파일은 표와 실측이 일치한다.

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
- `ChunkBreakerDemo`를 대체할 서버→클라 RemoteEvent 배선

⚠️ `cashout()`은 Touched 없이도 호출 가능해야 한다.
   자동 수령 게임패스와 자동 진행 모드가 나중에 직접 호출한다.

**[확정됨]** 자동 진행은 캐릭터를 이동시키지 않는다. 서버가 `advance()`를
직접 호출한다. 목표층은 유저가 지정하고 시스템은 안전선만 제시한다.
근거와 상세 → `DESIGN.md` "1. 챌린지 > 자동 진행 모드"

#### 4-2-a2. 개인 구역 (플레이어별 월드 공간) [미결 · 4-2-b 선행]

블록이 전원 같은 좌표에 선다. 2인 이상 접속하면 겹친다.
1인 테스트에서는 드러나지 않는다.

- 고칠 곳은 `BlockService`의 레이아웃 단계다. 플레이어별 원점을 받아야 한다
- `BlockSpawner`에서 오프셋을 붙이는 방식으로는 못 푼다 — 서버가 거리 판정에 쓰는
  좌표와 화면 위치가 어긋나면 "가까운 블록부터"가 틀어진다
  (근거 원본은 `Server/Systems/BlockSpawner.lua` 상단 주석)
- 4-2-b의 클릭 파워 패드도 플레이어별로 서야 한다. 같은 문제가 그대로 반복되므로
  패드를 놓기 전에 이 결정이 끝나 있어야 두 번 고치지 않는다

번호를 a와 b 사이에 끼운 이유: 4-2-a에서 드러났고 4-2-b의 선행 조건이라 그 사이가
제자리인데, b~f를 밀면 다른 절의 참조(`Phase 4-2-f` 등)가 같이 어긋난다.

#### 4-2-b. 클릭 파워 패드

힘 성장의 주 수단. 이것이 없으면 `RebirthService` 검증이 불가능하다.
`WorldConfig`에 패드 세트 필드를 추가한다.

**[확정됨]** 월드1 24개 / 시작 파워 1 / 시작 조건 36 × bloxBase.
파워는 세팅 방식(누적 아님). 수치와 근거 → `DESIGN.md` "클릭 파워 패드"

⚠️ 시작 파워 1은 근거가 약한 임시값이다. 4-2-f 튜닝 대상.
⚠️ 선행 조건 4-2-a2(개인 구역)가 아직 미결이다. 패드도 플레이어별로 서야 한다.

구현 시 함께 정할 것 — 선택 패드 저장 방식, 펀치 속도 / 자동 클릭 주기
(→ `DESIGN.md` "클릭 파워 패드 > 미결")

#### 4-2-c. 레벨 + 커스텀 스피드

`WalkSpeed` 서버 권위 검증.

**[착수 전 확정]** `레벨 = floor(힘 지수 ÷ N)` 의 N값
— 패드 곡선이 확정돼야 힘의 도달 범위를 알 수 있다.

#### 4-2-d. RebirthService

**검증**: 환생 후 배수가 정확히 적용된다.

#### 4-2-e. WarpService

**[착수 전 확정]** 비용 기준점 — 목표 절대 기준인가 거리 기준인가
— `cost(목표층)` / `cost(현재→목표)`. 지수라는 것만 확정됐다.

#### 4-2-f. 실측 튜닝

성공률 데이터를 보고 HP/보상 커브를 조정한다.
Phase 4-1의 수치는 레퍼런스 기반 후보값이다 (→ Phase 3-5에서 이월된 작업).

**[착수 전 확정]** `bloxBase = 1` 이 확정값인지 임시값인지
— 현재 커브 계산은 이 값을 전제로 했다.

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

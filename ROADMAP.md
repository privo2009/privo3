# 개발 로드맵

## 원칙
- 아래에서 위로 쌓는다. BigNum이 흔들리면 전부 무너진다
- 각 단계마다 검증하고 커밋한다
- 한 단계가 끝나기 전에 다음으로 넘어가지 않는다

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

**결과**: `BigNumTests.server.lua` 88개 통과 (Studio 실행 확인)

### 1-2. Formatter
`src/shared/Formatter.lua`

```
format(bignum) → "1.23Qa" / "4.56ab" / "7.89AB"
tier = floor(e/3)
tier 0~10  → 고정 테이블 (K M B T Qa Qi Sx Sp Oc No)
tier 11~   → 알파벳 계산
```

**검증**: 경계값 (10^32/10^33, 10^2058/10^2061)

**결과**: `FormatterTests.server.lua` 33개 통과 (Studio 실행 확인)

### 1-3. Config 골격
`src/shared/Config/`
```
StageConfig / UpgradeConfig / ShopConfig
AuraConfig / TitleConfig / PetConfig / WorldConfig
```
값은 임시. 구조만 확정.

**결과**: `ConfigTests.server.lua` 11개 통과 (Studio 실행 확인)

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

**결과**: `SchemaTests.server.lua` 31개, `MigrationsTests.server.lua` 8개 통과

### 2-2. CurrencyService
`src/server/Systems/CurrencyService.lua`

모든 재화 증감의 단일 통로. 여기서 검증과 로깅.

**결과**: `CurrencyServiceTests.server.lua` 38개 통과

**다음**: Phase 3 — 코어 루프

---

## Phase 3 — 코어 루프 (코드 + 에셋)

### 3-1. 블록 (서버) ✅ 완료
```
src/server/Systems/BlockService.lua
src/shared/BlockShuffle.lua (서버/클라 공유 파괴 순서 셔플)
```
HP 관리, 데미지 처리, 클리어 판정, 시드 생성

**결과**: `BlockServiceTests.server.lua` 22개, `BlockShuffleTests.server.lua` 3개 통과

### 3-2. 블록 (클라)
```
src/client/Effects/ChunkBreaker.lua
src/client/Effects/ParticlePool.lua
```
⚠️ 파편 상한 200, 풀링 필수, 물리 금지

### 3-3. 챌린지 ✅ 완료
`src/server/Systems/ChallengeService.lua`
20초 타이머(서버 권위), 스테이지 진행, 보상 갱신, 실패 처리

**결과**: `ChallengeServiceTests.server.lua` 19개 통과

### 3-4. 블록 모델 [수동]
Studio에서 큐브 격자 정육면체 제작. 재질별 프리셋.

**검증**: 블록을 부수고 다음 스테이지로 갈 수 있다

---

## Phase 4 — 성장 (코드)
```
힘 업그레이드 / 파괴 반경 (R = base × log(힘))
RebirthService (1000 블럭스 = +1x)
WarpService (미개척 구간만 유료)
```

**검증**: 환생 후 배수가 정확히 적용된다

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

화면 목록:
```
메인 HUD / 상점(업그레이드·로벅스) / 아우라 / 타이틀
펫 인벤토리 / 환생 / 드론 / 설정
```

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

## Privo가 직접 해야 하는 것
```
3D 모델링 (블록, 펫, 운동기구, 맵)
UI 이미지 / 색상 / 아이콘
이펙트 감각 튜닝
게임 아이콘 · 썸네일
사운드
플레이 테스트 ("재미있나?" 판단)
Roblox 대시보드 설정
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

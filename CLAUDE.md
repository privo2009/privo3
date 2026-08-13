# privo3 — Roblox 방치형 블록 파괴 게임

## 개요
힘을 키워 거대 블록을 부수고, 20초 챌린지로 블럭스를 획득하는
방치형 + 푸시-유어-럭 하이브리드 게임.

## 팀
- 2인 프로젝트. Claude 계정 공유
- 코드 담당 — 이 CLAUDE.md 기준 Claude Code와 실제로 대화하며 구현을 진행하는 쪽
- 디자인 담당 — 3D 모델링, UI, 이펙트, 사운드 등 에셋 전반을 맡는 쪽

## 기술 스택
- Roblox / Luau
- Rojo 7.7.0 — 파일 ↔ Studio 동기화
- Wally 0.3.2 — 패키지 관리
- ProfileStore (lm-loleris/profilestore@1.0.3, 서버 전용)

## 디렉토리
```
src/shared/     → ReplicatedStorage.Shared    (공용)
src/server/     → ServerScriptService.Server  (서버 전용)
src/client/     → StarterPlayerScripts.Client (클라 전용)
ServerPackages/ → Wally 패키지 (직접 수정 금지)
```

## 파일명 규칙
- `Name.server.lua` → Script (서버)
- `Name.client.lua` → LocalScript (클라이언트)
- `Name.lua`        → ModuleScript (모듈)

---

# 절대 규칙

## 1. BigNum 필수
게임 수치는 10^2000 이상까지 커진다. Luau number는 2^53(약 9e15)에서
정수 정밀도가 깨지고 1e308에서 inf가 된다.

- 모든 게임 수치는 `Shared/BigNum.lua`를 통해서만 다룬다
- 저장은 반드시 `{m = 가수, e = 지수}` 형태
- raw number를 프로필에 저장 금지 (inf 저장 시 프로필 영구 손상)
- 가수는 항상 1.0 ≤ m < 10 으로 정규화

### 정밀도 계약 (실측)
`BigNum.add()`로 두 값을 합쳤다가 큰 쪽을 다시 `sub()`로 빼서 작은 쪽을 복원할 때,
두 값의 지수 차이(diff = |큰 쪽 지수 - 작은 쪽 지수|)에 따라 보장되는 정밀도가 다르다:

| diff | 보장 범위 |
|---|---|
| ≤ 3 | 정확히 일치 (실측 100%) |
| 4~10 | 근사치. diff 1당 오차 약 10배씩 증가 (diff=4 최악 ~4e-8, diff=10 최악 ~4e-2) |
| 11~12 | 불안정 구간 — 0으로 소실되거나 예측 불가능하게 큰 오차, 혼재 |
| ≥ 13 | 확정적으로 0 소실 (정상 동작) |

비슷한 크기끼리 빼서 작은 결과가 나오는 연산(cancellation)에서 오차가 증폭되므로,
재화 비교와 정확한 0 판정이 필요한 곳은 `BigNum.lua` 상단 표를 확인할 것.

## 2. CurrencyService 단일 게이트
모든 재화 증감은 `Server/Systems/CurrencyService.lua`만 통과한다.
`profile.blox`를 직접 수정하는 코드를 절대 작성하지 말 것.
이유: 재화 누수 추적과 검증을 한 지점으로 좁힌다.

## 3. 서버 권위
- 챌린지 타이머: 서버 `os.clock()` 기준. 클라 시간 신뢰 금지
- 뽑기 롤: 100% 서버 판정. 클라는 애니메이션만 재생
- 오프라인 계산: 서버 `os.time()` 기준. 기기 시계 조작 방지
- 클라가 보낸 값은 전부 검증 대상

## 4. 파편·파티클은 클라이언트 전용
- 파편을 서버에 생성 금지 (복제 비용 폭발)
- 물리 시뮬레이션 금지. `Anchored = true` + 수동 낙하 애니메이션
- 동시 파편 상한 200개, 오브젝트 풀링 필수
- 아우라·펫 파티클도 클라 전용
- 서버는 블록 HP만 관리. 큐브 개수는 클라가 HP 비율로 역산

## 5. 게임패스 소유 상태 저장 금지
프로필에 저장하지 말 것. 매 세션 `MarketplaceService`로 확인 후
메모리 캐시만. (환불 시 영구 지급 방지)

## 6. ProcessReceipt 멱등성
동일 영수증이 재전달될 수 있다. 반드시 멱등하게 구현.
처리 실패 시 `NotProcessedYet` 반환하여 재시도 유도.
지급 후 저장 실패 시 롤백 필요.

## 7. schemaVersion
프로필 템플릿에 `schemaVersion` 유지. 로드 시 버전 비교 후
`Migrations.lua`를 태우는 구조.

---

# 금지 사항

- ❌ 안티-AFK 스크립트 (VirtualUser 입력 시뮬레이션) — ToS 위반
- ❌ raw number를 DataStore에 저장
- ❌ 게임패스 소유 여부 저장
- ❌ 서버에 파편/파티클 생성
- ❌ 물리 기반 파편
- ❌ 자동 롤 시 매 롤마다 프로필 저장 (쓰기 한도 초과)
- ❌ 자동 롤 시 롤 1회당 RemoteEvent (배치 처리할 것)
- ❌ 반복 루프에서 `Instance.new` (풀링할 것)
- ❌ Studio에서 스크립트 직접 편집 (Rojo가 덮어씀)
- ❌ 힘 배수 게임패스 중첩 적용 (최고 단계만 적용)

---

# 작업 방식

- 한 번에 하나의 모듈만 작업
- 새 모듈은 테스트 케이스를 함께 제시
- 기존 파일 수정 시 무엇을 왜 바꾸는지 먼저 설명
- 확신 없으면 추측하지 말고 질문
- 밸런싱 수치는 전부 `Shared/Config/`로 분리. 하드코딩 금지

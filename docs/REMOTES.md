# 리모트 목록 (클라 → 서버 입구)

문서 작성: 2026-11-25 (지시서 #38 — 출시 전 리모트 보안 점검) · 2026-11-27 #43 2부 이동 검사(5절) · 2026-11-28 #48 관리 도구(AdminRequest) · ServerNotice

이 문서는 **목록과 규칙**이다. 이름 원본은 `Shared/Remotes.lua`, 공통 문은 `Server/Systems/RemoteGuard.lua`,
입구마다의 검사는 각 서비스 코드다. 상한 수치는 그 원본을 본다(여기 적힌 수는 #38 시점 값 — 어긋나면 코드가 맞다).

## 0. 한눈에

- 클라 → 서버 **RemoteEvent 23개**(연결 24 — `SyncRequest`는 상태 · 드롭 두 서비스가 듣는다 · #48 `AdminRequest` 더함). **RemoteFunction 0개 · InvokeClient 0회**
  (서버가 클라 응답을 기다리다 멈추는 길이 없다 — `grep RemoteFunction|InvokeClient|OnServerInvoke` 0건)
- 서버 → 클라 전용 채널(BlockDamaged · RunStateChanged · PlayerState · *Result · EconomyEvent · #48 ServerNotice · AdminResult 등)은 서버가 듣지 않는다
- 모든 입구는 `RemoteGuard.connect(remote, fn)`으로만 붙인다. `OnServerEvent:Connect`를 직접 쓰지 않는다
  (`RemoteGuardTests` "목록" 4줄이 Remotes 정의 ↔ 붙은 리모트를 대조한다 — 새 입구를 만들면 그 표에 한 줄)

## 1. 공통 문 RemoteGuard (서비스에 닿기 전)

| 단계 | 하는 일 | 걸리면 |
|---|---|---|
| 나가는 중 | `player.Parent ~= Players`면 버림 | 조용히 버림 |
| 모양 예산 | nil · boolean · **유한한** number · 200바이트 이하 string · 표(깊이 3 · 키 32 · 값 총 128 · 키는 글/유한한 수)만 | 조용히 버림(NaN · inf · Instance · Vector3 · 함수 · 긴 글 · 큰 표) |
| 연타 통 | 플레이어 × 리모트마다 토큰 통. 기본 0.15초에 1번(몰아 쓰기 1) | 조용히 버림 · `RemoteGuard.stats()`에 수 |
| 오류 격리 | 처리 함수를 xpcall로 — 오류가 나도 연결은 살아 있고 다음 요청은 처리된다 | warn 한 줄(리모트마다 60초에 한 번) |
| 나가기 | PlayerRemoving에 그 플레이어 통 지움 | — |

통 크기 예외(`RemoteGuard.POLICIES`): ClickInput · SpeedRequest 초당 10 · 몰림 4(클라 0.2초 묶음 + 네트워크 몰림) ·
SyncRequest 초당 2 · 몰림 10(접속 직후 수신부 여러 개가 한꺼번에 — 서버가 모아 한 번 답한다).
버린 요청에는 답하지 않는다 — 정상 플레이로는 닿지 않는 빈도 · 모양이다. 서비스 자체 상한(아래 표)은 그대로 있고, 그쪽은 사유를 답한다.

## 2. 입구마다

"검사"는 서버가 다시 재는 것이다(클라 값은 요청일 뿐 — 가격 · 수량 · 보상 · 위치는 서버가 자기 상태에서 구한다).

| 리모트 | 보내는 쪽 | 인자 | 검사(서버) | 서비스 자체 상한 | 실패 응답 |
|---|---|---|---|---|---|
| ClickInput | Input/ClickInput (0.2초 묶음) | `{count}` | 정수 ≥ 1 · 배치 상한으로 자름 · 수동 초당 상한 창 · 자동 클리커 켜면 수동 무시 · 힘은 서버가 계산 | 창(초당 수동 상한) | ClickRejected(1초에 한 번) |
| SpeedRequest | Input/SpeedInput | `{speed}` | 유한한 수만 · `min(요청, 레벨 최대)` 서버 계산 · 주기 검사 | 창(REQUEST_LIMIT/WINDOW) | SpeedApplied(실제 값) |
| SyncRequest | Net/StateSync | `{}`(안 읽음) | 짧은 창의 요청을 모아 한 번 답함 | 모아 답하기 | PlayerState · RunStateChanged · EconomyEvent snapshot |
| RebirthRequest | WindowBoot | 없음 | 블럭스 ≥ 비용(1000 × 4^n) · 자동 진행 중이면 거부 · yield 없이 한 번에 | 1.0초 | RebirthResult(사유) |
| WarpRequest | WindowBoot | `{stage}` | **정수 1 이상(#38)** · 있는 층 · 블럭스 ≥ 비용 · 자동 진행 중 거부 | 1.0초 | WarpResult(invalid_stage 등) |
| UpgradeRequest | WindowBoot | `{name}` | 글 64자 이하 · 노출 항목 · 최대 레벨 · 비용 서버 계산 | 0.25초 | UpgradeResult |
| TitleRequest | WindowBoot | `{action, titleId?, on?}` | roll · equip · setAuto만 · 보유 확인 · 비용 서버 | 0.25초 | TitleResult |
| AuraRequest | WindowBoot | `{action, pack?, auraId?, credit?}` | 팩 정수 범위 · 열린 팩 · 보유 · 롤 충전 수 | 0.2초 + 롤 시계 | AuraResult |
| SettingsRequest | WindowBoot | `{key, value}` | 허용 키 4개 화이트리스트 · boolean만 | 0.25초 | SettingsResult |
| PetRequest | WindowBoot | `{action, egg?, uid?}` | 알 정수 범위 · uid 숫자 글 · 열린 알 · 코인 ≥ 비용 · 보유 | 0.2초 + 부화 시계 | PetResult |
| PurchaseRequest | Net/PurchaseClient | `{key}` | 글 64자 · 상품표에 있는 키 · 등록 ID · 제한 지역 유료 랜덤 차단 · 이미 보유 · beta 판매 | 1.0초 | PurchaseResult(프롬프트를 띄웠나). **지급은 ProcessReceipt만** |
| AutoClickRequest | HudBoot | `{on}` | boolean · 패스 보유(초당 횟수 > 0) | 0.25초 | AutoClickResult |
| PotionRequest | Net/PotionClient | `{boost}` | 아는 종류 · 제한 지역 유료 랜덤 차단 · 보관 수 ≥ 1 · 켜기 실패면 되돌림 | 0.5초 | PotionResult |
| PlusPromptRequest | WindowBoot | `{reason}` | shop · rebirth만 · 세션에 한 번 · 구독자 묻지 않음 | 세션 1회 | 없음 |
| AutoAdvanceRequest | Net/AutoAdvanceClient | `{action, target?}` | start · stop · 목표 정수 1 ~ maxTarget · 보유 · 런 없음 · 캐릭터 | 0.5초 | AutoAdvanceResult |
| DailyRequest | OverlayBoot | 없음(안 읽음) | 날짜 · 칸은 서버 os.time | 0.5초 | DailyResult |
| CodeRequest | WindowBoot | `{code}` | 서버가 정리(대문자 · 공백) · 아는 코드 · 받은 적 · 만료 · 틀린 횟수 막힘 | 0.5초 + 틀림 잠금 | CodeResult(입력 글자 되보내지 않음) |
| OnboardingRequest | OverlayBoot | `{action}` | finish · skip만 · 단계 확인 | 0.5초 | OnboardingResult |
| ForgeRequest | EconomyV2Boot | `{action, combo?, fill?, on?, id?}` | 대장간 열림 · 조합 정수 5개(1 ~ 10) · 광석 · 칸 · 간격 · 토큰 · 교환 가능 — 전부 서버 | 0.15초 + 제작 간격 | EconomyEvent forge_* |
| EquipmentRequest | EconomyV2Boot | `{action, id?}` | 있는 곡괭이 · 보유 · 대장간 열림 · 광석 · 사본 수 | 0.15초 | EconomyEvent equipment_* |
| PetAutoRequest | PetWindow | `{on, egg?}` | **알 번호 정수 1 ~ 알 수(#38)** · 틱마다 코인 · 간격 | 0.15초 | EconomyEvent auto_hatch_state |
| OnboardingTipRequest | EconomyV2Boot | `{action = "sync"}` | sync만 | 0.5초 | EconomyEvent tips |
| AdminRequest(#48) | AdminBoot(관리자에게만 있는 창) | `{action, target, kind, id, amount, text}`(빠진 필드 없이) | **관리자 판정이 먼저**(게임 주인 · 그룹 주인 · AdminConfig 목록 — 서버) · 아니면 조용히 버림(답 없음) · 행동 4종 · 대상 = 같은 서버 유저 UserId · 종류 6 · 개수 정수 1 ~ 상한(재화 1e15 · 광석 · 토큰 1만 · 곡괭이 · 펫 50) · id(광석 1 ~ 10 · 토큰 5종 · 있는 곡괭이 · 있는 펫 · 회수는 펫 uid) · 공지 120자 · 제어 문자 없음 · TextService 거름 실패면 안 보냄 · 지급 · 회수는 관문(CurrencyService · InventoryService · PetService — 사유 admin) | 기본 0.15초 | AdminResult(사유) · 쓸 때마다 [Admin] 로그 · admin_action 이벤트 |

## 3. 테스트

- `RemoteGuardTests`: 모양 · 통 · 격리 · 나가면 지움 · 목록 대조 + 입구 21종 흔들기(#48 관리 도구 지급 · 공지 — 관리자로 흔든다)(`RemoteFuzz` 공통 도우미 —
  통째로 잘못된 payload 15종 · 필드 하나씩 잘못(nil · NaN · inf · 음수 · 0 · 소수 · 1e308 · 2^53 · 빈 글 · 긴 글 · 틀린 타입) ·
  같은 요청 20번 1ms 간격 → **거부되고 바꾸는 deps 0회 · 처리 1번 이하 · 오류 0**)
- `AdminServiceTests`(#48): 관리자 아님 4종 → 관문 · 답 · 로그 0 · 잘못된 값 16종 → 관문 0 · 공지는 거른 글만
- `DupeTests`: 가짜 프로필로 수령 두 번 · 실패 뒤 수령 · 환생 중 수령 · 제작 · 교환 · 강화 · 별 연달아 · 대장간 · 장비 같은 시각 연타
- `ProductServiceTests` · `ProductGrantsTests`: 같은 영수증 두 번 = 지급 1회 · 프로필 없음 → NotProcessedYet(상품 16종 전부)

## 4. 새 입구를 만들 때

1. 이름을 `Shared/Remotes.lua`에 · 서버에서 `RemoteGuard.connect`로 붙인다
2. 인자는 서비스 안에서 다시 읽는다(타입 · 범위 · 정수) — 결과값(보상 · 가격)을 payload에 싣지 않는다
3. 빈도가 높게 오는 입구면 `RemoteGuard.POLICIES`에 통 크기를 적는다
4. `RemoteGuardTests` "목록"의 inbound 표에 한 줄 · 흔들기 spec 하나 · 이 문서 표에 한 줄

## 5. 이동 검사 — 순간이동 · 스피드핵 (지시서 #43 2부 · 2026-11-27)

리모트가 아니지만 같은 성격(클라가 보낸 값을 서버가 다시 잰다)이라 여기 둔다. 원본 `Server/Systems/MovementGuard` ·
숫자 `Shared/Config/MovementGuardConfig`(전부 TEMP) · 원칙 `DESIGN.md` "13. 서버 권위 — 근처 확인" N3.

| 무엇 | 어떻게 |
|---|---|
| 왜 | 캐릭터 물리는 클라 소유 — 서버가 읽는 HumanoidRootPart 위치는 클라가 보낸 값이다. 줍기(거리 폴링) · 근접 자동 공격이 그 위치를 믿는다 |
| 기록 | 서버 단일 루프가 `SAMPLE_SEC`마다 플레이어 위치를 적고 앞 표본과 비교한다 |
| 허용 | 수평 ≤ (레벨 이동 속도 상한 `SpeedService.getMaxSpeed` + `SPEED_MARGIN`) × dt + `SLACK_STUDS` · 오르기 ≤ `UP_SPEED_MAX` · 떨어지기 ≤ `FALL_SPEED_MAX` |
| 여유 `SLACK_STUDS` 8(#46 — 4에서 올림 · Claude 결정) | 위치 복제가 늦게 오면 표본 하나에 두 주기 몫이 들어온다. #45 봇이 진행 벽 통과 직후 정상 걷기(속도 43)를 걸렸다 — 0.15초 늦음 = 0.25초 표본에 17.3 studs(여유 4면 허용 16.75). 여유 8 + 속도 여유 몫 2 = 10 studs → 늦음을 속도 43에서 0.23초 · 상한 80에서 0.125초까지 받는다. 순간이동 · 3배 속도는 그대로 걸린다. "두 표본 연속일 때만"은 쓰지 않는다(한 번에 뛰는 순간이동을 놓친다) |
| 걸리면 | `HOLD_SEC` 동안 그 플레이어의 줍기 틱 · 펀치 틱을 건너뛴다(공격 결과 코드 `move_suspect` — 값은 아무것도 바꾸지 않는다) · warn 한 줄(LogFold로 접음). **킥 없음** |
| 예외 | 게임이 옮긴 순간 — `ArenaService.returnToSpawn`(수령 · 실패 · 환생 뒤) · `moveToStageEntrance`(워프 · 자동 진행) · 리스폰(CharacterAdded) — 은 `markTeleport`로 `TELEPORT_GRACE_SEC` 동안 재지 않고 기준점만 다시 잡는다 |
| 자동 진행 보유자 | 줍기는 거리를 안 보므로(전부 줍기) 이동 검사도 줍기에 안 건다 |
| 테스트 | `MovementGuardTests`(정상 걷기 · 점프 · 낙하 · 복제 흔들림 · 복제 0.15초 늦음(#45 오탐 재현) 통과 / 순간이동 · 3배 속도 걸림 / 게임 순간이동 직후 통과 / 공격 · 줍기 건너뜀 / 설정에서 읽음 — 레벨 0 속도도 LevelConfig에서) |
| 오탐 실측 | 자동 플레이 봇 3구간(fresh · min30 · hour2 — 워프 · 수령 뒤 스폰 · 시간 초과 · 점프 포함)에서 `[MovementGuard]` 경고 0 · #45에 1번(진행 벽 직후 — 위 여유) · #46 4구간(배율 0.5 · 여유 8)은 `docs/TUNING.md` 13절 |

새로 캐릭터를 옮기는 서버 코드를 쓰면 옮기기 **직전에** `MovementGuard.markTeleport(player)`를 부른다(무-yield).

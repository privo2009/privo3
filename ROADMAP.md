# 개발 로드맵

문서 갱신: 2026-10-23

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
| `Tests/ConfigTests.server.lua` | 71 | 모든 Config의 validate + 스모크 |
| `Tests/BlockShuffleTests.server.lua` | 3 | 파괴 순서 결정론적 셔플 |
| `Tests/WarpConfigTests.server.lua` | 31 | 워프 비용 곡선(지수·단조)·순수성·거부 사유 3종 |
| `Tests/AttackConfigTests.server.lua` | 29 | 펀치 속도·판정 반경 파생·경계(이하) |
| `Data/SchemaTests.server.lua` | 33 | 프로필 스키마 검증 |
| `Data/MigrationsTests.server.lua` | 25 | schemaVersion 마이그레이션·멱등성·v4 lifeBlox |
| `Systems/CurrencyServiceTests.server.lua` | 59 | 재화 단일 게이트·롤백·rebirths·lifeBlox(이번 생애 누적) |
| `Systems/BlockServiceTests.server.lua` | 51 | 배치·데미지 오버플로우·클리어 |
| `Systems/ChallengeServiceTests.server.lua` | 82 | 타이머·보상 갱신·진입점 거부·source 식별·블럭스 획득 배수 한 함수(payableReward)·view nextReward |
| `Systems/ClickServiceTests.server.lua` | 47 | 입력 위생·초당 상한 윈도우·통지 억제·자동 경로 |
| `Systems/PadServiceTests.server.lua` | 36 | 패드 배치·해금 경계·디바운스·세팅/클램프 |
| `Systems/SpeedServiceTests.server.lua` | 21 | 요청값 클램프·입력 위생·환생 하향·최대치 상승 불변 |
| `Systems/SpeedRequestServiceTests.server.lua` | 32 | 요청 빈도 상한·폐기·로그 억제·응답 payload |
| `Systems/RebirthServiceTests.server.lua` | 71 | 거부 시 부작용 0·순서·누적·부분 실패·패드 되돌리기(11단계) ※ |
| `Systems/WarpServiceTests.server.lua` | 84 | 거부 시 차감 0·차감이 런 시작보다 먼저·부분 실패 3종·W1 런 중 거부·W2 차감→이동→시작 순서·캐릭터 없음 거부·이동 실패에도 런 시작 ※ |
| `Systems/AttackServiceTests.server.lua` | 89 | 반경 밖 미호출·이중 계산 방지·경계(float32 이웃)·방향 독립·데미지 업그레이드 한 번만 곱함·플레이어별 펀치 주기(틱 · 몰아치기 없음) |
| `Tests/UiThemeTests.server.lua` | 33 | 색 역할 8종 존재·밝은/기본/어두운 3단계·Color3 타입 |
| `Tests/AssetRegistryTests.server.lua` | 125 | 24종 등록·source/scaleType/placeholderRole 검증·resolve() 도착·미도착 판정 ※ |
| `Tests/AssetImageTests.server.lua` | 16 | 미도착→Frame·도착→ImageLabel·SliceCenter·UIStroke 3px |
| `Tests/TextScaleTests.server.lua` | 16 | 글자 5단계 존재·heightFraction·maxTextSize 값 일치 ※ |
| `Tests/ScreenControllerTests.client.lua` | 29 | ScreenGui 3층·지연 생성·Window 단일 오픈·Overlay 다중·배경 흐리게·오류 케이스·closeAll이 자기 인스턴스에만 닿음 |
| `Tests/StoreTests.client.lua` | 30 | 초기값·구독/해지·setSource 교체·BigNum 형태 유지·싱글톤 API 존재 · 누수 없음(싱글톤에 쓰지 않음) |
| `Tests/PanelTests.client.lua` | 19 | 크기 2종 규격·제목/X버튼/여백의 화면 기준 환산 일치(root-상대 Scale 보정) |
| `Tests/ButtonTests.client.lua` | 37 | 색 6종 생성·크기 2종·비활성 gray 전환·미도착/도착 눌림 처리 ※ |
| `Tests/ValuePanelTests.client.lua` | 15 | 8자/4자 폭 AspectRatio·TextScaled·MaxTextSize·잘림 방지 |
| `Tests/LayoutTests.client.lua` | 22 | 구역 비율·중앙 금지 판정 경계·getBounds AnchorPoint 보정 |
| `Tests/BloxDisplayTests.client.lua` | 13 | 중앙 금지 미침범·Store 구독 반영·8자 잘림 방지 |
| `Tests/ChallengeInfoTests.client.lua` | 17 | 상단 정보 15% 안·타이머 특대 단계·active=false 레이아웃 유지 |
| `Tests/MenuRailTests.client.lua` | 59 | 6개 생성·좌측 레일 폭·세로 합계·BloxDisplay 비침범·AspectRatio·라벨 2~4자·격자 열 수 구성값 ※ |
| `Tests/HudVisibilityTests.client.lua` | 31 | PlayerGui 부착·Visible·Enabled·AbsoluteSize·10프레임 지속 관찰 ※ |
| `Tests/HudLayoutTests.client.lua` | 432 | 뷰포트 게이트 뒤 실물 HudGui — 크기 0·인셋/뷰포트 경계 침범·형제 겹침·MenuRail 격자 배치(AbsolutePosition)·칸 안 자식·컴포넌트 간 겹침·글자 하한·터치 조작부 겹침·구좌 가격이 칸 안 · 표기 통일 ※ |
| `Tests/PowerBlockTests.client.lua` | 49 | 세 행 Y 범위·하단 띠·8자/4자 규격·진행률 경계·Store 구독 반영·다른 인스턴스 미유출 |
| `Tests/ShopSlotsTests.client.lua` | 36 | 상점 4구좌 배치·ShopConfig 원본 참조·가격 표기 2꼴 |
| `Tests/AutoToolsTests.client.lua` | 28 | 자동 도구 아이콘 배치 |
| `Systems/ArenaServiceTests.server.lua` | 130 | 스폰 좌표·경계 높이·스테이지 수에 따른 경계 확장·출입구 개방·어깨 벽·바닥 파생과 파트 상한 분할(층 수 흔들기)·전 층 바닥 위 |
| `Systems/CashoutPadServiceTests.server.lua` | 47 | 발판 좌표·측면 오프셋·디바운스·런당 1회·플레이어별 격리·source 경로·층 불일치 무시·UiTheme 색 |
| `Tests/SuccessRateReportTests.server.lua` | 78 | 확률 시뮬레이터 식 — 펀치 간격·속도 미곱·반경 밖 지연·런 중 클릭·걷기 시간·진행 규칙 2종·모델 범위·seed 결정성·워프 비교(판단·워프 런)·문턱 구간 비교(구간 수·순서·합산·seed 재현)·운동기구 훈련·공허 구매자·업그레이드 S5(가장 싼 것부터 · 예산 = getLeftover · 최대 레벨 건너뜀)·TEMP 후보 교체 되돌림 |
| `Systems/GymServiceTests.server.lua` | 45 | 운동기구 조건·배수·가격 순증가·해금 경계·공허 훈련 구역(로벅스 전용·맨 끝·가장 비쌈·가장 셈·ShopConfig 가격)·스폰 구역 안·게이트 앞·패드와 안 겹침·발판 판정·배수 결정 |
| `Tests/CashoutPadViewTests.server.lua` | 23 | 런 상태 → 발판 켜짐(클리어 + 같은 층)·꺼짐(미클리어·다른 층·런 없음)·켜진 발판 1개·역할 키 |
| `Tests/AdvanceWallViewTests.server.lua` | 97 | 런 상태 → 벽 모습(숨김·닫힘·열림)·크기 파생·층별 위치·잘못된 stage·LevelConfig 깊이 소스 등록 |
| `Tests/AdvanceWallServiceTests.server.lua` | 26 | 트리거 스펙(최종층 없음·중심·크기)·층 대조·런 없음·디바운스 창·플레이어 격리 |
| `Tests/AdvanceWallRendererTests.client.lua` | 62 | 상태별 충돌·투명·색(닫힘·열림·최종층·숨김)·create 계약(Anchored·CanTouch=false) |
| `Tests/EntranceGateServiceTests.server.lua` | 25 | 런 없음→1층 startRun·런 있음 무동작·서 있기 반복·디바운스 공유·플레이어 격리·스펙 파생(지면·블록 바깥면 앞) |
| `Tests/RunDeathServiceTests.server.lua` | 9 | 런 있음 abandon 1회·런 없음 0회·같은 죽음 두 번 차단·리스폰 뒤 새 죽음 |
| `Systems/PlayerStateServiceTests.server.lua` | 39 | 상태 스냅샷 형태 · 직렬화 왕복 · 같음 비교 · 로드 시 1회 · 빈도 상한 · sync 모음(로드 전 요청 포함) · 리스폰 · 퇴장 · 업그레이드 레벨 8키 |
| `Tests/PlayerStateClientTests.client.lua` | 20 | payload 형태 판정 · Store 반영 · 틀린 payload 통째로 버림 · 업그레이드 표(키 · 음수 · 복사) |
| `Tests/CoreScreensTests.client.lua` | 56 | 런 안내 · 로딩 판정, 3D 안내 내용(서버 · Config 원본), 화면 규칙(Offset 0 · 금지 구역 밖 · 층 순서 · 역할 색), 패드 표시 역할 3종 · 역할별 높이 · 다음 해금 크기 · 벽 표시 서버 nextReward |
| `Systems/RebirthRequestServiceTests.server.lua` | 12 | 환생 요청 거부 경로(블럭스 부족 · 빈도 상한 · 부분 실패) · 성공 결과 형태 |
| `Tests/RebirthWindowTests.client.lua` | 52 | 표시 값(서버와 같은 함수) · 사유 문구 · 확인 단계 없이는 요청 안 나감 · 잠김 · 창 규격 · 버튼 그림 ZIndex · 남는 것에 업그레이드 · 상점 안내 · 상점으로 |
| `Tests/TouchSafeLayoutTests.client.lua` | 13 | 폰 실측 사각형으로 겹침 판정(구좌 · 자동 도구 겹침, 힘 블록 안 겹침) · 점프 버튼 위로 올림 양(간격 포함) · 올릴 필요 없으면 0 · Scale 환산 |
| `Systems/WarpRequestServiceTests.server.lua` | 12 | 워프 요청 payload 위생(invalid_stage) · 서버 거부 사유 그대로(W1 · 블럭스 부족) · 성공 결과 형태 · 빈도 상한 · 결과 매번 송신 |
| `Tests/WarpWindowTests.client.lua` | 36 | 표시 값(WarpConfig.cost 원본) · 잠김(블럭스 부족 · W1 런 중) · 사유 문구 · 확인 단계 · 쪽 넘김 · 창 규격 · 행 색 3단계 |
| `Tests/UpgradeConfigTests.server.lua` | 55 | 노출 4종 · 비노출 4종 · 스키마 8키 · 효과 선형(S1) · 펀치 속도 증가량 유도 · 최대 레벨 = 상한(S2) · 이동속도 80 상한(S3) · 비용 단조 증가 · canBuy 사유 3종 · validate 거부 |
| `Systems/UpgradeServiceTests.server.lua` | 35 | 구매 거부 경로(잘못된 항목 · 최대 레벨 · 블럭스 부족 · 프로필 없음) 부작용 0 · 차감 → 레벨 → 통지 순서 · 부분 실패 · 저장값 읽기 · 환생 경로가 업그레이드를 안 건드림 |
| `Systems/UpgradeRequestServiceTests.server.lua` | 13 | 구매 요청 payload 위생 · 서버 거부 사유 그대로 · 성공 결과 형태 · 빈도 상한(중복 요청) · 퇴장 정리 |
| `Tests/UpgradeShopTests.client.lua` | 40 | 상점 표시 값(UpgradeConfig 원본) · 잠김(MAX · 블럭스 부족) · 사유 문구 · 요청 한 번만(결과 대기 · 시간 뒤 풀림 · 잠긴 줄) · 로벅스 자리 숨김 · 창 규격 |
| `Tests/FeedbackTests.client.lua` | 44 | 클릭 팝업 증가분 · 문구 · 진행, HUD 환생 배수(서버와 같은 함수), 환생 안내(×이전 → ×이후 · 알림층 · 상단 띠 안), 운동기구 3D 표시 역할 · 문구, 패드 · 기구 본체 색 |
| `Systems/LogFoldTests.server.lua` | 11 | 첫 줄은 찍는다 · 창 안 반복은 접는다 · 창 뒤 'N번 더' 요약 + 새 줄 · 키(플레이어 · 사유)별 · ChallengeService 판정은 그대로 |
| **합계** | **2880** | |

※ 여덟 행 다 **헬퍼 또는 루프가 check를 여러 번 부른다.** `RebirthServiceTests`는
7개 check를 묶은 `checkUntouched`를 3번 호출하고(정적 53), `WarpServiceTests`는
3개 check를 묶은 `checkRejectedCleanly`를 거부 케이스마다 부른다. `AssetRegistryTests`
(정적 78) · `ButtonTests`(정적 22, 실측 37) · `MenuRailTests`(정적 18)는
항목 목록(색 6종·아이콘 6개)을 순회하는 루프 안에 check가 여러 개 있고, `TextScaleTests`
(정적 4, 실측 16)는 5단계 루프, `HudVisibilityTests`(정적 6)는 화면 3종 루프
안에 check가 있다. `HudLayoutTests`(정적 카운트 없음 — 처음부터 실측만 기록)는
HudGui 아래 렌더된 요소 전부를 순회하는 검사 1·2와 형제 쌍을 순회하는 검사 3, 행을
순회하는 검사 4가 전부 루프 안에 있다. 정적 세기에는 루프/헬퍼 안의 check가 한 번만
잡히고 런타임에는 반복 횟수만큼 돈다 — 어긋나는 것이 **정상**이다. 이 여덟 행은
실측만 믿을 것.

⚠️ **이 각주에서 옛 실측값 셋(`MenuRailTests` 58 · `HudVisibilityTests` 16 ·
`HudLayoutTests` 198)을 뺐다** (2026-09-07). 어느 Play의 값인지 확정할 수 없는
숫자였고 표 본문(59 · 31 · 381)과 어긋나 있었다. 각주가 하려는 말은 "정적 카운트와
실측이 어긋나는 것이 정상"이고 그건 숫자 없이 성립한다. **실측값은 표 본문에만
적는다** — 두 군데 적으면 반드시 어긋난다는 것이 이 절 첫 줄의 규칙이다.
남아 있는 실측값(37 · 16)은 표 본문과 일치하는 것만 확인하고 둔 것이다.
(2026-10-22: `RebirthServiceTests` 66 · `AssetRegistryTests` 130도 표 본문과 어긋나 뺐다 — 같은 이유다.)

⚠️ **역산으로 채운 칸은 합계가 맞아도 틀릴 수 있다.** `AttackConfigTests`는 한동안
합계에서 역산한 38이었고 실측은 **29**였다. 같은 시점에 `ClickServiceTests`가 38 → **47**로
늘어 있어서 두 오차가 정확히 상쇄됐고(-9 / +9), 합계 747도 행 수 18도 맞아 표가 멀쩡해 보였다.
**합계 대조는 개별 행의 오류를 잡지 못한다** — 상쇄되면 조용히 통과한다.
각 파일이 찍는 자기 줄과 눈으로 대조하는 것 말고 다른 방법이 없다.

최근 갱신: **2026-10-23 Studio Play 런타임 실측 (전량, 지시서 #8 — 맵 템포 · 피드백 · 화면 정리 · 로그 접기 · 리포트 끈 Play).** 60개 행 전부가
한 Play에 찍혔다. **2880 passed / 0 failed** — 서버 1740(38행) + 클라 1140(22행).

```
신설   FeedbackTests                44          (7753095 · cc9d344)
       LogFoldTests                 11          (07d5a1f)
갱신   ArenaServiceTests           119 → 130    M3 조건 · M2 목표 시간 (2ff2484)
       PadServiceTests              31 →  36    통로 밖 · 2줄 · 열 순서 (2ff2484)
       GymServiceTests              41 →  45    통로 밖 · 반대쪽 · 공허 맨 끝 · 2줄 (2ff2484)
       SuccessRateReportTests       76 →  78    걷는 동안 클릭 스위치 (2ff2484)
       RebirthRequestServiceTests   10 →  12    total (7753095)
       UpgradeConfigTests           48 →  55    최대 속도 도달 (cc9d344)
       UpgradeServiceTests          33 →  35    최대 속도 도달 서버 거부 (cc9d344)
       HudLayoutTests              413 → 432    환생 배수 칸 등 HUD 요소 증가 (7753095 · cc9d344)
       RebirthWindowTests           47 →  52    목록 3줄 · 버려지는 양 0 (cc9d344)
       UpgradeShopTests             37 →  40    최대 속도 도달 (cc9d344)
유지   나머지 46행 (ConfigTests는 확정 좌표만 바뀜 71 그대로, PowerBlockTests 49 그대로)
```
폰(Galaxy A06 시뮬레이션) Play에서도 클라 22행 0 failed.

그 전 갱신: **2026-10-22 Studio Play 런타임 실측 (전량, 지시서 #7 — 상점 1차 · UI 결함 · 리포트 끈 Play).** 58개 행 전부가
한 Play에 찍혔다. **2765 passed / 0 failed** — 서버 1696(37행) + 클라 1069(21행).

```
신설   UpgradeConfigTests           48          (a030722)
       UpgradeServiceTests          33          (c947e8b)
       UpgradeRequestServiceTests   13          (c947e8b)
       UpgradeShopTests             37          (57f6bf7)
갱신   AttackServiceTests           73 →  89    데미지 업그레이드 · 플레이어별 펀치 주기 (c947e8b)
       ChallengeServiceTests        74 →  82    payableReward · nextReward (c947e8b)
       PlayerStateServiceTests      33 →  39    업그레이드 레벨 (c947e8b)
       PlayerStateClientTests       15 →  20    업그레이드 표 (c947e8b)
       SuccessRateReportTests       60 →  76    S5 · TEMP 후보 (92e8f67)
       RebirthWindowTests           38 →  47    상점 안내 (9fe3a7e)
       HudLayoutTests              410 → 413    구좌 가격 칸 안 (1b728d5)
       CoreScreensTests             54 →  56    다음 해금 크기 · nextReward (1b728d5 · c947e8b)
       ShopSlotsTests               34 →  36    가격 표기 (1b728d5)
       WarpWindowTests              34 →  36    행 색 (1b728d5)
유지   나머지 44행
```

그 전 갱신: **2026-10-22 Studio Play 런타임 실측 (전량, 지시서 #6 — 폰 결함 · 패드 표시 · 월드·워프 창 · 리포트 끈 Play).** 54개 행 전부가
한 Play에 찍혔다. **2565 passed / 0 failed** — 서버 1556(34행) + 클라 1009(20행).

```
신설   TouchSafeLayoutTests         13          (fd6cf4d)
       WarpRequestServiceTests      12          (f4fe428)
       WarpWindowTests              34          (f4fe428)
갱신   HudLayoutTests              407 → 410    글자 하한 · 터치 조작부 (fd6cf4d)
       CoreScreensTests             47 →  54    패드 표시 역할 (55c3b05)
       WarpServiceTests             73 →  84    W1 · W2 (f4fe428)
유지   나머지 48행 (ChallengeInfoTests는 비교 방식만 바뀜, 17 그대로 — ab66959)
```

그 전 갱신: **2026-10-22 Studio Play 런타임 실측 (전량, 환생 창 · REBIRTH_VERIFY 삭제 뒤 · 리포트 끈 Play).** 51개 행 전부가
한 Play에 찍혔다. **2485 passed / 0 failed** — 서버 1533 + 클라 952.

```
신설   PlayerStateServiceTests      33          (f28f8b0)
       PlayerStateClientTests       15          (f28f8b0)
       CoreScreensTests             47          (3229ce0)
       RebirthRequestServiceTests   10          (6e5c27d)
       RebirthWindowTests           38          (6e5c27d)
갱신   StoreTests                   32  → 30    싱글톤에 쓰지 않음 (89b4877)
유지   나머지 45행
```

그 전 갱신: **2026-10-22 Studio Play 런타임 실측 (전량, 드론 폐기 뒤 · 리포트 끈 Play).** 46개 행 전부가
한 Play에 찍혔다. **2344 passed / 0 failed** — 서버 1490 + 클라 854.

```
삭제   DroneServiceTests        32          드론 폐기 (f2014e1, 태그 drone-archive-2026-10-21)
갱신   ConfigTests              73  → 71    DroneConfig 검사 2개 삭제 (f2014e1)
       AssetRegistryTests      130  → 125   icon_drone 삭제 (8f6f59f)
유지   나머지 44행
```

직전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 공허 훈련 구역 뒤 · 리포트 끈 Play).** 47개 행 전부가
한 Play에 찍혔다. **2383 passed / 0 failed** — 서버 1529 + 클라 854.

```
갱신   GymServiceTests          28  → 41    공허 훈련 구역 (4943356)
       SuccessRateReportTests   58  → 60    공허 구매자 (4943356)
유지   나머지 45행
```

직전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 운동기구 뒤 · 리포트 끈 Play).** 47개 행 전부가
한 Play에 찍혔다. **2368 passed / 0 failed** — 서버 1514 + 클라 854.

```
신설   GymServiceTests          28          (cb215b3)
갱신   CurrencyServiceTests     51  → 59    lifeBlox (3fc5262)
       MigrationsTests          20  → 25    v4 (3fc5262)
       RebirthServiceTests      66  → 71    11단계 (3fc5262)
       ConfigTests              71  → 73    1·3 사다리 (3fc5262)
       SuccessRateReportTests   52  → 58    운동기구 훈련 (cb215b3)
유지   나머지 41행
```

직전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 문턱 구간 비교 뒤 · 리포트 끈 Play).** 46개 행 전부가
한 Play에 찍혔다. **2314 passed / 0 failed** — 서버 1460 + 클라 854.

```
갱신   SuccessRateReportTests   42  → 52    문턱 구간 비교 (55cbcf0)
유지   나머지 45행
```

그 전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 워프 비교 뒤).** 46개 행 전부가 한 Play에
찍혔다. **2304 passed / 0 failed** — 서버 1450 + 클라 854.

```
갱신   SuccessRateReportTests   28  → 42    워프 비교 (41b455c)
유지   나머지 45행
```

그 이전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 성공률 시뮬레이터 뒤).** 46개 행 전부가 한 Play에
찍혔다. **2290 passed / 0 failed** — 서버 1436 + 클라 854.

```
신설   SuccessRateReportTests   28          (e145f36)
유지   나머지 45행
```

더 이전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 발판 켜짐 뒤).** 45개 행 전부가 한 Play에
찍혔다. **2262 passed / 0 failed** — 서버 1408 + 클라 854.

```
신설   CashoutPadViewTests      23          (b67be37)
유지   나머지 44행 (CashoutPadServiceTests 47은 색 검사 1건 교체라 개수 같음)
```

그보다 전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, U3-10b 뒤).** 44개 행 전부가 한 Play에
찍혔다. **2239 passed / 0 failed** — 서버 1385 + 클라 854.

```
갱신   CashoutPadServiceTests   46  → 47    UiTheme 색 (ef50c2b)
       HudLayoutTests          381  → 407   검사 7·8 (fa026b1)
유지   나머지 42행
```

그보다 더 전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 런 생명주기 4단계 뒤).** 44개 행 전부가
한 Play에 찍혔다. **2212 passed / 0 failed** — 서버 1384 + 클라 828.

```
갱신   CashoutPadServiceTests   40  → 46    층 불일치 무시 (dbd7411)
신설   EntranceGateServiceTests 25          RunDeathServiceTests      9
       (5af8110 · 70c9865)
유지   나머지 41행 (RebirthServiceTests 66은 검사 1건 교체라 개수 같음)
```

한참 전 갱신: **2026-10-21 Studio Play 런타임 실측 (전량, 3c 뒤).** 42개 행 전부가 한 Play에
찍혔다(LogService 필터 읽기 — CLAUDE.md 절대 규칙 8). **2172 passed / 0 failed** — 서버 1344 + 클라 828.

```
갱신   ArenaServiceTests        31  → 119   바닥 파생·파트 상한 분할(b5f7e18) 포함
신설   AdvanceWallViewTests     97          AdvanceWallServiceTests  26
       AdvanceWallRendererTests 62          (3c — af70b06 · d6fd191)
유지   나머지 38행
```

훨씬 전 갱신: **2026-09-06 Studio Play 런타임 실측 (전량).** 39개 행 전부가 한 Play에
찍혔다. **1899 passed / 0 failed** — 서버 1133 + 클라 766.

```
갱신   AttackServiceTests       41  → 73    낡은 원점 계약 1건을 3건으로,
                                            방향 독립 1건을 2건으로 나눔 + 경계 파생 1건
       BlockServiceTests        30  → 51
       ConfigTests              70  → 71    스테이지 N의 입구 X (5f908fb)
       LayoutTests              20  → 22
유지   나머지 35행
```

⚠️ **합계 줄이 실측으로 채워진 것은 이번이 처음이다.** 그전까지는 "전체 Play
로그가 한 번에 나올 때까지 합계를 임의로 계산하지 않는다"고 유예해 뒀고,
그 조건이 이번에 충족됐다 — 39개 행이 같은 Play에서 자기 줄을 찍었다.

⚠️ 그렇다고 **합계 대조로 개별 행을 검산하지 말 것.** 위 ⚠️ 문단(상쇄 사고)이
그대로 유효하다. 행 수와 합계가 안 맞으면 계산이 아니라 **옮겨 적기**를 다시 본다.

⚠️ 이 Play가 `733e060`(테스트 6건 수정)의 검증이기도 하다. 직전 Play의
`AttackServiceTests` 3 failed · `BlockServiceTests` 3 failed가 전부 사라졌다
(→ 4-2-a2b 절, `docs/PENDING.md` 해소 기록·함정 절).

직전 갱신: **2026-09-04 Studio Play 런타임 실측 (부분).** U3-9 격리 + 4-2-a 아레나
배치가 낳은 행들을 반영했다. 합계는 이때 재지 않아 1218로 남아 있었다.

```
갱신   ConfigTests              61  → 70    ArenaConfig.validate + 파생 검사 5건
       ChallengeServiceTests    51  → 74    스폰 복귀 8절
       StoreTests               18  → 32    Store.new() 인스턴스 격리 검사
       HudVisibilityTests       16  → 31
       HudLayoutTests          198  → 381
신설   PowerBlockTests          49          ArenaServiceTests        31
       ShopSlotsTests           34          CashoutPadServiceTests   40
       AutoToolsTests           28
유지   PadServiceTests 31 · AttackServiceTests 41 · AttackConfigTests 29
       (4-2-a 원점 이동이 이 셋을 하나도 안 깼다는 것이 확인 목적이었다)
```

⚠️ `BloxDisplayTests`(13)는 그 Play에서 **1 fail**이 났으나 개수는 그대로였다.
코드 회귀가 아니라 인셋을 두 번 재는 하네스 문제였고 `5174bdb`에서 해소됐다
(→ `docs/PENDING.md` 함정 "create 시점의 환경값과 검사 시점의 환경값").

직전 갱신: **2026-09-01 Studio Play 런타임 실측.** 1218 passed / 0 failed (33개 행).
U3(UI 뼈대 + HUD 3종) 테스트 11행 추가 — `TextScaleTests`(16) · `ScreenControllerTests`(29) ·
`StoreTests`(18) · `PanelTests`(19) · `ButtonTests`(37, 실측값) · `ValuePanelTests`(15) ·
`LayoutTests`(20) · `BloxDisplayTests`(13) · `ChallengeInfoTests`(17) · `MenuRailTests`(58, 실측값) ·
`HudVisibilityTests`(16, 실측값). 960 → 1218.

직전 갱신: 2026-08-31 Studio Play 런타임 실측. 960 passed / 0 failed (22개 행).
Phase 6 착수 산출물(UiTheme/AssetRegistry/AssetImage) 테스트 3행 추가 —
`UiThemeTests`(33) · `AssetRegistryTests`(130, 실측값) · `AssetImageTests`(16). 781 → 960.

직전 갱신: 2026-08-29 Studio Play 런타임 실측. 747 passed / 0 failed (18개 행).
`AttackConfigTests` 38 → **29**, `ClickServiceTests` 38 → **47**로 정정.
두 오차가 정확히 상쇄돼 있어(-9 / +9) 합계와 행 수는 바뀌지 않았다.

직전 갱신: 2026-08-28 실측 747 (18개 행).
4-2-e2로 `AttackConfigTests` · `AttackServiceTests` 두 행 추가, `ConfigTests` 58 → 59.

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
maxStage    환생 시 리셋. 워프는 참조하지 않음. 드론 폐기 뒤로 읽는 규칙 없음 (docs/PENDING.md)
워프        전 구간 유료. 진행 상태 무관한 순수 함수
레벨        힘의 지수 기반. 레벨당 최대 이동속도 +1
커스텀스피드  저장 안 함. 접속·환생 시 최대로 리셋. 서버 검증 필수
클릭패드     월드별 세트 + 세트 내 lifeBlox(이번 생애 누적) 순차 해금 — 환생하면 다시 잠김.
            파워 2배씩 / 조건 1·3 사다리. 월드 첫 패드는 조건 0
운동기구     환생 수로 해금(환생해도 유지) + 로벅스 전용 공허. 기구 위 클릭에만 배수
월드 1       25층. 클리어 시 자동 전환.
            다음 월드 없으면 진행 벽 막힘 (정식 동작)
커브         HP 세그먼트(값은 WorldConfig — 2026-10-21 확정), 보상 고정 2.7. 정지선 37%
목표 성공률   구간별 95% / 65~85% / 40~55%
```

⚠️ 이 목록은 "무엇이 결정됐는지"의 색인이다.
   수치와 근거의 원본은 `DESIGN.md` — 여기로 복사하지 말 것.

### Phase 4-2 — 성장 구현 (코드)

착수 순서대로. 앞이 뒤의 선행 조건이다.

```
a  진입점 배선          ✅  2026-10-20 진행 벽(3c)으로 완료
a2 블록 렌더링 클라 이관 ✅
a3 입장 게이트 + 런 생명주기 ✅  2026-10-21 Play 검증 (아래 4-2-a3)
b  클릭 파워 패드        ✅
c  레벨 + 커스텀 스피드  ✅
d  RebirthService       ✅  2026-08-27 Play 검증 (잔여 1건 — 아래 참조)
e  WarpService          ✅  2026-08-28 Play 검증
e2 근접 자동 공격        ✅  2026-08-28 Play 검증 (747 passed / 0 failed)
f  실측 튜닝            ◐  시뮬레이션 기준 완료 (HP 곡선 · 운동기구 · 패드 가격). 실플레이 대기: 패드 시작 파워 · 워프 가격
```

✅ `a`는 더 이상 ◐가 아니다. 수령 발판(3b)·진행 벽(3c) 파트가 `cashout()`·`advance()`를
부르고, 입장 게이트(a3)가 `startRun()`을 부른다. 파트는 지금 코드가 세우는 임시 모양이고
디자인 담당 에셋으로 교체할 수 있다(→ `docs/UI_ASSET_SPEC.md` "5-1"). d·e(환생·워프)의
진입점은 여전히 Phase 6 UI 몫이다.

각 항목의 **[착수 전 확정]** 은 설계가 덜 끝난 부분이다. 지금은 근거가 없어
정할 수 없고, 해당 모듈 구현 직전에 정한다. 미리 찍어두면 근거 없는 수치가
코드에 박힌다.

#### 4-2-a. 진입점 배선 [선행 조건] ✅ 완료

**2026-09-04 Play 검증.** 아레나 3D 배치가 실물에서 돌았다.

```
✅ 원점 이동        패드가 스폰 구역으로 (X -380~-104). PadService/Attack 테스트 무영향
✅ ArenaConfig      좌표 정본. 1차 상수 셋(STAGE_WIDTH/GAP_WIDTH/SPAWN_X)에서 전부 파생
✅ 3a 스폰·경계     SpawnLocation + 경계 벽 + 어깨 벽
✅ 3b 수령 발판     밟으면 지급된다 — 로그 실측
                    reason=challenge_cashout_cashout_pad_stage_1, 한 줄만(디바운스 동작)
✅ 3d 스폰 복귀     수령·실패·포기(환생·런 중 사망)가 ChallengeService.endRun 하나를 지난다
                    수령 뒤 dist=399.4 관측
✅ 3c 진행 벽       걸어서 통과하면 advance — 2026-10-20 Play, 1→8층 층마다 1회·거부 0줄
                    클라 렌더 벽(막기·표시) + 서버 트리거(판정 신호) 두 파트
✅ 3a 보강 바닥     스폰 한 장 + 챌린지 구간을 파트 상한으로 나눈 여러 장, 먼 층도 바닥 위
```

**3c 결과 (2026-10-20 ~ 10-21).** 커밋 `af70b06`(계산 계층 — 크기 파생 · `AdvanceWallView` ·
`LevelConfig` 깊이 소스) → `d6fd191`(`AdvanceWallService` 트리거 · `AdvanceWallRenderer` ·
벽 중심 좌표 계약) → `b5f7e18`(바닥 분할) → `5bebdf2`(`ADVANCE_VERIFY_ENABLED` 잔재 제거 —
벽이 진입점을 대신한다). 구조와 근거는 `DESIGN.md` "1. 챌린지 > 진행 벽".
✅ 닫힌 벽 막힘은 2026-10-21 환생 직후 Play에서 관측했다(→ `docs/PENDING.md` 해소 기록). ⚠️ 최종층 벽은 **아직 관측하지 못했다** (→ `docs/PENDING.md` 미결).

✅ **선행 조건이던 4-2-a2b가 끝났다** (2026-09-05). 블록이 스테이지 중심으로 가고
서버 거리 판정도 같은 자리를 기준으로 잰다 — "통과하면 다음 블록이 정면에 있다"가
성립한다. 좌표는 `ArenaConfig.getAdvanceX()`에 이미 있다.

벽 개폐는 블록(4-2-a2)과 같은 이유로 **클라 렌더링**이다 (→ `DESIGN.md` "1. 챌린지 > 진행 벽").

관련 커밋: `c9d0698` `87e72bb` `e612268` `fde74f8` `437590f` `0504a46` `0534ea8`

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

#### 4-2-a2b. 블록을 스테이지 중심으로 이동 ✅ 완료 (Play 검증됨)

**2026-09-05 구현.** `e2d5b4f`(계산 계층) + `cdc44a6`(판정 원점 + 렌더 셋 + 테스트).
**2026-09-06 Play 검증 완료.** 진행 벽(3c)이 없어 `Bootstrap`의
`ADVANCE_VERIFY_ENABLED`(`5f908fb` + `dfee635`)가 벽을 대신했다. 플래그는 3c 완료 뒤
`5bebdf2`에서 지웠다 — 지금은 벽이 진입점이다.

```
[Bootstrap][ADVANCE] stage=1->2 x=120.0 result=ok
[Bootstrap][ATTACK]  result=ok dist=80.1/92.8 (in)
```

⚠️ **두 줄이 함께 있어야 검증이다.** 첫 줄은 층이 바뀌었다는 것만 말하고, 판정과
렌더가 **둘 다** 따라왔다는 것은 둘째 줄의 `dist`가 말한다 — 스테이지 1 입구에서
나온 값과 같은 값이 스테이지 2 입구에서 재현됐다(같은 상대 위치이므로 같아야 한다).
한쪽만 옮겨졌을 때의 네 갈래는 `docs/PENDING.md` 해소 기록에 있다.

**같은 Play에서 테스트 6건이 fail로 나왔다.** `AttackServiceTests` 66 passed /
3 failed, `BlockServiceTests` 48 passed / 3 failed. 여섯 건 전부 **테스트 쪽**
문제였고 판정 코드는 건드리지 않았다 — `733e060`. 스테이지 1(X=0)은 전부 통과하고
오프셋이 붙는 층에서만 깨졌다: 위 ⚠️의 "1층만 보면 멀쩡해 보인다"가 게임이 아니라
테스트에서 실제로 일어난 사례다. 원인과 처리는 `docs/PENDING.md` 해소 기록·함정 절.

✅ **2026-09-06 Play에서 6건 전부 사라졌다.** `AttackServiceTests` 73 · 
`BlockServiceTests` 51로 둘 다 0 failed다(위 개수는 수정 **전** 값이다). 그 Play가
전량 실측이라 "테스트 현황"의 합계 줄도 이때 처음 실측으로 채워졌다.

```
BlockLayout.getStageOrigin(stage)     유일한 유도처. 200을 여기서만 계산한다
computeLayout(count, stage?)          그 원점을 더해 돌려준다
AttackService                         clusterOriginFor(run.stage) — 같은 함수
BlockService.buildBlockSet            stage를 좌표까지 실어보낸다
RemoteReceiver.buildModels            같은 함수로 클라 렌더
BlockModelGenerator.previewLayout     stage 선택 인자 (커맨드 바 도구라 사슬이 없다)
```

⚠️ **넷이 같은 함수를 통과하는 것이 이 작업의 전부다.** 한 곳이라도 자기 식으로
계산하면 "블록이 보이는데 안 맞는" 상태가 되고, 그 증상은 층을 옮겨야만 나타나서
1층만 보면 멀쩡해 보인다.

⚠️ 판정 반경 92.8은 안 건드렸다. `OUTER_RADIUS`가 클러스터 **중심으로부터의** 거리라
클러스터가 어디로 가든 같다 — 원점만 움직였다.

--- 이하 착수 당시 기록 ---

블록이 **어느 층이든 원점(X=0) 한 자리에** 섰다. `BlockLayout.computeLayout`이
클러스터 안의 상대 좌표만 주고 stage 오프셋을 받지 않기 때문이고,
서버(`BlockService`)도 클라(`RemoteReceiver`)도 그 값을 그대로 쓴다.

4-2-a에서 아레나가 +X로 늘어서면서 이것이 문제가 됐다. 스테이지 N의 블록 중심은
`ArenaConfig.getStageCenterX(N)` = 200×(N-1)이어야 하는데 실제로는 전부 0이다.
그래서 **진행 벽을 세워도 통과한 자리에 다음 블록이 없다** — 뒤에 있다.

```
지금    스테이지 1·2·3 블록이 전부 X=0
필요    스테이지 N 블록이 X = 200×(N-1)
```

⚠️ **"판정 좌표 = 표시 좌표" 계약이 얽힌다.** `BlockLayout.lua` 상단이 못박은
것이고, 오프셋을 한쪽에만 더하면 서버의 "가까운 블록부터" 판정이 통째로 틀어진다.
서버·클라가 **같은 함수로 같은 오프셋**을 얻어야 한다.

⚠️ `AttackService`의 거리 판정 원점도 함께 옮겨야 한다. 지금은 클러스터 중심이
원점이라는 전제로 거리를 재는데, 스테이지 3에 있으면 원점에서 400 떨어져 있다 —
그대로 두면 어느 층에서든 `out_of_range`가 된다.
판정 반경 자체(`AttackConfig.getRadius()`, 92.8)는 건드릴 일이 없다. 스테이지 폭
160의 절반보다 크다는 관계는 원점이 어디든 그대로다.

⚠️ 오프셋을 `BlockLayout.computeLayout`에 넣을지, 부르는 쪽에서 더할지는 착수 시
정한다. 그 함수에 `player` 인자를 붙이지 말라는 경고는 여전히 유효하다 —
stage는 플레이어별 값이 아니라 런 상태값이므로 그 경고와 충돌하지 않는다.

번호를 a2 뒤에 붙인 이유: 같은 "블록이 어디에 서는가" 문제의 연장이고,
4-2-a의 남은 조각(3c 진행 벽)이 이것을 기다렸다 (3c 완료 → 4-2-a 절).

#### 4-2-a3. 입장 게이트 + 런 생명주기 ✅ 완료

**2026-10-21 Play 검증.** 런이 언제 서고 언제 끝나는가를 유저 행동에 묶었다.
규칙과 근거는 `DESIGN.md` "1. 챌린지 > 런 시작".

```
✅ 입장 게이트      지나는 순간 1층 런 (EntranceGateService)      5af8110
                    걸어서 통과: start timeLeft 20.0 → 1층 클리어 때 19.8
✅ 환생 런 미시작   RebirthService 9단계(startRun) 삭제            70c9865
✅ 사망 = 포기      Humanoid.Died → abandonRun (RunDeathService)   70c9865
                    Esc 리셋: abandon 통지 1회 · 스폰 리스폰
✅ 발판 층 일치     밟은 발판 층 ≠ 런 층이면 무시                  dbd7411
                    2층 런에서 1층 발판 위: cashout 0 / 2층 발판: 1회
✅ 잔재 제거        DRONE_VERIFY_ENABLED · KEEP_RUN_ALIVE           5195114
```

`Bootstrap` `VERIFY_CHALLENGE`는 이제 `startRun`을 직접 부르지 않는다 — 캐릭터를 게이트
앞에 세우고 서버 `Humanoid:MoveTo`로 지나가게 한 뒤 게이트가 세운 런을 기다린다.
그래서 매 Play가 게이트를 저절로 검증한다(로그 "게이트가 런을 세움 = true").

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

⚠️ **2026-10-21 정정 — 환생은 런을 세우지 않는다.** 원래 마지막 단계(9)가 1층 런을
세웠으나 지웠다(`70c9865`). 환생은 진행 중 런을 버리고(3단계 → 스폰 복귀) 속도를
재적용하는 데서 끝나고, 다음 런은 입장 게이트가 세운다(4-2-a3). 같은 날 개발 계정
실제 환생 1회로 확인: 환생 뒤 런 시작 줄 0, WalkSpeed 36.0 → 16.0.

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

✅ **2026-10-22 진입점이 붙었다 (f4fe428, 지시서 #6).** 월드·워프 창 → `WarpRequest` →
`WarpRequestService`(빈도 상한) → `WarpService.warp(player, stage, "ui")`. 서버가 다시 판정한다.
W1(런 중 거부) · W2(차감 → 목표층 입구 이동 → 런 시작)가 함께 들어갔다 — 규칙은 `DESIGN.md` "워프 실행 규칙".
Bootstrap `WARP_VERIFY_ENABLED` 블록은 같은 커밋에서 지웠다(잔재 조건 "Phase 6 UI 진입 후" 충족).

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

✅ **`result=out_of_range` 실물 관측됨** (2026-09-04, 2026-10-21 재관측 — 반경 밖 ↔ 안 전이).
**거리 폴링을 택한 근거 자체**라 남겨 둔다 — 반경이 아레나를 덮어버리면 "이름만 거리 폴링인
상시 발동"이 되고, 그것을 가르는 것은 이 로그 한 줄뿐이다 (상태 원본 → `docs/PENDING.md`).

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

⚠️ 마진은 파워 1과 **같은 성격의 임시값**이다.
4-2-f 실측 튜닝 대상이다 — 확정값으로 취급하지 말 것.
(`bloxBase` = 1은 여기 포함되지 않는다 — 2026-08-30에 확정값으로 종료됐다. 아래 4-2-f 절 참조)

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

⚠️ 위 실측은 수령 발판 · 진행 벽 · 스폰 지점 · 물리적 아레나 경계가 **놓이기 전**의 것이다.
그것들은 이제 전부 배치됐다(4-2-a ✅). 배율을 만질 일이 생기면 배율만 만지지 말고
지금 배치에서 실측부터 다시 낼 것.

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
`VERIFY_CHALLENGE`는 런을 세우고(2026-10-21부터는 입장 게이트가 세운다) 블록 개수를 찍은 뒤
3초 기다렸다가 클리어 여부를 본다.
통째로 끄지 않은 이유는 런 진입·`getSnapshot`·`cashout` 검증이 관측 밖으로 나가기
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

✅ 4-2-e2로 두 조건 모두 해소됐고, `bloxBase` = 1도 확정값으로 종료됐다(아래) — 남는 미결 없음.

⚠️ **측정 전에 힘을 초기화할 것.** 힘이 프로필에 누적돼 있으면 1층이 0.1초에 끝난다
(2026-08-28 관측: `str=5513`, `timeLeft=19.8`). 이전 세션의 클릭이 측정값을 오염시킨다
(→ `docs/PENDING.md`).

성공률 데이터를 보고 HP/보상 커브를 조정한다.
Phase 4-1의 수치는 레퍼런스 기반 후보값이다 (→ Phase 3-5에서 이월된 작업).

✅ **[착수 전 확정] 해소 — `bloxBase` = 1은 확정값이다. 튜닝 축에서 제외한다** (2026-08-30).

검증: `ClickPadConfig` 의 층별 보상과 패드 해금 조건이 둘 다
`bloxBase`에 선형이라(`reward(stage) = bloxBase × f(stage)`,
`padUnlock(index) = bloxBase × g(index)`), 비율에서 `bloxBase`가
정확히 약분된다 — "`bloxBase`를 올리면 패드가 일찍 열린다"는 성립하지 않는다.
직접 채널이 약분되므로 실효 손잡이가 아니라 **단위 기준점**이다.

근거와 관계 서술 → `DESIGN.md` "4-2-f 튜닝 지도 > bloxBase — 보상의 기준점".
상태 원본은 `docs/PENDING.md` 해소 기록. 수치는 여기로 복사하지 말 것.

✅ **[우선순위 3] 종료 — `BLOX_PER_REBIRTH` = 1000 확정. 튜닝 대상에서 제외한다** (2026-08-30).

`StandardPathReport` BLOX_PER_REBIRTH 스윕(기준값의 0.25 / 0.5 / 1 / 2 / 4배 ×
클릭률 3종, 15개 조합) 실측 결과 두 가지를 확정했다:

1. **단가는 후반 환생 리듬을 바꾸지 못한다.** 마지막 세 번의 환생 간격이 다섯 배수
   전부에서 0.6~1.0분으로 수렴했다. 단가가 실효를 갖는 곳은 초반 페이싱(첫 환생
   시각·25층 총 소요)뿐이다 — 0.25배는 첫 환생이 2.5~3.2분으로 너무 일러 결단의
   무게가 없고, 4배는 25층 도달이 91~118분으로 월드2 없는 현재 구조에서 이탈
   구간이다. 기준값(1배)은 첫 환생 4.3~5.4분 / 25층 도달 45~58분으로 그 사이다.
2. **패드 개수 미결도 함께 종료됐다.** 스윕 전 구간(0.25~4배)에서 25층 첫 도달
   시점 패드가 21~23 사이에서만 나왔다 — 24는 어떤 단가로도 나오지 않는다.
   즉 "25층 이후 남는 패드가 4개"라는 서술은 틀렸고, 실측대로 **2개(23·24)**가
   맞다. 이 결론은 환생 단가를 조정해도 바뀌지 않는 구조적 결론이다.

근거와 서술 수정 → `DESIGN.md` "4-2-f 튜닝 지도 > 조정 대상과 원본 위치" 표,
"클릭 파워 패드 > 세트는 월드1 통과용이 아니다". 상태 원본은 `docs/PENDING.md`
해소 기록. 수치는 여기로 복사하지 말 것.

⚠️ 후반 환생 간격(0.6~1.0분)이 그 자체로 새 미결이다 — `docs/PENDING.md` "미결" 참조.

✅ **[우선순위 4] 종료 — `WarpConfig` TEMP 두 값 중 BASE만 100 → 10으로 조정.
RATIO(3.0)는 유지. ⚠️ 최종 확정이 아니다** (2026-08-30).

`WarpConversionReport` 실측(층별 워프 비용을 그 층 보상·환생 단가·`StandardPathReport`
실측 벌이 속도로 환산) 결과, BASE = 100은 어느 층이든 100판 이상이라는 바닥을 깔아
워프를 사치품이 아니라 사실상 못 쓰는 사문으로 만들고 있었다. 10으로 내리면
판어치가 10(1층) → 125(25층)로 내려와 사치품이되 도달 가능한 자리가 된다.
RATIO는 정상 진행 하한(보상 성장률 2.7) 위이고 25층 누적 12.5배가 "후반이
상대적으로 비싸진다"는 의도를 이미 만들고 있어 건드리지 않았다.

⚠️ **TEMP 접두어는 유지한다.** 이번 결정은 "사문을 벗어난 자리"이지 `bloxBase`·
`BLOX_PER_REBIRTH`처럼 튜닝 축에서 제외되는 최종 확정이 아니다.

근거와 서술 → `DESIGN.md` "4-2-f 튜닝 지도 > 워프 비용 두 값", 수치 원본은
`WarpConfig.lua` 상단 주석. 상태 원본은 `docs/PENDING.md` 해소 기록.

⚠️ **BASE를 내려도 워프는 환생과의 지갑 경쟁에서 구조적으로 진다** — 이번 실측이
새로 드러낸 미결이다. 환생은 절대 단가, 워프는 지수라 같은 지갑에서 후반으로
갈수록 환생이 무조건 이긴다. TEMP 두 값 튜닝으로는 못 고친다
(→ `docs/PENDING.md` "미결").

✅ **패드 시작 파워(`clickPadSet.basePower`) 1 → 2. ⚠️ 최종 확정이 아니다** (2026-08-30).

`StandardPathReport` 파워 스윕(기준값의 0.5/1/2/5/10배 × 클릭률 3종, 15개 조합)
실측 결과다. 1배는 1층 소요 7.0초로 방치형 첫인상 구간에서 너무 느렸고, 2배는
1층 5.0초 / 여유배수 15.73으로 튜토리얼 층으로 넉넉했다. 5배·10배는 반대로
무너진다 — 10배는 1층 2.1초 / 25층 18.4분이지만 도달 시점 패드가 21로 내려가
후반 성장 목표(패드 23·24)가 사라진다. 2배가 유지하는 것: 25층 41.1분, 도달
시점 패드 22(1배와 동일), 17층 여유배수 1.1~1.3.

⚠️ **이 판단은 시간 축이지 성공률 검증이 아니다.** 17층 여유배수가 배수와
무관하게 1.1~2.6으로 흩어져 단조성이 없었다 — 표준 플레이어가 정지선 규칙으로
늘 한계층에 붙어 있어 파워가 세져도 같은 성공률에 더 빨리 도착할 뿐이기
때문이다. 목표 성공률(1~8층 95% / 9~16층 65~85% / 17~25층 40~55%)에 실제로
드는지는 확률적 플레이어 모델이 없어 확인하지 못했다. TEMP 접두어를 유지한다.

근거와 서술 → `DESIGN.md` "4-2-f 튜닝 지도 > 패드 파워", 수치 원본은
`WorldConfig.lua` 상단 주석. 상태 원본은 `docs/PENDING.md`
"basePower 2는 시간 축 판단이다"(신규 미결).

◐ **확률적 플레이어 성공률 시뮬레이터 (2026-10-21 `e145f36`).** `SuccessRateReport` —
위 "basePower 2는 시간 축 판단" 미결이 기다리던 확률 모델이다. 사람 결정 모델로 처음 돌린
결과, 성공률은 HP 곡선보다 **진행 판단 규칙**에 더 크게 움직였다. 규칙이 정해져야 HP 곡선을
볼 수 있다. 규칙은 같은 날 사람 결정(남은 시간 50~90%)으로 정해졌고, 그 규칙으로 HP 곡선 후보
4종을 돌렸다.

✅ **HP 곡선 확정 (2026-10-21 `efaade6`) — 2.8 / 3.8 / 6.0.** 측정 기준 플레이어에서 전 층이
목표 성공률 ±10%p 안에 든다. 수치·후보 비교 원본은 `docs/PENDING.md` 해소 기록 "4-2-f HP 곡선",
곡선 값 원본은 `WorldConfig`. 남은 4-2-f: basePower(TEMP) 실플레이 재확인 · 워프 TEMP 값.

✅ **패드 리셋 + 운동기구 (2026-10-21 `3fc5262` · `cb215b3`, 사람 결정).** 패드는 이번 생애 블럭스
(`lifeBlox`)로 열려 환생하면 다시 잠긴다. 가격은 1·3 단위. 운동기구 8개는 환생 수로 열리고 기구 위
클릭에만 배수(`GymConfig` TEMP, 로벅스 선해금은 Phase 8). 9번 공허 훈련 구역은 로벅스 전용 ×100(`4943356`).
첫 기구는 첫 환생에 열리고 뒤로 갈수록 간격이 길어진다(`eddf85b` · `d07ef1e`, 지금 11.9분 → 58.5분).
25층 첫 진입은 46.7 → 75분으로 늦어졌다가 패드 가격 1/3(`b5c3c50`, 사람 결정)로 61.9분 (95.8 / 73.2 / 47.8%).
시간 축 리포트 재측정은 `docs/PENDING.md` 미결.

**착수 전에 읽을 것 → `DESIGN.md` "4-2-f 튜닝 지도".**
조정 대상이 서로 어떻게 물려 있는지(한쪽만 만지면 무엇이 조용히 어긋나는지)와
**Play에서 무엇을 재야 하는지**가 거기 있다. 측정의 선후 관계도 그 절에 있다 —
4-2-e2 Play 검증 전의 성공률은 측정값이 아니다.

---

## Phase 5 — 드론 — 폐기 (2026-10-21 사람 결정)

드론(maxStage 기반 자동 채집 · 오프라인 정산)은 2026-08-31 코드 완료 · Play 검증까지 갔지만 **폐기했다.**

```
이유   구현 부담이 크고, 이 장르에서 열심인 유저는 잠수를 태우므로 오프라인 수입의 중요도가 낮다
보관   git 태그 drone-archive-2026-10-21 (지우기 직전 상태)
삭제   f2014e1 (코드) · 8f6f59f (UI — 메뉴 레일 드론 → 워프, icon_drone)
저장   프로필 drones 필드는 다음 스키마 변경 때 정리 (571a960)
```

되살린다면 오프라인 수입이 아닌 다른 용도로 재설계한다 — 근거와 기록은 `DESIGN.md` "5. 드론".
"능동 플레이가 드론보다 분당 20~60배" 규약도 함께 폐기됐다.

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

코드 Phase 6은 `docs/UI.md` "UI Phase"의 U3~U8과 같은 작업이다. U2(에셋 제작)만
디자인 담당 몫이고, 배치는 전부 코드 담당이다 — 파이프라인이 "배치는 전부 코드로
한다"이므로 U3부터가 코드 진입 지점이다. 위 "코드 Phase와 독립 진행한다"는
U2 vs 코드 Phase 4~5 얘기였고, Phase 6에서 둘이 합류한다.

착수 조건 G1은 2026-08-23에 통과했다.

진행: 에셋 단일 교체점(`UiTheme`/`AssetRegistry`/`AssetImage`/`TextScale` — 에셋
부재 상태에서 U3를 시작하기 위한 것. 미도착 에셋은 역할색 Frame으로 대체된다) →
UI 뼈대(`ScreenController`/`Store`/`Panel`/`Button`/`ValuePanel`) →
HUD 3종(`BloxDisplay`/`ChallengeInfo`/`MenuRail`) 배치 — **여기까지 Play 검증 완료.**

U3-5(힘·레벨·속도 블록, `PowerBlock`) · U3-6(로벅스 구좌 `ShopSlots` + 자동 클리커
토글/자동 진행 버튼 `AutoTools`) · U3-7(토글 밝기 채널 정정)로 남은 HUD 4종의
코드가 전부 붙어 **HUD 7종 전체가 코드로는 완성됐다.**
✅ **2026-10-21 Play로 확인했다** — U3-8 순서표 1~8 · 10번 통과, 11번(메뉴 타일 크기)은 사람 결정으로 유지,
8번에서 나온 우하단 겹침은 U3-10b(`fa026b1`)로 고쳤다. 남은 것은 9번(모바일 해상도에서 토글 구분 —
MCP로 기기 해상도를 바꿀 수 없다) 하나다(→ `docs/PENDING.md` "다음 Play 검증 순서 (U3-8)").

```
상태 (2026-10-22, 지시서 #6 뒤)
U0 · U1   완료
U2        G1 통과(2026-08-23), G2(패널 2층) 대기. PNG 제작은 이제 지환 · 희준 둘 다(사람 결정)
U3        완료 — HUD 7종 · Play 확인 · U3-10b · 모바일 9번(Galaxy A06 시뮬레이션) 통과,
          HUD가 서버 값을 보인다(PlayerState 채널, f28f8b0). G4(세이프존)는 G1~G3 뒤
          폰 결함 수정(fd6cf4d) — 점프 버튼 자리 비키기 · 글자 하한 11px. 패드 표시 3장(55c3b05)
U4        완료 — 로딩 · 클리어 안내 · 실패 · 3D 안내 4종(3229ce0). 걸어서 1→8층 한 판 확인
환생 창   완료 — 메뉴 "환생" → 작은 창, 두 번 누름 확인, 서버 재판정(6e5c27d). 실제 환생은 아직 안 해 봤다
          (개발 계정 블럭스 부족 + 사람 승인 필요)
워프 창   완료 — 메뉴 "워프" → 작은 창, 층 목록 · 두 번 누름 확인 · 서버 재판정 · W1/W2(f4fe428).
          Play에서 1층 워프 1회 실행(32 → 22 블럭스, 1층 입구로 이동, 런 시작)
U5        업그레이드 1차 4종 완료(지시서 #7) — UpgradeConfig 정리(a030722) · UpgradeService + 효과 4종(c947e8b) ·
          시뮬레이터 S5 + TEMP 조정(92e8f67) · 상점 창(57f6bf7) · 환생 창 상점 안내(9fe3a7e).
          Play에서 이동 속도 1회 구매(165.49 → 65.49 블럭스, Lv 1, 최대 속도 20 → 21). 로벅스 구매 · 힘 배수 계단은 Phase 8
          남은 UI 결함 3건(구좌 가격 · 다음 해금 패드 · 워프 창 행 색, 1b728d5)
U6        미착수 (뽑기 — Phase 7과 같이)
첫 직접 플레이 피드백(지시서 #8, 2026-10-23)
          맵 템포(2ff2484) — 로비 재배치(패드 · 기구 통로 옆 2줄), 스테이지 폭 148 · 띠 24, 기본 이동 속도 16 → 32
            스폰 → 게이트 3.9초 · 층 → 진행 벽 5.4초(이론, 목표 4 · 5). 성공률 17~25층 53.8 → 60.8%(판단 대기)
          피드백(7753095) — 클릭 +숫자 팝업 · HUD 환생 배수 · 환생 안내 · 운동기구 3D 표시
          화면 정리(cc9d344) — 속도 줄 · 레벨 바 숫자 · 환생 창 목록 · 버려지는 양 0 · 최대 속도 도달 · 패드 · 기구 본체 색
          로그 접기(07d5a1f)
```

**다음: 사람이 다시 한 판(새 템포 · 환생 체감 · 기구 1 배수 — `docs/PENDING.md` "실플레이로 볼 것") → G2 확인(에셋 도착 시) → Phase 7 뽑기.**
(지시서 #6의 "사람이 직접 한 판"은 아직이다 — `docs/PENDING.md` "실플레이로 볼 것".)

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

--!strict
-- 화면 글자 원본 (지시서 #L1 K1). 키 → { en = 영어, ko = 한국어 }. **화면에 보이는 문장은 전부 여기 있다.**
-- 코드는 키로만 부른다: Locale.t(키, 자리 표시). 언어 고르기 · 없는 번역 처리는 Locale, 구조 · 절차는 docs/LOCALIZATION.md.
--
-- ===== 쓰는 법 ======================================================================================
--
--   한 줄에 항목 하나:  ["화면.항목"] = { en = "...", ko = "..." },
--   자리 표시 {name}:   영어 · 한국어가 같은 집합이어야 한다(LocaleTests · tools/check_strings.py가 잰다)
--   숫자:               Formatter로 만든 문자열을 자리 표시로 넣는다 — 이 표에 숫자 꼴을 두지 않는다
--   영어(K9):           짧게. 버튼은 명령형(Hatch · Equip · Claim). 문장 끝 마침표 없음(안내문만 마침표)
--   한국어:             지금 화면 문장 그대로(#L1에서 새로 쓰지 않았다)
--   ⚠️ 이 파일은 tools/check_strings.py · tools/export_localization_csv.py가 줄 단위로 읽는다. 한 항목을 여러 줄로 나누지 않는다.
--
-- ===== 용어집 (K8 — docs/LOCALIZATION.md "4. 용어집"과 같은 표. 바꿀 때 둘 다) ==========================
--
--   힘 Power · 블럭스 Blox · 환생 Rebirth · 환생 배수 Rebirth Multiplier · 층 Floor · 런 Run
--   수령 Claim · 수령 발판 Claim Pad · 진행 Advance · 진행 벽 Advance Wall · 입장 게이트 Entry Gate
--   클릭 파워 패드 Power Pad · 운동기구 Gym · 공허 훈련 구역 Void Training Zone · 워프 Warp
--   레벨 Level · 이동 속도 Speed · 업그레이드 Upgrade · 상점 Shop · 설정 Settings
--   칭호 Title · 아우라 Aura · 펫 Pet · 알 Egg · 부화 Hatch · 크래프팅 Craft · 놓아주기 Release · 장착 Equip
--   희귀도 Common · Rare · Epic · Legendary (아우라 · 펫)
--   칭호 6종 Novice · Apprentice · Destroyer · Champion · Legend · Mythic
--   강화 단계 Normal · Gold · Diamond · Rainbow
--   포션 Potion · 행운 Luck · 부스트 Boost · 자동 클리커 Auto Clicker · 자동 진행 Auto Advance
--   상품 이름은 대시보드 이름과 같은 꼴: x2 Power · Auto Clicker · Lucky Roll x5 (배수가 앞, 횟수가 뒤)
--   새 경제(#31): 광석 Ore · 곡괭이 Pickaxe · 제작 Craft · 토큰 Token · 교환 Exchange · 별 Star · 강화 Enhance · 가방 Bag · 코인 Coin
--
-- ===== 유럽 4개 언어 (지시서 #40 — AI 번역 · 원어민 검수 전) ==========================================
--
--   es · pt(브라질) · fr · de 문장은 언어마다 따로 있다: Localization/Lang/<코드>.lua — 한 줄에 ["키"] = "문장",
--   이 파일을 불러올 때 Entries[키][코드]로 합친다(아래 맨 끝). 그래서 Locale · 검사 · 내보내기는 한 표만 본다.
--   새 키를 여기에 넣으면 Lang 네 파일에도 한 줄씩 넣는다(없으면 en이 보인다 — check_strings가 "번역 없음"으로 알린다).
--   예외(지시서 #42 이름 번역 규칙): 고유 이름 키(꼴 목록 Localization/NameKeys.lua)는 UI 확정 전까지 en · ko만 — Lang 파일에 넣지 않는다.
--   이름이 든 문장은 이름을 직접 적지 않고 자리 표시({name})로 넣는다.
--   언어별 용어집은 docs/LOCALIZATION.md "4. 용어집" 둘째 표.

local Strings = {}

export type Entry = { en: string, ko: string?, es: string?, pt: string?, fr: string?, de: string? }

Strings.Entries = {
	-- ===== 공통 ==========================================================================================
	["common.reason.rate_limited"] = { en = "Please wait a moment and try again", ko = "잠시 뒤에 다시 눌러 주세요" },
	["common.reason.no_profile"] = { en = "Loading your data", ko = "데이터를 불러오는 중이에요" },
	["common.reason.insufficient_blox"] = { en = "Not enough Blox", ko = "블럭스가 모자라요" },
	["common.reason.invalid_request"] = { en = "Can't do that", ko = "할 수 없는 요청이에요" },
	["common.reason.partial_failure"] = { en = "Something went wrong. Please tell an admin.", ko = "문제가 생겼어요. 관리자에게 알려 주세요" },
	["common.reason.failed"] = { en = "Couldn't do that", ko = "하지 못했어요" },
	-- 자동 진행 중 워프 · 환생(지시서 #18 AA9) — 사유와 안내를 한 문장에
	["common.reason.auto_active"] = { en = "Auto Advance is on. Turn it off first.", ko = "자동 진행 중이에요. 자동 진행을 끄고 다시 해 주세요" },
	-- 자동 진행 설정 창 · HUD(지시서 #18)
	["auto.window.title"] = { en = "Auto Advance", ko = "자동 진행" },
	["auto.safe"] = { en = "Safe floor: Floor {n}", ko = "안전층 {n}층" },
	["auto.safeNone"] = { en = "No safe floor yet", ko = "아직 안전층이 없어요" },
	["auto.note.repeat"] = { en = "Claims at your target floor and repeats until you stop", ko = "목표층에서 자동 수령하고 멈출 때까지 반복해요" },
	["auto.note.boost"] = { en = "May change when boosts end", ko = "부스트가 끝나면 달라질 수 있어요" },
	["auto.target"] = { en = "Target floor", ko = "목표층" },
	["auto.targetValue"] = { en = "Floor {n}", ko = "{n}층" },
	["auto.start.safe"] = { en = "Start · Safe", ko = "시작 · 안전" },
	["auto.start.risky"] = { en = "Start · Risky", ko = "시작 · 도박" },
	["auto.status"] = { en = "Auto · Floor {target} · Run {runs}", ko = "자동 · 목표 {target}층 · {runs}회" },
	["auto.started"] = { en = "Auto Advance on", ko = "자동 진행을 켰어요" },
	["auto.stopped"] = { en = "Auto Advance off", ko = "자동 진행을 껐어요" },
	["auto.reason.run_active"] = { en = "Finish your current run first", ko = "지금 런이 끝난 뒤에 시작할 수 있어요" },
	["auto.reason.character_lost"] = { en = "Auto Advance stopped: character lost", ko = "캐릭터가 없어져 자동 진행을 껐어요" },
	["auto.reason.not_owned"] = { en = "You need {name}", ko = "{name}이 필요해요" }, -- {name} = 상품 이름 Auto Advance(#42 이름 규칙)
	["auto.reason.invalid_target"] = { en = "Pick a floor from 1 to {max}", ko = "1 ~ {max}층 중에서 골라 주세요" },
	-- ===== 이름 (K6 — Config id → 키. 만드는 곳은 Shared/Localization/Names) ==============================
	-- 희귀도(아우라 등급 · 펫 종 희귀도 공통)
	["rarity.common"] = { en = "Common", ko = "일반" },
	["rarity.rare"] = { en = "Rare", ko = "희귀" },
	["rarity.epic"] = { en = "Epic", ko = "영웅" },
	["rarity.legendary"] = { en = "Legendary", ko = "전설" },
	-- 리미티드 묶음(펫 — 지시서 #20 D4). 알 4등급 밖의 종 희귀도 칸
	["rarity.limited"] = { en = "Limited", ko = "리미티드" },
	-- 칭호 6종 (TitleConfig id)
	["title.name.novice"] = { en = "Novice", ko = "초보자" },
	["title.name.apprentice"] = { en = "Apprentice", ko = "견습생" },
	["title.name.breaker"] = { en = "Destroyer", ko = "파괴자" },
	["title.name.champion"] = { en = "Champion", ko = "챔피언" },
	["title.name.legend"] = { en = "Legend", ko = "레전드" },
	["title.name.mythic"] = { en = "Mythic", ko = "신화" },
	-- 아우라 20종 (AuraConfig id = pack<팩>_<희귀도>) — 영어 이름은 #L1에서 Claude가 지었다(바꿀 수 있다)
	["aura.name.pack1_common"] = { en = "Sparkle", ko = "반짝임" },
	["aura.name.pack1_rare"] = { en = "Flame", ko = "불꽃" },
	["aura.name.pack1_epic"] = { en = "Lightning", ko = "번개" },
	["aura.name.pack1_legendary"] = { en = "Aurora", ko = "오로라" },
	["aura.name.pack2_common"] = { en = "Gust", ko = "돌풍" },
	["aura.name.pack2_rare"] = { en = "Glacier", ko = "빙하" },
	["aura.name.pack2_epic"] = { en = "Lava", ko = "용암" },
	["aura.name.pack2_legendary"] = { en = "Comet", ko = "혜성" },
	["aura.name.pack3_common"] = { en = "Nebula", ko = "성운" },
	["aura.name.pack3_rare"] = { en = "Eclipse", ko = "일식" },
	["aura.name.pack3_epic"] = { en = "Supernova", ko = "초신성" },
	["aura.name.pack3_legendary"] = { en = "Black Hole", ko = "블랙홀" },
	["aura.name.pack4_common"] = { en = "Rift", ko = "차원균열" },
	["aura.name.pack4_rare"] = { en = "Distortion", ko = "시공왜곡" },
	["aura.name.pack4_epic"] = { en = "Collapse", ko = "붕괴" },
	["aura.name.pack4_legendary"] = { en = "Singularity", ko = "특이점" },
	["aura.name.pack5_common"] = { en = "Genesis", ko = "태초" },
	["aura.name.pack5_rare"] = { en = "Doomsday", ko = "종말" },
	["aura.name.pack5_epic"] = { en = "Eternity", ko = "영원" },
	["aura.name.pack5_legendary"] = { en = "Absolute", ko = "절대자" },
	-- 알 3종 (PetConfig 알 번호)
	["egg.name.1"] = { en = "Wood Egg", ko = "나무 알" },
	["egg.name.2"] = { en = "Stone Egg", ko = "돌 알" },
	["egg.name.3"] = { en = "Iron Egg", ko = "철 알" },
	-- 펫 12종 (PetConfig id = egg<알>_<희귀도>) — 영어 이름은 #L1에서 Claude가 지었다(바꿀 수 있다)
	["pet.name.egg1_common"] = { en = "Acorn", ko = "도토리" },
	["pet.name.egg1_rare"] = { en = "Squirrel", ko = "다람쥐" },
	["pet.name.egg1_epic"] = { en = "Owl", ko = "올빼미" },
	["pet.name.egg1_legendary"] = { en = "Ancient Treant", ko = "고대나무정령" },
	["pet.name.egg2_common"] = { en = "Pebble", ko = "자갈" },
	["pet.name.egg2_rare"] = { en = "Baby Golem", ko = "골렘새끼" },
	["pet.name.egg2_epic"] = { en = "Crystal Worm", ko = "크리스탈웜" },
	["pet.name.egg2_legendary"] = { en = "Mountain Spirit", ko = "산의정령" },
	["pet.name.egg3_common"] = { en = "Cog Rat", ko = "톱니쥐" },
	["pet.name.egg3_rare"] = { en = "Mech Hawk", ko = "기계매" },
	["pet.name.egg3_epic"] = { en = "Steel Drake", ko = "강철드레이크" },
	["pet.name.egg3_legendary"] = { en = "Machine God", ko = "기계신" },
	-- 리미티드 펫(일일 보상 7일째 — 지시서 #20 D4). 이름은 Claude가 지었다(바꿀 수 있다)
	["pet.name.limited_dawn"] = { en = "Dawn Phoenix", ko = "새벽불사조" },
	-- 펫 강화 단계 1 ~ 4 (종 희귀도와 다른 낱말 — E4 · G10)
	["pet.level.1"] = { en = "Normal", ko = "기본" },
	["pet.level.2"] = { en = "Gold", ko = "황금" },
	["pet.level.3"] = { en = "Diamond", ko = "다이아" },
	["pet.level.4"] = { en = "Rainbow", ko = "무지개" },
	-- 월드 (WorldConfig 번호)
	["world.name.1"] = { en = "Wood", ko = "나무" },
	-- 업그레이드 (UpgradeConfig 키)
	["upgrade.name.punchSpeed"] = { en = "Punch Speed", ko = "펀치 속도" },
	["upgrade.name.bloxGain"] = { en = "Blox Gain", ko = "블럭스 획득" },
	["upgrade.name.titleLuck"] = { en = "Title Luck", ko = "칭호 행운" },
	["upgrade.name.auraLuck"] = { en = "Aura Luck", ko = "아우라 행운" },
	["upgrade.name.petSlots"] = { en = "Pet Equip Slots", ko = "펫 장착 슬롯" },
	["upgrade.name.petLuck"] = { en = "Pet Luck", ko = "펫 행운" },
	-- 부스트(포션) — name = 상품 · 안내, short = HUD 남은 시간 줄
	["boost.strength.name"] = { en = "Power Potion", ko = "힘 포션" },
	["boost.damage.name"] = { en = "Damage Potion", ko = "데미지 포션" },
	["boost.luck.name"] = { en = "Luck Potion", ko = "행운 포션" },
	["boost.strength.short"] = { en = "Power", ko = "힘" },
	["boost.damage.short"] = { en = "Damage", ko = "데미지" },
	["boost.luck.short"] = { en = "Luck", ko = "행운" },

	-- ===== 상점 상품 (ShopConfig 키 — 대시보드 이름 · 설명도 이 영어를 쓴다. docs/DASHBOARD_PRODUCTS.md) =====
	["shop.autoClicker.name"] = { en = "Auto Clicker", ko = "자동 클리커" },
	["shop.autoClicker.desc"] = { en = "Clicks 15 times per second while on", ko = "켜 두면 초당 15번 자동으로 클릭해요" },
	["shop.autoClickerOP.name"] = { en = "OP Auto Clicker", ko = "OP 자동 클리커" },
	["shop.autoClickerOP.desc"] = { en = "Clicks 30 times per second while on", ko = "켜 두면 초당 30번 자동으로 클릭해요" },
	["shop.hatch3x.name"] = { en = "Triple Hatch", ko = "3배 부화" }, -- en = 대시보드 이름(#18 N1)
	["shop.hatch3x.desc"] = { en = "Hatch 3 eggs at once (3x cost)", ko = "알을 한 번에 3개 부화해요(비용 3배)" },
	["shop.petLuck2x.name"] = { en = "x2 Pet Luck", ko = "2배 펫 행운" },
	["shop.petLuck2x.desc"] = { en = "2x luck when hatching pets", ko = "펫 부화 행운이 2배예요" },
	["shop.petStorage100.name"] = { en = "+100 Pet Storage", ko = "+100 펫 저장 공간" },
	["shop.petStorage100.desc"] = { en = "Keep 100 more pets", ko = "펫을 100마리 더 보관해요" },
	["shop.damage2x.name"] = { en = "x2 Damage", ko = "2배 데미지" },
	["shop.damage2x.desc"] = { en = "2x damage per punch", ko = "1펀치 데미지가 2배예요" },
	["shop.petSlots3.name"] = { en = "+3 Pet Slots", ko = "+3 펫 장착" }, -- en = 대시보드 이름(#18 N1)
	["shop.petSlots3.desc"] = { en = "Equip 3 more pets", ko = "펫을 3마리 더 장착해요" },
	["shop.blox2x.name"] = { en = "x2 Blox", ko = "2배 블럭스" },
	["shop.blox2x.desc"] = { en = "2x Blox when you claim", ko = "수령할 때 받는 블럭스가 2배예요" },
	["shop.auraLuck10x.name"] = { en = "x10 Aura Luck", ko = "10배 아우라 행운" },
	["shop.auraLuck10x.desc"] = { en = "10x luck on Aura rolls", ko = "아우라 뽑기 행운이 10배예요" },
	["shop.titleLuck10x.name"] = { en = "x10 Title Luck", ko = "10배 칭호 행운" },
	["shop.titleLuck10x.desc"] = { en = "10x luck on Title rolls", ko = "칭호 뽑기 행운이 10배예요" },
	["shop.voidTrainingZone.name"] = { en = "Void Training Zone", ko = "공허 훈련 구역" },
	["shop.voidTrainingZone.desc"] = { en = "Unlocks the strongest Gym", ko = "가장 센 운동기구를 열어요" },
	["shop.autoAdvance.name"] = { en = "Auto Advance", ko = "자동 진행" },
	["shop.autoAdvance.desc"] = { en = "Keeps advancing up to your target floor", ko = "목표층까지 멈추지 않고 진행해요" },
	["shop.strengthTier.name"] = { en = "x{mult} Power", ko = "{mult}배 힘" },
	["shop.strengthTier.desc"] = { en = "x{mult} Power from clicks (only your highest tier applies)", ko = "클릭으로 얻는 힘이 {mult}배예요(가장 높은 단계 하나만)" },
	["shop.luckyRoll5.name"] = { en = "Lucky Roll x5", ko = "럭키 롤 5회" },
	["shop.luckyRoll5.desc"] = { en = "5 Aura rolls · Luck x5 · no Blox needed", ko = "아우라 뽑기 5회 · 행운 ×5 · 블럭스 없이" },
	["shop.luckyRoll15.name"] = { en = "Lucky Roll x15", ko = "럭키 롤 15회" },
	["shop.luckyRoll15.desc"] = { en = "15 Aura rolls · Luck x5 · no Blox needed", ko = "아우라 뽑기 15회 · 행운 ×5 · 블럭스 없이" },
	["shop.superRoll5.name"] = { en = "Super Roll x5", ko = "슈퍼 롤 5회" },
	["shop.superRoll5.desc"] = { en = "5 Aura rolls · Luck x100 · no Blox needed", ko = "아우라 뽑기 5회 · 행운 ×100 · 블럭스 없이" },
	["shop.superRoll15.name"] = { en = "Super Roll x15", ko = "슈퍼 롤 15회" },
	["shop.superRoll15.desc"] = { en = "15 Aura rolls · Luck x100 · no Blox needed", ko = "아우라 뽑기 15회 · 행운 ×100 · 블럭스 없이" },
	["shop.strengthPotion.name"] = { en = "Power Potion", ko = "힘 포션" },
	["shop.strengthPotion.desc"] = { en = "Power x2 for 15 minutes", ko = "15분 동안 힘 ×2" },
	["shop.damagePotion.name"] = { en = "Damage Potion", ko = "데미지 포션" },
	["shop.damagePotion.desc"] = { en = "Punch damage x2 for 15 minutes", ko = "15분 동안 1펀치 데미지 ×2" },
	["shop.luckPotion.name"] = { en = "Luck Potion", ko = "행운 포션" },
	["shop.luckPotion.desc"] = { en = "Title · Aura · Pet luck x2 for 15 minutes", ko = "15분 동안 칭호 · 아우라 · 펫 행운 ×2" },
	["shop.potionBundle.name"] = { en = "Potion Bundle", ko = "포션 번들" },
	["shop.potionBundle.desc"] = { en = "99 each of Power · Damage · Luck Potions", ko = "힘 · 데미지 · 행운 포션 각 99개" },
	["shop.gymUnlock.name"] = { en = "Gym {n} Unlock", ko = "운동기구 {n} 열기" }, -- en = 대시보드 이름(지시서 #17)
	["shop.gymUnlock.desc"] = { en = "Unlocks Gym {n} regardless of Rebirths", ko = "환생 수와 상관없이 운동기구 {n}을 열어요" },
	-- ===== HUD ===========================================================================================
	["hud.menu.shop"] = { en = "Shop", ko = "상점" },
	["hud.menu.rebirth"] = { en = "Rebirth", ko = "환생" },
	["hud.menu.warp"] = { en = "Warp", ko = "워프" },
	["hud.menu.aura"] = { en = "Aura", ko = "아우라" },
	["hud.menu.pet"] = { en = "Pets", ko = "펫 목록" },
	["hud.menu.settings"] = { en = "Settings", ko = "설정" },
	["hud.auto.clicker"] = { en = "Auto Click", ko = "자동클릭" },
	["hud.auto.advance"] = { en = "Auto Advance", ko = "자동진행" },
	["hud.challenge.idle"] = { en = "Waiting", ko = "대기 중" },
	["hud.challenge.stage"] = { en = "Floor {n}", ko = "스테이지 {n}" },
	["hud.power.rebirthMult"] = { en = "Rebirth Multiplier ×", ko = "환생 배수 ×" },
	["hud.power.maxSpeed"] = { en = "/ Max {n}", ko = "/ 최대 {n}" },
	["hud.slot.owned"] = { en = "Owned", ko = "보유" },
	["hud.boost.line"] = { en = "{name} {mult} {time}", ko = "{name} {mult} {time}" },
	-- ===== 3D 안내 (World/WorldLabelLogic — BillboardGui) ================================================
	["world.cashout.title"] = { en = "Claim", ko = "수령" },
	["world.cashout.reward"] = { en = "+{amount}", ko = "+{amount}" },
	["world.wall.title"] = { en = "Advance", ko = "진행" },
	["world.wall.nextReward"] = { en = "Next floor +{amount}", ko = "다음 층 +{amount}" },
	["world.wall.nextWorld"] = { en = "Next World", ko = "다음 월드" },
	["world.wall.comingSoon"] = { en = "Coming soon", ko = "준비 중" },
	["world.pad.power"] = { en = "Click {power}", ko = "클릭 {power}" },
	["world.pad.need"] = { en = "Need {amount}", ko = "필요 {amount}" },
	["world.gym.mult"] = { en = "Gym ×{mult}", ko = "기구 ×{mult}" },
	["world.gym.voidMult"] = { en = "Void ×{mult}", ko = "공허 ×{mult}" },
	["world.gym.inUse"] = { en = "In use", ko = "사용 중" },
	["world.gym.robuxOnly"] = { en = "Robux only", ko = "로벅스 전용" },
	["world.gym.robuxOnlySoon"] = { en = "Robux only (coming soon)", ko = "로벅스 전용(준비 중)" },
	["world.gym.need"] = { en = "Need {amount} Rebirths", ko = "필요 환생 {amount}" },
	["world.gym.buyPrompt"] = { en = "Unlock with Robux", ko = "로벅스로 열기" }, -- 잠긴 기구 프롬프트(지시서 #17)
	["world.gym.buyObject"] = { en = "{name} · {price}", ko = "{name} · {price}" },
	["world.gym.lockedNeed"] = { en = "Locked · Need {amount} Rebirths", ko = "잠김 · 필요 환생 {amount}" },
	["world.gate.title"] = { en = "Entry Gate", ko = "입장" },
	["world.gate.detail"] = { en = "Walk through to start", ko = "지나가면 시작" },
	-- ===== Overlay (로딩 · 오류 · 런 안내 · 결과 모달 · 환생 안내 · 클릭 팝업) ===============================
	["common.ok"] = { en = "OK", ko = "확인" },
	["overlay.loading"] = { en = "Loading...", ko = "불러오는 중..." },
	["overlay.error.loadingTimeout"] = { en = "The server isn't responding. Please rejoin.", ko = "서버 응답이 없습니다. 다시 접속해 주세요" },
	["overlay.run.cashout"] = { en = "Pad = Claim", ko = "발판 = 수령" },
	["overlay.run.advance"] = { en = "Wall = Advance", ko = "벽 = 진행" },
	["overlay.run.final"] = { en = "Claim only", ko = "수령만 가능" },
	["overlay.run.fail"] = { en = "Time's up · 0 earned", ko = "시간 초과 · 획득 0" },
	["feedback.popup"] = { en = "+{amount}", ko = "+{amount}" },
	["feedback.popup.gym"] = { en = "+{amount}  Gym ×{mult}", ko = "+{amount}  기구 ×{mult}" },
	["feedback.rebirth.title"] = { en = "Rebirth!", ko = "환생!" },
	["feedback.rebirth.reset"] = { en = "Power · Blox · best floor · pads start over", ko = "힘 · 블럭스 · 최고 층 · 패드는 처음부터" },
	["feedback.rebirth.change"] = { en = "Power multiplier ×{before} → ×{after}", ko = "힘 배수 ×{before} → ×{after}" },
	-- ===== 작은 창 — 설정 · 환생 · 월드 · 워프 ==========================================================
	["common.cancel"] = { en = "Cancel", ko = "취소" },
	["settings.title"] = { en = "Settings", ko = "설정" },
	["settings.on"] = { en = "On", ko = "켜짐" },
	["settings.off"] = { en = "Off", ko = "꺼짐" },
	["settings.hideOtherAuras"] = { en = "Hide other players' Auras", ko = "다른 사람 아우라 숨기기" },
	["settings.hideOtherPets"] = { en = "Hide other players' Pets", ko = "다른 사람 펫 숨기기" },
	["settings.reduceMotion"] = { en = "Reduce Motion", ko = "연출 줄이기" },
	["settings.sfxEnabled"] = { en = "Sound Effects", ko = "효과음" },
	["settings.reason.not_allowed"] = { en = "This setting can't be changed", ko = "바꿀 수 없는 설정이에요" },
	["settings.reason.bad_value"] = { en = "Invalid value", ko = "잘못된 값이에요" },
	["settings.reason.failed"] = { en = "Couldn't change it", ko = "바꾸지 못했어요" },
	-- 설정 창 → 코드 입력 창(지시서 #20 C6)
	["settings.codeButton"] = { en = "Enter Code", ko = "코드 입력" },
	-- ===== 일일 보상 (지시서 #20 D1 ~ D5) ===============================================================
	["daily.title"] = { en = "Daily Reward", ko = "일일 보상" },
	["daily.day"] = { en = "Day {n}", ko = "{n}일" },
	["daily.claim"] = { en = "Claim", ko = "받기" },
	["daily.claimed"] = { en = "Claimed", ko = "받음" },
	["daily.comeBack"] = { en = "Come back tomorrow", ko = "내일 또 받아요" },
	["daily.close"] = { en = "Close", ko = "닫기" },
	["daily.next"] = { en = "Next reward in {time}", ko = "다음 보상까지 {time}" },
	["daily.reward.blox"] = { en = "Blox", ko = "블럭스" },
	["daily.reward.count"] = { en = "x{count}", ko = "{count}개" },
	["daily.result.ok"] = { en = "Day {n} reward claimed!", ko = "{n}일째 보상을 받았어요" },
	["daily.reason.storage_full"] = { en = "Free up one pet storage slot", ko = "펫 보관함을 한 칸 비우세요" },
	["daily.reason.already_claimed"] = { en = "Already claimed today", ko = "오늘은 이미 받았어요" },
	["daily.reason.failed"] = { en = "Couldn't claim it", ko = "받지 못했어요" },
	["hud.daily"] = { en = "Daily", ko = "출석" },
	["hud.daily.badge"] = { en = "!", ko = "!" },
	-- ===== 코드 입력 (지시서 #20 C1 ~ C6 — 입력 글자는 되보이지 않는다) =========================================
	["code.title"] = { en = "Enter Code", ko = "코드 입력" },
	["code.placeholder"] = { en = "Type a code", ko = "코드를 입력하세요" },
	["code.submit"] = { en = "Redeem", ko = "확인" },
	["code.result.ok"] = { en = "Redeemed! {rewards}", ko = "받았어요! {rewards}" },
	["code.reason.not_found"] = { en = "That code doesn't exist", ko = "없는 코드예요" },
	["code.reason.already_redeemed"] = { en = "You already redeemed this code", ko = "이미 받았어요" },
	["code.reason.expired"] = { en = "This code has expired", ko = "만료됐어요" },
	["code.reason.too_many_attempts"] = { en = "Too many wrong codes. Try again in a minute", ko = "너무 많이 틀렸어요. 1분 뒤에 다시 해 주세요" },
	["code.reason.failed"] = { en = "Couldn't redeem it", ko = "받지 못했어요" },
	-- ===== 첫 접속 안내 (지시서 #20 O1 ~ O5) ==============================================================
	["onboarding.step.1"] = { en = "Click to grow your Power (10 clicks)", ko = "클릭해서 힘을 키워요 (10번)" },
	["onboarding.step.2"] = { en = "Walk through the gate to start a challenge", ko = "게이트를 지나 챌린지를 시작해요" },
	["onboarding.step.3"] = { en = "Clear floor 1 - stay near the blocks to auto-attack", ko = "1층을 깨요 - 가까이 있으면 자동으로 공격해요" },
	["onboarding.step.4"] = { en = "Claim on the yellow pad, or go through the purple wall", ko = "노랑 발판에서 받거나 보라 벽으로 진행해요" },
	["onboarding.step.5"] = { en = "Unlock pads with Blox. At 1000 Blox you can Rebirth", ko = "블럭스로 패드를 열어요. 1000이면 환생할 수 있어요" },
	["onboarding.step.4.v2"] = { en = "Yellow pad = claim · Purple wall = go on (fail = lose it)", ko = "노랑 발판 = 받기 · 보라 벽 = 진행(실패하면 잃어요)" }, -- #37: 폰 띠 두 줄에 들어가게 줄임
	["onboarding.tip.title"] = { en = "Tip", ko = "안내" },
	["onboarding.tip.blox"] = { en = "Blox! You get it when you claim. Spend it on Rebirth and the Shop", ko = "블럭스! 수령하면 받아요. 환생 · 상점에 써요" },
	["onboarding.tip.coins"] = { en = "Coins come in the moment a block breaks. You keep them even if you fail", ko = "블록을 깨면 코인이 바로 들어와요. 실패해도 남아요" },
	["onboarding.tip.bag"] = { en = "Ores go in your Bag. Claim to keep them", ko = "광석은 가방에 담겨요. 수령해야 내 것이 돼요" },
	["onboarding.tip.rebirth"] = { en = "You can Rebirth! Your Power multiplier goes up for good", ko = "환생할 수 있어요! 힘 배수가 영구로 올라요" },
	["onboarding.tip.craft"] = { en = "Forge: tap Auto Fill, then Craft to make a pickaxe", ko = "대장간: 자동 채우기 → 제작으로 곡괭이를 만들어요" },
	["onboarding.tip.equip"] = { en = "A better pickaxe! Open Equipment and equip it", ko = "더 좋은 곡괭이가 생겼어요! 장비에서 장착해요" },
	["onboarding.tip.egg"] = { en = "An egg is open! Hatch a pet with Coins in Pets", ko = "알이 열렸어요! 펫 목록에서 코인으로 부화해요" },
	["onboarding.progress"] = { en = "Step {n}/{total}", ko = "{n}/{total}단계" },
	["onboarding.skip"] = { en = "Skip", ko = "건너뛰기" },
	["onboarding.skipConfirm"] = { en = "Tap again", ko = "한 번 더" },
	["onboarding.finish"] = { en = "Got it", ko = "알겠어요" },
	["onboarding.done"] = { en = "Tutorial complete! {reward}", ko = "안내 끝! {reward}" },
	["rebirth.title"] = { en = "Rebirth", ko = "환생" },
	["rebirth.button"] = { en = "Rebirth", ko = "환생하기" },
	["rebirth.confirm"] = { en = "Press again to Rebirth", ko = "한 번 더 누르면 환생" },
	["rebirth.success"] = { en = "Reborn! Multiplier +{gained}", ko = "환생했어요! 배수 +{gained}" },
	["rebirth.blox"] = { en = "Your Blox", ko = "보유 블럭스" },
	["rebirth.gain"] = { en = "Multiplier gained", ko = "얻는 배수" },
	["rebirth.gainValue"] = { en = "+{gained}  (×{before} → ×{after})", ko = "+{gained}  (×{before} → ×{after})" },
	["rebirth.wasted"] = { en = "Wasted", ko = "버려지는 양" },
	["rebirth.resetsHeader"] = { en = "Reset on Rebirth", ko = "환생하면 초기화되는 것" },
	["rebirth.reset.blox"] = { en = "Blox → 0 (all spent)", ko = "블럭스 → 0 (전부 사용)" },
	["rebirth.reset.power"] = { en = "Power → starting value", ko = "힘 → 처음 값" },
	["rebirth.reset.floor"] = { en = "Best floor · current world → start", ko = "최고 층 기록 · 현재 월드 → 처음" },
	["rebirth.reset.pad"] = { en = "Power Pads → locked again (from pad 1)", ko = "클릭 파워 패드 → 다시 잠김 (패드 1부터)" },
	["rebirth.reset.speed"] = { en = "Max speed → recalculated from Power", ko = "최대 이동속도 → 힘에 맞춰 다시" },
	["rebirth.reset.run"] = { en = "Current run → ends, back to spawn", ko = "진행 중인 런 → 끝나고 스폰으로" },
	["rebirth.keeps"] = { en = "You keep: Rebirth Multiplier (goes up) · Gyms · lifetime Blox · Shop Upgrades", ko = "남는 것: 환생 배수(오름) · 운동기구 · 평생 누적 블럭스 · 상점 업그레이드" },
	["rebirth.shopHint"] = { en = "Spend in the Shop before you rebirth", ko = "환생 전에 상점에서 먼저 쓸 수 있어요" },
	["rebirth.shopButton"] = { en = "To Shop", ko = "상점으로" },
	["rebirth.confirmHint"] = { en = "This can't be undone. Press again to confirm.", ko = "되돌릴 수 없어요. 확인하면 한 번 더 누르세요" },
	["rebirth.sending"] = { en = "Rebirthing...", ko = "환생하는 중..." },
	["rebirth.reason.not_enough_blox"] = { en = "You can rebirth from {cost} Blox", ko = "{cost} 블럭스부터 환생할 수 있어요" },
	["rebirth.reason.failed"] = { en = "Couldn't rebirth", ko = "환생하지 못했어요" },
	-- 새 경제 환생 창(지시서 #30)
	["rebirth.v2.cost"] = { en = "Next Rebirth Cost", ko = "다음 환생 비용" },
	["rebirth.v2.gain"] = { en = "Power Multiplier", ko = "힘 배수" },
	["rebirth.v2.gainValue"] = { en = "×{before} → ×{after}", ko = "×{before} → ×{after}" },
	["rebirth.v2.success"] = { en = "Reborn! Rebirths: {total}", ko = "환생했어요! 환생 {total}회" },
	["rebirth.v2.reason.not_enough_blox"] = { en = "You need {cost} Blox to rebirth", ko = "{cost} 블럭스가 있어야 환생할 수 있어요" },
	["rebirth.v2.reset.blox"] = { en = "Blox → cost paid (rest stays)", ko = "블럭스 → 비용만 빠짐 (나머지는 남음)" },
	["rebirth.v2.keeps"] = { en = "You keep: Rebirth Multiplier (goes up) · Gyms · lifetime Blox · Shop Upgrades · Pickaxes · Ores", ko = "남는 것: 환생 배수(오름) · 운동기구 · 평생 누적 블럭스 · 상점 업그레이드 · 곡괭이 · 광석" },
	-- 새 경제 광석 · 곡괭이 이름(지시서 #31 — ⚠️ 전부 임시 이름 · 확정은 docs/PENDING.md N1). 키는 EconomyV2Config ORE_NAME_KEYS · PICKAXES.nameKey
	["ore.name.1"] = { en = "Copper", ko = "구리" }, -- 임시 이름
	["ore.name.2"] = { en = "Tin", ko = "주석" }, -- 임시 이름
	["ore.name.3"] = { en = "Iron", ko = "철" }, -- 임시 이름
	["ore.name.4"] = { en = "Silver", ko = "은" }, -- 임시 이름
	["ore.name.5"] = { en = "Gold", ko = "금" }, -- 임시 이름
	["ore.name.6"] = { en = "Jade", ko = "비취" }, -- 임시 이름
	["ore.name.7"] = { en = "Ruby", ko = "루비" }, -- 임시 이름
	["ore.name.8"] = { en = "Sapphire", ko = "사파이어" }, -- 임시 이름
	["ore.name.9"] = { en = "Amethyst", ko = "자수정" }, -- 임시 이름
	["ore.name.10"] = { en = "Starstone", ko = "별빛석" }, -- 임시 이름
	["pickaxe.name.pick_c1"] = { en = "Wooden Pickaxe", ko = "나무 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_c2"] = { en = "Stone Pickaxe", ko = "돌 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_c3"] = { en = "Copper Pickaxe", ko = "구리 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_r1"] = { en = "Iron Pickaxe", ko = "철 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_r2"] = { en = "Silver Pickaxe", ko = "은 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_r3"] = { en = "Gold Pickaxe", ko = "금 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_r4"] = { en = "Jade Pickaxe", ko = "비취 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_e1"] = { en = "Ruby Pickaxe", ko = "루비 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_e2"] = { en = "Sapphire Pickaxe", ko = "사파이어 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_e3"] = { en = "Amethyst Pickaxe", ko = "자수정 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_e4"] = { en = "Crystal Pickaxe", ko = "수정 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_m1"] = { en = "Storm Pickaxe", ko = "폭풍 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_m2"] = { en = "Magma Pickaxe", ko = "용암 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_m3"] = { en = "Frost Pickaxe", ko = "서리 곡괭이" }, -- 임시 이름
	["pickaxe.name.pick_l1"] = { en = "Starforge Pickaxe", ko = "별대장간 곡괭이" }, -- 임시 이름
	-- 새 경제 HUD · 알림(지시서 #32)
	["econ.coins.label"] = { en = "Coins", ko = "코인" },
	["econ.bag.label"] = { en = "Bag", ko = "가방" },
	["econ.bag.value"] = { en = "{used}/{cap}", ko = "{used}/{cap}" },
	["econ.forge.open"] = { en = "The Forge is open! Craft pickaxes from your ores", ko = "대장간이 열렸어요! 광석으로 곡괭이를 만들 수 있어요" },
	["econ.forge.hint"] = { en = "Reach Floor {floor} to open the Forge", ko = "{floor}층에 가면 대장간이 열려요" },
	-- 대장간(지시서 #33)
	["forge.title"] = { en = "Forge", ko = "대장간" },
	["forge.tab.craft"] = { en = "Craft", ko = "제작" },
	["forge.tab.exchange"] = { en = "Exchange", ko = "교환소" },
	["forge.gauge"] = { en = "Gauge {slots}/{max} · {points} pts", ko = "게이지 {slots}/{max} · {points}점" },
	["forge.tokens.get"] = { en = "Tokens: {tokens}", ko = "받을 토큰: {tokens}" },
	["forge.tokens.none"] = { en = "Tokens: none", ko = "받을 토큰: 없음" },
	["forge.result.tokens"] = { en = "Got: {tokens}", ko = "받은 토큰: {tokens}" },
	["forge.fill"] = { en = "Auto Fill", ko = "자동 채우기" },
	["forge.clear"] = { en = "Clear", ko = "비우기" },
	["forge.craft"] = { en = "Craft", ko = "제작" },
	["forge.auto.on"] = { en = "Auto Craft: ON", ko = "자동 제작: 켜짐" },
	["forge.auto.off"] = { en = "Auto Craft: OFF", ko = "자동 제작: 꺼짐" },
	["forge.auto.status"] = { en = "Auto Craft · {count}", ko = "자동 제작 · {count}회" },
	["forge.auto.stopped"] = { en = "Auto Craft stopped: {reason}", ko = "자동 제작 멈춤: {reason}" },
	["forge.odds.title"] = { en = "Odds · Gauge {slots}", ko = "확률 · 게이지 {slots}칸" },
	["forge.odds.tab"] = { en = "{n}", ko = "{n}칸" },
	["forge.result.new"] = { en = "NEW!", ko = "새 곡괭이!" },
	["forge.skip"] = { en = "Skip", ko = "건너뛰기" },
	["forge.big"] = { en = "Crafted {name}!", ko = "{name} 제작!" },
	["forge.reason.not_enough_ore"] = { en = "Not enough ore", ko = "광석이 모자라요" },
	["forge.reason.too_soon"] = { en = "Please wait a moment", ko = "잠시 기다려 주세요" },
	["forge.reason.forge_closed"] = { en = "The Forge is closed", ko = "대장간이 닫혀 있어요" },
	["forge.reason.bad_combo"] = { en = "Put in 5 ores", ko = "광석 5개를 넣어 주세요" },
	["forge.reason.not_enough_tokens"] = { en = "Not enough tokens", ko = "토큰이 모자라요" },
	["forge.reason.other"] = { en = "Something went wrong", ko = "처리하지 못했어요" },
	["forge.ex.have"] = { en = "{token}: {n}", ko = "{token}: {n}개" },
	["forge.ex.cost"] = { en = "Cost {n}", ko = "비용 {n}" },
	["forge.ex.owned"] = { en = "Owned ×{n}", ko = "보유 {n}" },
	["forge.ex.notOwned"] = { en = "Not owned", ko = "없음" },
	["forge.ex.button"] = { en = "Exchange", ko = "교환" },
	["forge.ex.done"] = { en = "Got {name}!", ko = "{name} 획득!" },
	["forge.ex.locked"] = { en = "Unlocks in a future update", ko = "다음 업데이트에서 열려요" },
	["forge.prompt.action"] = { en = "Open", ko = "열기" },
	["grade.common"] = { en = "Common", ko = "일반" },
	["grade.rare"] = { en = "Rare", ko = "희귀" },
	["grade.epic"] = { en = "Epic", ko = "에픽" },
	["grade.mythic"] = { en = "Mythic", ko = "신화" },
	["grade.legendary"] = { en = "Legendary", ko = "전설" },
	["grade.next"] = { en = "???", ko = "???" },
	["token.rare"] = { en = "Rare Token", ko = "희귀 토큰" },
	["token.epic"] = { en = "Epic Token", ko = "에픽 토큰" },
	["token.mythic"] = { en = "Mythic Token", ko = "신화 토큰" },
	["token.legendary"] = { en = "Legendary Token", ko = "전설 토큰" },
	["token.next"] = { en = "??? Token", ko = "??? 토큰" },
	-- 펫 코인 부화 · 자동 부화 · 새 게임패스(지시서 #35)
	["pet.egg.infoCoins"] = { en = "{egg} · {cost} Coins per hatch", ko = "{egg} · 1회 {cost} 코인" },
	["pet.hatchCostCoins"] = { en = "Hatch · {cost} Coins", ko = "부화 · {cost} 코인" },
	["pet.hatch3Coins"] = { en = "Hatch ×{n} · {cost} Coins", ko = "{n}마리 부화 · {cost} 코인" },
	["pet.reason.insufficient_coins"] = { en = "Not enough coins", ko = "코인이 모자라요" },
	["pet.reason.too_soon"] = { en = "Please wait a moment", ko = "잠시 기다려 주세요" },
	["pet.auto.off"] = { en = "Auto Hatch: OFF", ko = "자동 부화: 꺼짐" },
	["pet.auto.on"] = { en = "Auto Hatch · {count}", ko = "자동 부화 · {count}마리" },
	["pet.auto.stopped"] = { en = "Auto Hatch stopped: {reason}", ko = "자동 부화 멈춤: {reason}" },
	["pet.auto.big"] = { en = "Hatched {name}!", ko = "{name} 부화!" },
	["pet.hatching"] = { en = "Hatching...", ko = "부화 중..." },
	["shop.bigBag.name"] = { en = "Big Bag", ko = "큰 가방" },
	["shop.bigBag.desc"] = { en = "Bag capacity ×2", ko = "가방 용량 ×2" },
	["shop.instantCraft.name"] = { en = "Instant Craft", ko = "즉시 제작" },
	["shop.instantCraft.desc"] = { en = "Skip craft animations — craft every 1s", ko = "제작 연출 생략 · 1초마다 제작" },
	["shop.tripleCraft.name"] = { en = "Triple Craft", ko = "트리플 제작" },
	["shop.tripleCraft.desc"] = { en = "Craft 3 at once (uses 15 ores)", ko = "한 번에 3회 제작(광석 15개)" },
	["shop.instantHatch.name"] = { en = "Instant Hatch", ko = "즉시 부화" },
	["shop.instantHatch.desc"] = { en = "Skip hatch animations — hatch every 1s", ko = "부화 연출 생략 · 1초마다 부화" },
	-- 장비 화면(지시서 #34)
	["equip.title"] = { en = "Equipment", ko = "장비" },
	["equip.tab.pickaxe"] = { en = "Pickaxes", ko = "곡괭이" },
	["equip.open"] = { en = "Equipment", ko = "장비" },
	["equip.count"] = { en = "×{n}", ko = "×{n}" },
	["equip.stars"] = { en = "★{n}", ko = "★{n}" },
	["equip.enh"] = { en = "+{n}", ko = "+{n}" },
	["equip.mult"] = { en = "Mining ×{mult}", ko = "채굴 ×{mult}" },
	["equip.equipped"] = { en = "Equipped", ko = "장착 중" },
	["equip.unknown"] = { en = "???", ko = "???" },
	["equip.notOwned"] = { en = "Not found yet — craft or exchange at the Forge", ko = "아직 없어요 — 대장간에서 만들거나 교환하세요" },
	["equip.owned"] = { en = "Owned ×{n} · Spare {spare}", ko = "보유 {n}개 · 여벌 {spare}개" },
	["equip.equip"] = { en = "Equip", ko = "장착" },
	["equip.enhance"] = { en = "Enhance", ko = "강화" },
	["equip.star"] = { en = "Star Up", ko = "별 올리기" },
	["equip.enh.cost"] = { en = "Enhance +{from} → +{to} · Cost {points} pts: {ores}", ko = "강화 +{from} → +{to} · 비용 {points}점: {ores}" },
	["equip.enh.max"] = { en = "Enhance is maxed (+10)", ko = "강화 최대(+10)" },
	["equip.star.cost"] = { en = "Star {from} → {to} · Uses {need} spare (have {spare})", ko = "별 {from} → {to} · 여벌 {need}개 필요(지금 {spare}개)" },
	["equip.star.max"] = { en = "Stars are maxed (5)", ko = "별 최대(5성)" },
	["equip.multChange"] = { en = "Mining ×{before} → ×{after}", ko = "채굴 ×{before} → ×{after}" },
	["equip.reason.not_owned"] = { en = "You don't own this pickaxe", ko = "가지고 있지 않은 곡괭이예요" },
	["equip.reason.already_equipped"] = { en = "Already equipped", ko = "이미 장착했어요" },
	["equip.reason.max"] = { en = "Already at max", ko = "이미 최대예요" },
	["equip.reason.not_enough_ore"] = { en = "Not enough ore", ko = "광석이 모자라요" },
	["equip.reason.not_enough_copies"] = { en = "Not enough spare pickaxes", ko = "여벌 곡괭이가 모자라요" },
	["equip.reason.forge_closed"] = { en = "The Forge is closed", ko = "대장간이 닫혀 있어요" },
	["equip.reason.other"] = { en = "Something went wrong", ko = "처리하지 못했어요" },
	["equip.done.equip"] = { en = "Equipped {name}", ko = "{name} 장착" },
	["equip.done.enhance"] = { en = "{name} enhanced", ko = "{name} 강화 성공" },
	["equip.done.star"] = { en = "{name} star up", ko = "{name} 별 올림" },
	["warp.title"] = { en = "World · Warp", ko = "월드 · 워프" },
	["warp.world"] = { en = "World {n}", ko = "월드 {n}" },
	["warp.button"] = { en = "Warp", ko = "워프" },
	["warp.buttonFloor"] = { en = "{button} (Floor {stage})", ko = "{button} ({stage}층)" },
	["warp.confirm"] = { en = "Press again to Warp", ko = "한 번 더 누르면 워프" },
	["warp.success"] = { en = "Warped to Floor {stage} (-{cost})", ko = "{stage}층으로 워프했어요 (-{cost})" },
	["warp.row"] = { en = "  Floor {stage}   {cost} Blox   {state}", ko = "  {stage}층   {cost} 블럭스   {state}" },
	["warp.row.can"] = { en = "Available", ko = "갈 수 있음" },
	["warp.confirmHint"] = { en = "Costs {cost} Blox. Press again to confirm.", ko = "{cost} 블럭스를 써요. 확인하면 한 번 더 누르세요" },
	["warp.sending"] = { en = "Warping...", ko = "워프하는 중..." },
	["warp.reason.run_active"] = { en = "You can warp after your run ends", ko = "런이 끝난 뒤에 워프할 수 있어요" },
	["warp.reason.invalid_stage"] = { en = "You can't go to that floor", ko = "갈 수 없는 층이에요" },
	["warp.reason.no_character"] = { en = "Try again when your character is ready", ko = "캐릭터가 준비되면 다시 눌러 주세요" },
	["warp.reason.failed"] = { en = "Couldn't warp", ko = "워프하지 못했어요" },
	-- ===== 큰 창 — 칭호 · 아우라 · 펫 (뽑기 3종) ========================================================
	["common.equip"] = { en = "Equip", ko = "장착" },
	["common.equipped"] = { en = "Equipped", ko = "장착 중" },
	["common.owned"] = { en = "Owned", ko = "보유" },
	["common.notOwned"] = { en = "Not owned", ko = "미보유" },
	["common.result.equip"] = { en = "Equipped: {name}", ko = "장착: {name}" },
	["common.toast.result"] = { en = "{heading} {name} ({detail})", ko = "{heading} {name} ({detail})" },
	["roll.luckApplied"] = { en = "Luck ×{luck} applied", ko = "행운 ×{luck} 적용" },
	-- 유료 랜덤 상품 확률 표시(지시서 #27 — docs/POLICY_CHECK.md): 상품 줄의 행운 배수 · 아우라 창 확률 보기(보통 · 럭키 · 슈퍼)
	["shop.oddsChange"] = { en = "Luck ×{mult}: {name} {before} → {after}", ko = "행운 ×{mult}: {name} {before} → {after}" },
	["aura.odds.normal"] = { en = "Normal Odds (Luck x{luck})", ko = "보통 확률 (행운 ×{luck})" },
	["aura.odds.lucky"] = { en = "Lucky Roll Odds (Luck x{luck})", ko = "럭키 롤 확률 (행운 ×{luck})" },
	["aura.odds.super"] = { en = "Super Roll Odds (Luck x{luck})", ko = "슈퍼 롤 확률 (행운 ×{luck})" },
	-- 확률 보기 토글(지시서 #28 O1 · 후속 ②): 칭호 · 펫 · 아우라 창 공통 — 지금 ↔ 그 뽑기의 행운 패스를 더하면 · 상점 행운 패스 줄에서 그 창으로(O2)
	["odds.preview.now"] = { en = "Odds Now (Luck x{luck})", ko = "지금 확률 (행운 ×{luck})" },
	["odds.preview.pass"] = { en = "With {pass} (Luck x{luck})", ko = "{pass}를 더하면 (행운 ×{luck})" },
	["odds.passName"] = { en = "x{mult} Pass", ko = "×{mult} 패스" },
	["shop.oddsLink"] = { en = "All Odds", ko = "확률 보기" },
	["title.title"] = { en = "Titles", ko = "칭호" },
	["title.autoOn"] = { en = "Auto Roll On", ko = "자동 뽑기 켜짐" },
	["title.autoOff"] = { en = "Auto Roll Off", ko = "자동 뽑기 꺼짐" },
	["title.rollButton"] = { en = "Roll ({cost} Blox)", ko = "1회 뽑기 ({cost} 블럭스)" },
	["title.autoNote"] = { en = "Auto Roll spends {cost} Blox per second", ko = "자동 뽑기는 초당 {cost} 블럭스를 씁니다" },
	["title.mult"] = { en = "Power·Blox ×{mult}", ko = "힘·블럭스 ×{mult}" },
	["title.result.new"] = { en = "New Title! {name}", ko = "새 칭호! {name}" },
	["title.result.dup"] = { en = "Already owned: {name}", ko = "이미 있는 칭호: {name}" },
	["title.toast"] = { en = "New Title! {name} ({mult})", ko = "새 칭호! {name} ({mult})" },
	["title.reason.not_owned"] = { en = "You don't have this Title yet", ko = "아직 없는 칭호예요" },
	["aura.title"] = { en = "Aura", ko = "아우라" },
	["aura.titleButton"] = { en = "Titles", ko = "칭호" },
	["aura.roll"] = { en = "Roll", ko = "뽑기" },
	["aura.rollCost"] = { en = "Roll ({cost} Blox)", ko = "뽑기 ({cost} 블럭스)" },
	["aura.mult"] = { en = "Power·Damage ×{mult}", ko = "힘·데미지 ×{mult}" },
	["aura.pack.tab"] = { en = "Pack {pack}", ko = "팩 {pack}" },
	["aura.pack.tabLocked"] = { en = "Pack {pack} Locked", ko = "팩 {pack} 잠김" },
	["aura.pack.info"] = { en = "Pack {pack} · {cost} Blox per roll", ko = "팩 {pack} · 1회 {cost} 블럭스" },
	["aura.pack.infoLocked"] = { en = "Pack {pack} — unlocks at {cost} lifetime Blox", ko = "팩 {pack} — 누적 블럭스 {cost} 이상이면 열려요" },
	["aura.result.new"] = { en = "New Aura! {name}", ko = "새 아우라! {name}" },
	["aura.result.dup"] = { en = "Already owned: {name}", ko = "이미 있는 아우라: {name}" },
	["aura.modal.new"] = { en = "New Aura!", ko = "새 아우라!" },
	["aura.modal.heading"] = { en = "Aura", ko = "아우라" },
	["aura.modal.detail"] = { en = "{rarity} · {mult}", ko = "{rarity} · {mult}" },
	["aura.modal.detailEquipped"] = { en = "{rarity} · {mult} · Equipped", ko = "{rarity} · {mult} · 장착" },
	["aura.reason.not_owned"] = { en = "You don't have this Aura yet", ko = "아직 없는 아우라예요" },
	["aura.reason.pack_locked"] = { en = "This pack isn't unlocked yet", ko = "아직 열리지 않은 팩이에요" },
	["aura.reason.none_owned"] = { en = "No rolls left", ko = "남은 롤이 없어요" }, -- 지시서 #17
	["aura.useLucky"] = { en = "Use Lucky Roll ({n})", ko = "럭키 롤 사용 ({n})" },
	["aura.useSuper"] = { en = "Use Super Roll ({n})", ko = "슈퍼 롤 사용 ({n})" },
	["pet.hatch3"] = { en = "x{n} ({cost})", ko = "×{n} ({cost})" }, -- 3배 부화 버튼(지시서 #17)
	["pet.result.hatch3"] = { en = "Hatched {n}: {names}", ko = "{n}마리 부화: {names}" },
	["title.luckProduct"] = { en = "{name} {price}", ko = "{name} {price}" }, -- 칭호 창 10배 칭호 행운 버튼
	["title.luckProductOwned"] = { en = "{name} · Owned", ko = "{name} · 보유 중" },
	["title.luckOdds"] = { en = "With {name}: {odds}", ko = "{name} 사면: {odds}" },
	["pet.title"] = { en = "Pets", ko = "펫" },
	["pet.equipBest"] = { en = "Equip Best", ko = "최고 장착" },
	["pet.unequip"] = { en = "Unequip", ko = "해제" },
	["pet.release"] = { en = "Release", ko = "놓아주기" },
	["pet.releaseConfirm"] = { en = "Press again to Release", ko = "한 번 더 누르면 놓아줘요" },
	["pet.hatch"] = { en = "Hatch", ko = "부화" },
	["pet.hatchCost"] = { en = "Hatch ({cost} Blox)", ko = "부화 ({cost} 블럭스)" },
	["pet.craft"] = { en = "Craft", ko = "크래프팅" },
	["pet.craftTo"] = { en = "Craft → {level} ({n}/{need})", ko = "크래프팅 → {level} ({n}/{need})" },
	["pet.craftMax"] = { en = "Max level", ko = "최고 단계" },
	["pet.equippedSuffix"] = { en = " · Equipped", ko = " · 장착" },
	["pet.emptySlot"] = { en = "Empty slot", ko = "빈 슬롯" },
	["pet.noSelection"] = { en = "Pick a pet", ko = "펫을 골라 주세요" },
	["pet.gain"] = { en = "Power +{gain}", ko = "힘 +{gain}" },
	["pet.egg.tabLocked"] = { en = "{egg} Locked", ko = "{egg} 잠김" },
	["pet.egg.info"] = { en = "{egg} · {cost} Blox per hatch", ko = "{egg} · 1회 {cost} 블럭스" },
	["pet.egg.infoLocked"] = { en = "{egg} — unlocks at {cost} lifetime Blox", ko = "{egg} — 누적 블럭스 {cost} 이상이면 열려요" },
	["pet.odd"] = { en = "{name} ×{mult} · {chance}", ko = "{name} ×{mult} · {chance}" },
	["pet.storage"] = { en = "Owned {n} / {max}", ko = "보유 {n} / {max}" },
	["pet.slots"] = { en = "Equipped {n} / {max}", ko = "장착 {n} / {max}" },
	["pet.detail.info"] = { en = "{rarity} · {level} · {gain}", ko = "{rarity} · {level} · {gain}" },
	["pet.result.new"] = { en = "New Pet! {name}", ko = "새 펫! {name}" },
	["pet.result.hatch"] = { en = "Hatched: {name}", ko = "부화: {name}" },
	["pet.result.craft"] = { en = "Crafted! {name} {level}", ko = "크래프팅! {name} {level}" },
	["pet.result.equip"] = { en = "Equipped", ko = "장착했어요" },
	["pet.result.unequip"] = { en = "Unequipped", ko = "해제했어요" },
	["pet.result.equipBest"] = { en = "Equipped your best pets", ko = "가장 센 펫으로 장착했어요" },
	["pet.result.release"] = { en = "Released", ko = "놓아줬어요" },
	["pet.modal.new"] = { en = "New Pet!", ko = "새 펫!" },
	["pet.modal.heading"] = { en = "Pet", ko = "펫" },
	["pet.modal.detail"] = { en = "{rarity} · {gain}", ko = "{rarity} · {gain}" },
	["pet.modal.detailEquipped"] = { en = "{rarity} · {gain} · Equipped", ko = "{rarity} · {gain} · 장착" },
	["pet.reason.egg_locked"] = { en = "This egg isn't unlocked yet", ko = "아직 열리지 않은 알이에요" },
	["pet.reason.storage_full"] = { en = "Storage is full — release pets to make room", ko = "보관함이 가득 찼어요 — 놓아주기로 자리를 비워 주세요" },
	["pet.reason.not_owned"] = { en = "You don't have that pet", ko = "없는 펫이에요" },
	["pet.reason.slots_full"] = { en = "Equip slots are full", ko = "장착 슬롯이 가득 찼어요" },
	["pet.reason.not_equipped"] = { en = "That pet isn't equipped", ko = "장착하지 않은 펫이에요" },
	["pet.reason.pet_equipped"] = { en = "You can't release an equipped pet", ko = "장착 중인 펫은 놓아줄 수 없어요" },
	["pet.reason.max_level"] = { en = "Already at max level", ko = "이미 최고 단계예요" },
	["pet.reason.not_enough"] = { en = "You need {n} of the same pet", ko = "같은 펫 {n}마리가 필요해요" },
	-- ===== 상점 창 — 업그레이드 탭 · 로벅스 탭 ==========================================================
	["common.buy"] = { en = "Buy", ko = "구매" },
	["shop.title"] = { en = "Shop", ko = "상점" },
	["shop.tab.upgrade"] = { en = "Upgrades", ko = "업그레이드" },
	["shop.tab.robux"] = { en = "Robux", ko = "로벅스" },
	["shop.max"] = { en = "MAX", ko = "MAX" },
	["upgrade.level"] = { en = "Lv {n}", ko = "Lv {n}" },
	["upgrade.levelMax"] = { en = "Lv {n}/{max}", ko = "Lv {n}/{max}" },
	["upgrade.effect.perSec"] = { en = "{value}/sec", ko = "{value}회/초" },
	["upgrade.effect.slots"] = { en = "Slots +{n}", ko = "슬롯 +{n}" },
	["upgrade.effect.luck"] = { en = "Luck ×{value}", ko = "행운 ×{value}" },
	["upgrade.effect.max"] = { en = "{effect} (Max)", ko = "{effect} (최대)" },
	["upgrade.cost"] = { en = "{cost} Blox", ko = "{cost} 블럭스" },
	["upgrade.success"] = { en = "{name} Lv {n} (-{cost})", ko = "{name} Lv {n} (-{cost})" },
	["upgrade.reason.max_level"] = { en = "Max level", ko = "최대 레벨" },
	["upgrade.reason.invalid_upgrade"] = { en = "This can't be bought", ko = "살 수 없는 항목이에요" },
	["upgrade.reason.failed"] = { en = "Couldn't buy it", ko = "사지 못했어요" },
	["shop.owned"] = { en = "Owned", ko = "보유 중" },
	["shop.ownedHigher"] = { en = "Owned (Higher)", ko = "보유(상위)" }, -- R2: OP 자동 클리커 보유 중 기본 자동 클리커(지시서 #17)
	["shop.comingSoon"] = { en = "Coming soon", ko = "준비 중" },
	["shop.product"] = { en = "Item", ko = "상품" },
	["shop.purchased"] = { en = "{name} purchased!", ko = "{name} 구매 완료!" },
	["shop.ladder.title"] = { en = "Power Tiers  Now ×{mult}", ko = "힘 배수 계단  지금 ×{mult}" },
	["shop.ladder.top"] = { en = "{name} owned — highest tier", ko = "{name} 보유 — 가장 높은 단계예요" },
	["shop.ladder.next"] = { en = "Next: {name} (only your highest tier applies)", ko = "다음 {name}(가장 높은 단계 하나만 적용)" },
	["shop.ladder.maxButton"] = { en = "Max tier", ko = "최고 단계" },
	["shop.reason.not_registered"] = { en = "Coming soon", ko = "준비 중이에요" },
	["shop.reason.already_owned"] = { en = "You already own this", ko = "이미 가지고 있어요" },
	["shop.reason.ladder_owned_higher"] = { en = "You already own a higher Power tier", ko = "더 높은 힘 단계를 이미 가지고 있어요" },
	["shop.reason.already_unlocked"] = { en = "This Gym is already unlocked", ko = "이미 열린 운동기구예요" }, -- 지시서 #17
	["shop.reason.none_owned"] = { en = "You don't have any", ko = "보관한 것이 없어요" },
	["shop.potion.title"] = { en = "{name}  Owned {n}", ko = "{name}  보유 {n}" },
	["shop.potion.use"] = { en = "Use", ko = "켜기" },
	["shop.potion.used"] = { en = "{name} on (+{min} min)", ko = "{name} 켬 (+{min}분)" },
	["shop.reason.auto_owned_higher"] = { en = "You already own {name}", ko = "{name}를 이미 가지고 있어요" }, -- {name} = 상품 이름 OP Auto Clicker(#42)
	["shop.reason.restricted"] = { en = "This item isn't available in your region", ko = "이 지역에서는 살 수 없는 상품이에요" },
	["shop.reason.invalid_key"] = { en = "This item can't be bought", ko = "살 수 없는 상품이에요" },
	["shop.reason.prompt_failed"] = { en = "Couldn't open the purchase window", ko = "구매 창을 열지 못했어요" },
	["shop.reason.beta_disabled"] = { en = "Not on sale during the test", ko = "테스트 기간에는 팔지 않아요" }, -- 지시서 #23 E5(beta 서버 개발자 상품)
	["shop.reason.failed"] = { en = "Couldn't complete the purchase", ko = "구매하지 못했어요" },
	-- ===== 접속 끊김 안내 (서버 Player:Kick — Server/Systems/LocaleGate가 그 플레이어 언어로 고른다. K5의 단 하나 예외) =====
	["kick.loadFailed"] = { en = "Couldn't load your data. Please rejoin.", ko = "데이터 로드에 실패했습니다. 다시 접속해 주세요." },
	["kick.versionError"] = { en = "Data version error. Please rejoin.", ko = "데이터 버전 오류입니다. 다시 접속해 주세요." },
	["kick.corrupted"] = { en = "Your data is damaged and can't be loaded. Please contact an admin.", ko = "데이터가 손상되어 로드할 수 없습니다. 관리자에게 문의해 주세요." },
	["kick.otherServer"] = { en = "Your data was loaded on another server. Please rejoin.", ko = "다른 서버에서 데이터를 불러왔습니다. 다시 접속해 주세요." },
} :: { [string]: Entry }

-- 유럽 4개 언어 합치기(지시서 #40). 표에 없는 키는 버리고 Orphans에 남긴다(LocaleLangTests · check_strings가 0을 잰다)
Strings.LANG_FILES = { "es", "pt", "fr", "de" }
Strings.Orphans = {} :: { string }
for _, code in ipairs(Strings.LANG_FILES) do
	local texts = require(script.Parent.Lang[code]) :: { [string]: string }
	for key, text in pairs(texts) do
		local entry = (Strings.Entries :: any)[key]
		if entry ~= nil then
			entry[code] = text
		else
			table.insert(Strings.Orphans, code .. ":" .. key)
		end
	end
end

return Strings

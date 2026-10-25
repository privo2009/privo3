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

local Strings = {}

export type Entry = { en: string, ko: string? }

Strings.Entries = {
	-- ===== 공통 ==========================================================================================
	["common.reason.rate_limited"] = { en = "Please wait a moment and try again", ko = "잠시 뒤에 다시 눌러 주세요" },
	["common.reason.no_profile"] = { en = "Loading your data", ko = "데이터를 불러오는 중이에요" },
	["common.reason.insufficient_blox"] = { en = "Not enough Blox", ko = "블럭스가 모자라요" },
	["common.reason.invalid_request"] = { en = "Can't do that", ko = "할 수 없는 요청이에요" },
	["common.reason.partial_failure"] = { en = "Something went wrong. Please tell an admin.", ko = "문제가 생겼어요. 관리자에게 알려 주세요" },
	["common.reason.failed"] = { en = "Couldn't do that", ko = "하지 못했어요" },
	-- ===== 이름 (K6 — Config id → 키. 만드는 곳은 Shared/Localization/Names) ==============================
	-- 희귀도(아우라 등급 · 펫 종 희귀도 공통)
	["rarity.common"] = { en = "Common", ko = "일반" },
	["rarity.rare"] = { en = "Rare", ko = "희귀" },
	["rarity.epic"] = { en = "Epic", ko = "영웅" },
	["rarity.legendary"] = { en = "Legendary", ko = "전설" },
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
	-- 펫 강화 단계 1 ~ 4 (종 희귀도와 다른 낱말 — E4 · G10)
	["pet.level.1"] = { en = "Normal", ko = "기본" },
	["pet.level.2"] = { en = "Gold", ko = "황금" },
	["pet.level.3"] = { en = "Diamond", ko = "다이아" },
	["pet.level.4"] = { en = "Rainbow", ko = "무지개" },
	-- 월드 (WorldConfig 번호)
	["world.name.1"] = { en = "Wood", ko = "나무" },
	-- 업그레이드 (UpgradeConfig 키)
	["upgrade.name.punchDamage"] = { en = "Punch Damage", ko = "펀치 데미지" },
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
	["shop.rebirth2x.name"] = { en = "x2 Rebirth", ko = "2배 환생" },
	["shop.rebirth2x.desc"] = { en = "Get 2x Rebirths when you rebirth", ko = "환생할 때 얻는 환생 수가 2배예요" },
	["shop.hatch3x.name"] = { en = "x3 Hatch", ko = "3배 부화" },
	["shop.hatch3x.desc"] = { en = "Hatch 3 eggs at once (3x cost)", ko = "알을 한 번에 3개 부화해요(비용 3배)" },
	["shop.petLuck2x.name"] = { en = "x2 Pet Luck", ko = "2배 펫 행운" },
	["shop.petLuck2x.desc"] = { en = "2x luck when hatching pets", ko = "펫 부화 행운이 2배예요" },
	["shop.petStorage100.name"] = { en = "+100 Pet Storage", ko = "+100 펫 저장 공간" },
	["shop.petStorage100.desc"] = { en = "Keep 100 more pets", ko = "펫을 100마리 더 보관해요" },
	["shop.damage2x.name"] = { en = "x2 Damage", ko = "2배 데미지" },
	["shop.damage2x.desc"] = { en = "2x damage per punch", ko = "1펀치 데미지가 2배예요" },
	["shop.petSlots3.name"] = { en = "+3 Pet Equip", ko = "+3 펫 장착" },
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
	["shop.gymUnlock.name"] = { en = "Unlock Gym {n}", ko = "운동기구 {n} 열기" },
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
	["settings.reason.not_allowed"] = { en = "This setting can't be changed", ko = "바꿀 수 없는 설정이에요" },
	["settings.reason.bad_value"] = { en = "Invalid value", ko = "잘못된 값이에요" },
	["settings.reason.failed"] = { en = "Couldn't change it", ko = "바꾸지 못했어요" },
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
} :: { [string]: Entry }

return Strings

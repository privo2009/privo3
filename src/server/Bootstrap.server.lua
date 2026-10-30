--!strict
-- 임시 부트스트랩. 정식 서버 진입점으로 대체 예정이며, 그때 이 파일 자체를 들어낸다.
-- ⚠️ 이 파일 전체가 임시 파일이다. 아래 VERIFY_CHALLENGE 블록이
-- 그 성격이고, 상단의 [Bootstrap][VERIFY] 읽기 print만 상시 유지 대상이다.
--
-- 프로필 로드/저장 왕복을 검증하던 VERIFY_MODE 블록은 삭제했다 (Phase 4-2-b).
-- CurrencyService를 우회해 blox를 직접 대입하는 유일한 경로였고(CLAUDE.md 절대 규칙 2),
-- 그 우회 때문에 lifetimeBlox가 따라 오르지 않아 패드 해금이 막히는 오염이 실제로 났다.
-- 검증 목적은 CurrencyService 완성으로 이미 대체됐다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileManager = require(script.Parent.Data.ProfileManager)
local CurrencyService = require(script.Parent.Systems.CurrencyService)
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)

-- ── 테스트 프리셋: TEST_PRESET (Studio 전용, 지시서 #13 3단계) ──────────────────────────
-- 이름을 적고 Play하면 그 시점 상태의 **Mock 프로필**로 시작한다(실제 데이터에는 읽기도 쓰기도 하지 않는다 — TestPresetGate).
-- 이름: fresh · before_first_rebirth · floor9 · floor17 · floor25 · floor25_cleared (값 · 출처는 Shared/Config/TestPresets)
-- Studio가 아니면 무시하고 ERROR 로그를 남긴다. ⚠️ 커밋 값은 언제나 nil이다(TestPresetGateTests가 잰다 — 켠 Play에서는 그 줄이 실패한다).
local TEST_PRESET: string? = nil

-- ── 가짜 게임패스 소유: TEST_GAMEPASSES (Studio 전용, 지시서 #16 3단계) ────────────────────
-- 패스 키 목록을 적고 Play하면 Studio에서만 그 패스를 가진 것으로 친다(세션 메모리 — 저장하지 않는다. GamepassService).
-- 예: { "strength8x", "damage2x" } — 키는 Shared/Config/ShopConfig. Studio가 아니면 무시하고 ERROR 로그를 남긴다.
-- ⚠️ 커밋 값은 언제나 nil이다(GamepassServiceTests가 잰다 — 켠 Play에서는 그 줄이 실패한다. 그 Play로 테스트 개수를 세지 않는다).
local TEST_GAMEPASSES: { string }? = nil

-- ── 가짜 영수증: TEST_RECEIPTS (Studio · Mock 프리셋 전용, 지시서 #17 6단계) ─────────────────
-- 개발자 상품 키 목록을 적고 TEST_PRESET과 함께 Play하면 접속할 때 그 영수증을 처리 순서대로 흘린다(실제 결제 없음 · Mock 프로필만).
-- 예: { "strengthPotion", "luckyRoll5", "gymUnlock5" }. Studio가 아니거나 프리셋이 없으면 무시하고 ERROR 로그(ProductService).
-- ⚠️ 커밋 값은 언제나 nil이다(ProductGrantsTests가 잰다 — 켠 Play에서는 그 줄이 실패한다. 그 Play로 테스트 개수를 세지 않는다).
local TEST_RECEIPTS: { string }? = nil

-- ── 화면 언어: TEST_LOCALE (Studio 전용, 지시서 #L1 K2) ────────────────────────────────────
-- "en" 또는 "ko"를 적고 Play하면 계정 언어 대신 그 언어로 보인다(클라 · Kick 안내문 둘 다 — Server/Systems/LocaleGate).
-- Studio가 아니면 무시하고 ERROR 로그를 남긴다. ⚠️ 커밋 값은 언제나 nil이다(LocaleTests가 잰다 — 켠 Play에서는 그 줄이 실패한다).
local TEST_LOCALE: string? = nil
local LocaleGate = require(script.Parent.Systems.LocaleGate)
LocaleGate.init(TEST_LOCALE)

print("[Bootstrap] ProfileManager.init() 호출 시작")
ProfileManager.init(TEST_PRESET)
print("[Bootstrap] ProfileManager.init() 호출 완료")

-- 스폰 지점과 아레나 경계를 Workspace에 세운다 (4-2-a).
-- ⚠️ 순서: PadService.init()보다 앞이어야 한다. 둘 다 Workspace에 파트를 세우는데,
-- 이쪽이 SpawnLocation을 만든다 — 패드가 먼저 서면 첫 접속자가 스폰 지점 없이 원점
-- (0,0,0)에 떨어질 수 있고, 그 자리는 스테이지 1 블록 한가운데다.
-- ProfileManager.init()과의 선후는 상관없다. 이 파일은 프로필 훅을 걸지 않는다.
local ArenaService = require(script.Parent.Systems.ArenaService)
ArenaService.init()

-- 클릭 파워 패드를 Workspace에 세운다.
-- ⚠️ 순서: 반드시 ProfileManager.init() 뒤여야 한다. PadService.init()이 내부에서
-- ProfileManager.onLoaded로 로드 훅을 거는데, 그 전에 부르면 이미 접속해 있던 플레이어의
-- 로드 통지를 놓쳐서 selectedPadIndex 클램프가 건너뛰어진다.
local PadService = require(script.Parent.Systems.PadService)
PadService.init()

-- 수령 발판을 세운다 (4-2-a).
-- ⚠️ 순서: ArenaService.init() 뒤가 자연스럽다(같은 아레나 파트다). ChallengeService와의
-- 선후는 상관없다 — 발판은 모듈 로드 시점에 cashout 참조만 잡고, 실제 호출은 밟혔을 때다.
local CashoutPadService = require(script.Parent.Systems.CashoutPadService)
CashoutPadService.init()

-- 진행 벽 트리거를 세운다 (3c).
-- ⚠️ 순서: CashoutPadService.init()과 같은 이유로 ArenaService.init() 뒤다. ChallengeService와의
-- 선후는 상관없다 — 트리거는 모듈 로드 시점에 advance 참조만 잡고, 실제 호출은 통과했을 때다.
local AdvanceWallService = require(script.Parent.Systems.AdvanceWallService)
AdvanceWallService.init()

-- 챌린지 입장 게이트를 세운다. 지나가면 1층 런이 선다 — 런 시작 = 입장 순간이다.
-- ⚠️ 순서: 위 트리거들과 같은 이유로 ArenaService.init() 뒤다. ChallengeService와의
-- 선후는 상관없다 — 게이트는 모듈 로드 시점에 startRun 참조만 잡고, 실제 호출은 지났을 때다.
local EntranceGateService = require(script.Parent.Systems.EntranceGateService)
EntranceGateService.init()

-- 런 중 사망 = 포기. 캐릭터마다 Humanoid.Died에 abandonRun을 건다.
-- ⚠️ 순서: 플레이어 훅만 거므로 다른 init과의 선후는 상관없다. 이미 들어와 있던
-- 플레이어도 init 안에서 건다.
local RunDeathService = require(script.Parent.Systems.RunDeathService)
RunDeathService.init()

-- 클릭 입력 수신을 연다 (4-2-b).
-- ⚠️ 순서: PadService.init() 뒤여야 한다. 클릭 1회의 힘은 PadService.getClickPower가
-- 정하므로, 패드가 서기 전에 클릭이 들어오면 전부 패드 1 파워로 처리된다.
-- (getClickPower는 상태가 없으면 1로 답한다 — 조용히 틀린 값이 나가는 경로다)
local ClickService = require(script.Parent.Systems.ClickService)
ClickService.init()

-- 운동기구를 세운다 (2026-10-21). 클릭 배수는 ClickService가 클릭 시점에 GymService.getClickMultiplier로
-- 묻는다 — 상태가 없어 init 순서는 파트 생성뿐이다(클릭이 먼저 와도 배수 1로 답한다).
local GymService = require(script.Parent.Systems.GymService)
GymService.init()

-- 이동속도 서버 권위를 연다 (4-2-c).
-- ⚠️ 순서: ProfileManager.init() 뒤여야 한다. 최대치는 힘에서 나오고 힘은 프로필에 있어서,
-- 프로필이 없으면 CurrencyService.get이 nil을 주고 전원이 기본 속도로 시작한다.
-- (SpeedService는 nil을 힘 0으로 보고 넘어간다 — 조용히 틀린 값이 나가는 경로다)
-- PadService/ClickService와의 선후는 상관없다. 서로 읽는 값이 없다.
local SpeedService = require(script.Parent.Systems.SpeedService)
SpeedService.init()

-- 커스텀 스피드 요청 수신을 연다 (4-2-c Prompt 3).
-- ⚠️ 순서: SpeedService.init() 뒤여야 한다. 이 채널은 setCustomSpeed를 부르는 것이
-- 전부이고, 최대치 계산과 Humanoid 세팅은 전부 SpeedService 쪽에 있다.
local SpeedRequestService = require(script.Parent.Systems.SpeedRequestService)
SpeedRequestService.init()

-- AttackService가 몇 번 때리는지 지켜보는 시간(초). VERIFY_CHALLENGE 전용이다.
-- 펀치 주기(0.5초)보다 넉넉해야 몇 대는 들어간 뒤에 클리어 여부를 본다.
local ATTACK_OBSERVE_SEC = 3

-- [ATTACK] 관측 print의 폴링 주기(초). 펀치 주기(0.5초)보다 길게 둔다 —
-- 이 루프는 값을 만들지 않고 마지막 결과만 들여다보므로 촘촘할 이유가 없다.
local ATTACK_VERIFY_POLL_SEC = 0.5

-- 근접 자동 공격을 연다 (4-2-e2).
-- ⚠️ 순서: CurrencyService(힘 조회) · ChallengeService(런 상태·applyDamage)가 준비된
-- 뒤여야 한다. 둘 다 모듈 로드 시점에 준비되므로 여기가 그 뒤다.
-- SpeedService와의 선후는 상관없다 — 서로 읽는 값이 없다.
--
-- ⚠️ init()이 서버 단일 루프를 띄운다. 이 줄이 빠지면 루프가 아예 안 돌고,
-- 증상은 "블록을 때려도 안 부서진다" 하나뿐이라 원인이 보이지 않는다.
local AttackService = require(script.Parent.Systems.AttackService)
AttackService.init()

-- 환생을 연다 (4-2-d).
-- ⚠️ 순서: CurrencyService · ChallengeService · SpeedService가 전부 준비된 뒤여야 한다.
-- 환생은 그 셋을 한 흐름 안에서 순서대로 부르는 오케스트레이터이고, 스스로 계산하는
-- 것이 거의 없다. 특히 SpeedService.init() 뒤가 아니면 환생 마지막의 속도 재적용이
-- CharacterAdded 배선 없는 상태로 나가서, 힘은 내려갔는데 WalkSpeed는 옛 값으로
-- 남는다 — UI가 없으므로 그 어긋남은 화면에 아무 흔적을 남기지 않는다.
-- (ClickService.init()이 PadService.init() 뒤여야 했던 것과 같은 종류의 의존이다)
--
-- SpeedRequestService와의 선후는 상관없다. 환생은 그 파일을 거치지 않는다 —
-- 빈도 상한은 클라 입력 경로 전용이고 서버 재적용이 걸리면 안 되기 때문이다.
local RebirthService = require(script.Parent.Systems.RebirthService)
RebirthService.init()
-- Roblox Plus 프롬프트(S16 — 지시서 #17). ShopConfig.PLUS_PROMPT_ENABLED = false면 판정만 하고 띄우지 않는다
require(script.Parent.Systems.PlusPromptService).init(RebirthService.onRebirthed)

-- 환생 창의 요청 채널 (Phase 6 지시서 #5). RebirthService.init() 뒤 — 요청을 그쪽으로 넘긴다.
local RebirthRequestService = require(script.Parent.Systems.RebirthRequestService)
RebirthRequestService.init()

-- 워프를 연다 + 월드·워프 창의 요청 채널 (Phase 6 지시서 #6).
-- ⚠️ 순서: CurrencyService · ChallengeService · ArenaService가 준비된 뒤. 워프는 차감 → 입구 이동 → 런 시작이다.
local WarpService = require(script.Parent.Systems.WarpService)
WarpService.init()
local WarpRequestService = require(script.Parent.Systems.WarpRequestService)
WarpRequestService.init()

-- 상점 업그레이드 구매 채널 (Phase 6 지시서 #7). UpgradeService는 init이 없다(요청 때 프로필을 읽는다).
-- (이동속도 업그레이드 반응은 L3으로 지웠다 — 순서 제약이 없어졌다. 자리는 그대로 둔다.)
local UpgradeRequestService = require(script.Parent.Systems.UpgradeRequestService)
UpgradeRequestService.init()

-- 타이틀(칭호) — 자동 롤 서버 단일 루프 + 요청 채널 (Phase 7 지시서 #10).
-- ⚠️ 순서: ProfileManager.init() 뒤(접속 시 머리 위 칭호 Attribute를 onLoaded로 세운다). 요청 채널은 TitleService 뒤.
local TitleService = require(script.Parent.Systems.TitleService)
TitleService.init()
local TitleRequestService = require(script.Parent.Systems.TitleRequestService)
TitleRequestService.init()

-- 아우라 + 설정 요청 채널 (Phase 7 지시서 #11). ⚠️ 순서: ProfileManager.init() 뒤(접속 시 아우라 Attribute를 onLoaded로 세운다).
local AuraService = require(script.Parent.Systems.AuraService)
AuraService.init()
local AuraRequestService = require(script.Parent.Systems.AuraRequestService)
AuraRequestService.init()
local SettingsRequestService = require(script.Parent.Systems.SettingsRequestService)
SettingsRequestService.init()

-- 펫 + 요청 채널 (Phase 7 지시서 #12). ⚠️ 순서: ProfileManager.init() 뒤(접속 시 장착 펫 Attribute를 onLoaded로 세운다).
local PetService = require(script.Parent.Systems.PetService)
PetService.init()
local PetRequestService = require(script.Parent.Systems.PetRequestService)
PetRequestService.init()

-- 로벅스 구매 기반 (Phase 8 지시서 #16 3단계). 게임패스 소유(세션 메모리) · 행운 상품 제한 판정 · 영수증 처리 · 구매 요청 채널.
-- ⚠️ 순서: ProfileManager.init() 뒤(영수증이 프로필을 쓴다). PlayerStateService 앞(스냅샷이 소유 · 제한을 읽는다 — 모듈만 있으면 되지만
-- 접속 조회를 먼저 걸어 둔다). 요청 채널은 셋 뒤.
local GamepassService = require(script.Parent.Systems.GamepassService)
GamepassService.init(TEST_GAMEPASSES)
local PolicyGate = require(script.Parent.Systems.PolicyGate)
PolicyGate.init()
-- 부스트(포션) 엔진 — 접속 중에만 남은 시간을 깎는 서버 단일 루프(지시서 #16 4단계 S7).
local BoostService = require(script.Parent.Systems.BoostService)
BoostService.init()
local ProductService = require(script.Parent.Systems.ProductService)
ProductService.init()
-- 개발자 상품 16개 지급 함수(지시서 #17 4단계). 지급하면 PlayerState에 알린다 — 모듈만 먼저 불러 둔다(init은 아래 원래 자리)
local PlayerStateService = require(script.Parent.Systems.PlayerStateService)
-- [Bootstrap][VERIFY][SHOP] 줄을 지급 · 포션 켜기 뒤에도 찍는다(아래 VERIFY 절에서 채운다 — 효과 값 전후 대조용)
local printShopLine: ((Player) -> ())? = nil
local function notifyState(player: Player)
	PlayerStateService.notify(player)
	if printShopLine ~= nil then
		(printShopLine :: (Player) -> ())(player)
	end
end
local granted = require(script.Parent.Systems.ProductGrants).registerAll({
	register = ProductService.register,
	notify = notifyState,
})
print(string.format("[Bootstrap] 개발자 상품 지급 함수 %d개 등록", #granted))
ProductService.startTestReceipts(TEST_RECEIPTS, game:GetService("RunService"):IsStudio())
-- 포션 켜기 채널(지시서 #17 4단계): 보관함 −1 → 부스트 15분
require(script.Parent.Systems.PotionRequestService).init({
	getData = function(player: Player)
		local profile = ProfileManager.get(player)
		return if profile ~= nil then profile.Data else nil
	end,
	isRestricted = PolicyGate.isPaidRandomRestricted,
	addBoost = BoostService.add,
	notify = notifyState,
})
local PurchaseRequestService = require(script.Parent.Systems.PurchaseRequestService)
PurchaseRequestService.init()
-- 대시보드 가격 대조(지시서 #17 3단계) — 시작 때 한 번, 다르면 WARN만(자동으로 고치지 않는다). 기다리지 않는다(조회는 뒤에서)
local ShopPriceCheck = require(script.Parent.Systems.ShopPriceCheck)
task.spawn(function()
	ShopPriceCheck.run({ gateway = require(script.Parent.Systems.MarketplaceGateway).get() })
end)
-- 자동 클리커(지시서 #16 4단계 S8). ⚠️ 순서: ClickService.init() 뒤(수동 차단 훅을 단다).
local AutoClickService = require(script.Parent.Systems.AutoClickService)
AutoClickService.init()

-- [Bootstrap][VERIFY][SHOP] 상시 유지 — 게임패스 소유가 확정되거나 바뀔 때마다 효과 값 한 줄(지시서 #16 6단계).
-- 효과는 세션 값이라 화면 말고는 흔적이 없다 — 가짜 소유(TEST_GAMEPASSES) Play에서 "켜기 전 / 켠 뒤"를 이 줄로 대조한다.
-- 읽기만 한다(값을 바꾸지 않는다). execute_luau는 모듈 캐시가 따로라 게임 상태를 못 읽는다 — 관측은 이 줄로 한다.
do
	local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
	local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
	local ShopEffects = require(script.Parent.Systems.ShopEffects)
	local UpgradeService = require(script.Parent.Systems.UpgradeService)
	local RollService = require(script.Parent.Systems.RollService)
	local ChallengeServiceV = require(script.Parent.Systems.ChallengeService)
	local AuraServiceV = require(script.Parent.Systems.AuraService)
	local TitleServiceV = require(script.Parent.Systems.TitleService)
	local PetServiceV = require(script.Parent.Systems.PetService)
	local function shopLine(player: Player): string
		local profile = ProfileManager.get(player)
		local parts = { "owned=" .. table.concat(GamepassService.ownedKeys(player), ","),
			"restricted=" .. tostring(PolicyGate.isPaidRandomRestricted(player)) }
		local tier, potion = ShopEffects.strength(player)
		local dPass, dPotion = ShopEffects.damage(player)
		table.insert(parts, string.format("tier=%s strPotion=%s strengthMult=%s", tier, potion, BigNum.tostring(ClickService.strengthMultiplierOf(player))))
		table.insert(parts, string.format("damageMult=%s", AttackService.combineDamageMultiplier({
			punchDamage = UpgradeService.getEffect(player, "punchDamage"), auraMult = AuraServiceV.getMult(player), passMult = dPass, potionMult = dPotion })))
		table.insert(parts, string.format("bloxMult=%s", ChallengeServiceV.combineBloxMultiplier({
			bloxGain = UpgradeService.getEffect(player, "bloxGain"), titleMult = TitleServiceV.getMult(player), passMult = ShopEffects.blox(player) })))
		table.insert(parts, "autoRate=" .. ShopEffects.autoClickRate(player))
		if profile ~= nil then
			local d = profile.Data
			local inv = PlayerStateService.inventoryInto({}, d)
			table.insert(parts, string.format("potions=%d/%d/%d credits=%d/%d gymUnlocks=%s", inv.potions.strength, inv.potions.damage,
				inv.potions.luck, inv.rollCredits.lucky, inv.rollCredits.super, table.concat(inv.gymUnlocks, ",")))
		end
		if profile ~= nil then
			local data = profile.Data
			local preview = RebirthService.previewGain(player)
			table.insert(parts, string.format("blox=%s rebirthGain=%s", BigNum.tostring(data.blox), if preview ~= nil then BigNum.tostring(preview) else "-"))
			local pets = PetServiceV.summarizeFor(player, data)
			table.insert(parts, string.format("petSlots=%d petStorage=%d", pets.slots, pets.storage))
			for _, roll in ipairs({ "title", "aura", "pet" }) do
				table.insert(parts, string.format("luck_%s=%.4f", roll, RollService.computeLuck(roll, data, ShopEffects.luckOptions(player, roll))))
			end
			local vi = GymConfig.findByGamepass("voidTrainingZone") :: number
			local c = GymLayout.computeLayout(GymConfig.getCount())[vi]
			local r = GymLayout.resolve(Vector3.new(c.X, c.Y + 3, c.Z), data.rebirths, GymLayout.shopUnlocked(data.gymUnlocks, GamepassService.ownsFn(player)))
			table.insert(parts, "voidMult=" .. r.multiplier)
		end
		return string.format("[Bootstrap][VERIFY][SHOP] %s %s", player.Name, table.concat(parts, " "))
	end
	GamepassService.onChanged(function(player: Player)
		task.spawn(function()
			ProfileManager.waitFor(player, 10)
			print(shopLine(player))
		end)
	end)
	printShopLine = function(player: Player)
		print(shopLine(player))
	end
end

-- 플레이어 상태 채널을 연다 (Phase 6 지시서 #5 — HUD가 서버 값을 보인다).
-- ⚠️ 순서: ProfileManager · PadService · SpeedService · ChallengeService가 준비된 뒤여야 한다.
-- 스냅샷은 그 넷에서 읽고, 접속 직후 런 상태 sync는 ChallengeService.syncRunState가 보낸다.
-- 아무 상태도 바꾸지 않는다(읽기 + 통지).
PlayerStateService.init()

-- 프로필 읽기 print. 검증용 임시 코드가 아니라 상시 유지 대상이다.
--
-- ⚠️ lifetimeBlox를 지우지 말 것. 이 값은 클릭 파워 패드 해금(ClickPadConfig)과
-- 아우라 팩 해금 두 곳의 판정 기준인데 아직 이를 보여주는 UI가 없다. 값이 어긋나도
-- 화면에 아무 흔적이 없어서 다른 기능의 버그로 오인된다 — 실제로 "패드2가 안 열린다"로
-- 한 번 오진했다(원인은 lifetimeBlox=32). 서버 로그가 유일한 관측 지점이다.
Players.PlayerAdded:Connect(function(player: Player)
	local profile = ProfileManager.waitFor(player, 10)
	if profile == nil then
		warn(string.format("[Bootstrap][VERIFY] %s: waitFor 타임아웃 - 프로필 없음", player.Name))
		return
	end

	local b = profile.Data.blox
	local lb = profile.Data.lifetimeBlox
	local life = profile.Data.lifeBlox -- 패드 해금 기준 (이번 생애 누적, 환생하면 0)
	print(string.format(
		"[Bootstrap][VERIFY] %s schema=%s firstJoin=%s blox={m=%s, e=%s} lifetimeBlox={m=%s, e=%s} lifeBlox={m=%s, e=%s} pad=%s",
		player.Name,
		tostring(profile.Data.schemaVersion),
		tostring(profile.Data.stats.firstJoin),
		tostring(b.m),
		tostring(b.e),
		tostring(lb.m),
		tostring(lb.e),
		tostring(life and life.m),
		tostring(life and life.e),
		tostring(profile.Data.progress.selectedPadIndex)
	))

	-- WalkSpeed 실측 print. 위 lifetimeBlox print와 같은 성격이라 **상시 유지**한다.
	-- 1회성 검증 코드가 아니다 — 4-2-c Remotes 배선 후에도 같은 자리에서 확인한다.
	--
	-- 왜 필요한가: `[SpeedService] 초기화 완료`는 init()이 돌았다는 것만 말한다.
	-- CharacterAdded가 실제로 Humanoid.WalkSpeed를 세팅했는지는 아무 흔적이 없고,
	-- 속도는 UI가 없어서 화면으로도 확인이 안 된다. 세팅이 통째로 빠져도 캐릭터는
	-- 로블록스 기본값 16으로 멀쩡히 걸어다니므로 증상이 나타나지 않는다.
	--
	-- ⚠️ 커맨드 바에서 require로 확인하지 말 것. 커맨드 바는 별도 require 캐시를 써서
	-- 서버가 들고 있는 것과 다른 모듈 인스턴스를 잡는다 — states 테이블이 비어 보인다.
	--
	-- 판정 기준: **WalkSpeed == max**. 값이 몇이냐가 아니라 둘이 같으냐가 전부다.
	-- (2026-08-26) 스폰 즉시 적용이 들어가면서 기준이 이걸로 바뀌었다. 그 전에는
	-- 스폰 직후 최대 1.5초 동안 WalkSpeed(16) ≠ max가 정상이었고, 주기 검사가 한 바퀴
	-- 돈 뒤에야 맞았다. 이제 그 창이 없으므로 **스폰 직후에 이미 같아야 한다.**
	-- 어긋나면 SpeedService의 스폰 훅 또는 프로필 로드 훅 중 하나가 끊긴 것이다.
	--
	-- level까지 함께 찍는 이유: WalkSpeed만 찍으면 "세팅이 안 된 16"과 "세팅된 16"이
	-- 구분되지 않는다. 레벨 0에서는 max도 16이라 셋이 전부 같아야 정상이다.
	--
	-- req=적용/폐기 last=마지막적용값 — 커스텀 스피드 요청 경로의 관측 지점이다 (4-2-c).
	-- 상시 유지 대상이며, 이유는 WalkSpeed를 찍는 이유와 같다: 이 채널에는 UI가 없어서
	-- (Phase 6) 배선이 통째로 끊겨도 캐릭터는 최대속도로 멀쩡히 걸어다닌다. 증상이 없다.
	--
	-- ⚠️ 첫 스폰에서는 항상 0/0 last=0.0이다. 그게 정상이고, 이 값이 쓸모를 갖는 순간은
	--    **요청을 보낸 뒤 죽거나 리스폰했을 때**다. 그때도 0/0이면 요청이 서버에 한 번도
	--    닿지 않은 것이고, applied가 늘었는데 last가 0이면 setCustomSpeed까지는 갔으나
	--    값이 전부 거부된 것이다 — 두 고장이 이 한 줄에서 갈린다.
	--    (집계는 세션 메모리이고 퇴장 시 지워진다. 재접속하면 다시 0/0이다)
	local character = player.Character or player.CharacterAdded:Wait()

	-- ⚠️ 한 프레임 양보한다. SpeedService도 같은 CharacterAdded에 걸려 있는데 두 핸들러의
	-- 실행 순서는 보장되지 않는다. 양보하지 않으면 SpeedService가 세팅하기 *전*의 값을
	-- 읽을 수 있고, 레벨 0에서는 그 값이 기본값 16이라 정상 출력과 구분이 안 된다.
	task.wait()

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil then
		warn(string.format("[Bootstrap][VERIFY] %s: Humanoid 없음 - WalkSpeed 확인 불가", player.Name))
		return
	end


	-- ===== [ATTACK] 관측 (4-2-e2). 상시 유지 대상이다 =====================================
	--
	-- ⚠️ 잔재가 아니다. req= · last= 필드와 같은 성격이고 같은 이유로 있다:
	-- 이 경로에는 UI가 없어서(Phase 6) 배선이 끊겨도 화면에 아무 흔적이 없다.
	--
	-- ⚠️ **이 세 값이 이번 RC 검증의 전부다.** 3레이어(배수 배선 / 반경 판정 / 펀치 루프)를
	-- 한 번에 보는 Play라 "딜이 안 들어간다" 하나에 후보가 넷이다:
	--   배수 미배선   mult= 이 1.00인데 환생을 했다     → StrengthMultiplier 경로
	--   반경 판정     result=out_of_range               → 캐릭터가 멀리 있다 (정상일 수 있다)
	--   펀치 루프     줄 자체가 안 찍힌다               → AttackService.init 배선
	--   applyDamage   result=no_changes                 → 하류가 거부했다
	-- 이 필드들이 없으면 넷을 코드로 읽어 추측하게 된다.
	--
	-- ⚠️ 매 틱 찍지 않는다. 펀치는 초당 2회라 그대로 찍으면 다른 로그가 전부 묻힌다.
	-- **결과 코드가 바뀔 때만** 찍는다 — 상태 전이가 관심사이지 매회의 값이 아니다.
	-- (예전의 dedupe 우회 분기는 3c에서 ADVANCE_VERIFY_ENABLED와 함께 지웠다 — 이 억제가
	-- 상시 동작이다. 우회를 되살리면 초당 2줄이 찍혀 전이가 묻힌다.)
	local AttackService = require(script.Parent.Systems.AttackService)

	task.spawn(function()
		local lastResult: string? = nil

		while player.Parent ~= nil do
			task.wait(ATTACK_VERIFY_POLL_SEC)

			local outcome = AttackService.getLastOutcome(player)
			if outcome ~= nil and outcome.result ~= lastResult then
				lastResult = outcome.result

				-- 배수는 AttackService가 모른다(힘 트랙이다). 여기서 직접 만든다 —
				-- 클릭 지급이 쓰는 것과 **같은 compute**를 태워야 값이 갈리지 않는다.
				local mult = ClickService.strengthMultiplierOf(player)

				print(string.format(
					"[Bootstrap][ATTACK] %s result=%s dist=%s/%.1f (%s) dmg=%s mult=%s str=%s",
					player.Name,
					outcome.result,
					outcome.distance and string.format("%.1f", outcome.distance) or "-",
					AttackConfig.getRadius(),
					outcome.distance and (AttackConfig.isInRange(outcome.distance) and "in" or "out") or "-",
					outcome.damage and BigNum.tostring(outcome.damage) or "-",
					BigNum.tostring(mult),
					BigNum.tostring(CurrencyService.get(player, "strength") or BigNum.new(0, 0))
				))
			end
		end
	end)

	local speedStats = SpeedRequestService.getStats(player)
	print(string.format(
		"[Bootstrap][VERIFY] %s WalkSpeed=%.1f max=%.1f level=%d req=%d/%d last=%.1f (스폰 직후)",
		player.Name,
		humanoid.WalkSpeed,
		SpeedService.getMaxSpeed(player),
		LevelConfig.getLevel(CurrencyService.get(player, "strength") or BigNum.new(0, 0)),
		speedStats.applied,
		speedStats.dropped,
		speedStats.last
	))
end)

-- (REBIRTH_VERIFY_ENABLED 블록은 2026-10-22 지웠다 — 환생 창(Phase 6 지시서 #5)이 실물 진입점이 됐다.
--  실물 환생 뒤 WalkSpeed가 내려가는지는 환생 창으로 환생한 Play에서 [RebirthRequestService] 줄과
--  PlayerState의 walkSpeed · maxWalkSpeed로 본다. 마지막 코드는 git 이력에 있다.)

-- ⚠️ 임시 검증 코드. ChallengeService가 BlockService/CurrencyService를 올바른 순서·값으로
-- 배선했는지 — 특히 cashout()이 CurrencyService.add까지 실제로 도달해서 blox를 지급하는지 —
-- 확인한다. 가짜 Player 테이블로는 ProfileManager.get이 nil을 반환해서 CurrencyService.add가
-- 항상 "프로필 없음"으로 거부되기 때문에(ChallengeServiceTests는 거부 경로만 검증 가능),
-- 실제 접속한 플레이어로만 이 성공 경로를 확인할 수 있다.
-- RemoteEvent가 붙어 실제 플레이로 이 경로가 자연히 검증되는 단계에서 이 블록 전체 삭제.
--
-- 2026-10-22 꺼짐(사람 결정 V1): 접속마다 캐릭터가 저절로 1층을 돌고 수령해 사람이 직접 한 판 할 때
-- 방해된다. 코드는 지우지 않는다 — 매 Play 전 구간을 자동으로 확인하는 수단이라, 직접 플레이로
-- 경로가 안정됐다고 확인된 뒤에 지운다. 다시 보고 싶으면 이 값만 true로 켠다(켠 Play는 blox +1).
local VERIFY_CHALLENGE = false

-- ── 개발용 플래그: CHALLENGE_REVERIFY_ON_RESPAWN ──────────────────────────────
-- 리스폰할 때마다 챌린지 검증을 다시 돌린다. 사람이 3b(수령 발판)·3d(스폰 복귀)를
-- 눈으로 확인하려면 런을 여러 번 세워야 하는데, Bootstrap은 원래 접속 시 1회로 끝난다 —
-- 한 번 실패하면 나가서 다시 들어오는 수밖에 없었다.
--
-- **쓰는 법: Esc → Reset Character.** 그러면 스폰에서 다시 살아나고, 이 훅이
-- 캐릭터를 입장 게이트 앞으로 옮겨 걸어 지나가게 한다(런은 게이트가 세운다).
--
-- ⚠️ 리스폰이라는 **명시적 사람 동작**에만 걸린다. 주기 재시작으로 하지 않은 이유가
-- 이것이다 — 폴링으로 런을 다시 세우면 플레이 중에 끼어들고, 캐릭터까지 옮기면
-- 조작을 빼앗는다. 리스폰은 사람이 스스로 누르는 것이라 끼어들 여지가 없다.
--
-- ⚠️ **프로덕션에 켠 채로 남기지 말 것.** 남으면 유저가 리셋만으로 런을 임의로
-- 시작할 수 있게 된다 — 20초 타이머를 리셋으로 회피하는 길이 열린다.
--
-- **켜는 법: 이 줄을 true로 고치고 Rojo sync.** 지우지 말 것 — 3b·3d를 다시
-- 봐야 할 때 없으면 또 만들게 된다.
-- 지금 false인 이유: 3b·3d가 실물에서 확인됐다(발판 지급 로그 1줄 = 디바운스 동작,
-- reason=challenge_cashout_cashout_pad_stage_1 = source 조립 동작, 그리고
-- 수령 뒤 dist=399.4 = 스폰 복귀 동작). 켜둘 이유가 없어졌다.
--
-- ⚠️ 이 플래그는 `if VERIFY_CHALLENGE then` 안에 있어서 그쪽이 false면 어차피 죽는다.
-- 그것을 "프로덕션에서 확실히 꺼지는 구조"로 치지 않는다 — 사람이 고치는 플래그가
-- 하나 더 있는 것일 뿐이고, 회피 경로를 여는 값이 사람의 기억에 걸려 있으면 안 된다.
-- 진짜 방어선은 Phase 6 UI에서 이 블록을 통째로 지우는 것이다(docs/PENDING.md 잔재).
local CHALLENGE_REVERIFY_ON_RESPAWN = false

if VERIFY_CHALLENGE then
	-- ReplicatedStorage / BigNum / CurrencyService는 파일 상단에서 이미 require했다.
	local ChallengeService = require(script.Parent.Systems.ChallengeService)
	local BlockService = require(script.Parent.Systems.BlockService)
	local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)

	local function fmtBigNum(bn): string
		if bn == nil then
			return "nil"
		end
		return string.format("{m=%s, e=%s}", tostring(bn.m), tostring(bn.e))
	end

	-- 게이트가 런을 세우기까지 기다리는 최대 시간(초). 게이트 앞에서 출발해 한 깊이를
	-- 걷는 데 1초 안쪽이 걸린다 — 넉넉히 잡되 Play 하나를 붙잡을 만큼 길지 않게.
	local GATE_RUN_WAIT_SEC = 5

	-- 캐릭터를 **입장 게이트 바로 앞**에 세우고 게이트 너머로 걸어가게 한다.
	--
	-- 왜 걷는가: 런은 게이트를 지나는 순간 선다(EntranceGateService). 이 검증은 더 이상
	-- startRun을 직접 부르지 않고 게이트가 세운 런을 쓴다 — 그래서 매 Play가 게이트를
	-- 저절로 검증한다. 게이트 **안으로** 순간이동만 하면 Touched가 나지 않을 수 있어서,
	-- 앞에 세운 뒤 서버 Humanoid:MoveTo로 실제로 지나가게 한다.
	--
	-- ⚠️ 좌표는 ArenaConfig 파생뿐이다. 출발점 = 게이트 중심 − 게이트 깊이(앞면에서 반 깊이
	-- 떨어진 스폰 쪽), 도착점 = 게이트 중심 + 게이트 깊이(먼 면에서 반 깊이 지난 챌린지 쪽).
	-- 도착점은 스테이지 1 블록 바깥면보다 멀고 판정 반경보다 가까워야 한다 — 아래에서
	-- 실제 거리를 찍는다. Config가 바뀌어 이 관계가 깨지면 로그가 먼저 말해준다.
	-- ⚠️ 도착점이 게이트 밖인 이유: 게이트 안에 서 있으면 cashout으로 런이 끝난 뒤의
	-- 접촉이 새 런을 세운다.
	local function walkThroughEntranceGate(player: Player): boolean
		local character = player.Character
		if character == nil then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 캐릭터 없음 - 게이트 통과 건너뜀", player.Name))
			return false
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if character:FindFirstChild("HumanoidRootPart") == nil or humanoid == nil then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: HumanoidRootPart/Humanoid 없음 - 게이트 통과 건너뜀", player.Name))
			return false
		end

		local gateX = ArenaConfig.getEntranceGateCenter()
		local gateDepth = ArenaConfig.getEntranceGateSize().X
		local startX = gateX - gateDepth
		local targetX = gateX + gateDepth

		local ok, err = pcall(function()
			-- 지면(Y=0) 위에 세운다. PivotTo는 모델 중심을 맞추므로 절반을 올린다 —
			-- 높이는 아바타마다 달라서 상수로 박지 않는다(ArenaService.returnToSpawn과 같은 이유).
			local extents = character:GetExtentsSize()
			character:PivotTo(CFrame.new(Vector3.new(startX, extents.Y / 2, 0)))
		end)
		if not ok then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 게이트 앞 이동 실패 - %s", player.Name, tostring(err)))
			return false
		end

		-- 순간이동 직후 한 프레임은 물리가 자리를 잡는 중이다. 바로 MoveTo를 걸면 옛 위치
		-- 기준으로 계산될 수 있다.
		task.wait()
		humanoid:MoveTo(Vector3.new(targetX, 0, 0))

		-- 스테이지 1 블록 클러스터 중심까지의 거리. "사거리 안에서 멈추는가"를 로그만 보고
		-- 알 수 있게 한다. ⚠️ math.abs(targetX)로 쓰지 말 것 — 중심을 빼야 Config가 바뀌어도 맞다.
		local distance = math.abs(targetX - ArenaConfig.getStageCenterX(1))
		local radius = AttackConfig.getRadius()
		print(string.format(
			"[Bootstrap][VERIFY_CHALLENGE] %s 입장 게이트 통과 걷기 X=%.1f -> %.1f (게이트 X=%.1f, 도착점에서 블록까지 %.1f / 반경 %.1f -> %s)",
			player.Name,
			startX,
			targetX,
			gateX,
			distance,
			radius,
			AttackConfig.isInRange(distance) and "사거리 안" or "사거리 밖"
		))

		if not AttackConfig.isInRange(distance) then
			warn(string.format(
				"[Bootstrap][VERIFY_CHALLENGE] %s: 도착점이 사거리 밖이다 - ArenaConfig/AttackConfig 관계가 깨졌다. 검증은 계속하지만 클리어는 안 된다",
				player.Name
			))
		end

		return true
	end

	-- 게이트가 세운 런을 기다린다. 섰으면 걸린 시간을, 안 섰으면 nil을 준다.
	local function waitForGateRun(player: Player): number?
		local startedAt = os.clock()
		while os.clock() - startedAt < GATE_RUN_WAIT_SEC do
			if ChallengeService.getRunState(player) ~= nil then
				return os.clock() - startedAt
			end
			task.wait(0.1)
		end
		return nil
	end

	local function runChallengeVerification(player: Player)
		local profile = ProfileManager.waitFor(player, 10)
		if profile == nil then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 프로필 로드 대기 타임아웃 - 검증 중단", player.Name))
			return
		end

		-- 캐릭터가 서기를 기다린 뒤 게이트 앞에 세우고 걸어서 지나가게 한다.
		if player.Character == nil then
			player.CharacterAdded:Wait()
		end

		-- 이미 런이 있으면 게이트는 아무것도 하지 않는다 — 그러면 아래 대기가 "게이트가
		-- 세웠다"로 오독된다. 걸어가기 전에 확인해서 따로 찍는다.
		if ChallengeService.getRunState(player) ~= nil then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 이미 활성 런이 있다 - 게이트 검증을 할 수 없어 중단", player.Name))
			return
		end

		if not walkThroughEntranceGate(player) then
			return
		end

		local ok, err = pcall(function()
			-- 1. 게이트가 런을 세웠는가 (startRun은 EntranceGateService가 부른다)
			local waited = waitForGateRun(player)
			if waited == nil then
				warn(string.format(
					"[Bootstrap][VERIFY_CHALLENGE] %s: 게이트가 런을 세우지 않았다 (%.1f초 대기) - 검증 중단",
					player.Name,
					GATE_RUN_WAIT_SEC
				))
				return
			end
			print(string.format(
				"[Bootstrap][VERIFY_CHALLENGE] %s 게이트가 런을 세움 = true (걷기 시작 후 %.2f초, stage=%d)",
				player.Name,
				waited,
				(ChallengeService.getRunState(player) :: any).stage
			))

			-- 2. getSnapshot으로 블록 좌표를 받아 각 좌표에 압도적 데미지로 applyDamage
			local snapshot = BlockService.getSnapshot(player)
			if snapshot == nil then
				warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 블록 스냅샷 없음 - 검증 중단", player.Name))
				return
			end

			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s 블록 %d개 배치됨 - 데미지는 AttackService가 넣는다", player.Name, #snapshot))

			-- AttackService가 몇 번 때릴 시간을 준다.
			-- ⚠️ 여기서 데미지를 직접 넣지 않는다 (4-2-e2). 예전에는 HUGE_DAMAGE(10^999)를
			-- 모든 블록에 꽂아 한 프레임에 클리어시켰는데, 그러면 **새 공격 경로가 도는지
			-- 보이지 않는다** — 블록이 이미 없어진 뒤에 AttackService가 돌기 때문이다.
			-- timeLeft가 항상 20.0이었던 것도 이 때문이다 (→ docs/PENDING.md).
			--
			-- ⚠️ 그렇다고 이 블록을 통째로 끄지도 않는다. 끄면 입장 게이트·getSnapshot·cashout
			-- 이라는 진입점 검증이 관측 밖으로 나간다. 런을 세우는 데까지가 이 블록의
			-- 몫이고, 부수는 것은 AttackService가 한다.
			--
			-- 그래서 아래 클리어 검사는 **캐릭터가 반경 안에 있을 때만** 통과한다.
			-- 반경 밖이면 클리어 실패로 빠지는 것이 정상이고, 그때는 [ATTACK] 줄의
			-- out_of_range가 이유를 말해준다.
			task.wait(ATTACK_OBSERVE_SEC)

			local runStateAfterClear = ChallengeService.getRunState(player)
			local cleared = runStateAfterClear ~= nil and runStateAfterClear.cleared
			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s 클리어 여부: cleared=%s", player.Name, tostring(cleared)))

			if not cleared then
				warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 클리어 실패 - cashout 검증 중단", player.Name))
				return
			end

			-- (예전 2-b 진행 검증 — ADVANCE_VERIFY_ENABLED가 여기서 advance()를 불렀다 — 은
			-- 3c에서 지웠다. 진행은 진행 벽을 걸어서 통과하는 것으로 본다 — AdvanceWallService.)

			-- 3. cashout 전 blox 값 기록
			local bloxBefore = CurrencyService.get(player, "blox")
			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s cashout 전 blox=%s", player.Name, fmtBigNum(bloxBefore)))

			-- 4. cashout(player, "bootstrap_verify")
			--    source를 붙이는 이유: 이 루틴은 실제 프로필에 blox를 지급한다. source가 없으면
			--    CurrencyService 로그에 reason=challenge_cashout_unknown으로 남아서, 수령 경로별
			--    통계를 볼 때(Phase 4-2-f) 개발 중 검증 지급이 실제 플레이 데이터에 섞인다.
			local cashoutOk, reward = ChallengeService.cashout(player, "bootstrap_verify")
			print(string.format(
				"[Bootstrap][VERIFY_CHALLENGE] %s cashout(ok=%s) 보상액=%s",
				player.Name,
				tostring(cashoutOk),
				fmtBigNum(reward)
			))

			-- 5. cashout 후 blox 값과 getRunState 확인
			local bloxAfter = CurrencyService.get(player, "blox")
			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s cashout 후 blox=%s", player.Name, fmtBigNum(bloxAfter)))

			if cashoutOk and bloxBefore ~= nil and bloxAfter ~= nil and reward ~= nil then
				local delta = BigNum.sub(bloxAfter, bloxBefore)
				local matches = BigNum.eq(delta, reward)
				print(string.format(
					"[Bootstrap][VERIFY_CHALLENGE] %s 증가분=%s vs 보상액=%s -> %s",
					player.Name,
					fmtBigNum(delta),
					fmtBigNum(reward),
					matches and "일치" or "불일치"
				))
			else
				warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: cashout 실패 또는 값 누락 - 증가분 비교 불가", player.Name))
			end

			local runStateAfterCashout = ChallengeService.getRunState(player)
			print(string.format(
				"[Bootstrap][VERIFY_CHALLENGE] %s 런 종료 여부(getRunState == nil): %s",
				player.Name,
				tostring(runStateAfterCashout == nil)
			))
		end)

		if not ok then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 검증 중 에러 - %s", player.Name, tostring(err)))
		end
	end

	Players.PlayerAdded:Connect(function(player: Player)
		-- 첫 스폰. runChallengeVerification이 안에서 첫 CharacterAdded를 소비한다.
		runChallengeVerification(player)

		if not CHALLENGE_REVERIFY_ON_RESPAWN then
			return
		end

		-- ⚠️ 여기서 연결하는 이유가 있다. 위 호출이 첫 CharacterAdded를 이미 기다려
		-- 소비했으므로, 이 시점 이후에 오는 발화는 **전부 리스폰**이다. 카운터로
		-- 첫 회를 세지 않아도 되고, 세는 코드가 없으면 어긋날 일도 없다.
		player.CharacterAdded:Connect(function()
			-- 캐릭터가 조립될 시간을 준다. 바로 옮기면 부위가 다 붙기 전이라
			-- GetExtentsSize가 실제와 다른 값을 준다.
			task.wait()

			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s 리스폰 감지 - 검증을 다시 돌린다", player.Name))

			-- 이전 런이 남아 있으면 걷어낸다. 안 그러면 startRun이 덮어쓰면서
			-- 그 런의 종료 통지가 안 나가고, 클라 블록이 옛 세트로 남는다.
			ChallengeService.abandonRun(player)

			runChallengeVerification(player)
		end)
	end)
end

-- (WARP_VERIFY_ENABLED 블록은 2026-10-22 지웠다 — 월드·워프 창(Phase 6 지시서 #6)이 실물 진입점이 됐다.
--  실물 워프는 창으로 워프한 Play의 [WarpRequestService] 줄 · 캐릭터 위치 · RunStateChanged로 본다.
--  마지막 코드는 git 이력에 있다.)

-- ── 개발용 플래그: STANDARD_PATH_REPORT_ENABLED ───────────────────────────────
-- 표준 경로 시뮬레이터(4-2-f). 클릭률 6/8/10 세 벌의 표를 Play 로그로 찍는다.
-- 목적은 "17층 절벽이 표준 경로를 실제로 막는가"에 답할 숫자를 얻는 것이다.
--
-- ⚠️ 지운 WARP_VERIFY_ENABLED · REBIRTH_VERIFY_ENABLED와 **성격이 다르다.
--    같이 볼 때 같은 물건으로 취급하지 말 것.** 저것들은 켜면 blox와 lifetimeBlox가
--    되돌릴 수 없게 올라 접속한 계정이 오염되므로 켠 채로 커밋하면 안 된다.
--    이 리포트는 **Config만 읽고 순수 계산 후 print한다** — 프로필을 읽지도 쓰지도
--    않으므로 켠 채로 커밋해도 안전하다.
--
-- 끄는 이유는 오염이 아니라 소음이다. 4-2-f 동안 값을 바꿔가며 반복 실행할 물건이라,
-- 매 Play마다 표 세 벌이 찍히면 [ATTACK]·[Bootstrap] 관측 로그가 묻힌다.
--
-- 4-2-f 종료 후 이 블록 삭제 (docs/PENDING.md 잔재).
local STANDARD_PATH_REPORT_ENABLED = false

if STANDARD_PATH_REPORT_ENABLED then
	-- task.spawn: 뽑기 3종 · 걷기가 들어가(지시서 #13) 계산이 길어졌다 — 서버 시작을 붙잡지 않는다(SUCCESS_RATE_REPORT와 같다).
	task.spawn(function()
		require(script.Parent.Tools.StandardPathReport).run()
	end)
end


-- ── 개발용 플래그: SUCCESS_RATE_REPORT_ENABLED ────────────────────────────────
-- 확률적 플레이어 성공률 시뮬레이터(4-2-f). 층별 "첫 도달 성공률"과 HP 구간 합산을 찍는다.
-- 플레이어 모델(클릭 속도·반경 밖 시간·런 중 클릭·진행 문턱)은 사람 결정이다 — 파일 상단 MODEL.
--
-- ⚠️ STANDARD_PATH_REPORT_ENABLED와 같은 성격이다 — Config만 읽고 순수 계산 후 print한다.
--    프로필을 읽지도 쓰지도 않으므로 켠 채로 커밋해도 계정을 오염시키지 않는다.
--    기본값 false인 이유는 소음과 계산 시간이다. task.spawn으로 돌려 서버 시작을 붙잡지 않는다.
--
-- 4-2-f 종료 후 이 블록 삭제 (docs/PENDING.md 잔재).
local SUCCESS_RATE_REPORT_ENABLED = false

if SUCCESS_RATE_REPORT_ENABLED then
	task.spawn(function()
		require(script.Parent.Tools.SuccessRateReport).run()
	end)
end

-- ── 개발용 플래그: BALANCE_SUMMARY_ENABLED (지시서 #13 6단계 — 사람용 튜닝 요약) ─────────────
-- Play 한 번에 핵심 지표를 30줄 안팎으로 찍는다([BALANCE] 줄 — Tools/BalanceSummary). 값을 바꾼 뒤 이것 하나만 켜고 읽는다.
-- 순서 · 읽는 법은 docs/TUNING.md. 프로필을 읽지도 쓰지도 않는다. 이 플래그를 켠 Play에서는 테스트 개수를 세지 않는다.
local BALANCE_SUMMARY_ENABLED = false

if BALANCE_SUMMARY_ENABLED then
	task.spawn(function()
		require(script.Parent.Tools.BalanceSummary).run()
	end)
end

-- ── 개발용 플래그: HP_CANDIDATE_REPORT_ENABLED (지시서 #13 5단계) ─────────────────────
-- HP 곡선 후보 측정(Tools/HpCandidateReport). 기준점 B4 · 넓게 훑기 · 후보 자세히([HPCAND] 줄). ⚠️ 채택하지 않는다(D2).
-- SUCCESS_RATE_REPORT_ENABLED와 같은 성격이다 — Config를 메모리에서 잠깐 갈아끼우고 되돌린다. 프로필을 읽지도 쓰지도 않는다.
-- 계산이 길다(수 분). 이 플래그를 켠 Play에서는 테스트 개수를 세지 않는다.
local HP_CANDIDATE_REPORT_ENABLED = false

if HP_CANDIDATE_REPORT_ENABLED then
	task.spawn(function()
		require(script.Parent.Tools.HpCandidateReport).run()
	end)
end

-- ── 개발용 플래그: TEST_PRESET_EXPORT_ENABLED (지시서 #13 3단계) ──────────────────────
-- 테스트 프리셋(Shared/Config/TestPresets) 값을 다시 뽑는다. SuccessRateReport 결정 모델과 같은 시뮬레이터 · 같은 seed로
-- 시점마다 중앙값 플레이어의 상태를 Lua 표 글자로 print한다([PRESET] 줄) — 그대로 TestPresets.lua에 옮긴다.
-- ⚠️ SUCCESS_RATE_REPORT_ENABLED와 같은 성격이다 — Config만 읽고 print한다. 프로필을 읽지도 쓰지도 않는다.
--    끄는 이유는 소음과 계산 시간이다. 이 플래그를 켠 Play에서는 테스트 개수를 세지 않는다(CLAUDE.md 절대 규칙 8).
local TEST_PRESET_EXPORT_ENABLED = false

if TEST_PRESET_EXPORT_ENABLED then
	task.spawn(function()
		require(script.Parent.Tools.TestPresetExport).run()
	end)
end

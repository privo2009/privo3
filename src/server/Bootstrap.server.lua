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
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)

print("[Bootstrap] ProfileManager.init() 호출 시작")
ProfileManager.init()
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

-- 플레이어 상태 채널을 연다 (Phase 6 지시서 #5 — HUD가 서버 값을 보인다).
-- ⚠️ 순서: ProfileManager · PadService · SpeedService · ChallengeService가 준비된 뒤여야 한다.
-- 스냅샷은 그 넷에서 읽고, 접속 직후 런 상태 sync는 ChallengeService.syncRunState가 보낸다.
-- 아무 상태도 바꾸지 않는다(읽기 + 통지).
local PlayerStateService = require(script.Parent.Systems.PlayerStateService)
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
				local mult = StrengthMultiplier.compute({
					rebirths = CurrencyService.get(player, "rebirths"),
				})

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

-- ⚠️ 임시 검증 코드 (4-2-d). 환생이 **실물에서** 도는지 확인하는 유일한 지점이다.
-- 기본값은 false다 — 필요할 때만 켠다.
--
-- 왜 필요한가: RebirthServiceTests는 deps 이음매로 onRebirth의 **호출 순서**만 잰다.
-- 실제 Humanoid.WalkSpeed가 내려가는지는 그 방식으로 볼 수 없다. 그게 이 블록이
-- 존재하는 이유이고, 아래 출력에서 WalkSpeed를 절대 빼지 말 것 —
-- docs/PENDING.md가 경고한 "레벨 40에서 환생하면 최대치가 56 → 16으로 떨어지는데
-- 56으로 계속 다닌다"가 정확히 이 사각이다. 숫자가 안 내려가면 배선이 끊긴 것이고,
-- UI가 없으므로 다른 증상은 전혀 나타나지 않는다.
--
-- ⚠️ 이 블록은 **실제 프로필을 바꾼다.** 환생시키려면 블럭스가 필요하고, 힘이 내려가는
--    것을 보려면 레벨이 0보다 커야 해서 둘 다 지급한다. 지급은 전부 CurrencyService를
--    통과한다 — profile.blox 직접 대입은 금지다(그 우회 한 줄이 lifetimeBlox 오진을
--    낳았고, 이번엔 rebirths까지 얽혀 있어 오진 범위가 더 넓다).
--    ⚠️ blox add는 lifetimeBlox를 함께 올린다(설계대로). 그래서 이 블록을 켜면 그 계정의
--    클릭 파워 패드가 열린다. 되돌릴 수 없으니 켜기 전에 알고 켤 것.
--
-- ⚠️ source는 "bootstrap_verify"다. 실제 수령·환생과 로그에서 구분돼야 한다
--    (08-23 세션에 cashout에 같은 처리를 한 선례가 있다).
--
-- Phase 6 UI가 붙으면 이 블록 전체 삭제 (docs/PENDING.md 잔재).
local REBIRTH_VERIFY_ENABLED = false

if REBIRTH_VERIFY_ENABLED then
	-- ⚠️ 위에 같은 이름의 파일 스코프 로컬이 있지만 여기서 다시 require한다.
	-- 이 블록은 Phase 6 UI에서 **통째로 삭제**될 물건이라 바깥 로컬에 기대지 않는다
	-- (기대면 지울 때 바깥 배선까지 살펴야 한다). 모듈은 캐시되므로 비용은 없다.
	local RebirthService = require(script.Parent.Systems.RebirthService)
	local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)

	-- 지급량. 환생이 거부되지 않을 만큼의 블럭스와, 레벨이 0보다 커져 속도 하락이
	-- 눈에 보일 만큼의 힘.
	-- ⚠️ 힘 1e20 → 레벨 20 → 최대속도 36. 환생 후 힘 1 → 레벨 0 → 16이 되어야 한다.
	--    두 값이 같게 나오면(둘 다 16) 그건 지급이 안 됐거나 재적용이 끊긴 것이다.
	local VERIFY_BLOX = BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH * 3)
	local VERIFY_STRENGTH = BigNum.new(1, 20)

	local function fmt(bn): string
		if bn == nil then
			return "nil"
		end
		return BigNum.tostring(bn)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		local profile = ProfileManager.waitFor(player, 10)
		if profile == nil then
			warn(string.format("[Bootstrap][REBIRTH_VERIFY] %s: 프로필 로드 타임아웃 - 검증 중단", player.Name))
			return
		end

		local character = player.Character or player.CharacterAdded:Wait()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid == nil then
			warn(string.format("[Bootstrap][REBIRTH_VERIFY] %s: Humanoid 없음 - WalkSpeed 확인 불가", player.Name))
			return
		end
		local hum: Humanoid = humanoid

		-- ⚠️ task.delay로 띄운다. 같은 PlayerAdded에 걸린 아래 VERIFY_CHALLENGE 블록이
		-- 런을 세우고 cashout까지 끝낼 시간을 준다 — 두 블록이 섞이면 로그를 읽을 수
		-- 없고, 환생이 그 런을 중간에 걷어가서 무엇을 본 것인지도 흐려진다.
		-- 여기서 기다리는 것은 이 코루틴뿐이고, 기다림은 rebirth() **호출 전**에
		-- 끝난다 — 그 함수 안의 무-yield 계약과는 무관하다.
		task.delay(3, function()
			if player.Parent == nil or hum.Parent == nil then
				return
			end

			local function snapshot(label: string)
				local strength = CurrencyService.get(player, "strength")
				print(string.format(
					"[Bootstrap][REBIRTH_VERIFY] %s %s - blox=%s strength=%s rebirths=%s level=%d max=%.1f WalkSpeed=%.1f",
					player.Name,
					label,
					fmt(CurrencyService.get(player, "blox")),
					fmt(strength),
					fmt(CurrencyService.get(player, "rebirths")),
					LevelConfig.getLevel(strength or BigNum.new(0, 0)),
					SpeedService.getMaxSpeed(player),
					hum.WalkSpeed
				))
			end

			-- 환생 조건을 만들어 준다. 이미 충분하면 건너뛴다.
			if not CurrencyService.canAfford(player, "blox", VERIFY_BLOX) then
				CurrencyService.add(player, "blox", VERIFY_BLOX, "bootstrap_verify_grant")
			end
			CurrencyService.add(player, "strength", VERIFY_STRENGTH, "bootstrap_verify_grant")

			-- 지급이 WalkSpeed에 반영될 시간을 준다. SpeedService의 주기 검사가 한 바퀴
			-- 돌아야 힘 상승이 속도에 얹힌다(클릭당 세팅을 피한 설계 — SpeedService 상단).
			-- 이걸 건너뛰면 "환생 전 WalkSpeed"가 지급 전 값으로 찍혀서 하락 폭이 가짜가 된다.
			task.wait(2)

			snapshot("환생 전")

			local ok, result = RebirthService.rebirth(player, "bootstrap_verify")

			if ok then
				print(string.format(
					"[Bootstrap][REBIRTH_VERIFY] %s rebirth 성공 - gained=%s total=%s",
					player.Name,
					fmt(result.gained),
					fmt(result.total)
				))
			else
				warn(string.format(
					"[Bootstrap][REBIRTH_VERIFY] %s rebirth 거부 - 사유=%s",
					player.Name,
					tostring(result)
				))
			end

			snapshot("환생 후")

			-- 판정 기준을 로그에 함께 남긴다. 숫자만 보고 나중에 해석하지 않기 위함이다.
			print(string.format(
				"[Bootstrap][REBIRTH_VERIFY] %s 판정: WalkSpeed가 환생 전보다 내려갔어야 한다. 같으면 SpeedService.onRebirth 배선이 끊긴 것 (max=%.1f WalkSpeed=%.1f)",
				player.Name,
				SpeedService.getMaxSpeed(player),
				hum.WalkSpeed
			))
		end)
	end)
end

-- ⚠️ 임시 검증 코드. ChallengeService가 BlockService/CurrencyService를 올바른 순서·값으로
-- 배선했는지 — 특히 cashout()이 CurrencyService.add까지 실제로 도달해서 blox를 지급하는지 —
-- 확인한다. 가짜 Player 테이블로는 ProfileManager.get이 nil을 반환해서 CurrencyService.add가
-- 항상 "프로필 없음"으로 거부되기 때문에(ChallengeServiceTests는 거부 경로만 검증 가능),
-- 실제 접속한 플레이어로만 이 성공 경로를 확인할 수 있다.
-- RemoteEvent가 붙어 실제 플레이로 이 경로가 자연히 검증되는 단계에서 이 블록 전체 삭제.
local VERIFY_CHALLENGE = true

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

-- ⚠️ 임시 검증 코드 (4-2-e). 워프가 **실물에서** 도는지 확인하는 유일한 지점이다.
-- 기본값은 false다 — 필요할 때만 켠다.
--
-- 왜 필요한가: WarpServiceTests는 deps 이음매로 "차감했는가 / 순서가 맞는가"만 잰다.
-- 실제 CurrencyService가 프로필의 blox를 진짜로 깎는지, ChallengeService가 목표 층에
-- 런을 진짜로 세우는지는 그 방식으로 볼 수 없다 — 가짜 Player 테이블이면
-- ProfileManager.get이 nil을 주므로 모든 경로가 "프로필 없음" 한 갈래로 끝난다.
-- (VERIFY_CHALLENGE 블록이 존재하는 이유와 같은 제약이다)
--
-- ⚠️ 이 블록은 **실제 프로필을 바꾼다.** 워프하려면 블럭스가 필요해서 지급한다.
--    지급은 전부 CurrencyService를 통과한다 — profile.blox 직접 대입은 금지다
--    (CLAUDE.md 절대 규칙 2. 그 우회 한 줄이 lifetimeBlox 오진을 낳은 전례가 있다).
--    ⚠️ blox add는 lifetimeBlox를 함께 올린다(설계대로). 그래서 이 블록을 켜면 그 계정의
--    클릭 파워 패드가 열린다. 되돌릴 수 없으니 켜기 전에 알고 켤 것.
--    (REBIRTH_VERIFY_ENABLED에 붙은 경고와 완전히 같은 성격이다)
--
-- ⚠️ source는 "bootstrap_verify"다. 실제 워프와 로그에서 구분돼야 한다.
--
-- Phase 6 UI(텔레포트 버튼 → 스테이지 선택창)가 붙으면 이 블록 전체 삭제
-- (docs/PENDING.md 잔재).
local WARP_VERIFY_ENABLED = false

-- 워프할 목표 층.
--
-- ⚠️ 1층으로 두지 말 것. 위 VERIFY_CHALLENGE 블록이 이미 1층에 런을 세우므로,
-- 워프도 1층으로 가면 getRunState().stage == 1이 **어느 블록 때문인지 구분되지 않는다.**
-- 그러면 이 검증이 아무것도 증명하지 못한다. "1층에서 두 칸 건너뛰었다"가 보여야 한다.
--
-- 3층인 이유: 비용이 cost(s) = TEMP_COST_BASE × TEMP_COST_RATIO^(s-1)로 층당 3배씩
-- 오르므로 높일수록 지급액이 커지고 lifetimeBlox 오염 폭도 함께 커진다.
-- 1층과 구분되는 가장 싼 층 중에서 "건너뛴 것이 눈에 보이는" 값으로 골랐다.
local WARP_VERIFY_TARGET_STAGE = 3

if WARP_VERIFY_ENABLED then
	-- ReplicatedStorage / BigNum / CurrencyService는 파일 상단에서 이미 require했다.
	local WarpService = require(script.Parent.Systems.WarpService)
	local WarpConfig = require(ReplicatedStorage.Shared.Config.WarpConfig)
	local ChallengeService = require(script.Parent.Systems.ChallengeService)

	-- ⚠️ VERIFY_CHALLENGE와 같은 {m=, e=} 형태다. BigNum.tostring을 쓰지 않는 이유:
	-- 이 블록의 판정은 "차감분 == 비용"의 **정확한 일치**이고, 어긋났을 때 원인은
	-- 십중팔구 정밀도(유효자리 12)다. tostring은 그 순간 필요한 정보를 지운다.
	local function fmtBigNum(bn): string
		if bn == nil then
			return "nil"
		end
		return string.format("{m=%s, e=%s}", tostring(bn.m), tostring(bn.e))
	end

	local WARP_COST = WarpConfig.cost(WARP_VERIFY_TARGET_STAGE)

	-- 지급액 = 비용 × 2.
	-- ⚠️ 비용과 정확히 같은 액수를 주지 말 것. 그러면 차감 후 잔액이 0이 되는데,
	-- "정확히 비용만큼 뺐다"와 "그냥 0으로 밀었다"가 구분되지 않는다. 2배를 주면
	-- 잔액이 비용만큼 남아 둘이 갈린다.
	-- ⚠️ 큰 값(1e300 등)으로 주지 말 것. 잔액과 비용의 지수 차가 13을 넘으면 sub 결과가
	-- 원래 값과 같아져(CLAUDE.md 정밀도 계약) 차감분이 0으로 찍힌다 —
	-- 검산이 통과가 아니라 무의미해진다. WarpServiceTests에서 실제로 밟았던 함정이다.
	local WARP_VERIFY_GRANT = BigNum.mul(WARP_COST, BigNum.fromNumber(2))

	Players.PlayerAdded:Connect(function(player: Player)
		local profile = ProfileManager.waitFor(player, 10)
		if profile == nil then
			warn(string.format("[Bootstrap][WARP_VERIFY] %s: 프로필 로드 타임아웃 - 검증 중단", player.Name))
			return
		end

		-- ⚠️ task.delay로 띄운다. 같은 PlayerAdded에 걸린 VERIFY_CHALLENGE(즉시)와
		-- REBIRTH_VERIFY(약 5초)가 끝날 시간을 준다. 섞이면 로그를 읽을 수 없고,
		-- 특히 환생은 blox를 0으로 만들므로 그 뒤에 지급이 일어나야 액수가 예측된다.
		-- 여기서 기다리는 것은 이 코루틴뿐이고, 기다림은 warp() **호출 전**에 끝난다 —
		-- 그 함수 안의 무-yield 계약과는 무관하다.
		task.delay(6, function()
			if player.Parent == nil then
				return
			end

			local ok, err = pcall(function()
				-- 1. 워프 조건을 만들어 준다.
				-- ⚠️ **이미 충분하면 지급하지 않는다.** Play를 여러 번 돌리는 동안
				-- PlayerAdded마다 누적 지급되면 lifetimeBlox가 계속 올라 클릭 파워 패드
				-- 해금 상태가 검증할 때마다 달라진다. 어느 쪽으로 갔는지 로그에 남긴다 —
				-- 남기지 않으면 잔액이 왜 그 값인지 나중에 역추적할 수 없다.
				if CurrencyService.canAfford(player, "blox", WARP_COST) then
					print(string.format(
						"[Bootstrap][WARP_VERIFY] %s 지급 건너뜀 - 잔액이 이미 비용 이상 (blox=%s cost=%s)",
						player.Name,
						fmtBigNum(CurrencyService.get(player, "blox")),
						fmtBigNum(WARP_COST)
					))
				else
					CurrencyService.add(player, "blox", WARP_VERIFY_GRANT, "bootstrap_verify_grant")
					print(string.format(
						"[Bootstrap][WARP_VERIFY] %s 지급 실행 - %s (lifetimeBlox도 함께 올랐다)",
						player.Name,
						fmtBigNum(WARP_VERIFY_GRANT)
					))
				end

				-- 2. 워프 전 상태 기록.
				local bloxBefore = CurrencyService.get(player, "blox")
				local runBefore = ChallengeService.getRunState(player)
				print(string.format(
					"[Bootstrap][WARP_VERIFY] %s 워프 전 - blox=%s stage=%s cost(%d)=%s",
					player.Name,
					fmtBigNum(bloxBefore),
					runBefore and tostring(runBefore.stage) or "런 없음",
					WARP_VERIFY_TARGET_STAGE,
					fmtBigNum(WARP_COST)
				))

				-- 3. 워프. ⚠️ ok=false여도 Bootstrap이 죽으면 안 된다 —
				-- 사유 코드가 무엇인지가 이 검증의 결과 중 하나다.
				local warpOk, result = WarpService.warp(player, WARP_VERIFY_TARGET_STAGE, "bootstrap_verify")

				if warpOk then
					print(string.format(
						"[Bootstrap][WARP_VERIFY] %s warp(%d) 성공 - 차감액=%s",
						player.Name,
						WARP_VERIFY_TARGET_STAGE,
						fmtBigNum(result)
					))
				else
					warn(string.format(
						"[Bootstrap][WARP_VERIFY] %s warp(%d) 거부 - 사유=%s",
						player.Name,
						WARP_VERIFY_TARGET_STAGE,
						tostring(result)
					))
				end

				-- 4. 워프 후 blox와 차감분 검산.
				-- VERIFY_CHALLENGE의 "증가분 vs 보상액"을 뒤집은 것이다 (워프는 감소).
				local bloxAfter = CurrencyService.get(player, "blox")
				print(string.format("[Bootstrap][WARP_VERIFY] %s 워프 후 blox=%s", player.Name, fmtBigNum(bloxAfter)))

				if warpOk and bloxBefore ~= nil and bloxAfter ~= nil then
					local delta = BigNum.sub(bloxBefore, bloxAfter)
					local matches = BigNum.eq(delta, WARP_COST)
					print(string.format(
						"[Bootstrap][WARP_VERIFY] %s 차감분=%s vs 비용=%s -> %s",
						player.Name,
						fmtBigNum(delta),
						fmtBigNum(WARP_COST),
						matches and "일치" or "불일치"
					))
				else
					warn(string.format(
						"[Bootstrap][WARP_VERIFY] %s: 워프 실패 또는 값 누락 - 차감분 비교 불가",
						player.Name
					))
				end

				-- 5. 런이 목표 층에 실제로 섰는가.
				-- ⚠️ 이 줄이 이 블록의 핵심이다. 차감만 맞고 런이 안 서면 유저는 블럭스만
				-- 잃는다. 그 상태는 WarpServiceTests가 볼 수 없다 — 거기서는 startRun이
				-- 기록용 함수라 "불렸다"까지만 확인된다.
				local runAfter = ChallengeService.getRunState(player)
				local stageOk = runAfter ~= nil and runAfter.stage == WARP_VERIFY_TARGET_STAGE
				print(string.format(
					"[Bootstrap][WARP_VERIFY] %s 판정: 런이 %d층에 섰는가 -> %s (stage=%s cleared=%s timeLeft=%.1f)",
					player.Name,
					WARP_VERIFY_TARGET_STAGE,
					stageOk and "일치" or "불일치",
					runAfter and tostring(runAfter.stage) or "런 없음",
					runAfter and tostring(runAfter.cleared) or "-",
					runAfter and runAfter.timeLeft or 0
				))
			end)

			if not ok then
				warn(string.format("[Bootstrap][WARP_VERIFY] %s: 검증 중 에러 - %s", player.Name, tostring(err)))
			end
		end)
	end)
end


-- ── 개발용 플래그: STANDARD_PATH_REPORT_ENABLED ───────────────────────────────
-- 표준 경로 시뮬레이터(4-2-f). 클릭률 6/8/10 세 벌의 표를 Play 로그로 찍는다.
-- 목적은 "17층 절벽이 표준 경로를 실제로 막는가"에 답할 숫자를 얻는 것이다.
--
-- ⚠️ 위 REBIRTH_VERIFY_ENABLED · WARP_VERIFY_ENABLED와 **성격이 다르다.
--    셋을 같이 볼 때 같은 물건으로 취급하지 말 것.** 저 둘은 켜면 blox와 lifetimeBlox가
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
	require(script.Parent.Tools.StandardPathReport).run()
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

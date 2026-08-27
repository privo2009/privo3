--!strict
-- 임시 부트스트랩. 정식 서버 진입점으로 대체 예정이며, 그때 이 파일 자체를 들어낸다.
-- ⚠️ 이 파일 전체가 임시 파일이다. 아래 VERIFY_CHALLENGE 블록과 KEEP_RUN_ALIVE 플래그가
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

-- ── 개발용 플래그: KEEP_RUN_ALIVE ─────────────────────────────────────────────
-- 위치: 이 파일(src/server/Bootstrap.server.lua) 상단, 바로 이 줄.
-- 사용처: 아래 VERIFY_CHALLENGE 블록의 맨 끝 한 곳뿐이다(검증이 전부 끝난 뒤).
-- ⚠️ Studio에서 켜고 끄는 값이 아니다. 이 줄을 코드에서 고치고 Rojo sync 해야 반영된다.
--    (ChunkBreakerDemo.client.lua의 DEMO_ENABLED와 같은 패턴)
--
-- 왜 필요한가: VERIFY_CHALLENGE는 startRun → 전 블록 파괴 → cashout을 한 프레임에
-- 끝낸다. 그래서 런이 살아 있는 시간이 0이고, 클라는 세 RunStateChanged를 같은 프레임에
-- 받아 마지막 상태(active=false)로 끝난다. LocalBlocks가 서 있는 순간이 없으니
-- 2인 접속에서 "상대 블록이 안 보이는가"도, timeLeft가 도는지도 눈으로 볼 수 없다.
--
-- true면 검증이 전부 끝난 뒤 startRun을 한 번 더 불러 런을 살려둔다. 검증 지급은
-- 그대로 둔다 — 이미 source="bootstrap_verify"로 실제 플레이 데이터와 구분된다.
-- 살려둔 런은 20초 뒤 ChallengeService의 만료 루프가 걷어가고, 그때 클라에
-- reason=timeout이 찍힌다.
local KEEP_RUN_ALIVE = false

print("[Bootstrap] ProfileManager.init() 호출 시작")
ProfileManager.init()
print("[Bootstrap] ProfileManager.init() 호출 완료")

-- 클릭 파워 패드를 Workspace에 세운다.
-- ⚠️ 순서: 반드시 ProfileManager.init() 뒤여야 한다. PadService.init()이 내부에서
-- ProfileManager.onLoaded로 로드 훅을 거는데, 그 전에 부르면 이미 접속해 있던 플레이어의
-- 로드 통지를 놓쳐서 selectedPadIndex 클램프가 건너뛰어진다.
local PadService = require(script.Parent.Systems.PadService)
PadService.init()

-- 클릭 입력 수신을 연다 (4-2-b).
-- ⚠️ 순서: PadService.init() 뒤여야 한다. 클릭 1회의 힘은 PadService.getClickPower가
-- 정하므로, 패드가 서기 전에 클릭이 들어오면 전부 패드 1 파워로 처리된다.
-- (getClickPower는 상태가 없으면 1로 답한다 — 조용히 틀린 값이 나가는 경로다)
local ClickService = require(script.Parent.Systems.ClickService)
ClickService.init()

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

-- ── 개발용 플래그: REBIRTH_WIRING_ENABLED ────────────────────────────────────────
-- 위치: 이 파일, 바로 이 줄. Studio에서 켜고 끄는 값이 아니다 — 코드에서 고치고
-- Rojo sync 해야 반영된다 (ChunkBreakerDemo의 DEMO_ENABLED와 같은 패턴).
--
-- 4-2-d Prompt 2(RebirthService 본체)와 Prompt 3(이 배선)이 둘 다
-- Play 미검증 상태로 커밋됐다. Play가 실패하면 이 플래그를 false로
-- 바꿔 다시 돌린다 — 그래도 실패하면 원인은 2번 레이어, 통과하면 3번이다.
-- 코드를 읽으며 추측하는 대신 한 줄로 원인을 가르기 위한 것이다.
-- 양쪽 Play 검증이 끝나면 이 플래그는 제거 대상이다 (docs/PENDING.md 잔재).
--
-- ⚠️ 이 플래그는 **런타임 배선만** 가른다. RebirthServiceTests는 별도 Script라
--    Bootstrap을 거치지 않고 RebirthService를 직접 require한다 — 그래서 플래그를
--    꺼도 테스트는 그대로 돈다. 여기가 어긋나면(플래그가 테스트까지 끄면)
--    끄고 다시 돌려도 원인이 안 갈려서 이 플래그의 목적 자체가 사라진다.
local REBIRTH_WIRING_ENABLED = true

if REBIRTH_WIRING_ENABLED then
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
end

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
	print(string.format(
		"[Bootstrap][VERIFY] %s firstJoin=%s lastCollectAt=%s blox={m=%s, e=%s} lifetimeBlox={m=%s, e=%s}",
		player.Name,
		tostring(profile.Data.stats.firstJoin),
		tostring(profile.Data.drones.lastCollectAt),
		tostring(b.m),
		tostring(b.e),
		tostring(lb.m),
		tostring(lb.e)
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

if REBIRTH_WIRING_ENABLED and REBIRTH_VERIFY_ENABLED then
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

if VERIFY_CHALLENGE then
	-- ReplicatedStorage / BigNum / CurrencyService는 파일 상단에서 이미 require했다.
	local ChallengeService = require(script.Parent.Systems.ChallengeService)
	local BlockService = require(script.Parent.Systems.BlockService)

	local function fmtBigNum(bn): string
		if bn == nil then
			return "nil"
		end
		return string.format("{m=%s, e=%s}", tostring(bn.m), tostring(bn.e))
	end

	Players.PlayerAdded:Connect(function(player: Player)
		local profile = ProfileManager.waitFor(player, 10)
		if profile == nil then
			warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 프로필 로드 대기 타임아웃 - 검증 중단", player.Name))
			return
		end

		local ok, err = pcall(function()
			local HUGE_DAMAGE = BigNum.new(1, 999) -- 10^999. 어떤 스테이지 HP보다도 압도적으로 큼

			-- 1. startRun(player, 1)
			local startOk = ChallengeService.startRun(player, 1)
			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s startRun(1) = %s", player.Name, tostring(startOk)))

			-- 2. getSnapshot으로 블록 좌표를 받아 각 좌표에 압도적 데미지로 applyDamage
			local snapshot = BlockService.getSnapshot(player)
			if snapshot == nil then
				warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 블록 스냅샷 없음 - 검증 중단", player.Name))
				return
			end

			for _, block in ipairs(snapshot) do
				ChallengeService.applyDamage(player, block.position, HUGE_DAMAGE)
			end

			local runStateAfterClear = ChallengeService.getRunState(player)
			local cleared = runStateAfterClear ~= nil and runStateAfterClear.cleared
			print(string.format("[Bootstrap][VERIFY_CHALLENGE] %s 클리어 여부: cleared=%s", player.Name, tostring(cleared)))

			if not cleared then
				warn(string.format("[Bootstrap][VERIFY_CHALLENGE] %s: 클리어 실패 - cashout 검증 중단", player.Name))
				return
			end

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

		-- ⚠️ 여기부터가 KEEP_RUN_ALIVE 전용. 위 검증 로직은 한 글자도 건드리지 않는다 —
		-- 검증이 무엇을 통과시켰는지가 바뀌면 안 되므로 뒤에 붙이기만 한다.
		-- 검증 pcall 바깥이라 검증이 중간에 멈췄어도(스냅샷 없음·클리어 실패·에러) 런은
		-- 세운다. 그 상태를 눈으로 보려는 것이 이 플래그의 목적이다.
		-- startRun이 내부에서 BlockService.enterStage를 다시 부르고 seeds까지 실어
		-- 통지하므로, 서버 블록과 클라 LocalBlocks가 둘 다 다시 선다.
		if KEEP_RUN_ALIVE then
			local restartOk = ChallengeService.startRun(player, 1)
			print(string.format(
				"[Bootstrap][KEEP_RUN_ALIVE] %s 검증 후 런 재시작 = %s (20초 뒤 timeout 예정)",
				player.Name,
				tostring(restartOk)
			))
		end
	end)
end

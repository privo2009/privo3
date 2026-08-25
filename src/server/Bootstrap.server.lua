--!strict
-- 임시 부트스트랩. 정식 서버 진입점으로 대체 예정이며, 그때 이 파일 자체를 들어낸다.
-- ⚠️ 이 파일 전체가 임시 파일이다. 아래 VERIFY_CHALLENGE 블록과 개발용 플래그들이
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
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)

-- ── 개발용 플래그: LIFETIME_BLOX_FIXUP ────────────────────────────────────────
-- 위치: 이 파일 상단, 바로 이 줄. Studio에서 켜는 값이 아니다 — 코드를 고치고 Rojo sync
-- 해야 반영된다 (KEEP_RUN_ALIVE와 같은 패턴).
--
-- 왜 있는가: 삭제된 VERIFY_MODE 블록이 CurrencyService를 우회해 blox만 5000으로 대입해서,
-- lifetimeBlox가 32에 머문 프로필이 하나 생겼다. 패드2 조건이 36이라 4 차이로 막혀
-- 패드 기능을 아무것도 확인할 수 없는 상태였다. 이 보정은 그 프로필을 테스트 가능한
-- 지점까지 올린다 — blox 5000 복원이 목적이 아니다.
--
-- 1000을 넣으면 lifetimeBlox = 1032가 되어 패드 5까지 열린다
-- (unlock(5)=972 ≤ 1032 < unlock(6)=2916). 세팅 방식(낮은 패드 밟으면 내려감),
-- 잠김 warn, 로드 시 클램프를 전부 눈으로 확인할 수 있는 범위다.
--
-- ⚠️ 1회성이다. 확인이 끝나면 이 플래그와 fixupLifetimeBlox를 통째로 지운다.
-- 지우기 전까지 매 Play마다 누적되지 않도록 아래 함수가 스스로 조건을 건다.
local LIFETIME_BLOX_FIXUP = true

-- 보정량. 위 주석의 "패드 5까지"가 이 값에 달려 있으므로 같이 읽을 것.
local FIXUP_AMOUNT = { m = 1, e = 3 } -- 1000

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

-- lifetimeBlox 1회성 보정 (LIFETIME_BLOX_FIXUP 참고).
--
-- ⚠️ 반드시 CurrencyService.add를 통과한다. profile.Data.lifetimeBlox를 직접 대입하면
-- 이 보정 자체가 바로 위에서 지운 VERIFY_MODE와 같은 종류의 우회가 된다 —
-- 오염을 만든 방식으로 오염을 고치는 셈이다. add에 blox를 넣으면 lifetimeBlox는
-- CurrencyService가 같은 updates 묶음으로 함께 올린다(CurrencyService.lua:72).
--
-- ⚠️ 누적 방지: 플래그를 켜둔 채 Play를 반복해도 한 번만 먹도록, lifetimeBlox가 아직
-- FIXUP_AMOUNT에 못 미치는 프로필에만 적용한다. 보정 후에는 1032가 되어 다음 Play에서
-- 건너뛴다. 플래그를 끄는 것을 잊어도 1000씩 쌓이지 않는다 — 사람 기억에 맡기지 않는다.
--
-- 기준을 "패드 2 해금 여부(36)"로 잡지 않은 이유: 같은 Play의 VERIFY_CHALLENGE cashout이
-- 32를 먼저 지급하면 32+32=64로 패드 2가 열려버려서, 정작 필요한 이 보정이 건너뛰어진다.
-- 두 PlayerAdded 핸들러의 실행 순서는 보장되지 않으므로 조건이 그 순서에 걸리면 안 된다.
local function fixupLifetimeBlox(player: Player, profile: any)
	local before = BigNum.deserialize(profile.Data.lifetimeBlox)

	if BigNum.gte(before, BigNum.deserialize(FIXUP_AMOUNT)) then
		print(string.format(
			"[Bootstrap][FIXUP] %s 보정 불필요 - lifetimeBlox=%s 가 이미 보정량 이상 (해금 패드 %d개)",
			player.Name,
			BigNum.tostring(before),
			ClickPadConfig.getUnlockedPadCount(1, before)
		))
		return
	end

	local ok, newBlox = CurrencyService.add(player, "blox", BigNum.deserialize(FIXUP_AMOUNT), "dev_lifetime_blox_fixup")
	if not ok then
		warn(string.format("[Bootstrap][FIXUP] %s 보정 실패 - CurrencyService.add가 거부", player.Name))
		return
	end

	local after = BigNum.deserialize(profile.Data.lifetimeBlox)
	print(string.format(
		"[Bootstrap][FIXUP] %s lifetimeBlox %s -> %s (blox=%s, 해금 패드 %d개)",
		player.Name,
		BigNum.tostring(before),
		BigNum.tostring(after),
		BigNum.tostring(newBlox),
		ClickPadConfig.getUnlockedPadCount(1, after)
	))
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

	if LIFETIME_BLOX_FIXUP then
		fixupLifetimeBlox(player, profile)
	end
end)

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

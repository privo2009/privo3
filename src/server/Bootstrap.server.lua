--!strict
-- 임시 부트스트랩. Phase 2-2에서 정식 서버 진입점으로 대체 예정.
-- ⚠️ 이 파일 전체가 임시 파일이다. 아래 VERIFY_MODE 블록은 그중에서도
-- 커맨드 바가 다른 DataModel을 보는 문제를 우회해서 같은 VM 안에서
-- 프로필 로드/저장 왕복을 검증하기 위한 디버그 코드다.
-- Phase 2-2에서 정식 진입점으로 교체할 때 이 파일 자체를 들어낸다.

local Players = game:GetService("Players")

local ProfileManager = require(script.Parent.Data.ProfileManager)

-- 환경변수 대신 코드 상단 플래그로 on/off. false면 VERIFY_MODE 블록은 전혀 실행되지 않는다.
local VERIFY_MODE = false

print("[Bootstrap] ProfileManager.init() 호출 시작")
ProfileManager.init()
print("[Bootstrap] ProfileManager.init() 호출 완료")

-- 읽기 print는 VERIFY_MODE와 무관하게 항상 나온다 (검증 2단계: 저장된 값 확인용).
-- VERIFY_MODE로 막는 건 blox를 직접 대입하는 쓰기 부분뿐이다.
Players.PlayerAdded:Connect(function(player: Player)
	local profile = ProfileManager.waitFor(player, 10)
	if profile == nil then
		warn(string.format("[Bootstrap][VERIFY] %s: waitFor 타임아웃 - 프로필 없음", player.Name))
		return
	end

	local b = profile.Data.blox
	print(string.format(
		"[Bootstrap][VERIFY] %s firstJoin=%s lastCollectAt=%s blox={m=%s, e=%s}",
		player.Name,
		tostring(profile.Data.stats.firstJoin),
		tostring(profile.Data.drones.lastCollectAt),
		tostring(b.m),
		tostring(b.e)
	))

	if VERIFY_MODE then
		-- ⚠️ CLAUDE.md 규칙 2 예외. 저장 왕복 검증 전용 임시 코드.
		-- Phase 2-2에서 CurrencyService 완성 시 이 블록 전체 삭제.
		profile.Data.blox = { m = 5, e = 3 }
		print(string.format("[Bootstrap][VERIFY] %s blox 대입 완료: %s", player.Name, tostring(profile.Data.blox)))
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
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local BigNum = require(ReplicatedStorage.Shared.BigNum)
	local ChallengeService = require(script.Parent.Systems.ChallengeService)
	local BlockService = require(script.Parent.Systems.BlockService)
	local CurrencyService = require(script.Parent.Systems.CurrencyService)

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

			-- 4. cashout(player)
			local cashoutOk, reward = ChallengeService.cashout(player)
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
	end)
end

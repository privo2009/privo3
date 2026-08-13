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

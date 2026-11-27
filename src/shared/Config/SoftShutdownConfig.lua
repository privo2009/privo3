--!strict
-- 소프트 셧다운(업데이트 때 서버 재시작) 값 · 순수 판정(지시서 #48 1부). 흐름 · 이유 → DESIGN.md "15. 운영 > 소프트 셧다운".
--
-- 공식 문서(2026-11-28 확인):
--   - DataModel:BindToClose — 서버가 닫힐 때 부른다. 남은 플레이어가 있으면 그때 옮길 수 있다
--   - DataModel.ServerRestartScheduled(restartTime, source) — 대시보드 "Restart Servers"(지연 1 ~ 60분)를 누르면 먼저 온다.
--     Roblox는 지연이 끝나면 스스로 플레이어를 새 버전 서버로 옮긴다(docs/projects/update-games) — 우리는 그 전에 저장하고 옮긴다
--   - TeleportService:TeleportAsync(placeId, players, TeleportOptions) — 서버 전용 · pcall + 다시 시도(문서 예시 5번 · 1초 · Flooded 15초).
--     성공해도 마지막에 실패할 수 있다 → TeleportInitFailed에서 다시 시도
--   - TeleportOptions.ShouldReserveServer = true → 예약 서버를 새로 만들어 보낸다(대기실). 그 서버는
--     game.PrivateServerId ~= "" 이고 PrivateServerOwnerId == 0(예약 서버)
--   - TeleportOptions:SetTeleportData — 클라에도 보인다(비밀 금지). 도착 쪽은 Player:GetJoinData().TeleportData

local SoftShutdownConfig = {}

-- 대기실(예약 서버)에서 새 버전 서버로 다시 보내기 전 기다리는 시간(초). 옛 서버가 닫히고 새 버전 서버가 매치메이킹에 잡힐 틈.
-- 너무 짧으면 닫히는 옛 서버로 되돌아갈 수 있다(DevForum 사례) · 길면 화면을 오래 본다. Claude 판단 8초(2월 비공개 서버에서 확인)
SoftShutdownConfig.HOLD_SEC = 8

-- 순간이동 다시 시도(공식 문서 예시 값 그대로)
SoftShutdownConfig.TELEPORT_ATTEMPTS = 5
SoftShutdownConfig.RETRY_DELAY_SEC = 1
SoftShutdownConfig.FLOODED_DELAY_SEC = 15

-- 저장을 기다리는 상한(초). BindToClose 예산(약 30초) 안에서 저장 뒤 옮길 몫을 남긴다(ProfileManager의 서버 종료 저장도 같은 값을 쓴다)
SoftShutdownConfig.SAVE_TIMEOUT_SEC = 20

-- BindToClose에서 옮긴 뒤 플레이어가 다 나갈 때까지 붙잡는 상한(초 — 콜백 시작부터). 서버가 먼저 꺼지면 순간이동이 끊긴다
SoftShutdownConfig.CLOSE_HOLD_SEC = 28

-- 재시작 예정(ServerRestartScheduled): Roblox가 스스로 옮기기 이만큼 전에 우리가 저장 → 옮기기를 시작한다(초)
SoftShutdownConfig.RESTART_LEAD_SEC = 20

-- 순간이동 데이터 키(클라에도 보인다 — 값은 true뿐)
SoftShutdownConfig.TELEPORT_DATA_KEY = "privoSoftShutdown"

-- 이 서버가 소프트 셧다운 대기실인가. 이 게임은 예약 서버를 소프트 셧다운에만 쓴다(다른 예약 서버 · 파티 서버 없음 — 새로 쓰면 이 판정을 바꾼다).
-- Studio는 언제나 아니다(공식 문서: Team Test는 PrivateServerId가 비어 있지 않다)
function SoftShutdownConfig.isHoldingServer(isStudio: boolean, privateServerId: string, privateServerOwnerId: number): boolean
	if isStudio then
		return false
	end
	return privateServerId ~= "" and privateServerOwnerId == 0
end

-- 재시작 예정 시각 → 우리가 시작할 때까지 기다릴 초. restartTime이 유닉스 시각이면(> 1e9) 지금과의 차, 아니면 남은 초로 읽는다.
-- 이미 지났거나 앞당김보다 짧으면 0(바로)
function SoftShutdownConfig.delayBeforeEvacuate(restartTime: number?, now: number): number
	if type(restartTime) ~= "number" or restartTime ~= restartTime then
		return 0
	end
	local remaining = if restartTime > 1e9 then restartTime - now else restartTime
	return math.clamp(remaining - SoftShutdownConfig.RESTART_LEAD_SEC, 0, 3600)
end

return SoftShutdownConfig

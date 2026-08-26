--!strict
-- SpeedInput 모듈을 살아 있게 하는 부트 스크립트.
--
-- 왜 따로 있는가: SpeedInput은 Phase 6 UI가 require해야 해서 ModuleScript다. 그런데
-- 모듈은 아무도 require하지 않으면 실행되지 않고, 그러면 SpeedApplied 수신 연결도
-- 걸리지 않는다. UI가 생기기 전까지 그 자리를 이 파일이 대신한다.
-- ⚠️ Phase 6에서 UI가 SpeedInput을 require하게 되면 이 파일의 존재 이유는 아래
--    VERIFY 블록뿐이다. 그때 블록을 끄면 파일째 지워도 된다.

local SpeedInput = require(script.Parent.SpeedInput)

-- 적용 통지 print. Phase 6에서 입력칸 갱신으로 대체될 자리이고, 그때까지는
-- **SpeedApplied가 클라에 도착하는지 확인하는 유일한 지점**이다.
-- (ClickInput의 clickRejected print와 같은 성격이라 상시 유지한다)
SpeedInput.onApplied(function(speed: number, maxSpeed: number)
	print(string.format(
		"[SpeedInput] 서버 적용값 %.1f (최대 %.1f). Phase 6에서 입력칸 갱신으로 대체될 자리",
		speed,
		maxSpeed
	))
end)

-- ── 개발용 플래그: VERIFY_ENABLED ────────────────────────────────────────────────
-- 위치: 이 파일 상단, 바로 이 줄. Studio에서 켜고 끄는 값이 아니다 —
-- 코드에서 고치고 Rojo sync 해야 반영된다 (ChunkBreakerDemo의 DEMO_ENABLED와 같은 패턴).
--
-- 왜 필요한가: 이 단계에는 UI가 없어서(Phase 6) 유저가 속도를 요청할 수단이 아예 없다.
-- 그러면 "요청 → 적용 → 통지" 왕복 전체를 Play에서 한 번도 밟아보지 못한 채 넘어가게
-- 된다. 커맨드 바로 대신하지 말 것 — 커맨드 바는 별도 require 캐시를 써서 이 스크립트가
-- 들고 있는 것과 다른 모듈 인스턴스를 잡는다 (Bootstrap의 같은 경고 참고).
--
-- ⚠️ 임시 블록이다. **Phase 6 UI가 붙으면 이 블록을 삭제한다** (파일째 지워도 된다 —
--    위 onApplied print를 UI가 대신하는 시점이기도 하다). `docs/PENDING.md` 잔재 표에
--    같은 내용이 한 줄로 올라가 있다.
--
-- 2026-08-26 Play에서 왕복(요청 → 적용 → 통지)을 전부 확인해 목적을 다했으므로 false로
-- 껐다. 지우지 않고 남겨 두는 이유: UI가 없는 동안 이 채널이 살아 있는지 확인할 유일한
-- 수단이 이것이다. 4-2-d(RebirthService) 작업 중 채널이 깨져도 지금은 알 방법이 없다 —
-- 배선이 끊겨도 캐릭터는 최대속도로 멀쩡히 걸어다니므로 증상이 나타나지 않는다.
-- 확인이 필요하면 이 줄만 true로 바꾸고 Rojo sync 하면 된다.
local VERIFY_ENABLED = false

-- 요청 사이 간격(초). 서버 상한은 초당 5회이므로 2회 요청은 여유롭게 통과한다 —
-- 이 블록은 상한을 시험하는 것이 아니라 정상 경로를 밟아보는 것이다.
local VERIFY_GAP_SEC = 1.0

if VERIFY_ENABLED then
	task.spawn(function()
		-- 서버의 SpeedRequestService.init()과 프로필 로드가 끝날 시간을 준다.
		-- 여기서 기다리는 것은 이 코루틴뿐이라 위 수신 연결은 이미 살아 있다.
		task.wait(5)

		-- 1) 최대치보다 확실히 낮은 값. 실제로 느려지는 것이 눈에 보여야 한다.
		--    ⚠️ 로블록스 기본값 16과 다른 값을 고른다. 16을 쓰면 "요청이 먹었다"와
		--    "아무 일도 안 일어났다"가 구분되지 않는다.
		print("[SpeedInput][VERIFY] 1/2 - 정상 요청 8을 보낸다 (적용값 8.0이 와야 한다)")
		SpeedInput.request(8)

		task.wait(VERIFY_GAP_SEC)

		-- 2) 최대치를 확실히 넘는 값. 거부가 아니라 min()으로 잘려야 한다.
		--    끝을 이 요청으로 두는 이유: 잘린 결과가 곧 최대치라 캐릭터가 최대속도로
		--    돌아온다. 1)에서 끝내면 세션 내내 8로 다니게 된다.
		print("[SpeedInput][VERIFY] 2/2 - 초과 요청 9999를 보낸다 (거부가 아니라 최대치로 잘려야 한다)")
		SpeedInput.request(9999)

		task.wait(VERIFY_GAP_SEC)

		local applied, maxSpeed = SpeedInput.getLastApplied()
		if applied == nil or maxSpeed == nil then
			warn("[SpeedInput][VERIFY] SpeedApplied가 한 번도 도착하지 않았다 - 채널 배선 확인 필요")
			return
		end

		print(string.format(
			"[SpeedInput][VERIFY] 왕복 확인 - 마지막 적용값 %.1f / 최대치 %.1f -> %s",
			applied,
			maxSpeed,
			if applied == maxSpeed then "초과 요청이 최대치로 잘렸다 (정상)" else "잘림 결과가 최대치와 다르다 (확인 필요)"
		))
	end)
end

print("[SpeedInput] 커스텀 스피드 채널 준비 완료 (UI는 Phase 6)")

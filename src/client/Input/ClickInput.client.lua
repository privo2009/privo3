--!strict
-- 클릭 입력 수집·송신. 마우스와 모바일 터치를 모아 ClickInput 채널로 보낸다.
-- 채널 이름과 payload 형태는 Shared/Remotes.lua에 있다 — 여기 다시 적지 않는다.
--
-- ===== 이 파일이 하지 않는 일 (중요) ==================================================
--
-- ⚠️ 상한 검사를 여기서 하지 말 것. 초당 10회 제한은 서버(ClickService)에만 있다.
--    두 가지 이유다:
--      1. 클라 검사는 우회된다. 익스플로잇 클라는 이 스크립트를 안 돌리고 RemoteEvent를
--         직접 때린다. 여기 검사를 넣어봐야 정직한 클라만 걸린다
--      2. 두 곳에 상한이 있으면 어느 쪽이 잘랐는지 알 수 없게 된다. 서버가 "10회를
--         넘겼다"고 판단하려면 넘긴 입력이 실제로 도착해야 하는데, 클라가 미리 잘라내면
--         서버는 영원히 상한에 닿지 않고 ClickRejected도 뜨지 않는다
--    클라는 모으고 보내기만 한다. 자르는 것은 서버 몫이다.
--
-- ⚠️ 힘 증가량도 계산하지 않는다. payload에 담지 않으므로 알 필요가 없다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- 모아 보내는 주기(초).
--
-- ⚠️ 클릭 1회당 RemoteEvent 1회는 금지다 (CLAUDE.md 금지 사항의 "자동 롤 시 롤 1회당
-- RemoteEvent (배치 처리할 것)"와 같은 이유). 상한이 초당 10회이므로 1클릭 1발화는
-- 30명 서버에서 초당 300발화가 된다.
--
-- 0.2초를 고른 근거 — 두 방향에서 눌린 값이다:
--   위: 주기가 길수록 발화가 줄지만 클릭과 힘 증가 사이의 지연이 그대로 커진다.
--       0.5초면 최악 500ms 뒤에 반영되는데, 클리커 게임에서 이 정도 지연은 입력이
--       씹힌 것처럼 느껴진다
--   아래: 주기가 짧을수록 반응은 좋지만 발화가 늘어난다. 0.1초는 초당 10발화 ×
--       30명 = 300발화로, 애초에 피하려던 1클릭 1발화와 같은 수준이 된다
--   0.2초 = 플레이어당 초당 5발화, 30명이면 150발화. 1클릭 1발화의 절반이고
--   지연은 최악 200ms라 체감되지 않는다.
--
-- 빈 배치는 보내지 않으므로(아래 참고) 안 누르는 동안의 비용은 0이다.
local SEND_PERIOD = 0.2

local channels = Remotes.getClient()

-- 이번 주기에 쌓인 클릭 수. 보낼 때 0으로 비운다.
local pending = 0

-- ===== 입력 수집 =======================================================================
--
-- InputBegan 하나로 마우스와 터치를 함께 받는다. 모바일은 UserInputType.Touch로 들어온다.
--
-- gameProcessedEvent가 참이면 무시한다: 그 입력은 로블록스 UI(버튼·채팅창 등)가 이미
-- 소비한 것이다. 이걸 안 걸러내면 Phase 6에서 화면에 버튼이 생기는 순간 버튼을 누를
-- 때마다 클릭이 같이 들어간다.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		pending = pending + 1
	end
end)

-- ===== 주기 송신 =======================================================================

local elapsed = 0

RunService.Heartbeat:Connect(function(dt: number)
	elapsed = elapsed + dt
	if elapsed < SEND_PERIOD then
		return
	end
	elapsed = 0

	-- 빈 배치는 보내지 않는다. 안 누르고 있는 플레이어가 초당 5발화를 내면
	-- 배치로 줄인 의미가 없다 — 방치형이라 대부분의 시간이 이 상태다.
	if pending <= 0 then
		return
	end

	local payload: Remotes.ClickInputPayload = {
		count = pending,
	}
	pending = 0

	channels.clickInput:FireServer(payload)
end)

-- ===== 상한 통지 수신 ==================================================================
--
-- Phase 6에서 "최대 속도! 자동 클리커로 더 빠르게" 안내가 뜨는 자리다.
-- 지금은 채널이 살아 있는지 확인하는 print만 한다 — HUD는 이 단계의 범위가 아니다.
channels.clickRejected.OnClientEvent:Connect(function(payload: Remotes.ClickRejectedPayload)
	print(string.format(
		"[ClickInput] 상한 도달 - %d회 버려짐 (서버 상한 %d회/초). Phase 6에서 안내 UI로 대체될 자리",
		payload.dropped,
		payload.limitPerSec
	))
end)

print(string.format("[ClickInput] 클릭 수집 시작 (%.1f초마다 배치 송신, 클라 상한 없음)", SEND_PERIOD))

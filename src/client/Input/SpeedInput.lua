--!strict
-- 커스텀 스피드 송신·수신부. SpeedRequest로 보내고 SpeedApplied를 받는다.
-- 채널 이름과 payload 형태는 Shared/Remotes.lua에 있다 — 여기 다시 적지 않는다.
--
-- ⚠️ 이 파일은 ModuleScript다 (.client.lua가 아니다). Phase 6 UI가 require해서
--    request()를 부를 수 있어야 하기 때문이다. LocalScript는 require 대상이 못 된다.
--    살아 있게 하는 것은 같은 폴더의 SpeedInputBoot.client.lua다.
--
-- ===== 이 파일이 하지 않는 일 (중요) ==================================================
--
-- ⚠️ 최대치 검사를 여기서 하지 말 것. 아래 sanitize는 **위생 가드**이지 상한이 아니다.
--    최대치는 힘에서 나오고 힘은 서버 프로필에 있어서 클라가 알 수 있는 값이 아니며,
--    레벨업으로 계속 오른다. 클라가 캐시한 최대치로 미리 자르면:
--      1. 방금 레벨업한 유저가 새 최대치를 못 쓴다 (클라 캐시가 낡았다)
--      2. 서버가 "이 요청은 최대치를 넘었다"고 판단할 기회가 사라진다
--    자르는 것은 서버 몫이다. ClickInput이 초당 10회 제한을 클라에 두지 않은 것과
--    같은 이유이고, 근거도 같다 — 익스플로잇 클라는 이 스크립트를 안 돌리고
--    RemoteEvent를 직접 때리므로 클라 검사는 정직한 클라만 걸린다.
--
-- ⚠️ 그래서 아래 sanitize가 서버 검증을 대체한다고 생각하지 말 것. **서버가 원본이다.**
--    여기서 거르는 것은 "UI 입력칸이 비었거나 글자가 들어간" 명백한 사고뿐이고,
--    서버(SpeedService.sanitizeRequest)는 같은 검사를 어차피 다시 한다.
--    이걸 두는 이유는 검증이 아니라 왕복 절약이다 — 빈 입력칸으로 확정을 눌러도
--    발화가 나가면 그 자체로 초당 5회 상한(SpeedRequestService)을 갉아먹는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SpeedInput = {}

local channels = Remotes.getClient()

-- 서버가 마지막으로 알려준 적용값과 최대치. 아직 한 번도 안 왔으면 nil이다.
-- ⚠️ nil과 0을 구분한다. 0으로 초기화하면 Phase 6 UI가 "속도 0으로 적용됨"으로 읽는다.
local lastApplied: number? = nil
local lastMaxSpeed: number? = nil

local appliedCallbacks: { (number, number) -> () } = {}

-- ===== 송신 ============================================================================

-- 명백한 사고만 거른다. 상한이 아니다 (파일 상단 참고).
local function isSendable(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then -- nan
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return value > 0
end

-- 이 속도로 다니고 싶다고 서버에 요청한다. 보냈으면 true.
--
-- ⚠️ 반환값 true는 "요청을 보냈다"이지 "그 속도가 적용됐다"가 아니다. 실제 적용값은
-- 서버가 정하고 SpeedApplied로 돌아온다 — onApplied()로 받을 것. 이 둘을 혼동해서
-- 반환값으로 UI를 갱신하면, 최대치 18인 유저가 100을 넣었을 때 화면에 100이 남는다.
--
-- 값은 **절대값**이다(studs/s). 비율도 배수도 아니다.
function SpeedInput.request(speed: any): boolean
	if not isSendable(speed) then
		warn(string.format("[SpeedInput] 보낼 수 없는 값이라 요청하지 않는다: %s", tostring(speed)))
		return false
	end

	local payload: Remotes.SpeedRequestPayload = {
		speed = speed,
	}
	channels.speedRequest:FireServer(payload)
	return true
end

-- ===== 수신 ============================================================================

-- 서버가 실제 적용값을 알려올 때 부를 콜백을 건다. (적용값, 최대치)를 받는다.
-- Phase 6 UI가 입력칸을 실제값으로 되돌리는 자리다.
function SpeedInput.onApplied(callback: (number, number) -> ())
	table.insert(appliedCallbacks, callback)
end

-- 서버가 마지막으로 알려준 (적용값, 최대치). 아직 안 왔으면 nil, nil이다.
function SpeedInput.getLastApplied(): (number?, number?)
	return lastApplied, lastMaxSpeed
end

channels.speedApplied.OnClientEvent:Connect(function(payload: Remotes.SpeedAppliedPayload)
	lastApplied = payload.speed
	lastMaxSpeed = payload.maxSpeed

	for _, callback in ipairs(appliedCallbacks) do
		-- 콜백 하나가 에러를 내도 나머지가 죽지 않게 분리한다
		-- (ProfileManager.fireLoaded와 같은 이유).
		task.spawn(callback, payload.speed, payload.maxSpeed)
	end
end)

return SpeedInput

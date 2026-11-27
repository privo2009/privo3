--!strict
-- 서버 전체 알림(ServerNotice — 지시서 #48) → 화면에서 할 일. 순수 함수(테스트 · 화면 둘 다 이것만 본다).
--   updating  소프트 셧다운 "업데이트 중" 화면(차단 · 최상단) — 대기실로 옮겨지는 동안 · 대기실에서
--   restart   재시작 예정 토스트(남은 초)
--   announce  관리자 공지 토스트(서버가 TextService로 거른 글만 온다 — 클라는 그대로 보여 준다)
-- 모양이 틀리면 nil(아무것도 안 한다)

local ServerNoticeLogic = {}

ServerNoticeLogic.MAX_TEXT = 200 -- RemoteGuard 문자열 상한과 같다(서버가 보내는 쪽이지만 클라도 자른다)

export type Action = { kind: "updating" | "restart" | "announce", text: string, sec: number }

function ServerNoticeLogic.decide(payload: any): Action?
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return nil
	end
	if payload.kind == "updating" then
		return { kind = "updating", text = "", sec = 0 }
	elseif payload.kind == "restart" then
		local sec = payload.sec
		if type(sec) ~= "number" or sec ~= sec or sec < 0 or sec > 3600 then
			sec = 0
		end
		return { kind = "restart", text = "", sec = math.floor(sec) }
	elseif payload.kind == "announce" then
		local text = payload.text
		if type(text) ~= "string" or text == "" then
			return nil
		end
		return { kind = "announce", text = string.sub(text, 1, ServerNoticeLogic.MAX_TEXT), sec = 0 }
	end
	return nil
end

-- 대기실(예약 서버)로 도착했나 — 순간이동 데이터에 소프트 셧다운 표시(값 true)가 있으면 바로 "업데이트 중" 화면
function ServerNoticeLogic.arrivedForUpdate(teleportData: any, key: string): boolean
	return type(teleportData) == "table" and teleportData[key] == true
end

return ServerNoticeLogic

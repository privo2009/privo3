--!strict
-- 코드 입력 (지시서 #20 C1 ~ C5 — DESIGN.md 9장 "코드 입력"). 코드 원본은 이 파일 한 곳이다.
--
--   Codes[코드] = { rewards = 보상 목록(RewardLogic 형식 — 일일 보상과 같다), expiresAt = UTC 시각(os.time 초) 또는 nil(무기한) }
--   키는 normalize 꼴(앞뒤 공백 제거 · 대문자)로 적는다 — 비교 전에 입력을 같은 꼴로 바꾼다(대소문자 무시, C1). validate가 잰다
--   코드마다 계정당 1회(C2 — 프로필 redeemedCodes) · 틀린 코드 FAIL_LIMIT번 / FAIL_WINDOW_SEC → LOCK_SEC 동안 막힘(C3 — 세션 메모리)
--   ⚠️ RELEASE는 임시(TEMP, C5). 실제 코드 목록과 알릴 곳은 Phase 9에서 사람이 정한다(docs/PENDING.md)

local RewardLogic = require(script.Parent.Parent.RewardLogic)

export type CodeDef = {
	rewards: { RewardLogic.Reward },
	expiresAt: number?,
}

local CodesConfig = {}

CodesConfig.MAX_LENGTH = 32 -- 이보다 긴 입력은 없는 코드(Schema.LIMITS.MAX_CODE_LENGTH와 같다 — 테스트가 대조한다)
CodesConfig.FAIL_LIMIT = 5 -- C3: 1분에 5번
CodesConfig.FAIL_WINDOW_SEC = 60
CodesConfig.LOCK_SEC = 60 -- C3: 1분 동안
CodesConfig.REQUEST_MIN_INTERVAL_SEC = 0.5 -- 다른 Request 서비스와 같은 꼴

CodesConfig.Codes = {
	-- TEMP(C5): 힘 포션 2 + 데미지 포션 2. 무기한
	RELEASE = {
		rewards = {
			{ type = "potion", kind = "strength", count = 2 },
			{ type = "potion", kind = "damage", count = 2 },
		},
		expiresAt = nil,
	},
} :: { [string]: CodeDef }

-- 입력 → 비교용 꼴. 문자열이 아니거나 · 비었거나 · MAX_LENGTH를 넘으면 nil(없는 코드로 다룬다).
-- 앞뒤 공백(스페이스 · 탭 · 줄바꿈)을 지우고 대문자로 바꾼다. 가운데 공백은 그대로 둔다(그런 코드는 없다 — 없는 코드가 된다).
function CodesConfig.normalize(raw: any): string?
	if type(raw) ~= "string" or #raw > CodesConfig.MAX_LENGTH * 4 then
		return nil
	end
	local trimmed = string.match(raw, "^%s*(.-)%s*$") or ""
	if #trimmed == 0 or #trimmed > CodesConfig.MAX_LENGTH then
		return nil
	end
	return string.upper(trimmed)
end

function CodesConfig.validate(): boolean
	assert(CodesConfig.FAIL_LIMIT >= 1 and CodesConfig.FAIL_WINDOW_SEC > 0 and CodesConfig.LOCK_SEC > 0, "CodesConfig: 막힘 값은 양수")
	assert(CodesConfig.REQUEST_MIN_INTERVAL_SEC > 0, "CodesConfig: REQUEST_MIN_INTERVAL_SEC는 0 초과")
	for code, def in pairs(CodesConfig.Codes) do
		assert(CodesConfig.normalize(code) == code, "CodesConfig: 키 " .. code .. "는 normalize 꼴(대문자 · 공백 없음 · 길이 안)이어야 함")
		assert(RewardLogic.isValidList(def.rewards), "CodesConfig: " .. code .. " 보상 형식이 틀림")
		assert(def.expiresAt == nil or (type(def.expiresAt) == "number" and def.expiresAt > 0), "CodesConfig: " .. code .. " 만료는 UTC 초 또는 nil")
	end
	return true
end

return CodesConfig

--!strict
-- 개발자 전용 관리 도구 값(지시서 #48 4부). 규칙 원본 → DESIGN.md "17. 운영 > 관리 도구" · 입구 검사 → docs/REMOTES.md.
--
-- 누가 쓰나: 게임 주인(사용자 소유면 그 사용자 · 그룹 소유면 그룹 주인 — 서버가 game.CreatorType · CreatorId · GroupService로 읽는다)
--            + 아래 ADMIN_USER_IDS. 판정은 언제나 서버가 한다(클라가 보낸 것은 믿지 않는다). 관리자가 아니면 화면도 만들지 않고
--            리모트에도 답하지 않는다(조용히 버린다 — 있는지조차 알리지 않는다).
-- 무엇을: 재화 · 광석 · 토큰 · 곡괭이 · 펫 지급 · 회수(아이템 복구용) · 서버 공지 · 유저 상태 읽기. 같은 서버에 있는 유저만(오프라인 수정 없음).
-- 관문: 재화는 CurrencyService · 광석 · 토큰 · 곡괭이는 InventoryService · 펫은 PetService — 사유는 언제나 REASON("admin").
--       사용할 때마다 서버 로그 한 줄 + 분석 이벤트(admin_action).

local AdminConfig = {}

-- 지정 관리자 UserId(사람이 정한 값만 넣는다 — 지시서 #48: 모르면 게임 주인만). 지금 비어 있다 → 게임 주인만
AdminConfig.ADMIN_USER_IDS = {} :: { number }

AdminConfig.REASON = "admin"

-- 지급 · 회수 한 번의 상한(실수로 큰 값을 넣지 않게 — 재화는 BigNum으로 바꿔 넣는다. 더 크면 여러 번)
AdminConfig.MAX_CURRENCY = 1e15 -- 블럭스 · 코인(2^53 아래 — 정수가 정확하다)
AdminConfig.MAX_COUNT = 10000 -- 광석 · 토큰 개수
AdminConfig.MAX_ITEMS = 50 -- 곡괭이 · 펫 마리 수(하나씩 반복)

-- 서버 공지 글 길이(글자 — 바이트가 아니라 utf8 글자). RemoteGuard 문자열 상한(200바이트) 안. 공지는 TextService로 거른 뒤에만 보낸다
AdminConfig.ANNOUNCE_MAX_CHARS = 120

-- 행동 · 종류(클라 화면과 서버가 같은 표를 본다)
AdminConfig.ACTIONS = { grant = true, revoke = true, announce = true, inspect = true } :: { [string]: boolean }
AdminConfig.KINDS = { "blox", "coins", "ore", "token", "pickaxe", "pet" } :: { string }

local KIND_SET: { [string]: boolean } = {}
for _, k in ipairs(AdminConfig.KINDS) do
	KIND_SET[k] = true
end

function AdminConfig.isKind(kind: any): boolean
	return type(kind) == "string" and KIND_SET[kind] == true
end

-- 관리자 판정(순수). creatorType = "User" | "Group" · groupOwnerId는 그룹 소유일 때 서버가 읽은 그룹 주인(못 읽었으면 nil)
function AdminConfig.isAdmin(userId: any, creatorType: string, creatorId: number, groupOwnerId: number?, list: { number }?): boolean
	if type(userId) ~= "number" or userId <= 0 then
		return false
	end
	if creatorType == "User" and userId == creatorId then
		return true
	end
	if creatorType == "Group" and groupOwnerId ~= nil and userId == groupOwnerId then
		return true
	end
	for _, id in ipairs(list or AdminConfig.ADMIN_USER_IDS) do
		if id == userId then
			return true
		end
	end
	return false
end

function AdminConfig.validate(): boolean
	for _, id in ipairs(AdminConfig.ADMIN_USER_IDS) do
		assert(type(id) == "number" and id > 0 and id % 1 == 0, "AdminConfig: ADMIN_USER_IDS는 양의 정수 UserId")
	end
	assert(AdminConfig.MAX_CURRENCY <= 2 ^ 53, "AdminConfig: 재화 상한은 2^53 이하")
	return true
end

return AdminConfig

--!strict
-- 고유 이름 키 목록 (지시서 #42 — 이름 번역 규칙 · docs/LOCALIZATION.md "이름 번역 규칙"). **이 목록은 여기 한 곳에만 둔다.**
-- 읽는 곳: tools/check_strings.py(이 파일을 줄 단위로 읽는다 — 한 줄에 꼴 하나 · 꼴은 큰따옴표) · LocaleLangTests.
--
-- 규칙(2026-11-26 희준 결정): UI 제작이 끝날 때까지 고유 이름은 en · ko만 둔다. es · pt · fr · de Lang 파일에는 이름 키가 없고
-- 그 언어에서는 영어 이름이 보인다(키가 없으면 en — Locale.template). 일반 용어 · 문장은 번역을 그대로 둔다.
-- 이름이 든 문장은 자리 표시({name} 등)로 이름을 넣는다 — 문장 안에 이름을 직접 적지 않는다.

local NameKeys = {}

-- true = UI 확정 전(지금). 4개 언어 Lang 파일에 이름 키가 있으면 검사가 실패하고, 없어도 "번역 없음"으로 치지 않는다.
-- 4개 언어 이름을 다시 넣을 때(1월 말 출시 준비 — ROADMAP) false로 바꾸면 검사가 예전처럼 "모든 키에 번역"을 요구한다.
NameKeys.ENGLISH_ONLY = true

-- 이름 키 꼴 "앞*뒤" — 키가 "앞"으로 시작하고 "뒤"로 끝난다(* 하나). 새 이름 종류가 생기면 여기에 한 줄.
NameKeys.PATTERNS = {
	"ore.name.*", -- 광석
	"pickaxe.name.*", -- 곡괭이
	"pet.name.*", -- 펫
	"egg.name.*", -- 알
	"title.name.*", -- 칭호
	"aura.name.*", -- 아우라
	"token.*", -- 토큰(rare · epic · mythic · legendary · next — 이 이름공간에는 이름만 있다)
	"world.name.*", -- 구역(월드)
	"shop.*.name", -- 상품 이름(게임패스 · 개발자 상품 — 운동기구 선해금 Gym {n} Unlock · 공허 훈련 구역 포함)
	"boost.*.name", -- 포션 이름(상품 이름과 같은 낱말 — 일일 보상 · 코드 보상 · 온보딩 보상 줄)
}

local function matches(pattern: string, key: string): boolean
	local star = string.find(pattern, "*", 1, true)
	if star == nil then
		return key == pattern
	end
	local head, tail = string.sub(pattern, 1, star - 1), string.sub(pattern, star + 1)
	return #key >= #head + #tail and string.sub(key, 1, #head) == head and (tail == "" or string.sub(key, -#tail) == tail)
end

-- 고유 이름 키인가.
function NameKeys.isName(key: string): boolean
	for _, pattern in ipairs(NameKeys.PATTERNS) do
		if matches(pattern, key) then
			return true
		end
	end
	return false
end

-- 그 꼴에 맞는가(검사용 — 꼴마다 맞는 키가 하나 이상 있는지 잰다).
NameKeys.matches = matches

return NameKeys

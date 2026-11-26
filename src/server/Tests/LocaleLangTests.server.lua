--!strict
-- 유럽 4개 언어 검사 (지시서 #40 — es · pt(브라질) · fr · de, AI 번역 · 원어민 검수 전). 같은 규칙의 Python 판이 tools/check_strings.py 6번이다.
--   1. 지원 언어 목록 · Lang 파일 목록           2. 언어 판별(Locale ID 앞 두 글자 — es-mx · pt-pt · fr-ca도)
--   3. 언어마다 모든 키에 문장이 있다 · 고아 키 0   4. 언어마다 자리 표시 집합 = en · 줄바꿈 수 = en
--   5. 없거나 빈 번역 → en(지금 규칙 유지)         6. 메뉴 라벨 8자 이하(MenuRailTests의 영어 쪽 규칙 — 그 Play 언어만 재는 것을 표 전체로)
--   7. TEST_LOCALE · Kick 안내문이 새 언어로도 고른다
-- 개수는 언어 · 키 수와 상관없이 같다(언어마다 한 줄씩 — 지시서 #26).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local LANGS = { "es", "pt", "fr", "de" }

local function sameSet(a: { [string]: boolean }, b: { [string]: boolean }): boolean
	for k in pairs(a) do
		if not b[k] then
			return false
		end
	end
	for k in pairs(b) do
		if not a[k] then
			return false
		end
	end
	return true
end

local function countNewlines(s: string): number
	local _, n = string.gsub(s, "\n", "")
	return n
end

-- 1. 목록 ------------------------------------------------------------------------------------------
do
	local all = true
	for _, code in ipairs(LANGS) do
		all = all and Locale.isSupported(code)
	end
	check("지원 언어: en · ko · es · pt · fr · de 여섯", all and #Locale.SUPPORTED == 6 and Locale.isSupported("en") and Locale.isSupported("ko"))
	local same = #Strings.LANG_FILES == #LANGS
	for i, code in ipairs(LANGS) do
		same = same and Strings.LANG_FILES[i] == code
	end
	check("Lang 파일 목록 = es · pt · fr · de", same)
end

-- 2. 언어 판별 -------------------------------------------------------------------------------------
do
	check("es-es · es-mx → es", Locale.fromLocaleId("es-es") == "es" and Locale.fromLocaleId("es-mx") == "es")
	check("pt-br · pt-pt → pt", Locale.fromLocaleId("pt-br") == "pt" and Locale.fromLocaleId("pt-pt") == "pt")
	check("fr-fr · fr-ca → fr", Locale.fromLocaleId("fr-fr") == "fr" and Locale.fromLocaleId("fr-ca") == "fr")
	check("de-de → de", Locale.fromLocaleId("de-de") == "de")
	check("대문자 · 밑줄 · 두 글자만도", Locale.fromLocaleId("DE-DE") == "de" and Locale.fromLocaleId("pt_BR") == "pt" and Locale.fromLocaleId("fr") == "fr")
	check("그 밖은 en(ja-jp · zh-cn · it-it · 앞 두 글자만 같은 esx)", Locale.fromLocaleId("ja-jp") == "en" and Locale.fromLocaleId("zh-cn") == "en"
		and Locale.fromLocaleId("it-it") == "en" and Locale.fromLocaleId("esx") == "en")
end

-- 3 · 4. 언어마다 표 전체 (언어마다 한 줄씩) --------------------------------------------------------
do
	check("고아 키 0(Lang 파일에만 있는 키)", #Strings.Orphans == 0, table.concat(Strings.Orphans, ", "))
	for _, code in ipairs(LANGS) do
		local missing, badPh, badNl = {}, {}, {}
		for key, entry in pairs(Strings.Entries) do
			local text = (entry :: any)[code]
			if type(text) ~= "string" or text == "" then
				table.insert(missing, key)
			elseif type(entry.en) == "string" then
				if not sameSet(Locale.placeholders(text), Locale.placeholders(entry.en)) then
					table.insert(badPh, key)
				end
				if countNewlines(text) ~= countNewlines(entry.en) then
					table.insert(badNl, key)
				end
			end
		end
		table.sort(missing)
		table.sort(badPh)
		table.sort(badNl)
		check(code .. ": 모든 키에 문장이 있다(빈 문자열 없음)", #missing == 0, table.concat(missing, ", "))
		check(code .. ": 자리 표시 집합 = en", #badPh == 0, table.concat(badPh, ", "))
		check(code .. ": 줄바꿈 수 = en", #badNl == 0, table.concat(badNl, ", "))
	end
end

-- 5. 없거나 빈 번역 → en --------------------------------------------------------------------------
do
	local E = Strings.Entries :: any
	E["__test40.only_en"] = { en = "Floor {n}" }
	E["__test40.empty_de"] = { en = "Hello {name}", de = "" }
	E["__test40.has_fr"] = { en = "Pack {pack}", fr = "Pack {pack} FR" }
	check("es 없음 → en", Locale.tFor("es", "__test40.only_en", { n = 2 }) == "Floor 2")
	check("de 빈 문자열 → en", Locale.tFor("de", "__test40.empty_de", { name = "A" }) == "Hello A")
	check("fr 있으면 fr · pt 없으면 en", Locale.tFor("fr", "__test40.has_fr", { pack = 3 }) == "Pack 3 FR"
		and Locale.tFor("pt", "__test40.has_fr", { pack = 3 }) == "Pack 3")
	E["__test40.only_en"] = nil
	E["__test40.empty_de"] = nil
	E["__test40.has_fr"] = nil
	-- 진짜 표: 새 언어 문장은 en과 다른 곳이 있다(번역이 실제로 들어갔다 — 키 하나로 본다)
	local differs = true
	for _, code in ipairs(LANGS) do
		differs = differs and Locale.tFor(code, "hud.menu.settings") ~= Locale.tFor("en", "hud.menu.settings")
	end
	check("진짜 표: 4개 언어 '설정' 메뉴가 영어와 다르다", differs)
end

-- 6. 메뉴 라벨 길이 (MenuRailTests: ko 4자 · 그 밖 8자) ----------------------------------------------
do
	local long = {}
	for key, entry in pairs(Strings.Entries) do
		if string.sub(key, 1, 9) == "hud.menu." then
			for _, code in ipairs(LANGS) do
				local n = utf8.len((entry :: any)[code] or "") or 0
				if n < 2 or n > 8 then
					table.insert(long, code .. ":" .. key)
				end
			end
		end
	end
	table.sort(long)
	check("메뉴 라벨 2 ~ 8자(4개 언어)", #long == 0, table.concat(long, ", "))
end

-- 7. TEST_LOCALE · Kick 안내문 --------------------------------------------------------------------
do
	local code, line = Locale.resolveTest("de", true)
	check("TEST_LOCALE de(Studio) → de · 안내 한 줄", code == "de" and line ~= nil)
	local allKick = true
	for _, c in ipairs(LANGS) do
		allKick = allKick and Locale.tFor(c, "kick.loadFailed") ~= Locale.tFor("en", "kick.loadFailed")
	end
	check("Kick 안내문 4개 언어로 고른다(영어와 다름)", allKick)
end

print(string.format("[LocaleLangTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LocaleLangTests] %d test(s) failed", failed))
end

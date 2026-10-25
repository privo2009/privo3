--!strict
-- 다국어 표 · 고르기 검사 (지시서 #L1 단계 2). 같은 규칙의 Python 판이 tools/check_strings.py다(클라우드 세션은 그쪽을 돌린다).
--   1. 모든 키에 en이 있다                    2. 언어마다 자리 표시 집합 = en
--   3. 없는 키 → "?" + WARN(키는 화면에 안 나간다) 4. ko가 비었거나 없으면 en
--   5. 자리 표시 치환 · 남는 자리 표시 없음      6. 언어 고르기(K2) · TEST_LOCALE 관문
--   7. Config id → 이름 키가 전부 있다(K6)      8. 커밋된 TEST_LOCALE = nil
-- ⚠️ 8번은 TEST_LOCALE을 켠 Play에서 실패한다(TestPresetGateTests와 같은 방식). 그 Play로 테스트 개수를 세지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)
local LocaleGate = require(script.Parent.Parent.Systems.LocaleGate)

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

-- 1 · 2. 표 전체 ----------------------------------------------------------------------------------
do
	local noEn, badPlaceholders, total = {}, {}, 0
	for key, entry in pairs(Strings.Entries) do
		total += 1
		if type(entry.en) ~= "string" or entry.en == "" then
			table.insert(noEn, key)
		else
			local want = Locale.placeholders(entry.en)
			for lang, text in pairs(entry :: any) do
				if lang ~= "en" and type(text) == "string" and text ~= "" and not sameSet(Locale.placeholders(text), want) then
					table.insert(badPlaceholders, key .. "." .. lang)
				end
			end
		end
	end
	table.sort(noEn)
	table.sort(badPlaceholders)
	check("표: 항목이 있다", total > 0, tostring(total))
	check("표: 모든 키에 en이 있다", #noEn == 0, table.concat(noEn, ", "))
	check("표: 언어마다 자리 표시 집합 = en", #badPlaceholders == 0, table.concat(badPlaceholders, ", "))
	local badLang = {}
	for key, entry in pairs(Strings.Entries) do
		for lang in pairs(entry :: any) do
			if not Locale.isSupported(lang) then
				table.insert(badLang, key .. "." .. tostring(lang))
			end
		end
	end
	check("표: 언어 열은 Locale.SUPPORTED 안에서만", #badLang == 0, table.concat(badLang, ", "))
end

-- 3 · 4 · 5. 찾기 · 채우기 (가짜 표 항목을 잠깐 넣고 뺀다) --------------------------------------------
do
	local warns: { string } = {}
	Locale._setWarnSink(function(line: string)
		table.insert(warns, line)
	end)
	local E = Strings.Entries :: any
	E["__test.only_en"] = { en = "Hello {name}" }
	E["__test.empty_ko"] = { en = "Floor {n}", ko = "" }
	E["__test.both"] = { en = "Pack {pack} · {cost} Blox", ko = "팩 {pack} · {cost} 블럭스" }

	local missing = Locale.tFor("ko", "__test.no_such_key")
	check("없는 키: \"?\"로 보인다", missing == Locale.MISSING_TEXT, missing)
	check("없는 키: 키 문자열이 화면에 안 나간다", string.find(missing, "no_such_key", 1, true) == nil)
	check("없는 키: WARN 한 줄", #warns == 1 and string.find(warns[1], "__test.no_such_key", 1, true) ~= nil, tostring(warns[1]))
	Locale.tFor("ko", "__test.no_such_key")
	check("없는 키: WARN은 키마다 한 번", #warns == 1, tostring(#warns))

	check("ko 없음 → en", Locale.tFor("ko", "__test.only_en", { name = "A" }) == "Hello A")
	check("ko 빈 문자열 → en", Locale.tFor("ko", "__test.empty_ko", { n = 3 }) == "Floor 3")
	check("ko 있으면 ko", Locale.tFor("ko", "__test.both", { pack = 2, cost = "1K" }) == "팩 2 · 1K 블럭스")
	check("en", Locale.tFor("en", "__test.both", { pack = 2, cost = "1K" }) == "Pack 2 · 1K Blox")
	check("모르는 언어 → en", Locale.tFor("xx", "__test.both", { pack = 2, cost = "1K" }) == "Pack 2 · 1K Blox")

	local partial = Locale.tFor("en", "__test.both", { pack = 2 })
	check("채우기: 빠진 자리 표시는 \"?\" · 원래 {cost}는 안 남는다", partial == "Pack 2 · ? Blox", partial)
	check("채우기: 빠진 자리 표시 WARN", #warns == 2, tostring(#warns))
	check("채우기: 숫자 값도 문자열로", Locale.format("{a}/{b}", { a = 3, b = 10 }) == "3/10")
	check("채우기: 남는 값은 무시", Locale.format("x{a}", { a = 1, b = 2 }) == "x1")
	check("자리 표시 이름 집합", sameSet(Locale.placeholders("{a} {b_2} {a}"), { a = true, b_2 = true }))

	E["__test.only_en"] = nil
	E["__test.empty_ko"] = nil
	E["__test.both"] = nil
	Locale._setWarnSink(nil)

	-- 표의 진짜 항목 전부: 그 자리 표시를 채우면 en · ko 어디에도 { } 자리 표시가 남지 않는다
	local leftovers = {}
	for key, entry in pairs(Strings.Entries) do
		if type(entry.en) == "string" then
			local params = {}
			for name in pairs(Locale.placeholders(entry.en)) do
				params[name] = "1"
			end
			for _, code in ipairs(Locale.SUPPORTED) do
				local text = Locale.tFor(code, key, params)
				if string.find(text, "{[%w_]+}") ~= nil then
					table.insert(leftovers, key .. "." .. code)
				end
			end
		end
	end
	check("표 전체: 채운 뒤 남는 자리 표시 없음", #leftovers == 0, table.concat(leftovers, ", "))
end

-- 6. 언어 고르기 (K2) · TEST_LOCALE 관문 -------------------------------------------------------------
do
	check("ko-kr → ko", Locale.fromLocaleId("ko-kr") == "ko")
	check("KO → ko", Locale.fromLocaleId("KO") == "ko")
	check("en-us → en", Locale.fromLocaleId("en-us") == "en")
	check("es-es → en (그 밖은 전부 en)", Locale.fromLocaleId("es-es") == "en")
	check("ja-jp → en", Locale.fromLocaleId("ja-jp") == "en")
	check("빈 값 · nil → en", Locale.fromLocaleId("") == "en" and Locale.fromLocaleId(nil) == "en")
	local a, la = Locale.resolveTest(nil, true)
	check("TEST_LOCALE nil → 끔 · 로그 없음", a == nil and la == nil)
	local b, lb = Locale.resolveTest("ko", true)
	check("TEST_LOCALE ko(Studio) → ko · 안내 한 줄", b == "ko" and lb ~= nil)
	local c, lc = Locale.resolveTest("ko", false)
	check("TEST_LOCALE이 Studio 밖에서 무시됨 · ERROR", c == nil and lc ~= nil and string.find(lc :: string, "ERROR", 1, true) ~= nil)
	local d, ld = Locale.resolveTest("fr", true)
	check("모르는 TEST_LOCALE 무시 · ERROR", d == nil and ld ~= nil and string.find(ld :: string, "ERROR", 1, true) ~= nil)
	check("클라우드 Translator 커밋 값 = 꺼짐(Studio 확인 전 — K4)", Locale.CLOUD_TRANSLATOR_ENABLED == false)
end

-- 7. Config id → 이름 키 (K6) -----------------------------------------------------------------------
do
	local missing = {}
	local function need(key: string)
		if not Locale.has(key) then
			table.insert(missing, key)
		end
	end
	for _, pack in pairs(AuraConfig.Packs) do
		for _, def in ipairs(pack.auras) do
			need("aura.name." .. def.id)
		end
	end
	for eggId, egg in pairs(PetConfig.Eggs) do
		need("egg.name." .. tostring(eggId))
		for _, def in ipairs(egg.pets) do
			need("pet.name." .. def.id)
		end
	end
	for level = 1, PetConfig.MAX_LEVEL do
		need("pet.level." .. tostring(level))
	end
	for _, key in ipairs(Names.RARITY_KEYS) do
		need("rarity." .. key)
	end
	for _, def in ipairs(TitleConfig.Titles) do
		need("title.name." .. def.id)
	end
	for key in pairs(ShopConfig.Products) do
		for _, k in ipairs(Names.productKeys(key)) do
			need(k)
		end
	end
	for key in pairs(ShopConfig.BOOSTS) do
		need("boost." .. key .. ".name")
		need("boost." .. key .. ".short")
	end
	for _, name in ipairs(UpgradeConfig.SHOP_ORDER) do
		need("upgrade.name." .. name)
	end
	for worldId in pairs(WorldConfig.Worlds) do
		need("world.name." .. tostring(worldId))
	end
	table.sort(missing)
	check("Config id → 이름 키가 전부 있다(K6)", #missing == 0, table.concat(missing, ", "))
	check("이름 함수: 키가 아니라 문장이 나온다", Names.title("novice") ~= "title.name.novice" and Names.title("novice") ~= Locale.MISSING_TEXT)
	local clash = {}
	for level = 1, PetConfig.MAX_LEVEL do
		for tier = 1, #Names.RARITY_KEYS do
			for _, code in ipairs(Locale.SUPPORTED) do
				if Locale.tFor(code, "pet.level." .. level) == Locale.tFor(code, "rarity." .. Names.RARITY_KEYS[tier]) then
					table.insert(clash, code .. ":" .. level)
				end
			end
		end
	end
	check("펫 강화 단계 이름은 희귀도 이름과 겹치지 않는다(E4 · G10)", #clash == 0, table.concat(clash, ", "))
	check("상품 이름: 힘 배수 계단은 배수를 채운다", string.find(Locale.tFor("en", "shop.strengthTier.name", { mult = 8 }), "8", 1, true) ~= nil)
end

-- 8. 커밋된 TEST_LOCALE = nil (Bootstrap이 LocaleGate.init으로 넘긴 값) -----------------------------------
do
	local deadline = os.clock() + 15
	while not LocaleGate.isRegistered() and os.clock() < deadline do
		task.wait(0.1)
	end
	check("Bootstrap TEST_LOCALE 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)", LocaleGate.isRegistered() and LocaleGate.getRequested() == nil,
		tostring(LocaleGate.getRequested()))
end

print(string.format("[LocaleTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LocaleTests] %d test(s) failed", failed))
end

--!strict
-- 화면 글자 고르기 (지시서 #L1 K1 · K2 · K3). 원본 문자열은 Strings(데이터) 하나다 — 이 파일은 언어를 고르고, 없는 번역을 처리하고,
-- 자리 표시를 채운다. 규칙 원본은 DESIGN.md "12. 언어", 사람용 절차는 docs/LOCALIZATION.md.
--
--   Locale.t(키, 자리 표시)     지금 언어로 한 줄. 화면 코드는 이것만 부른다(화면 문장을 코드에 직접 쓰지 않는다 — CLAUDE.md)
--   Locale.tFor(언어, 키, …)    언어를 지정해서. 서버가 Kick 안내문을 그 플레이어 언어로 고를 때(Server/Systems/LocaleGate)
--
-- ===== 언어 고르기 (K2) ===========================================================================
--
-- 계정 언어(Player.LocaleId — 게임 콘텐츠 현지화에 쓰는 값, 공식 문서 Player.LocaleId)가 "ko"로 시작하면 ko, 그 밖은 전부 en.
-- Studio 확인용 TEST_LOCALE은 서버 Bootstrap 한 곳에 있다(커밋 값 nil — LocaleTests가 잰다). 서버 LocaleGate가 Studio에서만
-- ReplicatedStorage 속성(TEST_LOCALE_ATTRIBUTE)으로 내려 주고, 클라는 처음 t를 부를 때 한 번 읽는다.
-- 세션 중에 언어가 바뀌지 않는다(언어 선택 설정 항목 없음 — K2). 그래서 모듈 맨 위에서 t를 불러 상수로 둬도 된다.
--
-- ===== 없는 번역 (K3) =============================================================================
--
--   그 언어 문장이 있으면 그것 → 비었거나 없으면 en → en도 없으면 "?" + WARN(키마다 한 번)
--   키 문자열 자체는 화면에 내보내지 않는다. 자리 표시가 안 채워지면 그 자리를 "?"로 바꾸고 WARN한다.
--
-- ===== 클라우드 현지화 표 (K4 — 지금은 꺼져 있다) ===================================================
--
-- CLOUD_TRANSLATOR_ENABLED를 켜면 en · ko가 아닌 언어 플레이어에게 LocalizationService:GetTranslatorForPlayerAsync의
-- Translator:FormatByKey(키, 자리 표시)를 먼저 해 본다. 실패 · 없음이면 en. 켜는 조건은 docs/LOCALIZATION.md "5. 런타임 연결".
-- ⚠️ Studio에서 확인하기 전에는 켜지 않는다(지시서 #L1).

local Strings = require(script.Parent.Strings)

local Locale = {}

export type LocaleCode = string -- "en" | "ko" (SUPPORTED)

Locale.DEFAULT = "en"
Locale.SUPPORTED = { "en", "ko" }
Locale.MISSING_TEXT = "?"
Locale.TEST_LOCALE_ATTRIBUTE = "TestLocale"
Locale.CLOUD_TRANSLATOR_ENABLED = false

local supportedSet: { [string]: boolean } = {}
for _, code in ipairs(Locale.SUPPORTED) do
	supportedSet[code] = true
end

function Locale.isSupported(code: any): boolean
	return type(code) == "string" and supportedSet[code] == true
end

-- 계정 언어 ID("ko-kr" · "en-us" · "es-es" …) → 게임 언어. 한국어만 ko, 그 밖은 전부 en(K2).
function Locale.fromLocaleId(localeId: any): LocaleCode
	if type(localeId) == "string" and string.lower(string.sub(localeId, 1, 2)) == "ko" then
		return "ko"
	end
	return Locale.DEFAULT
end

-- TEST_LOCALE을 받아도 되는가. 돌려주는 값: (쓸 언어 또는 nil, 로그 한 줄 또는 nil). TestPresetGate.resolve와 같은 꼴.
function Locale.resolveTest(test: any, isStudio: boolean): (LocaleCode?, string?)
	if test == nil then
		return nil, nil
	end
	if not isStudio then
		return nil, string.format("[Locale] ERROR Studio가 아닌데 TEST_LOCALE(%s)이 켜져 있다 — 무시한다. Bootstrap의 TEST_LOCALE을 nil로 되돌릴 것", tostring(test))
	end
	if not Locale.isSupported(test) then
		return nil, string.format("[Locale] ERROR 알 수 없는 TEST_LOCALE %s — 무시한다(목록: %s)", tostring(test), table.concat(Locale.SUPPORTED, ", "))
	end
	return test, string.format("[Locale] ⚠️ TEST_LOCALE = %s (Studio 전용) — 계정 언어 대신 이 언어로 보인다", test)
end

-- ===== WARN 통로 (테스트가 바꿔 끼운다) ============================================================

local warnSink: (string) -> () = function(line: string)
	warn(line)
end
local warnedKeys: { [string]: boolean } = {}

local function warnOnce(id: string, line: string)
	if warnedKeys[id] then
		return
	end
	warnedKeys[id] = true
	warnSink(line)
end

-- 테스트 전용. WARN을 모으는 함수로 바꾸고, 이미 한 번 찍은 키 기록을 비운다. nil이면 기본(warn)으로 되돌린다.
function Locale._setWarnSink(sink: ((string) -> ())?)
	warnSink = sink or function(line: string)
		warn(line)
	end
	table.clear(warnedKeys)
end

-- ===== 찾기 · 채우기 ==============================================================================

local function nonEmpty(v: any): string?
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

-- 원문 하나(자리 표시 채우기 전). 없으면 nil(그때는 "?"로 보인다).
function Locale.template(code: LocaleCode, key: string): string?
	local entry = (Strings.Entries :: any)[key]
	if type(entry) ~= "table" then
		return nil
	end
	return nonEmpty(entry[code]) or nonEmpty(entry[Locale.DEFAULT])
end

-- 원문의 자리 표시 이름 집합. 검사(LocaleTests · tools/check_strings.py)와 채우기가 같은 규칙을 쓴다: {영문자 · 숫자 · _}.
function Locale.placeholders(template: string): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for name in string.gmatch(template, "{([%w_]+)}") do
		set[name] = true
	end
	return set
end

-- {name}을 params.name으로 바꾼다. 값은 tostring. 없는 자리 표시는 "?"로 바꾸고 WARN.
function Locale.format(template: string, params: { [string]: any }?, keyForWarn: string?): string
	return (string.gsub(template, "{([%w_]+)}", function(name: string): string
		local v = if params ~= nil then params[name] else nil
		if v == nil then
			warnOnce((keyForWarn or template) .. "{" .. name .. "}",
				string.format("[Locale] WARN 자리 표시 {%s}가 채워지지 않았다 (키 %s)", name, tostring(keyForWarn)))
			return Locale.MISSING_TEXT
		end
		return tostring(v)
	end))
end

-- ===== 클라우드 Translator (꺼져 있다 — CLOUD_TRANSLATOR_ENABLED) ==================================

local cloudTranslator: any = nil

local function cloudText(key: string, params: { [string]: any }?): string?
	if cloudTranslator == nil then
		return nil
	end
	local ok, text = pcall(function()
		return cloudTranslator:FormatByKey(key, params or {})
	end)
	if ok and type(text) == "string" and text ~= "" then
		return text
	end
	return nil
end

local function startCloudTranslator(player: any, localeId: any)
	if not Locale.CLOUD_TRANSLATOR_ENABLED or player == nil then
		return
	end
	if type(localeId) ~= "string" or Locale.isSupported(string.lower(string.sub(localeId, 1, 2))) then
		return -- en · ko는 Strings가 직접 낸다
	end
	task.spawn(function()
		local ok, translator = pcall(function()
			return game:GetService("LocalizationService"):GetTranslatorForPlayerAsync(player)
		end)
		if ok then
			cloudTranslator = translator
		else
			warnSink("[Locale] WARN 클라우드 Translator를 받지 못했다 — 영어로 보인다: " .. tostring(translator))
		end
	end)
end

-- ===== 지금 언어 ==================================================================================

local current: LocaleCode? = nil

-- 클라: 계정 언어 + (Studio면) 서버가 내려 준 TEST_LOCALE. 서버: en(서버는 Locale.t를 쓰지 않는다 — tFor로 언어를 지정한다).
local function resolveCurrent(): LocaleCode
	local RunService = game:GetService("RunService")
	if not RunService:IsClient() then
		return Locale.DEFAULT
	end
	local player = game:GetService("Players").LocalPlayer
	local localeId = if player ~= nil then player.LocaleId else nil
	local test = game:GetService("ReplicatedStorage"):GetAttribute(Locale.TEST_LOCALE_ATTRIBUTE)
	local chosen = Locale.resolveTest(test, RunService:IsStudio())
	if chosen ~= nil then
		return chosen
	end
	startCloudTranslator(player, localeId)
	return Locale.fromLocaleId(localeId)
end

function Locale.current(): LocaleCode
	if current == nil then
		current = resolveCurrent()
	end
	return current :: LocaleCode
end

-- 테스트 전용. 지금 언어를 정한다(nil이면 다음 current()에서 다시 고른다).
function Locale._setCurrent(code: LocaleCode?)
	current = code
end

-- ===== 부르는 곳 ==================================================================================

function Locale.tFor(code: LocaleCode, key: string, params: { [string]: any }?): string
	local template = Locale.template(code, key)
	if template == nil then
		warnOnce(key, string.format("[Locale] WARN 키 %s에 문장이 없다(%s · en 둘 다) — \"%s\"로 보인다", key, code, Locale.MISSING_TEXT))
		return Locale.MISSING_TEXT
	end
	return Locale.format(template, params, key)
end

function Locale.t(key: string, params: { [string]: any }?): string
	local code = Locale.current()
	if cloudTranslator ~= nil and code == Locale.DEFAULT then
		local text = cloudText(key, params)
		if text ~= nil then
			return text
		end
	end
	return Locale.tFor(code, key, params)
end

-- 키가 표에 있는가(영어 기준). 동적 키(이름 · 사유 코드)를 고를 때 "없으면 다른 키" 판단에 쓴다.
function Locale.has(key: string): boolean
	return Locale.template(Locale.DEFAULT, key) ~= nil
end

return Locale

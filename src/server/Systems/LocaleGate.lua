--!strict
-- 서버 쪽 언어 관문 (지시서 #L1 K2 · K5). 둘만 한다:
--   1. Bootstrap의 TEST_LOCALE(Studio 전용)을 받아 클라에 내려 준다 — ReplicatedStorage 속성(Locale.TEST_LOCALE_ATTRIBUTE)
--   2. 서버가 플레이어에게 직접 글자를 보여야 하는 단 하나의 자리(Player:Kick 안내문)에서 그 플레이어 언어를 고른다
-- 그 밖에 서버는 화면 문장을 보내지 않는다(K5 — 사유 코드 · 키 · 숫자만). 서버 로그는 번역하지 않는다.
--
-- ⚠️ 커밋되는 TEST_LOCALE(Bootstrap)은 언제나 nil이다 — register로 받은 값을 LocaleTests가 읽어 nil인지 본다
--    (켠 Play에서는 그 줄이 실패한다 — 그 Play로 테스트 개수를 세지 않는다. TestPresetGate와 같은 방식)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local LocaleGate = {}

local requested: any = nil
local registered = false
local active: string? = nil

function LocaleGate.init(testLocale: any)
	requested = testLocale
	registered = true
	local chosen, line = Locale.resolveTest(testLocale, RunService:IsStudio())
	active = chosen
	if line ~= nil then
		if chosen == nil then
			warn(line)
		else
			print(line)
		end
	end
	ReplicatedStorage:SetAttribute(Locale.TEST_LOCALE_ATTRIBUTE, chosen)
	-- K11(#L2): 언어 신호를 정했다 — 클라는 Studio에서 이것을 기다린 뒤 첫 글자를 고른다(TEST_LOCALE이 nil이어도 세운다)
	ReplicatedStorage:SetAttribute(Locale.READY_ATTRIBUTE, true)
end

function LocaleGate.isRegistered(): boolean
	return registered
end

function LocaleGate.getRequested(): any
	return requested
end

-- 그 플레이어에게 보일 언어. Studio TEST_LOCALE이 켜져 있으면 그것, 아니면 계정 언어(K2).
function LocaleGate.localeFor(player: Player): Locale.LocaleCode
	if active ~= nil then
		return active
	end
	return Locale.fromLocaleId(player.LocaleId)
end

-- Kick 안내문 — 그 플레이어 언어로 Strings에서 고른다.
function LocaleGate.kickText(player: Player, key: string): string
	return Locale.tFor(LocaleGate.localeFor(player), key)
end

return LocaleGate

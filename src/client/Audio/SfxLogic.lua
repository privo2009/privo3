--!strict
-- 효과음 순수 판정 (지시서 #25 S1 · S2 — docs/UI.md "효과음"). 실물 재생은 Audio/Sfx, 키 · 볼륨은 Shared/Config/SoundConfig.
--
--   decide(def, enabled, lastAt, now)   재생할까: "muted"(효과음 끔) · "throttled"(같은 키 SFX_MIN_INTERVAL 안) · "noId"(id 없음) · "play"
--   rollKey(tier)                       표시 단계(UiTheme.Rarity 1 ~ 6) → rollCommon(1 ~ 2) · rollRare(3 ~ 4) · rollLegend(5 ~ 6)
--   for*(payload)                       이미 클라가 받는 결과 · 상태 변화 → 키(nil = 소리 없음). 서버는 소리용 채널을 만들지 않는다

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
-- 희귀도 표(칭호 · 아우라 · 펫)는 처음 쓸 때 부른다 — 버튼 반응(ButtonFx)이 HUD를 만들 때 이 모듈을 불러오므로, 창 로직 모듈까지
-- 시작 때 다 불러오면 HUD가 늦게 떠 첫 PlayerState와의 순서가 바뀐다(2026-11-12 #25 단계 3 — HudLayoutTests 개수가 흔들렸다)
local function titleConfig(): any
	return require(ReplicatedStorage.Shared.Config.TitleConfig) :: any
end
local function auraLogic(): any
	return require(script.Parent.Parent.UI.Logic.AuraWindowLogic) :: any
end
local function petLogic(): any
	return require(script.Parent.Parent.UI.Logic.PetWindowLogic) :: any
end

local SfxLogic = {}

export type Outcome = "play" | "noId" | "muted" | "throttled" | "unknown"

function SfxLogic.decide(def: SoundConfig.SoundDef?, enabled: boolean, lastAt: number?, now: number): Outcome
	if def == nil then
		return "unknown"
	end
	if not enabled then
		return "muted"
	end
	if lastAt ~= nil and now - lastAt < UIFxConfig.SFX_MIN_INTERVAL then
		return "throttled"
	end
	if def.id == nil then
		return "noId"
	end
	return "play"
end

-- 비어 있는 소리 수(시작 때 한 줄)
function SfxLogic.emptyCount(sounds: { [string]: SoundConfig.SoundDef }): number
	local n = 0
	for _, def in pairs(sounds) do
		if def.id == nil then
			n += 1
		end
	end
	return n
end

function SfxLogic.rollKey(tier: number?): string
	local t = if type(tier) == "number" then tier else 1
	if t >= 5 then
		return "rollLegend"
	elseif t >= 3 then
		return "rollRare"
	end
	return "rollCommon"
end

-- 런 상태: 수령 · 진행 · 실패(시간 초과 — 실패 안내가 뜨는 때. 포기 · 죽음은 소리 없음)
function SfxLogic.forRunState(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if payload.reason == "cashout" then
		return "cashout"
	elseif payload.reason == "advance" then
		return "advance"
	elseif payload.reason == "timeout" then
		return "fail"
	end
	return nil
end

-- 칭호: 직접 롤 성공은 언제나 · 자동 롤은 새 칭호일 때만(자동은 잦다 — 토스트와 같은 조건)
function SfxLogic.forTitle(payload: any): string?
	if type(payload) ~= "table" or payload.ok ~= true then
		return nil
	end
	if payload.action == "roll" or (payload.action == "autoRoll" and payload.isNew == true) then
		local _, index = titleConfig().get(payload.titleId)
		return SfxLogic.rollKey(index)
	end
	return nil
end

function SfxLogic.forAura(payload: any): string?
	if type(payload) ~= "table" or payload.ok ~= true or (payload.action ~= "roll" and payload.action ~= "rollCredit") then
		return nil
	end
	return SfxLogic.rollKey(auraLogic().rarityTier(tonumber(payload.tier) or 1))
end

-- 펫 부화: 한 마리는 그 펫 · 3배 부화는 셋 중 가장 귀한 것
function SfxLogic.forPet(payload: any): string?
	if type(payload) ~= "table" or payload.ok ~= true or (payload.action ~= "hatch" and payload.action ~= "hatch3") then
		return nil
	end
	local best = tonumber(payload.rarity) or 1
	if type(payload.pets) == "table" then
		for _, p in ipairs(payload.pets) do
			if type(p) == "table" and type(p.rarity) == "number" and p.rarity > best then
				best = p.rarity
			end
		end
	end
	return SfxLogic.rollKey(petLogic().rarityTier(best))
end

function SfxLogic.forRebirth(payload: any): string?
	return if type(payload) == "table" and payload.ok == true then "rebirth" else nil
end

-- 로벅스 구매: 프롬프트가 끝났고(phase finished) 산 경우만
function SfxLogic.forPurchase(payload: any): string?
	return if type(payload) == "table" and payload.phase == "finished" and payload.ok == true then "purchase" else nil
end

function SfxLogic.forDaily(payload: any): string?
	return if type(payload) == "table" and payload.ok == true then "dailyClaim" else nil
end

return SfxLogic

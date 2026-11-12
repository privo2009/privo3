--!strict
-- 효과음 검증 (지시서 #25 S1 ~ S3 — docs/UI.md "효과음"). 키 · 볼륨은 Shared/Config/SoundConfig, 스로틀은 UIFxConfig에서 읽는다.
--   설정: 키 12개 · validate · 커밋 값 id 전부 nil(소리는 사람이 고른다 — S4)
--   판정: id nil이면 재생 안 함 · 효과음 끔이면 재생 안 함 · 같은 키 SFX_MIN_INTERVAL 스로틀 · 다른 키는 따로 · 모르는 키
--   매핑: 희귀도 → 키(칭호 · 아우라 · 펫 같은 규칙) · 런 상태 · 환생 · 구매 · 일일 보상
--   실물: 재생 시도 기록(Attribute) · 효과음 끔이면 시도 0 · 풀(키마다 POOL_PER_KEY장 · 돌려 쓴다)
-- 실제 소리를 내지 않는다(id가 없다 — 풀 검사는 가짜 정의로 Sound를 만들기만 하고 재생하지 않는다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local Audio = script.Parent.Parent.Audio
local SfxLogic = require(Audio.SfxLogic)
local Sfx = require(Audio.Sfx)
local FxPrefs = require(script.Parent.Parent.UI.FxPrefs)

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

local savedReduce, savedSfx = FxPrefs.reduceMotion(), FxPrefs.sfxEnabled()

-- 1. 설정 --------------------------------------------------------------------------------------------------
do
	local empty = 0
	for _, key in ipairs(SoundConfig.KEYS) do
		if SoundConfig.Sounds[key] ~= nil and SoundConfig.Sounds[key].id == nil then
			empty += 1
		end
	end
	check("SoundConfig: validate · 키 12개 · 지시서 목록 그대로", SoundConfig.validate() and #SoundConfig.KEYS == 12
		and table.concat(SoundConfig.KEYS, ",") == "button,click,cashout,advance,fail,rollCommon,rollRare,rollLegend,levelUp,rebirth,purchase,dailyClaim")
	check("SoundConfig: 커밋 값은 id 전부 nil(사람이 고른다 — S4) · 비어 있는 소리 12개", empty == 12 and SfxLogic.emptyCount(SoundConfig.Sounds) == 12)
	check("스로틀 간격 = UIFxConfig.SFX_MIN_INTERVAL(0.05 시작값)", UIFxConfig.SFX_MIN_INTERVAL > 0)
end

-- 2. 판정 ---------------------------------------------------------------------------------------------------
do
	local withId: SoundConfig.SoundDef = { id = 123, volume = 0.5 }
	local noId: SoundConfig.SoundDef = { volume = 0.5 }
	local I = UIFxConfig.SFX_MIN_INTERVAL
	check("판정: id nil이면 재생 안 함(noId — 오류 없음)", SfxLogic.decide(noId, true, nil, 0) == "noId")
	check("판정: 효과음 끔이면 재생 안 함(muted — id가 있어도)", SfxLogic.decide(withId, false, nil, 0) == "muted")
	check("판정: 같은 키 간격 안이면 throttled · 간격이 지나면 play", SfxLogic.decide(withId, true, 1, 1 + I * 0.5) == "throttled"
		and SfxLogic.decide(withId, true, 1, 1 + I) == "play")
	check("판정: 모르는 키는 unknown", SfxLogic.decide(nil, true, nil, 0) == "unknown")
end

-- 3. 매핑 --------------------------------------------------------------------------------------------------
do
	check("희귀도 → 키: 1 ~ 2 common · 3 ~ 4 rare(레어 · 영웅) · 5 ~ 6 legend(전설 · 신화 · 리미티드)", SfxLogic.rollKey(1) == "rollCommon"
		and SfxLogic.rollKey(2) == "rollCommon" and SfxLogic.rollKey(3) == "rollRare" and SfxLogic.rollKey(4) == "rollRare"
		and SfxLogic.rollKey(5) == "rollLegend" and SfxLogic.rollKey(6) == "rollLegend" and SfxLogic.rollKey(nil) == "rollCommon")
	check("아우라: common → common · rare · epic → rare · legendary → legend · 거부는 없음", SfxLogic.forAura({ action = "roll", ok = true, tier = 1 }) == "rollCommon"
		and SfxLogic.forAura({ action = "roll", ok = true, tier = 2 }) == "rollRare" and SfxLogic.forAura({ action = "rollCredit", ok = true, tier = 3 }) == "rollRare"
		and SfxLogic.forAura({ action = "roll", ok = true, tier = 4 }) == "rollLegend" and SfxLogic.forAura({ action = "roll", ok = false, tier = 4 }) == nil
		and SfxLogic.forAura({ action = "equip", ok = true, tier = 4 }) == nil)
	check("펫: 영웅 → rare · 전설 → legend · 리미티드 → legend · 3배 부화는 가장 귀한 것 · 크래프팅은 없음",
		SfxLogic.forPet({ action = "hatch", ok = true, rarity = 3 }) == "rollRare" and SfxLogic.forPet({ action = "hatch", ok = true, rarity = 4 }) == "rollLegend"
			and SfxLogic.forPet({ action = "hatch", ok = true, rarity = 5 }) == "rollLegend"
			and SfxLogic.forPet({ action = "hatch3", ok = true, rarity = 1, pets = { { rarity = 1 }, { rarity = 4 }, { rarity = 2 } } }) == "rollLegend"
			and SfxLogic.forPet({ action = "craft", ok = true, rarity = 4 }) == nil)
	local T = TitleConfig.Titles
	check("칭호: 단계 = 표시 단계(breaker rare · legend legend) · 자동 롤은 새 칭호만 · 장착은 없음",
		SfxLogic.forTitle({ action = "roll", ok = true, titleId = T[1].id }) == "rollCommon" and SfxLogic.forTitle({ action = "roll", ok = true, titleId = T[3].id }) == "rollRare"
			and SfxLogic.forTitle({ action = "roll", ok = true, titleId = T[5].id }) == "rollLegend"
			and SfxLogic.forTitle({ action = "autoRoll", ok = true, titleId = T[5].id, isNew = false }) == nil
			and SfxLogic.forTitle({ action = "autoRoll", ok = true, titleId = T[6].id, isNew = true }) == "rollLegend"
			and SfxLogic.forTitle({ action = "equip", ok = true, titleId = T[2].id }) == nil)
	check("런 상태: cashout · advance · timeout(fail) · 그 밖은 없음", SfxLogic.forRunState({ reason = "cashout" }) == "cashout"
		and SfxLogic.forRunState({ reason = "advance" }) == "advance" and SfxLogic.forRunState({ reason = "timeout" }) == "fail"
		and SfxLogic.forRunState({ reason = "start" }) == nil and SfxLogic.forRunState({ reason = "abandon" }) == nil)
	check("환생 · 구매(끝남 + 성공만) · 일일 보상(성공만)", SfxLogic.forRebirth({ ok = true }) == "rebirth" and SfxLogic.forRebirth({ ok = false }) == nil
		and SfxLogic.forPurchase({ phase = "finished", ok = true }) == "purchase" and SfxLogic.forPurchase({ phase = "prompt", ok = true }) == nil
		and SfxLogic.forPurchase({ phase = "finished", ok = false }) == nil and SfxLogic.forDaily({ ok = true }) == "dailyClaim"
		and SfxLogic.forDaily({ ok = false }) == nil)
end

-- 4. 실물 — 시도 기록 · 효과음 끔 · 스로틀 · 풀 --------------------------------------------------------------------------
do
	local t = 5000
	Sfx._debug.setClock(function()
		return t
	end)
	Sfx._debug.resetThrottle()
	local folder = Sfx._debug.folder()
	local function attempts(key: string): number
		local n = folder:GetAttribute(key)
		return if type(n) == "number" then n else 0
	end
	FxPrefs.set(savedReduce, true)
	local before = attempts("rebirth")
	local outcome = Sfx.play("rebirth")
	check("실물: id nil → 재생 안 함(noId) · 시도 기록 +1 · Sound를 만들지 않는다", outcome == "noId" and attempts("rebirth") == before + 1
		and Sfx._debug.poolOf("rebirth") == nil)
	t += UIFxConfig.SFX_MIN_INTERVAL * 0.5
	check("실물: 같은 키 간격 안 → throttled · 기록 그대로", Sfx.play("rebirth") == "throttled" and attempts("rebirth") == before + 1)
	check("실물: 다른 키는 따로 센다", Sfx.play("purchase") == "noId")
	t += UIFxConfig.SFX_MIN_INTERVAL
	FxPrefs.set(savedReduce, false)
	local mutedBefore = attempts("muted_rebirth")
	local tries = attempts("rebirth")
	check("실물: 효과음 끔 → muted · 시도 기록 0(늘지 않음) · 막은 수만 센다", Sfx.play("rebirth") == "muted" and attempts("rebirth") == tries
		and attempts("muted_rebirth") == mutedBefore + 1)
	FxPrefs.set(savedReduce, true)
	check("실물: 모르는 키 → unknown(오류 없음)", Sfx.play("nope") == "unknown")
	local outside = Instance.new("Folder") -- DataModel 밖(없는 에셋 1을 불러오려 하지 않게)
	local pool = Sfx._debug.poolFor("__test_pool", { id = 1, volume = 0.25 }, outside)
	local again = Sfx._debug.poolFor("__test_pool", { id = 1, volume = 0.25 }, outside)
	check("풀: 키마다 POOL_PER_KEY장 · 다시 불러도 새로 만들지 않는다 · id · volume", #pool.sounds == SoundConfig.POOL_PER_KEY and pool == again
		and #outside:GetChildren() == SoundConfig.POOL_PER_KEY and pool.sounds[1].SoundId == "rbxassetid://1" and pool.sounds[1].Volume == 0.25)
	outside:Destroy()
	Sfx._debug.setClock(nil)
	Sfx._debug.resetThrottle()
end

FxPrefs.set(savedReduce, savedSfx)

print(string.format("[SfxTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[SfxTests] %d test(s) failed", failed))
end

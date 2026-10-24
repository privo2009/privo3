--!strict
-- Studio 전용 테스트 프리셋의 관문 (지시서 #13 3단계). 프리셋 값은 Shared/Config/TestPresets(데이터만)가 원본이고,
-- 이 파일은 (1) 켜도 되는가 (2) 어느 저장소로 세션을 여는가 (3) 프리셋을 프로필 데이터로 만드는가 셋만 한다.
--
-- ===== 안전장치 (전부 TestPresetGateTests가 잰다) =====================================
--
--   1. Studio에서만. RunService:IsStudio()가 아니면 프리셋을 무시하고 ERROR 로그를 남긴다 — 실제 저장소로 정상 진행한다
--   2. 프리셋이 켜지면 ProfileStore의 **Mock 저장소만** 쓴다(Store.Mock:StartSessionAsync). 실제 저장소(PlayerData_v1)에는
--      세션을 열지 않는다 — 읽기도 쓰기도 없다. Mock은 서버 메모리 안의 표(UserMockStore)라 Play를 멈추면 사라진다
--      (ProfileStore 1.0.3 소스 확인: Mock 프로필은 is_mock이 붙어 저장 · 세션 종료도 UserMockStore로 간다 · MessagingService 구독도 안 한다)
--   3. 프리셋 상태는 **세션을 열기 전에 템플릿으로** 만든다(Mock 저장소의 템플릿 = 프리셋 데이터). 런타임 재화 변경이 아니다 —
--      CurrencyService 단일 게이트(절대 규칙 2)의 예외는 이 경로(Studio · Mock 한정) 하나다(CLAUDE.md 절대 규칙 2에 적었다)
--   4. 커밋되는 TEST_PRESET(Bootstrap)은 언제나 nil이다 — register로 받은 값을 테스트가 읽어 nil인지 본다
--      (프리셋을 켠 Play에서는 그 테스트 하나가 실패한다 — 그 Play로 테스트 개수를 세지 않는다)
--
-- 사용법(사람): docs/TUNING.md "테스트 프리셋".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestPresets = require(ReplicatedStorage.Shared.Config.TestPresets)
local Schema = require(script.Parent.Schema)

local TestPresetGate = {}

-- Mock 전용 스토어 이름. 실제 스토어(ProfileManager STORE_NAME)와 일부러 다르게 둔다 —
-- Mock은 어차피 DataStore에 닿지 않지만, 혹시 Mock이 아닌 호출이 섞여도 실제 데이터 키와 겹치지 않게.
TestPresetGate.STORE_NAME = "PlayerData_v1_TestPreset_Mock"

local requested: string? = nil
local registered = false

-- Bootstrap의 TEST_PRESET 값을 기록한다(ProfileManager.init이 부른다). 테스트가 커밋 값(nil)을 확인하는 통로다.
function TestPresetGate.register(name: any)
	requested = if type(name) == "string" then name else nil
	registered = true
end

function TestPresetGate.isRegistered(): boolean
	return registered
end

function TestPresetGate.getRequested(): string?
	return requested
end

-- 켜도 되는가. 돌려주는 값: (켤 프리셋 이름 또는 nil, 로그 한 줄 또는 nil, 로그 수준 "warn" | "print" | nil)
function TestPresetGate.resolve(name: any, isStudio: boolean): (string?, string?, string?)
	if name == nil then
		return nil, nil, nil
	end
	if not isStudio then
		return nil, string.format(
			"[TestPreset] ERROR Studio가 아닌데 TEST_PRESET(%s)이 켜져 있다 — 무시하고 실제 저장소로 진행한다. Bootstrap의 TEST_PRESET을 nil로 되돌릴 것",
			tostring(name)
		), "warn"
	end
	if type(name) ~= "string" or TestPresets.Presets[name] == nil then
		return nil, string.format(
			"[TestPreset] ERROR 알 수 없는 프리셋 %s — 무시하고 실제 저장소로 진행한다(목록: %s)",
			tostring(name), table.concat(TestPresets.NAMES, ", ")
		), "warn"
	end
	return name, string.format(
		"[TestPreset] ⚠️ 프리셋 %s(%s) — Mock 프로필로 시작한다. 실제 데이터에는 읽기도 쓰기도 하지 않는다. Play를 멈추면 사라진다",
		name, TestPresets.Presets[name].label
	), "print"
end

local function copyBig(v: { m: number, e: number }): { m: number, e: number }
	return { m = v.m, e = v.e }
end

-- 프리셋 → 프로필 데이터(신규 템플릿 위에 덮는다). Schema.validate를 통과하지 못하면 에러 — 깨진 데이터로 세션을 열지 않는다.
function TestPresetGate.buildData(name: string): any
	local preset = TestPresets.Presets[name]
	assert(preset ~= nil, "TestPresetGate.buildData: 없는 프리셋 " .. tostring(name))
	local data = Schema.new() :: any
	data.strength = copyBig(preset.strength)
	data.blox = copyBig(preset.blox)
	data.lifeBlox = copyBig(preset.lifeBlox)
	data.lifetimeBlox = copyBig(preset.lifetimeBlox)
	data.rebirths = copyBig(preset.rebirths)
	data.progress.maxStage = preset.maxStage
	data.progress.selectedPadIndex = preset.padIndex
	for key, level in pairs(preset.upgrades) do
		if data.upgrades[key] ~= nil then
			data.upgrades[key] = level
		end
	end
	if preset.title then
		data.cosmetics.ownedTitles[preset.title] = true
		data.cosmetics.equippedTitle = preset.title
	end
	if preset.aura then
		data.cosmetics.ownedAuras[preset.aura] = true
		data.cosmetics.equippedAura = preset.aura
	end
	data.rolling.autoRollTitle = false -- 켜 두면 시작부터 블럭스가 빠져 상태가 흘러간다(TestPresetExport 상단)
	for i, pet in ipairs(preset.pets) do
		data.pets.owned[tostring(i)] = { petId = pet.petId, tier = pet.tier }
	end
	for _, i in ipairs(preset.equipped) do
		table.insert(data.pets.equipped, tostring(i))
	end
	data.pets.nextUid = #preset.pets + 1
	local ok, errors = Schema.validate(data)
	assert(ok, "TestPresetGate.buildData: 프리셋 " .. name .. "이 스키마 검증 실패 - " .. table.concat(errors or {}, " / "))
	return data
end

-- 어느 저장소로 세션을 여는가. 프리셋이 켜지면 newStore(Mock 전용 이름, 프리셋 데이터)로 새 스토어를 만들고 그 **.Mock**을 돌려준다.
-- 실제 스토어(realStore)는 건드리지 않는다(메서드를 하나도 부르지 않는다). 꺼져 있으면 realStore를 그대로 돌려준다.
-- 돌려주는 값: (세션을 열 대상, 켜진 프리셋 이름 또는 nil, 로그 한 줄, 로그 수준)
function TestPresetGate.chooseSessionStore(name: any, isStudio: boolean, realStore: any, newStore: (string, any) -> any): (any, string?, string?, string?)
	local active, line, level = TestPresetGate.resolve(name, isStudio)
	if active == nil then
		return realStore, nil, line, level
	end
	local store = newStore(TestPresetGate.STORE_NAME, TestPresetGate.buildData(active))
	return store.Mock, active, line, level
end

return TestPresetGate

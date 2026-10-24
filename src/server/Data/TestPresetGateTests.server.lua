--!strict
-- TestPresetGate · TestPresets 검증 (지시서 #13 3단계 — Studio 전용 테스트 프리셋의 안전장치).
--   1. Studio가 아니면 무시 + ERROR 로그     2. 켜지면 Mock 저장소만 — 실제 저장소 메서드를 하나도 부르지 않는다
--   3. 프리셋은 세션 전에 템플릿으로(스키마 검증 통과)     4. 커밋된 TEST_PRESET은 nil
-- ⚠️ 4번은 TEST_PRESET을 켠 Play에서 실패한다(PET_SWEEP_ONLY 검사와 같은 방식). 그 Play로 테스트 개수를 세지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local TestPresets = require(ReplicatedStorage.Shared.Config.TestPresets)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Schema = require(script.Parent.Schema)
local TestPresetGate = require(script.Parent.TestPresetGate)
local TestPresetExport = require(script.Parent.Parent.Tools.TestPresetExport)

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

-- 1. 목록 · 값의 형태 ----------------------------------------------------------------------------
do
	local n = 0
	for _ in pairs(TestPresets.Presets) do
		n += 1
	end
	local allListed = #TestPresets.NAMES == n
	for _, name in ipairs(TestPresets.NAMES) do
		if TestPresets.Presets[name] == nil then
			allListed = false
		end
	end
	check("NAMES = Presets 키 (6개)", allListed and n == 6, tostring(n))
	local stages = TestPresetExport.milestoneStages()
	local entries = TestPresetExport.entries(stages[#stages], stages)
	local same = #entries == #TestPresets.NAMES
	for i, entry in ipairs(entries) do
		if TestPresets.NAMES[i] ~= entry.name or TestPresets.Presets[entry.name].label ~= entry.label then
			same = false
		end
	end
	check("이름 · 화면 이름 = 뽑기 도구(TestPresetExport)의 시점 목록과 같은 순서", same)
end

for _, name in ipairs(TestPresets.NAMES) do
	local preset = TestPresets.Presets[name]
	local ok, data = pcall(TestPresetGate.buildData, name)
	check(name .. ": 프로필 데이터가 스키마 검증 통과", ok and (Schema.validate(data)), if ok then nil else tostring(data))
	if ok then
		check(name .. ": 재화 · 진행 값 = 프리셋 그대로", BigNum.eq(data.strength, preset.strength) and BigNum.eq(data.blox, preset.blox)
			and BigNum.eq(data.lifetimeBlox, preset.lifetimeBlox) and BigNum.eq(data.lifeBlox, preset.lifeBlox) and BigNum.eq(data.rebirths, preset.rebirths)
			and data.progress.maxStage == preset.maxStage and data.progress.selectedPadIndex == preset.padIndex
			and data.schemaVersion == Schema.VERSION and data.rolling.autoRollTitle == false)
		local titleKnown = preset.title == false
		for _, def in ipairs(TitleConfig.Titles) do
			if def.id == preset.title then
				titleKnown = true
			end
		end
		local idsOk = titleKnown and (preset.aura == false or AuraConfig.get(preset.aura) ~= nil)
		for _, pet in ipairs(preset.pets) do
			if PetConfig.get(pet.petId) == nil or not PetConfig.isLevel(pet.tier) then
				idsOk = false
			end
		end
		for key in pairs(preset.upgrades) do
			if UpgradeConfig.Upgrades[key] == nil then
				idsOk = false
			end
		end
		check(name .. ": 칭호 · 아우라 · 펫 · 업그레이드 id가 Config에 있다", idsOk)
		check(name .. ": 장착 ≤ 파생 슬롯 · 보유 ≤ 저장 공간 · 장착 uid는 보유에 있다",
			#data.pets.equipped <= PetConfig.getSlots(data.upgrades.petSlots, false) and #preset.pets <= PetConfig.getStorage(false)
				and (function()
					for _, uid in ipairs(data.pets.equipped) do
						if data.pets.owned[uid] == nil then
							return false
						end
					end
					return data.pets.nextUid == #preset.pets + 1
				end)())
	end
end
check("fresh = 신규 프로필과 같은 재화(시뮬레이터 시작 상태 = Schema.new)", (function()
	local data = TestPresetGate.buildData("fresh")
	local new = Schema.new()
	return BigNum.eq(data.strength, new.strength) and BigNum.eq(data.blox, new.blox) and next(data.pets.owned) == nil
end)())

-- 2. 켜도 되는가 (Studio에서만) -------------------------------------------------------------------
do
	local a, la = TestPresetGate.resolve(nil, true)
	check("resolve: nil이면 꺼짐 · 로그 없음", a == nil and la == nil)
	local b, lb, vb = TestPresetGate.resolve("floor25", false)
	check("resolve: Studio가 아니면 무시 + ERROR 로그(warn)", b == nil and lb ~= nil and string.find(lb :: string, "ERROR", 1, true) ~= nil and vb == "warn")
	local c, lc, vc = TestPresetGate.resolve("floor99", true)
	check("resolve: 없는 이름이면 무시 + ERROR 로그(warn)", c == nil and lc ~= nil and string.find(lc :: string, "ERROR", 1, true) ~= nil and vc == "warn")
	local d, ld, vd = TestPresetGate.resolve(7, true)
	check("resolve: 문자열이 아니면 무시 + ERROR", d == nil and ld ~= nil and vd == "warn")
	local e, le, ve = TestPresetGate.resolve("floor17", true)
	check("resolve: Studio + 있는 이름이면 켜짐 + Mock 안내(print)", e == "floor17" and le ~= nil and string.find(le :: string, "Mock", 1, true) ~= nil and ve == "print")
end

-- 3. 어느 저장소로 여는가 — 실제 저장소는 건드리지 않는다 -------------------------------------------
local function recorder(label: string, log: { string })
	local store: any = {}
	setmetatable(store, {
		__index = function(_t, key)
			if key == "Mock" then
				return rawget(store, "_mock")
			end
			return function(...)
				table.insert(log, label .. ":" .. tostring(key))
				return nil
			end
		end,
	})
	return store
end

do
	local log: { string } = {}
	local real = recorder("real", log)
	local made: { string } = {}
	local madeTemplate: any = nil
	local function newStore(name: string, template: any)
		table.insert(made, name)
		madeTemplate = template
		local s = recorder("preset", log)
		rawset(s, "_mock", recorder("mock", log))
		return s
	end
	local source, active = TestPresetGate.chooseSessionStore("floor25", true, real, newStore)
	source:StartSessionAsync("1")
	check("켜짐: 세션 대상 = 새 스토어의 .Mock · 실제 스토어 호출 0", active == "floor25" and #log == 1 and log[1] == "mock:StartSessionAsync", table.concat(log, ","))
	check("켜짐: 새 스토어 이름은 실제 스토어(PlayerData_v1)가 아니다", #made == 1 and made[1] == TestPresetGate.STORE_NAME and made[1] ~= "PlayerData_v1")
	check("켜짐: 새 스토어 템플릿 = 프리셋 데이터(세션 전에 만든다)", madeTemplate ~= nil and BigNum.eq(madeTemplate.strength, TestPresets.Presets.floor25.strength))

	local log2: { string } = {}
	local real2 = recorder("real", log2)
	local made2 = 0
	local source2, active2 = TestPresetGate.chooseSessionStore("floor25", false, real2, function()
		made2 += 1
		return nil
	end)
	check("Studio가 아니면: 실제 스토어 그대로 · 새 스토어를 만들지 않는다", source2 == real2 and active2 == nil and made2 == 0)
	local source3, active3 = TestPresetGate.chooseSessionStore(nil, true, real2, function()
		made2 += 1
		return nil
	end)
	check("nil이면: 실제 스토어 그대로 · 새 스토어를 만들지 않는다", source3 == real2 and active3 == nil and made2 == 0)
end

-- 4. ProfileStore 1.0.3 Mock 실물 왕복 — 서버 메모리(UserMockStore)에만 남는다 -----------------------
do
	local storeName = "TestPresetGateTests_Mock"
	local key = "t" .. tostring(math.floor(os.clock() * 1000))
	local store = ProfileStore.New(storeName, TestPresetGate.buildData("floor17"))
	local profile = store.Mock:StartSessionAsync(key)
	check("Mock 세션: 열린다 · 데이터 = 프리셋 템플릿", profile ~= nil and BigNum.eq(profile.Data.strength, TestPresets.Presets.floor17.strength)
		and profile.Data.cosmetics.equippedTitle == TestPresets.Presets.floor17.title)
	local test = ProfileStore.Test()
	local userMock = test.UserMockStore[storeName]
	check("Mock 세션: UserMockStore(사용자 Mock)에만 기록 · API 대체 MockStore에는 없다", userMock ~= nil and userMock[key] ~= nil and test.MockStore[storeName] == nil)
	if profile ~= nil then
		profile:EndSession()
	end
end

-- 5. 커밋된 TEST_PRESET은 nil (Bootstrap이 ProfileManager.init으로 넘긴 값) -------------------------------
do
	local deadline = os.clock() + 15
	while not TestPresetGate.isRegistered() and os.clock() < deadline do
		task.wait(0.1)
	end
	check("Bootstrap TEST_PRESET 커밋 값 = nil (켠 Play에서는 이 줄이 실패한다)", TestPresetGate.isRegistered() and TestPresetGate.getRequested() == nil,
		tostring(TestPresetGate.getRequested()))
end

print(string.format("[TestPresetGateTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TestPresetGateTests] %d test(s) failed", failed))
end

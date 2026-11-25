--!strict
-- RemoteGuard(입구 공통 문) + 입구마다 흔들기(지시서 #38 — 리모트 보안).
-- 1. 모양 예산 2. 연타 통 3. 오류 격리 4. 나가면 지움 5. 입구 목록(Remotes 정의 ↔ 붙은 리모트)
-- 6. 입구마다: 잘못된 인자 묶음 · 연타 → 거부되고 상태(바꾸는 deps) 그대로. 공통 도우미 RemoteFuzz.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CodesConfig = require(ReplicatedStorage.Shared.Config.CodesConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local RemoteGuard = require(script.Parent.RemoteGuard)
local RemoteFuzz = require(script.Parent.RemoteFuzz)

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

local pure = RemoteGuard._pure
local function noop() end

-- 1. 모양 예산 ---------------------------------------------------------------------------------------
do
	local okCases = { nil, true, 3, "craft", { action = "craft", combo = { 1, 2, 3, 4, 5 }, fill = false }, { stage = 2 }, {} }
	local allOk = true
	for i = 1, 7 do
		allOk = allOk and (pure.checkShape(okCases[i]))
	end
	check("모양: 정상 payload 7종 통과(nil · 불 · 수 · 글 · 대장간 표 · 워프 표 · 빈 표)", allOk)
	local wide = {}
	for i = 1, 40 do
		wide[i] = i
	end
	local bad = {
		{ 0 / 0, "not_finite" },
		{ math.huge, "not_finite" },
		{ { stage = -math.huge }, "not_finite" },
		{ string.rep("a", RemoteGuard.MAX_STRING + 1), "string_too_long" },
		{ { a = { b = { c = {} } } }, "too_deep" }, -- 표 4단
		{ wide, "too_many_keys" },
		{ { [true :: any] = 1 }, "bad_key" },
		{ Vector3.new(1, 2, 3), "bad_type" },
		{ workspace, "bad_type" },
		{ function() end, "bad_type" },
	}
	local allBad = true
	local detail = ""
	for _, case in ipairs(bad) do
		local ok, why = pure.checkShape(case[1])
		if ok or why ~= case[2] then
			allBad = false
			detail ..= string.format("%s→%s ", case[2], tostring(why))
		end
	end
	check("모양: 거부 10종(NaN · inf · 긴 글 · 깊은 표 · 큰 표 · 이상한 키 · Vector3 · Instance · 함수) 사유 그대로", allBad, detail)
	local manyValues = {}
	for i = 1, 30 do
		manyValues["k" .. i] = { 1, 2, 3, 4, 5 }
	end
	local ok, why = pure.checkShape(manyValues)
	check("모양: 값 총수 상한(키 30 × 5)", not ok and why == "too_many_values", tostring(why))
end

-- 2. 연타 통 ----------------------------------------------------------------------------------------
do
	local gate = pure.newGate()
	local P = {}
	local a = gate.check(P, "ForgeRequest", {}, 10)
	local b = gate.check(P, "ForgeRequest", {}, 10.1)
	local c = gate.check(P, "ForgeRequest", {}, 10.16)
	check("연타: 기본 0.15초 — 0.1초 뒤 거부 · 0.16초 뒤 통과", a and not b and c)
	local other = gate.check(P, "PetRequest", {}, 10.1)
	local P2 = {}
	local p2 = gate.check(P2, "ForgeRequest", {}, 10.1)
	check("연타: 통은 리모트마다 · 플레이어마다 따로", other and p2)
	-- 클릭 묶음: 0.2초 주기 클라가 몰려 도착해도(같은 시각 4개) 다 받는다. 그 뒤 초당 10개
	local clicks = 0
	for _ = 1, 6 do
		if gate.check(P, "ClickInput", { count = 3 }, 20) then
			clicks += 1
		end
	end
	local steady = 0
	for i = 1, 50 do
		if gate.check(P, "ClickInput", { count = 3 }, 21 + i * 0.2) then
			steady += 1
		end
	end
	check("연타: ClickInput — 몰림 4개까지 · 0.2초 주기는 전부", clicks == 4 and steady == 50, string.format("%d %d", clicks, steady))
	local syncs = 0
	for _ = 1, 12 do
		if gate.check(P, "SyncRequest", {}, 30) then
			syncs += 1
		end
	end
	local syncs2 = 0
	for _ = 1, 3 do
		if gate.check(P, "SyncRequest#2", {}, 30) then
			syncs2 += 1
		end
	end
	check("연타: SyncRequest — 접속 직후 10개까지 · 두 번째 서비스 통은 따로", syncs == 10 and syncs2 == 3, string.format("%d %d", syncs, syncs2))
	local spam = 0
	for i = 0, 999 do
		if gate.check(P, "UpgradeRequest", { name = "x" }, 40 + i * 0.001) then
			spam += 1
		end
	end
	check("연타: 1초에 1000번 → 기본 통은 7번 이하", spam <= 7, tostring(spam))
	local s = gate.stats()
	check("연타: 버린 수를 센다(stats)", (s.UpgradeRequest.rate_limited or 0) == 1000 - spam and (s.UpgradeRequest.passed or 0) == spam)
	local shapeBad = gate.check(P, "WarpRequest", { stage = 0 / 0 }, 50)
	local after = gate.check(P, "WarpRequest", { stage = 2 }, 50)
	check("연타: 모양에 걸린 요청은 통을 쓰지 않는다", not shapeBad and after)
	gate.forget(P)
	check("나가기: forget 뒤 그 플레이어 통이 없다", gate._buckets(P) == nil and gate._buckets(P2) ~= nil)
end

-- 3. 오류 격리 --------------------------------------------------------------------------------------
do
	local lines = {}
	local state = { n = 0 }
	local function handler(_p: any, payload: any)
		if payload.boom then
			error("boom")
		end
		state.n += 1
	end
	local ok1 = pure.runIsolated("TestRemote", handler, {}, { boom = true }, 1000, function(l)
		table.insert(lines, l)
	end)
	local ok2 = pure.runIsolated("TestRemote", handler, {}, { boom = false }, 1001, function(l)
		table.insert(lines, l)
	end)
	local ok3 = pure.runIsolated("TestRemote", handler, {}, { boom = true }, 1002, function(l)
		table.insert(lines, l)
	end)
	check("오류 격리: 오류가 나도 다음 요청은 처리된다 · 상태는 오류 전 그대로", not ok1 and ok2 and not ok3 and state.n == 1)
	check("오류 격리: warn은 60초에 한 번(같은 리모트)", #lines == 1 and string.find(lines[1], "TestRemote", 1, true) ~= nil)
end

-- 4. 입구 목록: Remotes에 정의된 클라 → 서버 리모트 = RemoteGuard로 붙은 리모트 -------------------------------
do
	local inbound = {
		Remotes.CLICK_INPUT, Remotes.SPEED_REQUEST, Remotes.SYNC_REQUEST, Remotes.REBIRTH_REQUEST, Remotes.WARP_REQUEST,
		Remotes.UPGRADE_REQUEST, Remotes.TITLE_REQUEST, Remotes.AURA_REQUEST, Remotes.SETTINGS_REQUEST, Remotes.PET_REQUEST,
		Remotes.PURCHASE_REQUEST, Remotes.AUTO_CLICK_REQUEST, Remotes.POTION_REQUEST, Remotes.PLUS_PROMPT_REQUEST,
		Remotes.AUTO_ADVANCE_REQUEST, Remotes.DAILY_REQUEST, Remotes.CODE_REQUEST, Remotes.ONBOARDING_REQUEST, Remotes.FORGE_REQUEST,
		Remotes.EQUIPMENT_REQUEST, Remotes.PET_AUTO_REQUEST, Remotes.ONBOARDING_TIP_REQUEST,
	}
	check("목록: 클라 → 서버 리모트 22개(이름 전부 정의됨)", #inbound == 22)
	-- 서비스 init은 Bootstrap이 테스트와 같은 때 돌린다 — 붙을 때까지 기다린다(상한 20초 · 넘으면 실패 1개)
	local deadline = os.clock() + 20
	local connected = RemoteGuard.connected()
	while os.clock() < deadline do
		connected = RemoteGuard.connected()
		local all = true
		for _, name in ipairs(inbound) do
			all = all and (connected[name] or 0) >= 1
		end
		if all then
			break
		end
		task.wait(0.5)
	end
	local missing = {}
	for _, name in ipairs(inbound) do
		if (connected[name] or 0) < 1 then
			table.insert(missing, name)
		end
	end
	check("목록: 22개 전부 RemoteGuard로 붙었다", #missing == 0, table.concat(missing, ","))
	check("목록: SyncRequest는 두 서비스(상태 · 드롭)가 듣는다 — 합 23", (connected[Remotes.SYNC_REQUEST] or 0) == 2)
	-- 서버 → 클라 쪽은 클라가 OnServerEvent로 보낼 수 없다 — 붙은 것이 inbound 밖에 없어야 한다
	local extra = {}
	local set = {}
	for _, name in ipairs(inbound) do
		set[name] = true
	end
	for name in pairs(connected) do
		if not set[name] then
			table.insert(extra, name)
		end
	end
	check("목록: 목록 밖 리모트를 듣는 서비스 없음", #extra == 0, table.concat(extra, ","))
end

-- 5. 입구마다 흔들기 ----------------------------------------------------------------------------------
local function fuzz(label: string, spec: any)
	local r = RemoteFuzz.run(spec)
	check(label .. ": 정상 요청은 받아들인다(대조)", r.controlOk)
	check(label .. ": 잘못된 payload 통째 15종 → 거부 · 상태 그대로", #r.wholeLeaks == 0, table.concat(r.wholeLeaks, ","))
	check(label .. ": 필드 하나씩 잘못 → 거부 · 상태 그대로", #r.badLeaks == 0, table.concat(r.badLeaks, ","))
	check(label .. ": 연타 20번(1ms 간격) → 처리 1번 이하", r.spamCalls <= 1, tostring(r.spamCalls))
	check(label .. ": 처리 중 오류 없음", #r.errors == 0, r.errors[1])
end

local function handlerOf(module: any, mutators: any, reads: any?, viaRuntime: boolean?)
	return function()
		local deps, calls = RemoteFuzz.spyDeps(reads or { send = noop }, mutators)
		local h = if viaRuntime then module._pure.createRuntime(deps) else module._pure.createHandler(deps)
		return function(p: any, payload: any, now: number)
			return h.onRequest(p, payload, now)
		end, calls
	end
end

local function okWith(v: any)
	return function()
		return true, v
	end
end

do
	local Aura = require(script.Parent.AuraRequestService)
	local muts = { roll = okWith({ auraId = "a", tier = 1 }), rollCredit = okWith({ auraId = "a", tier = 1 }), equip = okWith(nil), selectPack = okWith(nil) }
	fuzz("Aura roll", { name = Remotes.AURA_REQUEST, make = handlerOf(Aura, muts), valid = { action = "roll", pack = 1 }, fields = { action = "string", pack = "number" } })
	fuzz("Aura equip", { name = Remotes.AURA_REQUEST, make = handlerOf(Aura, muts), valid = { action = "equip", auraId = "aura_1" }, fields = { auraId = "id" } })
end

do
	local Pet = require(script.Parent.PetRequestService)
	local muts = {}
	for _, k in ipairs({ "hatch", "hatchMulti", "equip", "unequip", "equipBest", "craft", "release" }) do
		muts[k] = okWith({})
	end
	fuzz("Pet hatch", { name = Remotes.PET_REQUEST, make = handlerOf(Pet, muts), valid = { action = "hatch", egg = 1 }, fields = { action = "string", egg = "number" } })
	fuzz("Pet equip", { name = Remotes.PET_REQUEST, make = handlerOf(Pet, muts), valid = { action = "equip", uid = "12" }, fields = { uid = "string" } })
end

do
	local Title = require(script.Parent.TitleRequestService)
	local muts = { roll = okWith({}), equip = okWith(nil), setAutoRoll = okWith(nil) }
	fuzz("Title setAuto", { name = Remotes.TITLE_REQUEST, make = handlerOf(Title, muts), valid = { action = "setAuto", on = true }, fields = { action = "string", on = "boolean" } })
	fuzz("Title equip", { name = Remotes.TITLE_REQUEST, make = handlerOf(Title, muts), valid = { action = "equip", titleId = "title_1" }, fields = { titleId = "id" } })
end

do
	local Upgrade = require(script.Parent.UpgradeRequestService)
	fuzz("Upgrade", { name = Remotes.UPGRADE_REQUEST, make = handlerOf(Upgrade, { buy = okWith({ level = 1, cost = BigNum.new(1, 2) }) }), valid = { name = "punchSpeed" },
		fields = { name = "id" } })
end

do
	local Warp = require(script.Parent.WarpRequestService)
	fuzz("Warp", { name = Remotes.WARP_REQUEST, make = handlerOf(Warp, { warp = okWith(BigNum.new(1, 2)) }), valid = { stage = 2 }, fields = { stage = "number" } })
end

do
	local Settings = require(script.Parent.SettingsRequestService)
	fuzz("Settings", { name = Remotes.SETTINGS_REQUEST, make = handlerOf(Settings, { getCosmetics = function()
		return {}
	end }), valid = { key = "reduceMotion", value = true }, fields = { key = "string", value = "boolean" } })
end

do
	local Potion = require(script.Parent.PotionRequestService)
	local reads = { send = noop, notify = noop, isRestricted = function()
		return false
	end, getData = function()
		return { potions = { strength = 3, damage = 3, luck = 3 } }
	end }
	fuzz("Potion", { name = Remotes.POTION_REQUEST, make = handlerOf(Potion, { addBoost = function()
		return true
	end }, reads), valid = { boost = "strength" }, fields = { boost = "string" } })
end

do
	local Code = require(script.Parent.CodeService)
	local reads = { send = noop, codes = CodesConfig.Codes, now = function()
		return 0
	end, getData = function()
		return { redeemedCodes = {} }
	end }
	fuzz("Code", { name = Remotes.CODE_REQUEST, make = handlerOf(Code, { grant = okWith({ blox = BigNum.new(0, 0) }) }, reads, true), valid = { code = "RELEASE" },
		fields = { code = "string" } })
end

do
	local Onboarding = require(script.Parent.OnboardingService)
	local reads = { send = noop, notify = noop, log = noop, logFunnel = noop }
	fuzz("Onboarding", { name = Remotes.ONBOARDING_REQUEST, make = handlerOf(Onboarding, { getData = function()
		return { onboarding = { step = 1, done = false } }
	end, grant = okWith({}) }, reads, true), valid = { action = "skip" }, fields = { action = "string" } })
end

do
	local AutoAdvance = require(script.Parent.AutoAdvanceService)
	local reads = { send = noop, notify = noop, log = noop, owns = function()
		return true
	end, getRunState = function()
		return nil
	end, hasCharacter = function()
		return true
	end, safeFloorOf = function()
		return 1
	end, moveToEntrance = function()
		return true -- 시작 한 번이 입구 이동 + 런 시작을 같이 부른다 — 런 시작으로만 센다
	end }
	local muts = { startRun = okWith(nil), advance = okWith(nil), cashout = okWith(nil) }
	fuzz("AutoAdvance", { name = Remotes.AUTO_ADVANCE_REQUEST, make = handlerOf(AutoAdvance, muts, reads, true), valid = { action = "start", target = 5 },
		fields = { action = "string", target = "number" } })
end

do
	local AutoClick = require(script.Parent.AutoClickService)
	fuzz("AutoClick", { name = Remotes.AUTO_CLICK_REQUEST, valid = { on = true }, fields = { on = "boolean" }, make = function()
		local calls = { on = 0 }
		local rt = AutoClick._pure.createRuntime({ send = noop, click = noop, rateOf = function()
			return 5
		end })
		return function(p: any, payload: any, now: number)
			local out = rt.onRequest(p, payload, now)
			if rt.isOn(p) then
				calls.on += 1
			end
			return out
		end, calls
	end })
end

do
	local Rebirth = require(script.Parent.RebirthRequestService)
	fuzz("Rebirth", { name = Remotes.REBIRTH_REQUEST, payloadFree = true, valid = {}, make = function()
		local deps, calls = RemoteFuzz.spyDeps({ send = noop }, { rebirth = okWith({ rebirths = BigNum.new(1, 0) }) })
		local h = Rebirth._pure.createHandler(deps)
		return function(p: any, _payload: any, now: number)
			return h.onRequest(p, now)
		end, calls
	end })
end

do
	local Purchase = require(script.Parent.PurchaseRequestService)
	-- 새 패스 ID가 nil이라 정상 대조는 못 한다 — 변형 · 통째 · 연타만(프롬프트가 한 번도 안 뜬다)
	fuzz("Purchase", { name = Remotes.PURCHASE_REQUEST, noControl = true, valid = { key = "auto_clicker" }, fields = { key = "id" }, make = function()
		local calls = { prompt = 0 }
		local gateway = setmetatable({}, { __index = function(_, k)
			return function()
				if string.find(string.lower(tostring(k)), "prompt", 1, true) then
					calls.prompt += 1
				end
				return false
			end
		end })
		local h = Purchase._pure.createHandler({ gateway = gateway :: any, owns = function()
			return false
		end, isRestricted = function()
			return false
		end, hasGrant = function()
			return true
		end, send = noop })
		return function(p: any, payload: any, now: number)
			return h.onRequest(p, payload, now)
		end, calls
	end })
end

do
	local PlusPrompt = require(script.Parent.PlusPromptService)
	fuzz("PlusPrompt", { name = Remotes.PLUS_PROMPT_REQUEST, valid = { reason = "shop" }, fields = { reason = "string" }, make = function()
		local calls = { prompt = 0 }
		local rt = PlusPrompt._pure.createRuntime({ enabled = true, log = noop, gateway = {
			hasRobloxSubscription = function()
				return false
			end,
			promptRobloxSubscription = function()
				calls.prompt += 1
				return true
			end,
		} })
		return function(p: any, payload: any, _now: number)
			return rt.request(p, if type(payload) == "table" then payload.reason else nil)
		end, calls
	end })
end

-- 새 경제 입구(모듈 상태 + _deps 바꿔 끼우기 — 끝나면 되돌린다)
local FUZZ_P = nil :: any
do
	local Forge = require(script.Parent.ForgeService)
	local saved = Forge._deps
	local clock = 0
	local ores = {}
	for k = 1, EconomyV2Config.ORE_COUNT do
		ores[k] = 99
	end
	fuzz("Forge craft", { name = Remotes.FORGE_REQUEST, valid = { action = "craft", combo = { 1, 1, 1, 1, 1 } }, fields = { action = "string", combo = "array" },
		make = function()
			local deps, calls = RemoteFuzz.spyDeps({
				isForgeOpen = function()
					return true
				end,
				getOres = function()
					return table.clone(ores)
				end,
				getTokens = function()
					return {}
				end,
				getOwned = function()
					return {}
				end,
				ownsSkipPass = function()
					return false
				end,
				ownsTriple = function()
					return false
				end,
				send = noop,
				rand = function()
					return 0.5
				end,
				now = function()
					return clock
				end,
			}, { craft = okWith(nil), exchange = okWith(nil) })
			Forge._deps = deps
			return function(p: any, payload: any, now: number)
				FUZZ_P = p
				Forge._reset(p)
				clock = now
				Forge._deps = deps
				return Forge.handleRequest(p, payload)
			end, calls
		end })
	-- 연타는 상태를 지우지 않고 다시(위 make는 매번 _reset — 대장간 자체 0.15초 · 제작 간격을 같이 본다)
	do
		local deps, calls = RemoteFuzz.spyDeps({
			isForgeOpen = function()
				return true
			end,
			getOres = function()
				return table.clone(ores)
			end,
			getTokens = function()
				return {}
			end,
			getOwned = function()
				return {}
			end,
			ownsSkipPass = function()
				return false
			end,
			ownsTriple = function()
				return false
			end,
			send = noop,
			rand = function()
				return 0.5
			end,
			now = function()
				return clock
			end,
		}, { craft = okWith(nil) })
		Forge._deps = deps
		local P = {}
		Forge._reset(P :: any)
		for i = 0, 99 do
			clock = 500 + i * 0.01 -- 1초 동안 100번(문 없이 서비스만)
			Forge.handleRequest(P :: any, { action = "craft", combo = { 1, 1, 1, 1, 1 } })
		end
		local most = math.floor(1 / EconomyV2Config.CRAFT_MIN_INTERVAL_SEC) + 1 -- 가장 짧은 제작 간격(연출 생략)으로도 이만큼
		check("Forge: 문 없이 1초에 100번 → 제작은 간격만큼만(서비스 자체 상한)", calls.craft >= 1 and calls.craft <= most, tostring(calls.craft))
		Forge._reset(P :: any)
	end
	if FUZZ_P ~= nil then
		Forge._reset(FUZZ_P)
	end
	Forge._deps = saved
end

do
	local Equipment = require(script.Parent.EquipmentService)
	local saved = Equipment._deps
	local clock = 0
	fuzz("Equipment equip", { name = Remotes.EQUIPMENT_REQUEST, valid = { action = "equip", id = "pick_c1" }, fields = { action = "string", id = "string" },
		make = function()
			local deps, calls = RemoteFuzz.spyDeps({
				isForgeOpen = function()
					return true
				end,
				getEquipment = function()
					return { pick_c1 = { count = 3, stars = 0, enh = 0 } }
				end,
				getEquipped = function()
					return ""
				end,
				getOres = function()
					local inv = {}
					for k = 1, EconomyV2Config.ORE_COUNT do
						inv[k] = 99
					end
					return inv
				end,
				onEquipped = noop,
				send = noop,
				now = function()
					return clock
				end,
			}, { equip = okWith(nil), enhance = okWith(nil), starUp = okWith(nil) })
			return function(p: any, payload: any, now: number)
				FUZZ_P = p
				Equipment._deps = deps
				Equipment._reset(p)
				clock = now
				return Equipment.handleRequest(p, payload)
			end, calls
		end })
	if FUZZ_P ~= nil then
		Equipment._reset(FUZZ_P)
	end
	Equipment._deps = saved
end

do
	local PetAuto = require(script.Parent.PetAutoHatchService)
	local saved = PetAuto._deps
	local clock = 0
	fuzz("PetAuto", { name = Remotes.PET_AUTO_REQUEST, valid = { on = true, egg = 1 }, fields = { on = "boolean", egg = "number" }, make = function()
		local calls = { on = 0 }
		local deps = { hatch = okWith({}), hatchMulti = okWith({}), ownsTriple = function()
			return false
		end, send = noop, notify = noop, now = function()
			return clock
		end }
		return function(p: any, payload: any, now: number)
			FUZZ_P = p
			PetAuto._deps = deps
			PetAuto._reset(p)
			clock = now
			PetAuto.handleRequest(p, payload)
			local s = PetAuto._state(p)
			if s ~= nil and s.on then
				calls.on += 1
			end
		end, calls
	end })
	if FUZZ_P ~= nil then
		PetAuto._reset(FUZZ_P)
	end
	PetAuto._deps = saved
end

-- 클릭 수: 서비스 자체 정리(sanitizeCount)
do
	local ClickService = require(script.Parent.ClickService)
	local s = ClickService._pure.sanitizeCount
	local zero = true
	for _, v in ipairs({ 0 / 0, math.huge, -math.huge, -1, 0, 1.5, "5", {}, true }) do
		zero = zero and s(v) == 0
	end
	check("Click: count NaN · inf · 음수 · 0 · 소수 · 글 · 표 → 0(지급 없음)", zero)
	check("Click: 아주 큰 count는 배치 상한으로 잘린다", s(1e12) < 1e12 and s(1e12) > 0 and s(3) == 3)
end

print(string.format("[RemoteGuardTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RemoteGuardTests] %d test(s) failed", failed))
end

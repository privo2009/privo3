--!strict
-- UpgradeService 검증 (지시서 #7 3단계): 구매 거부 경로(잘못된 항목 · 최대 레벨 · 블럭스 부족 · 프로필 없음),
-- 차감 → 레벨 + 1 → 통지 순서, 부분 실패, 저장값 읽기, 환생 경로가 업그레이드를 건드리지 않는다(S5 — 유지).
--
-- UpgradeService._pure.runBuy에 **기록용 deps**를 넣는다(RebirthServiceTests와 같은 이유 — 가짜 Player로는
-- 프로필이 없어 "프로필 없음" 한 갈래로만 끝난다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local UpgradeService = require(script.Parent.UpgradeService)
local RebirthService = require(script.Parent.RebirthService)
local Schema = require(script.Parent.Parent.Data.Schema)

local pure = UpgradeService._pure

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

local fakePlayer = { Name = "UpgradeTest", UserId = 1 } :: any

type World = {
	hasProfile: boolean,
	blox: BigNum.BigNumber,
	levels: { [string]: number },
	calls: { string },
	subtracted: { { amount: BigNum.BigNumber, reason: string } },
	failAt: string?,
	notified: { { name: string, level: number } },
}

local function newWorld(blox: BigNum.BigNumber): World
	return { hasProfile = true, blox = blox, levels = {}, calls = {}, subtracted = {}, failAt = nil, notified = {} }
end

local function depsFor(w: World)
	return {
		getLevel = function(_p: any, name: string)
			table.insert(w.calls, "getLevel")
			if not w.hasProfile then
				return nil
			end
			return w.levels[name] or 0
		end,
		getBlox = function(_p: any)
			table.insert(w.calls, "getBlox")
			return if w.hasProfile then w.blox else nil
		end,
		subtractBlox = function(_p: any, amount: BigNum.BigNumber, reason: string)
			table.insert(w.calls, "subtract")
			if w.failAt == "subtract" then
				return false
			end
			table.insert(w.subtracted, { amount = amount, reason = reason })
			w.blox = BigNum.sub(w.blox, amount)
			return true
		end,
		setLevel = function(_p: any, name: string, level: number)
			table.insert(w.calls, "setLevel")
			if w.failAt == "setLevel" then
				return false
			end
			w.levels[name] = level
			return true
		end,
		notify = function(_p: any, name: string, level: number)
			table.insert(w.calls, "notify")
			table.insert(w.notified, { name = name, level = level })
		end,
	}
end

local function sideEffects(w: World): number
	local n = 0
	for _, c in ipairs(w.calls) do
		if c == "subtract" or c == "setLevel" or c == "notify" then
			n += 1
		end
	end
	return n
end

local RICH = BigNum.new(1, 50)

-- 1. 거부 경로 — 전부 부작용 0 -------------------------------------------------------------------
do
	-- nil이 끼어 있어 ipairs를 쓰지 않는다(nil에서 멈춘다)
	-- 비노출 항목은 #12에서 없어졌다(petSlots · petLuck 노출) — 없는 이름 둘로 대신한다
	local bads: { any } = { "radius", "drones", "auraluck", "", 5, false, { name = "punchDamage" } }
	bads[8] = nil
	for i = 1, 8 do
		local bad = bads[i]
		local w = newWorld(RICH)
		local ok, reason = pure.runBuy(depsFor(w) :: any, fakePlayer, bad)
		check("거부: 잘못된 항목 " .. tostring(bad) .. " → invalid_upgrade · 부작용 0 · 프로필도 안 읽음",
			not ok and reason == UpgradeConfig.REASON_INVALID_UPGRADE and #w.calls == 0, tostring(reason))
	end

	local noProfile = newWorld(RICH)
	noProfile.hasProfile = false
	local ok1, r1 = pure.runBuy(depsFor(noProfile) :: any, fakePlayer, "punchDamage")
	check("거부: 프로필 없음 → no_profile · 부작용 0", not ok1 and r1 == UpgradeService.REASON_NO_PROFILE and sideEffects(noProfile) == 0)

	local maxed = newWorld(RICH)
	maxed.levels.punchSpeed = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number
	local ok2, r2 = pure.runBuy(depsFor(maxed) :: any, fakePlayer, "punchSpeed")
	check("거부: 최대 레벨 → max_level · 블럭스가 많아도 차감 없음", not ok2 and r2 == UpgradeConfig.REASON_MAX_LEVEL and sideEffects(maxed) == 0)

	local poor = newWorld(BigNum.sub(UpgradeConfig.getCostAtLevel("punchSpeed", 0), BigNum.fromNumber(1)))
	local ok3, r3 = pure.runBuy(depsFor(poor) :: any, fakePlayer, "punchSpeed")
	check("거부: 블럭스 부족 → insufficient_blox · 차감 없음", not ok3 and r3 == UpgradeConfig.REASON_INSUFFICIENT_BLOX and sideEffects(poor) == 0)
end

-- 2. 성공 — 차감 → 레벨 + 1 → 통지 ----------------------------------------------------------------
do
	local w = newWorld(RICH)
	w.levels.punchDamage = 3
	local cost = UpgradeConfig.getCostAtLevel("punchDamage", 3)
	local ok, result = pure.runBuy(depsFor(w) :: any, fakePlayer, "punchDamage")
	check("성공: true + 레벨 4 + 비용", ok and result.level == 4 and BigNum.eq(result.cost, cost) and result.name == "punchDamage")
	check("성공: 차감은 getCostAtLevel(지금 레벨) 그대로 한 번", #w.subtracted == 1 and BigNum.eq(w.subtracted[1].amount, cost))
	check("성공: 차감 사유에 항목 이름(재화 로그 추적)", #w.subtracted == 1 and w.subtracted[1].reason == "upgrade_punchDamage")
	check("성공: 레벨이 정확히 1 올랐다", w.levels.punchDamage == 4)
	local order = table.concat(w.calls, ",")
	check("성공: 순서 = 읽기 → 차감 → 레벨 → 통지", order == "getLevel,getBlox,subtract,setLevel,notify", order)
	check("성공: 통지에 새 레벨", #w.notified == 1 and w.notified[1].name == "punchDamage" and w.notified[1].level == 4)

	-- 딱 맞는 잔액이면 산다(경계는 이상)
	local exact = newWorld(UpgradeConfig.getCostAtLevel("bloxGain", 0))
	local okE = pure.runBuy(depsFor(exact) :: any, fakePlayer, "bloxGain")
	check("성공: 잔액 = 비용이면 산다", okE and exact.levels.bloxGain == 1)

	-- 최대 레벨 바로 아래에서 사면 최대 레벨이 되고, 그다음은 max_level
	local nearTop = newWorld(RICH)
	local top = UpgradeConfig.Upgrades.punchSpeed.maxLevel :: number
	nearTop.levels.punchSpeed = top - 1
	local okT = pure.runBuy(depsFor(nearTop) :: any, fakePlayer, "punchSpeed")
	local okT2, rT2 = pure.runBuy(depsFor(nearTop) :: any, fakePlayer, "punchSpeed")
	check("성공 → 최대 레벨 도달 뒤 다음 구매는 max_level", okT and nearTop.levels.punchSpeed == top and not okT2 and rT2 == UpgradeConfig.REASON_MAX_LEVEL)
end

-- 2b. 이동 속도 업그레이드 삭제 (L3, 지시서 #13) — 옛 클라가 보내도 서버가 거부한다 -----------------------------
do
	local w = newWorld(RICH)
	local ok, reason = pure.runBuy(depsFor(w) :: any, fakePlayer, "moveSpeed")
	check("L3: moveSpeed 구매 요청 → invalid_upgrade · 부작용 0 · 프로필도 안 읽음", not ok and reason == UpgradeConfig.REASON_INVALID_UPGRADE
		and #w.calls == 0)
end

-- 3. 부분 실패 ---------------------------------------------------------------------------------------
do
	local w = newWorld(RICH)
	w.failAt = "subtract"
	local ok, reason = pure.runBuy(depsFor(w) :: any, fakePlayer, "punchDamage")
	check("차감 거부: insufficient_blox · 레벨 그대로 · 통지 없음", not ok and reason == UpgradeConfig.REASON_INSUFFICIENT_BLOX
		and w.levels.punchDamage == nil and #w.notified == 0)

	-- 잔액은 작게 — RICH(1e50)에서 10을 빼면 BigNum 정밀도 계약(지수 차 13 이상은 0 소실)대로 1e50 그대로다
	local v = newWorld(BigNum.fromNumber(1000))
	v.failAt = "setLevel"
	local before = v.blox
	local ok2, reason2 = pure.runBuy(depsFor(v) :: any, fakePlayer, "punchDamage")
	check("레벨 저장 실패: partial_failure (차감은 일어났다 — 공짜 레벨 없음)", not ok2 and reason2 == UpgradeService.REASON_PARTIAL_FAILURE
		and #v.subtracted == 1 and BigNum.lt(v.blox, before))
	check("레벨 저장 실패: 통지 없음", #v.notified == 0)
end

-- 4. 저장값 읽기 ---------------------------------------------------------------------------------
do
	check("readLevel: 정상값", pure.readLevel({ upgrades = { punchDamage = 7 } }, "punchDamage") == 7)
	check("readLevel: 없는 키 · 표 없음 · Data 없음 → 0", pure.readLevel({ upgrades = {} }, "punchDamage") == 0
		and pure.readLevel({}, "punchDamage") == 0 and pure.readLevel(nil, "punchDamage") == 0)
	check("readLevel: 음수 · NaN · inf · 문자열 → 0", pure.readLevel({ upgrades = { a = -1, b = 0 / 0, c = math.huge, d = "3" } }, "a") == 0
		and pure.readLevel({ upgrades = { b = 0 / 0 } }, "b") == 0 and pure.readLevel({ upgrades = { c = math.huge } }, "c") == 0
		and pure.readLevel({ upgrades = { d = "3" } }, "d") == 0)
	check("readLevel: 소수는 내림", pure.readLevel({ upgrades = { punchDamage = 2.7 } }, "punchDamage") == 2)
	local levels = UpgradeService.readLevels(Schema.new())
	local n = 0
	for _, v in pairs(levels) do
		n += 1
		if v ~= 0 then
			n = -100
		end
	end
	check("readLevels: 새 프로필은 7키 전부 0 (L3 — moveSpeed 없음)", n == 7, tostring(n))

	-- 프로필 없는 플레이어: 레벨 0 · 효과 = 0레벨 효과
	check("getLevel: 프로필 없음 → 0", UpgradeService.getLevel(fakePlayer, "punchSpeed") == 0)
	check("getEffect: 프로필 없음 → 기본 펀치 속도", UpgradeService.getEffect(fakePlayer, "punchSpeed") == AttackConfig.PUNCH_SPEED_BASE)
	check("getEffect: 프로필 없음 → 데미지 · 블럭스 배수 1", UpgradeService.getEffect(fakePlayer, "punchDamage") == 1 and UpgradeService.getEffect(fakePlayer, "bloxGain") == 1)
end

-- 5. 환생 경로는 업그레이드를 건드리지 않는다 (S5 — 확인만. RebirthService는 바꾸지 않았다) ---------------
-- runRebirth가 부르는 deps 키를 전부 기록한다. 업그레이드를 바꾸는 통로가 deps에 없으면 환생은 upgrades에 손댈 수 없다
-- (runRebirth는 프로필을 직접 만지지 않고 deps로만 바깥을 바꾼다 — RebirthService 상단).
do
	local touched: { [string]: boolean } = {}
	local fake = setmetatable({}, {
		__index = function(_t, key: string)
			touched[key] = true
			if key == "getBlox" then
				return function()
					return BigNum.fromNumber(2500)
				end
			elseif key == "addRebirths" then
				return function()
					return true, BigNum.fromNumber(2)
				end
			elseif key == "onRebirth" then
				return function()
					return 16
				end
			end
			return function()
				return true
			end
		end,
	})
	local ok = RebirthService._pure.runRebirth(fake :: any, fakePlayer, "test")
	local upgradeTouched = false
	local names = {}
	for key in pairs(touched) do
		-- getRebirthMult는 2배 환생 배수를 읽기만 한다(지시서 #16 S6) — 초기화 대상이 아니라 따로 센다
		if key ~= "getRebirthMult" then
			table.insert(names, key)
		end
		if string.find(string.lower(key), "upgrade", 1, true) then
			upgradeTouched = true
		end
	end
	table.sort(names)
	check("환생: 성공 경로를 끝까지 탔다", ok == true)
	check("환생: 업그레이드를 바꾸는 통로를 하나도 부르지 않는다(유지)", not upgradeTouched, table.concat(names, ","))
	check("환생 화면 문구와 맞출 원본: 초기화 대상 deps가 10개 그대로", #names == 10, table.concat(names, ","))
	check("환생: 2배 환생 배수를 읽는다(읽기만 — 지시서 #16 S6)", touched.getRebirthMult == true)
end

print(string.format("[UpgradeServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[UpgradeServiceTests] %d test(s) failed", failed))
end

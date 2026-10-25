--!strict
-- 운동기구 검증: GymConfig(조건·배수·가격) / GymLayout(좌표·발판 판정) / GymService.resolve(배수 결정).
-- Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ⚠️ 설정 숫자를 리터럴로 적지 않는다. 기대값은 Config에서 다시 유도한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local ClickPadConfig = require(ReplicatedStorage.Shared.Config.ClickPadConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local GymService = require(ServerScriptService.Server.Systems.GymService)

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

local COUNT = GymConfig.getCount()
local REBIRTH_COUNT = GymConfig.getRebirthTierCount()
local VOID = GymConfig.findByGamepass("voidTrainingZone")
local resolve = GymService._pure.resolve

-- 1. GymConfig ---------------------------------------------------------------------------
check("GymConfig.validate", pcall(GymConfig.validate))
check("기구가 1개 이상", COUNT >= 1)

do
	local increasing = true
	for i = 2, REBIRTH_COUNT do
		if not BigNum.gt(GymConfig.getUnlockRebirths(i), GymConfig.getUnlockRebirths(i - 1)) then
			increasing = false
		end
	end
	check("환생 조건이 기구마다 순증가", increasing)

	local stronger = true
	for i = 2, COUNT do
		if not (GymConfig.getMultiplier(i) > GymConfig.getMultiplier(i - 1)
			and GymConfig.getRobuxPrice(i) > GymConfig.getRobuxPrice(i - 1)) then
			stronger = false
		end
	end
	check("배수·가격이 기구마다 순증가 (로벅스 전용 포함)", stronger)
end

-- 1b. 공허 훈련 구역 (로벅스 전용, 사람 결정 2026-10-21) -------------------------------------
check("공허 훈련 구역이 기구 목록에 있음", VOID ~= nil)
if VOID ~= nil then
	check("공허 훈련 구역은 맨 끝 기구", VOID == COUNT)
	check("공허 훈련 구역은 로벅스 전용", GymConfig.isRobuxOnly(VOID))
	check("환생 기구는 로벅스 전용이 아님", not GymConfig.isRobuxOnly(1) and not GymConfig.isRobuxOnly(REBIRTH_COUNT))
	check("환생 기구 수 = 공허 앞 기구 수", REBIRTH_COUNT == VOID - 1)
	check("공허 가격 = ShopConfig 게임패스 가격",
		GymConfig.getRobuxPrice(VOID) == (ShopConfig.get("voidTrainingZone") :: any).priceRobux)
	check("환생 기구 선해금 가격 = ShopConfig gymUnlock1 ~ 8(29 ~ 449, 지시서 #16 — 원본 한 곳)", (function()
		for i = 1, REBIRTH_COUNT do
			local def = ShopConfig.get("gymUnlock" .. i) :: any
			if GymConfig.getShopKey(i) ~= "gymUnlock" .. i or GymConfig.getRobuxPrice(i) ~= def.priceRobux then
				return false
			end
		end
		return GymConfig.getRobuxPrice(1) == 29 and GymConfig.getRobuxPrice(REBIRTH_COUNT) == 449 and GymConfig.getShopKey(VOID) == "voidTrainingZone"
	end)())
	local mostExpensive = true
	local strongest = true
	for i = 1, COUNT do
		if i ~= VOID then
			if GymConfig.getRobuxPrice(i) >= GymConfig.getRobuxPrice(VOID) then mostExpensive = false end
			if GymConfig.getMultiplier(i) >= GymConfig.getMultiplier(VOID) then strongest = false end
		end
	end
	check("공허가 가장 비싸다", mostExpensive)
	check("공허가 가장 센 배수", strongest)
	check("공허는 환생 조건이 없다 (getUnlockRebirths 에러)", not pcall(GymConfig.getUnlockRebirths, VOID))
	check("환생 수가 아주 커도 공허는 환생으로 안 열림", not GymConfig.isUnlockedByRebirths(VOID, BigNum.new(1, 300)))
end

check("환생 0이면 열린 기구 0개", GymConfig.getUnlockedCount(BigNum.new(0, 0)) == 0)
do
	local first = GymConfig.getUnlockRebirths(1)
	check("기구 1 조건 딱 맞추면 1개", GymConfig.getUnlockedCount(first) == 1)
	local justUnder = BigNum.mul(first, BigNum.new(9.9, -1))
	check("기구 1 조건의 99%면 0개", GymConfig.getUnlockedCount(justUnder) == 0)
	local last = GymConfig.getUnlockRebirths(REBIRTH_COUNT)
	check("마지막 환생 기구 조건이면 환생 기구 전부 열림", GymConfig.getUnlockedCount(last) == REBIRTH_COUNT)
	check("환생 수가 아주 커도 열린 수는 환생 기구 수까지", GymConfig.getUnlockedCount(BigNum.new(1, 300)) == REBIRTH_COUNT)
	check("isUnlockedByRebirths: 조건 이상 true", GymConfig.isUnlockedByRebirths(1, first))
	check("isUnlockedByRebirths: 미만 false", not GymConfig.isUnlockedByRebirths(1, justUnder))
end

do
	local v = GymConfig.getUnlockRebirths(1)
	v.m = 9
	check("getUnlockRebirths는 복사본 (고쳐도 Config 불변)", GymConfig.getUnlockRebirths(1).m ~= 9)
	check("범위 밖 인덱스는 에러", not pcall(GymConfig.getMultiplier, 0) and not pcall(GymConfig.getMultiplier, COUNT + 1))
end

-- 2. GymLayout ---------------------------------------------------------------------------
local positions = GymLayout.computeLayout(COUNT)
check("좌표 개수 = 기구 수", #positions == COUNT)

do
	local half = GymLayout.SIZE / 2
	local inSpawn = true
	local beforeGate = true
	for _, p in ipairs(positions) do
		if p.X - half.X < ArenaConfig.SPAWN_ZONE_X_MIN or p.X + half.X > ArenaConfig.SPAWN_ZONE_X_MAX
			or math.abs(p.Z) + half.Z > ArenaConfig.SPAWN_ZONE_Z_HALF then
			inSpawn = false
		end
		-- 입장 게이트 너머(챌린지 구간)에 걸치면 런 중 클릭에 배수가 붙는다.
		if p.X + half.X >= ArenaConfig.getEntranceX() then
			beforeGate = false
		end
	end
	check("기구가 전부 스폰 구역 안", inSpawn)
	check("기구가 전부 입장 게이트 앞 (런 중에는 기구에 못 선다)", beforeGate)
end

do
	-- 패드와 겹치면 한 자리에서 패드 밟기와 기구 판정이 섞인다.
	local pads = PadLayout.computeLayout(ClickPadConfig.getSet(1).count)
	local apart = true
	local needZ = GymLayout.SIZE.Z / 2 + PadLayout.PAD_SIZE.Z / 2
	for _, g in ipairs(positions) do
		for _, pad in ipairs(pads) do
			if math.abs(g.Z - pad.Z) < needZ and math.abs(g.X - pad.X) < GymLayout.SIZE.X / 2 + PadLayout.PAD_SIZE.X / 2 then
				apart = false
			end
		end
	end
	check("기구와 패드가 겹치지 않음", apart)

	-- 2줄 격자라 이웃 번호가 같은 X일 수 있다(지시서 #8 M1) — 모든 쌍을 X · Z 둘 다로 본다.
	local separated = true
	for i = 1, #positions do
		for j = i + 1, #positions do
			if math.abs(positions[i].X - positions[j].X) < GymLayout.SIZE.X and math.abs(positions[i].Z - positions[j].Z) < GymLayout.SIZE.Z then
				separated = false
			end
		end
	end
	check("기구끼리 겹치지 않음", separated)

	-- M1: 통로 밖 · 패드 반대쪽(+Z) · 공허(맨 끝 번호)가 게이트 쪽 맨 끝 열
	local clearOfPath, oppositeSide = true, true
	local maxX = -math.huge
	for _, p in ipairs(positions) do
		if math.abs(p.Z) - GymLayout.SIZE.Z / 2 < 24 then
			clearOfPath = false
		end
		if p.Z <= 0 then
			oppositeSide = false
		end
		maxX = math.max(maxX, p.X)
	end
	check("M1: 기구가 가운데 통로 밖", clearOfPath)
	check("M1: 기구가 패드 반대쪽(+Z)", oppositeSide and pads[1].Z < 0)
	check("M1: 맨 끝 번호(공허)가 게이트 쪽 맨 끝 열", positions[#positions].X == maxX)
	check("M1: 기구 2줄", GymLayout.ROWS == 2 and #positions >= 2 and positions[1].X == positions[2].X and positions[1].Z ~= positions[2].Z)
end

do
	local c = positions[1]
	local standing = Vector3.new(c.X, c.Y + 3, c.Z) -- 서 있는 HumanoidRootPart 높이 근처
	check("발판 가운데 위에 서면 기구 1", GymLayout.findAt(standing, COUNT) == 1)
	check("발판 가장자리 안쪽도 기구 1", GymLayout.findAt(standing + Vector3.new(GymLayout.SIZE.X / 2 - 0.1, 0, 0), COUNT) == 1)
	check("발판 바로 밖은 nil", GymLayout.findAt(standing + Vector3.new(GymLayout.SIZE.X / 2 + 0.1, 0, 0), COUNT) == nil)
	check("너무 높으면 nil", GymLayout.findAt(Vector3.new(c.X, c.Y + GymLayout.STAND_HEIGHT + 1, c.Z), COUNT) == nil)
	check("스폰 지점은 어느 기구 위도 아님", GymLayout.findAt(Vector3.new(ArenaConfig.SPAWN_X, 3, 0), COUNT) == nil)
	if COUNT >= 2 then
		local c2 = positions[2]
		check("두 번째 발판 위면 기구 2", GymLayout.findAt(Vector3.new(c2.X, c2.Y + 3, c2.Z), COUNT) == 2)
	end
end

-- 3. GymService.resolve ------------------------------------------------------------------
do
	local c = positions[1]
	local onGym1 = Vector3.new(c.X, c.Y + 3, c.Z)
	local unlock1 = GymConfig.getUnlockRebirths(1)

	local none = resolve(nil, unlock1)
	check("캐릭터 없음 → 배수 1", none.multiplier == 1 and none.index == nil)

	local off = resolve(Vector3.new(ArenaConfig.SPAWN_X, 3, 0), unlock1)
	check("기구 밖 → 배수 1", off.multiplier == 1 and off.index == nil)

	local locked = resolve(onGym1, BigNum.new(0, 0))
	check("잠긴 기구 위 → 배수 1, 기구 번호는 알려줌", locked.multiplier == 1 and locked.index == 1 and locked.unlocked == false)

	local open = resolve(onGym1, unlock1)
	check("열린 기구 위 → 그 기구 배수", open.multiplier == GymConfig.getMultiplier(1) and open.unlocked == true)

	local noRebirths = resolve(onGym1, nil)
	check("환생 수 없음(nil) → 0으로 보고 잠김", noRebirths.multiplier == 1 and noRebirths.unlocked == false)

	if COUNT >= 2 then
		local c2 = positions[2]
		local onGym2 = Vector3.new(c2.X, c2.Y + 3, c2.Z)
		local onlyFirst = resolve(onGym2, unlock1)
		check("기구 1만 열린 상태로 기구 2 위 → 배수 1 (높은 기구는 따로 열어야 한다)", onlyFirst.multiplier == 1 and onlyFirst.index == 2)
	end

	if VOID ~= nil then
		-- Phase 8 전에는 게임패스 소유 확인이 없다 — 누구도 공허 배수를 받지 못한다.
		local cv = positions[VOID]
		local onVoid = Vector3.new(cv.X, cv.Y + 3, cv.Z)
		local v = resolve(onVoid, BigNum.new(1, 300))
		check("공허 위 + 환생 아주 많음 → 배수 1, 기구 번호는 공허", v.multiplier == 1 and v.index == VOID and v.unlocked == false)
	end
end

print(string.format("[GymServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[GymServiceTests] %d test(s) failed", failed))
end

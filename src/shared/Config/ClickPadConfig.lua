--!strict
-- 클릭 파워 패드의 파워 / 해금 조건 계산. 값을 저장하지 않고 WorldConfig.clickPadSet의
-- 성장식으로 매번 계산한다 (StageConfig가 HP·보상에 하는 것과 같은 패턴 — WorldConfig는
-- 데이터, 계산은 별도 모듈).
--
-- 패드는 스테이지 축이 아니라 월드 축이다. 스테이지를 오르내려도 패드 구성은 그대로고,
-- 월드가 바뀔 때만 세트가 통째로 갈린다. 그래서 StageConfig에 넣지 않고 모듈을 나눴다.
--
-- 해금 조건의 기준은 lifetimeBlox(누적 획득량)다. 현재 보유량이 아니다 — 보유량 기준이면
-- 상점에서 쓰는 순간 이미 밟던 패드가 잠기기 때문이다.

local BigNum = require(script.Parent.Parent.BigNum)
local WorldConfig = require(script.Parent.WorldConfig)

type BigNumber = BigNum.BigNumber
type WorldDef = WorldConfig.WorldDef
type ClickPadSet = WorldConfig.ClickPadSet

local ClickPadConfig = {}

local ZERO = BigNum.new(0, 0)

local function getWorld(worldId: number): WorldDef
	local world = WorldConfig.get(worldId)
	assert(world ~= nil, string.format("ClickPadConfig: 월드 %d가 없음", worldId))
	return world :: WorldDef
end

-- 인덱스는 1..count. 범위를 벗어난 조회는 설정/호출 오류이므로 조용히 0을 주지 않고 터뜨린다.
local function assertIndex(worldId: number, set: ClickPadSet, index: number)
	assert(
		type(index) == "number" and index % 1 == 0,
		string.format("ClickPadConfig: 월드 %d의 패드 인덱스(%s)는 정수여야 함", worldId, tostring(index))
	)
	assert(
		index >= 1 and index <= set.count,
		string.format("ClickPadConfig: 월드 %d의 패드 인덱스(%d)가 범위(1..%d)를 벗어남", worldId, index, set.count)
	)
end

function ClickPadConfig.getSet(worldId: number): ClickPadSet
	return getWorld(worldId).clickPadSet
end

-- 패드 index를 밟는 동안의 클릭 파워 = basePower × powerGrowth^(index-1).
-- 패드 1이 basePower 그대로이므로 지수는 index가 아니라 index-1이다.
function ClickPadConfig.getPadPower(worldId: number, index: number): BigNumber
	local set = ClickPadConfig.getSet(worldId)
	assertIndex(worldId, set, index)

	return BigNum.mul(set.basePower, BigNum.pow(BigNum.fromNumber(set.powerGrowth), index - 1))
end

-- 패드 index를 해금하는 데 필요한 lifetimeBlox.
--   index == 1 : 0 (시작 패드. 조건 없음)
--   index >= 2 : bloxBase × unlockMultiplier × unlockGrowth^(index-2)
--
-- ⚠️ bloxBase에서 유도하는 것이 핵심이다. 절대값으로 박으면 bloxBase를 튜닝하는 순간
-- (4-2-f) 패드 곡선만 옛 기준에 남아 조용히 어긋난다. 근거는 WorldConfig.ClickPadSet 주석.
-- 지수가 index-2인 이유: 배수(unlockMultiplier)가 적용되는 첫 패드가 2번이므로,
-- 2번에서 growth가 0제곱(=1)이어야 조건이 정확히 bloxBase × unlockMultiplier가 된다.
function ClickPadConfig.getPadUnlock(worldId: number, index: number): BigNumber
	local world = getWorld(worldId)
	local set = world.clickPadSet
	assertIndex(worldId, set, index)

	if index == 1 then
		return ZERO
	end

	local base = BigNum.mul(world.bloxBase, BigNum.fromNumber(set.unlockMultiplier))
	return BigNum.mul(base, BigNum.pow(BigNum.fromNumber(set.unlockGrowth), index - 2))
end

-- 조건을 만족하는 가장 높은 패드 인덱스. 패드 1은 조건이 0이라 항상 열려 있으므로 최소 1.
-- 조건이 인덱스에 대해 순증가하는 것은 validate()가 보장하므로, 처음 막히는 지점에서 끊는다.
function ClickPadConfig.getUnlockedPadCount(worldId: number, lifetimeBlox: BigNumber): number
	local set = ClickPadConfig.getSet(worldId)

	local unlocked = 1
	for index = 2, set.count do
		if not BigNum.gte(lifetimeBlox, ClickPadConfig.getPadUnlock(worldId, index)) then
			break
		end
		unlocked = index
	end

	return unlocked
end

function ClickPadConfig.isUnlocked(worldId: number, index: number, lifetimeBlox: BigNumber): boolean
	local set = ClickPadConfig.getSet(worldId)
	assertIndex(worldId, set, index)

	return BigNum.gte(lifetimeBlox, ClickPadConfig.getPadUnlock(worldId, index))
end

function ClickPadConfig.validate(): boolean
	for worldId, world in pairs(WorldConfig.Worlds) do
		local set = world.clickPadSet

		-- 범위 밖 인덱스는 반드시 거부되어야 한다. 조용히 0이나 nil이 나오면 PadService가
		-- 파워 0짜리 패드를 세우고도 모르게 된다.
		assert(
			not pcall(ClickPadConfig.getPadPower, worldId, 0),
			string.format("ClickPadConfig: 월드 %d에서 인덱스 0이 거부되지 않음", worldId)
		)
		assert(
			not pcall(ClickPadConfig.getPadPower, worldId, set.count + 1),
			string.format("ClickPadConfig: 월드 %d에서 인덱스 %d(범위 초과)가 거부되지 않음", worldId, set.count + 1)
		)

		assert(
			BigNum.eq(ClickPadConfig.getPadUnlock(worldId, 1), ZERO),
			string.format("ClickPadConfig: 월드 %d의 패드 1 조건이 0이 아님", worldId)
		)

		local prevPower: BigNumber? = nil
		local prevUnlock: BigNumber? = nil
		for index = 1, set.count do
			local power = ClickPadConfig.getPadPower(worldId, index)
			assert(
				BigNum.gt(power, ZERO),
				string.format("ClickPadConfig: 월드 %d 패드 %d의 파워가 0 이하", worldId, index)
			)
			if prevPower ~= nil then
				assert(
					BigNum.gt(power, prevPower),
					string.format("ClickPadConfig: 월드 %d 패드 %d의 파워가 이전 패드보다 크지 않음", worldId, index)
				)
			end
			prevPower = power

			local unlock = ClickPadConfig.getPadUnlock(worldId, index)
			if prevUnlock ~= nil then
				assert(
					BigNum.gt(unlock, prevUnlock),
					string.format("ClickPadConfig: 월드 %d 패드 %d의 해금 조건이 이전 패드보다 크지 않음", worldId, index)
				)
			end
			prevUnlock = unlock
		end
	end

	return true
end

return ClickPadConfig

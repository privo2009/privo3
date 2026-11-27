--!strict
-- 아레나 · 로비 배율(지시서 #46 1부). Shared/Config/ArenaScale · ArenaConfig.layoutAt.
-- 잰다: 배율 1.0 = #45까지의 배치(숫자 하나도 안 바뀜) · 지금 값 = layoutAt(지금 배율)(블록 · 반경 · 패드 · 기구 · 대장간 · 줍기 · 봇) ·
-- 로비 물체 수 = 게임 · 지금 배율과 후보 배율마다 배치 관계(블록이 스테이지 안 · 입구가 반경 안 · 벽이 반경 밖 · 통로 · 로비 안 겹침) ·
-- 블록이 캐릭터보다 충분히 큼.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaScale = require(ReplicatedStorage.Shared.Config.ArenaScale)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local AttackConfig = require(ReplicatedStorage.Shared.Config.AttackConfig)
local AutoplayConfig = require(ReplicatedStorage.Shared.Config.AutoplayConfig)
local BlockLayoutConfig = require(ReplicatedStorage.Shared.Config.BlockLayoutConfig)
local EconomyV2Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

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

-- 기대표와 실제를 견주어 어긋난 항목 목록(빈 문자열이면 전부 같다). 1e-9 안이면 같다고 본다(반경처럼 소수 배율이 든 값)
local function diff(expected: { [string]: number }, actual: { [string]: any }): string
	local bad = {}
	local keys = {}
	for k in pairs(expected) do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local a = actual[k]
		if type(a) ~= "number" or math.abs(a - expected[k]) > 1e-9 then
			table.insert(bad, string.format("%s %s ≠ %s", k, tostring(a), tostring(expected[k])))
		end
	end
	return table.concat(bad, " · ")
end

-- 1. 배율 자체
check("배율: 0 초과 1 이하 · validate 통과 · 후보도 범위 안", (function()
	local ok = pcall(ArenaScale.validate)
	for _, s in ipairs(ArenaScale.CANDIDATES) do
		ok = ok and s > 0 and s <= 1
	end
	return ok and ArenaScale.ARENA_SCALE > 0 and ArenaScale.ARENA_SCALE <= 1
end)())

-- 2. 배율 1.0 = 옛 배치(#45까지의 숫자 — 1부에서 배율을 넣기 전 값을 그대로 적었다. 줄인 뒤에도 이 줄은 그대로 맞아야 한다)
do
	local L = ArenaConfig.layoutAt(1.0)
	local d = diff({
		blockSpan = 16,
		stageWidth = 148,
		gapWidth = 24,
		entranceX = -74,
		spawnX = -200,
		spawnZoneXMin = -260,
		spawnZoneXMax = -54,
		spawnZoneZHalf = 120,
		challengeZHalf = 100,
		padPitch = 12,
		padRowPitch = 12,
		padLaneZ = -36,
		padFirstX = -220,
		padLastX = -88,
		gymPitch = 24,
		gymRowPitch = 24,
		gymLaneZ = 40,
		gymFirstX = -192,
		gymLastX = -96,
		forgeX = -235,
		forgeZ = -60,
		pickupRadius = 12,
		dropScatter = 2.5,
		radius = 92.8,
		clusterFace = 68.8,
	}, L :: any)
	check("배율 1.0 = 옛 배치(스테이지 148 · 띠 24 · 스폰 -200 · 패드 -220 · 기구 -192 · 대장간 (-235, -60) · 반경 92.8 …)",
		d == "" and BlockLayoutConfig.cubeSizeAt(1.0) == 4, d)
end

-- 3. 지금 값 = layoutAt(지금 배율) — 파트를 놓는 모듈이 모두 같은 표를 읽는가
do
	local L = ArenaConfig.LIVE
	local d = diff({
		stageWidth = ArenaConfig.STAGE_WIDTH,
		gapWidth = ArenaConfig.GAP_WIDTH,
		spawnX = ArenaConfig.SPAWN_X,
		spawnZoneXMin = ArenaConfig.SPAWN_ZONE_X_MIN,
		spawnZoneXMax = ArenaConfig.SPAWN_ZONE_X_MAX,
		spawnZoneZHalf = ArenaConfig.SPAWN_ZONE_Z_HALF,
		challengeZHalf = ArenaConfig.CHALLENGE_ZONE_Z_HALF,
		entranceX = ArenaConfig.getEntranceX(),
		blockSpan = BlockLayoutConfig.BLOCK_SPAN,
		radius = AttackConfig.getRadius(),
		clusterFace = AttackConfig.getArenaRadius(),
		padPitch = PadLayout.PITCH,
		padRowPitch = PadLayout.ROW_PITCH,
		padLaneZ = PadLayout.LANE_Z,
		gymPitch = GymLayout.PITCH,
		gymRowPitch = GymLayout.ROW_PITCH,
		gymLaneZ = GymLayout.LANE_Z,
		forgeX = EconomyV2Config.FORGE_SITE.position.X,
		forgeZ = EconomyV2Config.FORGE_SITE.position.Z,
		pickupRadius = EconomyV2Config.PICKUP_RADIUS,
		dropScatter = EconomyV2Config.DROP_SCATTER,
	}, L :: any)
	check("지금 값 = layoutAt(지금 배율) — ArenaConfig · 블록 · 반경 · 패드 · 기구 · 대장간 · 줍기 · 흩어짐", d == ""
		and L.scale == ArenaScale.ARENA_SCALE and BlockLayoutConfig.CUBE_SIZE == BlockLayoutConfig.cubeSizeAt(ArenaScale.ARENA_SCALE), d)
	local pads = PadLayout.computeLayout(ArenaConfig.LOBBY_PAD_COUNT)
	local gyms = GymLayout.computeLayout(ArenaConfig.LOBBY_GYM_COUNT)
	local lastGym = gyms[(math.ceil(#gyms / GymLayout.ROWS) - 1) * GymLayout.ROWS + 1]
	check("실제 좌표: 패드 첫 · 마지막 열 · 기구 첫 · 마지막 열 · 안쪽 줄 Z = 배치표", math.abs(pads[1].X - L.padFirstX) < 1e-6
		and math.abs(pads[#pads].X - L.padLastX) < 1e-6 and math.abs(pads[1].Z - L.padLaneZ) < 1e-6
		and math.abs(gyms[1].X - L.gymFirstX) < 1e-6 and math.abs(lastGym.X - L.gymLastX) < 1e-6 and math.abs(gyms[1].Z - L.gymLaneZ) < 1e-6,
		string.format("패드 %.3f..%.3f · 기구 %.3f..%.3f", pads[1].X, pads[#pads].X, gyms[1].X, lastGym.X))
	check("봇 실패 줄 = 반경과 통로 끝 가운데(배율을 따른다)", math.abs(AutoplayConfig.FAIL_STAND_Z - (L.radius + L.challengeZHalf) / 2) < 1e-9)
end

-- 4. 로비 물체 수 · 크기 = 게임
check("로비 물체 = 게임(패드 수 = 월드 1 패드 세트 · 기구 수 = GymConfig · 줄 수 · 크기 = PadLayout · GymLayout)",
	ArenaConfig.LOBBY_PAD_COUNT == (WorldConfig.get(1) :: any).clickPadSet.count and ArenaConfig.LOBBY_GYM_COUNT == GymConfig.getCount()
	and ArenaConfig.LOBBY_PAD_ROWS == PadLayout.ROWS and ArenaConfig.LOBBY_GYM_ROWS == GymLayout.ROWS
	and PadLayout.PAD_SIZE.X == ArenaConfig.LOBBY_PAD_SIZE and GymLayout.SIZE.X == ArenaConfig.LOBBY_GYM_SIZE
	and EconomyV2Config.FORGE_SITE.size == ArenaConfig.FORGE_SIZE)

-- 5. 배치 관계 — 지금 배율과 후보 배율마다(요소 수만큼 늘지 않게 배율별 어긋남을 한 줄로 모은다)
local scales = { ArenaScale.ARENA_SCALE }
for _, s in ipairs(ArenaScale.CANDIDATES) do
	table.insert(scales, s)
end

local function rect(cx: number, cz: number, sx: number, sz: number): { number }
	return { cx - sx / 2, cx + sx / 2, cz - sz / 2, cz + sz / 2 }
end
local function overlap(a: { number }, b: { number }): boolean
	return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4]
end

local function relationProblems(L: ArenaConfig.Layout): { string }
	local bad = {}
	local wallHalf = ArenaConfig.ADVANCE_WALL_DEPTH / 2
	local half = L.stageWidth / 2
	-- 스테이지: 블록 바깥면 + 벽 깊이 절반이 스테이지 안 · 입구(시작 면)가 판정 반경 안 · 진행 벽 가까운 면이 반경 밖
	if half < L.clusterFace + wallHalf then
		table.insert(bad, "블록이 스테이지 밖")
	end
	if not (L.radius > half) then
		table.insert(bad, "입구가 반경 밖")
	end
	if not (half + L.gapWidth - wallHalf > L.radius) then
		table.insert(bad, "진행 벽이 반경 안")
	end
	-- 통로: 블록 · 수령 발판 바깥이 통로 안 · 스폰 구역이 통로보다 넓다
	local padOuter = ArenaConfig.CASHOUT_LATERAL_OFFSET + ArenaConfig.CASHOUT_PAD_SIZE.Z / 2
	if not (L.challengeZHalf > L.clusterFace and L.challengeZHalf > padOuter and L.spawnZoneZHalf >= L.challengeZHalf) then
		table.insert(bad, "통로 폭")
	end
	-- 로비: 스폰 · 패드 · 기구 · 대장간이 서로 안 겹치고 · 스폰 구역 안 · 입구 앞 · 통로(Z 0) 비움
	local items: { { number } } = {}
	local spawnHalf = 4 -- ArenaService SPAWN_SIZE 8
	table.insert(items, rect(L.spawnX, 0, spawnHalf * 2, spawnHalf * 2))
	local padSize = ArenaConfig.LOBBY_PAD_SIZE
	local columns = math.ceil(ArenaConfig.LOBBY_PAD_COUNT / ArenaConfig.LOBBY_PAD_ROWS)
	for c = 1, columns do
		for r = 0, ArenaConfig.LOBBY_PAD_ROWS - 1 do
			table.insert(items, rect(L.padFirstX + (c - 1) * L.padPitch, L.padLaneZ - r * L.padRowPitch, padSize, padSize))
		end
	end
	local gymSize = ArenaConfig.LOBBY_GYM_SIZE
	for i = 1, ArenaConfig.LOBBY_GYM_COUNT do
		local c = math.ceil(i / ArenaConfig.LOBBY_GYM_ROWS)
		local r = (i - 1) % ArenaConfig.LOBBY_GYM_ROWS
		table.insert(items, rect(L.gymFirstX + (c - 1) * L.gymPitch, L.gymLaneZ + r * L.gymRowPitch, gymSize, gymSize))
	end
	table.insert(items, rect(L.forgeX, L.forgeZ, ArenaConfig.FORGE_SIZE.X, ArenaConfig.FORGE_SIZE.Z))
	local overlaps, outside, pastGate, inCorridor = 0, 0, 0, 0
	for i, a in ipairs(items) do
		for j = i + 1, #items do
			if overlap(a, items[j]) then
				overlaps += 1
			end
		end
		if a[1] < L.spawnZoneXMin or a[2] > L.spawnZoneXMax or a[3] < -L.spawnZoneZHalf or a[4] > L.spawnZoneZHalf then
			outside += 1
		end
		if a[2] > L.entranceX - ArenaConfig.ADVANCE_WALL_DEPTH / 2 then
			pastGate += 1
		end
		if i > 1 and a[3] < spawnHalf * 2 and a[4] > -spawnHalf * 2 then
			inCorridor += 1 -- 통로(스폰 발판 폭의 두 배) 안에 물체
		end
	end
	if overlaps + outside + pastGate + inCorridor > 0 then
		table.insert(bad, string.format("로비 겹침 %d · 구역 밖 %d · 게이트 넘음 %d · 통로 위 %d", overlaps, outside, pastGate, inCorridor))
	end
	if not (L.spawnX > L.spawnZoneXMin and L.spawnX < L.entranceX) then
		table.insert(bad, "스폰이 구역 밖 · 입구 너머")
	end
	return bad
end

check("배치 관계: 지금 배율 · 후보 0.4 ~ 0.7마다 블록 · 입구 · 진행 벽 · 통로 · 로비(겹침 · 구역 · 게이트 · 통로) 전부", (function()
	local all = {}
	for _, s in ipairs(scales) do
		local bad = relationProblems(ArenaConfig.layoutAt(s))
		if #bad > 0 then
			table.insert(all, string.format("%.2f: %s", s, table.concat(bad, ", ")))
		end
	end
	return #all == 0, table.concat(all, " / ")
end)())

-- 6. 걷는 길이가 배율을 따라 줄어든다(이동 속도는 그대로 — 걷는 시간이 이 비율로 준다)
check("걷는 길이: 배율이 작을수록 층 주기 · 스폰 → 입구가 짧다(1.0보다 짧고 후보끼리 차례)", (function()
	local prevPitch, prevSpawn = math.huge, math.huge
	local sorted = table.clone(ArenaScale.CANDIDATES)
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local base = ArenaConfig.layoutAt(1.0)
	prevPitch, prevSpawn = base.stageWidth + base.gapWidth, base.entranceX - base.spawnX
	for _, s in ipairs(sorted) do
		local L = ArenaConfig.layoutAt(s)
		local pitch, spawn = L.stageWidth + L.gapWidth, L.entranceX - L.spawnX
		if not (pitch < prevPitch and spawn < prevSpawn) then
			return false
		end
		prevPitch, prevSpawn = pitch, spawn
	end
	return true
end)())

-- 7. 블록이 캐릭터보다 충분히 크다(지금 배율 — 고르는 기준 2)
check("블록 한 변 ≥ 캐릭터 키 × MIN_BLOCK_TO_CHARACTER(지금 배율)",
	BlockLayoutConfig.BLOCK_SPAN >= ArenaScale.CHARACTER_HEIGHT * ArenaScale.MIN_BLOCK_TO_CHARACTER,
	string.format("블록 %.2f · 캐릭터 %.1f × %.2f", BlockLayoutConfig.BLOCK_SPAN, ArenaScale.CHARACTER_HEIGHT, ArenaScale.MIN_BLOCK_TO_CHARACTER))

print(string.format("[ArenaScaleTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ArenaScaleTests] %d test(s) failed", failed))
end

--!strict
-- 근처 확인 검증 (지시서 #23 N1 ~ N3 — DESIGN.md 13장).
--   근처 · 멀리 · 경계 · 캐릭터 없음 · 루트 없음 · 회전된 파트 · 여유 식(ProximityConfig) ·
--   최고 속도에서 프레임당 이동 거리를 감안한 여유 근거 · 실제 파트 크기(수령 발판 · 진행 벽 · 패드 · 게이트)에서 정상 위치 통과
--
-- ⚠️ 수치를 리터럴로 적지 않는다 — ProximityConfig · LevelConfig · ArenaConfig · PadLayout에서 읽는다.
-- 파트 · 캐릭터는 Workspace에 넣지 않는다(Parent 없음 — Touched도 물리도 없다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProximityConfig = require(ReplicatedStorage.Shared.Config.ProximityConfig)
local LevelConfig = require(ReplicatedStorage.Shared.Config.LevelConfig)
local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local PadLayout = require(ReplicatedStorage.Shared.PadLayout)
local Proximity = require(ServerScriptService.Server.Systems.Proximity)

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

local M = ProximityConfig.PROXIMITY_MARGIN
local MAX_SPEED = LevelConfig.getMaxWalkSpeed()

-- 1. 여유 식 · 근거 ----------------------------------------------------------------------------------------
check("여유 = REACH + 최고 속도 × LAG", math.abs(M - (ProximityConfig.REACH_STUDS + MAX_SPEED * ProximityConfig.LAG_SEC)) < 1e-9, tostring(M))
check("validate 통과", pcall(ProximityConfig.validate))
do
	-- 프레임 드랍 근거: 기준 fps(REFERENCE_FPS)의 한 프레임 이동이 여유 안에 여러 번 들어간다
	local perFrame = MAX_SPEED / LevelConfig.REFERENCE_FPS
	local framesCovered = (M - ProximityConfig.REACH_STUDS) / perFrame
	check("최고 속도 한 프레임(" .. string.format("%.2f", perFrame) .. " studs)을 MIN_FRAMES_ON_PART의 2배 이상 덮는다",
		framesCovered >= LevelConfig.MIN_FRAMES_ON_PART * 2, string.format("%.1f프레임", framesCovered))
	-- 심한 드랍(10fps) 한 프레임 이동 + 팔다리 거리도 여유 안
	check("10fps 한 프레임 이동 + REACH ≤ 여유", MAX_SPEED / 10 + ProximityConfig.REACH_STUDS <= M)
end

-- 2. 순수 판정 — 근처 · 멀리 · 경계 · 루트 없음 -----------------------------------------------------------------
local size = Vector3.new(12, 1, 12)
local cf = CFrame.new(100, 0.5, 20)
local function at(dx: number, dy: number, dz: number): Vector3
	return cf.Position + Vector3.new(dx, dy, dz)
end
check("근처: 파트 위 가운데(루트는 발판 위 3)", Proximity.isNear(at(0, 3, 0), cf, size, M))
check("근처: 가장자리 밖 여유 안(X)", Proximity.isNear(at(size.X / 2 + M - 0.5, 3, 0), cf, size, M))
check("경계: 정확히 반 + 여유는 근처", Proximity.isNear(at(size.X / 2 + M, 0, 0), cf, size, M))
do
	local ok, why = Proximity.isNear(at(size.X / 2 + M + 0.01, 0, 0), cf, size, M)
	check("경계: 반 + 여유를 조금 넘으면 far", not ok and why == Proximity.REASON_FAR)
	local okZ, whyZ = Proximity.isNear(at(0, 0, -(size.Z / 2 + M + 1)), cf, size, M)
	check("멀리(Z 음수 쪽) → far", not okZ and whyZ == Proximity.REASON_FAR)
	local okY, whyY = Proximity.isNear(at(0, size.Y / 2 + M + 1, 0), cf, size, M)
	check("멀리(위) → far", not okY and whyY == Proximity.REASON_FAR)
	local okFar = Proximity.isNear(at(500, 3, 0), cf, size, M)
	check("멀리(500 studs) → far", not okFar)
	local okNil, whyNil = Proximity.isNear(nil, cf, size, M)
	check("루트 위치 없음 → no_root", not okNil and whyNil == Proximity.REASON_NO_ROOT)
end
do
	-- 회전된 파트: 로컬 좌표로 본다. 90도 돌린 긴 판(40 × 1 × 2)의 긴 축 끝은 근처, 월드 X로는 멀어도
	local long = Vector3.new(40, 1, 2)
	local rotated = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	check("회전: 로컬 긴 축 끝(월드 Z 20)은 근처", Proximity.isNear(Vector3.new(0, 0, 20), rotated, long, M))
	check("회전: 로컬 짧은 축으로 여유 밖(월드 X 1 + M + 1)은 far", not Proximity.isNear(Vector3.new(1 + M + 1, 0, 0), rotated, long, M))
end

-- 3. 플레이어 → 루트 · check ------------------------------------------------------------------------------------
local function newPart(name: string, partSize: Vector3, position: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = partSize
	p.Position = position
	p.Anchored = true
	return p
end
local function newCharacter(rootPosition: Vector3?): Model
	local model = Instance.new("Model")
	if rootPosition ~= nil then
		local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), rootPosition)
		root.Parent = model
	end
	return model
end

do
	local pad = newPart("ProximityTestPad", size, cf.Position)
	local before = Proximity.rejectCount()
	local noChar: any = { Name = "ProxNoChar", UserId = 9101, Character = nil }
	check("캐릭터 없음 → false", not Proximity.check(noChar, pad, "test"))
	local _, why = Proximity.rootPosition(noChar)
	check("캐릭터 없음 → no_character", why == Proximity.REASON_NO_CHARACTER)
	local noRoot: any = { Name = "ProxNoRoot", UserId = 9102, Character = newCharacter(nil) }
	local _, why2 = Proximity.rootPosition(noRoot)
	check("루트 없음 → false · no_root", not Proximity.check(noRoot, pad, "test") and why2 == Proximity.REASON_NO_ROOT)
	local near: any = { Name = "ProxNear", UserId = 9103, Character = newCharacter(at(0, 3, 0)) }
	check("근처 캐릭터 → true", Proximity.check(near, pad, "test"))
	local far: any = { Name = "ProxFar", UserId = 9104, Character = newCharacter(at(300, 3, 0)) }
	check("먼 캐릭터 → false", not Proximity.check(far, pad, "test"))
	check("거부 수: 셋(캐릭터 없음 · 루트 없음 · 멀리)만 센다", Proximity.rejectCount() - before == 3)
	check("여유 인자를 주면 그 값으로 본다(0이면 가장자리 밖 1은 far)",
		not Proximity.check({ Name = "ProxM0", UserId = 9105, Character = newCharacter(at(size.X / 2 + 1, 0, 0)) } :: any, pad, "test", 0))
	pad:Destroy()
end

-- 4. 실제 파트 크기에서 정상 위치는 통과 — 발판 · 패드 위 서 있기 · 벽 트리거를 최고 속도로 지나 한 프레임 뒤 ------------------------
do
	local padSize = ArenaConfig.CASHOUT_PAD_SIZE
	local cashout = CFrame.new(0, padSize.Y / 2, 0)
	-- 발판 모서리 위에 서 있다(루트는 발판 윗면 + 3)
	check("수령 발판 모서리 위 → 근처", Proximity.isNear(Vector3.new(padSize.X / 2, padSize.Y + 3, padSize.Z / 2), cashout, padSize, M))
	local clickPad = PadLayout.PAD_SIZE
	check("클릭 패드 모서리 위 → 근처", Proximity.isNear(Vector3.new(clickPad.X / 2, clickPad.Y + 3, clickPad.Z / 2), CFrame.new(), clickPad, M))
	-- 얇은 트리거(진행 벽 · 게이트처럼 X가 얇다)를 최고 속도로 지나 LAG_SEC 뒤에 서버가 위치를 읽어도 근처
	local thin = Vector3.new(1, 20, 40)
	local passedBy = MAX_SPEED * ProximityConfig.LAG_SEC
	check("얇은 트리거를 최고 속도로 지난 뒤 LAG_SEC 거리 → 근처", Proximity.isNear(Vector3.new(thin.X / 2 + passedBy, 3, 0), CFrame.new(), thin, M))
	check("얇은 트리거에서 스폰 쪽으로 여유 + 10 → far", not Proximity.isNear(Vector3.new(-(thin.X / 2 + M + 10), 3, 0), CFrame.new(), thin, M))
end

print(string.format("[ProximityTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ProximityTests] %d test(s) failed", failed))
end

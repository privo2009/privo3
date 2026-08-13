--!strict
-- 파편 오브젝트 풀. CLAUDE.md 규칙 4 적용 대상:
--   - 파편은 클라 전용 (이 모듈은 src/client 밑에만 있고 서버는 절대 require 안 함)
--   - 물리 금지 — 풀에 있는 파츠는 항상 Anchored = true
--   - 동시 파편 상한 200개
--   - 반복 루프에서 Instance.new 금지 — 모듈 로드 시 POOL_SIZE개를 딱 한 번만 만들고,
--     그 이후로는 acquire()/release()로 재사용만 한다
--
-- 사용법: local fragment = ParticlePool.acquire(); if fragment then ... ParticlePool.release(fragment) end

local Workspace = game:GetService("Workspace")

local ParticlePool = {}

local POOL_SIZE = 200
local POOL_FOLDER_NAME = "ParticlePool"
local PARKED_POSITION = Vector3.new(0, -1000, 0) -- 안 쓰는 조각을 치워두는 자리 (화면 밖)

export type Fragment = BasePart

local freeList: { Fragment } = {} -- 빌려줄 수 있는(반환된) 조각 스택
local acquiredSet: { [Fragment]: boolean } = {} -- 이미 빌려준 조각인지 추적 (이중 release 방지)

local poolFolder: Folder? = nil

local function createFragmentPart(): Fragment
	local part = Instance.new("Part")
	part.Name = "Fragment"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true -- 물리 시뮬레이션 금지 (CLAUDE.md 규칙 4)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Transparency = 1
	part.Material = Enum.Material.Plastic
	part.CFrame = CFrame.new(PARKED_POSITION)
	return part
end

-- 모듈이 처음 require될 때 딱 한 번만 POOL_SIZE개를 만든다. 이후 acquire/release에서는
-- Instance.new를 절대 호출하지 않는다.
local function ensureInitialized()
	if poolFolder ~= nil then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = POOL_FOLDER_NAME
	folder.Parent = Workspace
	poolFolder = folder

	for i = 1, POOL_SIZE do
		local part = createFragmentPart()
		part.Parent = folder
		freeList[i] = part
	end
end

ensureInitialized()

-- 풀에서 조각 하나를 빌린다. 풀이 비었으면 새로 만들지 않고 nil을 반환한다 — 호출부가
-- "연출 생략"으로 처리해야 한다 (게임 진행이 파편 연출보다 우선).
function ParticlePool.acquire(): Fragment?
	local count = #freeList
	if count == 0 then
		return nil
	end

	local fragment = freeList[count]
	freeList[count] = nil
	acquiredSet[fragment] = true

	return fragment
end

-- 빌린 조각을 반환한다. 다음에 빌려질 때 이전 연출 상태가 안 남도록 전부 초기화한다.
function ParticlePool.release(fragment: Fragment)
	if not acquiredSet[fragment] then
		warn("[ParticlePool] release: 빌린 적 없거나 이미 반환된 조각")
		return
	end
	acquiredSet[fragment] = nil

	fragment.Anchored = true
	fragment.CanCollide = false
	fragment.Transparency = 1
	fragment.Size = Vector3.new(1, 1, 1)
	fragment.Color = Color3.new(1, 1, 1)
	fragment.Material = Enum.Material.Plastic
	fragment.CFrame = CFrame.new(PARKED_POSITION)

	table.insert(freeList, fragment)
end

-- 디버그/데모용 현황 조회.
function ParticlePool.getStats(): { total: number, free: number, inUse: number }
	return {
		total = POOL_SIZE,
		free = #freeList,
		inUse = POOL_SIZE - #freeList,
	}
end

return ParticlePool

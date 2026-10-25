--!strict
-- 운동기구 런타임. 스폰 구역에 기구 발판을 세우고, 클릭이 들어온 순간 그 플레이어가 어느 기구 위에
-- 있는지와 그 기구가 열렸는지로 클릭 배수를 답한다.
--
-- 값의 원본은 Shared/Config/GymConfig(조건·배수·가격)와 Shared/GymLayout(좌표·발판 판정)이다.
-- 이 파일에 식을 다시 쓰지 말 것.
--
-- ===== 판정 시점 =========================================================================
--
-- 폴링 루프도 Touched도 쓰지 않는다. ClickService가 클릭 배치를 처리하는 그 순간
-- getClickMultiplier를 부르고, 그때 HumanoidRootPart 위치로 판정한다 — 판정이 필요한 유일한 순간에
-- 한 번만 본다(AttackService가 펀치 시점에 거리를 재는 것과 같은 이유: 주기가 따로 돌면 타이밍
-- 함정이 생긴다).
--
-- ⚠️ 위치는 클라가 물리를 소유하는 캐릭터에서 온다. 패드 Touched와 같은 신뢰 수준이다 —
--    익스플로잇 클라가 기구 위로 순간이동하면 배수를 받는다. 받는 것은 "열린 기구의 배수"뿐이고
--    잠긴 기구는 서버가 환생 수로 판정하므로 열리지 않는다. 이동 검증은 SpeedService 몫이다.
--
-- ===== 해금 =============================================================================
--
-- 환생 수 해금 **OR** 로벅스(지시서 #16): 선해금 기록(profile.Data.gymUnlocks — 개발자 상품, 기록은 #17이 쓴다) ·
-- 게임패스 소유(공허 훈련 구역 — GamepassService 세션 값, 절대 규칙 5). 판정 식은 GymLayout.resolve 하나다.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local CurrencyService = require(script.Parent.CurrencyService)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)
local GamepassService = require(script.Parent.GamepassService)

type BigNumber = BigNum.BigNumber

local GymService = {}

local CONTAINER_NAME = "Gyms"

-- ===== 순수 로직 ==========================================================================

-- 판정(위치 · 환생 수 → 배수)은 Shared/GymLayout.resolve가 원본이다 — 클라 표시(클릭 팝업 · 기구 3D 표시)가 같은 함수를 쓴다(지시서 #8).
export type Resolution = GymLayout.Resolution
local resolve = GymLayout.resolve

-- 로벅스로 열렸는가: 선해금 기록(gymUnlocks["번호"] == true) 또는 그 기구의 게임패스 소유.
local function shopUnlockedWith(gymUnlocks: any, owns: (string) -> boolean): (number) -> boolean
	return function(index: number): boolean
		if type(gymUnlocks) == "table" and gymUnlocks[tostring(index)] == true then
			return true
		end
		local key = GymConfig.getShopKey(index)
		local def = ShopConfig.get(key)
		return def ~= nil and def.kind == "gamepass" and owns(key)
	end
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
GymService._pure = {
	resolve = resolve,
	shopUnlockedWith = shopUnlockedWith,
}

-- ===== 런타임 =============================================================================

local initialized = false

-- ⚠️ 지환 파트 교체 지점. 지금은 임시 발판이다. 바뀌지 않아야 하는 계약:
--   - Anchored = true (물리 금지)
--   - GymIndex Attribute
--   - 판정은 이 파트가 아니라 GymLayout 좌표로 한다 — 파트 모양이 바뀌어도 판정은 그대로다.
--     모양을 바꾸면 GymLayout.SIZE도 같이 바꿀 것
local function createGymPart(index: number, position: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = string.format("Gym_%02d", index)
	part.Size = GymLayout.SIZE
	part.Position = position
	part.Anchored = true
	part.CanCollide = true -- 올라서는 발판이다(패드와 다르다)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("GymIndex", index)
	part.Parent = parent
	return part
end

function GymService.init()
	if initialized then
		warn("[GymService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	GymConfig.validate()

	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace

	local positions = GymLayout.computeLayout(GymConfig.getCount())
	for i, position in ipairs(positions) do
		createGymPart(i, position, container)
	end

	local rebirthTiers = GymConfig.getRebirthTierCount()
	print(string.format(
		"[GymService] 운동기구 %d개 생성 완료 (Z=%.0f, 환생 해금 %d · 로벅스 전용 %d)",
		#positions, GymLayout.LANE_Z, rebirthTiers, #positions - rebirthTiers
	))
end

-- 지금 이 플레이어의 클릭에 붙는 기구 배수. 기구 위가 아니거나 잠겼으면 1.
-- ⚠️ yield하지 않는다 (ClickService가 클릭 배치 처리 중에 부른다).
function GymService.getClickMultiplier(player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root ~= nil and root:IsA("BasePart") then root.Position else nil
	local profile = ProfileManager.get(player)
	local gymUnlocks = if profile ~= nil and type(profile.Data) == "table" then profile.Data.gymUnlocks else nil
	return resolve(position, CurrencyService.get(player, "rebirths"), shopUnlockedWith(gymUnlocks, GamepassService.ownsFn(player))).multiplier
end

-- 플레이어별 상태가 없다 — PlayerRemoving 정리가 필요 없다.

return GymService

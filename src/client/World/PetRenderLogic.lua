--!strict
-- 펫 추적 표시 계획 (Phase 7 지시서 #12 E9). 순수 모듈 — 렌더러는 World/PetRenderer.
--
--   장착 목록은 서버 Player Attribute "EquippedPets"(PetConfig.serializeEquipped 형식)에서 읽는다(PetConfig.parseEquipped).
--   펫 하나 = 종 희귀도 색 구 1개 + 강화 단계 2 이상이면 외곽 껍질 1개(파트 1~2개). 크기는 강화 단계(PetConfig.DISPLAY).
--   다른 사람 펫은 내 hideOtherPets가 켜져 있으면 그리지 않는다(내 펫은 언제나 보인다).
--   한 클라가 그리는 파트 합은 DISPLAY.MAX_TOTAL_PARTS 이하 — 내 펫을 먼저 넣고, 다른 사람 펫은 남는 예산까지만.
--   자리: 캐릭터 뒤 BEHIND 스터드에 가로로 SPACING 간격, 가운데 정렬.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local PetWindowLogic = require(script.Parent.Parent.UI.Logic.PetWindowLogic)

local PetRenderLogic = {}

export type Owner = { key: any, attribute: any, isLocal: boolean }
export type Pet = { petId: string, level: number, rarityTier: number, size: number, shell: boolean, parts: number }
export type Plan = { key: any, pets: { Pet } }

local function petOf(p: PetConfig.OwnedPet): Pet?
	local _, _, rarity = PetConfig.get(p.petId)
	if rarity == nil then
		return nil
	end
	local d = PetConfig.DISPLAY
	local shell = p.tier >= 2
	return {
		petId = p.petId,
		level = p.tier,
		rarityTier = PetWindowLogic.rarityTier(rarity),
		size = d.SIZE_BY_LEVEL[p.tier],
		shell = shell,
		parts = if shell then 2 else 1,
	}
end

-- 그릴 펫 계획. owners 순서와 무관하게 내 것이 먼저 예산을 쓴다. 반환은 그릴 것이 있는 주인만.
function PetRenderLogic.plan(owners: { Owner }, hideOthers: boolean): { Plan }
	local ordered: { Owner } = {}
	for _, o in ipairs(owners) do
		if o.isLocal then
			table.insert(ordered, 1, o)
		elseif not hideOthers then
			table.insert(ordered, o)
		end
	end
	local budget = PetConfig.DISPLAY.MAX_TOTAL_PARTS
	local out: { Plan } = {}
	for _, o in ipairs(ordered) do
		local pets: { Pet } = {}
		for _, p in ipairs(PetConfig.parseEquipped(o.attribute)) do
			local pet = petOf(p)
			if pet ~= nil and pet.parts <= budget then
				budget -= pet.parts
				table.insert(pets, pet)
			end
		end
		if #pets > 0 then
			table.insert(out, { key = o.key, pets = pets })
		end
	end
	return out
end

function PetRenderLogic.totalParts(plans: { Plan }): number
	local n = 0
	for _, p in ipairs(plans) do
		for _, pet in ipairs(p.pets) do
			n += pet.parts
		end
	end
	return n
end

-- i번째(1부터) 펫의 HumanoidRootPart 객체 공간 자리. count마리를 가운데 정렬.
-- ⚠️ 로블록스 객체 공간에서 앞(LookVector)은 −Z다 — 뒤는 +Z. 그래서 z = +BEHIND.
function PetRenderLogic.offset(i: number, count: number): Vector3
	local d = PetConfig.DISPLAY
	local x = (i - (count + 1) / 2) * d.SPACING
	return Vector3.new(x, d.HEIGHT, d.BEHIND)
end

-- 치는 모습(E9 — 데미지 없음): 블록 반경 안이면 PUNCH_PERIOD_SEC 주기로 앞으로 0~1 내밀었다 돌아온다. 밖이면 0.
function PetRenderLogic.punchPhase(inRange: boolean, t: number, index: number): number
	if not inRange then
		return 0
	end
	local period = PetConfig.DISPLAY.PUNCH_PERIOD_SEC
	local phase = ((t / period) + index * 0.37) % 1 -- 펫마다 조금씩 어긋나게
	return math.sin(phase * math.pi)
end

-- 보간 비율(프레임 dt에서). 1을 넘지 않는다.
function PetRenderLogic.alpha(dt: number): number
	return math.clamp(dt * PetConfig.DISPLAY.FOLLOW_RATE, 0, 1)
end

return PetRenderLogic

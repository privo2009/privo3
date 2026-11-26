--!strict
-- 에셋 자리 목록과 "값이 있으면 그 에셋, 없으면 임시 도형" 규칙(지시서 #36 — DESIGN 16장 "에셋 교체 방식"). 값의 원본은 각 설정(EconomyV2Config)이다 —
-- 여기는 그 nil 자리들을 한 표로 모아 읽기만 한다(주문서 docs/ASSET_ORDER.md · 테스트가 이 표를 본다).
--
--   종류 model    Model 에셋 ID. 스크립트가 MeshPart.MeshId를 바꿀 수 없다(공식 문서 MeshPart — Not Accessible Security) ·
--                 Rojo가 MeshId를 실시간 동기화 못 한다(rojo.space sync-details) → 서버 AssetLoader가 InsertService:LoadAsset으로 한 번 불러
--                 ReplicatedStorage.AssetTemplates.<키>에 두고, 쓰는 곳은 복제한다(template)
--        image    이미지 에셋 ID → ImageLabel.Image = contentId(id)
--        texture  이미지 에셋 ID → ParticleEmitter.Texture = contentId(id)
--        anim     애니메이션 ID → Animation.AnimationId = contentId(id)(게임 주인 계정 · 그룹 소유여야 재생된다 — 에셋 권한)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local GymConfig = require(ReplicatedStorage.Shared.Config.GymConfig)

local AssetSlots = {}

AssetSlots.FOLDER = "AssetTemplates"

export type Kind = "model" | "image" | "texture" | "anim"
export type Slot = { key: string, kind: Kind, id: number?, use: string }

-- 정수 ID면 "rbxassetid://ID", 아니면 nil(임시 도형)
function AssetSlots.contentId(id: any): string?
	if type(id) == "number" and id > 0 and id % 1 == 0 then
		return "rbxassetid://" .. string.format("%d", id)
	end
	return nil
end

-- 운동기구 모델 자리 키(지시서 #42) — 기구 번호 1 ~ GymConfig.getCount()(맨 끝 = 공허 훈련 구역)
function AssetSlots.gymKey(index: number): string
	return "gym_" .. tostring(index)
end

-- 설정의 자리 전부(지금 값 포함). 순서 = 주문서 우선순위(곡괭이 → 광석 → 연출 → 코인 → 대장간 → 부화 → 토큰 → 운동기구)
function AssetSlots.list(): { Slot }
	local out: { Slot } = {}
	local function add(key: string, kind: Kind, id: number?, use: string)
		table.insert(out, { key = key, kind = kind, id = id, use = use })
	end
	for _, def in ipairs(Config.PICKAXES) do
		local v = Config.PICKAXE_VISUALS[def.id] or {}
		add("pick_" .. def.id, "model", v.modelId, "손에 든 곡괭이(서버 · 다른 플레이어에게도 보임)")
		add("pick_icon_" .. def.id, "image", v.iconId, "장비 창 칸 아이콘")
		add("swing_" .. def.id, "anim", v.swingAnimId, "채굴 휘두르기(펀치마다)")
	end
	for k, v in ipairs(Config.ORE_VISUALS) do
		add("ore_" .. k, "model", v.modelId, "바닥 드롭(클라 · 풀링)")
		add("ore_icon_" .. k, "image", v.iconId, "가방 · 대장간 칸 아이콘")
		add("ore_fx_" .. k, "texture", v.effectId, "줍기 이펙트 텍스처")
	end
	add("craft_fx", "image", Config.CRAFT_FX_VISUAL.imageId, "제작 결과 연출 그림(화면)")
	add("craft_fx_effect", "image", Config.CRAFT_FX_VISUAL.effectId, "제작 결과 빛 그림(화면 — 결과 이름 뒤)")
	add("coin_icon", "image", Config.COIN_VISUAL.iconId, "HUD 코인 칸 아이콘")
	add("coin_fx", "image", Config.COIN_VISUAL.effectId, "코인 획득 이펙트(화면 — 날아가는 코인 그림)")
	add("forge_site", "model", Config.FORGE_SITE.modelId, "로비 대장간 건물(클라)")
	add("forge_icon", "image", Config.FORGE_SITE.iconId, "HUD 대장간 버튼 아이콘(버튼 왼쪽)")
	add("forge_fx", "texture", Config.FORGE_SITE.effectId, "대장간 화로 이펙트 텍스처")
	add("hatch_egg", "image", Config.HATCH_FX_VISUAL.eggImageId, "부화 연출 알 그림(화면)")
	add("hatch_fx", "image", Config.HATCH_FX_VISUAL.effectId, "부화 결과 빛 그림(화면 — 결과 이름 뒤)")
	-- 펫 모델(#37 — 알 3 × 4등급 + 리미티드). 펫 id 순서 = 알 번호 · 등급 순
	local petIds = {}
	for eggId = 1, #PetConfig.Eggs do
		for _, def in ipairs(PetConfig.Eggs[eggId].pets) do
			table.insert(petIds, def.id)
		end
	end
	for _, id in ipairs(PetConfig.LIMITED_IDS) do
		table.insert(petIds, id)
	end
	for _, id in ipairs(petIds) do
		local v = PetConfig.VISUALS[id] or {}
		add("pet_" .. id, "model", v.modelId, "따라다니는 펫(클라 · 풀링)")
	end
	for _, key in ipairs({ "rare", "epic", "mythic", "legendary", "next" }) do
		local v = Config.TOKEN_VISUALS[key] or {}
		add("token_icon_" .. key, "image", v.iconId, "토큰 아이콘(교환소 · 제작 결과)")
	end
	-- 운동기구 모델(#42 — A2 12기구 + 공허). 값 원본 GymConfig.VISUALS · 쓰는 곳 Client/World/GymModels(발판 위에 얹는다)
	for index = 1, GymConfig.getCount() do
		local v = GymConfig.VISUALS[index] or {}
		add(AssetSlots.gymKey(index), "model", v.modelId,
			if GymConfig.isRobuxOnly(index) then "로비 공허 훈련 구역 모델(클라 — 발판 위)" else "로비 운동기구 모델(클라 — 발판 위)")
	end
	return out
end

-- ===== UI 칸(2026-11-26 지시서 #39 — docs/UI.md "UI 키트 > AssetSlots의 UI 칸" · docs/UI_ASSET_SPEC.md "9") =====
-- UI 그림(9-slice 틀 · 버튼 · 아이콘)을 한 목록으로 본다. list()와 따로 둔다 — list()는 서버 AssetLoader가 모델을 불러오는 목록이다.
--   ui_<키>   AssetRegistry 24종(버튼 6 · 패널 2 · 아이콘 16) — 값의 원본은 Config/AssetConfig(도착하면 한 줄). 없으면 역할색 도형(지금 모양)
--   kit_<칸>  키트 부품 그림(카드 · 탭 · 게이지 · 토스트 · 제목 판 · 모달 · 띠 · 막) — 값의 원본은 UiTheme.Skin.images(Config/UiSkin). 없으면 지금 모양
export type UiSlot = { key: string, id: number?, scaleType: string, slice: Rect?, use: string }

local KIT_IMAGE_USE: { [string]: string } = {
	card = "아이템 칸 · 줄 바탕(등급 테두리는 위에 그린다)",
	cardSelected = "고른 칸",
	tab = "탭(안 고른 것)",
	tabSelected = "탭(고른 것)",
	gaugeBack = "게이지 바탕",
	gaugeFill = "게이지 채움",
	toast = "토스트 한 줄 바탕",
	titlePlate = "창 제목 판(글자 뒤)",
	modal = "모달 판(결과 · 일일 보상)",
	band = "띠 판(안내 · 환생 알림)",
	dim = "모달 뒤 막",
}
AssetSlots.KIT_IMAGE_SLOTS = { "card", "cardSelected", "tab", "tabSelected", "gaugeBack", "gaugeFill", "toast", "titlePlate", "modal", "band", "dim" }

local function numberOf(content: any): number?
	if type(content) == "number" then
		return content
	end
	if type(content) == "string" then
		return tonumber(string.match(content, "%d+$"))
	end
	return nil
end

function AssetSlots.uiList(): { UiSlot }
	local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
	local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
	local out: { UiSlot } = {}
	local keys = {}
	for key in pairs(AssetRegistry.Entries) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local r: any = AssetRegistry.resolve(key)
		table.insert(out, {
			key = "ui_" .. key,
			id = if r.arrived then numberOf(r.id) else nil,
			scaleType = r.scaleType,
			slice = if r.arrived then r.slice else nil,
			use = (AssetRegistry.Entries[key].source :: { string })[1],
		})
	end
	for _, slot in ipairs(AssetSlots.KIT_IMAGE_SLOTS) do
		local spec = UiTheme.Skin.images[slot]
		local hasId = type(spec) == "table" and type(spec.id) == "number"
		table.insert(out, {
			key = "kit_" .. slot,
			id = if hasId then spec.id else nil,
			scaleType = "Slice",
			slice = if hasId and typeof(spec.slice) == "Rect" then spec.slice else nil,
			use = KIT_IMAGE_USE[slot],
		})
	end
	return out
end

-- 화면 칸에 그림을 붙인다(#36): id가 있으면 자식 ImageLabel "SlotImage"를 보이고 그 그림으로 · 없으면 숨긴다(임시 도형 그대로).
-- 붙였으면 그 ImageLabel(보일 때), 아니면 nil. opts: position · size(Scale — 기본 칸 전체) · behind(글자 뒤로 — 기본 true)
function AssetSlots.applyImage(frame: GuiObject, id: any, opts: { position: UDim2?, size: UDim2? }?): ImageLabel?
	local img = frame:FindFirstChild("SlotImage") :: ImageLabel?
	local content = AssetSlots.contentId(id)
	if content == nil then
		if img ~= nil then
			img.Visible = false
		end
		return nil
	end
	if img == nil then
		local l = Instance.new("ImageLabel")
		l.Name = "SlotImage"
		l.BackgroundTransparency = 1
		l.ScaleType = Enum.ScaleType.Fit
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.ZIndex = frame.ZIndex
		l.Parent = frame
		img = l
	end
	local o = opts or {}
	local i = img :: ImageLabel
	i.Position = o.position or UDim2.fromScale(0.5, 0.5)
	i.Size = o.size or UDim2.fromScale(1, 1)
	i.Image = content
	i.Visible = true
	return i
end

-- 불러 둔 모델 틀(없으면 nil — 임시 도형). root는 테스트가 가짜 폴더를 넘긴다
AssetSlots._root = nil :: Instance?
function AssetSlots.template(key: string, root: Instance?): Instance?
	local folder = root or AssetSlots._root or ReplicatedStorage:FindFirstChild(AssetSlots.FOLDER)
	if folder == nil then
		return nil
	end
	return folder:FindFirstChild(key)
end

return AssetSlots

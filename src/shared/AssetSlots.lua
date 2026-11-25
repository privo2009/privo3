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

-- 설정의 자리 전부(지금 값 포함). 순서 = 주문서 우선순위(곡괭이 → 광석 → 연출 → 코인 → 대장간 → 부화 → 토큰)
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
	for _, key in ipairs({ "rare", "epic", "mythic", "legendary", "next" }) do
		local v = Config.TOKEN_VISUALS[key] or {}
		add("token_icon_" .. key, "image", v.iconId, "토큰 아이콘(교환소 · 제작 결과)")
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

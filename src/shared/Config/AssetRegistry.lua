--!strict
-- 화면 코드가 요구하는 이미지 에셋 25종의 목록과, 미도착 시 대체 규칙.
-- 실물 값(id · size · slice)은 여기 두지 않는다 — 그건 AssetConfig.lua가 원본이다.
-- 이 파일은 "무엇이 어떤 모양으로 존재해야 하는가"만 안다.
--
-- ⚠️ 참조는 AssetRegistry -> AssetConfig 단방향이다. AssetConfig.lua는 이 파일을
-- require하지 않는다 (에셋 카탈로그가 화면 목록을 알 필요가 없다).
--
-- 에셋이 아직 제작 전이라 AssetConfig에 엔트리가 없는 것은 오류가 아니라 정상 상태다
-- (25종 중 24종이 지금 그 상태). resolve()는 이때 error를 던지지 않고 "미도착"을 반환한다.
--
-- 에셋이 도착하면 AssetConfig.lua에 엔트리 한 줄이 추가되고, 이 파일은 손대지 않아도
-- resolve()가 자동으로 "도착"을 반환하게 되는 것이 이 설계의 목적이다.

local AssetConfig = require(script.Parent.AssetConfig)
local UiTheme = require(script.Parent.UiTheme)

local AssetRegistry = {}

export type ScaleType = "Slice" | "Tile" | "Stretch"

export type Entry = {
	source: { string }, -- AssetConfig 안의 경로. 예: {"Buttons", "yellow"}
	scaleType: ScaleType,
	placeholderRole: UiTheme.ColorRole,
}

-- 도착: AssetConfig에 실물이 있다. 미도착: 아직 없다 (정상 상태).
export type Resolved =
	{
		arrived: true,
		id: string,
		size: Vector2,
		slice: Rect?, -- scaleType이 Slice일 때만 존재 (AssetConfig 원본에서 옴)
		scaleType: ScaleType,
		placeholderRole: UiTheme.ColorRole,
	}
	| {
		arrived: false,
		scaleType: ScaleType,
		placeholderRole: UiTheme.ColorRole,
	}

local Entries: { [string]: Entry } = {
	-- 버튼 6종 (전부 Slice)
	btn_yellow = { source = { "Buttons", "yellow" }, scaleType = "Slice", placeholderRole = "cashout" },
	btn_purple = { source = { "Buttons", "purple" }, scaleType = "Slice", placeholderRole = "advance" },
	btn_blue = { source = { "Buttons", "blue" }, scaleType = "Slice", placeholderRole = "blox" },
	btn_green = { source = { "Buttons", "green" }, scaleType = "Slice", placeholderRole = "robux" },
	btn_red = { source = { "Buttons", "red" }, scaleType = "Slice", placeholderRole = "danger" },
	btn_gray = { source = { "Buttons", "gray" }, scaleType = "Slice", placeholderRole = "neutral" },

	-- 패널 2종
	panel_frame = { source = { "Panels", "panel_frame" }, scaleType = "Slice", placeholderRole = "neutral" },
	texture_lego = { source = { "Panels", "texture_lego" }, scaleType = "Tile", placeholderRole = "neutral" },

	-- 아이콘 17종 (전부 Stretch)
	icon_shop = { source = { "Icons", "icon_shop" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_rebirth = { source = { "Icons", "icon_rebirth" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_drone = { source = { "Icons", "icon_drone" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_settings = { source = { "Icons", "icon_settings" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_aura = { source = { "Icons", "icon_aura" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_title = { source = { "Icons", "icon_title" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_pet = { source = { "Icons", "icon_pet" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_warp = { source = { "Icons", "icon_warp" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_world = { source = { "Icons", "icon_world" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_power = { source = { "Icons", "icon_power" }, scaleType = "Stretch", placeholderRole = "power" },
	icon_blox = { source = { "Icons", "icon_blox" }, scaleType = "Stretch", placeholderRole = "blox" },
	icon_code = { source = { "Icons", "icon_code" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_attend = { source = { "Icons", "icon_attend" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_close = { source = { "Icons", "icon_close" }, scaleType = "Stretch", placeholderRole = "danger" },
	icon_autoclick = { source = { "Icons", "icon_autoclick" }, scaleType = "Stretch", placeholderRole = "neutral" },
	icon_autoadvance = { source = { "Icons", "icon_autoadvance" }, scaleType = "Stretch", placeholderRole = "neutral" },
	-- 인라인 아이콘 — 타일 규격이 적용되지 않는다 (docs/UI.md "7. 아이콘 > 필요 목록").
	-- 배치 코드가 나머지 16종과 다르게 다뤄야 할 수 있어 표시만 해 둔다.
	icon_edit = { source = { "Icons", "icon_edit" }, scaleType = "Stretch", placeholderRole = "neutral" },
}

AssetRegistry.Entries = Entries

local SCALE_TYPES = { Slice = true, Tile = true, Stretch = true }

-- source 경로를 따라 AssetConfig를 훑는다. 중간에 없으면 nil (미도착, 정상).
local function lookup(source: { string }): any
	local node: any = AssetConfig
	for _, segment in ipairs(source) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return node
end

function AssetRegistry.resolve(key: string): Resolved
	local entry = Entries[key]
	assert(entry ~= nil, "AssetRegistry: 등록되지 않은 키: " .. tostring(key))

	local asset = lookup(entry.source)
	if asset == nil then
		return {
			arrived = false,
			scaleType = entry.scaleType,
			placeholderRole = entry.placeholderRole,
		}
	end

	return {
		arrived = true,
		id = asset.id,
		size = asset.size,
		slice = asset.slice,
		scaleType = entry.scaleType,
		placeholderRole = entry.placeholderRole,
	}
end

function AssetRegistry.validate(): boolean
	for key, entry in pairs(Entries) do
		local label = "AssetRegistry: " .. key
		assert(type(entry.source) == "table" and #entry.source > 0, label .. "의 source가 비어 있음")
		assert(SCALE_TYPES[entry.scaleType], label .. "의 scaleType이 허용값 밖: " .. tostring(entry.scaleType))
		assert(UiTheme.Colors[entry.placeholderRole] ~= nil, label .. "의 placeholderRole이 UiTheme에 없음: " .. tostring(entry.placeholderRole))
	end
	return true
end

return AssetRegistry

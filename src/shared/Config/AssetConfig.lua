--!strict
-- 로블록스에 업로드한 에셋 ID의 단일 원본. 이 파일이 곧 에셋 카탈로그다 (별도 문서 없음).
-- 스크립트에 ID를 직접 박지 말 것 — 재업로드하면 새 ID가 발급된다(덮어쓰기가 아니다).
-- 흩어져 있으면 갱신 시 전부 찾아 고쳐야 하고, 하나 놓치면 옛 그림이 남는다.
--
-- 제작 규격(크기, 9-slice 여백)의 원본은 `docs/UI_ASSET_SPEC.md`다.
-- 여기 적힌 size/slice는 그 규격대로 올라왔는지 확인하기 위한 실제 업로드본의 값이다.
--
-- 아직 제작 전인 에셋은 넣지 않는다. 빈 스텁을 미리 만들면 nil id가 코드로 흘러든다.

local AssetConfig = {}

export type ButtonAsset = {
	id: string, -- "rbxassetid://<숫자>"
	size: Vector2, -- 업로드한 PNG의 픽셀 크기
	slice: Rect, -- SliceCenter. Rect.new(좌, 상, 우, 하) — 우/하는 여백이 아니라 좌표다
	uploaded: string, -- YYYY-MM-DD
	version: number, -- 디자인 담당 제작본 회차
}

-- 버튼 6종 중 yellow만 제작·업로드 완료. 나머지 5종(purple/blue/green/red/gray)은 G1 통과 후 착수한다.
local Buttons: { [string]: ButtonAsset } = {
	yellow = {
		id = "rbxassetid://131146567482435",
		size = Vector2.new(192, 64),
		slice = Rect.new(24, 24, 168, 40), -- 사방 24px 여백 (192-168 = 24, 64-40 = 24)
		uploaded = "2026-08-23",
		version = 2, -- 지환 제작본 v2 (파일명 btn_yellow_2.png)
	},
}

AssetConfig.Buttons = Buttons

local ID_PREFIX = "rbxassetid://"

local function validateAsset(kind: string, name: string, asset: ButtonAsset)
	local label = string.format("AssetConfig: %s.%s", kind, name)

	assert(type(asset.id) == "string", label .. "의 id가 없음")
	assert(string.sub(asset.id, 1, #ID_PREFIX) == ID_PREFIX, label .. '의 id가 "' .. ID_PREFIX .. '"로 시작하지 않음: ' .. asset.id)

	-- 업로드 전 플레이스홀더(rbxassetid://0)가 그대로 남는 사고를 막는다.
	local numeric = tonumber(string.sub(asset.id, #ID_PREFIX + 1))
	assert(numeric ~= nil and numeric > 0, label .. "의 id가 유효한 숫자가 아님(플레이스홀더?): " .. asset.id)

	assert(asset.size ~= nil, label .. "의 size가 nil")
	assert(asset.slice ~= nil, label .. "의 slice가 nil")
	assert(asset.size.X > 0 and asset.size.Y > 0, label .. "의 size가 0 이하")

	-- slice가 size 범위 안에 있는가. 벗어나면 로블록스가 조용히 잘라내므로 여기서 잡는다.
	local min, max = asset.slice.Min, asset.slice.Max
	assert(min.X >= 0 and min.Y >= 0, label .. "의 slice 시작점이 음수")
	assert(min.X < max.X and min.Y < max.Y, label .. "의 slice에 중앙 영역이 없음(시작점 >= 끝점)")
	assert(
		max.X <= asset.size.X and max.Y <= asset.size.Y,
		string.format("%s의 slice가 size를 벗어남: slice max (%d, %d) > size (%d, %d)", label, max.X, max.Y, asset.size.X, asset.size.Y)
	)
end

function AssetConfig.validate(): boolean
	for name, asset in pairs(Buttons) do
		validateAsset("Buttons", name, asset)
	end

	return true
end

return AssetConfig

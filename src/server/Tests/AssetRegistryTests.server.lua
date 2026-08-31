--!strict
-- AssetRegistry 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- U3 착수 준비: 25종 등록 여부, source/scaleType/placeholderRole 형식, resolve()의
-- 도착·미도착 판정을 확인한다. AssetConfig 자체의 값 검증(9-slice 여백 등)은
-- 기존 ConfigTests.server.lua가 이미 덮고 있으므로 여기서 반복하지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
local AssetConfig = require(ReplicatedStorage.Shared.Config.AssetConfig)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)

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

-- U3 착수 준비 명세의 25종 그대로. 개수를 하드코딩하지 않고 이 목록과 대조한다.
local EXPECTED_KEYS = {
	"btn_yellow", "btn_purple", "btn_blue", "btn_green", "btn_red", "btn_gray",
	"panel_frame", "texture_lego",
	"icon_shop", "icon_rebirth", "icon_drone", "icon_settings",
	"icon_aura", "icon_title", "icon_pet", "icon_warp", "icon_world",
	"icon_power", "icon_blox",
	"icon_code", "icon_attend", "icon_close",
	"icon_autoclick", "icon_autoadvance",
	"icon_edit",
}

local SCALE_TYPES = { Slice = true, Tile = true, Stretch = true }

check("AssetRegistry.validate()가 통과한다", AssetRegistry.validate())

for _, key in ipairs(EXPECTED_KEYS) do
	local entry = AssetRegistry.Entries[key]
	check(string.format("AssetRegistry: '%s'가 등록돼 있다", key), entry ~= nil)
	if entry then
		check(string.format("AssetRegistry: '%s'.scaleType이 허용값 안에 있다", key), SCALE_TYPES[entry.scaleType] == true, tostring(entry.scaleType))
		check(
			string.format("AssetRegistry: '%s'.placeholderRole이 UiTheme에 실재한다", key),
			UiTheme.Colors[entry.placeholderRole] ~= nil,
			tostring(entry.placeholderRole)
		)
	end
end

local count = 0
for _ in pairs(AssetRegistry.Entries) do
	count += 1
end
check("AssetRegistry: 정확히 25종만 등록돼 있다", count == #EXPECTED_KEYS, tostring(count))

-- resolve(): btn_yellow는 AssetConfig에 실물이 있으므로 도착 상태여야 한다.
do
	local resolved = AssetRegistry.resolve("btn_yellow")
	check("resolve('btn_yellow'): 도착 상태다", resolved.arrived == true)
	if resolved.arrived then
		check("resolve('btn_yellow'): id가 AssetConfig 값과 같다", resolved.id == AssetConfig.Buttons.yellow.id)
		check("resolve('btn_yellow'): slice가 AssetConfig 값과 같다", resolved.slice == AssetConfig.Buttons.yellow.slice)
		check("resolve('btn_yellow'): scaleType이 Slice다", resolved.scaleType == "Slice")
	end
end

-- resolve(): 나머지 24종은 AssetConfig에 실물이 없으므로 미도착이어야 하고,
-- error 없이 정상 반환돼야 한다 (25종 중 24종이 지금 이 상태가 정상).
for _, key in ipairs(EXPECTED_KEYS) do
	if key ~= "btn_yellow" then
		local ok, resolved = pcall(AssetRegistry.resolve, key)
		check(string.format("resolve('%s'): error 없이 반환된다", key), ok)
		if ok then
			check(string.format("resolve('%s'): 미도착 상태다", key), resolved.arrived == false)
		end
	end
end

-- 등록되지 않은 키는 프로그래머 실수(오타)이므로 이건 실제로 error여야 한다.
do
	local ok = pcall(AssetRegistry.resolve, "icon_does_not_exist")
	check("resolve(): 등록되지 않은 키는 error", ok == false)
end

print(string.format("[AssetRegistryTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AssetRegistryTests] %d test(s) failed", failed))
end

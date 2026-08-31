--!strict
-- AssetImage 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- U3 착수 준비: AssetRegistry.resolve() 결과를 넘겼을 때 미도착/도착 각각 올바른
-- Instance가 나오는지, 공통으로 UIStroke(3px)가 붙는지 확인한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetImage = require(ReplicatedStorage.Shared.UI.AssetImage)
local AssetRegistry = require(ReplicatedStorage.Shared.Config.AssetRegistry)
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

local function findStroke(instance: Instance): UIStroke?
	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("UIStroke") then
			return child
		end
	end
	return nil
end

-- 1. 미도착 엔트리 -> Frame + 역할 기본색 -----------------------------------------
-- btn_purple은 AssetConfig에 아직 실물이 없다 (U2 완료 전 정상 상태).

do
	local resolved = AssetRegistry.resolve("btn_purple")
	check("전제: btn_purple은 미도착이다", resolved.arrived == false)

	local instance = AssetImage.create(resolved)
	check("미도착 엔트리 -> Frame을 반환한다", instance:IsA("Frame"))
	check(
		"미도착 엔트리 -> 배경색이 역할 기본색과 같다",
		(instance :: Frame).BackgroundColor3 == UiTheme.Colors.advance.base
	)

	local stroke = findStroke(instance)
	check("미도착 엔트리에 UIStroke가 붙어 있다", stroke ~= nil)
	if stroke then
		check("미도착 엔트리의 UIStroke Thickness가 3이다", stroke.Thickness == 3)
	end
end

-- 2. 도착 엔트리(Slice) -> ImageLabel + Image/ScaleType/SliceCenter ----------------
-- btn_yellow는 AssetConfig에 실물이 있는 유일한 엔트리다.

do
	local resolved = AssetRegistry.resolve("btn_yellow")
	check("전제: btn_yellow는 도착 상태다", resolved.arrived == true)

	local instance = AssetImage.create(resolved)
	check("도착 엔트리 -> ImageLabel을 반환한다", instance:IsA("ImageLabel"))

	if instance:IsA("ImageLabel") and resolved.arrived then
		check("도착 엔트리 -> Image가 세팅된다", instance.Image == resolved.id)
		check("도착 엔트리 -> ScaleType이 Slice다", instance.ScaleType == Enum.ScaleType.Slice)
		check("Slice 엔트리 -> SliceCenter가 세팅된다", instance.SliceCenter == resolved.slice)
	end

	local stroke = findStroke(instance)
	check("도착 엔트리에 UIStroke가 붙어 있다", stroke ~= nil)
	if stroke then
		check("도착 엔트리의 UIStroke Thickness가 3이다", stroke.Thickness == 3)
	end
end

-- 3. 도착 엔트리(Tile / Stretch) -----------------------------------------------
-- 실제 AssetConfig에는 아직 이 scaleType의 실물이 없어서, resolve()가 낼 수 있는
-- 모양을 합성 값으로 직접 구성해 SliceCenter 없이도 정상 동작하는지 확인한다.

do
	local resolved: AssetRegistry.Resolved = {
		arrived = true,
		id = "rbxassetid://1",
		size = Vector2.new(128, 128),
		slice = nil,
		scaleType = "Tile",
		placeholderRole = "neutral",
	}
	local instance = AssetImage.create(resolved)
	check("Tile 도착 엔트리 -> ImageLabel을 반환한다", instance:IsA("ImageLabel"))
	if instance:IsA("ImageLabel") then
		check("Tile 도착 엔트리 -> ScaleType이 Tile이다", instance.ScaleType == Enum.ScaleType.Tile)
	end
end

do
	local resolved: AssetRegistry.Resolved = {
		arrived = true,
		id = "rbxassetid://2",
		size = Vector2.new(256, 256),
		slice = nil,
		scaleType = "Stretch",
		placeholderRole = "neutral",
	}
	local instance = AssetImage.create(resolved)
	check("Stretch 도착 엔트리 -> ImageLabel을 반환한다", instance:IsA("ImageLabel"))
	if instance:IsA("ImageLabel") then
		check("Stretch 도착 엔트리 -> ScaleType이 Stretch다", instance.ScaleType == Enum.ScaleType.Stretch)
	end
end

print(string.format("[AssetImageTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AssetImageTests] %d test(s) failed", failed))
end

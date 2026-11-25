--!strict
-- 모델 에셋 불러 두기(지시서 #36 — DESIGN 16장 "에셋 교체 방식").
--
-- 설정의 model 자리(Shared/AssetSlots.list — kind "model")에 ID가 있으면 서버가 시작할 때 한 번 InsertService:LoadAsset(ID)으로 불러
-- ReplicatedStorage.AssetTemplates.<키>에 둔다(이름 = 자리 키). 쓰는 곳(드롭 · 대장간 · 손에 든 곡괭이)은 AssetSlots.template(키)를 복제한다.
--   - 스크립트는 MeshPart.MeshId를 바꿀 수 없다(공식 문서 MeshPart — Not Accessible Security) → 모델을 통째로 불러 복제한다
--   - LoadAsset 권한(공식 문서 Capabilities "LoadOwnedAsset"): 내 것 · 나에게 공유된 것 · Roblox 것 — 게임 주인 계정 · 그룹으로 올린다
--   - 실패(권한 · 네트워크 · 빈 모델)면 경고 한 줄 · 그 자리는 임시 도형 그대로(게임은 멈추지 않는다)
--   - 실행 중 만든 인스턴스다 — 플레이스 파일은 바뀌지 않는다. ID가 전부 nil이면 빈 폴더만 만든다
-- 불러온 것: LoadAsset이 돌려주는 Model 안 첫 자식. 그 자식이 Model이 아니면(MeshPart 하나 등) 그대로 둔다(드롭은 BasePart를 쓴다)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)

local AssetLoader = {}

export type Deps = {
	load: (number) -> Instance, -- InsertService:LoadAsset(id) (yield · 실패하면 error)
	folder: () -> Instance,
	warn: (string) -> (),
}

local function liveDeps(): Deps
	return {
		load = function(id: number): Instance
			return game:GetService("InsertService"):LoadAsset(id)
		end,
		folder = function(): Instance
			local f = ReplicatedStorage:FindFirstChild(AssetSlots.FOLDER)
			if f == nil then
				f = Instance.new("Folder")
				f.Name = AssetSlots.FOLDER
				f.Parent = ReplicatedStorage
			end
			return f :: Instance
		end,
		warn = warn,
	}
end

-- 자리 하나를 불러 폴더에 둔다. 성공이면 둔 인스턴스, 아니면 nil(임시 도형 그대로)
function AssetLoader.loadOne(deps: Deps, key: string, id: number): Instance?
	local ok, result = pcall(deps.load, id)
	if not ok or typeof(result) ~= "Instance" then
		deps.warn(string.format("[AssetLoader] %s(%d) 불러오기 실패 — 임시 도형 그대로: %s", key, id, tostring(result)))
		return nil
	end
	local container = result :: Instance
	local item = container:GetChildren()[1]
	if item == nil then
		deps.warn(string.format("[AssetLoader] %s(%d) 빈 모델 — 임시 도형 그대로", key, id))
		container:Destroy()
		return nil
	end
	item.Name = key
	item.Parent = deps.folder()
	container:Destroy()
	return item
end

-- 설정의 model 자리 중 ID가 있는 것을 전부 불러 둔다. 불러 둔 키 목록
function AssetLoader.loadAll(deps: Deps?): { string }
	local d = deps or liveDeps()
	d.folder()
	local out = {}
	for _, slot in ipairs(AssetSlots.list()) do
		if slot.kind == "model" and AssetSlots.contentId(slot.id) ~= nil then
			if AssetLoader.loadOne(d, slot.key, slot.id :: number) ~= nil then
				table.insert(out, slot.key)
			end
		end
	end
	return out
end

local initialized = false
function AssetLoader.init()
	if initialized then
		return
	end
	initialized = true
	task.spawn(function()
		local keys = AssetLoader.loadAll()
		print(string.format("[AssetLoader] 모델 에셋 %d개 불러 둠%s", #keys, if #keys > 0 then " — " .. table.concat(keys, ", ") else "(전부 nil — 임시 도형)"))
	end)
end

return AssetLoader

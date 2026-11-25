--!strict
-- 새 경제 안내 · 해금 순서 · 에셋 자리 서버 검증(지시서 #36 — 플래그 ECONOMY_V2 뒤에서만 쓰는 경로). 전역 플래그는 건드리지 않는다.
-- OnboardingTipsLogic(조건 · 순서 · 한 번만 · 이미 지난 것) · OnboardingTipsService(가짜 deps — 한 틱에 하나 · 접속 backfill · 동기화) ·
-- OnboardingService 건너뛰기 = 안내 끔(새 경제만) · Schema(기존 필드 안 tips · tipsOff · 버전 그대로) · AssetSlots · AssetLoader(가짜 불러오기) ·
-- 손에 든 곡괭이 모델 틀(가짜 틀) · 휘두르기 자리 · 플래그 꺼짐.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Config = require(ReplicatedStorage.Shared.Config.EconomyV2Config)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local Strings = require(ReplicatedStorage.Shared.Localization.Strings)
local L = require(ReplicatedStorage.Shared.EconomyV2Logic)
local T = require(ReplicatedStorage.Shared.OnboardingTipsLogic)
local AssetSlots = require(ReplicatedStorage.Shared.AssetSlots)
local Schema = require(ServerScriptService.Server.Data.Schema)
local OnboardingService = require(ServerScriptService.Server.Systems.OnboardingService)
local OnboardingTipsService = require(ServerScriptService.Server.Systems.OnboardingTipsService)
local AssetLoader = require(ServerScriptService.Server.Systems.AssetLoader)
local HeldPickaxeService = require(ServerScriptService.Server.Systems.HeldPickaxeService)
local OreDropService = require(ServerScriptService.Server.Systems.OreDropService)

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

local function fresh(): any
	return Schema.new()
end

local function pickOf(data: any, bag: number?): (string?, boolean)
	return T.pick(data.onboarding, T.facts(data, bag))
end

-- 1. 조건 · 순서 ---------------------------------------------------------------------------------------------
do
	local d = fresh()
	local k0 = pickOf(d)
	d.lifetimeBlox, d.blox = BigNum.new(5, 0), BigNum.new(5, 0)
	d.coins = BigNum.new(3, 0)
	local k1, s1 = pickOf(d)
	T.mark(d.onboarding, k1 :: string)
	local k2 = pickOf(d)
	T.mark(d.onboarding, k2 :: string)
	local k3 = pickOf(d)
	check("새 유저: 처음엔 안내 없음 · 첫 수령(블럭스)과 첫 코인이 함께면 순서대로 blox → coins · 한 번 적으면 다시 안 나옴",
		k0 == nil and k1 == "blox" and s1 == false and k2 == "coins" and k3 == nil, string.format("%s %s %s %s", tostring(k0), tostring(k1), tostring(k2), tostring(k3)))
end
do
	local d = fresh()
	local kBag = pickOf(d, 2)
	local d2 = fresh()
	d2.ores[1] = 1
	check("첫 광석: 가방에 들었거나(런 중) 인벤토리에 있으면 bag", kBag == "bag" and pickOf(d2) == "bag")
end
do
	local d = fresh()
	d.onboarding.tips = { blox = true }
	d.blox = L.rebirthCost(0)
	local k = pickOf(d)
	local d2 = fresh()
	d2.onboarding.tips = { blox = true }
	d2.blox = BigNum.sub(L.rebirthCost(0), BigNum.new(1, 0))
	check("첫 환생 가능: 블럭스 ≥ 첫 환생 비용이면 rebirth(모자라면 없음)", k == "rebirth" and pickOf(d2) == nil)
	local d3 = fresh()
	d3.onboarding.tips = { blox = true }
	d3.rebirths = BigNum.new(1, 0)
	local k3, s3 = pickOf(d3)
	check("환생을 이미 했으면 rebirth는 글 없이(지난 것)", k3 == "rebirth" and s3 == true)
end
do
	local d = fresh()
	d.forgeOpen = true
	d.onboarding.tips = { bag = true }
	local k = pickOf(d)
	d.tokens.rare = 1
	local k2, s2 = pickOf(d)
	check("대장간 열림 → craft · 이미 제작했으면(토큰) 글 없이", k == "craft" and k2 == "craft" and s2 == true)
end
do
	local d = fresh()
	d.forgeOpen = true
	d.onboarding.tips = { bag = true, craft = true }
	local better = Config.PICKAXES[2].id
	d.equipment.pickaxe[better] = { count = 1, stars = 0, enh = 0 }
	local k = pickOf(d)
	d.equipped.pickaxe = better
	d.equipment.pickaxe[Config.PICKAXES[3].id] = { count = 1, stars = 0, enh = 0 }
	local k2, s2 = pickOf(d)
	check("더 좋은 곡괭이 → equip · 이미 바꿔 장착했으면 글 없이", k == "equip" and k2 == "equip" and s2 == true)
end
do
	local d = fresh()
	d.onboarding.tips = { blox = true }
	d.lifetimeBlox = PetConfig.Eggs[1].rollCost
	local k = pickOf(d)
	d.lifetimeBlox = BigNum.sub(PetConfig.Eggs[1].rollCost, BigNum.new(1, 0))
	local kLow = pickOf(d)
	local d2 = fresh()
	d2.onboarding.tips = { blox = true }
	d2.pets.owned["1"] = { petId = "egg1_common", tier = 1 }
	local k2, s2 = pickOf(d2)
	check("첫 알 해금(누적 블럭스 ≥ 알 1) → egg · 모자라면 없음 · 펫이 있으면 글 없이", k == "egg" and kLow == nil and k2 == "egg" and s2 == true)
end
do
	local d = fresh()
	d.onboarding.tipsOff = true
	d.coins = BigNum.new(1, 0)
	local k, s = pickOf(d)
	check("안내를 끈 유저: 칸은 나타나게 적지만 글 없이", k == "coins" and s == true)
end

-- 2. 이미 지난 유저(접속 backfill) -------------------------------------------------------------------------------
do
	local d = fresh()
	d.lifetimeBlox, d.blox = BigNum.new(5.05, 3), BigNum.new(2.87, 3)
	d.rebirths = BigNum.new(1, 0)
	d.pets.owned["1"] = { petId = "egg1_rare", tier = 2 }
	local keys = T.backfill(d.onboarding, T.facts(d))
	local set = {}
	for _, k in ipairs(keys) do
		set[k] = true
	end
	check("floor9 꼴 접속: blox · rebirth · egg를 글 없이 적고 · 코인 · 가방 · 대장간 · 장비는 남김",
		set.blox and set.rebirth and set.egg and not set.coins and not set.bag and not set.craft and not set.equip, table.concat(keys, ","))
	local fd = fresh()
	check("새 유저 접속: 지난 것 없음", #T.backfill(fd.onboarding, T.facts(fd)) == 0)
end

-- 3. 서비스(가짜 deps): 한 틱에 하나 · 접속 상태 · 동기화 ------------------------------------------------------------
do
	local d = fresh()
	local sent = {}
	local player: any = { Name = "Fake" }
	OnboardingTipsService._deps = {
		getData = function()
			return d
		end,
		bagUsed = function()
			return 0
		end,
		send = function(_p, payload)
			table.insert(sent, payload)
		end,
		log = function() end,
	}
	OnboardingTipsService.onLoaded(player)
	local first = sent[1]
	d.lifetimeBlox, d.blox, d.coins = BigNum.new(5, 0), BigNum.new(5, 0), BigNum.new(1, 0)
	local a = OnboardingTipsService.tick(player)
	local b = OnboardingTipsService.tick(player)
	local c = OnboardingTipsService.tick(player)
	check("서비스: 접속 때 전체 상태(tips) · 한 틱에 안내 하나(blox → coins → 없음) · 보낼 때 저장",
		first ~= nil and first.kind == "tips" and #first.seen == 0 and a == "blox" and b == "coins" and c == nil
			and sent[2].kind == "tip" and sent[2].key == "blox" and sent[2].silent == false and d.onboarding.tips.blox == true and d.onboarding.tips.coins == true)
	local n = #sent
	OnboardingTipsService.handleRequest(player, { action = "sync" }, 1000)
	OnboardingTipsService.handleRequest(player, { action = "sync" }, 1000.1)
	OnboardingTipsService.handleRequest(player, { action = "other" }, 1002)
	check("서비스: 동기화 요청 → 전체 상태 · 연타 · 모르는 요청은 버림", #sent == n + 1 and sent[n + 1].kind == "tips" and #sent[n + 1].seen == 2)
	OnboardingTipsService._deps = nil
end

-- 4. 건너뛰기 = 새 경제 안내도 끔(새 경제만) ---------------------------------------------------------------------------
do
	local function run(v2: boolean?): any
		local d = fresh()
		local deps: any = {
			getData = function()
				return d
			end,
			grant = function()
				return true, nil
			end,
			notify = function() end,
			logFunnel = function() end,
			send = function() end,
			log = function() end,
		}
		if v2 ~= nil then
			deps.isV2 = function()
				return v2
			end
		end
		local rt = OnboardingService._pure.createRuntime(deps)
		rt.onRequest({ Name = "Fake" } :: any, { action = "skip" }, 10)
		return d.onboarding
	end
	local on, off, none = run(true), run(false), run(nil)
	check("건너뛰기: 새 경제면 tipsOff · 꺼져 있으면(또는 deps 없음) 지금 그대로", on.done and on.tipsOff == true and off.done and off.tipsOff == nil
		and none.done and none.tipsOff == nil)
end

-- 5. 저장(기존 필드 안 · 스키마 버전 그대로) ---------------------------------------------------------------------------
do
	local d = fresh()
	local okEmpty = Schema.validate(d)
	d.onboarding.tips = { blox = true, coins = true }
	d.onboarding.tipsOff = true
	local okFull = Schema.validate(d)
	local bad1 = fresh()
	bad1.onboarding.tips = { blox = 1 }
	local bad2 = fresh()
	bad2.onboarding.tipsOff = "yes"
	local bad3 = fresh()
	bad3.onboarding.tips = {}
	for i = 1, Schema.LIMITS.MAX_ONBOARDING_TIPS + 1 do
		bad3.onboarding.tips["k" .. i] = true
	end
	check("저장: tips · tipsOff 없어도 · 있어도 통과 · 틀린 꼴 · 상한 초과는 거부", okEmpty and okFull and not Schema.validate(bad1) and not Schema.validate(bad2)
		and not Schema.validate(bad3))
	check("저장: 템플릿에 새 필드 없음 · 스키마 버전 10 그대로 · 새 최상위 필드 없음", Schema.VERSION == 10 and fresh().onboarding.tips == nil
		and fresh().tipsOff == nil and fresh().tips == nil)
end

-- 6. 설정 · 문장 ---------------------------------------------------------------------------------------------------
do
	local ok, seen = true, {}
	for _, tip in ipairs(OnboardingConfig.V2_TIPS) do
		local s = Strings.Entries["onboarding.tip." .. tip.key]
		ok = ok and not seen[tip.key] and s ~= nil and type(s.en) == "string" and type(s.ko) == "string"
		seen[tip.key] = true
	end
	local s4 = Strings.Entries["onboarding.step.4.v2"]
	check("설정: 안내 키 겹침 없음 · 문장 en · ko · 4단계 새 경제 문장 · 상한 안", ok and s4 ~= nil and s4.en ~= nil and s4.ko ~= nil
		and #OnboardingConfig.V2_TIPS <= Schema.LIMITS.MAX_ONBOARDING_TIPS)
	check("HUD 칸: 안내를 지나야 보임(blox · coins · bag · rebirth · pet) · 안내로 여는 칸이 아니면 언제나",
		not T.hudShown({}, "blox") and T.hudShown({ blox = true }, "blox") and not T.hudShown({}, "pet") and T.hudShown({ egg = true }, "pet")
			and T.hudShown({}, "forge"))
	check("가방 수: 런 밖 플레이어는 0", OreDropService.bagUsed({} :: any) == 0)
end

-- 7. 에셋 자리 ------------------------------------------------------------------------------------------------------
do
	local slots = AssetSlots.list()
	local count, anyId, models = {}, false, 0
	for _, s in ipairs(slots) do
		count[s.kind] = (count[s.kind] or 0) + 1
		anyId = anyId or s.id ~= nil
		if s.kind == "model" then
			models += 1
		end
	end
	check("자리 목록: 곡괭이 15 × (모델 · 아이콘 · 휘두르기) · 광석 10 × 3 · 대장간 · 코인 · 부화 · 제작 · 토큰 5 — 지금은 전부 nil",
		#slots == 15 * 3 + 10 * 3 + 2 + 2 + 3 + 2 + 5 and models == 15 + 10 + 1 and count.anim == 15 and not anyId, tostring(#slots))
	check("contentId: 양의 정수만 rbxassetid · nil · 소수 · 0은 nil(임시 도형)", AssetSlots.contentId(123) == "rbxassetid://123"
		and AssetSlots.contentId(nil) == nil and AssetSlots.contentId(1.5) == nil and AssetSlots.contentId(0) == nil)
	local root = Instance.new("Folder")
	local m = Instance.new("Model")
	m.Name = "ore_1"
	m.Parent = root
	check("틀 찾기: 폴더에 있으면 그 틀 · 없으면 nil", AssetSlots.template("ore_1", root) == m and AssetSlots.template("ore_2", root) == nil)
	root:Destroy()
end
do
	local folder = Instance.new("Folder")
	local warns = {}
	local loads = {}
	local deps: any = {
		load = function(id: number): Instance
			table.insert(loads, id)
			if id == 1 then
				local c = Instance.new("Model")
				local inner = Instance.new("Model")
				inner.Name = "Whatever"
				inner.Parent = c
				return c
			elseif id == 2 then
				return Instance.new("Model") -- 빈 모델
			end
			error("권한 없음")
		end,
		folder = function()
			return folder
		end,
		warn = function(s)
			table.insert(warns, s)
		end,
	}
	local ok1 = AssetLoader.loadOne(deps, "pick_pick_c1", 1)
	local ok2 = AssetLoader.loadOne(deps, "ore_2", 2)
	local ok3 = AssetLoader.loadOne(deps, "ore_3", 3)
	check("불러오기: 성공이면 폴더에 자리 키 이름으로 · 빈 모델 · 실패는 nil + 경고(임시 도형 그대로)",
		ok1 ~= nil and ok1.Name == "pick_pick_c1" and ok1.Parent == folder and ok2 == nil and ok3 == nil and #warns == 2)
	table.clear(loads)
	local keys = AssetLoader.loadAll(deps)
	check("불러오기: 자리가 전부 nil이면 아무것도 부르지 않는다", #keys == 0 and #loads == 0)
	folder:Destroy()
end
do
	-- 손에 든 곡괭이: 틀이 있으면 그 모델(Handle을 손에) · 없으면 임시 도형
	local function character(): (Model, Part)
		local c = Instance.new("Model")
		local hand = Instance.new("Part")
		hand.Name = "RightHand"
		hand.Parent = c
		return c, hand
	end
	local tpl = Instance.new("Model")
	local h = Instance.new("Part")
	h.Name = "Handle"
	h.Parent = tpl
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Parent = tpl
	local saved = HeldPickaxeService._template
	HeldPickaxeService._template = function(key: string): Instance?
		return if key == "pick_" .. Config.START_PICKAXE then tpl else nil
	end
	local c1, hand1 = character()
	local m1 = HeldPickaxeService.attach(c1, Config.START_PICKAXE)
	local mh = if m1 ~= nil then m1:FindFirstChild("Handle") else nil
	local weld = if mh ~= nil then mh:FindFirstChildOfClass("WeldConstraint") else nil
	local bladeWeld = if m1 ~= nil and m1:FindFirstChild("Blade") then (m1 :: any).Blade:FindFirstChildOfClass("WeldConstraint") else nil
	check("손 모델 틀: 있으면 복제(Handle은 손에 · 나머지는 Handle에 · 충돌 끔)", m1 ~= nil and m1:GetAttribute("FromAsset") == true and weld ~= nil
		and weld.Part0 == hand1 and bladeWeld ~= nil and bladeWeld.Part0 == mh and (mh :: any).CanCollide == false)
	local c2 = character()
	local m2 = HeldPickaxeService.attach(c2, Config.PICKAXES[2].id)
	check("손 모델 틀: 없으면 임시 도형(자루 + 머리)", m2 ~= nil and m2:GetAttribute("FromAsset") == nil and m2:FindFirstChild("Head") ~= nil)
	HeldPickaxeService._template = saved
	c1:Destroy()
	c2:Destroy()
	tpl:Destroy()
	local before = Config.PICKAXE_VISUALS[Config.START_PICKAXE]
	check("휘두르기 자리: 지금은 nil(없음)", HeldPickaxeService.swingAnimationId(Config.START_PICKAXE) == nil)
	Config.PICKAXE_VISUALS[Config.START_PICKAXE] = { swingAnimId = 4242 }
	local withId = HeldPickaxeService.swingAnimationId(Config.START_PICKAXE)
	Config.PICKAXE_VISUALS[Config.START_PICKAXE] = before
	check("휘두르기 자리: ID가 있으면 그 애니메이션(rbxassetid) · 되돌림", withId == "rbxassetid://4242"
		and HeldPickaxeService.swingAnimationId(Config.START_PICKAXE) == nil)
end

-- 8. 플래그 꺼짐 = 지금과 같다 ---------------------------------------------------------------------------------------
check("플래그 꺼짐: 안내 서비스 init 없음(켜져 있으면 init됨)", OnboardingTipsService._initialized() == L.isOn())

print(string.format("[OnboardingTipsTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[OnboardingTipsTests] %d test(s) failed", failed))
end

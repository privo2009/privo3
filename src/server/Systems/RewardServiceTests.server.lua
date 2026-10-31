--!strict
-- RewardService(무료 보상 지급 공용) · RewardLogic(형식 · 블럭스 양) · PetService.grant(보상 펫 발급) 검증 (지시서 #20 단계 3 — R1).
-- 가짜 deps로 굴린다 — 실제 프로필을 건드리지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
local RewardLogic = require(ReplicatedStorage.Shared.RewardLogic)
local RewardService = require(script.Parent.RewardService)
local PetService = require(script.Parent.PetService)
local Schema = require(script.Parent.Parent.Data.Schema)

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

local A: any = { Name = "A", UserId = 1 }
local PET = PetConfig.Eggs[1].pets[1].id

-- 가짜 세계: 프로필 하나 · 블럭스 add 기록 · 펫 저장 공간
local function world(opts: { maxStage: number?, room: number?, addOk: boolean? }?)
	local o = opts or {}
	local data = Schema.new() :: any
	data.progress.maxStage = o.maxStage or 1
	local w: any = { data = data, adds = {}, pets = {}, notified = 0, logs = {} }
	local room = if o.room ~= nil then o.room else 10
	w.rt = RewardService._pure.createRuntime({
		getData = function()
			return w.data
		end,
		addBlox = function(_, amount, reason)
			if o.addOk == false then
				return false
			end
			table.insert(w.adds, { amount = amount, reason = reason })
			return true
		end,
		petRoom = function()
			return room - #w.pets
		end,
		grantPet = function(_, petId)
			table.insert(w.pets, petId)
			return true
		end,
		notify = function()
			w.notified += 1
		end,
		log = function(line)
			table.insert(w.logs, line)
		end,
	})
	return w
end

-- 1. 형식 -----------------------------------------------------------------------------------------------
check("형식: 포션(힘 · 데미지 1 ~ 99) · bloxScaled(k > 0) · 펫(아는 id) 통과", RewardLogic.isValidList({
	{ type = "potion", kind = "strength", count = 1 }, { type = "potion", kind = "damage", count = 99 }, { type = "bloxScaled", k = 2.5 },
	{ type = "pet", petId = PET } }))
check("형식 거부: 행운 포션(무료로 주지 않는다 #17) · 개수 0 · 100 · 소수 · 모르는 종류", not RewardLogic.isValid({ type = "potion", kind = "luck", count = 1 })
	and not RewardLogic.isValid({ type = "potion", kind = "strength", count = 0 }) and not RewardLogic.isValid({ type = "potion", kind = "strength", count = 100 })
	and not RewardLogic.isValid({ type = "potion", kind = "strength", count = 1.5 }) and not RewardLogic.isValid({ type = "potion", kind = "xp", count = 1 }))
check("형식 거부: k 0 · 음수 · inf · nan · 모르는 펫 · 모르는 type · 빈 목록 · 표 아님", not RewardLogic.isValid({ type = "bloxScaled", k = 0 })
	and not RewardLogic.isValid({ type = "bloxScaled", k = -1 }) and not RewardLogic.isValid({ type = "bloxScaled", k = math.huge })
	and not RewardLogic.isValid({ type = "bloxScaled", k = 0 / 0 }) and not RewardLogic.isValid({ type = "pet", petId = "nope" })
	and not RewardLogic.isValid({ type = "gem" }) and not RewardLogic.isValidList({}) and not RewardLogic.isValidList("x"))

-- 2. bloxScaled 양 — maxStage 0 · 중간 · 25 ------------------------------------------------------------------
check("bloxScaled: maxStage 0 · 음수 · 숫자 아님 → 1층 보상 × k", BigNum.eq(RewardLogic.bloxAmount(0, 2), BigNum.mul(StageConfig.getBloxReward(1), BigNum.fromNumber(2)))
	and BigNum.eq(RewardLogic.bloxAmount(-3, 1), StageConfig.getBloxReward(1)) and BigNum.eq(RewardLogic.bloxAmount(nil, 1), StageConfig.getBloxReward(1)))
check("bloxScaled: maxStage 9 → 9층 보상 × 3", BigNum.eq(RewardLogic.bloxAmount(9, 3), BigNum.mul(StageConfig.getBloxReward(9), BigNum.fromNumber(3))))
check("bloxScaled: maxStage 25 → 25층 보상 × 5 · 정의된 층을 넘으면 마지막 층", BigNum.eq(RewardLogic.bloxAmount(25, 5),
	BigNum.mul(StageConfig.getBloxReward(25), BigNum.fromNumber(5))) and RewardLogic.baseStage(9999) == 25)

-- 3. grant — 세 형식 · 전부 아니면 0 ----------------------------------------------------------------------------
do
	local w = world({ maxStage = 9 })
	w.data.potions.strength = 2
	local ok, g = w.rt.grant(A, { { type = "potion", kind = "strength", count = 1 }, { type = "bloxScaled", k = 2 }, { type = "pet", petId = PET },
		{ type = "potion", kind = "damage", count = 2 } }, "test")
	check("grant 세 형식: 성공 · 블럭스 add 1회(9층 × 2 · 사유 reward_test) · 포션 보관함 += · 펫 발급 · 통지 1회", ok and #w.adds == 1
		and BigNum.eq(w.adds[1].amount, RewardLogic.bloxAmount(9, 2)) and w.adds[1].reason == "reward_test" and w.data.potions.strength == 3
		and w.data.potions.damage == 2 and #w.pets == 1 and w.pets[1] == PET and w.notified == 1)
	check("grant 결과 요약: blox · potions · pets", ok and BigNum.eq(g.blox, RewardLogic.bloxAmount(9, 2)) and #g.potions == 2 and g.pets[1] == PET)
	local okP, gP = w.rt.grant(A, { { type = "potion", kind = "damage", count = 1 } }, "p")
	check("포션만이면 블럭스 add를 부르지 않는다(blox 0)", okP and #w.adds == 1 and BigNum.eq(gP.blox, BigNum.new(0, 0)))
end
do
	local w = world()
	local ok, reason = w.rt.grant(A, { { type = "potion", kind = "strength", count = 1 }, { type = "potion", kind = "luck", count = 1 } }, "bad")
	check("전부 아니면 0: 한 항목이라도 틀리면 invalid_reward · 아무것도 안 줌 · 통지 없음", not ok and reason == RewardService.REASON_INVALID
		and w.data.potions.strength == 0 and w.notified == 0)
end
do
	local w = world({ room = 0 })
	local ok, reason = w.rt.grant(A, { { type = "bloxScaled", k = 2 }, { type = "potion", kind = "strength", count = 1 }, { type = "pet", petId = PET } }, "full")
	check("펫 보관함 가득 → storage_full · 블럭스 · 포션 · 펫 전부 안 줌", not ok and reason == RewardService.REASON_STORAGE_FULL and #w.adds == 0
		and w.data.potions.strength == 0 and #w.pets == 0 and w.notified == 0)
	local w2 = world({ room = 1 })
	local ok2, reason2 = w2.rt.grant(A, { { type = "pet", petId = PET }, { type = "pet", petId = PET } }, "two")
	check("펫 2마리에 남은 칸 1 → storage_full(칸은 펫 수만큼 본다)", not ok2 and reason2 == RewardService.REASON_STORAGE_FULL and #w2.pets == 0)
end
do
	local w = world({ addOk = false })
	local ok, reason = w.rt.grant(A, { { type = "bloxScaled", k = 1 }, { type = "potion", kind = "strength", count = 1 } }, "deny")
	check("블럭스 add 거부 → grant_failed · 포션도 안 줌(블럭스를 맨 앞에 둔 이유)", not ok and reason == RewardService.REASON_GRANT_FAILED
		and w.data.potions.strength == 0 and w.notified == 0)
	local w2 = world()
	w2.data = nil
	local ok2, reason2 = w2.rt.grant(A, { { type = "potion", kind = "strength", count = 1 } }, "np")
	check("프로필 없음 → no_profile", not ok2 and reason2 == RewardService.REASON_NO_PROFILE)
end

-- 4. PetService.grant — 보상 펫 발급(uid · 저장 공간 · 자동 장착 · 새 펫 저장) -------------------------------------------
do
	local data = Schema.new() :: any
	local saves = 0
	local rt = PetService._pure.createRuntime({
		now = function()
			return 0
		end,
		getData = function()
			return data
		end,
		getBlox = function()
			return BigNum.new(0, 0)
		end,
		subtractBlox = function()
			return false
		end,
		roll = function(tiers)
			return tiers[1], 1
		end,
		save = function()
			saves += 1
		end,
		setAttribute = function() end,
		hasSlotPass = function()
			return false
		end,
		hasStoragePass = function()
			return false
		end,
	})
	local ok, r = rt.grant(A, PET, "test")
	check("PetService.grant: uid \"1\" · 강화 1 · 빈 슬롯 자동 장착 · 새 펫이면 저장 1회", ok and r.uid == "1" and data.pets.owned["1"].tier == 1
		and r.equipped and data.pets.equipped[1] == "1" and r.isNew and saves == 1)
	local ok2, r2 = rt.grant(A, PET, "test")
	check("PetService.grant: 같은 종 두 번째는 중복(저장 안 함) · uid 2", ok2 and r2.uid == "2" and not r2.isNew and saves == 1)
	check("PetService.grant: 모르는 petId → invalid_request", (function()
		local okX, why = rt.grant(A, "nope", "x")
		return not okX and why == "invalid_request"
	end)())
	check("PetService.storageRoom = 저장 공간 − 보유", rt.storageRoom(A) == PetConfig.getStorage(false) - 2)
	for i = 3, PetConfig.getStorage(false) do
		data.pets.owned[tostring(i)] = { petId = PET, tier = 1 }
	end
	local okF, whyF = rt.grant(A, PET, "full")
	check("PetService.grant: 저장 공간 가득 → storage_full · 보유 수 그대로", not okF and whyF == PetService.REASON_STORAGE_FULL
		and rt.storageRoom(A) == 0)
end

print(string.format("[RewardServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[RewardServiceTests] %d test(s) failed", failed))
end

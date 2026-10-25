--!strict
-- PlayerStateService 검증: 스냅샷 형태 · 직렬화 왕복 · 같음 비교 · 로드 시 1회 · 빈도 상한 · sync 모음.
-- 실제 RemoteEvent 대신 기록용 deps로 runtime을 굴린다(RebirthServiceTests와 같은 패턴).

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Schema = require(ServerScriptService.Server.Data.Schema)
local PlayerStateService = require(ServerScriptService.Server.Systems.PlayerStateService)

local pure = PlayerStateService._pure

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

local function sampleData(): any
	local data = Schema.new()
	data.blox = BigNum.new(1.5, 3)
	data.strength = BigNum.new(2.25, 7)
	data.lifetimeBlox = BigNum.new(4, 5)
	data.lifeBlox = BigNum.new(3, 4)
	data.rebirths = BigNum.new(2.8, 1)
	data.progress.maxStage = 6
	return data
end

-- 1. 스냅샷 형태 --------------------------------------------------------------------------
do
	local data = sampleData()
	local snap = pure.buildSnapshot(data, 20, 36, 3)
	local allPresent = true
	for _, key in ipairs(pure.BIG_FIELDS) do
		local v = (snap :: any)[key]
		if not (type(v) == "table" and type(v.m) == "number" and type(v.e) == "number") then
			allPresent = false
		end
	end
	for _, key in ipairs(pure.NUMBER_FIELDS) do
		if type((snap :: any)[key]) ~= "number" then
			allPresent = false
		end
	end
	check("스냅샷: 모든 필드가 채워진다 (선택 필드 없음)", allPresent)
	check("스냅샷: blox 값", BigNum.eq(snap.blox, data.blox))
	check("스냅샷: lifeBlox 값", BigNum.eq(snap.lifeBlox, data.lifeBlox))
	check("스냅샷: 숫자 필드", snap.walkSpeed == 20 and snap.maxWalkSpeed == 36 and snap.maxStage == 6 and snap.padIndex == 3)

	data.blox.m = 9
	check("스냅샷: BigNum은 복사본 (프로필을 고쳐도 안 바뀐다)", snap.blox.m == 1.5)

	local weird = pure.buildSnapshot(data, 0 / 0, math.huge, nil)
	check("스냅샷: nan · inf · nil 숫자는 기본값", weird.walkSpeed == 0 and weird.maxWalkSpeed == 0 and weird.padIndex == 1)

	local broken = Schema.new()
	broken.progress = nil
	broken.lifeBlox = nil
	local b = pure.buildSnapshot(broken, 16, 16, 1)
	check("스냅샷: 빠진 필드는 0 · maxStage 1로 채운다", BigNum.eq(b.lifeBlox, BigNum.new(0, 0)) and b.maxStage == 1)
end

-- 2. 직렬화 왕복 (JSON으로 대신 잰다 — 문자열 키뿐 · 메타테이블 없음 · 유한한 숫자) ---------
do
	local snap = pure.buildSnapshot(sampleData(), 20, 36, 3)
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snap)
	check("직렬화: JSON으로 인코딩된다", ok)
	if ok then
		local back = HttpService:JSONDecode(encoded)
		check("직렬화: 왕복 뒤에도 같다", pure.snapshotsEqual(snap, back), encoded)
		check("직렬화: 왕복 뒤 BigNum을 BigNum 함수에 바로 넘길 수 있다", BigNum.gt(back.strength, back.blox))
	end
	check("직렬화: BigNum에 메타테이블이 없다", getmetatable(snap.blox :: any) == nil)
end

-- 3. 같음 비교 -----------------------------------------------------------------------------
do
	local a = pure.buildSnapshot(sampleData(), 20, 36, 3)
	local b = pure.buildSnapshot(sampleData(), 20, 36, 3)
	check("비교: 같은 입력이면 같다", pure.snapshotsEqual(a, b))
	local data = sampleData()
	data.strength = BigNum.new(2.26, 7)
	check("비교: 힘이 다르면 다르다", not pure.snapshotsEqual(a, pure.buildSnapshot(data, 20, 36, 3)))
	check("비교: padIndex가 다르면 다르다", not pure.snapshotsEqual(a, pure.buildSnapshot(sampleData(), 20, 36, 4)))
	check("비교: walkSpeed가 다르면 다르다", not pure.snapshotsEqual(a, pure.buildSnapshot(sampleData(), 21, 36, 3)))
	check("비교: nil과는 다르다", not pure.snapshotsEqual(a, nil))
	local upgraded = sampleData()
	upgraded.upgrades.punchSpeed = 2
	check("비교: 업그레이드 레벨이 다르면 다르다(지시서 #7)", not pure.snapshotsEqual(a, pure.buildSnapshot(upgraded, 20, 36, 3)))
end

-- 3b. 업그레이드 레벨 (지시서 #7) ----------------------------------------------------------
do
	local data = sampleData()
	data.upgrades.punchDamage = 4
	data.upgrades.bloxGain = 1
	local snap = pure.buildSnapshot(data, 20, 36, 3)
	local count = 0
	for _ in pairs(snap.upgrades) do
		count += 1
	end
	check("업그레이드: Config 7키 전부 실린다(L3 — moveSpeed 없음)", count == 7 and snap.upgrades.moveSpeed == nil, tostring(count))
	check("업그레이드: 레벨 값", snap.upgrades.punchDamage == 4 and snap.upgrades.bloxGain == 1 and snap.upgrades.punchSpeed == 0)
	data.upgrades.punchDamage = 9
	check("업그레이드: 표는 복사본 (프로필을 고쳐도 안 바뀐다)", snap.upgrades.punchDamage == 4)
	local broken = Schema.new()
	broken.upgrades = nil
	local b = pure.buildSnapshot(broken, 16, 16, 1)
	check("업그레이드: 표가 없으면 전부 0", b.upgrades.punchDamage == 0 and b.upgrades.petSlots == 0)
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snap)
	check("업그레이드: JSON 왕복 뒤에도 같다", ok and pure.snapshotsEqual(snap, HttpService:JSONDecode(encoded)))
end

-- 3c. 칭호 요약 (지시서 #10) -------------------------------------------------------------
do
	local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
	local T = TitleConfig.Titles
	local data = sampleData()
	data.cosmetics.ownedTitles[T[3].id] = true
	data.cosmetics.ownedTitles[T[2].id] = true
	data.cosmetics.equippedTitle = T[3].id
	local snap = pure.buildSnapshot(data, 20, 36, 3)
	check("칭호: 요약이 실린다 (owned 희귀도 순 · equipped · autoRoll)",
		type(snap.titles) == "table" and #snap.titles.owned == 2 and snap.titles.owned[1] == T[2].id
			and snap.titles.equipped == T[3].id and snap.titles.autoRoll == false)
	local base = pure.buildSnapshot(sampleData(), 20, 36, 3)
	check("칭호: 빈 프로필은 owned {} · equipped \"\" (선택 필드 없음)", #base.titles.owned == 0 and base.titles.equipped == "")
	check("비교: 칭호 보유가 다르면 다르다", not pure.snapshotsEqual(base, snap))
	local auto = sampleData()
	auto.rolling.autoRollTitle = true
	check("비교: 자동 롤 토글이 다르면 다르다", not pure.snapshotsEqual(base, pure.buildSnapshot(auto, 20, 36, 3)))
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snap)
	check("칭호: JSON 왕복 뒤에도 같다", ok and pure.snapshotsEqual(snap, HttpService:JSONDecode(encoded)))
	local okEmpty, encEmpty = pcall(HttpService.JSONEncode, HttpService, base)
	check("칭호: 빈 owned도 JSON 왕복 뒤 같다", okEmpty and pure.snapshotsEqual(base, HttpService:JSONDecode(encEmpty)))
end

-- 3d. 아우라 요약 (지시서 #11) ---------------------------------------------------------------
do
	local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
	local A = AuraConfig.Packs[1].auras
	local data = sampleData()
	data.cosmetics.ownedAuras[A[2].id] = true
	data.cosmetics.equippedAura = A[2].id
	data.rolling.selectedPack = 2
	local snap = pure.buildSnapshot(data, 20, 36, 3)
	check("아우라: 요약이 실린다 (owned · equipped · selectedPack · hideOtherAuras)", type(snap.auras) == "table" and #snap.auras.owned == 1
		and snap.auras.equipped == A[2].id and snap.auras.selectedPack == 2 and snap.auras.hideOtherAuras == false)
	local base = pure.buildSnapshot(sampleData(), 20, 36, 3)
	check("비교: 아우라 보유가 다르면 다르다", not pure.snapshotsEqual(base, snap))
	local hide = sampleData()
	hide.cosmetics.hideOtherAuras = true
	check("비교: 숨기기 설정이 다르면 다르다", not pure.snapshotsEqual(base, pure.buildSnapshot(hide, 20, 36, 3)))
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snap)
	check("아우라: JSON 왕복 뒤에도 같다", ok and pure.snapshotsEqual(snap, HttpService:JSONDecode(encoded)))
end

-- 3e. 펫 요약 (지시서 #12) ---------------------------------------------------------------
do
	local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)
	local E = PetConfig.Eggs[1].pets
	local data = sampleData()
	data.pets.owned["1"] = { petId = E[2].id, tier = 1 }
	data.pets.owned["2"] = { petId = E[3].id, tier = 2 }
	data.pets.equipped = { "2" }
	data.pets.nextUid = 3
	local snap = pure.buildSnapshot(data, 20, 36, 3)
	check("펫: 요약이 실린다 (owned · equipped · 파생 슬롯 · 저장 공간 · 숨기기)", type(snap.pets) == "table" and #snap.pets.owned == 2
		and snap.pets.owned[2].level == 2 and snap.pets.equipped[1] == "2" and snap.pets.slots == PetConfig.getSlots(0, false)
		and snap.pets.storage == PetConfig.getStorage(false) and snap.pets.hideOtherPets == false)
	local base = pure.buildSnapshot(sampleData(), 20, 36, 3)
	check("비교: 펫 보유가 다르면 다르다", not pure.snapshotsEqual(base, snap))
	local crafted = sampleData()
	crafted.pets.owned["1"] = { petId = E[2].id, tier = 1 }
	crafted.pets.owned["2"] = { petId = E[3].id, tier = 3 }
	crafted.pets.equipped = { "2" }
	check("비교: 강화 단계가 다르면 다르다", not pure.snapshotsEqual(snap, pure.buildSnapshot(crafted, 20, 36, 3)))
	local unequipped = sampleData()
	unequipped.pets.owned = data.pets.owned
	check("비교: 장착이 다르면 다르다", not pure.snapshotsEqual(snap, pure.buildSnapshot(unequipped, 20, 36, 3)))
	local slotUp = sampleData()
	slotUp.upgrades.petSlots = 1
	check("비교: 파생 슬롯이 다르면 다르다", not pure.snapshotsEqual(base, pure.buildSnapshot(slotUp, 20, 36, 3)))
	local hide = sampleData()
	hide.cosmetics.hideOtherPets = true
	check("비교: 펫 숨기기 설정이 다르면 다르다", not pure.snapshotsEqual(base, pure.buildSnapshot(hide, 20, 36, 3)))
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snap)
	check("펫: JSON 왕복 뒤에도 같다", ok and pure.snapshotsEqual(snap, HttpService:JSONDecode(encoded)))
	local okE, encE = pcall(HttpService.JSONEncode, HttpService, base)
	check("펫: 빈 보유 · 빈 장착도 JSON 왕복 뒤 같다", okE and pure.snapshotsEqual(base, HttpService:JSONDecode(encE)))
end

-- 4. 런타임 — 로드 시 1회 · 바뀔 때만 · 빈도 상한 -----------------------------------------
local fakePlayer: any = { Name = "PlayerStateTest", UserId = 1 }

local function newWorld()
	local w = { snapshot = pure.buildSnapshot(sampleData(), 20, 36, 3) :: any, sends = 0, syncs = 0, loaded = true }
	local runtime = pure.createRuntime({
		readSnapshot = function(_player)
			return if w.loaded then w.snapshot else nil
		end,
		sendState = function(_player, _snapshot)
			w.sends += 1
		end,
		syncRun = function(_player)
			w.syncs += 1
		end,
	})
	return w, runtime
end

do
	local w, runtime = newWorld()
	runtime.onLoaded(fakePlayer, 100)
	check("로드: 프로필 로드 직후 정확히 1회 보낸다", w.sends == 1)
	runtime.tick(100 + pure.SEND_PERIOD * 2)
	check("로드: 값이 그대로면 더 보내지 않는다", w.sends == 1)

	local data = sampleData()
	data.blox = BigNum.new(1.6, 3)
	w.snapshot = pure.buildSnapshot(data, 20, 36, 3)
	runtime.tick(100 + pure.SEND_PERIOD * 3)
	check("변경: 바뀌면 다음 틱에 보낸다", w.sends == 2)
end

do
	local w, runtime = newWorld()
	runtime.onLoaded(fakePlayer, 0)
	-- 1초 동안 0.01초마다 값이 바뀐다(클릭으로 힘이 계속 오르는 상황). 상한은 SEND_PERIOD당 1회.
	local t = 0
	local i = 0
	while t < 1 do
		t += 0.01
		i += 1
		local data = sampleData()
		data.strength = BigNum.new(1 + i / 1000, 7)
		w.snapshot = pure.buildSnapshot(data, 20, 36, 3)
		runtime.tick(t)
	end
	local maxAllowed = 1 + math.ceil(1 / pure.SEND_PERIOD)
	check("빈도 상한: 1초에 값이 100번 바뀌어도 SEND_PERIOD당 1회 이하", w.sends <= maxAllowed, string.format("%d회 (상한 %d)", w.sends, maxAllowed))
	check("빈도 상한: 그래도 보내긴 한다", w.sends >= 2, tostring(w.sends))
end

do
	local w, runtime = newWorld()
	w.loaded = false
	runtime.onLoaded(fakePlayer, 0)
	check("로드: 프로필이 없으면 보내지 않는다", w.sends == 0)
end

-- 5. sync 모음 -----------------------------------------------------------------------------
do
	local w, runtime = newWorld()
	runtime.onLoaded(fakePlayer, 0)
	local sendsAfterLoad = w.sends
	for k = 1, 4 do
		runtime.onSyncRequest(fakePlayer, 0.01 * k) -- 수신부 넷이 거의 동시에 요청
	end
	runtime.tick(0.1)
	check("sync: 모으는 창 안에서는 아직 답하지 않는다", w.syncs == 0)
	runtime.tick(0.01 + pure.SYNC_COALESCE_SEC + 0.01)
	check("sync: 네 요청을 한 번으로 모아 런 상태를 보낸다", w.syncs == 1, tostring(w.syncs))
	check("sync: 값이 그대로여도 PlayerState 전체를 다시 보낸다", w.sends == sendsAfterLoad + 1, tostring(w.sends))
	runtime.tick(5)
	check("sync: 만기 뒤 더 보내지 않는다", w.syncs == 1)
end

do
	-- 수신부는 프로필 로드보다 먼저 요청한다 — 기억했다가 로드 뒤에 답해야 한다.
	local w, runtime = newWorld()
	runtime.onSyncRequest(fakePlayer, 0)
	runtime.onSyncRequest(fakePlayer, 0.01)
	runtime.tick(1)
	check("sync: 로드 전 요청에는 아직 답하지 않는다", w.syncs == 0 and w.sends == 0)
	runtime.onLoaded(fakePlayer, 2)
	runtime.tick(2 + pure.SYNC_COALESCE_SEC + 0.01)
	check("sync: 로드 전 요청은 로드 뒤 한 번 답한다", w.syncs == 1, tostring(w.syncs))
	runtime.tick(10)
	check("sync: 그 뒤로 더 답하지 않는다", w.syncs == 1)
end

do
	local _w, runtime = newWorld()
	runtime.onLoaded(fakePlayer, 0)
	local accepted = 0
	for _ = 1, pure.SYNC_MAX_PER_WINDOW + 5 do
		if runtime.onSyncRequest(fakePlayer, 1) then
			accepted += 1
		end
	end
	check("sync: 창 안 요청 수에 상한이 있다", accepted == pure.SYNC_MAX_PER_WINDOW, tostring(accepted))
end

do
	local w, runtime = newWorld()
	runtime.onCharacterAdded(fakePlayer)
	check("리스폰: 로드 전에는 아무것도 안 한다", w.syncs == 0)
	runtime.onLoaded(fakePlayer, 0)
	runtime.onCharacterAdded(fakePlayer)
	check("리스폰: 로드 뒤에는 런 상태를 다시 보낸다", w.syncs == 1)
	runtime.onRemoving(fakePlayer)
	local data = sampleData()
	data.blox = BigNum.new(7, 7)
	w.snapshot = pure.buildSnapshot(data, 20, 36, 3)
	runtime.tick(10)
	check("퇴장: 나간 플레이어에게는 더 보내지 않는다", w.sends == 1)
end

-- 3z. 상점 요약 (지시서 #16 — 세션 값: 보유 게임패스 · 행운 상품 제한) -------------------------------------
do
	local base = pure.buildSnapshot(sampleData(), 20, 36, 3)
	check("상점: 없으면 보유 없음 · 제한(확인 전과 같다)", type(base.shop) == "table" and #base.shop.gamepasses == 0
		and base.shop.paidRandomRestricted == true)
	local owned = pure.buildSnapshot(sampleData(), 20, 36, 3, nil, { gamepasses = { "damage2x", "strength8x" }, paidRandomRestricted = false })
	check("상점: 넘긴 요약이 그대로 실린다", #owned.shop.gamepasses == 2 and owned.shop.gamepasses[2] == "strength8x"
		and owned.shop.paidRandomRestricted == false)
	check("비교: 보유 게임패스가 다르면 다르다", not pure.snapshotsEqual(base, owned))
	local open = pure.buildSnapshot(sampleData(), 20, 36, 3, nil, { gamepasses = {}, paidRandomRestricted = false })
	check("비교: 제한 여부만 달라도 다르다", not pure.snapshotsEqual(base, open))
	local same = pure.buildSnapshot(sampleData(), 20, 36, 3, nil, { gamepasses = { "damage2x", "strength8x" }, paidRandomRestricted = false })
	check("비교: 같은 상점 요약이면 같다", pure.snapshotsEqual(owned, same))
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, owned)
	check("상점: JSON 왕복 뒤에도 같다", ok and pure.snapshotsEqual(owned, HttpService:JSONDecode(encoded)))
end

print(string.format("[PlayerStateServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[PlayerStateServiceTests] %d test(s) failed", failed))
end

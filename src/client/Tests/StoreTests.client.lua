--!strict
-- Store 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-1 착수 준비.
--
-- ⚠️ 이 파일은 싱글톤을 쓰지 않는다. 자기 인스턴스(Store.new())로 검사한다.
--
-- U3-9 이전에는 싱글톤에 직접 setSource를 걸고 마지막에 더미값으로 되돌리는
-- 방식이었다. 그 "되돌리기"로는 부족했다 — 이 파일이 도는 0.86초 동안
-- PowerBlockTests와 실물 HUD 6종이 같은 싱글톤을 동시에 밟았고, 복원은 맨 끝에
-- 한 번뿐이라 중간 구간이 통째로 무방비였다. 실측으로 여기서 4건이 깨졌고
-- (검사 시점에 이미 다른 주체가 값을 바꿨다), 반대로 여기서 건 walkSpeed=1000이
-- PowerBlockTests의 SpeedValue 검사를 깼다.
--
-- 이름 접두어로 가리는 것으로는 안 된다(→ ScreenController.lua의 U3-4 주석,
-- closeAll()이 실물 HUD를 껐던 그 부류). 상태 자체를 분리한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Store = require(script.Parent.Parent.UI.Store)
local TestHelpers = require(script.Parent.TestHelpers)
local checkClose = TestHelpers.checkClose

type BigNumber = BigNum.BigNumber

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

local function isBigNumShape(value: any): boolean
	return type(value) == "table" and type(value.m) == "number" and type(value.e) == "number"
end

-- Store.lua DUMMY_STATE와 동일한 기대 더미값. 새 인스턴스의 초기 상태가 이것이다.
local ORIGINAL_STRENGTH = BigNum.new(9.99, 20)
local DUMMY_MAX_STAGE = 17

-- 이 파일 전용 인스턴스. 싱글톤과 어떤 상태도 공유하지 않으므로 끝에서 되돌릴
-- 것이 없다 — 파일이 끝나면 그냥 버려진다.
local store = Store.new()

-- 1. get이 초기값을 돌려준다 -------------------------------------------------------
--
-- ⚠️ "level" 키는 없다(U3-6에서 제거 — Store.lua 상단 주석 참고). 레벨은
-- LevelConfig.getLevel(strength)로만 계산한다.

check("get('walkSpeed')이 number다", type(store.get("walkSpeed")) == "number")
check("get('maxWalkSpeed')이 number다", type(store.get("maxWalkSpeed")) == "number")
check("get('maxStage')이 number다", type(store.get("maxStage")) == "number")

-- U3-5: walkSpeed/maxWalkSpeed 더미값이 4자리를 꽉 채운다 (docs/UI.md "이동 속도 조절은
-- 편의 기능이 아니다" — 실제 값(2자리)에 칸을 맞춰 좁히면 안 되므로, 더미값 자체를
-- 4자리로 둬서 G4에서 눈으로 확인할 수 있게 한다).
check("더미 walkSpeed가 4자리다", store.get("walkSpeed") >= 1000 and store.get("walkSpeed") <= 9999)
check("더미 maxWalkSpeed가 4자리다", store.get("maxWalkSpeed") >= 1000 and store.get("maxWalkSpeed") <= 9999)

check("get('strength')가 BigNum 형태다", isBigNumShape(store.get("strength")))
check("get('blox')가 BigNum 형태다", isBigNumShape(store.get("blox")))
check("get('lifetimeBlox')가 BigNum 형태다", isBigNumShape(store.get("lifetimeBlox")))
check("get('rebirths')가 BigNum 형태다", isBigNumShape(store.get("rebirths")))

-- 이 검사가 U3-9에서 깨졌던 것이다. 약화하지 않고 그대로 둔다 — 자기 인스턴스라
-- 아무도 이 값을 먼저 건드릴 수 없으므로 다시 참이어야 한다.
check("초기 strength가 더미값과 같다", BigNum.eq(store.get("strength"), ORIGINAL_STRENGTH))

-- get이 내부 상태의 사본을 돌려주는지 (StrengthMultiplier 반환값 오염 방지 테스트와
-- 같은 이유 — 호출자가 반환값을 고쳐도 다음 get이 오염되면 안 된다).
do
	local first = store.get("strength")
	first.m = 999
	local second = store.get("strength")
	check("get 반환값을 고쳐도 다음 get이 오염되지 않는다", BigNum.eq(second, ORIGINAL_STRENGTH))
end

-- 2. 값이 바뀌면 구독자가 불린다 ----------------------------------------------------
--
-- 메커니즘 자체(구독/통지/unsubscribe)를 재는 절이라 어느 number 키를 써도
-- 무방하다 — "level" 대신 "walkSpeed"를 쓴다(U3-6, level 제거에 따른 교체).

do
	local received: number? = nil
	local handle = store.subscribe("walkSpeed", function(value: any)
		received = value :: number
	end)

	store.setSource(function(setter)
		setter("walkSpeed", 999)
	end)

	task.wait() -- setValue의 콜백 통지는 task.spawn으로 비동기 발화된다

	check("구독자가 새 값으로 불린다", received == 999, tostring(received))

	-- 3. unsubscribe 후에는 안 불린다 ----------------------------------------------

	store.unsubscribe(handle)
	received = nil

	-- ⚠️ 이 1000이 PowerBlockTests의 "- 1000"으로 새어나갔던 값이다. 이제 이
	-- 인스턴스 밖으로 나가지 않는다(PowerBlockTests 6b가 반대편에서 확인한다).
	store.setSource(function(setter)
		setter("walkSpeed", 1000)
	end)
	task.wait()

	check("unsubscribe 후에는 콜백이 불리지 않는다", received == nil, tostring(received))
	check("unsubscribe와 무관하게 상태 자체는 갱신된다", checkClose(store.get("walkSpeed"), 1000))
end

-- 4. setSource로 소스를 갈아끼워도 구독자가 계속 동작한다 ---------------------------

do
	local calls = 0
	local handle = store.subscribe("maxStage", function(_value: any)
		calls += 1
	end)

	store.setSource(function(setter)
		setter("maxStage", 20)
	end)
	task.wait()

	-- 소스 자체를 다른 함수로 교체한다 (실제로는 더미 -> Remote 연결부 교체에 해당).
	store.setSource(function(setter)
		setter("maxStage", 21)
	end)
	task.wait()

	check("소스를 갈아끼운 뒤에도 이전 구독자가 계속 불린다", calls == 2, tostring(calls))
	check("소스 교체 후 최신값이 반영된다", checkClose(store.get("maxStage"), 21))

	store.unsubscribe(handle)
end

-- 5. BigNum 필드가 BigNum 형태를 유지한다 -------------------------------------------

do
	local received: any = nil
	local handle = store.subscribe("blox", function(value: any)
		received = value
	end)

	local newBlox = BigNum.new(1, 30)
	store.setSource(function(setter)
		setter("blox", newBlox)
	end)
	task.wait()

	check("갱신된 blox도 BigNum 형태를 유지한다", isBigNumShape(received))
	check("갱신된 blox 값이 맞다", isBigNumShape(received) and BigNum.eq(received, newBlox))
	check("get('blox')도 BigNum 형태를 유지한다", isBigNumShape(store.get("blox")))

	store.unsubscribe(handle)
end

-- 6. 인스턴스끼리 상태·구독자를 공유하지 않는다 --------------------------------------
--
-- 격리가 실제로 성립하는지 이 파일 안에서 직접 잰다. 여기가 통과하지 않으면
-- 위 1~5절이 통과한 것은 "이번엔 운이 좋았다"는 뜻일 뿐이다.

do
	local a = Store.new()
	local b = Store.new()

	a.setSource(function(setter)
		setter("walkSpeed", 111)
	end)
	b.setSource(function(setter)
		setter("walkSpeed", 222)
	end)
	task.wait()

	check("인스턴스 A의 상태가 B의 변경에 영향받지 않는다", checkClose(a.get("walkSpeed"), 111))
	check("인스턴스 B의 상태가 A의 변경에 영향받지 않는다", checkClose(b.get("walkSpeed"), 222))

	local aCalls, bCalls = 0, 0
	local aValue: number? = nil
	local handleA = a.subscribe("maxStage", function(value: any)
		aCalls += 1
		aValue = value :: number
	end)
	local handleB = b.subscribe("maxStage", function(_value: any)
		bCalls += 1
	end)

	a.setSource(function(setter)
		setter("maxStage", 42)
	end)
	task.wait()

	check("A의 구독자가 A의 변경으로 불린다", aCalls == 1, tostring(aCalls))
	check("B의 구독자는 A의 변경으로 불리지 않는다", bCalls == 0, tostring(bCalls))
	if aValue ~= nil then
		check("A의 구독자가 받은 값이 맞다", checkClose(aValue :: number, 42))
	else
		check("A의 구독자가 받은 값이 맞다", false, "콜백이 불리지 않았다")
	end
	check("B의 상태는 A의 변경 뒤에도 더미값 그대로다", checkClose(b.get("maxStage"), DUMMY_MAX_STAGE))

	a.unsubscribe(handleA)
	b.unsubscribe(handleB)

	-- BigNum 값은 테이블이다. 인스턴스들이 DUMMY_STATE의 같은 테이블을 참조하면
	-- 한쪽에서 고친 것이 다른 쪽에 보인다 (Store.freshState()가 막는 것).
	local aStrength = a.get("strength")
	aStrength.m = 999
	check(
		"한 인스턴스의 get 반환값을 고쳐도 다른 인스턴스가 오염되지 않는다",
		BigNum.eq(b.get("strength"), ORIGINAL_STRENGTH)
	)
end

-- 7. 싱글톤이 여전히 살아 있고 동작한다 (실물 HUD 경로) -------------------------------
--
-- 격리를 만드느라 실물 경로를 끊어먹지 않았는지 본다. maxStage를 쓰는 이유는
-- 이 키를 읽는 HUD가 하나도 없기 때문이다(grep 확인) — strength/walkSpeed였다면
-- 여기서 잠깐 바꾸는 동안 실물 PowerBlock이 그 값을 그리게 되고, PowerBlockTests와
-- 다시 경쟁하게 된다. 그래도 끝에서 더미값으로 되돌린다.

do
	check("Store.new가 함수다", type(Store.new) == "function")
	check("싱글톤 get이 더미 maxStage를 돌려준다", checkClose(Store.get("maxStage"), DUMMY_MAX_STAGE))

	local received: number? = nil
	local handle = Store.subscribe("maxStage", function(value: any)
		received = value :: number
	end)

	Store.setSource(function(setter)
		setter("maxStage", 20)
	end)
	task.wait()

	check("싱글톤 구독자가 새 값으로 불린다", received == 20, tostring(received))
	check("싱글톤 상태가 갱신된다", checkClose(Store.get("maxStage"), 20))

	Store.unsubscribe(handle)

	-- 자기 인스턴스의 변경이 싱글톤으로 새지 않는다. 이번 사고의 정확한 반대 방향
	-- 검사다 — store는 4절에서 maxStage=21이 됐지만 싱글톤은 20 그대로여야 한다.
	store.setSource(function(setter)
		setter("maxStage", 4321)
	end)
	task.wait()
	check("자기 인스턴스 변경이 싱글톤으로 새지 않는다", checkClose(Store.get("maxStage"), 20))

	-- 원상 복구 (싱글톤은 실물 HUD가 계속 쓴다).
	Store.setSource(function(setter)
		setter("maxStage", DUMMY_MAX_STAGE)
	end)
	task.wait()
	check("싱글톤이 더미값으로 복구된다", checkClose(Store.get("maxStage"), DUMMY_MAX_STAGE))
end

print(string.format("[StoreTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[StoreTests] %d test(s) failed", failed))
end

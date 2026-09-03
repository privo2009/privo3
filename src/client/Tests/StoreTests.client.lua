--!strict
-- Store 검증. Studio에서 Rojo 연결 후 Play 하면 클라 시작 시 자동 실행된다.
-- U3-1 착수 준비.
--
-- ⚠️ Store도 전역 싱글턴이다. 여기서 setSource로 값을 바꾸면 그 값이 프로세스가
-- 끝날 때까지 남는다 — 마지막에 원래 더미값으로 되돌려 다른 코드(향후 HUD)가
-- 이 테스트의 잔여값을 보지 않게 한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Store = require(script.Parent.Parent.UI.Store)

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

-- 원래 더미값을 복원할 때 쓴다 (BigNum.new(9.99, 20) 등, Store.lua DUMMY_STATE와 동일).
local ORIGINAL_STRENGTH = BigNum.new(9.99, 20)

-- 1. get이 초기값을 돌려준다 -------------------------------------------------------

check("get('level')이 number다", type(Store.get("level")) == "number")
check("get('walkSpeed')이 number다", type(Store.get("walkSpeed")) == "number")
check("get('maxWalkSpeed')이 number다", type(Store.get("maxWalkSpeed")) == "number")
check("get('maxStage')이 number다", type(Store.get("maxStage")) == "number")

-- U3-5: walkSpeed/maxWalkSpeed 더미값이 4자리를 꽉 채운다 (docs/UI.md "이동 속도 조절은
-- 편의 기능이 아니다" — 실제 값(2자리)에 칸을 맞춰 좁히면 안 되므로, 더미값 자체를
-- 4자리로 둬서 G4에서 눈으로 확인할 수 있게 한다).
check("더미 walkSpeed가 4자리다", Store.get("walkSpeed") >= 1000 and Store.get("walkSpeed") <= 9999)
check("더미 maxWalkSpeed가 4자리다", Store.get("maxWalkSpeed") >= 1000 and Store.get("maxWalkSpeed") <= 9999)

check("get('strength')가 BigNum 형태다", isBigNumShape(Store.get("strength")))
check("get('blox')가 BigNum 형태다", isBigNumShape(Store.get("blox")))
check("get('lifetimeBlox')가 BigNum 형태다", isBigNumShape(Store.get("lifetimeBlox")))
check("get('rebirths')가 BigNum 형태다", isBigNumShape(Store.get("rebirths")))

check("초기 strength가 더미값과 같다", BigNum.eq(Store.get("strength"), ORIGINAL_STRENGTH))

-- get이 내부 상태의 사본을 돌려주는지 (StrengthMultiplier 반환값 오염 방지 테스트와
-- 같은 이유 — 호출자가 반환값을 고쳐도 다음 get이 오염되면 안 된다).
do
	local first = Store.get("strength")
	first.m = 999
	local second = Store.get("strength")
	check("get 반환값을 고쳐도 다음 get이 오염되지 않는다", BigNum.eq(second, ORIGINAL_STRENGTH))
end

-- 2. 값이 바뀌면 구독자가 불린다 ----------------------------------------------------

do
	local received: number? = nil
	local handle = Store.subscribe("level", function(value: any)
		received = value :: number
	end)

	Store.setSource(function(setter)
		setter("level", 999)
	end)

	task.wait() -- setValue의 콜백 통지는 task.spawn으로 비동기 발화된다

	check("구독자가 새 값으로 불린다", received == 999)

	-- 3. unsubscribe 후에는 안 불린다 ----------------------------------------------

	Store.unsubscribe(handle)
	received = nil

	Store.setSource(function(setter)
		setter("level", 1000)
	end)
	task.wait()

	check("unsubscribe 후에는 콜백이 불리지 않는다", received == nil)
	check("unsubscribe와 무관하게 상태 자체는 갱신된다", Store.get("level") == 1000)
end

-- 4. setSource로 소스를 갈아끼워도 구독자가 계속 동작한다 ---------------------------

do
	local calls = 0
	local handle = Store.subscribe("maxStage", function(_value: any)
		calls += 1
	end)

	Store.setSource(function(setter)
		setter("maxStage", 20)
	end)
	task.wait()

	-- 소스 자체를 다른 함수로 교체한다 (실제로는 더미 -> Remote 연결부 교체에 해당).
	Store.setSource(function(setter)
		setter("maxStage", 21)
	end)
	task.wait()

	check("소스를 갈아끼운 뒤에도 이전 구독자가 계속 불린다", calls == 2)
	check("소스 교체 후 최신값이 반영된다", Store.get("maxStage") == 21)

	Store.unsubscribe(handle)
end

-- 5. BigNum 필드가 BigNum 형태를 유지한다 -------------------------------------------

do
	local received: any = nil
	local handle = Store.subscribe("blox", function(value: any)
		received = value
	end)

	local newBlox = BigNum.new(1, 30)
	Store.setSource(function(setter)
		setter("blox", newBlox)
	end)
	task.wait()

	check("갱신된 blox도 BigNum 형태를 유지한다", isBigNumShape(received))
	check("갱신된 blox 값이 맞다", isBigNumShape(received) and BigNum.eq(received, newBlox))
	check("get('blox')도 BigNum 형태를 유지한다", isBigNumShape(Store.get("blox")))

	Store.unsubscribe(handle)
end

-- 원상 복구 (다른 테스트·향후 HUD가 이 테스트의 잔여값을 보지 않게 한다).
Store.setSource(function(setter)
	setter("level", 128)
	setter("maxStage", 17)
	setter("blox", BigNum.new(9.99, 23))
end)

print(string.format("[StoreTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[StoreTests] %d test(s) failed", failed))
end

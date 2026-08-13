--!strict
-- CurrencyService 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 2-2 검증: 잔액 부족 / 음수 amount 거부 / lifetimeBlox 동반 증가 / 롤백.
--
-- CurrencyService._pure의 순수 함수만 호출한다 — Player/ProfileManager 없이,
-- {strength=BigNumber, blox=BigNumber, lifetimeBlox=BigNumber} 형태의 평범한 테이블만으로 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local CurrencyService = require(script.Parent.CurrencyService)

local pure = CurrencyService._pure

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function freshData()
	return {
		strength = BigNum.new(1, 0), -- 1
		blox = BigNum.new(5, 1), -- 50
		lifetimeBlox = BigNum.new(5, 1), -- 50
	}
end

-- 1. CURRENCIES 목록 ------------------------------------------------------------------

check("CURRENCIES.strength == true", CurrencyService.CURRENCIES.strength == true)
check("CURRENCIES.blox == true", CurrencyService.CURRENCIES.blox == true)
check("CURRENCIES.lifetimeBlox는 없음 (직접 증감 대상 아님)", CurrencyService.CURRENCIES.lifetimeBlox == nil)

-- 2. applyAdd: 정상 증가 ---------------------------------------------------------------

do
	local data = freshData()
	local ok, updates = pure.applyAdd("strength", data, BigNum.new(2, 0)) -- +2
	check("add 정상: ok == true", ok == true)
	check(
		"add 정상: strength 1 + 2 == 3",
		ok and updates ~= nil and BigNum.eq(updates.strength, BigNum.new(3, 0)),
		ok and updates and BigNum.tostring(updates.strength) or "no updates"
	)
	check("add는 data를 직접 수정하지 않음 (순수 함수)", BigNum.eq(data.strength, BigNum.new(1, 0)))
end

-- 3. applyAdd: blox 증가 시 lifetimeBlox도 동일량 증가 -------------------------------------

do
	local data = freshData()
	local ok, updates = pure.applyAdd("blox", data, BigNum.new(1, 1)) -- +10
	check("add(blox) ok == true", ok == true)
	check(
		"add(blox): blox 50 + 10 == 60",
		ok and updates ~= nil and BigNum.eq(updates.blox, BigNum.new(6, 1)),
		ok and updates and BigNum.tostring(updates.blox) or "no updates"
	)
	check(
		"add(blox): lifetimeBlox도 50 + 10 == 60으로 동일 증가",
		ok and updates ~= nil and BigNum.eq(updates.lifetimeBlox, BigNum.new(6, 1)),
		ok and updates and BigNum.tostring(updates.lifetimeBlox) or "no updates"
	)
end

do
	local data = freshData()
	local ok, updates = pure.applyAdd("strength", data, BigNum.new(2, 0))
	check("add(strength)는 lifetimeBlox를 건드리지 않음", ok and updates ~= nil and updates.lifetimeBlox == nil)
end

-- 4. applyAdd: 음수 amount 거부 (add로 subtract 흉내내기 방지) -----------------------------

do
	local data = freshData()
	local ok, updates, err = pure.applyAdd("strength", data, BigNum.new(-2, 0))
	check("add에 음수 amount는 거부됨", ok == false and updates == nil)
	check("거부 사유 메시지가 있음", type(err) == "string" and #(err :: string) > 0)
end

-- 5. applyAdd: 잘못된 BigNum 형태 거부 -----------------------------------------------------

do
	local data = freshData()
	local ok = pure.applyAdd("strength", data, { m = math.huge, e = 0 })
	check("add에 inf mantissa는 거부됨", ok == false)
end

do
	local data = freshData()
	local ok = pure.applyAdd("strength", data, nil)
	check("add에 nil amount는 거부됨", ok == false)
end

-- 6. applySubtract: 정상 감소, lifetimeBlox는 건드리지 않음 --------------------------------

do
	local data = freshData()
	local ok, updates = pure.applySubtract("blox", data, BigNum.new(2, 1)) -- -20
	check("subtract 정상: ok == true", ok == true)
	check(
		"subtract 정상: blox 50 - 20 == 30",
		ok and updates ~= nil and BigNum.eq(updates.blox, BigNum.new(3, 1)),
		ok and updates and BigNum.tostring(updates.blox) or "no updates"
	)
	check("subtract는 lifetimeBlox를 건드리지 않음", ok and updates ~= nil and updates.lifetimeBlox == nil)
end

-- 7. applySubtract: 잔액 부족 시 실패, 절대 음수 잔액을 만들지 않음 --------------------------

do
	local data = freshData() -- blox = 50
	local ok, updates, err = pure.applySubtract("blox", data, BigNum.new(6, 1)) -- -60 > 잔액
	check("잔액 부족이면 subtract 실패", ok == false and updates == nil)
	check("잔액 부족 사유 메시지가 있음", type(err) == "string" and #(err :: string) > 0)
end

-- 8. applySubtract: 음수 amount 거부 -------------------------------------------------------

do
	local data = freshData()
	local ok = pure.applySubtract("blox", data, BigNum.new(-5, 0))
	check("subtract에 음수 amount는 거부됨", ok == false)
end

-- 9. applySet: 직접 대입, lifetimeBlox는 건드리지 않음 (환생/관리 전용) ----------------------

do
	local data = freshData()
	local ok, updates = pure.applySet("strength", data, BigNum.new(1, 0)) -- 환생으로 힘 초기화
	check("set 정상: ok == true", ok == true)
	check(
		"set 정상: strength가 amount로 대입됨",
		ok and updates ~= nil and BigNum.eq(updates.strength, BigNum.new(1, 0))
	)
end

do
	local data = freshData()
	local ok, updates = pure.applySet("blox", data, BigNum.new(0, 0))
	check("set(blox)은 lifetimeBlox를 건드리지 않음 (환생 진척도 유지)", ok and updates ~= nil and updates.lifetimeBlox == nil)
end

do
	local data = freshData()
	local ok = pure.applySet("strength", data, BigNum.new(-1, 0))
	check("set에 음수 amount는 거부됨", ok == false)
end

-- 10. applyUpdatesWithRollback: 정상 적용 --------------------------------------------------

do
	local data = freshData()
	local ok, err = pure.applyUpdatesWithRollback(data, {
		blox = BigNum.new(6, 1),
		lifetimeBlox = BigNum.new(6, 1),
	})
	check("정상 업데이트는 성공", ok == true, err)
	check("정상 업데이트 후 data.blox가 실제로 바뀜", BigNum.eq(data.blox, BigNum.new(6, 1)))
	check("정상 업데이트 후 data.lifetimeBlox가 실제로 바뀜", BigNum.eq(data.lifetimeBlox, BigNum.new(6, 1)))
end

-- 11. applyUpdatesWithRollback: 손상된 결과는 롤백 (inf/nan이 프로필에 들어가면 영구 손상) ----

do
	local data = freshData()
	local originalBlox = data.blox
	local originalLifetime = data.lifetimeBlox

	local ok, err = pure.applyUpdatesWithRollback(data, {
		blox = { m = math.huge, e = 0 }, -- 손상된 연산 결과를 흉내냄
		lifetimeBlox = BigNum.new(6, 1),
	})

	check("손상된 필드가 있으면 applyUpdatesWithRollback은 실패 반환", ok == false)
	check("실패 사유 메시지가 있음", type(err) == "string" and #(err :: string) > 0)
	check("롤백 후 data.blox가 원래 값으로 복원됨", BigNum.eq(data.blox, originalBlox))
	check("롤백 후 data.lifetimeBlox도 원래 값으로 복원됨 (같은 updates에 묶여 있었으므로)", BigNum.eq(data.lifetimeBlox, originalLifetime))
end

-- 12. applyAdd: amount == 0은 즉시 noop 성공, 값 불변, lifetimeBlox도 안 건드림 --------------

do
	local data = freshData() -- blox = 50
	local ok, updates, err, isNoop = pure.applyAdd("blox", data, BigNum.new(0, 0))
	check("add(0)은 성공으로 처리됨", ok == true, err)
	check("add(0)은 isNoop == true를 반환함", isNoop == true)
	check(
		"add(0) 후 값이 그대로임 (blox 50 유지)",
		ok and updates ~= nil and BigNum.eq(updates.blox, BigNum.new(5, 1)),
		ok and updates and BigNum.tostring(updates.blox) or "no updates"
	)
	check("add(0)은 blox여도 lifetimeBlox를 건드리지 않음", ok and updates ~= nil and updates.lifetimeBlox == nil)
end

-- 13. applySubtract: amount == 0은 잔액과 무관하게 즉시 noop 성공 -----------------------------

do
	-- 잔액이 0이라 조금이라도 빼면 잔액 부족이 나야 정상인 상황에서, amount도 0이면
	-- 잔액 부족 검사 자체가 실행되지 않고 그냥 성공해야 한다.
	local data = freshData()
	data.blox = BigNum.new(0, 0)

	local ok, updates, err, isNoop = pure.applySubtract("blox", data, BigNum.new(0, 0))
	check("subtract(0)은 잔액이 0이어도 잔액 부족으로 실패하지 않음", ok == true, err)
	check("subtract(0)은 isNoop == true를 반환함", isNoop == true)
	check(
		"subtract(0) 후 값이 그대로임 (0 유지)",
		ok and updates ~= nil and BigNum.eq(updates.blox, BigNum.new(0, 0)),
		ok and updates and BigNum.tostring(updates.blox) or "no updates"
	)
end

print(string.format("[CurrencyServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[CurrencyServiceTests] %d test(s) failed", failed))
end

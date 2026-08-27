--!strict
-- CLAUDE.md 절대 규칙 2의 단일 게이트. 모든 재화 증감은 이 모듈만 통과한다.
-- profile.Data.strength / profile.Data.blox를 직접 대입하는 코드는 이 파일 밖에 있으면 안 된다.
--
-- 대상 재화:
--   strength    — 힘. 환생(rebirth) 시 CurrencyService.set으로 초기화됨
--   blox        — 블럭스. add로 증가할 때마다 lifetimeBlox(환생 진척도)도 동일량 증가
--   rebirths    — 환생 배수. add로만 늘고 줄지 않는다 (4-2-d)
--
-- ⚠️ lifetimeBlox는 여기 없다. 그건 blox add에 딸려 오르는 파생 필드이지 직접 증감 대상이
--    아니다. 목록에 넣으면 blox를 거치지 않고 진척도만 올리는 경로가 생긴다.
--    rebirths는 반대다 — DESIGN "3. 화폐와 배수 > 환생"이 못박은 대로 **역산 불가능한
--    독립 필드**이므로(누적 블럭스 파생값으로 두면 환생 버튼을 누를 이유가 사라진다)
--    직접 증감 대상이 맞다.
--
-- 순수 계산 로직(applyAdd/applySubtract/applySet/applyUpdatesWithRollback)은 profile이나
-- Player 없이 {[string]: BigNumber} 형태의 data 테이블만으로 동작하도록 분리했다.
-- CurrencyServiceTests.server.lua가 이 함수들을 CurrencyService._pure로 직접 호출해서
-- 프로필 로드 없이 검증한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Schema = require(script.Parent.Parent.Data.Schema)
local ProfileManager = require(script.Parent.Parent.Data.ProfileManager)

type BigNumber = BigNum.BigNumber

local CurrencyService = {}

-- 이 API로 다룰 수 있는 재화 이름. 여기 없는 문자열이 들어오면 호출부 버그이므로 assert로 막는다.
local CURRENCIES: { [string]: boolean } = {
	strength = true,
	blox = true,
	rebirths = true,
}
CurrencyService.CURRENCIES = CURRENCIES

-- amount 자체의 형태/부호 검증. add에 음수를 넣어 subtract를 흉내내는 것을 막는다.
local function validateAmount(amount: any): (boolean, string?)
	if amount == nil or not Schema.isBigNum(amount) then
		return false, "amount가 올바른 BigNum({m,e}) 형태가 아님"
	end
	if amount.m < 0 then
		return false, "amount는 음수일 수 없음"
	end
	return true, nil
end

-- ===== 순수 계산 로직 (profile/Player 의존 없음) =====================================

-- data[currency]에 amount를 더한 결과를 updates로 반환한다 (data는 수정하지 않음).
-- currency == "blox"면 lifetimeBlox도 같은 양만큼 증가시켜 updates에 함께 담는다.
-- 네 번째 반환값(isNoop)은 amount.m == 0이라 실질적으로 아무 것도 안 바뀌었음을 알리는 신호다 —
-- 공개 API가 이걸 보고 로깅을 건너뛴다.
local function applyAdd(currency: string, data: { [string]: any }, amount: any): (boolean, { [string]: BigNumber }?, string?, boolean?)
	local validOk, validErr = validateAmount(amount)
	if not validOk then
		return false, nil, validErr
	end

	local current = data[currency]
	if not Schema.isBigNum(current) then
		return false, nil, string.format("%s 현재값이 올바른 BigNum이 아님", currency)
	end

	-- amount == 0: 보상 0, 배수 0 등 정상 흐름에서 흔히 발생한다. 값이 그대로이므로
	-- lifetimeBlox도 건드리지 않고 즉시 성공 처리한다 (아래 isNoop=true).
	if amount.m == 0 then
		return true, { [currency] = current }, nil, true
	end

	local updates: { [string]: BigNumber } = { [currency] = BigNum.add(current, amount) }

	-- ⚠️ lifetimeBlox 연동은 blox 전용이다. strength·rebirths는 이 분기를 타지 않는다 —
	-- 환생은 lifetimeBlox를 유지해야 하고(패드 해금 기준), rebirths add가 진척도를
	-- 올리면 환생할수록 패드가 저절로 열린다.
	if currency == "blox" then
		local currentLifetime = data.lifetimeBlox
		if not Schema.isBigNum(currentLifetime) then
			return false, nil, "lifetimeBlox 현재값이 올바른 BigNum이 아님"
		end
		updates.lifetimeBlox = BigNum.add(currentLifetime, amount)
	end

	return true, updates, nil, false
end

-- data[currency]에서 amount를 뺀 결과를 updates로 반환한다. lifetimeBlox는 건드리지 않는다.
-- 잔액이 부족하면 실패 반환 — 절대 음수 잔액을 만들지 않는다.
-- amount == 0은 applyAdd와 동일하게 즉시 성공/noop 처리한다 (잔액 부족 검사보다 먼저 걸림).
local function applySubtract(currency: string, data: { [string]: any }, amount: any): (boolean, { [string]: BigNumber }?, string?, boolean?)
	local validOk, validErr = validateAmount(amount)
	if not validOk then
		return false, nil, validErr
	end

	local current = data[currency]
	if not Schema.isBigNum(current) then
		return false, nil, string.format("%s 현재값이 올바른 BigNum이 아님", currency)
	end

	if amount.m == 0 then
		return true, { [currency] = current }, nil, true
	end

	if BigNum.lt(current, amount) then
		return false, nil, "잔액 부족"
	end

	return true, { [currency] = BigNum.sub(current, amount) }, nil, false
end

-- data[currency]를 amount로 직접 덮어쓴다 (환생/관리 전용). lifetimeBlox는 건드리지 않는다.
-- add/subtract와 달리 amount == 0을 특별 취급하지 않는다 — set에서 0은 "변화가 없다"가 아니라
-- "0으로 만들어라"라는 명시적 지시(예: 환생으로 strength를 초기화)이므로, 여느 값과 동일하게
-- 정상적으로 대입하고 로그도 그대로 남겨야 한다.
local function applySet(currency: string, data: { [string]: any }, amount: any): (boolean, { [string]: BigNumber }?, string?)
	local validOk, validErr = validateAmount(amount)
	if not validOk then
		return false, nil, validErr
	end

	if not Schema.isBigNum(data[currency]) then
		return false, nil, string.format("%s 현재값이 올바른 BigNum이 아님", currency)
	end

	return true, { [currency] = amount }, nil
end

-- updates를 data에 실제로 적용한다. 적용 후 각 필드를 Schema.isBigNum으로 재검증해서,
-- 하나라도 실패하면(inf/nan 등) 전부 원래 값으로 롤백한다. 프로필에 손상된 값이
-- 반영된 채로 남는 경우를 만들지 않기 위함이다.
local function applyUpdatesWithRollback(data: { [string]: any }, updates: { [string]: BigNumber }): (boolean, string?)
	local previous: { [string]: any } = {}
	for field in pairs(updates) do
		previous[field] = data[field]
	end

	for field, newValue in pairs(updates) do
		data[field] = newValue
	end

	for field, newValue in pairs(updates) do
		if not Schema.isBigNum(newValue) then
			for f, oldValue in pairs(previous) do
				data[f] = oldValue
			end
			return false, string.format("%s 필드가 연산 후 유효한 BigNum이 아님(inf/nan 의심) - 롤백함", field)
		end
	end

	return true, nil
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
CurrencyService._pure = {
	applyAdd = applyAdd,
	applySubtract = applySubtract,
	applySet = applySet,
	applyUpdatesWithRollback = applyUpdatesWithRollback,
}

-- ===== 공개 API =====================================================================

-- 재화 증감 로깅. 지금은 print/warn이지만 나중에 Analytics 이벤트 전송으로 교체할 지점이다.
local function logChange(opName: string, player: Player, currency: string, amount: BigNumber, newValue: BigNumber, reason: string)
	print(string.format(
		"[CurrencyService] %s: %s(%d) %s %s -> %s (reason=%s)",
		opName,
		player.Name,
		player.UserId,
		currency,
		BigNum.tostring(amount),
		BigNum.tostring(newValue),
		reason
	))
end

local function logRejected(opName: string, player: Player, currency: string, reason: string, detail: string)
	warn(string.format(
		"[CurrencyService] %s 거부: %s(%d) currency=%s reason=%s - %s",
		opName,
		player.Name,
		player.UserId,
		currency,
		reason,
		detail
	))
end

function CurrencyService.get(player: Player, currency: string): BigNumber?
	assert(CurrencyService.CURRENCIES[currency], "CurrencyService.get: 알 수 없는 재화 - " .. tostring(currency))

	local profile = ProfileManager.get(player)
	if profile == nil then
		return nil
	end

	return profile.Data[currency]
end

function CurrencyService.canAfford(player: Player, currency: string, amount: BigNumber): boolean
	assert(CurrencyService.CURRENCIES[currency], "CurrencyService.canAfford: 알 수 없는 재화 - " .. tostring(currency))

	local validOk = validateAmount(amount)
	if not validOk then
		return false
	end

	local current = CurrencyService.get(player, currency)
	if current == nil then
		return false
	end

	return BigNum.gte(current, amount)
end

function CurrencyService.add(player: Player, currency: string, amount: BigNumber, reason: string): (boolean, BigNumber?)
	assert(CurrencyService.CURRENCIES[currency], "CurrencyService.add: 알 수 없는 재화 - " .. tostring(currency))
	assert(type(reason) == "string" and #reason > 0, "CurrencyService.add: reason은 필수 문자열이다")

	local profile = ProfileManager.get(player)
	if profile == nil then
		-- 로딩 중이거나 이미 나간 플레이어. 서버 권위 규칙을 지키면서도 여기서 죽으면
		-- 호출부(챌린지 보상 등)가 통째로 에러 처리해야 하므로 error()를 던지지 않는다.
		warn(string.format("[CurrencyService] add 실패: %s(%d) 프로필 없음 (currency=%s, reason=%s)", player.Name, player.UserId, currency, reason))
		return false, nil
	end

	local ok, updates, err, isNoop = applyAdd(currency, profile.Data, amount)
	if not ok then
		logRejected("add", player, currency, reason, err or "알 수 없는 오류")
		return false, nil
	end

	if isNoop then
		-- amount == 0. 값이 안 바뀌었으니 대입도, 로그도 남기지 않는다 (Analytics 노이즈 방지).
		return true, (updates :: { [string]: BigNumber })[currency]
	end

	local applyOk, applyErr = applyUpdatesWithRollback(profile.Data, updates :: { [string]: BigNumber })
	if not applyOk then
		warn(string.format("[CurrencyService][ERROR] add 롤백: %s(%d) currency=%s reason=%s - %s", player.Name, player.UserId, currency, reason, applyErr))
		return false, nil
	end

	local newValue = (updates :: { [string]: BigNumber })[currency]
	logChange("add", player, currency, amount, newValue, reason)
	return true, newValue
end

function CurrencyService.subtract(player: Player, currency: string, amount: BigNumber, reason: string): (boolean, BigNumber?)
	assert(CurrencyService.CURRENCIES[currency], "CurrencyService.subtract: 알 수 없는 재화 - " .. tostring(currency))
	assert(type(reason) == "string" and #reason > 0, "CurrencyService.subtract: reason은 필수 문자열이다")

	local profile = ProfileManager.get(player)
	if profile == nil then
		warn(string.format("[CurrencyService] subtract 실패: %s(%d) 프로필 없음 (currency=%s, reason=%s)", player.Name, player.UserId, currency, reason))
		return false, nil
	end

	local ok, updates, err, isNoop = applySubtract(currency, profile.Data, amount)
	if not ok then
		logRejected("subtract", player, currency, reason, err or "알 수 없는 오류")
		return false, nil
	end

	if isNoop then
		-- amount == 0. 값이 안 바뀌었으니 대입도, 로그도 남기지 않는다 (Analytics 노이즈 방지).
		return true, (updates :: { [string]: BigNumber })[currency]
	end

	local applyOk, applyErr = applyUpdatesWithRollback(profile.Data, updates :: { [string]: BigNumber })
	if not applyOk then
		warn(string.format("[CurrencyService][ERROR] subtract 롤백: %s(%d) currency=%s reason=%s - %s", player.Name, player.UserId, currency, reason, applyErr))
		return false, nil
	end

	local newValue = (updates :: { [string]: BigNumber })[currency]
	logChange("subtract", player, currency, amount, newValue, reason)
	return true, newValue
end

-- 환생/관리 전용. 일반 재화 획득/소모 경로에서는 add/subtract를 쓸 것.
function CurrencyService.set(player: Player, currency: string, amount: BigNumber, reason: string): (boolean, BigNumber?)
	assert(CurrencyService.CURRENCIES[currency], "CurrencyService.set: 알 수 없는 재화 - " .. tostring(currency))
	assert(type(reason) == "string" and #reason > 0, "CurrencyService.set: reason은 필수 문자열이다")

	local profile = ProfileManager.get(player)
	if profile == nil then
		warn(string.format("[CurrencyService] set 실패: %s(%d) 프로필 없음 (currency=%s, reason=%s)", player.Name, player.UserId, currency, reason))
		return false, nil
	end

	local ok, updates, err = applySet(currency, profile.Data, amount)
	if not ok then
		logRejected("set", player, currency, reason, err or "알 수 없는 오류")
		return false, nil
	end

	local applyOk, applyErr = applyUpdatesWithRollback(profile.Data, updates :: { [string]: BigNumber })
	if not applyOk then
		warn(string.format("[CurrencyService][ERROR] set 롤백: %s(%d) currency=%s reason=%s - %s", player.Name, player.UserId, currency, reason, applyErr))
		return false, nil
	end

	local newValue = (updates :: { [string]: BigNumber })[currency]
	logChange("set", player, currency, amount, newValue, reason)
	return true, newValue
end

return CurrencyService

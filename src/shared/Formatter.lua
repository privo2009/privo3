--!strict
-- BigNum -> 사람이 읽는 문자열. 가수 1.00~999.99 고정, tier = floor(e/3) 단위로 접미사를 계산한다.
-- DESIGN.md 4. 숫자 표기 참고.

local BigNum = require(script.Parent.BigNum)

type BigNumber = BigNum.BigNumber

local Formatter = {}

-- tier 0~10 고정 테이블 (0-based)
local FIXED_SUFFIXES: { [number]: string } =
	{ [0] = "", [1] = "K", [2] = "M", [3] = "B", [4] = "T", [5] = "Qa", [6] = "Qi", [7] = "Sx", [8] = "Sp", [9] = "Oc", [10] = "No" }

local LOWER_A = string.byte("a")
local UPPER_A = string.byte("A")
local BLOCK = 26 * 26 -- 두 글자 조합 수 (aa~zz, AA~ZZ 각각 676개)

local function twoLetterSuffix(n: number, base: number): string
	local first = math.floor(n / 26)
	local second = n % 26
	return string.char(base + first) .. string.char(base + second)
end

local function threeLetterSuffix(n: number, base: number): string
	local first = math.floor(n / BLOCK)
	local rem = n % BLOCK
	local second = math.floor(rem / 26)
	local third = rem % 26
	return string.char(base + first) .. string.char(base + second) .. string.char(base + third)
end

-- tier 11~686: 소문자 2글자(aa~zz) / 687~1362: 대문자 2글자(AA~ZZ) / 1363~: 소문자 3글자(aaa~) 예비 확장
local function getSuffix(tier: number): string
	if tier <= 10 then
		return FIXED_SUFFIXES[tier]
	end

	local n = tier - 11
	if n < BLOCK then
		return twoLetterSuffix(n, LOWER_A)
	end

	n = n - BLOCK
	if n < BLOCK then
		return twoLetterSuffix(n, UPPER_A)
	end

	n = n - BLOCK
	return threeLetterSuffix(n, LOWER_A)
end

function Formatter.format(value: BigNumber): string
	assert(type(value) == "table" and type(value.m) == "number" and type(value.e) == "number", "Formatter.format: invalid BigNum")

	if value.m == 0 then
		return "0.00"
	end

	local sign = value.m < 0 and "-" or ""
	local m = math.abs(value.m)
	-- 1보다 작은 값(지시서 #46 — 봇이 찾음: 코인은 블록마다 소수로 들어와 100짜리 알을 사면 0.4999…가 남는다 → HUD가 오류로 멈췄다).
	-- 단위 없이 소수 두 자리로 보인다(0.50 · 0.00). 예전에는 "negative tier" assert로 멈췄다
	if value.e < 0 then
		return sign .. string.format("%.2f", m * (10 ^ value.e))
	end
	local tier = math.floor(value.e / 3)
	local r = value.e - tier * 3
	local displayM = m * (10 ^ r)

	-- %.2f 반올림으로 999.995... 가 1000.00으로 넘어가면 다음 tier로 올려 보정한다.
	if tonumber(string.format("%.2f", displayM)) >= 1000 then
		displayM = displayM / 1000
		tier = tier + 1
	end

	assert(tier >= 0, "Formatter.format: negative tier is not supported")

	return sign .. string.format("%.2f", displayM) .. getSuffix(tier)
end

-- 정수로 세는 값(환생 수 · 층 · 개수 · 별 · 강화 단계 — 지시서 #42). 1000 미만은 소수 없이("1" · "15" · "999"),
-- 1000 이상은 format과 같은 꼴("1.50K" — DESIGN 4 큰 수 표기 그대로). 재화(블럭스 · 코인) 양은 format을 쓴다(소수 2자리 고정).
-- number도 받는다. 소수가 섞여 들어오면 가장 가까운 정수로 반올림한다(BigNum 1.2e1 = 12.000000000000002 같은 오차).
function Formatter.formatCount(value: BigNumber | number): string
	local v: BigNumber = if type(value) == "number" then BigNum.fromNumber(value) else value
	assert(type(v) == "table" and type(v.m) == "number" and type(v.e) == "number", "Formatter.formatCount: invalid value")
	if v.m == 0 then
		return "0"
	end
	if v.e < 3 then
		local n = math.floor(math.abs(v.m) * (10 ^ v.e) + 0.5)
		local sign = if v.m < 0 and n > 0 then -1 else 1
		if n < 1000 then
			return (if sign < 0 then "-" else "") .. tostring(n)
		end
		return Formatter.format(BigNum.fromNumber(sign * n)) -- 999.6 → 1000 → "1.00K"(반올림한 정수로 큰 수 표기)
	end
	return Formatter.format(v)
end

return Formatter

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

return Formatter

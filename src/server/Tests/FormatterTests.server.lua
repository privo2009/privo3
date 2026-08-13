--!strict
-- Formatter 검증 스크립트. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 1-2 검증 항목: 경계값 (10^32/10^33, tier10/11, tier686/687)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)

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

local function checkFormat(name: string, m: number, e: number, expected: string)
	local actual = Formatter.format(BigNum.new(m, e))
	check(name, actual == expected, string.format("expected=%s actual=%s", expected, actual))
end

-- 1. 기본 / tier 0 (접미사 없음) ------------------------------------------

checkFormat("tier0: 1 -> 1.00", 1, 0, "1.00")
checkFormat("tier0: 1234 -> 1.23K (r 계산 확인용, e=3)", 1.234, 3, "1.23K")
checkFormat("소수점 2자리 고정: 999.9 -> 999.90", 9.999, 2, "999.90")

do
	local actual = Formatter.format(BigNum.new(0, 0))
	check("zero -> 0.00", actual == "0.00", actual)
end

do
	local actual = Formatter.format(BigNum.new(-5, 3))
	check("negative: -5000 -> -5.00K", actual == "-5.00K", actual)
end

-- 2. tier 0~10 고정 테이블 전수 확인 ------------------------------------------

local FIXED_EXPECTED = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }
for tier = 0, 10 do
	local e = tier * 3
	local expected = "1.00" .. FIXED_EXPECTED[tier + 1]
	checkFormat(string.format("fixed table tier=%d (e=%d)", tier, e), 1, e, expected)
end

-- 3. 경계값: 10^32 / 10^33 (tier 10 <-> tier 11) --------------------------------

checkFormat("10^32 -> tier10 마지막 (No)", 1, 32, "100.00No")
checkFormat("10^33 -> tier11 시작 (aa)", 1, 33, "1.00aa")

-- 4. 경계값: tier 10/11 자체 (e=30~32 vs e=33~35) -----------------------------

checkFormat("e=30 tier10 시작 -> 1.00No", 1, 30, "1.00No")
checkFormat("e=32 tier10 끝 -> 100.00No", 1, 32, "100.00No")
checkFormat("e=33 tier11 시작 -> 1.00aa", 1, 33, "1.00aa")
checkFormat("e=35 tier11 끝 -> 100.00aa", 1, 35, "100.00aa")

-- 5. 경계값: tier 686/687 (소문자 2글자 <-> 대문자 2글자) ------------------------

checkFormat("e=2058 tier686 시작 -> 1.00zz", 1, 2058, "1.00zz")
checkFormat("e=2060 tier686 끝 -> 100.00zz", 1, 2060, "100.00zz")
checkFormat("e=2061 tier687 시작 -> 1.00AA", 1, 2061, "1.00AA")
checkFormat("e=2063 tier687 끝 -> 100.00AA", 1, 2063, "100.00AA")

-- 6. 알파벳 시작/끝 확인 (aa, zz, AA, ZZ) --------------------------------------

checkFormat("tier11 aa", 1, 33, "1.00aa")
checkFormat("tier686 zz", 1, 2058, "1.00zz")
checkFormat("tier687 AA", 1, 2061, "1.00AA")
checkFormat("tier1362 ZZ (2글자 대문자 마지막)", 1, 4086, "1.00ZZ")

-- 7. tier 1362/1363 경계 (2글자 -> 3글자 확장) ---------------------------------

checkFormat("tier1363 aaa (3글자 확장 시작)", 1, 4089, "1.00aaa")

-- 8. 반올림 캐리 경계 (999.99... -> 다음 tier로 승격) ----------------------------

do
	-- m=9.999999999999, e=2 -> tier0, displayM ~= 999.9999999999 -> "1000.00"으로 반올림되면 안 되고 tier1 "1.00K"로 승격되어야 한다.
	local actual = Formatter.format(BigNum.new(9.999999999999, 2))
	check("반올림 캐리: 999.99999...9 -> 1.00K로 승격", actual == "1.00K", actual)
end

do
	-- 캐리가 발생하지 않는 근접값은 그대로 999.xx로 표시되어야 한다.
	local actual = Formatter.format(BigNum.new(9.9998, 2))
	check("반올림 캐리 없음: 999.98 유지", actual == "999.98", actual)
end

-- 결과 -------------------------------------------------------------------

print(string.format("[FormatterTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[FormatterTests] %d test(s) failed", failed))
end

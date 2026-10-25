--!strict
-- BoostService 검증 (지시서 #16 4단계 · DESIGN 9장 S7). 순수 함수만 굴린다 — 프로필을 건드리지 않는다.
--   감소 · 연장 · 만료 · 오프라인 중 안 줄어듦(남은 초를 저장한다 — 시각을 저장하지 않는다) · 같은 종류는 한 번만 곱함 · 요약

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Schema = require(ServerScriptService.Server.Data.Schema)
local BoostService = require(ServerScriptService.Server.Systems.BoostService)

local B = BoostService._pure

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

local DUR = ShopConfig.BOOSTS.strength.durationSec

do
	local boosts: any = {}
	check("없음: 배수 1", B.activeMult(boosts, "strength") == 1 and B.activeMult(nil, "strength") == 1)
	check("켜기: 새 항목 · ShopConfig 배수 · 지속 시간", B.addBoost(boosts, "strength") and #boosts == 1 and boosts[1].mult == ShopConfig.BOOSTS.strength.mult
		and boosts[1].remainingSec == DUR)
	check("켜면 배수 = 2", B.activeMult(boosts, "strength") == 2)
	check("모르는 종류는 거부", not B.addBoost(boosts, "victory") and #boosts == 1)
	B.tickBoosts(boosts, 10)
	check("감소: 10초 흐르면 10초 준다", boosts[1].remainingSec == DUR - 10)
	B.addBoost(boosts, "strength")
	check("연장: 같은 종류를 또 켜면 시간이 더해진다 · 배수는 그대로 · 항목은 하나", #boosts == 1 and boosts[1].remainingSec == DUR * 2 - 10
		and B.activeMult(boosts, "strength") == 2)
	B.addBoost(boosts, "damage")
	check("다른 종류는 따로", #boosts == 2 and B.activeMult(boosts, "damage") == 2 and B.activeMult(boosts, "luck") == 1)
	B.tickBoosts(boosts, DUR)
	check("만료: 데미지(남은 0) 지움 · 힘은 남음", #boosts == 1 and boosts[1].type == "strength" and B.activeMult(boosts, "damage") == 1)
	B.tickBoosts(boosts, DUR * 2)
	check("만료: 다 지나면 비고 배수 1", #boosts == 0 and B.activeMult(boosts, "strength") == 1)
	check("dt 0 · 음수는 아무것도 안 한다", not B.tickBoosts({ { type = "luck", mult = 2, remainingSec = 5 } }, 0)
		and not B.tickBoosts({ { type = "luck", mult = 2, remainingSec = 5 } }, -3))
end

do
	-- 같은 종류가 둘(옛 데이터): 곱하지 않고 큰 배수 하나
	local dup: any = { { type = "luck", mult = 2, remainingSec = 30 }, { type = "luck", mult = 2, remainingSec = 60 } }
	check("같은 종류가 둘이어도 한 번만(2 — 4 아님)", B.activeMult(dup, "luck") == 2)
	local broken: any = { "x", { type = "strength", mult = 2, remainingSec = 0 / 0 }, { type = "strength", mult = 2, remainingSec = 5 } }
	B.tickBoosts(broken, 1)
	check("깨진 항목은 틱에서 지운다", #broken == 1 and broken[1].remainingSec == 4)
end

do
	-- 오프라인 중 안 줄어듦: 저장되는 것은 남은 초다. 루프가 돌지 않으면(접속 안 함) 그대로다 — 저장 · 로드 왕복 뒤에도 같다.
	local data = Schema.new() :: any
	B.addBoost(data.boosts, "strength")
	B.tickBoosts(data.boosts, 100)
	local saved = table.clone(data.boosts[1])
	check("오프라인: 남은 초만 저장된다(시각 필드 없음)", saved.remainingSec == DUR - 100 and saved.expiresAt == nil)
	check("오프라인: 저장한 모양이 스키마 v7 검증을 통과", (Schema.validate(data)))
	check("오프라인: 틱 없이는 그대로(나가 있는 동안 루프가 그 프로필을 보지 않는다)", data.boosts[1].remainingSec == DUR - 100)
end

do
	local boosts: any = { { type = "luck", mult = 2, remainingSec = 10.2 }, { type = "strength", mult = 2, remainingSec = 899.5 } }
	local s = B.summarize(boosts)
	check("요약: BOOST_ORDER 순서 · 남은 초 올림", #s == 2 and s[1].type == "strength" and s[1].remainingSec == 900 and s[2].type == "luck"
		and s[2].remainingSec == 11 and s[2].mult == 2)
	local hidden = B.summarize(boosts, function(t: string)
		return t == "luck"
	end)
	check("요약: hide로 뺀 종류는 없다(제한 유저의 행운 포션)", #hidden == 1 and hidden[1].type == "strength")
	check("요약: 비면 빈 목록", #B.summarize({}) == 0 and #B.summarize(nil) == 0)
end

print(string.format("[BoostServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[BoostServiceTests] %d test(s) failed", failed))
end

--!strict
-- 모든 Config 모듈의 validate()를 실행. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- ROADMAP Phase 1-3 검증: Config 골격이 자기 자신의 값 정합성을 통과하는지 확인.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)

local Config = ReplicatedStorage.Shared.Config
local WorldConfig = require(Config.WorldConfig)
local StageConfig = require(Config.StageConfig)
local UpgradeConfig = require(Config.UpgradeConfig)
local ShopConfig = require(Config.ShopConfig)
local AuraConfig = require(Config.AuraConfig)
local TitleConfig = require(Config.TitleConfig)
local PetConfig = require(Config.PetConfig)

local passed = 0
local failed = 0

local function check(name: string, fn: () -> boolean)
	local ok, result = pcall(fn)
	if ok and result then
		passed = passed + 1
	else
		failed = failed + 1
		warn(string.format("[FAIL] %s%s", name, ok and "" or (" - " .. tostring(result))))
	end
end

check("WorldConfig.validate", function()
	return WorldConfig.validate()
end)

check("StageConfig.validate", function()
	return StageConfig.validate()
end)

check("UpgradeConfig.validate", function()
	return UpgradeConfig.validate()
end)

check("ShopConfig.validate", function()
	return ShopConfig.validate()
end)

check("AuraConfig.validate", function()
	return AuraConfig.validate()
end)

check("TitleConfig.validate", function()
	return TitleConfig.validate()
end)

check("PetConfig.validate", function()
	return PetConfig.validate()
end)

-- 각 모듈이 실제로 사용 가능한 값을 돌려주는지 스모크 테스트 --------------------

check("StageConfig.getHp(1)이 BigNum을 반환", function()
	local hp = StageConfig.getHp(1)
	return type(hp) == "table" and type(hp.m) == "number" and type(hp.e) == "number"
end)

check("StageConfig.hasStage: 0층과 최종 층 다음은 없다", function()
	local finalStage = 0
	for _, world in pairs(WorldConfig.Worlds) do
		finalStage = math.max(finalStage, world.stageRange[2])
	end
	return StageConfig.hasStage(1) == true
		and StageConfig.hasStage(finalStage) == true
		and StageConfig.hasStage(finalStage + 1) == false
		and StageConfig.hasStage(0) == false
end)

check("StageConfig.isFinalStage: 최종 층만 true", function()
	local finalStage = 0
	for _, world in pairs(WorldConfig.Worlds) do
		finalStage = math.max(finalStage, world.stageRange[2])
	end
	return StageConfig.isFinalStage(finalStage) == true and StageConfig.isFinalStage(finalStage - 1) == false
end)

check("UpgradeConfig.getCostAtLevel이 레벨에 따라 증가", function()
	local cost0 = UpgradeConfig.getCostAtLevel("punchDamage", 0)
	local cost5 = UpgradeConfig.getCostAtLevel("punchDamage", 5)
	return BigNum.gt(cost5, cost0)
end)

check("ShopConfig: 힘 배수 게임패스는 최고 단계만 적용된다", function()
	-- 10개 단계를 전부 "소유"한 것으로 가정해도 누적 곱셈이 아니라 최고 배수(1024x) 하나만 나와야 한다.
	local mult = ShopConfig.getActiveStrengthMultiplier(function(_id: number)
		return true
	end)
	return mult == 1024
end)

check("PetConfig.getNextTier: 최고 등급은 nil", function()
	return PetConfig.getNextTier(4) == nil and PetConfig.getNextTier(1) == 2
end)

print(string.format("[ConfigTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ConfigTests] %d test(s) failed", failed))
end

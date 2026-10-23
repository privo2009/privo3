--!strict
-- 뽑기 공통 서버 층 (Phase 7 지시서 #10 S2). 서버 RNG를 소유하고, 행운 체인을 조립하고, 결과 코드를 정한다.
-- 판정 자체는 RollLogic(순수)이 한다. 타이틀 · 아우라 · 펫 서비스는 이 파일을 거쳐 굴린다.
--
-- ===== 행운 체인 (G14, DESIGN.md "6. 뽑기 3종 > 공통") ===================================
--
--   최종 확률 = 기본 × 그 뽑기의 행운 업그레이드 × 롤 상품 배수 × 행운 게임패스 × 부스트
--
--   행운 업그레이드  UpgradeConfig.getEffect(titleLuck · auraLuck · petLuck, 레벨) = 1 + 증가량 × 레벨 (G13)
--   롤 상품 배수     럭키 · 슈퍼 롤 — **아우라 전용**(G15, Phase 8). 다른 뽑기에서는 넘겨도 1
--   행운 게임패스    세션 값(절대 규칙 5). Phase 8 전까지 호출자가 넘기지 않는다 → 1
--   부스트           1인 자리만 둔다(행운 부스트 상품은 없다)
--
-- ===== RNG =============================================================================
--
-- 서버 Random 하나를 이 모듈이 갖는다. 클라는 확률을 표시만 한다(절대 규칙 3 — 뽑기 롤 100% 서버 판정).
-- 테스트는 _setRandom으로 난수 열을 주입하고, 끝나면 _resetRandom으로 되돌린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local RollLogic = require(script.Parent.RollLogic)

local RollService = {}

-- 뽑기 종류 → 그 뽑기의 행운 업그레이드 이름 · 롤 상품을 받는가.
export type Kind = "title" | "aura" | "pet"
local KINDS: { [string]: { luckUpgrade: string, acceptsRollProduct: boolean } } = {
	title = { luckUpgrade = "titleLuck", acceptsRollProduct = false },
	aura = { luckUpgrade = "auraLuck", acceptsRollProduct = true }, -- G15
	pet = { luckUpgrade = "petLuck", acceptsRollProduct = false },
}
RollService.KINDS = KINDS

-- 결과 코드 · 거부 사유 코드. 문구는 UI가 매핑한다(문자열 그대로 클라에 간다).
RollService.RESULT_NEW = "new" -- 처음 얻은 id
RollService.RESULT_DUPLICATE = "duplicate" -- 이미 있는 id — 조용히 사라진다(알림 · 저장 없음)
RollService.REASON_NO_PROFILE = "no_profile"
RollService.REASON_INSUFFICIENT_BLOX = "insufficient_blox"
RollService.REASON_RATE_LIMITED = "rate_limited" -- 롤 시계(그 뽑기의 간격) 안 두 번째 요청
RollService.REASON_INVALID = "invalid_request"
RollService.REASON_PARTIAL_FAILURE = "partial_failure" -- 차감 뒤 결과 반영 실패(로그가 복구 근거)

export type LuckOptions = {
	rollProductMult: number?, -- 롤 상품(아우라 전용). 없거나 다른 뽑기면 1
	luckPassMult: number?, -- 행운 게임패스(세션 값). Phase 8 전까지 넘기지 않는다
	boostMult: number?, -- 부스트 자리. 지금 상품 없음
}

-- 1 이상의 유한수만 배수로 받는다. 그 밖(nil · nan · 1 미만 · inf)은 1 — 깨진 배수가 확률을 줄이거나 터뜨리지 않게.
local function factor(v: any): number
	if type(v) ~= "number" or v ~= v or v < 1 or v == math.huge then
		return 1
	end
	return v
end

local function readUpgradeLevel(data: any, name: string): number
	local upgrades = if type(data) == "table" then data.upgrades else nil
	local raw = if type(upgrades) == "table" then upgrades[name] else nil
	if type(raw) ~= "number" or raw ~= raw or raw < 0 or raw == math.huge then
		return 0
	end
	return math.floor(raw)
end

-- G14 체인. data는 profile.Data(또는 같은 모양의 표 — 시뮬레이터는 { upgrades = { titleLuck = L } }를 넘긴다).
-- 지금 실제로 1이 아닌 항은 행운 업그레이드 하나다.
function RollService.computeLuck(kind: string, data: any, opts: LuckOptions?): number
	local def = KINDS[kind]
	assert(def ~= nil, "RollService.computeLuck: 모르는 뽑기 종류 - " .. tostring(kind))
	local upgrade = UpgradeConfig.getEffect(def.luckUpgrade, readUpgradeLevel(data, def.luckUpgrade))
	local o: LuckOptions = opts or {}
	local product = if def.acceptsRollProduct then factor(o.rollProductMult) else 1
	return upgrade * product * factor(o.luckPassMult) * factor(o.boostMult)
end

-- ===== RNG ==============================================================================

local rng = Random.new()
local randomFn: () -> number = function()
	return rng:NextNumber()
end

-- 서버 RNG로 순차 판정한다. 반환: (등급, 인덱스).
function RollService.roll<T>(tiers: { T }, luck: number): (T, number)
	return RollLogic.roll(tiers, luck, randomFn)
end

-- 같은 seed → 같은 난수 열. 시뮬레이터 · 테스트가 결정성을 잴 때 쓴다(게임 RNG에는 영향 없음).
function RollService.seededRandom(seed: number): () -> number
	local r = Random.new(seed)
	return function()
		return r:NextNumber()
	end
end

-- 테스트 전용 통로. 공개 API 계약이 아니므로 이 밖에서는 쓰지 말 것.
-- ⚠️ 주입한 채 yield하지 말 것 — 같은 Play의 실제 롤이 주입한 난수를 쓰게 된다(SuccessRateReport.runBand와 같은 주의).
function RollService._setRandom(fn: () -> number)
	randomFn = fn
end

function RollService._resetRandom()
	randomFn = function()
		return rng:NextNumber()
	end
end

RollService._pure = {
	factor = factor,
	readUpgradeLevel = readUpgradeLevel,
}

return RollService

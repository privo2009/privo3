--!strict
-- TitleService 검증 (지시서 #10 4단계). 가짜 deps로 Player 없이 굴린다:
-- 거부 경로 부작용 0 · 차감 → 롤 순서 · 신규 / 중복 · 자동 장착 · 롤 시계 · 자동 루프 틱 · 장착 · 자동 롤 토글 ·
-- 행운 전달 · 상태 요약 · 배수 두 자리 "한 번만". 기대값은 Config에서 읽는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local TitleConfig = require(ReplicatedStorage.Shared.Config.TitleConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local Schema = require(script.Parent.Parent.Data.Schema)
local RollService = require(script.Parent.RollService)
local TitleService = require(script.Parent.TitleService)
local ChallengeService = require(script.Parent.ChallengeService)

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

local TITLES = TitleConfig.Titles
local INTERVAL = TitleConfig.ROLL_INTERVAL_SEC
local COST = TitleConfig.ROLL_COST

-- 가짜 세계. 플레이어는 테이블 키로만 쓴다(Instance가 아니다).
local function world(opts: { blox: number?, data: any? }?)
	local o = opts or {}
	local w = {
		clock = 100,
		blox = BigNum.fromNumber(o.blox or 1000),
		data = o.data or Schema.new(),
		log = {} :: { string },
		rolls = {} :: { number }, -- 다음 롤이 돌려줄 인덱스 열
		lastLuck = nil :: number?,
		saves = 0,
		notified = {} :: { any },
		attr = "unset" :: any,
		present = true,
	}
	local deps: TitleService.Deps = {
		now = function()
			return w.clock
		end,
		getData = function(_p)
			return if w.present then w.data else nil
		end,
		subtractBlox = function(_p, amount, reason)
			table.insert(w.log, "subtract:" .. reason)
			if BigNum.lt(w.blox, amount) then
				return false
			end
			w.blox = BigNum.sub(w.blox, amount)
			return true
		end,
		roll = function(tiers, luck)
			table.insert(w.log, "roll")
			w.lastLuck = luck
			local i = table.remove(w.rolls, 1) or 1
			return tiers[i], i
		end,
		save = function(_p)
			w.saves += 1
		end,
		notifyAutoNew = function(_p, r)
			table.insert(w.notified, r)
		end,
		setAttribute = function(_p, id)
			w.attr = id
		end,
	}
	local runtime = TitleService._pure.createRuntime(deps)
	return w, runtime
end

local P = ({} :: any) :: Player
local Q = ({} :: any) :: Player

-- 1. 거부 경로 — 부작용 0 ----------------------------------------------------------------------
do
	local w, rt = world()
	w.present = false
	local ok, reason = rt.roll(P, "manual")
	check("프로필 없음 → no_profile, 차감 · 롤 없음", not ok and reason == RollService.REASON_NO_PROFILE and #w.log == 0)
end

do
	local w, rt = world({ blox = 5 })
	local ok, reason = rt.roll(P, "manual")
	check("잔액 부족 → insufficient_blox", not ok and reason == RollService.REASON_INSUFFICIENT_BLOX)
	check("잔액 부족: 롤 · 저장 · 알림 · 보유 변화 없음",
		#w.log == 1 and w.log[1] == "subtract:title_roll_manual" and w.saves == 0 and #w.notified == 0 and next(w.data.cosmetics.ownedTitles) == nil)
	w.blox = BigNum.fromNumber(1000)
	local ok2 = rt.roll(P, "manual")
	check("잔액 부족은 롤 시계를 쓰지 않는다 (바로 다시 굴릴 수 있다)", ok2)
end

-- 2. 순서 · 신규 · 자동 장착 · 저장 ----------------------------------------------------------------
do
	local w, rt = world()
	w.rolls = { 3 }
	local ok, r = rt.roll(P, "manual")
	check("차감 → 롤 순서", w.log[1] == "subtract:title_roll_manual" and w.log[2] == "roll")
	check("비용 = TitleConfig.ROLL_COST", BigNum.eq(w.blox, BigNum.sub(BigNum.fromNumber(1000), COST)))
	check("신규: isNew · 보유 추가", ok and r.isNew and r.titleId == TITLES[3].id and w.data.cosmetics.ownedTitles[TITLES[3].id] == true)
	check("신규: 장착 없음 → 자동 장착 + Attribute", r.equipped and w.data.cosmetics.equippedTitle == TITLES[3].id and w.attr == TITLES[3].id)
	check("신규: 저장 1회 (S11)", w.saves == 1)
	check("수동 롤 신규는 서비스가 알리지 않는다 (요청 응답이 알린다)", #w.notified == 0)

	-- 더 낮은 새 칭호 → 장착 그대로
	w.clock += INTERVAL
	w.rolls = { 2 }
	local _, low = rt.roll(P, "manual")
	check("낮은 신규: 보유는 늘고 장착은 그대로", low.isNew and not low.equipped and w.data.cosmetics.equippedTitle == TITLES[3].id
		and w.data.cosmetics.ownedTitles[TITLES[2].id] == true and w.saves == 2)

	-- 더 높은 새 칭호 → 바로 장착
	w.clock += INTERVAL
	w.rolls = { #TITLES }
	local _, high = rt.roll(P, "manual")
	check("높은 신규: 바로 장착", high.equipped and w.data.cosmetics.equippedTitle == TITLES[#TITLES].id and w.attr == TITLES[#TITLES].id)

	-- 중복
	w.clock += INTERVAL
	w.rolls = { 3 }
	local before = w.saves
	local blox = w.blox
	local okDup, dup = rt.roll(P, "auto")
	check("중복: 성공이지만 isNew false · 장착 안 바뀜", okDup and not dup.isNew and not dup.equipped and w.data.cosmetics.equippedTitle == TITLES[#TITLES].id)
	check("중복: 저장 · 알림 없음 (자동 롤이어도)", w.saves == before and #w.notified == 0)
	check("중복: 비용은 낸다", BigNum.eq(w.blox, BigNum.sub(blox, COST)))
end

-- 3. 롤 시계 (G6 — 수동 · 자동 공용) -----------------------------------------------------------------
do
	local w, rt = world()
	rt.roll(P, "manual")
	local spent = w.blox
	w.clock += INTERVAL * 0.5
	local ok, reason = rt.roll(P, "auto")
	check("간격 안 두 번째 롤 → rate_limited (수동 뒤 자동도)", not ok and reason == RollService.REASON_RATE_LIMITED)
	check("rate_limited: 차감 없음", BigNum.eq(w.blox, spent))
	w.clock += INTERVAL * 0.5
	check("간격이 지나면 다시 굴린다", (rt.roll(P, "manual")))
	w.clock += INTERVAL - TitleService._pure.CLOCK_EPSILON_SEC * 0.5
	check("여유(epsilon) 안쪽으로 조금 짧아도 굴린다 (자동 루프 틱 흔들림)", (rt.roll(P, "auto")))
	local _w2, rt2 = world()
	rt2.roll(P, "manual")
	check("시계는 플레이어마다 따로", (rt2.roll(Q, "manual")))
end

-- 4. 자동 루프 틱 ---------------------------------------------------------------------------------
do
	local w, rt = world()
	w.data.rolling.autoRollTitle = false
	check("자동 롤 끔 → 틱이 굴리지 않는다", rt.autoTick({ P }) == 0 and #w.log == 0)
	w.data.rolling.autoRollTitle = true
	w.rolls = { 2 }
	check("자동 롤 켬 → 틱당 1회", rt.autoTick({ P }) == 1 and w.log[1] == "subtract:title_roll_auto")
	check("자동 롤 신규 → 알림 1건", #w.notified == 1 and w.notified[1].titleId == TITLES[2].id and w.notified[1].isNew)
	check("같은 틱 안에서 다시 불러도 시계가 막는다", rt.autoTick({ P }) == 0)
	w.clock += INTERVAL
	w.blox = BigNum.fromNumber(1)
	check("잔액 부족 틱은 건너뛴다", rt.autoTick({ P }) == 0)
	check("잔액 부족이어도 토글은 그대로", w.data.rolling.autoRollTitle == true)
	w.blox = BigNum.fromNumber(1000)
	w.rolls = { 2 }
	check("돈이 다시 생기면 다음 틱에 굴린다", rt.autoTick({ P }) == 1 and #w.notified == 1)
end

-- 5. 장착 · 토글 --------------------------------------------------------------------------------------
do
	local w, rt = world()
	w.data.cosmetics.ownedTitles[TITLES[2].id] = true
	local ok = rt.equip(P, TITLES[2].id)
	check("보유한 칭호 장착", ok and w.data.cosmetics.equippedTitle == TITLES[2].id and w.attr == TITLES[2].id)
	local ok2, r2 = rt.equip(P, TITLES[4].id)
	check("미보유 장착 → not_owned, 그대로", not ok2 and r2 == TitleService.REASON_NOT_OWNED and w.data.cosmetics.equippedTitle == TITLES[2].id)
	local ok3, r3 = rt.equip(P, "no_such_title")
	check("모르는 id → invalid_request", not ok3 and r3 == RollService.REASON_INVALID)
	local ok4, r4 = rt.equip(P, 7)
	check("id가 문자열이 아니면 invalid_request", not ok4 and r4 == RollService.REASON_INVALID)

	check("자동 롤 켬 저장", (rt.setAutoRoll(P, true)) and w.data.rolling.autoRollTitle == true)
	local ok5, r5 = rt.setAutoRoll(P, "yes")
	check("자동 롤 값이 boolean이 아니면 invalid_request, 그대로", not ok5 and r5 == RollService.REASON_INVALID and w.data.rolling.autoRollTitle == true)
	check("자동 롤 끔 저장", (rt.setAutoRoll(P, false)) and w.data.rolling.autoRollTitle == false)
	w.present = false
	check("프로필 없으면 장착 · 토글 no_profile", select(2, rt.equip(P, TITLES[2].id)) == RollService.REASON_NO_PROFILE
		and select(2, rt.setAutoRoll(P, true)) == RollService.REASON_NO_PROFILE)
end

-- 6. 행운이 판정에 전달된다 (G13 · G14) -------------------------------------------------------------------
do
	local w, rt = world()
	w.data.upgrades.titleLuck = 7
	rt.roll(P, "manual")
	check("판정에 넘어간 행운 = computeLuck(title, 프로필) = titleLuck 효과",
		w.lastLuck ~= nil and math.abs((w.lastLuck :: number) - UpgradeConfig.getEffect("titleLuck", 7)) < 1e-12)
end

-- 7. 요약 · 배수 ------------------------------------------------------------------------------------------
do
	local data = Schema.new()
	data.cosmetics.ownedTitles[TITLES[4].id] = true
	data.cosmetics.ownedTitles[TITLES[2].id] = true
	data.cosmetics.equippedTitle = TITLES[4].id
	data.rolling.autoRollTitle = true
	local s = TitleService.summarize(data)
	check("요약: owned는 희귀도 순", #s.owned == 2 and s.owned[1] == TITLES[2].id and s.owned[2] == TITLES[4].id)
	check("요약: equipped · autoRoll", s.equipped == TITLES[4].id and s.autoRoll == true)
	local empty = TitleService.summarize(Schema.new())
	check("요약: 장착 없음은 \"\" (선택 필드 금지)", empty.equipped == "" and #empty.owned == 0 and empty.autoRoll == false)
	data.cosmetics.equippedTitle = "ghost"
	check("요약: 모르는 장착 id는 \"\"", TitleService.summarize(data).equipped == "")
	check("요약: 깨진 데이터도 안 죽는다", TitleService.summarize(nil).equipped == "")
end

do
	check("multOf: 장착 없음 · 모르는 id는 1", TitleConfig.multOf(false) == 1 and TitleConfig.multOf("ghost") == 1)
	check("multOf: 칭호 배수 = TitleConfig 값", TitleConfig.multOf(TITLES[#TITLES].id) == TITLES[#TITLES].mult)
end

-- 힘 계통 — StrengthMultiplier 한 곳에서 한 번만 곱한다 (S3)
do
	local m = TITLES[#TITLES].mult
	local rebirths = BigNum.fromNumber(2)
	local withTitle = StrengthMultiplier.compute({ rebirths = rebirths, titleMult = m })
	local expect = BigNum.mul(BigNum.fromNumber(3), BigNum.fromNumber(m))
	check("힘: (1 + 환생) × 칭호 — 한 번만 (제곱 아님)", math.abs(BigNum.toRatio(withTitle, expect) - 1) < 1e-9)
	check("힘: 칭호 없음 = 환생 배수 그대로", BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths }), BigNum.fromNumber(3)))
	check("힘: 깨진 칭호 배수(nan · 0.5 · inf)는 무시",
		BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, titleMult = 0 / 0 }), BigNum.fromNumber(3))
			and BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, titleMult = 0.5 }), BigNum.fromNumber(3))
			and BigNum.eq(StrengthMultiplier.compute({ rebirths = rebirths, titleMult = math.huge }), BigNum.fromNumber(3)))
end

-- 블럭스 계통 — ChallengeService 결합 한 곳에서 한 번만 곱한다 (S4)
do
	local combine = ChallengeService._pure.combineBloxMultiplier
	local m = TITLES[#TITLES].mult
	local g = UpgradeConfig.getEffect("bloxGain", 4)
	check("블럭스: 획득 업그레이드 × 칭호 — 한 번만", math.abs(combine({ bloxGain = g, titleMult = m }) - g * m) < 1e-12)
	check("블럭스: 칭호 없음 = 업그레이드 그대로", combine({ bloxGain = g }) == g)
	check("블럭스: 깨진 값은 1", combine({ bloxGain = 0 / 0, titleMult = 0.2 }) == 1)
	local base = BigNum.fromNumber(1000)
	local paid = ChallengeService._pure.payableReward(base, combine({ bloxGain = 1, titleMult = m }))
	check("블럭스: 수령액 = 층 보상 × 칭호 (한 번)", math.abs(BigNum.toRatio(paid, BigNum.mul(base, BigNum.fromNumber(m))) - 1) < 1e-9)
end

print(string.format("[TitleServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TitleServiceTests] %d test(s) failed", failed))
end

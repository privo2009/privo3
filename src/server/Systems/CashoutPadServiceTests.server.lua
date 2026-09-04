--!strict
-- 수령 발판 검증. Studio에서 Rojo 연결 후 Play 하면 서버 시작 시 자동 실행된다.
-- Phase 4-2-a 커밋 3b 검증: 발판 좌표 / 디바운스 / 런당 1회 처리.
--
-- 순수 함수와 deps 이음매만 쓴다 — 진짜 ChallengeService도 Instance도 없이 검증한다
-- (RebirthServiceTests / WarpServiceTests와 같은 방식). 실제로 밟히는지는
-- Studio Play 육안 확인 몫이다.
--
-- ⚠️ TestHelpers.checkClose를 쓰지 못한다(src/client에 있어 서버가 require 불가).
-- ArenaServiceTests와 같은 이유로 같은 기준(1e-6)의 헬퍼를 파일 안에 둔다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Shared.Config.ArenaConfig)
local CashoutPadService = require(script.Parent.CashoutPadService)

local pure = CashoutPadService._pure

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

local RELATIVE_TOLERANCE = 1e-6
local function checkClose(actual: number, expected: number): (boolean, string)
	local diff = actual - expected
	local relative = if expected ~= 0 then diff / expected else diff
	return math.abs(relative) < RELATIVE_TOLERANCE,
		string.format("기대값=%.17g 실제값=%.17g 차이=%.3e", expected, actual, diff)
end

-- 런 상태를 흉내내는 세계. cashout은 성공하면 런을 지운다 — 그것이 "런당 1회"의
-- 진짜 보장이므로, 그 동작을 그대로 재현해야 이 테스트가 의미를 갖는다.
--
-- ===== ⚠️ 케이스마다 새 플레이어를 만든다 (U3-10a 수정) ================================
--
-- CashoutPadService의 디바운스 상태(states)는 **모듈 수준 싱글턴이고 플레이어 테이블을
-- 키로 쓴다.** 예전에는 이 파일이 fakePlayer 하나를 모든 케이스가 공유했고, 그러면서
-- 케이스마다 clock을 100.0으로 되돌렸다. 그래서 앞 케이스가 남긴 lastTouchAt(100.51)이
-- 뒤 케이스의 시계(100.0)보다 **미래**가 되어, now - lastTouchAt이 음수가 되고
-- 모든 접촉이 debounced로 접혔다 — cashout이 한 번도 안 불려서 실측값이 전부 0이었다.
--
-- 실물은 정상이었다. 서버 로그에 source=cashout_pad_stage_1이 (x2)로 뭉쳐 찍혔고,
-- 그건 source 조립도 디바운스도 도는 증거다. 깨진 것은 하네스뿐이었다.
--
-- ⚠️ 이름 접두어로 가리지 않는다. 키가 플레이어 테이블이므로 **새 테이블이 곧 새
-- 상태**다 — 격리를 흉내내는 것이 아니라 실제로 분리한 것이다.
-- (U3-9에서 Store가 같은 이유로 죽었고, ScreenController.new()가 같은 방식으로 살았다)
--
-- ⚠️ 프로덕션을 고치지 않았다. CashoutPadService.new()를 만들면 실물 발판이 쓰는
-- 싱글턴과 테스트 인스턴스가 갈리지만, 실물이 정상 동작하는 것이 이미 확인됐으므로
-- 하네스만으로 충분하다. 테스트가 만든 states 항목은 가짜 플레이어라
-- PlayerRemoving이 걷어가지 않고 Play 세션 동안 남는다 — 케이스 수만큼이라 무시 가능하다.
local nextPlayerId = 0
local function newWorld(cleared: boolean)
	nextPlayerId += 1

	local w = {
		run = { cleared = cleared } :: any,
		cashoutCalls = 0,
		sources = {} :: { string },
		clock = 100.0,
		-- 이 케이스 전용 플레이어. states의 키가 되므로 케이스끼리 디바운스가 안 섞인다.
		player = ({ Name = string.format("CashoutPadTestPlayer%d", nextPlayerId) } :: any) :: Player,
	}

	local deps = {
		cashout = function(_player: Player, source: string?): (boolean, any)
			w.cashoutCalls += 1
			table.insert(w.sources, source or "nil")

			if w.run == nil then
				return false, nil -- ChallengeService: "활성 런 없음"
			end
			if not w.run.cleared then
				return false, nil -- ChallengeService: "아직 클리어 안 됨"
			end

			w.run = nil -- 성공하면 런이 사라진다. 여기가 런당 1회의 근거다.
			return true, 1
		end,
		now = function(): number
			return w.clock
		end,
	}

	return w, deps
end

-- 1. 발판 좌표 -------------------------------------------------------------------------
--
-- ⚠️ 100·20을 여기 적지 않는다. ArenaConfig에서 읽어야 폭을 조정했을 때 따라온다.

do
	for _, stage in ipairs({ 1, 2, 7 }) do
		local pos = pure.getPadPosition(stage)

		check(
			string.format("스테이지 %d 발판 X = 블록중심 + 수령 오프셋", stage),
			checkClose(pos.X, ArenaConfig.getCashoutX(stage))
		)
		check(
			string.format("스테이지 %d 발판 X가 블록중심보다 앞", stage),
			pos.X > ArenaConfig.getStageCenterX(stage),
			string.format("발판=%.1f 중심=%.1f", pos.X, ArenaConfig.getStageCenterX(stage))
		)
		check(
			string.format("스테이지 %d 발판이 진행축에서 비켜 있다", stage),
			checkClose(pos.Z, ArenaConfig.CASHOUT_LATERAL_OFFSET)
		)
		check(string.format("스테이지 %d 발판이 지면 위에 얹힌다", stage), checkClose(pos.Y, pure.PAD_SIZE.Y / 2))
	end
end

do
	-- 축 위에 있으면 지나가다 밟혀 런이 끝난다. 0이 아닌 것이 이 검사의 전부다.
	check(
		"발판이 진행축(Z=0) 위에 있지 않다",
		pure.getPadPosition(1).Z ~= 0,
		tostring(pure.getPadPosition(1).Z)
	)

	-- 안쪽 모서리가 통로를 침범하지 않는가. 캐릭터 반폭(약 2)보다 넉넉해야 한다.
	local innerEdge = ArenaConfig.CASHOUT_LATERAL_OFFSET - pure.PAD_SIZE.Z / 2
	check(
		"발판 안쪽 모서리가 축에서 캐릭터 반폭보다 멀다",
		innerEdge > 2,
		string.format("안쪽 모서리=%.1f", innerEdge)
	)

	-- 진행 방향 깊이가 최소 깊이(8) 이상인가. 이 하한이 이동속도 상한을 정한다
	-- (docs/UI_ASSET_SPEC.md "5-1").
	check(
		"발판 진행 방향 깊이가 8 이상",
		pure.PAD_SIZE.X >= 8,
		string.format("깊이=%.1f", pure.PAD_SIZE.X)
	)
end

-- 2. 디바운스 — 같은 창 안의 재접촉은 처리되지 않는다 ---------------------------------------

do
	local state = pure.newPadState()

	local s1, r1 = pure.applyTouch(state, 100.0)
	check("첫 접촉은 처리됨", r1 == "ok", tostring(r1))

	local s2, r2 = pure.applyTouch(s1, 100.0 + pure.TOUCH_DEBOUNCE_SEC / 2)
	check("같은 창 안의 재접촉은 무시됨", r2 == "debounced", tostring(r2))
	check("무시된 접촉은 상태를 바꾸지 않음", s2 == s1)

	local _, r3 = pure.applyTouch(s2, 100.0 + pure.TOUCH_DEBOUNCE_SEC + 0.01)
	check("창이 지나면 다시 처리됨", r3 == "ok", tostring(r3))
end

-- 3. 런당 1회 — 같은 런에서 Touched 두 번이면 지급은 한 번 --------------------------------
--
-- ⚠️ 이것이 이 파일에서 가장 중요한 케이스다. 중복 지급은 재화 누수다.
-- 보장은 발판이 아니라 ChallengeService에 있다 — cashout 성공이 런을 지운다.
-- 그래서 두 번째 호출은 "런 없음"으로 거부되고, 지급은 한 번만 일어난다.

do
	local w, deps = newWorld(true)

	CashoutPadService._handleTouch(deps, w.player, 1)
	check("클리어 상태: 첫 접촉이 cashout을 부른다", w.cashoutCalls == 1, tostring(w.cashoutCalls))
	check("첫 접촉으로 런이 끝났다", w.run == nil)

	-- 디바운스 창을 넘겨서 다시 밟는다. 디바운스가 아니라 런 소멸이 막아야 한다.
	w.clock += pure.TOUCH_DEBOUNCE_SEC + 0.01
	CashoutPadService._handleTouch(deps, w.player, 1)

	check("런이 끝난 뒤 다시 밟아도 cashout은 거부된다", w.run == nil)
	check(
		"두 번째 접촉이 지급을 만들지 않는다 (런당 1회)",
		w.cashoutCalls == 2 and w.run == nil,
		string.format("호출=%d", w.cashoutCalls)
	)
end

do
	-- 디바운스 창 안에서 연타하면 cashout 자체가 한 번만 불린다 (로그 폭주 방지).
	local w, deps = newWorld(true)

	for _ = 1, 10 do
		CashoutPadService._handleTouch(deps, w.player, 1)
		w.clock += 0.01 -- 같은 창 안
	end

	check("창 안의 연타 10회에 cashout은 1회", w.cashoutCalls == 1, tostring(w.cashoutCalls))
end

do
	-- 디바운스가 **플레이어별**인지. 이 검사가 U3-10a의 회귀 방지선이다.
	--
	-- 두 겹을 함께 잰다:
	--   (1) A가 밟은 것이 B의 디바운스를 소모하지 않는다 — 한 사람이 밟으면 서버에
	--       있는 다른 사람의 수령이 막히는 것은 실물 버그다
	--   (2) 케이스끼리 상태가 안 섞인다 — 예전에 이 파일이 플레이어 하나를 공유해
	--       앞 케이스의 lastTouchAt이 뒤 케이스의 시계보다 미래가 됐고, 모든 접촉이
	--       음수 경과로 debounced에 접혀 fail 4건이 났다
	local a, depsA = newWorld(true)
	local b, depsB = newWorld(true)

	check("케이스마다 다른 플레이어를 쓴다", a.player ~= b.player)

	CashoutPadService._handleTouch(depsA, a.player, 1)
	check("A의 첫 접촉이 처리된다", a.cashoutCalls == 1, tostring(a.cashoutCalls))

	-- B는 같은 시각에 처음 밟는다. A가 방금 밟았어도 막히면 안 된다.
	CashoutPadService._handleTouch(depsB, b.player, 1)
	check("B는 A의 디바운스에 걸리지 않는다", b.cashoutCalls == 1, tostring(b.cashoutCalls))
	check("A의 호출 수가 B 때문에 늘지 않는다", a.cashoutCalls == 1, tostring(a.cashoutCalls))
end

-- 4. 클리어 전에는 지급이 없다 -------------------------------------------------------------
--
-- 발판은 판정하지 않는다. cashout이 거부하고, 런은 그대로 남는다.

do
	local w, deps = newWorld(false)

	CashoutPadService._handleTouch(deps, w.player, 1)

	check("미클리어: cashout은 불린다 (발판은 판정하지 않는다)", w.cashoutCalls == 1, tostring(w.cashoutCalls))
	check("미클리어: 런이 그대로 남는다 (지급 없음)", w.run ~= nil)
	check("미클리어: 런이 아직 클리어 상태가 아니다", w.run ~= nil and w.run.cleared == false)
end

do
	-- 런이 아예 없을 때. 수령 뒤 발판 위에 서 있는 상황이다.
	local w, deps = newWorld(true)
	w.run = nil

	CashoutPadService._handleTouch(deps, w.player, 1)
	check("런 없음: 지급이 일어나지 않는다", w.run == nil)
end

-- 5. source에 경로가 실린다 ---------------------------------------------------------------
--
-- CurrencyService 로그만 봐도 발판 수령인지 자동 수령인지 갈려야 한다
-- (CLAUDE.md 절대 규칙 2 — 누수 추적을 한 지점으로 좁힌다).

do
	local w, deps = newWorld(true)
	CashoutPadService._handleTouch(deps, w.player, 7)

	check("source가 비어 있지 않다", #w.sources == 1 and #w.sources[1] > 0, w.sources[1] or "없음")
	check(
		"source에 스테이지 번호가 실린다",
		w.sources[1] ~= nil and string.find(w.sources[1], "7") ~= nil,
		w.sources[1] or "없음"
	)
end

-- 6. 세울 발판 목록 ------------------------------------------------------------------------

do
	local stages = pure.stagesToBuild(5)
	check("스테이지 수만큼 발판이 선다", #stages == 5, tostring(#stages))
	check("1층부터 선다", stages[1] == 1)
	check("최종 층에도 발판이 선다 (진행 벽이 막혀도 수령은 가능)", stages[#stages] == 5)

	local more = pure.stagesToBuild(9)
	check("스테이지 수가 늘면 발판도 는다", #more == 9, tostring(#more))
end

do
	local last = pure.findLastStage()
	local StageConfig = require(ReplicatedStorage.Shared.Config.StageConfig)
	-- ⚠️ 25를 적지 않는다. 월드가 추가되면 저절로 올라가야 하는 값이다.
	check("마지막 스테이지가 실재한다", StageConfig.hasStage(last))
	check("그 다음은 없다", not StageConfig.hasStage(last + 1))
end

print(string.format("[CashoutPadServiceTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[CashoutPadServiceTests] %d test(s) failed", failed))
end

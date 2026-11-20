--!strict
-- 유료 랜덤 아이템 제한 판정 (Phase 8 지시서 #16 · DESIGN 9장 S13 · 6장 P2).
--
-- 접속할 때 PolicyService:GetPolicyInfoForPlayerAsync(player)의 ArePaidRandomItemsRestricted를 한 번 확인해 세션 메모리에 둔다.
-- 제한 유저면 로벅스 행운 상품(ShopConfig paidRandom — 럭키 · 슈퍼 롤 · 10배 아우라 · 칭호 행운 · 2배 펫 행운 · 행운 포션 · 포션 번들)을
-- 숨기고, **보유한 것도 효과를 끈다.** 판정 실패 · 확인 전도 제한으로 본다 — 행운 상품에만 쓰는 판정이다(다른 상품은 막지 않는다).
-- 공식 문서의 처리 5가지 중 "숨김"(Removing or hiding)을 고른 것이다(사람 결정 2026-10-25).
--
-- 가짜 제한 판정(지시서 #27): Bootstrap TEST_PAID_RANDOM_RESTRICTED(true · false)를 넣고 Play하면 **Studio에서만** 정책 응답 대신 그 값을
-- 쓴다 — 제한 유저 화면(행운 상품 숨김 · 효과 꺼짐 · 롤 쓰기 막힘)을 띄워 보는 용도. Studio가 아니면 무시하고 ERROR 로그.
-- 커밋 값은 언제나 nil(PolicyGateTests가 잰다 — 켠 Play에서는 그 줄이 실패한다. 그 Play로 테스트 개수를 세지 않는다).

local Players = game:GetService("Players")

local MarketplaceGateway = require(script.Parent.MarketplaceGateway)

local PolicyGate = {}

export type Deps = {
	gateway: MarketplaceGateway.Gateway,
	notify: (Player) -> (),
	forced: boolean?, -- 가짜 제한 판정(Studio 전용 — resolveTestRestricted가 고른 값). nil이면 정책 응답
}

-- TEST_PAID_RANDOM_RESTRICTED → 쓸 값 · 로그 한 줄. boolean이 아니면 nil(줄 없음 — nil이 커밋 값). Studio가 아니면 nil + ERROR.
local function resolveTestRestricted(value: any, isStudio: boolean): (boolean?, string?)
	if value == nil then
		return nil, nil
	end
	if not isStudio then
		return nil, "[PolicyGate] ERROR TEST_PAID_RANDOM_RESTRICTED는 Studio 전용이다 — 무시하고 정책 응답을 쓴다"
	end
	if type(value) ~= "boolean" then
		return nil, "[PolicyGate] ERROR TEST_PAID_RANDOM_RESTRICTED는 true · false만 — 무시한다"
	end
	return value, string.format("[PolicyGate] ⚠️ TEST_PAID_RANDOM_RESTRICTED = %s (Studio 전용) — 정책 응답 대신 이 값", tostring(value))
end

local function createRuntime(deps: Deps)
	local restricted: { [Player]: boolean } = {}
	local checked: { [Player]: boolean } = {}
	local runtime = {}

	-- 접속 확인(yield할 수 있다). 실패면 제한.
	function runtime.onJoin(player: Player)
		if deps.forced ~= nil then
			restricted[player] = deps.forced
			checked[player] = false -- 실제 응답이 아니다
			deps.notify(player)
			return
		end
		local ok, info = deps.gateway.getPolicy(player)
		restricted[player] = not ok or info == nil or info.ArePaidRandomItemsRestricted ~= false
		checked[player] = ok
		deps.notify(player)
	end

	-- 행운 상품을 막아야 하는가. 확인 전이면 true.
	function runtime.isPaidRandomRestricted(player: Player): boolean
		local v = restricted[player]
		return v == nil or v == true
	end

	-- 판정이 실제 정책 응답에서 왔는가(실패 · 확인 전이면 false — 관측용)
	function runtime.wasChecked(player: Player): boolean
		return checked[player] == true
	end

	function runtime.onRemoving(player: Player)
		restricted[player] = nil
		checked[player] = nil
	end

	return runtime
end

PolicyGate._pure = { createRuntime = createRuntime, resolveTestRestricted = resolveTestRestricted }

local runtime: any = nil
local listeners: { (Player) -> () } = {}

function PolicyGate.onChanged(callback: (Player) -> ())
	table.insert(listeners, callback)
end

function PolicyGate.isPaidRandomRestricted(player: Player): boolean
	return runtime == nil or runtime.isPaidRandomRestricted(player)
end

local initialized = false
local requested: boolean? = nil
local registered = false

-- Bootstrap이 넘긴 TEST_PAID_RANDOM_RESTRICTED(커밋 값 검사용 — PolicyGateTests). 두 번째 값 = init이 불렸는가
function PolicyGate.getRequestedTestRestricted(): (boolean?, boolean)
	return requested, registered
end

function PolicyGate.init(testRestricted: boolean?)
	if initialized then
		return
	end
	initialized = true
	requested = testRestricted
	registered = true
	local forced, line = resolveTestRestricted(testRestricted, game:GetService("RunService"):IsStudio())
	if line ~= nil then
		if forced == nil then
			warn(line)
		else
			print(line)
		end
	end
	runtime = createRuntime({
		gateway = MarketplaceGateway.get(),
		forced = forced,
		notify = function(player: Player)
			for _, cb in ipairs(listeners) do
				pcall(cb, player)
			end
		end,
	})
	local function join(player: Player)
		task.spawn(function()
			runtime.onJoin(player)
			print(string.format("[PolicyGate] %s(%d) 유료 랜덤 아이템 제한=%s (정책 응답=%s)", player.Name, player.UserId,
				tostring(runtime.isPaidRandomRestricted(player)), tostring(runtime.wasChecked(player))))
		end)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in ipairs(Players:GetPlayers()) do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		runtime.onRemoving(player)
	end)
end

return PolicyGate

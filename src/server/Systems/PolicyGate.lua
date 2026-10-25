--!strict
-- 유료 랜덤 아이템 제한 판정 (Phase 8 지시서 #16 · DESIGN 9장 S13 · 6장 P2).
--
-- 접속할 때 PolicyService:GetPolicyInfoForPlayerAsync(player)의 ArePaidRandomItemsRestricted를 한 번 확인해 세션 메모리에 둔다.
-- 제한 유저면 로벅스 행운 상품(ShopConfig paidRandom — 럭키 · 슈퍼 롤 · 10배 아우라 · 칭호 행운 · 2배 펫 행운 · 행운 포션 · 포션 번들)을
-- 숨기고, **보유한 것도 효과를 끈다.** 판정 실패 · 확인 전도 제한으로 본다 — 행운 상품에만 쓰는 판정이다(다른 상품은 막지 않는다).
-- 공식 문서의 처리 5가지 중 "숨김"(Removing or hiding)을 고른 것이다(사람 결정 2026-10-25).

local Players = game:GetService("Players")

local MarketplaceGateway = require(script.Parent.MarketplaceGateway)

local PolicyGate = {}

export type Deps = {
	gateway: MarketplaceGateway.Gateway,
	notify: (Player) -> (),
}

local function createRuntime(deps: Deps)
	local restricted: { [Player]: boolean } = {}
	local checked: { [Player]: boolean } = {}
	local runtime = {}

	-- 접속 확인(yield할 수 있다). 실패면 제한.
	function runtime.onJoin(player: Player)
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

PolicyGate._pure = { createRuntime = createRuntime }

local runtime: any = nil
local listeners: { (Player) -> () } = {}

function PolicyGate.onChanged(callback: (Player) -> ())
	table.insert(listeners, callback)
end

function PolicyGate.isPaidRandomRestricted(player: Player): boolean
	return runtime == nil or runtime.isPaidRandomRestricted(player)
end

local initialized = false

function PolicyGate.init()
	if initialized then
		return
	end
	initialized = true
	runtime = createRuntime({
		gateway = MarketplaceGateway.get(),
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

--!strict
-- 런 중 사망 = 포기. 활성 런이 있는 플레이어의 Humanoid가 죽으면
-- ChallengeService.abandonRun(player)를 부른다 (보상 0, endRun 경로 그대로 — 스폰 복귀 포함).
--
-- 왜 필요한가: 이 파일 전에는 사망과 런을 잇는 코드가 없었다. 죽어도 런은 살아 있고,
-- 리스폰은 스폰 지점이라 캐릭터는 아레나 밖에 있는데 타이머만 돌다가 시간 초과로 끝났다.
-- 클리어 대기 중인 런이면 시간 초과도 없어서(클리어된 런은 만료되지 않는다) 런이 남은 채로
-- 다음 입장 게이트를 막았다 — 게이트는 런이 있으면 아무것도 안 한다.
--
-- ===== 리스폰마다 다시 연결한다 =======================================================
--
-- Humanoid는 캐릭터마다 새로 생긴다. 첫 캐릭터의 Died에만 걸면 두 번째 죽음부터 놓친다.
-- 그래서 CharacterAdded마다 그 캐릭터의 Humanoid.Died에 건다.
--
-- ===== 같은 죽음에 두 번 불리지 않는다 ================================================
--
-- 두 겹이다:
--   1. 죽음 하나마다 상태 테이블을 하나 두고, 처리하면 표시한다 — 같은 죽음 신호가
--      다시 와도(Died 재발화·HealthChanged 경로 추가 등) 두 번째는 걸러진다
--   2. abandonRun이 런을 지운다 — 표시가 어떻게 되든 두 번째 호출은 "런 없음"이 된다
-- 1번이 이 파일의 보장이고 2번은 ChallengeService의 보장이다.

local Players = game:GetService("Players")

local ChallengeService = require(script.Parent.ChallengeService)

local RunDeathService = {}

-- ===== 순수 로직 =====================================================================

export type DeathState = {
	handled: boolean,
}

local function newDeathState(): DeathState
	return { handled = false }
end

export type Deps = {
	getRunState: (Player) -> any?,
	abandonRun: (Player) -> boolean,
}

local defaultDeps: Deps = {
	getRunState = ChallengeService.getRunState :: any,
	abandonRun = ChallengeService.abandonRun,
}

-- 죽음 하나를 처리한다. abandon을 불렀으면 true.
--
-- ⚠️ yield하지 않는다. 런 확인과 abandon 사이에 다른 핸들러(cashout 등)가 끼면 안 된다.
local function handleDied(deps: Deps, player: Player, death: DeathState): boolean
	if death.handled then
		return false
	end
	death.handled = true

	if deps.getRunState(player) == nil then
		return false
	end

	deps.abandonRun(player)
	print(string.format("[RunDeathService] %s 런 중 사망 -> abandonRun (보상 0)", player.Name))
	return true
end

RunDeathService._pure = {
	newDeathState = newDeathState,
	handleDied = handleDied,
}

-- ===== 런타임 =========================================================================

local function watchCharacter(player: Player, character: Model)
	-- Humanoid는 캐릭터 조립 중에 붙는다. 기다리는 시간은 짧게 — 없으면 이 캐릭터는 포기한다
	-- (다음 리스폰에서 다시 건다).
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		humanoid = character:WaitForChild("Humanoid", 10) :: any
	end
	if humanoid == nil then
		warn(string.format("[RunDeathService] %s: Humanoid 없음 - 이 캐릭터의 사망은 감시하지 않는다", player.Name))
		return
	end

	local death = newDeathState()
	humanoid.Died:Connect(function()
		handleDied(defaultDeps, player, death)
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
	if player.Character ~= nil then
		task.spawn(watchCharacter, player, player.Character)
	end
end

local initialized = false

function RunDeathService.init()
	if initialized then
		warn("[RunDeathService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(watchPlayer)
	-- init 전에 이미 들어와 있던 플레이어도 건다 (Studio Play에서 순서가 바뀔 수 있다).
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
end

return RunDeathService

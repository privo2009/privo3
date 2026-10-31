--!strict
-- 무료 보상 지급 공용 (지시서 #20 R1 — DESIGN.md 9장 "무료 요소 > 보상 지급 공용 — RewardService"). 일일 보상 · 코드 · 첫 접속 완료가 함께 쓴다.
--
--   grant(player, rewards, source) → (true, Granted) | (false, 사유 코드)
--
-- ===== 전부 아니면 0 =====================================================================
--
--   1. 형식      RewardLogic.isValidList가 아니면 invalid_reward
--   2. 프로필    없으면 no_profile
--   3. 저장 공간  펫 수만큼 남은 칸이 없으면 storage_full(PetService.storageRoom — 파생 저장 공간)
--   ----- 여기까지 부작용 0 -----
--   4. 블럭스    bloxScaled 합을 CurrencyService.add 한 번(절대 규칙 2). 거부되면 grant_failed — 아직 아무것도 주지 않았다
--   5. 포션      보관함 potions[kind] += count(바로 켜지지 않는다 — ProductGrants · PotionRequestService와 같은 표)
--   6. 펫        PetService.grant(uid · 빈 슬롯 자동 장착 · 새 petId면 저장). 3에서 칸을 봤으므로 실패하지 않는다 — 실패하면 ERROR 로그
--   7. 통지      PlayerState(notify)
-- 순서가 블럭스 → 포션 → 펫인 이유: 실패할 수 있는 외부 게이트(CurrencyService)를 맨 앞에 둬야 "앞의 것만 준" 상태가 생기지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local RewardLogic = require(ReplicatedStorage.Shared.RewardLogic)

type BigNumber = BigNum.BigNumber

local RewardService = {}

RewardService.REASON_INVALID = "invalid_reward"
RewardService.REASON_NO_PROFILE = "no_profile"
RewardService.REASON_STORAGE_FULL = "storage_full"
RewardService.REASON_GRANT_FAILED = "grant_failed"

-- 준 것 요약(로그 · 결과 payload용). blox = 준 블럭스 합(없으면 0) · potions = {kind, count} · pets = petId.
export type Granted = {
	blox: BigNumber,
	potions: { { kind: string, count: number } },
	pets: { string },
}

export type Deps = {
	getData: (Player) -> any?,
	addBlox: (Player, BigNumber, string) -> boolean,
	petRoom: (Player) -> number?,
	grantPet: (Player, string, string) -> boolean,
	notify: (Player) -> (),
	log: (string) -> (),
}

local function createRuntime(deps: Deps)
	local runtime = {}

	function runtime.grant(player: Player, rewards: any, source: string): (boolean, any)
		if not RewardLogic.isValidList(rewards) then
			return false, RewardService.REASON_INVALID
		end
		local data = deps.getData(player)
		if type(data) ~= "table" or type(data.potions) ~= "table" then
			return false, RewardService.REASON_NO_PROFILE
		end
		local petCount = RewardLogic.petCount(rewards)
		if petCount > 0 then
			local room = deps.petRoom(player)
			if room == nil then
				return false, RewardService.REASON_NO_PROFILE
			end
			if room < petCount then
				return false, RewardService.REASON_STORAGE_FULL
			end
		end

		-- ===== 여기부터 부작용 =====
		local maxStage = if type(data.progress) == "table" then data.progress.maxStage else nil
		local blox = BigNum.new(0, 0)
		for _, r in ipairs(rewards) do
			if r.type == "bloxScaled" then
				blox = BigNum.add(blox, RewardLogic.bloxAmount(maxStage, r.k :: number))
			end
		end
		if BigNum.gt(blox, BigNum.new(0, 0)) and not deps.addBlox(player, blox, "reward_" .. source) then
			return false, RewardService.REASON_GRANT_FAILED
		end

		local granted: Granted = { blox = blox, potions = {}, pets = {} }
		for _, r in ipairs(rewards) do
			if r.type == "potion" then
				local kind = r.kind :: string
				local have = data.potions[kind]
				data.potions[kind] = (if type(have) == "number" and have >= 0 then have else 0) + (r.count :: number)
				table.insert(granted.potions, { kind = kind, count = r.count :: number })
			end
		end
		for _, r in ipairs(rewards) do
			if r.type == "pet" then
				if deps.grantPet(player, r.petId :: string, "reward_" .. source) then
					table.insert(granted.pets, r.petId :: string)
				else
					deps.log(string.format("[RewardService][ERROR] %s 펫 %s 지급 실패(저장 공간을 미리 봤는데도) source=%s", player.Name,
						tostring(r.petId), source))
				end
			end
		end
		deps.notify(player)
		return true, granted
	end

	return runtime
end

RewardService._pure = {
	createRuntime = createRuntime,
}

local live: any = nil

export type InitDeps = {
	getData: (Player) -> any?,
	addBlox: (Player, BigNumber, string) -> boolean,
	petRoom: (Player) -> number?,
	grantPet: (Player, string, string) -> boolean,
	notify: (Player) -> (),
}

-- 서비스를 Bootstrap이 넘긴다(PlayerStateService가 일일 보상 요약 때문에 이 파일을 쓰는 쪽을 require해서 순환을 피한다).
function RewardService.init(services: InitDeps)
	if live ~= nil then
		warn("[RewardService] init()이 이미 호출된 상태 - 중복 호출 무시")
		return
	end
	live = createRuntime({
		getData = services.getData,
		addBlox = services.addBlox,
		petRoom = services.petRoom,
		grantPet = services.grantPet,
		notify = services.notify,
		log = function(line: string)
			warn(line)
		end,
	})
	print("[RewardService] 무료 보상 지급 준비 완료")
end

-- 지급. init 전이면 no_profile(아무것도 주지 않는다).
function RewardService.grant(player: Player, rewards: any, source: string): (boolean, any)
	if live == nil then
		return false, RewardService.REASON_NO_PROFILE
	end
	local ok, value = live.grant(player, rewards, source)
	if ok then
		local potions = {}
		for _, p in ipairs(value.potions) do
			table.insert(potions, string.format("%s×%d", p.kind, p.count))
		end
		print(string.format("[RewardService] %s(%d) %s → blox=%s potions=%s pets=%s", player.Name, player.UserId, source,
			BigNum.tostring(value.blox), table.concat(potions, ","), table.concat(value.pets, ",")))
	else
		print(string.format("[RewardService] %s(%d) %s 거부 reason=%s", player.Name, player.UserId, source, tostring(value)))
	end
	return ok, value
end

return RewardService

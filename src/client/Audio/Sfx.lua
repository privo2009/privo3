--!strict
-- 효과음 재생 (지시서 #25 S2 — docs/UI.md "효과음"). 판정은 Audio/SfxLogic, 키 · 볼륨 · 풀 크기는 Shared/Config/SoundConfig.
--
--   Sfx.play(key)   설정(FxPrefs.sfxEnabled) · 같은 키 스로틀(UIFxConfig.SFX_MIN_INTERVAL) · id를 보고 재생한다. 돌려주는 값 = 판정
--   Sfx.init()      시작 때 한 번 — "비어 있는 소리 N개" 한 줄(HudBoot)
--
-- Sound는 키마다 풀(SoundConfig.POOL_PER_KEY장)이고 처음 재생할 때 한 번 만든다(반복 루프의 Instance.new 아님). 자리는 SoundService 아래
-- 클라 폴더 "Sfx"(이 기기에서만 — 서버로 복제되지 않는다. 2D 소리). 서버는 소리용 채널을 만들지 않는다 — 클라가 이미 받는 결과 · 상태에서 부른다.
-- 재생 시도 기록: 폴더 "Sfx"의 Attribute — "<key>" = 시도 수(효과음 켜짐 · 스로틀 통과 — id가 없으면 소리 없이 여기까지만),
--   "muted_<key>" = 효과음 끔으로 막은 수. Play 중 execute_luau(Client)로 읽어 실물 확인을 한다(모듈 값은 그 캐시에서 안 보인다).
-- 재생기: 모듈 함수(Sfx.play)는 전역 재생기 하나다. Sfx.newPlayer({ clock, prefs, folder })는 자기 시계 · 자기 스로틀 기록 · 자기 설정 ·
--   자기 기록 폴더를 가진 따로 노는 재생기(테스트 전용 — 전역 시계 · 기록을 같이 쓰면 다른 테스트의 버튼 소리가 수를 흔든다. #28 단계 0)

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local SfxLogic = require(script.Parent.SfxLogic)
local FxPrefs = require(script.Parent.Parent.UI.FxPrefs)

local Sfx = {}

Sfx.FOLDER_NAME = "Sfx"

export type Player = { play: (key: string) -> SfxLogic.Outcome, _debug: any }
export type Options = { clock: (() -> number)?, prefs: FxPrefs.Prefs?, folder: Folder? }

local function newPlayer(opts: Options?): Player
	local o: Options = opts or {}
	local defaultClock: () -> number = o.clock or os.clock
	local prefs: FxPrefs.Prefs = o.prefs or FxPrefs.global
	local P = {} :: Player

	local lastAt: { [string]: number } = {}
	local pools: { [string]: { sounds: { Sound }, next: number } } = {}
	local folder: Folder? = o.folder
	local clock: () -> number = defaultClock

	local function getFolder(): Folder
		if o.folder ~= nil then
			return o.folder :: Folder
		end
		if folder == nil or folder.Parent == nil then
			local existing = SoundService:FindFirstChild(Sfx.FOLDER_NAME)
			if existing ~= nil and existing:IsA("Folder") then
				folder = existing
			else
				local f = Instance.new("Folder")
				f.Name = Sfx.FOLDER_NAME
				f.Parent = SoundService
				folder = f
			end
		end
		return folder :: Folder
	end

	local function bump(name: string)
		local f = getFolder()
		local n = f:GetAttribute(name)
		f:SetAttribute(name, (if type(n) == "number" then n else 0) + 1)
	end

	-- parent: 테스트만 넘긴다(DataModel 밖 폴더 — 없는 에셋을 불러오려 하지 않게)
	local function poolFor(key: string, def: SoundConfig.SoundDef, parent: Instance?): { sounds: { Sound }, next: number }
		local pool = pools[key]
		if pool == nil then
			local sounds: { Sound } = {}
			for i = 1, SoundConfig.POOL_PER_KEY do
				local s = Instance.new("Sound")
				s.Name = key .. "_" .. i
				s.SoundId = "rbxassetid://" .. tostring(def.id)
				s.Volume = def.volume
				s.Parent = parent or getFolder()
				sounds[i] = s
			end
			pool = { sounds = sounds, next = 1 }
			pools[key] = pool
		end
		return pool :: { sounds: { Sound }, next: number }
	end

	function P.play(key: string): SfxLogic.Outcome
		local def = SoundConfig.Sounds[key]
		local now = clock()
		local outcome = SfxLogic.decide(def, prefs.sfxEnabled(), lastAt[key], now)
		if outcome == "muted" then
			bump("muted_" .. key)
			return outcome
		end
		if outcome == "unknown" or outcome == "throttled" then
			return outcome
		end
		lastAt[key] = now
		bump(key)
		if outcome == "play" then
			local pool = poolFor(key, def :: SoundConfig.SoundDef)
			local s = pool.sounds[pool.next]
			pool.next = pool.next % #pool.sounds + 1
			s.TimePosition = 0
			s:Play()
		end
		return outcome
	end

	-- 테스트 전용: 시계 · 스로틀 기록 지우기 · 풀 보기
	P._debug = {
		setClock = function(f: (() -> number)?)
			clock = f or defaultClock
		end,
		resetThrottle = function()
			table.clear(lastAt)
		end,
		poolOf = function(key: string): { Sound }?
			local p = pools[key]
			return if p ~= nil then p.sounds else nil
		end,
		poolFor = poolFor,
		folder = getFolder,
	}

	return P
end

local global = newPlayer()
Sfx.newPlayer = newPlayer
Sfx.play = global.play
Sfx._debug = global._debug

local initialized = false

function Sfx.init()
	if initialized then
		return
	end
	initialized = true
	global._debug.folder()
	print(string.format("[Sfx] 비어 있는 소리 %d개 (키 %d개 — id를 넣기 전에는 재생하지 않는다 · docs/TUNING.md \"소리 넣는 법\")",
		SfxLogic.emptyCount(SoundConfig.Sounds), #SoundConfig.KEYS))
end

return Sfx

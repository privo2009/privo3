--!strict
-- 저사양 모드 켜짐 · 꺼짐(지시서 #48 3부 — 클라 세션 메모리. 서버에 보내지 않고 저장하지 않는다). 값 · 규칙은 Shared/Config/LowEndConfig.
-- FxPrefs와 같은 꼴: get · set · onChanged · new(테스트 전용 — 따로 노는 하나). 연출 모듈(ParticlePool · ChunkBreaker · CoinFx ·
-- DropRenderer · Shine · 환생 번쩍임)은 이 모듈만 읽는다.
-- 첫 값: initFromDevice()가 기기 그래픽 품질(UserGameSettings.SavedQualityLevel)로 정한다 — 접속마다 한 번(EconomyV2Boot · HudBoot보다 먼저 —
-- 그 전에 부르면 꺼짐으로 시작했다가 바로 바뀐다. 연출은 바뀐 뒤 것부터 따른다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LowEndConfig = require(ReplicatedStorage.Shared.Config.LowEndConfig)

-- ── 저사양 모드 강제: TEST_LOW_END (Studio 전용, 지시서 #48 3부) ───────────────────────────────
-- true · false를 적고 Play하면 Studio에서만 기기 품질 대신 이 값으로 시작한다(봇 fresh를 저사양으로 돌리는 용도).
-- Studio가 아니면 무시한다. ⚠️ 커밋 값은 언제나 nil이다(tools/check_test_gate.py가 잰다)
local TEST_LOW_END: boolean? = nil

export type Prefs = {
	get: () -> boolean,
	set: (on: boolean) -> (),
	onChanged: (f: (boolean) -> ()) -> (),
}

local function newPrefs(): Prefs
	local on = false
	local listeners: { (boolean) -> () } = {}
	local p = {} :: Prefs
	function p.get(): boolean
		return on
	end
	function p.set(v: boolean)
		local nv = v == true
		if nv == on then
			return
		end
		on = nv
		for _, f in ipairs(listeners) do
			f(nv)
		end
	end
	function p.onChanged(f: (boolean) -> ())
		table.insert(listeners, f)
	end
	return p
end

local global = newPrefs()

local LowEndPrefs = {}

LowEndPrefs.new = newPrefs
LowEndPrefs.get = global.get
LowEndPrefs.set = global.set
LowEndPrefs.onChanged = global.onChanged
LowEndPrefs.global = global

-- 기기 품질 단계(0 ~ 10) — 못 읽으면 nil(공식 문서 예시도 pcall로 읽는다)
function LowEndPrefs.readQualityLevel(): number?
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" then
		return level
	end
	return nil
end

local initialized = false
-- 접속마다 한 번: 기기 품질로 첫 값. 돌려주는 값: (정한 값, 읽은 단계)
function LowEndPrefs.initFromDevice(read: (() -> number?)?): (boolean, number?)
	local level = (read or LowEndPrefs.readQualityLevel)()
	local on = LowEndConfig.defaultFromQuality(level)
	if read == nil and TEST_LOW_END ~= nil and RunService:IsStudio() then
		on = TEST_LOW_END == true
		print(string.format("[LowEndPrefs] ⚠️ TEST_LOW_END = %s (Studio 전용) — 기기 품질(%s) 대신", tostring(TEST_LOW_END), tostring(level)))
	end
	if not initialized then
		initialized = true
		global.set(on)
	end
	return on, level
end

-- 처음 require될 때 기기 품질로 첫 값(연출 모듈 · 설정 창 · 봇 어느 쪽이 먼저 불러도 같은 값으로 시작한다)
LowEndPrefs.initFromDevice()

return LowEndPrefs

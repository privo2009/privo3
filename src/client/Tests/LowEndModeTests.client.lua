--!strict
-- 저사양 폰 모드 검증(지시서 #48 3부). 켜면 상한 · 연출이 줄어드는가 · 꺼지면 원래대로 · 첫 값은 기기 품질 · 게임 판정에는 닿지 않는가.
-- 전역 값(LowEndPrefs.global)을 바꾸는 검사는 yield 없이 바꾸고 바로 되돌린다(같이 도는 다른 테스트의 연출이 섞이지 않게).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LowEndConfig = require(ReplicatedStorage.Shared.Config.LowEndConfig)
local LowEndPrefs = require(script.Parent.Parent.UI.LowEndPrefs)
local ParticlePool = require(script.Parent.Parent.Effects.ParticlePool)
local ChunkBreaker = require(script.Parent.Parent.Effects.ChunkBreaker)
local CoinFx = require(script.Parent.Parent.Economy.CoinFx)
local DropRenderer = require(script.Parent.Parent.Economy.DropRenderer)

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

-- 전역 값을 잠깐 바꿔 f를 부르고 되돌린다(yield 금지)
local function withGlobal<T>(on: boolean, f: () -> T): T
	local before = LowEndPrefs.get()
	LowEndPrefs.set(on)
	local r = f()
	LowEndPrefs.set(before)
	return r
end

-- 1. 첫 값: 기기 품질 1 ~ QUALITY_ON_MAX면 켜짐 · Automatic(0) · 높은 단계 · 못 읽음은 꺼짐 -----------------------
do
	local d = LowEndConfig.defaultFromQuality
	local lowOk = true
	for level = 1, LowEndConfig.QUALITY_ON_MAX do
		lowOk = lowOk and d(level)
	end
	local highOk = true
	for level = LowEndConfig.QUALITY_ON_MAX + 1, 10 do
		highOk = highOk and not d(level)
	end
	check("첫 값: 품질 1 ~ 3 켜짐 · 4 ~ 10 꺼짐 · Automatic(0) · nil · NaN 꺼짐", lowOk and highOk and not d(0) and not d(nil) and not d(0 / 0))
	local on, level = LowEndPrefs.initFromDevice(function()
		return 2
	end)
	check("기기 읽기: 가짜 품질 2 → 켜짐을 돌려주되 이미 정한 전역 값은 다시 덮지 않는다(접속마다 한 번)", on == true and level == 2)
	local real = LowEndPrefs.readQualityLevel()
	check("기기 읽기: 실제 값은 0 ~ 10 또는 nil(못 읽음)", real == nil or (real >= 0 and real <= 10), tostring(real))
end

-- 2. 따로 노는 설정(new): 바뀔 때만 알린다 -------------------------------------------------------------------
do
	local p = LowEndPrefs.new()
	local calls = 0
	p.onChanged(function()
		calls += 1
	end)
	p.set(true)
	p.set(true)
	p.set(false)
	check("설정: 기본 꺼짐 · 바뀔 때만 알림(같은 값 두 번은 한 번)", calls == 2 and p.get() == false)
end

-- 3. 줄어드는 것: 동시 파편 · 파편 솎기 · 코인 · 드롭 · 반짝이 ------------------------------------------------------
do
	local capOn = withGlobal(true, function()
		return ParticlePool.cap()
	end)
	local capOff = withGlobal(false, function()
		return ParticlePool.cap()
	end)
	check("동시 파편: 켜면 FRAGMENT_CAP(100) · 끄면 풀 200(절대 규칙 4 상한)", capOn == LowEndConfig.FRAGMENT_CAP and capOff == 200)
	-- 켠 채로 빌릴 수 있는 만큼 빌려 본다(yield 없이 — 바로 돌려준다)
	local got = withGlobal(true, function()
		local list = {}
		local inUse = ParticlePool.getStats().inUse
		while true do
			local f = ParticlePool.acquire()
			if f == nil then
				break
			end
			table.insert(list, f)
		end
		local n = #list + inUse
		for _, f in ipairs(list) do
			ParticlePool.release(f)
		end
		return n
	end)
	check("동시 파편: 켜면 빌려준 수가 상한에서 멈춘다", got <= LowEndConfig.FRAGMENT_CAP, tostring(got))
	local si = ChunkBreaker._computeSampleInterval
	local on = withGlobal(true, function()
		return { si(3), si(12), si(60) }
	end)
	local off = withGlobal(false, function()
		return { si(3), si(12), si(60) }
	end)
	check("파편 솎기: 켜면 배치당 파편 약 절반(12개 배치 간격 1 → 2 · 60개 5 → 10)", on[1] == 1 and off[1] == 1 and off[2] == 1 and on[2] == 2
		and off[3] == 5 and on[3] == 10)
	check("코인: 한 번에 6 → 3(재화는 서버 값 그대로 — 그림만)", CoinFx.burstMax(function()
		return true
	end) == LowEndConfig.COIN_BURST and CoinFx.burstMax(function()
		return false
	end) == CoinFx.MAX_PER_BURST)
	local function drops(low: boolean): (number, number)
		local folder = Instance.new("Folder")
		local r = DropRenderer.create({ parent = folder, autoStep = false, lowEnd = function()
			return low
		end, template = function(_key: string): Instance?
			return nil
		end })
		local list = {}
		for i = 1, LowEndConfig.DROP_VISIBLE_MAX + 10 do
			table.insert(list, { id = i, ore = 1, position = Vector3.new(i, 0, 0) })
		end
		r.spawn(list)
		local n = r.activeCount()
		r.pick({ 1, LowEndConfig.DROP_VISIBLE_MAX + 5 }) -- 안 그린 드롭을 주웠다는 신호도 오류 없이
		local after = r.activeCount()
		r.destroy()
		folder:Destroy()
		return n, after
	end
	local nOn, afterOn = drops(true)
	local nOff = drops(false)
	check("드롭: 켜면 동시에 그리는 수 DROP_VISIBLE_MAX · 끄면 전부 · 안 그린 드롭 줍기 신호도 문제없음", nOn == LowEndConfig.DROP_VISIBLE_MAX
		and nOff == LowEndConfig.DROP_VISIBLE_MAX + 10 and afterOn == nOn - 1)
	check("끄는 연출: 드롭 반짝이 · 빛 띠 · 환생 번쩍임 꺼짐(화면 흔들림은 이 게임에 없다)", LowEndConfig.DROP_SPARKLE == false and LowEndConfig.SHINE == false
		and LowEndConfig.REBIRTH_FLASH == false)
end

-- 4. 게임 판정에는 닿지 않는다: 값은 클라 세션 메모리뿐 · 줄어드는 것은 전부 상한 쪽(늘리지 않는다) ----------------------
do
	local pickOk = LowEndConfig.pick(true, 6, 3) == 3 and LowEndConfig.pick(false, 6, 3) == 6 and LowEndConfig.pick(true, 2, 3) == 2
	local lower = LowEndConfig.FRAGMENT_CAP < 200 and LowEndConfig.FRAGMENT_FULL_BATCH < 6 and LowEndConfig.FRAGMENT_TARGET < 12
		and LowEndConfig.COIN_BURST < CoinFx.MAX_PER_BURST
	check("판정 무관: 켜도 줄기만 한다(원래보다 크게 안 됨) · pick", pickOk and lower)
	-- 서버로 가는 리모트가 없다: 설정 줄은 localOnly(서버 화이트리스트 키가 아니다)
	local SettingsWindow = require(script.Parent.Parent.UI.Screens.Window.SettingsWindow)
	local row = SettingsWindow.ROWS[#SettingsWindow.ROWS] :: any
	check("판정 무관: 설정 줄은 서버에 안 보낸다(localOnly — 저장 필드 없음)", row.key == "lowEnd" and row.localOnly == true)
end

print(string.format("[LowEndModeTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[LowEndModeTests] %d test(s) failed", failed))
end

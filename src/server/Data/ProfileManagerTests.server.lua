--!strict
-- ProfileManager 데이터 안전(지시서 #38 3단계). 가짜 저장소 · 가짜 프로필로만 — 실제 DataStore는 건드리지 않는다.
--   1. 세션 열기 실패 경로(저장소 없음 · 세션 잠금 실패 · 로딩 중 나감 · 버전 오류 · 손상) → 킥 문구 키 · 세션 닫음
--   2. 킥 문구가 Strings에 en · ko 둘 다
--   3. 세션 끝(나감 · 서버 종료는 경고 아님 · 다른 서버는 경고 + 킥)
--   4. 서버 종료 저장 기다리기(전부 EndSession · 빌 때까지 · 상한)

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local ProfileManager = require(script.Parent.ProfileManager)
local Migrations = require(script.Parent.Migrations)
local Schema = require(script.Parent.Schema)

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

local pure = ProfileManager._pure
local P = ({ Name = "PMTest", UserId = 3838 } :: any) :: Player

local function fakeProfile(data: any)
	local p = { Data = data, ended = 0 }
	function p.EndSession(self: any)
		self.ended += 1
	end
	function p.AddUserId() end
	function p.Reconcile() end
	return p
end

local function fakeStore(profile: any, onStart: ((any) -> ())?)
	local store = { calls = 0, lastKey = nil :: any, cancel = nil :: any }
	function store.StartSessionAsync(self: any, key: string, opts: any)
		self.calls += 1
		self.lastKey = key
		self.cancel = opts and opts.Cancel
		if onStart then
			onStart(self)
		end
		return profile
	end
	return store
end

local function run(store: any, inGame: boolean | () -> boolean): (any, string?, { string })
	local lines = {}
	local profile, key = pure.openProfile(P, store, {
		inGame = function()
			if type(inGame) == "function" then
				return inGame()
			end
			return inGame
		end,
		log = function(l: string)
			table.insert(lines, l)
		end,
	})
	return profile, key, lines
end

-- 1. 세션 열기 ----------------------------------------------------------------------------------------
do
	local p0, k0 = run(nil, true)
	check("저장소 없음 → 킥 kick.loadFailed", p0 == nil and k0 == "kick.loadFailed")

	local lockStore = fakeStore(nil)
	local p1, k1, l1 = run(lockStore, true)
	check("세션 잠금 실패(StartSessionAsync nil) → 킥 kick.loadFailed · 경고 한 줄", p1 == nil and k1 == "kick.loadFailed" and #l1 == 1
		and lockStore.lastKey == tostring(P.UserId))
	check("세션 열기 Cancel: 나가면 기다림을 그만둔다", type(lockStore.cancel) == "function")

	local p2, k2 = run(fakeStore(nil), false)
	check("세션 잠금 실패인데 이미 나감 → 킥 없음(조용히 끝)", p2 == nil and k2 == nil)

	local left = fakeProfile(Schema.new())
	local p3, k3 = run(fakeStore(left), false)
	check("세션은 열렸는데 로딩 중 나감 → 세션 닫음 · 킥 없음", p3 == nil and k3 == nil and left.ended == 1)

	local future = Schema.new()
	future.schemaVersion = Migrations.CURRENT + 1
	local fp = fakeProfile(future)
	local p4, k4 = run(fakeStore(fp), true)
	check("버전이 서버보다 새것 → 킥 kick.versionError · 세션 닫음(덮어쓰지 않음)", p4 == nil and k4 == "kick.versionError" and fp.ended == 1, tostring(k4))

	local broken = Schema.new()
	broken.blox = "garbage" :: any -- BigNum이 아님
	local bp = fakeProfile(broken)
	local p5, k5, l5 = run(fakeStore(bp), true)
	check("데이터 손상(블럭스가 BigNum이 아님) → 킥 kick.corrupted · 세션 닫음 · 사유 줄", p5 == nil and k5 == "kick.corrupted" and bp.ended == 1 and #l5 >= 2,
		tostring(k5))

	local good = fakeProfile(Schema.new())
	local p6, k6 = run(fakeStore(good), true)
	check("정상 → 프로필 · 세션 그대로", p6 == good and k6 == nil and good.ended == 0)

	-- 잠금이 늦게 풀리는 동안 나간 경우: StartSessionAsync 안에서 나감 → 열린 세션을 바로 닫는다
	local inGame = true
	local late = fakeProfile(Schema.new())
	local p7, k7 = run(fakeStore(late, function()
		inGame = false
	end), function()
		return inGame
	end)
	check("세션 여는 동안 나감 → 세션 닫음 · 킥 없음", p7 == nil and k7 == nil and late.ended == 1)
end

-- 2. 킥 문구 ------------------------------------------------------------------------------------------
do
	local all = true
	for _, key in ipairs({ "kick.loadFailed", "kick.versionError", "kick.corrupted", "kick.otherServer" }) do
		local en = Locale.template("en", key)
		local ko = Locale.template("ko", key)
		all = all and en ~= nil and ko ~= nil and en ~= ko
	end
	check("킥 문구 4개: Strings에 en · ko 둘 다(서로 다름)", all)
end

-- 3. 세션 끝 ------------------------------------------------------------------------------------------
do
	local l1, w1 = pure.sessionEndedLine(P, true)
	local l2, w2 = pure.sessionEndedLine(P, false)
	check("세션 끝: 서버에 있는데 끝남(다른 서버) → 경고 · 킥", w1 and string.find(l1, "다른 서버", 1, true) ~= nil)
	check("세션 끝: 나감 · 서버 종료 → 경고 아님", not w2)
end

-- 4. 서버 종료 저장 기다리기 -------------------------------------------------------------------------------
do
	local list: { [any]: any } = {}
	local ends = 0
	for i = 1, 12 do
		local key = {}
		list[key] = {
			EndSession = function()
				ends += 1
				task.defer(function()
					list[key] = nil -- OnSessionEnd가 지우는 것과 같다(다음 프레임)
				end)
			end,
		}
	end
	local remaining = pure.drainOnClose(list, 5, os.clock, function()
		task.wait()
	end)
	check("서버 종료: 12명 전부 EndSession · 저장 끝까지 기다림 → 남은 0", ends == 12 and remaining == 0 and next(list) == nil)

	local stuck: { [any]: any } = { [1] = { EndSession = function() end }, [2] = { EndSession = function() end } }
	local t = 0
	local r2 = pure.drainOnClose(stuck, 20, function()
		return t
	end, function()
		t += 1
	end)
	check("서버 종료: 저장이 안 끝나면 상한(20초)에서 포기 · 남은 수", r2 == 2 and t == 20)
end

print(string.format("[ProfileManagerTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ProfileManagerTests] %d test(s) failed", failed))
end

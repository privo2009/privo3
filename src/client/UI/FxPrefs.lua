--!strict
-- 연출 줄이기 · 효과음 설정의 클라 쪽 값 (지시서 #25 U7 · S3). 원본은 서버 프로필 cosmetics(v9) → PlayerState "settings" → Store.
-- Fx · ButtonFx · Shine · Sfx는 이 모듈만 읽는다(Store를 직접 구독하지 않는다 — 테스트가 값을 바꿨다 되돌릴 수 있게).
--
--   FxPrefs.reduceMotion()   켜져 있으면 화면 연출 · 버튼 반응 · 빛 띠가 움직이지 않는다(기본 false)
--   FxPrefs.sfxEnabled()     꺼져 있으면 효과음을 하나도 재생하지 않는다(기본 true)
--   FxPrefs.set(r, s)        값을 바꾸고 바뀌었으면 듣는 쪽을 부른다
--   FxPrefs.onChanged(f)     값이 바뀔 때마다 f(reduceMotion, sfxEnabled)
--   FxPrefs.bind(store)      Store "settings"를 따른다(HudBoot가 한 번 부른다)
--   FxPrefs.new()            따로 노는 설정 하나(같은 함수 넷 — 테스트 전용). 게임은 모듈 함수(전역 설정)만 쓴다.
--                            테스트가 전역 설정을 바꾸면 같이 도는 다른 테스트의 연출까지 끝난다(#28 단계 0 — 격리 구동기와 짝)

export type Prefs = {
	reduceMotion: () -> boolean,
	sfxEnabled: () -> boolean,
	set: (reduceMotion: boolean, sfxEnabled: boolean) -> (),
	onChanged: (f: (boolean, boolean) -> ()) -> (),
}

local function newPrefs(): Prefs
	local reduce = false
	local sfx = true
	local listeners: { (boolean, boolean) -> () } = {}
	local p = {} :: Prefs
	function p.reduceMotion(): boolean
		return reduce
	end
	function p.sfxEnabled(): boolean
		return sfx
	end
	function p.set(reduceMotion: boolean, sfxEnabled: boolean)
		local r, s = reduceMotion == true, sfxEnabled ~= false
		if r == reduce and s == sfx then
			return
		end
		reduce, sfx = r, s
		for _, f in ipairs(listeners) do
			f(r, s) -- 바로 부른다 — 켜는 순간 이미 붙은 버튼 · 빛 띠가 같은 프레임에 따른다
		end
	end
	function p.onChanged(f: (boolean, boolean) -> ())
		table.insert(listeners, f)
	end
	return p
end

local global = newPrefs()

local FxPrefs = {}

FxPrefs.new = newPrefs
FxPrefs.reduceMotion = global.reduceMotion
FxPrefs.sfxEnabled = global.sfxEnabled
FxPrefs.set = global.set
FxPrefs.onChanged = global.onChanged
-- 전역 설정 자체(구동기 · 빛 띠 · 효과음의 기본 prefs)
FxPrefs.global = global

local bound = false

function FxPrefs.bind(store: any)
	if bound then
		return
	end
	bound = true
	local function apply(v: any)
		if type(v) == "table" then
			global.set(v.reduceMotion == true, v.sfxEnabled ~= false)
		end
	end
	apply(store.get("settings"))
	store.subscribe("settings", apply)
end

return FxPrefs

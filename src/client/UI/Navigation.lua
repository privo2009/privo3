--!strict
-- 화면 사이 이동 요청 한 곳 (지시서 #17). HUD(HudBoot)와 창(WindowBoot)은 다른 LocalScript라 서로의 핸들을 모른다 —
-- 같은 ModuleScript는 클라에서 한 번만 실행되므로 이 모듈의 신호로 잇는다.
--   openPotions()  상점 창을 로벅스 탭 "포션" 묶음으로 연다(HUD 부스트 표시를 누르면). 듣는 쪽은 WindowBoot 하나

local Navigation = {}

local potionListeners: { () -> () } = {}

function Navigation.onOpenPotions(callback: () -> ())
	table.insert(potionListeners, callback)
end

function Navigation.openPotions()
	for _, cb in ipairs(potionListeners) do
		task.spawn(cb)
	end
end

return Navigation

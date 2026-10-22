--!strict
-- TouchSafeLayout 순수 계산 검증 (Phase 6 지시서 #6). 사각형은 2026-10-22 실측값(Galaxy A06, HudGui 705×280)을
-- Scale로 바꾼 것이다 — 실측 원본은 세션 로그와 UI/TouchSafeLayout 상단.

local TouchSafeLayout = require(script.Parent.Parent.UI.TouchSafeLayout)

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

local GUI = Vector2.new(705, 280)
local function px(x: number, y: number, w: number, h: number)
	return TouchSafeLayout.pixelToScale(Vector2.new(x, y), Vector2.new(w, h), GUI)
end

local jump = px(610, 190, 70, 70)
local thumb = px(29, 187, 74, 74)
local autoTools = px(585, 180, 98, 29)
local shopSlots = px(585, 216, 98, 49)
local powerBlock = px(211, 218, 282, 46)

check("변환: 점프 버튼 Scale 좌상단", math.abs(jump.x0 - 610 / 705) < 1e-9 and math.abs(jump.y0 - 190 / 280) < 1e-9)
check("겹침: 실측 구좌는 점프 버튼과 겹친다", TouchSafeLayout.overlaps(shopSlots, jump))
check("겹침: 실측 자동 도구도 겹친다", TouchSafeLayout.overlaps(autoTools, jump))
check("겹침: 힘 블록은 점프 버튼과 안 겹친다", not TouchSafeLayout.overlaps(powerBlock, jump))
check("겹침: 힘 블록은 조이스틱 휴지 자리와 안 겹친다", not TouchSafeLayout.overlaps(powerBlock, thumb))

do
	local gap = TouchSafeLayout.GAP
	local lift = TouchSafeLayout.computeLift({ autoTools, shopSlots }, { jump }, gap)
	check("올림: 양수", lift > 0)
	local lifted = { y0 = shopSlots.y0 - lift, y1 = shopSlots.y1 - lift, x0 = shopSlots.x0, x1 = shopSlots.x1 }
	check("올림: 올린 뒤 구좌 아랫변 = 점프 윗변 - 간격", math.abs(lifted.y1 - (jump.y0 - gap)) < 1e-9)
	check("올림: 올린 뒤 겹치지 않는다", not TouchSafeLayout.overlaps(lifted, jump))
	local liftedAuto = { y0 = autoTools.y0 - lift, y1 = autoTools.y1 - lift, x0 = autoTools.x0, x1 = autoTools.x1 }
	check("올림: 묶음 윗변이 화면 안", liftedAuto.y0 > 0)
end

check("올림: 피할 것이 없으면 0", TouchSafeLayout.computeLift({ shopSlots }, {}, TouchSafeLayout.GAP) == 0)
check("올림: 가로로 안 겹치면 0", TouchSafeLayout.computeLift({ powerBlock }, { jump }, TouchSafeLayout.GAP) == 0)
check("올림: 이미 위에 있으면 0", TouchSafeLayout.computeLift({ px(585, 60, 98, 40) }, { jump }, TouchSafeLayout.GAP) == 0)

do
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.fromScale(0.97, 0.75)
	frame.Size = UDim2.fromScale(0.14, 0.1)
	local r = TouchSafeLayout.scaleRect(frame)
	check("scaleRect: AnchorPoint 반영", math.abs(r.x0 - 0.83) < 1e-6 and math.abs(r.y0 - 0.65) < 1e-6 and math.abs(r.y1 - 0.75) < 1e-6)
	frame:Destroy()
end

print(string.format("[TouchSafeLayoutTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[TouchSafeLayoutTests] %d test(s) failed", failed))
end

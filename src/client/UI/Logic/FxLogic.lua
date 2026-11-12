--!strict
-- 화면 연출 순수 계산 (지시서 #25 U1 ~ U7 — docs/UI.md "UI 효과 > 화면 연출"). 실물 구동은 Components/Fx, 수치는 Shared/Config/UIFxConfig.
--
--   연출 하나 = 시작값 from + 구간 목록 segments({ to, time, style, direction }). sample(from, segments, t)가 t초의 값 · 끝났나를 낸다
--   *Spec(...)     창 열기 · 닫기 · 결과 모달 · 튀기의 시작값 · 구간(전부 UIFxConfig에서 읽는다)
--   lerpLog        BigNum 두 값 사이를 log10 공간에서 보간(블럭스 올라가기 U3). raw number로 바꾸지 않는다 — 지수 + log10(가수)만 쓴다
--   countUpPlan    표시값 → 새 값: 늘면 animate · 줄면 instant · 같으면 none
--   throttle       마지막 시각에서 간격이 지났나(레벨 튀기 · 효과음)
--   centerPosition 가운데(0.5, 0.5) 기준으로 바꿀 때 같은 화면 자리를 가리키는 Position(Scale) — UIScale은 AnchorPoint 기준으로 커진다
--   newCraftSeq    크래프팅 연출 순서(U6): 누름(재료 자리) · 서버 결과 · 결과 펫이 격자에 들어옴 — 셋이 다 차야 재생, 어느 쪽이 먼저 와도

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UIFxConfig = require(ReplicatedStorage.Shared.Config.UIFxConfig)

type BigNumber = BigNum.BigNumber

local FxLogic = {}

export type Segment = { to: number, time: number, style: Enum.EasingStyle, direction: Enum.EasingDirection }
export type Spec = { from: number, segments: { Segment } }
-- ease(alpha, style, direction) = TweenService:GetValue. 테스트도 같은 함수를 넘긴다
export type Ease = (number, Enum.EasingStyle, Enum.EasingDirection) -> number

function FxLogic.totalTime(segments: { Segment }): number
	local total = 0
	for _, seg in ipairs(segments) do
		total += seg.time
	end
	return total
end

-- t초 뒤의 값과 끝났는가. 끝났으면 정확히 마지막 to(이징 오차 없이). 구간이 없으면 from에서 바로 끝.
function FxLogic.sample(from: number, segments: { Segment }, t: number, ease: Ease): (number, boolean)
	local start = from
	local elapsed = math.max(0, t)
	for _, seg in ipairs(segments) do
		if elapsed < seg.time then
			local alpha = if seg.time > 0 then elapsed / seg.time else 1
			return start + (seg.to - start) * ease(alpha, seg.style, seg.direction), false
		end
		elapsed -= seg.time
		start = seg.to
	end
	return start, true
end

-- 진행률(0 ~ 1)로 고른 시각. 스크린샷 멈춤(DEBUG_FREEZE_PROGRESS)이 쓴다
function FxLogic.timeAtProgress(segments: { Segment }, progress: number): number
	return FxLogic.totalTime(segments) * math.clamp(progress, 0, 1)
end

-- 연출 줄이기(U7): 움직임 없이 끝값
function FxLogic.finalValue(spec: Spec): number
	local last = spec.segments[#spec.segments]
	return if last ~= nil then last.to else spec.from
end

-- ===== 사양 (UIFxConfig) =====

function FxLogic.windowOpenSpec(): Spec
	return { from = UIFxConfig.WINDOW_OPEN_SCALE_FROM, segments = {
		{ to = 1, time = UIFxConfig.WINDOW_OPEN_TIME, style = UIFxConfig.WINDOW_OPEN_STYLE, direction = UIFxConfig.WINDOW_OPEN_DIRECTION },
	} }
end

-- 지금 Scale(열리는 중이면 1이 아닐 수 있다)에서 닫힘 크기로
function FxLogic.windowCloseSpec(current: number): Spec
	return { from = current, segments = {
		{ to = UIFxConfig.WINDOW_CLOSE_SCALE_TO, time = UIFxConfig.WINDOW_CLOSE_TIME, style = UIFxConfig.WINDOW_CLOSE_STYLE,
			direction = UIFxConfig.WINDOW_CLOSE_DIRECTION },
	} }
end

-- 배경 막 투명도: 보이기(지금 값 → rest) · 숨기기(지금 값 → 1)
function FxLogic.dimSpec(current: number, show: boolean, rest: number): Spec
	if show then
		return { from = current, segments = {
			{ to = rest, time = UIFxConfig.WINDOW_DIM_TIME, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out },
		} }
	end
	return { from = current, segments = {
		{ to = 1, time = UIFxConfig.WINDOW_CLOSE_TIME, style = UIFxConfig.WINDOW_CLOSE_STYLE, direction = UIFxConfig.WINDOW_CLOSE_DIRECTION },
	} }
end

function FxLogic.isRare(tier: number?): boolean
	return type(tier) == "number" and tier >= UIFxConfig.MODAL_RARE_MIN_TIER
end

-- 결과 모달(U2). 영웅 이상은 MODAL_RARE_SCALE_FROM → MODAL_RARE_PEAK → 1
function FxLogic.modalSpec(tier: number?): Spec
	if FxLogic.isRare(tier) then
		local up = UIFxConfig.MODAL_RARE_TIME * UIFxConfig.POP_PEAK_AT
		return { from = UIFxConfig.MODAL_RARE_SCALE_FROM, segments = {
			{ to = UIFxConfig.MODAL_RARE_PEAK, time = up, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out },
			{ to = 1, time = UIFxConfig.MODAL_RARE_TIME - up, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.In },
		} }
	end
	return { from = UIFxConfig.MODAL_SCALE_FROM, segments = {
		{ to = 1, time = UIFxConfig.MODAL_TIME, style = UIFxConfig.MODAL_STYLE, direction = UIFxConfig.MODAL_DIRECTION },
	} }
end

-- 1 → peak → 1 (레벨 · 환생 배수)
function FxLogic.popSpec(peak: number, time: number): Spec
	local up = time * UIFxConfig.POP_PEAK_AT
	return { from = 1, segments = {
		{ to = peak, time = up, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out },
		{ to = 1, time = time - up, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.In },
	} }
end

-- from → 1 (크래프팅 결과 칸)
function FxLogic.popInSpec(from: number, time: number): Spec
	return { from = from, segments = {
		{ to = 1, time = time, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out },
	} }
end

-- 진행률 0 → 1 (블럭스 올라가기 · 모이기 · 번쩍임처럼 값을 직접 그리는 연출)
function FxLogic.progressSpec(time: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Spec
	return { from = 0, segments = {
		{ to = 1, time = time, style = style or Enum.EasingStyle.Linear, direction = direction or Enum.EasingDirection.Out },
	} }
end

-- ===== 블럭스 올라가기 (U3) =====

-- log10(값). 0 이하는 nil. 지수 + log10(가수) — 10^2000이어도 2000.x라 number로 충분하다
function FxLogic.log10Of(v: BigNumber): number?
	if type(v) ~= "table" or type(v.m) ~= "number" or type(v.e) ~= "number" or v.m <= 0 then
		return nil
	end
	return v.e + math.log10(v.m)
end

local function copy(v: BigNumber): BigNumber
	return { m = v.m, e = v.e }
end

export type CountUpPlan = "animate" | "instant" | "none"

function FxLogic.countUpPlan(shown: BigNumber, target: BigNumber): CountUpPlan
	if BigNum.eq(shown, target) then
		return "none"
	end
	if BigNum.lt(target, shown) then
		return "instant"
	end
	return "animate"
end

-- alpha 0 = from 그대로 · 1 = to 그대로(사본). 사이는 log10 공간 직선 — 값이 언제나 from 이상 to 이하.
-- from이 0 이하면 log 0(값 1)에서 시작한다(목표가 1보다 작으면 목표에서). 줄어들거나 같으면 to(움직이지 않는다 — countUpPlan이 거른다).
function FxLogic.lerpLog(from: BigNumber, to: BigNumber, alpha: number): BigNumber
	if alpha >= 1 or not BigNum.lt(from, to) then
		return copy(to)
	end
	if alpha <= 0 then
		return copy(from)
	end
	local logTo = FxLogic.log10Of(to)
	if logTo == nil then
		return copy(to)
	end
	local logFrom = FxLogic.log10Of(from) or math.min(0, logTo)
	local l = logFrom + (logTo - logFrom) * alpha
	local e = math.floor(l)
	local v = BigNum.new(10 ^ (l - e), e)
	if BigNum.gt(v, to) then
		return copy(to)
	end
	if BigNum.lt(v, from) then
		return copy(from)
	end
	return v
end

-- ===== 스로틀 · 가운데 기준 =====

function FxLogic.throttle(lastAt: number?, now: number, minInterval: number): boolean
	return lastAt == nil or now - lastAt >= minInterval
end

-- anchor · position(Scale) · 자기 픽셀 크기 · 부모 픽셀 크기 → AnchorPoint (0.5, 0.5)로 바꿨을 때 같은 자리의 Position Scale (x, y).
-- Offset은 그대로 둔다(이 프로젝트의 배치는 Offset 0). 부모 크기가 0이면 바꾸지 않는다
function FxLogic.centerPosition(anchor: Vector2, position: UDim2, size: Vector2, parentSize: Vector2): UDim2
	if parentSize.X <= 0 or parentSize.Y <= 0 then
		return position
	end
	local dx = (0.5 - anchor.X) * size.X / parentSize.X
	local dy = (0.5 - anchor.Y) * size.Y / parentSize.Y
	return UDim2.new(position.X.Scale + dx, position.X.Offset, position.Y.Scale + dy, position.Y.Offset)
end

-- ===== 크래프팅 순서 (U6) =====
-- 서버 결과(PetResult)와 PlayerState(새 펫이 격자에 들어옴)는 어느 쪽이 먼저 올지 모른다(#12 순서 버그).
-- 누름에서 재료 자리를 받고, 결과 uid가 오고, 그 uid가 격자에 보일 때 한 번 재생한다. CRAFT_WAIT_SEC가 지나면 버린다.

export type Rect = { x: number, y: number, w: number, h: number } -- 연출 층 기준 Scale
export type CraftSeq = {
	begin: (materials: { Rect }, now: number) -> (),
	result: (ok: boolean, uid: string?, now: number) -> (),
	-- 격자에 그 uid 칸이 있나(있으면 그 자리). "wait" · "play"(자리 · 재료 · uid) · "idle"(할 것 없음 · 버림)
	poll: (findCell: (uid: string) -> Rect?, now: number) -> ("idle" | "wait" | "play", Rect?, { Rect }?, string?),
	cancel: () -> (),
	state: () -> string,
}

function FxLogic.newCraftSeq(): CraftSeq
	local materials: { Rect }? = nil
	local uid: string? = nil
	local startedAt = 0
	local st = "idle" -- idle · pressed · waiting
	local seq = {}

	function seq.begin(m: { Rect }, now: number)
		materials = m
		uid = nil
		startedAt = now
		st = "pressed"
	end

	function seq.result(ok: boolean, newUid: string?, now: number)
		if st ~= "pressed" then
			return
		end
		if not ok or type(newUid) ~= "string" or newUid == "" then
			st = "idle"
			materials = nil
			return
		end
		uid = newUid
		startedAt = now
		st = "waiting"
	end

	function seq.poll(findCell: (string) -> Rect?, now: number)
		if st == "idle" then
			return "idle", nil, nil, nil
		end
		if now - startedAt > UIFxConfig.CRAFT_WAIT_SEC then
			st = "idle"
			materials = nil
			return "idle", nil, nil, nil
		end
		if st ~= "waiting" or uid == nil then
			return "wait", nil, nil, nil
		end
		local rect = findCell(uid :: string)
		if rect == nil then
			return "wait", nil, nil, nil
		end
		local m = materials or {}
		local u = uid
		st = "idle"
		materials = nil
		uid = nil
		return "play", rect, m, u
	end

	function seq.cancel()
		st = "idle"
		materials = nil
		uid = nil
	end

	function seq.state(): string
		return st
	end

	return seq :: CraftSeq
end

return FxLogic

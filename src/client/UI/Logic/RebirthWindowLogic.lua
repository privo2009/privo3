--!strict
-- 환생 창의 표시 값 · 확인 단계 · 사유 문구 (Phase 6 지시서 #5). 순수 모듈 — 화면은
-- Screens/Window/RebirthWindow. docs/UI.md "1. 화면 목록 > 환생 창 — 반드시 보여야 하는 것".
--
-- 값은 서버와 같은 함수에서 나온다: 얻는 배수 = RebirthConfig.getGainedRebirths(블럭스)
-- (서버 RebirthService.runRebirth가 부르는 그 함수), 배수 = StrengthMultiplier.compute.
-- 화면 값은 안내일 뿐이고, 실제 환생 여부는 서버가 요청을 받은 순간 다시 판정한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local StrengthMultiplier = require(ReplicatedStorage.Shared.StrengthMultiplier)
local ConfirmFlow = require(script.Parent.ConfirmFlow)

type BigNumber = BigNum.BigNumber

local RebirthWindowLogic = {}

export type View = {
	blox: BigNumber,
	gained: BigNumber, -- 얻는 배수
	wasted: BigNumber, -- 버려지는 양 (1000 미만 나머지 — 환생은 전액 소모라 이만큼은 아무것도 안 된다)
	canRebirth: boolean,
	lockReason: string?, -- 잠긴 이유 코드 (canRebirth=false일 때)
	multiplierNow: BigNumber,
	multiplierAfter: BigNumber,
}

function RebirthWindowLogic.compute(blox: BigNumber, rebirths: BigNumber): View
	local gained = RebirthConfig.getGainedRebirths(blox)
	-- 버려지는 양은 RebirthConfig.getLeftover가 원본이다(시뮬레이터의 S5 업그레이드 예산과 같은 함수 — 지시서 #7).
	-- 블럭스가 아주 크면 나머지가 표현되지 않아 0이다(음수 잡음도 0으로 접는다).
	local wasted = RebirthConfig.getLeftover(blox)
	local can = RebirthConfig.canRebirth(blox)
	return {
		blox = blox,
		gained = gained,
		wasted = wasted,
		canRebirth = can,
		lockReason = if can then nil else "not_enough_blox",
		multiplierNow = StrengthMultiplier.compute({ rebirths = rebirths }),
		multiplierAfter = StrengthMultiplier.compute({ rebirths = BigNum.add(rebirths, gained) }),
	}
end

-- 사유 코드 → 화면 문구. 코드는 서버 RebirthService.REASON_* · RebirthRequestService.REASON_RATE_LIMITED
-- 와 같은 문자열이다. 모르는 코드는 일반 문구.
function RebirthWindowLogic.reasonText(code: string): string
	if code == "not_enough_blox" then
		return string.format("%s 블럭스부터 환생할 수 있어요", Formatter.format(BigNum.fromNumber(RebirthConfig.BLOX_PER_REBIRTH)))
	elseif code == "no_profile" then
		return "데이터를 불러오는 중이에요"
	elseif code == "rate_limited" then
		return "잠시 뒤에 다시 눌러 주세요"
	elseif code == "partial_failure" then
		-- 부작용이 이미 생긴 뒤의 사고다. "환생하지 못했다"로 안내하면 거짓말이 된다(RebirthService 상단).
		return "문제가 생겼어요. 관리자에게 알려 주세요"
	end
	return "환생하지 못했어요"
end

-- 환생하면 바뀌는 것 / 남는 것. 문서가 아니라 RebirthService.runRebirth가 실제로 하는 일을 읽어 맞췄다
-- (괄호 안은 그 함수의 단계 번호). 그쪽 단계가 바뀌면 여기도 바꾼다.
RebirthWindowLogic.RESETS = {
	"블럭스 → 0 (전부 사용)", -- 4
	"힘 → 처음 값", -- 6
	"최고 층 기록 · 현재 월드 → 처음", -- 7 · 8
	"클릭 파워 패드 → 다시 잠김 (패드 1부터)", -- 11 (lifeBlox 0, 선택 패드 1)
	"최대 이동속도 → 힘에 맞춰 다시", -- 10
	"진행 중인 런 → 끝나고 스폰으로", -- 3
}
-- 상점 업그레이드: runRebirth의 deps에는 업그레이드를 바꾸는 통로가 없다 — 남는다(UpgradeServiceTests 5번이 확인한다, 지시서 #7).
RebirthWindowLogic.KEEPS = "남는 것: 환생 배수(오름) · 운동기구 · 평생 누적 블럭스 · 상점 업그레이드"

-- 버려지는 양 옆 안내 + 상점 창으로 가는 버튼(지시서 #7 6단계). 버려질 나머지를 업그레이드에 먼저 쓰라는 안내다
-- (시뮬레이터 표준 플레이어의 구매 규칙 S5와 같은 행동).
RebirthWindowLogic.SHOP_HINT = "환생 전에 상점에서 먼저 쓸 수 있어요"
RebirthWindowLogic.SHOP_BUTTON_TEXT = "상점으로"

-- ===== 확인 단계 ==============================================================================
--
-- 한 번 누름으로는 절대 실행되지 않는다. 첫 누름은 "확인 중"으로 바꿀 뿐이고, CONFIRM_WINDOW_SEC 안에
-- 한 번 더 눌러야 요청이 나간다. 시간이 지나거나 취소하면 처음으로 돌아간다.

RebirthWindowLogic.CONFIRM_WINDOW_SEC = 5 -- 시각 튜닝값(세션 로그)

export type ConfirmAction = ConfirmFlow.Action

-- 확인 단계는 월드·워프 창과 같은 규칙이라 UI/Logic/ConfirmFlow로 옮겼다(지시서 #6). 이름은 그대로 둔다.
function RebirthWindowLogic.newConfirm(): ConfirmFlow.Flow
	return ConfirmFlow.new(RebirthWindowLogic.CONFIRM_WINDOW_SEC)
end

return RebirthWindowLogic

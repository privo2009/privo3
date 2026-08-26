--!strict
-- 힘 배수의 합성 지점. 여러 출처의 배수를 받아 최종 배수 하나를 돌려준다.
--
-- ===== 프로필을 받지 않는다 (중요) ====================================================
--
-- 인자는 **값 테이블**이다. `profile`이나 `Player`를 받는 형태로 바꾸지 말 것.
-- 프로필을 받으면 이 모듈이 서버 전용이 되고, 그 순간 둘이 함께 막힌다:
--   1. 클라 표시용 계산 (Phase 6 UI가 "현재 배수 x12"를 보여줄 때 서버 왕복이 필요해진다)
--   2. 순수 테스트 (ProfileManager 없이 값만 넣어보는 지금의 방식이 불가능해진다)
-- 읽어오는 일은 호출자가 하고, 이 파일은 계산만 한다.
--
-- ===== 지금 인식하는 필드 =============================================================
--
--   sources.rebirths   환생 배수 (BigNum). 결과는 1 + rebirths
--
-- 환생 배수가 선형 가산인 근거는 DESIGN.md "3. 화폐와 배수 > 환생"이 원본이다
-- (1000 블럭스 = +1x). ⚠️ 수치를 여기로 복사하지 말 것.
--
-- ===== 앞으로 붙을 필드 ===============================================================
--
-- Phase 7·8에서 아래가 이 함수에 필드로 붙는다 (DESIGN.md "3. 화폐와 배수 > 배수 계통"):
--
--   아우라          힘 배율
--   펫              합산, 힘 배수 전담
--   힘 배수 게임패스 2x~1024x — ⚠️ 중첩 금지, 최고 단계만 적용 (CLAUDE.md 금지 사항)
--   힘 포션         15분 2x
--
-- ⚠️ 각 배수를 **합산할지 곱할지는 지금 정하지 않는다.** 붙이는 시점에 위 DESIGN 절을
--    근거로 정한다. 여기서 미리 `1 + a + b + c` 같은 골격을 만들어두면, 그게 곧
--    결정이 되어버리고 근거 없이 굳는다. 필드가 하나뿐인 지금은 그 결정이 불필요하다.
--
-- ⚠️ "서로 곱하지 않는다"는 것은 **힘 계통과 블럭스 계통 사이의** 이야기다
--    (DESIGN "배수 계통"). 힘 계통 안에서의 결합 방식과는 다른 질문이니 혼동하지 말 것.

local BigNum = require(script.Parent.BigNum)

type BigNumber = BigNum.BigNumber

local StrengthMultiplier = {}

-- 힘 배수 출처. 필드는 전부 선택이다 — 없으면 "그 배수 없음"으로 본다.
export type Sources = {
	rebirths: BigNumber?,
}

-- ⚠️ 상수 테이블을 만들어 재사용하지 않는다. BigNum 값은 평범한 테이블이라 호출자가
-- 반환값을 고치면 그 상수 자체가 바뀐다 — 한 번 오염되면 이후 모든 호출이 틀린 값을 받고,
-- 원인이 이 파일에 남지 않는다. 매번 새로 만든다.
local function one(): BigNumber
	return BigNum.new(1, 0)
end

-- 값이 쓸 만한 BigNum인가.
--
-- ⚠️ Shared에서는 Data/Schema.isBigNum을 쓸 수 없다(서버 전용 모듈이다). 그래서 여기에
-- 최소 검사만 둔다. 프로필 무결성 검사를 대신하려는 것이 아니라, 호출자가 nil이나
-- 엉뚱한 값을 넘겼을 때 **에러 대신 "배수 없음"으로 접기 위한** 판정이다.
local function isBigNum(value: any): boolean
	return type(value) == "table"
		and type(value.m) == "number"
		and type(value.e) == "number"
		and value.m == value.m -- nan 아님
		and value.e == value.e
end

-- 힘 계통 배수를 한 곳에서 결합한다.
-- 힘에 곱해지는 배수가 새로 생기면 여기에 필드로 붙인다 —
-- 호출부에서 직접 곱하지 말 것. 곱셈 지점이 흩어지면 하나가 빠져도
-- 조용히 어긋나고, 힘은 blox와 달리 감사 로그가 없어 발견이 늦다.
--
-- sources가 nil이거나 필드가 비어 있으면 1(배수 없음)을 돌려준다. 에러를 내지 않는다 —
-- 신규 프로필과 로드 전 상태가 정상적으로 이 경로를 탄다.
--
-- ⚠️ 0을 돌려주는 경로가 있으면 안 된다. 배수 0은 힘이 통째로 0이 된다는 뜻이라,
-- 어디서 왔든 그 값이 그대로 곱해지면 플레이어의 성장이 조용히 멈춘다.
function StrengthMultiplier.compute(sources: Sources?): BigNumber
	if sources == nil then
		return one()
	end

	local total = one()

	-- 환생: 1 + rebirths (선형 가산).
	if isBigNum(sources.rebirths) then
		total = BigNum.add(total, sources.rebirths :: BigNumber)
	end

	return total
end

return StrengthMultiplier

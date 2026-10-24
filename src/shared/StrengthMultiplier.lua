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
--   sources.rebirths   환생 배수 (BigNum). 1 + rebirths
--   sources.titleMult  장착 칭호 힘 배수 (number, TitleConfig.multOf). 장착 없음 = 1  (지시서 #10)
--   sources.auraMult   장착 아우라 m (number, AuraConfig.multOf). 장착 없음 = 1  (지시서 #11 A10)
--                      m은 1펀치 데미지(AttackService.combineDamageMultiplier)에도 한 번 들어간다 — DPS에는 m²(A1, 의도)
--   sources.petMult    장착 펫 배수 (number, PetConfig.totalMult — 1 + Σ 실효 증가분, E3). 장착 없음 = 1  (지시서 #12)
--                      **여기 한 자리에서만** 곱한다. 펫은 데미지 항이 없다(S9) — combineDamageMultiplier에 넣지 말 것
--
--   결과 = (1 + rebirths) × titleMult × auraMult × petMult
--
-- ===== 결합 규칙 (S3, 2026-10-24 사람 결정 — DESIGN.md "3. 화폐와 배수 > 배수 계통") =================
--
-- 힘 계통은 **출처끼리 곱한다.** 이 함수 한 곳에서 한다. 예외 둘:
--   펫              안에서 합산 — 펫 배수 = 1 + Σ(실효 증가분) (G9 · E3, PetConfig.totalMult). 그 결과 하나를 여기서 곱한다 (#12)
--   힘 배수 게임패스 최고 단계만 — ⚠️ 중첩 금지 (CLAUDE.md 금지 사항) (Phase 8)
-- 힘 포션(Phase 8)도 필드로 붙어 곱해진다. 운동기구 · 패드는 여기 들어오지 않는다
-- (ClickService.computeGain의 클릭 1회 값 — 다른 자리다).
--
-- 환생 배수가 선형 가산인 근거는 DESIGN.md "3. 화폐와 배수 > 환생"이 원본이다
-- (1000 블럭스 = +1x). ⚠️ 수치를 여기로 복사하지 말 것.
--
-- ⚠️ "서로 곱하지 않는다"는 것은 **힘 계통과 블럭스 계통 사이의** 이야기다
--    (DESIGN "배수 계통"). 힘 계통 안에서의 결합 방식과는 다른 질문이니 혼동하지 말 것.

local BigNum = require(script.Parent.BigNum)

type BigNumber = BigNum.BigNumber

local StrengthMultiplier = {}

-- 힘 배수 출처. 필드는 전부 선택이다 — 없으면 "그 배수 없음"으로 본다.
export type Sources = {
	rebirths: BigNumber?,
	titleMult: number?,
	auraMult: number?,
	petMult: number?,
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

	-- 칭호 · 아우라 · 펫: 곱한다(S3). 1 이하 · nan · inf · 숫자 아님은 "배수 없음" — 0이나 1 미만이 곱해지면 성장이 줄거나 멈춘다.
	-- ⚠️ ipairs로 돌리지 말 것 — 앞 값이 nil이면(칭호 없음) 뒤 값(아우라)에서 멈춘다(2026-10-24 AuraServiceTests가 잡았다).
	local function apply(factor: any)
		if type(factor) == "number" and factor == factor and factor > 1 and factor < math.huge then
			total = BigNum.mul(total, BigNum.fromNumber(factor))
		end
	end
	apply(sources.titleMult)
	apply(sources.auraMult)
	apply(sources.petMult) -- 지시서 #12 E3. 앞 둘이 없어도 곱해진다(PetServiceTests)

	return total
end

return StrengthMultiplier

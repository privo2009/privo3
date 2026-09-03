--!strict
-- 상시 노출 로벅스 구좌 4개가 무엇을 보여줄지 고른다. docs/UI.md "1. 화면 목록 >
-- 로벅스 상품 구좌" · DESIGN.md "9. 수익화".
--
-- ⚠️ TEMP — 상시 노출 구좌에 무엇을 띄울지는 Phase 8 수익화에서 실제 전환율을
-- 보고 다시 정할 값이다. 지금 확정하지 않는다(`WarpConfig.TEMP_COST_BASE`와 같은
-- 성격). 지금은 트랙(힘 / 클릭 입력 / 재화 / 오프라인) 하나씩 잠정으로 골랐을
-- 뿐이고, 4개라는 개수·이 넷이라는 선택 둘 다 다시 열릴 수 있다.
--
-- ⚠️ 가격·이름을 여기 다시 적지 않는다. `ShopConfig`가 원본이고 이 파일은
-- "그 중 뭘 상시 노출할지"만 고른다 — 값을 복사하면 `ShopConfig`가 바뀔 때
-- 이 파일만 옛 값에 남는 사고가 난다(docs/UI.md가 화면 개수·색값을 문서마다
-- 복사하지 말라는 것과 같은 이유). `DESIGN.md` "9. 수익화" 표를 여기로
-- 복사하지 않는 것도 같은 이유다.

local ShopConfig = require(script.Parent.ShopConfig)

export type Slot = {
	key: string, -- 화면 코드·테스트가 항목을 가리키는 식별자. 표시 문구 아님
	track: string, -- 문서/테스트용 트랙 이름(힘/클릭 입력/재화/오프라인). 표시 안 함
	name: string, -- ShopConfig에서 그대로 가져온 표시 이름
	priceRobux: number, -- ShopConfig에서 그대로 가져온 가격
}

local ShopSlotConfig = {}

-- 힘 배수 계단은 항상 첫 단계(2x)를 보여준다.
--
-- ⚠️ "보유 중 다음 단계"를 띄우는 것이 최종 동작이지만, 게임패스 소유 여부는
-- 프로필에 저장하지 않고 매 세션 MarketplaceService로 확인해야 한다(CLAUDE.md
-- 절대 규칙 5). 그 조회 배선이 이번 Phase에 없으므로 보유 단계를 알 방법이
-- 없다 — 보유 조회는 Phase 8.
local strengthTier = ShopConfig.StrengthMultTiers[1]
local autoClickerGamepass = ShopConfig.Gamepasses.autoClicker
local bloxGamepass = ShopConfig.Gamepasses.blox2x
local droneTier = ShopConfig.DroneTiers[1]

-- 순서 = 화면 표시 순서(2행 2열, 좌->우 위->아래). U3-6 결정 — 접근 빈도가 아니라
-- "서로 다른 소비 트랙 하나씩"으로 골랐다(힘 성장 / 조작 편의 / 재화 배수 / 오프라인 수입).
ShopSlotConfig.TEMP_SLOTS = {
	{
		key = "strengthTier1",
		track = "힘",
		name = string.format("%dx 힘", strengthTier.multiplier),
		priceRobux = strengthTier.priceRobux,
	},
	{
		key = "autoClicker",
		track = "클릭 입력",
		name = autoClickerGamepass.name,
		priceRobux = autoClickerGamepass.priceRobux,
	},
	{
		key = "blox2x",
		track = "재화",
		name = bloxGamepass.name,
		priceRobux = bloxGamepass.priceRobux,
	},
	{
		key = "drone2",
		track = "오프라인",
		name = string.format("드론 %d대", droneTier.count),
		priceRobux = droneTier.priceRobux,
	},
} :: { Slot }

function ShopSlotConfig.validate(): boolean
	assert(#ShopSlotConfig.TEMP_SLOTS == 4, "ShopSlotConfig: 구좌는 4개여야 함(U3-6 확정)")

	local seenKeys: { [string]: boolean } = {}
	for _, slot in ipairs(ShopSlotConfig.TEMP_SLOTS) do
		assert(type(slot.key) == "string" and #slot.key > 0, "ShopSlotConfig: key가 비어 있음")
		assert(not seenKeys[slot.key], "ShopSlotConfig: key가 중복됨: " .. slot.key)
		seenKeys[slot.key] = true

		assert(type(slot.track) == "string" and #slot.track > 0, "ShopSlotConfig: track이 비어 있음: " .. slot.key)
		assert(type(slot.name) == "string" and #slot.name > 0, "ShopSlotConfig: name이 비어 있음: " .. slot.key)
		assert(
			type(slot.priceRobux) == "number" and slot.priceRobux > 0,
			"ShopSlotConfig: priceRobux는 0보다 커야 함: " .. slot.key
		)
	end

	return true
end

return ShopSlotConfig

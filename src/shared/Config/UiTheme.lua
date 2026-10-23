--!strict
-- 색 역할 8종의 밝은/기본/어두운 3단계. 문서 원본은 docs/UI.md "3. 색"이다.
-- 실행 가능한 코드가 필요해 불가피하게 옮겨왔으므로, 색을 고칠 때는 반드시 양쪽을 함께 고친다.
--
-- 역할 키는 docs/UI.md 표의 역할 명칭과 1:1 대응한다 (임의로 이름을 바꾸지 않는다):
--   power=힘  blox=블럭스  advance=진행·도박  cashout=수령·안전
--   robux=로벅스  danger=경고·닫기·실패  premium=프리미엄  neutral=중립

local UiTheme = {}

export type ColorRole = "power" | "blox" | "advance" | "cashout" | "robux" | "danger" | "premium" | "neutral"

export type RoleColors = {
	light: Color3,
	base: Color3,
	dark: Color3,
}

local Colors: { [ColorRole]: RoleColors } = {
	power = {
		light = Color3.fromHex("FFB347"),
		base = Color3.fromHex("FF8C1A"),
		dark = Color3.fromHex("C25E00"),
	},
	blox = {
		light = Color3.fromHex("7DD3FC"),
		base = Color3.fromHex("38A8E8"),
		dark = Color3.fromHex("1668A8"),
	},
	advance = {
		light = Color3.fromHex("C77DFF"),
		base = Color3.fromHex("9D4EDD"),
		dark = Color3.fromHex("5A189A"),
	},
	cashout = {
		light = Color3.fromHex("FFE066"),
		base = Color3.fromHex("FFC61A"),
		dark = Color3.fromHex("C28F00"),
	},
	robux = {
		light = Color3.fromHex("86EFAC"),
		base = Color3.fromHex("3FBF5F"),
		dark = Color3.fromHex("1F7A38"),
	},
	danger = {
		light = Color3.fromHex("FF8080"),
		base = Color3.fromHex("E63946"),
		dark = Color3.fromHex("A11D28"),
	},
	premium = {
		light = Color3.fromHex("4A6FA5"),
		base = Color3.fromHex("2C4A78"),
		dark = Color3.fromHex("16294A"),
	},
	neutral = {
		light = Color3.fromHex("E8E8E8"),
		base = Color3.fromHex("B0B0B0"),
		dark = Color3.fromHex("6B6B6B"),
	},
}

UiTheme.Colors = Colors

-- ===== 희귀도 색 — 역할색과 별도 묶음 (2026-10-24 사람 결정 S14, docs/UI.md "3. 색 > 희귀도 색") =====
--
-- 역할(무엇을 하는가)과 희귀도(얼마나 귀한가)는 축이 다르다. 그래서 Colors 표에 넣지 않고 따로 둔다.
--   - 역할색 hex를 재사용하지 않는다(UiThemeTests가 24개 역할 hex와 대조한다)
--   - 단계가 오를수록 채도가 오르고 밝기는 내려가지 않는다 — 40px에서 "더 귀한 것이 더 눈에 띈다"
--   - 쓰는 곳은 뽑기 창 · 결과 연출 · 토스트 · 칭호 표시뿐이다(버튼 · HUD · 3D 오브젝트에 쓰지 않는다)
-- 타이틀 6등급 = tier1~6. 아우라 · 펫 4등급 매핑은 #11 · #12에서 정한다. hex는 Claude가 골랐다(세션 로그).
--   tier1 따뜻한 회색(채도 9%) · tier2 연초록 · tier3 하늘 · tier4 보라 · tier5 금 · tier6 진분홍(채도 92%)
export type RarityTier = "tier1" | "tier2" | "tier3" | "tier4" | "tier5" | "tier6"
UiTheme.RARITY_TIERS = { "tier1", "tier2", "tier3", "tier4", "tier5", "tier6" } :: { RarityTier }
UiTheme.Rarity = {
	tier1 = Color3.fromHex("B8B2A7"),
	tier2 = Color3.fromHex("7FCF9A"),
	tier3 = Color3.fromHex("5AA8F0"),
	tier4 = Color3.fromHex("B050FF"),
	tier5 = Color3.fromHex("FFB21E"),
	tier6 = Color3.fromHex("FF1470"),
} :: { [RarityTier]: Color3 }

-- 단계 번호(1~6) → 색. 범위 밖은 가장 가까운 끝 단계.
function UiTheme.rarityColor(tier: number): Color3
	local i = math.clamp(math.floor(tonumber(tier) or 1), 1, #UiTheme.RARITY_TIERS)
	return UiTheme.Rarity[UiTheme.RARITY_TIERS[i]]
end

return UiTheme

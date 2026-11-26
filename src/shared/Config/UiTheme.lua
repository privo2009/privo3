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

-- ===== 장비 등급 색 — 색 역할 규칙의 예외 (2026-11-24 지시서 #33 — PENDING C1 · docs/UI.md "3. 색 > 장비 등급 색") =====
-- 새 경제 장비(곡괭이 · 칼) 등급: 일반 회색 · 희귀 파랑 · 에픽 보라 · 신화 빨강 · 전설 금색(게임 관례). next = ???(다음 등급 — 잠긴 칸).
-- ⚠️ 아이템 테두리와 이름 글자에만 쓴다(버튼 바탕 · HUD · 3D 역할 파트 금지). 위 희귀도 색(Rarity — 칭호 · 아우라 · 펫)과 따로 둔다. hex는 Claude가 골랐다
UiTheme.EquipGrade = {
	common = Color3.fromHex("A8A8A8"),
	rare = Color3.fromHex("4A90FF"),
	epic = Color3.fromHex("B05CFF"),
	mythic = Color3.fromHex("FF4040"),
	legendary = Color3.fromHex("FFC83A"),
	next = Color3.fromHex("FFFFFF"),
} :: { [string]: Color3 }

function UiTheme.equipGradeColor(rarity: string): Color3
	return UiTheme.EquipGrade[rarity] or UiTheme.EquipGrade.common
end

-- 화면 글꼴 하나(지시서 #17 F1 · 2026-10-30 사람 결정 — #L2 후보 비교: 폭이 지금과 거의 같고 한글 대체 글꼴과 굵기 차이가 작다).
-- 코드에서 Enum.Font를 직접 쓰지 않는다 — 글꼴을 바꾸면 여기 한 줄만 바꾼다(tools/check_fonts.py · LocaleClientTests가 잰다).
UiTheme.FONT = Enum.Font.BuilderSansBold

-- 단계 번호(1~6) → 색. 범위 밖은 가장 가까운 끝 단계.
function UiTheme.rarityColor(tier: number): Color3
	local i = math.clamp(math.floor(tonumber(tier) or 1), 1, #UiTheme.RARITY_TIERS)
	return UiTheme.Rarity[UiTheme.RARITY_TIERS[i]]
end

-- ===== 스킨 — 보이는 모양의 숫자를 한 표에 (2026-11-26 지시서 #39 — docs/UI.md "UI 키트") =====
-- 색(위 Colors · Rarity · EquipGrade 표 그대로 — 같은 표를 가리킨다) · 글꼴 · 글자색 · 테두리 두께 · 둥글기 · 투명도 · 틀 여백 · 버튼 높이 ·
-- UI 그림 ID가 전부 여기 있다. 화면 코드는 이 숫자를 직접 쓰지 않고 키트(Client/UI/Components/Kit)가 읽는다.
-- 기본값 = #39 이전 화면 코드에 흩어져 있던 숫자 그대로(모양이 바뀌지 않게). 갈아 끼우기 = Config/UiSkin 한 파일(아래 applySkin이 덮는다).
-- ⚠️ 스킨은 화면을 만들 때 읽힌다(창은 처음 열 때 만든다). 이미 만든 창은 바꾸지 않는다 — 스킨은 접속 때 한 번 정한다.
export type Skin = {
	colors: { [ColorRole]: RoleColors },
	rarity: { [RarityTier]: Color3 },
	equipGrade: { [string]: Color3 },
	font: Enum.Font,
	text: { main: Color3, stroke: Color3, dim: Color3 },
	fill: { [string]: Color3 },
	line: { [string]: number },
	corner: { [string]: UDim },
	alpha: { [string]: number },
	panel: { margin: number, frameInset: number, small: Vector2, large: Vector2 },
	button: { heightBig: number, heightSmall: number, pressOffsetPx: number, pressDarken: number },
	images: { [string]: any },
}

UiTheme.Skin = {
	colors = Colors,
	rarity = UiTheme.Rarity,
	equipGrade = UiTheme.EquipGrade,
	font = UiTheme.FONT,
	-- 글자: 흰 글자 + 검은 외곽선(docs/UI.md "4. 글자 > 외곽선"). dim = 받은 칸 · 꺼진 글자(지금 neutral.light와 같은 값)
	text = { main = Color3.new(1, 1, 1), stroke = Color3.new(0, 0, 0), dim = Colors.neutral.light },
	-- 역할 밖 바탕색(임시 도형): silhouette = 장비 창 잠긴 칸(??? — 거의 검정) · egg = 부화 연출 알 · shade = 막 · 결과 덮개(검정)
	fill = { silhouette = Color3.fromRGB(25, 25, 30), egg = Color3.fromRGB(245, 235, 210), shade = Color3.new(0, 0, 0) },
	-- 테두리 두께(px — UIStroke.Thickness는 픽셀 예외, Button 머리 주석). 이름 = 쓰는 자리
	line = {
		asset = 3, -- AssetImage 임시 도형 · 그림 테두리(docs/UI.md "8. 비주얼 스타일" 3~4px)
		modal = 4, -- 결과 모달 · 일일 보상 판
		notice = 3, -- 환생 알림 판
		band = 2, -- 첫 접속 안내 띠
		cell = 2, -- 작은 칸(일일 보상 날짜 · 펫 칸 · 대장간 광석 칸 · 코드 입력칸)
		cellToday = 4, -- 일일 보상 오늘 칸
		slot = 3, -- 장비 칸 · HUD 상점 칸
		slotSelected = 5, -- 장비 칸 고른 것
		text = 1, -- 글자 외곽선(UIStroke 기본 두께)
	},
	-- 둥글기(UICorner) — round = 원(코인 · 배지) · cell = 대장간 광석 칸
	corner = { round = UDim.new(0.5, 0), cell = UDim.new(0.15, 0) },
	-- 바탕 투명도
	alpha = {
		dim = 0.45, -- 모달 뒤 막(결과 · 일일 보상)
		hatchDim = 0.35, -- 부화 연출 막
		band = 0.15, -- 안내 띠 · 환생 알림 판
		cell = 0.15, -- 칸 바탕(장비 · 대장간)
		cellSoft = 0.2, -- 대장간 고른 광석 칸
		row = 0.3, -- 대장간 확률 줄 · 잠김 막
		toast = 0.1, -- 토스트 줄
	},
	-- 창 틀(Panel): 크기 2종(화면 대비) · 여백(화면 폭의 2%) · 틀 그림 두께(화면 높이 대비 — 0 = 틀 그림 없음, 1월 템플릿이 정한다)
	panel = { margin = 0.02, frameInset = 0, small = Vector2.new(0.60, 0.70), large = Vector2.new(0.85, 0.85) },
	-- 버튼(docs/UI.md "5. 버튼"): 높이 2종(화면 높이 대비) · 눌림 아래로 px · 눌림 어둡게 비율
	button = { heightBig = 0.09, heightSmall = 0.06, pressOffsetPx = 2, pressDarken = 0.8 },
	-- 키트 부품 그림(9-slice 등). nil = 지금 모양(색 도형). { id = 이미지 ID, slice = Rect(px) } — 목록 · 규격 → AssetSlots.uiList · docs/UI_ASSET_SPEC.md "9"
	images = {},
} :: Skin

-- 이름 붙은 색 역할(#39): "role.power"(= base) · "role.power.light" · "grade.epic" · "rarity.tier3" · "text.main" · "text.stroke" · "text.dim".
-- 모르는 이름은 오류(오타를 조용히 흰색으로 그리지 않게)
function UiTheme.color(name: string): Color3
	local parts = string.split(name, ".")
	local group, key, step = parts[1], parts[2], parts[3]
	local skin = UiTheme.Skin
	local out: any = nil
	if group == "role" and key ~= nil then
		local entry = (skin.colors :: any)[key]
		out = entry and entry[step or "base"]
	elseif group == "grade" and key ~= nil and step == nil then
		out = skin.equipGrade[key]
	elseif group == "rarity" and key ~= nil and step == nil then
		out = (skin.rarity :: any)[key]
	elseif group == "text" and key ~= nil and step == nil then
		out = (skin.text :: any)[key]
	end
	assert(typeof(out) == "Color3", "UiTheme.color: 알 수 없는 색 이름: " .. tostring(name))
	return out :: Color3
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in pairs(v) do
		t[k] = deepCopy(x)
	end
	return t
end

-- 표 안을 제자리에서 덮는다(다른 모듈이 들고 있는 Colors · Rarity 같은 표 참조가 그대로 새 값을 본다)
local function mergeInto(dst: any, src: any)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			mergeInto(dst[k], v)
		else
			dst[k] = v
		end
	end
end

local DEFAULT_SKIN = deepCopy(UiTheme.Skin)

-- 스킨 덮기: overrides는 Skin과 같은 모양의 일부(적은 칸만 바뀐다). 접속 때 Config/UiSkin을 한 번 덮는다 — 미리보기 · 테스트도 부른다
function UiTheme.applySkin(overrides: any)
	if type(overrides) ~= "table" then
		return
	end
	mergeInto(UiTheme.Skin, overrides)
	UiTheme.FONT = UiTheme.Skin.font
end

-- 기본 스킨(#39 이전 모양)으로 되돌린다. images는 비운다
function UiTheme.resetSkin()
	local skin = UiTheme.Skin :: any
	for k, v in pairs(DEFAULT_SKIN) do
		if k == "images" then
			table.clear(skin.images)
		else
			mergeInto(skin, { [k] = deepCopy(v) })
		end
	end
	UiTheme.FONT = UiTheme.Skin.font
end

UiTheme.applySkin(require(script.Parent.UiSkin))

return UiTheme

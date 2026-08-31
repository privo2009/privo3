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

return UiTheme

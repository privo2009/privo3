--!strict
-- 글자 크기 5단계. 문서 원본은 docs/UI.md "4. 글자 > 크기 5단계"다.
-- 실행 가능한 코드가 필요해 불가피하게 옮겨왔으므로, 값을 고칠 때는 반드시 양쪽을
-- 함께 고친다 (UiTheme.lua 상단과 같은 사정).
--
-- UiTheme(색)과 섞이지 않도록 별도 파일로 뺐다 — 색과 글자 크기는 서로 다른 축이다.
--
-- heightFraction: 화면 높이 대비 비율. Size.Y.Scale 계산에 쓴다.
-- maxTextSize: docs 표의 "1080 기준" 칸. UITextSizeConstraint.MaxTextSize에 그대로 쓴다 —
--   TextScaled는 프레임을 꽉 채우도록 글자를 늘리므로, 자릿수가 늘어 프레임 폭이
--   좁아 보일 때 특대가 중처럼 보이지 않도록 이 값으로 상한을 건다.

local TextScale = {}

export type Level = "huge" | "large" | "medium" | "small" | "tiny"

export type LevelSpec = {
	heightFraction: number,
	maxTextSize: number,
}

-- 한글 이름 대응: huge=특대 large=대 medium=중 small=소 tiny=극소
local Levels: { [Level]: LevelSpec } = {
	huge = { heightFraction = 0.07, maxTextSize = 76 },
	large = { heightFraction = 0.05, maxTextSize = 54 },
	medium = { heightFraction = 0.035, maxTextSize = 38 },
	small = { heightFraction = 0.025, maxTextSize = 27 },
	tiny = { heightFraction = 0.02, maxTextSize = 22 },
}

TextScale.Levels = Levels

return TextScale
